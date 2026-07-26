# Goal:
Main goal is to create network with multiple locations for family use. The key point is safety by design and easy usability and managebility with (preferable) UI. CLI for setup is perfectly fine, but not for later management.

## Current state
At home i have following infrastructure: 
 - Comtrend GRG-4260us by ISP (Telekom Slovenije) with optical connection and wired to mikrotik router, with unconfigured PPPoE connection
 - mikrotik rb4011iGS+ as main router at home, wired to Comtrend GRG-4260us, with configured PPPoE connection for internet access
 - mikrotik CRS328-24P-4S+ switch at home, wired to APs and other devices
 - various mikrotik AP points at home: 
   - RB962Uigs-5HacT2Hnt: used as AP, wired to switch
   - RBD52G-5HacD2Hnd: used as AP, wired to switch
   - hAP ac2: unused
 - rPi v4 running HomeAssistant OS
 - Gira IP router KXIPRT01 for managing KNX devices (cevers and lightning) with HomeAssistant
 - several Schelly shellyrgbw2 devices connected to home wifi, managed by HomeAssistant
 - main desktop PC wired to router
 - main laptop with docking station wired to router
 - several other devices as tables, phones, TVs, gaming consoles

## Planned in near future
Could VPS with Proxmox running:
 - Authentik
 - Pangolin
 - reverse proxy (not decided: traefik or caddy or nginx)
 - immich
 - git server (not decided: forgejo or gittea) for storing config of mikrotik devices, homeassisant, ansible scriptsm etc
 - seaprate services for testing and learning that sould not interfere with other in production

## Goals in home network
 - create easy managable safe home network with separate subnets (management, local, iot, guest, etc)
 - create easy managable networking with cloud VPS with proxmox and two porpuses: production services (authentik, pangolin, imich)
 - create easy managable vpn tunnels to home network for laptop, phones and VPS in cloud
 - create easy managable transportable mikrotik AP for use outside slovenia to access geoblocked content while traveling

## Goals in VPS
- create easy managable safe proxmox network with separate subnets and VPN acceesibility

# Tasks:
 - analyze current network at home (rb4011_config.rsc). Should i start with fresh network? Starting fresh is not a problem, downtime is expected.
 - propose new network architecture using existing infrastructure
 - propofe new netowrk architecture using existing infrastructure and new with budged of 1000€
 - propose network arhitecture for VPS
 - propose solution for easy managable VPS tunnels