---
title: Pi Provision Runbook — Phase 4 (HA primary on pi.kogler.si)
role: detail
domain: deployment
status: active
tags: [deployment, raspberry-pi, homeassistant, knx, phase4, runbook, provision]
---
# Pi Provision Runbook — Phase 4 (`pi.kogler.si` HA primary)

> **Role:** Detail — imperative, step-by-step runbook to provision (or re-provision) the
> Raspberry Pi 4 as the **Home Assistant primary** node. It is the concrete executor for
> `deployment-manual.md` §Phase 4 / `deployment-tasks.md` §Phase 4 / HD-04 / HD-307 /
> HD-319, and includes the KNX + dashboard pieces.
> **Links to:** `deployment-manual.md` (§Phase 4), `deployment-tasks.md` (§Phase 4),
> `smart-home.md` (KNX decision), `smart-home-failover.md` (VIP/failover),
> `home-assistant-current.md` (HA instance inventory), `network-addresses-generated.md` (IPs)
> **Linked from:** `index.md`, `deployment-manual.md`

> **Status: ✅ provisioned and live.** The Pi (`pi.kogler.si`) runs Debian 13 + Docker with
> **home-assistant-primary** (HA + keepalived MASTER on the `ha-vip` VIP), **technitium-secondary**
> and **traefik-ha** (TLS `*.kogler.si`), on the dual-home network (`pi-eth0` Home + `pi-mgmt`
> tagged-99). HA boots with zero config errors and `https://ha.kogler.si/` serves through
> `traefik-ha`. This is the **live HA instance** — the old HAOS box is gone.
>
> **Remaining on this host:** the KNX dashboard render check is an owner UI step (§4), the HA metrics
> scrape stays off until `prometheus_ha_exporter` + the `ha_api` item exist, and the **failover
> runbook** belongs to HD-04 ([smart-home-failover.md](smart-home-failover.md)).
> Authentik OIDC on `ha` is **not wanted** (owner decision, HD-310).

---

## 0. Preconditions (must hold before running)

| # | Check | How to verify |
|---|-------|---------------|
| 1 | Vault items present | `ha-vrrp_password`, `smtp_login`, `meteoblue_api`, `ha-failover_api` (standby-only) — **all required items must exist before the run** (fail-loud lookups). `ha_api` is **NOT required** for the Pi (it gates the `monitoring` role's Alloy HA-exporter scrape token via `prometheus_ha_exporter`; not a HA YAML secret). |
| 2 | Pi reachable | `ping 10.10.1.20` + `ssh ansible-admin@10.10.1.20 'echo ok'` (SSH via the 1Password SSH agent / `~/.ssh/config`). |
| 3 | Router static reservations | Pi Home `10.10.1.20` + Mgmt `10.10.99.20` bound (SSOT `network_static_hosts`). |
| 4 | Oldsrv standby config renders (cold) | `home_servers.yml` on oldsrv already renders `/opt/home-assistant-standby/` (cold; not started). Not a blocker for the Pi. |
| 5 | Review-only on `main` | Run everything from the session worktree (`homelab-wt-*`); primary is the merge station. |

> **Gate:** this is a **live deploy on a home host** that carries the production HA instance, the DNS
> secondary and the HA edge. Re-running it re-renders config and restarts HA on config change — see §5.

---

## 1. Dry-run first (must be green)

> ⚠ **`--check` can fail on stale units that no longer exist in the role.** A partial earlier run can
> leave broken timer units behind (`ha-cert-sync` / `ha-config-sync` did: invalid `OnCalendar=:0/15` plus
> a missing trailing newline). `--check` does not write, so the `systemd` enable task re-validates the old
> broken unit and fails — **check-mode failing on a unit the role no longer renders is stale host state,
> not a role bug.** Clear it, then re-check:
> `ssh ansible-admin@10.10.1.20 'sudo rm -f /etc/systemd/system/ha-cert-sync.{service,timer} /etc/systemd/system/ha-config-sync.{service,timer} && sudo systemctl daemon-reload'`
> A real run's `copy` + `daemon-reload` overwrites them anyway.

lovelace, secrets.yaml with 4 keys, keepalived master/peer), `network` (2 NM keyfiles — **will be
unchanged** if the Pi is already at SSOT), `docker`/`docker_services` created.

> ⚠ If `--check` shows the `network` role would **re-apply `pi-eth0`/`pi-mgmt`**, that is safe **only**
> while the live IPs are already correct: the connection ids are stable and the Home IP is unchanged, so
> it re-applies without switching paths. See the NM warning in §5.

---

## 2. Provision (full run)

```bash
# single host, full playbook (roles: common → ai_diag → network → nut → docker →
# home_assistant → docker_services → monitoring)
bash scripts/ansible-run.sh playbooks/raspberry_pi.yml
```

This (re)renders on the Pi:
- `network` — idempotent re-apply of the dual-home NM keyfiles (no change if already correct).
- `home_assistant` (render-first, HD-204/185) — `config/configuration.yaml` (**now with `knx:
  !include knx-entities.yaml` + `lovelace-stanovanje` + scripts**), `config/knx-entities.yaml`,
  `config/knx/StanovanjeKogler_v1_0.knxproj`, `config/lovelace/*` (4 views), **`secrets.yaml`
  (4 keys, mode 0600)** — all as **regular files** before `compose up` (HD-185 guard passes).
  **Shelly wiring (HD-320/HD-323):** the lovelace views include the 4× Shelly RGBW2 LED
  strips (`light.kuhinja`, `light.wc_4_channel_1..4`, `light.orhideje`, `light.kopalnica_2`) —
  all four devices are added with entities bound. Required for the “add by IP” flow to
  succeed: the Pi→IoT **firewall rules** (REST tcp/80 + **CoAP client udp/5683** — the Gen1 config
  flow opens a CoAP client session toward each device, without which the flow aborts
  `cannot_connect`) live in the `router` converge template; the HA CoAP **server** binds inside
  the container so `home-assistant-primary`/`-standby` compose publish `5683:5683/udp` to the
  host/VIP; the devices' CoIoT peer must point at the VIP (`ha-vip` — SSOT
  `network-addresses-generated.md`), not a stale host IP.
- `docker_services` — installs the `docker-compose@.service` unit + brings up
  `home-assistant-primary`, `technitium-secondary`, `traefik-ha` (the HD-185 first-boot guard
  asserts `./config/configuration.yaml`, `./keepalived.conf`, `./secrets.yaml` are regular files).
- `monitoring` — Alloy only (HA token file gated off until `prometheus_ha_exporter`).

Expected tail (modeled on the oldsrv/VPS converges): `ok=… changed=… failed=0` with the
`home-assistant-primary` guard green.

---

## 3. Post-provision verify (Performing the checks)

```bash
# 3.1 Containers healthy
ssh ansible-admin@10.10.1.20 'docker compose -p home-assistant-primary ps
  && docker compose -p technitium-secondary ps && docker compose -p traefik-ha ps'
# 3.2 HA web (via traefik-ha on the Pi, VIP-bound) — after DNS is wired
curl -k https://10.10.1.200:443/api/   # traefik-ha binds the VIP; expect HA API json
# 3.3 KNX + dashboard files landed
ssh ansible-admin@10.10.1.20 'ls /opt/home-assistant-primary/config/knx-entities.yaml
  /opt/home-assistant-primary/config/lovelace/ /opt/home-assistant-primary/config/knx/'
# 3.4 secrets.yaml has the 4 keys (names only — never print values)
ssh ansible-admin@10.10.1.20 'grep -oE "^[a-z_-]+:" /opt/home-assistant-primary/secrets.yaml'
# 3.5 keepalived MASTER on the Pi (normal mode)
ssh ansible-admin@10.10.1.20 'docker logs home-assistant-primary-keepalived-1 2>&1 | grep -iE "Entering|MASTER" | tail'
```

---

## 4. Owner steps (one-time, UI) — required for KNX + SSO to fully work

1. **KNX connection + project import** (HA UI, on the new instance):
   **Settings → Connectivity → KNX** → configure the connection **Tunneling** to the GIRA IP
   router (`knx_router_ip` SSOT = `knx-ip`, VLAN 20) → **import** `StanovanjeKogler_v1_0.knxproj`
   (already deployed at `/config/knx/`). The entity maps (`knx-entities.yaml`) are already
   active via YAML; the import ONLY adds Group Monitor names + `knx.telegram` destination names
   (HA does NOT auto-create control entities from the import — verified).
2. **Monitoring scrape:** create the `ha_api` 1Password item and set `prometheus_ha_exporter: true` so
   the Alloy HA exporter has a token (note: `ha_api` is a **monitoring** credential, not a HA YAML secret —
   it must **not** appear in `secrets.yaml.j2`).
3. **No Authentik OIDC on `ha`** — considered and declined: HA stays local-auth and WAN-independent
   ([smart-home-failover.md](smart-home-failover.md)), and `ha.kogler.si` is served by the Pi's own
   `traefik-ha` edge with no Forward-Auth.

---

## 5. Gotchas / live lessons (do not skip)

- **Three role bugs a `--check` would have surfaced** (each is a general Ansible trap, not a Pi quirk):
  ① a role variable computed by a lookup that runs **only on the master** crashes every client that
  references it (`nut`'s `_nut_exporter_release` → `'dict' has no attribute 'json'`) — gate the lookup and
  parse with `content | from_json`; ② `copy:` srcs resolve **relative to the role's `files/`**, so a
  template that lives in `templates/` silently 404s at copy time; ③ same trap with `remote_src: true` —
  use an absolute path. `--check` is what makes these cheap.
- **NM profile-switch is dangerous:** never `nmcli connection up <new-profile>` on the
  Pi — it deactivates the DHCP connection and drops SSH. The `network` role uses `pi-eth0`/
  `pi-mgmt` ids that persist; a re-apply is safe.
- **render-first is load-bearing (HD-185/204):** `home_assistant` MUST run before `docker_services`.
  If reordered, Docker auto-creates `config/` etc. as empty dirs and HA silently runs default
  config. The `deploy-service.yml` guard fails loud if that happens (remove the dir + re-run).
- **`ha_api` is NOT a HA secret** — the monitoring role writes `/etc/prometheus/ha_token` under
  `prometheus_ha_exporter`; it is absent from the vault pre-gate and correctly excluded from
  `secrets.yaml.j2`.
- **KNX addresses are the .knxproj SSOT, not the old maps:** `knx-entities.yaml` is generated from
  the ETS project; the old hand-maps (`docs/assets/references/old-ha/knx-*.yaml`) used stale
  addresses (e.g. `10/0/0` vs the project's `0/0/1`). Regenerate with `scripts/knx-hass-gen.py`.
- **Re-provision is idempotent** — re-running the playbook re-renders configs + restarts compose
  on config change (restart-on-config-change guard), but does NOT churn containers when nothing
  changed.

---

## 6. Success criteria

- [x] `docker compose ps` on the Pi: `home-assistant-primary` (HA + keepalived) healthy,
      `technitium-secondary` healthy, `traefik-ha` healthy
- [x] `configuration.yaml` includes `knx: !include knx-entities.yaml`, `lovelace-stanovanje`
      (YAML mode) and the radiator-timer scripts
- [x] `secrets.yaml` has `meteoblue_api`, `smtp_login`, `smtp_password`, `ha-vrrp_password`
      (mode 0600)
- [ ] KNX entities live: dashboard renders KNX lights/covers/switches/sensors (needs the UI tunneling
      config flow to `knx-ip`) — **owner step**
- [x] `ha.kogler.si` → VIP; keepalived MASTER on the Pi (priority 110), TLS verify 0
- [x] `validate-all.sh` green on the session worktree

Progress lives in `todo.md` + the owning docs; this file is the runbook, not a log.