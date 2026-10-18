#!/usr/bin/env python3
"""Lint: the subagent contract is one fact in four places, and it stays that way.

WHY THIS EXISTS. The child-lane contract (delegation is the default, at most two live children,
the parent's model only, a two-hour deadline, and a minutes-long compaction pause that is NOT a
hang) is the kind of rule that reads as settled prose in one document and as a different number in
three others. Each half already disagreed with the others by accident: the reviewer guidance said
"~10 min then steer or abort" while the engine's own concurrency arithmetic (`max_num_seqs` minus
the parent minus the always-on consumers) says two children at a time, and the harness's 30-minute
run backstop silently cut short the very deadline the guidance was about to promise. Prose alone
cannot hold four files to one value, and CONVENTIONS §6 refuses a test that cannot fail -- so each
rule here has a canary in `--self-test` that breeds the failure it claims to catch.

RULES
  R-1  settings SSOT carries the model scope. `pi-agent/settings-ssot.json` must declare
       `subagents.modelScope` = {enforce: true, strict: true, allow: ["inherit"]}. That key is
       MERGED into every seat's settings.json by scripts/harness/pi-settings-config.sh, so "a child
       runs the session model" is a launch-time refusal, not a convention. A seat-local
       `subagents.*` key is replaced by that merge -- the plane names it as drift before it writes.
  R-2  the child-runtime knobs are written down once. `_subagentConfig` (the UNDERSCORE prefix is
       what keeps the plane from merging it -- it is the payload for the extension's own
       ~/.pi/agent/extensions/subagent/config.json, which no seat plane installs yet) must carry
       timeoutMs = 7200000 (2 h), globalConcurrencyLimit = 2, maxActiveAsyncRunsPerSession = 2,
       asyncByDefault = true, and a checkpointBeforeDeadlineMs that is positive and leaves room.
  R-3  the docs state the same contract. docs/orchestration.md names O10 and O11 and the child-lane
       section, CONVENTIONS.md states the child count, README.md points at O10-O11 rather than
       inventing its own numbers.
  R-4  the retired rule stays retired. The abort-on-silence phrase (`~10 min`) may not come back to
       README.md or docs/orchestration.md: a locally-served child compacts for minutes, so "quiet"
       is a normal state and a timer on it manufactures a stall nobody had.
  R-5  the inherit-only premise holds. scripts/harness/pi/models-spec.yml declares no `spark-*`
       provider alias (a lane/DR profile with the same endpoint and a different harness-side
       window). §4's inherit rule rests on there being exactly one serving provider in the rendered
       file; landing the lane alias is a legitimate move, but then this gate and both docs change in
       the SAME commit, because the scope allows `inherit` and would silently reject the alias.

BOUNDARIES, stated so a green line means what it says: the gate reads tracked files at the checked
out commit and nothing live -- it proves the repo's promise, never a seat's effective settings
(that is `scripts/harness/pi-settings-config.sh --check`, a different instrument on a different
object). It reads YAML with a line walk, not a parser, because only provider `id:` lines matter
here and pulling PyYAML into a gate would make the suite depend on the venv for one regex.

Run:   python3 scripts/gate/check_subagent_contract.py [--show] [--self-test]
Exit:  0 = contract holds, 1 = a rule broke.  Wired into `validate-all.sh`.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import require_corpus, root as _hl_root  # noqa: E402

ROOT = _hl_root(__file__)

SSOT = ROOT / "pi-agent" / "settings-ssot.json"
ORCH = ROOT / "docs" / "orchestration.md"
CONV = ROOT / "CONVENTIONS.md"
README = ROOT / "README.md"
SPEC = ROOT / "scripts" / "harness" / "pi" / "models-spec.yml"

# R-1: the exact scope that makes "inherit the parent model" a refusal and not a wish.
SCOPE = {"enforce": True, "strict": True, "allow": ["inherit"]}

# R-2: the child-runtime knobs, keyed as the extension's own config file keys them.
CONCURRENCY = 2
TIMEOUT_MS = 7_200_000          # 2 h -- a bounded task at ~11 tok/s outlives the 30-min backstop
CHECKPOINT_MS = 600_000         # ask it to checkpoint 10 min before the deadline kills it

# R-3/R-4: the strings that make the contract findable, and the phrase that must stay gone.
ORCH_MUST = ("O10", "O11", "Child lanes inside one session", "≤2 children live at a time")
CONV_MUST = ("≤2 children run concurrently",)
README_MUST = ("O10", "O11")
# R-4: the retired abort-on-silence timer, in its literal spelling and in any re-phrasing that keeps
# a minute-scale clock next to a verdict verb. A doc may NAME the retired rule (this file does) as long
# as it does not re-derive a number for it.
BANNED = ("~10 min",)
TIMER_RE = re.compile(r"\b\d+\s*min\b", re.I)
VERDICT_RE = re.compile(r"\b(steer|abort|wrap up)\b", re.I)

# R-5: a provider alias of the serving endpoint would let a child escape the shared-window premise.
ALIAS_RE = re.compile(r"^\s*-\s+id:\s*(spark-[A-Za-z0-9_-]+)\s*$")

TRACKED = (SSOT, ORCH, CONV, README, SPEC)


def check_scope(raw: str) -> list[str]:
    """R-1 on parsed JSON text -- a missing or softened scope is a finding, never a shrug."""
    try:
        doc = json.loads(raw)
    except json.JSONDecodeError as exc:
        return [f"R-1  settings SSOT is not parseable JSON: {exc}"]
    scope = (doc.get("subagents") or {}).get("modelScope")
    if scope is None:
        return ["R-1  `subagents.modelScope` is absent -- a child may point at any model the seat "
                "renders, and the inherit rule is prose only"]
    bad = [f"R-1  subagents.modelScope.{k} = {scope.get(k)!r}, expected {v!r}"
           for k, v in SCOPE.items() if scope.get(k) != v]
    return bad


def check_runtime(raw: str) -> list[str]:
    """R-2 on the same text: the `_`-prefixed payload the settings plane will NOT merge."""
    try:
        doc = json.loads(raw)
    except json.JSONDecodeError as exc:
        return [f"R-2  settings SSOT is not parseable JSON: {exc}"]
    cfg = doc.get("_subagentConfig")
    if cfg is None:
        return ["R-2  `_subagentConfig` is absent -- the 2 h deadline and the two-child ceiling "
                "live in no machine-readable place"]
    bad = []
    for key, want in (("timeoutMs", TIMEOUT_MS),
                      ("globalConcurrencyLimit", CONCURRENCY),
                      ("maxActiveAsyncRunsPerSession", CONCURRENCY),
                      ("asyncByDefault", True)):
        if cfg.get(key) != want:
            bad.append(f"R-2  _subagentConfig.{key} = {cfg.get(key)!r}, expected {want!r}")
    cp = cfg.get("checkpointBeforeDeadlineMs")
    if not isinstance(cp, int) or cp <= 0:
        bad.append(f"R-2  _subagentConfig.checkpointBeforeDeadlineMs = {cp!r}, expected a positive ms value")
    elif isinstance(cfg.get("timeoutMs"), int) and cp >= cfg["timeoutMs"]:
        bad.append("R-2  checkpointBeforeDeadlineMs must leave run time after the checkpoint "
                   "(a checkpoint one second before the kill is no checkpoint)")
    return bad


def check_arm() -> list[str]:
    """R-3: the payload has a seat arm. The child-runtime numbers are only effective when a
    seat-planes record's owner writes them into ~/.pi/agent/extensions/subagent/config.json;
    R-2 proves they are WRITTEN DOWN, not that a seat is converged to them. This reads tracked
    files only (the registry + the arm script), so it proves an arm exists and nothing more —
    the read that stops a seat going green with the payload missing is the arm's own --check on
    that seat's HOME, which is exactly what did not exist before this arm."""
    bad: list[str] = []
    try:
        registry = (
            ROOT / "scripts" / "lib" / "seat-planes.yml"
        ).read_text(encoding="utf-8")
    except FileNotFoundError:
        return ["R-3  cannot read scripts/lib/seat-planes.yml -- the registry is missing"]
    # a record names `owner:` under scripts/**; the arm is that owner
    arm_path = None
    for rec in re.split(r"\n---\n", registry):
        if not re.search(r"^plane:\s*subagent\s*$", rec, re.M):
            continue
        m = re.search(r"^owner:\s*(.+?)\s*$", rec, re.M)
        if m:
            arm_path = ROOT / "scripts" / "harness" / m.group(1).strip()
        break
    if arm_path is None or not arm_path.is_file():
        return ["R-3  no seat-planes record for plane `subagent` names an owner under scripts/**"]
    arm = arm_path.read_text(encoding="utf-8")
    # The arm renders the WHOLE `_subagentConfig` block; a payload key can then never be
    # dropped silently (a key the arm omits would leave a seat on the harness default while
    # the SSOT claims the number). So the checks are: it reads the SSOT's `_subagentConfig`,
    # and its default target is the extension file (not some other path).
    if "_subagentConfig" not in arm:
        bad.append(f"R-3  {arm_path.name} does not render _subagentConfig from the SSOT")
    if "extensions/subagent/config.json" not in arm:
        bad.append(f"R-3  {arm_path.name} does not write ~/.pi/agent/extensions/subagent/config.json")
    return bad


def check_docs(name: str, text: str, must: tuple[str, ...]) -> list[str]:
    """R-3: the contract is stated where a session reads it, in the same words the gate can find."""
    return [f"R-3  {name} no longer states the child-lane contract: {frag!r} is gone"
            for frag in must if frag not in text]


def check_banned(name: str, text: str) -> list[str]:
    """R-4: the abort-on-silence timer stays retired, in literal and re-spelled form."""
    hits = [f"R-4  {name} reintroduced the retired silence timer {frag!r} -- a compaction pause is "
            "not a hang; see docs/orchestration.md O11" for frag in BANNED if frag in text]
    for line in text.splitlines():
        if TIMER_RE.search(line) and VERDICT_RE.search(line) and "retired" not in line.lower():
            hits.append(f"R-4  {name} pairs a minute-scale clock with a verdict verb "
                        f"({line.strip()[:80]!r}) -- a locally-served child is quiet for minutes at a "
                        "time while it compacts; see docs/orchestration.md O11")
    return hits


def check_alias(text: str) -> list[str]:
    """R-5: no provider alias of the serving endpoint, because the scope allows `inherit` only."""
    hits = sorted({m.group(1) for line in text.splitlines() if (m := ALIAS_RE.match(line))})
    if not hits:
        return []
    return [f"R-5  models-spec declares a serving-endpoint alias {hits} while the scope allows "
            "`inherit`: land the alias, widen `allow`, and restate docs/orchestration.md O11 in the "
            "same commit"]


def evaluate(ssot: str, orch: str, conv: str, readme: str, spec: str) -> tuple[list[str], list[str]]:
    problems: list[str] = []
    ok: list[str] = []
    problems += check_scope(ssot)
    problems += check_runtime(ssot)
    for name, text, must in (("docs/orchestration.md", orch, ORCH_MUST),
                             ("CONVENTIONS.md", conv, CONV_MUST),
                             ("README.md", readme, README_MUST)):
        problems += check_docs(name, text, must)
    for name, text in (("README.md", readme), ("docs/orchestration.md", orch)):
        problems += check_banned(name, text)
    problems += check_alias(spec)
    if not problems:
        ok = [f"R-1 model scope {SCOPE} is repo-owned and merged by the settings plane",
              f"R-2 child runtime: timeout {TIMEOUT_MS // 3_600_000} h, "
              f"≤{CONCURRENCY} concurrent, checkpoint {CHECKPOINT_MS // 60_000} min before the deadline",
              "R-3 orchestration + CONVENTIONS + README state one contract (O10-O11)",
              "R-4 no abort-on-silence timer in README or the contract",
              "R-5 the model spec carries no serving-endpoint alias (inherit-only holds)"]
    return problems, ok


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()
    missing = [str(p.relative_to(ROOT)) for p in TRACKED if not p.is_file()]
    if missing:
        print(f"FAIL: {len(missing)} contract file(s) missing -- a moved path is not a clean tree:")
        for m in missing:
            print(f"  - {m}")
        return 1
    require_corpus(len(TRACKED), 4, "check_subagent_contract tracked files")
    texts = [p.read_text(encoding="utf-8") for p in TRACKED]
    problems, ok = evaluate(*texts)
    if problems:
        print(f"FAIL: {len(problems)} subagent-contract problem(s):")
        for p in problems:
            print(f"  - {p}")
        print("\nContract: docs/orchestration.md §4 (O10-O11) + docs/harness-pi.md §6. The values live "
              "in pi-agent/settings-ssot.json; the docs cite it, they do not restate numbers.")
        return 1
    for line in ok:
        print(f"OK: {line}")
    if "--show" in argv:
        print(f"   (read {len(TRACKED)} files, {sum(len(t) for t in texts)} bytes of contract text)")
    return 0


def self_test() -> int:
    """Each rule seen to fail on a canary, and the clean corpus seen to pass it.

    The final line prints the ARM COUNT, because the row and the registry refuse to type one: a
    self-test that reports how many rules it bred is the only honest answer to "does this gate
    still have teeth" (CONVENTIONS §4 derived-values ban).
    """
    fails = 0
    arms = 0

    def case(label: str, got: list[str], want: str) -> None:
        nonlocal fails, arms
        arms += 1
        if any(want in p for p in got):
            print(f"  ok   {label}")
            return
        fails += 1
        print(f"  FAIL {label}: expected a finding matching {want!r}, got {got}")

    def case_quiet(label: str, got: list[str]) -> None:
        nonlocal fails, arms
        arms += 1
        if not got:
            print(f"  ok   {label}")
            return
        fails += 1
        print(f"  FAIL {label}: expected silence, got {got}")

    good = json.dumps({"subagents": {"modelScope": dict(SCOPE)},
                       "_subagentConfig": {"timeoutMs": TIMEOUT_MS, "globalConcurrencyLimit": CONCURRENCY,
                                           "maxActiveAsyncRunsPerSession": CONCURRENCY,
                                           "asyncByDefault": True,
                                           "checkpointBeforeDeadlineMs": CHECKPOINT_MS}})
    arms += 1
    if check_scope(good) or check_runtime(good):
        fails += 1
        print(f"  FAIL (a) clean settings SSOT must pass both halves, got {check_scope(good) + check_runtime(good)}")
    else:
        print("  ok   (a) clean settings SSOT passes")

    case("(b) model scope removed", check_scope("{}"), "absent")
    case("(c) strict dropped (would warn instead of refuse)",
         check_scope(json.dumps({"subagents": {"modelScope": {"enforce": True, "allow": ["inherit"]}}})),
         "strict")
    case("(d) scope widened to a named model",
         check_scope(json.dumps({"subagents": {"modelScope": {**SCOPE, "allow": ["inherit", "entrim/x"]}}})),
         "allow")
    case("(e) unparseable SSOT fails loud, never OK", check_scope("{oops"), "not parseable")
    case("(f) 30-minute backstop regrows",
         check_runtime(json.dumps({"_subagentConfig": {"timeoutMs": 1_800_000,
                                                        "globalConcurrencyLimit": CONCURRENCY,
                                                        "maxActiveAsyncRunsPerSession": CONCURRENCY,
                                                        "asyncByDefault": True,
                                                        "checkpointBeforeDeadlineMs": CHECKPOINT_MS}})),
         "timeoutMs")
    case("(g) three concurrent children",
         check_runtime(json.dumps({"_subagentConfig": {"timeoutMs": TIMEOUT_MS,
                                                        "globalConcurrencyLimit": 3,
                                                        "maxActiveAsyncRunsPerSession": CONCURRENCY,
                                                        "asyncByDefault": True,
                                                        "checkpointBeforeDeadlineMs": CHECKPOINT_MS}})),
         "globalConcurrencyLimit")
    case("(h) checkpoint later than the deadline is refused",
         check_runtime(json.dumps({"_subagentConfig": {"timeoutMs": TIMEOUT_MS,
                                                        "globalConcurrencyLimit": CONCURRENCY,
                                                        "maxActiveAsyncRunsPerSession": CONCURRENCY,
                                                        "asyncByDefault": True,
                                                        "checkpointBeforeDeadlineMs": TIMEOUT_MS}})),
         "leave run time")
    case("(i) the silence timer comes back to README", check_banned("README.md", "steer at ~10 min"), "~10 min")
    case("(i2) the timer re-spelled without the tilde", check_banned("README.md",
         "if a child exceeds 12 min with no verdict, abort it"), "minute-scale clock")
    case("(j) a child-lane rule vanishes from the contract doc",
         check_docs("docs/orchestration.md", "## 4. Orchestrator mode", "≤2 children live at a time"),
         "no longer states")
    case("(k) a serving-endpoint alias lands without the docs",
         check_alias("providers:\n  - id: spark-lane\n    baseUrl: https://llm.kogler.si/v1\n"),
         "alias")
    case_quiet("(l) the ordinary provider pair stays quiet",
               check_alias("providers:\n  - id: entrim\n  - id: spark\n"))

    case_quiet("(i3) an unrelated minute-scale duration stays quiet",
               check_banned("README.md", "a full converge takes 10–30 min and must run detached"))

    case_quiet("(n) the real registry arm resolves and emits every payload key", check_arm())
    # (o) the arm resolves to a DIFFERENT file: the registry owner text is the trigger, so a
    #     canary that names a file that also exists would pass; name a nonexistent owner so the
    #     record itself is what must break.
    import tempfile
    _td = tempfile.mkdtemp()
    _orig = (ROOT / "scripts" / "lib" / "seat-planes.yml").read_bytes()
    # the whole block round-trips BYTES (binary): Path.write_text on Windows defaults to CRLF
    # text mode, which re-CRLFs the registry on every self-test run (the CRLF round-trip that
    # reddened the pi-seat/lib self-tests inside the gate). read_bytes/write_bytes is the
    # byte-truthful half and matches the file's LF discipline (.gitattributes eol=lf).
    try:
        (ROOT / "scripts" / "lib" / "seat-planes.yml").write_bytes(
            _orig.replace(b"owner: pi-subagent-config.sh", b"owner: no-such-owner.sh"))
        case("(o) a broken subagent arm reddens", check_arm(), "no seat-planes record")
    finally:
        (ROOT / "scripts" / "lib" / "seat-planes.yml").write_bytes(_orig)


    # the whole-suite shape: a mutation of the real corpus must produce a finding
    real = [p.read_text(encoding="utf-8") for p in TRACKED]
    base_problems, _ = evaluate(*real)
    if base_problems:
        print(f"  note current tree reports {len(base_problems)} finding(s) -- run without --self-test for the verdict")
    mutated = list(real)
    mutated[0] = json.dumps({"defaultProvider": "spark"})
    m_problems, _ = evaluate(*mutated)
    arms += 1
    if not m_problems:
        fails += 1
        print("  FAIL (m) an SSOT stripped of both blocks produced no finding -- the gate cannot fail")
    else:
        print(f"  ok   (m) SSOT stripped of both blocks reddens ({len(m_problems)} finding(s))")

    print(f"SELF-TEST {'FAIL' if fails else 'OK'}: {arms} arms, {fails} failure(s)")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
