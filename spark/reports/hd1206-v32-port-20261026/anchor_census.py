"""Read-only anchor census for the v0.32 lineage (HD-1206).

One row per `edit()`-style call in every staged day-0 patcher, counted against the BASE image's own
copy of the target file:

    old == 1            the anchor still holds, the patcher will apply;
    old == 0, new  > 0  the base ALREADY has the post-state — the patcher is a no-op here;
    old == 0, new  == 0 the effect is absent at this base — re-anchor, or park it for disposition.

That is the whole point of the census: a build answers these questions one attempt per surprise, and
each attempt costs ~12 G of build cache. Nothing here writes — the patchers are mounted read-only,
their anchors are read out of the source with `ast`, and each is counted with `str.count`.

Usage (inside the base image, staged patchers mounted at /src):  python3 census.py /src
"""
import ast
import os
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "/src"
SITE = "/usr/local/lib/python3.12/dist-packages"
# Fallback corpus for an anchor whose target path is built in a loop (`for key in FILES: edit(FILES[key], …)`):
# the whole installed tree, read once. A tree-wide count is a weaker claim than a per-file one, so the
# row says which it is.
TREE_ROOT = SITE + "/vllm"
_tree = []
for _dp, _d, _fs in os.walk(TREE_ROOT):
    for _f in _fs:
        if _f.endswith(".py"):
            try:
                _tree.append(open(os.path.join(_dp, _f), encoding="utf-8", errors="replace").read())
            except OSError:
                pass
BLOB = "\x00".join(_tree)
EDIT_NAMES = ("edit", "patch", "insert", "repl", "add_gate", "sub")
SKIP_NAMES = ("init_logger", "open", "print", "len", "range", "str", "int", "set", "dict", "list")


def raw_env(tree):
    env = {}
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for t in node.targets:
                if isinstance(t, ast.Name):
                    env[t.id] = node.value
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
        d = value(node.value, env, depth + 1)
        if isinstance(d, dict):
            try:
                return d.get(ast.literal_eval(node.slice))
            except Exception:
                return None
        return None
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        a, b = value(node.left, env, depth + 1), value(node.right, env, depth + 1)
        return a + b if isinstance(a, str) and isinstance(b, str) else None
    if isinstance(node, ast.Call) and getattr(node.func, "attr", "") == "join":
        parts = [value(a, env, depth + 1) for a in node.args]
        return os.path.join(*parts) if all(isinstance(p, str) for p in parts) else None
    if isinstance(node, ast.JoinedStr):
        out = []
        for p in node.values:
            v = p.value if isinstance(p, ast.Constant) else value(p, env, depth + 1)
            if not isinstance(v, str):
                return None
            out.append(v)
        return "".join(out)
    return None


def rows_for(patcher, tree, env):
    funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
    bound = {}
    for node in tree.body:                       # helper bindings from the module-level call sites
        if isinstance(node, ast.Expr) and isinstance(node.value, ast.Call):
            c = node.value
            if isinstance(c.func, ast.Name) and c.func.id in funcs:
                for p, arg in zip([a.arg for a in funcs[c.func.id].args.args], c.args):
                    v = value(arg, env)
                    if isinstance(v, str):
                        bound[p] = v
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


def count(path, needle):
    """(count, where, per_file). A target the patcher builds in a loop is counted over the whole
    installed tree instead, and the row says so — an honest weak answer beats a blank one."""
    if isinstance(path, str) and path.endswith(".py"):
        p = path if path.startswith("/") else SITE + "/" + path.lstrip("/")
        try:
            return open(p, encoding="utf-8", errors="replace").read().count(needle), p.replace(SITE + "/vllm/", "vllm/"), True
        except OSError:
            return -1, p, True
    return BLOB.count(needle), "whole tree", False


print(f"{'patcher':30.30} {'old':>4} {'new':>4}  {'anchor (first line)':46.46}  verdict")
def table_anchors(tree):
    """The shape most of these patchers actually use:

        EDITS = [ (PATH_CONST, "sentinel", [(old, new), …]), … ]

    Reading the table, not the loop that walks it, is what makes one row per anchor possible."""
    consts = {k: value(v, raw_env(tree)) for k, v in raw_env(tree).items() if isinstance(v, ast.Constant)}
    out = []
    for node in ast.walk(tree):
        if not (isinstance(node, ast.List)):
            continue
        for el in node.elts:
            if not (isinstance(el, ast.Tuple) and len(el.elts) >= 3):
                continue
            path = el.elts[0]
            if isinstance(path, ast.Name):
                path = raw_env(tree).get(path.id)
            p = value(path, raw_env(tree))
            if not isinstance(p, str) or not p.endswith(".py"):
                continue
            edits = el.elts[2]
            sentinel = value(el.elts[1], raw_env(tree)) if isinstance(el.elts[1], ast.Constant) else ""
            if isinstance(edits, (ast.List, ast.Tuple)):
                for pair in edits.elts:
                    if isinstance(pair, ast.Tuple) and len(pair.elts) >= 2:
                        old = value(pair.elts[0], raw_env(tree))
                        new = value(pair.elts[1], raw_env(tree))
                        if isinstance(old, str) and old.strip():
                            out.append((p, old, new if isinstance(new, str) else "", sentinel if isinstance(sentinel, str) else ""))
            elif isinstance(sentinel, str) and sentinel:
                out.append((p, sentinel, "", sentinel))
    return out


def data_anchors(tree):
    """Patchers that keep their anchors in a table rather than in a call argument: every string
    constant that looks like source code. Weaker than a call-site row (no target), so the row says
    `anchor-as-data` and the count is over the whole installed tree."""
    out = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            s = node.value
            if len(s) >= 15 and ("(" in s or "=" in s) and not s.strip().startswith(("#", "vllm.", "from ", "import ")):
                out.append(s)
    return list(dict.fromkeys(out))


rows = []
for patcher in sorted(os.listdir(SRC)):
    if patcher.startswith("patch_") and patcher.endswith(".py"):
        src = open(os.path.join(SRC, patcher), encoding="utf-8").read()
        tree = ast.parse(src)
        env = raw_env(tree)
        call_rows = rows_for(patcher, tree, env)      # (patcher, target, old, new)
        tab_rows = table_anchors(tree)                 # (path, old, new, sentinel)
        rows += [(patcher, t, o, n, "") for _p, t, o, n in call_rows]
        rows += [(patcher, p, o, n, s) for p, o, n, s in tab_rows]
        if not call_rows and not tab_rows:
            rows += [(patcher, None, s, "", "") for s in data_anchors(tree)]

tally = {}
for patcher, target, old, new, sentinel in rows:
    n_old, where, per_file = count(target, old)
    n_new = count(target, new)[0] if new else 0
    verdict = ("anchor holds" if n_old == 1 else
               "no-op at this base" if n_old == 0 and n_new > 0 else
               "absent at this base" if n_old == 0 else
               "anchor NOT unique" if n_old > 1 else "unreadable")
    tally[verdict] = tally.get(verdict, 0) + 1
    print(f"{patcher:30.30} {n_old:>4} {n_new:>4}  "
          f"{(old.strip().splitlines() or ['(blank)'])[0][:46]:46.46}  {verdict}"
          f"  [{where}{'' if per_file else ' (loop-built target)'}]")

print("\n" + "  ".join(f"{k}: {v}" for k, v in sorted(tally.items())) +
      f"   — {len(rows)} anchors read in the base image at the pin digest.")
