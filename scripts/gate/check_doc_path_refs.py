#!/usr/bin/env python3
"""
check_doc_path_refs.py — prove that every path a doc promises actually exists (HD-490).

WHY THIS EXISTS. A session writing the HD-489 funnel cited `scripts/llm_serving_bench.py`
and `spark/llm-profiles/acceptance/` — neither was ever in this repository. Nobody invented
them out of malice; they read plausibly next to their neighbours, and the next session would
have planned a 20-minute boot leg around a tool that does not exist. A repo this size quotes
several hundred paths per document set, and no existing validator looked at one of them.
CONVENTIONS §6: a doc that cites a path is making a promise; a broken promise in prose is a
defect with the same blast radius as one in code, and slower to notice.

WHAT MAKES THIS TRUSTWORTHY IS THAT IT KNOWS WHEN IT IS WRONG. Five shapes look like
dangling refs and are not, and each is exempted with a reason printed in --verbose:

  1. GLOBS (`templates/docker_services/**/*.j2`) — a pattern names a set, not a file.
  2. PLACEHOLDERS (`scripts/probe-<name>.py`, `{{ item.path }}`) — explicitly unfinished.
  3. THE FROZEN ARCHIVES (`reports/changelog.md`, `reports/deployment-journal.md`) — these
     record what the tree looked like on a date. `IaC/.../prometheus-web-config.yml.j2` was
     real when its changelog row was written and was deleted later; rewriting the row to
     point at the replacement would falsify the record. CONVENTIONS: archive-only. The list
     is TWO files and it is not widened: dated records anywhere else in `reports/` get the
     same mercy only when git itself proves the path was real once (see DATED RECORD below),
     so an invented path in a run log still reddens the gate.
  4. GIT-IGNORED GENERATED FILES (`IaC/host/post_install_with_secrets.sh`) — the manual's
     procedure is "generate it, use it, delete it". `git check-ignore` is the authority for
     whether absence is intentional, which is why this exemption is a lookup and not a list.
  5. PROSE THAT SAYS THE PATH IS MISSING (HD-490's tracked-gap shape: "`x.sh` does not exist
     yet", "optional, ignored if not found", "the file is not in git"). The state word is read in
     the CLAUSE carrying the path and within CLAUSE_WINDOW characters of it, never across the
     line, because a `todo.md` row is ONE line of several kilobytes: a `was never built` or a
     `does not exist` elsewhere in that row may not shelter a second, plainly-asserted citation
     beside it. Reading the whole line would have traded one blind spot for a bigger one.

WHAT THE MATCHER SEES, because the matcher shape decides what is checked (HD-1156 found the
anchor half of this, in `check_doc_headings.py`, and HD-1168 the citation half here): the
original `BARE_RE` carried a backtick in its lookbehind, so `` `scripts/x.py` `` — the way
almost every path in this repo is actually written — was never handed to `Path.exists()`,
and `extract()` masked only markdown-link spans. A backticked path is now read as the claim
it is (kind `code`), one token at a time, so `` `ansible-playbook playbooks/site.yml` ``
checks the playbook too. A `path:line` or `path:var` suffix cites a place INSIDE the file,
so the promise is the file and the suffix is stripped before anything is asked of the disk.

THE ROOTS ARE DERIVED, NOT RECALLED: every real top-level directory of this checkout, plus the
Ansible names this repo's prose actually uses (`roles/…`, `templates/…`, `group_vars/…`,
`playbooks/…`, `host_vars/…`). README §2: there is ONE physical root, `IaC/`, and the fleet's
Ansible tree sits under `IaC/ansible/` — so those names are resolved against that base, and
Ansible's own rule (a template is named `x.j2` from inside `<role>/templates/`) is honoured for
the role-local sub-directory names. `spark/ansible/` is the Spark box's own SECOND Ansible project,
and prose under `spark/` writes `group_vars/spark_nodes.yml` about THAT directory, which is where
the file is. A root added to the tree becomes citable without editing this file; a root that stops
existing stops being excused.

DATED RECORD, the honest version: inside `reports/**`, a path is exempt when it MOVED
(its basename is still in the tree) or when git says it was DELETED (`git log
--diff-filter=D`, so a template the Victoria migration removed stays as written in the run
log that used it). Both halves are lookups; neither is a list, and a name git has never seen
is still a lie wherever it was written.

WHAT IS LEFT OVER IS LEDGERED, NEVER QUIET. The pre-existing dangling refs live in the
committed ledger `scripts/gate/path_refs_baseline.txt` — one TAB-separated line per
<citing file, path as written> with its count, the `check_doc_headings.py` discipline: frozen
debt reads green, a NEW dangling path reddens, and a ledger line whose path now resolves also
reddens, because an entry that outlives its citation is a free pass for the next one. Re-derive
the body with `--show-baseline`; never hand-edit it and never quote its counts (CONVENTIONS §2).
The reason a given entry is carried, and what would close it, belongs to the `todo.md` row that
owns this gate, not to this file.

--self-test does what every other gate here does: breeds a dangling ref in a synthetic tree
and FAILS if it is not caught — in BOTH citation forms, prose and backticked, plus the
role-relative form — breeds the exemptions and fails if any of them is flagged, and proves
both halves of the ledger ratchet. A checker that has never been seen to fail is not a checker.

Stdlib + git only. Exit 0 = no dangling refs; 1 = dangling refs found; 2 = could not run.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# HD-1135#2: on a Windows seat the locale default is cp1252, so printing a non-Latin1
# character (the → in a finding, or any UTF-8 filename) raises UnicodeEncodeError and
# `text=True` subprocess reads crash on non-decodable bytes. Pin stdout/stderr to UTF-8
# for this process — the byte-truthful half; a no-op on UTF-8 platforms.
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

# CONVENTIONS: frozen, archive-only records. A path inside them is a statement about a date,
# not a promise about the working tree, so it may not be "fixed" by editing history.
FROZEN = {"reports/changelog.md", "reports/deployment-journal.md"}

# Roots that mean "relative to the repository root" when they appear in prose or in a code
# span. The top-level half is READ from the tree (HD-1118's found-not-assumed rule: a hardcoded
# list silently stops matching the layout, and `deploy/` was in the old one for six months while
# no such directory existed). The Ansible half is the set of names this repo's prose actually
# writes; README §2 puts all of them under the one physical root `IaC/`.
ANSIBLE_ROOTS = ("roles/", "templates/", "handlers/", "tasks/", "defaults/", "vars/",
                 "files/", "meta/", "group_vars/", "playbooks/", "host_vars/")
# Names Ansible resolves from INSIDE a role (`template: src: x.j2` is found in <role>/templates/).
ROLE_LOCAL = ("templates/", "handlers/", "tasks/", "defaults/", "vars/", "files/", "meta/")
# README §2: the fleet's IaC has ONE physical root, `IaC/`, and the Ansible tree sits under
# `IaC/ansible/`. `spark/ansible/` is the Spark box's own, separate Ansible project — prose inside
# `spark/` writes `group_vars/spark_nodes.yml` the same way, meaning that project's directory, and
# `spark/README.md` runs `ansible-vault encrypt group_vars/spark_nodes.yml` from there. A
# playbook-relative name therefore resolves against the project it belongs to, not the repo root.
ANSIBLE_BASES = ("IaC/", "IaC/ansible/", "spark/ansible/")


def top_roots():
    """Every real top-level directory of this checkout, as `dir/`. Derived, so the gate cannot
    drift from the layout — and so an empty or wrong root walk is loud, not a silent zero."""
    out = sorted(p.name + "/" for p in ROOT.iterdir() if p.is_dir() and not p.name.startswith("."))
    if len(out) < 5:
        raise RuntimeError("check_doc_path_refs: the root walk found %d top-level directories "
                           "(%r) — that is a broken ROOT, not a clean tree" % (len(out), out))
    return out


ROOT_DIRS = tuple(top_roots()) + tuple(r for r in ANSIBLE_ROOTS if r not in top_roots())

LINK_RE = re.compile(r"\[[^\]]*\]\(<?([^)>\s]+)>?\)")
_ROOT_ALT = "|".join(sorted({r.rstrip("/") for r in ROOT_DIRS}, key=len, reverse=True))
BARE_RE = re.compile(
    r"(?<![\w/`~.\-])(?P<p>(?:%s)/"
    r"[^\s`'\"|<>)\],;]*[A-Za-z0-9_])" % _ROOT_ALT
)
# A backticked span: the way this repo writes almost every path. The old BARE_RE lookbehind
# carried a backtick, which made the whole form invisible to the gate (HD-1168).
CODE_SPAN_RE = re.compile(r"`([^`\n]+)`")
# `path:NN`, `path:NN-MM`, `path:var-or-label` — the file is the promise, the suffix is where
# inside it to look. Without this rule a `file.yml:302` citation is "dangling" and the honest
# reading of the sentence is thrown away.
LINE_REF_RE = re.compile(r"^(?P<p>[^:]+):(?P<ref>\d+(?:-\d+)?(?:,\d+)*|[A-Za-z0-9_.-]+)$")
SKIP_SCHEME = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")
GLOB_CHARS = "*?["


def is_exempt(target, origin, reason_hint=""):
    """(bool exempt, str why). Every exemption here is a claim about the repo's conventions,
    so each one is stated rather than silently encoded in a regex."""
    if SKIP_SCHEME.match(target) or target.startswith("#") or target.startswith("mailto:"):
        return True, "not a local path (URL / data URI / anchor)"
    if any(c in target for c in GLOB_CHARS):
        return True, "glob pattern"
    if any(c in target for c in "<>{}") or "{{" in target or "${" in target or "$" in target:
        return True, "placeholder / templated"
    if origin in FROZEN:
        return True, "frozen archive (records a date, not the tree)"
    if origin.startswith("reports/") and _dated_record(target):
        # HD-1118 Stage 3, and the half it left open. `reports/**` is dated EVIDENCE — captured
        # transcripts, per-HD folders, journals. Rewriting a path inside a captured run log to the
        # location the script has reached today falsifies the record: the transcript would claim it
        # invoked a command that did not exist on the date it was produced. So a path stays as
        # written here — but ONLY when git can produce the file, either still present under another
        # path (it MOVED) or deleted later (the Victoria migration removed templates that the 2026-08
        # run logs ran). Both halves are lookups, not lists: a name git has never seen is a wrong
        # path, it is still reported, and that is the arm in --self-test. The FROZEN set above is
        # deliberately NOT widened to make this file green.
        return True, "dated record under reports/ citing a path git has held (_moved_path/_deleted_path)"
    if target.endswith((".md", ".yml", ".yaml", ".j2", ".py", ".sh", ".json", ".csv", ".gz",
                        ".txt", ".ini", ".conf", ".service", ".toml", ".sls", ".gz",
                        ".rsc", ".cfg", ".pub", ".ps1", ".xml", ".timer", ".target",
                        ".network", ".netdev", ".mmd")) is False \
            and "/" in target and not target.endswith("/"):
        # No recognised extension and not spelled as a directory: prose that merely LOOKS like a
        # path. This exemption is what keeps the benign shapes quiet — the model id
        # `spark/qwen3.8-flash-next`, a prose name like `scripts/README` or `docs/index`, a branch
        # name, a URL fragment — and it is also the hole that lets a wrong Ansible role written
        # without a trailing slash (`roles/technitium-seed`, the HD-480/481 view line) through
        # unread. The two grammars are identical, so they cannot be told apart by shape: the
        # tightening was tried here and measured at +111 findings, ~30 of them that one model id,
        # which is a muted gate waiting to happen. The exemption stays, the blind spot is DECLARED
        # in the todo.md row that owns this gate, and what closes it is prose that ends in `/` (a
        # directory claim the gate CAN check) or that names the file.
        return True, "no extension and not a directory"
    return False, ""


def _moved_path(target):
    """Does this path's BASENAME still exist somewhere in the tree? Yes = the file moved, which is
    one honest reading of a stale path in a dated record. Used by the reports/ exemption."""
    name = target.rstrip("/").rsplit("/", 1)[-1]
    if not name or name in (".", ".."):
        return False
    try:
        return any(True for _ in ROOT.rglob(name))
    except (OSError, RecursionError):
        return False


_DELETED_CACHE = {}


def _deleted_path(target):
    """Has git ever tracked this exact path and then removed it? That is the other honest reading of
    a stale path in a dated record: the file was real when the record was written. A lookup, never a
    list, so an invented path in a run log stays a finding (the --self-test arm breeds exactly one).
    Pathspec-limited, so the walk is short; the answer is cached per path."""
    if target in _DELETED_CACHE:
        return _DELETED_CACHE[target]
    try:
        r = subprocess.run(["git", "-C", str(ROOT), "log", "--all", "--diff-filter=D",
                            "--name-only", "--pretty=format:", "--", target], capture_output=True)
        v = bool(r.stdout.decode("utf-8", "replace").strip()) if r.returncode == 0 else False
    except OSError:
        v = False
    _DELETED_CACHE[target] = v
    return v


def _dated_record(target):
    return _moved_path(target) or _deleted_path(target)


def usable(target):
    """Cheap, filesystem-free filter. Applied BEFORE anything touches the disk, because the
    first version of this script fed a `data:image/png;base64,…` URI (a 90 KB "path" from an
    inline image in brainstorming/) to Path.exists() and died with ENAMETOOLONG. A doc scanner
    that can be killed by a doc is worse than no scanner."""
    if not target or len(target) > 256:
        return False
    if SKIP_SCHEME.match(target) or target.startswith("#") or target.startswith("//"):
        return False
    return True


LINK_SPAN_RE = re.compile(r"\[[^\]]*\]\(<?[^)>\s]+>?\)")
# Trailing sentence punctuation on a token: `…see scripts/x.py.` must not become "a file called
# x.py.", and it must not fall through the no-extension exemption either.
_TRAILING_PUNCT = ".,;:)]\"'"


def pathish(tok):
    """Normalise one token to the path it claims, or None. Handles the `path:line` suffix and
    sentence punctuation; the ROOT test is what separates a claim from ordinary prose."""
    t = tok.rstrip(_TRAILING_PUNCT)
    m = LINE_REF_RE.match(t)
    if m:
        t = m.group("p")
    if t.count("/") < 1 or SKIP_SCHEME.match(t) or not usable(t):
        return None
    if t.split("/")[0] + "/" not in ROOT_DIRS:
        return None
    return t


def extract(path, text):
    """[(target, kind)] where kind ∈ {link, bare, code} — links resolve relative to `path`, the
    other two against the repo root (with the Ansible bases, and the containing file, as
    alternative satisfiers). Link LABELS are masked out first: they are prose, and the extremely
    common `[`x/y.md`](../x/y.md)` shape would otherwise be counted a second time as a
    root-relative claim that does not exist. BACKTICKED spans are read one token at a time, so
    `` `ansible-playbook playbooks/site.yml` `` checks the playbook it names: BARE_RE's lookbehind
    has always refused a path that a backtick stands in front of, and that blind spot is HD-1168."""
    out = []
    for m in LINK_RE.finditer(text):
        t = m.group(1).split("#")[0]
        if t and usable(t):
            out.append((t, "link", m.start(1)))
    # Masked with SPACES, not with one space: the offsets must stay true or the clause the
    # negation exemption reads is the wrong piece of text.
    bare_text = LINK_SPAN_RE.sub(lambda m: " " * (m.end() - m.start()), text)
    for m in BARE_RE.finditer(bare_text):
        if usable(m.group("p")):
            out.append((m.group("p"), "bare", m.start("p")))
    for span in CODE_SPAN_RE.finditer(bare_text):
        for tok in re.finditer(r"\S+", span.group(1)):
            t = pathish(tok.group(0))
            if t:
                out.append((t, "code", span.start(1) + tok.start()))
    return out


_ROLE_DIRS = None


def bases(target):
    """Where a root-relative claim is looked for, in order. README §2: one physical root `IaC/`,
    and the Ansible tree lives under `IaC/ansible/` — so `group_vars/all/main.yml` and
    `playbooks/site.yml` are how prose writes a path in that tree (HD-1118 made scripts resolve
    from the repo root; the same fact puts the Ansible names one directory deeper). For the names
    Ansible resolves from inside a role (`templates/x.j2`), every role's copy of that directory is
    a satisfier — the same bargain this gate already strikes when a skill writes `scripts/x.py`
    about its own `skills/x/scripts/x.py`: report defects, not stylistic preferences."""
    global _ROLE_DIRS
    head = target.split("/")[0] + "/"
    out = [""]
    if head in ANSIBLE_ROOTS:
        out += list(ANSIBLE_BASES)
    if head in ROLE_LOCAL:
        if _ROLE_DIRS is None:
            rd = ROOT / "IaC" / "ansible" / "roles"
            _ROLE_DIRS = [f"IaC/ansible/roles/{p.name}/"
                          for p in sorted(rd.iterdir()) if p.is_dir()] if rd.is_dir() else []
        out += _ROLE_DIRS
    return out


RENDER_MAP = {}   # {template path: directory its rendered output lands in}


def load_render_map():
    """{template: output-dir} parsed out of playbooks/render-docs.yml (src:/dest: pairs)."""
    play = ROOT / "IaC" / "ansible" / "playbooks" / "render-docs.yml"
    if not play.is_file():
        return {}
    text = play.read_text(encoding="utf-8")
    out = {}
    pair = re.compile(
        r'src:\s*"?[^"\n]*?([\w.-]+\.j2)"?[\s\S]{0,200}?'
        r'dest:\s*"?[^"\n]*?([\w./{%-][\w./{}% -]*)"',
    )
    for m in pair.finditer(text):
        tmpl, dest = m.group(1), m.group(2).strip()
        for f in files_of_templates():
            if f.endswith("/" + tmpl):
                out[f] = os.path.dirname(os.path.normpath(dest.replace("{{ playbook_dir }}",
                                                                       "IaC/ansible")))
    return out


def files_of_templates():
    return getattr(load_render_map, "_files", [])


def resolve(origin, kind, target, render_map=None):
    if kind == "link":
        base = (render_map or {}).get(origin, os.path.dirname(origin))
    else:
        base = ""
    return os.path.normpath(os.path.join(base, target)).replace(os.sep, "/")


# ------------------------------------------------------------------ the carried-debt ledger
#
# This is NOT the frozen-archive list. FROZEN names two files whose paths are statements about a
# date; this file names INDIVIDUAL citations the repo has agreed to carry while it decides them,
# so that widening the matcher does not turn the suite permanently red (and so the gate cannot be
# quietly muted the way one that prints dozens of findings is). Same discipline as
# gate/doc_headings_baseline.txt and gate/twin_baseline.txt, and for the same reason: the debt is
# LISTED, keyed on the citing file and the path as written, never on a line number.
#
#   GROWTH  a dangling citation this file does not carry, or carries fewer times than it appears.
#   STALE   a line here whose path now resolves. Clearing debt is a two-line change: fix the
#           citation AND delete its ledger line in the same commit, or the entry becomes a free
#           pass for the next wrong path written at that key.
#
# Re-derive the body, never hand-edit it and never quote its counts (CONVENTIONS §2):
#     python3 scripts/gate/check_doc_path_refs.py --show-baseline > /tmp/refs-baseline.txt
# then replace the lines below the header with that output; stdout is the body, the summary the
# redirect must not overwrite goes to stderr. Why a given entry is still carried belongs to the
# todo.md row that owns this gate.
BASELINE = "scripts/gate/path_refs_baseline.txt"


def key_of(hit):
    """(citing file, path as it resolves). NOT the line number: a `todo.md` row grows, and a ledger
    keyed on position would report that edit as new debt."""
    return (hit[0], hit[1])


def render_ledger(hits):
    """The ledger body for a population: `<count>TAB<citing file>TAB<path>`, sorted. The count is
    how many copies of that one citation dangle, so repeating a path twice in one file cannot be
    cleared by deleting one line."""
    counts = {}
    for h in hits:
        counts[key_of(h)] = counts.get(key_of(h), 0) + 1
    return "".join("%d\t%s\t%s\n" % (n, k[0], k[1]) for k, n in sorted(counts.items()))


def parse_ledger(text):
    """`{key: count}` plus one complaint per malformed line — a line that can never match a
    citation is silent debt that reads as coverage, so refuse instead."""
    counts, bad = {}, []
    for n, line in enumerate(text.split("\n"), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 3 or not parts[0].isdigit() or not parts[1].strip() or not parts[2].strip():
            bad.append("%s:%d -- want <count>TAB<citing file>TAB<path>" % (BASELINE, n))
            continue
        key = (parts[1], parts[2])
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


def ledger_verdict(hits, ledger):
    """(kept, frozen, cleared) for a population read against the ledger. Carried debt comes out of
    the findings; a citation the ledger does not carry is GROWTH and stays in; a ledger line whose
    citation now resolves comes back as CLEARED, because an entry that outlives its citation would
    otherwise exempt the next one (gate/iac_identifier_allowlist.txt states the same rule)."""
    budget = dict(ledger)
    kept, frozen = [], []
    for h in sorted(hits):
        k = key_of(h)
        if budget.get(k, 0) > 0:
            budget[k] -= 1
            frozen.append(h)
        else:
            kept.append(h)
    cleared = [(k, n) for k, n in sorted(budget.items()) if n > 0]
    return kept, frozen, cleared


NEGATION_RE = re.compile(
    r"(?:does|do) not exist|doesn.t exist|not (?:yet )?(?:created|written|present|committed)|"
    r"to be (?:written|created)|planned|TODO: create|create if missing|will (?:be )?exist|"
    r"there (?:is|are) no\b|not in git|(?:ignored |skipped |used )?if (?:not )?(?:found|absent|present)", re.I)
# The clause is the window a state word may act in, and the window is SHORT. A `todo.md` row is
# one line of several kilobytes, so "the line" is not a scope, and even "the cell" is too
# wide: the HD-480/481 row says a mechanism `was never built` and its neighbour says a `Group`
# column is pending — either phrase would shelter every wrong path written in the same row. So:
# nearest clause edge, and never further than CLAUSE_WINDOW characters from the path it excuses.
# A NEWLINE IS an edge, which is what makes the rule checkable by eye: the state word has to
# travel on the SAME line as the path it excuses. A wrapped list item that parks "DO NOT
# EXIST" on the following line has to be re-wrapped by its author, not read generously
# here. `:` deliberately does NOT cut: a table row's cells precede its prose and a "⏳" marker ends
# with one, so cutting there would open a shelter inside every queue row of `todo-table.md`.
CLAUSE_EDGE = re.compile(r"[;|]|\n|\.\s|\?\s|!\s")
CLAUSE_WINDOW = 120


def clause_of(text, pos):
    """The sentence-ish run around `pos`, bounded both ways by the nearest clause edge."""
    lo = max(0, pos - CLAUSE_WINDOW)
    edges = [m.end() for m in CLAUSE_EDGE.finditer(text, lo, pos)]
    start = edges[-1] if edges else lo
    m = CLAUSE_EDGE.search(text, pos)
    return text[start:m.start() if m else min(len(text), pos + CLAUSE_WINDOW)]


def candidates(origin, kind, target, render_map=None):
    """Every place a claim can be satisfied, in order: the resolution `resolve()` gives, the
    Ansible bases `bases()` names for a root-relative claim, and the containing file's own
    directory. The GIT-IGNORED exemption asks the same list, because `git check-ignore` answers
    for the path it is handed and `IaC/router/rendered/` is a directory entry the tree cannot show."""
    out = [resolve(origin, kind, target, render_map)]
    if kind in ("bare", "code"):
        out += [os.path.normpath(b + target) for b in bases(target)]
        out.append(os.path.normpath(os.path.join(os.path.dirname(origin), target)))
    return [os.path.normpath(c) for c in out]


def ignore_candidates(origin, kind, target, render_map=None):
    """The two spellings `git check-ignore` may be asked about: the path AS WRITTEN and the path
    read from the directory of the citing file. The Ansible bases are deliberately NOT asked:
    `spark/.gitignore` ignores `spark/ansible/host_vars/`, so widening the ignore probe to every
    base would excuse `host_vars/router.kogler.si.yml` — a file the repo's prose says does not
    exist — just because some project somewhere ignores that shape. Ignore is a claim about a
    path, not about a guess."""
    out = [resolve(origin, kind, target, render_map)]
    if kind in ("bare", "code"):
        out.append(os.path.normpath(os.path.join(os.path.dirname(origin), target)))
    return [os.path.normpath(c) for c in out]


def check(corpus, exists, ignored=frozenset(), verbose=False, render_map=None, ledger=None):
    """corpus: {relpath: text}; exists: callable(relpath) -> bool.
    Returns (findings, skipped, stats).

    A root-relative path is satisfied if it resolves from the repository root, from one of the
    Ansible bases `bases()` names, or from the containing file (the way a skill writes
    `scripts/shelly.py` about its own `skills/shelly/scripts/shelly.py`). Accepting any of those
    resolutions is deliberate: this tool reports defects, not stylistic preferences, and a path
    that names a real file somewhere unambiguously reachable is not a broken promise."""
    findings, skipped, seen, hits = [], [], set(), []
    for origin, text in corpus.items():
        for target, kind, pos in extract(origin, text):
            resolved = resolve(origin, kind, target, render_map)
            if resolved.startswith("..") or resolved == ".":
                skipped.append((origin, target, "escapes the repo"))
                continue
            cands = candidates(origin, kind, target, render_map)
            ex, why = is_exempt(target, origin)
            if not ex and any(c in ignored for c in ignore_candidates(origin, kind, target,
                                                                       render_map)):
                ex, why = True, "git-ignored generated file"
            if ex:
                if verbose:
                    skipped.append((origin, target, why))
                continue
            if any(exists(c) for c in cands):
                continue
            line_no = text.count("\n", 0, pos) + 1
            if NEGATION_RE.search(clause_of(text, pos)):
                # Prose that SAYS the path is missing ("`scripts/harness/install-pi-debian.sh` does
                # not exist; needs >= 22.19.0") is a tracked gap, not a false claim. The exemption is
                # bound to the CLAUSE carrying the path — never the line, which in a `todo.md` row is
                # the whole row — so it cannot shelter a stale citation beside it. That boundary is
                # the canary --self-test breeds.
                if verbose:
                    skipped.append((origin, target, "clause states the file does not exist"))
                continue
            key = (origin, resolved)
            if key in seen:
                continue
            seen.add(key)
            hits.append((origin, resolved, kind, line_no))
    kept, frozen, cleared = (hits, [], []) if ledger is None else ledger_verdict(hits, ledger)
    findings = [f"{o}:{ln}: {k} \u2192 {p} does not exist" for o, p, k, ln in kept]
    for o, p, k, ln in frozen:
        skipped.append((o, p, "carried by the committed ledger"))
    stats = {"hits": hits, "frozen": frozen, "cleared": cleared}
    return findings, skipped, stats


def git_files():
    # git emits UTF-8 filenames; decode them explicitly. `text=True` lets subprocess decode
    # with the LOCALE default, which on a Windows seat is cp1252 — a non-decodable byte makes
    # r.stdout None and this crashes (HD-1135#2). text=False + .decode("utf-8") is the
    # byte-truthful form and works on any platform (git ls-files -z is NUL-separated bytes).
    r = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z", "--",
                        "*.md", "*.yml", "*.yaml", "*.j2"],
                       capture_output=True)
    if r.returncode != 0:
        print(f"ERROR: git ls-files failed: {r.stderr.decode('utf-8', 'replace').strip()}", file=sys.stderr)
        sys.exit(2)
    return [f for f in r.stdout.decode("utf-8", "replace").split("\0") if f]


def git_ignored(paths):
    """Ask git which of these absences are INTENTIONAL. Chunked, and a failed chunk is retried
    line by line: one weird candidate (an `\u2026` ellipsis in a doc path was enough) must not
    silently disable the exemption for the whole corpus \u2014 that is how the generated
    post_install_with_secrets.sh, which .gitignore declares by name, came to be reported as a
    defect while the isolated test said it was fine."""
    paths = [p for p in paths if p and not p.startswith("-")]
    out = set()
    for i in range(0, len(paths), 64):
        chunk = paths[i:i + 64]
        # input is the joined UTF-8 paths; git answers UTF-8 — same explicit-decode rule as git_files.
        r = subprocess.run(["git", "-C", str(ROOT), "check-ignore", "--stdin"],
                           input="\n".join(chunk).encode("utf-8"), capture_output=True)
        if r.returncode in (0, 1):
            out.update(x for x in r.stdout.decode("utf-8", "replace").splitlines() if x)
            continue
        for one in chunk:
            r2 = subprocess.run(["git", "-C", str(ROOT), "check-ignore", "--", one],
                                capture_output=True)
            if r2.returncode == 0:
                out.add(one)
    return frozenset(out)


def self_test():
    """The checker must catch the defect in EVERY form a citation takes and leave the legitimate
    shapes alone, and the ledger must fail in BOTH directions. Each arm is one class of blindness
    the matcher can have; the tree is bred in a temp directory so the assertions are about the
    matcher and not about what this checkout happens to contain today."""
    global ROOT, _ROLE_DIRS
    saved_root, saved_roles = ROOT, _ROLE_DIRS
    root = tempfile.mkdtemp(prefix="check-doc-path-refs-")
    fails = []

    def arm(name, cond, detail=""):
        print(f"  {'OK  ' if cond else 'FAIL'}  {name}{'' if cond else ' -- ' + detail}")
        if not cond:
            fails.append(name)

    docs_a = "\n".join([
        "[good](../spark/reports/x.md)",
        "[bad](../spark/reports/gone.md)",
        "`scripts/tool.py` and `scripts/glob/**/*.j2` and `scripts/probe-<n>.py`",
        "`IaC/host/gen.sh` `#anchor` [x](#anchor) [ext](https://e.com/p.md)",
        "`IaC/host/gone-too.sh` does not exist yet - planned",
        "a skill says `scripts/tool.py` about its own copy",
        "a link label [says `spark/tool.md`](../spark/reports/x.md) is prose, not a second claim",
        "`scripts/gone-backtick.py` is the tool this lane will run",
        "`ansible-playbook playbooks/gone-cmd.yml --check` runs the play",
        "see `scripts/tool.py:12` and `scripts/gone-line.py:3-9`",
        "`IaC/host/absent-first.sh` does not exist yet; `IaC/host/absent-second.sh` runs next",
        "the leg lives in `roles/real/tasks/main.yml`, and `roles/real/tasks/gone-leg.yml` does not",
        "the template is `templates/real.j2`",
        "\u2192 spark/tool.md in prose, an arrow, not a path",
    ]) + "\n"
    files = {
        "docs/a.md": docs_a,
        "docs/sibling.md": "the real sibling of the RENDERED document\n",
        "IaC/ansible/templates/tpl.md.j2": "[`sibling.md`](sibling.md)\n",
        "IaC/ansible/roles/real/tasks/main.yml": "- debug: msg=ok\n",
        "IaC/ansible/roles/real/templates/real.j2": "ok\n",
        "IaC/host/gen.sh": "#!/bin/sh\n",
        "spark/reports/x.md": "ok\n",
        "spark/tool.md": "ok\n",
        "scripts/tool.py": "ok\n",
        "reports/changelog.md": "deleted `IaC/ansible/playbooks/gone.yml` here once\n",
        "reports/run-log.md": ("ran `IaC/ansible/playbooks/gone.yml`, then "
                               "`scripts/never-existed-4242.py` in the same pass\n"),
        "docs/moved.md": "the file that MOVED, by basename\n",
    }
    tree_root = Path(root)
    for rel, text in files.items():
        f = tree_root / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(text, encoding="utf-8")
    (tree_root / "archive").mkdir(exist_ok=True)
    (tree_root / "archive" / "gone.yml").write_text("moved here\n", encoding="utf-8")
    ROOT, _ROLE_DIRS = tree_root, None
    try:
        rmap = {"IaC/ansible/templates/tpl.md.j2": "docs"}
        corpus = {rel: (tree_root / rel).read_text(encoding="utf-8") for rel in files}
        found, skipped, stats = check(
            corpus, lambda p: (tree_root / p).exists() or (tree_root / p).is_dir(),
            ignored={"IaC/host/gen.sh"}, render_map=rmap, ledger={})
        got = {(f.split(":")[0], f.split(" \u2192 ")[1].split(" does not exist")[0]) for f in found}

        def hits(*pairs):
            return [p for p in pairs if p in got]

        arm("link canary (HD-490): the bred dangling link is caught",
            hits(("docs/a.md", "spark/reports/gone.md")) == [("docs/a.md", "spark/reports/gone.md")],
            str(sorted(got)))
        want_back = [("docs/a.md", "scripts/gone-backtick.py")]
        arm("backtick arm (HD-1168): a dangling `path` is caught -- the form the old lookbehind "
            "handed to nobody", hits(*want_back) == want_back, str(sorted(got)))
        want_cmd = [("docs/a.md", "playbooks/gone-cmd.yml")]
        arm("command-span arm: the SECOND token of `ansible-playbook playbooks/x.yml` is checked",
            hits(*want_cmd) == want_cmd, str(sorted(got)))
        want_role = [("docs/a.md", "roles/real/tasks/gone-leg.yml")]
        arm("role-relative arm: a dangling `roles/...` path is caught",
            hits(*want_role) == want_role, str(sorted(got)))
        green = [("docs/a.md", "scripts/tool.py"), ("docs/a.md", "roles/real/tasks/main.yml"),
                 ("docs/a.md", "templates/real.j2"), ("docs/a.md", "playbooks/site.yml")]
        arm("the SAME paths in BOTH forms stay green: bare prose, backticked, role-relative",
            not hits(*green), str(sorted(set(green) & got)))
        arm("`path:line` arm: the FILE is the promise -- `scripts/tool.py:12` is green and "
            "`scripts/gone-line.py:3-9` is still caught",
            ("docs/a.md", "scripts/gone-line.py") in got and
            not hits(("docs/a.md", "scripts/tool.py:12"), ("docs/a.md", "scripts/tool.py.12")),
            str(sorted(got)))
        arm("clause arm (the todo.md-row blind spot): a `does not exist yet` in one clause may NOT "
            "shelter a plainly-asserted path in the next clause of the SAME line",
            ("docs/a.md", "IaC/host/absent-second.sh") in got and
            ("docs/a.md", "IaC/host/absent-first.sh") not in got, str(sorted(got)))
        arm("role-local template arm: `<role>/templates/x.j2` satisfies `templates/x.j2`",
            ("docs/a.md", "templates/real.j2") not in got, str(sorted(got)))
        arm("exemptions held: the glob, the placeholder, the frozen archive, the git-ignored "
            "generated file, the anchor, the external URL and the non-path-with-no-extension",
            not hits(("docs/a.md", "scripts/glob/**/*.j2"), ("docs/a.md", "scripts/probe-<n>.py"),
                     ("docs/a.md", "IaC/host/gen.sh"), ("docs/a.md", "https://e.com/p.md"),
                     ("reports/changelog.md", "IaC/ansible/playbooks/gone.yml")))
        arm("dated-record arm: inside reports/, a MOVED path is excused and an INVENTED one is not "
            "(the lookup is the exemption; FROZEN was not widened to get here)",
            ("reports/run-log.md", "scripts/never-existed-4242.py") in got and
            ("reports/run-log.md", "IaC/ansible/playbooks/gone.yml") not in got, str(sorted(got)))
        arm("render map: a generated-doc template resolves its links from the doc it renders into",
            not hits(("IaC/ansible/templates/tpl.md.j2", "docs/sibling.md")), str(sorted(got)))

        # BOTH halves of the ledger ratchet. Frozen debt, growth, and a line whose path went back
        # to existing -- an entry that outlives its citation must redden, or it exempts the next one.
        h = [("docs/a.md", "scripts/gone-backtick.py", "code", 8)]
        kept, frozen, cleared = ledger_verdict(h, {("docs/a.md", "scripts/gone-backtick.py"): 1})
        arm("ledger ratchet, frozen half: a carried citation is not reported as growth",
            kept == [] and frozen == h and cleared == [], f"{kept} {frozen} {cleared}")
        kept, frozen, cleared = ledger_verdict(h, {})
        arm("ledger ratchet, growth half: the same citation with no ledger line reddens",
            kept == h and cleared == [], f"{kept} {frozen} {cleared}")
        kept, frozen, cleared = ledger_verdict([], {("docs/a.md", "scripts/gone-backtick.py"): 1})
        arm("ledger ratchet, stale half: a ledger line whose citation now resolves comes back CLEARED",
            kept == [] and cleared == [(("docs/a.md", "scripts/gone-backtick.py"), 1)],
            f"{kept} {frozen} {cleared}")
        counts, bad = parse_ledger(render_ledger(h))
        arm("render_ledger/parse_ledger round-trip: the body the redirect writes is the body that "
            "parses", counts == {("docs/a.md", "scripts/gone-backtick.py"): 1} and bad == [],
            f"{counts} {bad}")
        arm("a malformed ledger line is a loud refusal, never silent coverage",
            parse_ledger("nope\tfields\there")[1] != [], "parsed cleanly")
        arm("the ledger key is the citation, not its position: render_ledger is sorted and stable",
            render_ledger(h + h) == "2\tdocs/a.md\tscripts/gone-backtick.py\n",
            repr(render_ledger(h + h)))
    finally:
        ROOT, _ROLE_DIRS = saved_root, saved_roles
        shutil.rmtree(root, ignore_errors=True)
    if fails:
        print(f"\n  {len(fails)} SELF-TEST ARM(S) FAILED: {fails}")
        return 1
    print("  OK    every arm held: the matcher sees prose, backticks, command spans, role-relative "
          "names, path:line suffixes and clause-scoped state words; the ledger fails in both "
          "directions; every exemption stayed quiet")
    return 0


def main():
    verbose = "--verbose" in sys.argv
    if "--self-test" in sys.argv:
        return self_test()
    # `--show-baseline` makes STDOUT the ledger file body, so every informational line has to go to
    # stderr: one summary sentence landing in column 1 of the ledger is a malformed line that reads
    # as coverage.
    say = sys.stderr if "--show-baseline" in sys.argv else sys.stdout
    files = git_files()
    load_render_map._files = files
    render_map = load_render_map()
    corpus = {}
    for f in files:
        try:
            corpus[f] = (ROOT / f).read_text(encoding="utf-8")
        except (UnicodeDecodeError, FileNotFoundError):
            pass
    targets, probe = set(), set()
    for origin, text in corpus.items():
        for target, kind, _pos in extract(origin, text):
            targets.add(resolve(origin, kind, target, render_map))
            probe.update(ignore_candidates(origin, kind, target, render_map))
    missing = sorted(c for c in probe if not (ROOT / c).exists())
    # Ask git about BOTH spellings: `.gitignore` declares the rendered-router dir as
    # `IaC/router/rendered/`, and `git check-ignore` only answers 0 for a directory-only pattern
    # when the queried path carries the trailing slash. Normalising the slash away — which is what
    # a path comparison has to do — would silently drop the exemption for every generated DIR.
    ignored = {os.path.normpath(p) for p in git_ignored(missing + [m + "/" for m in missing])}
    ledger = read_ledger()
    findings, skipped, stats = check(
        corpus, lambda p: (ROOT / p).exists() or (ROOT / p).is_dir(), ignored, verbose,
        render_map, ledger)
    if render_map:
        print(f"render map honoured: {len(render_map)} generated-doc template(s) resolve their "
              f"links from the document they render into", file=say)
    print(f"scanned {len(corpus)} files, {len(targets)} distinct path targets", file=say)
    if skipped and verbose:
        print(f"exempted {len(skipped)} (patterns, placeholders, frozen and dated archives, "
              f"generated files, external links, clauses that say the file is missing):", file=say)
        for o, t, why in skipped[:25]:
            print(f"  ·  {o}: {t}  [{why}]", file=say)
    if "--show-baseline" in sys.argv:
        # stdout is the file body, so re-deriving is one redirect; the summary goes to stderr.
        body = render_ledger(stats["hits"])
        sys.stdout.write(body)
        print("--show-baseline: %d ledger line(s) for %d dangling citation(s) across %d file(s) "
              "-- replace the body of %s with this, keep its header"
              % (body.count("\n"), len(stats["hits"]), len(corpus), BASELINE), file=sys.stderr)
        return 0
    print(f"ledger carried: {len(stats['frozen'])} citation(s); "
          f"{len(ledger)} line(s) in {BASELINE}")
    if stats["cleared"]:
        print(f"\n{len(stats['cleared'])} LEDGER LINE(S) NOW RESOLVE — stale debt, and a free pass "
              "for the next wrong path written at that key:")
        for (origin, target), n in stats["cleared"]:
            print(f"  FAIL  {origin}: {target}  ({n} carried, all now present)")
        print(f"\nDelete those line(s) from {BASELINE} in the same change that fixed the citation.")
    if findings:
        print(f"\n{len(findings)} DANGLING PATH REFERENCE(S) (growth, not carried debt):")
        for f in findings:
            print(f"  FAIL  {f}")
        print("\nFix the citation to the path that exists, or delete the claim, or — when it is "
              "pre-existing debt the repo has decided to carry — name it in the ledger "
              f"({BASELINE}) AND in the todo.md row that owns this gate. Never leave "
              "a plausible-sounding path in prose because it is the one thing a reader cannot "
              "distinguish from a real one until they try to run it.")
        return 1
    require_corpus(len(corpus), 200, "check_doc_path_refs scanned corpus")
    # The number is the carried debt this run depends on, not a corpus count: a green line that
    # says "all clear" while a ledger exempts nineteen citations would be the view lying again.
    print("OK: no new dangling path reference; %d citation(s) carried by %s"
          % (len(stats["frozen"]), BASELINE))
    return 0


if __name__ == "__main__":
    sys.exit(main())
