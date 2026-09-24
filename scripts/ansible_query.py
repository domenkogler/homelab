#!/usr/bin/env python3
"""HD-456: read-only Ansible fact queries over this repo — answers, not syntax trees.

Why this exists

The two existing ways to interrogate the Ansible tree both spend the one scarce currency:
the context window. `grep` over 167 YAML + 212 `.j2` files returns raw lines and forces a
re-read of whole roles to recover meaning; a file read returns the whole file (`roles/router/
tasks/main.yml` is 68 KB, `group_vars/all/main.yml` is 45 KB). An AST route (ast-grep plus a
tree-sitter Jinja grammar, with `languageInjections` in `sgconfig.yml`) was evaluated and
rejected on four counts: `languageInjections` is experimental; ast-grep's own LSP reports
nothing for injected-language rules (upstream #2522), so it cannot surface through an editor
lane; the Jinja grammars are young enough to crash on real templates (cathaysia/
tree-sitter-jinja #37); and — deciding — Ansible's `when:`/`failed_when:`/`changed_when:`
conditions carry **bare** Jinja with no `{{ }}`, which no Jinja grammar parses. Trees are
not answers.

This script answers the questions that actually recur, bounded by `--limit`:

    --var NAME        where DEFINED (precedence-ordered, winner marked) and where USED
    --handler NAME    who defines it, who notifies it
    --handlers        every handler + the dangling-notify verdict (--unresolved = verdict only)
    --role NAME       role anatomy + bounded task manifest (--tasks-all widens)
    --module NAME     every task using a module, by role, short name or FQCN
    --vault           every 1Password lookup site (item/field NAMES only, never values)
    --jinja REGEX     search Jinja expressions only — YAML scaffolding excluded
    --list-vars       defined-var names by precedence rank (discovery)
    --context         what the scanner sees: roots, file counts, the precedence ladder

Design constraints, and why they are what they are:

  * **Bare Jinja is first-class.** Usage extraction reads `{{ }}` / `{% %}` expressions AND
    the values of `when:` / `failed_when:` / `changed_when:` / `until:`. A brace-only scanner
    misses precisely the conditions that break converges — canary #2 in `--self-test`.
  * **`.j2` templates are in scope.** 212 templates are the largest class of var *consumers*
    and are out of scope for the Ansible language server (its own docs say Jinja template
    files are not supported).
  * **Static, and honest about being static.** `set_fact`, `register`, `include_vars` and
    `-e` are reported, never resolved. The precedence ladder is printed with every `--var`
    answer so the reasoning is inspectable rather than implied.
  * **Dangling-notify verdict is tree-wide on purpose** (see `q_handlers`): flagging only
    names absent from the WHOLE tree is a true positive without needing play-scoping;
    cross-role-only matches are counted, not flagged, because handlers in any role of the
    same play are visible to each other and a static scan cannot prove play membership.
  * **Never prints a secret VALUE** (CONVENTIONS §6 — probes show lengths/prefixes/IDs only):
    `!vault` / `$ANSIBLE_VAULT` payloads are masked, keys matching the secret-name pattern
    print `<masked:N chars>`, and `--vault` prints item/field names and file:line only.
    Canary #3 asserts the ciphertext never reaches stdout.
  * **Query, not gate.** Deliberately NOT wired into `validate-all.sh`: a query has no
    pass/fail and a read tool must not be able to fail a commit. The one mode that carries a
    verdict — `--handlers --unresolved` — exits 1 on findings, so it can be gated later
    without changing this file.

Interpreter: needs PyYAML + Jinja2, both present in `~/ansible-venv` and absent from a bare
runner python. `validate-all.sh` runs its portability sweep with `python3`, which on a runner
without the venv activated is the system python — so missing imports make this script re-exec
itself under `~/ansible-venv/bin/python3` instead of dying with an ImportError that reads
like a code fault. Precedent: `ansible-run.sh` resolving the same venv.

Run:    python3 scripts/ansible_query.py --var docker_services
        python3 scripts/ansible_query.py --role docker_services --tasks
        python3 scripts/ansible_query.py --handlers --unresolved
        python3 scripts/ansible_query.py --self-test
Exit:   0 = answered (including "no matches"); 1 = --handlers --unresolved found dangling
        notifies, or --self-test failed; 2 = bad usage / unreadable root.
"""
from __future__ import annotations

import argparse
import bisect
import os
import re
import shutil
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path


# --------------------------------------------------------------------------- #
# Dependency guard — must run before the yaml/jinja2 imports below
# --------------------------------------------------------------------------- #
def _ensure_deps() -> None:
    try:
        import yaml  # noqa: F401
        import jinja2  # noqa: F401
        return
    except ImportError:
        pass
    venv_py = Path.home() / "ansible-venv" / "bin" / "python3"
    same = Path(sys.executable).resolve() == venv_py.resolve() if venv_py.exists() else True
    if os.environ.get("HD456_REEXEC") == "1" or not venv_py.is_file() or same:
        sys.exit(
            "FAIL: PyYAML + Jinja2 are required and not importable by "
            f"{sys.executable}.\n"
            "      Remedy: ~/ansible-venv/bin/python3 scripts/ansible_query.py …\n"
            "      (no venv at all → bash scripts/bootstrap-runner.sh)"
        )
    os.environ["HD456_REEXEC"] = "1"
    os.execv(str(venv_py), [str(venv_py), str(Path(__file__).resolve()), *sys.argv[1:]])


_ensure_deps()

import yaml  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ROOT = ROOT / "IaC" / "ansible"
ALT_ROOTS = {"iac": ROOT / "IaC" / "ansible", "spark": ROOT / "spark" / "ansible"}

VAULT_MASK = "<vault:encrypted>"
NO_MATCH = "(no matches)"

# Ansible's documented precedence ladder (user docs, "Variable precedence rules", listed
# low → high), reduced to the classes this repo uses. The rank numbers are arbitrary; the
# ORDER is not — answers print low → high so the last DEFINED row is what wins at deploy.
# Reference (low→high): role defaults(2) < inv group_vars(3) < inv group_vars/all(4) <
# playbook group_vars/all(5) < inv group_vars/*(6) < inv host_vars(8-9) < play vars(12) <
# play vars_files(14) < role vars(15) < block/task vars(17) < include_vars(18) <
# set_facts/registered(19) < role/include params(20-21) < extra vars(22).
PRECEDENCE = [
    (10, "role defaults", "roles/<r>/defaults/main.yml"),
    (20, "inventory group_vars/all", "group_vars/all/*.yml"),
    (30, "inventory group_vars/<group>", "group_vars/<group>.yml"),
    (40, "inventory host_vars/<host>", "host_vars/<host>.yml"),
    (50, "play vars / vars_files", "playbooks/*.yml"),
    (60, "role vars", "roles/<r>/vars/main.yml"),
    (70, "dynamic: set_fact / register / include_vars / task vars", "reported, not resolved"),
    (90, "extra vars (-e)", "never visible statically"),
]
RANK_LABEL = {r: label for r, label, _ in PRECEDENCE}
RANK_WHERE = {r: where for r, _, where in PRECEDENCE}

# Keys whose VALUE is bare Jinja — no braces. The whole reason a brace-only scan under-reports.
# `that` is here because ansible.builtin.assert expressions are un-braced Jinja; it was found
# live on HD-456 day one (the only lookup the same-line matcher missed sat under `that:`).
# Deliberately NOT included: `loop:` / `with_items`, whose items are usually data, not
# expressions — including them would flood the usage index with non-Jinja strings.
BARE_JINJA_KEYS = ("when", "failed_when", "changed_when", "until", "that")

# YAML keys that are Ansible constructs, not module names.
CONTROL_KEYS = {
    "name", "when", "failed_when", "changed_when", "until", "register", "set_fact",
    "loop", "loop_control", "with_items", "with_dict", "with_fileglob", "with_list",
    "notify", "tags", "vars", "vars_files", "vars_prompt", "become", "become_user",
    "become_method", "become_flags", "become_exe", "delegate_to", "delegate_facts",
    "run_once", "ignore_errors", "ignore_unreachable", "any_errors_fatal",
    "max_fail_percentage", "check_mode", "diff", "no_log", "async", "poll", "throttle",
    "timeout", "retries", "delay", "environment", "args", "block", "rescue", "always",
    "listen", "action", "local_action", "connection", "remote_user", "port", "user",
    "hosts", "plays", "roles", "tasks", "pre_tasks", "post_tasks", "handlers",
    "strategy", "gather_facts", "gather_subset", "fact_path", "module_defaults",
    "force_handlers", "order", "apply", "meta", "auth", "import_playbook",
    "ansible.builtin.import_playbook", "import_role", "include_role", "import_tasks",
    "include_tasks", "include_vars", "ansible.builtin.import_role",
    "ansible.builtin.include_role", "ansible.builtin.import_tasks",
    "ansible.builtin.include_tasks", "ansible.builtin.include_vars",
}

SECRET_KEY_RE = re.compile(
    r"(passw|secret|token|apikey|api_key|credential|private_key|_key\b|_keys\b|_pwd\b|_otp\b)"
)
JINJA_SPAN = re.compile(r"\{\{[-+?]?(.*?)[-+?]?}}|\{%[-+?]?(.*?)[-+?]?%}", re.S)
BARE_JINJA_LINE = re.compile(
    r"^\s*-?\s*(" + "|".join(BARE_JINJA_KEYS) + r")\s*:\s*(?!--|\[|\{|\|)(.+?)\s*$"
)
# `when:` with an empty value carries its expression as a BLOCK LIST on the next lines:
#     when:
#       - (lookup('community.general.onepassword', …) | length) >= 16
# Missing this form silently loses usage sites — live-found on HD-456 day one
# (roles/home_assistant/tasks/standby.yml:79 was the only lookup the same-line matcher missed).
BARE_JINJA_BLOCK = re.compile(
    r"^(\s*)(" + "|".join(BARE_JINJA_KEYS) + r")\s*:\s*$"
)
IDENTS = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
TOP_KEY_LINE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:(?:\s|$)")
TASK_NAME_LINE = re.compile(r"^\s*-?\s*name\s*:\s*(.+?)\s*$")
LOOKUP_RE = re.compile(r"lookup\(\s*['\"]([^'\"]+)['\"](.*?)\)", re.S)
OP_PLUGIN_RE = re.compile(r"onepassword", re.I)
KV_ARG = re.compile(r"(\w+)\s*=\s*(?:'([^']*)'|\"([^\"]*)\"|([A-Za-z_][\w.]*))")
POS_ARG = re.compile(r"['\"]([^'\"]+)['\"]")


# --------------------------------------------------------------------------- #
# YAML loading — tolerant of Ansible's custom tags
# --------------------------------------------------------------------------- #
class TolerantLoader(yaml.SafeLoader):
    """SafeLoader that survives `!vault`, `!KeyOf`, `!Find`, … instead of losing the file.

    The Authentik blueprint YAML under templates/ carries custom tags (validate_blueprints.py
    owns their real semantics); a plain safe_load raises mid-file and the whole file drops out
    of the index.
    """


def _tagged(loader, suffix, node):
    if isinstance(node, yaml.ScalarNode):
        raw = loader.construct_scalar(node)
        if node.tag == "!vault" or str(raw).lstrip().startswith("$ANSIBLE_VAULT"):
            return VAULT_MASK
        return raw
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node, deep=True)
    if isinstance(node, yaml.MappingNode):
        return loader.construct_mapping(node, deep=True)
    return None


TolerantLoader.add_multi_constructor("", _tagged)


# --------------------------------------------------------------------------- #
# Output helpers — shape/length only, never a secret VALUE (CONVENTIONS §6)
# --------------------------------------------------------------------------- #
def first_positional(argstr: str) -> str:
    """First non-keyword argument of a lookup() call — quoted literal OR a bare expression
    like `svc.vault_item`. Returns "" when the item genuinely arrives from kwargs only."""
    parts, depth, cur = [], 0, ""
    for ch in argstr:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    parts.append(cur)
    for part in parts:
        part = part.strip()
        if not part:
            continue
        if re.match(r"^\w+\s*=", part):
            break  # keyword arguments start here
        return part.strip("'\"")
    return ""


def mask(value) -> str:
    if isinstance(value, dict):
        return f"dict({len(value)} keys)"
    if isinstance(value, list):
        return f"list({len(value)} items)"
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    s = str(value)
    if s == VAULT_MASK or s.lstrip().startswith("$ANSIBLE_VAULT"):
        return VAULT_MASK
    s = " ".join(s.split())
    return s[:71] + "…" if len(s) > 72 else s


def masked_value(key, value) -> str:
    if isinstance(value, str) and (
        value == VAULT_MASK or value.lstrip().startswith("$ANSIBLE_VAULT")
    ):
        return VAULT_MASK
    if SECRET_KEY_RE.search(str(key)) and not isinstance(value, (dict, list, type(None))):
        return f"<masked:{len(str(value))} chars>"
    return mask(value)


def collapse(s, width=76) -> str:
    s = " ".join(str(s).replace("\n", " ").split())
    return s[: width - 1] + "…" if len(s) > width else s


def emit(lines, limit, note="raise --limit"):
    for ln in lines[:limit]:
        print(ln)
    extra = len(lines) - limit
    if extra > 0:
        print(f"  … +{extra} more ({note})")


# --------------------------------------------------------------------------- #
# Record types
# --------------------------------------------------------------------------- #
@dataclass
class Def:
    rank: int
    name: str
    cls: str
    path: str
    line: int
    value: str


@dataclass
class Use:
    path: str
    line: int
    expr: str          # display form — collapsed + truncated
    kind: str          # braces | block | bare
    raw: str = ""      # full expression — ALWAYS what matching/parsing runs against

    @property
    def match_text(self) -> str:
        """Matching must never see the truncated display form: an expression longer than the
        display cap loses its closing paren, which silently dropped every long lookup()."""
        return self.raw or self.expr


@dataclass
class Task:
    path: str
    role: str
    name: str
    module: str
    when: str = ""
    loop: str = ""
    notifies: list = field(default_factory=list)
    registers: str = ""
    line: int = 0


@dataclass
class Handler:
    path: str
    role: str
    name: str
    listen: list = field(default_factory=list)
    line: int = 0


# --------------------------------------------------------------------------- #
# The scanned tree
# --------------------------------------------------------------------------- #
class Tree:
    def __init__(self, root: Path, label: str = ""):
        self.root = root
        self.label = label or root.name
        self.defs: list[Def] = []
        self.uses: list[Use] = []
        self.tasks: list[Task] = []
        self.handlers: list[Handler] = []
        self.play_roles: dict[str, set] = {}
        self.errors: list[tuple[str, str]] = []
        self.yml_files: list[Path] = []
        self.j2_files: list[Path] = []
        self.scan()

    # -- discovery ---------------------------------------------------------- #
    def rel(self, p: Path) -> str:
        try:
            return p.relative_to(self.root).as_posix()
        except ValueError:
            return p.as_posix()

    def scan(self):
        if not self.root.is_dir():
            return
        for path in sorted(
            p for p in self.root.rglob("*") if p.is_file() and p.suffix in (".yml", ".yaml", ".j2")
        ):
            if path.suffix == ".j2":
                self.j2_files.append(path)
                self._index_usage(path)
            else:
                self.yml_files.append(path)
                self._index_yml(path)

    # -- YAML: definitions, structure, usage -------------------------------- #
    def _index_yml(self, path: Path):
        rel = self.rel(path)
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            self.errors.append((rel, f"read-error: {exc}"))
            return
        self._index_usage(path, text)

        docs = []
        try:
            docs = [d for d in yaml.load_all(text, Loader=TolerantLoader) if d is not None]
        except yaml.YAMLError as exc:
            self.errors.append((rel, f"yaml-parse-error: {str(exc).splitlines()[0][:90]}"))

        lines = text.splitlines()
        rank, cls = classify(rel)
        if rank and cls in ("group_vars", "host_vars", "role_defaults", "role_vars"):
            key_lines = top_key_lines(lines)
            for doc in docs:
                if not isinstance(doc, dict):
                    continue
                for key, value in doc.items():
                    self.defs.append(
                        Def(rank, str(key), cls, rel, key_lines.get(str(key), 0),
                            masked_value(key, value))
                    )

        if cls == "playbook" or rel.startswith("playbooks/"):
            self._index_plays(docs, rel)

        role = role_of(rel)
        name_lines = task_name_lines(lines)
        # handlers/ is a task list too; handlers are extracted separately below
        for doc in docs:
            for item in as_list(doc):
                if not isinstance(item, dict):
                    continue
                if "hosts" in item:
                    for key in ("pre_tasks", "tasks", "post_tasks", "handlers"):
                        self._walk_tasks(item.get(key), rel, role, name_lines)
                else:
                    self._walk_tasks([item], rel, role, name_lines, prefix_block=True)

        if "/handlers/" in f"/{rel}" or rel.endswith("handlers/main.yml") or "handlers/" in rel:
            for doc in docs:
                for item in as_list(doc):
                    if isinstance(item, dict) and item.get("name"):
                        listen = item.get("listen")
                        self.handlers.append(
                            Handler(
                                path=rel,
                                role=role,
                                name=collapse(item["name"], 120),
                                listen=[str(x) for x in as_list(listen)] if listen else [],
                                line=(name_lines.get(collapse(item["name"], 120)) or [0])[0],
                            )
                        )

    def _index_plays(self, docs, rel: str):
        """Map playbook -> the roles it pulls in. A playbook document is a LIST of plays,
        so both the document level and the play level need flattening."""
        for doc in docs:
            for item in as_list(doc):
                if not isinstance(item, dict) or "hosts" not in item:
                    continue
                roles = set(role_names(item.get("roles")))
                if roles:
                    self.play_roles.setdefault(rel, set()).update(roles)

    def _walk_tasks(self, items, rel: str, role: str, name_lines, prefix_block=False):
        for item in as_list(items):
            if not isinstance(item, dict):
                continue
            if any(k in item for k in ("block", "rescue", "always")):
                for key in ("block", "rescue", "always"):
                    self._walk_tasks(item.get(key), rel, role, name_lines)
                if any(k in item for k in ("notify", "when", "loop", "with_items")):
                    self.tasks.append(mk_task(item, rel, role, name_lines, block=True))
                continue
            self.tasks.append(mk_task(item, rel, role, name_lines))

    # -- usage: Jinja only, braces + blocks + bare conditions ---------------- #
    def _index_usage(self, path: Path, text: str | None = None):
        rel = self.rel(path)
        if text is None:
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError as exc:
                self.errors.append((rel, f"read-error: {exc}"))
                return
        starts = line_offsets(text)
        for m in JINJA_SPAN.finditer(text):
            expr = (m.group(1) or m.group(2) or "").strip()
            if not expr:
                continue
            kind = "braces" if m.group(1) is not None else "block"
            self.uses.append(
                Use(rel, line_for(starts, m.start()), collapse(expr), kind, expr)
            )
        block_indent: int | None = None
        for i, raw in enumerate(text.splitlines(), 1):
            bm = BARE_JINJA_LINE.match(raw)
            if bm:
                expr = bm.group(2).strip().strip("'\"")
                if expr and "://" not in expr:
                    self.uses.append(Use(rel, i, collapse(expr), "bare", expr))
                block_indent = None
                continue
            kb = BARE_JINJA_BLOCK.match(raw)
            if kb:
                # entering a `when:` block list — items are expressions until the indent closes
                block_indent = len(kb.group(1))
                continue
            if block_indent is None:
                continue
            if not raw.strip() or raw.lstrip().startswith("#"):
                continue
            if (len(raw) - len(raw.lstrip())) <= block_indent:
                block_indent = None
                continue
            item = raw.strip()
            if item.startswith("- "):
                item = item[2:].strip()
            item = item.strip("'\"")
            if item and "://" not in item and item not in ("|", ">"):
                self.uses.append(Use(rel, i, collapse(item), "bare", item))


def as_list(doc):
    if doc is None:
        return []
    if isinstance(doc, list):
        return doc
    return [doc]


def classify(rel: str):
    """-> (rank, class) for a definition-bearing path, else (None, None)."""
    p = rel.replace("\\", "/")
    if p.startswith("roles/"):
        parts = p.split("/")
        if len(parts) >= 3 and parts[2] == "defaults" and p.endswith("main.yml"):
            return 10, "role_defaults"
        if len(parts) >= 3 and parts[2] == "vars" and p.endswith("main.yml"):
            return 60, "role_vars"
        return None, None
    if p.startswith("group_vars/all/") or p == "group_vars/all.yml":
        return 20, "group_vars"
    if p.startswith("group_vars/"):
        return 30, "group_vars"
    if p.startswith("host_vars/"):
        return 40, "host_vars"
    if p.startswith("playbooks"):
        return 50, "playbook"
    return None, None


def role_of(rel: str) -> str:
    parts = rel.replace("\\", "/").split("/")
    if len(parts) >= 2 and parts[0] == "roles":
        return parts[1]
    return "(playbook)"


def role_names(roles) -> list[str]:
    out = []
    for r in as_list(roles):
        if isinstance(r, str):
            out.append(r)
        elif isinstance(r, dict):
            for k in ("role", "import_role", "include_role"):
                if k in r:
                    v = r[k]
                    out.append(v if isinstance(v, str) else str(v.get("name", v)))
    return out


def top_key_lines(lines) -> dict[str, int]:
    """Column-0 `key:` first-occurrence lines for a vars file."""
    out: dict[str, int] = {}
    for i, raw in enumerate(lines, 1):
        m = TOP_KEY_LINE.match(raw)
        if m and m.group(1) not in out:
            out[m.group(1)] = i
    return out


def task_name_lines(lines) -> dict[str, list[int]]:
    """`name:` value -> [lines], in document order, consumed as matched."""
    out: dict[str, list[int]] = {}
    for i, raw in enumerate(lines, 1):
        m = TASK_NAME_LINE.match(raw)
        if not m:
            continue
        val = m.group(1).strip().strip("'\"").strip('"')
        out.setdefault(collapse(val, 120), []).append(i)
    return out


def line_offsets(text: str) -> list[int]:
    offs, pos = [0], 0
    for ln in text.splitlines(keepends=True):
        pos += len(ln)
        offs.append(pos)
    return offs


def line_for(starts: list[int], pos: int) -> int:
    return bisect.bisect_right(starts, pos)


def mk_task(item, rel: str, role: str, name_lines, block=False) -> Task:
    name = collapse(item.get("name") or ("(block)" if block else "(unnamed)"), 120)
    module = ""
    for k in item:
        if k not in CONTROL_KEYS:
            module = str(k)
            break
    raw_notify = item.get("notify")
    notifies = [collapse(x, 120) for x in as_list(raw_notify)] if raw_notify else []
    pool = name_lines.get(name)
    line = pool.pop(0) if pool else 0
    return Task(
        path=rel,
        role=role,
        name=name,
        module=module,
        when=collapse(item["when"], 60) if item.get("when") is not None else "",
        loop=mask(item["loop"] if item.get("loop") is not None else item.get("with_items")),
        notifies=notifies,
        registers=str(item.get("register") or ""),
        line=line,
    )


# --------------------------------------------------------------------------- #
# Queries — every one bounded by --limit
# --------------------------------------------------------------------------- #
def q_var(tree: Tree, name: str, limit: int) -> int:
    defs = sorted((d for d in tree.defs if d.name == name), key=lambda d: d.rank)
    uses = [u for u in tree.uses if name in set(IDENTS.findall(u.match_text))]

    print(f"# var: {name}")
    if defs:
        print(f"  DEFINED  {len(defs)} site(s), precedence low → high (last row WINS):")
        emit(
            [
                f"    [{d.rank:>2}] {RANK_LABEL[d.rank]:<38} {d.path}:{d.line:<4} = {d.value}"
                for d in defs
            ],
            limit,
        )
        top = defs[-1]
        print(f"    ⇒ effective: {top.path}:{top.line}  ({RANK_LABEL[top.rank]})")
        ties = [d for d in defs[:-1] if d.rank == top.rank]
        if ties:
            print(
                f"    ⚠ {len(ties)} more at the SAME rank — tie broken by group/host name order; "
                f"verify with: ansible-inventory --hostvars <host>"
            )
            for d in ties[: min(len(ties), 6)]:
                print(f"        {d.path}:{d.line} = {d.value}")
    else:
        print(f"  DEFINED  {NO_MATCH} — no defaults/group_vars/host_vars/role-vars/play-vars entry")
        print("           (could be dynamic: set_fact, register, include_vars, -e, or a role param)")

    print(f"\n  USED     {len(uses)} site(s)")
    if uses:
        rows = []
        for u in sorted(uses, key=lambda u: (u.path, u.line)):
            tag = {"bare": "bare  ", "block": "{% %} ", "braces": "{{ }} "}[u.kind]
            rows.append(f"    {u.path}:{u.line:<4} [{tag}]{u.expr}")
        emit(rows, limit)
        bare = sum(1 for u in uses if u.kind == "bare")
        j2 = sum(1 for u in uses if u.path.endswith(".j2"))
        print(f"    ({bare} of them in bare conditions — no braces; {j2} in .j2 templates)")
    else:
        print(f"    {NO_MATCH}")

    dyn = [t for t in tree.tasks
           if (t.registers == name) or (t.module.endswith("set_fact") and name in t.name)
           or (t.module.endswith("include_vars"))]
    if dyn:
        print(f"\n  DYNAMIC  {len(dyn)} site(s) that can shadow every static definition above")
        emit([f"    {t.path}:{t.line or '?'}  [{t.module}] {collapse(t.name, 44)}" for t in dyn], 8)

    print(
        "\n  NOTE     ansible.cfg: inject_facts_as_vars=False (HD-271) → facts reach tasks only\n"
        "           as ansible_facts['…'], never as ansible_* top-level vars."
    )
    return 0


def _notify_verdict(tree: Tree):
    """Tree-wide dangling-notify verdict (see module docstring for why tree-wide)."""
    known = set()
    for h in tree.handlers:
        known.add(h.name)
        known.update(h.listen)
    sites = [(t, n) for t in tree.tasks for n in t.notifies]
    templated = [(t, n) for t, n in sites if "{{" in n or "{%" in n]
    static = [(t, n) for t, n in sites if n not in {x[1] for x in templated}]
    dangling = [(t, n) for t, n in static if n not in known]
    return len(tree.handlers), sites, static, templated, dangling


def q_handlers(tree: Tree, limit: int, unresolved_only: bool) -> int:
    n_def, sites, static, templated, dangling = _notify_verdict(tree)

    if unresolved_only:
        print("# handlers — dangling-notify verdict (static, tree-wide)")
        print(f"  {n_def} handlers defined · {len(static)} static notify sites · "
              f"{len(templated)} templated notify names excluded from the verdict")
        print()
        if not dangling:
            print("  OK: every static notify names a handler or a listen topic somewhere in the tree")
            return 0
        emit(
            [f"  ✗ {t.path}:{t.line or '?'}  notify: {n}   (task: {collapse(t.name, 40)})"
             for t, n in dangling],
            limit,
        )
        print(
            "\n  Verdict basis: name absent from EVERY handler/listen in the tree — a typo or an\n"
            "  orphaned notify regardless of play scoping. Cross-role matches are NOT flagged:\n"
            "  handlers of any role in the same play are mutually visible and play membership is\n"
            "  not statically provable here. Templated names ({{ }}) are never flagged."
        )
        return 1

    print(f"# handlers — {n_def} defined across {len({h.role for h in tree.handlers})} roles")
    emit(
        [
            f"  {h.role:<18} {h.path}:{h.line or '?':<4} {collapse(h.name, 42)}"
            + (f"   listen: {', '.join(h.listen)}" if h.listen else "")
            for h in sorted(tree.handlers, key=lambda h: (h.role, h.path, h.line))
        ],
        limit,
    )
    print(f"\n  NOTIFY sites: {len(sites)} ({len(static)} static, {len(templated)} templated)")
    print(f"  DANGLING (tree-wide): {len(dangling)}")
    if dangling:
        emit([f"    ✗ {t.path}:{t.line or '?'}  {n}" for t, n in dangling], limit)
    return 0


def q_handler_one(tree: Tree, name: str, limit: int) -> int:
    key = collapse(name, 120)
    defs = [h for h in tree.handlers if h.name == key or key in h.listen]
    sites = [(t, n) for t in tree.tasks for n in t.notifies if n == key]
    print(f"# handler: {name}")
    if defs:
        print("  DEFINED")
        emit(
            [
                f"    {d.role:<18} {d.path}:{d.line or '?'}"
                + (f"   listen: {', '.join(d.listen)}" if d.listen else "")
                for d in defs
            ],
            limit,
        )
    else:
        print("  DEFINED  (nothing in the tree names this handler or listens on it)")
    print(f"\n  NOTIFIED BY  {len(sites)} task(s)")
    if sites:
        emit([f"    {t.path}:{t.line or '?'}  {collapse(t.name, 56)}" for t, _ in sites], limit)
    else:
        print("    (nothing notifies it — a handler nobody calls never runs)")
    return 0 if defs else 1


def q_role(tree: Tree, role: str, limit: int, all_tasks: bool) -> int:
    rdir = tree.root / "roles" / role
    if not rdir.is_dir():
        avail = sorted(p.name for p in (tree.root / "roles").glob("*") if p.is_dir())
        print(f"FAIL: no role '{role}' under {tree.rel(rdir)}")
        print(f"  available: {', '.join(avail)}")
        return 2

    def n(*parts):
        """Files in a role sub-dir. YAML-only for the code dirs; every
        file for templates/ and files/, where the payload is not YAML by design."""
        p = rdir.joinpath(*parts)
        if not p.exists():
            return 0
        src = [p] if p.is_file() else [x for x in p.rglob("*") if x.is_file()]
        if parts[-1] in ("templates", "files"):
            return len(src)
        return len([x for x in src if x.suffix in (".yml", ".yaml")])

    tasks = [t for t in tree.tasks if t.role == role]
    scope = "all task files" if all_tasks else "tasks/main.yml"
    if not all_tasks:
        primary = [t for t in tasks if t.path == f"roles/{role}/tasks/main.yml"]
        tasks = primary or tasks
    hs = [h for h in tree.handlers if h.role == role]
    mods = {}
    for t in tasks:
        if t.module:
            mods[t.module] = mods.get(t.module, 0) + 1

    print(f"# role: {role}   ({tree.rel(rdir)})")
    print(
        f"  anatomy   defaults {n('defaults')} · vars {n('vars')} · handlers {len(hs)} · "
        f"task files {n('tasks')} · templates {n('templates')} · files {n('files')} · "
        f"meta {n('meta')}"
    )
    top = sorted(mods.items(), key=lambda kv: -kv[1])[:6]
    if top:
        print("  modules   " + ", ".join(f"{k}×{v}" for k, v in top)
              + (f" (+{len(mods) - len(top)} more kinds)" if len(mods) > len(top) else ""))
    print(f"  TASKS     {len(tasks)} ({scope})"
          + ("" if all_tasks or not tasks else "   — --tasks-all widens to every task file"))
    rows = []
    for t in tasks:
        bits = []
        if t.when:
            bits.append(f"when: {collapse(t.when, 28)}")
        if t.loop not in ("", "null"):
            bits.append(f"loop: {collapse(t.loop, 20)}")
        if t.notifies:
            bits.append("notify: " + ", ".join(t.notifies)[:30])
        if t.registers:
            bits.append(f"→{t.registers}")
        rows.append(
            f"    {t.path.split('/', 2)[-1]:<32} {t.line or '?':>4}  "
            f"{(t.module or '(block)'):<36} {collapse(t.name, 30)}  {'; '.join(bits)}"
        )
    if rows:
        emit(rows, limit)
    else:
        print("    (no tasks)")
    if hs:
        print(f"  HANDLERS  {len(hs)}")
        emit([f"    {h.path}:{h.line or '?'}  {h.name}" for h in hs], 10)
    return 0


def q_module(tree: Tree, mod: str, limit: int) -> int:
    needle = mod.lower()
    hits = [t for t in tree.tasks if t.module
            and (t.module.lower() == needle or t.module.lower().endswith("." + needle))]
    print(f"# module: {mod}  —  {len(hits)} task(s)")
    if not hits:
        print("  (no task uses it; try the short name — 'template' also matches the FQCN)")
        return 0
    spell, byrole = {}, {}
    for t in hits:
        spell[t.module] = spell.get(t.module, 0) + 1
        byrole[t.role] = byrole.get(t.role, 0) + 1
    print("  spelling  " + ", ".join(f"{k}×{v}" for k, v in sorted(spell.items())))
    print("  by role   " + ", ".join(f"{k}×{v}" for k, v in sorted(byrole.items(), key=lambda kv: -kv[1])))
    emit([f"    {t.path}:{t.line or '?'}  {collapse(t.name, 62)}" for t in hits], limit)
    return 0


def q_vault(tree: Tree, limit: int) -> int:
    sites = []
    for u in tree.uses:
        for lm in LOOKUP_RE.finditer(u.match_text):
            plugin, argstr = lm.group(1), lm.group(2)
            if not OP_PLUGIN_RE.search(plugin):
                continue
            args = {
                m.group(1): (m.group(2) or m.group(3) or m.group(4) or "")
                for m in KV_ARG.finditer(argstr)
            }
            # §6: item/field/vault NAMES and file:line only. Those identifiers are already
            # tracked in git; the value behind them is never read, so there is nothing here
            # to mask — and nothing is printed that could be one.
            item = args.get("vault_item") or args.get("item") or args.get("item_id")
            if not item:
                item = first_positional(argstr) or "?"
            field = args.get("field") or args.get("subkey_list") or "?"
            vault = args.get("vault") or "?"
            sites.append(f"    {u.path}:{u.line:<4} item={item}  field={field}  vault={vault}")

    print(f"# vault — 1Password lookup sites: {len(sites)}")
    print("  CONVENTIONS §6: item/field NAMES + file:line only — no value is read or printed.")
    if sites:
        emit(sites, limit)
    else:
        print("  (none)")

    items = {}
    for s in sites:
        m = re.search(r"item=(\S+)", s)
        if m:
            items[m.group(1)] = items.get(m.group(1), 0) + 1
    print(f"\n  distinct items: {len(items)}")
    emit([f"    {k}×{v}" for k, v in sorted(items.items(), key=lambda kv: (-kv[1], kv[0]))], limit,
         note="raise --limit")
    print(
        "  Cross-check against scripts/check-vault-items.sh (the seed-before-converge gate,\n"
        "  HD-244 coverage rule) — this query is discovery, not the contract."
    )
    return 0


def q_jinja(tree: Tree, pattern: str, limit: int) -> int:
    try:
        rx = re.compile(pattern)
    except re.error as exc:
        print(f"FAIL: bad regex: {exc}")
        return 2
    hits = [u for u in tree.uses if rx.search(u.match_text)]
    print(f"# jinja matching /{pattern}/ — {len(hits)} expression(s)")
    print("  (YAML scaffolding excluded by construction; bare conditions included)")
    if hits:
        emit(
            [f"    {u.path}:{u.line:<4} [{u.kind:<5}] {collapse(u.match_text, 110)}"
             for u in sorted(hits, key=lambda u: (u.path, u.line))],
            limit,
        )
        print("  (matched against the full expression; display capped at 110 chars)")
    else:
        print(f"  {NO_MATCH}")
    return 0


def q_list_vars(tree: Tree, rank: int | None, limit: int) -> int:
    buckets: dict[int, dict[str, list[str]]] = {}
    for d in tree.defs:
        if rank and d.rank != rank:
            continue
        buckets.setdefault(d.rank, {}).setdefault(d.path, []).append(d.name)
    print("# defined variables, by precedence rank (low → high)")
    for r, label, where in PRECEDENCE:
        if r == 70 or r == 90:
            continue
        if rank and r != rank:
            continue
        files = buckets.get(r, {})
        total = sum(len(v) for v in files.values())
        print(f"\n  [{r}] {label}   {where}")
        print(f"      {total} var(s) in {len(files)} file(s)")
        for path in sorted(files)[:6]:
            names = files[path]
            shown = ", ".join(sorted(names)[:8])
            print(f"      {path:<44} {shown}" + (f" … +{len(names) - 8}" if len(names) > 8 else ""))
        if len(files) > 6:
            print(f"      … +{len(files) - 6} more files")
    print(
        "\n  Dynamic classes (not listed): set_fact / register / include_vars / task vars (-e).\n"
        "  Resolve one end-to-end with: --var NAME"
    )
    return 0


def q_context(tree: Tree, limit: int) -> int:
    print(f"# scan context — {tree.label}  ({tree.root})")
    print(f"  exists      {tree.root.is_dir()}")
    print(f"  YAML files  {len(tree.yml_files)}   .j2 templates {len(tree.j2_files)}")
    print(f"  var defs    {len(tree.defs)}   jinja sites {len(tree.uses)}   "
          f"tasks {len(tree.tasks)}   handlers {len(tree.handlers)}")
    print(f"  plays with roles: {len(tree.play_roles)}")
    if tree.errors:
        print(f"\n  PARSE/SKIP NOTES ({len(tree.errors)}) — these files are only partially indexed:")
        emit([f"    {p}: {e}" for p, e in tree.errors[: limit]], limit)
    print("\n  Precedence ladder used by --var (low → high; last match wins):")
    for r, label, where in PRECEDENCE:
        print(f"    [{r:>2}] {label:<52} {where}")
    print(
        "\n  Static scope: include_role/import_role param passing, vars_files content, and\n"
        "  group ordering within a rank are NOT resolved. For ground truth on one host use:\n"
        "    ansible-inventory --inventory=IaC/ansible/inventory.ini "
        "--host=<host> --list | ..."
    )
    return 0


# --------------------------------------------------------------------------- #
# Self-test: a sandbox fixture + canaries that FAIL under a naive implementation
# --------------------------------------------------------------------------- #
def self_test() -> int:
    """Fixture built in a temp dir; every assertion is chosen to distinguish the correct
    implementation from the obvious wrong one (CONVENTIONS §6: a test that cannot fail is
    not evidence)."""
    tmp = Path(tempfile.mkdtemp(prefix="hd456-selftest-"))
    fails: list[str] = []

    def check(label, cond, detail=""):
        print(f"  {'ok  ' if cond else 'FAIL'}  {label}" + (f"   [{detail}]" if detail and not cond else ""))
        if not cond:
            fails.append(label)

    try:
        A = tmp / "ansible"
        (A / "roles" / "r1" / "defaults").mkdir(parents=True)
        (A / "roles" / "r1" / "vars").mkdir(parents=True)
        (A / "roles" / "r1" / "tasks").mkdir(parents=True)
        (A / "roles" / "r1" / "handlers").mkdir(parents=True)
        (A / "roles" / "r1" / "templates").mkdir(parents=True)
        (A / "group_vars" / "all").mkdir(parents=True)
        (A / "group_vars").mkdir(parents=True, exist_ok=True)
        (A / "host_vars").mkdir(parents=True, exist_ok=True)
        (A / "playbooks").mkdir(parents=True, exist_ok=True)

        w = lambda p, s: (A / p).write_text(s, encoding="utf-8")  # noqa: E731
        w("roles/r1/defaults/main.yml", "my_var: from_defaults\nbase_port: 8080\n")
        w("roles/r1/vars/main.yml", "my_var: from_role_vars\n")
        w("group_vars/all/main.yml", "my_var: from_group_all\n")
        w("group_vars/g1.yml",
          "my_var: from_group_g1\nplain_secret: \"hunter2literal\"\n")
        w("host_vars/h1.yml",
          "my_var: from_host\nthe_password: !vault |\n"
          "          $ANSIBLE_VAULT;1.1;AES256\n"
          "          DEADBEEFBEEFCAFEBABEsecretciphertextmustneverprint\n")
        w("roles/r1/tasks/main.yml",
          "- name: assert task with a bare that-list\n"
          "  ansible.builtin.assert:\n"
          "    that:\n"
          "      - my_var != \'from_defaults\'\n"
          "      - base_port >= 1\n"
          "\n"
          "- name: block-when task\n"
          "  ansible.builtin.stat:\n"
          "    path: /x\n"
          "  when:\n"
          "    - blocklisted_var is defined\n"
          "    - (lookup('community.general.onepassword', 'op-item', field='credential',"
          " vault=op_vault) | length) >= 16\n"
          "\n"
          "- name: gate task\n"
          "  ansible.builtin.debug:\n"
          "    msg: hi\n"
          "  when: my_var == 'from_host'\n"
          "  notify: ghost handler\n"
          "  register: my_var_reg\n"
          "\n"
          "- name: good task\n"
          "  ansible.builtin.command: true\n"
          "  notify: real handler\n")
        w("roles/r1/handlers/main.yml",
          "- name: real handler\n  ansible.builtin.systemd:\n    name: x\n    state: restarted\n")
        w("roles/r1/templates/x.j2", "{% for i in range(3) %}{{ my_var }}{% endfor %}\n")
        w("playbooks/p.yml", "- hosts: g1\n  roles:\n    - r1\n")

        tree = Tree(A, label="selftest")
        out = _capture(lambda: q_var(tree, "my_var", 50))
        outh = _capture(lambda: q_handlers(tree, 50, True))
        outv = _capture(lambda: q_vault(tree, 50))

        # 1. precedence ORDER, and the winner is role vars (rank 60) not host_vars (40).
        #    A naive "host beats group" implementation picks host_vars → fails here.
        check("precedence: role vars outrank host_vars",
              "⇒ effective: host_vars/h1.yml" not in out
              and "⇒ effective: roles/r1/vars/main.yml" in out,
              "winner row")
        check("precedence: all four lower ranks listed in order",
              all(f"from_{x}" in out for x in ("defaults", "group_all", "group_g1", "host"))
              and out.index("from_defaults") < out.index("from_group_all")
              < out.index("from_group_g1") < out.index("from_host") < out.index("from_role_vars"),
              "row order")

        # 2. CANARY: bare Jinja usage in `when:` — a {{ }}-only scanner finds nothing.
        check("bare-Jinja usage found in when: (no braces)",
              "[bare  ] my_var ==" in out or "bare" in out and "my_var ==" in out,
              "expected a bare-condition usage row")

        # 3. CANARY (§6, two distinct masking paths): an encrypted payload must surface as
        #    the mask, and a secret-named plaintext must surface as a length — never as the
        #    literal. Both literals are asserted absent from every captured output.
        outp = _capture(lambda: q_var(tree, "the_password", 50))
        outs = _capture(lambda: q_var(tree, "plain_secret", 50))
        check("§6 encrypted payload → mask, ciphertext never printed",
              VAULT_MASK in outp and "mustneverprint" not in outp
              and "mustneverprint" not in out and "mustneverprint" not in outh
              and "mustneverprint" not in outv, outp[:120])
        check("§6 secret-named plaintext → length only",
              bool(re.search(r"<masked:\d+ chars>", outs)) and "hunter2literal" not in outs,
              outs[:120])

        # 4. handler verdict: ghost flagged, real handler not
        flagged = [ln for ln in outh.splitlines() if ln.strip().startswith("✗")]
        check("dangling notify flagged", any("ghost handler" in ln for ln in flagged),
              outh[:140])
        check("resolved notify NOT flagged",
              not any("real handler" in ln for ln in flagged), str(flagged))

        # 5. usage found in .j2 via a {% %} block (invisible to a braces-only scan too)
        check("{% %} block usage in .j2 indexed",
              any(u.path.endswith("x.j2") and u.kind == "block" for u in tree.uses))

        # 6. module + role digests carry the task
        oq = _capture(lambda: q_role(tree, "r1", 20, False))
        check("--role lists tasks with module", "gate task" in oq and "ansible.builtin.debug" in oq)
        om = _capture(lambda: q_module(tree, "command", 20))
        check("--module matches by short name", "good task" in om)
        om2 = _capture(lambda: q_module(tree, "debug", 20))
        check("--module matches FQCN suffix", "gate task" in om2)

        # 5b. CANARY: bare Jinja in a BLOCK-LIST `when:` (a same-line-only matcher misses it)
        check("bare-Jinja block list under when: is indexed",
              any(u.kind == "bare" and "blocklisted_var" in u.match_text
                  for u in tree.uses),
              str([u.expr for u in tree.uses if u.kind == "bare"]))

        # 5c. CANARY: bare Jinja under ansible.builtin.assert `that:` (un-braced by design)
        check("bare-Jinja under assert that: is indexed",
              any(u.kind == "bare" and "base_port" in u.match_text for u in tree.uses),
              str([u.expr for u in tree.uses if u.kind == "bare"][:6]))

        # 6b. playbook -> role map (a playbook document is a LIST of plays: a scan that
        #     flattens only the document level silently reports "no roles anywhere")
        check("playbook role map populated",
              tree.play_roles.get("playbooks/p.yml") == {"r1"}, str(tree.play_roles))

        # 7. custom tags do not lose the file (!vault handled; blueprint-style tags survive)
        w("group_vars/g1.yml", "my_var: from_group_g1\ntagged_thing: !KeyOf {a: b}\n")
        t2 = Tree(A, label="selftest2")
        check("unknown custom tag does not drop the file",
              any(d.name == "tagged_thing" for d in t2.defs)
              and not any("tag" in e.lower() and "g1.yml" in p for p, e in t2.errors),
              str([e for p, e in t2.errors if "g1" in p]))

        # 8. line numbers are real, not 0
        check("definition line numbers resolved",
              any(d.path.endswith("defaults/main.yml") and d.line == 1 for d in tree.defs))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print(f"\nself-test: {'PASS' if not fails else 'FAIL — ' + ', '.join(fails)}")
    return 0 if not fails else 1


def _capture(fn) -> str:
    import io
    from contextlib import redirect_stdout
    buf = io.StringIO()
    with redirect_stdout(buf):
        fn()
    return buf.getvalue()


# --------------------------------------------------------------------------- #
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        prog="ansible_query.py",
        description="Read-only Ansible fact queries over this repo (HD-456). "
                    "Answers, not syntax trees. Never prints a secret value.",
        epilog="examples:\n"
               "  --var docker_services            --role docker_services --tasks\n"
               "  --handlers --unresolved          --module template\n"
               "  --vault                          --jinja \"selectattr\\('enabled'\\)\"\n"
               "  --list-vars --rank 30            --context\n"
               "  --root spark --list-vars         --self-test\n",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--var", metavar="NAME", help="definitions (precedence-ordered) + usage sites")
    g.add_argument("--handler", metavar="NAME", help="who defines this handler, who notifies it")
    g.add_argument("--handlers", action="store_true", help="all handlers + dangling-notify count")
    g.add_argument("--role", metavar="ROLE", help="role anatomy + bounded task manifest")
    g.add_argument("--module", metavar="NAME", help="tasks using a module (short name or FQCN)")
    g.add_argument("--vault", action="store_true", help="1Password lookup sites (names only)")
    g.add_argument("--jinja", metavar="REGEX", help="search Jinja expressions only")
    g.add_argument("--list-vars", action="store_true", help="defined vars by precedence rank")
    g.add_argument("--context", action="store_true", help="what the scan sees + precedence ladder")
    g.add_argument("--self-test", action="store_true", help="sandboxed fixture + canaries")

    ap.add_argument("--unresolved", action="store_true",
                    help="with --handlers: verdict only (exit 1 when dangling notifies exist)")
    ap.add_argument("--tasks-all", action="store_true",
                    help="with --role: every task file, not just tasks/main.yml")
    ap.add_argument("--rank", type=int, metavar="N",
                    help="with --list-vars: only this precedence rank")
    ap.add_argument("--root", default="iac", metavar="PATH|iac|spark",
                    help="Ansible tree to scan (default: IaC/ansible)")
    ap.add_argument("--limit", type=int, default=40, metavar="N",
                    help="max rows per section (default 40) — context discipline")
    args = ap.parse_args(argv)

    if args.self_test:
        print("# ansible_query.py self-test (sandboxed temp fixture)")
        return self_test()

    root = ALT_ROOTS.get(args.root, Path(args.root)) if args.root != "iac" else DEFAULT_ROOT
    if args.root in ("iac", "spark"):
        root = ALT_ROOTS[args.root]
    root = root.resolve()
    if not root.is_dir():
        print(f"FAIL: --root is not a directory: {root}")
        return 2

    tree = Tree(root, label=args.root)
    if not tree.yml_files and not tree.j2_files:
        print(f"FAIL: no .yml/.j2 under {root}")
        return 2

    if args.var:
        return q_var(tree, args.var, args.limit)
    if args.handler:
        return q_handler_one(tree, args.handler, args.limit)
    if args.handlers:
        return q_handlers(tree, args.limit, args.unresolved)
    if args.role:
        return q_role(tree, args.role, args.limit, args.tasks_all)
    if args.module:
        return q_module(tree, args.module, args.limit)
    if args.vault:
        return q_vault(tree, args.limit)
    if args.jinja:
        return q_jinja(tree, args.jinja, args.limit)
    if args.list_vars:
        return q_list_vars(tree, args.rank, args.limit)
    return q_context(tree, args.limit)


if __name__ == "__main__":
    sys.exit(main())
