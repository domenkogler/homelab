#!/usr/bin/env python3
"""Render docs/network-rack-generated.md + docs/rack-layout.mmd from the rack SSOT JSON.

SSOT (hand-maintained, parsed from docs/assets/Rack.canvas):
    docs/rack-connections.json
Generated outputs (do NOT hand-edit):
    docs/network-rack-generated.md   - per-device & per-patch-panel port connectivity
    docs/rack-layout.mmd       - Mermaid wiring diagram

Usage:
    python scripts/render_rack_connections.py
Idempotent: overwrites both outputs.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SSOT = ROOT / "docs" / "rack-connections.json"
MD_DEST = ROOT / "docs" / "network-rack-generated.md"
MMD_DEST = ROOT / "docs" / "rack-layout.mmd"

import json


def load() -> dict:
    return json.loads(SSOT.read_text(encoding="utf-8"))


def main() -> int:
    d = load()
    devices = {x["id"]: x for x in d["devices"]}
    panels = d["patch_panels"]

    def dev_name(did):
        return devices[did]["name"]

    def iface_mac(did, iface):
        return devices[did].get("iface_macs", {}).get(iface)

    # Index links by device id -> list of (own_iface, description, is_from)
    from_idx: dict[str, list] = {}
    to_idx: dict[str, list] = {}
    for c in d["connections"]:
        from_idx.setdefault(c["from_device"], []).append(c)
        if c.get("to_type") == "device":
            to_idx.setdefault(c["to_device"], []).append(c)

    def resolve(c, from_side=True):
        """Human description of the *other* end of a connection."""
        mask = lambda s: f"`{s}`" if s else "_— (no MAC)_"
        if from_side:
            if c["to_type"] == "patch":
                p = panels[c["to_panel"]]
                port = p["ports"][str(c["to_patch_port"])]
                tail = f" → {port['ends_at'] or 'room'}" if port.get("ends_at") else ""
                return (f"**Panel {c['to_panel']} / port {c['to_patch_port']}**{tail}"
                        f" · {port['device'] or 'no device'} {mask(port['mac'])}")
            else:
                other = c["to_iface"]
                return (f"**{dev_name(c['to_device'])}** {other} {mask(iface_mac(c['to_device'], other))}")
        else:  # device is the target; describe the source
            other = c["from_iface"]
            return f"**{dev_name(c['from_device'])}** {other} {mask(iface_mac(c['from_device'], other))}"

    def device_rows(did):
        rows = []
        for c in from_idx.get(did, []):
            rows.append((c["from_iface"], resolve(c, True), c.get("note") or c.get("role") or ""))
        for c in to_idx.get(did, []):
            rows.append((c["to_iface"], resolve(c, False), c.get("note") or c.get("role") or ""))
        return sorted(rows, key=lambda r: _iface_sort(r[0]))

    md = []
    # Canonical managed header (CONVENTIONS §8.2 / HD-163): exactly Ansible's
    # built-in ansible_managed default, first line of every generated doc.
    md.append("# Ansible managed")
    md.append("# Rack Connections")
    md.append("")
    md.append("> **Generated** from [`rack-connections.json`](rack-connections.json) by "
              "`scripts/render_rack_connections.py` — do not hand-edit.")
    md.append("> Source of truth: [`assets/Rack.canvas`](assets/Rack.canvas) (Obsidian Canvas).")
    md.append("")
    md.append("Each row = one physical link. Patch-panel targets show the wall-side "
              "room/device + MAC (see the panel tables).")
    md.append("")

    # ---- Device connectivity tables ----
    order = ["rb4011", "crs328", "comtrend", "nas", "pi", "hmip", "tplink-sg108e"]
    md.append("## Device connectivity")
    md.append("")
    for did in order:
        if did not in devices:
            continue
        dev = devices[did]
        rows = device_rows(did)
        md.append(f"### {dev['name']} (`{did}`)")
        if dev.get("role"):
            md.append(f"> Role: {dev['role']}")
        if dev.get("note"):
            md.append(f"> Note: {dev['note']}")
        md.append("")
        if not rows:
            md.append("_No modelled connections (appears in canvas but wiring unknown)._")
        else:
            md.append("| Interface | Connected to | Note |")
            md.append("|-----------|--------------|------|")
            for iface, dest, note in rows:
                md.append(f"| `{iface}` | {dest} | {note} |")
        md.append("")

    # ---- Patch panel tables ----
    md.append("## Patch panel wiring")
    md.append("")
    for pid in ["A", "B"]:
        p = panels[pid]
        md.append(f"### Patch Panel {pid} — {p['name']} (`{p['rack_unit']}`)")
        md.append("")
        md.append("| Port | Patched from | Room / end | Device | MAC |")
        md.append("|------|--------------|------------|--------|-----|")
        # which connection targets each panel port
        patch_src = {}
        for c in d["connections"]:
            if c["to_type"] == "patch" and c["to_panel"] == pid:
                patch_src[c["to_patch_port"]] = f"{dev_name(c['from_device'])} `{c['from_iface']}`"
        for port_no in range(1, 25):
            port = p["ports"][str(port_no)]
            src = patch_src.get(port_no, "—")
            used = "✔" if port.get("used") else "✗"
            room = port.get("room") or "—"
            ends = port.get("ends_at") or ""
            dev = port.get("device") or "—"
            mac = port.get("mac") or "—"
            md.append(f"| {used} {port_no} | {src} | {room} {ends} | {dev} | `{mac}` |")
        md.append("")

    md.append("## Notes")
    md.append("")
    for n in d.get("notes", []):
        md.append(f"- {n}")
    md.append("")

    MD_DEST.write_text("\n".join(md), encoding="utf-8", newline="\n")

    # ---- Mermaid ----
    mmd = []
    mmd.append("flowchart LR")
    for did in order:
        if did not in devices:
            continue
        nm = devices[did]["name"].replace('"', "'")
        shape = "(((" if did in ("rb4011", "crs328", "comtrend") else "("
        mmd.append(f'  {did}[{nm}]')
    mmd.append('  subgraph PANELA["Patch Panel A (U18)"]')
    mmd.append("  end")
    mmd.append('  subgraph PANELB["Patch Panel B (U17)"]')
    mmd.append("  end")
    for c in d["connections"]:
        fr = c["from_device"]
        if c["to_type"] == "patch":
            to = f"PANEL{c['to_panel']}"
            lbl = f"{c['from_iface']} → {c['to_panel']}{c['to_patch_port']}"
            mmd.append(f'  {fr} -- "{lbl}" --> {to}')
        else:
            to = c["to_device"]
            lbl = f"{c['from_iface']} ↔ {c['to_iface']}"
            mmd.append(f'  {fr} -- "{lbl}" --> {to}')
    MMD_DEST.write_text("\n".join(mmd) + "\n", encoding="utf-8", newline="\n")

    print(f"wrote {MD_DEST}")
    print(f"wrote {MMD_DEST}")
    return 0


def _iface_sort(s: str):
    """Sort interface labels sensibly: ether1..ether10, eth1.., sfp+1, eno1.."""
    import re
    m = re.match(r"([A-Za-z+]*?)(\d+)$", s)
    if not m:
        return (1, s, 0)
    return (0, m.group(1), int(m.group(2)))


if __name__ == "__main__":
    raise SystemExit(main())
