#!/usr/bin/env python3
"""Render docs/network-addresses-generated.md from the IaC SSOT without Ansible.

Windows note: `ansible-playbook playbooks/render-docs.yml` cannot run on this
Windows host (ansible crashes at startup: `os.get_blocking` -> OSError [WinError 87]).
This standalone script performs the same single-template render with the real
`group_vars/all/main.yml` + host_vars SSOT, so the generated doc can be refreshed
after any master .yml change WITHOUT needing a working Ansible install.

Run after editing group_vars/all/main.yml (or the DNS host_vars):
    python scripts/render_network_addresses.py  # requires PyYAML

Idempotent: overwrites docs/network-addresses-generated.md.
"""
from datetime import datetime, timezone
from pathlib import Path

import yaml
from jinja2 import Environment, StrictUndefined

ROOT = Path(__file__).resolve().parent.parent
ANSIBLE = ROOT / "IaC" / "ansible"
TEMPLATE = ANSIBLE / "templates" / "network-addresses.md.j2"
DEST = ROOT / "docs" / "network-addresses-generated.md"


def load_yml(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def main() -> int:
    all_yml = load_yml(ANSIBLE / "group_vars" / "all" / "main.yml")

    # DNS host_vars used by the template (with template-default fallbacks)
    oldsrv_vars = load_yml(ANSIBLE / "host_vars" / "oldsrv.kogler.si.yml") or {}
    pi_vars = load_yml(ANSIBLE / "host_vars" / "pi.kogler.si.yml") or {}
    dns_primary = oldsrv_vars.get("dns_primary_ip") or "10.10.1.30"
    dns_secondary = pi_vars.get("dns_secondary_ip") or "10.10.1.20"

    ctx = {
        "ansible_managed": "Ansible managed",
        "ansible_date_time": {
            "iso8601": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        },
        "network_vlans": all_yml["network_vlans"],
        "network_static_hosts": all_yml["network_static_hosts"],
        "network_ranges": all_yml["network_ranges"],
        "ha_vip": str(all_yml["ha_vip"]),
        "technitium_secondary_ip": dns_secondary,  # Technitium secondary == Pi node IP
        "hostvars": {
            "oldsrv.kogler.si": {"dns_primary_ip": dns_primary},
            "pi.kogler.si": {"dns_secondary_ip": dns_secondary},
        },
    }

    env = Environment(undefined=StrictUndefined, trim_blocks=True, lstrip_blocks=True)

    # Replicate Ansible's `comment` filter (default 'plain' style):
    # each input line becomes "# <line>".
    def comment(text, style="plain", begin="", end="", decoration="#"):
        result = []
        lines = text.split("\n")
        if style == "plain":
            if begin:
                result.append(begin)
            for line in lines:
                result.append(f"{decoration} {line}")
            if end:
                result.append(end)
        return "\n".join(result)

    env.filters["comment"] = comment

    rendered = env.from_string(TEMPLATE.read_text(encoding="utf-8")).render(**ctx)
    DEST.write_text(rendered, encoding="utf-8", newline="\n")
    print(f"Rendered {DEST.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
