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
"""
import sys
from pathlib import Path

import yaml
from jinja2 import Environment, StrictUndefined

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
# NOTE: `pi-oldsrv` is deliberately ABSENT from every set here. It is a
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


def _build_context(gv: dict, instance: str) -> dict:
    """Mirror the exact Jinja context the seed role resolves for this instance.

    The SSOT keys (dns_primary_ip, oldsrv_home_ip, ha_vip, spark_home_ip, ...) are
    THEMSELVES Jinja expressions in group_vars/all/main.yml that reference
    network_static_hosts. Resolve them once with network_static_hosts in scope, exactly
    like Ansible does at converge time, so the expected targets are real IPs.
    """
    hosts = gv.get("network_static_hosts", [])
    env = Environment(undefined=StrictUndefined)
    base = {"network_static_hosts": hosts}

    def resolve(key: str, fallback: str = "") -> str:
        raw = gv.get(key, fallback)
        if isinstance(raw, str) and "{{" in raw:
            try:
                return env.from_string(raw).render(**base).strip()
            except Exception:  # noqa: BLE001 — surfaces in the finding if it fails
                return raw
        return raw or ""

    return {
        # Rows in the seed may legitimately derive an address from the SSOT inline (the
        # `network_static_hosts | selectattr(...)` idiom that `nut_exporter_host` and the
        # cockpit route backends use), so the render context must carry the SSOT itself —
        # Ansible has it in scope at converge time. Without it such a row renders as a
        # StrictUndefined error and the checker reports an invented target.
        "network_static_hosts": hosts,
        "dns_primary_ip": resolve("dns_primary_ip"),
        "oldsrv_home_ip": resolve("oldsrv_home_ip"),
        "ha_vip": resolve("ha_vip"),
        "spark_home_ip": resolve("spark_home_ip"),
        "tailnet_sidecar_ip": gv.get("tailnet_sidecar_ip", DEFAULT_TAILNET),
        "svc": {"instance": instance},
    }


def _load_seed_rows(path: Path) -> list[dict] | None:
    """Return the record loop rows from the seed task, or None (task not found)."""
    try:
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as e:
        print(f"FAIL: cannot parse {path}: {e}", file=sys.stderr)
        sys.exit(1)

    def walk(tasks):
        for task in tasks or []:
            if not isinstance(task, dict):
                continue
            if task.get("name") == SEED_TASK and isinstance(task.get("loop"), list):
                return task["loop"]
            # Recurse into block/always/rescue/when nesting (the seed file is a `block:`).
            for sub_key in ("block", "always", "rescue", "tasks"):
                if isinstance(task.get(sub_key), list):
                    sub = walk(task[sub_key])
                    if sub is not None:
                        return sub
        return None

    found = walk(doc)
    if found is None:
        # Fail loud: the SSOT task must exist — otherwise the checker would pass vacuously.
        print(f"FAIL: seed task '{SEED_TASK}' not found in {path}", file=sys.stderr)
        sys.exit(1)
    return found


INSTANCES = ["primary", "secondary", "secondary-pi"]


def _render_ip(row: dict, ctx: dict) -> str | None:
    env = Environment(undefined=StrictUndefined)
    try:
        return env.from_string(row.get("ip", "")).render(**ctx).strip()
    except Exception as e:  # noqa: BLE001 — any render failure is a drift finding
        return f"<render error: {e}>"


def _name_prefix(domain: str) -> str:
    return domain.split(".kogler.si", 1)[0] if domain.endswith(".kogler.si") else domain


def main() -> int:
    gv = _load_ssot()
    rows = _load_seed_rows(SEED_FILE)
    findings = []
    # Resolve SSOT-derived addrs ONCE (they are Jinja in all/main.yml referencing
    # network_static_hosts); use them both as render context and as expectations.
    _ctx_primary = _build_context(gv, "primary")
    _ctx_home = _build_context(gv, "secondary")
    EXPECT = {
        "vps": _ctx_primary["dns_primary_ip"],
        "oldsrv": _ctx_home["oldsrv_home_ip"],
        "ha_vip": _ctx_primary["ha_vip"],
        "spark": _ctx_home["spark_home_ip"],
        # nas has no `nas_home_ip` var (the seed renders it from the address SSOT inline), so the
        # expectation resolves through the same helper the seed's expression models.
        "nas": _host_ip(gv, "nas", 10),
        "tailnet": gv.get("tailnet_sidecar_ip", DEFAULT_TAILNET),
    }
    rendered = {inst: {} for inst in INSTANCES}

    # First pass: render every row for every instance (the whole cross product).
    for row in rows:
        name = row.get("name", "")
        for inst in INSTANCES:
            rendered[inst][name] = _render_ip(row, _build_context(gv, inst))

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

    # Gate guard: every LAN-only row must be covered by the seed's per-item `when` so it
    # NEVER resolves on the VPS primary (forgetting a row in the exclusion list = the seed
    # would happily add it on the VPS — the exact modem/spark class). Scrape the when-
    # expression and compare against LAN_ONLY.
    gate = _load_seed_when(SEED_FILE)
    if gate != set(LAN_ONLY):
        findings.append(
            f"seed when-gate {sorted(gate)} != LAN-only set {sorted(LAN_ONLY)} — "
            f"a LAN-only record is missing from the exclusion list and could seed on the VPS primary"
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


def _load_seed_when(path: Path) -> set[str]:
    """Extract the LAN-only names from the seed task's per-item `when` exclusion list.

    The record task's `when: item.name not in [...] or svc.instance ...` is the ONLY thing
    keeping LAN-only records off the VPS primary. Parse the `not in [...]` list and return
    it as a set. This is the gate that must stay equal to LAN_ONLY.
    """
    import re

    doc = yaml.safe_load(path.read_text(encoding="utf-8"))

    def walk(tasks):
        for task in tasks or []:
            if not isinstance(task, dict):
                continue
            if task.get("name") == SEED_TASK:
                when = task.get("when", "")
                # pattern: item.name not in ["a", "b", ...]
                m = re.search(r"item\.name not in \[([^\]]*)\]", str(when))
                if m:
                    return {s.strip().strip('\"').strip("'") for s in m.group(1).split(",")}
            for sub_key in ("block", "always", "rescue", "tasks"):
                if isinstance(task.get(sub_key), list):
                    sub = walk(task[sub_key])
                    if sub is not None:
                        return sub
        return None

    found = walk(doc)
    if found is None:
        print(f"FAIL: seed when-gate not parsed in {path}", file=sys.stderr)
        sys.exit(1)
    return found


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