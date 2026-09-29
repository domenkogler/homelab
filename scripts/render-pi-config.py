#!/usr/bin/env python3
"""Render the client model contract from ONE spec (HD-388).

SSOT: scripts/pi-config/models-spec.yml  →  per-vendor files. Replaces the hand-maintained
~/.pi/agent/models.json that docs/pi-harness.md §1 had to call its own "reference copy" because
carrying a bearer key made it uncommittable, and that scripts/install-pi-wsl.sh deliberately
refuses to sync. A second client (HD-409's cockpit on oldsrv, a `spark-lane` profile, a second
workstation) turns a hand-copied JSON into silent drift; this makes the drift a non-zero exit.

    python3 scripts/render-pi-config.py --check                  # gate: exit 1 on drift
    python3 scripts/render-pi-config.py                            # write vendor files, mode 0600
    python3 scripts/render-pi-config.py --vendor pi --out /tmp/m.json   # render anywhere

What it will not do:
  * put a credential in git, in the spec, or in a log — values are resolved from 1Password at
    render time and every printed line masks them (CONVENTIONS §6);
  * overwrite a target without a timestamped backup, or write anything but 0600;
  * invent a credential: a provider whose vault item cannot be read is an ERROR naming the item.
    `--keep-legacy-credentials` preserves whatever the target file already holds for providers
    explicitly marked `unmanaged: true` in the spec — and says so out loud. That flag exists
    because `entrim` has no vault item today (measured 2026-09-23: 120 visible items, none).
  * merge into a workstation's own Continue config — the continue vendor emits a SEPARATE
    generated file, because a generated block written over user-authored keys is a data-loss bug.

Key order follows the spec's own field order (spec order == render order), which is why the spec
reads like the output. Comparison for --check is STRUCTURAL, so reordering the spec is not drift;
byte-equality is reported as information, not enforced.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("PyYAML missing — use the ansible venv or `pip install pyyaml`")

REPO = Path(__file__).resolve().parent.parent
SPEC = REPO / "scripts" / "pi-config" / "models-spec.yml"
# Spec-only keys that describe intent or another vendor; never rendered into a vendor file.
META_KEYS = {"description", "credential", "unmanaged", "gateway_row", "continue", "hosts",
             "native_only"}
SECRET_RE = re.compile(r"key|token|secret|password|credential", re.I)


def sa_token() -> None:
    """Same convention as ansible-run.sh / provision-secrets.py: fall back to the 0600 file."""
    if os.environ.get("OP_SERVICE_ACCOUNT_TOKEN"):
        return
    f = Path.home() / ".config" / "op" / "homelab-sa-token"
    if f.is_file():
        m = re.search(r"OP_SERVICE_ACCOUNT_TOKEN=['\"]?([^'\"\n]+)", f.read_text())
        if m:
            os.environ["OP_SERVICE_ACCOUNT_TOKEN"] = m.group(1)


def mask(v: str) -> str:
    return f"«redacted len={len(v)}»" if v else "«empty»"


def op_secret(vault: str, item: str, field: str) -> str:
    """Resolve one field. Fails LOUD with the item name — a missing credential is the finding,
    not something to default() around (the HD-399 rule)."""
    sa_token()
    if not shutil.which("op"):
        sys.exit("FAIL: the `op` CLI is not installed on this machine")
    r = subprocess.run(["op", "item", "get", item, "--vault", vault, "--format", "json"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        why = (r.stderr or r.stdout).strip().splitlines()
        sys.exit(f"FAIL: cannot read op://{vault}/{item} (field '{field}'): "
                 f"{why[-1] if why else 'op failed'}\n"
                 f"      Either mint/record that item, or mark the provider `unmanaged: true` and "
                 f"run with --keep-legacy-credentials.")
    for f in json.loads(r.stdout).get("fields", []):
        if field in (f.get("id"), f.get("label")) and f.get("value"):
            return str(f["value"])
    sys.exit(f"FAIL: op://{vault}/{item} has no non-empty field '{field}'")


def in_wsl() -> bool:
    """Are we running INSIDE the Linux guest? /proc/version is the documented marker (the kernel
    string carries 'microsoft'); it is a read of local fact, not a guess from the hostname, which is
    the SAME on both seats of this laptop."""
    try:
        return "microsoft" in Path("/proc/version").read_text().lower()
    except OSError:
        return False


def scope_skip(p: dict, host: str) -> str | None:
    """Why this provider must NOT be rendered here, or None to render it.

    Two INDEPENDENT scopes, because the laptop has two seats that report the same hostname:
      `hosts:`        which MACHINE (case-insensitive: Windows says `DomenP14s`, §8 wants lowercase,
                      and a case mismatch would silently drop a provider);
      `native_only:`  which SEAT on that machine. The laptop's LM Studio listener is loopback and
                      WSL2 runs networkingMode=Nat here ON PURPOSE, so 127.0.0.1 inside the guest is
                      the guest — rendering the provider there would put a dead endpoint in the
                      picker, which is the HD-409 failure mode wearing a different hat.
    A provider with neither renders everywhere: the back-compat contract, proven by --host oldsrv
    reproducing the previous output. Why this is a property of the provider row rather than a
    per-host spec file: §15 forbids the second copy, and HD-388's whole point is ONE spec."""
    allowed = p.get("hosts")
    if allowed and str(host).lower() not in [str(a).lower() for a in allowed]:
        return f"hosts={allowed} does not include '{host}'"
    if p.get("native_only") and in_wsl():
        return ("native_only: true but this is WSL2 — with networkingMode=Nat, 127.0.0.1 here is the "
                "Linux guest, so this endpoint would be dead in the picker")
    return None


def on_host(p: dict, host: str) -> bool:
    """Back-compat name for the boolean answer; `scope_skip` carries the reason so both render paths
    can print the SAME explanation instead of paraphrasing it."""
    return scope_skip(p, host) is None


def render_pi(spec: dict, target: Path, keep_legacy: bool, host: str = "") -> tuple[str, list[str]]:
    """models.json for pi. Returns (text, notes)."""
    notes: list[str] = []
    prev_existing = {}
    if target.is_file():
        try:
            prev_existing = json.loads(target.read_text()).get("providers", {})
        except Exception:
            notes.append(f"existing {target} is not valid JSON — legacy values cannot be preserved")

    providers = {}
    for p in spec.get("providers", []):
        skip = scope_skip(p, host)
        if skip:
            notes.append(f"skipped provider '{p['id']}': {skip} (rendering it here would put a dead "
                         "endpoint in the picker)")
            continue
        body: dict = {}
        cred = p.get("credential", {})
        if "credential" in p and "apiKey" in p:
            sys.exit(f"FAIL: provider '{p['id']}' names BOTH a vault credential and a literal apiKey "
                     "— one of them would win silently. Pick one source (§6).")
        if "credential" in p:
            body["apiKey"] = op_secret(cred["vault"], cred["item"], cred.get("field", "credential"))
        elif p.get("unmanaged"):
            legacy = prev_existing.get(p["id"], {}).get("apiKey")
            if keep_legacy and legacy:
                body["apiKey"] = legacy
                notes.append(f"{p['id']}: credential NOT from the vault — preserved the value already "
                             f"in {target.name} ({mask(legacy)}); spec names "
                             f"op://{cred.get('vault','?')}/{cred.get('item','?')} which does not exist")
            else:
                sys.exit(f"FAIL: provider '{p['id']}' is `unmanaged: true` and no previous value exists to "
                         f"preserve. The spec names op://{cred.get('vault','?')}/{cred.get('item','?')} — "
                         f"record that item (and its row in docs/deployment-secrets.md), or pass "
                         f"--keep-legacy-credentials on a host that already holds a working key.")
        elif "apiKey" in p:
            # A machine-local listener with no auth: the laptop LM Studio leg (HD-474), baseUrl loopback.
            # The literal is a placeholder pi requires to be non-empty, NOT a secret — which is the only
            # reason it may sit in git when a real key never could. Loud, so nobody mistakes it for
            # managed auth, and so widening that endpoint past loopback stays a visible decision.
            body["apiKey"] = p["apiKey"]
            notes.append(f"{p['id']}: literal apiKey from the spec — a placeholder for a listener with "
                         "no auth. If this endpoint ever leaves loopback it needs a vault credential.")
        else:
            sys.exit(f"FAIL: provider '{p['id']}' names no `credential:`, is not `unmanaged: true`, and "
                     "carries no literal apiKey — refusing to render a provider with no apiKey at all.")
        body.update({k: v for k, v in p.items() if k not in META_KEYS and k not in ("models", "id")})
        # `id` is the spec's key for the provider, not a pi field — it becomes the dict KEY below.
        # (First live run proved this: rendering it produced a phantom drift on every provider.)
        # provider key order: baseUrl, api, apiKey, compat, models — whatever the spec order is,
        # with apiKey hoisted to where the live file has it so diffs stay readable.
        order = ["baseUrl", "api", "apiKey", "compat"]
        body = {k: body[k] for k in order if k in body} | {k: v for k, v in body.items() if k not in order}
        body["models"] = [{k: v for k, v in m.items() if k not in META_KEYS}
                          for m in p.get("models", [])]
        providers[p["id"]] = body
    return json.dumps({"providers": providers}, indent=2) + "\n", notes


def render_continue(spec: dict, host: str = "") -> tuple[str, list[str]]:
    """A standalone generated block. NOT merged into a user's config.yaml — see module docstring.
    Returns (text, notes): a Continue row pointing at a seat that cannot reach it is exactly as dead
    as a pi row, and silently dropping it would leave the operator wondering where the FIM model went."""
    rows = []
    notes: list[str] = []
    for p in spec.get("providers", []):
        skip = scope_skip(p, host)
        if skip:
            notes.append(f"continue: skipped provider '{p['id']}': {skip}")
            continue
        for m in p.get("models", []):
            c = m.get("continue", {})
            rows.append({
                "name": m.get("name", m["id"]),
                "model": f"{p['id']}/{m['id']}",
                "provider": "openai",
                "apiBase": p["baseUrl"],
                "apiKey": "«from 1Password — Continue reads it from its own secret store»",
                "contextLength": m["contextWindow"],
                "maxOutputTokens": m.get("maxTokens"),
                "capabilities": c.get("capabilities", []),
            })
    head = ("# GENERATED by scripts/render-pi-config.py from scripts/pi-config/models-spec.yml — HD-388\n"
            "# Do not hand-edit, and do not let it overwrite a real config: this file is a block.\n"
            "# Wiring a workstation to it (an `@`-import or a merge) is a per-machine choice and is\n"
            "# NOT verified by this script — see docs/pi-harness.md §4b.\n")
    return head + yaml.dump({"models": rows}, sort_keys=False, allow_unicode=True), notes


def render_piauth(spec: dict, target: Path) -> tuple[str, list[str]]:
    """auth.json for pi: {provider: {type, key}}. Returns (text, notes).

    Preserves, and SHOUTS about, any provider the target holds that the spec does not name: dropping
    somebody's working credential because the spec has not caught up is the worst thing this tool
    could do, and a silent drop in a credential file is the kind of bug you find out about by being
    locked out. Byte-for-byte pi-shaped output (2-space indent, NO trailing newline) is what lets
    `--check` prove a takeover was a no-op.
    """
    notes: list[str] = []
    out: dict = {}
    for a in spec.get("auth", []):
        cred = a["credential"]
        out[a["provider"]] = {"type": a.get("type", "api_key"),
                              "key": op_secret(cred["vault"], cred["item"], cred.get("field", "credential"))}
    if target.is_file():
        try:
            cur = json.loads(target.read_text())
        except Exception:
            cur = {}
        for k, v in cur.items():
            if k not in out:
                out[k] = v
                notes.append(f"{target.name}: provider '{k}' exists on this machine but is not in the "
                             f"spec — preserved. Add it to `auth:` (with its vault item) or delete it "
                             f"on purpose; do not let a render drop it quietly.")
    return json.dumps(out, indent=2), notes


def compare(tgt, sp, path: str = "") -> list[str]:
    """Structural diff, target first: '+' is something the spec renders and the target lacks,
    '-' is something the target holds that the spec no longer produces. Values under a
    secret-looking key are masked, so --check output is safe to paste into a commit."""
    out = []
    if isinstance(tgt, dict) and isinstance(sp, dict):
        for k in sorted(set(tgt) | set(sp)):
            if k not in tgt:
                out.append(f"  + {path}{k} (the spec renders it, the target does not have it)")
            elif k not in sp:
                out.append(f"  - {path}{k} (the target holds it, the spec does not produce it)")
            else:
                out += compare(tgt[k], sp[k], f"{path}{k}.")
    elif isinstance(tgt, list) and isinstance(sp, list):
        if len(tgt) != len(sp):
            out.append(f"  ~ {path}: target has {len(tgt)} item(s), the spec renders {len(sp)}")
        for i, (a, b) in enumerate(zip(tgt, sp)):
            out += compare(a, b, f"{path}[{i}].")
    elif tgt != sp:
        s = lambda v: mask(str(v)) if SECRET_RE.search(path) else f"{v!r}"
        out.append(f"  ~ {path.rstrip('.')}: target {s(tgt)} != spec {s(sp)}")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="Render client model config from one spec (HD-388)")
    ap.add_argument("--vendor", default="pi", choices=["pi", "pi_auth", "continue", "all"])
    ap.add_argument("--spec", default=str(SPEC))
    ap.add_argument("--out", help="override the target path (single --vendor only; e.g. a staging "
                                  "file for another host)")
    ap.add_argument("--check", action="store_true", help="compare against the target(s); write nothing")
    ap.add_argument("--keep-legacy-credentials", action="store_true",
                    help="preserve existing apiKey values for spec providers marked unmanaged: true")
    ap.add_argument("--no-backup", action="store_true", help="skip the timestamped backup (plumbing)")
    ap.add_argument("--host", default=socket.gethostname(),
                    help="host name to scope machine-local providers against (default: this host). "
                         "Pass the TARGET's name when rendering for another box, e.g. --host oldsrv.")
    args = ap.parse_args()

    spec = yaml.safe_load(Path(args.spec).read_text())
    if spec.get("version") != 1:
        sys.exit(f"FAIL: unsupported spec version {spec.get('version')!r}")
    vendors = spec.get("vendors", {})
    rc = 0

    targets = []
    if args.out and args.vendor == "all":
        # Silently ignoring --out for one of the two vendors is how a test render lands in a live
        # agent directory — which is exactly what it did on the first run of this flag.
        sys.exit("FAIL: --out with --vendor all is ambiguous (two targets, one path). Render one vendor.")
    # Predictable vendor mapping: each name renders exactly its own file, `all` = the two pi files.
    # (continue stays opt-in on purpose — see the spec: it writes beside a user's config, not into it.)
    if args.vendor in ("pi", "all"):
        targets.append(("pi", Path(args.out).expanduser() if args.out and args.vendor == "pi"
                        else Path(vendors.get("pi", {}).get("out", "~/.pi/agent/models.json")).expanduser()))
    if args.vendor in ("pi_auth", "all"):
        targets.append(("pi_auth", Path(args.out).expanduser() if args.out and args.vendor == "pi_auth"
                        else Path(vendors.get("pi_auth", {}).get("out", "~/.pi/agent/auth.json")).expanduser()))
    if args.vendor == "continue":
        targets.append(("continue", Path(args.out).expanduser() if args.out
                        else Path(vendors.get("continue", {}).get("out", "~/.continue/homelab-models.generated.yaml")).expanduser()))

    for name, target in targets:
        if name == "pi":
            text, notes = render_pi(spec, target, args.keep_legacy_credentials, args.host)
        elif name == "pi_auth":
            text, notes = render_piauth(spec, target)
        else:
            text, notes = render_continue(spec, args.host)
        for n in notes:
            print(f"NOTE {name}: {n}")
        if args.check:
            if not target.is_file():
                print(f"DRIFT {name}: {target} does not exist — render it")
                rc = 1
                continue
            spec_obj = (json.loads(text) if name in ("pi", "pi_auth")
                        else yaml.safe_load(text.split("\n", 4)[-1]))
            try:
                cur = json.loads(target.read_text()) if name == "pi" else yaml.safe_load(target.read_text())
            except Exception as e:
                print(f"DRIFT {name}: {target} is unreadable ({e.__class__.__name__})")
                rc = 1
                continue
            diff = compare(cur, spec_obj)
            if diff:
                print(f"DRIFT {name}: {target} differs from the spec in {len(diff)} place(s):")
                print("\n".join(diff[:40]))
                print("  → render it, or fix the spec if the spec is what changed. Either way do not "
                      "hand-edit the target and call it converged (HD-388).")
                rc = 1
            else:
                same = "" if name == "continue" else f" (byte-identical: {text == target.read_text()})"
                print(f"OK {name}: {target} matches the spec{same}")
            continue

        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_file() and not args.no_backup:
            stamp = subprocess.run(["date", "+%Y%m%d-%H%M%S"], capture_output=True, text=True).stdout.strip()
            shutil.copy2(target, target.with_name(f"{target.name}.pre-render-{stamp}"))
        fd, tmp = tempfile.mkstemp(dir=target.parent, prefix=".render-")
        with os.fdopen(fd, "w") as fh:
            fh.write(text)
        os.chmod(tmp, 0o600)
        os.replace(tmp, target)
        print(f"wrote {target} (mode 0600, {len(text)} bytes)")
    return rc


if __name__ == "__main__":
    sys.exit(main())
