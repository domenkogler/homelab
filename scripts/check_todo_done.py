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

prompt.md handoff check (same run):
  * prompt_done — an HD presented as OPEN/actionable work in prompt.md
    (⏳/Remaining/Deploy-gated/next/verify) whose todo.md row is GONE
    (done/deleted) → stale open-work claim in the handoff (exit 1).
  * prompt_contradiction — an HD claimed WHOLE-row DONE in prompt.md (no open
    context) but still OPEN in todo.md → handoff/backlog mismatch (exit 1).
  * prompt_info — §2 SESSION entries that are pure history (all-done, no open
    ⏳) → compressible to the owning docs (INFO only).
  * Sub-IDs (HD-318a) inherit their parent row's open-ness; phase-done prose
    ("IaC done … ⏳ deploy") on an open row is NOT a contradiction.

Marker grammar (provable: `python3 scripts/check_todo_done.py --self-test`): a completion
marker is a ✅/✔ glyph or an UPPERCASE marker word at a word boundary. Lowercase prose is
never a marker, so "the live headscale config" does not claim the row is finished.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TODO = ROOT / "todo.md"
PROMPT = ROOT / "prompt.md"

# Completion markers for the row's own outcome (row-level state, not a tail item).
#
# ⚠ Matched CASE-SENSITIVELY and at WORD BOUNDARIES, because every one of these words is
# also ordinary English. The match used to be a case-INSENSITIVE substring test, which made
# prose into completion claims: "the live headscale config", "deliver the record", "olive
# oil", "unresolved drift" and "closed the loop" all matched, and since the prompt-side
# window is only -60/+90 characters around an HD id, an innocent word a few lines away from
# the id was enough to fail the gate with "prompt.md marks it done but the todo.md row is
# open" — for a reason that looked completely unrelated to the sentence anyone wrote.
# Status markers in this repo are written UPPERCASE or as a glyph (`ALL LEGS LIVE`, `DONE`,
# `✅`); lowercase prose is prose, not a marker.
#
# Direction of the tradeoff, deliberately: tightening can only turn a FALSE ALARM into a
# keep. A row that is genuinely finished and carries no marker at all is still caught by
# CONVENTIONS §4's own delete step + the audit sweep, never silently blessed.
_GLYPHS = "✅✔"
# Row-level vocabulary — exactly the words this checker matched before, unchanged.
_ROW_MARKERS = (
    "DONE", "LIVE", "COMPLETE", "CLOSED",
    "RESOLVED", "VERIFIED", "REJECTED", "SUPERSEDED",
)
# Prompt-level vocabulary — again exactly the previous set. REJECTED/SUPERSEDED are
# deliberately NOT here: "⛔ Ladder #10 (LMCache KV offload) is REJECTED" next to an HD id
# says nothing about whether that HD's row is finished, and folding them in made HD-376
# read as done (measured). Neither is COMPLETE, which the prompt side never matched.
_PROMPT_DONE_MARKERS = ("DONE", "LIVE", "CLOSED", "RESOLVED", "DELETED", "VERIFIED")
_ROW_MARKER_RE = re.compile(f"[{_GLYPHS}]|\\b(?:{'|'.join(_ROW_MARKERS)})\\b")
_DONE_MARKER_RE = re.compile(f"[{_GLYPHS}]|\\b(?:{'|'.join(_PROMPT_DONE_MARKERS)})\\b")
# REJECTED/SUPERSEDED drive a different question — "does this row belong in the owning
# <domain>-rejected.md decision log instead of the backlog?" — and that is an INFO nudge,
# not a completion claim. Here prose IS the signal, and the repo writes it that way
# ("**Superseded note (2026-09-03):** …", "superseded by decisions #24/#25"), so this one
# stays case-INSENSITIVE. Word boundaries still apply, so "unsuperseded" cannot match.
_REJECT_RE = re.compile(r"\b(?:REJECTED|SUPERSEDED)\b", re.IGNORECASE)
# If any of these appear in the text AFTER the final completion marker, the row
# has remaining open work → keep (never a fully-done violation).
_REMAIN = re.compile(
    r"(Remaining|Pending|verify|deploy-gat|live[- ]?verify|needs|apply|then |next |"
    r"owner |todo|step|run |after |once |until |check |confirm|before )",
    re.IGNORECASE,
)

# Contexts in prompt.md that mark an HD as OPEN/ACTIONABLE work (a stale claim if
# the row is actually done/deleted).
_PROMPT_OPEN = re.compile(
    r"(⏳|Remaining|Pending|Deploy-gated|next session|next |verify|live-verify|deploy-gat|"
    r"owner:|owner step|owner verify|before |needs|apply|TODO|open)",
    re.IGNORECASE,
)
# Every HD reference in prompt.md (whole-word).
_HD_RE = re.compile(r"HD-(\d+[A-Za-z]?)")


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
    """Start index of the last completion marker, or -1. Grammar: _DONE_MARKER_RE."""
    last = -1
    for m in _ROW_MARKER_RE.finditer(text):
        last = m.start()
    return last


def classify(body: str) -> str:
    """'keep' | 'fully_done' | 'rejected_info'."""
    last = _last_marker(body)
    if last < 0:
        return "keep"  # no completion marker → open backlog

    tail = body[last:]

    # Reject/supersede rows: never a violation, always INFO-only.
    if _REJECT_RE.search(tail):
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


def _open_todo_ids() -> set[str]:
    """IDs of HD rows still open in todo.md (present as a row at all)."""
    return {ident for ident, _ in _rows()}


def _prompt_hds(text: str) -> dict[str, list[str]]:
    """Map HD id -> [context snippets] where it appears in prompt.md."""
    hds: dict[str, list[str]] = {}
    for m in _HD_RE.finditer(text):
        ident = m.group(1)
        start = max(0, m.start() - 60)
        end = min(len(text), m.end() + 90)
        ctx = text[start:end].replace("\n", " ")
        hds.setdefault(ident, []).append(ctx)
    return hds


def _ctx_is_open(ctx: str) -> bool:
    """Does this context present the HD as open/actionable work?"""
    return bool(_PROMPT_OPEN.search(ctx))


def _ctx_is_done(ctx: str) -> bool:
    """Does this context present the HD as done?

    Case-sensitive and boundary-anchored on purpose — see _DONE_MARKER_RE. Prose that
    merely contains a marker word ('deliver', 'olive', 'unresolved') is not a claim.
    """
    return bool(_DONE_MARKER_RE.search(ctx))


def scan_prompt(open_ids: set[str]) -> tuple[list[str], list[str], list[str]]:
    """Return (prompt_done, prompt_contradiction, prompt_info).

    prompt_done          — HD presented as OPEN work in prompt.md but its todo.md
                            row is GONE (done/deleted) → stale open-work claim.
    prompt_contradiction — HD presented as DONE in prompt.md but still OPEN in
                            todo.md → handoff claims done, backlog keeps it open.
    prompt_info          — SESSION entries that are pure history (all-done, no ⏳):
                            compressible, informational only.
    """
    if not PROMPT.exists():
        return [], [], []
    text = PROMPT.read_text(encoding="utf-8")
    hds = _prompt_hds(text)

    prompt_done: list[str] = []
    prompt_contradiction: list[str] = []

    for ident, ctxs in sorted(hds.items()):
        any_open = any(_ctx_is_open(c) for c in ctxs)
        any_done = any(_ctx_is_done(c) for c in ctxs)
        # Sub-IDs (HD-318a / HD-318b) are part of their parent row (HD-318);
        # they are never "deleted/done" on their own while the parent is open.
        base = ident[:-1] if ident[-1:].isalpha() else ident
        is_open_row = (ident in open_ids) or (base in open_ids)

        if not is_open_row:
            # todo.md row deleted (= done) but prompt presents it as open work.
            if any_open:
                prompt_done.append(ident)
        else:
            # todo.md keeps it (or its parent) open. Only a *whole-row-done* claim with
            # NO open context is a contradiction; phase-done prose ("IaC done … ⏳ deploy")
            # alongside an open ⏳ is normal and NOT flagged.
            if any_done and not any_open:
                prompt_contradiction.append(ident)

    # INFO: whole §2 SESSION entries that are pure history (done, no open ⏳).
    info: list[str] = []
    for m in re.finditer(r"- \*\*SESSION[^*]*\*\*", text):
        ent = m.group(0)
        if "⏳" in ent or _PROMPT_OPEN.search(ent):
            continue
        info.append(ent[:70])

    return prompt_done, prompt_contradiction, info


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

    open_ids = _open_todo_ids()
    prompt_done, prompt_contra, prompt_info = scan_prompt(open_ids)

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

    if prompt_done:
        bad = True
        print(
            f"FAIL: {len(prompt_done)} HD(s) presented as OPEN work in prompt.md but their todo.md "
            "row is GONE (done/deleted) — stale open-work claim in the handoff:"
        )
        for i in prompt_done:
            print(f"  - HD-{i}: prompt.md lists it as pending/remaining but todo.md row is deleted (done)")

    if prompt_contra:
        bad = True
        print(
            f"FAIL: {len(prompt_contra)} HD(s) presented as DONE in prompt.md but still OPEN in "
            "todo.md — handoff claims done, backlog keeps it open:"
        )
        for i in prompt_contra:
            print(f"  - HD-{i}: prompt.md marks it done but todo.md row still exists (open)")

    if prompt_info:
        print(
            f"INFO: {len(prompt_info)} §2 SESSION entr(ies) in prompt.md are pure history "
            "(all-done, no open ⏳) — compressible to the owning docs:"
        )
        for e in prompt_info:
            print(f"  - {e}")

    if bad:
        print("\nSee CONVENTIONS.md §4 (post-task housekeeping) + todo.md §0.")
        return 1

    print(
        f"OK: {len(rows)} todo.md rows scanned; {len(open_ids)} open ROWs, "
        f"{len({_HD_RE.search(l).group(1) for l in PROMPT.read_text(encoding='utf-8').splitlines() if _HD_RE.search(l)})} HDs in prompt.md; "
        "no fully-done rows / stale prompt claims (CONVENTIONS §4)"
    )
    return 0


# ── Self-test: the marker grammar, independent of todo.md / prompt.md content ───────
# The negative set is the class that bit a runner writing a §2 handoff: sentences whose
# only crime is containing a substring of a marker word.
_ST_NOT_DONE = (
    "the live headscale config all along",
    "deliver the record to the seed",
    "alive on the netmap",
    "olive oil",
    "unresolved drift in the table",
    "closed the loop on the alias",
    "complete the login on LTE",
    "an undeleted item, kept",
    "delivery of the key",
    "resolve later, not now",
)
_ST_DONE = (
    "✅ ALL LEGS LIVE",
    "row DONE, nothing left",
    "✔ shipped",
    "decision CLOSED",
    "question RESOLVED",
    "surface DELETED",
    "path VERIFIED",
    "rollout COMPLETE",
)
_ST_REJECT = ("decision REJECTED", "row SUPERSEDED by HD-1")
_ST_NOT_REJECT = ("this is unresolved, not a rejection", "supersede logic in lowercase")


def _self_test() -> int:
    fails: list[str] = []
    for s in _ST_NOT_DONE:
        m = _DONE_MARKER_RE.search(s)
        if m:
            fails.append(f"prose read as a completion claim: {s!r} matched {m.group(0)!r}")
    for s in _ST_DONE:
        if not (_DONE_MARKER_RE.search(s) or _ROW_MARKER_RE.search(s)):
            fails.append(f"real marker NOT detected: {s!r}")
    for s in _ST_REJECT:
        if not _REJECT_RE.search(s):
            fails.append(f"reject/supersede marker NOT detected: {s!r}")
    for s in _ST_NOT_REJECT:
        if _REJECT_RE.search(s):
            fails.append(f"prose read as reject/supersede: {s!r}")
    # The decision-log nudge deliberately reads prose case-insensitively:
    for s in ("**Superseded note (2026-09-03):** the path moved", "superseded by decisions #24/#25"):
        if not _REJECT_RE.search(s):
            fails.append(f"decision-log prose no longer nudges: {s!r}")
    # Row-level vs prompt-level vocabularies differ on purpose (measured, not taste):
    # a rejected ladder inside a row's text is not a claim that the row is finished.
    _rej = "⛔ **Ladder #10 (LMCache KV offload) is REJECTED**"
    if _DONE_MARKER_RE.search(_rej):
        fails.append(f"prompt detector treats REJECTED as a completion claim: {_rej!r}")
    if classify(_rej + " — rest of the row") != "rejected_info":
        fails.append("row classifier no longer reports rejected_info for a REJECTED row")
    # Row classification: marker + no tail = fully_done (must be deleted); an explicit ⏳
    # or stated remaining work keeps the row; no marker = open backlog.
    for body, want in (
        ("✅ all legs LIVE", "fully_done"),
        ("✅ IaC merged ⏳ deploy on oldsrv", "keep"),
        ("✅ shipped. Remaining: the LAN alias delete", "keep"),
        ("open work, no marker here", "keep"),
        ("the live headscale config, nothing else", "keep"),
        ("REJECTED by decision #26", "rejected_info"),
    ):
        got = classify(body)
        if got != want:
            fails.append(f"classify({body!r}) = {got}, expected {want}")
    if fails:
        print(f"FAIL: check_todo_done self-test — {len(fails)} case(s):")
        for f in fails:
            print(f"  - {f}")
        return 1
    n = len(_ST_NOT_DONE) + len(_ST_DONE) + len(_ST_REJECT) + len(_ST_NOT_REJECT)
    print(f"OK: check_todo_done self-test passed ({n} marker-grammar cases, 6 row-classification cases)")
    return 0


if __name__ == "__main__":
    if "--self-test" in sys.argv[1:]:
        sys.exit(_self_test())
    sys.exit(main())