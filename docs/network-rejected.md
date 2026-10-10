---
title: Network — Rejected / Dropped Decision Log
role: log
domain: network
status: active
tags: [network, rejected, decision-log]
---
# Network — Rejected / Dropped

> **Role:** Decision log — network options this homelab evaluated and declined; the per-domain
> decision-log SSOT. One row per decision, sorted by subject. The current-state fact a decision settled
> lives in the owning doc, not here.
> **Links to:** `network.md`
> **Linked from:** `index.md`, `network.md`

## Decisions

| Decision | Status     | Why                                                                                                                                    |
| -------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Advertised routes to user nodes, including a tailnet-routable VIP | rejected | User nodes get no routes; home subnets become reachable from any network |
| Aggressive Home block-list tier (Hagezi multi+ / premium / PRO) | rejected | Answers the operator's own tailnet traffic, so false positives are self-inflicted |
| Block lists on the IoT tier | rejected | Appliance firmware shares CDN ranges with ad endpoints; Quad9 upstream only |
| bootstrap_dns_servers as both boot and steady-state host resolver | rejected | Two lifetimes in one variable; different needs and different targets |
| CAPsMAN manager datapath vlan-id for per-SSID VLANs | rejected | wifi-qcom-ac rejects it; per-SSID VLAN rides the CAP bridge pvid |
| CAPsMAN one shared master config for both bands | rejected | The 5GHz channel pin disturbed the 2.4GHz IOT slaves; pins are per-band |
| CAPsMAN per-MAC vlan-id access-list | rejected | Modern wifi access-list cannot set a per-client VLAN; bridge pvid only |
| Comtrend modem ether1 /32 host route | superseded | No connected route; a static /24 plus the masquerade is the model |
| Converge rsc tier renamed to full | rejected | Churn across files and tooling for no semantic gain |
| Deblab 00:15:5D:01:67:1E | dropped | Hyper-V VM, deleted; the MAC left the inventory |
| DFS channels on the CAPsMAN 5GHz band | rejected | Auto-selected DFS breaks association on many phones; 5GHz pins channel 36 |
| DHCP pointed at the router /ip dns for LAN clients | rejected | A single global resolver cannot differentiate per-VLAN upstreams |
| DNS primary on oldsrv | superseded | VPS is always-on and WAN-reachable, so resolution does not depend on home |
| dns.nameservers.split for kogler.si over the tailnet | rejected | LAN answers away, unreachable, and a split domain is never retried |
| dns.override_local_dns: true | rejected | Forces every device query through home: a DNS exit, not resolution |
| Dozzle and CrowdSec UI published on the public edge | rejected | Puts container logs and the security console on the open internet |
| Exit node on the router | rejected | RouterOS has no tailscaled; loses the app toggle |
| Exit-node host moved from the Pi to oldsrv | rejected | Widens the tailnet boundary; the Pi throughput constraint stays accepted |
| Fleet-wide logQueries on every DNS instance | rejected | Per-device behaviour record; only the Pi dst-nat target needs one |
| Floating the host resolver address with the HA VIP | rejected | It replaces the first entry instead of adding a rung |
| Full router.yml converge for mgmt-plane-sensitive changes | rejected | Re-asserting the bridge dropped VLAN-99 memberships and locked mgmt clients |
| Garage wAP ac AP | dropped | Board boot-loops after net init; wifi-qcom-ac-capable replacement needed |
| GitHub commit-signing SSH key | dropped | Signing off on every seat; nothing reads the key |
| Hand-kept seat `~/.ssh/config` blocks | superseded | The `ssh/aliases.tmpl` seat plane renders them |
| hAP ac at dnevna | superseded | hAP ac² replaced it; MIPSBE cannot run wifi-qcom-ac |
| Headplane docker-socket integration | dropped | UI DNS editing needs a socket proxy first |
| Home block lists (Hagezi multi + privacy) | superseded | Home and Guest load no list; this tier answers the operator's tailnet |
| Home hosts joined to the tailnet for off-LAN admin | rejected | Widens the tailnet boundary; the Home leg through the VPS jump works |
| Home node joined by interactive OIDC login | rejected | Node lands under the user and inherits `:*` |
| Home→IoT new-connection gating via trusted-admin | superseded | Narrowed to trusted-ha: oldsrv plus ha-vip, nas excluded |
| Hosts-file aliases as the answer mechanism | rejected | Overrides DNS per machine, reaches no device, hides a wrong zone answer |
| Inbound v6 accept for tailscale punches | dropped | Phone sends nothing; the destination would get no packet |
| Inbound v6 exception in chain=input | superseded | Host traffic is forwarded; input never sees it |
| Inbound v6 udp/41641 accept to oldsrv | dropped | RFC 7217 stable-privacy leaves no address to name |
| Internal AAAA records | rejected | Needs stable per-host global addressing and mirrored v6 inter-VLAN isolation |
| IPv6 kept off / WAN-only | superseded | DHCPv6-PD delegates a /56; Home runs scoped dual-stack |
| Kids filtered-DNS sighting as a separate bedtime close | dropped | One mechanism, one symptom: a re-watch buys nothing |
| Kids filtering scoped to VLAN 40 only | rejected | The tablets sit on Home VLAN; the per-MAC dst-nat is the mechanism |
| LAN-address entries in the tailnet nameserver chain | rejected | Private home addresses, unreachable away; the node address takes over |
| Laptop→Mgmt plane via ProxyJump pi | superseded | The Windows Mgmt99 vNIC reaches .99.x directly on-site |
| LiteLLM on the flat traefik-public bridge | rejected | Keeps the key-holding spine off the public-route apps bridge |
| mDNS reflection across VLANs (RouterOS repeater / Avahi) | rejected | Re-couples broadcast domains the VLAN plan separates; no integration needs it |
| Mgmt VLAN 99 reachable over the VPS site-to-site tunnel | rejected | A compromised VPS would gain admin-plane reach toward router, switch, oldsrv |
| Mgmt-access plus single-VLAN port model | superseded | Dual-home instead: untagged access VLAN, tagged Mgmt 99, same port |
| n8n firmware workflow: temporary iot-wan-allow toggles | superseded | The per-device wan_allow flag already gives cloud-IoT permanent WAN |
| NAS as a third tailnet node | rejected | Scope stays the two home nodes; owner decision |
| Netplan | rejected | Ubuntu default plus an extra python3/libnetplan layer; NM for Debian hosts |
| Nftables INPUT source-allow as the whole Technitium :53 gate | rejected | Published ports are FORWARDed, never INPUT; the FORWARD chain is the gate |
| No filtering on the Guest VLAN | superseded | Guest inherits the Home set: same protection, one group instead of two |
| No home host runs a tailnet node | superseded | oldsrv joins as one node, no routes, no bridge; the purpose survives |
| One config manager per box | rejected | Two managers on one host is chaos, none is lockout-class |
| One home tailnet node only | superseded | One box holding the tailnet answer leaves ha.kogler.si unreachable away |
| Per-box unversioned resolver drop-in files | dropped | A fourth source of zone answers; the generated alias artifact replaces it |
| Per-instance dns_resolver_upstreams lists | rejected | Parallel forwarding takes the fastest; independent operators is the point |
| Per-purpose SSIDs, five per VLAN | superseded | 3-SSID consolidation; every MAC is static, so per-MAC control is stronger |
| Pi exit node alone as the sole admin VPN path | rejected | Pi 4 throughput is the ceiling; a router WG peer needs neither |
| Pi granted tailnet `udp 53` | rejected | Technitium tertiary is a LAN role; naming it is its own call |
| Pi joined to the tailnet as `tag:dev` | rejected | Would widen every tag:dev rule to the DNS-tertiary box |
| Plain `ha.kogler.si` as a MagicDNS extra_record | rejected | A tailnet-enabled phone at home bypasses the VIP |
| Plain systemd-networkd `[WireGuardPeer]` on the VPS | superseded | networkd 257 silently never applies the peer block |
| Port-based tailnet sidecar on fixed ports 8080-8085 | superseded | The traefik-tailnet edge serves subdomains on 443 with wildcard certs |
| `.pub` hint as `IdentityFile` on seats | superseded | No agent under Git-Bash; private halves on disk |
| Public/VPS third rung in a home host resolver pair | rejected | It answers NXDOMAIN for these names: worse than a timeout |
| RecursionNetworkACL as the only recursion gate | rejected | The network-level gate is authoritative; the ACL alone does not enforce |
| Remote desktop over the relayed tailnet path | dropped | Relayed 70–240 ms; a direct session is required first |
| Reordering the Home resolver chain for latency | rejected | HA-independence: Home must resolve with oldsrv down; forwarding closed the gap |
| Self-hosted DERP on the VPS | rejected | Another relay leg; latency sits on the phone leg |
| Single shared WireGuard keypair on both wg-s2s ends | rejected | WireGuard silently refuses to handshake with your own key |
| Split-DNS routes and client --accept-dns toggles for tailnet names | rejected | A client-side stopgap; the headscale chain is the durable fix |
| systemd-networkd as the nas and oldsrv config manager | superseded | nas only: oldsrv is NetworkManager too, its netd units name nothing |
| systemd-networkd as the oldsrv config manager | rejected | NetworkManager already holds the routes; cutover risks the converge leg itself |
| systemd-networkd as the repo-wide config manager | superseded | Measured per host instead; NetworkManager fleet-wide, networkd on the VPS |
| systemd-networkd on the Pi | superseded | The Pi ships NetworkManager; two keyfiles are the dual-home shape |
| Tailnet DNS servers, the VPS primary first | rejected | Unreachable off-site; the MagicDNS loop answers locally on any network |
| Tailnet resolver chain left unchanged | rejected | Away devices burn timeouts on two resolvers they cannot reach |
| Tailnet resolver chain trimmed of the LAN entries | rejected | Buys the away case by selling the WAN-out case |
| Technitium forwarders pointed at the router /ip dns or oldsrv | rejected | A loop through the same chain, dragging oldsrv and VPS back in |
| Temporary Home→Mgmt forward as the laptop mgmt path | superseded | Reverted: Mgmt is reached by tagged VLAN 99, never by widening Home |
| The tailnet edge joining services-internal | rejected | Would let the edge reach every app on the flat internal bridge |
| The VPS public address as the tailnet's resolver | rejected | Same zone, views by source: NXDOMAIN away for names the node serves |
| Truenas 92:47:15:04:EB:49 | dropped | Locally-administered MAC never owned; the VM is deleted |
| Two config managers, or none, on one box | rejected | Per-box file ownership is unpredictable and self-conflicting |
| UPS web-UI firewall rule | rejected | UPS left the Mgmt VLAN; its web UI and Modbus stay unused |
| v4 dst-nat + input accept for tailscale punches | dropped | Scan traffic proves the mechanism; the phone cannot ask |
| VLAN 21 IoT-Internet as a Wi-Fi-reachable network | dropped | wifi-qcom-ac cannot tag per client; VLAN 20 plus wan_allow is reality |
| Whole internal zone as MagicDNS extra_records | rejected | A frozen zone copy per device: per-subnet views and VIP semantics die |
| Winbox `*-wb` LocalForward aliases / Pi-dial pattern | superseded | Winbox binds VLAN 99; use the on-site Mgmt leg |
| WireGuard on the router for user devices | superseded | Headscale serves the family; one owner WG peer adds a VPS-free path |
| WSL bridged Mgmt99 route-through as the default | superseded | Durable state is NAT plus generated resolv.conf; Mgmt99 is opt-in on-site |
