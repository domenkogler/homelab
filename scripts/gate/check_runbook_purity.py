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
                      cannot mean the deploy button in one file and a GPU box in the other. The
                      capture admits a digit, an optional `.N`, and ONE trailing letter `a`-`z`, so
                      every letter-suffixed phase either document can write is compared and counted;
                      PHASE_RE states the one shape still outside it (a TWO-letter suffix, arm (d)).

The phase comparison is the only rule here that reads a SECOND document, so it is the one rule that
can go blind silently: a runbook that numbers more phases than the verdict counts is a runbook this
gate did not read. `--self-test` proves each arm can fail — an orphan phase RED, the `0.5` exemption
GREEN (live, not dead code), a letter suffix past `b` RED on a ledger that omits it and GREEN once the
ledger names it (the arm that keeps the capture honest), and a probe witness that refuses a run whose
walk saw no phase heading or could not open one of the two documents.

Run:   python3 scripts/gate/check_runbook_purity.py              # the tree
       python3 scripts/gate/check_runbook_purity.py --self-test  # the probes, on in-memory fixtures
Exit:  0 = clean · 1 = violations found · 2 = could not run (an input missing, or a walk that saw no
       phase heading the capture admits — an empty verdict is never a pass).
       Wired into `validate-all.sh`, both the run and the self-test.
"""
from __future__ import annotations

import contextlib
import io
import re
import sys
from pathlib import Path

# HD-1118 Stage 1: FOUND, not assumed from a depth — scripts/lib/repo_root.py.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import root as _hl_root  # noqa: E402
ROOT = _hl_root(__file__)
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
# 0.5 = the netcup reinstall, which the ledger carries as the first step of Phase 1. This set holds
# exactly ONE documented exception; a runbook-only phase with any other suffix is an undocumented one.
MANUAL_ONLY_PHASES = {"0.5"}

# The capture admits a digit, an optional `.N` and ONE trailing letter `a`-`z`. ONE regex serves both
# documents, so the runbook half and the ledger half of rule 5 cannot disagree about what a phase
# number is. A phase whose suffix is not exactly one letter (a two-letter suffix, a second `.N`) yields
# no capture at all and is therefore invisible to rule 5 — arm (d) names that residue and arm (c) proves
# no single-letter suffix is invisible: a runbook phase the ledger does not carry goes RED whatever
# letter it carries. Consequence for a writer: a phase the runbook numbers needs its ledger section in
# the same change, and changing this shape changes this comment, the `scripts/README.md` row and
# `docs/deployment.md` §Phase numbering with it — arm (c) reddens when those drift apart.
PHASE_RE = re.compile(r"^## Phase (\d+(?:\.\d+)?[a-z]?)(?=[\s—-])", re.M)
# Shape-agnostic witness, used ONLY by self-test arm (c): every `## Phase <something starting with a
# digit>` heading, whatever its suffix. The DELTA between what PHASE_RE captures and what this counts
# IS the blind spot, so arm (c) cannot pass by both regexes going blind at once.
PHASE_ANY_RE = re.compile(r"^## Phase (\d\S*)(?=[\s—-])", re.M)


def in_code_fence(flags: list[bool], idx: int) -> bool:
    return flags[idx]


def scan(manual_text: str, ledger_text: str) -> tuple[list[str], dict]:
    """(problems, stats) — the verdict half, PURE over two texts so --self-test can drive it with a
    fixture pair instead of the two real documents. A missing file is not this function's business:
    it is refused before the verdict by refusal_for_missing(), so `ledger_text` is always text here
    and the comparison never silently degrades to a one-document walk.
    """
    lines = manual_text.splitlines()

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
    manual_phases = set(PHASE_RE.findall(manual_text))
    ledger_phases = set(PHASE_RE.findall(ledger_text))
    orphans = sorted(manual_phases - ledger_phases - MANUAL_ONLY_PHASES)
    for ph in orphans:
        problems.append(f"phase-alignment runbook has “Phase {ph}” with no matching ledger "
                        f"phase — number the two documents the same way")

    stats = {"lines": len(lines), "manual_phases": manual_phases, "ledger_phases": ledger_phases}
    return problems, stats


def refusal_for_missing(paths=(MANUAL, LEDGER)):
    """None when both comparison inputs are there, else the sentence the run prints.

    Split from the print so --self-test reads the SAME sentence the run prints — a witness nobody can
    call is a witness nobody proves (CONVENTIONS §6, "a gate that cannot see the file cannot fail
    either"). A run that opened one of the two documents has no comparison to report, so it refuses
    rather than printing an `OK` for a phase set it never compared anything against.
    """
    gone = [p.name for p in paths if not p.is_file()]
    if not gone:
        return None
    # The f-string ENDS at "not found" and the sentence continues after a `+`, not beside it:
    # ` not found` is a cross-file twin (check_string_twins.py — the tail these checkers print when
    # an input is absent) and implicit concatenation would fold it into the next literal, severing
    # that twin for a wording change. The `+` keeps the twin's bytes where the baseline had them.
    return (f"CANNOT RUN: {' and '.join(gone)} not found" +
            " — this gate compares the runbook with the ledger, and with one of them absent every "
            "phase would be aligned with nothing. A missing input is not a clean tree "
            "(CONVENTIONS §6).")


def refusal_for_phases(manual_phases: set[str], ledger_phases: set[str]):
    """None when the walk actually saw phase headings, else the refusal sentence (probe witness).

    Without this, a broken root, a moved file or a heading shape outside PHASE_RE yields an EMPTY
    phase set, and rule 5's only direction is "runbook minus ledger" — so nothing is an orphan, the
    run prints `OK: … 0 phases aligned with the ledger`, and the gate is green having read nothing.
    """
    if not manual_phases:
        return ("CANNOT RUN: the runbook yielded no `## Phase …` heading that the capture admits, so "
                "there was nothing to align. Either the walk is blind (wrong repo root, moved file) "
                "or every phase heading is outside the admitted shape — a digit, an optional `.N`, "
                "then at most ONE letter. An empty phase set is not a pass (CONVENTIONS §6).")
    if not ledger_phases:
        return ("CANNOT RUN: the ledger yielded no `## Phase …` heading that the capture admits, so "
                "every runbook phase would be reported as an orphan by accident rather than by rule. "
                "That is a broken walk, not nine violations.")
    return None


def report(manual_text: str, ledger_text: str) -> int:
    """The verdict half — separate from main() so --self-test can drive it with a fixture pair."""
    problems, stats = scan(manual_text, ledger_text)
    refusal = refusal_for_phases(stats["manual_phases"], stats["ledger_phases"])
    if refusal:
        print(refusal)
        return 2
    if problems:
        print(f"FAIL: {len(problems)} runbook-purity problem(s):")
        for p in problems:
            print(f"  - {p}")
        return 1
    print(f"OK: runbook is procedure-only ({stats['lines']} lines, "
          f"{len(stats['manual_phases'])} phases aligned with the ledger)")
    return 0


# The fixtures are IN MEMORY, not files under scripts/testdata/: a fixture tree would owe a row to
# the layout gate (check_script_layout.py, registry ≡ tree) for text no run reads, and this checker
# needs two strings rather than a directory. Same choice check_doc_domain.py makes, for the half of
# its corpus that is a canary rather than the tracked tree.
BASE_PHASES = ("0", "1", "1a", "1.5", "2", "3", "4", "4b")


def fixture_manual(phases=BASE_PHASES, extra_headings=()) -> str:
    """A legal runbook: one phase heading and one imperative line each, nothing rules 1-4 can bite."""
    out = ["# Fixture runbook", ""]
    for head in [f"## Phase {ph} — Track {ph}" for ph in phases] + list(extra_headings):
        out += [head, "", "Run `ansible-playbook site.yml`, then read its output.", ""]
    return "\n".join(out)


def fixture_ledger(phases=BASE_PHASES) -> str:
    """The ledger the fixture runbook is aligned with — checkboxes, because that is the ledger's form."""
    out = ["# Fixture ledger", ""]
    for ph in phases:
        out += [f"## Phase {ph} — Track {ph}", "", "- [ ] do the thing", ""]
    return "\n".join(out)


def self_test() -> int:
    """Every arm seen RED, the same fixtures seen GREEN, and the suffix capture proved to reach past `b`.

    Arms are strings in memory: breed one heading, require the finding, put it back, require silence.
    Arm (c) is the canary for the capture itself — a letter suffix this gate could not see would make
    rule 5 a rule about only the phases the regex happens to match, so it is seen RED and GREEN rather
    than described.
    """
    ok = True
    base_manual, base_ledger = fixture_manual(), fixture_ledger()

    def findings_of(manual, ledger):
        return scan(manual, ledger)[0]

    def shown(findings):
        return "; ".join(findings) if findings else "0 findings"

    def green(label, manual, ledger):
        """The control half: the same fixtures with the canary gone must yield NOTHING."""
        nonlocal ok
        got = findings_of(manual, ledger)
        if got:
            print(f"  FAIL  {label}: expected 0 findings, got {shown(got)}")
            ok = False
        else:
            print(f"  GREEN {label}: 0 findings")

    def orphan(label, manual, ledger):
        """The RED half for rule 5: the phase-alignment finding, or a failed arm."""
        nonlocal ok
        caught = [f for f in findings_of(manual, ledger) if "phase-alignment" in f]
        if caught:
            print(f"  RED   {label}: {caught[0]}")
            return
        print(f"  FAIL  {label}: bred an unaligned phase and rule 5 stayed silent — "
              f"{shown(findings_of(manual, ledger))}")
        ok = False

    green("control: aligned fixtures, no canary", base_manual, base_ledger)

    # (a) An orphan phase: a `## Phase 6` the ledger does not carry. This is the rule working.
    orphan("(a) orphan phase: `## Phase 6` with no ledger counterpart",
           fixture_manual(extra_headings=("## Phase 6 — Observability hardening",)), base_ledger)
    green("(a) the same fixtures with that heading removed", base_manual, base_ledger)

    # (b) The exemption must be LIVE, not dead code: `0.5` is the ONE documented runbook-only phase,
    # so a heading the ledger does not carry is still green — and the SAME shape with a suffix the
    # set does not hold has to redden, or the arm proves nothing.
    manual_05 = fixture_manual(extra_headings=("## Phase 0.5 — VPS (re-)provisioning (netcup SCP)",))
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = report(manual_05, base_ledger)   # base_ledger carries no 0.5 heading: the ledger folds it in
    if rc == 0 and "OK:" in buf.getvalue():
        print(f"  GREEN (b) a runbook-only phase listed in MANUAL_ONLY_PHASES stays exempt — "
              f"{buf.getvalue().strip()}")
    else:
        print(f"  FAIL  (b) the `0.5` exemption is not live: rc {rc} — {buf.getvalue().strip()}")
        ok = False
    orphan("(b) the same shape OUTSIDE the exemption set (`## Phase 6.5`)",
           fixture_manual(extra_headings=("## Phase 6.5 — A phase nothing exempts",)), base_ledger)

    # (c) The suffix capture is the load-bearing half of rule 5, so it is canaried rather than
    # described. `4d` is the shape that used to be invisible — the capture stopped at `b`. With
    # `a`-`z` admitted, a runbook numbering a `Phase 4d` the ledger omits MUST redden rule 5, and the
    # SAME fixtures with a ledger that names that phase MUST be silent, or the arm proves nothing
    # either way. Reverting the widening reddens it twice over: the orphan half finds no finding at
    # all, and the witness delta below goes nonzero (a heading numbered but never captured).
    manual_4d = fixture_manual(extra_headings=("## Phase 4d — A suffix the capture must admit",))
    orphan("(c) `## Phase 4d` with no ledger counterpart — every letter suffix is compared",
           manual_4d, base_ledger)
    green("(c) the same runbook with a ledger that names Phase 4d",
          manual_4d, fixture_ledger(tuple(BASE_PHASES) + ("4d",)))
    # The witness half: PHASE_ANY_RE counts every `## Phase <digit…>` heading whatever its shape, so a
    # nonzero delta IS a phase rule 5 never sees. Both regexes going blind at once cannot pass here.
    captured = set(PHASE_RE.findall(manual_4d))
    numbered = set(PHASE_ANY_RE.findall(manual_4d))
    if numbered - captured:
        print(f"  FAIL  (c) the capture went blind: {sorted(numbered - captured)} numbered but NOT "
              f"captured — the suffix set and this arm disagree, and the record (this checker's "
              "comment, the scripts/README.md row, docs/deployment.md) has to be re-argued.")
        ok = False
    else:
        print(f"  GREEN (c) the capture admits every single-letter suffix: {len(captured)} of "
              f"{len(numbered)} phases this fixture numbers reach rule 5")

    # (d) The probe witness: a walk that saw no phase heading, or a missing input, must REFUSE. Both
    # halves of the phase witness, plus the case that matters here — both documents headed only with a
    # phase OUTSIDE the admitted shape, which is the blind spot turning into a false `OK: 0 phases`.
    # The residue is a TWO-letter suffix: one letter is admitted since the capture widened to `a-z`,
    # so this arm names the only phase shape rule 5 still cannot see.
    for label, manual, ledger in (
            ("(d) a runbook with no phase heading at all", "", base_ledger),
            ("(d) a ledger with no phase heading at all", base_manual, ""),
            ("(d) both sides headed only with `Phase 4ca`, outside the admitted shape",
             fixture_manual(phases=("4ca",)), fixture_ledger(("4ca",)))):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = report(manual, ledger)
        out = buf.getvalue()
        if rc == 2 and "CANNOT RUN" in out and "OK:" not in out:
            print(f"  RED   {label} is refused with rc 2 — {out.strip().splitlines()[0][:110]}")
        else:
            print(f"  FAIL  {label} returned rc {rc} instead of refusing: {out.strip()[:160]}")
            ok = False

    # (d), other half: a comparison input that is not there. Called through the SAME witness the run
    # uses, and the real tree must pass it — otherwise this leg only proves a string is non-empty.
    absent = refusal_for_missing([MANUAL, ROOT / "deployment-tasks.md.self-test-absent"])
    present = refusal_for_missing()
    if absent and absent.startswith("CANNOT RUN") and present is None:
        print(f"  RED   (d) a missing input is refused with rc 2 — {absent.splitlines()[0][:110]}")
    else:
        print(f"  FAIL  (d) the missing-input witness is not load-bearing: absent={absent!r} "
              f"present={present!r}")
        ok = False
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = report(base_manual, base_ledger)
    if rc == 0 and "OK:" in buf.getvalue():
        print(f"  GREEN (d) the witness passes a healthy fixture — {buf.getvalue().strip()}")
    else:
        print(f"  FAIL  (d) the control fixture did not reach the OK line: rc {rc} — "
              f"{buf.getvalue().strip()}")
        ok = False

    print("self-test: " + ("all arms caught, control clean" if ok else "NOT PROVEN"))
    return 0 if ok else 1


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()
    refusal = refusal_for_missing()
    if refusal:
        print(refusal)
        return 2
    return report(MANUAL.read_text(encoding="utf-8"), LEDGER.read_text(encoding="utf-8"))


if __name__ == "__main__":
    sys.exit(main())
