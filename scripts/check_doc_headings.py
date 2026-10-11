#!/usr/bin/env python3
"""
check_doc_headings.py -- prove every `\u00a7Section` pointer, in a doc or in an IaC comment,
names a heading that exists in the document it points at, and that a `decision #N` cites a row
that is actually in the decision table.

WHY THIS EXISTS. scripts/check_doc_path_refs.py proves the PATH half of a citation; nothing
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
  * `decision #N`, `\u00a79 #N`, `\u00a79 decisions #24/#27`, `\u00a79 row 26` -- N must be a row of
    the owning numbered decision table (a table whose header starts `| # |` and whose remaining
    cells say rule/decision). One exists today -- `docs/services-ai.md` \u00a79 -- so a
    `decision #N` written in a document without one is read against it, which is how the repo
    already reads `decision #26`.

WHAT IT IGNORES, each named by --verbose: code fences, shell heredocs and YAML block scalars --
deployed payload, not a promise to a reader (RULES R-2); `*-generated.md` as a SOURCE -- rendered
output, hand-editing it is banned, so its pointers belong to the template that wrote them;
gitignored files -- `git ls-files` never lists them; anything inside a URL; and `.json` under IaC
-- a dashboard `description` is text written to a device, not a pointer a reader follows.

--self-test breeds six shapes in a temp tree and FAILS if any is missed, including the rename that
breaks a previously-good pointer.

Exit 0 = every reference resolves; 1 = dangling references found; 2 = could not run.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SECTION = "\u00a7"          # section sign: the thing being validated, and part of the output
EMDASH = "\u2014"

DOC_DIR = "docs"
IAC_DIR = "IaC"
GENERATED = "-generated.md"
CONVENTIONS = "CONVENTIONS.md"
CANONICAL_TABLE_DOC = DOC_DIR + "/services-ai.md"
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
        self.norm = norm(text)
        self.num = sec_no(text)
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
        # A reference ends at a word, not in the middle of a number: `\u00a7Phase 0` is
        # `Phase 0 -- Management runner`, not `Phase 0.5 -- VPS (re-)provisioning`. Only a tie
        # that survives that tie-break is an ambiguity.
        def rest(h):
            base = h.tail if h.tail.startswith(ck) else h.norm
            return base[len(ck):]
        # score 2 = the reference stops in the middle of a word or a number label (`\u00a7Phase 4`
        # cannot mean `Phase 4b -- DGX Spark`); score 1 = it stops at a word boundary, which is a
        # legitimate short citation.
        scored = [(0 if not rest(h) else 2 if (rest(h)[0].isalnum() or
                  re.match(r"^[.\-]\s*\d", rest(h))) else 1, h) for h in hits]
        best = min(sc[0] for sc in scored)
        hits = [sc[1] for sc in scored if sc[0] == best]
        return "prefix", hits
    return None, []


def resolve_ref(ref, headings):
    """Longest token window that names a heading wins: prose trailing an anchor, and a pointer
    wrapped onto the next comment line, both degrade to the part that is a real heading.
    Returns (resolved, kind, candidates, used_text)."""
    toks = ref.split()[:8]
    used = ""
    for k in range(len(toks), 0, -1):
        used = " ".join(toks[:k]).rstrip(TRAIL_JUNK)
        if not used:
            continue
        kind, hits = match_candidate(used, headings)
        if kind is None:
            continue
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
    is_doc = path.startswith(DOC_DIR + "/")

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
        if target is None and hinted:
            findings.append(Finding(path, line_no, "(unresolved target)", SECTION + raw, why))
            continue
        if target is None:
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
                                    "a section pointer in an IaC comment names no document: "
                                    "cite `docs/<file>.md \u00a7Heading`"))
            continue
        if target not in tree.headings:
            findings.append(Finding(path, line_no, target, SECTION + raw, why))
            continue
        headings = tree.headings[target]
        ok, kind, hits, used = resolve_ref(raw, headings)
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
            if not (DECISION_WORD_RE.search(back) or SECTION_NUM_RE.search(back)):
                continue
            n = int(m.group(1))
            line_no = masked.count("\n", 0, m.start()) + 1
            if (path, line_no, n) in seen:
                continue
            seen.add((path, line_no, n))
            hints = MD_PATH_RE.findall(back)
            origin = path
            if hints:
                probe, _ = tree.doc_for_hint(hints[-1], path)
                if probe:
                    origin = probe
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
    r = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("ERROR: git ls-files failed: %s" % r.stderr.strip(), file=sys.stderr)
        sys.exit(2)
    return [f for f in r.stdout.split("\0") if f]


def sources_and_targets(files):
    """Sources of references: docs/**.md and comments under IaC/**. Targets: every tracked .md
    plus every tracked IaC file, because CONVENTIONS.md, todo.md, spark/**.md and a role's own
    comment banners are all pointed at by name."""
    docs = [f for f in files if f.startswith(DOC_DIR + "/") and f.endswith(".md")
            and not f.endswith(GENERATED)]
    iac = [f for f in files if f.startswith(IAC_DIR + "/") and f.endswith(IAC_EXTS)
           and not f.endswith(GENERATED)]
    scripts = [f for f in files if f.startswith("scripts/") and f.endswith((".py", ".yml",
                                                                              ".sh", ".md"))]
    targets = sorted(set(f for f in files if f.endswith(".md")) | set(iac) | set(scripts))
    return sorted(set(docs) | set(iac)), targets


def load(paths):
    texts = {}
    for rel in paths:
        try:
            texts[rel] = (ROOT / rel).read_text(encoding="utf-8")
        except (UnicodeDecodeError, FileNotFoundError):
            pass
    return texts


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
    finally:
        shutil.rmtree(root, ignore_errors=True)
    if ok:
        print("OK: self-test -- missing heading, unique prefix, ambiguous prefix, decision row, "
              "code fence, and the renamed-heading regression all behave")
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
    print("scanned %d files (%d docs, %d IaC) for %s references; %d target documents"
          % (len(corpus), n_docs, len(corpus) - n_docs, SECTION, len(targets)))
    print("exempt as sources: *-generated.md (rendered), .json under IaC (device text), "
          "gitignored files; blanked: code fences, heredocs, block scalars, URLs")
    if verbose:
        print("resolved references, first %d:" % min(len(notes), 25))
        for note in notes[:25]:
            print("  .  %s" % note)
    if findings:
        print("")
        for f in sorted(findings, key=lambda f: (f.path, f.line)):
            print("  FAIL  %s" % f)
        print("")
        print("FAIL: %d dangling" % len(findings))
        return 1
    print("OK: %d refs across %d files resolve" % (refs, len(corpus)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
