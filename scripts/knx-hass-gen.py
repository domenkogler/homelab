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

Dependency: xknxproject (pip install xknxproject) for `--check` and for generation itself;
`--self-test` is pure stdlib so it can sit in `validate-all.sh` on a runner that has no
xknxproject (the runner today has none — measured 2026-09-25: `import xknxproject` fails in
the system python, and nothing in the repo declares the dependency).

Self-check (`--check`) — WHY it exists: most addresses here are read out of the project file
and cannot be invented, but the `sensor:` appendix below is a HAND-TYPED list of 19 group
addresses. That is the one place this generator can ship an address that ETS does not know,
and HA fails per-entity on exactly that (`Did not respond to GroupValueRead`). `--check`
re-renders and asserts every emitted address is published in the project, so the appendix
cannot silently drift from the SSOT. Measured on 2026-09-25: 246 GAs published in the
project, 154 emitted, 0 outside the project — including all 19 hand-typed ones.
"""
import argparse
import re
import sys

# Every address shape the renderer can emit (address / state_address / brightness_… etc.)
EMITTED_ADDR = re.compile(r'address:\s*"(\d+/\d{1,2}/\d{1,5})"')


def emitted_addresses(yaml_text: str) -> set:
    """Every KNX group address in a rendered block."""
    return set(EMITTED_ADDR.findall(yaml_text))


def phantom_addresses(emitted: set, published) -> list:
    """Emitted addresses that the ETS project does not publish, sorted for a stable diff."""
    pub = set(published)
    return sorted(a for a in emitted if a not in pub)


def self_test() -> int:
    """Pure-stdlib check of the subset logic `--check` relies on (no xknxproject, no project file)."""
    failures = []
    published = {"1/1/1", "1/1/2", "2/0/5"}
    doc = '\n'.join([
        '  light:',
        '    - name: "Hall"',
        '      address: "1/1/1"',
        '      state_address: "1/1/2"',
        '  sensor:',
        '    - name: "Boiler"',
        '      state_address: "9/9/9"',
    ])
    got = emitted_addresses(doc)
    if got != {"1/1/1", "1/1/2", "9/9/9"}:
        failures.append(f"emitted_addresses() read {sorted(got)} — the checker cannot see what to verify")
    if phantom_addresses(got, published) != ["9/9/9"]:
        failures.append("a hand-typed address that ETS does not publish was NOT flagged — the check is decorative")
    clean = '\n'.join(['    - name: "Hall"', '      address: "1/1/1"', '      state_address: "1/1/2"'])
    if phantom_addresses(emitted_addresses(clean), published):
        failures.append("a clean render was flagged — the check would cry wolf on every regeneration")
    if phantom_addresses(set(), published):
        failures.append("an empty render reported phantoms")
    if failures:
        print("FAIL: knx-hass-gen.py --self-test:")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("OK: self-test — the emitter reader sees every address field, an address outside the ETS "
          "project is caught, a clean render is not (HD-439)")
    return 0

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
    """FT-1 (switchable) / FT-6 (dimmable) -> HA light map.

    brightness_address MUST be the ABSOLUTE dimming GA (DPT 5.001, role
    'DimmingValue'), NOT the relative step-dim GA ('DimmingControl', DPT 3.007,
    used for brief up/down presses). HA's KNX light writes an absolute 0-255 value
    to brightness_address to set brightness AND to turn OFF (brightness=0). A
    DPT 3.007 GA ignores absolute values -> OFF/ON brightness commands go nowhere
    while the state_address echo keeps HA stuck (light.jedilnica: could ON but
    never OFF — live 2026-09-07). xknxproject exposes the ETS roles per function:
    SwitchOnOff / InfoOnOff / DimmingControl (3.007) / InfoDimmingValue (5.001) /
    DimmingValue (5.001).
    """
    sw = role_addr(fn, 'SwitchOnOff')
    st = role_addr(fn, 'InfoOnOff')
    dim_val = role_addr(fn, 'DimmingValue')        # absolute brightness write (DPT 5.001)
    info_dim = role_addr(fn, 'InfoDimmingValue')    # absolute brightness state (DPT 5.001)
    out = {"name": name, "address": sw, "state_address": st}
    if dim_val:
        out["brightness_address"] = dim_val
        out["brightness_state_address"] = info_dim or dim_val
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


# Hand-typed on purpose: these GAs are published in the ETS project but sit outside any
# FT-1/6/7 function, so nothing derives them. They are the ONLY place this generator can
# emit an address ETS does not know — which is what `--check` exists to prove.
APPENDIX_SENSORS = [
        ("Rekuperator Airflow",         "12/1/13", "flow_rate_m3h"),
        ("Rekuperator Room Temperature",  "12/1/14", "temperature"),
        ("Rekuperator Extract Temperature","12/1/15", "temperature"),
        ("Rekuperator Exhaust Temperature","12/1/16", "temperature"),
        ("Rekuperator Outdoor Temperature","12/1/17", "temperature"),
        ("Rekuperator Supply Temperature", "12/1/18", "temperature"),
        ("Rekuperator Room Humidity",     "12/1/19", "percent"),
        ("Rekuperator Extract Humidity",  "12/1/20", "percent"),
        ("Rekuperator Exhaust Humidity",  "12/1/21", "percent"),
        ("Rekuperator Outdoor Humidity",  "12/1/22", "percent"),
        ("Rekuperator Supply Humidity",   "12/1/23", "percent"),
        ("Rekuperator Filter Replace",    "12/1/24", "delta_time_hrs"),
        ("Kopalnica Radiator Current",    "4/4/3",   "current"),
        ("WC Radiator Current",           "10/4/3",  "current"),
        ("Pecica velika Current",         "5/4/2",   "current"),
        ("Pecica mala Current",           "5/4/5",   "current"),
        ("Pomivalni stroj Current",       "5/4/8",   "current"),
        ("Pralni stroj Current",          "6/4/2",   "current"),
        ("Susilni stroj Current",         "6/4/5",   "current"),
    ]

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
    # ---- Appendix: sensors whose GAs are in the project but NOT inside an
    # FT-1/6/7 function (ComfoConnect rekuperator + appliance current clamps).
    # DPTs verified from the .knxproj group_addresses (12/1/13 = 13.002,
    # 12/1/14-18 = 9.001, 12/1/19-23 = 5.001, 12/1/24 = 7.007 '(h)'). The
    # current clamps (ElektricniTok Status) have no DPT in ETS but are mA
    # (legacy live-config type). Kept here so regeneration never drops them.
    appendix_sensors = APPENDIX_SENSORS
    if appendix_sensors:
        lines.append("  sensor:")
        for name, addr, t in appendix_sensors:
            lines.append(f"    - name: \"{name}\"")
            lines.append(f"      state_address: \"{addr}\"")
            lines.append(f"      type: {t}")
            # KNX tunnel has route_back=false -> poll these status GAs so values
            # refresh (ComfoConnect/appliance don't push status to the tunnel).
            lines.append("      sync_state: every 30")
    lines.append("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--knxproj', required=False)
    ap.add_argument('--check', action='store_true',
                    help="re-render and assert every emitted address is published in the project; "
                         "print the counts instead of the YAML")
    ap.add_argument('--self-test', action='store_true', help="pure-stdlib check of --check's logic")
    args = ap.parse_args()

    if args.self_test:
        sys.exit(self_test())
    if not args.knxproj:
        ap.error("--knxproj is required unless --self-test is given")
    from xknxproject import XKNXProj
    proj = XKNXProj(args.knxproj).parse()
    lights, covers, switches, binary_sensors, sensors = build(proj)
    out = render_yaml(lights, covers, switches, binary_sensors, sensors)

    if args.check:
        published = set(proj['group_addresses'].keys())
        emitted = emitted_addresses(out)
        bad = phantom_addresses(emitted, published)
        hand = sorted({a for _, a, _ in APPENDIX_SENSORS})
        print(f"ETS project publishes {len(published)} group addresses; this render emits "
              f"{len(emitted)} of them ({len(hand)} of those come from the hand-typed sensor appendix).")
        if bad:
            print(f"FAIL: {len(bad)} emitted address(es) are NOT published in the ETS project — HA will "
                  "fail those entities per-entity ('Did not respond to GroupValueRead'):")
            for a in bad:
                origin = "hand-typed appendix" if a in hand else "derived from a function"
                print(f"  {a}  ({origin})")
            sys.exit(1)
        print(f"OK: every emitted address is published in the project (HD-439). The render is safe to "
              "commit; regenerate without --check to write it.")
        sys.exit(0)

    # Encode UTF-8 + LF explicitly (Windows console/stdout mangles the em-dash to
    # cp1252 0x97 and adds CRLF; repo convention = UTF-8/LF).
    sys.stdout.buffer.write(out.encode('utf-8'))


if __name__ == '__main__':
    main()