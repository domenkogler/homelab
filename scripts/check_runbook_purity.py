#!/usr/bin/env python3
"""Lint: the redeploy runbook stays IMPERATIVE PROCEDURE (CONVENTIONS §"Deployment ledger & journal").

`deployment-manual.md` is the procedure SSOT: commands, panel settings, per-step evidence, and
nothing else. It drifted twice in the same direction — knowledge written inline where a link
belonged, and execution history pasted in as if it were a step. Inline knowledge goes stale the
moment the owning doc changes (the live case: a section teaching a superseded AI-tier decision
as current, and a "seed blocked on a 1Password item that is currently absent" note years after
that item was created).

Checks:
  1. status-glyph   — ✅/⏳/🟢/❌ anywhere, or a heading carrying a status word. A marker in the
                      runbook is a progress claim that nobody un-ticks.
  2. history-prose  — "live lesson", "live fix", "as executed", "this session", "recorded <date>",
                      "close-out", "recap": execution narrative, which belongs in the commit.
  3. date-in-prose  — a `20YY-MM-DD` date outside a code fence and outside a `decision #NN`
                      citation. Dates are evidence; evidence lives in the ledger/owning docs.
  4. dup-heading    — two identical headings (a renumbering accident that hides a section).
  5. phase-alignment— every `## Phase X` in the runbook must exist in the ledger, so "Phase 5"
                      cannot mean the deploy button in one file and a GPU box in the other.

Run:   python3 scripts/check_runbook_purity.py
Exit:  0 = clean, 1 = violations found.  Wired into `validate-all.sh`.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANUAL = ROOT / "deployment-manual.md"
LEDGER = ROOT / "deployment-tasks.md"

STATUS_GLYPHS = "✅⏳🟢❌"  # caution glyphs (⚠) are procedure, not status
HISTORY_RE = re.compile(
    r"\b(live lesson|live fix|live hit|as executed|this session|close-out|live recap|"
    r"first proven|session #\d+)", re.I)
DATE_RE = re.compile(r"20\d\d-\d\d-\d\d")
DECISION_CITE_RE = re.compile(r"decision #\d+", re.I)
STATUS_HEADING_RE = re.compile(r"\b(deploy-gated|as-built|current state|\bstatus\b|\blive\b|\bdone\b|\bpending\b)", re.I)
# Phases the runbook numbers for its own true-zero order but the ledger folds into a step:
# 0.5 = the netcup reinstall, which the ledger carries as the first step of Phase 1.
MANUAL_ONLY_PHASES = {"0.5"}


def in_code_fence(flags: list[bool], idx: int) -> bool:
    return flags[idx]


def main() -> int:
    if not MANUAL.exists():
        print(f"FAIL: {MANUAL.name} not found")
        return 1
    lines = MANUAL.read_text(encoding="utf-8").splitlines()

    # fence map
    fence, open_fence = [], False
    for ln in lines:
        if ln.strip().startswith("```"):
            fence.append(open_fence)          # the fence line itself: previous state
            open_fence = not open_fence
        else:
            fence.append(open_fence)

    problems: list[str] = []
    seen: dict[str, int] = {}

    for i, raw in enumerate(lines, start=1):
        lineno = i
        stripped = raw.strip()
        is_heading = stripped.startswith("#")
        fenced = in_code_fence(fence, i - 1)

        if not fenced:
            glyphs = [g for g in STATUS_GLYPHS if g in raw]
            if glyphs:
                problems.append(f"status-glyph  :{lineno} {''.join(sorted(set(glyphs)))} — "
                                f"progress belongs in the ledger: {stripped[:70]}")
            m = HISTORY_RE.search(raw)
            if m:
                problems.append(f"history-prose   :{lineno} “{m.group(0)}” — the commit records "
                                f"what happened: {stripped[:70]}")
            for dte in DATE_RE.findall(raw):
                if not DECISION_CITE_RE.search(raw):
                    problems.append(f"date-in-prose   :{lineno} {dte} — link the owning doc "
                                    f"instead: {stripped[:70]}")

        if is_heading and not fenced:
            if stripped in seen:
                problems.append(f"dup-heading     :{lineno} repeats line {seen[stripped]}: {stripped[:70]}")
            else:
                seen[stripped] = lineno
            if STATUS_HEADING_RE.search(stripped) and not stripped.startswith("# "):
                problems.append(f"status-glyph    :{lineno} status word in a heading: {stripped[:70]}")

    # phase alignment against the ledger
    manual_phases = set(re.findall(r"^## Phase (\d+(?:\.\d+)?[ab]?)(?=[\s—-])", MANUAL.read_text(encoding="utf-8"), re.M))
    if LEDGER.exists():
        ledger_phases = set(re.findall(r"^## Phase (\d+(?:\.\d+)?[ab]?)(?=[\s—-])", LEDGER.read_text(encoding="utf-8"), re.M))
        orphans = sorted(manual_phases - ledger_phases - MANUAL_ONLY_PHASES)
        for ph in orphans:
            problems.append(f"phase-alignment runbook has “Phase {ph}” with no matching ledger "
                            f"phase — number the two documents the same way")
    else:
        problems.append("phase-alignment deployment-tasks.md not found")

    if problems:
        print(f"FAIL: {len(problems)} runbook-purity problem(s):")
        for p in problems:
            print(f"  - {p}")
        return 1
    print(f"OK: runbook is procedure-only ({len(lines)} lines, "
          f"{len(manual_phases)} phases aligned with the ledger)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
