#!/usr/bin/env python3
"""Smoke-render the SSOT doc templates with REAL group_vars context.

Renders templates/network-addresses.md.j2 + templates/inventory.md.j2 the way
render-docs.yml does, using values parsed from group_vars/all.yml (+ host_vars)
so this check fails when the SSOT and its doc templates drift apart (HD-197 F2:
the hardcoded copies this script once carried could never catch that).

What is checked:
  * both templates render under StrictUndefined with real group_vars data
  * no missing-variable / Jinja errors

Mocked (host/instance-specific, no plain group_vars equivalent): per-host
dns_*_ip entries are derived here from network_static_hosts exactly like the
playbook does; ansible_date_time is a fixed instant.

Run:   python scripts/validate_doc_templates.py
Exit:  0 = both templates render; 1 = any render/parsing failure.
Wired into `validate-all.sh`.
"""
import sys
from pathlib import Path

import yaml
from jinja2 import Environment, StrictUndefined

ROOT = Path(__file__).resolve().parent.parent
ANSIBLE = ROOT / "IaC" / "ansible"


def _load_group_vars() -> dict:
    out = {}
    for rel in ("group_vars/all/main.yml", "group_vars/all/versions.yml"):
        p = ANSIBLE / rel
        try:
            data = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
        except (OSError, yaml.YAMLError) as e:
            print(f"FAIL: cannot parse {p}: {e}", file=sys.stderr)
            sys.exit(1)
        out.update(data)
    return out


def _derive_host_ips(gv: dict) -> dict:
    """Derive per-host DNS IPs from network_static_hosts (same derivation the
    playbook uses) — no phantom hosts, no hardcoded IPs."""
    hosts = gv.get("network_static_hosts", [])

    def ip(name, vlan):
        match = [h for h in hosts if h.get("name") == name and h.get("vlan") == vlan]
        return match[0]["ip"] if match else None

    oldsrv = ip("oldsrv", 10)
    pi = ip("pi", 10)
    hostvars = {}
    if oldsrv:
        hostvars["oldsrv.kogler.si"] = {"dns_primary_ip": oldsrv}
    if pi:
        hostvars["pi.kogler.si"] = {"dns_secondary_ip": pi}
    return hostvars


def main() -> int:
    gv = _load_group_vars()
    for key in ("network_vlans", "network_static_hosts", "network_ranges",
                "ha_vip", "domain_public"):
        if key not in gv:
            print(f"FAIL: group_vars/all.yml is missing '{key}' — SSOT incomplete",
                  file=sys.stderr)
            return 1

    docker_services = []
    for gvf in sorted((ANSIBLE / "group_vars").glob("*.yml")):
        try:
            data = yaml.safe_load(gvf.read_text(encoding="utf-8")) or {}
        except (OSError, yaml.YAMLError) as e:
            print(f"FAIL: cannot parse {gvf}: {e}", file=sys.stderr)
            return 1
        docker_services.extend(data.get("docker_services", []))

    ctx = {
        # Canonical managed header (CONVENTIONS §8.2 / HD-163): exactly Ansible's
        # built-in ansible_managed default.
        "ansible_managed": "Ansible managed",
        "ansible_date_time": {"iso8601": "2026-01-01T00:00:00Z"},
        "network_vlans": gv["network_vlans"],
        "network_static_hosts": gv["network_static_hosts"],
        "network_ranges": gv["network_ranges"],
        "ha_vip": gv["ha_vip"],
        # DNS tier (HD-299, VPS-primary): the resolver trio lives in group_vars/all.yml
        # (single SSOT) and the generated doc template references them.
        "dns_primary_ip": gv["dns_primary_ip"],
        "dns_secondary_ip": gv["dns_secondary_ip"],
        "dns_tertiary_ip": gv["dns_tertiary_ip"],
        "technitium_secondary_ip": "{{ pi_home_ip }}",   # rendered literally in all.yml
        "hostvars": _derive_host_ips(gv),
        "docker_services": docker_services,
        "all_hostvars": [
            {"key": h, "value": {"_docker_services": docker_services}}
            for h in ("vps.kogler.si", "oldsrv.kogler.si")
        ],
        "domain_public": gv["domain_public"],
        "inventory_hostname": "oldsrv.kogler.si",
    }

    env = Environment(undefined=StrictUndefined, keep_trailing_newline=True,
                      trim_blocks=True, lstrip_blocks=True)

    def ansible_comment(text, style="plain"):
        return "\n".join(f"# {l}" if l else "#" for l in str(text).splitlines())

    env.filters["comment"] = ansible_comment

    failed = False
    for tpl in ("network-addresses.md.j2", "inventory.md.j2"):
        src = (ANSIBLE / "templates" / tpl).read_text(encoding="utf-8")
        try:
            out = env.from_string(src).render(**ctx)
        except Exception as e:
            print(f"FAIL: {tpl} does not render with real group_vars context: {e}",
                  file=sys.stderr)
            failed = True
            continue
        print(f"===== {tpl} rendered OK ({len(out)} bytes) =====")

    if failed:
        print("\nSee docs/deployment-ansible.md (render pipeline) — a template that "
              "references a variable absent from group_vars is an SSOT drift defect.",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
