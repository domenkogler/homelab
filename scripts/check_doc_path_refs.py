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

WHAT MAKES THIS TRUSTWORTHY IS THAT IT KNOWS WHEN IT IS WRONG. Four shapes look like
dangling refs and are not, and each is exempted with a reason printed in --verbose:

  1. GLOBS (`templates/docker_services/**/*.j2`) — a pattern names a set, not a file.
  2. PLACEHOLDERS (`scripts/probe-<name>.py`, `{{ item.path }}`) — explicitly unfinished.
  3. THE FROZEN ARCHIVES (`reports/changelog.md`, `reports/deployment-journal.md`) — these
     record what the tree looked like on a date. `IaC/.../prometheus-web-config.yml.j2` was
     real when its changelog row was written and was deleted later; rewriting the row to
     point at the replacement would falsify the record. CONVENTIONS: archive-only.
  4. GIT-IGNORED GENERATED FILES (`IaC/host/post_install_with_secrets.sh`) — the manual's
     procedure is "generate it, use it, delete it". `git check-ignore` is the authority for
     whether absence is intentional, which is why this exemption is a lookup and not a list.

Markdown LINKS resolve relative to the containing file (`../reports/stability/README.md`
from `spark/llm-profiles/` is `spark/reports/stability/README.md`, and one of them was
written as `../spark/...`, silently pointing at `spark/spark/` — a real defect this script
found on its first run). Bare paths in prose/code resolve relative to the repo root, which
is how humans write them.

--self-test does what every other gate here does: breeds a dangling ref in a synthetic tree
and FAILS if it is not caught, plus breeds the four exemptions and fails if any of them is
flagged. A checker that has never been seen to fail is not a checker.

Stdlib + git only. Exit 0 = no dangling refs; 1 = dangling refs found; 2 = could not run.
"""
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# CONVENTIONS: frozen, archive-only records. A path inside them is a statement about a date,
# not a promise about the working tree, so it may not be "fixed" by editing history.
FROZEN = {"reports/changelog.md", "reports/deployment-journal.md"}

# Roots that mean "relative to the repository root" when they appear bare in prose.
ROOT_DIRS = ("IaC/", "scripts/", "docs/", "spark/", "reports/", "deploy/")

LINK_RE = re.compile(r"\[[^\]]*\]\(<?([^)>\s]+)>?\)")
BARE_RE = re.compile(
    r"(?<![\w/`~.\-])(?P<p>(?:IaC|scripts|docs|spark|reports|deploy)/"
    r"[^\s`'\"|<>)\],;]*[A-Za-z0-9_])"
)
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
    if target.endswith((".md", ".yml", ".yaml", ".j2", ".py", ".sh", ".json", ".csv", ".gz",
                        ".txt", ".ini", ".conf", ".service", ".toml", ".sls", ".gz")) is False \
            and "/" in target and not target.endswith("/"):
        # No recognised extension and not a directory: almost always prose that merely
        # looks like a path (a name, a branch, a URL fragment). Reported only in --verbose.
        return True, "no extension and not a directory"
    return False, ""


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


def extract(path, text):
    """[(target, kind)] where kind ∈ {link, bare} — links resolve relative to `path`, bare
    paths resolve against the repo root. Link LABELS are masked out first: they are prose, and
    the extremely common `[`x/y.md`](../x/y.md)` shape would otherwise be counted a second
    time as a root-relative claim that does not exist."""
    out = []
    for m in LINK_RE.finditer(text):
        t = m.group(1).split("#")[0]
        if t and usable(t):
            out.append((t, "link"))
    bare_text = LINK_SPAN_RE.sub(" ", text)
    for m in BARE_RE.finditer(bare_text):
        if usable(m.group("p")):
            out.append((m.group("p"), "bare"))
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


NEGATION_RE = re.compile(
    r"does not exist|doesn.t exist|not (?:yet )?(?:created|written|present|committed)|"
    r"to be (?:written|created)|planned|TODO: create|create if missing|will (?:be )?exist", re.I)


def check(corpus, exists, ignored=frozenset(), verbose=False, render_map=None):
    """corpus: {relpath: text}; exists: callable(relpath) -> bool. Returns findings.

    A BARE path is satisfied if it resolves EITHER from the repository root (the way docs and
    IaC comments write them) or from the containing file (the way a skill writes
    `scripts/shelly.py` about its own `skills/shelly/scripts/shelly.py`). Accepting either
    resolution is deliberate: this tool reports defects, not stylistic preferences, and a path
    that names a real file somewhere unambiguously reachable is not a broken promise."""
    findings, skipped, seen = [], [], set()
    for origin, text in corpus.items():
        for target, kind in extract(origin, text):
            resolved = resolve(origin, kind, target, render_map)
            if resolved.startswith("..") or resolved == ".":
                skipped.append((origin, target, "escapes the repo"))
                continue
            ex, why = is_exempt(target, origin)
            if not ex and resolved in ignored:
                ex, why = True, "git-ignored generated file"
            if ex:
                if verbose:
                    skipped.append((origin, target, why))
                continue
            alt = resolve(origin, "link", target, {}) if kind == "bare" else None
            if exists(resolved) or (alt is not None and exists(alt)):
                continue
            line_no = next((i for i, l in enumerate(text.splitlines(), 1)
                            if target in l), 0)
            if NEGATION_RE.search(text.splitlines()[line_no - 1] if line_no else ""):
                # Prose that SAYS the path is missing ("`scripts/install-pi-debian.sh` does not
                # exist; needs >= 22.19.0") is a tracked gap, not a false claim. The exemption is
                # bound to that wording on that line, so it cannot shelter a stale citation: the
                # canary in --self-test breeds a plain citation and requires it to be caught.
                if verbose:
                    skipped.append((origin, target, "line states the file does not exist"))
                continue
            if True:
                key = (origin, kind, resolved)
                if key in seen:
                    continue
                seen.add(key)
                findings.append(f"{origin}:{line_no}: {kind} \u2192 {resolved} does not exist")
    return findings, skipped


def git_files():
    r = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z", "--",
                        "*.md", "*.yml", "*.yaml", "*.j2"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print(f"ERROR: git ls-files failed: {r.stderr.strip()}", file=sys.stderr)
        sys.exit(2)
    return [f for f in r.stdout.split("\0") if f]


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
        r = subprocess.run(["git", "-C", str(ROOT), "check-ignore", "--stdin"],
                           input="\n".join(chunk), capture_output=True, text=True)
        if r.returncode in (0, 1):
            out.update(x for x in r.stdout.splitlines() if x)
            continue
        for one in chunk:
            r2 = subprocess.run(["git", "-C", str(ROOT), "check-ignore", "--", one],
                                capture_output=True, text=True)
            if r2.returncode == 0:
                out.add(one)
    return frozenset(out)


def self_test():
    """The checker must catch the defect and leave the four legitimate shapes alone."""
    tree = {
        "docs/a.md": ("[good](../spark/reports/x.md)\n"
                      "[bad](../spark/reports/gone.md)\n"
                      "`scripts/tool.py` and `scripts/glob/**/*.j2` and `scripts/probe-<n>.py`\n"
                      "`IaC/host/gen.sh` `#anchor` [x](#anchor) [ext](https://e.com/p.md)\n"
                      "`IaC/host/gone-too.sh` does not exist yet — planned\n"
                      "a skill says `scripts/tool.py` about its own copy\n"),
        "IaC/ansible/templates/tpl.md.j2": "[`sibling.md`](sibling.md)\n",
        "docs/sibling.md": "the real sibling of the RENDERED document",
        "spark/reports/x.md": "ok",
        "scripts/tool.py": "ok",
        "reports/changelog.md": "deleted `IaC/ansible/playbooks/gone.yml` here once\n",
    }
    present = set(tree) | {"IaC/host/gen.sh"}     # the ignored/generated shape
    rmap = {"IaC/ansible/templates/tpl.md.j2": "docs"}
    findings, _ = check(tree, lambda p: p in present, ignored={"IaC/host/gen.sh"},
                        render_map=rmap)
    ok = True
    if len(findings) != 1 or "spark/reports/gone.md" not in findings[0]:
        print(f"  FAIL  self-test: expected exactly the one bred dangling ref, got {findings}")
        ok = False
    else:
        print(f"  OK    canary: bred dangling ref caught — {findings[0]}")
    for good in ("x.md", "scripts/tool.py"):
        if not any(good in f for f in findings) and good == "gone.md":
            ok = False
    if not ok:
        return 1
    print("  OK    exemptions held: the glob, the placeholder, the frozen archive, "
          "the git-ignored generated file, the anchor and the external URL were all left alone")
    return 0


def main():
    verbose = "--verbose" in sys.argv
    if "--self-test" in sys.argv:
        return self_test()
    files = git_files()
    load_render_map._files = files
    render_map = load_render_map()
    corpus = {}
    for f in files:
        try:
            corpus[f] = (ROOT / f).read_text(encoding="utf-8")
        except (UnicodeDecodeError, FileNotFoundError):
            pass
    candidates = set()
    for origin, text in corpus.items():
        for target, kind in extract(origin, text):
            candidates.add(resolve(origin, kind, target, render_map))
    ignored = git_ignored(sorted(c for c in candidates if not (ROOT / c).exists()))
    findings, skipped = check(
        corpus, lambda p: (ROOT / p).exists() or (ROOT / p).is_dir(), ignored, verbose,
        render_map)
    if render_map:
        print(f"render map honoured: {len(render_map)} generated-doc template(s) resolve their "
              f"links from the document they render into")
    print(f"scanned {len(corpus)} files, {len(candidates)} distinct path targets")
    if skipped and verbose:
        print(f"exempted {len(skipped)} (patterns, placeholders, frozen archives, "
              f"generated files, external links):")
        for o, t, why in skipped[:25]:
            print(f"  ·  {o}: {t}  [{why}]")
    if findings:
        print(f"\n{len(findings)} DANGLING PATH REFERENCE(S):")
        for f in findings:
            print(f"  FAIL  {f}")
        print("\nFix the citation to the path that exists, or delete the claim. Never leave "
              "a plausible-sounding path in prose because it is the one thing a reader cannot "
              "distinguish from a real one until they try to run it.")
        return 1
    print("OK: every local path a doc cites resolves to something in the tree")
    return 0


if __name__ == "__main__":
    sys.exit(main())
