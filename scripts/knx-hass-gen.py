#!/usr/bin/env python3
"""
knx-hass-gen.py — generate Home Assistant KNX integration YAML from an ETS .knxproj.

The repo's KNX SSOT is the ETS export
  docs/assets/references/knx/StanovanjeKogler_v1_0.knxproj
(smart-home.md decision 2026-08-21: project file, NOT hand-maintained YAML GA maps;
the old `docs/assets/references/old-ha/knx-*.yaml` are the LEGACY live config only).

xknxproject parses the project and the `functions` carry the per-device roles
(SwitchOnOff / InfoOnOff / DimmingControl / MoveUpDown / StopStepUpDown /
CurrentAbsolutePositionBlindsPercentage …). This script emits the `knx:` YAML
blocks for the platforms with entities mapped from those roles.

Usage:
  python3 scripts/knx-hass-gen.py --knxproj docs/assets/references/knx/StanovanjeKogler_v1_0.knxproj \
      > IaC/ansible/roles/home_assistant/templates/knx-entities.yaml
  (the output is a static include consumed by configuration.yaml.j2's `knx:` key)

Output contract:
  - light / cover / switch / binary_sensor / sensor lists with `name`,`address`,
    `state_address`, brightness/position/angle addresses where present.
  - Names are the ETS function names (e.g. "Hodnik Luc ON/OFF 1/1"), which are the
    SSOT names; the dashboard then references entities by the HA entity IDs derived
    by HA from these names (light.hodnik_luc_on_off_1_1 etc.).
  - idempotent + deterministic; no secrets.

Dependency: xknxproject (pip install xknxproject).
"""
import argparse
import re
import sys

# FT-0 "custom" functions whose role-uuid addresses are opaque — classify by name.
CUSTOM_SWITCH_NAMES = re.compile(
    r'^(Radiator|Pecica1|Pecica2|Pomivalni stroj|Pralni stroj|Susilni stroj)$'
)
CUSTOM_BINARY_NAMES = re.compile(r'^V\d+ - vrata$')
CUSTOM_SENSOR_NAMES = re.compile(r'(Rekuperator|temperature|Temperature|airflow|Airflow)', re.I)


def slugify(name: str) -> str:
    """Turn an ETS name into an HA-style entity slug (lowercase, _ separators)."""
    s = name.lower()
    s = re.sub(r'[^a-z0-9]+', '_', s)
    s = re.sub(r'_+', '_', s).strip('_')
    return s


def role_addr(fn, role):
    for addr, ga in fn['group_addresses'].items():
        if ga['role'] == role:
            return addr
    return None


def addr_list_first(fn, roles):
    for r in roles:
        a = role_addr(fn, r)
        if a:
            return a
    return None


def emit_light(fn, name):
    """FT-1 (switchable) / FT-6 (dimmable) -> HA light map."""
    sw = role_addr(fn, 'SwitchOnOff')
    st = role_addr(fn, 'InfoOnOff')
    dim = role_addr(fn, 'DimmingControl')
    info_dim = role_addr(fn, 'InfoDimmingValue')
    out = {"name": name, "address": sw, "state_address": st}
    if dim:
        out["brightness_address"] = dim
        out["brightness_state_address"] = info_dim or dim
    return out


def emit_cover(fn, name):
    """FT-7 sun protection -> HA cover map."""
    move_long = role_addr(fn, 'MoveUpDown')
    step = role_addr(fn, 'StopStepUpDown')
    pos = role_addr(fn, 'CurrentAbsolutePositionBlindsPercentage')
    ang = role_addr(fn, 'CurrentAbsolutePositionSlatPercentage')
    out = {
        "name": name,
        "move_long_address": move_long,
        "move_short_address": step or move_long,
        "stop_address": step or move_long,
        "position_address": pos,
        "position_state_address": pos,
        "angle_address": ang,
        "angle_state_address": ang,
        "travelling_time_down": 30,
        "travelling_time_up": 30,
    }
    return out


def emit_switch(fn, name):
    """FT-0 custom ON/OFF (radiator/appliance) -> HA switch (1.001 addr + status)."""
    addrs = list(fn['group_addresses'].keys())
    # first group-address (uids ordered); typically ON/OFF, then status, then current
    out = {"name": name, "address": addrs[0]}
    if len(addrs) > 1:
        out["state_address"] = addrs[1]
    return out


def emit_binary_sensor(fn, name):
    """FT-0 door-contact -> HA binary_sensor (1.001 contact).

    `invert: true` — the ETS door contact telegrams are inverted on the bus
    (1 = closed / 0 = open; live-verified 2026-09-03 on the vrata contacts,
    all showed `off` while the doors were open). This keeps HA's
    `device_class: door` rendering (on=Open, off=Closed) aligned with reality.
    """
    addrs = list(fn['group_addresses'].keys())
    return {
        "name": name,
        "state_address": addrs[0],
        "device_class": "door",
        "invert": True,
    }


def build(proj):
    lights, covers, switches, binary_sensors, sensors = [], [], [], [], []
    # space_id -> room name (first Room space in the ETS locations tree)
    space_room = {}
    for loc in (proj.get('locations') or {}).values():
        for sp_id, sp in (loc.get('spaces', {}) if isinstance(loc, dict) else {}).items():
            if isinstance(sp, dict) and sp.get('type') in ('Room', None):
                space_room[sp.get('identifier', sp_id)] = sp.get('name') or sp_id
    for fid, fn in proj['functions'].items():
        ftype = fn['function_type']
        name = fn['name'].strip()
        if not name:
            continue
        room = space_room.get(fn.get('space_id'), '')
        # ETS names like "Luc ON/OFF 1/1" are per-room already-uncomfortable; prefix the
        # ROOM so radiator/appliance categories don't collide (Kopalnica vs WC) and the
        # dashboard/entity names read naturally ("Hodnik Luc DIMM 1/2").
        display = f"{room} {name}" if room and room not in name else name
        if ftype in ('FT-1', 'FT-6'):            # light
            lights.append(emit_light(fn, display))
        elif ftype == 'FT-7':                      # cover / sun protection
            covers.append(emit_cover(fn, display))
        elif ftype == 'FT-0':                      # custom: classify by name
            if CUSTOM_SWITCH_NAMES.match(name):
                switches.append(emit_switch(fn, display))
            elif CUSTOM_BINARY_NAMES.match(name):
                binary_sensors.append(emit_binary_sensor(fn, display))
            elif CUSTOM_SENSOR_NAMES.search(name):
                sensors.append({"name": display, "state_address": list(fn['group_addresses'].keys())[0], "type": "percent"})
            # else: skip unclassified custom functions
        # sensors from DPT 9.001 temperature GAs anywhere
        for addr, ga in fn['group_addresses'].items():
            dpt = proj['group_addresses'].get(addr, {}).get('dpt') or {}
            if dpt.get('main') == 9:
                sensors.append({"name": f"{display} {ga['role']}", "state_address": addr, "type": "temperature"})
    # dedupe sensors by state_address
    seen = set(); dedup = []
    for s in sensors:
        if s['state_address'] not in seen:
            seen.add(s['state_address']); dedup.append(s)
    return lights, covers, switches, binary_sensors, dedup


def render_yaml(lights, covers, switches, binary_sensors, sensors):
    lines = []
    lines.append("# Generated by scripts/knx-hass-gen.py from the ETS project file")
    lines.append("# (docs/assets/references/knx/StanovanjeKogler_v1_0.knxproj) — DO NOT HAND-EDIT.")
    lines.append("# Regenerate with: python3 scripts/knx-hass-gen.py --knxproj docs/.../StanovanjeKogler_v1_0.knxproj")
    # NOTE: NO `knx:` wrapper — configuration.yaml.j2 includes this file via
    # `knx: !include knx-entities.yaml`, so the file must contain only the knx block's
    # CONTENTS (light/cover/switch/...) or HA sees `knx: knx:` (invalid option — live
    # 2026-09-03: "'knx' is an invalid option for 'knx'").
    if lights:
        lines.append("  light:")
        for lg in lights:
            lines.append(f"    - name: \"{lg['name']}\"")
            lines.append(f"      address: \"{lg['address']}\"")
            lines.append(f"      state_address: \"{lg['state_address']}\"")
            if 'brightness_address' in lg:
                lines.append(f"      brightness_address: \"{lg['brightness_address']}\"")
                lines.append(f"      brightness_state_address: \"{lg['brightness_state_address']}\"")
    if covers:
        lines.append("  cover:")
        for cv in covers:
            lines.append(f"    - name: \"{cv['name']}\"")
            for k in ('move_long_address','move_short_address','stop_address','position_address',
                      'position_state_address','angle_address','angle_state_address'):
                if k in cv:
                    lines.append(f"      {k}: \"{cv[k]}\"")
            lines.append(f"      travelling_time_down: {cv['travelling_time_down']}")
            lines.append(f"      travelling_time_up: {cv['travelling_time_up']}")
    if switches:
        lines.append("  switch:")
        for sw in switches:
            lines.append(f"    - name: \"{sw['name']}\"")
            lines.append(f"      address: \"{sw['address']}\"")
            if 'state_address' in sw:
                lines.append(f"      state_address: \"{sw['state_address']}\"")
    if binary_sensors:
        lines.append("  binary_sensor:")
        for bs in binary_sensors:
            lines.append(f"    - name: \"{bs['name']}\"")
            lines.append(f"      state_address: \"{bs['state_address']}\"")
            lines.append(f"      device_class: {bs['device_class']}")
            if bs.get('invert'):
                lines.append(f"      invert: true")
    if sensors:
        lines.append("  sensor:")
        for sn in sensors:
            lines.append(f"    - name: \"{sn['name']}\"")
            lines.append(f"      state_address: \"{sn['state_address']}\"")
            lines.append(f"      type: {sn['type']}")
    lines.append("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--knxproj', required=True)
    args = ap.parse_args()
    from xknxproject import XKNXProj
    proj = XKNXProj(args.knxproj).parse()
    lights, covers, switches, binary_sensors, sensors = build(proj)
    sys.stdout.write(render_yaml(lights, covers, switches, binary_sensors, sensors))


if __name__ == '__main__':
    main()