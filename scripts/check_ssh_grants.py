#!/usr/bin/env python3
"""HD-416 — SSH grant audit: every authorized_keys entry on a managed host is NAMED, or it is loud.

WHY (the row): the per-host grant inventory in docs/deployment-secrets.md §Who is authorized where
exists only because a hand-made key authorizing `ansible-admin` on nas (NOPASSWD root there) was
found by sweeping every authorized_keys BY HAND. An inventory nothing checks is a list, not a gate.

WHAT IT DOES — read-only, by construction:
  * collects, per host and per account, `ssh-keygen -lf <file>` output (FINGERPRINT + COMMENT only);
  * builds the NAMED set from two authoritative sources, never a re-typed copy:
      1. the vault itself — `op` reads the `public_key` field of every `*_ssh` item and computes the
         fingerprint locally (authoritative, current, no prose involved);
      2. docs/deployment-secrets.md §Who is authorized where — the hand-made grants that have no
         vault item, plus the per-host placement and any `retired` verdict;
  * FAILS (rc 1) on a live grant no source names, on a grant marked retired that is still present,
    and on an ambiguous (colliding) fingerprint prefix;  reports named-but-absent as INFORMATIONAL
    (a revoked key is not an incident, an un-named key is).

GRANULARITY (HD-443, 2026-09-28): a grant is (key, HOST, ACCOUNT), and one row's `Where` cell can
carry SEVERAL placements of the same key with one of them struck through — `every managed host →
ansible-admin, plus pi → admin` with the `pi → admin` half revoked is a state this fleet actually
has. Live runs before this scored per IDENTITY, so the struck half made the WHOLE key read as revoked
and the fleet's own converge key came back as six `RETIRED-BUT-PRESENT` violations on the very
account IaC connects as. A gate that reds on the healthy case is a gate that gets muted, so
placements are scored per (host, account), and a whole key is retired only on a STRUCTURAL marker
(`Verdict` starting with `retired`, or a `Where` cell whose every placement is struck) — never
because the word appears somewhere in prose. `--self-test` pins both directions of that.

⛔ IT NEVER WRITES. There is no code path here that opens an `authorized_keys` for anything but
reading, and the remote command list is fixed (find / ssh-keygen -lf / cat). The characteristic
failure of an SSH-management tool is locking yourself out with your own fix (HD-416's own warning,
and HD-413's lesson in a different mechanism) — so revoke by hand, through the reversible sequence
in the owning doc, never through this script.

Usage:
  python3 scripts/check_ssh_grants.py                 # live audit of every managed host
  python3 scripts/check_ssh_grants.py --hosts vps,oldsrv
  python3 scripts/check_ssh_grants.py --self-test     # fixture run, no ssh, no op  (the canary)
  python3 scripts/check_ssh_grants.py --offline FILE  # score a captured collection (see --dump)
  python3 scripts/check_ssh_grants.py --dump FILE     # also write the collection for re-scoring
Exit: 0 = every live grant named; 1 = at least one unknown/retired-present/ambiguous; 2 = tooling
      failure (ssh/op missing, nothing collected) — a failed audit is not a clean audit.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import os
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DOC = REPO / "docs" / "deployment-secrets.md"
SECTION = "Who is authorized where"
# The vault items that ARE grants. Deriving fingerprints from the vault beats parsing prose:
# it cannot go stale, and a rotated key shows up as an unknown on the first run.
VAULT_SSH_ITEMS = ["domen_ssh", "ansible-admin_ssh", "ai_ssh"]
VAULT = "Homelab-ansible"
MANAGED_HOSTS = ["vps", "oldsrv", "nas", "pi", "spark"]
# Where to look. Accounts, not paths: an account's authorized_keys is the grant surface.
ACCOUNTS = ["root", "ansible-admin", "ai-debug", "domen", "svc-backup"]

# Fixed remote command: enumerate, then fingerprint. Nothing else runs remotely.
REMOTE = (
    "for f in $(sudo -n find /root /home /opt /srv /etc -maxdepth 4 -name authorized_keys "
    "-type f 2>/dev/null | sort); do "
    "echo \"@@FILE $f\"; sudo -n ssh-keygen -lf \"$f\" 2>/dev/null | sed 's/^/@@KEY /'; done"
)


def fp_of_pubkey(pub: str) -> str | None:
    """SHA256:<b64> fingerprint of an OpenSSH public-key line, computed locally."""
    parts = pub.split()
    if len(parts) < 2:
        return None
    try:
        blob = base64.b64decode(parts[1] + "=" * (-len(parts[1]) % 4))
    except Exception:
        return None
    d = hashlib.sha256(blob).digest()
    return "SHA256:" + base64.b64encode(d).decode().rstrip("=")


def core(fp: str) -> str:
    """The base64 payload only. The doc deliberately records SHORT fingerprints (`1uKzmwf…`), the
    vault/ssh-keygen give the full form, so both are compared on this."""
    return re.sub(r"[^A-Za-z0-9+/=]", "", fp.split("SHA256:")[-1])


def vault_named() -> list[dict]:
    """Authoritative named entries: fingerprints computed from the vault's public halves."""
    # Same convention as ansible-run.sh / restore-runner-key.sh: if the ambient shell has no token,
    # source the runner's 0600 token file. Without this the audit silently loses its authoritative
    # source and falls back to the doc's 7-char prefixes — still useful, but weaker, and it must
    # not fail quietly.
    if not os.environ.get("OP_SERVICE_ACCOUNT_TOKEN"):
        tok = Path.home() / ".config" / "op" / "homelab-sa-token"
        if tok.is_file():
            m = re.search(r"OP_SERVICE_ACCOUNT_TOKEN=['\"]?([^'\"\n]+)", tok.read_text(encoding="utf-8", errors="ignore"))
            if m:
                os.environ["OP_SERVICE_ACCOUNT_TOKEN"] = m.group(1)
    out = []
    for item in VAULT_SSH_ITEMS:
        r = subprocess.run(["op", "item", "get", item, "--vault", VAULT, "--format", "json"],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(f"WARN: op could not read {item} ({r.stderr.strip().splitlines()[-1] if r.stderr.strip() else 'op failed'})"
                  " — that key will be reported as UNKNOWN unless the doc names it", file=sys.stderr)
            continue
        import json
        try:
            data = json.loads(r.stdout)
        except Exception:
            continue
        for f in data.get("fields", []):
            if f.get("id") == "public_key" and f.get("value"):
                fp = fp_of_pubkey(str(f["value"]))
                if fp:
                    out.append({"fp": core(fp), "identity": item, "hosts": None,
                                "user": None, "placements": [],
                                "retired": False, "source": "vault"})
    return out


def merge_named(entries: list[dict]) -> list[dict]:
    """One row per identity: the FINGERPRINT from the vault (authoritative, full length), the
    PLACEMENT from the doc (that is what the table is for), a retired verdict from either.

    Why a merge and not a union: an earlier shape let the vault entry stand for "every managed
    host", which silently switched the placement check off — a claim nobody had measured. The
    vault knows WHICH KEY; only the doc knows WHERE it belongs and UNDER WHICH ACCOUNT.
    """
    by_id: dict[str, dict] = {}
    for e in entries:
        cur = by_id.get(e["identity"])
        if cur is None:
            by_id[e["identity"]] = dict(e)
            continue
        if e["source"] == "vault":
            cur["fp"] = e["fp"]
            cur["source"] = "vault+doc" if cur["source"] == "doc" else "vault"
        else:
            # The doc owns placement — including WHICH ACCOUNT on WHICH HOST — so its placement list
            # replaces whatever was there. The vault owns the fingerprint and nothing else.
            if e.get("placements"):
                cur["placements"] = e["placements"]
                cur["hosts"] = {h for q in e["placements"] if not q["revoked"] for h in q["hosts"]}
                cur["user"] = next((q["user"] for q in e["placements"]
                                    if not q["revoked"] and q["user"]), cur.get("user"))
            if e["retired"]:
                cur["retired"] = True
            if cur["source"] == "vault":
                cur["source"] = "vault+doc"
    return list(by_id.values())


def _placement(seg: str, revoked: bool) -> dict | None:
    """One `host(s) → account` fragment. `every managed host` expands; a fragment naming a user but
    no host means `wherever this key is named`."""
    hosts = set(re.findall(r"\b(vps|oldsrv|nas|pi|spark)\b", seg))
    if "every managed host" in seg.lower():
        hosts |= set(MANAGED_HOSTS)
    um = re.search(r"→\s*\**\s*`?([A-Za-z0-9._-]+)`?", seg)
    if not hosts and not um:
        return None
    return {"hosts": hosts, "user": um.group(1) if um else None, "revoked": revoked}


def parse_where(where: str) -> list[dict]:
    """Split a `Where` cell into PLACEMENTS. It can carry several (`every managed host →
    ansible-admin, plus pi → admin`), and one of them can be struck through, which revokes THAT
    placement and not the key. Struck segments are read first and then removed, so a revoked
    placement can never be re-added as a live one by the comma split."""
    out = [_placement(seg, True) for seg in re.findall(r"~~([^~]*)~~", where)]
    rest = re.sub(r"~~[^~]*~~", " ", where)
    for part in re.split(r"[,;]| \u2014 ", rest):
        out.append(_placement(part, False))
    return [q for q in out if q]


def parse_doc(path: Path = DOC) -> list[dict]:
    """Parse the grant table. Cells are `key | identity | where | verdict`."""
    text = path.read_text(encoding="utf-8")
    m = re.search(r"^#+ .*" + SECTION, text, re.M)
    if not m:
        die(f"section {SECTION!r} not found in {path}")
    rows, in_table = [], False
    for line in text[m.start():].splitlines():
        s = line.strip()
        if s.startswith("|") and "Fingerprint" in s:
            in_table = True
            continue
        if not in_table:
            continue
        if not s.startswith("|"):
            if rows:
                break                      # table ended
            continue
        if set(s) <= set("|-: "):
            continue                       # separator
        cells = [c.strip() for c in s.strip("|").split("|")]
        if len(cells) < 4:
            continue
        raw = cells[0].strip("` ")
        fp = core(raw)
        if len(fp) < 5:                    # not a fingerprint cell (a stray row)
            continue
        identity = cells[1].strip("` ")
        where, verdict = cells[2], cells[3]
        places = parse_where(where)
        live_places = [q for q in places if not q["revoked"]]
        # WHOLE-key retirement is STRUCTURAL, never a word found in prose: this row's verdict explains
        # that ONE of its placements is retired, which is not the same claim as "this key is revoked".
        retired = bool(re.match(r"\**\s*retired\b", verdict, re.I)) or (bool(places) and not live_places)
        rows.append({"fp": fp, "identity": identity,
                     "hosts": {h for q in live_places for h in q["hosts"]},
                     "user": next((q["user"] for q in live_places if q["user"]), None),
                     "placements": places,
                     "retired": retired, "source": "doc"})
    if not rows:
        die(f"no grant rows parsed from {path} §{SECTION}")
    return rows


def collect(hosts: list[str], accounts: list[str]) -> tuple[dict, list[str]]:
    """live[(host, file)][(fingerprint, comment)] — ssh is read-only; failures are collected."""
    live, errors = {}, []
    for h in hosts:
        r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", h, REMOTE],
                           capture_output=True, text=True)
        if r.returncode != 0:
            errors.append(f"{h}: ssh rc={r.returncode} {r.stderr.strip().splitlines()[-1] if r.stderr.strip() else ''}")
            continue
        cur = None
        for line in (r.stdout + r.stderr).splitlines():
            if line.startswith("@@FILE "):
                cur = line[len("@@FILE "):]
                live.setdefault((h, cur), [])
            elif line.startswith("@@KEY ") and cur:
                body = line[len("@@KEY "):]
                bits = body.split()
                if len(bits) >= 3:                     # bits: <bits> SHA256:xx comment
                    live[(h, cur)].append((bits[1], " ".join(bits[2:]) or "(no comment)"))
    if not live:
        die(f"collected nothing (hosts={hosts}); a failed audit is not a clean audit: {errors}")
    return live, errors


def account_of(path: str) -> str | None:
    """Which account's grant surface a file is: /root/… or /home/<user>/.ssh/… ."""
    if path.startswith("/root/"):
        return "root"
    m = re.match(r"^/home/([^/]+)/", path)
    return m.group(1) if m else None


def match(n: dict, fp: str) -> bool:
    c = core(fp)
    return bool(c) and (n["fp"] == c or c.startswith(n["fp"]) or n["fp"].startswith(c))


def score(live: dict, named: list[dict]) -> tuple[list, list, list]:
    """Return (violations, informational, notes). Pure: this is what the self-test pins."""
    bad, info = [], []
    for (host, path), keys in sorted(live.items()):
        for fp, comment in keys:
            matches = [n for n in named if match(n, fp)]
            # ^ prefix-tolerant: the doc deliberately records SHORT fingerprints (`1uKzmwf…`).
            # A key named by BOTH sources (vault + doc) is corroboration, not ambiguity — so
            # dedupe by identity and prefer the vault entry (it carries the full fingerprint).
            # First-run live lesson (2026-09-22): without the dedupe, every healthy vault-issued
            # grant on every host reported "AMBIGUOUS … matches ai_ssh, ai_ssh" — a red gate that
            # cries wolf is a muted gate.
            uniq, seen_ids = [], set()
            for m in sorted(matches, key=lambda x: 0 if x["source"] == "vault" else 1):
                if m["identity"] not in seen_ids:
                    seen_ids.add(m["identity"])
                    uniq.append(m)
            matches = uniq
            if len(matches) > 1:
                bad.append(f"AMBIGUOUS {host} {path}: {fp} ({comment}) matches "
                           + ", ".join(m["identity"] for m in matches))
                continue
            if not matches:
                bad.append(f"UNKNOWN {host} {path}: {fp} ({comment}) — no vault item and no doc row. "
                           "Name it in deployment-secrets.md §Who is authorized where or retire it.")
                continue
            n = matches[0]
            acct = account_of(path)
            places = n.get("placements") or []
            # A struck placement is must-be-absent at THAT (host, account) only. Scoring it against the
            # whole identity is what made the healthy converge key read as revoked on every host.
            struck = [q for q in places if q["revoked"]
                      and (not q["hosts"] or host in q["hosts"])
                      and (not q["user"] or not acct or q["user"] == acct)]
            if n["retired"] or struck:
                which = "the whole key" if n["retired"] else \
                        f"the {host} → {struck[0]['user'] or 'any account'} placement"
                bad.append(f"RETIRED-BUT-PRESENT {host} {path}: {fp} ({comment}) = {n['identity']} — "
                           f"{which} is struck in the inventory; the file says otherwise.")
                continue
            on_host = [q for q in places if not q["revoked"] and (not q["hosts"] or host in q["hosts"])]
            if places and not on_host:
                bad.append(f"UNPLACED {host} {path}: {fp} ({comment}) = {n['identity']} — named for "
                           f"{sorted(n['hosts'])}, found on {host}")
                continue
            # The ACCOUNT is half the grant. A named key under an unnamed account is the exact
            # shape HD-416 was born from (a key authorizing ansible-admin as NOPASSWD root on nas
            # was found by hand-sweeping, because nothing compared the account either).
            want = {q["user"] for q in on_host if q["user"]}
            if acct and want and acct not in want:
                bad.append(f"WRONG-ACCOUNT {host} {path}: {fp} ({comment}) = {n['identity']} — "
                           f"named as {sorted(want)}, authorized as {acct}. Name the account or revoke it.")
    seen = {core(fp) for keys in live.values() for fp, _ in keys}
    for n in named:
        if not n["retired"] and not any(s.startswith(n["fp"]) or n["fp"].startswith(s) for s in seen):
            info.append(f"named-but-unseen: {n['identity']} ({n['fp']}…) — expected on "
                        f"{sorted(n['hosts']) or 'any host'}; not collected (revoked, host offline, or scope)")
    return bad, info, []


def self_test() -> int:
    """The canary: a fixture live-set that MUST go red on an unknown, a retired-present and an
    ambiguous prefix, and MUST stay green on a named grant. Without this the checker could stop
    detecting and still print OK — the failure mode CONVENTIONS §6 names."""
    named = [{"fp": "AAAA1111", "identity": "ansible-admin_ssh", "hosts": set(MANAGED_HOSTS),
              "user": "ansible-admin", "retired": False, "source": "vault",
              "placements": [{"hosts": set(MANAGED_HOSTS), "user": "ansible-admin", "revoked": False}]},
             {"fp": "BBBB2222", "identity": "ha-sync@pi.kogler.si", "hosts": {"oldsrv", "vps"},
              "user": None, "retired": False, "source": "doc",
              "placements": [{"hosts": {"oldsrv", "vps"}, "user": None, "revoked": False}]},
             {"fp": "CCCC3333", "identity": "oldsrv-rsync", "hosts": set(),
              "user": None, "retired": True, "source": "doc",
              "placements": [{"hosts": {"nas"}, "user": "ansible-admin", "revoked": True}]}]
    cases = [
        ("named grant stays green",
         {("oldsrv", "/home/ansible-admin/.ssh/authorized_keys"): [("SHA256:AAAA1111ABC", "ansible-admin")]}, 0),
        ("unknown key is red",
         {("oldsrv", "/home/ansible-admin/.ssh/authorized_keys"): [("SHA256:ZZZZ9999ABC", "hand-made")]}, 1),
        ("retired key still present is red",
         {("nas", "/root/.ssh/authorized_keys"): [("SHA256:CCCC3333ABC", "oldsrv-rsync")]}, 1),
        ("grant found off its named host is red",
         {("spark", "/home/ansible-admin/.ssh/authorized_keys"): [("SHA256:BBBB2222ABC", "ha-sync@pi")]}, 1),
        ("a short doc prefix still matches a full fingerprint",
         {("vps", "/home/x/.ssh/authorized_keys"): [("SHA256:BBBB", "ha-sync@pi")]}, 0),
        ("a named key under an unnamed ACCOUNT is red",   # the HD-416 origin story, mechanised
         {("spark", "/home/other/.ssh/authorized_keys"): [("SHA256:AAAA1111ABC", "someone")]}, 1,
         "WRONG-ACCOUNT"),
        ("ONE struck placement does not revoke the key elsewhere (HD-443)",
         {("oldsrv", "/home/ansible-admin/.ssh/authorized_keys"): [("SHA256:AAAA1111ABC", "iac")]}, 0),
        ("the struck placement, live where it was revoked, is red AS a retired grant",
         {("pi", "/home/admin/.ssh/authorized_keys"): [("SHA256:AAAA1111ABC", "owner")]}, 1,
         "RETIRED-BUT-PRESENT"),
    ]
    # The multi-placement row must be scored per placement, so the fixtures carry a revoked `pi →
    # admin` half next to the live `every managed host → ansible-admin` half — the exact shape of the
    # `ansible-admin_ssh` row, whose struck `admin` placement used to mark the converge key itself
    # retired on all five hosts (six false REDs, 2026-09-28).
    named[0]["placements"].append({"hosts": {"pi"}, "user": "admin", "revoked": True})
    rc = 0
    for case in cases:
        label, live, want = case[:3]
        kind = case[3] if len(case) > 3 else None
        bad, _, _ = score(live, named)
        got = 1 if bad else 0
        # The KIND is part of the assertion: a red that fires for the wrong reason (retired where the
        # claim was wrong-account, or the other way round) teaches the next reader the wrong lesson.
        kind_ok = kind is None or any(v.startswith(kind) for v in bad)
        print(f"  {'ok  ' if got == want and kind_ok else 'FAIL'} {label} → {'red' if got else 'green'}"
              + ('' if kind_ok else f" (wanted {kind}, got {[v.split(' ')[0] for v in bad]})"))
        rc |= (got ^ want) | (0 if kind_ok else 1)
    # ambiguity: a live key matching two DIFFERENT named identities must be reported, never
    # guessed away — and a key named twice under ONE identity must NOT be reported.
    dup = named + [{"fp": "AAAA", "identity": "looks-similar", "hosts": set(MANAGED_HOSTS),
                    "user": None, "retired": False, "source": "doc", "placements": []}]
    bad, _, _ = score({("vps", "/root/.ssh/authorized_keys"): [("SHA256:AAAA1111ABC", "x")]}, dup)
    ok = any(v.startswith("AMBIGUOUS") for v in bad)
    print(f"  {'ok  ' if ok else 'FAIL'} colliding short prefixes are reported, not guessed")
    both = named + [{"fp": "AAAA1111", "identity": "ansible-admin_ssh", "hosts": set(MANAGED_HOSTS),
                     "user": "ansible-admin", "retired": False, "source": "doc",
                     "placements": [{"hosts": set(MANAGED_HOSTS), "user": "ansible-admin",
                                     "revoked": False}]}]
    bad2, _, _ = score({("vps", "/home/ansible-admin/.ssh/authorized_keys"): [("SHA256:AAAA1111ABC", "ansible")]}, both)
    ok2 = not bad2
    print(f"  {'ok  ' if ok2 else 'FAIL'} one key named by vault AND doc is corroboration, not ambiguity")
    # merge_named: the vault must NOT get to assert a placement the doc never named
    merged = merge_named([{"fp": "ZZZZ1111", "identity": "ai_ssh", "hosts": None, "user": None,
                           "placements": [], "retired": False, "source": "vault"},
                          {"fp": "ZZZZ", "identity": "ai_ssh", "hosts": {"nas"}, "user": "ai-debug",
                           "placements": [{"hosts": {"nas"}, "user": "ai-debug", "revoked": False}],
                           "retired": False, "source": "doc"}])
    ok3 = (len(merged) == 1 and merged[0]["hosts"] == {"nas"} and merged[0]["fp"] == "ZZZZ1111")
    print(f"  {'ok  ' if ok3 else 'FAIL'} merge keeps the doc's placement and the vault's fingerprint")

    # The parser, pinned: a verdict that merely EXPLAINS a retired placement must not revoke the key,
    # and a fully-struck row must. This is the regression that made the healthy fleet key read as
    # revoked six times over; prose is not a marker.
    fx = Path(tempfile.mkdtemp(prefix="grant-fixture-")) / "grant-table.md"
    fx.write_text(
        "### Who is authorized where\n"
        "| Fingerprint | Identity | Where authorized | Verdict |\n|---|---|---|---|\n"
        "| `AAAA1111` | `ansible-admin_ssh` | every managed host → `ansible-admin`, ~~plus pi → `admin`~~ |"
        " live converge key; this row's prose explains that one placement is retired, which is NOT a marker |\n"
        "| `CCCC3333` | `oldsrv-rsync` | ~~nas → `ansible-admin`~~ | **retired 2026-09-21** |\n",
        encoding="utf-8")
    rows = {r["identity"]: r for r in parse_doc(fx)}
    r1, r2 = rows.get("ansible-admin_ssh"), rows.get("oldsrv-rsync")
    ok4 = (r1 and not r1["retired"] and len(r1["placements"]) == 2
           and any(q["revoked"] and q["hosts"] == {"pi"} for q in r1["placements"])
           and not any(q["revoked"] for q in r1["placements"] if q["user"] == "ansible-admin")
           and r2 and r2["retired"])
    print(f"  {'ok  ' if ok4 else 'FAIL'} a struck placement revokes that placement, not the key")
    return rc | (0 if ok else 1) | (0 if ok2 else 1) | (0 if ok3 else 1) | (0 if ok4 else 1)


def die(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(2)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0], formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--hosts", default=",".join(MANAGED_HOSTS), help="comma list (default: all managed)")
    ap.add_argument("--accounts", default=",".join(ACCOUNTS), help="informational only: the sweep is by authorized_keys file, so an unexpected account still surfaces")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--offline", metavar="FILE", help="score a captured collection instead of ssh-ing")
    ap.add_argument("--dump", metavar="FILE", help="write the collection (host<TAB>file<TAB>fp<TAB>comment) for re-scoring")
    args = ap.parse_args()

    if args.self_test:
        return self_test()
    named = merge_named(vault_named() + parse_doc())

    if args.offline:
        live = {}
        for line in Path(args.offline).read_text(encoding="utf-8").splitlines():
            if not line.strip() or line.startswith("#"):
                continue
            host, path, fp, *rest = line.split("\t")
            live.setdefault((host, path), []).append((fp, " ".join(rest) or "(no comment)"))
        errors = []
    else:
        live, errors = collect([h for h in args.hosts.split(",") if h], [a for a in args.accounts.split(",") if a])
        if args.dump:
            with open(args.dump, "w", encoding="utf-8") as fh:
                fh.write("# host\tfile\tfingerprint\tcomment — captured by check_ssh_grants.py (read-only)\n")
                for (host, path), keys in sorted(live.items()):
                    for fp, c in keys:
                        fh.write(f"{host}\t{path}\t{fp}\t{c}\n")
            print(f"collection written: {args.dump}")

    total = sum(len(v) for v in live.values())
    print(f"collected {total} grant(s) from {len({h for h, _ in live})} host(s); "
          f"{len([n for n in named if n['source'] == 'vault'])} from the vault, "
          f"{len([n for n in named if n['source'] == 'doc'])} from the doc")
    for e in errors:
        print(f"  ssh-scope note: {e}", file=sys.stderr)
    bad, info, _ = score(live, named)
    for v in bad:
        print("VIOLATION: " + v)
    for i in info:
        print("info: " + i)
    if bad:
        print(f"\nFAIL: {len(bad)} grant(s) are not named (or are retired and still present). "
              "Revoke by hand with the reversible sequence in deployment-secrets.md — never with this tool.")
        return 1
    print("OK: every live grant is named (vault-issued or written in the inventory).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
