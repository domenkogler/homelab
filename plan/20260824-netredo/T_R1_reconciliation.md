# R-1 — Reconciliation: home-server VLAN/IP/DNS model (Option A)

**Status:** DONE (analysis complete; patches in this worktree).
**Decision:** **Option A — pi & oldsrv dual-homed (trunk 10+99); nas single-Home (10.10.1.10) with iLO4 on 99.**
Owner-confirmed prior to orchestrator handoff.

## Why Option A fits (evidence)

- The **SSOT `group_vars/all.yml` already models pi/oldsrv as dual** (99 services + 10 Home
  addresses). nas is dual too (Home `10.10.1.10` + `mgmt_ip 10.10.99.10`).
- The **migration inventory** (created 2026-08-23) lists pi/oldsrv → `trunk 10+99`; nas → Home.
- `oldsrv.host_vars` already dual (`ansible_host 10.10.99.30` + `home_ip` derived 10.10.1.30).
- DNS home IPs (10.10.1.30 primary / 10.10.1.20 secondary) are **already the current bind** and
  must keep pointing Home — Technitium binds the node IP, not the mgmt plane.
- The **router role skips VLAN-99 DHCP** (`id not in [1,99]` on pools/servers/nets) and only
  reserves AP MACs → all 99 hosts must be **static IPs**, which preseed/host_vars already assign.

## Contradictions found + resolution

| # | File | Contradiction | Fix |
|---|------|---------------|-----|
| 1 | `host_vars/pi.kogler.si.yml` | pi not actually dual (only Home `10.10.1.20`); all.yml + addresses-generated both list pi→99 `10.10.99.20` | add `mgmt_ips`/doc line: pi mgmt plane = 10.10.99.20 (trunk 10+99). **Keep `ansible_host: 10.10.1.20` Home** (SSH/VPN anchor); document the 99 address |
| 2 | `host_vars/oldsrv.kogler.si.yml` | dual already; comment drift only | clarify: `ansible_host` = mgmt 99 is the **management** door; `home_ip` is the Home node addr |
| 3 | `host_vars/nas.kogler.si.yml` | nas single-Home already (mgmt_ip 99.10 kept); all.yml **kept a nas 99 entry** | nas is **not** dual — keep all.yml nas `vlan 99` removed? NO: keep the 99 mgmt_ip as iLO-adjacent mgmt; but remove the prod confusion by renaming that entry to make clear it's mgmt-plane-only. **Leave as is** (mgmt_ip is the field; all.yml 99 is the SSOT reg) |
| 4 | `group_vars/all/main.yml` | nas `vlan 99` entry duplicates the mgmt-plane intent; fine as SSOT | keep (it feeds `mgmt_ip`) |
| 5 | `switch_port_map` (switch.yml) | `nvidia-shield` MAC `48:B0:2D:09:6F:90` — inventory flags that exact MAC as **⚠️ unknown**; switch map claims Media(50). Also Nintendo Switch listed **VLAN 21** but plan says **Media (50)**; `nas-eno1/eno2` vlan blank | **defer to R-2** (reservations) — flag both as findings |

## DNS model (unchanged — the critical invariant)

- oldsrv Technitium **primary**: `10.10.1.30` (Home) — `dns_primary_ip` host_var / router `dns_primary_ip` hostvar.
- pi Technitium **secondary**: `10.10.1.20` (Home) — `dns_secondary_ip`.
- router hosts the **tertiary** `/ip dns` (HD-182) on the mgmt plane — already in role.
- DNS does **not** move to Mgmt (99). Option-A mgmt IPs are for management plane only.

## Why single-Home nas is correct

- nas is the **Cockpit/NFS/NUT master** — its services (NFS, NUT) are Home-LAN services; Home is
  where the family + HA (ha-vip 10.10.1.200) reach it. iLO4 (BMC) is the out-of-band mgmt on 99.
- Its `mgmt_ip 10.10.99.10` is the **static reg on 99** (mgmt door) — consistent with single-Home.

## Router reservation implication (R-2 pre-check)

- pi/oldsrv/nas need **static IPs** (preseed): pi(10.10.1.20 / mgmt 10.10.99.20), oldsrv(10.10.99.30, home 10.10.1.30), nas(10.10.99.10 result) — none rely on DHCP. Option A holds. Verified the router skips 99. Good.

## Doc/IaC deltas to apply (this worktree)

1. `host_vars/pi.kogler.si.yml` — add mgmt-plane comment + confirm 10.10.99.20 reg (no structural change).
2. `docs/network-migration-inventory.md` — pi/oldsrv rows: ensure "trunk 10+99"; nas row single-Home(10) + iLO(99); fix the **duplicate AP-dnevna row** (task leftover R-2/4) — do here to keep R-1 self-consistent.
3. `docs/network-addresses-generated.md` — regenerate only if SSOT moved (it had pi/99 already); note single-Home nas.

**Changelog + journal:** R-1 closes a portion of HD-03 "reconcile at cutover" for the 3 host nodes; append one journal block + changelog row (owning doc → network-vlans.md / new pending note).