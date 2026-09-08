#!/usr/bin/env python3
"""Lint: flag todo.md rows that are DONE but were not removed (CONVENTIONS §4).

The post-task housekeeping rule (CONVENTIONS.md §4 / todo.md §0): a **fully
done** row — one whose ✅/✔/DONE/LIVE state carries **no remaining open work** —
must be **deleted** from todo.md in the closing change (the record lives in the
owning docs/*.md + git history). Only a row that is IaC-done-but-**deploy-gated**
stays, and it must carry a `⏳` tail trimmed to the pending steps.

This linter catches the recurring drift where a session marks a row ✅ but forgets
the §4(a) delete step, leaving a *done* row in the backlog (2026-09-08 sweep:
HD-198 was exactly this — done + no tail, only removed by manual audit).

What is flagged (exit 1):
  * fully_done — a row whose body carries a completion marker (✅, ✔, DONE,
    LIVE, COMPLETE, CLOSED, RESOLVED, VERIFIED) for the row's own outcome, and
    the text AFTER that final marker is **only whitespace / trailing doc-links /
    a trailing `·` cluster / an audit ref**. No `⏳` anywhere, no "Remaining:",
    no verify/deploy-gate prose. That is a §4(a) violation: the row should have
    been deleted (or its remaining work stated as a `⏳` tail). A row is NOT
    flagged if:
      - it contains a `⏳` (anywhere — a title ⏳ like "⏳ residual audit" is real
        open work, so it's deploy-gated/backlog, keep),
      - the text after the last completion marker contains remaining-work prose
        ("Remaining", "verify", "deploy-gat", "pending", "live-verify", "needs",
        "apply", etc.) — deploy-gated, keep.

False-positive guards:
  * "REJECTED"/"SUPERSEDED" rows are reported as **INFO only** (they belong in a
    `<domain>-rejected.md` decision log, not the backlog) — never exit 1.
  * Historical ⏳ markers embedded in a completed sentence (e.g. "the old ⏳
    stalled path") are ignored as long as a real tail/prose follows.

Run:   python3 scripts/check_todo_done.py
Exit:  0 = clean, 1 = violations found. Wired into `scripts/validate-all.sh`.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TODO = ROOT / "todo.md"

# Completion markers for the row's own outcome (row-level state, not a tail item).
_COMPLETION = (
    "✅", "✔", "DONE", "LIVE", "COMPLETE", "CLOSED",
    "RESOLVED", "VERIFIED", "REJECTED", "SUPERSEDED",
)
# If any of these appear in the text AFTER the final completion marker, the row
# has remaining open work → keep (never a fully-done violation).
_REMAIN = re.compile(
    r"(Remaining|Pending|verify|deploy-gat|live[- ]?verify|needs|apply|then |next |"
    r"owner |todo|step|run |after |once |until |check |confirm|before )",
    re.IGNORECASE,
)


def _rows() -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    for line in TODO.read_text(encoding="utf-8").splitlines():
        if not line.startswith("| HD-"):
            continue
        parts = line.split("|")
        if len(parts) < 4:
            continue
        ident = parts[1].strip()
        if not re.fullmatch(r"HD-\d+[A-Za-z]?", ident):   # HD-123 / HD-123A
            continue
        out.append((ident.removeprefix("HD-"), line))
    return out


def _last_marker(text: str) -> int:
    last = -1
    for tok in _COMPLETION:
        i = text.find(tok)
        while i != -1:
            last = max(last, i)
            i = text.find(tok, i + 1)
    return last


def classify(body: str) -> str:
    """'keep' | 'fully_done' | 'rejected_info'."""
    last = _last_marker(body)
    if last < 0:
        return "keep"  # no completion marker → open backlog

    tail = body[last:]

    # Reject/supersede rows: never a violation, always INFO-only.
    if re.search(r"(REJECTED|SUPERSEDED)", tail, re.I):
        return "rejected_info"

    # Any ⏳ anywhere → deploy-gated / backlog, keep (a title ⏳ is real open work).
    if "⏳" in tail or "⏳" in body:
        return "keep"

    # Strip trailing doc-link cluster / `·` / audit ref, then check for open-work prose.
    stripped = re.sub(
        r"(?:\s*(?:·|,)\s*\[[^\]]*\]\([^)]*\)\s*)+$", "", tail
    )
    stripped = stripped.replace("·", " ").strip()
    # trailing "· [audit] B2/W7 …" style refs
    stripped = re.sub(r"\s*·\s*\[[^\]]*\]\([^)]*\)\s*$", "", stripped)
    stripped = re.sub(r"Closes?\s+audit[\w\s/]*$", "", stripped, flags=re.I).strip()

    if not stripped:
        return "fully_done"  # completion marker, nothing after → forgot to delete
    if _REMAIN.search(stripped):
        return "keep"  # real remaining work stated in prose → deploy-gated
    # Remaining prose doesn't look like open work → treat as fully done (borderline,
    # conservative: only prose that reads like remaining work keeps it).
    return "fully_done"


def main() -> int:
    if not TODO.exists():
        print(f"FAIL: {TODO} not found", file=sys.stderr)
        return 1

    rows = _rows()
    fully_done: list[str] = []
    rejected: list[str] = []

    for ident, body in rows:
        kind = classify(body)
        if kind == "fully_done":
            fully_done.append(ident)
        elif kind == "rejected_info":
            rejected.append(ident)

    bad = False
    if fully_done:
        bad = True
        print(
            f"FAIL: {len(fully_done)} done row(s) still in todo.md "
            "(CONVENTIONS §4(a) — a fully-done row must be DELETED; record in owning docs):"
        )
        for i in fully_done:
            print(f"  - HD-{i}: completion marker with nothing after → delete the row (or add a ⏳ tail)")

    if rejected:
        print(
            f"INFO: {len(rejected)} decided/rejected/superseded row(s) still in todo.md — "
            "the owning <domain>-rejected.md decision log is the owner, not the backlog:"
        )
        for i in rejected:
            print(f"  - HD-{i}: rejected/superseded; consider moving to the decision log")
    if bad:
        print("\nSee CONVENTIONS.md §4 (post-task housekeeping) + todo.md §0.")
        return 1

    print(f"OK: {len(rows)} todo.md rows scanned; no fully-done rows left (all done rows deleted per §4(a))")
    return 0


if __name__ == "__main__":
    sys.exit(main())