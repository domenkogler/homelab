# HD-307 (remaining) — Pi host-side static dual-home (network role)

> **Role:** Implementation plan — close the last host-side gap of HD-307 by authoring the
> `network`-role static dual-home for the Pi, so the Pi holds 10.10.1.20 (Home) +
> 10.10.99.20 (Mgmt) on its own interface and becomes the Home Assistant **primary**
> (VIP / keepalived MASTER).
> **Environment:** laptop = WSL Debian 13 (bash) · target = Raspberry Pi 4 (Raspberry Pi OS
> Lite / raspi.debian.net trixie), user `admin`, SSH key `~/.ssh/id_ed25519` (the
> `ansible-admin_ssh` private key). Session runs in worktree `../homelab-wt-20260901-2056`
> / branch `session/hd307-pi-network`.

## 0. Why this is the next task (handoff #50 §3-N #1)

The latest handoff (`prompt.md` #50) names HD-307 as **next**, with the **router side DONE +
LIVE (2026-09-01)** — Pi + laptop static DHCP reservations + whole-Mgmt `Mgmt(99)→Home(10)`
FORWARD allow (delta `rb4011_hd307_delta.rsc.j2`, live-applied). The remaining host-side
item, still **open**, is exactly:

- Pi **`network` role static dual-home on `eth0`** (mgmt + Home per SSOT — the `role:network`
  scoped TODO, still un-authored for Pi/oldsrv/nas),
- create `ansible-admin` (NOPASSWD + key) on the Pi,
- run `raspberry_pi.yml` (Docker + HA-Container + technitium-secondary + traefik-ha, render-first HD-185),
- verify `ha.kogler.si`→VIP + failover.

This plan implements the first bullet (the static dual-home), plus the `ansible-admin` ensure
and the playbook-verify skeleton. The later bullets (HA/keepalived live verification,
failover runbook) are separate deploy-gated steps that depend on Phase 2 (NUT) + Phase 1.5
settle — out of this change's scope, tracked in todo (§2 below).

## 1. Context already settled (do not re-decide)

- **Config manager = systemd-networkd (repo default), BUT the Pi ships NetworkManager.** netplan
  rejected 2026-08-16 (HD-56, `network-rejected.md` line 22) for the repo's desktop/VPS hosts;
  the live Pi OS uses **NetworkManager** (RPi OS default, cloud-init `renderers/activators:
  netplan, network-manager`, NM 1.52.1). This plan uses **NetworkManager keyfile** for the Pi
  and records the delta (Pi-uses-NM) in `network-rejected.md` — do not silently fight the OS
  default or the networkd-on-Pi assumption.
- **Pi is dual-homed** (Option A, R-1): `10.10.1.20` (Home, `ansible_host`, VRRP anchor) +
  `10.10.99.20` (Mgmt, `mgmt_ip`). SSOT already in `host_vars/pi.kogler.si.yml`.
- **`ha_keepalived_interface: eth0`** — keepalived binds the VIP on `eth0`; the profile must
  keep Home-VLAN addressing on `eth0` ONLINE always (Mgmt leg may flap; `ha` must not).
- **Firewall** (network-vlans.md): Home→Mgmt accept (SSH/WinBox/API/HTTPS); Mgmt→Home accept
  (whole-Mgmt, HD-307); default-deny otherwise. The Pi's Mgmt leg is a `trusted-admin` peer,
  but needs no inter-VLAN exceptions of its own.
- **Pi is an access port on VLAN 10** (`ha_keepalived_interface` note) — **plain `eth0`, no trunk /
  sub-interfaces** (unlike oldsrv trunk 10+99+20+50). Both static addresses sit on the same
  untagged `eth0`.
- **`/etc/hosts`** is already templated by the same `network` role (bootstrap resolution includes
  the Pi's `ansible_host`); will re-verify after the profile lands.

## 2. Scope

**In scope (this change):**
1. `network` role: author static dual-home for the Pi via **NetworkManager keyfile profile** on `eth0` (Option A — see §6):
   - static IPv4 `10.10.1.20/24` (Home) + `10.10.99.20/24` (Mgmt) on `eth0`, Home = default via `10.10.1.1`, Mgmt `never-default` (no mgmt default route; admin laptop reaches the Pi via the router's Mgmt(99)→Home(10) accept).
   - disable DHCP on `eth0`; keep the profile idempotent (modify-only, never deletes the active connection); session-safe (NM applies both addresses while the connection stays up).
   - keep `ha_keepalived_interface: eth0` semantics (Home addr always online; mgmt addr additive).
2. Template the profile from SSOT (`pi` `network_static_hosts` rows + `mgmt_ip`/`ansible_host`), never literals.
3. `ansible-admin` ensure on the Pi (mirror `first-boot-config.sh`/post_install: create the user + NOPASSWD + key), so the repo user (not just `admin`) can run Ansible. Also align SSH `AllowUsers` + hostname `pi`.
4. `raspberry_pi.yml` run (role order already correct: `common → ai_diag → network → nut → docker → docker_services → …`) — dry-run first, then live converge on the Pi.
5. Update owning docs (todo HD-307 tail, `deployment-manual.md` §Phase 4 network step, the stale `roles/network` header, `IaC/README`, `docs/network-vlans.md` if it implies host static already live) + record the **Pi-uses-NetworkManager** delta in `network-rejected.md` + render generated docs (`render_all.py`) + validate green.

**Out of scope (already tracked):** wg-s2s handshake (HD-285), CAPsMAN/Phase-1.5 remainder, Technitium primary→VPS (HD-299), tailnet clean URLs (HD-297(c)), HA live failover verification, singular NUT/etc. — see `todo.md` rows.

## 3. Files

- `IaC/ansible/roles/network/tasks/main.yml` — add a Pi-only block that renders + activates a **NetworkManager keyfile** profile for `eth0`: `ipv4.method manual`, two static addresses (Home `10.10.1.20/24` + Mgmt `10.10.99.20/24`), Home default via `10.10.1.1`, `never-default: yes`, DHCP off. Guarded by a var (e.g. `network_static_hosts` + `mgmt_ip is defined` on `pi.kogler.si`). Keep the existing admin assert + `/etc/hosts` + doc render.
- `IaC/ansible/roles/network/templates/eth0.nmconnection.j2` — the NM keyfile, values from SSOT (host_vars `ansible_host`/`mgmt_ip` + `network_static_hosts` gateway), never literals.
- `IaC/ansible/roles/network/handlers/main.yml` — NEW: `reload NetworkManager` (tags: always).
- `IaC/ansible/host_vars/pi.kogler.si.yml` — no change needed (IPs already there).
- `IaC/ansible/group_vars/raspberry_pi.yml` — no change (role list already includes `network`).
- `scripts/render_all.py` — regenerate `docs/network-addresses-generated.md` (IPs unchanged, likely no diff).
- `deployment-manual.md` §Phase 4 — update the "network (static on VLAN 10)" step to the NetworkManager dual-home implementation + verify.
- `IaC/README.md` + `roles/network/tasks/main.yml` header — clear the stale "config manager undecided" TODO once implemented.
- `docs/network-rejected.md` — append the Pi-uses-NetworkManager decision delta (Option A) per the append-only log.
- `todo.md` HD-307 — trim completed host-side pieces; keep ⏳ deploy-gated verification.
- `docs/network-vlans.md` — note the Pi host-side static dual-home is now implemented. 

_(User SSH-config note, non-repo: `~/.ssh/config` `Host pi` was fixed by the owner to `id_ed25519`; `Host oldsrv` points at `10.10.99.79` (DHCP, non-SSOT) — unrelated to this change, flag only.)_

## 4. Verify (after converge, on the Pi)

```bash
ip -4 a show eth0                      # expect 10.10.1.20/24 AND 10.10.99.20/24
ip route                               # default via 10.10.1.1 (Home); NO mgmt default
nmcli -g ipv4.method,ipv4.addresses con show "Wired connection 1"
                                       # manual + both addresses, never-default on mgmt
systemctl status NetworkManager        # active; profile loaded
resolvectl status / cat /etc/resolv.conf   # DNS OK (NM renders 10.10.1.30/20/1)
ping -c1 10.10.1.1                     # Home gateway reachable
ping -c1 10.10.99.1                    # Mgmt reachable (router INPUT from trusted-admin)
ss -tlnp | grep -E ':(22|5380|8123|9090)'   # ssh + technitium + HA + traefik-ha surfaces
# Session-safety proof:
ssh -o ConnectTimeout=10 admin@10.10.1.20   # still open AFTER the apply (no sever)
```

From the laptop (Mgmt side):
```bash
ping -c1 10.10.99.20                   # Pi on the Mgmt leg (router FORWARD Mgmt→Home + Pi's own mgmt addr)
curl -ks https://10.10.99.20/          # (traefik-ha surface, if that service is up)
```

## 5. Risks / guards

- **Session sever:** the NM profile is additive (both addresses applied while the connection stays up; never removes the Home addr mid-run; `nmcli connection modify` is idempotent).
- **Mgmt-leg flap** must not take down keepalived/`ha` — Home addr drives the connection; mgmt is additive (`never-default`).
- **Fail-closed secrets:** this role touches no secrets; the NM keyfile is 0644 root-owned, no 1P lookups.
- **Idempotency:** `nmcli connection modify`/`save` on the existing profile; never a destructive recreate; `NetworkManager reload` via handler only on change.
- **Decision delta:** Pi-uses-NetworkManager must be recorded in `network-rejected.md` (append-only) per §8.3 — the stale "networkd-or-netplan undecided" TODO in the role header is removed.
- **Validation:** `validate-all.sh` must stay green (no new IP literals, doc-map, generated suffix).

## 6. Recon results (2026-09-01) — Pi networking reality = NetworkManager

**Recon (live probes, read-only) settled the earlier SSH confusion:**
- **Pi = `admin@10.10.1.20`, key = `~/.ssh/id_ed25519` (the `ansible-admin_ssh` private key, fingerprint `SHA256:1uKzm…`)** — SSH **works** with the right combination. Earlier denials were from probing `ansible-admin@` (a user the Pi does not have yet; it has `admin`).
- **`~/.ssh/config` `Host pi` has a bug:** `IdentityFile ~/.ssh/id_ed25519.pub` should be `~/.ssh/id_ed25519` (the `.pub` is a reference-only file, not a usable identity). Fixing the user's private SSH config is a **human decision** (propose, not silently edit).
- **Pi = Debian 13 (trixie), RPi OS, hostname `pi`, user `admin` in `sudo` group.** eth0 = `10.10.1.20/24` **dynamic** (DHCP) — the gap this task closes.
- **The Pi's network is managed by NetworkManager** (RPi OS default; NM 1.52.1; cloud-init `renderers/activators: netplan, network-manager`; `Wired connection 1` = eth0, `ipv4.method auto`; `/etc/resolv.conf` by NM; no netplan dir, no systemd-networkd active, no dhcpcd unit).
- `systemd-networkd` + `systemd-resolved` are **inactive**; no `/etc/systemd/network` units for eth0.
- **Decision re-opened:** `network-rejected.md` says netplan rejected → **systemd-networkd** (2026-08-16), but that predates the actual Pi image which ships **NetworkManager**. Implementing the networkd static unit as-is would *disable* NM or add a second manager fighting NM — high risk of severing the DHCP session.

**Options (need owner sign-off — this is a re-opened decision):**
- **A. NetworkManager keyfile connection profile for `eth0` (recommended for the Pi):** `ipv4.method manual` + two static addresses (`10.10.1.20/24` Home + `10.10.99.20/24` Mgmt, Home = default via `10.10.1.1`, Mgmt route `never-default: yes`), NM keeps DHCP off. Native to the Pi OS, idempotent (`nmcli connection modify`), session-safe (NM adds both addresses before remote connection; interface stays up). No `systemd-networkd` needed. Record the Pi-as-NM decision in `network-rejected.md` (supersedes the networkd-only assumption for hosts that ship NM).
- **B. systemd-networkd on the Pi (repo decision as written):** would require stopping/disabling NM + installing networkd + re-owning eth0 — heavier, fights the OS default, higher sever risk, and the `networkd` role is currently host-agnostic (desktop/VPS assume networkd).

**This plan implements Option A** unless the owner says otherwise; the `network` role gains an NM-profile task (Pi-only) while keeping the networkd path for hosts that use it.

## 7. Definition of done

- `network` role authors Pi static dual-home (NM keyfile); dry-run + live converge on the Pi come back green.
- Pi holds both addresses; Home routing intact; SSH session survives (admin@10.10.1.20).
- `ansible-admin` user present + key authorized (repo user can run Ansible).
- `validate-all.sh` green; docs + `network-rejected.md` delta + todo updated; commit signed on the session branch; merged back ff-only to main; worktree pruned.