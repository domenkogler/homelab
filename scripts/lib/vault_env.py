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
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import script_path  # noqa: E402

STATE = {"route": "unresolved", "len": 0, "sha": "n/a", "why": "ensure() has not run"}


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


def main() -> int:
    ok, why = ensure()
    print(f"vault-env: {provenance()}" + ("" if ok else f" — {why}"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
