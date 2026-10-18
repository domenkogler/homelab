---
title: Network Architecture
role: index
domain: network
status: active
tags: [network, topology]
---
# Network Architecture

> **Role:** Index — the network domain hub. Broad topology overview + links to each `network-*.md` stack doc.
> **Links to:** `network-vlans.md`, `network-dns.md`, `network-vpn.md`, `network-rack.md`, `network-rack-generated.md`, `network-ops.md`
> **Linked from:** `index.md`

---

## Hosts

| Host (FQDN) | Model | Role |
|-------------|-------|------|
| `router.kogler.si` | MikroTik RB4011iGS+ | PPPoE, VLAN routing, firewall, WireGuard server, CAPsMAN |
| `switch.kogler.si` | MikroTik CRS328-24P-4S+ | Layer-2 VLAN-aware, PoE for APs, trunk via SFP+ |
| APs | hAP ac² (spalnica), hAP ac² (dnevna), hAP ac² spare, **wAP ac (garaža) = DEAD (hardware fault, needs replacement — ether1 reserved)** | CAPsMAN-managed, all wired (no mesh) |

---

## Config-manager truth

One config manager per box, and which one it is on a given box is a **declared fact of that host**:
`IaC/ansible/host_vars/<host>.yml` carries `network_manager` (who owns the interface the default route
rides today) and `network_manager_target` (what is owed there). Equal values = settled. Different
values = an owner-present migration is owed and `roles/network` **freezes** every address and resolver
leg on that host, because writing config under a manager that does not own the box produces files
nothing reads. Listing the hosts and their states here would only drift from that file — the read-only
answer for any moment is `scripts/ansible/probe-net-manager.sh`, and
`scripts/gate/check_net_manager.py` refuses a commit where a host the `network` role touches declares
nothing, declares a value outside the vocabulary, or implies one from a role default.

**Freeze is decided by the owed target, never by list membership.** `network_nm_dualhome_hosts` selects
which hosts get the NetworkManager keyfile leg, and that leg follows the manager the host **adopted**
(`network_manager`), not the one it is heading toward — so a settled NetworkManager host may legally sit
in the list, and a host whose `NetworkManager` declaration still owes `systemd-networkd` may not: the
latter would move the address under a manager that does not own the box, leaving the real one with no
address leg at all. The two shapes are one field apart and both read as "`NetworkManager` in a list", so
the gate's `--self-test` breeds the frozen state deliberately — an owed target in `host_vars`, then each of
the three things a frozen host may not declare (membership in the keyfile list, a `netd_phys_name`, a resolver
leg) — while a SETTLED host joining that same list is held out as a required-green control, so an always-red
check cannot masquerade as coverage.

Three states are legal, and the third is not a config manager at all:

| State | What it means | What `roles/network` does there |
|-------|---------------|---------------------------------|
| `NetworkManager` | NM holds the uplink (keyfiles in `/etc/NetworkManager/system-connections`) | renders/edits NM config only; a second running manager is refused or, when it provably holds no interface, disarmed by the same run |
| `systemd-networkd` | networkd is the manager whose units this repo writes | renders netd units only where the host also declares its NIC (`netd_phys_name`); a host that declares none renders none |
| `ifupdown` | **neither** manager owns the uplink: classic `/etc/network/interfaces`, driven by dhcpcd/dhclient, owns the address — proved by the route interface being up in `/run/network/ifstate`. A box here is *managed*, by a third path; both managers may be installed and running while configuring nothing | writes no address leg; it removes the netd units no manager reads and reports the state |

And two shapes that are findings, not states: `BOTH` (two managers able to rewrite one interface —
[network-rejected.md](network-rejected.md) *Two config managers, or none, on one box*) and `NONE`
(the address came from somewhere this repo cannot see).

⚠ **A rendered file is not configuration.** A unit written for a manager that does not run on the box
changes nothing on the wire and the converge still prints green — so a leg is gated on the *declared
manager*, never on whether some variable happens to be defined (a role-level NIC default once made
every such guard true on every host, and units naming `eno1` landed on the Pi, on spark and on the
VPS, none of which has that interface). `systemctl is-active` is not "owns the route" either: a
manager can be enabled, active and holding nothing, which is why the verdict is read from the
interface the default route rides.

The converge-time half lives in `roles/network`: it measures the box (`service_facts`,
`/run/network/ifstate`, `nmcli`, `networkctl`) and refuses where the measurement contradicts the
declaration, naming the fix. The one host where the declared manager is not the uplink's owner is the
VPS: its address belongs to the provider image's own `ifupdown` file, and networkd there exists only to
create the `wg-s2s` netdev, deliberately told to configure no interface
([network-vpn.md](network-vpn.md) §Layer 1: WireGuard Site-to-Site). So the rule asserts only what the declaration
commits to there — networkd runs, and no second manager runs beside it — while "the manager configures
nothing" stays a finding on every other box.

⚠ **Disarming the second manager must stop its socket too.** A `systemd-networkd` that holds no
interface and must be stood down is stopped *and disabled* by the same role, and so is its
`systemd-networkd.socket`: the service is `TriggeredBy` that socket (netlink/rtnetlink activation),
and a socket that survives the service stop will re-spawn the second manager on the next RTNL event
— measured live when the same play's own NM reload brought networkd back seconds after the stop. A
disarm that leaves the socket enabled is not settled: the next event resurrects the shape the
converge refused.

---

## WAN / ISP

- **ISP:** Telekom Slovenije
- **Connection:** PPPoE on `ether1` (ONT: Comtrend GRG-4260us)
- **IPv4:** Static public IP with domain `kogler.si`
- **IPv6:** **Scoped, not global.** The ISP delegates a **/56 via DHCPv6-PD on the PPPoE session** — leased
  (~15 min), not static — and the router advertises one /64 **on the Home VLAN (10) only**. 20/30/40/50/99 get
  no GUA at all, and because there is no NAT to hide behind there the v6 filter is the inbound protection: it
  drops everything from the WAN except stateless ICMPv6/DHCPv6, and refuses v6 egress from the untrusted VLANs.
  Plan of record, invariants and the two-switch rollback: [network-vlans.md](network-vlans.md) §IPv6;
  measurement + probe runbook: [network-ops.md](network-ops.md) §IPv6.

### Comtrend modem management path

> **✅ live** — laptop → modem web UI answers (401 auth page).

The Comtrend GRG-4260us is a consumer ONT in **PPPoE-bridge mode** — the RB4011
dials the PPPoE session on `ether1` via `pppoe-telekom`. The Comtrend's own
web UI lives on its LAN at the SSOT `comtrend_modem.modem_mgmt_ip` and is needed for the **twice-yearly
PPPoE-redial dance** (when the ISP-side session gets sticky and needs a manual
release). To avoid a physical cable swap every time:

- The RB4011 takes a **static `/24` on the modem's LAN** (SSOT:
  [`comtrend_modem.router_on_modem`](network-addresses-generated.md)) on `ether1`
  so the RB4011 can route to the modem's web UI. It must be a **`/24`, not a `/32`**:
  a `/32` gives no connected route to the modem subnet, so forwarded laptop traffic
  hits the PPPoE default instead of `ether1`
  ([network-rejected.md](network-rejected.md) `ether1` `/32` host route).
- A **srcnat masquerade** (SSOT: `comtrend_modem.modem_mgmt_ip`,
  `comtrend_modem.iface` — `out-interface=<iface> dst-address=<modem mgmt IP>
  protocol=tcp dst-port=80,443`) is REQUIRED: the consumer ONT only answers its
  web UI to its directly-connected LAN peer (the router's own modem-LAN
  address, SSOT `comtrend_modem.router_on_modem`) and silently ignores forwarded
  HTTP from deeper LAN subnets (the connection tracker shows `syn-sent` with 0
  reply packets). The router presents trusted-admin traffic to the modem as its
  own modem-LAN address.
- A **FORWARD rule** in the `router` Ansible role restricts access to
  `trusted-admin` hosts only (the laptop). All other homelab hosts get an
  explicit **default-deny** to the modem's subnet (SSOT:
  [`comtrend_modem.modem_subnet`](network-addresses-generated.md)).
- Private DNS record **`modem.kogler.si`** (SSOT:
  [`comtrend_modem.modem_mgmt_ip`](network-addresses-generated.md)) is ✅ live and lets
  the laptop browse the modem by name. The record must **never** go to Cloudflare —
  the modem is on a private RFC1918 subnet. In `technitium-seed.yml` it is seeded on the
  **home instances only** (Pi tertiary `secondary-pi` + oldsrv secondary `secondary`),
  gated OFF the VPS primary: it must never resolve from VPS/internet.

SSOT: `IaC/ansible/group_vars/router.yml` → `comtrend_modem`. The role is
idempotent and gated by `comtrend_modem.enabled: true` for opt-out per host.

---

## Physical Topology

```
Internet → ONT → router ether1 (WAN)
                    │
                    │ sfp-sfpplus1 (trunk)
                    ▼
              switch (CRS328-24P-4S+)
                    │
        ┌───────────┼───────────┐
        │           │           │
    APs (PoE)   Wired devices  oldsrv (trunk)
  2× hAP (access ports) VLAN 10,20,50 tagged
                       VLAN 99 native (Mgmt)
  (☠️ garage AP DEAD — hardware fault, ether1 reserved for replacement)
```

- **oldsrv** uses single UTP (Intel i350-T2) to switch as VLAN trunk — all VLANs over one cable; host-side dual-home (Home 10 untagged + Mgmt 99 tagged) is carried by **NetworkManager**, the manager that owns this box ([§Config-manager truth](#config-manager-truth))
- **nas** connects via access port (VLAN 10 Home, VLAN 99 tagged for Mgmt); **NetworkManager** owns its
  uplink and its manual-static keyfile carries the Home address — the Mgmt `.99` address is reserved
  on the router side and configured nowhere. Host side: [hardware-nas.md](hardware-nas.md) §Network;
  manager rule:
  [§Config-manager truth](#config-manager-truth)
- **pi** connects via access port (VLAN 10 Home); **NetworkManager** owns its uplink and carries its addressing ([§Config-manager truth](#config-manager-truth)) — `/etc/systemd/network` holds no netd units (only the OS `.link` files)

---

## Key Design Decisions

- Router does all inter-VLAN routing; switch is pure Layer-2
- Single VLAN-aware bridge on the router carries all traffic
- CAPsMAN in `local-forwarding=no` mode (all traffic tunneled to router)
- No mesh — all APs wired
- **IPv6 is scoped by construction, not by a rule per VLAN:** only the Home VLAN has a prefix to route, the
  untrusted VLANs get no GUA, and the v6 forward chain additionally refuses their egress. Nothing on the
  internet may reach a home host over v6 — the WAN input chain has **no inbound accept at all**, and adding
  one requires a row that names the one host and port (invariants: [network-vlans.md](network-vlans.md) §IPv6)

> **Status:** VLAN segmentation is **LIVE** — the network is segmented, not flat. VLAN definitions, subnets
> and firewall rules: [`network-vlans.md`](network-vlans.md); subnets/DHCP/SSIDs SSOT:
> [`network-addresses-generated.md`](network-addresses-generated.md).

---

## Document Map

| For | Read |
|-----|------|
| VLAN plan, subnets, firewall rules | [`network-vlans.md`](network-vlans.md) |
| DNS architecture, Technitium | [`network-dns.md`](network-dns.md) |
| VPN layers, Headscale mesh | [`network-vpn.md`](network-vpn.md) |
| Device wiring & interconnections | [`assets/Network-Devices.canvas`](assets/Network-Devices.canvas) (Obsidian Canvas) ⚠️ WIP |
| Rack layout (18U cabinet, rooms) | [`network-rack.md`](network-rack.md) → `assets/Rack.canvas` |
| Rack wiring (port↔device, generated) | [`network-rack-generated.md`](network-rack-generated.md) |
| Router config storage & versioning | [`network-ops.md`](network-ops.md) |
| Monitoring / SNMP | [`observability.md`](observability.md) |

## Related

- [VLAN Plan](network-vlans.md)
- [DNS Architecture](network-dns.md)
- [VPN & Remote Access](network-vpn.md)
- [Rack Layout](network-rack.md) · [Rack Wiring](network-rack-generated.md)
- [Network Operations — Router Config Storage](network-ops.md)
- [Network Review Queue](network-review.md)
- [Network Rejected / Dropped (decision log)](network-rejected.md)
