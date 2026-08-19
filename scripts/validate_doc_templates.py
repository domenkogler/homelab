#!/usr/bin/env python3
"""Validate network-addresses.md.j2 + inventory.md.j2 render with real group_vars context."""
import re
from pathlib import Path
from jinja2 import Environment, StrictUndefined, Template

root = Path("IaC/ansible")

# --- parse group_vars/all.yml (safe subset) ---
def grab_yml_var(text, var):
    m = re.search(rf"^{var}:\s*(.*)$", text, re.M)
    return m.group(1).strip() if m else None

all_yml = (root / "group_vars/all.yml").read_text(encoding="utf-8")
ha_vip = grab_yml_var(all_yml, "ha_vip").split("#")[0].strip()
print(f"ha_vip = {ha_vip}")

# network_static_hosts / network_vlans are list-of-dicts; replicate from group_vars/all.yml
network_vlans = [
    {"id": 10, "name": "Home", "subnet": "10.10.1.0/24", "pool": "10.10.1.100-10.10.1.199", "ssid": "Kogler"},
    {"id": 20, "name": "IoT", "subnet": "10.10.20.0/24", "pool": "10.10.20.100-10.10.20.199", "ssid": "Kogler IOT"},
    {"id": 21, "name": "IoT-Internet", "subnet": "10.10.21.0/24", "pool": "10.10.21.100-10.10.21.199", "ssid": "Kogler IOT WAN"},
    {"id": 30, "name": "Guest", "subnet": "10.10.30.0/24", "pool": "10.10.30.100-10.10.30.199", "ssid": "Kogler guest"},
    {"id": 40, "name": "Kids", "subnet": "10.10.40.0/24", "pool": "10.10.40.100-10.10.40.199", "ssid": "Kogler Kids"},
    {"id": 50, "name": "Media", "subnet": "10.10.50.0/24", "pool": "10.10.50.100-10.10.50.199", "ssid": ""},
    {"id": 99, "name": "Management", "subnet": "10.10.99.0/24", "pool": "10.10.99.50-10.10.99.99", "ssid": ""},
]
network_static_hosts = [
    {"vlan": 99, "ip": "10.10.99.1", "name": "router", "role": "RB4011 gateway"},
    {"vlan": 10, "ip": "10.10.1.30", "name": "oldsrv", "role": "node + DNS primary"},
]

ctx = {
    "ansible_managed": "Ansible managed: file edited by Ansible",
    "ansible_date_time": {"iso8601": "2026-01-01T00:00:00Z"},
    "network_vlans": network_vlans,
    "network_static_hosts": network_static_hosts,
    # subset of group_vars/all.yml network_ranges — enough to smoke-test the template
    "network_ranges": [
        {"name": "wireguard", "cidr": "10.255.0.0/16", "purpose": "tunnel family"},
        {"name": "wg-s2s", "cidr": "10.255.40.0/30", "purpose": "S2S link"},
        {"name": "headscale", "cidr": "100.64.0.0/10", "purpose": "overlay"},
        {"name": "traefik-public", "cidr": "172.20.0.0/16", "purpose": "docker edge"},
        {"name": "site", "cidr": "10.10.0.0/16", "purpose": "site"},
    ],
    "ha_vip": ha_vip,
    "technitium_secondary_ip": "10.10.1.20",
    "hostvars": {
        "oldsrv.kogler.si": {"dns_primary_ip": "10.10.1.30"},
        "ha.kogler.si": {"dns_secondary_ip": "10.10.1.20"},
        "pi.kogler.si": {"dns_secondary_ip": "10.10.1.20"},
    },
    "docker_services": [
        {"name": "traefik", "subdomain": None, "enabled": True},
        {"name": "grafana", "subdomain": "stats", "enabled": True},
    ],
    # Multi-host inventory render: list of {key: host, value: {('_docker_services'): [...]}}
    # (the shape render-docs.yml builds via dict2items + selectattr).
    "all_hostvars": [
        {"key": "vps.kogler.si", "value": {"_docker_services": [{"name": "traefik", "subdomain": None, "enabled": True}]}},
        {"key": "oldsrv.kogler.si", "value": {"_docker_services": [{"name": "jellyfin", "subdomain": "media", "enabled": True}]}},
    ],
    "domain_public": "kogler.si",
    "inventory_hostname": "oldsrv.kogler.si",
}

env = Environment(undefined=StrictUndefined, keep_trailing_newline=True, trim_blocks=True, lstrip_blocks=True)

# Emulate Ansible's `comment` filter (simple '#' style) for local validation.
def ansible_comment(text, style="plain"):
    return "\n".join(f"# {l}" if l else "#" for l in str(text).splitlines())

env.filters["comment"] = ansible_comment

for tpl in ["network-addresses.md.j2", "inventory.md.j2"]:
    src = (root / "templates" / tpl).read_text(encoding="utf-8")
    out = env.from_string(src).render(**ctx)
    print(f"===== {tpl} rendered OK ({len(out)} bytes) =====")
    print(out[:400])
