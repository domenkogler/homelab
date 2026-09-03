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
> HD-313, and includes the KNX + dashboard pieces that landed 2026-09-03.
> **Links to:** `deployment-manual.md` (§Phase 4), `deployment-tasks.md` (§Phase 4),
> `smart-home.md` (KNX decision), `smart-home-failover.md` (VIP/failover),
> `home-assistant-current.md` (live HAOS inventory), `network-addresses-generated.md` (IPs)
> **Linked from:** `index.md`, `deployment-manual.md`

> ✅ **FULLY PROVISIONED + LIVE as of 2026-09-03 (HD-307/HD-310/HD-04).** `raspberry_pi.yml` full run
> ended `failed=0`; all three services live + verified on `pi.kogler.si`:
> Debian 13 trixie + Docker 29.7.2 + Compose v5.5.0 · network dual-home
> (`pi-eth0` Home 10.10.1.20 + `pi-mgmt` tagged-99 10.10.99.20) ·
> **home-assistant-primary** (HA 2026.8.1 + keepalived MASTER on VIP `ha-vip` 10.10.1.200) ·
> **technitium-secondary** (DNS :53 alive) · **traefik-ha** (TLS `*.kogler.si` valid,
> Verify 0). KNX/dashboard/secrets render; HA boots with **0 config errors**;
> `https://ha.kogler.si/` via traefik-ha → **302** (login). Live-fixed this session:
> docker_services enabled-set crash, first-boot guard loop_var, technitium read_only + cap_add,
> knx-entities `knx:` wrapper, meteoblue-not-in-2026.8, trusted_proxies + stale `.storage/http`,
> ha-cert-sync `dump/` exclusion + VPS rsync/key auth. **Remaining (owner steps):** KNX UI
> config-flow import, Authentik OIDC, `ha.kogler.si` DNS cutover → VIP.

---

## 0. Preconditions (must hold before running)

| # | Check | How to verify |
|---|-------|---------------|
| 1 | Vault items present | `ha-vrrp_password`, `smtp_login`, `meteoblue_api`, `ha-failover_api` (standby-only) — **all confirmed present** 2026-09-03. `ha_api` is **NOT required** for the Pi (it gates the `monitoring` role's Prometheus scrape token via `prometheus_ha_exporter`; not a HA YAML secret). |
| 2 | Pi reachable | `ping 10.10.1.20` + `ssh ansible-admin@10.10.1.20 'echo ok'` (SSH via 1Password SSH agent / `~/.ssh/config`). Verified live this session. |
| 3 | Router static reservations | Pi Home `10.10.1.20` + Mgmt `10.10.99.20` bound (SSOT `network_static_hosts`; live-verified 2026-09-01/02). |
| 4 | Oldsrv standby config renders (cold) | `home_servers.yml` on oldsrv already renders `/opt/home-assistant-standby/` (cold; not started). Not a blocker for the Pi. |
| 5 | Review-only on `main` | Run everything from the session worktree (`homelab-wt-*`); primary is the merge station. |

> **Gate:** this is a **live deploy on a home host** — the Pi currently runs an old HAOS? No — the
> Pi is **fresh Debian**; the LIVE HA instance is the **HAOS box documented in
> `home-assistant-current.md`** (still running on the old SD/HAOS, at the old IP). The new Pi is a
> parallel install. **The cutover (pointing `ha.kogler.si` clients at the new VIP) is a separate,
> owner-gated step** (`smart-home-failover.md`) — provisioning the Pi does NOT affect the live HAOS
> instance.

---

## 1. Dry-run first (must be green)

> ⚠ **Known stale-Pi-state (2026-09-03):** the partial 09-01 run left **broken timer units** on the
> Pi (`ha-cert-sync.timer` / `ha-config-sync.timer` — `OnCalendar=:0/15` invalid + no trailing newline;
> fixed in the role this session). `--check` does NOT write, so the `systemd` enable task re-validates
> the OLD broken unit and fails. **Expected in check-mode ONLY on the current Pi state.** Forward:
> (a) **clean the stale units first** (one command, no play) so `--check` is fully green:
>    `ssh ansible-admin@10.10.1.20 'sudo rm -f /etc/systemd/system/ha-cert-sync.{service,timer} /etc/systemd/system/ha-config-sync.{service,timer} && sudo systemctl daemon-reload'`
> (b) or proceed directly to step 2 — the real run's `copy` + `daemon-reload` fixes the units on the live run.

lovelace, secrets.yaml with 4 keys, keepalived master/peer), `network` (2 NM keyfiles — **will be
unchanged** if the Pi is already at SSOT), `docker`/`docker_services` created.

> ⚠ If `--check` shows the `network` role would **re-apply pi-eth0/pi-mgmt**, that's safe on a
> session where the live IPs are correct (2026-09-02 lesson: id stays `pi-eth0`/`pi-mgmt`, Home IP
> unchanged → re-apply only).

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
  **Shelly additions (HD-320):** the lovelace views now include the 4× Shelly RGBW2 LED strips
  (`light.kuhinja`, `light.wc_4_channel_1..4`, `light.orhideje`, `light.kopalnica_2`) — authored
  now, they bind after the owner adds the devices in the HA UI by IP. The Pi→IoT **firewall rule**
  (narrow new-TCP tcp/80, HD-319 pattern) lives in the `router` role / next router converge.
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
2. **Authentik native OIDC** on the `ha` route when `ha.kogler.si` is cut over (no Forward-Auth).
3. **Cutover** (owner decision — the LIVE HAOS instance still runs until then): point
   `ha.kogler.si` clients/DNS at the VIP per `smart-home-failover.md` (not part of provision).
4. Once cut over: `ha_api` 1Password item + `prometheus_ha_exporter: true` → monitoring scrape.

---

## 5. Gotchas / live lessons (do not skip)

- **Dry-run caught + fixed 3 real bugs this session (2026-09-03):** ① `nut` role `_nut_exporter_release`
  crashed on client hosts (`'dict' has no attribute 'json'` — release lookup only ran on master; now
  gated master-only + parsed `content | from_json`); ② `copy:` srcs for `knx-entities.yaml`/lovelace
  looked under role `files/` but lived in `templates/` (moved to `files/`); ③ the `remote_src: true`
  keepalived copy used a relative src (looks under `files/`) — absolute path now. All three were why
  `--check` failed before the first real provision.
- **NM profile-switch is DANGEROUS (2026-09-01):** never `nmcli connection up <new-profile>` on the
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
      `technitium-secondary` healthy, `traefik-ha` healthy.  **2026-09-03 live**
- [x] `configuration.yaml` on the Pi includes `knx: !include knx-entities.yaml`,
      `lovelace-stanovanje` (YAML mode), the radiator-timer scripts.  **2026-09-03 live**
- [x] `secrets.yaml` on the Pi has `meteoblue_api`, `smtp_login`, `smtp_password`,
      `ha-vrrp_password` (mode 0600).  **2026-09-03 live**
- [ ] KNX entities live: dashboard renders KNX lights/covers/switches/sensors (KNX connection
      configured via UI tunneling to `knx-ip`).  *(owner step — UI config flow, post-provision)*
- [x] `ha.kogler.si` → VIP after cutover; keepalived MASTER on the Pi (priority 110).
      **2026-09-03 live: VIP bound, MASTER state, TLS Verify 0** (DNS cutover still owner-gated)
- [x] `validate-all.sh` green on the session worktree (only pre-existing sync-skills drift
      allowed, owner decision pending).  **2026-09-03 green**

---

*Last updated 2026-09-03 · supercedes the stale 2026-09-01 §Phase 4 notes with the now-landed
secrets.yaml renderer + KNX-from-.knxproj + Stanovanje dashboard. Progress lives in
`deployment-tasks.md` + owning docs.*