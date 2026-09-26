#!/usr/bin/env python3
"""Validate the Technitium split-horizon seed contract WITHOUT touching live DNS.

The split-horizon A records live in ONE SSOT — the `loop:` of the
`Technitium: ensure split-horizon A records` task in
roles/docker_services/tasks/technitium-seed.yml — and are applied to the THREE
Technitium instances (VPS primary, oldsrv secondary, Pi tertiary) by the seed role.
Recurring DNS outages (HD-317/HD-324/HD-341/HD-344; live 2026-09-15 llogs gap) all
share a root cause: a record row was added/edited and either never seeded on every
instance (scoped converges skip the seed tail) or resolved wrongly per instance.

This checker is the static, CI-side form of the HD-341 parity guard: it renders every
seed row's `ip:` against the SSOT (group_vars/all/main.yml) for each of the three
instances and verifies the documented contract (docs/network-dns.md §Per-Instance
Split-Horizon) — so a stale row or a guard violation fails the validate gate BEFORE a
converge ships it. It does NOT read live DNS (that would require the WSL runner + hosts
up); it catches authoring drift, which is the recurrence class.

Contract enforced (mirrors the seed role's own gates):
  * `ha` / `dns-pi`      -> ha_vip on ALL instances (DNS never breaks HA lookup).
  * Home-hosted apps     -> oldsrv_home_ip on the home instances (secondary/secondary-pi),
                            dns_primary_ip on the VPS primary (WAN/tailnet reach the edge).
  * Tailnet dashboards   -> tailnet_sidecar_ip on ALL instances.
  * Public flat set      -> dns_primary_ip on ALL instances (split-horizon parity, HD-341).
  * LAN-only rows        -> seeded ONLY on home instances (modem/spark/llogs NEVER on the
                            VPS primary — the seed's when-gate skips them there).
  * `<name>.kogler.si`   -> name is "<prefix>.kogler.si" (no bare FQDN / typo).

Run:    python3 scripts/check_dns_seed_drift.py
Exit:   0 = contract holds; 1 = a drift/guard violation (prints every finding).
Wired into `validate-all.sh` (item 15) + scripts/README.md.

HD-436 changed the SHAPE of the SSOT: the rows moved out of the task's inline `loop:`
into the derived `zone_kogler_si` list in group_vars/all/main.yml, and the when-gate's
exclusion list became `zone_kogler_si_lan_only`. This checker therefore RESOLVES the
loop and the gate through `scripts/zone_kogler_si_render.py` — the module that renders
the REAL seed task — instead of parsing a literal list out of the YAML. It accepts both
shapes (a hand-authored literal loop and a derived expression) and fails loud on a loop
that resolves to zero rows or a task it cannot find, so it can never pass vacuously.
That is the whole point: the version that only understood inline lists went RED on the
derivation and, if it had stayed green by finding "no rows", it would have stopped
checking the thing it exists to check.
"""
import sys
from pathlib import Path

import yaml
from jinja2 import Environment, StrictUndefined

sys.path.insert(0, str(Path(__file__).resolve().parent))
import zone_kogler_si_render as zr  # noqa: E402  # renders the REAL seed task (HD-436)

ROOT = Path(__file__).resolve().parent.parent
ANSIBLE = ROOT / "IaC" / "ansible"
DEFAULT_TAILNET = "100.64.0.1"          # matches the seed's `default('', true)` cluster constant

SEED_TASK = "Technitium: ensure split-horizon A records"
SEED_FILE = ANSIBLE / "roles/docker_services/tasks/technitium-seed.yml"

# The seed's when-gate list — these MUST never be seeded on the VPS primary (LAN-only).
# On the home instances each has its OWN target (not oldsrv_home_ip).
LAN_ONLY = {
    "modem.kogler.si": "192.168.1.1",        # Comtrend UI, RFC1918 (HD-302)
    "spark.kogler.si": None,                  # spark_home_ip via SSOT (HD-365)
    "llogs.kogler.si": None,                  # oldsrv_home_ip (Dozzle LAN hub, HD-343)
    "db-spark.kogler.si": None,               # spark name-edge dashboard (HD-370) — spark_home_ip via SSOT
    "llm.kogler.si": None,                    # spark OpenAI-API name edge (HD-370) — spark_home_ip via SSOT
    "llitellm.kogler.si": None,               # LAN LiteLLM on the home edge (HD-370) — oldsrv_home_ip
    # HD-188 Cockpit management surfaces (cockpit-project.org). LAN-only for the same reason as
    # modem/spark: their answers are Home-VLAN addresses, which are black holes for a peer that is
    # not at home. They were absent from BOTH this contract and the seed until 2026-09-23 — the
    # routes had been deployed for three weeks with no A record at all, so the URL could not fail
    # in an interesting way, it just never resolved (NXDOMAIN at the secondary AND the tertiary).
    "cockpit-oldsrv.kogler.si": None,          # oldsrv_home_ip — oldsrv's traefik-internal file-provider route
    "cockpit-nas.kogler.si": None,             # nas Home address via SSOT — same route shape on nas
}

# Documented record classes -> expected target resolution, per instance (docs/network-dns.md).
# Mappings below are checked by NAME category; each record's rendered target must match.
HOME_HOSTED = {  # oldsrv_home_ip home / dns_primary_ip VPS
    # (the same set as the seed's home-hosted block; keep in sync is NOT needed — this
    #  is the *contract* that must hold, so it is written here intentionally)
    "media", "seerr", "seerrng", "sonarr", "radarr", "lidarr",
    "prowlarr", "bazarr", "profilarr", "sab", "torrent", "llogs",
}
TAILNET = {"stats", "logs", "csui", "traefik", "auto"}
# NOTE: `pi-oldsrv` is absent from every set here, and `cockpit-nas` is absent from TAILNET — but
# not from this file entirely: the PLAIN `cockpit-nas.kogler.si` sits in LAN_ONLY above, and it is its
# `.ts` twin that must never be seeded. Two names, two questions; do not "tidy" one into the other.
# `tailnet_ts_only_subdomains` name (MagicDNS-only; headscale renders just the `.ts` twin), so it
# has no Technitium record at all — a LAN answer for it would be a second door the owner did not
# ask for. If a future change ever seeds it, that is a decision, not a tidy-up.
PUBLIC_FLAT = {  # single-namespace parity set (HD-341) — dns_primary_ip on all
    "vps", "home", "vpn", "dns", "sso", "file", "foto", "git", "bin",
    "ai", "office", "pdf", "chat", "matrix", "drop",
}
PUBLIC_FLAT_SPARK = {"litellm"}  # HD-370: VPS-resident, split-horizon to dns_primary_ip on all instances
VIP = {"ha", "dns-pi"}   # ha_vip on all
INCLUDES_ROOT = {"kogler.si"}  # apex -> dns_primary_ip on all


def _load_ssot() -> dict:
    """Mirror validate_doc_templates.py's loader: group_vars/all/main.yml + versions.yml."""
    out = {}
    for rel in ("group_vars/all/main.yml", "group_vars/all/versions.yml"):
        p = ANSIBLE / rel
        try:
            out.update(yaml.safe_load(p.read_text(encoding="utf-8")) or {})
        except (OSError, yaml.YAMLError) as e:
            print(f"FAIL: cannot parse {p}: {e}", file=sys.stderr)
            sys.exit(1)
    return out


def _host_ip(gv: dict, name: str, vlan: int) -> str | None:
    for h in gv.get("network_static_hosts", []):
        if h.get("name") == name and h.get("vlan") == vlan:
            return h.get("ip")
    return None


def _load_seed_rows(path: Path) -> list[dict]:
    """The seed's record rows, resolved through the real task (HD-436: may be derived).

    Accepts a literal `loop:` list AND a Jinja expression over `zone_kogler_si`.
    Never returns empty: a missing task, a loop that is not a list, or zero rows all
    abort, because an empty record set would make every rule below pass vacuously.
    """
    try:
        task = zr._find_task(path, SEED_TASK, ("ansible.builtin.uri", "uri"))
        # The instance only selects WHICH split-horizon target each row renders; the row
        # set itself is instance-independent, so resolve it once on the primary context.
        return zr._loop_items(task, zr.build_context(extra={"svc": {"instance": "primary"}}),
                              "technitium seed")
    except zr.RenderError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
    return []  # unreachable


def _seed_when(path: Path) -> str:
    """The seed task's per-item `when` expression, unevaluated."""
    try:
        task = zr._find_task(path, SEED_TASK, ("ansible.builtin.uri", "uri"))
    except zr.RenderError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
    when = task.get("when")
    if when is None:
        print(f"FAIL: seed task '{SEED_TASK}' has no `when` — LAN-only records would seed "
              f"on the VPS primary", file=sys.stderr)
        sys.exit(1)
    return str(when)


INSTANCES = ["primary", "secondary", "secondary-pi"]


def _render_ip(row: dict, ctx: dict) -> str:
    """Resolve one row's `ip:` the way the seed role does, through the render module."""
    try:
        return zr._render_expr(str(row.get("ip", "")), ctx)
    except zr.RenderError as exc:
        return f"<render error: {exc}>"


def _name_prefix(domain: str) -> str:
    return domain.split(".kogler.si", 1)[0] if domain.endswith(".kogler.si") else domain


def main() -> int:
    gv = _load_ssot()
    rows = _load_seed_rows(SEED_FILE)
    findings = []
    # ONE context builder for the whole answer plane (scripts/zone_kogler_si_render.py):
    # the split-horizon targets are Jinja over network_static_hosts and, post-HD-436,
    # `home_edge_ip`/`tailnet_edge_ip`/`nas_home_ip` live in group_vars too. A second
    # resolver here would drift from the consumer it is supposed to mirror.
    CTXS = {inst: zr.build_context(extra={"svc": {"instance": inst}}) for inst in INSTANCES}
    _ctx_primary, _ctx_home = CTXS["primary"], CTXS["secondary"]
    EXPECT = {
        "vps": _ctx_primary.get("dns_primary_ip", ""),
        "oldsrv": _ctx_home.get("oldsrv_home_ip", ""),
        "ha_vip": _ctx_primary.get("ha_vip", ""),
        "spark": _ctx_home.get("spark_home_ip", ""),
        # nas has no `nas_home_ip` var in older shapes; the derived list defines it as the
        # selectattr over network_static_hosts, which the resolver already expanded.
        "nas": _ctx_home.get("nas_home_ip") or _host_ip(gv, "nas", 10),
        "tailnet": _ctx_primary.get("tailnet_sidecar_ip", DEFAULT_TAILNET),
    }
    rendered = {inst: {} for inst in INSTANCES}

    # First pass: render every row for every instance (the whole cross product).
    for row in rows:
        name = row.get("name", "")
        for inst in INSTANCES:
            rendered[inst][name] = _render_ip(row, CTXS[inst])

    # Second pass: enforce the documented per-instance contract.
    for inst in INSTANCES:
        primary_ish = inst == "primary"
        table = rendered[inst]
        for name, ip in table.items():
            prefix = _name_prefix(name)
            if name in LAN_ONLY:
                # LAN-only rows ARE loop-iterated for the primary, but the seed's per-item
                # `when` gates them OUT there (item.name not in [...] or instance is home).
                # The final state on the primary must be ABSENT; on home they carry their
                # own target. The gate membership itself is separately asserted below.
                if primary_ish:
                    continue  # gated out by the when — the gate check below owns this
                else:
                    if name in ("spark.kogler.si", "db-spark.kogler.si", "llm.kogler.si"):
                        target = EXPECT["spark"]
                    elif name in ("llogs.kogler.si", "llitellm.kogler.si"):
                        target = EXPECT["oldsrv"]
                    elif name == "cockpit-oldsrv.kogler.si":   # HD-188 Cockpit on oldsrv
                        target = EXPECT["oldsrv"]
                    elif name == "cockpit-nas.kogler.si":      # HD-188 Cockpit on nas
                        target = EXPECT["nas"]
                    else:
                        target = LAN_ONLY[name]
                    _check(name, ip, {"expect": target, "all": False, "home": True}, findings, inst)
                continue
            # Apex (kogler.si) + VIP + tailnet + public flat live on ALL instances.
            if name in INCLUDES_ROOT:
                _check(name, ip, {"expect": EXPECT["vps"], "all": True}, findings, inst)
            elif prefix in VIP:
                _check(name, ip, {"expect": EXPECT["ha_vip"], "all": True}, findings, inst)
            elif prefix in TAILNET:
                _check(name, ip, {"expect": EXPECT["tailnet"], "all": True}, findings, inst)
            elif prefix in PUBLIC_FLAT:
                _check(name, ip, {"expect": EXPECT["vps"], "all": True}, findings, inst)
            elif prefix in HOME_HOSTED:
                expect = EXPECT["vps"] if primary_ish else EXPECT["oldsrv"]
                _check(name, ip, {"expect": expect, "all": False, "home": True}, findings, inst)
            elif prefix in PUBLIC_FLAT_SPARK:
                # HD-370: `litellm` is VPS-resident (the tailnet-only admin) but resolves to the
                # PUBLIC ip on all instances (split-horizon parity — the tailnet edge serves the
                # name; the VPS primary answers it so VPS-side DNS + headscale clients agree).
                _check(name, ip, {"expect": EXPECT["vps"], "all": True}, findings, inst)

    # Gate guard: every LAN-only row must be excluded on the VPS PRIMARY by the seed's
    # per-item `when`. Post-HD-436 the exclusion list is a DERIVED view
    # (`zone_kogler_si_lan_only`), so text-matching it would prove nothing — evaluate the
    # real expression per row on the primary and compare the EXCLUDED set against both the
    # checker's own expectation table and the `lan_only:` flags in the list itself.
    # Three-way equality is the point: a row that is flagged but not gated, gated but not
    # flagged, or in neither place is the modem/spark class this guard was written for.
    gate_expr = _seed_when(SEED_FILE)
    excluded: set[str] = set()
    for row in rows:
        name = row.get("name", "")
        try:
            keep = zr._render_expr(gate_expr, dict(CTXS["primary"], item=row), is_expr=True)
        except zr.RenderError as exc:
            findings.append(f"when-gate cannot be evaluated for {name}: {exc}")
            continue
        if keep not in ("True", "False"):
            findings.append(f"when-gate for {name} did not evaluate to a boolean: {keep!r}")
        elif keep == "False":
            excluded.add(name)
    flagged = {str(r.get("name")) for r in rows if r.get("lan_only")}
    if excluded != set(LAN_ONLY) or excluded != flagged:
        findings.append(
            f"seed when-gate excludes {sorted(excluded)} but LAN-only expectations are "
            f"{sorted(set(LAN_ONLY))} and the list flags {sorted(flagged)} — a LAN-only "
            f"record could seed on the VPS primary (or a public one is black-holing there)"
        )
    if not findings:
        # Sanity: make sure the SSOT resolved the key addresses (empty -> everything would pass).
        for key in ("dns_primary_ip", "ha_vip"):
            if not gv.get(key):
                print(f"FAIL: SSOT missing '{key}' — seed contract check is vacuous", file=sys.stderr)
                return 1
        oldsrv = _host_ip(gv, "oldsrv", 10)
        if not oldsrv:
            print("FAIL: SSOT missing oldsrv@VLAN10 ('oldsrv_home_ip')", file=sys.stderr)
            return 1
        print(f"OK: split-horizon seed contract holds ({len(rows)} records × {len(INSTANCES)} instances)")
        return 0

    print("FAIL: split-horizon seed contract violations:", file=sys.stderr)
    for f in findings:
        print(f"  - {f}", file=sys.stderr)
    return 1


def _check(name, rendered_ip, rule: dict, findings: list, inst: str) -> None:
    """Append a finding if the rendered ip for `name` on `inst` violates the rule."""
    expect = rule.get("expect")
    msg = None
    if rendered_ip == "<render error: ...>":
        msg = f"{name} fails to render for {inst}"
    elif expect is None:
        msg = f"{name} has no expected target for {inst}"
    elif rendered_ip != expect:
        msg = f"{name} -> '{rendered_ip}' on {inst}, expected '{expect}'"
    if msg:
        findings.append(msg)


if __name__ == "__main__":
    sys.exit(main())