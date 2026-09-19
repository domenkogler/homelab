#!/usr/bin/env python3
"""Lint: the deployment ledger stays a LEDGER (CONVENTIONS §"Deployment ledger & journal").

`deployment-tasks.md` is what README points every agent at to answer "what is live / what is
next". Three ways it drifts, all of them observed, all of them silent to the other linters:

  1. stale-row        — an OPEN (`- [ ]`) deploy-gated item names an HD whose `todo.md` row no
                        longer exists (done, deleted or renamed). It then reads as open work
                        forever and the ledger stops matching reality. A CLOSED `- [x]` item may
                        still name a gone row — that is the record of a verification that
                        happened, and it is what rule 3 keeps honest.
  2. prose-status     — an HD line inside a deploy-gated block is written as a status sentence
                        (`- **HD-370** — ✅ ALL LEGS LIVE ...`) instead of a checkbox. Status
                        prose is the failure mode this ledger keeps falling into: it is long,
                        undatable, and nobody ever un-ticks it.
  3. undated-tick     — a `- [x]` step or closed HD item with no date. The convention is
                        checkbox + date when done, otherwise "done" has no evidence time attached.

Run:   python3 scripts/check_ledger_state.py
Exit:  0 = clean, 1 = violations found.  Wired into `validate-all.sh`.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEDGER = ROOT / "deployment-tasks.md"
TODO = ROOT / "todo.md"

DATE_RE = re.compile(r"20\d\d-\d\d-\d\d")
HD_REF_RE = re.compile(r"\bHD-\d+\b")
BLOCK_HEAD_RE = re.compile(r"^\*\*Deploy-gated verification")
ITEM_RE = re.compile(r"^- (?:\[([ x])\] )?\*\*(HD-\d+)\*\*")


def open_todo_ids() -> set[str]:
    """Every HD with a row in todo.md. A missing row means the work item is gone."""
    if not TODO.exists():
        raise SystemExit(f"missing {TODO}")
    return set(re.findall(r"^\|\s*(HD-\d+)\s*\|", TODO.read_text(encoding="utf-8"), re.M))


def deploy_gated_blocks(text: str):
    """Yield (block_label, [lines]) for each '**Deploy-gated verification (...):**' block."""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if not BLOCK_HEAD_RE.match(line):
            continue
        label = line.strip().strip("*")
        body = []
        for nxt in lines[i + 1:]:
            if nxt.startswith("---") or nxt.startswith("## "):
                break
            body.append(nxt)
        yield label, body


def main() -> int:
    if not LEDGER.exists():
        print(f"FAIL: {LEDGER.name} not found")
        return 1
    text = LEDGER.read_text(encoding="utf-8")
    have = open_todo_ids()
    problems: list[str] = []

    rows = 0
    for label, body in deploy_gated_blocks(text):
        for raw in body:
            m = ITEM_RE.match(raw)
            if not m:
                continue
            box, hd = m.group(1), m.group(2)
            rows += 1
            if box is None:
                problems.append(
                    f"prose-status  [{label}] {hd}: deploy-gated item has no checkbox — "
                    "use `- [ ] **HD-nnn** — <pending action> · [doc](docs/…)`"
                )
            if box == " " and hd not in have:
                problems.append(
                    f"stale-row     [{label}] {hd}: no row in todo.md — the item is closed, "
                    "deleted or renamed; delete the line (record = owning doc + commit)"
                )
            if box == "x" and not DATE_RE.search(raw):
                problems.append(
                    f"undated-tick  [{label}] closed item {hd} carries no date"
                )

    # undated ticks — only phase STEP lines (`- [x] **Step**`), not the HD rows above
    for raw in text.splitlines():
        if not raw.startswith("- [x] ") or HD_REF_RE.search(raw):
            continue
        if not DATE_RE.search(raw):
            problems.append(f"undated-tick  step lacks a date: {raw[:80]}")

    if problems:
        print(f"FAIL: {len(problems)} ledger-discipline problem(s):")
        for p in problems:
            print(f"  - {p}")
        print(f"\n(scanned {rows} deploy-gated item(s) against {len(have)} todo.md rows)")
        return 1
    print(f"OK: {rows} deploy-gated item(s) all open in todo.md; every tick dated; no status prose in blocks")
    return 0


if __name__ == "__main__":
    sys.exit(main())
