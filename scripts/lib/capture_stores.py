#!/usr/bin/env python3
"""capture_stores.py — WHERE this seat keeps its own conversation, in ONE walk (HD-1181's seam).

WHAT MOVED HERE AND WHY IT IS HERE RATHER THAN COPIED. `gate/check_secret_leak.py` owned the walk, and
two legs already reached it by IMPORT (`contain-leaked-values.py` does `import check_secret_leak as
leak`; `check_secret_debt.py` reads a verdict through `leak.capture_stores` and carries a ratchet that
reddens if the walk is ever re-spelled locally). A third leg — `secrets/redact.py`, the containment
tool for the seats that hold NO vault — needs the same answer, and importing a GATE from a seat tool
would make the gate a dependency of an act that has no business judging anything. So the walk lives
here, stdlib-only and vault-blind, and the leak eye re-exports it so every existing importer, and that
ratchet, keeps resolving exactly as before (`from capture_stores import capture_stores` lands in the
module `__dict__`, which is what `check_secret_debt.py` asserts).

THE DISTINCTION THAT IS THE WHOLE POINT — `read` is not `files`. A store whose root exists was READ, so
zero files in it PROVES ABSENCE; a root that is not there was NOT READ and proves nothing, and a
scratch root under `$TMPDIR` can keep a corpus non-empty while the persistent store the debts live in
was never opened at all. That is the HD-1181 failure shape — a store-less checkout printing live debts
as STALE — so no caller may decide a class on "corpus non-empty" without naming its stores. `--list`
and `--self-test` both print the store line for that reason.

WHAT IT NEVER DOES: read a value, hash one, or print one. It returns PATHS and store metadata only, so
the disclosure budget of the caller (CONVENTIONS §6: no value, no length, no captured line) cannot be
broken by the discovery step.

USE:
    python3 scripts/lib/capture_stores.py --list        # what stores exist on THIS seat, counts only
    python3 scripts/lib/capture_stores.py --self-test   # fixture arms; writes nothing outside a temp dir
Exit: 0 ok · 1 a self-test arm failed. Stdlib only; imports nothing from this repo.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys
import tempfile
from pathlib import Path

# Run-capture patterns under the pi temp roots and $SESSION_DIR. `session.jsonl` is the child-session
# capture; without it a value that reached a subagent's own transcript is invisible to every leg.
CAPTURE_PATTERNS = ("output-*.log", "events.jsonl", "session.jsonl", "logs/*.log")

# The run-capture class is not one corpus, it is STORES, and they are not interchangeable:
# `pi-transcripts` (~/.pi/agent/sessions) is the PERSISTENT store the ledger debts sit in — it
# survives a reboot, so its ABSENCE proves nothing while its PRESENCE proves absence of a hit;
# `pi-subagents-*` scratch roots and a per-session `$SESSION_DIR` live under /tmp, so they are
# wiped (their absence can be evidence of closure, their presence is no evidence about the
# persistent store at all). A guard that judges the class on "corpus non-empty" lets scratch keep
# the corpus non-empty when the transcript store is absent — that is how a store-less checkout
# exits 0 and prints live debts as STALE. So: every run-capture verdict NAMES the stores it read,
# and the class is JUDGED only when the persistent store was READ.
def capture_stores(home: Path | None = None) -> dict[str, dict]:
    """store name -> {files, read, why}. READ means the store's root exists and was scanned — zero
    files in a READ store still proves absence there; a root that is not there was NOT READ and
    cannot close a debt recorded in it."""
    home = Path(home) if home else Path.home()
    stores: dict[str, dict] = {}
    sess = home / ".pi" / "agent" / "sessions"
    files = [str(p) for p in sess.rglob("*.jsonl")] if sess.is_dir() else []
    stores["pi-transcripts"] = {
        "files": files,
        "read": sess.is_dir(),
        "why": f"scanned {sess}" if sess.is_dir() else f"no store at {sess} on this seat",
    }
    scratch: list[str] = []
    roots: list[str] = []
    tmp = os.environ.get("TMPDIR", "/tmp")
    roots += sorted(glob.glob(os.path.join(tmp, "pi-subagents-*")))
    if tmp != "/tmp":
        roots += sorted(glob.glob("/tmp/pi-subagents-*"))
    for root in roots:
        for pat in CAPTURE_PATTERNS:
            scratch += [p for p in glob.glob(os.path.join(root, "**", pat), recursive=True)
                        if os.path.isfile(p)]
    stores["pi-subagents-scratch"] = {
        "files": sorted(set(scratch)),
        "read": bool(roots),
        "why": f"scanned {len(roots)} root(s)" if roots else f"no pi-subagents-* root under {tmp}",
    }
    if os.environ.get("SESSION_DIR"):
        sd = os.environ["SESSION_DIR"]
        sfiles: list[str] = []
        if os.path.isdir(sd):
            for pat in CAPTURE_PATTERNS:
                sfiles += [p for p in glob.glob(os.path.join(sd, "**", pat), recursive=True)
                           if os.path.isfile(p)]
        stores["session-dir"] = {"files": sorted(set(sfiles)), "read": os.path.isdir(sd),
                                 "why": f"scanned {sd}" if os.path.isdir(sd)
                                        else f"SESSION_DIR points nowhere ({sd})"}
    return stores


def capture_files(home: Path | None = None) -> list[str]:
    """Flat view of every store — the scan set. The VERDICT view is `capture_stores()`; a run that
    decides per class on "is the corpus non-empty" without naming its stores is the HD-1181 failure
    shape (scratch keeping a store-less checkout green)."""
    return sorted({p for s in capture_stores(home).values() for p in s["files"]})


def stores_note(stores: dict[str, dict]) -> str:
    """The line that makes the verdict name its stores — a run must say WHERE it looked, because
    'checked the captures' is false whenever only scratch answered."""
    read = [f"{name} ({len(s['files'])} file(s); {s['why']})" for name, s in sorted(stores.items())
            if s["read"]]
    unread = [f"{name} ({s['why']})" for name, s in sorted(stores.items()) if not s["read"]]
    line = "run-capture stores read: " + (", ".join(read) or "NONE")
    if unread:
        line += " — NOT READ: " + ", ".join(unread)
    return line


# ------------------------------------------------------------------------ self-test
def self_test() -> int:
    """Four arms, all inside a temp dir, ZERO writes to a real store: the PERSISTENT store read with
    two captures in it (one of them a CHILD session.jsonl), the scratch root proving every entry of
    CAPTURE_PATTERNS is actually reachable, a HOME with no store at all (the arm that must say NOT
    READ rather than print a clean count), and $SESSION_DIR on a real dir and on a path that is not
    one. The last arm is the one that keeps `--list` honest on a seat where the variable is set but
    the directory was already reaped."""
    fails: list[str] = []
    with tempfile.TemporaryDirectory(prefix="capture-stores-selftest-") as td:
        root = Path(td)
        home = root / "home"
        sess = home / ".pi" / "agent" / "sessions" / "--D--source-x--"
        (sess).mkdir(parents=True)
        (sess / "session.jsonl").write_text("{}\n", encoding="utf-8")
        child = sess / "uuid" / "run-0"
        child.mkdir(parents=True)
        (child / "session.jsonl").write_text("{}\n", encoding="utf-8")

        tmp = root / "tmp"
        scratch = tmp / "pi-subagents-fixture"
        (scratch / "logs").mkdir(parents=True)
        (scratch / "events.jsonl").write_text("{}\n", encoding="utf-8")
        (scratch / "logs" / "a.log").write_text("x\n", encoding="utf-8")
        (scratch / "output-1.log").write_text("x\n", encoding="utf-8")

        saved = dict(os.environ)
        try:
            os.environ["TMPDIR"] = str(tmp)
            os.environ.pop("SESSION_DIR", None)
            st = capture_stores(home)
            if not (st["pi-transcripts"]["read"] and len(st["pi-transcripts"]["files"]) == 2):
                fails.append(f"persistent store arm: {st['pi-transcripts']}")
            if not (st["pi-subagents-scratch"]["read"] and len(st["pi-subagents-scratch"]["files"]) == 3):
                fails.append(f"scratch arm (a CAPTURE_PATTERNS entry is unreachable): "
                             f"{st['pi-subagents-scratch']}")
            files = capture_files(home)
            if files != sorted(set(files)) or len(files) != 5:
                fails.append(f"capture_files arm: not sorted+deduped, or the set is wrong ({len(files)})")
            note = stores_note(st)
            if "run-capture stores read:" not in note or "pi-transcripts" not in note:
                fails.append("stores_note arm: the line does not name the stores it read")

            empty = root / "empty-home"
            empty.mkdir()
            st2 = capture_stores(empty)
            if st2["pi-transcripts"]["read"]:
                fails.append("absent-store arm: a HOME with no store reported itself READ")
            if "NOT READ" not in stores_note(st2):
                fails.append("absent-store arm: the note hid an unread store (a clean 0 with no caveat)")

            sd = root / "session-dir"
            sd.mkdir()
            (sd / "events.jsonl").write_text("{}\n", encoding="utf-8")
            os.environ["SESSION_DIR"] = str(sd)
            st3 = capture_stores(home)
            if not (st3.get("session-dir", {}).get("read") and st3["session-dir"]["files"]):
                fails.append("SESSION_DIR arm: a real session dir was not read")
            os.environ["SESSION_DIR"] = str(root / "reaped")
            st4 = capture_stores(home)
            if st4.get("session-dir", {}).get("read"):
                fails.append("SESSION_DIR arm: a reaped directory reported itself READ")
            if "points nowhere" not in st4["session-dir"]["why"]:
                fails.append("SESSION_DIR arm: the boundary line does not say the path is gone")
        finally:
            os.environ.clear()
            os.environ.update(saved)
    for f in fails:
        print(f"FAIL {f}")
    print("capture_stores self-test: " + ("FAIL " + str(len(fails)) + " arm(s)" if fails else
          "GREEN — every store named, READ and absent both proved, all four CAPTURE_PATTERNS reached"))
    return 1 if fails else 0


def main() -> int:
    ap = argparse.ArgumentParser(description="The pi capture-store walk, vault-blind (scripts/lib).")
    ap.add_argument("--list", action="store_true", help="this seat's stores: names, counts, boundaries")
    ap.add_argument("--self-test", action="store_true", help="fixture arms; nothing outside a temp dir")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    stores = capture_stores()
    print(json.dumps({k: {"read": v["read"], "files": len(v["files"]), "why": v["why"]}
                      for k, v in stores.items()}, indent=2))
    print(stores_note(stores))
    return 0


if __name__ == "__main__":
    sys.exit(main())
