#!/usr/bin/env python3
"""check_doc_sensitivity.py — the data-sensitivity class CONVENTIONS §8.6 declares is proved to exist.

WHY THIS EXISTS. README.md §3 makes a hosted lane the owner's call and §8.6 states the egress rule — a run
whose read list names a `personal` or a `secret-bearing` doc is not an external-lane run. The shape scanners
(`check_secrets.py`, `check_secret_leak.py`) prove no credential TEXT ships; neither can say what a document
is ABOUT, which is the fact a run needs BEFORE it decides where its read list may go. HD-1195 swept the class
onto every hand-authored doc; a sweep is a one-time act, and without this file "the sweep changed nothing but
classes" stays a claim in a commit message. Four rules, each with a canary in `--self-test`:

  declared        every tracked hand-authored `docs/**/*.md` declares `sensitivity:` in its LEADING `---`
                  block. The four `-generated.md` render views are exempt: §8.2 gives a generated file
                  `# Ansible managed` on line 1, so there is no frontmatter block to put the field in, and
                  §8.6 says the view inherits its source doc's class — a second declaration would be a second
                  source. A missing field is a gap and never a silent exemption (§8.6: "unprotected rather
                  than protected by accident").
  vocab           the value is ONE BARE LOWERCASE slug from {infra, personal, secret-bearing}. `sensitivity:
                  "personal"`, `sensitivity: Personal` and `sensitivity: personal # retagged` all PARSE to
                  something only that doc carries: a fourth class nothing else reads, which drops the doc out
                  of the egress rule and out of the payload rule below while the run stays green. This is
                  §8.1's `check_doc_domain.py` shape rule moved to the other axis, and the finding quotes what
                  a YAML reader would store, so the line explains itself. A key written TWICE in one block is
                  the same defect by another route — last wins silently (CONVENTIONS §6, the
                  `check_yaml_dup_keys.py` class) — so `vocab` means "exactly one bare slug", both ways.
  floor           the owner's classification is carried here as an explicit map, so RETAGGING a family or
                  secrets doc down to `infra` reddens a commit instead of quietly widening what may leave the
                  house. This is the one list of files in the gate and it is deliberately a FLOOR, not the
                  corpus: the corpus is derived and printed on every run (§8.6: derive the population, never
                  re-type it), the floor is a ruling, and a ruling has to be written down somewhere to be
                  contradicted by a diff.
  payload         a `personal` doc may not carry a person's contact payload — an email at a non-`kogler.si`
                  domain, an IBAN, or a phone number. The class says a run may not carry this text out; the
                  rule says the text that would hurt most is not in there to carry. Floor 0 by measurement
                  (see `--self-test` and the run line): every email literal in `docs/` is a service address on
                  the family domain, and no IBAN- or phone-shaped token exists anywhere under `docs/`.

The class the payload rule reads is max(declared, floor): a downgrade that would dodge rule (d) is exactly
what rule (c) exists to make impossible, so the two cannot be played against each other. §8.6's "highest class
wins" is the same max.

WHAT THIS DOES NOT CHECK, stated rather than left to be found:
  * not the key's ORDER inside the block. §8.6 names `after status:` as the human slot; every doc carries it
    there and the mechanical reader keys on the leading block, not on the position, so a reorder stays legal.
  * not what a `-generated.md` view renders. Its class is inherited and invisible here — and §8.6 rules that
    scanning the output anyway would be the wrong end: a renderer that puts a personal value into a render
    view is a defect at the source, so fix the renderer or the SSOT it reads (§8.5).
  * not where the text goes next. No gate inspects a child's read list; the class binds the human/agent
    decision, and the mechanical launch-time leg belongs in `scripts/harness/` beside the settings plane.
  * not whether a class is CORRECT for a doc that changes subject — only that one is declared, spelled from
    the controlled set, at or above its floor, and clean of the one payload shape the family plane must never
    hold. Re-classifying a doc is a frontmatter edit and this gate never blocks a deliberate promotion.

Run:   python3 scripts/gate/check_doc_sensitivity.py [--show] [--verbose] [--self-test]
Exit:  0 clean · 1 finding(s) · 2 could not run (no tracked docs under docs/ — a corpus that cannot be read is
       never a pass). An unreadable doc is a FINDING, not a skip: a doc whose bytes cannot be read cannot be
       proved clean. Stdlib + git only; no network, no vault, no host.
"""
from __future__ import annotations

import argparse
import contextlib
import io
import re
import subprocess
import sys
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

# CONVENTIONS §8.6 — the three classes, ordered low → high because "highest class wins" is a max.
VOCAB = ("infra", "personal", "secret-bearing")
RANK = {slug: i for i, slug in enumerate(VOCAB)}
GENERATED_SUFFIX = "-generated.md"
KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):(.*)$")
SLUG_RE = re.compile(r"^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$")
QUOTED_RE = re.compile(r"""^(?:(['"])(.*?)\1)\s*(?:#.*)?$""")

# THE FLOOR MAP — the owner's ruling, not the corpus. Two shapes, because the family plane is a PLANE:
# naming its 13 files is the copy that silently under-reads the day `docs/manual/` grows a doc, which is
# the drift §8.6's "derive it, never re-type it" is about. Measured on 2026-10-24: `docs/manual/` = 13 docs,
# and the exact entries are the four §8.6 names as the secrets-plane docs (the vault notes, the secret
# catalogs, the OIDC glue).
FLOOR_PREFIXES = (("docs/manual/", "personal"),)
FLOOR_EXACT = {
    "docs/services-finance.md": "personal",
    "docs/1password.md": "secret-bearing",
    "docs/deployment-ai-stack-secrets.md": "secret-bearing",
    "docs/deployment-secrets.md": "secret-bearing",
    "docs/services-authentik.md": "secret-bearing",
}

# The payload shapes, rule (d). Each one is a shape a person's contact data takes when it is copied out of a
# vault note into a doc that is about a person. Nothing here prints a value: a finding names the SHAPE and the
# line, never the payload (§6 — a guard that quotes what it found is a second leak).
HOME_DOMAIN = "kogler.si"           # the family domain: service addresses live here, people do not
EMAIL_RE = re.compile(r"(?<![A-Za-z0-9._%+=-])[A-Za-z0-9._%+-]+@((?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,})\b")
# An IBAN is `CC + 2 check digits + BBAN`, 15..34 characters (ISO 13616). The country prefix is not decoration:
# without it every SHA-256 / apt-key fingerprint in `docs/` (`E09C A29F 6E17 8040 EF22 …`) reads as an account
# number, and a rule that cries wolf at 40 hex groups gets muted inside a week. The set is the IBAN registry's
# prefixes; a code missing from it only ever makes the rule quieter, never louder about the wrong thing.
IBAN_CC = sorted("""AD AE AT AZ BA BE BG BH BR CH CR CY CZ DE DK DO EE ES FI FO FR GB GE GI GL GR HR HU IE IL
IM IS IT JO KW KZ LB LI LT LU LV MC MD MT MR MS NL NO PK PL PT QA RO RS SA SE SI SK SM TN TR UA UK VA XK
""".split())
# The separators a copied-out payload keeps: space, tab, NBSP, thin/nbsp hyphen, hyphen. The hyphen is
# ESCAPED so it stays a literal in every class it is spliced into — at the end of a class it would otherwise
# open a range against whatever follows (`\u2011-.` is not a range, it is a PatternError at import).
SEPS = r" \t\u00a0\u2009\u2011\-"
IBAN_RE = re.compile(r"\b(?:" + "|".join(IBAN_CC) + r")\d{2}(?:(?:[" + SEPS + r"][A-Z0-9]{4}){2,7}"
                     r"|[A-Z0-9]{11,30})\b")
# International form: a `+` with 8+ digits behind it. The `+` is what keeps this off port numbers, byte
# counts and pins — nothing else in a doc starts a token with `+` and then nine digits.
PHONE_INTL_RE = re.compile(r"\+\d[\d" + SEPS + r".()]{6,}\d")
# Domestic form (no `+`): `0` + 7-10 digits, optionally spaced or hyphenated. Two guards carry the whole
# false-positive load, both measured: `(?<![0-9] )` is the thousands-grouping class — `mmproj-BF16.gguf
# (1 087 039 168 B)` contains "087 039 168", which is a byte count wearing a phone's shape — and the tail
# guard refuses a number that goes on to name a unit. A 9-digit number in 3-3-3 groups is genuinely ambiguous
# between the two, so the rule leans on the guards and the run prints the line it fired on.
# EDGE = the characters that GLUE a digit run into a longer token (an IP, a pin, a ratio, a port). Space is
# deliberately NOT one of them: a phone number in prose is preceded by a space, and a class that includes it
# makes the rule blind to the exact shape it exists to find.
EDGE = r"0-9A-Za-z:%/\u2011\-"
PHONE_DOM_RE = re.compile(r"(?<![" + EDGE + r"])(?<![0-9] )0\d(?:[" + SEPS + r"]?\d){6,9}"
                          r"(?![" + EDGE + r"])(?!\.\d)"
                          r"(?!\s(?:[kmgt]i?B|KB|bps|[KMHG]Hz|%|s)\b)")
MIN_PHONE_DIGITS = 8

# TWO floors, same reason as check_doc_domain.py: the walk and the in-scope set can each go blind on their
# own, and these are MEASUREMENTS the floors sit under, not measurements (the floor stays put while the tree
# drifts).  WALK_FLOOR — tracked `.md` under docs/: 92 measured 2026-10-24. HAND_FLOOR — the hand-authored
# docs the rules apply to: 88 measured the same day (92 minus the four `-generated` render views).
WALK_FLOOR = 80
HAND_FLOOR = 60


def scalar(raw: str) -> str:
    """What a YAML reader would STORE for this scalar (one layer of matching quotes, then an UNQUOTED trailing
    comment). Like check_doc_domain.py's twin: this is the value a downstream parser uses, NOT the verdict —
    `vocab` judges the RAW text, because a value that needs parsing to be understood is a value no sibling
    doc carries.
    """
    raw = raw.strip()
    m = QUOTED_RE.match(raw)
    if m:
        return m.group(2) or ""
    return re.split(r"\s+#", raw, maxsplit=1)[0].strip()


def frontmatter(text: str):
    """(fields | None, error | None, dup {key: [lines]}) from the LEADING `---` block. Prose is never read.

    (None, None, {}) = no frontmatter block at all; (None, msg, {}) = a block that opens and never closes
    within 40 lines. Those are different defects — the first is a missing field, the second a truncated file
    that would otherwise read as "no frontmatter" forever. Keys match at column 0 only. A key seen TWICE is
    reported, not resolved: `fields` keeps the LAST value because that is what every real YAML parser does.
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


def is_generated(rel: str) -> bool:
    return rel.rsplit("/", 1)[-1].endswith(GENERATED_SUFFIX)


def floor_for(rel: str):
    """(floor, which line of the map demands it) for one path — `infra`/`no floor entry` when the map is silent.

    The map is the OWNER'S ruling, not the corpus: rule (c) is the one place a filename list belongs, because a
    floor has to be written down somewhere to be contradicted by a diff. The population it applies to is still
    derived and printed every run, so drift shows in both directions (§8.6).
    """
    if rel in FLOOR_EXACT:
        return FLOOR_EXACT[rel], f"the named file `{rel}`"
    for prefix, cls in FLOOR_PREFIXES:
        if rel.startswith(prefix):
            return cls, f"the plane `{prefix}**`, which §8.6 names as a whole"
    return "infra", "no floor entry"


def digits(s: str) -> int:
    return sum(c.isdigit() for c in s)


def contact_hits(text: str) -> list[tuple[int, str, str]]:
    """[(line, shape, descriptor)] for the payload shapes in `text` — never a value, never the same span twice.

    The descriptors are written so a reader can act on the finding without the finding being the payload:
    an email names its DOMAIN (the non-personal half), an IBAN its country prefix and length, a phone its
    digit count. Fixing the line needs a position, not a copy.
    """
    found: list[tuple[int, int, str, str]] = []

    def note(m: re.Match, shape: str, desc: str) -> None:
        found.append((m.start(), m.end(), shape, desc))

    for m in EMAIL_RE.finditer(text):
        domain = m.group(1).lower().rstrip(".")
        if domain == HOME_DOMAIN or domain.endswith("." + HOME_DOMAIN):
            continue                       # a service address on the family domain is not a person's payload
        note(m, "email", f"an email at a non-`{HOME_DOMAIN}` domain (`{domain}`)")
    for m in IBAN_RE.finditer(text):
        flat = re.sub("[" + SEPS + r"]", "", m.group(0))
        if not 15 <= len(flat) <= 34:
            continue
        note(m, "iban", f"an IBAN-shaped account number (`{flat[:2]}` + {len(flat) - 2} characters)")
    for m in PHONE_INTL_RE.finditer(text):
        if digits(m.group(0)) >= MIN_PHONE_DIGITS:
            note(m, "phone", f"a phone-shaped number in international form ({digits(m.group(0))} digits)")
    for m in PHONE_DOM_RE.finditer(text):
        if digits(m.group(0)) >= MIN_PHONE_DIGITS - 1:
            note(m, "phone", f"a phone-shaped number ({digits(m.group(0))} digits)")

    out, taken = [], []
    for start, end, shape, desc in sorted(found):
        if any(s < end and start < e for s, e in taken):
            continue                       # one payload, one finding — `+386 41 …` matches two phone shapes
        taken.append((start, end))
        out.append((text[:start].count("\n") + 1, shape, desc))
    return sorted(out)


def declared_class(rel: str, text: str):
    """(class_or_None, [findings]) for one hand-authored doc — rules `declared` and `vocab`."""
    fields, err, dups = frontmatter(text)
    if err:
        return None, [f"FAIL: {rel}: frontmatter — {err}, so no field in it can be trusted, `sensitivity:` "
                      "included"]
    if fields is None:
        return None, [f"FAIL: {rel}: declared — no leading `---` frontmatter block, so the doc declares no "
                      "sensitivity class (CONVENTIONS §8.6: a doc carrying no `sensitivity:` line is `infra` "
                      "— unprotected rather than protected by accident)"]
    dups = {k: v for k, v in dups.items() if k == "sensitivity"}
    if dups:
        detail = "; ".join(f"lines {', '.join(map(str, v))}" for _, v in sorted(dups.items()))
        return None, [f"FAIL: {rel}: vocab — `sensitivity:` appears more than once in one frontmatter block "
                      f"({detail}) — the LAST one wins silently, so the first keeps looking authoritative while "
                      "editing it is a no-op (CONVENTIONS §6, the frontmatter twin of check_yaml_dup_keys.py)"]
    if "sensitivity" not in fields:
        return None, [f"FAIL: {rel}: declared — no `sensitivity:` key in the frontmatter block. §8.6's egress "
                      "rule reads this field; with no field the doc is `infra` by default and the run cannot "
                      "tell that from a doc that was classified"]
    raw = fields["sensitivity"]
    value = scalar(raw)
    if not value:
        return None, [f"FAIL: {rel}: vocab — `sensitivity:` carries no value at all, so the key is present and "
                      "the class is still undeclared"]
    if raw != value or not SLUG_RE.match(value) or value not in VOCAB:
        hint = "" if value == raw.strip() else f" (a YAML reader stores `{value or 'nothing'}`)"
        return None, [f"FAIL: {rel}: vocab — `{raw}` is not one bare lowercase slug from "
                      f"{' / '.join(VOCAB)}{hint}. Quotes, a capital, a trailing `# …` and a list each MINT a "
                      "fourth class nothing else reads, which drops the doc out of §8.6's egress rule and out "
                      "of this gate's payload rule (the shape rule of §8.1's check_doc_domain.py, on the "
                      "sensitivity axis)"]
    return value, []


def scan(corpus: dict[str, str]):
    """corpus {relpath: text} -> (findings, stats). Pure: no git, no filesystem."""
    findings: list[str] = []
    by_class: dict[str, list[str]] = {slug: [] for slug in VOCAB}
    n_generated = 0
    payload_docs = 0
    payload_hits = 0
    floors_seen: dict[str, str] = {}
    for rel in sorted(corpus):
        if is_generated(rel):
            n_generated += 1                       # §8.2: a render view, out of scope by design
            continue
        cls, fm_findings = declared_class(rel, corpus[rel])
        if fm_findings:
            findings += fm_findings
            continue
        by_class[cls].append(rel)
        # `floor` — the map is the owner's ruling; a class below it is a downgrade, whatever the reason.
        floor, why = floor_for(rel)
        if why != "no floor entry":
            floors_seen[rel] = floor
        if RANK[cls] < RANK[floor]:
            findings.append(
                f"FAIL: {rel}: floor — declares `{cls}`, its floor is `{floor}` ({why}: CONVENTIONS §8.6). "
                "Re-classifying a doc downward is the owner's act, and this line is where that act has to be "
                "visible in the diff that makes it")
            continue
        effective = VOCAB[max(RANK[cls], RANK[floor])]
        if effective != "personal":
            continue
        payload_docs += 1                          # `payload` — only the class a person's data would travel in
        for line, shape, desc in contact_hits(corpus[rel]):
            payload_hits += 1
            findings.append(
                f"FAIL: {rel}:{line}: payload — {desc}, in a `personal` doc. The class says this text may not "
                "leave the house and the payload is the reason it must not: move it to the vault / the owning "
                "secret-bearing doc and keep the doc ABOUT the person rather than CONTAINING them")
    stats = {"generated": n_generated, "docs": sum(len(v) for v in by_class.values()),
             "by_class": {k: len(v) for k, v in by_class.items()},
             "docs_by_class": by_class, "payload_docs": payload_docs, "payload_hits": payload_hits,
             "floors_seen": floors_seen}
    return findings, stats


def floor_entries() -> list[str]:
    """The map's own entries, for the drift note — plane prefixes expanded to what the corpus matched."""
    return sorted(FLOOR_EXACT) + [f"{p}* for `{c}`" for p, c in FLOOR_PREFIXES]


def distribution(stats: dict) -> None:
    """The derived population, printed on EVERY path — it is rule (c)'s second half: the floor map is one
    opinion, the docs are the other, and a reader has to see both to notice they disagree (§8.6)."""
    print(f"distribution over {stats['docs']} hand-authored doc(s) — derived from the field, never from a "
          f"list (`rg -l '^sensitivity: <class>' docs/` is the same answer):")
    for slug in VOCAB:
        print(f"  {slug:<15} {stats['by_class'][slug]:>3} docs")
    print(f"  ({stats['generated']} `-generated.md` render view(s) exempt — §8.2 leaves them no frontmatter "
          "to declare in, §8.6 has them inherit)")
    missing = [e for e in sorted(FLOOR_EXACT) if e not in stats["floors_seen"]]
    exact = sum(1 for rel in stats["floors_seen"] if rel in FLOOR_EXACT)
    plane = len(stats["floors_seen"]) - exact
    print(f"  floor map: {len(stats['floors_seen'])} doc(s) carry a floor — {exact} named file(s) + "
          f"{plane} under {FLOOR_PREFIXES[0][0]}* (the rest of the corpus is `infra`, which needs no floor)")
    for rel in missing:
        # NOT a finding: a doc retired is not a defect, it is a stale map line. Printed, because a floor that
        # silently stops covering a path is how a later rename escapes rule (c) unnoticed.
        print(f"  NOTE: the floor map names {rel} and the walk did not find it — if the doc was renamed or "
              "retired, drop the line; if the walk missed it, that is the bug")


def report(corpus: dict[str, str], verbose: bool = False, unreadable=()) -> int:
    """The verdict half — separate from main() so --self-test can drive it with a synthetic corpus.

    `unreadable` is the already-worded FAIL list for docs whose bytes could not be read: FINDINGS, counted
    rather than short-circuited, so one unreadable doc can neither print `OK` nor mute the rest of the tree.
    """
    if not corpus and not unreadable:
        print("CANNOT RUN: no tracked docs were read. `git ls-files` answered with nothing under docs/, and "
              "a gate that sees nothing cannot fail either (HD-1118 Stage 1).")
        return 2
    findings, stats = scan(corpus)
    findings = list(unreadable) + findings
    distribution(stats)
    if verbose:
        for slug in VOCAB:
            for rel in stats["docs_by_class"][slug]:
                print(f"  {rel:<52} {slug}")
    for line in findings:
        print(line)
    if findings:
        print(f"\n{len(findings)} finding(s). Three of the four rules are fixed by a frontmatter edit; the "
              "floor rule is fixed by an owner's decision, and this file is where that decision is written.")
        return 1
    require_corpus(stats["docs"], HAND_FLOOR, "check_doc_sensitivity walked hand-authored docs under docs/")
    print(f"OK: {stats['docs']} hand-authored docs, one sensitivity class each, floors held, "
          f"{stats['payload_hits']} contact payload(s) in the {stats['payload_docs']} personal doc(s)")
    return 0


def tracked_docs() -> list[str]:
    """Tracked `.md` under docs/ — the corpus, derived from git and never from a list."""
    r = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z", "--", "docs"], capture_output=True)
    if r.returncode != 0:
        print(f"ERROR: git ls-files failed: {r.stderr.decode('utf-8', 'replace').strip()}", file=sys.stderr)
        raise SystemExit(2)
    return [p for p in r.stdout.decode("utf-8", "replace").split("\0")
            if p.endswith(".md") and "/assets/" not in "/" + p]


def require_walk(files: list[str]) -> int:
    """Refuse a walk that saw almost none of the corpus, then hand back the count. Narrowing the pathspec by
    hand is the canary: `git ls-files -z -- docs/manual` is 13 of these 92, and a run that lost `manual/`
    would still clear a parsed-doc floor while its personal rules scanned nothing."""
    return require_corpus(len(files), WALK_FLOOR, "check_doc_sensitivity walked tracked .md under docs/")


# --- the self-test corpus --------------------------------------------------------------------------- #

def doc(title: str, sens: str | None, domain: str = "deployment", body: str = "prose\n") -> str:
    fm = ["---", f"title: {title}", "role: detail", f"domain: {domain}", "status: active"]
    if sens is not None:
        fm.append(f"sensitivity: {sens}")
    fm += ["tags: [example]", "---"]
    return "\n".join(fm) + f"\n# {title}\n\n{body}"


def legal_corpus() -> dict[str, str]:
    """A small LEGAL tree: one doc per rule's green side, including both halves of the floor map."""
    return {
        "docs/network.md": doc("Network", "infra", "network"),
        "docs/manual/chat.md": doc("Chat", "personal", "manual"),
        "docs/manual/wifi.md": doc("Wifi", "personal", "manual"),
        "docs/services-finance.md": doc("Finance", "personal", "services"),
        "docs/1password.md": doc("1Password", "secret-bearing", "deployment"),
        "docs/services-inventory-generated.md": "# Ansible managed\n\nrendered view, no frontmatter\n",
    }


def self_test() -> int:
    """Every rule seen RED on a mutation of the legal tree, then the same tree GREEN with it gone."""
    base = legal_corpus()
    ok = True

    def tagged(corpus, tag):
        return [f for f in scan(corpus)[0] if f": {tag} —" in f]

    def green(label):
        findings = scan(base)[0]
        if findings:
            print(f"  FAIL  {label}: the unmutated corpus is not clean:\n    " + "\n    ".join(findings))
            return False
        print(f"  GREEN {label}: the legal tree yields 0 findings")
        return True

    def red(label, tag, mutate):
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
        def apply(mutant):
            mutant[rel] = "\n".join(ln for ln in mutant[rel].splitlines()
                                    if not ln.startswith(f"{key}:")) + "\n"
        return apply

    def append_body(rel, text):
        def apply(mutant):
            mutant[rel] = mutant[rel].rstrip("\n") + "\n\n" + text + "\n"
        return apply

    # 1 — the field the whole rule set reads, and the exemption that keeps it honest.
    red("missing `sensitivity:`", "declared", drop_field("docs/network.md", "sensitivity"))

    def no_block(mutant):
        mutant["docs/network.md"] = "# Network\n\nno frontmatter at all\n"
    red("no frontmatter block", "declared", no_block)

    # 2 — the four spellings that PARSE and still mint a fourth class, plus the duplicate key.
    for shape, raw in (("quoted", '"personal"'),
                       ("capitalised", "Personal"),
                       ("trailing comment", "infra # retagged"),
                       ("unknown slug", "private")):
        red(f"vocab: {shape} value", "vocab", set_field("docs/network.md", "sensitivity", raw))

    def repeat_field(mutant):
        lines = mutant["docs/network.md"].splitlines()
        lines.insert(1, "sensitivity: personal")        # a second `sensitivity:` above the first
        mutant["docs/network.md"] = "\n".join(lines) + "\n"
    red("duplicate `sensitivity:` in one block", "vocab", repeat_field)

    # 3 — the floor, from both halves of the map: the named file and the plane.
    red("floor: the named finance doc drops to infra", "floor",
        set_field("docs/services-finance.md", "sensitivity", "infra"))
    red("floor: a family-plane doc drops to infra", "floor",
        set_field("docs/manual/chat.md", "sensitivity", "infra"))
    red("floor: the vault doc drops to personal", "floor",
        set_field("docs/1password.md", "sensitivity", "personal"))

    # 3b — the floor is a FLOOR: promoting past it is the owner's right and must stay quiet, or the rule
    # becomes an allow-list that reddens every deliberate re-classification and gets widened.
    promote = dict(base)
    set_field("docs/manual/chat.md", "sensitivity", "secret-bearing")(promote)
    if scan(promote)[0]:
        print(f"  FAIL  a promotion above the floor was reported: {scan(promote)[0]}")
        ok = False
    else:
        print("  GREEN the floor only holds a class DOWN — `personal` raised to `secret-bearing` stays quiet")

    # 4 — the payload rule, one canary per shape, in a doc whose class says it must not hold them.
    red("payload: an email off the family domain", "payload",
        append_body("docs/manual/chat.md", "Reach the tutor at name@example.com."))
    red("payload: an IBAN", "payload",
        append_body("docs/manual/chat.md", "Account SI56 0000 0001 2345 678."))
    red("payload: an international phone", "payload",
        append_body("docs/manual/chat.md", "Call +386 41 234 567."))
    red("payload: a domestic phone", "payload",
        append_body("docs/manual/wifi.md", "Support: 041 234 567."))

    # 4b — the three near-misses that must stay GREEN, or the rule is a sledgehammer and gets muted. The
    # byte count is the real one from docs/hardware-workstation.md: a grouped number, not a number to call.
    for label, text in (("a service address on the family domain", "Mail notify@kogler.si daily."),
                        ("a subdomain of it", "Mail ansible-admin@vps.kogler.si daily."),
                        ("a grouped byte count", "The file is 1 087 039 168 B."),
                        ("an apt key fingerprint", "Ascensio key E09C A29F 6E17 8040 EF22 B409 8320 CA65.")):
        probe = dict(base)
        append_body("docs/manual/chat.md", text)(probe)
        if tagged(probe, "payload"):
            print(f"  FAIL  the payload rule bit on {label}: {tagged(probe, 'payload')[0]}")
            ok = False
        else:
            print(f"  GREEN the payload rule ignores {label}")

    # 4c — scope: the same payloads in an `infra` doc are not this rule's business. Stated as an arm because
    # it is the difference between "the corpus is clean" and "the rule looks at 14 docs".
    scope = dict(base)
    append_body("docs/network.md", "Admin name@example.com, account SI56 0000 0001 2345 678.")(scope)
    if tagged(scope, "payload"):
        print(f"  FAIL  the payload rule reached outside the personal class: {tagged(scope, 'payload')[0]}")
        ok = False
    else:
        print("  GREEN the payload rule is scoped to the `personal` class (an `infra` doc is not its subject)")

    # 5 — §8.2: a render view carries no frontmatter, so its absence is NOT a finding.
    gen = dict(base)
    gen["docs/services-inventory-generated.md"] = "# Ansible managed\n\nrendered view, no frontmatter\n"
    if scan(gen)[0]:
        print(f"  FAIL  the `-generated` exemption leaked: {scan(gen)[0]}")
        ok = False
    else:
        print("  GREEN a `-generated.md` render view with no frontmatter stays out of scope (§8.2)")

    # 6 — the empty corpus may never read as a clean tree: the assertion every gate here carries.
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = report({})
    if rc == 2:
        print("  OK    an empty corpus is refused with rc 2, never `OK: 0 docs` — " + buf.getvalue().splitlines()[-1])
    else:
        print(f"  FAIL  an empty corpus returned rc {rc} instead of 2 — not green on an empty corpus is the "
              "floor this gate starts from")
        ok = False

    # 6b — the walk floor at its own boundary, proved as a boundary rather than as a number copied from the
    # tree: exactly WALK_FLOOR paths must be refused and one more must pass.
    for n, expect_refusal in ((WALK_FLOOR, True), (WALK_FLOOR + 1, False)):
        refused = None
        try:
            require_walk([f"docs/d{i}.md" for i in range(n)])
        except SystemExit as e:
            refused = str(e)
        if expect_refusal and refused:
            print(f"  RED   walk floor: a walk of {n} files is refused — {refused.splitlines()[0]}")
        elif expect_refusal:
            print(f"  FAIL  walk floor: a walk of {n} files passed — a walk that loses docs/manual/ (13 of "
                  "the 92) would print OK, which is the failure this floor exists for")
            ok = False
        elif refused:
            print(f"  FAIL  walk floor: a healthy walk of {n} files was refused — {refused.splitlines()[0]}")
            ok = False
        else:
            print(f"  GREEN walk floor: {n} tracked files pass, {WALK_FLOOR} does not")

    # 6c — floor vs drift: the measurement WALK_FLOOR was derived from, re-taken now.
    try:
        measured = len(tracked_docs())
    except SystemExit:
        measured = 0
    if not measured:
        print("  SKIP  no `git ls-files` here, so the walk floor is proved at its boundary only")
    elif measured <= WALK_FLOOR:
        print(f"  FAIL  the real walk yields {measured} tracked .md, at or below WALK_FLOOR {WALK_FLOOR} "
              "(measured 92 on 2026-10-24) — raise the floor with the tree")
        ok = False
    else:
        print(f"  OK    the real walk yields {measured} tracked .md, above WALK_FLOOR {WALK_FLOOR}")

    # 7 — the payload shapes must be seen by the scanner at all: the same four inputs through the detector
    # directly, so a broken regex cannot hide behind a rule that keys on the class.
    for label, text in (("email", "write to name@example.com now"),
                        ("iban", "SI56 0000 0001 2345 678"),
                        ("phone intl", "+386 41 234 567"),
                        ("phone dom", "041 234 567")):
        if not contact_hits(text):
            print(f"  FAIL  the detector does not see a {label} shape: {text!r}")
            ok = False
    print("  OK    the detector sees all four payload shapes when the rule's own text carries them")

    if not green("the whole legal tree, last"):
        ok = False
    print("self-test: " + ("all canaries caught, control clean" if ok else "NOT PROVEN"))
    return 0 if ok else 1


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        prog="check_doc_sensitivity.py",
        description="CONVENTIONS §8.6 — every hand-authored doc declares one sensitivity class, at or above "
                    "its floor, and the family plane carries no contact payload.",
        epilog="exit 0 clean · 1 finding(s) · 2 could not run")
    ap.add_argument("--show", action="store_true",
                    help="print the derived population per class, not just the counts")
    ap.add_argument("--verbose", action="store_true", help="list every doc with the class it declared")
    ap.add_argument("--self-test", action="store_true", help="breed each defect and require the red")
    args = ap.parse_args(argv)
    if args.self_test:
        return self_test()
    files = tracked_docs()
    if not files:
        print("CANNOT RUN: `git ls-files` reports no tracked .md under docs/ — either the walk is broken or "
              "this is not the repo root. A gate that sees nothing cannot fail either.")
        return 2
    require_walk(files)
    corpus, unreadable = {}, []
    for f in files:
        try:
            corpus[f] = (ROOT / f).read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            unreadable.append(f"FAIL: {f}: frontmatter — unreadable as UTF-8, so its `sensitivity:` cannot "
                              "be checked (an unreadable doc is never a pass)")
    if args.show:
        _, stats = scan(corpus)
        distribution(stats)
        for slug in VOCAB:
            if slug == "infra":
                continue
            print(f"  {slug}:")
            for rel in stats["docs_by_class"][slug]:
                print(f"    {rel}")
        return 0
    return report(corpus, args.verbose, unreadable)


if __name__ == "__main__":
    sys.exit(main())
