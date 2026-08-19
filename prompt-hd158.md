# Prompt: HD-158 — `network-addresses.md` = IP-SSOT only until `switch_port_map` verified

> Handoff written 2026-08-19. Goal: stop the generated rack doc from treating a WIP switch map as real.

## Task

The generated `docs/network-addresses.md` currently renders **physical port mappings** from
`switch_port_map` — but that map is work-in-progress (the real switch ports are only known at the
HD-03 network cutover). The generated doc must be **IP-address-SSOT only** until the map is verified.

## What to do

1. **Read `docs/network-addresses.md`** (generated — never hand-edit) + `scripts/render_rack_connections.py`
   (the renderer) + `docs/network-rack.md` (owning doc).
2. **Gate the physical-port render** behind a `switch_port_map_verified` flag:
   - Add the flag (default **false**) to `group_vars/all.yml` (or wherever the renderer reads config).
   - When **false**: the generated `network-addresses.md` renders **only** the IP/CIDR SSOT
     (no physical-port/rack section), or renders the rack section with a clear
     "⚠ WIP — switch port map unverified (HD-03)" banner.
   - When **true**: render the full physical-port output as today.
3. **Update `docs/network-rack.md`** to document the flag + the WIP state.
4. Update the **HD-158 row in `todo.md`** (✅ IaC done; ⏳ deploy-gated tail: set the flag at
   HD-03 when real ports are recorded).
5. Re-render the generated doc if the repo's render path produces it (see the render command in
   the doc header — `python scripts/render_network_addresses.py` or `render-docs.yml`).
6. `bash scripts/validate-all.sh` must be green.

## Guardrails
- `network-addresses.md` is **generated** — never hand-edit; change the renderer/flag and re-render.
- Do not remove the IP SSOT content — only the physical-port part is gated.
- Keep the flag name consistent with existing `*_verified` conventions if any exist.

## Definition of done
Physical-port render is gated behind `switch_port_map_verified: false` by default; the generated doc
shows IPs only (or a WIP banner); `network-rack.md` documents it; HD-158 row updated; validators green.
