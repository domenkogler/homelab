#!/usr/bin/env python3
"""Render every ``kogler.si`` answer-plane consumer into one normalized shape (HD-436).

The zone's membership is consumed by THREE renderers:

  * the Technitium seed task (``roles/docker_services/tasks/technitium-seed.yml``)
    — per instance: VPS ``primary``, oldsrv ``secondary``, Pi ``secondary-pi``;
  * headscale ``dns.extra_records`` (``templates/docker_services/headscale/config.yaml.j2``)
    — the plain ``*.kogler.si`` list and the ``*.ts.kogler.si``-only list;
  * the public Cloudflare set (``roles/cloudflare_dns/tasks/main.yml`` + its vars).

This module renders those THREE REAL SOURCES (the actual template file, the actual
seed task, the actual role task — not a paraphrase of them) into a normalized dict, so
``capture_zone_kogler_si_golden.py`` (pre-change) and ``check_zone_kogler_si_parity.py``
(post-change) compare the same shape. Rendering the real artifacts is the whole point:
a mirror implementation would validate itself and prove nothing.

Nothing here contacts a host, reads the vault, or runs Ansible. Secrets are replaced by
an in-memory dummy (`DUMMY-VAULT-NOT-A-SECRET`); no vault value is ever read or printed.

Run directly for a human-readable dump:  python3 scripts/zone_kogler_si_render.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import yaml
from jinja2 import ChainableUndefined, Environment, StrictUndefined

ROOT = Path(__file__).resolve().parent.parent
ANSIBLE = ROOT / "IaC" / "ansible"

SEED_TASK = "Technitium: ensure split-horizon A records"
CF_TASK = "Ensure public DNS records are present (idempotent)"
SEED_FILE = ANSIBLE / "roles/docker_services/tasks/technitium-seed.yml"
HEADSCALE_TEMPLATE = ANSIBLE / "templates/docker_services/headscale/config.yaml.j2"
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
            base[key] = value
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


def render_headscale(ctx: dict) -> dict[str, list[dict]]:
    """headscale `dns.extra_records` from the REAL template, split by namespace."""
    base_domain = str(ctx.get("tailnet_base_domain") or "")
    zone = str(ctx.get("domain_public") or "")
    if not base_domain or "{{" in base_domain:
        raise RenderError(f"tailnet_base_domain unresolved: {base_domain!r}")
    env = _env(strict=False)
    try:
        rendered = env.from_string(HEADSCALE_TEMPLATE.read_text(encoding="utf-8")).render(**ctx)
    except Exception as exc:  # noqa: BLE001
        raise RenderError(f"cannot render {HEADSCALE_TEMPLATE.name}: {exc}") from exc
    try:
        doc = yaml.safe_load(rendered)
    except yaml.YAMLError as exc:
        raise RenderError(f"rendered headscale config is not valid YAML: {exc}") from exc
    if not isinstance(doc, dict) or "dns" not in doc:
        raise RenderError("rendered headscale config has no `dns:` section")
    records = (doc.get("dns") or {}).get("extra_records")
    if records is None:
        raise RenderError("rendered headscale config has no `dns.extra_records` key at all")
    if not isinstance(records, list):
        raise RenderError(f"dns.extra_records is {type(records).__name__}, expected a list")
    if not records:
        # `[]` is a LEGAL render (every tailnet_*_ip unset) — but it is never legal for
        # this repo's live values, so the caller's golden comparison is what turns it red.
        return {"plain": [], "ts_only": []}

    plain, ts_only = [], []
    for rec in records:
        name, value = str(rec.get("name", "")), str(rec.get("value", ""))
        if not name.endswith(f".{zone}"):
            raise RenderError(f"extra_record {name!r} is outside zone {zone!r}")
        rel = name[: -len(f".{zone}")]
        if "." in rel:            # e.g. "stats.ts" / "ha.ts" -> the tailnet namespace
            ts_only.append({"name": name, "value": value, "type": str(rec.get("type", "A"))})
        else:
            plain.append({"name": name, "value": value, "type": str(rec.get("type", "A"))})
    return {"plain": _dedup_sorted(plain), "ts_only": _dedup_sorted(ts_only)}


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
    cf_vars = yaml.safe_load(CF_VARS_FILE.read_text(encoding="utf-8")) or {}
    for key, val in cf_vars.items():
        cf_ctx.setdefault(key, val)
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
    return {
        "technitium": render_technitium(),
        "headscale": render_headscale(ctx),
        "cloudflare": render_cloudflare(ctx),
    }


def is_derived() -> bool:
    """True once the zone list has replaced the hand-authored sources (HD-436 step 1)."""
    data = yaml.safe_load(ZONE_VAR_FILE.read_text(encoding="utf-8")) or {}
    return "zone_kogler_si" in data


if __name__ == "__main__":
    if "--is-derived" in sys.argv:
        print("derived" if is_derived() else "hand-authored")
        sys.exit(0)
    try:
        print(json.dumps(render_all(), indent=2, sort_keys=True))
    except RenderError as exc:
        print(f"RENDER FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
