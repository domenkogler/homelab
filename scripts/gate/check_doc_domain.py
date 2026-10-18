#!/usr/bin/env python3
"""check_doc_domain.py — every tracked doc claims a domain, and every domain has ONE home (HD-1119b).

WHY THIS EXISTS. `domain:` frontmatter is the placement axis of CONVENTIONS §8 — the field a session
reads to decide where a new doc goes and where a `-review`/`-rejected` pair dispatches from — and
until now nothing in the gate read it. Two shapes slip through silently: a doc whose `domain:` is a
value only it carries, and a domain whose docs disagree about which one of them is the entry point.
Neither is visible from `docs/index.md`, because the doc map (check_doc_map.py) checks REACHABILITY,
not the taxonomy in the frontmatter.

THE DOMAIN SET IS DERIVED, NEVER LISTED. There is no domain list in this file: the set is whatever
`domain:` values the tracked docs actually carry. That is what makes the taxonomy call in
prompt-scripts.md §The taxonomy call a FRONTMATTER change rather than a code change — retag a doc and
the checker's universe moves with it. What IS written down is the `role:` vocabulary of CONVENTIONS
§8.1, because a typo'd role would otherwise drop a doc out of the hub rules below and out of every
other rule that reads role.

SIX RULES, both halves proved by --self-test:

  domain        every in-scope doc declares a `domain:` in its leading `---` block. A
                `-generated.md` render view is out of scope: §8.2 says generated views carry no
                frontmatter by design, so demanding one here would be a lie about the format.
  domain-shape  that value must be a BARE lowercase slug. `domain: "network"`, `domain: Network` and
                `domain: network # retag` all used to be accepted, and each one silently MINTS a new
                one-doc domain while dropping the doc out of the domain whose hub rule it was
                satisfying — the run prints `OK` and `--show` prints a domain nobody meant. The finding
                quotes what a parser would have stored, so the fix is visible from the line alone.
  dup-key       a `domain:`/`role:` written TWICE in one block is last-wins with no warning — the
                frontmatter twin of `check_yaml_dup_keys.py` (CONVENTIONS §6 "a duplicate YAML mapping
                key is a silent no-op"). Refused, never guessed: the gate does not pick a winner.
  role          every in-scope doc declares a `role:` that exists in the §8.1 vocabulary (widened
                2026-10-18 with the four values the tree already carries: log, queue, evidence,
                incident-log). A missing role is the same defect as a wrong one — an undeclared role
                cannot be a hub, and a domain of undeclared roles has no entry point to find.
  hub           a domain needs a `role: index|broad` hub only when it has ≥2 NON-PAIR docs. One doc
                IS its entry point whatever its role — that is what lets a one-doc domain and an
                `ssot` body pass without inventing a file. TWO index|broad docs in one domain is a
                finding: two hubs are two opinions about where to start.
  pair-domain   a `-review.md` / `-rejected.md` pair cannot create a domain (§8.3): a pair whose
                `domain:` appears on no doc body is a decision log dispatched from a hub that does
                not exist. This is the rule that made `storage` a retag instead of a domain.

WHAT THIS DOES NOT CHECK, on purpose: not "every hub is linked from docs/index.md" — check_doc_map.py
already refuses a doc under docs/ the map cannot reach, so an orphaned hub cannot exist, and a second
checker for the same fact is the CONVENTIONS §2 second-opinion error. Not prose either: this reads the
FIRST `---` block and nothing else, which is what makes it a floor-0 gate (cheap, no corpus sweep)
and legal on a spark-served session.

Output: `OK: <n> docs, <m> domains, each with one claimed home`, or one
`FAIL: <file>: <rule> — <detail>` line per finding. A domain-level finding (missing-hub) names the
DOMAIN in the file slot, because the fact is about the domain and naming one of its docs would blame
a file that did nothing.

Exit: 0 clean · 1 finding(s) · 2 could not run (no tracked docs, or no fixture for --self-test). TWO
floors refuse a walk that saw almost nothing — `WALK_FLOOR` on tracked files, `CORPUS_FLOOR` on parsed
docs, for the HD-1118 mute-failure class: a gate that cannot see the files cannot fail either. Stdlib
+ git only.
"""
from __future__ import annotations

import contextlib
import io
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except (AttributeError, ValueError):
    pass
# HD-1118 Stage 1: FOUND, not assumed from a depth — scripts/lib/repo_root.py.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import require_corpus, root as _hl_root  # noqa: E402

ROOT = _hl_root(__file__)
FIXTURE = ROOT / "scripts" / "testdata" / "check_doc_domain"

# CONVENTIONS §8.1 — the ROLE vocabulary. This is not the domain set (that is derived); it is the
# shape axis, and §8.1 carries the same list. `log`/`queue`/`evidence`/`incident-log` were added to
# §8.1 on 2026-10-18 because the tree already carried them and the list omitted them, which made an
# assert-membership rule red at authoring.
ROLE_VOCAB = ("index", "broad", "ssot", "detail", "reference", "design-spec", "runbook", "research",
              "cross-cutting", "log", "queue", "evidence", "incident-log")
HUB_ROLES = ("index", "broad")
PAIR_SUFFIXES = ("-review.md", "-rejected.md")
GENERATED_SUFFIX = "-generated.md"
# TWO floors, because the walk and the parse can each go blind on their own, and the numbers below are
# MEASUREMENTS, not the floors — the floor is the number that stays put while the measurement drifts.
#   CORPUS_FLOOR — in-scope PARSED docs: 84 measured 2026-10-18, so this sits far below the tree and
#     fires on a broken root/walk, never on an ordinary commit that deletes one doc.
#   WALK_FLOOR   — tracked `.md` under docs/ BEFORE the `-generated` exemption: 88 measured the same day
#     (84 in scope + 4 `-generated`), of which `docs/manual/` is 13. It sits 8 below the measurement, so
#     losing a whole subdirectory is RED while deleting one doc in a normal commit is not: 88 tracked and
#     a `manual`-blind walk yields 75, and 75 is below 80. CORPUS_FLOOR cannot catch that shape (75 - 4
#     generated = 71 parsed, still over 40) and no sibling gate covers it: `check_doc_map.py` exempts
#     `manual/*`. Raise WALK_FLOOR when the tree grows past the drift margin.
CORPUS_FLOOR = 40
WALK_FLOOR = 80
KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):(.*)$")
# A `domain:` is a slug, not free text: lowercase alphanumerics, hyphens between, nothing else.
DOMAIN_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
# One quoted YAML scalar: quotes are syntax, not content, and may be followed by a comment.
QUOTED_RE = re.compile(r"""^(?:(['"])(.*?)\1)\s*(?:#.*)?$""")


def scalar(raw: str) -> str:
    """What a YAML reader would STORE for this scalar: one layer of matching quotes, then an UNQUOTED
    trailing comment (YAML opens a comment at a `#` preceded by whitespace, so `foo#bar` is a value and
    `foo #bar` is `foo`). This is the value a downstream parser uses — it is NOT the verdict: the
    `domain-shape` rule judges the RAW text, because a value that needs parsing to be understood is
    already a value no sibling doc carries.
    """
    raw = raw.strip()
    m = QUOTED_RE.match(raw)
    if m:
        return m.group(2) or ""
    return re.split(r"\s+#", raw, maxsplit=1)[0].strip()


def is_pair(rel: str) -> bool:
    return rel.rsplit("/", 1)[-1].endswith(PAIR_SUFFIXES)


def frontmatter(text: str):
    """(fields | None, error | None, dup {key: [line, …]}) from the LEADING `---` block only.

    Prose is never read. Returns (None, None, {}) for a file with no frontmatter block at all, and
    (None, msg, {}) for a block that opens and never closes, because those are different defects: the
    first is a missing field, the second is a truncated file that would otherwise read as "no
    frontmatter" forever. The scan stops 40 lines in: a `---` that opens and does not close inside 40
    lines is a Markdown horizontal rule above a document, not a frontmatter block, and parsing prose as
    fields is worse than refusing it. Keys are matched at column 0 only, so a nested list item cannot
    read as one. A key seen TWICE is reported, not resolved: `fields` keeps the LAST value because that
    is what every real YAML parser does, and the caller turns the repetition into a finding.
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None, None, {}
    fields: dict[str, str] = {}
    first: dict[str, int] = {}
    dups: dict[str, list[int]] = {}
    for n, ln in enumerate(lines[1:40], start=2):
        if ln.strip() == "---":
            break
        m = KEY_RE.match(ln)
        if not m:
            continue
        key = m.group(1)
        if key in first:
            dups.setdefault(key, [first[key]]).append(n)
        else:
            first[key] = n
        fields[key] = m.group(2).strip()
    else:
        return None, "the `---` block never closes", {}
    return fields, None, dups


def scan(corpus: dict[str, str]):
    """corpus {relpath: text} -> (findings, stats). Pure: no git, no filesystem."""
    findings: list[str] = []
    docs: dict[str, dict] = {}
    n_generated = 0
    for rel in sorted(corpus):
        if rel.rsplit("/", 1)[-1].endswith(GENERATED_SUFFIX):
            n_generated += 1              # §8.2: a render view, out of scope by design
            continue
        fields, err, dups = frontmatter(corpus[rel])
        if err:
            findings.append(f"FAIL: {rel}: frontmatter — {err}")
            continue
        if dups:
            detail = "; ".join(f"`{k}` appears {len(v)}× in one frontmatter block "
                               f"on line{'s' * (len(v) > 1)} {' + '.join(map(str, v))}"
                               for k, v in sorted(dups.items()))
            findings.append(f"FAIL: {rel}: dup-key — {detail} — the LAST one wins silently, so the first "
                            "keeps looking authoritative while editing it is a no-op (CONVENTIONS §6, the "
                            "frontmatter twin of check_yaml_dup_keys.py): delete the stale key")
            continue
        fields = fields or {}
        raw_domain = fields.get("domain", "").strip()
        domain = scalar(raw_domain)
        role = fields.get("role", "").strip()
        if not domain:
            findings.append(f"FAIL: {rel}: domain — no `domain:` value in the frontmatter block, so the "
                            "doc claims no home in the derived set")
            continue
        if raw_domain != domain or not DOMAIN_RE.match(domain):
            parsed = "" if domain == raw_domain else f" (a parser reads it as `{domain or 'nothing'}`)"
            findings.append(f"FAIL: {rel}: domain-shape — `{raw_domain}` is not a bare lowercase "
                            f"slug{parsed}. Write it lowercase with hyphens and nothing after it — quotes, "
                            "capitals and a trailing `# …` each mint a NEW one-doc domain and drop the doc "
                            "from the domain it belongs to (CONVENTIONS §8.1)")
            continue
        # `role:` needs no shape rule of its own and no scalar(): membership in ROLE_VOCAB is a strict
        # equality, so anything that is not EXACTLY one of the §8.1 words — quoted, capitalised, commented
        # — is already a finding. The open set is the one that needs the slug rule.
        if not role:
            findings.append(f"FAIL: {rel}: role — no `role:` in the frontmatter block, so the doc "
                            "cannot be read as a hub or a body")
            continue
        if role not in ROLE_VOCAB:
            findings.append(f"FAIL: {rel}: role — `{role}` is not in the CONVENTIONS §8.1 vocabulary "
                            f"({' / '.join(ROLE_VOCAB)})")
            continue
        docs[rel] = {"domain": domain, "role": role}

    by_domain: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for rel, d in docs.items():
        by_domain[d["domain"]].append((rel, d["role"]))
    body_domains = {d["domain"] for rel, d in docs.items() if not is_pair(rel)}

    for domain in sorted(by_domain):
        members = sorted(by_domain[domain])
        bodies = [m for m in members if not is_pair(m[0])]
        hubs = [m for m in members if m[1] in HUB_ROLES]
        if len(hubs) > 1:
            # ONE finding per domain, keyed on the first hub path: which of the two is the hub is the
            # owner's call, so the finding names both and blames neither.
            findings.append(
                f"FAIL: {hubs[0][0]}: two-hubs — domain `{domain}` carries "
                f"{len(hubs)} `role: {'|'.join(HUB_ROLES)}` docs "
                f"({', '.join(f'{r} ({ro})' for r, ro in hubs)}); two hubs are two entry-point "
                "opinions, so keep one and retag the other")
        if len(bodies) >= 2 and not hubs:
            findings.append(
                f"FAIL: domain {domain}: missing-hub — {len(bodies)} docs carry `domain: {domain}` and "
                "none is "
                f"`role: {'|'.join(HUB_ROLES)}`; a domain with ≥2 bodies needs one entry point "
                f"({', '.join(rel for rel, _ in sorted(bodies))})")

    for rel in sorted(docs):
        d = docs[rel]
        # Read rule 2 for exactly what it enforces: the pair's `domain:` appears on SOME doc BODY — it is
        # NOT hub-proof. A domain can satisfy this line and still owe a hub to the rule above, so when
        # HD-1119(a) gives `harness` bodies nobody should read a green pair-domain as "that domain has an
        # entry point".
        if is_pair(rel) and d["domain"] not in body_domains:
            findings.append(
                f"FAIL: {rel}: pair-domain — `domain: {d['domain']}` appears on no doc body, and a "
                "`-review`/`-rejected` pair cannot create a domain (CONVENTIONS §8.3): retag the pair "
                "to the domain its hub lives in, or give it a hub")

    domains = {d["domain"] for d in docs.values()}
    stats = {"docs": len(docs), "domains": len(domains), "generated": n_generated,
             "by_domain": {k: len(v) for k, v in by_domain.items()}}
    return findings, stats


def show(corpus: dict[str, str]) -> int:
    """The DERIVED set with its counts — printed, never remembered (CONVENTIONS §2)."""
    _, stats = scan(corpus)
    print(f"derived from {stats['docs']} tracked docs ({stats['generated']} `-generated` render "
          f"view(s) out of scope): {stats['domains']} domains")
    for domain, n in sorted(stats["by_domain"].items(), key=lambda kv: (-kv[1], kv[0])):
        print(f"  {domain:<14} {n:>3} docs")
    return 0


def report(corpus: dict[str, str], verbose: bool = False, unreadable=()) -> int:
    """The verdict half — separate from main() so --self-test can drive it with a fixture tree.

    `unreadable` is the list of already-worded FAIL lines for docs whose bytes could not be read. They
    are FINDINGS, counted here rather than short-circuiting the run: an unreadable doc may never reach
    the `OK` line, and it may never mute the rest of the tree either.
    """
    if not corpus and not unreadable:
        print("CANNOT RUN: no tracked docs were read. `git ls-files` answered with nothing under "
              "docs/, and a gate that sees nothing cannot fail either (HD-1118 Stage 1).")
        return 2
    findings, stats = scan(corpus)
    findings = list(unreadable) + findings
    if verbose:
        show(corpus)
    for line in findings:
        print(line)
    if findings:
        print(f"\n{len(findings)} finding(s). The domain set is derived from the docs themselves — "
              "every fix here is a frontmatter edit, not a change to this script.")
        return 1
    require_corpus(stats["docs"], CORPUS_FLOOR, "check_doc_domain walked docs carrying frontmatter")
    print(f"OK: {stats['docs']} docs, {stats['domains']} domains, each with one claimed home")
    return 0


def tracked_docs() -> list[str]:
    """Tracked `.md` under docs/ — the whole corpus, derived from git, never from a list.

    The `--  docs` pathspec is the ONE place this walk is stated, which is why the hand proof for
    WALK_FLOOR is "narrow that pathspec" (`git ls-files -z -- docs/manual` is 13 files of these 88): a
    walk that silently loses a subdirectory has to be visible in the count, and the count is proved
    below by require_walk.
    """
    r = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z", "--", "docs"],
                       capture_output=True)
    if r.returncode != 0:
        print(f"ERROR: git ls-files failed: {r.stderr.decode('utf-8', 'replace').strip()}",
              file=sys.stderr)
        raise SystemExit(2)
    return [p for p in r.stdout.decode("utf-8", "replace").split("\0")
            if p.endswith(".md") and "/assets/" not in "/" + p]


def require_walk(files: list[str]) -> int:
    """Refuse a walk that saw almost none of the corpus, then hand back the count.

    tracked_docs() alone only refuses an EMPTY walk, so a pathspec/glob regression that drops one
    subdirectory would print `OK: 71 docs, 9 domains` for a tree this gate only partly read — and
    `docs/manual/` is 13 of the 88, uncovered by any sibling gate. Returns len(files); raises when the
    walk is below WALK_FLOOR.
    """
    return require_corpus(len(files), WALK_FLOOR,
                          "check_doc_domain walked tracked .md under docs/")


def fixture_corpus() -> dict[str, str]:
    """The committed legal tree, keyed as `docs/<name>` so a finding reads like a real one."""
    if not FIXTURE.is_dir():
        raise SystemExit(f"CANNOT RUN: the --self-test fixture {FIXTURE} is missing — a self-test "
                         "that silently finds no fixture proves nothing")
    out = {}
    for p in sorted(FIXTURE.glob("*.md")):
        out["docs/" + p.name] = p.read_text(encoding="utf-8")
    require_corpus(len(out), 3, "check_doc_domain --self-test read its fixture")
    return out


def self_test() -> int:
    """Every rule seen RED, then the same tree seen GREEN with the mutation gone.

    The canary is ONE frontmatter line changed in memory on a copy of the committed fixture, so the
    fixture on disk is always the legal control and each arm's GREEN half is the same measurement.
    """
    base = fixture_corpus()
    ok = True

    def tagged(corpus, tag):
        return [f for f in scan(corpus)[0] if f": {tag} —" in f]

    def green(label):
        findings = scan(base)[0]
        if findings:
            print(f"  FAIL  {label}: the unmutated fixture is not clean:\n    "
                  + "\n    ".join(findings))
            return False
        print(f"  GREEN {label}: the fixture as committed yields 0 findings")
        return True

    def red(label, tag, mutate):
        """Apply one mutation, require the named rule to fire, revert it and require silence."""
        nonlocal ok
        mutant = dict(base)
        mutate(mutant)
        caught = tagged(mutant, tag)
        if not caught:
            print(f"  FAIL  {label}: bred `{tag}`, nothing was reported. Findings: {scan(mutant)[0]}")
            ok = False
            return
        print(f"  RED   {label}: {caught[0]}")
        if not green(label):
            ok = False

    def set_field(rel, key, value):
        """Rewrite ONE line of the frontmatter block — the shape a real retag has."""
        def apply(mutant):
            lines = mutant[rel].splitlines()
            for n, ln in enumerate(lines):
                if ln.startswith(f"{key}:"):
                    lines[n] = f"{key}: {value}"
                    break
            else:
                lines.insert(1, f"{key}: {value}")
            mutant[rel] = "\n".join(lines) + "\n"
        return apply

    def drop_field(rel, key):
        """Delete ONE frontmatter line — the shape an unfinished doc has."""
        def apply(mutant):
            mutant[rel] = "\n".join(ln for ln in mutant[rel].splitlines()
                                    if not ln.startswith(f"{key}:")) + "\n"
        return apply

    # 1 — the rule that made `storage` a retag rather than a domain.
    def orphan_pair(mutant):
        for rel in ("docs/network-review.md", "docs/network-rejected.md"):
            set_field(rel, "domain", "paironly")(mutant)
    red("orphan pair-domain (a pair cannot create a domain)", "pair-domain", orphan_pair)

    # 2 — two hubs are two entry-point opinions.
    red("two-hub domain", "two-hubs",
        set_field("docs/network-dns.md", "role", "index"))

    # 3 — a ≥2-doc domain with no index|broad doc has no entry point.
    red("missing-hub on a 2-doc domain", "missing-hub",
        set_field("docs/network.md", "role", "detail"))

    # 4 — the field the whole rule set reads.
    red("missing domain", "domain", drop_field("docs/network-dns.md", "domain"))

    # 5 — a typo'd role must not silently leave every other rule.
    red("unknown role", "role", set_field("docs/subscription.md", "role", "overview"))

    # 5b — the SHAPE of the value, not just the value. Each of these three used to be accepted, minting a
    # one-doc domain and dropping the doc from the domain it was written for; the run stayed green.
    for shape, raw in (("quoted", '"network"'),
                       ("uppercase", "Network"),
                       ("trailing comment", "network # retag")):
        red(f"domain-shape: {shape} value", "domain-shape",
            set_field("docs/network-dns.md", "domain", raw))

    # 5c — the same key TWICE in one block: last wins, silently — the frontmatter twin of the duplicate
    # YAML mapping key CONVENTIONS §6 names and check_yaml_dup_keys.py refuses in IaC.
    def repeat_domain(mutant):
        lines = mutant["docs/network-dns.md"].splitlines()
        lines.insert(1, "domain: governance")        # a second `domain:` above the first, both at column 0
        mutant["docs/network-dns.md"] = "\n".join(lines) + "\n"
    red("duplicate `domain:` in one block", "dup-key", repeat_domain)

    # 6 — §8.2: a render view is out of scope, so its missing frontmatter is NOT a finding.
    gen = dict(base)
    gen["docs/services-inventory-generated.md"] = "# Ansible managed\n\nrendered view, no frontmatter\n"
    if scan(gen)[0]:
        print(f"  FAIL  the `-generated` exemption leaked: {scan(gen)[0]}")
        ok = False
    else:
        print("  GREEN a `-generated.md` render view with no frontmatter stays out of scope (§8.2)")

    # 7 — the corpus floor: an empty walk may never read as a clean tree.
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = report({})
    if rc == 2:
        print("  OK    an empty walk is refused with rc 2, never `OK: 0 domains` — "
              + buf.getvalue().strip())
    else:
        print(f"  FAIL  an empty walk returned rc {rc} instead of 2")
        ok = False

    # 7b — the WALK floor, proved at its own boundary rather than by a number copied from the tree:
    # exactly WALK_FLOOR tracked paths must be refused and one more must pass. This is the class the hand
    # proof reproduces — narrowing `git ls-files -z -- docs` by hand so the walk loses docs/manual (13 of
    # 88) leaves 75 files, which still parses 71 docs and so sails under CORPUS_FLOOR.
    for n, expect_refusal in ((WALK_FLOOR, True), (WALK_FLOOR + 1, False)):
        refused = None
        try:
            require_walk([f"docs/d{i}.md" for i in range(n)])
        except SystemExit as e:
            refused = str(e)
        if expect_refusal and refused:
            print(f"  RED   walk floor: a walk of {n} files is refused — {refused.splitlines()[0]}")
        elif expect_refusal:
            print(f"  FAIL  walk floor: a walk of {n} files passed. A walk that loses a subdirectory "
                  "would print OK — that is the failure this floor exists for")
            ok = False
        elif refused:
            print(f"  FAIL  walk floor: a healthy walk of {n} files was refused — "
                  f"{refused.splitlines()[0]}")
            ok = False
        else:
            print(f"  GREEN walk floor: {n} tracked files pass, {WALK_FLOOR} does not")

    # 7c — floor vs drift: the measurement WALK_FLOOR was derived from. `docs/manual` is 13 of these, so
    # a tree that drifts far enough to sit under its own floor says so here instead of going red in CI.
    try:
        measured = len(tracked_docs())
    except SystemExit:
        measured = 0                      # no git on this seat: an environment boundary, never a pass
    if not measured:
        print("  SKIP  no `git ls-files` here, so the walk floor is proved at its boundary only")
    elif measured <= WALK_FLOOR:
        print(f"  FAIL  the real walk yields {measured} tracked .md, at or below WALK_FLOOR "
              f"{WALK_FLOOR} (measured 88 on 2026-10-18) — raise the floor with the tree")
        ok = False
    else:
        print(f"  OK    the real walk yields {measured} tracked .md, above WALK_FLOOR {WALK_FLOOR}")

    # 8 — the single-doc-domain half of the hub rule, stated where it is exercised: the fixture's
    # `governance` doc is alone in its domain with `role: reference` and yields nothing.
    gov = [rel for rel in base if (frontmatter(base[rel])[0] or {}).get("domain") == "governance"]
    if len(gov) == 1 and not scan(base)[0]:
        print("  OK    a one-doc domain is its own entry point (`governance` here: 1 doc, "
              "role: reference, no hub owed)")
    else:
        print("  FAIL  the one-doc-domain exemption is not exercised by the fixture")
        ok = False

    if not green("the whole fixture, last"):
        ok = False
    print("self-test: " + ("all canaries caught, control clean" if ok else "NOT PROVEN"))
    return 0 if ok else 1


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()
    files = tracked_docs()
    if not files:
        print("CANNOT RUN: `git ls-files` reports no tracked .md under docs/ — either the walk is "
              "broken or this is not the repo root. A gate that sees nothing cannot fail either.")
        return 2
    require_walk(files)
    corpus = {}
    unreadable_findings = []
    for f in files:
        try:
            corpus[f] = (ROOT / f).read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            # A doc whose bytes cannot be read cannot be proved to carry a `domain:` — reported, not
            # skipped, because a silently-missing doc is the mute-failure class this gate exists for.
            unreadable_findings.append(
                f"FAIL: {f}: frontmatter — unreadable as UTF-8, so its `domain:` cannot be checked")
    if "--show" in sys.argv:
        for line in unreadable_findings:
            print(line)
        return show(corpus)
    # One unreadable doc is ONE finding, not a verdict on the run: report() scans the rest of the tree and
    # counts these into the total, so a single latin-1 file can neither print OK nor hide what it masked
    # (review HD-1119b — this used to be `return 1 if unreadable else report(…)`).
    return report(corpus, "--verbose" in sys.argv, unreadable_findings)


if __name__ == "__main__":
    sys.exit(main())
