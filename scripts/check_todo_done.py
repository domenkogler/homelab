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

It is also the duplicate-ID gate (HD-485): a lane branched from a base that lacked the
earlier push re-derives `max+1`, two rows reach main with one id, and the merge reports no
conflict because the two rows sit in **different module sections** — only an id-aware check
can see it. It also prints the minting evidence (highest id ever used + the next mintable id),
so a session mints from the registry instead of guessing.

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
# Markdown link TARGETS only — `[text](path)` -> `text`. A path is a filename, never a claim.
_LINK_TARGETS_RE = re.compile(r"\]\(([^)]*)\)")
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
# A row id split into its NUMERIC STEM + letter suffix. The duplicate gate keys on the stem, so a
# suffixed row collides with its bare parent and a human decides which of the two is really the
# sub-task. Measured 2026-10-01: the first pair this caught (HD-336 / HD-336b) turned out to be TWO
# independent rows, so the collision itself is the finding, not a false alarm to be suppressed.
_STEM_RE = re.compile(r"^(\d+)([A-Za-z]*)$")

# Ids where a letter-suffixed row is a GENUINE sub-task of the same-numbered parent, so the
# pair is legal. EMPTY, and measured rather than assumed (2026-10-01): `grep -o '^| HD-[0-9]+[A-Z]'
# todo.md` finds no letter-suffixed row except the HD-336b one, so today the gate has no exemption
# to make. Sub-ID notation is common in prose (HD-318a/c/d appear 19 times) but NEVER headed a row
# — `git log -S '| HD-318a' -- todo.md` is empty — so no legal pair has ever been exercised here.
# That is why the self-test breeds one (HD-900 + HD-900z) instead of trusting the registry: an
# exemption path with no live case is exactly the untested branch that rots. Adding a stem here
# REQUIRES its reason in the comment next to it.
#
# ⚠ `HD-900` is TOOL FIXTURE TEXT, never a backlog id, and it must therefore stay listed in
# `RESERVED_IDS` in scripts/next-hd.sh: that script scans the whole tracked tree on purpose, so it
# reads these fixture rows as evidence. Measured 2026-10-06 — it reported max 900 and minted HD-901
# for real work while the registry top was HD-494. This file's own MINT line is immune (it reads
# todo.md rows only), which is why the two tools disagreed and nothing downstream noticed.
SUBTASK_PAIRS: frozenset[str] = frozenset()


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


def _mint_evidence() -> tuple[int, str]:
    """(highest numeric id ever used, next mintable id) — derived from todo.md, never typed.

    CONVENTIONS §4 derived-values ban: a session must mint from evidence, not by guessing
    `max+1`. Gaps are deliberately NOT reported — closed rows are deleted (§4(a)), so the registry
    is mostly holes: measured 2026-10-01, 373 of the 489 ids below the top are absent and every one
    of them is intentional. Printing them would invite a mint into a retired id. `highest` counts
    letter-suffixed rows too, so a lane that minted HD-488z cannot also mint HD-488.
    """
    stems = {int(m.group(1)) for ident, _ in _rows() if (m := _STEM_RE.match(ident))}
    if not stems:
        return 0, "1"
    highest = max(stems)
    return highest, str(highest + 1)


def find_duplicate_ids(subtasks: frozenset[str] = SUBTASK_PAIRS) -> list[tuple[str, list[tuple[int, int, str]]]]:
    """Duplicate numeric row ids: [(stem, [(line_no, col, full_id), ...])], sorted by stem.

    Keyed on the NUMERIC STEM, so a letter-suffixed row collides with its bare parent. That is
    deliberate, not a false positive (HD-336 / HD-336b, found by the first run of this gate):
    a `<n><letter>` id was only ever meant for a genuine sub-task of one parent, and HD-336b
    ("CrewAI pilot") says in its own text that it does not gate HD-336 ("agent memory") —
    independent work wearing a sub-ID's clothes, which is what makes the pair ambiguous at
    renumber time. The second instance of this class (HD-476/HD-477) cost two docs + IaC
    reference sweeps.

    A row that is a REAL sub-task of one parent (one outcome genuinely split in two, the way
    HD-318 was split in prose) is legitimate and is resolved by adding the stem to `SUBTASK_PAIRS`,
    which records WHY the pair is legal — the exemption must be an assertion with a reason, never a
    silent widening of the gate. `grep -o '^| HD-[0-9]*' | sort | uniq -d` cannot make this
    distinction at all (it truncates any `<n>a` to `<n>`), which is why that recipe stays a hint and
    this gate is the verdict.

    `col` is 1-based: a row lives inside a one-line table cell, so the line number alone does
    not locate it once a section holds several rows.
    """
    seen: dict[str, list[tuple[int, int, str]]] = {}
    for lineno, line in enumerate(TODO.read_text(encoding="utf-8").splitlines(), 1):
        if not line.startswith("| HD-"):
            continue
        ident = line.split("|")[1].strip().removeprefix("HD-")
        m = _STEM_RE.match(ident)
        if not m or len(line.split("|")) < 4:
            continue
        seen.setdefault(m.group(1), []).append((lineno, line.index(f"HD-{ident}") + 1, ident))
    dups = [(stem, hits) for stem, hits in sorted(seen.items(), key=lambda kv: int(kv[0]))
            if len(hits) > 1 and stem not in subtasks]
    return dups


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
    # Link TARGETS are stripped first: `docs/network-rejected.md` is a filename, and since the
    # reject test is case-insensitive a pointer to the decision log read as a claim that the row
    # ITSELF was rejected (measured 2026-10-01 on HD-487 — an open row reported as decided). Same
    # class as the marker-grammar rule below: prose that merely CONTAINS a marker is not a claim.
    # Link TEXT is kept, because "**Rejected** — see the log" is a real claim.
    if _REJECT_RE.search(_LINK_TARGETS_RE.sub("", tail)):
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
    dups = find_duplicate_ids()

    bad = False
    if dups:
        bad = True
        print(
            f"FAIL: {len(dups)} HD id(s) head more than one todo.md row — one id, one outcome, "
            "so a duplicate makes a row uncloseable and invisible (HD-485; two live instances "
            "2026-09-30, HD-476 and HD-477):"
        )
        for stem, hits in dups:
            where = ", ".join(f"todo.md:{ln}:{col} = HD-{fid}" for ln, col, fid in hits)
            print(f"  - HD-{stem}: {len(hits)} rows — {where}")
        print(
            "  Rule: match on the row's SUBJECT TEXT, never `^| HD-<n>` (a duplicated row gives "
            "two hits). Re-number the later claimant across EVERY file type, then re-run "
            "`grep -rhoE 'HD-[0-9]{3}'` immediately before committing — the collision window is "
            "minutes, not days. A genuine sub-task row is exempt via SUBTASK_PAIRS (with its "
            "reason written next to the entry); unrelated work must be re-numbered, not suffixed."
        )
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

    highest, nxt = _mint_evidence()
    print(
        f"MINT: highest HD id ever used = {highest}; next mintable id = HD-{nxt} "
        "— mint from this line, not from a guess (CONVENTIONS §4 derived-values ban; gaps below "
        "the top are retired ids, never reuse them)"
    )

    if bad:
        print("\nSee CONVENTIONS.md §4 (post-task housekeeping) + todo.md §0.")
        return 1

    print(
        f"OK: {len(rows)} todo.md rows scanned; no duplicate row ids; {len(open_ids)} open ROWs, "
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
    # A decision-log LINK is not a rejection of the row (HD-487, 2026-10-01). Both halves: the
    # link alone must classify as open work, the same link PLUS a real claim must still nudge.
    if classify("⏳ Implement + converge off-box · [network-rejected.md](docs/network-rejected.md)") != "keep":
        fails.append("a link to *-rejected.md was read as a claim that the row is rejected")
    if classify("✅ decision REJECTED · [network-rejected.md](docs/network-rejected.md)") != "rejected_info":
        fails.append("link-stripping also swallowed a real REJECTED claim next to the link")
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
    # ── Duplicate-ID gate (HD-485). The canary writes into todo.md and restores it from a
    # byte-for-byte snapshot in `finally`: the assertion "the gate sees the duplicate" is only
    # evidence if a crash cannot leave a fabricated row in the backlog.
    import tempfile
    import os

    dup_row = ("| HD-476 | 2 | AI | 1 | canary second claimant — ⏳ a tail so it is not "
               "also flagged fully_done · [x](docs/index.md) |\n")
    sub_row = ("| HD-900z | 2 | AI | 1 | canary sub-ID — ⏳ tail · [x](docs/index.md) |\n")

    def _dup_gate(payload: str, subtasks: frozenset[str] = frozenset()) -> list[str]:
        """Run the gate over an injected registry — for the cases that cannot be bred in the
        real file: an id duplicated ACROSS module sections (the shape that crossed a merge with
        no conflict), and a sub-ID pair that must be exempted only when registered as such."""
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as fh:
            fh.write(f"| HD-900 | 2 | AI | 1 | canary parent — ⏳ tail · [x](docs/index.md) |\n"
                     + payload)
            tmp = Path(fh.name)
        try:
            global TODO
            saved, TODO = TODO, tmp
            try:
                return [stem for stem, _ in find_duplicate_ids(subtasks)]
            finally:
                TODO = saved
        finally:
            os.unlink(tmp)

    try:
        original = TODO.read_bytes()
    except OSError as exc:  # the canary needs the real registry; a missing one is a hard error
        fails.append(f"cannot read todo.md for the duplicate-ID canary: {exc}")
        original = None

    if original is not None:
        try:
            lines = original.decode("utf-8").splitlines(keepends=True)
            # Insert after the LAST row line, so the canary lands in the final module section —
            # a different section from every real HD-476 row, which is the shape that hid it.
            idx = max(i for i, ln in enumerate(lines) if ln.startswith("| HD-")) + 1
            mutated = "".join(lines[:idx]) + dup_row + "".join(lines[idx:])
            if "476" not in _dup_gate(mutated):
                fails.append("duplicate-ID gate missed a second row heading HD-476 "
                             "(the exact failure that reached main twice)")
            # Proof the canary is load-bearing, not decorative: without the injected row the
            # same file must NOT report 476, else the check would pass on any registry.
            if "476" in _dup_gate("".join(lines)):
                fails.append("canary is not discriminating: HD-476 already duplicated in todo.md "
                             "on main — investigate before trusting this self-test")
            # Un-registered sub-ID → flagged. Registered → silent. Both halves, or the
            # exemption is a hole nobody tested.
            if "900" not in _dup_gate(sub_row):
                fails.append("unregistered sub-ID HD-900z under HD-900 was not flagged")
            if "900" in _dup_gate(sub_row, frozenset({"900"})):
                fails.append("SUBTASK_PAIRS exemption does not silence the pair it registers "
                             "— the exemption path is untested and would be a silent hole")
        except Exception as exc:  # never leave the registry mutated, never swallow the reason
            fails.append(f"duplicate-ID canary could not run: {type(exc).__name__}: {exc}")
        finally:
            TODO.write_bytes(original)

    if fails:
        print(f"FAIL: check_todo_done self-test — {len(fails)} case(s):")
        for f in fails:
            print(f"  - {f}")
        return 1
    n = len(_ST_NOT_DONE) + len(_ST_DONE) + len(_ST_REJECT) + len(_ST_NOT_REJECT)
    print(f"OK: check_todo_done self-test passed ({n} marker-grammar cases, 8 row-classification cases)")
    return 0


if __name__ == "__main__":
    if "--self-test" in sys.argv[1:]:
        sys.exit(_self_test())
    sys.exit(main())