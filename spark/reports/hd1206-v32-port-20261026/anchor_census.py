"""Read-only anchor census for the v0.32 lineage (HD-1206).

One row per `edit()`-style call in every staged day-0 patcher, counted against the BASE image's own
copy of the target file:

    old == 1            the anchor still holds, the patcher will apply;
    old == 0, new  > 0  the base ALREADY has the post-state — the patcher is a no-op here;
    old == 0, new  == 0 the effect is absent at this base — re-anchor, or park it for disposition.

That is the whole point of the census: a build answers these questions one attempt per surprise, and
each attempt costs ~12 G of build cache. Nothing here writes — the patchers are mounted read-only,
their anchors are read out of the source with `ast`, and each is counted with `str.count`.

WHY THE PATCHER SET IS DERIVED AND NOT LISTED. A hand-kept list of patcher names is a second source of
truth for a question `Dockerfile.v32` already answers: which patchers the build runs, in which step,
and which of them it only guards. A name missing from the list is invisible to the census and the
census prints a green tally anyway — that is how a "census clean" could once be produced while the
step-14 patcher was never counted at all. So the set is read out of the Dockerfile here, in step
order: a `COPY src/patch_*.py` and the `RUN python3 /tmp/patch_*.py` that applies it make a step
`applied`, a step that names a patcher in prose and greps the post-state instead makes it
`guard-only`, and the `--integrity` cross-check reddens on any patcher present in the staged `src/`
that no step names. `--self-test` breeds that last shape and requires it to redden.

Usage (inside the base image, staged patchers mounted at /src, the Dockerfile mounted at /Dockerfile):

    python3 census.py /src                       # positional src, Dockerfile at /Dockerfile
    python3 census.py --src /src --dockerfile /Dockerfile
    python3 census.py --self-test                # enumeration + integrity, no base image needed

Exit: 0 = census ran and the derived set agrees with the staged corpus · 1 = anchor rows only, no
verdict could be read · 2 = the derived set and the staged corpus disagree, so the census is NOT a
statement about the build. Stdlib only.
"""
from __future__ import annotations

import argparse
import ast
import os
import re
import sys
import tempfile

SITE = "/usr/local/lib/python3.12/dist-packages"
EDIT_NAMES = ("edit", "patch", "insert", "repl", "add_gate", "sub")
SKIP_NAMES = ("init_logger", "open", "print", "len", "range", "str", "int", "set", "dict", "list")

# --- the derived patcher set -------------------------------------------------------------------
# `# ---- 13–17. The rest of upstream's patchers, verbatim ----`
STEP_HEADER = re.compile(r"^#\s*-{4,}\s*(\d+(?:\s*[–-]\s*\d+)?)\.(.*?)\s-{3,}\s*$")
# `COPY src/patch_hit_debug.py /tmp/patch_hit_debug.py` — group 2 is the staged path, group 3 the name.
COPY_PATCHER = re.compile(r"^\s*COPY\s+(\S*?(patch_[A-Za-z0-9_]+\.py))\s+(\S+)")
# `RUN python3 /tmp/patch_hit_debug.py && rm …` (and the `&&` continuations of a multi-line RUN).
# The target is read as a PATH, not as a name: a step may COPY a patcher under another file name, so
# `python3 /tmp/renamed_beta.py` still applies patch_beta.py and must count as running it.
RUN_TARGET = re.compile(r"python3\s+(\S+?\.py)")
# Any other mention, e.g. the prose line of a step that guards a post-state instead of applying one.
MENTION = re.compile(r"(patch_[A-Za-z0-9_]+\.py)")


def derive_patchers(dockerfile_text: str) -> list[dict]:
    """Every patcher `Dockerfile.v32` names, in step order.

    `kind` is `applied` (the step COPYs it), `guard-only` (the step names it and greps the post-state
    instead) or `run-unstaged` (it runs a patcher no COPY stages — a broken step). Three passes, and
    the order matters: the COPY pass is authoritative over a prose mention, so a patcher introduced
    in an earlier step's comment is still attributed to the step that applies it."""
    lines = dockerfile_text.splitlines()
    step_at: list[tuple[str, str]] = []
    step, title = "?", ""
    for line in lines:
        header = STEP_HEADER.match(line)
        if header:
            step, title = header.group(1).replace(" ", ""), header.group(2).strip()
        step_at.append((step, title))

    found: dict[str, dict] = {}
    order: list[str] = []
    def record(name: str, at: int, kind: str, staged: str = "src/") -> dict:
        rec = found.get(name)
        if rec is None:
            rec = {"name": name, "step": step_at[at][0], "title": step_at[at][1], "kind": kind,
                   "staged": staged, "line": at + 1, "runs": False}
            found[name] = rec
            order.append(name)
        return rec

    dest_map: dict[str, str] = {}
    for at, line in enumerate(lines):                     # 1. what the build stages
        copy = COPY_PATCHER.match(line)
        if not copy:
            continue
        staged = copy.group(1)
        rec = record(copy.group(2), at, "applied",
                     "src/" if staged.startswith("src/") else "(build dir)")
        rec.update({"kind": "applied", "step": step_at[at][0],
                    "title": step_at[at][1], "line": at + 1})
        # A step may COPY a patcher under another name; the RUN line then carries that name, so the
        # destination is the only thing that ties the run back to the patcher being counted.
        dest_map[copy.group(3).split()[0].rstrip("\\").rsplit("/", 1)[-1]] = rec["name"]

    for at, line in enumerate(lines):                     # 2. what the build actually runs
        for match in RUN_TARGET.finditer(line):
            base = match.group(1).rsplit("/", 1)[-1]
            name = dest_map.get(base) or (base if base.startswith("patch_") else None)
            if name is None:
                continue
            rec = found.get(name) or record(name, at, "run-unstaged")
            rec["runs"] = True

    for at, line in enumerate(lines):                     # 3. what only a step's prose names
        for name in MENTION.findall(line):
            if name not in found:
                record(name, at, "guard-only")
    # Build order, not discovery order: the line a step stages or guards the patcher on, so the
    # guard-only steps land in their own step block instead of at the end of the table.
    order.sort(key=lambda name: found[name]["line"])
    return [found[name] for name in order]


def integrity(records: list[dict], staged_names: list[str]) -> list[str]:
    """The instrument-level reds: the derived set and the staged corpus must describe one build."""
    problems = []
    derived = {r["name"] for r in records}
    for name in sorted(set(staged_names) - derived):
        problems.append(f"{name} is staged in src/ but named by NO Dockerfile step — the census "
                        "cannot see it, and neither can the build")
    for rec in records:
        if rec["kind"] == "run-unstaged":
            problems.append(f"{rec['name']} is run by step {rec['step']} but no COPY stages it")
        elif rec["kind"] == "applied" and not rec["runs"]:
            problems.append(f"{rec['name']} is COPYed by step {rec['step']} but never run — it would "
                            "sit in /tmp and change nothing")
        elif rec["staged"] == "src/" and rec["name"] not in staged_names:
            problems.append(f"step {rec['step']} runs {rec['name']} but the staged src/ has no such file")
    return problems


# --- the base corpus -------------------------------------------------------------------------
def load_tree(site: str) -> str:
    """Fallback corpus for an anchor whose target path is built in a loop
    (`for key in FILES: edit(FILES[key], …)`): the whole installed tree, read once. A tree-wide count
    is a weaker claim than a per-file one, so the row says which it is."""
    blob = []
    for dirpath, _dirs, files in os.walk(os.path.join(site, "vllm")):
        for name in files:
            if name.endswith(".py"):
                try:
                    with open(os.path.join(dirpath, name), encoding="utf-8", errors="replace") as fh:
                        blob.append(fh.read())
                except OSError:
                    pass
    return "\x00".join(blob)


def raw_env(tree):
    env = {}
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    env[target.id] = node.value
    return env


def value(node, env, depth=0):
    """A literal Python value from an expression, following module-level NAMEs. Paths in these
    patchers are built from module constants, so a NAME has to be chased, not skipped."""
    if depth > 6 or node is None:
        return None
    if isinstance(node, ast.Constant):
        return node.value
    if isinstance(node, ast.Name):
        return value(env.get(node.id), env, depth + 1)
    if isinstance(node, ast.Dict):
        try:
            return {ast.literal_eval(k): value(v, env, depth + 1) for k, v in zip(node.keys, node.values)}
        except Exception:
            return None
    if isinstance(node, ast.Subscript):
        table = value(node.value, env, depth + 1)
        if isinstance(table, dict):
            try:
                return table.get(ast.literal_eval(node.slice))
            except Exception:
                return None
        return None
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left, right = value(node.left, env, depth + 1), value(node.right, env, depth + 1)
        return left + right if isinstance(left, str) and isinstance(right, str) else None
    if isinstance(node, ast.Call) and getattr(node.func, "attr", "") == "join":
        parts = [value(a, env, depth + 1) for a in node.args]
        return os.path.join(*parts) if all(isinstance(p, str) for p in parts) else None
    if isinstance(node, ast.JoinedStr):
        out = []
        for part in node.values:
            val = part.value if isinstance(part, ast.Constant) else value(part, env, depth + 1)
            if not isinstance(val, str):
                return None
            out.append(val)
        return "".join(out)
    return None


def rows_for(patcher, tree, env):
    funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
    bound = {}
    for node in tree.body:                       # helper bindings from the module-level call sites
        if isinstance(node, ast.Expr) and isinstance(node.value, ast.Call):
            call = node.value
            if isinstance(call.func, ast.Name) and call.func.id in funcs:
                for p, arg in zip([a.arg for a in funcs[call.func.id].args.args], call.args):
                    val = value(arg, env)
                    if isinstance(val, str):
                        bound[p] = val
    out = []
    for node in ast.walk(tree):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)):
            continue
        name = node.func.id
        if not any(k in name.lower() for k in EDIT_NAMES) or name in SKIP_NAMES:
            continue
        if name in funcs and not node.args:
            continue          # a helper's own definition site, not a call with anchors in it
        target = value(node.args[0], env, 7) if node.args else None
        if not isinstance(target, str) or not target.endswith(".py"):
            target = bound.get(node.args[0].id) if (node.args and isinstance(node.args[0], ast.Name)) else None
        strs = [a.value for a in node.args[1:] if isinstance(a, ast.Constant) and isinstance(a.value, str)]
        if not strs:
            continue
        old = strs[0]
        new = strs[1] if len(strs) > 1 else ""
        out.append((patcher, target, old, new))
    return out


def table_anchors(tree):
    """The shape most of these patchers actually use:

        EDITS = [ (PATH_CONST, "sentinel", [(old, new), …]), … ]

    Reading the table, not the loop that walks it, is what makes one row per anchor possible."""
    consts = raw_env(tree)
    out = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.List):
            continue
        for element in node.elts:
            if not (isinstance(element, ast.Tuple) and len(element.elts) >= 3):
                continue
            path = element.elts[0]
            if isinstance(path, ast.Name):
                path = consts.get(path.id)
            target = value(path, consts)
            if not isinstance(target, str) or not target.endswith(".py"):
                continue
            edits = element.elts[2]
            sentinel = value(element.elts[1], consts) if isinstance(element.elts[1], ast.Constant) else ""
            if isinstance(edits, (ast.List, ast.Tuple)):
                for pair in edits.elts:
                    if isinstance(pair, ast.Tuple) and len(pair.elts) >= 2:
                        old = value(pair.elts[0], consts)
                        new = value(pair.elts[1], consts)
                        if isinstance(old, str) and old.strip():
                            out.append((target, old, new if isinstance(new, str) else "",
                                        sentinel if isinstance(sentinel, str) else ""))
            elif isinstance(sentinel, str) and sentinel:
                out.append((target, sentinel, "", sentinel))
    return out


def data_anchors(tree):
    """Patchers that keep their anchors in a table rather than in a call argument: every string
    constant that looks like source code. Weaker than a call-site row (no target), so the row says
    `anchor-as-data` and the count is over the whole installed tree."""
    out = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            text = node.value
            if len(text) >= 15 and ("(" in text or "=" in text) and not text.strip().startswith(
                    ("#", "vllm.", "from ", "import ")):
                out.append(text)
    return list(dict.fromkeys(out))


def count(path, needle, site, blob):
    """(count, where, per_file). A target the patcher builds in a loop is counted over the whole
    installed tree instead, and the row says so — an honest weak answer beats a blank one."""
    if isinstance(path, str) and path.endswith(".py"):
        full = path if path.startswith("/") else site + "/" + path.lstrip("/")
        try:
            with open(full, encoding="utf-8", errors="replace") as fh:
                return fh.read().count(needle), full.replace(site + "/vllm/", "vllm/"), True
        except OSError:
            return -1, full, True
    return blob.count(needle), "whole tree", False


VERDICTS = ("anchor holds", "no-op at this base", "absent at this base",
            "anchor NOT unique", "unreadable target")


def census(src: str, dockerfile: str, site: str) -> tuple[list[dict], list[str]]:
    """Print the census. Returns (per-patcher rows in step order, integrity problems)."""
    records = derive_patchers(open(dockerfile, encoding="utf-8").read())
    staged = sorted(f for f in os.listdir(src) if f.startswith("patch_") and f.endswith(".py"))
    problems = integrity(records, staged)

    print("derived patcher set, read out of the Dockerfile in step order:")
    for rec in records:
        where = rec["staged"] if rec["staged"] != "src/" else "src/"
        print(f"  step {rec['step']:>5}  {rec['name']:34.34} {rec['kind']:12.12} "
              f"({where}, :{rec['line']}) — {rec['title'][:52]}")
    print(f"  {len(records)} names derived · {sum(1 for r in records if r['kind'] == 'applied')} applied · "
          f"{sum(1 for r in records if r['kind'] == 'guard-only')} guard-only · "
          f"{len(staged)} patch_*.py present in {src}")
    if problems:
        print("\nINTEGRITY — the census below is NOT a statement about the build:")
        for problem in problems:
            print(f"  RED  {problem}")
    else:
        print("  integrity: the derived set and the staged corpus describe the same patch set")

    blob = load_tree(site)
    print(f"\n{'step':>5} {'patcher':34.34} {'old':>4} {'new':>4}  "
          f"{'anchor (first line)':46.46}  verdict")
    rows: list[dict] = []
    for rec in records:
        path = os.path.join(src, rec["name"])
        if rec["staged"] != "src/":
            print(f"{rec['step']:>5} {rec['name']:34.34} {'-':>4} {'-':>4}  "
                  f"{'(staged at the build-dir root)':46.46}  not read: its anchors are "
                  f"self-measured in the in-repo patcher")
            rows.append({**rec, "anchors": 0, "tally": {}, "read": False})
            continue
        try:
            source = open(path, encoding="utf-8").read()
        except OSError as exc:
            print(f"{rec['step']:>5} {rec['name']:34.34} {'-':>4} {'-':>4}  {'(unreadable)':46.46}  {exc}")
            rows.append({**rec, "anchors": 0, "tally": {"unreadable target": 1}, "read": False})
            continue
        tree = ast.parse(source)
        env = raw_env(tree)
        anchors = [(rec["name"], t, o, n, "") for _p, t, o, n in rows_for(rec["name"], tree, env)]
        anchors += [(rec["name"], p, o, n, s) for p, o, n, s in table_anchors(tree)]
        if not anchors:
            anchors = [(rec["name"], None, s, "", "") for s in data_anchors(tree)]
        tally: dict[str, int] = {}
        for patcher, target, old, new, _sentinel in anchors:
            n_old, where, per_file = count(target, old, site, blob)
            n_new = count(target, new, site, blob)[0] if new else 0
            verdict = ("anchor holds" if n_old == 1 else
                       "no-op at this base" if n_old == 0 and n_new > 0 else
                       "absent at this base" if n_old == 0 else
                       "anchor NOT unique" if n_old > 1 else "unreadable target")
            tally[verdict] = tally.get(verdict, 0) + 1
            print(f"{rec['step']:>5} {patcher:34.34} {n_old:>4} {n_new:>4}  "
                  f"{(old.strip().splitlines() or ['(blank)'])[0][:46]:46.46}  {verdict}"
                  f"  [{where}{'' if per_file else ' (loop-built target)'}]")
        rows.append({**rec, "anchors": len(anchors), "tally": tally, "read": True})

    print(f"\nper-patcher summary, step order ({len(records)} patchers derived from {dockerfile}):")
    print(f"{'step':>5} {'patcher':34.34} {'kind':12.12} {'anchors':>7}  " +
          "  ".join(f"{v:>16.16}" for v in VERDICTS) + "   reads the build applies it?")
    for row in rows:
        counts = [row["tally"].get(v, 0) for v in VERDICTS]
        answer = ("no — guard only" if row["kind"] == "guard-only" else
                  "not read here" if not row["read"] else
                  "yes" if row["kind"] == "applied" else "step is broken")
        print(f"{row['step']:>5} {row['name']:34.34} {row['kind']:12.12} {row['anchors']:>7}  " +
              "  ".join(f"{c:>16}" for c in counts) + f"   {answer}")
    total = sum(r["anchors"] for r in rows)
    overall: dict[str, int] = {}
    for row in rows:
        for verdict, num in row["tally"].items():
            overall[verdict] = overall.get(verdict, 0) + num
    print("\n" + "  ".join(f"{k}: {v}" for k, v in sorted(overall.items())) +
          f"   — {total} anchors read in the base image at the pin digest, "
          f"{sum(1 for r in rows if r['read'])} of {len(rows)} derived patchers read.")
    return rows, problems


# --- --self-test -------------------------------------------------------------------------------
FIXTURE_DOCKERFILE = """\
FROM base
ARG SP=/opt
# ---- 1. The first day-0 patcher ----
COPY src/patch_alpha.py /tmp/patch_alpha.py
RUN python3 /tmp/patch_alpha.py && rm /tmp/patch_alpha.py
# ---- 2. A patcher COPYed under a different name ----
COPY src/patch_beta.py /tmp/renamed_beta.py
RUN python3 /tmp/renamed_beta.py && rm /tmp/renamed_beta.py
# ---- 3. A patcher the base already satisfies ----
# Upstream's patch_gamma.py rewrites the transfer this base already does, so the step applies
# nothing and guards the post-state instead.
RUN grep -q 'already_done(' ${SP}/thing.py
"""
# Step 2's COPY line is the one this arm breeds out of the Dockerfile: the step stays, the patcher
# vanishes from the derived set, and patch_beta.py is still sitting in the staged src/.
MUTATED_DOCKERFILE = FIXTURE_DOCKERFILE.replace(
    "COPY src/patch_beta.py /tmp/renamed_beta.py\n", "")


def self_test() -> int:
    """Prove the enumeration is real: the control fixture must derive all four patchers, and a
    Dockerfile whose step-2 patcher went missing from the derived set must RED."""
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "src")
        os.makedirs(src)
        for name in ("patch_alpha.py", "patch_beta.py", "patch_gamma.py"):
            with open(os.path.join(src, name), "w", encoding="utf-8") as fh:
                fh.write("")
        staged = sorted(os.listdir(src))

        ok_records = derive_patchers(FIXTURE_DOCKERFILE)
        got = [(r["step"], r["name"], r["kind"]) for r in ok_records]
        want = [("1", "patch_alpha.py", "applied"),
                ("2", "patch_beta.py", "applied"),
                ("3", "patch_gamma.py", "guard-only")]
        arm_a = got == want and not integrity(ok_records, staged)
        print(f"arm A control:  derived {got}")
        print(f"arm A expected: {want}")
        print(f"arm A: {'PASS' if arm_a else 'FAIL'} — step order, the renamed COPY and the guard "
              "marker all read out of the Dockerfile")

        bad_records = derive_patchers(MUTATED_DOCKERFILE)
        red = integrity(bad_records, staged)
        named = any("patch_beta.py" in p for p in red)
        arm_b = bool(red) and named
        print(f"arm B bred:     a step-2 Dockerfile that names no patcher for the staged "
              f"patch_beta.py")
        print(f"arm B verdict:  {red}")
        verdict_b = "PASS (reddens as designed)" if arm_b else \
            "FAIL — a missing patcher stayed invisible, which is what this arm exists to catch"
        print(f"arm B: {verdict_b}")

        arm_c = bool(integrity(derive_patchers(FIXTURE_DOCKERFILE.replace(
            "RUN python3 /tmp/patch_alpha.py", "RUN python3 /tmp/patch_unstaged.py")), staged))
        print(f"arm C a RUN with no COPY stages nothing: "
              f"{'PASS (reddens)' if arm_c else 'FAIL'}")
    return 0 if (arm_a and arm_b and arm_c) else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src", nargs="?", default="/src",
                    help="the staged patchers, mounted read-only (default /src)")
    ap.add_argument("--src", dest="src_opt", help="same as the positional form")
    ap.add_argument("--dockerfile", default="/Dockerfile",
                    help="the Dockerfile whose steps own the patcher set (default /Dockerfile)")
    ap.add_argument("--site", default=SITE, help="the base image's dist-packages root")
    ap.add_argument("--self-test", action="store_true",
                    help="prove the enumeration reddens a patcher the derived set misses")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    src = args.src_opt or args.src
    if not os.path.isfile(args.dockerfile):
        print(f"census: {args.dockerfile} is not a file — the patcher set has no source of truth, so "
              "nothing here can certify a build. Mount the Dockerfile the build reads.",
              file=sys.stderr)
        return 2
    rows, problems = census(src, args.dockerfile, args.site)
    if problems:
        return 2
    if not any(r["anchors"] for r in rows):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
