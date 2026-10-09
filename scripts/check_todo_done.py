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

Reference-existence pass — `python3 scripts/check_todo_done.py --refs`, its own validate-all.sh item:
  * every `HD-<digits>` token named in ANY root `prompt*.md` brief must exist as a row in
    todo.md (`^| HD-<id> `), else FAIL naming `file:line` (exit 1).

  WHY: CONVENTIONS §4 says an `HD` id is not stable prose — a closed row is DELETED (§4(a)) and a
  renumbered row moves — so a brief that names one keeps a pointer to nothing. Nothing complained:
  the first run of this pass found the pointers only in HISTORICAL mentions of rows that closed,
  which is exactly the text no STATUS claim reads, so the whole existing prompt.md half of this
  checker was blind to it. Fixing a finding means re-pointing the fact at whatever carries it now
  (the owning doc, the decision log, the commit) — never minting an id, never re-opening a row,
  never a skip list (a skip list is the same rot with a maintenance cost).

  ⚠ THE ASYMMETRY IS THE POINT, keep it: a STATUS claim stays `prompt.md`-only (§2/§4 ARE the
  handoff), a REFERENCE is checked across every root brief (a dead id misleads whoever reads it).
  Do not widen the claim half to the domain briefs and do not narrow this half back to prompt.md.

  Scope: ROOT `prompt*.md`, non-recursive — a `prompt.md` under `brainstorming/obsolete/` is a
  frozen artifact, not a handoff. A token is the full `HD-<id>` form; a letter-suffixed id is
  satisfied by its PARENT row (the same inheritance `scan_prompt` applies). An abbreviated cluster
  (`HD-361 · 411 · 442`) therefore checks its HEAD only: a bare number is prose, not an id — the
  naming rule is to repeat the prefix when a row is named.

Run:   python3 scripts/check_todo_done.py            (row sweep + prompt.md claims)
       python3 scripts/check_todo_done.py --refs     (reference existence over the briefs)
       python3 scripts/check_todo_done.py --self-test
Exit:  0 = clean, 1 = violations found. Wired into `scripts/validate-all.sh`.
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
# Case-sensitivity alone was not enough (HD-466): at §2/§4/§5 entry lengths a ±60/+90 window reaches
# into the NEIGHBOURING entry, so a right marker got charged to the wrong id — or, with an ⏳ sitting in
# the next row, the wrong verdict in the other direction. See `_prompt_claim_spans`: the window is now
# bounded by the entry and by any sibling id inside it. The radius is unchanged on purpose.
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


def _rows(todo: Path = TODO) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    for line in todo.read_text(encoding="utf-8").splitlines():
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


def _open_todo_ids(todo: Path = TODO) -> set[str]:
    """IDs of HD rows still open in todo.md (present as a row at all)."""
    return {ident for ident, _ in _rows(todo)}


# ── Where a claim belongs: structure, not proximity (HD-466) ──────────────────────────
# `_prompt_hds` used to hand every id occurrence a fixed ±60/+90 character window and nothing else.
# prompt.md §2/§4/§5 entries run 200–400 characters per bullet, so a window around one id reaches
# into the neighbouring entry and credits ITS marker to this one — the verdict then names an id that
# was never said to be done. Claim ownership is a property of the ENTRY, so the text is split into
# entries first, and each occurrence gets the region around it clipped to its own entry and to the
# midpoint of any sibling id inside that entry. Inside one entry nothing changes (same radius, same
# catch); across entries, misattribution becomes impossible by construction rather than by tuning.
_UNIT_HEAD_RE = re.compile(r"^\s*(?:[-*+]\s|\d+[.)]\s+|#{1,6}\s|\|)")
_CTX_BEFORE = 60   # the radius is not the bug — the missing bounds were
_CTX_AFTER = 90


def _split_prompt_units(text: str) -> list[tuple[int, int]]:
    """(start, end) of every ENTRY in prompt.md: a bullet / numbered item / heading / table row,
    plus the wrapped continuation lines under it. A blank line closes an entry, and so does the
    next head — which is what makes a §2 bullet and a §4 table row the same kind of unit here."""
    units: list[tuple[int, int]] = []
    start: int | None = None
    pos = 0
    for line in text.splitlines(keepends=True):
        if not line.strip():
            if start is not None:
                units.append((start, pos))
                start = None
            pos += len(line)
            continue
        if _UNIT_HEAD_RE.match(line):
            if start is not None:
                units.append((start, pos))
            start = pos
        elif start is None:
            start = pos          # a plain prose paragraph line starts a unit of its own
        pos += len(line)
    if start is not None:
        units.append((start, pos))
    return units


def _prompt_claim_spans(text: str) -> dict[str, list[tuple[int, int]]]:
    """id -> regions of `text` in which prompt.md makes a status claim about that id."""
    spans: dict[str, list[tuple[int, int]]] = {}
    for lo, hi in _split_prompt_units(text):
        occ = [(m.start(), m.end(), m.group(1)) for m in _HD_RE.finditer(text[lo:hi])]
        for i, (s, e, ident) in enumerate(occ):
            prev_end = occ[i - 1][1] if i else None
            next_start = occ[i + 1][0] if i + 1 < len(occ) else None
            a = s - _CTX_BEFORE if prev_end is None else max(s - _CTX_BEFORE, (prev_end + s) // 2)
            b = e + _CTX_AFTER if next_start is None else min(e + _CTX_AFTER, (e + next_start) // 2)
            spans.setdefault(ident, []).append((lo + max(a, 0), lo + min(b, hi - lo)))
    return spans


def _prompt_hds(text: str) -> dict[str, list[str]]:
    """Map HD id -> the context snippets in which prompt.md makes a claim about it.

    The snippets are the OWNED regions from `_prompt_claim_spans`, not a raw ±window: same radius,
    but bounded by the entry and by any sibling id inside it, so a marker can only ever be charged to
    the id the sentence is about (HD-466).
    """
    return {
        ident: [text[a:b].replace("\n", " ") for a, b in spans]
        for ident, spans in _prompt_claim_spans(text).items()
    }


def _ctx_is_open(ctx: str) -> bool:
    """Does this context present the HD as open/actionable work?"""
    return bool(_PROMPT_OPEN.search(ctx))


def _ctx_is_done(ctx: str) -> bool:
    """Does this context present the HD as done?

    Case-sensitive and boundary-anchored on purpose — see _DONE_MARKER_RE. Prose that
    merely contains a marker word ('deliver', 'olive', 'unresolved') is not a claim.
    """
    return bool(_DONE_MARKER_RE.search(ctx))


def scan_prompt(open_ids: set[str], text: str | None = None) -> tuple[list[str], list[str], list[str]]:
    """Return (prompt_done, prompt_contradiction, prompt_info).

    prompt_done          — HD presented as OPEN work in prompt.md but its todo.md
                            row is GONE (done/deleted) → stale open-work claim.
    prompt_contradiction — HD presented as DONE in prompt.md but still OPEN in
                            todo.md → handoff claims done, backlog keeps it open.
    prompt_info          — SESSION entries that are pure history (all-done, no ⏳):
                            compressible, informational only.

    `text` is injectable for the self-test; production callers pass nothing and get prompt.md.
    """
    if text is None:
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


# ── Reference existence: a brief may only name a row that exists (CONVENTIONS §4) ────────
# The pointer half of the same problem the row sweep solves. §4(a) DELETES a closed row, and §4
# (Backlog) says an HD id is not stable prose — so every brief that named that row now points at
# nothing. Rows are re-derived at each doc's own commit precisely because a copied list decays into
# a false pointer, and until this pass nothing checked it.
_BRIEF_GLOB = "prompt*.md"


def _brief_paths(root: Path = ROOT) -> list[Path]:
    """Every ROOT-level prompt brief, sorted: `prompt.md` + one `prompt-<domain>.md` per domain.

    Non-recursive on purpose — a `prompt.md` left under `brainstorming/obsolete/` is a frozen
    artifact of an old plan, not a handoff, and sweeping it would fail on prose nobody maintains.
    """
    return sorted(root.glob(_BRIEF_GLOB))


def _hd_refs(text: str) -> list[tuple[int, str]]:
    """[(1-based line, id)] for every `HD-<id>` token in a brief, in document order.

    Scanned line by line rather than with one regex over the file, because the finding has to name
    `file:line` — the unit a human edits. No subprocess per file: this runs inside a concurrent gate
    whose whole budget is seconds, and a dozen briefs cost milliseconds.
    """
    return [(i, m.group(1))
            for i, line in enumerate(text.splitlines(), 1)
            for m in _HD_RE.finditer(line)]


def scan_brief_refs(todo: Path = TODO,
                    root: Path = ROOT) -> tuple[list[tuple[str, int, str]], int, int]:
    """(dangling refs `[(file, line, id)]`, tokens examined, briefs examined).

    A reference dangles when todo.md carries no `^| HD-<id>` row for the token. A letter-suffixed
    id (HD-318a) is satisfied by its PARENT row, which is the same inheritance `scan_prompt` applies
    to status claims: a sub-ID is part of its parent's row, it never has a row of its own. An
    orphan sub-ID whose parent is gone is still a dead pointer and still fails.
    """
    ids = _open_todo_ids(todo)
    briefs = _brief_paths(root)
    dangling: list[tuple[str, int, str]] = []
    refs = 0
    for path in briefs:
        for line_no, ident in _hd_refs(path.read_text(encoding="utf-8")):
            refs += 1
            if ident in ids:
                continue
            base = ident[:-1] if ident[-1:].isalpha() else ident
            if base in ids:
                continue
            ref = (path.name, line_no, ident)
            if ref not in dangling:      # one line naming the same dead id twice is one finding
                dangling.append(ref)
    return dangling, refs, len(briefs)


def run_refs() -> int:
    """The `--refs` verdict: reference existence only, no status claims."""
    if not TODO.exists():
        print(f"FAIL: {TODO} not found", file=sys.stderr)
        return 1
    dangling, refs, briefs = scan_brief_refs()
    if dangling:
        print(
            f"FAIL: {len(dangling)} HD reference(s) in the root prompt briefs name a todo.md row "
            "that does not exist — a false pointer (§4: a closed row is deleted, a colliding id is "
            "renumbered, so a brief must re-derive its ids):"
        )
        for name, line_no, ident in sorted(dangling):
            print(f"  - {name}:{line_no}: HD-{ident} → no `| HD-{ident}` row in todo.md")
        print(
            "  Fix: keep the FACT and drop the dead id — point at what carries it now (the owning "
            "doc, the <domain>-rejected.md log, the commit) or rephrase to the invariant. Never mint "
            "an id to satisfy this gate, never re-open a closed row, and never add a skip list: the "
            "skip list is the same rot with a maintenance cost."
        )
        print(f"\n({refs} HD references examined over {briefs} root prompt briefs)")
        return 1
    print(
        f"OK: {refs} HD references over {briefs} root prompt briefs all resolve to a todo.md row "
        "(CONVENTIONS §4 — a closed row is deleted, so a brief must re-derive its ids)"
    )
    return 0


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
    # The canaries need a scratch tree: the marker/claim cases are pure strings, the reference and
    # duplicate-ID cases write fixtures. `tempfile`/`os` are imported ONCE here, for both canaries.
    import tempfile
    import os

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
    # Row classification: marker + no tail = fully_done; an explicit ⏳ or stated remaining work
    # keeps the row; no marker = open backlog. NAMED, because the OK line counts it — a typed case
    # count in a self-test rots the same way a typed count anywhere else does (CONVENTIONS §2).
    _ST_CLASSIFY = (
        ("✅ all legs LIVE", "fully_done"),
        ("✅ IaC merged ⏳ deploy on oldsrv", "keep"),
        ("✅ shipped. Remaining: the LAN alias delete", "keep"),
        ("open work, no marker here", "keep"),
        ("the live headscale config, nothing else", "keep"),
        ("REJECTED by decision #26", "rejected_info"),
    )
    for body, want in _ST_CLASSIFY:
        got = classify(body)
        if got != want:
            fails.append(f"classify({body!r}) = {got}, expected {want}")
    # ── Claim attribution (HD-466): a marker counts for the id whose ENTRY it sits in ──
    # Synthetic prompts, because the shape that broke is a two-bullet §2 handoff and cannot be bred
    # in the real prompt.md on demand. Both directions are asserted: the neighbour's marker must NOT
    # be charged (the bug), and the entry's OWN marker must still be (the catch). Both outcomes were
    # measured against the unbounded ±60/+90 window before committing: cases 1 and 3 flagged the WRONG
    # id there, case 4 flagged NOTHING at all (a false negative), case 6 invented a stale-open claim.
    _ST_ATTR = (
        ("- **SESSION 1**: HD-1 tailnet alias work\n"
         "- **SESSION 2**: HD-2 ✅ LIVE, merged and converged\n",
         {"1", "2"}, ([], ["2"]),
         "a done marker in the NEXT bullet charged to HD-1 (the ±window had no entry bound)"),
        ("- **SESSION 1**: HD-1 tailnet alias work\n"
         "  ✅ LIVE on both legs, merged and converged\n",
         {"1"}, ([], ["1"]),
         "a marker in the entry's OWN wrapped continuation must still count — the catch, not just the bound"),
        ("- HD-1 tailnet alias work; HD-2 ✅ LIVE, merged and converged\n",
         {"1", "2"}, ([], ["2"]),
         "two ids in one sentence: the marker belongs to the nearer id, not to both"),
        ("| HD-1 | 2 | AI | 2 | ⏳ the Pi leg, next session |\n"
         "| HD-2 | 2 | AI | 2 | ✅ LIVE, merged and converged |\n",
         {"1", "2"}, ([], ["2"]),
         "an ⏳ in the neighbouring ROW swallowed HD-2's real contradiction (false negative)"),
        ("- **SESSION 9**: ✅ LIVE, HD-9 shipped the alias fleet-wide\n",
         {"9"}, ([], ["9"]),
         "a marker BEFORE the id in the same entry counts"),
        ("- **SESSION 3**: HD-1 the Pi leg, ⏳ next session\n"
         "- **SESSION 4**: HD-2 ✅ LIVE, merged and converged\n",
         {"1"}, ([], []),
         "HD-2's row is gone and presented as DONE — nothing stale there; HD-1's ⏳ must not leak into it"),
    )
    for _text, _open, _want, _why in _ST_ATTR:
        _got = tuple(scan_prompt(_open, _text)[:2])
        if _got != _want:
            fails.append(f"claim attribution wrong ({_why}): got {_got}, expected {_want}")
        # The structural half, so the verdicts above cannot be an accident of tuning: a claim region may
        # never cross its entry. Re-widening the window without the bound trips THIS, not just case 1.
        _units = _split_prompt_units(_text)
        for _ident, _spans in _prompt_claim_spans(_text).items():
            for _a, _b in _spans:
                if not any(lo <= _a and _b <= hi for lo, hi in _units):
                    fails.append(f"HD-{_ident}'s claim region crosses its entry boundary ({_why})")

        # ── Reference existence (`--refs`): a brief may only name a row that exists ────────────
    # Both directions, on a throwaway tree, because the shape to catch is a brief naming a CLOSED
    # row and that cannot be bred in the real registry without deleting a live row. `HD-900` is the
    # reserved FIXTURE id (see the note on SUBTASK_PAIRS / RESERVED_IDS in scripts/next-hd.sh); the
    # GREEN half names `HD-{_live}` derived from the real todo.md by `_mint_evidence()`, so the green
    # case points at a live row rather than at a second fixture (CONVENTIONS §4: never type an id).
    import tempfile
    import os

    _live = str(_mint_evidence()[0])
    _ref_registry = f"| HD-{_live} | 2 | AI | 1 | synthetic registry — ⏳ tail · [x](docs/index.md) |\n"
    _REF_BRIEF = "prompt-900.md"      # any name matching prompt*.md; the name is not the point

    def _ref_gate(briefs: dict[str, str], registry: str = _ref_registry,
                  others: dict[str, str] | None = None) -> list[tuple[str, int, str]]:
        """Run the reference pass over a throwaway tree: a synthetic todo.md plus the named files.
        Paths are INJECTED (no global swapping), so a crash cannot leave a fixture in the registry."""
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            (tmp / "todo.md").write_text(registry, encoding="utf-8")
            for files in (briefs, others or {}):
                for name, body in files.items():
                    p = tmp / name
                    p.parent.mkdir(parents=True, exist_ok=True)
                    p.write_text(body, encoding="utf-8")
            return scan_brief_refs(tmp / "todo.md", tmp)[0]

    # The red this exists for, and the green that proves it is not always-red.
    _dead = _ref_gate({_REF_BRIEF: f"- **HD-900** names a row this registry does not have\n"})
    if _dead != [(_REF_BRIEF, 1, "900")]:
        fails.append(f"the reference pass did not breed the red it exists for: {_dead}")
    _green = _ref_gate({_REF_BRIEF: f"- **HD-{_live}** names a row this registry HAS\n"})
    if _green:
        fails.append(f"the reference pass calls an existing row a dangling ref: {_green}")
    # A sub-ID inherits its parent row — both halves, or the inheritance is an untested branch.
    if _ref_gate({_REF_BRIEF: f"- **HD-{_live}z** is a sub-task of the row above\n"}):
        fails.append("a sub-ID under an existing parent row was called dangling")
    if [i for _, _, i in _ref_gate({_REF_BRIEF: "- **HD-900z** has no parent row either\n"})] != ["900z"]:
        fails.append("an orphan sub-ID with no parent row was not called dangling")
    # Scope is the ROOT briefs and nothing else: an archived brief in a subfolder and a file that is
    # not a brief must both be left alone, or the gate sweeps frozen prose it cannot be true about.
    if _ref_gate({_REF_BRIEF: ""},
                 others={"archive/prompt-901.md": "- **HD-900** archived prose, out of scope\n",
                         "notes.md": "- **HD-900** not a brief\n"}):
        fails.append("the reference pass swept something that is not a root prompt*.md brief")
    # The real tree, as the discriminator the duplicate-ID canary has: the fixture green must not be
    # the only thing proving the pass can be green over REAL briefs, and if a real brief dangles the
    # `--refs` item is red too, so both say so at the same moment.
    _real_dangling, _real_refs, _real_briefs = scan_brief_refs()
    if _real_dangling:
        fails.append("a real root brief names a row todo.md does not have (the --refs item fails too): "
                     + ", ".join(f"{n}:{l}=HD-{i}" for n, l, i in sorted(_real_dangling)))
    if _real_briefs < 2:
        fails.append(f"the reference pass found only {_real_briefs} brief(s) at the repo root — "
                     f"the `{_BRIEF_GLOB}` glob is not matching the briefs")

# ── Duplicate-ID gate (HD-485). The canary writes into todo.md and restores it from a
    # byte-for-byte snapshot in `finally`: the assertion "the gate sees the duplicate" is only
    # evidence if a crash cannot leave a fabricated row in the backlog.
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
    print(
        f"OK: check_todo_done self-test passed ({n} marker-grammar cases, "
        f"{len(_ST_CLASSIFY)} row-classification cases, "
        f"{len(_ST_ATTR)} claim-attribution cases, and the reference pass bred its red and its green "
        f"— {_real_refs} HD references over {_real_briefs} real briefs all resolve)"
    )
    return 0


if __name__ == "__main__":
    if "--self-test" in sys.argv[1:]:
        sys.exit(_self_test())
    if "--refs" in sys.argv[1:]:
        sys.exit(run_refs())
    sys.exit(main())