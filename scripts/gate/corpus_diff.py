#!/usr/bin/env python3
"""corpus_diff.py -- the wave-2 gate: make a string-only token purge auditable.

usage: corpus_diff.py --gate                       # the registered form, pinned to the baseline
       corpus_diff.py --gate --show-baseline        # re-derive every baseline field
       corpus_diff.py <repo> <base-ref> [<file> ... | --list <file>]    # hand-run audit
       corpus_diff.py <repo> <base-ref> <file> ... --against REV        # replay a closed window
       corpus_diff.py <repo> <base-ref> <file> ... --accept FILE        # with signed exceptions
       corpus_diff.py --keys <repo> [<path> ...]
       corpus_diff.py --self-test | --guard-self-test

--accept names a SIGNED exceptions file, one TAB-separated `<path>\t<line>\t<reason>` per
line, for the rare REJECT that is a real edit beside the purge rather than a purge. An
entry applies ONLY to a REJECT at that exact path+line, and an entry that matches nothing
is STALE and fails the run -- an exception may not outlive the edit it was signed for, the
same anti-whitelisting rule `scripts/gate/iac_identifier_allowlist.txt` lives by. The reason
must state what the edit was; "it was fine" is not a reason. The registered gate reads the
in-tree list `scripts/gate/corpus_diff_accepts.txt`, so DELETING an entry reddens the run
instead of quietly narrowing it.

--gate is the form `scripts/validate-all.sh` runs. It reads the window from the pinned baseline
`scripts/gate/corpus_baseline.txt` -- `baseline_rev` (the base end), `compare_rev` (the now end),
`scope`, and a digest of what was compared -- and replays that window, so a green verdict is a
re-derivable fact about two commits rather than about whatever a working copy looked like when
someone ran it by hand. A hand-run audit of an in-flight purge still compares a base ref against
the working copy, which is the only sensible reading of an edit that is not committed yet;
`--against REV` pins the now end to replay any closed window.

The baseline is a canary, the job `scripts/gate/twin_baseline.txt` does for the twin gate: the
population is a pure function of (baseline_rev, compare_rev, scope, this extractor), so a
narrowed scope or a moved rev changes `compared_sha256` and the run REFUSES rather than pretending
the population is still the one that was reviewed. `compare_rev..HEAD` past STALE_AFTER_COMMITS is
refused too: an ancient window measures an old wave and turns its refactors into false severs, so
re-publish at the wave tip with `--show-baseline`.

A scope that resolves to ZERO files -- no file argument that names a tracked file, an empty
--list, a directory with nothing in it -- is an ERROR and exits non-zero: a run that read
nothing must never print a green verdict.

Wave 2 removes `HD-<n>` / `KOPS-<n>` / ISO-date tokens from **string literals and
comments**: Ansible `- name:` task names, systemd `Description=`, RouterOS `comment=` /
`comment:`, `msg:`/`fail_msg`, `description:` values, `role:`/`purpose:`, Prometheus
`# HELP` text, and `#` lines inside YAML block scalars / shell heredocs. `proof.py`
books every such edit as a code change -- correctly -- so this is a second, purpose-built
gate; the four shared tools are only imported, never modified.

For every changed line the change region is located inside the line and must be CONFINED
to rendered text (a quoted string, a comment -- also a `#` line inside a block scalar or
heredoc body -- the value of a YAML key, a Python docstring body in a `*.py.j2`, or prose in
a `*.md(.j2)`) while the rest of the line stays identical character for character. So a key
name, a boolean/number indicator, a Jinja `{{ }}` / `{% %}` expression **outside its quoted
literals**, a path or URL, a shell token outside a comment, a fused identifier
(`HD-9-push.timer`), an expiry date that IS state, or the indentation -> REJECTED with
file:line and both sides quoted.

Rendered Markdown, Python docstrings and Jinja literals are *text*: they are how these files
say something, not something the machine parses. So in a `*.md(.j2)` every line is prose, in
a `*.py(.j2)` the body of a triple-quoted string is prose, and inside a `{{ ... }}` the inside
of a `'...'` / `"..."` is prose -- in all three cases the delimiters, the expression, the
condition, the filters and the indentation around it stay code and must be byte-identical.

A value that is a MATCH KEY rather than a mention of a key -- a RouterOS `find where
comment=`/`comment~` selector and the `comment=` value it selects, an Ansible `tags:` item,
a `line:`/`regexp:` pair, a whole scalar whose value is one id (`seerr_profile: HD-1080p`) --
is never purged by this gate: deleting one of those changes WHICH object is found, not what
a file says about it. `--keys <repo> [<path> ...]` lists every such site, with the construct
that makes it an identifier AND the menu path plus the selector's file:line that made it one,
for the owner to rule on; a changed line at a listed site is REJECTED.

The RouterOS join is MENU-SCOPED, because that is the only way a `find` can work: a `[find ...]`
selects rows in the menu path of the command it sits on (`/ipv6 address`, `/ip firewall filter`,
...), a bare `[find ...]` -- including one inside a `do={ ... }` body -- inherits the enclosing menu,
and a `/menu path ... add comment=` row is a key only when a selector in the SAME menu, in any
file, matches its value. Same menu + `=` (whole-string equality) is a key, same menu +
`~="^X"` (regex search, `^` anchors a prefix) is a key for a value starting with `X`, a
different menu is never a key -- `/ipv6 address remove [find where comment~"^HD-414"]` cannot
find a `/ipv6 firewall filter` row, so that row's comment is prose.

The REJECT set is TOKEN-ANCHORED. A changed line is REJECTED only when a token the BASE side
carries is GONE from the new side *and* some change region reaches outside rendered text. A line
that removes no token is INFORMATIONAL -- reported and counted, never a verdict -- because what
this gate audits is what a purge may touch, and an edit that removes no token cannot be a purge.
That anchor is what makes a window holding the ordinary development between two purge commits
auditable at all: without it every changed line in such a window owes a signed exception, and the
audit could only ever be replayed over a wave that is nothing but purges. What the anchor does NOT
relax: a line that DOES lose a token still has every one of its regions judged, so a purge that
hid by reflowing the code around it stays REJECTED, an expiry date stays protected, and a line
that mints a token while losing another is a rewrite. A MATCH KEY site is judged first, under the
other promise above: changing it edits WHICH object is found, token or not.

Accepted changes are classified and counted per file and category; every change that is more than
the bare token removal -- rewording, reordering, dropped punctuation, a Jinja literal, or no token
removal at all -- is listed for manual review, because that is where a claim can escape together
with the token.

Every REJECT describes a line the diff actually changed, and says so: `this line WAS changed by
the diff`, with both sides quoted.

The self-test has two halves. The classifier CASES are single-line pairs, so they cannot see the
payload mask -- block-scalar and heredoc bodies are exercised by the real window the gate replays,
not there. The pinned-run cases build a throwaway repo and assert the accepts list and the baseline
canary in BOTH directions, because a self-test that cannot fail is the hole this gate exists to
close; switch the REJECT branch off and the suite must print FAIL and exit 1.

Exit 0 = every change in the diff is a confined token purge, or removes no token at all (an
         informational edit, reported not judged), or is carried by a used, exact entry of the
         signed --accept exceptions list; a stale entry never lets a run pass.
Exit 1 = at least one change is REJECTED, or the signed accept list holds a stale entry.
Exit 2 = the gate could not measure: nothing was audited (no files in scope, or a scope with no
         changed line in it), or a baseline that does not describe the population it is pinned
         to, or one past STALE_AFTER_COMMITS, or a revision this clone does not have.
Wired into scripts/validate-all.sh -- the run and the self-test.
"""
import argparse, difflib, hashlib, os, re, signal, subprocess, sys, time, traceback
import contextlib, io, tempfile
from pathlib import Path

# HD-1118 Stage 1: the repo root is FOUND, never assumed from a depth -- scripts/lib/repo_root.py.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import require_corpus, root as _hl_root    # noqa: E402

ROOT = _hl_root(__file__)
BASELINE = "scripts/gate/corpus_baseline.txt"
ACCEPTS = "scripts/gate/corpus_diff_accepts.txt"
# One wave measured 176 commits (34e77f82 -> 953255b8). Past this many the pinned window is no
# longer "the current wave", which is the only window this gate is honest about -- the same cap,
# for the same reason, as scripts/gate/check_string_twins.py.
STALE_AFTER_COMMITS = 300

ID = re.compile(r"\bHD-\d+[a-z]?\b|\bKOPS-\d+[a-z]?\b")
IDSH = re.compile(r"(?:HD-\d+|KOPS-\d+)")            # an id SHAPE: `HD-414`, `HD-1080p`
DATE = re.compile(r"\b20\d\d-\d\d-\d\d\b")
TOKEN = re.compile(ID.pattern + "|" + DATE.pattern)
WORD = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9._/@:+-]*[A-Za-z0-9])?")
KEY = re.compile(r"(?m)^[ \t]{0,12}(?:-\s+)?([A-Za-z_][\w.]*)\s*:")
SEQ = re.compile(r"^[ \t]*-[ \t]+([^ \t>&*!%@`\[{])")
KV = re.compile(r"(?:^|[\s,{/])([A-Za-z][\w.]*)=")
CLOSE = {"{{": "}}", "{%": "%}", "{#": "#}"}
PATHY = re.compile(r"^(?:[\w.-]*://|~?[/.])[\w./@:+~$*()-]*$")
NUM = re.compile(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?[a-zA-Z%]*$")
BLOCKY, NULLS = "|>&*!%@`", {"true", "false", "null", "yes", "no", "on", "off", "~", ""}
# `key=` values that are prose, not a command; `name=` is absent on purpose -- in RouterOS
# it is a device interface name, so changing it changes the config
PROSE_KEYS = {"description", "documentation", "comment", "title", "tooltip", "caption",
              "text", "msg", "fail_msg", "role", "purpose", "help"}
# RULES: a date that IS state -- an expiry, a renewal -- is not changelog and must survive
STATE_DATE = re.compile(r"\b(valid_until|valid_from|valid_to|not_after|not_before|expiry"
                        r"|expires|renewal|renew_by|renew_date|due_by|deadline)\b", re.I)
# RULES: a value that IS a match key. `find where comment=...` / `comment~"^HD-414"` selects an
# object BY its comment, so the id in it is the handle; `tags: [... hd17]` is a selector a
# playbook is run with; a `line:`/`regexp:` pair selects the line to rewrite; a whole scalar
# that is one id (`seerr_profile: HD-1080p`) is a name looked up by a later task.
FIND_WHERE = re.compile(r"\bfind\s+where\b([^\]]*)")
COMMENT_SEL = re.compile(r"""comment\s*(==|!=|!~=|!~|~=?|=~|=)\s*("([^"]*)"|'([^']*)'|(\S+))""")
SEL_EQ, SEL_RE = {"=", "=="}, {"~", "~=", "=~"}      # equality | regex search
SEL_NOT = {"!=", "!~", "!~="}     # finds everything EXCEPT the match: never a value's handle
COMMENT_VAL = re.compile(r"""(?:^|[\s,{/])comment\s*=\s*("([^"]*)"|'([^']*)'|(\S+))""")
TAGS = re.compile(r"""^\s*(?:-\s+)?tags\s*:\s*(?:\[([^\]]*)\]|(.*?))\s*(?:#.*)?$""")
LOWER_ID = re.compile(r"^(?:hd[-_]?\d+[a-z]?|kops[-_]?\d+[a-z]?)$", re.I)
SCALAR_KEY = re.compile(r"^(?:[A-Za-z]+[-_])?(?:HD|KOPS)[-_]?\d+[A-Za-z0-9]*$", re.I)
SCALAR_ID = re.compile(r"""^[ \t]{0,14}[A-Za-z_][\w.]*:\s*["']?(\S+?)["']?[ \t]*(?:#.*)?$""")
MODULE_KEY = re.compile(r"""^\s*(?:-\s+)?(line|regexp|insertafter|insertbefore)\s*:\s*(.*?)\s*$""")
COMPARE = re.compile(r"""(?:[=!]=|=~|!~|\bnot in\b|\bin\b|matches)\s*(["'])((?:(?!\1).)+)\1""")
LINE_MODULE = re.compile(r"\blineinfile\b|\b(?:ansible\.builtin\.)?replace\s*:")
JINJA_OUT = re.compile(r"\{\{.*?\}\}|\{%.*?%\}|\{#.*?#\}", re.S)
# RouterOS menu scope: a `[find ...]` can only reach rows in the menu its command sits in, so the
# menu path is half of the key join. A path is `/word word ...` and ends at a command verb, at a
# `key=` parameter, at a `[`, or at the end of the text.
RSC_VERB = {"add", "remove", "set", "unset", "print", "find", "find-only", "get", "export",
            "import", "move", "copy", "paste", "edit", "enable", "disable", "make", "start",
            "stop", "restart", "run", "reset", "join", "reg-add", "where"}
RSC_WORD = re.compile(r"[A-Za-z][\w.-]*")
RSC_SLASH = re.compile(r"(?:(?<=\A)|(?<=[ \t([{'\"]))(/)")
RSC_BARE = re.compile(r"^[ \t]*(/\w[\w ./-]*\w|/\w+)[\s\\]*$")   # the whole line is a menu path
HOLE = "\x01"                          # what a Jinja expression renders to: unknown, not empty
HOLE_RX = re.compile(r"\{\{.*?\}\}|\{%.*?%\}", re.S)

# payload_regions: the block-scalar + heredoc mask, ported with the tool because it was the tool's
# one external dependency. The sequence-item `SEQ` above is a different question and is
# deliberately NOT redefined here.
PAYLOAD_MAP = re.compile(r'^([^#]*?):\s*[|>][-+0-9]*\s*(?:#.*)?$')
PAYLOAD_SEQ = re.compile(r'^\s*-\s+[|>][-+0-9]*\s*(?:#.*)?$')
HEREDOC = re.compile(r"<<-?\s*[\"']?([A-Za-z_]\w*)[\"']?")


def _payload_end(line, lines, i):
    """-> the first line after the indented block that starts at line `i`."""
    ind = len(line) - len(line.lstrip(' \t'))
    j = i + 1
    while j < len(lines):
        if lines[j].strip() and len(lines[j]) - len(lines[j].lstrip(' \t')) <= ind:
            break
        j += 1
    return j


def payload_regions(text):
    """-> [(start, end)] the line ranges that are PAYLOAD: a YAML block-scalar body or a shell
    heredoc body. Inside a payload a `#` line is something the file SAYS rather than code, which
    is what makes a purge there auditable at all."""
    lines, out, i = text.split('\n'), [], 0
    while i < len(lines):
        line, s = lines[i], lines[i].strip()
        if s and ((PAYLOAD_MAP.match(line) and not s.startswith('- ')) or PAYLOAD_SEQ.match(line)):
            j = _payload_end(line, lines, i)
            out.append((i + 1, j))
            i = j
            continue
        h = HEREDOC.search(line)
        if h and s and not s.startswith('#'):
            delim, j, n = h.group(1), i + 1, 0
            while j < len(lines) and n < 5000:
                if lines[j].strip() in (delim, '-' + delim):
                    break
                j += 1
                n += 1
            out.append((i + 1, min(j, len(lines))))
            i = j + 1
            continue
        i += 1
    return out


def jinja_out(s):
    """A Jinja expression renders to something the reader cannot see from the source, so a
    literal comparison treats every `{{ }}` / `{% %}` as a wildcard-sized hole."""
    return JINJA_OUT.sub("", s).strip()


def rsc_code(line):
    """-> the line with its trailing `#` comment cut off: a menu path written in prose is not the
    menu a command runs in."""
    for i, c in enumerate(line):
        if c == "#" and (i == 0 or line[i - 1] in " \t"):
            return line[:i]
    return line


def quoted_mask(s):
    """-> per-char True inside a `"..."` / `'...'` literal: a `/` inside a value (`KNXnet/IP tunnel`)
    is data, never the start of a menu path."""
    out, q = [False] * len(s), None
    for i, c in enumerate(s):
        if q:
            out[i] = True
            if c == q:
                q = None
        elif c in "\"'":
            q = c
    return out


def norm_menu(toks):
    """-> one spelling for one menu: `/ip/firewall/filter` and `/ip  firewall filter` are the same
    place to look, so a selector in one spelling finds a row written in the other."""
    return "/" + " ".join(w for w in "/".join(t.lower() for t in toks).split("/"))


def rsc_path(text, i, bare=False):
    """-> (menu, end) for the RouterOS command path at text[i] == '/'. `bare` says the path IS the
    whole line (`/ipv6 firewall filter` alone = select that menu), so no verb is needed; otherwise
    a run of words that never reaches a verb is prose (`docs/network-vlans.md`), not a menu."""
    j, toks, verb, n = i + 1, [], False, len(text)
    while j < n:
        m = RSC_WORD.match(text, j)
        if not m:
            break
        j = m.end()
        if m.group(0).lower() in RSC_VERB:
            verb = True
            break
        if re.match(r"[ \t]*=", text[j:]):                    # `key=`: a parameter, not a menu
            break
        toks.append(m.group(0))
        gap = re.match(r"(?:[ \t]+|/)", text[j:])
        if not gap:
            break
        j += gap.end()
    return (norm_menu(toks) if toks and (verb or bare) else "", j)


def menu_of(text, bare=False):
    """-> the menu path of the LAST RouterOS command path in `text`, '' if it holds none. The
    caller cuts the text at the command it cares about, so `last` = the one that owns it."""
    mask, out = quoted_mask(text), ""
    for m in RSC_SLASH.finditer(text):
        if mask[m.start()]:
            continue
        menu, _ = rsc_path(text, m.start(), bare)
        if menu:
            out = menu
    return out


def rsc_menus(lines, context=True):
    """-> per line, the menu a BARE `add` / `set` / `[find ...]` on it runs in: a bare `/menu path`
    line selects the menu for every line that follows it -- how these scripts are written -- and a
    `\\` continuation stays on the menu of the command it belongs to. `context=False` (prose
    quoting a script) carries nothing from one line to the next."""
    code = [rsc_code(l) for l in lines]
    if not context:                       # a quote in a *.md: only a path on the line itself
        return [menu_of(c, bool(RSC_BARE.match(c))) for c in code]
    out, ctx, keep = [], "", None
    for c in code:
        bare = bool(RSC_BARE.match(c))
        here = menu_of(c, bare)           # the path THIS line spells for itself
        menu = here or (keep if keep is not None else ctx)
        out.append(menu)
        if here:      # K3/F-2: a `/menu path ... verb ...` COMMAND line selects the menu for
            ctx = here                    # the lines after it too, not only a bare path line,
                                          # so a `do={ ... }` body hanging off a command keys
        keep = menu if c.rstrip().endswith("\\") else None
    return out


def menu_at(code, menus, i, pos, verb=""):
    """-> the menu a `[find ...]` or a `comment=` at code[pos] runs in: the path written before it on
    the line, else the menu the line inherits. `verb` is the keyword the cut left behind -- `find`
    -- so `/ip firewall filter <find> where ...` still reads as that menu."""
    return menu_of(code[:pos] + verb) or menus[i]


def render(s):
    """-> a value as the device sees it: quotes gone and every Jinja expression replaced by ONE
    hole rather than erased, so `"HD-326 kids drop: {{ h.name }}"` still has to line up with a
    selector that says the same thing."""
    return HOLE_RX.sub(HOLE, s).strip().strip("\"'")


def sel_matches(op, pat, val):
    """-> True when `find where comment<op><pat>` finds the row whose `comment=` value is `val`.
    `=` / `==` are whole-string equality, `~` / `~=` are an unanchored regex SEARCH so a leading
    `^` anchors a prefix, and `!=` / `!~` select everything but the match, so they are never what
    makes a value a handle. A hole on either side stands for whatever that renders to."""
    if op in SEL_NOT:
        return False
    wild = r"[\s\S]*?"
    if op in SEL_RE:
        try:
            return re.compile(pat.replace(HOLE, wild)).search(val) is not None
        except re.error:            # not a valid regexp after all: compare it as plain text
            esc = re.escape(pat.lstrip("^")).replace(re.escape(HOLE), wild)
            return re.compile(esc).search(val) is not None
    return re.compile(re.escape(pat).replace(re.escape(HOLE), wild)).fullmatch(val) is not None


def selector_ops(clause):
    """-> [(op, pattern, shown)] for the `comment` operands of one RouterOS `find where` clause:
    `op` is `=` / `==` / `~` / `~=` / `!=` / `!~`, `pattern` is the operand with its quotes gone
    and every `{{ ... }}` replaced by one HOLE (its rendered value is unknown here), `shown` is
    the operand as written, for the report."""
    out = []
    for m in COMMENT_SEL.finditer(clause):
        raw = next((g for g in m.groups()[2:] if g), "")
        shown = raw.strip("\"'")
        if len(shown.strip()) >= 4:                 # `=\"\"` and other debris select nothing
            out.append((m.group(1), render(raw), shown))
    return out


def key_sites(rel, lines, selectors):
    """-> {lineno: {family, why, tok, menu, sel}} -- every value in this file that is a MATCH KEY
    rather than a mention. `selectors` is the corpus-wide
    [(file, lineno, menu, op, pattern, shown)] a `find where` matches on: a `comment=` written
    here is the handle a delta script elsewhere selects by, but only if that selector sits in the
    SAME menu path -- a `find` cannot reach into another menu."""
    out, rsc = {}, bool(re.search(r"\.rsc(\.j2)?$", rel))
    yml = bool(re.search(r"\.(ya?ml)(\.j2)?$", rel))
    menus = rsc_menus(lines, True) if rsc else [""] * len(lines)
    for i, line in enumerate(lines, 1):
        code = rsc_code(line) if rsc else line
        kinds = scan_line(line, yml)[0]                           # "not a comment" for compare
        for m in FIND_WHERE.finditer(code):                       # the selector itself
            for op, pat, shown in selector_ops(m.group(1)):
                if IDSH.search(shown) or LOWER_ID.match(shown.strip('"\'')):
                    fmenu = menu_at(code, menus, i - 1, m.start(), "find")
                    out.setdefault(i, {"family": "find-where", "menu": fmenu,
                                       "sel": f"{rel}:{i}", "tok": shown,
                                       # K3/F-3: name the menu and the selector site, like the
                                       # comment-key reason already does -- a pattern alone
                                       # makes a REJECT unreadable away from this file
                                       "why": f"RouterOS `find where` ({op}) in "
                                              f"{fmenu or '(no RouterOS menu)'} selects BY this "
                                              f"comment ({shown[:60]!r}) "
                                              f"(selector {rel}:{i})"})
        if rsc:                                                   # the value it selects
            for m in COMMENT_VAL.finditer(code):
                v = render(next((g for g in m.groups()[1:] if g), ""))
                if not IDSH.search(v):
                    continue
                menu = menu_at(code, menus, i - 1, m.start())
                for f, ln, smenu, op, pat, shown in selectors:    # a selector in any file
                    if menu and smenu == menu and sel_matches(op, pat, v):
                        out.setdefault(i, {"family": "comment-key", "menu": menu,
                                           "sel": f"{f}:{ln}", "tok": IDSH.search(v).group(0),
                                           "why": f"comment= value a RouterOS selector in "
                                                  f"{smenu} matches on "
                                                  f"({f}:{ln} uses {shown[:45]!r})"})
                        break
        m = TAGS.match(line)                                      # --tags <item>
        if m:
            for it in (m.group(1) or m.group(2) or "").split(","):
                it = jinja_out(it.strip().strip('"\''))
                if it and (LOWER_ID.match(it) or IDSH.fullmatch(it)):
                    out.setdefault(i, {"family": "tags", "menu": "", "sel": "", "tok": it,
                                       "why": f"Ansible `tags:` item {it!r} -- a playbook is "
                                              f"RUN with --tags {it}"})
                    break
        if yml and MODULE_KEY.match(line):                        # the line a task rewrites
            key, val = MODULE_KEY.match(line).groups()
            val = jinja_out(val.strip('"\''))
            near = "\n".join(lines[max(0, i - 17):i - 1])
            if IDSH.search(val) and (key == "regexp" or LINE_MODULE.search(near)):
                out.setdefault(i, {"family": "line/regexp", "menu": "", "sel": "", "tok": val,
                                   "why": f"Ansible `{key}:` value selects the line to "
                                          f"rewrite ({val[:45]!r})"})
        m = SCALAR_ID.match(line)                                 # `seerr_profile: HD-1080p`
        if m and SCALAR_KEY.match(m.group(1)) and IDSH.search(m.group(1)):
            out.setdefault(i, {"family": "whole-scalar", "menu": "", "sel": "", "tok": m.group(1),
                               "why": f"the whole value of this key IS one id -- a name "
                                      f"another task looks up ({m.group(1)})"})
        for m in COMPARE.finditer(line):                          # `x == "HD-9"` tests on it
            v = jinja_out(m.group(2))
            if IDSH.search(v) and kinds[m.start()] in "cj":
                out.setdefault(i, {"family": "compare", "menu": "", "sel": "", "tok": v,
                                   "why": f"a string compared for equality is the value the "
                                          f"code tests ({v[:45]!r})"})
    return out


CATS = [("# HELP", re.compile(r"""^\s*["']?\s*#\s*HELP\b""")),
        ("task-name", re.compile(r"^\s*(?:-\s+)?name\s*[:=]")),
        ("Description=", re.compile(r"(?:^|\s)Description\s*=")),
        ("comment=", re.compile(r"""(?:^|[\s,{/])["']?comment["']?\s*[:=]""")),
        ("msg/fail_msg", re.compile(r"^\s*(?:-\s+)?(?:fail_)?msg\s*[:=]")),
        ("description:", re.compile(r"""(?:^|[\s,{])["']?description["']?\s*[:=]""")),
        ("role/purpose", re.compile(r"^\s*(?:-\s+)?(?:role|purpose)\s*[:=]"))]


def jinja_span(line, i):
    """-> (end, kinds-full-length) for the Jinja block that opens at line[i]. In a `{{ ... }}`
    expression the INSIDE of a quoted literal is rendered text ("t") and everything else --
    braces, condition, filters, pipes -- is code ("j"); a `{% ... %}` tag is code throughout,
    because a string there is compared or assigned, not rendered. A purge confined to a
    literal changes what the expression RENDERS and nothing else, so it is text; a purge in
    the condition or in a filter argument (`default(8)`) is code. Unterminated braces never
    close, so a missing `}}` can never be blamed on a quote."""
    n, close, tag, j, q, start, lits, end = len(line), CLOSE[line[i:i + 2]], line[i:i + 2], i + 2, None, 0, [], len(line)
    while j < n:
        c = line[j]
        if q:
            if c == "\\" and j + 1 < n:
                j += 2
                continue
            if c == q:
                lits.append((start, j + 1))
                q = None
            j += 1
            continue
        if line[j:j + len(close)] == close:
            end = j + len(close)
            break
        if c in "\"'":
            q, start = c, j
        j += 1
    k = ["c"] * n
    k[i:end] = ["j"] * (end - i)
    if tag == "{{":
        for a, b in lits:
            k[a:b] = ["t"] * (b - a)
    return end, k


def triple_at(line, i):
    """-> the Python triple-quote delimiter opening at line[i] (`r\"\"\"` included), or None."""
    for p in ("", "r", "u", "b", "f", "rb", "br", "fr", "rf", "R", "U", "B", "F"):
        if line.startswith(p, i):
            j = i + len(p)
            for d in ('"""', "'''"):
                if line.startswith(d, j):
                    return p + d
    return None


def scan_line(line, prose=False, slash=False, py=False, md=False, doc=None):
    """-> (kinds, val, doc): kinds[i] labels char i -- c=code, s=string, m=comment, j=jinja,
    t=text inside a Jinja literal -- and val is where this line's YAML scalar value begins
    (None if there is none). doc is the triple-quote delimiter this line STARTS inside, or
    None, and the returned doc is the delimiter the NEXT line starts inside: a module
    docstring is prose on every one of its lines, its quotes stay code. prose=True for
    YAML-shaped files, where a line that parses as no syntax at all is a continuation of a
    multi-line scalar and is therefore rendered text too; slash=True for River/HuJSON, whose
    comment marker is `//`; py=True for a Python file / template, which adds the triple-quote
    state machine; md=True for Markdown, whose every line is prose bar the Jinja spans."""
    n, k, q, i, val = len(line), ["c"] * len(line), None, 0, None
    while i < n:
        c, t = line[i], line[i:i + 2]
        if t in CLOSE:                                           # Jinja / Jinja comment
            if t == "{#":
                j = line.find("#}", i + 2)
                j = n - 1 if j < 0 else j + 1                    # unterminated = to EOL
                k[i:j + 1] = ["m"] * (j - i + 1)
                i = j + 1
                continue
            e, jk = jinja_span(line, i)                          # rule 1: literals are text
            k[i:e] = jk[i:e]
            i = e
            continue
        if doc:                                                  # inside a triple-quoted body
            if line.startswith(doc, i):
                k[i:i + 3] = ["c"] * 3                           # the closing quotes are code
                i, doc = i + 3, None
                continue
            if c == "\\" and i + 1 < n:
                k[i:i + 2] = ["s"] * 2
                i += 2
                continue
            k[i] = "s"                                           # docstring body = prose
            i += 1
            continue
        if q:                                                    # inside a quoted string
            k[i] = "s"
            if c == "\\" and q == '"' and i + 1 < n:
                k[i + 1] = "s"; i += 2; continue
            q = None if c == q else q
            i += 1
            continue
        if c == "#" and (i == 0 or line[i - 1] in " \t"):         # comment runs to EOL
            k[i:n] = ["m"] * (n - i)
            break
        if slash and t == "//":                                          # River/HuJSON
            k[i:n] = ["m"] * (n - i)
            break
        if py:
            d = triple_at(line, i)                               # `"""` / `r'''` opens a docstring
            if d:
                k[i:i + len(d)] = ["c"] * len(d)                 # the quotes themselves are code
                i, doc = i + len(d), d[-3:]
                continue
        if c in "\"'":
            q, k[i] = c, "s"
            i += 1
            continue
        i += 1
    keyed = [m for m in KEY.finditer(line) if k[m.start(1)] == "c"]
    vstart = None
    if keyed:                                          # `key: <scalar>` = text
        vstart = keyed[0].end()
        j = vstart + len(re.match(r"[ \t]*", line[vstart:]).group(0))
        if j < n and line[j] not in BLOCKY and k[j] == "c":
            val = j                                    # `key: |` is syntax
    else:
        m = SEQ.match(line)
        if m:                                          # `- <scalar>` = text too
            val = vstart = m.end() - len(m.group(1))
    if val is not None:                                # the scalar and its gap are text
        k[min(vstart, val):n] = ["s" if c == "c" else c for c in k[min(vstart, val):n]]
    kvs = list(KV.finditer(line))                         # `Description=...`, `comment=...`
    for i, m in enumerate(kvs):        # a prose value runs to the next `key=` or EOL
        if m.group(1).lower() in PROSE_KEYS and k[m.start(1)] == "c":
            stop = kvs[i + 1].start(1) if i + 1 < len(kvs) else n
            k[m.end():stop] = ["s" if c == "c" else c for c in k[m.end():stop]]
    if val is None and not kvs and prose and not keyed and line.strip():
        k[:] = ["s" if c == "c" else c for c in k]      # scalar continuation line
    if md:
        k[:] = ["s" if c == "c" else c for c in k]      # Markdown body is prose; Jinja stays
    return k, val, doc


def text_only(s):
    """Drop ids/dates and the punctuation debris they leave; keep every other word."""
    t = ID.sub(" ", DATE.sub(" ", s))
    t = re.sub(r"\(\s*\)|\[\s*\]|\{\s*\}", " ", t)               # now-empty groups
    t = re.sub(r"(?:\s*[-\u2013\u2014:,/]\s*){2,}", " ", t)                # "HD-1 - - HD-2"
    t = re.sub(r"(?:^\s*|[^A-Za-z0-9])[-\u2013\u2014:,]\s+", " ", " " + t)  # "HD-1: foo"
    t = re.sub(r"\s*[-\u2013\u2014:,]\s*$", " ", t)
    return re.sub(r"\s+", " ", t).strip(" .;,").lower()


def words(s):
    """The words left after ids/dates and their debris are gone -- the identity of a label."""
    return WORD.findall(text_only(s))


def skeleton(s):
    """Punctuation only: same words but a different skeleton = re-punctuated, not purged."""
    return re.sub(r"[\s\w./@:+-]", "", text_only(s))


def lit(x, y):
    """Both sides bare indicators/numbers (`true`->`false`, `8`->`6`): a value, not prose."""
    bare = lambda s: s.strip().lower() in NULLS or bool(NUM.match(s.strip()))
    return bare(x) and bare(y)


def pathy(line, i1, i2):
    """True when the changed span sits inside a path/URL-shaped word."""
    lo, hi = i1, i2
    while lo and line[lo - 1] not in " \t\"',;=((": lo -= 1
    while hi < len(line) and line[hi] not in " \t\"',;)": hi += 1
    return bool(PATHY.match(line[lo:hi]))


def fused(a, i1, i2):
    """True when the removed text is welded into a longer word (`HD-368-rewritten`,
    `x-HD-9-name`): deleting it edits an identifier, not a mention of one."""
    return ((i2 + 1 < len(a) and a[i2] == "-" and a[i2 + 1].isalnum())
            or (i1 >= 2 and a[i1 - 1] == "-" and a[i1 - 2].isalnum()))


def classify(line, in_payload):
    if in_payload:
        return "payload-comment" if re.match(r"^\s*(\{?#|//)", line) else "payload-body"
    for name, rx in CATS:
        if rx.search(line):
            return name
    return "comment" if re.match(r"^\s*(\{?#|//)", line) else "string-other"


def corpus_selectors(texts):
    """-> [(file, lineno, menu, op, pattern, shown)] for every RouterOS `find where comment`
    selector in the corpus, WITH the menu path it selects from -- a `find` only ever reaches rows
    in its own menu, so the menu is half of what a `comment=` value must match. A `comment=`
    written in one file is the handle a delta script in ANOTHER file selects by, so this join
    cannot be made file by file."""
    out = []
    for rel, text in sorted(texts.items()):
        lines = text.split("\n")
        rsc = bool(re.search(r"\.rsc(\.j2)?$", rel))
        menus = rsc_menus(lines, rsc)
        for i, line in enumerate(lines, 1):
            code = rsc_code(line) if rsc else line          # a `#` comment is not a menu path
            for m in FIND_WHERE.finditer(code):
                for op, pat, shown in selector_ops(m.group(1)):
                    out.append((rel, i, menu_at(code, menus, i - 1, m.start(), "find"),
                                op, pat, shown))
    return out


CHANGED = "; this line WAS changed by the diff (base -> new, both sides quoted below)"


def audit_line(a, b, in_payload, yamlish=False, slash=False, py=False, md=False,
               doca=None, docb=None, key=None):
    """One changed line -> (accepted record | None, reject reason | None).

    The REJECT set is TOKEN-ANCHORED. A changed line REJECTs only when a token the BASE side
    carries is GONE from the NEW side *and* some change region reaches outside rendered text. A
    line that removes no token is INFORMATIONAL and can never be a REJECT: what this gate promises
    is that a string-only token purge may not touch anything but rendered text, so an ordinary edit
    that removes no token is outside the promise -- and without that rule no window containing the
    development between two purge commits could be audited at all.

    What the anchor does NOT relax: every region of a line that DOES lose a token is still judged,
    so a purge that hid by reflowing the code around it stays RED, an expiry date stays protected,
    and a line that gains a token while losing another is a rewrite, not a purge. A MATCH KEY site
    is the one exception and is judged first, because it rests on a different promise: changing it
    edits WHICH object a selector finds, token or not (`--keys` is that ledger).
    """
    if key:
        side = ("the base side carries the match key and the new side removes it"
                if IDSH.search(a) and not IDSH.search(b) else
                "the id-shaped text is on both sides, so this is a rewrite of the key itself")
        return None, ("this value is a MATCH KEY, not a mention: " + key +
                      " -- deleting an id here changes WHICH object is found; " + side)
    gone = [t for t in TOKEN.findall(a) if t not in TOKEN.findall(b)]
    added_t = [t for t in dict.fromkeys(TOKEN.findall(b)) if t not in TOKEN.findall(a)]
    if not gone:
        # No token left this line, so there is nothing here a purge could have done and nothing to
        # judge -- the edit is reported for the reviewer's eye, never as a verdict. `added_t` keeps
        # the one shape worth a shout: a line that MINTS a token is not a purge either.
        return {"cat": classify(a, in_payload), "a": a, "b": b, "info": True, "ids": 0, "dates": 0,
                "why": ["no HD-/KOPS-/date token left this line -- an edit, not a purge, so this "
                        "gate renders no verdict on it"
                        + (f"; {' '.join(added_t)} was ADDED here, which no purge does"
                           if added_t else "")]}, None
    if re.match(r"[ \t]*", a).group(0) != re.match(r"[ \t]*", b).group(0):
        return None, "indentation changed"
    if added_t:
        return None, ("an id/date token was added here (" + " ".join(added_t) +
                      ") while another was removed -- a purge removes tokens, it does not mint one")
    ka, va, _ = scan_line(a, yamlish, slash, py, md, doca)
    kb, _, _ = scan_line(b, yamlish, slash, py, md, docb)
    # the characters that are NOT rendered text must be identical, or the parse moved
    nontext = ["".join(ch for ch, d in zip(t, k) if d not in "smt").rstrip()
               for t, k in ((a, ka), (b, kb))]
    if nontext[0] != nontext[1]:
        return None, ("the syntax of the line itself changed: "
                      f"{nontext[0][:70]!r} != {nontext[1][:70]!r}")
    lit_val = va is not None and va < len(b) and lit(a[va:], b[va:])   # value is a literal
    if [t for t in gone if DATE.match(t)] and STATE_DATE.search(a):
        return None, "this date IS state (expiry/renewal) -- RULES keeps it"
    # where this line's scalar value ends (before any trailing comment), if it has one
    vend = len(a.rstrip())
    if va is not None:
        vend = next((x for x in range(va, len(a)) if ka[x] == "m"), len(a.rstrip()))
    spans = [(i1, i2) for op, i1, i2, j1, j2
             in difflib.SequenceMatcher(None, a, b).get_opcodes() if op != "equal"]
    bad = []
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b).get_opcodes():
        if op == "equal":
            continue
        if op == "insert":                        # nothing may be added; judge by context
            if all(kb[x] in "smt" for x in range(max(j1 - 1, 0), min(j1 + 1, len(b)))):
                continue
            bad.append("text inserted outside a string/comment")
            continue
        seg, kind = a[i1:i2], ka[min(i1, len(ka) - 1)]
        if kind == "j":
            bad.append("a Jinja {{ }} / {% %} expression changed")
        elif kind == "c":
            bad.append("the change sits in code (key, indicator, bare value or shell token)")
        elif kind in "st" and pathy(a, i1, i2):
            bad.append("the change sits inside a path/URL")
        if fused(a, i1, i2):
            bad.append("the token is part of a longer word (an identifier), not a mention")
        if lit_val and kind in "cs":
            bad.append("an indicator/number value changed, not text")
        if va is not None and i1 <= va and i2 >= vend and len(seg.split()) <= 1:
            bad.append("the whole value of this key changed, not a token inside it")
    if bad:
        return None, "; ".join(dict.fromkeys(bad))
    wa, wb = words(a), words(b)
    extra = [w for w in wb if w not in wa]
    if extra:
        return None, "text was added that is not in the base line: " + " ".join(extra[:6])
    why = []
    if wa != wb:
        lost = [w for w in wa if w not in wb]
        why.append("more than a token removal (reworded/reordered)" +
                   (", prose gone: " + " ".join(lost[:8]) if lost else ""))
    elif skeleton(a) != skeleton(b):
        why.append("punctuation changed around the removed token")
    if in_payload and not re.match(r"^\s*\{?#", a):
        why.append("payload body line -- this text is deployed, not just read")
    in_jinja = any(ka[x] == "t" for i1, i2 in spans for x in range(i1, max(i1, i2)))
    if in_jinja:
        why.append("id removed INSIDE a Jinja expression's quoted literal -- the expression, its "
                   "condition and its filters are byte-identical, only what it renders changed")
    ids = len([t for t in gone if ID.match(t)])
    cat = "jinja-string" if in_jinja else classify(a, in_payload)
    return {"cat": cat, "a": a, "b": b, "why": why,
            "ids": ids, "dates": len(gone) - ids}, None


def py_docstate(lines, py):
    """-> for each line, the triple-quote delimiter that line STARTS inside (None on the outside).
    A docstring body is a single string spanning lines, so its text cannot be judged line by
    line; the returned state per line lets audit_text hand each line its own context."""
    out, doc = [], None
    for line in lines:
        out.append(doc)
        if py:
            doc = scan_line(line, False, False, True, False, doc)[2]
    return out


def audit_text(base, new, rel="", selectors=()):
    """-> (accepted {line: record}, rejected {line: (reason, base, new)}) for two texts."""
    bl, nl = base.split("\n"), new.split("\n")
    yamlish = bool(re.search(r"\.(ya?ml)(\.j2)?$", rel))
    slash = bool(re.search(r"\.(river|hujson)(\.j2)?$", rel))
    py, md = bool(re.search(r"\.py(\.j2)?$", rel)), bool(re.search(r"\.md(\.j2)?$", rel))
    acc, rej = {}, {}
    if len(bl) != len(nl):                             # a line appeared or vanished
        rng = lambda x, y: f"{x + 1}" if y <= x + 1 else f"{x + 1}-{y}"
        for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, bl, nl).get_opcodes():
            if op != "equal" and (i2 - i1) != (j2 - j1):
                rej[i1 + 1] = (f"lines were added or removed ({op}) -- a purge never adds or "
                               f"drops a line: base {rng(i1, i2)} -{i2 - i1} / new {rng(j1, j2)} +{j2 - j1}"
                               + CHANGED,
                               "\n".join(bl[i1:i2]), "\n".join(nl[j1:j2]))
        return acc, rej
    payload = set(x for s, e in payload_regions(base) for x in range(s, e))
    keys = key_sites(rel, bl, selectors)
    doca, docb = py_docstate(bl, py), py_docstate(nl, py)
    for i, (a, b) in enumerate(zip(bl, nl)):
        if a == b:
            continue
        try:                                        # an unauditable line is never hidden
            rec, why = audit_line(a, b, i in payload, yamlish, slash, py, md, doca[i], docb[i],
                                  keys[i + 1]["why"] if i + 1 in keys else None)
        except Exception as exc:
            rec, why = None, "could not analyse this line (" + exc.__class__.__name__ + ")"
        if why:
            # a REJECT can only describe a line the diff touched: say so instead of letting the
            # reader infer it from where this was called
            rej[i + 1] = (why + CHANGED, a, b)
        elif rec:
            acc[i + 1] = rec
    return acc, rej


def git_text(repo, ref, rel, now_ref=None):
    """-> ((base_text, now_text) | None, error | None). The NOW side is the working copy, or the
    `now_ref` revision when a closed window is replayed -- the form `--gate` runs. A path the base
    ref does not have stays an error rather than an empty text: a purge never adds a file."""
    try:
        raw = subprocess.run(["git", "-C", repo, "show", f"{ref}:{rel}"],
                             capture_output=True, check=True).stdout
    except subprocess.CalledProcessError:
        return None, "not in base ref"
    if now_ref is None:
        if not os.path.exists(os.path.join(repo, rel)):
            return None, "missing in worktree"
        now = open(os.path.join(repo, rel), "rb").read()
    else:
        got = subprocess.run(["git", "-C", repo, "show", f"{now_ref}:{rel}"], capture_output=True)
        if got.returncode:
            return None, f"missing at {now_ref}"
        now = got.stdout
    if b"\0" in raw or b"\0" in now:
        return None, "unchanged binary" if raw == now else "binary file changed -- not auditable"
    return (raw.decode("utf-8", "surrogateescape"), now.decode("utf-8", "surrogateescape")), None


def expand(repo, args, listfile):
    out = [p.strip() for p in open(listfile)] if listfile else []
    for a in args:
        if os.path.isdir(os.path.join(repo, a)):       # a directory = every tracked file in it
            out += [p for p in subprocess.run(["git", "-C", repo, "ls-files", "--", a],
                       capture_output=True, text=True).stdout.split("\n") if p]
        else:
            out.append(a)
    return sorted(set(p for p in out if p))


def load_accepts(path):
    """-> ([(rel, line, reason)], [error line]) for a signed --accept exceptions file: one
    `<path>TAB<line>TAB<reason>` per line, `#` starts a comment. A reason is mandatory because an
    entry that does not say WHAT the edit was cannot be reviewed, only believed."""
    ents, errs = [], []
    try:
        raw = open(path, encoding="utf-8").read()
    except OSError as exc:
        return [], [f"{path}: cannot be read ({exc.strerror or exc})"]
    for n, line in enumerate(raw.split("\n"), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        f = line.split("\t")
        if len(f) != 3 or not f[2].strip():
            errs.append(f"{path}:{n}: want <path>TAB<line>TAB<reason> with a non-empty reason")
            continue
        try:
            ln = int(f[1])
        except ValueError:
            errs.append(f"{path}:{n}: the line field must be a number, got {f[1]!r}")
            continue
        ents.append((f[0].strip(), ln, f[2].strip()))
    return ents, errs


class Refused(Exception):
    """The gate cannot measure: no baseline file, a baseline that does not describe the population
    it is pinned to, a window older than one wave, a revision this clone does not have. Exit 2 -- a
    refusal is never a pass, and it is never reported as a verdict the run reached."""


def _git_out(repo, *args):
    """-> stdout of one git call, raising Refused when git refuses."""
    got = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    if got.returncode:
        raise Refused(f"git {' '.join(args)}: {got.stderr.strip() or 'failed'}")
    return got.stdout


def compared_window(repo, base_rev, now_rev, scope):
    """-> [(path, base_oid, now_oid)] sorted by path: every file the window ACTUALLY compared. The
    list is derived from the two revisions, never from a working copy or a folder listing, so the
    population does not depend on what a lane happened to `git add`; a `0000…` oid marks the side
    where the path does not exist."""
    raw = _git_out(repo, "diff", "--raw", "-z", "--no-renames", base_rev, now_rev, "--", scope)
    fields, recs = raw.split("\0"), []
    for i in range(0, len(fields) - 1, 2):
        meta = fields[i].split()
        path = fields[i + 1]
        if len(meta) >= 4 and path:
            recs.append((path, meta[2], meta[3]))
    return sorted(set(recs))


def digest_keys(keys):
    """-> sha256 over the sorted keys, hashing one digest per key first so a key containing a
    newline cannot shift the digest of its neighbours -- the construction
    `scripts/gate/check_string_twins.py` uses for its group keys."""
    h = hashlib.sha256()
    for k in sorted(keys):
        h.update(hashlib.sha256(k.encode("utf-8", "surrogatepass")).digest())
    return h.hexdigest()


def compared_sha256(recs):
    """-> the digest of WHAT was compared: one path + both blob ids per line. A narrower scope, a
    moved revision or a rewritten file all change it, so the population cannot quietly shrink."""
    return digest_keys(f"{p}\t{b}\t{n}" for p, b, n in recs)


def read_baseline(path, strict=True):
    """-> the recorded fields, `<key> <value>` per line with `#` starting a comment -- the file
    shape of `scripts/gate/twin_baseline.txt`, read the same way: `--show-baseline` may read a
    half-written file, because that is exactly how a re-baseline is produced (point compare_rev at
    the wave tip, then paste the re-derived numbers back in)."""
    if not os.path.isfile(path):
        raise Refused(f"{path} is missing, so the window this gate was reviewed against is unknown")
    fields = {}
    for line in open(path, encoding="utf-8").read().splitlines():
        if line.strip() and not line.lstrip().startswith("#"):
            parts = line.split(None, 1)
            if len(parts) == 2:
                fields[parts[0]] = parts[1].strip()
    want = ("baseline_rev", "compare_rev", "scope", "compared_files", "compared_sha256",
            "rejected") if strict else ("baseline_rev", "compare_rev", "scope")
    for key in want:
        if key not in fields:
            raise Refused(f"{path} has no `{key}` field, so this run cannot be attributed to a "
                          f"reviewed population")
    return fields


def gate_window(repo, fields, gate=True):
    """-> (recs, baseline fields) for the pinned window, refusing when it cannot be measured. Both
    ends must exist and sit on the history being gated, and `compare_rev` must be within
    STALE_AFTER_COMMITS of HEAD: an ancient window measures an old wave and turns its refactors
    into false severs, which is the refusal check_string_twins.py already has, ported.
    `gate=False` is the `--show-baseline` path, which exists precisely to print the fields for a
    window that has aged out, so it reads the population without the ancestry verdict."""
    for rev in (fields["baseline_rev"], fields["compare_rev"]):
        got = subprocess.run(["git", "-C", repo, "cat-file", "-e", f"{rev}^{{commit}}"],
                             capture_output=True)
        if got.returncode:
            raise Refused(f"needs full history -- {rev}, named by {BASELINE}, is not in this "
                          f"clone's object store")
        if gate and subprocess.run(["git", "-C", repo, "merge-base", "--is-ancestor", rev, "HEAD"],
                                   capture_output=True).returncode:
            raise Refused(f"{rev} is not an ancestor of HEAD -- the baseline has to be a revision "
                          f"on the history being gated")
    if gate:
        behind = int(_git_out(repo, "rev-list", "--count",
                              f"{fields['compare_rev']}..HEAD").strip())
        if behind > STALE_AFTER_COMMITS:
            raise Refused(f"the baseline's now end {fields['compare_rev']} is {behind} commits "
                          f"behind HEAD, past the cap of {STALE_AFTER_COMMITS} (a wave measured "
                          f"176): this gate measures the CURRENT wave or says nothing. Re-baseline "
                          f"at the wave tip -- point compare_rev at HEAD and publish the fields "
                          f"`--gate --show-baseline` prints")
    return compared_window(repo, fields["baseline_rev"], fields["compare_rev"], fields["scope"])


def gate_run(repo, baseline=BASELINE, accepts=ACCEPTS, show=False):
    """The registered run. Replay the pinned window over the in-tree signed accepts list, and
    verify the baseline's own record of what it compared -- so the verdict the suite reports is a
    re-derived fact about two commits, and neither a narrowed scope nor a moved revision nor a
    deleted accept entry can leave it green. `--show-baseline` prints the fields this run checks."""
    fields = read_baseline(baseline, strict=not show)
    recs = gate_window(repo, fields, gate=not show)
    # floor 0, not a sampled count: the population comes from one `git diff`, and the failure this
    # asserts is an EMPTY window -- a run that read nothing must not be able to print OK
    require_corpus(len(recs), 0, f"files the window {fields['baseline_rev']}.."
                                 f"{fields['compare_rev']} changed under {fields['scope']}")
    print(f"corpus_diff GATE baseline={baseline} window={fields['baseline_rev']}.."
          f"{fields['compare_rev']} scope={fields['scope']} files={len(recs)} "
          f"accepts={accepts}")
    if show:
        print(f"baseline_rev {fields['baseline_rev']}\ncompare_rev {fields['compare_rev']}\n"
              f"scope {fields['scope']}\ncompared_files {len(recs)}\n"
              f"compared_sha256 {compared_sha256(recs)}")
    rc, st = report(repo, fields["baseline_rev"], [p for p, _b, _n in recs], accepts,
                    now_ref=fields["compare_rev"], quiet=True)
    got = {"compared_files": len(recs), "compared_sha256": compared_sha256(recs),
           "rejected": st["rejected"]}
    if show:
        for k, v in got.items():
            print(f"{k} {v}")
        for key in st["rej_keys"]:
            print(f"reject_key {key}")
        return rc
    for key, value in got.items():
        if str(value) != fields[key]:
            raise Refused(f"{baseline} records {key} {fields[key]!r}; this window yields "
                          f"{str(value)!r}. A population that moves or a verdict that changes shape "
                          f"is a decision, not a detail: publish all the fields "
                          f"`--gate --show-baseline` prints in the commit that moves the window")
    return rc


def report(repo, ref, paths, accept_path=None, now_ref=None, quiet=False):
    """-> (rc, stats). 0 when every change in scope is a confined token purge -- or is carried by a
    used, exact entry of the signed --accept list -- 1 when anything is REJECTED or an accept entry
    is stale, 2 when the run audited nothing at all -- a green verdict has to mean a line was read.
    `now_ref` names the revision the NOW side is read from, which is how a closed window is
    replayed; None reads the working copy, which is what an in-flight purge looks like.
    `quiet` keeps the per-file, per-category and manual-review dumps out of the output, so the
    registered gate prints a verdict instead of a 100 KB transcript."""
    stats = {"files": len(paths or []), "accepted": 0, "rejected": 0, "review": 0, "rej_keys": []}
    if not paths:
        print("ERROR: no files in scope -- the diff was never read, so this run proves nothing; "
              "name the changed files, a directory, or --list <file>")
        return 2, stats
    accepts = []
    if accept_path:
        accepts, errs = load_accepts(accept_path)
        if errs:
            for e in errs:
                print("ACCEPT LIST ERROR " + e)
            print("ERROR: the signed accept list is malformed, so nothing is accepted and this "
                  "run proves nothing -- fix the list first")
            return 2, stats
    acc_all, rej_all, cats, per_file = {}, {}, {}, {}
    ids = dates = clean = binary = info = 0
    texts = {}
    for rel in paths:                                # the join needs every file, not one
        got, err = git_text(repo, ref, rel, now_ref)
        texts[rel] = (got, err)
    # A `comment=` outside the audited set can still be the handle a selector in this set uses,
    # and a selector outside it can select a `comment=` written here: read every RouterOS
    # template at the base ref, however narrow the diff is, so the key set does not depend on
    # which files a lane was pointed at.
    sel_src = {r: g[0] for r, (g, _) in texts.items() if g}
    for rel in subprocess.run(["git", "-C", repo, "ls-tree", "-r", "--name-only", ref],
                              capture_output=True, text=True).stdout.split("\n"):
        if rel.endswith((".rsc", ".rsc.j2")) and rel not in sel_src:
            got, _ = git_text(repo, ref, rel)
            if got:
                sel_src[rel] = got[0]
    selectors = corpus_selectors(sel_src)
    for rel in paths:
        got, err = texts[rel]
        if err:
            if err.startswith("unchanged"):
                binary += 1
            else:
                rej_all[(rel, 0)] = (err, None, None)
            continue
        acc, rej = audit_text(got[0], got[1], rel=rel, selectors=selectors)
        acc_all[rel] = acc
        rej_all.update({(rel, ln): why for ln, why in rej.items()})
        for rec in acc.values():
            cats[rec["cat"]] = cats.get(rec["cat"], 0) + 1
            ids, dates = ids + rec["ids"], dates + rec["dates"]
            info += 1 if rec.get("info") else 0     # reported, not judged -- no token left the line
        if acc or rej:
            per_file[rel] = (len(acc), len(rej))
        else:
            clean += 1
    acc_n = sum(n for n, _ in per_file.values())
    changed = acc_n + sum(1 for (_, ln) in rej_all if ln)     # lines actually compared
    # an accepted change that is MORE than the bare token removal is the half a human owes, so
    # the count prints even in quiet mode, where the list itself does not
    rev = sum(1 for recs in acc_all.values() for rec in recs.values() if rec["why"])
    stats.update(accepted=acc_n, rejected=len(rej_all), review=rev,
                 rej_keys=sorted(f"{rel}:{ln}" for (rel, ln) in rej_all))
    print(f"corpus_diff repo={repo} base={ref} files={len(paths)} "
          f"unchanged={clean} files-with-changes={len(per_file)} binary-skipped={binary}")
    pending, covered = list(accepts), set()        # one entry consumed per REJECT it covers
    for (rel, ln), (why, a, b) in sorted(rej_all.items()):
        ent = next((e for e in pending if (e[0], e[1]) == (rel, ln)), None)
        if ent:
            pending.remove(ent)
            covered.add((rel, ln))
        print(f"{'ACCEPTED' if ent else 'REJECT'} {rel}{':' + str(ln) if ln else ''}  {why}")
        if ent:
            print(f"    signed accept: {ent[2]}")
        if a is not None:
            print(f"    base: {a!r}\n    new : {b!r}")
    for rel, ln, reason in sorted(pending):        # the anti-whitelisting rule, in print
        print(f"STALE {rel}:{ln}  signed for a REJECT this run does not have -- the exception "
              "outlived its edit, which is how an allowlist rots; retire or re-sign it")
        if not quiet:
            print(f"    signed reason was: {reason}")
    if not quiet:
        print("\n-- accepted, per file --")
        for rel, (n, m) in sorted(per_file.items()):
            print(f"  {n:5d} {rel}" + (f"   (+{m} rejected)" if m else ""))
        print("\n-- accepted, per category --")
        for c, n in sorted(cats.items(), key=lambda kv: (-kv[1], kv[0])):
            print(f"  {n:5d} {c}")
        if not cats:
            print("      0 (none)")
    print(f"\ntotals: accepted={acc_n} rejected={len(rej_all)} "
          f"ids-removed={ids} dates-removed={dates} needs-review={rev} informational={info}"
          + (f" accept-covered={len(covered)} accept-stale={len(pending)}" if accept_path else ""))
    if not quiet:
        print("\n-- manual review: accepted changes that are MORE than a token removal --")
        for rel in sorted(acc_all):
            for ln, rec in sorted(acc_all[rel].items()):
                if not rec["why"]:
                    continue
                print(f"REVIEW {rel}:{ln} [{rec['cat']}] {'; '.join(rec['why'])}"
                      f"\n    base: {rec['a']!r}\n    new : {rec['b']!r}")
    if not changed and not rej_all:
        # an empty scope and a clean scope must not wear the same face as a passing audit
        print("\nVERDICT: NOTHING AUDITED -- 0 changed lines in scope, so nothing was verified; "
              "this is not a pass (name the changed files: <repo> <base-ref> <file> ...)")
        return 2, stats
    uncovered = [k for k in rej_all if k not in covered]
    if not uncovered and not pending:
        print("\nVERDICT: OK -- every change is confined to a string literal or a comment"
              + (f" ({len(covered)} change(s) carried by used, exact entries of {accept_path})"
                 if covered else ""))
        return 0, stats
    reasons = ([f"{len(uncovered)} change(s) reach outside rendered text"] if uncovered else []) \
        + ([f"{len(pending)} stale signed accept entry/entries cover no REJECT in this run"
            " -- the list must shrink with the tree"] if pending else [])
    print("\nVERDICT: REJECTED -- " + "; ".join(reasons))
    return 1, stats


def keys_report(repo, paths):
    """List every value in the tree that is a MATCH KEY rather than a mention, with the menu path
    and the selector that made it one. A report, not a gate: it exits 0 and the owner rules on each
    family. This is the input the wave needs to know what a purge may NOT touch, so the listing is
    what matters, not the classifier."""
    texts = {}
    for rel in paths:
        try:
            raw = open(os.path.join(repo, rel), "rb").read()
        except OSError:
            continue
        if b"\0" not in raw:
            texts[rel] = raw.decode("utf-8", "surrogateescape")
    sel = dict(texts)                      # the join also needs the delta scripts outside `paths`
    for rel in subprocess.run(["git", "-C", repo, "ls-files"], capture_output=True,
                              text=True).stdout.split("\n"):
        if rel.endswith((".rsc", ".rsc.j2")) and rel not in sel:
            try:
                raw = open(os.path.join(repo, rel), "rb").read()
                if b"\0" not in raw:
                    sel[rel] = raw.decode("utf-8", "surrogateescape")
            except OSError:
                pass
    selectors = corpus_selectors(sel)
    fam, n = {}, 0
    if not texts:
        print("ERROR: no files in scope -- --keys read 0 files, so an empty key list would be "
              "worthless; name a path that exists in " + repo)
        return 2
    print(f"corpus_diff --keys repo={repo} files={len(texts)} "
          f"selectors-found={len(selectors)}")
    for rel in sorted(texts):
        lines = texts[rel].split("\n")
        for ln, k in sorted(key_sites(rel, lines, selectors).items()):
            n += 1
            fam[k["family"]] = fam.get(k["family"], 0) + 1
            print(f"KEY {rel}:{ln}  [{k['family']}] menu={k['menu'] or '(no RouterOS menu)'} "
                  + k["why"])
            if k["family"] == "comment-key":      # triage in one look: WHICH find claims this row
                print(f"    selector: {k['sel']} {k['tok']}")
            print(f"    {lines[ln - 1].strip()[:140]}")
    print("\n-- by construct --")
    for f, c in sorted(fam.items(), key=lambda kv: (-kv[1], kv[0])):
        print(f"  {c:5d} {f}")
    print(f"\ntotals: match-key sites={n} in {len(texts)} files -- none of these may be purged "
          "without an owner ruling; the gate REJECTS a change to any of them")
    return 0


CASES = {  # (base, edited, verdict, rel, expected match-key sites) -- verdict "none" = no record
           # at all, which only an UNCHANGED line produces; "ok" with an info record means the
           # audit saw an edit and correctly rendered no verdict on it (the token anchor, w/x/y/z)
    "a task-name id":  ("- name: Restart nginx after HD-312 reload\n",
                        "- name: Restart nginx after reload\n", "ok", "", None),
    # each of these four is a CODE change, so under the token anchor it needs a token on the base
    # side to be judged at all -- the same pair with no token removed is arm w, which is not a
    # verdict. The tokens below are fixtures, not citations: they name nothing.
    "b indicator":     ("    enabled: true   # HD-9001\n",
                        "    enabled: false   # the pin\n", "bad", "", None),
    "e jinja default": ("  port: {{ x | default(8) }}   # HD-9002\n",
                        "  port: {{ x | default(6) }}   # tuning\n", "bad", "", None),
    "c path in cmd":   ("  cmd: /opt/forwarder/run.sh --state /opt/old/state   # HD-9003\n",
                        "  cmd: /opt/forwarder/run.sh --state /opt/new/state   # the pin\n",
                        "bad", "", None),
    "d payload #":     ("  - |\n    # HD-298: keep the ignore flag\n    run: x\n",
                        "  - |\n    # keep the ignore flag\n    run: x\n", "ok", "", None),
    "f msg":           ('    msg: "disk quota HD-411 exceeded"\n',
                        '    msg: "disk quota exceeded"\n', "ok", "", None),
    "g state date":    ('    valid_until: "2027-06-24"\n', '    valid_until: ""\n',
                        "bad", "", None),
    # --- K1b: the three text classes, plus the match-key class -------------------------------
    "h jinja literal": ("      {{ 'traefik.http.routers.grafana.tls.certresolver: letsencrypt' "
                        "if (traefik_acme_issuer | default(false)) else '# consumer mode: TLS "
                        "from the synced cert pair (HD-181/HD-204)' }}\n",
                        "      {{ 'traefik.http.routers.grafana.tls.certresolver: letsencrypt' "
                        "if (traefik_acme_issuer | default(false)) else '# consumer mode: TLS "
                        "from the synced cert pair' }}\n", "ok", "c/docker-compose.yml.j2", None),
    "i jinja filter":  ("      {{ 'x' if (traefik_acme_issuer | default(8)) else '# consumer "
                        "mode' }}   # HD-9004\n",
                        "      {{ 'x' if (traefik_acme_issuer | default(6)) else '# consumer "
                        "mode' }}   # tuning\n", "bad", "c/docker-compose.yml.j2", None),
    "j docstring body": ('r"""qbittorrent-seeding.py -- reconcile the goal.\n'
                         '\nKEY NAMES WERE READ, NOT REMEMBERED (measured 2026-10-07, API 5.2.3):\n'
                         '"""\nimport sys\n',
                         'r"""qbittorrent-seeding.py -- reconcile the goal.\n'
                         '\nKEY NAMES WERE READ, NOT REMEMBERED (measured, API 5.2.3):\n'
                         '"""\nimport sys\n', "ok", "roles/docker_services/t/qbittorrent-seeding.py.j2",
                         None),
    "k docstring reindent": ('"""Seed goals.\n    both time goals stay disabled, the HD-1086 ruling\n"""\n',
                             '"""Seed goals.\n  both time goals stay disabled, the ruling\n"""\n',
                             "bad", "roles/docker_services/t/qbittorrent-seeding.py.j2", None),
    "l md table prose": ("| 192.168.1.2/24 | router.kogler.si | RB4011 on the modem LAN, "
                         "srcnat masquerade for trusted-admin (HD-302) | `group_vars/router.yml` |\n",
                         "| 192.168.1.2/24 | router.kogler.si | RB4011 on the modem LAN, "
                         "srcnat masquerade for trusted-admin | `group_vars/router.yml` |\n",
                         "ok", "templates/network-addresses.md.j2", None),
    "m find-where key": ('/ipv6 address remove [find where comment~"^HD-414"]\n',
                         '/ipv6 address remove [find where comment~"^"]\n',
                         "bad", "router/templates/rb4011_converge.rsc.j2", 1),
    "n md jinja tag":  ("{% for r in network_ranges %} (HD-9005)\n",
                        "{% for r in network_ranges if r.id != 99 %} (the reserved row)\n",
                        "bad", "templates/network-addresses.md.j2", None),
    "o docstring quote": ('"""Seed goals: the HD-1086 ruling."""\n',
                          "'''Seed goals: the ruling.'''\n", "bad",
                          "roles/docker_services/t/qbittorrent-seeding.py.j2", None),
    # the anchor is LINE-local, and this is that limit stated where a reader will meet it: the same
    # re-quote, with the token leaving a DIFFERENT line than the one whose parse moved, is invisible
    # to this gate -- reported as an edit, and the run goes green. The blind spot the registry row
    # carries, asserted rather than assumed.
    "ab requote elsewhere": ('"""Seed goals.\nboth goals stay off, the HD-1086 ruling\n"""\n',
                             "'''Seed goals.\nboth goals stay off, the ruling\n'''\n", "ok",
                             "roles/docker_services/t/qbittorrent-seeding.py.j2", None),
    "p tags item":     ("  tags: [ha_failover, hd17]\n", "  tags: [ha_failover]\n",
                        "bad", "roles/home_assistant/tasks/standby.yml", 1),
    "q compared string": ('if profile == "HD-1080p":\n', 'if profile == "":\n', "bad",
                          "roles/docker_services/tasks/x.py.j2", 1),
    # --- K2: the RouterOS join is menu-scoped, so a `find` in another menu proves nothing ------
    "r cross-menu purge": ('/ipv6 address remove [find where comment~"^HD-414"]\n'
                           '/ipv6 firewall filter\n'
                           'add chain=forward action=drop in-interface=vlan30-no-v6 comment="HD-414 no v6 egress"\n',
                           '/ipv6 address remove [find where comment~"^HD-414"]\n'
                           '/ipv6 firewall filter\n'
                           'add chain=forward action=drop in-interface=vlan30-no-v6 comment="no v6 egress"\n',
                           "ok", "router/templates/rb4011_converge.rsc.j2", 1),
    "s same-menu = key": ('/ip firewall filter\n'
                          ':local homeWan [/ip firewall filter find where chain=forward and '
                          'comment="Home -> WAN allowed (HD-309 row 73)"]\n'
                          'add chain=forward action=accept src-address=10.10.1.0/24 '
                          'comment="Home -> WAN allowed (HD-309 row 73)"\n',
                          '/ip firewall filter\n'
                          ':local homeWan [/ip firewall filter find where chain=forward and '
                          'comment="Home -> WAN allowed (HD-309 row 73)"]\n'
                          'add chain=forward action=accept src-address=10.10.1.0/24 '
                          'comment="Home -> WAN allowed"\n',
                          "bad", "router/templates/rb4011_converge.rsc.j2", 2),
    "t same-menu ~ prefix": ('/ip firewall filter\n'
                             '/ip firewall filter remove [find where comment~"^HD-326"]\n'
                             'add chain=forward action=drop src-address=10.10.40.0/24 '
                             'comment="HD-326 kids bedtime WAN block"\n',
                             '/ip firewall filter\n'
                             '/ip firewall filter remove [find where comment~"^HD-326"]\n'
                             'add chain=forward action=drop src-address=10.10.40.0/24 '
                             'comment="kids bedtime WAN block"\n',
                             "bad", "router/templates/rb4011_converge.rsc.j2", 2),
    # --- the token anchor: what a window may contain besides the purge -------------------------
    # w and z are ONE pair, the same renamed key, differing only in whether a token left the line.
    # That is the fix seen from both sides: the anchor must let ordinary development through (w
    # prints a record and no verdict) and it must not soften a purge that reached the parse (z
    # quotes the two key names at each other). Delete the anchor and w goes RED; delete the region
    # judgement and z goes GREEN. Either way this pair is the proof, not this comment.
    "w no-token edit":   ("  restart_delay: 30   # the drain window\n",
                          "  restart_interval: 30   # the drain window\n", "ok", "", None),
    "z purge in code":   ("  restart_delay: 30   # HD-9006\n",
                          "  restart_interval: 30   # the pin\n", "bad", "", None),
    # a reflow around a purged line is still a purge that moved code: RED with the token gone,
    # nothing to report with no token gone (the old classifier called the second pair a REJECT too)
    "y purge reflowed":  ("# HD-9007 restarts the arr after the pin\n",
                          "    # restarts the arr after the pin\n", "bad", "", None),
    "x reflow no token": ("# restarts the arr after the pin\n",
                          "    # restarts the arr after the pin\n", "ok", "", None),
    # a line the diff never touched answers with nothing at all: no record, no verdict, no count
    "aa unchanged line": ("# restarts the arr after the pin\n",
                          "# restarts the arr after the pin\n", "none", "", None)}


GUARD_CANARIES = {  # run ONLY by --guard-self-test; both FAIL the suite BY DESIGN, because a
                    # guard that is never challenged is assumed, not tested (K3, after I-9)
    "u block canary": (
        # a case that BLOCKS, built the way the real hang was: not a sleep, but a selector whose
        # regex backtracks catastrophically -- `re.search` then never returns to the interpreter
        # loop, so a signal-only guard can miss it and only the waitpid deadline catches it.
        # The matched value must END in a non-`a` char: `(a+)+$` SUCCEEDS instantly on a run of
        # plain a's (measured on 3.13 -- without the failing tail this canary is a placebo)
        '/ip firewall filter\n'
        '/ip firewall filter remove [find where comment~"(a+)+$"]\n'
        'add chain=forward action=drop comment="HD-9 ' + "a" * 36 + 'b"\n',
        '/ip firewall filter\n'
        '/ip firewall filter remove [find where comment~"(a+)+$"]\n'
        'add chain=forward action=drop comment="kids bedtime WAN block"\n',
        "bad", "router/templates/rb4011_converge.rsc.j2", None),
    "v raise canary": (None, "", "bad", "", None),   # a case that RAISES: named CRASH, not lost
}


CASE_DEADLINE = 10.0   # seconds one case may take; past it the case is killed and FAILS


def _one_case(name, base, new, want, rel, want_keys):
    """-> (ok, report line) for one case. Runs in the child, so a hang cannot stop the run."""
    # the key join is corpus-wide, so the audit and the count must see the same selectors
    sels = corpus_selectors({rel or "x": base})
    acc, rej = audit_text(base, new, rel=rel, selectors=sels)
    # "none" is the face of a line the diff did not change: neither record. It is asserted, not
    # assumed -- a pair that produced no record for some other reason would pass a weaker check.
    got = "none" if not acc and not rej else ("bad" if rej else "ok")
    found = len(key_sites(rel, base.split("\n"), sels))
    keys_ok = want_keys is None or found == want_keys
    ok = (got == want) and keys_ok
    line = (f"{'PASS' if ok else 'FAIL'} {name:19s} expected={want} got={got} "
            f"cat={[r['cat'] for r in acc.values()]}"
            f"{f' keys={found}' if want_keys is not None else ''} "
            f"{list(rej.values())[0][0] if rej else ''}")
    return ok, line


def self_test(guard=False):
    """Each case is announced on stderr and then runs in its own child under a hard wall-clock
    deadline. A case that blocks is a named FAIL with a non-zero exit, never a silent hang: a
    verdict that cannot be attributed to a case is what costs a lane its run (wave 2, case m).
    `guard=True` (--guard-self-test) also runs the two GUARD_CANARIES, which FAIL by design
    under a shortened deadline -- the ordinary --self-test never runs them and stays green."""
    global CASE_DEADLINE
    cases = CASES
    if guard:
        CASE_DEADLINE, cases = 2.0, dict(CASES, **GUARD_CANARIES)
    bad = 0
    for name, (base, new, want, rel, want_keys) in sorted(cases.items()):
        print(f"-- case {name}", file=sys.stderr, flush=True)     # name it BEFORE running it
        sys.stdout.flush()                     # nothing may sit in the buffer across the fork
        pid = os.fork()
        if pid == 0:
            signal.alarm(int(CASE_DEADLINE) + 1)                  # child-side second layer
            try:
                ok, line = _one_case(name, base, new, want, rel, want_keys)
                print(line, flush=True)
                sys.stdout.flush()
                os._exit(0 if ok else 1)
            except BaseException:                # one broken case must not end the run
                traceback.print_exc(file=sys.stderr)
                sys.stderr.flush()
                os._exit(3)
        deadline, st, hung = time.monotonic() + CASE_DEADLINE, None, False
        while True:
            done, st = os.waitpid(pid, os.WNOHANG)
            if done:
                break
            if time.monotonic() >= deadline:      # the deadline is wall-clock, not CPU time
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
                hung = True
                break
            time.sleep(0.02)
        if hung:
            print(f"FAIL {name:19s} HANG <{name}>: no answer in {CASE_DEADLINE:g}s -- killed; "
                  "a case that blocks is a FAIL, never a pass", flush=True)
            bad += 1
        elif not os.WIFEXITED(st):
            print(f"FAIL {name:19s} HANG <{name}>: killed by signal {os.WTERMSIG(st)}; "
                  "a case that does not answer is a FAIL", flush=True)
            bad += 1
        elif os.WEXITSTATUS(st) == 3:
            print(f"FAIL {name:19s} CRASH in this case (traceback above)", flush=True)
            bad += 1
        elif os.WEXITSTATUS(st):
            bad += 1                              # the child already printed its FAIL line
    bad += _gate_cases()
    print("SELF-TEST: " + ("OK" if not bad else f"{bad} case(s) misjudged"))
    return 0 if not bad else 1


# --- the pinned-run half of the self-test --------------------------------------------------------
# The CASES above prove the CLASSIFIER; they cannot see the three things that make the registered
# run a gate rather than a report: the signed accepts list, the baseline digest, the staleness cap.
# Each of those is proven here on a throwaway repo, and each case asserts the RED verdict -- a
# canary that cannot fail is the hole this whole promotion exists to close.

FIXTURE_BASE = ["- name: Restart nginx after HD-312 reload\n",
                "- name: Reload nginx after HD-313 drain\n",
                "- name: Verify nginx listeners   # HD-314\n"]
FIXTURE_NOW = ["- name: Restart nginx reload\n",          # a confined purge -- accepted
               "- name: Reload nginx\n",
               # the parse moved: a `- name:` item became a top-level comment while its token left.
               # Not a thing a purge may do, and the one REJECT the gate cases sign and remove.
               "# verify nginx listeners after the drain\n"]
FIXTURE_REASON = ("the task's `- name:` line was rewritten into a top-level comment beside the "
                  "purge, so the parse moved with the token")


class _FixtureRepo:
    """A throwaway repo: commit 1 is the base, commit 2 is the purge, nothing outside a temp dir is
    touched and nothing is pushed. Mirrors the fixture scripts/gate/check_string_twins.py builds."""

    def __init__(self, base_lines, now_lines):
        self.dir = tempfile.mkdtemp(prefix="corpus-diff-")
        self.env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_AUTHOR_NAME="t",
                        GIT_AUTHOR_EMAIL="t@t.invalid", GIT_COMMITTER_NAME="t",
                        GIT_COMMITTER_EMAIL="t@t.invalid")
        self._run("init", "-q")
        (Path(self.dir) / "IaC").mkdir()
        self._write("".join(base_lines))
        self._commit("base")
        self.base_rev = self._rev()
        self._write("".join(now_lines))
        self._commit("the purge")
        self.head_rev = self._rev()

    def _run(self, *args, check=True):
        got = subprocess.run(["git", "-C", self.dir, *args], env=self.env,
                             capture_output=True, text=True)
        if check and got.returncode:
            raise RuntimeError(f"git {args}: {got.stderr}")
        return got.stdout

    def _write(self, text):
        (Path(self.dir) / "IaC" / "a.yml").write_text(text, encoding="utf-8")

    def _commit(self, msg):
        self._run("add", "-A")
        self._run("commit", "-q", "-m", msg)

    def _rev(self):
        return self._run("rev-parse", "HEAD").strip()

    def advance(self):
        """One more commit on the tree, touching nothing in scope -- the way a real tree ages away
        from a baseline that nobody re-published."""
        self._run("commit", "-q", "--allow-empty", "-m", "later work outside the scope")

    def cleanup(self):
        subprocess.run(["rm", "-rf", self.dir], check=False)

    def window(self, path):
        """The three window fields only -- what a human writes before re-deriving the rest."""
        Path(path).write_text(f"baseline_rev {self.base_rev}\ncompare_rev {self.head_rev}"
                              f"\nscope IaC/\n", encoding="utf-8")

    def complete(self, path):
        """Append the three fields the run re-derives, taken from `--show-baseline` on this repo --
        the paste-back half of the documented re-baseline act."""
        f = Path(path)
        out, _rc = self.gate(f, _accepts(f.parent, []), show=True)
        got = {}
        for ln in out.splitlines():
            parts = ln.split(None, 1)
            if len(parts) == 2 and parts[0] in ("compared_files", "compared_sha256", "rejected"):
                got[parts[0]] = parts[1]
        with f.open("a", encoding="utf-8") as fh:
            for k in ("compared_files", "compared_sha256", "rejected"):
                fh.write(f"{k} {got[k]}\n")

    def gate(self, baseline, accepts, show=False):
        """-> (everything the run printed, rc). The printed text is the evidence, so a FAIL line
        quotes it; nothing here writes to the real stdout. Refused is mapped to exit 2 exactly the
        way main() maps it -- the self-test must exercise the verdict a caller actually gets."""
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf):
                rc = gate_run(self.dir, str(baseline), str(accepts), show=show)
        except Refused as exc:
            print(f"ERROR: {exc}", file=buf)
            rc = 2
        return buf.getvalue(), rc


def _accepts(directory, entries):
    """-> path to a signed accepts list holding exactly `entries` ((path, line, reason) tuples)."""
    p = Path(directory) / "accepts.txt"
    p.write_text("# signed --accept exceptions list\n" +
                 "".join(f"{rel}\t{ln}\t{why}\n" for rel, ln, why in entries), encoding="utf-8")
    return p


def _gate_cases():
    """-> number of failed cases across the five properties of the pinned run."""
    global STALE_AFTER_COMMITS
    fails = 0
    tmp = Path(tempfile.mkdtemp(prefix="corpus-diff-fix-"))
    baseline, stale_cap = tmp / "baseline.txt", STALE_AFTER_COMMITS
    try:
        repo = _FixtureRepo(FIXTURE_BASE, FIXTURE_NOW)
        try:
            # the reject the fixture provokes, discovered the way a signer would discover it
            repo.window(baseline)
            out, _rc = repo.gate(baseline, _accepts(tmp, []), show=True)
            keys = [ln.split()[1] for ln in out.splitlines() if ln.startswith("reject_key ")]
            rel, ln = keys[0].rsplit(":", 1)
            entry = (rel, int(ln), FIXTURE_REASON)
            repo.complete(baseline)

            def run(accepts):
                return repo.gate(baseline, accepts)[1]
            def record(name, ok, said):
                nonlocal fails
                print(f"{'PASS' if ok else 'FAIL'} {'gate ' + name:19s} {said}", flush=True)
                if not ok:
                    fails += 1

            good = _accepts(tmp, [entry])
            rc = run(good)
            record("i  run is green", rc == 0, f"rc={rc}")
            record("ii deleting the accept entry reddens the run",
                   run(_accepts(tmp, [])) == 1, "rc of a run with no signed entry")
            moved = _accepts(tmp, [(entry[0], entry[1] + 1, entry[2])])
            record("iii a moved accept entry is stale", run(moved) == 1, "rc of a stale entry")

            text = baseline.read_text(encoding="utf-8")
            baseline.write_text(text.replace("compared_sha256 ", "compared_sha256 0"),
                                encoding="utf-8")
            record("iv a baseline digest that does not match is refused", run(good) == 2,
                   "rc of a population that does not match its record")
            baseline.write_text(text, encoding="utf-8")

            STALE_AFTER_COMMITS = 0
            repo.advance()            # the window is now one commit behind the tree it gates
            try:
                record("v a baseline past the staleness cap is refused", run(good) == 2,
                       "rc of a window older than the cap")
            finally:
                STALE_AFTER_COMMITS = stale_cap
        finally:
            repo.cleanup()
    except Exception as exc:                          # a fixture that cannot build is a FAIL
        print(f"FAIL gate fixture: {exc.__class__.__name__}: {exc}\n{traceback.format_exc()}",
              flush=True)
        fails += 1
    finally:
        subprocess.run(["rm", "-rf", str(tmp)], check=False)
    return fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--list")
    ap.add_argument("--gate", action="store_true",
                    help="the registered form: replay the window the baseline pins, over the "
                         "in-tree signed accepts list")
    ap.add_argument("--baseline", metavar="FILE", default=BASELINE,
                    help="the pinned baseline --gate reads (default scripts/gate/corpus_baseline.txt)")
    ap.add_argument("--show-baseline", action="store_true",
                    help="print every baseline field, re-derived from this tree")
    ap.add_argument("--against", metavar="REV",
                    help="read the NOW side from REV instead of the working copy: replay a closed "
                         "window (the hand-run form of what --gate does to its pinned window)")
    ap.add_argument("--keys", action="store_true",
                    help="list match-key sites (never purged) instead of auditing a diff")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--guard-self-test", action="store_true",
                    help="the 20 real cases PLUS the two guard canaries, which FAIL by design")
    ap.add_argument("--accept", metavar="FILE",
                    help="signed exceptions file (<path>\\t<line>\\t<reason>); exact path+line "
                         "only, and a stale entry fails the run")
    a = ap.parse_args()
    if a.self_test or a.guard_self_test:
        return self_test(guard=a.guard_self_test)
    try:
        if a.gate or a.show_baseline:
            if a.paths:
                print("--gate takes no file arguments: the scope is the baseline's, and a scope a "
                      "run can widen is not a pinned population", file=sys.stderr)
                return 2
            return gate_run(str(ROOT), a.baseline, a.accept or ACCEPTS, show=a.show_baseline)
        if a.keys:
            if not a.paths:
                print("usage: corpus_diff.py --keys <repo> [<path> ...]   (an empty scope is an "
                      "ERROR, not an empty key list)", file=sys.stderr)
                return 2
            repo = a.paths[0]
            extra = a.paths[1:] or ([] if a.list else ["."])   # no path argument = the whole tree
            return keys_report(repo, expand(repo, extra, a.list))
        if len(a.paths) < 2:
            print("usage: corpus_diff.py --gate | <repo> <base-ref> [<file> ... | --list <file>]\n"
                  "       corpus_diff.py --keys <repo> [<path> ...]\n"
                  "       name the changed files: a scope with no file in it is ERROR: no files in "
                  "scope and exits non-zero, it is never a pass", file=sys.stderr)
            return 2
        # report()'s own verdict: 0 clean, 1 REJECTed or stale accept entry, 2 nothing audited
        rc, _stats = report(a.paths[0], a.paths[1], expand(a.paths[0], a.paths[2:], a.list),
                            a.accept, now_ref=a.against)
        return rc
    except Refused as exc:
        print(f"ERROR: {exc}")        # a refusal to measure is exit 2, never a verdict and never 0
        return 2


if __name__ == "__main__":
    sys.exit(main())
