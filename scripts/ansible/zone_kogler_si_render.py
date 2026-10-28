#!/usr/bin/env python3
"""Render every ``kogler.si`` answer-plane consumer into one normalized shape (HD-436).

The zone's membership is consumed by THREE renderers:

  * the Technitium seed task (``roles/docker_services/tasks/technitium-seed.yml``)
    — per instance: VPS ``primary``, oldsrv ``secondary``, Pi ``secondary-pi``;
  * headscale's MagicDNS records (``templates/docker_services/headscale/config.yaml.j2`` and the
    ``extra_records.yaml.j2`` file its ``dns.extra_records_path`` key may point at) — the plain
    ``*.kogler.si`` list and the ``*.ts.kogler.si``-only list, rendered in BOTH record shapes so a
    comparison can prove the key switch moves no answer;
  * the public Cloudflare set (``roles/cloudflare_dns/tasks/main.yml`` + its vars).

This module renders those THREE REAL SOURCES (the actual template file, the actual
seed task, the actual role task — not a paraphrase of them) into a normalized dict, so
``capture_zone_kogler_si_golden.py`` (pre-change) and ``check_zone_kogler_si_parity.py``
(post-change) compare the same shape. Rendering the real artifacts is the whole point:
a mirror implementation would validate itself and prove nothing.

Nothing here contacts a host, reads the vault, or runs Ansible. Secrets are replaced by
an in-memory dummy (`DUMMY-VAULT-NOT-A-SECRET`); no vault value is ever read or printed.

Run directly for a human-readable dump:  python3 scripts/ansible/zone_kogler_si_render.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import yaml
from jinja2 import ChainableUndefined, Environment, StrictUndefined

# HD-1118 Stage 1: FOUND, not assumed from a depth — scripts/lib/repo_root.py.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import root as _hl_root  # noqa: E402
ROOT = _hl_root(__file__)
ANSIBLE = ROOT / "IaC" / "ansible"

SEED_TASK = "Technitium: ensure split-horizon A records"
CF_TASK = "Ensure public DNS records are present (idempotent)"
SEED_FILE = ANSIBLE / "roles/docker_services/tasks/technitium-seed.yml"
HEADSCALE_TEMPLATE = ANSIBLE / "templates/docker_services/headscale/config.yaml.j2"
HEADSCALE_COMPOSE_TEMPLATE = ANSIBLE / "templates/docker_services/headscale/docker-compose.yml.j2"
HEADSCALE_RECORDS_TEMPLATE = ANSIBLE / "templates/docker_services/headscale/extra_records.yaml.j2"
# The rendered form of that template — the compose bind SOURCE name. The `.j2` suffix is not
# cosmetic: the deploy copies the whole template dir raw and then renders every `_extra_templates`
# entry OVER that copy with the suffix stripped, so a records source without `.j2` would reach the
# host as unrendered template text.
HEADSCALE_RECORDS_FILE = HEADSCALE_RECORDS_TEMPLATE.with_suffix("").name
# The two keys headscale can take its MagicDNS records from. Exactly ONE may be rendered: the
# pinned headscale exits at startup when both are set, and the container still reports `Running`.
RECORD_KEYS = ("extra_records", "extra_records_path")
CF_TASKS_FILE = ANSIBLE / "roles/cloudflare_dns/tasks/main.yml"
CF_VARS_FILE = ANSIBLE / "roles/cloudflare_dns/vars/main.yml"
ZONE_VAR_FILE = ANSIBLE / "group_vars/all/main.yml"
GOLDEN_PATH = ROOT / "scripts" / "testdata" / "zone_kogler_si_golden.json"

# The three instances the seed runs against (docs/network-dns.md §Per-Instance view).
INSTANCES = ["primary", "secondary", "secondary-pi"]

# Context sources. group_vars/all is the only group readable by ALL THREE consumers
# (seed on VPS/oldsrv/Pi, headscale template on VPS, playbooks/dns.yml on localhost),
# which is why the derived zone list lives there.
CONTEXT_FILES = [
    "group_vars/all/main.yml",
    "group_vars/all/versions.yml",
    "group_vars/vps.yml",
]

VAULT_DUMMY = "DUMMY-VAULT-NOT-A-SECRET"


class RenderError(RuntimeError):
    """A source could not be rendered — reported, never swallowed."""


def _lookup(name: str, *args, **kwargs):
    """The lookups the answer-plane sources actually use — nothing else.

    An unimplemented lookup RAISES rather than returning empty: a derived view built on
    a lookup this renderer silently stubbed would make the parity check fiction.
    """
    short = str(name).rsplit(".", 1)[-1]
    if short == "subelements":
        needle, key = args[0], args[1]
        if kwargs.get("start_index", 0):
            raise RenderError("subelements start_index is not supported here")
        skip_missing = str(kwargs.get("skip_missing", "False")).lower() == "true"
        pairs = []
        for entry in needle:
            rows = entry.get(key) if isinstance(entry, dict) else None
            if rows is None:
                if skip_missing:
                    continue
                raise RenderError(f"subelements: entry {entry!r} has no {key!r} key")
            for row in rows:
                pairs.append([entry, row])
        return pairs
    if short == "vars":
        # Only used by unrelated group_vars (WireGuard keys); empty keeps those resolvable
        # while the answer plane, which uses no lookup of that kind, stays exact.
        return ""
    raise RenderError(f"lookup {name!r} is not implemented in the answer-plane renderer")


def _env(strict: bool = True) -> Environment:
    """Jinja environment close enough to Ansible's for these sources.

    ``strict`` (the default everywhere except the whole-file headscale render) means an
    UNRESOLVED name is an error, not an empty string. That is not a style choice: an
    answer-plane value that silently renders empty is precisely the silent-no-op class
    this refactor exists to kill, and during the group_vars fixpoint it is also what
    forces dependency-ordered resolution (a name that is not ready raises and is retried
    on the next pass instead of resolving to '').

    ``strict=False`` uses ``ChainableUndefined``, which mirrors Ansible's
    ``AnsibleUndefined`` for ``x | default('y')`` and for attribute chains into host
    facts this checker deliberately does not resolve — needed to render the WHOLE
    headscale config file, whose OIDC/facts legs are not part of the answer plane.
    """
    env = Environment(undefined=StrictUndefined if strict else ChainableUndefined,
                      trim_blocks=False, lstrip_blocks=False)

    def _comment(value, prefix="# ", string=None):  # ansible's `comment` filter
        text = str(value)
        return "\n".join(f"{prefix}{line}" if line.strip() else prefix.rstrip() for line in text.splitlines())

    # Ansible lookups in group_vars (WireGuard public keys read from host_vars) are not
    # part of the answer plane; they resolve to empty here rather than aborting the load.
    env.globals["lookup"] = _lookup
    env.globals["query"] = env.globals["q"] = _lookup
    env.filters["comment"] = _comment
    env.filters["flatten"] = lambda seq: [x for item in seq for x in (item if isinstance(item, (list, tuple)) else [item])]
    env.filters["to_json"] = lambda v, **kw: json.dumps(v)
    env.filters["from_json"] = lambda v: json.loads(v)
    env.filters["from_yaml"] = lambda v: yaml.safe_load(v)

    def _combine(base, *others, **kwargs):  # ansible's `combine`, shallow merge only
        """Merge dicts — the one use is attaching the canonical public CNAME record to an entry.

        ``recursive=``/``list_merge=`` are NOT implemented: the answer plane declares exposure, it
        never merges deep structures, and a shim that quietly differed from Ansible here would make
        the parity claim fiction. An option this renderer does not implement RAISES.
        """
        if kwargs:
            raise RenderError(f"combine options {sorted(kwargs)} are not implemented in the answer-plane renderer")
        out = dict(base)
        for other in others:
            out.update(other)
        return out

    env.filters["combine"] = _combine
    # The handful of Ansible-only filters/tests the loaded group_vars actually use.
    # Deliberately an allowlist, not a catch-all: an unknown filter must raise rather
    # than silently return empty, or a typo inside a zone entry would render quietly.
    env.filters["regex_replace"] = lambda v, find, rep, **kw: re.sub(find, rep, str(v))
    env.filters["regex_search"] = lambda v, find, **kw: (re.search(find, str(v)) or [None])[0] if not isinstance(v, list) else next((m[0] for m in (re.findall(find, str(x)) for x in v) if m), None)
    env.filters["regex_findall"] = lambda v, find, **kw: re.findall(find, str(v))
    env.filters["split"] = lambda v, sep=None: str(v).split(sep)
    env.filters["basename"] = lambda v: str(Path(str(v)).name)
    env.tests["search"] = lambda v, pattern, **kw: re.search(pattern, str(v)) is not None
    env.tests["match"] = lambda v, pattern, **kw: re.match(pattern, str(v)) is not None
    return env


def _raw_vars() -> dict:
    out: dict = {}
    for rel in CONTEXT_FILES:
        path = ANSIBLE / rel
        if not path.exists():
            raise RenderError(f"context source missing: {path}")
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        except (OSError, yaml.YAMLError) as exc:
            raise RenderError(f"cannot parse {path}: {exc}") from exc
        if not isinstance(data, dict):
            raise RenderError(f"{path} is not a mapping")
        out.update(data)
    return out


def build_context(extra: dict | None = None) -> dict:
    """Resolve group_vars the way Ansible does at consume time: lazily, per host.

    SSOT keys such as ``dns_primary_ip`` / ``nas_home_ip`` / ``tailnet_base_domain`` are
    THEMSELVES Jinja expressions over ``network_static_hosts``, so they must be resolved
    before any consumer renders — otherwise a consumer would compare against an
    unresolved ``'{{ … }}'`` string and every parity claim would be fiction.

    Resolution is deliberately PARTIAL and per-``extra``: a split-horizon target
    (``home_edge_ip``) reads ``svc.instance``, which only exists on the host the seed
    runs against, so it is resolved with the caller's context rather than once globally.
    A key that cannot resolve here (host facts, vault keys) stays as authored; the
    consumer that actually needs it raises, instead of comparing against a silent empty
    string.
    """
    env = _env()
    raw = _raw_vars()
    base = {k: v for k, v in raw.items() if not (isinstance(v, str) and "{{" in v)}
    base["vault"] = {"headscale_api": {"username": VAULT_DUMMY, "credential": VAULT_DUMMY}}
    base["ansible_managed"] = "Ansible managed"
    if extra:
        base.update(extra)

    pending = {k for k, v in raw.items() if isinstance(v, str) and "{{" in v}
    for _ in range(8):  # fixpoint: expressions that reference other expressions
        if not pending:
            break
        progressed = False
        for key in sorted(pending):
            try:
                value = env.from_string(raw[key]).render(**base)
            except Exception:  # noqa: BLE001 - unresolved now; the consumer that needs it reports
                continue
            base[key] = _native(value)
            pending.discard(key)
            progressed = True
        if not progressed:
            break
    # Keys still unresolved here are host-scoped (a split-horizon target reads
    # `svc.instance`, which only exists on the host the seed runs against) or belong to
    # other groups. They are left OUT of the context on purpose: a consumer that needs
    # one gets "undefined" from the strict environment and reports it, instead of
    # comparing against an empty string that resolved from nothing.
    return base


def _native(value: str) -> object:
    """Round-trip a literal-looking rendered string back to data (Ansible native types).

    Jinja ALWAYS yields a string, so a group_vars view authored as
    `"{{ zone_kogler_si | selectattr(...) | list }}"` comes back as the TEXT
    "['llogs.kogler.si', ...]". Left as a string, the seed's per-item gate
    `item.name not in zone_kogler_si_lan_only` becomes a STRING SUBSTRING test — and
    `logs.kogler.si` IS a substring of `llogs.kogler.si`, `litellm.kogler.si` of
    `llitellm.kogler.si`, `kogler.si` of both — so three legitimate records were reported
    as gated OFF the VPS primary. Ansible hands the consumer a real list, so a checker
    that does not does not mirror Ansible.

    Only `[`/`{` prefixes are parsed: `yaml.safe_load('no')` is `False` and `'10.10.1.200'`
    would stop being an address, so a scalar keeps its text (same convention as
    ``_loop_items``).
    """
    text = value.strip()
    if text[:1] in ("[", "{"):
        try:
            return yaml.safe_load(text)
        except yaml.YAMLError:
            return value
    return value


def _render_value(value, ctx: dict, env: Environment) -> object:
    """Template every string in a loaded structure, as Ansible does for task args."""
    if isinstance(value, dict):
        return {k: _render_value(v, ctx, env) for k, v in value.items()}
    if isinstance(value, list):
        return [_render_value(v, ctx, env) for v in value]
    if isinstance(value, str) and "{{" in value:
        try:
            return env.from_string(value).render(**ctx)
        except Exception as exc:  # noqa: BLE001 - reported, never swallowed
            raise RenderError(f"cannot render {value!r}: {exc}") from exc
    return value


def _render_expr(expr: str, ctx: dict, *, is_expr: bool = False) -> str:
    """Render one value from a real Ansible source.

    ``is_expr=True`` marks a bare Ansible expression (a task ``when:``), which Ansible
    wraps in ``{{ }}`` implicitly. Everything else is rendered only if it carries its own
    braces — the literal ``state: present`` must stay the string ``present``, not become a
    reference to a variable named ``present``.
    """
    text = str(expr)
    if is_expr and "{{" not in text and "{%" not in text:
        text = "{{ " + text + " }}"
    if "{{" not in text and "{%" not in text:
        return text.strip()
    env = _env()
    out = text
    # Ansible templates recursively: `ip: "{{ home_edge_ip }}"` resolves to a string that
    # is itself a template, and so on. Stop when it stops changing shape; a value that is
    # STILL a template after that is reported, not passed through unresolved.
    for _ in range(6):
        try:
            rendered = env.from_string(out).render(**ctx).strip()
        except Exception as exc:  # noqa: BLE001 - reported, never swallowed
            raise RenderError(f"cannot render expression {expr!r}: {exc}") from exc
        if rendered == out:
            break
        out = rendered
    if "{{" in out or "{%" in out:
        raise RenderError(f"expression {expr!r} never resolved to a value (still {out!r})")
    return out


def _walk_tasks(node):
    """Yield every task dict in a task file, descending into block/always/rescue/tasks."""
    if isinstance(node, list):
        for item in node:
            yield from _walk_tasks(item)
    elif isinstance(node, dict):
        if "action" in node or any(isinstance(v, dict) for k, v in node.items() if k in {
                "ansible.builtin.uri", "community.general.cloudflare_dns", "uri", "cloudflare_dns"}):
            yield node
        for key in ("block", "always", "rescue", "tasks"):
            if key in node:
                yield from _walk_tasks(node[key])


def _find_task(path: Path, name: str, module_hints: tuple[str, ...]) -> dict:
    try:
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        raise RenderError(f"cannot parse {path}: {exc}") from exc
    for task in _walk_tasks(doc):
        if task.get("name") != name:
            continue
        if not any(k in task for k in module_hints):
            continue
        return task
    # Fail loud: a missing task would make the whole comparison vacuously green.
    raise RenderError(f"task {name!r} not found in {path} — the parity check would be vacuous")


def _loop_items(task: dict, ctx: dict, source: str) -> list[dict]:
    """Resolve a task's ``loop:`` to concrete item dicts.

    Accepts BOTH shapes on purpose: the hand-authored literal list (the pre-change
    sources) and a Jinja expression over the derived list (post-change). A loop that
    yields nothing is an ERROR here, never an empty set — an empty answer-plane is the
    silent-no-op class this refactor exists to make impossible.
    """
    loop = task.get("loop")
    if loop is None:
        raise RenderError(f"{source}: task has no `loop:` — nothing to render")
    if isinstance(loop, str):
        items = _render_value(loop, ctx, _env())
        if isinstance(items, str):
            # Ansible native-types: a literal-looking string round-trips back to data.
            try:
                items = yaml.safe_load(items)
            except yaml.YAMLError as exc:
                raise RenderError(f"{source}: loop rendered to a non-list string: {items!r}") from exc
    else:
        items = _render_value(loop, ctx, _env())
    if not isinstance(items, list):
        raise RenderError(f"{source}: loop rendered to {type(items).__name__}, expected a list: {items!r}")
    if not items:
        raise RenderError(f"{source}: loop rendered ZERO items — an empty answer plane is never valid")
    return items


# --------------------------------------------------------------------------- consumers

def render_technitium() -> dict[str, list[dict]]:
    """Per-instance Technitium record set, driven by the REAL seed task.

    The context is built PER INSTANCE on purpose: a split-horizon target resolves
    against ``svc.instance``, which is exactly what makes oldsrv and the VPS answer the
    same name differently.
    """
    task = _find_task(SEED_FILE, SEED_TASK, ("ansible.builtin.uri", "uri"))
    body = task.get("ansible.builtin.uri", task.get("uri", {})).get("body", {})
    for field in ("domain", "ipAddress"):
        if field not in body:
            raise RenderError(f"seed task body lost its {field!r} field")
    expr_domain, expr_ip = str(body["domain"]), str(body["ipAddress"])
    gate = task.get("when")
    if gate is None:
        raise RenderError("seed task lost its per-item `when` gate — LAN-only records would seed on the VPS")

    out: dict[str, list[dict]] = {}
    for instance in INSTANCES:
        ctx_i = build_context(extra={"svc": {"instance": instance}})
        rows = []
        for item in _loop_items(task, ctx_i, "technitium seed"):
            row_ctx = dict(ctx_i, item=item)
            keep = _render_expr(str(gate), row_ctx, is_expr=True)
            if keep not in ("True", "False"):
                raise RenderError(f"seed when-gate did not evaluate to a boolean: {keep!r}")
            if keep == "False":
                continue
            domain = _render_expr(expr_domain, row_ctx)
            ip = _render_expr(expr_ip, row_ctx)
            if not domain or not ip:
                raise RenderError(f"seed row rendered empty: {domain!r} -> {ip!r}")
            if "<" in ip or " " in ip:
                raise RenderError(f"seed row {domain} rendered a non-IP value {ip!r}")
            rows.append({"name": domain, "ip": ip})
        if not rows:
            raise RenderError(f"seed rendered ZERO records for instance {instance}")
        out[instance] = _dedup_sorted(rows)
    return out


def _render_text(path: Path, ctx: dict, where: str) -> str:
    """Render one headscale template to TEXT with the SAME Jinja shape the deploy uses.

    The vault here is the in-memory dummy `build_context` installs, so a render printed from the
    command line validates SHAPE only — it is not the file a converge writes and must never be copied
    to a host.
    """
    env = _env(strict=False)
    try:
        return env.from_string(path.read_text(encoding="utf-8")).render(**ctx)
    except Exception as exc:  # noqa: BLE001 - a template that will not render is reported, never swallowed
        raise RenderError(f"cannot render {path.name} ({where}): {exc}") from exc


def _render_yaml_template(path: Path, ctx: dict, where: str):
    """Render one headscale template and parse it."""
    try:
        return yaml.safe_load(_render_text(path, ctx, where))
    except yaml.YAMLError as exc:
        raise RenderError(f"rendered {path.name} ({where}) is not valid YAML: {exc}") from exc


def _dns_record_key(dns, where: str) -> str:
    """The ONE key this headscale config takes its MagicDNS records from.

    `dns.extra_records` and `dns.extra_records_path` are mutually exclusive on the pinned headscale:
    both set exits the process at startup while `docker` still reports the container `Running`, so a
    render that emits both is a dead control plane, not a config. This is the probe; the parity
    gate's `--self-test` plants that shape to prove the probe fires.
    """
    present = [key for key in RECORD_KEYS if key in (dns or {})]
    if len(present) != 1:
        raise RenderError(f"{where}: dns renders {present or ['<neither record key>']} — headscale takes "
                          "EXACTLY ONE of dns.extra_records / dns.extra_records_path")
    return present[0]


def _records_bind_path(ctx: dict) -> str:
    """The container path the records file is bind-mounted at, read from the compose template.

    Read from the mount rather than re-typed here so the config key and the bind cannot drift apart
    unnoticed: the check compares the rendered `extra_records_path` against this value.
    """
    doc = _render_yaml_template(HEADSCALE_COMPOSE_TEMPLATE, ctx, "headscale compose")
    volumes = ((doc or {}).get("services") or {}).get("headscale", {}).get("volumes") or []
    prefix = f"./{HEADSCALE_RECORDS_FILE}:"
    found = {str(v).split(":")[1] for v in volumes if str(v).startswith(prefix) and str(v).count(":") == 2}
    if len(found) != 1:
        raise RenderError(f"the headscale compose mounts {HEADSCALE_RECORDS_FILE} "
                          f"at {sorted(found) or 'nothing'} — expected exactly one ./<file>:<container path> bind")
    return found.pop()


def _headscale_rows(ctx: dict, shape: str) -> list[dict]:
    """headscale's MagicDNS records IN DOCUMENT ORDER for one render shape.

    `inline` forces the `dns.extra_records` block, `file` forces `dns.extra_records_path` at the path
    the compose bind mounts, and `default` renders whatever `headscale_extra_records_path` authors
    today. Same zone views, same context, so a shape that answers differently is an error here rather
    than an NXDOMAIN after the switch.
    """
    zone = str(ctx.get("domain_public") or "")
    base_domain = str(ctx.get("tailnet_base_domain") or "")
    if not zone or "{{" in zone:
        raise RenderError(f"domain_public unresolved: {zone!r}")
    if not base_domain or "{{" in base_domain:
        # The `.ts` twin is spelled from this value; unresolved, every twin name would land in the
        # "outside zone" branch below with a message that blames the zone instead of the variable.
        raise RenderError(f"tailnet_base_domain unresolved: {base_domain!r}")
    if shape == "inline":
        render_ctx, path = dict(ctx, headscale_extra_records_path=""), None
    elif shape == "file":
        path = _records_bind_path(ctx)
        render_ctx = dict(ctx, headscale_extra_records_path=path)
    elif shape == "default":
        render_ctx, path = dict(ctx), None
    else:
        raise RenderError(f"unknown headscale render shape {shape!r}")

    doc = _render_yaml_template(HEADSCALE_TEMPLATE, render_ctx, f"headscale config ({shape} shape)")
    if not isinstance(doc, dict) or "dns" not in doc:
        raise RenderError(f"rendered headscale config ({shape} shape) has no `dns:` section")
    key = _dns_record_key(doc["dns"], f"headscale config ({shape} shape)")
    wanted = {"inline": "extra_records", "file": "extra_records_path"}.get(shape)
    if wanted is not None and key != wanted:
        raise RenderError(f"the {shape} shape renders `{key}`, not `{wanted}` "
                          "— forcing the shape did not select it, so the switch is not what decides the key")
    if key == "extra_records_path":
        configured = str(doc["dns"]["extra_records_path"])
        bind = path or _records_bind_path(ctx)
        if configured != bind:
            raise RenderError(f"dns.extra_records_path is {configured!r} but the compose bind mounts the "
                              "records file at {bind!r} — headscale would open a path that is not there")
        rows = _render_yaml_template(HEADSCALE_RECORDS_TEMPLATE, ctx, "headscale records file")
        if not isinstance(rows, list):
            raise RenderError(f"the headscale records file renders {type(rows).__name__}, expected a list")
    else:
        rows = doc["dns"]["extra_records"]
        if not isinstance(rows, list):
            raise RenderError(f"dns.extra_records is {type(rows).__name__}, expected a list")

    out = []
    for rec in rows:
        # `[]` is a LEGAL render (every tailnet_*_ip unset) — it is never legal for this repo's live
        # values, so the caller's golden comparison is what turns an empty plane red.
        if not isinstance(rec, dict):
            raise RenderError(f"headscale record {rec!r} is not a mapping ({shape} shape)")
        name, value = str(rec.get("name", "")), str(rec.get("value", ""))
        if not name.endswith(f".{zone}"):
            raise RenderError(f"extra_record {name!r} is outside zone {zone!r} ({shape} shape)")
        out.append({"name": name, "value": value, "type": str(rec.get("type", "A"))})
    return out


def require_same_records(actual: list[dict], expected: list[dict], where: str) -> None:
    """Two render shapes must answer the SAME records in the SAME order.

    Order is part of the claim: the swap is only "the FILE moves" if the rows are the same rows, and a
    re-ordered answer plane is what a reviewer would have to diff by hand otherwise.
    """
    if actual == expected:
        return
    first = next((i for i, (a, b) in enumerate(zip(actual, expected)) if a != b), min(len(actual), len(expected)))
    raise RenderError(f"{where}: the record sets differ at row {first} "
                      f"({actual[first:first + 1] or ['<end>']} vs {expected[first:first + 1] or ['<end>']}; "
                      f"{len(actual)} vs {len(expected)} rows)")


def _split_namespaces(rows: list[dict], zone: str) -> dict[str, list[dict]]:
    """Split a record list into the plain and the `.ts` namespace, normalized for the fixture."""
    plain, ts_only = [], []
    for rec in rows:
        rel = rec["name"][: -len(f".{zone}")]
        (ts_only if "." in rel else plain).append(rec)   # "stats.ts" / "ha.ts" -> the tailnet namespace
    return {"plain": _dedup_sorted(plain), "ts_only": _dedup_sorted(ts_only)}


def _load_cf_vars() -> dict:
    """The role's own vars — absent is legal (a role may carry no vars file at all)."""
    if not CF_VARS_FILE.exists():
        return {}
    try:
        return yaml.safe_load(CF_VARS_FILE.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError) as exc:
        raise RenderError(f"cannot read {CF_VARS_FILE}: {exc}") from exc


def render_cloudflare(ctx: dict) -> list[dict]:
    """The public set, driven by the REAL role task and its own vars."""
    task = _find_task(CF_TASKS_FILE, CF_TASK, ("community.general.cloudflare_dns", "cloudflare_dns"))
    mod = task.get("community.general.cloudflare_dns") or task.get("cloudflare_dns") or {}
    for field in ("record", "type", "value"):
        if field not in mod:
            raise RenderError(f"cloudflare task lost its {field!r} field")
    if str(mod.get("state", "present")) != "present":
        raise RenderError("cloudflare task no longer pins state: present — the role must stay incremental-only")
    cf_ctx = dict(ctx)
    # Role vars are VARIABLES, so Ansible templates them: a post-derivation role carries a pointer
    # (`cloudflare_dns_records: "{{ zone_kogler_si_public_dns }}"`) rather than a hand-authored list,
    # and a pointer left untemplate here would be compared as text. An unresolvable pointer RAISES —
    # it may never degrade into an empty record set (`_loop_items` refuses zero rows too).
    cf_ctx.update({key: _render_value(val, ctx, _env())
                   for key, val in _load_cf_vars().items() if key not in cf_ctx})
    rows = []
    for item in _loop_items(task, cf_ctx, "cloudflare_dns"):
        row_ctx = dict(cf_ctx, item=item)
        rows.append({
            "record": _render_expr(str(mod["record"]), row_ctx),
            "type": _render_expr(str(mod["type"]), row_ctx),
            "value": _render_expr(str(mod["value"]), row_ctx),
            "ttl": _render_expr(str(mod.get("ttl", 300)), row_ctx),
            "proxied": _render_expr(str(mod.get("proxied", False)), row_ctx),
        })
    if not rows:
        raise RenderError("cloudflare_dns rendered ZERO records")
    return _dedup_sorted(rows)


def _dedup_sorted(rows: list[dict]) -> list[dict]:
    seen = {json.dumps(r, sort_keys=True) for r in rows}
    if len(seen) != len(rows):
        raise RenderError(f"duplicate record emitted: {sorted(seen ^ {json.dumps(r, sort_keys=True) for r in rows})}")
    return sorted(rows, key=lambda r: json.dumps(r, sort_keys=True))


def render_all() -> dict:
    ctx = build_context()
    inline = _headscale_rows(ctx, "inline")
    file_rows = _headscale_rows(ctx, "file")
    # The swap may move the records between the two keys; it may not move an ANSWER.
    require_same_records(file_rows, inline, "headscale inline block vs records file")
    # And whatever `headscale_extra_records_path` authors today must be coherent with itself: one
    # key, and a path the compose bind actually provides.
    shipped = _headscale_rows(ctx, "default")
    require_same_records(shipped, inline, "headscale authored default vs the shape it selects")
    return {
        "technitium": render_technitium(),
        "headscale": _split_namespaces(inline, str(ctx.get("domain_public") or "")),
        "headscale_file": _split_namespaces(file_rows, str(ctx.get("domain_public") or "")),
        "cloudflare": render_cloudflare(ctx),
    }


def is_derived() -> bool:
    """True once the zone list has replaced the hand-authored sources (HD-436 step 1)."""
    data = yaml.safe_load(ZONE_VAR_FILE.read_text(encoding="utf-8")) or {}
    return "zone_kogler_si" in data


def _flag_value(argv: list[str], flag: str):
    """The value after `flag`; None when the flag is absent, "" when it carries no value."""
    if flag not in argv:
        return None
    i = argv.index(flag)
    nxt = argv[i + 1] if i + 1 < len(argv) else ""
    return "" if nxt.startswith("--") else nxt


if __name__ == "__main__":
    if "--is-derived" in sys.argv:
        print("derived" if is_derived() else "hand-authored")
        sys.exit(0)
    # The two headscale artefacts, as the owner-present read-back needs them (docs/network-dns.md
    # §The MagicDNS records FILE). `--render-config PATH` forces the file shape at that path; without
    # a value the authored `headscale_extra_records_path` decides, exactly as on a converge.
    config_arg = _flag_value(sys.argv, "--render-config")
    if config_arg is not None or "--render-records" in sys.argv:
        try:
            ctx = build_context()
            if config_arg is not None:
                if config_arg:
                    ctx["headscale_extra_records_path"] = config_arg
                sys.stdout.write(_render_text(HEADSCALE_TEMPLATE, ctx, "local render"))
            else:
                sys.stdout.write(_render_text(HEADSCALE_RECORDS_TEMPLATE, ctx, "local render"))
        except RenderError as exc:
            print(f"RENDER FAIL: {exc}", file=sys.stderr)
            sys.exit(1)
        sys.exit(0)
    try:
        print(json.dumps(render_all(), indent=2, sort_keys=True))
    except RenderError as exc:
        print(f"RENDER FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
