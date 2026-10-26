#!/usr/bin/env python3
"""The python half of ONE decision: which 1Password credential answers this leg.

The rule itself lives in `scripts/lib/vault-env.sh` (env → this seat's 0600 install → the Debian
engine's install across the WSL door → nothing). This module does not re-implement it: it runs
`vault-env.sh --emit` and takes the value off a PIPE, so a python leg and a bash leg can never
disagree about which credential they used — the failure that made the Win11 seat fall back to the
1Password desktop app while every python-side fallback still looked healthy.

Hygiene: the value is never printed, never an argument, never written to a file. What is kept is
provenance — route, length, `sha256[:12]` — because `op vault list` cannot tell the read-scoped and
write-scoped service accounts apart, so "which credential answered" has to be stated, not assumed.

`--check` prints that provenance and nothing else. Exit 0 resolved · 1 boundary (no credential
reachable here) · 2 could not run.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import script_path  # noqa: E402

STATE = {"route": "unresolved", "len": 0, "sha": "n/a", "why": "ensure() has not run"}

# --- vault IDs: the half that costs quota -------------------------------------------------
# A NAME is not a free address: `op item get` and `op read` resolve the name first and 1Password bills
# the resolving — 3 requests for a name-addressed read, 1 for an ID-addressed one (1Password CLI docs,
# "Commands that make multiple requests"). The ceiling that binds is not the token's 1000 reads/hour but
# the ACCOUNT's 1000 requests/24 h shared by every service account on it (`op service-account ratelimit`
# prints both lines), so the leak gate's 143 name-addressed gets spent ~429 of them: THREE gate runs
# empty the day for every other automation on the account. `item_ref()` is the leg's way of asking for
# the cheapest address that is still CORRECT: an unknown title returns the NAME plus a note, never a
# guessed ID, because a stale ID is a wrong answer dressed as a cheap one.
#
# The map is ONE file per vault, the same file the bash face reads and writes, so a warm seat costs the
# vault nothing: line 1 `# vault_id=<id>`, then `title\titem_id`. IDs are not secrets; the file is still
# written 0600 and atomically, because a half-written map would answer wrong IDs.


def state_dir() -> Path:
    return Path(os.environ.get("HL_VAULT_STATE_DIR")
                 or Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local" / "state")))
                 / "homelab")


def map_file(vault: str) -> Path:
    return state_dir() / f"op-map-{vault.replace('/', '_')}.tsv"


def _read_map(vault: str) -> tuple[str | None, dict[str, str]]:
    """(vault_id, {title: item_id}) from the cache file; (None, {}) when there is no map yet."""
    f = map_file(vault)
    try:
        lines = f.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return None, {}
    vid = None
    items: dict[str, str] = {}
    for line in lines:
        if line.startswith("# vault_id="):
            vid = line.split("=", 1)[1].strip() or None
            continue
        parts = line.split("\t")
        if len(parts) == 2 and parts[1]:
            items[parts[0]] = parts[1]
    return vid, items


def map_refresh(vault: str) -> tuple[bool, str]:
    """Rebuild the map from ONE `op item list` (2 reads by name, 1 by ID). rc-style (ok, why).

    A failed read leaves the OLD map in place: one unreachable vault read must not widen ignorance by
    deleting what the last successful read learned.
    """
    ok, why = ensure()
    if not ok:
        return False, f"no vault credential ({why})"
    if not shutil.which("op"):
        return False, "no op CLI on PATH"
    try:
        r = subprocess.run(["op", "item", "list", "--vault", vault, "--format", "json"],
                           capture_output=True, stdin=subprocess.DEVNULL, timeout=120)
    except (subprocess.TimeoutExpired, OSError) as exc:
        return False, f"op item list did not answer: {exc}"
    if r.returncode != 0:
        return False, f"op item list rc {r.returncode}: {(r.stderr or b'').decode('utf-8', 'replace').strip()[:120]}"
    try:
        rows = json.loads(r.stdout.decode("utf-8", "replace"))
    except json.JSONDecodeError as exc:
        return False, f"op item list was not JSON: {exc}"
    if not isinstance(rows, list) or not rows:
        return False, "op item list answered no rows — an empty vault answer is not an empty map"
    vids = [str((row.get("vault") or {}).get("id") or "") for row in rows if isinstance(row, dict)]
    vid = next((v for v in vids if v), "")
    body = "".join(f"{row.get('title', '')}\t{row.get('id', '')}\n"
                   for row in rows if isinstance(row, dict) and row.get("id"))
    if not body:
        return False, "the item list carried no id/title pairs"
    f = map_file(vault)
    try:
        f.parent.mkdir(parents=True, exist_ok=True)
        tmp = f.with_name(f".op-map-{os.getpid()}.tmp")
        tmp.write_text(f"# vault_id={vid}\n{body}", encoding="utf-8")
        os.replace(tmp, f)
        os.chmod(f, 0o600)
    except OSError as exc:
        return False, f"cannot write {f}: {exc}"
    return True, vid or "written"


def vault_id(vault: str) -> str | None:
    """The vault's ID when the map knows it — None means the caller keeps the NAME."""
    vid, _ = _read_map(vault)
    if vid:
        return vid
    ok, _why = map_refresh(vault)
    vid, _ = _read_map(vault)
    return vid if ok else None


def item_ref(vault: str, item: str) -> tuple[str, str, str]:
    """(vault_arg, item_arg, note) — the ID form when it is known, the NAME form when it is not.

    A miss refreshes the map once, because a renamed item should cost 2 reads and then be right
    forever; it still does not invent an ID. `note` is what a leg prints so the cheap route is visible
    in the log rather than assumed: `IDs` for the 1-read form, `names` for the 3-read fallback.
    """
    vid, items = _read_map(vault)
    iid = items.get(item)
    if iid is None:
        map_refresh(vault)
        vid, items = _read_map(vault)
        iid = items.get(item)
    if iid:
        return (vid or vault), iid, "IDs"
    return vault, item, "names (ID map had no entry — 3 reads instead of 1)"



def _lib() -> Path:
    return script_path("vault-env.sh")


def provenance() -> str:
    """route / hash — the line a report prints so a verdict names its credential.

    Length stays out on purpose: `check_secret_leak.py` forbids a value LENGTH in its own output
    (its requirement (b)), and the hash plus the route is what identifies the credential anyway.
    """
    s = STATE
    return f"vault credential: route={s['route']} sha256[:12]={s['sha']}"


def ensure(timeout: int = 120) -> tuple[bool, str]:
    """Make OP_SERVICE_ACCOUNT_TOKEN available to this process. Returns (ok, reason).

    An ambient token is respected untouched — a seat that already exported one is not re-resolved,
    and an `op whoami` that answers 403 with a fresh file is the environment-beats-the-file trap, not
    this function's bug. Otherwise the bash lib decides; on rc != 0 NOTHING is set, which is the
    point: a leg that proceeds without a credential calls `op` into the desktop app, and on the Win11
    seat that is a consent dialog per read rather than an error.
    """
    if os.environ.get("OP_SERVICE_ACCOUNT_TOKEN"):
        STATE.update(route="env", len=len(os.environ["OP_SERVICE_ACCOUNT_TOKEN"]),
                     sha=hashlib.sha256(os.environ["OP_SERVICE_ACCOUNT_TOKEN"].encode()).hexdigest()[:12],
                     why="ambient")
        return True, "ambient"
    bash = shutil.which("bash")
    if not bash:
        STATE.update(route="none", why="no bash on PATH, so lib/vault-env.sh cannot answer")
        return False, STATE["why"]
    lib = _lib()
    try:
        # stdin from DEVNULL: a script reading a TTY-shaped stdin is the hang-with-a-plausible-face
        # class. The value arrives on stdout (a pipe); the verdict line arrives on stderr.
        r = subprocess.run([bash, str(lib), "--emit"], capture_output=True,
                           stdin=subprocess.DEVNULL, timeout=timeout)
    except subprocess.TimeoutExpired:
        STATE.update(route="none", why=f"lib/vault-env.sh --emit did not answer within {timeout}s")
        return False, STATE["why"]
    out = (r.stdout or b"").decode("utf-8", "replace")
    err = (r.stderr or b"").decode("utf-8", "replace")
    if r.returncode != 0 or not out.strip():
        why = " ".join(err.split()) or f"--emit rc {r.returncode}"
        STATE.update(route="none", why=why)
        return False, why
    val = out.strip("\r\n")
    os.environ["OP_SERVICE_ACCOUNT_TOKEN"] = val
    route = "resolved"
    for tok in err.split():
        if tok.startswith("route="):
            route = tok.split("=", 1)[1]
    STATE.update(route=route, len=len(val),
                 sha=hashlib.sha256(val.encode("utf-8", "surrogateescape")).hexdigest()[:12],
                 why="resolved")
    return True, route


def self_test() -> int:
    """Offline arms: the map is read, honored, and fallen back from WITHOUT a vault read.

    These are the arms that matter on a day the account's request budget is spent: the cheapest correct
    address has to be provable from the fixture, because tomorrow it may not be provable from the vault.
    The last arm is the one that keeps the two faces honest — a map written by python must be readable by
    the bash lib, or "one map" is a comment, not a design.
    """
    import tempfile

    fails = 0

    def check(label: str, ok: bool, detail: str = "") -> None:
        nonlocal fails
        fails += 0 if ok else 1
        print(f"  arm {label}: {'ok' if ok else 'FAIL'}{(' — ' + detail) if (detail and not ok) else ''}")

    with tempfile.TemporaryDirectory() as td:
        os.environ["HL_VAULT_STATE_DIR"] = str(Path(td) / "state")
        f = map_file("Test-vault")
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text("# vault_id=xvh7vv7aaaaaaaaaaaaaaaaaaaaaaaaaa\n"
                     "item_one\taaaaaaaaaaaaaaaaaaaaaaaaaa\n",
                     encoding="utf-8")
        check("the map file is the SAME path the bash lib uses", map_file("Test-vault").is_file())
        vid, items = _read_map("Test-vault")
        check("the map parses the vault ID and the title rows",
              vid == "xvh7vv7aaaaaaaaaaaaaaaaaaaaaaaaaa" and items.get("item_one") == "aaaaaaaaaaaaaaaaaaaaaaaaaa",
              f"vid={vid!r} items={items!r}")
        v_arg, i_arg, form = item_ref("Test-vault", "item_one")
        check("a known title answers with IDs (1 read, not 3)",
              v_arg == "xvh7vv7aaaaaaaaaaaaaaaaaaaaaaaaaa"
              and i_arg == "aaaaaaaaaaaaaaaaaaaaaaaaaa" and form == "IDs", f"{v_arg} {i_arg} {form}")

        real = map_refresh

        def offline(_vault: str) -> tuple[bool, str]:
            return False, "offline fixture"

        globals()["map_refresh"] = offline
        try:
            v_arg, i_arg, form = item_ref("Test-vault", "never_named")
        finally:
            globals()["map_refresh"] = real
        check("an unknown title keeps the NAME and says the cost out loud",
              v_arg == "Test-vault" and i_arg == "never_named" and form.startswith("names"),
              f"{v_arg} {i_arg} {form}")

        # The cross-face arm: the bash lib must read what python wrote. It runs against a stub `op` that
        # MARKS the call and fails, so a read is both visible and fatal — and PATH stays real, because a
        # stripped PATH makes the sourced lib's own `d=$(dirname "$d")` walk spin forever: the hang this
        # arm's first draft caused. A fixture that can hang is a fixture that must carry a timeout.
        bash = shutil.which("bash")
        if not bash:
            print("  arm the bash face reads a map python wrote: NOTE — no bash on PATH, not judged")
        else:
            stub = Path(td) / "bin"
            stub.mkdir()
            (stub / "op").write_text(
                '#!/bin/sh\nprintf x >> "$VAULT_STUB_CALLS"\n'
                'echo "fixture: no vault read allowed in this arm" >&2\nexit 1\n',
                encoding="utf-8")
            (stub / "op").chmod(0o755)
            calls = Path(td) / "op.calls"
            calls.write_text("", encoding="utf-8")
            try:
                r = subprocess.run(
                    [bash, "-c", 'source "$1" >/dev/null 2>&1 || source "$1" --source-only; '
                                 'printf "%s|%s" "$(hl_vault_id Test-vault)" '
                                 '"$(hl_vault_item_id Test-vault item_one)"',
                     "x", str(_lib())],
                    capture_output=True, stdin=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace", timeout=60,
                    env=dict(os.environ, PATH=f"{stub}{os.pathsep}{os.environ.get('PATH', '')}",
                             VAULT_STUB_CALLS=str(calls), HL_VAULT_FILE="/nonexistent"))
                clean = r.returncode == 0 and not calls.read_text(encoding="utf-8")
                check("the bash face reads a map python wrote, and reads the vault ZERO times", clean
                      and r.stdout == "xvh7vv7aaaaaaaaaaaaaaaaaaaaaaaaaa|aaaaaaaaaaaaaaaaaaaaaaaaaa",
                      f"rc {r.returncode} calls {len(calls.read_text(encoding='utf-8'))} "
                      f"out {r.stdout!r} err {(r.stderr or '')[:120]!r}")
            except subprocess.TimeoutExpired:
                check("the bash face reads a map python wrote, and reads the vault ZERO times", False,
                      "60 s timeout — a fixture that hangs is a bug in the fixture")
        os.environ.pop("HL_VAULT_STATE_DIR", None)

    if fails:
        print(f"vault_env.py --self-test: FAILED — {fails} arm(s)")
        return 1
    print("vault_env.py --self-test: OK (5 arms — the map is read, honored, fallen back from, and shared "
          "with the bash face; none of it needed a vault read)")
    return 0


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()
    if len(sys.argv) > 2 and sys.argv[1] == "--map":
        ok, why = map_refresh(sys.argv[2])
        vid, items = _read_map(sys.argv[2])
        print(f"vault-env: map {sys.argv[2]} items={len(items)} vault_id={vid} file={map_file(sys.argv[2])}"
              if ok else f"vault-env: the map for {sys.argv[2]} was not rebuilt: {why}"
              " — legs keep the name form (3 reads each)")
        return 0 if ok else 1
    ok, why = ensure()
    print(f"vault-env: {provenance()}" + ("" if ok else f" — {why}"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
