#!/usr/bin/env python3
"""
check_doc_headings.py -- prove every `\u00a7Section` pointer, in a doc or in an IaC comment,
names a heading that exists in the document it points at, and that a `decision #N` cites a row
that is actually in the decision table.

WHY THIS EXISTS. scripts/gate/check_doc_path_refs.py proves the PATH half of a citation; nothing
proved the ANCHOR half. A `docs/x.md \u00a7Heading` pointer therefore reads as verified while its
anchor is unchecked. Found by hand tonight: docs/services-ai-bench.md cited `decision
#19`/`#25`, which are not rows of the decision log, and IaC/ansible/roles/access/tasks/main.yml
pointed at a rescue section docs/security.md did not have (lane XD later added it as
`## 11. SSH admission gate -- break-glass / rescue path`). Both are invisible to the path gate.
The failure mode that matters most is the RENAME: a heading reworded in the target silently
dangles every pointer to it, and no test notices until a human follows one.

THE GRAMMAR IT ACCEPTS, stated rather than buried in a regex:
  * `docs/x.md \u00a7Heading` / `x.md \u00a7Heading` -- the nearest `.md` token before the `\u00a7` on
    the same line owns the reference; that is how docs and IaC comments both write it.
  * `CONVENTIONS \u00a77` -- a bare stem immediately before the `\u00a7` that names exactly one
    tracked file owns it the same way.
  * `maint-user.yml \u00a7why-for-this-file` -- a pointer into an IaC file resolves against that
    file's own comment banners, which is the anchor style IaC files actually have.
  * `\u00a7Heading` alone -- the same document (docs/**). In an IaC comment, where the file has no
    headings of its own, the document named earlier in the same comment block owns it; if none
    was named that is reported, not guessed. A bare NUMBER in an IaC comment defaults to
    CONVENTIONS.md, whose \u00a73 comment-hygiene rule makes it the file every IaC comment cites
    implicitly (`invisible to a fleet review (\u00a77)`); when it does not resolve there, the
    finding says so instead of pretending the rulebook was meant.
  * Match order: exact heading text -> section number (`\u00a79b-1`, `\u00a78.3`) -> normalized
    prefix (`\u00a7The GLOBAL ceiling` resolves
    `### The GLOBAL ceiling: `spark_llm_device_hold_ceiling_bytes``). Normalization drops
    backticks and emphasis markers, folds whitespace, lowercases, folds em/en dashes to a hyphen,
    and knows that `## 10. Open work` is pointed at both as `\u00a710` and as `\u00a7Open work`. A
    prefix that matches two headings FAILS and names both: guessing is the failure this tool
    exists to prevent, so an ambiguous match is a defect, not a coin flip.
  * A heading that writes its own section mark -- `## \u00a72 Terminal B -- run the ladder`, the
    style `spark/stability-test.md` and the audit reports use -- is compared with that leading
    mark removed, so `\u00a72`, `\u00a7Terminal B` and `\u00a72 Terminal B` all name it. The strip is
    on the HEADING side and only at its start; it never touches text in the middle of a line.
  * BOUNDARIES, three of them, stated because each has a corpus behind it. (1) A NUMERIC reference
    must end at a digit boundary, so `\u00a73` never names `30 Other thing` and `\u00a79` never names
    `90 things` -- an absolute rule, such a match is dropped, not merely de-ranked. (2) A reference
    that is ONLY a number must not land on a LETTERED sub-number either: `\u00a71` is not
    `1b. Why the harness does NOT go through LiteLLM`, because the label written is a label the
    document does not have (HD-1156 -- a normalized prefix was calling that resolved, which is how a
    pointer to a section that does not exist reported `resolved=True kind=prefix`). (3) A LETTER-internal
    prefix still resolves for a reference spelled with WORDS -- `\u00a7Alert` names `## Alerts` -- BY
    DESIGN, so a short citation into a plural heading stays legal; making that absolute dangles two
    real pointers in this corpus, so it is a corpus decision, not a bug found in here. The token
    window that degrades a long reference to its heading part is KEPT (prose trailing an anchor is
    legal), and it may no longer throw away a LETTERED sub-number to do it -- `\u00a7Phase index 99q`
    names a sub-number the target does not have, and used to resolve onto `Phase index` anyway. The
    one degradation that stays is `\u00a7Phase 0` onto `Phase 0.5 -- VPS`: a bare number, a real heading,
    and the reading the row keeps. Self-test (h) holds all three halves open; (j) holds (2) and the
    word-boundary tie-break; (k) holds the source set below.
  * `decision #N`, `\u00a79 #N`, `\u00a79 decisions #24/#27`, `\u00a79 row 26` -- N must be a row of
    the owning numbered decision table (a table whose header starts `| # |` and whose remaining
    cells say rule/decision). One exists today -- `docs/services-ai.md` \u00a79 -- so a
    `decision #N` written in a document without one is read against it, which is how the repo
    already reads `decision #26`.

THE SOURCES ARE WHERE POINTERS ARE WRITTEN, not only where headings live: `docs/**`, comments under
`IaC/**`, EVERY root-level `.md`, and `scripts/**`. The last two used to be missing (HD-1156), which
left every `\u00a7`-cite written from `CONVENTIONS.md`, `deployment-manual.md`, `scripts/README.md`,
`prompt.md` or `todo.md` unchecked in BOTH directions -- its anchor never resolved, and renaming a
heading never reddened the file pointing at it. A Markdown source owns its unqualified cites (an
unqualified `\u00a72` in `CONVENTIONS.md` is that file's own section 2, exactly as in `docs/`), and a
BARE number its own file does not carry is read against the rulebook, which is the same reading an
IaC comment already got.

WHAT IT IGNORES, each named by --verbose: code fences, shell heredocs and YAML block scalars --
deployed payload, not a promise to a reader (RULES R-2); `*-generated.md` as a SOURCE -- rendered
output, hand-editing it is banned, so its pointers belong to the template that wrote them;
gitignored files -- `git ls-files` never lists them; anything inside a URL; and `.json` under IaC
-- a dashboard `description` is text written to a device, not a pointer a reader follows.

THE FROZEN LEDGER, and why a verdict is about the DIFF and not about the tree. The corpus carries
pre-existing dangling anchors, so a bare "fail on any finding" gate is red at rest and gets muted.
Registered instead as a ratchet over a committed ledger --
`scripts/gate/doc_headings_baseline.txt`, one `<count>TAB<path>TAB<target>TAB<cite>` line per
pointer the repo has AGREED to carry. A pointer matches a line by KEY, never by line number
(`gate/iac_identifier_allowlist.txt` says why): position moves when a doc grows, so a ledger keyed
on it would report an unrelated edit above the pointer as new debt. Two directions fail:
GROWTH -- a pointer the ledger does not carry, or carries fewer times than it appears -- and
STALE -- a ledger line whose pointer now resolves. The second half is what keeps the ledger honest:
an entry that outlives its pointer stops being agreed debt and becomes a free pass for the next
dangling pointer written at that key. Clearing debt is therefore welcome, but it is a two-line
change: fix the pointer and delete its ledger line in the same commit, or lower its count.
`--show-baseline` re-derives the body, so the number is never remembered (CONVENTIONS \u00a72).

--self-test breeds nine shapes in a temp tree and FAILS if any is missed: the rename that breaks a
previously-good pointer, the heading that carries its own `\u00a7`, the numeric boundary that a
`\u00a73`-for-`\u00a730` match would cross, the token-window hole that still lets `\u00a7Phase 0`
land on `Phase 0.5`, and the ledger ratchet -- frozen debt stays green, one new pointer reddens,
a pointer that went reddens its own ledger line, and the rendered ledger parses back to the
population it was rendered from.

Run:   python3 scripts/gate/check_doc_headings.py [--verbose] [--show-baseline] [--self-test]
Exit 0 = every reference resolves or is frozen in the ledger; 1 = new dangling references, or a
ledger line whose pointer is gone; 2 = could not run (including a missing or malformed ledger,
which would silently exempt everything).
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# HD-1118 Stage 1: FOUND, not assumed from a depth — scripts/lib/repo_root.py.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import root as _hl_root  # noqa: E402
ROOT = _hl_root(__file__)

SECTION = "\u00a7"          # section sign: the thing being validated, and part of the output
EMDASH = "\u2014"

DOC_DIR = "docs"
IAC_DIR = "IaC"
GENERATED = "-generated.md"
CONVENTIONS = "CONVENTIONS.md"
CANONICAL_TABLE_DOC = DOC_DIR + "/services-ai.md"
# The committed debt ledger this gate is ratcheted to. It lives next to its checker, because a
# rule file at `scripts/` top level is a data file with no owner (`check_script_layout.py` rule 5).
BASELINE = "scripts/gate/doc_headings_baseline.txt"
# A rendered dashboard `description` is text written to a device (RULES R-2), not a pointer a
# reader follows, so .json is not a reference source. Everything else under IaC that can hold a
# comment is.
IAC_EXTS = (".md", ".yml", ".yaml", ".j2", ".sh", ".bash", ".py", ".conf", ".cfg", ".ini",
            ".toml", ".service", ".timer", ".river", ".hujson", ".txt")

HEADING_RE = re.compile(r"^(?P<hashes>#{1,6})[ \t]+(?P<text>.*?)[ \t]*#*$")
FENCE_RE = re.compile(r"^[ \t]*(?:```|~~~)")
URL_RE = re.compile(r"\b[a-z][a-z0-9+.\-]*://[^\s\"')>]+|(?<![\w/])www\.[^\s\"')>]+")
MD_PATH_RE = re.compile(r"[\w.\-]+(?:/[\w.\-]+)*\.md")
FILE_PATH_RE = re.compile(r"[\w.\-]+(?:/[\w.\-]+)*\.(?:yml|yaml|j2|py|sh|service|river|hujson)")
STEM_BEFORE_RE = re.compile(r"([A-Za-z][\w\-]*)[ \t]*$")
NUM_RE = re.compile(r"^(\d+[a-z]?(?:[.\-]\d+[a-z]?)*)((?=[.\s:\-)]|$))")
# A heading may carry its own section mark (`## \u00a72 Terminal B -- run the ladder`). The mark is
# not part of the name, so it comes off the HEADING side before comparison, and only at its start.
SECTION_MARK_RE = re.compile(r"^[ \t]*(?:[" + SECTION + r"#+][ \t]*)+")
# `.5` / `-1`: the start of a match tail that stopped inside a number label, so that spelling of
# the reference names a section that is not there (`3` against `30 Other thing`, `Phase 0` against
# `Phase 0.5`). resolve_ref may still retry a shorter window -- see self-test (h).
SUBNUM_RE = re.compile(r"[.\-]\s*\d")
# A reference that is nothing but a section number (`1`, `8.3`, `9c`) -- the shape HD-1156 bounds,
# because such a reference carries no words to disambiguate it and a normalized prefix was enough to
# call it a hit.
BARE_NUM_RE = re.compile(r"\d+[a-z]?(?:[.\-]\d+[a-z]?)*")
# A section number whose label carries a LETTER (`99q`, `1a`) -- the shape a retried token window
# used to drop in silence.
LETTERED_NUM_RE = re.compile(r"\d+[a-z]")
ROW_HASH_RE = re.compile(r"#(\d+)")
ROW_WORD_RE = re.compile(r"\brows?[ \t]+(\d+)\b")
DECISION_WORD_RE = re.compile(r"\bdecisions?\b")
SECTION_NUM_RE = re.compile(SECTION + r"[ \t]*\d")
JINJA_OPEN = "{#"
JINJA_CLOSE = "#}"
BLOCK_SCALAR_RE = re.compile(r"^[ \t]*(?:[^#|>'\"]*[|>][+-]?|-[ \t]+[|>][+-]?)[ \t]*(?:#.*)?$")
HEREDOC_RE = re.compile(r"<<-?[ \t]*['\"]?([\w.]+)['\"]?")
# A reference ENDS at a Markdown link tail, a bracket, a pipe, a colon, a sentence break, an
# opening parenthesis (headings are cited by their leading words, not through a parenthetical),
# a second `\u00a7` (`\u00a72/\u00a73` is two pointers), or a range dash before a number
# (`\u00a7\u00a78-10` is sections 8 through 10, so the pointer is section 8).
REF_STOP_RE = re.compile(r"\]\(|[\[\]<>|;)\u00b7\u2192\"]|\s\(|/" + SECTION +
                         r"|[\u2013\u2014-] ?\d")
POSSESSIVE_RE = re.compile(r"['\u2019]s$")
ANCHOR_RE = re.compile(r"^[ \t]*#+[ \t]*([^\n]{1,70}?)[ \t]*(?::|\n|$)")
DASH_MAP = {0x2014: "-", 0x2013: "-", 0x2212: "-", 0x00a0: " "}   # em dash, en dash, minus, nbsp
# The characters that are never part of a heading name, assembled from chr() so the
# tab and the backslash are what they say and not an escaping accident.
LEAD_JUNK = " " + chr(9) + chr(92) + "\"'`(+*\u2014"
TRAIL_JUNK = " " + chr(9) + chr(92) + ".,;:!?)]}'\u2014>-"


def blank(text):
    return " " * len(text)


def blank_match(m):
    return " " * len(m.group(0))


def norm(text):
    """Comparison form of a heading or a reference. Nothing aggressive: meaning must survive."""
    text = text.translate(DASH_MAP).replace("`", "").replace("*", "")
    return re.sub(r"\s+", " ", text).strip().lower()


def key(text):
    """norm(), then the punctuation that is prose, not part of a heading name."""
    return norm(POSSESSIVE_RE.sub("", text)).rstrip(TRAIL_JUNK)


def sec_no(text):
    """Leading section number of a heading or reference (`9b-1.`, `8.3 `, `9c`) or None. The
    number must be followed by a separator, so `1Password CLI` is a title, not section 1."""
    m = NUM_RE.match(text.strip().lower())
    if not m:
        return None
    return m.group(1).rstrip(".-") or None


class Heading(object):
    """One Markdown heading, with the two comparison forms a pointer can use."""

    __slots__ = ("text", "level", "line", "norm", "num", "tail")

    def __init__(self, text, level, line):
        self.text = text
        self.level = level
        self.line = line
        # `## \u00a72 Terminal B` is pointed at as `\u00a72`, as `\u00a7Terminal B` and as
        # `\u00a72 Terminal B`; the leading `\u00a7`/`#` is furniture, not part of the name.
        name = SECTION_MARK_RE.sub("", text, count=1)
        self.norm = norm(name)
        self.num = sec_no(name)
        # "10. Open work" is pointed at as \u00a710 and as \u00a7Open work; keep both spellings.
        self.tail = norm(self.norm[len(self.num or ""):].lstrip(".):- ")) if self.num else self.norm

    def __repr__(self):
        return "`%s`" % self.text


def parse_headings(text):
    out, in_fence = [], False
    for i, line in enumerate(text.split("\n"), 1):
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = HEADING_RE.match(line)
        if m:
            out.append(Heading(m.group("text"), len(m.group("hashes")), i))
    return out


# ---------------------------------------------------------------- masking

def mask_file(path, text):
    """The same text with everything that is not comment-or-prose replaced by spaces, so offsets
    and line numbers survive. Blanked shapes are deployed payload, not pointers: Markdown fences,
    shell heredocs, YAML block scalars, Jinja code, URLs."""
    is_md = path.endswith(".md")
    is_yaml = (not is_md) and re.search(r"\.(ya?ml)(\.j2)?$", path) is not None
    has_heredoc = (not is_md) and re.search(r"\.(sh|bash|j2|conf|cfg)$", path) is not None
    out = []
    in_fence = False
    in_jinja = False
    scalar_indent = None
    heredoc_end = None
    for line in text.split("\n"):
        if heredoc_end is not None:
            if line.strip() == heredoc_end:
                heredoc_end = None
            out.append(blank(line))
            continue
        if re.search(r"<<-?[ \t]*['\"]?[\w.]+", line) and not is_md and not in_jinja:
            heredoc_end = HEREDOC_RE.search(line).group(1)
            out.append(blank(line))
            continue
        if scalar_indent is not None:
            if not line.strip() or (len(line) - len(line.lstrip())) > scalar_indent:
                out.append(blank(line))
                continue
            scalar_indent = None
        if is_yaml and BLOCK_SCALAR_RE.match(line):
            scalar_indent = len(line) - len(line.lstrip())
        if in_jinja:
            end = line.find(JINJA_CLOSE)
            if end < 0:
                out.append(URL_RE.sub(blank_match, line))
                continue
            in_jinja = False
            line = blank(line[:end + 2]) + line[end + 2:]
        if FENCE_RE.match(line):
            in_fence = not in_fence
            out.append(blank(line))
            continue
        if in_fence:
            out.append(blank(line))
            continue
        if is_md:
            kept = line
        else:
            kept, in_jinja = mask_code_line(line, is_yaml, has_heredoc)
        out.append(URL_RE.sub(blank_match, kept))
    return "\n".join(out)


def mask_code_line(line, is_yaml, has_heredoc):
    """Comment text only, at the original columns. Quotes are tracked so a `#` inside a string is
    not mistaken for a comment, and `{# ... #}` Jinja comments are kept because a pointer inside
    one is a pointer a maintainer reads."""
    blanks = blank(line)
    quote = None
    i = 0
    n = len(line)
    while i < n:
        ch = line[i]
        if quote:
            if ch == quote and line[i - 1] != "\\":
                quote = None
            i += 1
            continue
        if ch in "'\"":
            quote = ch
            i += 1
            continue
        if line.startswith(JINJA_OPEN, i):
            end = line.find(JINJA_CLOSE, i + 2)
            if end < 0:
                return blanks[:i] + line[i:], True
            line = line[:i] + blanks[i:end + 2] + line[end + 2:]
            i = end + 2
            continue
        if ch == "#" and (i == 0 or line[i - 1] in " \t"):
            if has_heredoc or (is_yaml and BLOCK_SCALAR_RE.match(line[:i])):
                return blanks, False
            return blanks[:i] + line[i:], False
        i += 1
    return blanks, False


# ---------------------------------------------------------------- the document index

class Tree(object):
    """What the repository's Markdown looks like: which files exist, which headings each holds,
    which decision table each owns. Everything is derived, nothing is configured."""

    def __init__(self, texts):
        self.texts = dict(texts)
        self.headings = {}
        for path, text in self.texts.items():
            self.headings[path] = (parse_headings(text) if path.endswith(".md")
                                   else parse_anchors(text))

    def doc_for_hint(self, hint, origin=""):
        """(path or None, reason) for a name written before a `\u00a7`. A real path wins. A bare
        name is read in the citing file's own tree first -- `observability.md` from a doc is
        docs/observability.md, `versions.yml` from an Ansible file is the Ansible one -- and only
        a tie that survives that ordering is reported, never silently guessed."""
        hint = hint.strip().strip("./")
        if not hint:
            return None, "empty document reference"
        if hint in self.texts:
            return hint, ""
        probe = hint if hint.lower().endswith(".md") else hint + ".md"
        if probe in self.texts:            # a bare stem that is a real path: CONVENTIONS, README
            return probe, ""
        named = sorted(set(p for p in self.texts
                           if p in (hint, probe) or p.endswith("/" + hint)
                           or os.path.basename(p).lower() in (hint.lower(), probe.lower())))
        if len(named) == 1:
            return named[0], ""
        if len(named) > 1:
            best = min(named, key=lambda p: self._nearness(p, origin))
            scored = [p for p in named if self._nearness(p, origin) == self._nearness(best, origin)]
            if len(scored) == 1:
                return scored[0], ""
            return None, "%r is %s -- say which one" % (hint, " and ".join(sorted(scored)))
        return None, "no document %r in the tree" % hint

    @staticmethod
    def _nearness(path, origin):
        """Sort key: same directory, then the same half of the repo, then docs/, then anything."""
        same_dir = os.path.dirname(path) == os.path.dirname(origin)
        same_tree = bool(origin) and path.split("/")[0] == origin.split("/")[0]
        tier = 0 if same_dir else 1 if same_tree else 2 if path.startswith(DOC_DIR + "/") else 3
        return tier, path.count("/")

    def decision_table(self, path):
        """Sorted row numbers of the numbered decision table in `path`, or None."""
        text = self.texts.get(path)
        if text is None:
            return None
        rows, header = [], False
        for line in text.split("\n"):
            stripped = line.strip()
            if not (stripped.startswith("|") and stripped.endswith("|")):
                header = False
                continue
            cells = [c.strip() for c in stripped.strip("|").split("|")]
            if not header:
                header = bool(cells) and cells[0] == "#" and any(
                    re.search(r"\b(rule|decision)\b", c, re.I) for c in cells[1:])
                continue
            if re.match(r"^\d+$", cells[0] or ""):
                rows.append(int(cells[0]))
        return sorted(rows) or None

    def is_decision_cite(self, origin, back, cited_doc):
        """Does this `#N` / `row N` cite a decision-log row? True when the words say so right
        before the number (`decision #26`), or when the nearest `\u00a7<num>` in the window resolves
        to a heading whose text is a decision log."""
        if DECISION_WORD_RE.search(back[-45:]):
            return True
        pos = back.rfind(SECTION)
        if pos < 0:
            return False
        probe_doc = cited_doc
        hints = MD_PATH_RE.findall(back[:pos])
        if hints:
            found, _ = self.doc_for_hint(hints[-1], origin)
            if found:
                probe_doc = found
        ok, _, hits, _ = resolve_ref(clean_ref(back[pos + 1:]), self.headings.get(probe_doc, []))
        return bool(ok and "decision" in hits[0].norm)

    def table_for(self, path):
        """The table a `decision #N` written in `path` binds to: that document's own numbered
        decision table if it has one, else the repository's canonical one
        (`docs/services-ai.md` \u00a79) -- which is what a bare `decision #N` has always meant."""
        rows = self.decision_table(path)
        if rows:
            return rows, path
        return self.decision_table(CANONICAL_TABLE_DOC), CANONICAL_TABLE_DOC


def parse_anchors(text):
    """Named sections of a non-Markdown file -- the only anchor style IaC files have, and what
    `maint-user.yml \u00a7why-for-this-file` points at. Two shapes count, and both read as a name
    rather than as prose: a comment KEY (`# why-for-this-file: ...`) and the title line right
    after a `# =====` banner (`# LLM SERVING PROFILES -- the one-var config switch`)."""
    out = []
    lines = text.split("\n")
    for i, line in enumerate(lines, 1):
        if not line.startswith("#"):
            continue
        body = line[1:]
        if set(body.strip()) <= set("=-*# "):
            continue                       # a `# ====` rule is not a name
        key_form = re.match(r"[ \t]*([\w][\w.\-]{1,40}):\s", body)
        banner = (i > 1 and lines[i - 2].startswith("#")
                  and set(lines[i - 2][1:].strip()) <= set("=-*# ")
                  and bool(body.strip()) and set(body.strip()) > set("=-*# "))
        if key_form:
            out.append(Heading(key_form.group(1), 2, i))
        elif banner:
            out.append(Heading(re.split(r"\s[\u2014-]\s|:\s", body.strip())[0].strip(), 2, i))
    return out


# ---------------------------------------------------------------- matching

def match_candidate(cand, headings):
    """(kind or None, candidates) for one spelling of a reference."""
    cand = POSSESSIVE_RE.sub("", cand.strip())
    ck = key(cand)
    if not ck:
        return None, []
    hits = [h for h in headings if h.norm == ck or h.tail == ck]
    if hits:
        return "exact", hits
    num = sec_no(cand)
    if num:
        hits = [h for h in headings if h.num == num]
        if hits:
            return "number", hits
        hits = [h for h in headings if h.num and h.num.startswith(num + ".")]
        if hits:
            return "children", hits
        hits = [h for h in headings
                if h.num and num.startswith(h.num + ".") and h.num != num]
        if hits and all(h.num == hits[0].num for h in hits):
            return "parent", hits
    hits = [h for h in headings if h.norm.startswith(ck) or h.tail.startswith(ck)]
    if hits:
        def rest(h):
            base = h.tail if h.tail.startswith(ck) else h.norm
            return base[len(ck):]

        def inside_a_number(h):
            """Absolute rule, not a tie-break: a reference that stops inside a number label names
            a section that does not exist -- `3` is not `30 Other thing`, `9` is not `90 things`,
            and the window `Phase 0` is not `Phase 0.5 -- VPS`. It says nothing about the shorter
            windows resolve_ref retries afterwards; that is the hole self-test (h) records."""
            r = rest(h)
            return bool(r) and (r[0].isdigit() or SUBNUM_RE.match(r) is not None)

        # A LETTER boundary stays a tie-break for a reference spelled with WORDS: `\u00a7Alert` still
        # resolves `## Alerts`, and making that absolute would dangle real pointers for no reader's
        # benefit (measured: 2 of them in this corpus). A reference that is ONLY a number gets the
        # opposite rule (HD-1156): `numbered_sub` below. Where both rules are silent is the retried
        # window: `\u00a7Phase 0` loses `Phase 0` here, then resolves `Phase 0.5 -- VPS` on the unique
        # prefix `Phase`, which ends at a space rather than inside a number.
        bare_number = bool(BARE_NUM_RE.fullmatch(ck))

        def numbered_sub(h):
            """HD-1156: a BARE number must not land on a LETTERED sub-number. `\u00a71` reaching
            `1b. Why the harness does NOT go through LiteLLM` is the reported defect -- the label
            cited is a label the document does not have, and a normalized prefix called it resolved.
            Bounded to a number-only reference so the spelled-name tie-break above survives: a
            reference with words in it still gets the letter boundary."""
            r = rest(h)
            return bare_number and bool(r) and r[0].isalpha()

        hits = [h for h in hits if not inside_a_number(h) and not numbered_sub(h)]
        if not hits:
            return None, []
        # score 2 = the reference stops in the middle of a word (`\u00a7Alert` and `## Alerts`);
        # score 1 = it stops at a word boundary, which is a legitimate short citation.
        scored = [(0 if not rest(h) else 2 if rest(h)[0].isalnum() else 1, h) for h in hits]
        best = min(sc[0] for sc in scored)
        hits = [sc[1] for sc in scored if sc[0] == best]
        return "prefix", hits
    return None, []


def bare_section_ref(raw):
    """True when the reference is nothing but a section number -- the only spelling that may be read
    against the rulebook from a document that has no such section of its own."""
    return bool(BARE_NUM_RE.fullmatch(key(raw)))


def resolve_ref(ref, headings):
    """Longest token window that names a heading wins: prose trailing an anchor, and a pointer
    wrapped onto the next comment line, both degrade to the part that is a real heading.
    Returns (resolved, kind, candidates, used_text)."""
    toks = ref.split()[:8]
    used = ""
    # HD-1156 hole (i), the LETTERED half. A retried window ends at a space, so `inside_a_number()`
    # has nothing to bite on -- which is how `§Phase index 99q` reached `Phase index (true-zero
    # order)` after the full window had failed: the retry silently THREW AWAY the sub-number the
    # pointer named. So before a shorter window is allowed to stand, a dropped tail that IS a
    # lettered section number (`99q`, `1a`) must exist somewhere in the target as a section number.
    # The bare-number case stays the recorded limitation of self-test (h) -- the row keeps that
    # window green, and `§Phase 0` onto `Phase 0.5 -- VPS` is a real heading reached by a real
    # degradation, not a dropped label.
    for k in range(len(toks), 0, -1):
        used = " ".join(toks[:k]).rstrip(TRAIL_JUNK)
        if not used:
            continue
        kind, hits = match_candidate(used, headings)
        if kind is None:
            continue
        if k < len(toks):
            dropped = [tok.strip(TRAIL_JUNK) for tok in toks[k:]]
            named = [d for d in dropped if LETTERED_NUM_RE.fullmatch(d)]
            if named and not any(h.num and h.num.lower() in {n.lower() for n in named}
                                 for h in headings):
                return False, None, [], used
        return len(hits) == 1, kind, hits, used
    return False, None, [], used or ref.strip().rstrip(TRAIL_JUNK)


def clean_ref(raw):
    """The reference part of the text after a `\u00a7`: no link syntax, no sentence, no
    possessive, no range tail."""
    raw = raw.lstrip(" \t" + SECTION)
    m = REF_STOP_RE.search(raw)
    if m:
        raw = raw[:m.start()]
    raw = POSSESSIVE_RE.sub("", raw.strip())
    return raw.strip(LEAD_JUNK).rstrip(TRAIL_JUNK)


# ---------------------------------------------------------------- the scan

class Finding(object):
    __slots__ = ("path", "line", "target", "cite", "reason")

    def __init__(self, path, line, target, cite, reason):
        self.path, self.line = path, line
        self.target, self.cite, self.reason = target, cite, reason

    def __str__(self):
        return "DANGLING %-56s %s %s" % ("%s:%d -> %s %s" % (self.path, self.line, self.target,
                                                            self.cite), EMDASH, self.reason)


def scan_file(path, text, tree, notes):
    """Findings for one source file, and how many references it resolved."""
    findings = []
    refs = 0
    lines = text.split("\n")
    masked = mask_file(path, text)
    mlines = masked.split("\n")
    # A MARKDOWN document owns its own unqualified `§`-cites; an IaC comment does not (it names
    # the document beside the pointer, or the rulebook for a bare number). The old test was
    # `path.startswith("docs/")`, which made a root-level doc like CONVENTIONS.md or
    # deployment-manual.md behave like an IaC comment and read its own `§B0` against some other
    # file (HD-1156: those files were not sources at all; widening the source set without this
    # line would report their self-cites as wrong-target findings).
    is_doc = path.endswith(".md")

    # Which document an IaC comment is about: the last one named in the comment block. A real
    # code line resets it, so the context cannot leak down a 1500-line file.
    context = []
    last = None
    for raw, mline in zip(lines, mlines):
        if mline.strip():
            found = MD_PATH_RE.findall(mline)
            if found:
                last = found[-1]
        elif raw.strip():
            last = None
        context.append(last)

    for m in re.finditer(SECTION, masked):
        pos = m.start()
        line_no = masked.count("\n", 0, pos) + 1
        line_end = masked.find("\n", pos)
        line_start = masked.rfind("\n", 0, pos) + 1
        raw = clean_ref(masked[pos + 1:line_end if line_end > 0 else len(masked)])
        if not raw or raw[0] in ".,":
            notes.append("%s:%d a section sign used as the word \u00a7, not as a pointer"
                         % (path, line_no))
            continue
        before = masked[line_start:pos]
        # The owner of a `\u00a7` is the closest name that resolves: in a long table row that
        # mentions a script, a playbook and a rulebook, `CONVENTIONS \u00a76` means the rulebook.
        hinted = bool(MD_PATH_RE.findall(before) or FILE_PATH_RE.findall(before))
        target, why = None, ""
        candidates = [(len(before) - m.start(), m.group(0))
                      for m in MD_PATH_RE.finditer(before) if len(before) - m.start() <= 200]
        # A source file has no numbered sections, so `versions.yml` does NOT own the `\u00a77` in
        # "one copy lives in `versions.yml` (\u00a77)" -- that number is the rulebook's.
        if not re.match(r"^[ \t]*\d", raw):
            candidates += [(len(before) - m.start(), m.group(0))
                           for m in FILE_PATH_RE.finditer(before) if len(before) - m.start() <= 200]
        stem = STEM_BEFORE_RE.search(before[-40:])
        if stem:
            candidates.append((len(before) - stem.start(1), stem.group(1)))
        for _, hint in sorted(candidates):
            target, why = tree.doc_for_hint(hint, path)
            if target:
                break
        if target is None and hinted and not is_doc:
            findings.append(Finding(path, line_no, "(unresolved target)", SECTION + raw, why))
            continue
        if target is None:
            # In a MARKDOWN document an unqualified `§` means THIS document's own section: the
            # name-nearest rule that reads an IaC comment is wrong here, where the word before the
            # sign is prose ("...per §2"), not a document stem. (HD-1156 made the root docs and
            # `scripts/**` sources; without this ordering their self-cites were read against a
            # guessed document and every long table row reported an unresolved target.)
            if is_doc:
                target, why = path, ""
            elif context[line_no - 1]:
                target, why = tree.doc_for_hint(context[line_no - 1])
            else:
                target = None
        if target is None and not is_doc and sec_no(raw):
            target, why = CONVENTIONS, ""
            notes.append("%s:%d bare %s%s read against %s" % (path, line_no, SECTION, raw,
                                                             CONVENTIONS))
        if target is None:
            findings.append(Finding(path, line_no, "(no owning document)", SECTION + raw,
                                    "a section pointer in a comment names no document: cite "
                                    "`docs/<file>.md \u00a7Heading`"))
            continue
        if target not in tree.headings:
            findings.append(Finding(path, line_no, target, SECTION + raw, why))
            continue
        headings = tree.headings[target]
        ok, kind, hits, used = resolve_ref(raw, headings)
        # A BARE number a root-level document does not carry itself is the rulebook's number -- the
        # same reading the IaC branch above already gives an IaC comment. `AGENTS.md §6.4` means
        # `CONVENTIONS.md` §6.4, and once a root doc is a source, refusing this reading would report
        # the rulebook's own section numbers as dangling inside every file that cites them. Bounded
        # to a number-only reference whose own document has no such section, so a spelled name and a
        # number the document DOES have never leave home.
        if (not ok and target.endswith(".md") and target != CONVENTIONS
                and not target.startswith(DOC_DIR + "/") and bare_section_ref(raw)
                and CONVENTIONS in tree.headings):
            rule_ok, rule_kind, rule_hits, rule_used = resolve_ref(raw, tree.headings[CONVENTIONS])
            if rule_ok:
                target, headings = CONVENTIONS, tree.headings[CONVENTIONS]
                ok, kind, hits, used = rule_ok, rule_kind, rule_hits, rule_used
                notes.append("%s:%d bare %s read against %s, not against %s"
                             % (path, line_no, SECTION + raw, CONVENTIONS, path))
        cite = SECTION + used
        if ok:
            refs += 1
            notes.append("%s:%d %s -> %s:%d [%s]" % (path, line_no, cite, target,
                                                     hits[0].line, kind))
        elif kind == "number":
            findings.append(Finding(path, line_no, target, cite,
                                    "%s and %s both carry section number %s in %s"
                                    % (hits[0], hits[1], sec_no(raw), target)))
        elif kind == "children":
            findings.append(Finding(path, line_no, target, cite,
                                    "no section %s in %s -- only its subsections %s"
                                    % (sec_no(raw), target,
                                       " and ".join(str(h) for h in hits[:2]))))
        elif kind is None:
            reason = "no heading in %s starts with %r" % (target, used)
            if target == CONVENTIONS and not is_doc:
                reason += " (a bare numeric pointer in an IaC comment; the rulebook has no such " \
                          "section -- name the document you meant)"
            findings.append(Finding(path, line_no, target, cite, reason))
        else:
            findings.append(Finding(path, line_no, target, cite,
                                    "%s %r matches %s -- name the heading you mean"
                                    % (kind, used, " and ".join(str(h) for h in hits[:2]))))

    # decision #N / \u00a79 #N / \u00a79 row N -- over the masked text, so a citation whose number
    # wrapped onto the next line is still read as one citation
    seen = set()
    for rx in (ROW_HASH_RE, ROW_WORD_RE):
        for m in rx.finditer(masked):
            back = masked[max(0, m.start() - 70):m.start()]
            n = int(m.group(1))
            line_no = masked.count("\n", 0, m.start()) + 1
            if (path, line_no, n) in seen:
                continue
            hints = MD_PATH_RE.findall(back)
            origin = path
            if hints:
                probe, _ = tree.doc_for_hint(hints[-1], path)
                if probe:
                    origin = probe
            # "a number after a `\u00a7`" is a row citation ONLY where that section is a decision
            # log: `\u00a79 #24` is decision 24, while `\u00a76 ladder **#10` is a benchmark rung and
            # "`services-vps.md` checklist rows 3/8" is a checklist. Without this test the gate
            # would flag every numbered thing in the repo.
            if not tree.is_decision_cite(path, back, origin):
                continue
            seen.add((path, line_no, n))
            rows, table = tree.table_for(origin)
            if rows is None:
                continue
            if n in rows:
                refs += 1
                notes.append("%s:%d decision #%d -> %s row %d" % (path, line_no, n, table, n))
            else:
                findings.append(Finding(path, line_no, table, "decision #%d" % n,
                                        "not a row of the decision table (rows: %s)"
                                        % ", ".join(str(r) for r in rows)))
    return findings, refs


def check(corpus, tree, notes=None):
    findings, refs, seen = [], 0, set()
    for path in sorted(corpus):
        got, count = scan_file(path, corpus[path], tree, notes if notes is not None else [])
        for f in got:
            if (f.path, f.line, f.target, f.cite) in seen:
                continue          # one pointer is one defect, however many times it repeats
            seen.add((f.path, f.line, f.target, f.cite))
            findings.append(f)
        refs += count
    return findings, refs


# ---------------------------------------------------------------- driver

def git_files():
    # ls-files -z answers in UTF-8 with NUL separators. Without an explicit encoding a Windows host decodes it with the
    # ANSI codepage, the reader thread dies on a non-ASCII byte, and stdout arrives as None — the gate would then report
    # its own crash as a finding. The gate exports PYTHONUTF8=1 for the same reason; this is the same rule for a direct run.
    r = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        print("ERROR: git ls-files failed: %s" % r.stderr.strip(), file=sys.stderr)
        sys.exit(2)
    return [f for f in r.stdout.split("\0") if f]


def sources_and_targets(files):
    """Sources of references: docs/**.md, comments under IaC/**, every root-level .md and
    scripts/** (HD-1156). Targets: every tracked .md plus every tracked IaC and scripts file,
    because CONVENTIONS.md, todo.md, spark/**.md and a role's own comment banners are all pointed
    at by name."""
    docs = [f for f in files if f.startswith(DOC_DIR + "/") and f.endswith(".md")
            and not f.endswith(GENERATED)]
    iac = [f for f in files if f.startswith(IAC_DIR + "/") and f.endswith(IAC_EXTS)
           and not f.endswith(GENERATED)]
    scripts = [f for f in files if f.startswith("scripts/") and f.endswith((".py", ".yml",
                                                                              ".sh", ".md"))]
    # HD-1156: the source set is not `docs/` plus IaC comments. A root-level doc and a script
    # comment both write `§`-cites, and while they were not sources, every pointer written from
    # `CONVENTIONS.md`, `deployment-manual.md`, `scripts/README.md` or `todo.md` was unchecked in
    # BOTH directions — its anchor never resolved, and renaming a heading never reddened it.
    roots = [f for f in files if "/" not in f and f.endswith(".md") and not f.endswith(GENERATED)]
    targets = sorted(set(f for f in files if f.endswith(".md")) | set(iac) | set(scripts))
    return sorted(set(docs) | set(iac) | set(roots) | set(scripts)), targets


def load(paths):
    texts = {}
    for rel in paths:
        try:
            texts[rel] = (ROOT / rel).read_text(encoding="utf-8")
        except (UnicodeDecodeError, FileNotFoundError):
            pass
    return texts


# ---------------------------------------------------------------- the frozen ledger

def key_of(finding):
    """The identity of a dangling pointer: the file that writes it, the document it aims at, and
    the spelling it aims with. NOT the line number -- it moves whenever a doc grows, and a ledger
    keyed on position would report an unrelated edit above the pointer as new debt."""
    return (finding.path, finding.target, finding.cite)


def render_ledger(findings):
    """The ledger body for a population, sorted: `<count>TAB<path>TAB<target>TAB<cite>`. The count
    is how many copies of that ONE pointer dangle, so two identical pointers written in one file
    cannot be cleared by deleting one line."""
    counts = {}
    for f in findings:
        k = key_of(f)
        counts[k] = counts.get(k, 0) + 1
    return "".join("%d\t%s\t%s\t%s\n" % (n, k[0], k[1], k[2]) for k, n in sorted(counts.items()))


def parse_ledger(text):
    """`{key: count}` plus one complaint per malformed line. A line with no count or no path can
    never match a pointer, so it would be silent debt that reads as coverage: refuse instead."""
    counts, bad = {}, []
    for n, line in enumerate(text.split("\n"), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 4 or not parts[0].isdigit() or not parts[1].strip():
            bad.append("%s:%d -- want <count>TAB<path>TAB<target>TAB<cite>" % (BASELINE, n))
            continue
        key = (parts[1], parts[2], parts[3])
        counts[key] = counts.get(key, 0) + int(parts[0])
    return counts, bad


def read_ledger():
    path = ROOT / BASELINE
    if not path.is_file():
        print("ERROR: %s is missing, so the debt this gate was registered against is unknown and "
              "every pre-existing finding would read as growth. Re-derive it with --show-baseline."
              % BASELINE, file=sys.stderr)
        sys.exit(2)
    counts, bad = parse_ledger(path.read_text(encoding="utf-8"))
    if bad:
        for b in bad:
            print("ERROR: %s" % b, file=sys.stderr)
        sys.exit(2)
    return counts


def verdict(findings, ledger):
    """(growth, frozen, cleared) for a population read against the ledger. Frozen debt is green;
    a pointer the ledger does not carry reddens, and so does a ledger line whose pointer went --
    an entry that outlives the pointer it was written for exempts the next one (the discipline
    `gate/iac_identifier_allowlist.txt` states)."""
    budget = dict(ledger)
    growth, frozen = [], []
    for f in sorted(findings, key=lambda f: (f.path, f.line)):
        k = key_of(f)
        if budget.get(k, 0) > 0:
            budget[k] -= 1
            frozen.append(f)
        else:
            growth.append(f)
    cleared = [(k, n) for k, n in sorted(budget.items()) if n > 0]
    return growth, frozen, cleared


def self_test():
    """Breed the defect in a temp tree. A checker that only proves today's tree is clean proves
    nothing about the next rename."""
    root = tempfile.mkdtemp(prefix="check-doc-headings-")
    ok = True
    try:
        target_doc = ("# Target\n\n## Admission gate\n\ntext\n\n"
                      "### The GLOBAL ceiling: `spark_llm_device_hold_ceiling_bytes`\n\n"
                      "## Music\n\n### Music stack\n\n## Bench + engine selection\n")
        base = {
            "docs/target.md": target_doc,
            "docs/same.md": ("# Same\n\n## Living section\n\nSee \u00a7Living section.\n"
                             "Also \u00a7Nonexistent thing.\n\n```\n\u00a7Inside a fence\n```\n"),
            CONVENTIONS: "# Conventions\n\n## 7. Version-pin hygiene\n",
            "IaC/ansible/group_vars/x.yml": ("# Placement: docs/target.md \u00a7Admission gate\n"
                                             "#   and the ceiling \u00a7The GLOBAL ceiling\n"),
        }

        def tree_of(files):
            for rel, text in files.items():
                dest = os.path.join(root, rel)
                if os.path.dirname(dest):
                    os.makedirs(os.path.dirname(dest), exist_ok=True)
                with open(dest, "w", encoding="utf-8") as fh:
                    fh.write(text)
            return Tree(dict(files))

        def shown(findings):
            return "\n".join(str(f) for f in findings) or "(none)"

        findings = check(base, tree_of(base))[0]
        want = [f for f in findings if "Nonexistent" in str(f)]
        if len(want) == 1:
            print("  OK    (a) pointer to a missing heading FAILS -- %s" % want[0])
        else:
            print("  FAIL  (a) wanted exactly one finding for the missing heading, got:\n%s"
                  % shown(findings))
            ok = False
        if any("GLOBAL ceiling" in str(f) for f in findings) or not findings:
            print("  FAIL  (b) a unique prefix was reported as dangling: %s" % shown(findings))
            ok = False
        else:
            print("  OK    (b) prefix `The GLOBAL ceiling` resolved to the long heading")

        two = dict(base)
        two["docs/target.md"] = target_doc + "## Bench + engine limits\n"
        two["docs/two.md"] = "# Two\n\nsee [t](target.md) \u00a7Bench + engine\n"
        findings = check(two, tree_of(two))[0]
        want = [f for f in findings if "Bench + engine selection" in str(f)
                and "Bench + engine limits" in str(f)]
        if len(want) == 1:
            print("  OK    (c) a prefix matching two headings FAILS naming both -- %s" % want[0])
        else:
            print("  FAIL  (c) wanted the ambiguity caught, got:\n%s" % shown(findings))
            ok = False

        real = os.path.join(str(ROOT), CANONICAL_TABLE_DOC)
        if os.path.isfile(real):
            files = dict(base)
            files["docs/cites.md"] = "# Cites\n\nPer decision #99 nothing is decided here.\n"
            tree = tree_of(files)
            with open(real, encoding="utf-8") as fh:
                tree.texts[CANONICAL_TABLE_DOC] = fh.read()
            findings = check({"docs/cites.md": files["docs/cites.md"]}, tree)[0]
            want = [f for f in findings if "decision #99" in str(f)]
            if len(want) == 1:
                print("  OK    (d) `decision #99` FAILS against the real table -- %s" % want[0])
            else:
                print("  FAIL  (d) wanted decision #99 caught, got:\n%s" % shown(findings))
                ok = False
        else:
            print("  FAIL  (d) cannot read the real decision table at %s" % real)
            ok = False

        findings = check({"docs/same.md": base["docs/same.md"]}, tree_of(base))[0]
        if any("Inside a fence" in str(f) for f in findings):
            print("  FAIL  (e) a reference inside a code fence was reported: %s"
                  % shown(findings))
            ok = False
        else:
            print("  OK    (e) a reference inside a code fence is ignored")

        pointer = "# P\n\nsee [t](target.md) \u00a7Admission gate\n"
        before = check({"docs/pointing.md": pointer},
                       tree_of(dict(base, **{"docs/pointing.md": pointer})))[0]
        after_files = dict(base)
        after_files["docs/pointing.md"] = pointer
        after_files["docs/target.md"] = target_doc.replace(
            "## Admission gate", "## SSH admission gate -- rescue path")
        after = check({"docs/pointing.md": pointer}, tree_of(after_files))[0]
        if not before and len(after) == 1:
            print("  OK    (f) renaming the heading dangles the pointer -- %s" % after[0])
        else:
            print("  FAIL  (f) rename regression not isolated: before=%s after=%s"
                  % (shown(before), shown(after)))
            ok = False

        # (g) The style `spark/stability-test.md` and the audit reports actually write: the
        # heading carries its own section sign. `\u00a73` must reach `## \u00a73 Doing the thing`
        # and must NOT reach `## \u00a730 Other thing`.
        mark = dict(base, **{"docs/mark.md": "# Mark\n\n## \u00a73 Doing the thing\n",
                             "docs/marked.md": "# Marked\n\nsee [m](mark.md) \u00a73\n"})
        findings = check({"docs/marked.md": mark["docs/marked.md"]}, tree_of(mark))[0]
        if not findings:
            print("  OK    (g) heading `## \u00a73 Doing the thing` is resolved by `\u00a73`")
        else:
            print("  FAIL  (g) a heading that writes its own \u00a7 dangled: %s" % shown(findings))
            ok = False
        thirty = dict(mark)
        thirty["docs/mark.md"] = "# Mark\n\n## \u00a730 Other thing\n"
        findings = check({"docs/marked.md": mark["docs/marked.md"]}, tree_of(thirty))[0]
        if len(findings) == 1:
            print("  OK    (g) `\u00a73` does not match `## \u00a730 Other thing` -- %s"
                  % findings[0])
        else:
            print("  FAIL  (g) the numeric boundary is gone, `\u00a73` reached `\u00a730`: %s"
                  % shown(findings))
            ok = False

        # (h) The retried token window, in BOTH directions (HD-1156 closed the half that used to be
        # a limitation on the record). A pointer with a PROSE tail must still degrade to the heading
        # it names -- that is what makes `\u00a7Admission gate proves nothing` a legal cite and what
        # the row means by keeping the retried window green. And a pointer whose tail is a LETTERED
        # sub-number the target does not have must NOT resolve: the retry used to throw `99q` away
        # and land on `Phase index`, which is how a wrong lettered ref read as a correct one.
        prose = dict(base, **{"docs/prose.md": "# Doc\n\n## Admission gate\n\ntext\n",
                              "docs/proseref.md": "# Ref\n\nsee [p](prose.md) "
                                                  "\u00a7Admission gate proves the point\n"})
        findings = check({"docs/proseref.md": prose["docs/proseref.md"]}, tree_of(prose))[0]
        if not findings:
            print("  OK    (h) a retried window still resolves a pointer with a PROSE tail "
                  "(`\u00a7Admission gate proves the point` -> `## Admission gate`)")
        else:
            print("  FAIL  (h) the prose-tail degradation is gone: %s" % shown(findings))
            ok = False
        lettered = dict(base, **{"docs/phase.md": "# Doc\n\n## Phase index (true-zero order)\n",
                                 "docs/phaseref.md": "# Ref\n\nsee [p](phase.md) "
                                                     "\u00a7Phase index 99q\n"})
        findings = check({"docs/phaseref.md": lettered["docs/phaseref.md"]},
                         tree_of(lettered))[0]
        if len(findings) == 1:
            print("  OK    (h) a retried window may NOT drop a LETTERED sub-number the target "
                  "lacks -- %s" % findings[0])
        else:
            print("  FAIL  (h) `\u00a7Phase index 99q` still resolves by throwing `99q` away: %s"
                  % shown(findings))
            ok = False
        # The bare-number case keeps its own arm: `\u00a7Phase 0` against `Phase 0.5 -- VPS` is a
        # degradation the row keeps green, so a change to the retry has to say which half moved.
        phase = dict(base, **{"docs/phase.md": "# Doc\n\n## Phase 0.5 -- VPS "
                                              "(re-)provisioning\n",
                              "docs/phaseref.md": "# Ref\n\nsee [p](phase.md) \u00a7Phase 0\n"})
        findings = check({"docs/phaseref.md": phase["docs/phaseref.md"]}, tree_of(phase))[0]
        if not findings:
            print("  OK    (h) the kept half: `\u00a7Phase 0` still reaches `Phase 0.5 -- VPS` "
                  "through the retried window `Phase`")
        else:
            print("  FAIL  (h) the kept half moved, `\u00a7Phase 0` now dangles: %s"
                  % shown(findings))
            ok = False

        # (j) HD-1156: a BARE number must not land on a LETTERED sub-number, and the spelled-name
        # letter-internal tie-break must survive the rule that bounds it.
        bare = dict(base, **{"docs/lettered.md": "# L\n\n## 1b. Why the harness does not "
                                                "go through the gateway\n",
                             "docs/bareref.md": "# R\n\nsee [l](lettered.md) \u00a71\n",
                             "docs/nameref.md": "# R\n\nsee [t](target.md) \u00a7Admission\n"})
        findings = check({"docs/bareref.md": bare["docs/bareref.md"]}, tree_of(bare))[0]
        if len(findings) == 1:
            print("  OK    (j) `\u00a71` does NOT match `## 1b. ...` -- %s" % findings[0])
        else:
            print("  FAIL  (j) a bare number reached a lettered sub-number: %s" % shown(findings))
            ok = False
        findings = check({"docs/nameref.md": bare["docs/nameref.md"]}, tree_of(bare))[0]
        if not findings:
            print("  OK    (j) the spelled-name tie-break is intact: `\u00a7Admission` still names "
                  "`## Admission gate`")
        else:
            print("  FAIL  (j) the letter-internal tie-break for a WORD is gone: %s"
                  % shown(findings))
            ok = False

        # (k) HD-1156: the source set. A root-level document and a script comment are SOURCES now,
        # so a pointer written from either one is resolved, and renaming its heading reddens it.
        for src_name, body in ((CONVENTIONS, "# C\n\nsee [t](docs/target.md) "
                                             "\u00a7Admission gate\n"),
                               ("scripts/tool.py", "# see docs/target.md \u00a7Admission gate\n")):
            pair = dict(base, **{src_name: body})
            before = check({src_name: body}, tree_of(pair))[0]
            after_files = dict(pair)
            after_files["docs/target.md"] = target_doc.replace(
                "## Admission gate", "## Gatekeeping, renamed")
            after = check({src_name: body}, tree_of(after_files))[0]
            if not before and len(after) == 1:
                print("  OK    (k) %s is a SOURCE: its pointer resolves, and renaming the heading "
                      "dangles it" % src_name)
            else:
                print("  FAIL  (k) %s is not a source (before=%s after=%s)"
                      % (src_name, shown(before), shown(after)))
                ok = False

    finally:
        shutil.rmtree(root, ignore_errors=True)

    # (i) The ledger ratchet, in memory: frozen debt stays green, ONE new pointer reddens, a
    # pointer that went reddens its own ledger line, a copy of a repeated pointer reddens the
    # count, and the rendered ledger parses back to the population it was rendered from -- a file
    # format that drifts from the verdict is not a ledger at all.
    debt = [Finding("docs/a.md", 7, "docs/b.md", "\u00a7Gone", "x"),
            Finding("docs/a.md", 9, "docs/b.md", "\u00a7Gone", "x"),
            Finding("docs/c.md", 3, CONVENTIONS, "\u00a799", "y")]
    body = render_ledger(debt)
    ledger, bad = parse_ledger(body)
    rebuilt = [Finding(k[0], 1, k[1], k[2], "") for k, n in sorted(ledger.items())
               for _ in range(n)]
    if bad:
        print("  FAIL  (i) the rendered ledger does not parse: %s" % "; ".join(bad))
        ok = False
    elif render_ledger(rebuilt) != body:
        print("  FAIL  (i) the ledger loses a key or a count in the round-trip:\n%s\n--vs--\n%s"
              % (body, render_ledger(rebuilt)))
        ok = False
    else:
        print("  OK    (i) the ledger round-trips -- %d line(s), %d pointer(s)"
              % (body.count("\n"), len(debt)))

    growth, frozen, cleared = verdict(debt, ledger)
    if growth or cleared or len(frozen) != len(debt):
        print("  FAIL  (i) frozen debt did not stay green: growth=%s cleared=%s frozen=%d"
              % (growth, cleared, len(frozen)))
        ok = False
    else:
        print("  OK    (i) frozen debt is reported, not failed -- %d pointer(s)" % len(frozen))

    growth, frozen, cleared = verdict(debt + [Finding("docs/c.md", 4, CONVENTIONS,
                                                      "\u00a798", "new")], ledger)
    if len(growth) != 1 or cleared:
        print("  FAIL  (i) a new dangling pointer did not read as growth: growth=%s cleared=%s"
              % (growth, cleared))
        ok = False
    else:
        print("  OK    (i) one pointer the ledger does not carry is growth -- %s" % growth[0])

    growth, frozen, cleared = verdict(debt[:2], ledger)
    if growth or len(cleared) != 1 or cleared[0] != (key_of(debt[2]), 1):
        print("  FAIL  (i) a pointer that went did not redden its ledger line: growth=%s "
              "cleared=%s" % (growth, cleared))
        ok = False
    else:
        print("  OK    (i) a ledger line whose pointer is gone reddens -- %s" % (cleared[0],))

    growth, frozen, cleared = verdict([debt[0], debt[2]], ledger)
    if growth or len(cleared) != 1 or cleared[0] != (key_of(debt[1]), 1):
        print("  FAIL  (i) one copy of a repeated pointer did not redden the count: cleared=%s"
              % cleared)
        ok = False
    else:
        print("  OK    (i) a repeated pointer reddens the COUNT, not just the key -- %s"
              % (cleared[0],))

    if ok:
        print("OK: self-test -- missing heading, unique prefix, ambiguous prefix, decision row, "
              "code fence, the renamed-heading regression, a heading that carries its own "
              "\u00a7 with its numeric boundary, the token-window limitation and the ledger ratchet "
              "all behave")
        return 0
    print("FAIL: self-test -- the checker missed a bred defect")
    return 1


def main():
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="backslashreplace")
        except (AttributeError, ValueError):
            pass
    verbose = "--verbose" in sys.argv
    if "--self-test" in sys.argv:
        return self_test()
    files = git_files()
    sources, targets = sources_and_targets(files)
    tree = Tree(load(targets))
    corpus = load(sources)
    notes = []
    findings, refs = check(corpus, tree, notes)
    n_docs = len([f for f in corpus if not f.startswith(IAC_DIR + "/")])
    if "--show-baseline" in sys.argv:
        # stdout is the file body, so re-deriving is one redirect; the summary goes to stderr.
        body = render_ledger(findings)
        sys.stdout.write(body)
        print("--show-baseline: %d ledger line(s) for %d dangling pointer(s) across %d files "
              "(%d docs, %d IaC) -- replace the body of %s with this, keep its header"
              % (body.count("\n"), len(findings), len(corpus), n_docs, len(corpus) - n_docs,
                 BASELINE), file=sys.stderr)
        return 0
    print("scanned %d files (%d docs, %d IaC) for %s references; %d target documents"
          % (len(corpus), n_docs, len(corpus) - n_docs, SECTION, len(targets)))
    print("exempt as sources: *-generated.md (rendered), .json under IaC (device text), "
          "gitignored files; blanked: code fences, heredocs, block scalars, URLs")
    if verbose:
        print("resolved references, first %d:" % min(len(notes), 25))
        for note in notes[:25]:
            print("  .  %s" % note)
    growth, frozen, cleared = verdict(findings, read_ledger())
    if verbose and frozen:
        print("")
        for f in frozen:
            print("  frozen  %s" % f)
    if growth or cleared:
        print("")
        for f in growth:
            print("  NEW     %s" % f)
        for (key, n) in cleared:
            print("  CLEARED %s -> %s %s  x%d -- the pointer resolves now; delete this ledger "
                  "line (or lower its count) in the same change, or it exempts the next pointer "
                  "written here" % (key[0], key[1], key[2], n))
        print("")
        print("FAIL: %d new dangling, %d frozen in %s, %d ledger line(s) to clear"
              % (len(growth), len(frozen), BASELINE, len(cleared)))
        return 1
    print("OK: %d refs across %d files resolve; %d dangling pointer(s) frozen in %s"
          % (refs, len(corpus), len(frozen), BASELINE))
    return 0


if __name__ == "__main__":
    sys.exit(main())
