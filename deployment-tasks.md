# Deployment Tasks — Kogler Homelab (redo from scratch)

> **Goal:** take the homelab from zero — **network redo** (flat single subnet → VLAN segmentation),
> **provision the netcup VPS as the public edge**, **fresh installs of `nas`, `pi`, `oldsrv`**, and
> **1Password-secret wiring** — to the **working homelab as desired** (single `*.kogler.si` namespace,
> HA primary+standby, observability, GitOps CD).
>
> **Authoritative build order:** derived from `docs/index.md`, `docs/deployment-preseed.md`,
> `docs/deployment-ansible.md`, `docs/network-vlans.md`, `IaC/README.md`, and
> `docs/deployment-secrets.md` (secrets single source of truth).
>
> **Status tracking for sub-tasks / difficulty:** [`todo.md`](todo.md) (HD-XX IDs) — the lifecycle SSOT.
> This file is the **ledger**: it records *what has been run* and *what is next*; it never carries the
> status story of an HD row (copying that here is what made it drift).
>
> **Where each fact lives:** progress = the `- [x]` + date checkboxes below (**`[MANUAL]`** prefixes a
> human-only step) · **as-built evidence** = the owning docs' ✅ status lines + the git commit of the
> change (the changelog/journal were frozen → `reports/`, archive-only) · **procedure** =
> [deployment-manual.md](deployment-manual.md) · **values** = IaC (`group_vars`/`host_vars`) +
> [`docs/deployment-secrets.md`](docs/deployment-secrets.md).
>
> **Human feed:** raw notes go straight into the owning-doc edit + the ledger tick + the commit — the
> `prompt-journal.md` DATA feed was retired 2026-09-01 together with the journal.

> **✅ Decisions (2026-08-16 — overriding some phase wording below):** see `todo.md` for the full
> rationale. **HD-92:** `oldsrv` stays bare-metal Debian + Docker (no Proxmox / no GPU passthrough on the
> single Phase-1 box; Proxmox deferred to HD-41/42). **HD-93:** the netcup VPS (**RS 2000 G12**, bought 2026-08-18) is **bought before go-live**
> and the **public edge (Traefik + CrowdSec + Authentik + public apps) goes on the VPS from day one**
> (fold HD-40A/40B into Phase 1) — oldsrv becomes an internal/GPU/LAN box. **The VPS carries the
> independent public tier (Authentik, Traefik, CrowdSec + co-located public apps & DBs) and is
> deployed BEFORE oldsrv/nas — it has no dependency on them** (only the GPU-backend cross-host links
> — immich-app→immich-ml, litellm→ollama — wait for the WG tunnel). **HD-135:** storage split (Immich
> originals+encoded-video → live Box,CIFS; hot data → VPS NVMe). **HD-51:** multi-axis identity model
> (persons = Authentik; shared bytes = neutral `media` owner via `storage_uid`/`storage_gid`; no human
> logins on nas; OpenCloud via Authentik OIDC).
>
---

## 0. Prerequisites & Global Secrets

> **Everything runs from the management laptop (Phase 0).** The `Homelab-ansible` 1Password vault is the
> **only** secrets backend — Ansible lookups resolve items at render time, keys are served on demand
> by the 1Password SSH agent. No secret is ever committed to Git.

### 1Password items — human-gated (not auto-generated)

> The 1Password item catalog SSOT is [`docs/deployment-secrets.md`](docs/deployment-secrets.md) — the canonical list
> of ALL items (generated + human + derived). This section lists **only the human-gated items**: external values,
> manual/deploy-provisioned tokens or keys, break-glass vaults, and connection refs. Auto-generatable items are
> seeded by [`scripts/provision-secrets.py`](scripts/provision-secrets.py) and are **not repeated here**.
> `✓` = item already present. Ansible-consumed vs account/ref-only are split into two tables below.
> **HD-205 reconciliation:** `network-snmp_api`'s *value* is catalog-`--create`d (auto-generated), so it is not a
> human-gated *value* — but its device-side `/snmp community` apply is a manual HD-03 step, so it sits in the
> provisioner's `NOT_AUTO_ROTATABLE` guard. It is kept in table A only as a "needed before the phase" reminder.

#### A) Ansible-consumed secrets (rendered into IaC — need a value in `Homelab-ansible` before the phase runs)

> `✓` = owner-verified present. **`In OP?` was re-audited 2026-09-19** against what the live services
> actually render: with the fail-loud rule (no `default('')`), an item consumed by an enabled + live service
> cannot be missing — so the old `✗` marks on `authentik_login` / `forgejo_api` / `headscale_api` /
> `signal_api` were wrong (their services are live). `ha_api` is the one genuinely absent item: it is gated
> behind `prometheus_ha_exporter: false` (`roles/monitoring/tasks/main.yml`) and lands only with HD-14.
> **Placeholder-then-swap class:** the catalog seeds a random value so the render can run; the REAL value is
> minted by the app on first boot and a human overwrites the item (`forgejo_api`, `sonarr_api`,
> `radarr_api`, `lidarr_api`, `slskd_login`, `soulseek_api`).
> `scripts/check-vault-items.sh --strict` is the authority on the full required set — run it, not this table.

| Item | type → `field=` | First needed in | In OP? |
|------|-----------------|-----------------|--------|
| **Phase 0 — runner** | | | |
| `ai_ssh` | ssh → `private_key`/`public_key` | Phase 0 | ✓ |
| `ansible-admin_ssh` | ssh → `private_key`/`public_key` | Phase 0 | ✓ |
| `laptop-domen_ssh` | ssh → `private_key`/`public_key` | Phase 0 (bootstrap key on laptop) | ✓ |
| `op_api` | api → `credential` (1Password SA token, **read**-scoped) | Phase 0 — `scripts/bootstrap-runner.sh` stores it as the runner token | ✓ |
| `op-write_api` | api → `credential` (**read+write** SA token; renamed 2026-09-19 from `vps-op-write_api`) | Phase 1 — the docker_services pre-pass deploys it to `/etc/op/provision-token` for the secret-egress glue | ✓ |
| **Phase 1 — VPS edge** | | | |
| `Hertzner-SB-Data` | — (connection ref; CIFS/SMB/WebDAV live box, `cifs` role) | Phase 1 | ✓ |
| `cloudflare_api` | api → `credential` (ACME DNS-01 wildcard; **exact-IP** token filter, never CIDR) | Phase 1 — the VPS Traefik is the ONLY ACME issuer | ✓ |
| `authentik_login` | login → `password` (bootstrap admin `akadmin`) | Phase 1 — Authentik is a VPS service (live since 2026-08-22) | ✓ |
| `grafana_login` | login → `password` (admin) | Phase 1 | ✓ |
| `forgejo_api` | api → `credential` (Forgejo token for Renovate) | Phase 1 — **placeholder-then-swap**: mint it in the Forgejo UI after the wizard (manual §1.7), then overwrite | ✓ |
| `headscale_api` | api → `credential` (OIDC client secret; `username`=client id) | Phase 1 — headscale/headplane are VPS services (`vpn.kogler.si`) | ✓ |
| `tailscale-sidecar_api` | api → `credential` (headscale preauth key, `tag:sidecar`) | Phase 1 — **fail-loud** if absent when `traefik-tailnet` renders | ✓ |
| `crowdsec-bouncer_api` | api → `credential` (CrowdSec LAPI bouncer key) | Phase 1 — regenerate + re-store if the crowdsec volume is fresh | ✓ |
| `technitium_login` | login → `password` (`username` = admin) | Phase 1 — **hard gate for the DNS seed**: the app seeds `admin`/`admin`, so set the admin to THIS value through the `changePassword` API **before** the first `technitium-seed` run, on all 3 instances | ✓ |
| `technitium_api` | api → `credential` | **Declared prerequisite only** — listed in `_service_vault_items.technitium` (so the scanner demands it) while no task looks it up. Wire it or drop the entry. | ✓ |
| **Phase 1.5 — network redo** | | | |
| `mikrotik-admin_login` | login → `password` | Phase 1.5 (router + switch + APs, shared across the gear) | ✓ |
| `network-snmp_api` | api → `credential` (SNMP RO community; catalog-created once, the device `/snmp community` is a manual step — HD-205, not auto-rotatable) | Phase 1.5 | ✓ |
| `pppoe_login` | login → `password` (`username`=PPPoE user) | Phase 1.5 | ✓ |
| `wg_password` | password → `password` (**WireGuard S2S private key, ROUTER side** — a `wg genkey` value; the auto-tool never writes it) | Phase 1.5 | ✓ |
| `wg_password_vps` | password → `password` (**WireGuard S2S private key, VPS side** — HD-285: each side holds a DISTINCT keypair; with a shared key the router tries to handshake with itself and no tunnel ever forms) | Phase 1.5 (and the VPS `wireguard` role) | ✓ |
| `wifi-kogler_password` / `wifi-kogler-iot_password` / `wifi-kogler-guest_password` | password → `password` | Phase 1.5 — **3 live SSIDs**; the `-iot-wan` and `-kids` items are tombstones (both SSIDs deleted 2026-09-03, HD-312) | ✓ |
| **Phase 2 — nas** | | | |
| `smtp_login` | login → `password` (**SMTP relay, HD-54 SMTP2Go** — shared by Grafana + NUT; `username`=SMTP user/notify email) | Phase 2 | ✓ |
| **Phase 3 — oldsrv** | | | |
| `signal_api` | api → `credential` (`username`=phone number) | Phase 3 — signal-cli-rest-api (live) | ✓ |
| `sonarr_api` / `radarr_api` / `lidarr_api` | api → `credential` | Phase 3 — **placeholder-then-swap**: copy each instance's real `config.xml` ApiKey after first boot (recyclarr reads them) | ✓ |
| `slskd_login` / `soulseek_api` / `privado-vpn_api` | login / api | Phase 3 — slskd + its gluetun sidecar; `privado-vpn_api` is the owner-supplied PrivadoVPN WireGuard client key | ✓ |
| `ha-vrrp_password` | password → `password` (keepalived VRRP auth) | Phase 3/4 — shared secret of the HA pair | ✓ |
| **Phase 4 — pi** | | | |
| `ha_api` | api → `credential` (HA long-lived token) | ⏳ **absent by design** — consumed only by the HA-exporter bearer, gated behind `prometheus_ha_exporter: false`; seed it together with HD-14 | ✗ |
| **spark** | | | |
| `spark-llm_api` | api → `credential` (vLLM `--api-key` = the engine bearer) | spark phase (`spark-ai`) — the SAME string is sent upstream by BOTH LiteLLM instances as `OPENAI_API_KEY`, so rotation is a coupled window: `scripts/rotate-spark-llm-key.sh` + [deployment-ai-stack-secrets.md](docs/deployment-ai-stack-secrets.md) §4a | ✓ |

**Deploy-provisioned, not hand-seeded** (do not hunt for these before a converge):
`kopia-server_fingerprint` (written by the `kopia-fingerprint-sync` task from the live cert),
`authentik-ldap_bind` + the OIDC client-credential items (minted by the Authentik secret-egress glue),
and the LiteLLM virtual keys (bootstrap glue — currently `bootstrap_keys: false`).

**`op_api` as a Forgejo-runner secret (HD-396, open):** the Phase 5 premise "the deploy runner holds
`op_api`" is **unverified from the repo** — no `.forgejo/` workflow exists here and no IaC file reads the
item as a runner token. Confirm on the Forgejo side: if the runner exists, renew its token after the
2026-09-19 SA rotation (or its vault access 403s); if it does not, that premise is folklore and goes.

#### B) Account / connection refs — NOT consumed by Ansible (human maintenance / break-glass)

> These live in the **Homelab (human)** vault — deliberately NOT in
> `Homelab-ansible`, so the Ansible Service Account cannot see them (least-access). They are not consumed
> by Ansible lookups; they gate human operations only. `✓` = owner-verified present (an SA-scoped vault
> audit cannot check this table).

| Item | What it is | Vault | In OP? |
|------|-------------------------|-------|--------|
| `netcup-ccp_login` | netcup Customer Control Panel login (billing/orders) | Homelab (human) vault | ✓ |
| `netcup-scp_login` | netcup Server Control Panel login (reboot/OS reset) | Homelab (human) vault | ✓ |
| `netcup-vps_login` | netcup root/OS credential | Homelab (human) vault *(owner decision 2026-08-22 — consolidated with the other netcup-* logins; former break-glass-vault plan dropped)* | ✓ |
| `Hertzner-SB-Backup` | Hetzner backup Box SSH/SFTP connection ref (kopia, no password) | Homelab (human) vault | ✓ |
| `spark_login` | DGX Spark (GB10) first-boot `admin` account — the DGX OS setup-wizard password; console/KVM break-glass on a headless box. Not consumed by Ansible (the automation identity is `ansible-admin`). | Homelab (human) vault | ✓ |
| `GitHub auth` / `GitHub sign` | the laptop's GitHub SSH + commit-signing keys, served by the 1Password **desktop** app over the Windows named pipe (HD-265) | Homelab (human) vault | ✓ |

> **Provisioning note:** the generated items — the DB items `authentik_db`/`opencloud_db`/`immich_db`/`forgejo_db`/
> `qdrant_db`/`onlyoffice_db`/`zipline_db`/`litellm_db`, the secrets `authentik_password`/`nut_password`/
> `nut-exporter_password`/`kopia_password`/`ha-vrrp_password`/`n8n_password`/`matrix_password`/
> `opencloud-collab_password`/`openwebui_secret`/`zipline_password`, and the API creds `litellm_api`/
> `immich-ml-internal_api`/`n8n-webhook_api`/`signal-internal_api`/`kopia-server-internal_api`/
> `victoria-metrics_api`/`victoria-logs_api`/`network-snmp_api`/`mikrotik-logpipe_api` — are seeded automatically
> into `Homelab-ansible` by the provisioner above, so they are deliberately **absent** from the human-gated
> tables. Two exceptions (manual keys): `wg_password` + `wg_password_vps` stay out of the auto-catalog because
> WireGuard needs a real `wg genkey` private key on each side — provision both by hand.

---

## Phase 0 — Bootstrap the Management Laptop

> **Depends on:** nothing (first action).
> **1Password prerequisites:** `laptop-domen_ssh`, `ansible-admin_ssh`, `ai_ssh`, `op_api`, and
> `kopia_password` (seed `password`-type item read by `test-1password.yml`) all exist in `Homelab-ansible`.
> **Continuation:** once verified, you can run Ansible and the 1Password test; nothing else.
> **Step-by-step runbook:** [deployment-manual.md](deployment-manual.md) §Phase 0 (true-zero rebuild incl. canonical key restore).

1. Clone the repo; run the runner bootstrap (relocated to `scripts/`, HD-256):
   ```bash
   bash scripts/bootstrap-runner.sh
   source ~/.bashrc
   ```
2. Verify tooling: `ansible --version`, `op --version`.
3. Set up the 1Password SSH agent + `~/.ssh/config` (see `docs/deployment-secrets.md`).
4. Verify 1Password connectivity:
   ```bash
   ansible-playbook -i IaC/ansible/inventory.ini IaC/ansible/test-1password.yml
   ```
   (reads `kopia_password` — item must exist, `<service>_db` placeholders don't matter here.)

**Verify:** test-1password.yml prints the fetched password; laptop can `ssh nas` via the agent.

---

## Phase 1 — VPS Public Edge (netcup `vps.kogler.si`) — the independent public tier

> **Depends on:** Phase 0 (laptop + 1Password agent). Requires **public access** to netcup SCP + the VPS public IP;
> the LAN/network work (Phase 1.5) is **not** a prerequisite — this tier is public (netcup → internet → Cloudflare), not LAN.
> The VPS hosts the **self-contained public tier first**: Traefik + CrowdSec + Authentik (+ their co-located Postgres/Redis)
> and the public apps whose DBs live on VPS NVMe. It has **no dependency on oldsrv or nas**. **Needed before Phase 2.**
> **1Password prerequisites (new this phase):** `netcup-ccp_login`, `netcup-scp_login`, `netcup-vps_login` (Homelab (human) vault),
> `Hertzner-SB-Data`, `Hertzner-SB-Backup`, `op-write_api`, `cloudflare_api`, `authentik_login`, `grafana_login`,
> `forgejo_api`, `headscale_api`, `tailscale-sidecar_api`, `crowdsec-bouncer_api` and **`technitium_login`** (the
> app boots with `admin`/`admin` — re-point it to the vault value via the `changePassword` API before the first
> `technitium-seed` run), plus the catalog DB items — full list in **§0 table A**. `wg_password_vps` is needed by
> the `wireguard` role played in this same playbook. ~~"items listed in Phase 3"~~ — those were VPS services all along.
> **Continuation:** once the edge + Authentik are live, the LAN track (Phase 1.5 network redo → Phase 2 nas → Phase 3 oldsrv)
> brings up the internal/GPU backends; the WG S2S tunnel (Phase 1.5 / HD-03 WG VPS peer) then lets the VPS reach them.
> **Step-by-step runbook:** [deployment-manual.md](deployment-manual.md) §Phase 0.5 (re-provisioning; §Phase 1 lands after the first green Verify block).

- [x] **[MANUAL]** **Provision VPS (netcup SCP)** — ✅ done 2026-08-18; Custom Script confirmed applied (first key-auth login verified 2026-08-21; owning-doc + commit evidence). netcup boots its **pre-built Debian 13 image**; the operative install hook
   is the **Custom Script** (netcup SCP field) = **`IaC/host/vps/post_install.sh`** (pasted as `*_with_secrets.sh`;
   no `ai-debug`, `AllowUsers ansible-admin` only — public box). **NOTE:** the `d-i` preseed lines
   (`IaC/host/vps/preseed.cfg`) do **NOT** run on netcup's image — that file is a reference/fallback only
   (see `deployment-preseed.md` → VPS Deviations). The `*_with_secrets.sh` injects the real SSH keys;
   root login disabled. Single 512 GB NVMe root (ext4, no ZFS).
   - [x] **[MANUAL]** **Re-provision with the HD-208-fixed script** (reinstall) — ✅ done 2026-08-22: reinstalled via Custom Script (Minimal image), then console-remediated after the HD-209 pubkey-doubling bug (template fixed `a97783d`); first-boot verified — `sshd -T` = **no/no/3** from the drop-in alone, sudoers NOPASSWD, both identities authorized (owning-doc ✅ + commit evidence).
- [x] **Ansible** — ✅ **first green 2026-08-22** (stack Up; re-converged many times since — the VPS carries
   the whole public tier + the observability backend). `ansible-playbook -i inventory.ini playbooks/vps.yml`:
   `common` → `docker` → **`vps-hardening`** (HD-154: fail2ban + nftables default-deny + docker daemon) →
   `network` (static public IP per SSOT) → `cifs` → `wireguard` (conditional) → `docker_services` →
   `monitoring`.
- [x] **Mandatory hardening (HD-154, enforced by the `vps-hardening` role — NOT optional prose)** — role-deployed
   and verified on first boot; re-asserted by every later converge:
   - **SSH:** `PasswordAuthentication no`, `PermitRootLogin no`, `MaxAuthTries 3`, `AllowUsers ansible-admin` only (post_install.sh + role assert).
   - **fail2ban:** SSH jail (`maxretry 3`) + `http-auth` jail for public login pages (n8n/Grafana/Forgejo) — role-installed + enabled.
   - **Firewall (nftables):** default-deny inbound; allow only `:22` (SSH/Ansible — added 2026-08-22 after a live lockout) + `:443` (Traefik) + `:51820` (WG S2S) + loopback + established/related; ICMP echo limited. Role-deployed `/etc/nftables.conf`. ⚠ `:53` (Technitium publish) is **source-restricted at the FORWARD chain** (tailnet CGNAT + home-WAN allow-list), not the input chain — a Docker published port bypasses input filtering (HD-317 exposure fix, `network-dns.md`).
   - **Docker daemon:** `iptables: true`, `userland-proxy: false`, `live-restore: true`, capped json-file logs; no public container `privileged` / host-net by compose policy.
   - **SSO admission:** root disabled, per-host keys only (Domen + Ansible), no `ai-debug` on a public box.
- [x] **Edge tier + the rest of the public catalog** — ✅ issued since 2026-08-22, catalog grown since. `group_vars/vps.yml` is the loop source of truth (see
   [`docs/services-inventory-generated.md`](docs/services-inventory-generated.md)); Traefik issues the wildcard
   `*.kogler.si` + `*.ts.kogler.si` certs via ACME **DNS-01** (`cloudflare_api`) and `certs-rename.sh` publishes
   the pairs for the consumers. The `dns.yml` control-plane playbook maintains the public records
   (`vps` A/AAAA + each app CNAME; SSOT `roles/cloudflare_dns/vars/main.yml`).
- [x] **Live Box CIFS mount** — ✅ 2026-08-22. The `cifs` role mounts `//u653411.your-storagebox.de/backup`
   (`Hertzner-SB-Data`) at `/mnt/storagebox` (0600 creds from 1Password) for Immich originals + encoded-video +
   OpenCloud files + the Navidrome library (HD-135 storage split). Verify `mountpoint --q /mnt/storagebox`.
- [x] **Cross-host links that had to wait for the WG S2S tunnel** — ✅ 2026-09-08: `immich-app→immich-ml` came up
   ✅ 2026-09-08 (VPS server health-checks the oldsrv ML endpoint over WG). `litellm→ollama` is history: rerank
   and STT left Ollama entirely (decisions #25/#27) and generation moved to spark (`llm.kogler.si`), reached
   over WG by the VPS LiteLLM.

**Verify:**
- `sso.kogler.si` (Authentik) reachable publicly through the VPS Traefik with the wildcard cert; crowdsec decision active.
- **Authentik OAuth2 Blueprint** — `ks-oidc.yml` + `ks-forward-auth.yml` import on the pinned release and the secret-egress glue seeds the client creds (8 OIDC apps + 9 edge providers).
- `vps` A/AAAA records live at Cloudflare (via `dns.yml`); `ansible-admin` SSH works with the agent.
- **Hardening verified (HD-154):** `fail2ban-client status sshd` shows the SSH jail active; `nft list ruleset` shows the default-deny input chain with `:22`/`:443`/`:51820` accepts; `sshd -T | grep -E 'maxauthtries|passwordauthentication|permitrootlogin'` = 3/no/no; `docker info` shows `userland-proxy=false` + capped log driver.
- Live Box CIFS mount returns data; VPS NVMe under 80%.

**Deploy-gated verification (Phase 1 — VPS):** every line is an open `todo.md` row; a row that closed was deleted
here (its record is the owning doc + the commit). Run `todo.md` for the full status story.

- [ ] **HD-101** — Open Web UI: verify the SSO → Authentik round-trip, then a LiteLLM completion + RAG at the pin. · [services-ai.md](docs/services-ai.md)
- [ ] **HD-402** — Docling OCR engine: the bench is blocked on **two dependencies**, not a measurement — (a) `rapidocr` is not installed in the pinned `docling-serve-cpu:2.118.0` image (EasyOCR 1.7.2 is; the container sets no OCR env), though the **RapidOcr PP-OCRv6 weights are already baked into the image**; (b) the model bind cannot receive any runtime fetch (`/models` empty + root-owned vs uid 1001 → `PermissionError: /models/hub`), so `bind_owner_uid: "1001"` (or an `HF_HOME` repoint) comes first. Then the bench. Free lever meanwhile: `do_ocr=false` per request for born-digital PDFs (call-site, not service env). · [services-ai.md](docs/services-ai.md)
- [ ] **HD-421** — ⏳ Docling: make the model cache writable before any engine change. `/models` is empty + root-owned while the container runs as uid 1001 ⇒ a runtime fetch dies `PermissionError: /models/hub`; the served pipeline works only because its weights are baked into the pinned image. Fix: `bind_owner_uid: "1001"` on the registry entry (or repoint `HF_HOME` / `DOCLING_SERVE_ARTIFACTS_PATH` at the bind) + prove a fetch lands on the bind. Until then any engine change (HD-402) or a pin bump that drops a baked weight is dead on arrival. [todo.md](todo.md) · [services-ai.md](docs/services-ai.md) §Where the model weights actually live
- [ ] **HD-103** — Docling: live-verify a **real** Slovenian scan conversion (the multi-GB model pull is a non-event — weights are baked into the pinned image; the `/models` bind is decorative). · [services-ai.md](docs/services-ai.md)
- [ ] **HD-104** — OpenClaw: `openclaw onboard` → schema-valid `openclaw.json`, then the OWUI ↔ OpenClaw ↔ OpenCloud WebDAV round-trip (folds in **HD-160**'s remaining half). · [services-ai.md](docs/services-ai.md)
- [ ] **HD-159** — blackbox liveness: prove the `wg-s2s-down` Critical rule actually fires on a `wg down` test. · [observability.md](docs/observability.md)
- [ ] **HD-47** — Matrix public records + `_matrix` well-known/SRV delegation (matrix + Element are live, so federation is one DNS step away). · [services-traefik.md](docs/services-traefik.md)
- [ ] **HD-122** — Matrix federation hardening: live-verify profile endpoints require auth. · [services-matrix.md](docs/services-matrix.md)
- [ ] **HD-268** — Qdrant as the vector store: re-index + OKF wiki skeletons (the PGVector swap is long done; the re-index cutover is not). · [services-ai.md](docs/services-ai.md)
- [ ] **HD-412** — RustDesk server (VPS): seed the `rustdesk_login` keypair (step 1–3 of the runbook), flip the registry row `enabled: true`, converge `--tags hardening,docker_services,rustdesk-server`, then verify the caps + the two sessions. `[MANUAL]` for the vault write + the human-gated first apply. · [deployment-manual.md](deployment-manual.md) §1.11 · [services-admin.md](docs/services-admin.md)
- [x] **HD-240** — grafana SSO round-trip: ✅ traefik edge IP pinned to the whitelist entry; ✅ owner mapped as Grafana Admin; ✅ **[MANUAL]** sso-dashboard → stats.kogler.si lands IN Grafana — **verified by owner 2026-08-25**. · [observability.md](docs/observability.md)

**Also open on this host** (each is a live `todo.md` row; they were invisible here before 2026-09-19):
- [ ] **HD-141 / HD-147** — the Authentik OIDC epic (Blueprint + secret-egress glue) and its live deploy-verify tail (`ai`/`vpn` verified; the remaining apps are not). · [deployment-oidc.md](docs/deployment-oidc.md)
- [ ] **HD-194** — `sso` route edge middleware: decided + done, the enforcement ride-along is the open tail. · [services-traefik.md](docs/services-traefik.md)
- [ ] **HD-230** — Phase-1 wave-2 corrective batch (pairdrop PUBLIC, blueprint one-shot-apply, onlyoffice `cap_add`, db-backup boot-race delay). · [deployment-compose.md](docs/deployment-compose.md)
- [ ] **HD-280** — fail2ban: add the Traefik `accesslog` + a Traefik-aware filter (deployed + live-verified; row open for the remainder). · [deployment-compose.md](docs/deployment-compose.md)
- [ ] **HD-287** — `cap_drop: ALL` + targeted `cap_add` on immich-ml (rescoped after Ollama left the host). · [security.md](docs/security.md)
- [ ] **HD-112** — Zipline public bin + private OIDC share (`bin.kogler.si`). · [services-utilities.md](docs/services-utilities.md)
- [ ] **HD-111** — Office MCP via Open WebUI (`ppt-mcp` first). · [services-ai.md](docs/services-ai.md)
- [ ] **HD-354** — Navidrome on VPS + the live Storage Box. · [services-media.md](docs/services-media.md)
- [ ] **HD-356** — the LiteLLM split (family instance on the VPS vs the LAN instance). · [services-ai.md](docs/services-ai.md)
- [ ] **HD-397** — off-LAN access parity: landed + verified off-LAN; the **on-site** pass is the open leg. · [services-vps.md](docs/services-vps.md)
- [ ] **HD-316** — the Homepage family launchpad (real app dashboard + a separate technical section). · [services.md](docs/services.md)
---

## Phase 1a — Parallel Track: NAS Pools + Host Installs (before / during Phase 1.5)

> **Decision (HD-215, 2026-08-22):** the long-pole destructive disk work and the host OS reinstalls
> start in parallel with Phase 1 completion — they carry zero network dependency.
> **Hard line:** both hosts stay OUT of the Ansible configuration loop until Phase 1.5 lands —
> their SSOT addresses include Mgmt-VLAN 99 IPs that don't exist before the router redo.
> **Depends on:** Phase 0 (runner + vault identities). **Feeds:** Phase 2 (the storage role is
> import-only — pools must already exist), HD-207, HD-128.
> **Execution runbook:** [deployment-manual.md §Phase 1a](deployment-manual.md) — official path is interactive install + catch-up bootstrap (preseed automation deferred).

| Work | Why it can precede 1.5 |
|------|------------------------|
| **NAS Pool-Creation Runbook (HD-207)** — bulk RAIDZ2 → migrate the legacy pool off the IronWolf into `bulk/migrate` → tank mirror | Purely local disk work, human-gated (destructive), and the longest pole in the whole homelab (hours of copying/resilvering). Zero network dependency. |
| **OS installs of nas/oldsrv via preseed media** | Both preseeds are DHCP-based (`netcfg` auto, no static lines) → the boxes come up fine on today's flat LAN, which IS the future VLAN-10 Home subnet (SSOT: [`network-addresses-generated.md`](docs/network-addresses-generated.md)) — planned Home IPs stay valid across the cutover. |
| **oldsrv NVMe by-id capture** | HD-128 still waits for real `/dev/disk/by-id/nvme-…` values "at first pool create" — doing the install early unblocks that IaC fill-in. |

- [x] **[MANUAL]** Execute the Pool-Creation Runbook ([docs/hardware-nas.md](docs/hardware-nas.md)) — bulk RAIDZ2 first, legacy pool migrated into `bulk/migrate`, tank mirror; export both pools before the nas installer boots. ✅ **2026-08-23** — executed on the running Debian (gen8): SMART all-pass pre-check (report archived); legacy pool = `new-pool` (~1.96 T) sent `-R` into `bulk/migrate` (57 snapshots, tree-diff + subtree diff clean); second pool `backup` destroyed as disposable (owner decision b); `tank` mirror ONLINE; both pools EXPORTED — installer-ready. As-built: [deployment-tasks.md §Phase 1a](deployment-tasks.md) + [hardware-nas.md](docs/hardware-nas.md) (ledger + commit evidence).
- [x] **[MANUAL]** Reinstall oldsrv via preseed media (retires the rarely-used Windows 10 install); capture the real NVMe by-ids and fill HD-128 (`storage_nvme_data_by_id`). ✅ **2026-08-23** — installed interactively (manual partitioning; see [hardware-oldsrv.md](docs/hardware-oldsrv.md) + commit for why automation was bypassed); by-ids verified 2026-08-22 (HD-128 closed); catch-up via `bootstrap-oldsrv.sh` (ansible-admin/ai-debug/keys/hardening) — `ssh ansible-admin@oldsrv` key-only confirmed. **Hold rule active:** no Ansible runs against oldsrv until Phase 1.5 cutover.
- [x] **[MANUAL]** Reinstall nas via preseed media (boot-disk/USB by-ids already pinned, HD-206). ✅ **2026-08-23** — FULLY AUTOMATED install succeeded hands-off (Automated grub entry, ZERO interactive questions; early_command resolved the Crucial by-id, GRUB landed on the Generic_Flash_Disk carrier pin, late_command ran the keyed post_install) — preseed path re-proven (oldsrv had gone interactive); SanDisk booted explicitly via iLO one-time menu, pulled before reboot; Generic carrier stays (HD-226 roles). Verified post-install: `ssh ansible-admin@nas` key-only, `domen@nas` refused (AllowUsers), hostname `nas`, both Crucial by-id forms resolve, six data-disk by-ids intact (`zfs_member` labels survived untouched — pools stay exported for the Phase-2 import-only role), hardening drop-in + admin keys live. As-built: [deployment-tasks.md §Phase 1a](deployment-tasks.md) + [hardware-nas.md](docs/hardware-nas.md) (ledger + commit). **Hold rule active:** no Ansible runs against nas until Phase 1.5 cutover.
- [x] **Hold removed 2026-09-03** — the "no Ansible against nas/oldsrv until Phase 1.5" rule expired with the cutover: first Ansible contact ran on **nas** (`storage.yml`, 2026-09-03) and then on **oldsrv** (Phase 3, 2026-09-08). Both hosts are on their pinned SSOT addresses now; the note above is history.

## Phase 1.5 — Network Redo from Scratch (Router RB4011 + Switch CRS328)

> **This is the irreversible cutover**: the current **flat single-subnet** network is replaced by
> **VLAN segmentation** per `docs/network-vlans.md`. Until the router is rebuilt, the whole home is
> offline — do this at a planned maintenance window. Phases 2–3 (nas/oldsrv fresh installs) depend on it.
>
> **Depends on:** Phase 0 (laptop + 1Password agent), Phase 1 (VPS edge + Authentik live).
> **1Password prerequisites:** `mikrotik-admin_login` (login→`password`), `pppoe_login`,
> `wg_password` **+ `wg_password_vps`** (HD-285: two distinct `wg genkey` values — one per side), the three
> live `wifi-kogler*_password` SSIDs, `network-snmp_api` (manual device `/snmp community` re-apply).
> **Continuation:** next phases require the router serving DHCP on VLANs 10 + 99 (and 20/30/40/50 as configured).
> **VLAN 21 is deleted** (HD-325, 2026-09-04) — cloud-IoT lives on VLAN 20 behind the per-device `wan_allow` flag.

- [x] **[MANUAL]** **Router baseline** — ✅ **cut over 2026-09-02** (factory-reset + `run-after-reset`,
     then handed to the Ansible `router` role; re-converged + delta-applied since). Apply `IaC/router/rb4011_initial.rsc`
     (rendered from `IaC/router/templates/*.rsc.j2` — never hand-edit the rendered file):
   - VLANs: 10 Home, 20 IoT, 30 Guest, 40 Kids, 50 Media, 99 Management (VLAN 21 deleted HD-325)
   - Inter-VLAN firewall (default-deny; address-lists `trusted-ha`/`trusted-admin`; the UPS web rule on 99)
   - DHCP per VLAN (option 15 `domain=kogler.si`), WireGuard S2S (**two distinct keys**: `wg_password` router side +
     `wg_password_vps` VPS side — HD-285)
   - CAPsMAN: SSIDs `Kogler` + `Kogler IOT` (2.4 GHz) + `Kogler guest` (5 GHz), `local-forwarding=no`
     (IOT-WAN/Kids SSIDs deleted HD-312; VLAN 21 deleted HD-325; per-SSID band split in `routeros_capsman_ssids`)
   - DNS: **3-instance Technitium HA** — VPS **primary** (resolver = VPS public IP), oldsrv **secondary**,
     Pi **tertiary**; DHCP hands all three and is **Pi-first on VLAN 10** (HD-334). Spec: `docs/network-dns.md`
   - Config is stored/versioned via `docs/network-ops.md` (render → `/import` over SSH is the apply path).
- [x] **[MANUAL]** **Switch + APs** — ✅ 2026-09-02 (bootstrap `.rsc` per device) → CRS328 as L2 trunk +
     PoE (`auto-on`, never `on`), APs in CAP mode with per-AP rendered identities (`ap-spalnica` / `ap-dnevna` /
     `ap-spare`). ✅ **CAPsMAN steady-state imported + verified 2026-09-02/03** and switch bridge-VLAN membership
     completed 2026-09-03 (wifi VLANs tagged on the AP ports) + 2026-09-04 (access-port untagged membership, HD-328).
     ⚠ **Flash-persistence (HD-304):** the `.pub` files go in `flash/` on switch/APs — device-root files are wiped on reboot.
- [x] **[MANUAL]** **Migrate devices** — ✅ 2026-09-03/04 per-VLAN as leases turned over; UPS NIC moved to
     IoT VLAN 20 (HD-338), AP wired ports locked down off-Mgmt (HD-89, live 2026-09-08).

**Verify:**
- `ip addr` on the router shows all VLAN interfaces up; DHCP issues leases on each VLAN.
- Inter-VLAN reachability matches the firewall matrix (Home→99 management from `trusted-admin` only;
  Home→IoT gated to `trusted-ha` = oldsrv + ha-vip, **nas excluded**).
- CAPsMAN: manager `enabled=yes`, provisioning rows create dynamic CAP entries, registration-table fills per SSID.
- WireGuard handshake established + **both directions carry traffic** (`sudo wg show wg-s2s transfer`).
- Rollback: the previous flat config is preserved as `rb4011_flat_backup.rsc` before any reset.

**Deploy-gated verification (Phase 1.5):**
- [ ] residual (Pkg B, `todo.md` §2.1a) — the `trusted-ha` template correction of 2026-09-10 still needs one
      render + `/import` of the converge to make the live rule set match the SSOT.

---

## Phase 2 — NAS Fresh Install + Storage + UPS Master (`nas.kogler.si`)

> **Depends on:** Phase 1 (VPS edge + Authentik live), Phase 1a (pools created + hosts installed), Phase 1.5 (router VLANs + DHCP). NAS rides **VLAN 10 (Home) untagged + VLAN 99 (Mgmt) tagged** on one NIC (like oldsrv/pi/spark).
> **1Password prerequisites (new this phase):** `nut_password` (password→`password`), `smtp_login`
> (login; `username`=notify email/SMTP user, `password`=SMTP pass). SSH items from Phase 0 are injected
> by `post_install.sh`. **No Docker on NAS.**
> **Continuation:** the NAS is the **NUT master** — `oldsrv` and `pi` are NUT clients and depend on it.

- [x] **[MANUAL]** **Preseed install** — ✅ done 2026-08-23 (Phase 1a); boot the HP MicroServer from `IaC/host/nas/preseed.cfg`
   (single-SSD boot; ZFS HDDs **not touched** by preseed) + shared `IaC/host/post_install.sh`
   (ansible-admin + ai-debug keys, sshd hardening).
- [x] **Ansible** — ✅ **EXECUTED 2026-09-03 (failed=0):** `ansible-playbook -i inventory.ini playbooks/storage.yml`:
   `common` → `ai_diag` → `network` (client-id=MAC on 10.10.1.10 + tagged-99 netd units; HD-314) → `storage` (ZFS import, datasets+props, NFS exports, sanoid/syncoid, Samba, exporters) → `nut` (mode=master, LIVE) → `cockpit` (cockpit-storaged on trixie) → `monitoring` (per-node Alloy, apt — no Docker on nas).
- [x] **NUT master** — ✅ LIVE 2026-09-03 (client auth + the notify/shutdown layer fixed 2026-09-08/09,
   see HD-06): `nut-server` + `usbhid-ups` (PowerWalker USB), `upsd` on the intra-VLAN `nas:3493` (no inter-VLAN
   rule needed), `nut_exporter` as a host binary (:9199), `upssched-cmd` email/Signal notify (`smtp_login`).
- [x] **Storage** — ✅ 2026-09-03: pools already created by the one-time bootstrap runbook (`docs/hardware-nas.md` → Pool-Creation Runbook; role is import-only for tank/bulk); Ansible imports them + creates datasets, exports (NFS/SMB); mount layout per `docs/hardware-nas.md`.

**Verify:**
- `zpool status` healthy; `upsc powerwalker@nas` returns live UPS data.
- `nut_exporter` scrapable on :9199; cockpit reachable at `cockpit-nas.kogler.si` (Traefik file-provider route).

**Deploy-gated verification (Phase 2):**
- [ ] **HD-06** — **[MANUAL, owner]** the one thing left in the UPS lane: a short power-pull → poweroff + WoL
      wake **end-to-end** re-test (the full defect fix set deployed to nas/oldsrv/pi 2026-09-09; the 2026-09-09
      drill is what found those three latent defects). · [hardware-ups.md](docs/hardware-ups.md)
- [ ] **HD-360** — Samba Authentik-as-LDAP, VPS side (the deploy-gated remainder of the old HD-132): declare the
      LDAP provider + `svc_samba` in the Blueprint, mint a **fresh** `authentik-ldap_bind` token (the current item
      is an expired outpost token), redeploy the outpost, THEN flip `storage_samba_passdb: ldapsam` on nas and
      live-verify a family drive. **Do not flip the var first — smbd fails hard on an unreachable outpost.**
      Re-probed live 2026-09-21: **two** blockers, not one — Authentik holds **no LDAP provider, no LDAP source
      and no LDAP outpost object** (the only Outpost row is the proxy one), and the `authentik-ldap` container is
      crash-looping `403 Forbidden (Token invalid/expired)`; minting a token alone therefore yields an outpost
      serving zero providers. Ordered gates + the `ldapsearch` proof step (WG side only) recorded in
      [deployment-compose.md](docs/deployment-compose.md); parked at the owner gate (a write-scoped `op` session
      is required — the runner's SA token is read-scoped).
      · [deployment-compose.md](docs/deployment-compose.md)
- [ ] **HD-207** — land the migrated data: redistribute the `bulk/migrate` landing zone (personal → OpenCloud/live
- [ ] **HD-361** — Cockpit break-glass login on nas: the PAM identity is missing, so `cockpit-nas` has **no
      valid credential today** (it is reachable but unusable in an emergency). · [hardware-nas.md](docs/hardware-nas.md)
- [ ] **HD-191** — oldsrv Kopia agent is Up with snapshots in the repo; the open tail is the **restore drill from a
      snapshot** (+ volume-name pin verified at restore). · [backup.md](docs/backup.md)
      Box + `/tank/data/users/<name>`, media → `bulk/media/*`), then destroy the landing zone. · [hardware-nas.md](docs/hardware-nas.md)

---

## Phase 3 — oldsrv Fresh Install + Internal/GPU Compute Host (`oldsrv.kogler.si`)

> **Depends on:** Phase 1.5 (VLAN 99 native + tags), Phase 2 (NAS NUT master for the `nut` client),
> Phase 1 (VPS edge + Authentik live).
> **Status:** ✅ **Phase 3 COMPLETE + LIVE 2026-09-08** — full `home_servers.yml` converge **failed=0**, every
> role green, service set Up + healthy; the RO-path fix batch and the kopia-agent leg closed the same day
> (**HD-318a**), HA standby cold-render completed (**HD-318c**), and the music pillar landed 2026-09-14/15
> (**HD-362**). The three knowns this row used to carry (kopia-agent VPS-gated, signal-cli unlinked, "do not
> re-converge monitoring until Victoria") are **all closed** — record: `docs/hardware-oldsrv.md` + the commits.
> ⏳ What is left on oldsrv is listed in its deploy-gated block below.
> oldsrv is the **internal/GPU/LAN compute host**: the GPU + storage-bound backends (ollama, immich-ml,
> jellyfin/iGPU, sunshine), HA **standby**, DNS, media/*arr, observability, and the **`traefik-internal`
> home edge** (the LAN all-app edge — ✅ LIVE 2026-09-14, HD-349/350; it took over the role HD-331 had
> cancelled on the VPS `traefik-tailnet` edge alone). The **public edge + stateless/live-data public apps live
> on the VPS** (Phase 1) — the wildcard cert is issued **only** by the VPS Traefik (ACME); oldsrv runs **no
> ACME**: its `traefik-internal` pulls the cert pair from the VPS over the `traefik-cert-sync` timer (HD-350).
> **1Password prerequisites (new this phase):** the platform block below must exist in `Homelab-ansible`.
> **Continuation:** the GPU/AI stack (Phase 1's deferred `litellm→ollama`, `immich-app→immich-ml` links) comes
> online here once the WG S2S tunnel to the VPS exists; HA primary (Phase 4) builds on this node's standby.

- [x] **[MANUAL]** **Preseed install** — ✅ **2026-08-23** (Phase 1a): boot from `IaC/host/oldsrv/preseed.cfg`
   (NVMe partitions; iGPU-primary, dGPU RX 7600 reserved for compute) + shared `post_install.sh`;
   installed interactively + catch-up bootstrap.
   ✅ **2026-09-03 (pre-Ansible, first-contact prep):** oldsrv was on a DHCP lease (`.101`), but `host_vars`
   pins `ansible_host` = SSOT `oldsrv` Mgmt row (tagged-99) → the lease fallback made the pinned static unreachable.
   **Applied directly via NetworkManager** (host runs NM — the role's netd/systemd-networkd units only land during
   provision): `Wired connection 1` → `manual` (SSOT `oldsrv` Home row + gateway, DNS 1.1.1.1/1.0.0.1,
   `ipv4.dhcp-client-id=mac`) + new NM VLAN profile `VLAN 99 Mgmt` (`enp0s31f6.99`, SSOT `oldsrv` Mgmt row,
   `never-default`). Host verified reachable at the Home row — `.99` Mgmt bound but not reachable while the
   mgmt plane is down.
- [x] **Ansible** — ✅ **2026-09-08 failed=0** — `ansible-playbook -i inventory.ini playbooks/home_servers.yml` (ordered):
   `common` → `ai_diag` → `docker` → `network` (Home 10 untagged + Mgmt 99 tagged on the same NIC) →
   `storage` (ZFS `nvme` + NFS mounts to nas) → `nut` (client, `shutdown_delay_seconds=60` →
   `powerwalker@nas`) → `cockpit` → `amd_rocm` (trixie-native userland, udev, `OLLAMA_KEEP_ALIVE=5m`) →
   `desktop` → `office` → `proxmox` (`when: homelab_mode == 'proxmox'` — inert on this box) →
   `docker_services` → `home_assistant` (cold standby) → `monitoring`. Order of record = `playbooks/home_servers.yml`.
- [x] **Services (internal/GPU subset)** — ✅ deployed 2026-09-08 (music pillar added 2026-09-14) —
   `docker_services` deploys the **oldsrv** set in
   `group_vars/home_servers.yml` (the loop source of truth, rendered to
   [`docs/services-inventory-generated.md`](docs/services-inventory-generated.md)): the pinned-AI tier
   (the three **Vulkan legs** `embed`/`reranker`/`whisper` — live under decision #27 — plus
   ollama `:rocm`, kept as the **embed fallback rung**), immich-ml, **technitium (SECONDARY — the VPS is primary, Pi tertiary)**, ~~pihole~~
   (`enabled: false`), **`traefik-internal`** (the home all-app edge, live 2026-09-14), dozzle +
   dozzle-agent, signal-cli-rest-api, sunshine (`homelab_mode == 'desktop'` gated),
   home-assistant-standby (`enabled: false` cold standby), the media stack (jellyfin iGPU +
   seerr/seerrng/sonarr/radarr/lidarr/aurral/slskd/lidarr-ydl/prowlarr/bazarr/sabnzbd/qbittorrent/
   profilarr/recyclarr; tube-archivist `enabled: false`), lan-litellm (+ its DB), actual-budget,
   kopia-agent, mcp-victoriametrics/mcp-victorialogs, and the parked `dsh`/`pi-dev` pair (HD-386).
   The public apps (traefik/crowdsec/authentik/opencloud/forgejo/immich-app/grafana/homepage and the
   observability backend) are on the VPS (Phase 1/HD-135), not oldsrv.

   ✅ **Templates status (live):** all compose templates exist under `docker_services/` — HD-16
   (authentik + Forward-Auth middleware) and HD-50 (`docker_services` role) are **done**. The authoritative
   service list is `group_vars/home_servers.yml` (the loop source of truth) + `docs/services.md`; it is
   **not** a per-template TODO list. New services are added by dropping a template under
   `docker_services/<name>/` and listing it in `home_servers.yml` — no per-template placeholder caveats.

- [x] **HA standby** — ✅ **HD-318c closed + LIVE 2026-09-08**: `home-assistant-standby` compose + keepalived
   (`ha-vrrp_password`, BACKUP instance) rendered cold at `/opt/home-assistant-standby`; the registry row is
   `enabled: false` by design (it starts on failover, not on boot).

**New 1Password prerequisites (Phase 3):** — the authority is table A in §0; the list below is what is
**newly** needed on oldsrv (the platform/VPS items are already in by Phase 1).
- ~~`cloudflare_api` (api→`credential`) — wildcard cert~~ — **moved to Phase 1 (VPS)**: the wildcard is issued by the VPS Traefik only (HD-178). **Cert consumers = VPS `traefik-tailnet` (bind-mount) + oldsrv `traefik-internal` (cert-pull timer, HD-350) + Pi `traefik-ha` (`ha-cert-sync`)**; HD-331's "no home edge" position was re-decided by **HD-349** and the oldsrv edge has been live since 2026-09-14.
- `kopia_password` (password) — Kopia off-site = **backup Box over SSH/SFTP (port 23)** (`kopia_sftp_*` in `group_vars/all/main.yml`; SSH key in `Hertzner-SB-Backup`; **no password secret item**). ~~`kopia-s3_api`~~ retired (iDrive e2 dropped). `kopia-server_fingerprint` is **not** hand-seeded — the `kopia-fingerprint-sync` task writes it from the live VPS cert.
- **Genuinely new here:** `signal_api` (api; `username`=phone, `credential`=captcha) · `ha-vrrp_password`
  (VRRP auth of the HA pair) · the media/pillar placeholder-then-swap keys `sonarr_api`/`radarr_api`/
  `lidarr_api` (+ `slskd_login`/`soulseek_api`/`privado-vpn_api`) · `actual-budget_login` (human-side ref for
  the n8n API leg).
- ~~Already seeded in Phase 1 (VPS services), not here:~~ `authentik_db`/`authentik_password`/`authentik_login`,
  `opencloud_db`, `immich_db`, `forgejo_db`, `forgejo_api`, `grafana_login`, `headscale_api`, `smtp_login`.
- `ha_api` is **not** a Phase-3 item: it is gated behind `prometheus_ha_exporter: false` and lands with HD-14.

**Verify:**
- `docker compose ps` for every service is healthy; `systemctl status docker-compose@<service>`.
- Homepage (`home.kogler.si`), Grafana and Forgejo are **VPS-edge** services (HD-180 landed) — verify them via their public URLs in Phase 1, not here. oldsrv's own LAN-facing routes (`media`/`*arr`/`llitellm`/`llogs`/…) serve through its `traefik-internal` home edge.
- Wildcard `*.kogler.si` cert: issued on the **VPS** (Phase 1, HD-178) — consumers = VPS `traefik-tailnet` internal edge (bind-mount `/opt/traefik/certs`) + Pi `traefik-ha` (ha-cert-sync); oldsrv serves **no** Traefik/ACME (HD-331 supersedes the old internal-edge plan).

**Deploy-gated verification (Phase 3 — oldsrv):** open rows only; closed ones were deleted here (record =
owning doc + commit). **HD-100 (LiteLLM), HD-102 (Qdrant), HD-43 (\*arr stack), HD-44 (ops services), HD-128
(NVMe by-id), HD-46 (Matrix), HD-58/HD-113 (Stirling/PairDrop) and HD-59 (internal-auth items) all closed.**

- [ ] **HD-57** — Finance stack: the tokens + EB app creation are owner steps; then the n8n import/categorization
      flows, the WG AllowedIPs scope for the :5006 API leg, and the first live verify. · [services-finance.md](docs/services-finance.md)
- [ ] **HD-318(b)** — recyclarr @daily quality-profile sync verify (the stacks have been up since 2026-09-08; the
      *arr configs were chowned to their image uid 2026-09-15 after a converge recreated them root-owned). · [hardware-oldsrv.md](docs/hardware-oldsrv.md)
- [ ] **HD-347** — the Signal alerting **group UUID** belongs in SSOT (`signal_alert_recipients` is empty); the
      device itself is linked and alerts flow. · [observability.md](docs/observability.md) §Alerting
- [ ] **HD-350** — **[MANUAL, owner]** authorize oldsrv's `traefik-cert-sync.pub` on the VPS so `traefik-internal`
      can pull the wildcard pair (the timer is armed; the pull 401s until the key is authorized). · [services-traefik.md](docs/services-traefik.md)
- [ ] **HD-353** — **[MANUAL, owner]** verify own Jellyfin login at the `seerrng` route. · [services-media.md](docs/services-media.md)
- [ ] **HD-357** — Homepage tiles: wire the Jellyfin/Seerr/Immich widgets to the verified endpoints (the edge model
      and route tables are final now). · [services.md](docs/services.md)
- [ ] **HD-358** — record the Seerr → \*arr API-key + URL wiring as an owner step (and consider automating it). · [services-media.md](docs/services-media.md)
- [ ] **HD-362** — music pillar tails: overwrite the placeholder 1P values with real ones, wire the Lidarr download
      clients in-UI, refresh the Navidrome Box library. **Tube Archivist stays torn down** — re-enabling it requires
      `path.repo` in the ES `elasticsearch.yml` directly first (env-var/`-E` forms destabilize ES bootstrap). · [services-media.md](docs/services-media.md)
- [x] **HD-386 tail** — **CLOSED 2026-09-21: no owner step, it was already decided.** — the `dsh`/`pi-dev` tailnet names + `dsh-backend`/`pi-backend` routes still answer **502 by
- [ ] **HD-288** — `sunshine` deployment tail on oldsrv (the enable decision is resolved in IaC; the deploy +
      verify is not). · [hardware-gpu.md](docs/hardware-gpu.md)
- [ ] **HD-399** — `technitium-seed` is **not `--check`-safe**: every `docker_services --check` on oldsrv dies at
      `technitium-seed.yml:102`. Until it is idempotent-under-check, a dry run on that host is not available. · [services-dns.md](docs/services-dns.md)
- [ ] **HD-133** — subscription renewal reminders (SSOT `subscriptions.yml`) driving Homepage + calendar + n8n. · [subscription.md](docs/subscription.md)
- [ ] **HD-238** — write the oldsrv→VPS DR runbook for the non-GPU services (an imperative procedure, not prose). ✅ **Written 2026-09-21**: backup.md §Runbook — restore the non-GPU tier on a replacement VPS + §Restore drill (yearly) + a VPS-loss row in §Recovery Paths. ⏳ Owner: schedule/run the drill (its tick needs the dated result) and decide the per-service fail-over-vs-accept-loss table. · [backup.md](docs/backup.md)
- [ ] **HD-45** — network dashboard / who-is-on-network (re-scoped 2026-09-09). · [observability.md](docs/observability.md)
      design**; kept by design — settled, see [network-vpn.md](docs/network-vpn.md) · [services-ai.md](docs/services-ai.md)


---

## Phase 4 — Pi Fresh Install + HA Primary (`pi.kogler.si`)

> **Depends on:** Phase 1.5 (VLANs), Phase 2 (NAS NUT master). The Pi is the HA **primary** node;
> oldsrv (Phase 3) is standby. Both share one `configuration.yaml` and the VIP (`ha-vip`).
> **1Password prerequisites (new this phase):** none — `ha-vrrp_password`, `nut_password` and `smtp_login` are
> already in from Phase 2/3. (`ha_api` is NOT a Phase-4 item: it is gated behind `prometheus_ha_exporter: false`
> and arrives with HD-14.) Add `ha-mqtt_login` if/when MQTT is introduced — currently out of scope.
> **Continuation:** `ha.kogler.si` → VIP becomes live here; observability (Phase 6) scrapes the HA
> exporter and smart-home work (Phase 7) builds on this node.

- [x] **[MANUAL]** **Flash + first-boot config** — ✅ 2026-09-03 on the **Sandisk Max 128 GB** (HD-315: the old
   Samsung EVO 64 GB was the root cause of HA's whole flaky history). Flash **Raspberry Pi OS Lite (64-bit)** via
   Imager with the ⚙ advanced gear (Enable SSH + user + `ansible-admin_ssh` pubkey + hostname `pi`); no manual
   boot-partition edit / no `first-boot-config.sh` (raspi.debian.net-only, replaced 2026-09-01 after a
   rainbow-screen boot failure)
- [x] **Ansible** — ✅ 2026-09-03 (re-converged since; the Pi also took the Victoria migration 2026-09-08).
   `ansible-playbook -i inventory.ini playbooks/raspberry_pi.yml` (full imperative
   runbook incl. KNX + dashboard + secrets renderer: [deployment-pi-provision.md](docs/deployment-pi-provision.md)):
   `common` → `ai_diag` → `network` (dual-homed via **two NetworkManager keyfiles**: `pi-eth0` = Home 10
   untagged + default/DNS, `pi-mgmt` = Mgmt 99 tagged `never-default`; IP per SSOT) → `nut` (client,
   `shutdown_delay_seconds=0`) → `docker` → **`home_assistant`** (**primary**, Debian + HA Container +
   keepalived → VIP `ha-vip`) → **`docker_services`** (Pi-specific: `home-assistant-primary`,
   `technitium-secondary`, `traefik-ha`, `dozzle-agent` — no pihole/raspberrymatic) → `monitoring` (Alloy only).
   ⚠ **The HA-before-docker_services order is load-bearing** (HD-185/204 render-first): it renders
   `configuration.yaml`/`keepalived.conf`/`secrets.yaml` as regular files before the first `compose up`. The
   old KOPS-063 order (containers first) made Docker auto-create the bind dirs and HA silently ran default config.
- [x] **Local Homematic** — ⏳ **parked by decision, not pending work** (HD-13): `raspberrymatic` was dropped from the Pi loop
   (2026-08-18); re-add with an HmIP-RFUSB only when local RF is purchased (HmIP-HAP stays in
   cloud mode until then).

**Verify:**
- `ha.kogler.si` resolves to the VIP (`ha-vip` per SSOT); `keepalived` is MASTER on the Pi (priority 110 > oldsrv 100).
- Technitium resolves `*.kogler.si` internally — the Pi is the **tertiary** instance (VPS primary / oldsrv
  secondary) and is the **first resolver handed out on VLAN 10** (HD-334). Pi-hole is `enabled: false` — filtering is not active.
- HA web login is **local** (the owner declined Authentik OIDC for HA — recorded in `todo.md` §2.1a Pkg E).
- Manual failover runbook in `docs/smart-home-failover.md` passes Pi→oldsrv and back.

**Deploy-gated verification (Phase 4 — Raspberry Pi):**
- [x] **HD-04 phase-4 gate** — ✅ **met 2026-09-03**: Pi provisioned with the proven runbook, HA LIVE + VIP
      MASTER + Technitium secondary + traefik-ha; the redo is **complete**. What remains is the failover re-drill
      below. · [deployment-pi-provision.md](docs/deployment-pi-provision.md)
- [ ] **HD-04 tail** — **[MANUAL, owner]** second failover drill: exercise **Pi→oldsrv→Pi** and the oldsrv→Pi
      **reverse** takeover (the 2026-09-09 drill proved forward + reported Pi→oldsrv only; the reverse direction is
      untested and the manual runbook has a documented gap). · [smart-home-failover.md](docs/smart-home-failover.md)
- [ ] **HD-17** — render the Homepage failover **button** (gate `homepage_failover_button`; the RFUSB path is
      obsolete — HD-18 rejected the stick, the active path is IP-only: VIP move + standby start). The
      `ha-failover-api` service itself is live since 2026-09-08. · [smart-home-failover.md](docs/smart-home-failover.md)
- [ ] **HD-318(g)** — the HA **ZHA** radio on the Pi (the one serial device no converge can reach — it is host
- [ ] **HD-217** — Homepage failover-button **gating** (`homepage_failover_button`): IaC done + owner sign-off,
      the deploy render is the open half (pairs with HD-17 above). · [smart-home.md](docs/smart-home.md)
- [ ] **HD-319** — **[MANUAL, owner]** confirm the 3 rekuperator group addresses (12/1/*) answer on the KNX bus
      (some `GroupValueRead` warnings remain); the render-from-`.knxproj` + dashboard are live. · [smart-home.md](docs/smart-home.md)
      hardware, not a container): after a physical re-seat, grant the serial device **dialout access + a stable
      `/dev/serial/by-id` symlink** and **re-run `home_servers.yml`** (not just `docker_services.yml`). · [smart-home.md](docs/smart-home.md)


---

## Phase 4b — spark AI compute node (DGX Spark GB10) — LIVE since 2026-09-15

> **Depends on:** Phase 1 (VPS LiteLLM + the wildcard cert), Phase 1.5 (the WG S2S tunnel is the transport for
> `llm.kogler.si`), Phase 3 (oldsrv LiteLLM + the pinned-AI tier). **It was not in this ledger at all until
> 2026-09-19** — the host, its playbook (`playbooks/spark.yml`, 7 roles) and its group_vars all shipped in
> September while the phase list stopped at 10. The runbook uses the **same** numbering (its spark section is
> §Phase 4b — it was §Phase 5 until the two documents were unified on 2026-09-19).
> `docs/hardware-spark.md` + `docs/services-ai.md` §2 are the SSOTs;
> `todo.md` HD-335/336/337/369/373/386/391/393 is the status record.
> **1Password prerequisites:** `spark-llm_api` (engine bearer — the SAME string both LiteLLM instances send
> upstream, so rotation is a coupled window: `scripts/rotate-spark-llm-key.sh`) and the human-vault `spark_login`
> (DGX OS first-boot admin, console break-glass). Full note in §0 table A.

- [x] **[MANUAL]** **Physical + OS first-boot** — ✅ 2026-09-14: the **rack-fit problem is the real work item**
   (it is not a 1U server), and the DGX OS setup wizard needs a human at a display + keyboard to set `spark_login`.
- [x] **Network identity** — ✅ 2026-09-14: `spark.kogler.si` = **Home VLAN 10**, static per the address SSOT; the Mgmt-99 leg
   is a **tagged dual-home on the same NIC** (`IaC/ansible/host_vars/spark.yml` + the switch role's parity-trunk
   task), and the VLAN-10↔99 allow is **source-pinned per device**, never a /24 shortcut. The DGX dashboard edge
   (`spark.kogler.si:11000`) is a Traefik file-provider route, live 2026-09-15.
- [x] **Ansible** — ✅ 2026-09-14: `ansible-playbook -i inventory.ini playbooks/spark.yml` — `spark-prep` → `spark-models`
   → `spark-wireguard` → `spark-node-exporter` → `spark-docker` → **`spark-ai`** (generation: `llm.kogler.si`) →
   `spark-node-local-dns`. The engine is started with `--api-key` (the bearer), **not** the retired `--root-path /spark`.
- [x] **Name edge + LiteLLM wiring** — ✅ **HD-370 closed 2026-09-15/17**: `llm` / `db-spark` / `spark` resolve
   to spark **on home instances only** (split-horizon), `litellm` stays public on the primary; TLS-in-TLS hop
   verified with the bearer key; the model row carries **no key** (the key is the container's `OPENAI_API_KEY`).
- [x] **Unified-memory budget governor** — ✅ deployed 2026-09-16, re-certified 2026-09-18 at **16 GiB** (`spark_vllm_kv_cache_memory: "16000000000"`,
   reserved 14.9 GiB / 515,786 tok / 1.97× @262k), re-certified 2026-09-18 by the 3-rung load chain. **A converge
   that regresses to the 8.2 GiB figure restores the pre-certification value — do not do it.**
- [x] **Pinned-AI tier deployed** — ✅ 2026-09-19: the RX 7600 runs the three Vulkan legs (`embed` :9002,
   `reranker` :9001, `whisper` :9000) with their LiteLLM rows (`bge-m3-vk` / `local-rerank` / `local-stt`); spark
   stays the generation tier (decisions #24/#27). `ollama:0.32.15-rocm` is **kept** as the embed fallback rung
   (owner decision), not retired. Plan of record: `docs/services-ai.md` §3a.

**Verify:**
- `https://llm.kogler.si/v1/models` answers **401 without** and **200 with** the bearer key; the home split-horizon
  resolves `llm` → spark while the public primary still answers `litellm` → the VPS.
- Both LiteLLM UIs complete a generation against `spark/qwen3.8-flash-next` (owner-closed HD-382).
- The 3-rung stability chain (re-runs of `spark/stability-test.md`) shows 0 kernel OOM / 0 engine restarts /
  0 guard-fires, and the journal shows the reserved-KV line at the expected token count.
- `spark` appears in the Prometheus/VictoriaMetrics target set (node-exporter) and the engine log carries no
  unified-memory warning.

**Deploy-gated verification (Phase 4b — spark):**
- [ ] **HD-337** — the bring-up epic: OS → placement → the HD-155 spark leg → engine → models → the Cohere
      retirement/embed cutover → Mem0 + OpenHands. Most legs are done; the row stays open until the tail lands. · [hardware-spark.md](docs/hardware-spark.md)
- [ ] **HD-336** — the coding plane: agent-memory.dev per-project memory on oldsrv (MCP + a LiteLLM key), the
      ZeroClaw system-mgmt runner, CrewAI gated on the homelab being finished. · [services-ai.md](docs/services-ai.md)
- [ ] **HD-373** — LiteLLM admin UI: the `/ui/login` deep-link 404s (no nginx SPA fallback in the container);
      workaround `https://litellm.kogler.si/fallback/login`. Fix = SPA fallback or route-scoped `/ui/*`. · [services-ai.md](docs/services-ai.md)
- [ ] **HD-369** — the tail of the tier row: Ollama stays as the **embed fallback** (the owner keeps it), and
      the rerank leg still has **no consumer** — `rag-mcp` is a compose stub, so nothing calls the reranker yet. · [services-ai.md](docs/services-ai.md)
- [ ] **HD-393** — the spark re-cert that gates the rerank cutover: attribute that OOM episode per-process,
      decide benign-vs-OOM-adjacent, fix it or accept it as noise. **Never converge an unpinned AI leg.** · [services-ai.md](docs/services-ai.md)
- [x] **HD-386 tail** — **CLOSED 2026-09-21: there was no owner step.** The retired `dsh`/`pi-dev` harness records and their 502 tailnet routes were settled in `group_vars/vps.yml` and documented in [network-vpn.md](docs/network-vpn.md) — the names stay, the 502 is the design, and removal is the one-change procedure written there. What is left on HD-386 is the `failed=0` oldsrv converge sighting, which is Table AI work, not an owner call.
- [ ] **HD-367 / HD-359** — the Mgmt-99 dual-home leg + the engine-neutral benchmark kit: IaC and boot done, the
      **S1 bench is not yet certified** — the numbers still do not back the tier decision. · [services-ai-bench.md](docs/services-ai-bench.md)
- [x] **HD-375** — **CLOSED 2026-09-22 (owner).** The two spark host-memory OOM rules are live in the ruler
      (deployed 2026-09-17 22:33C, `vps.yml --tags monitoring`, failed=0) and the owner took the Grafana-UI +
      n8n confirmation, so the row is deleted. Record: [observability.md](docs/observability.md) §Alerting.
- [ ] **HD-380 / HD-395** — the governor's second term + OOM-forensics watchdog, and the idle-recycle baselines
      that move with a boot-time coin-flip. · [hardware-spark.md](docs/hardware-spark.md)
- [ ] **HD-377** — one unified LLM dashboard (`homelab-llm`) instead of three vLLM boards. · [observability.md](docs/observability.md)
- [ ] **HD-420** — spark metric cadence: the hot/cold Alloy scrape split (5 s for the ~50 series behind the nine
      panels the owner named, 60 s for the rest), the DCGM sidecar's 30 s collection interval, the Grafana
      datasource `timeInterval` floor, and the hard-coded `[5m]` prefix-cache panel — then converge
      `vps.yml --tags monitoring` plus the spark-side Alloy/DCGM restart and verify the 5 s granularity survived.
      ⛔ never restart the vLLM engine for this. · [observability.md](docs/observability.md)
- [ ] **HD-387** — the thinking-control re-measure **through the gateway** (a recorded contradiction between a
      recommendation and a measurement is still open). · [services-ai-bench.md](docs/services-ai-bench.md)
- [ ] **HD-366** — DGX Dashboard JupyterLab on the LAN (`:11002`) — the integrated lab assigns per-user ports. · [hardware-spark.md](docs/hardware-spark.md)
- [ ] **HD-376 / HD-388** — harness-side context/timeout tuning and generating the client model config from a repo
      template instead of hand-kept files. · [services-ai.md](docs/services-ai.md)
- [ ] **HD-383 / HD-384** — parked LAN-LiteLLM bootstrap-keys glue (parked by HD-386) and the gateway grant for
      `spark/*` to the simple-querier tier. · [services-ai.md](docs/services-ai.md)
      deleting them (decision #26 routes harnesses straight to the engine). · [services-ai.md](docs/services-ai.md)
- [ ] **[MANUAL, owner]** the human-only surface of a headless GB10: the DGX OS first-boot wizard needs a person at
      a display + keyboard (that is where `spark_login` is set), and there is **no out-of-band console** afterwards —
      a wedged box (the documented unified-memory wedge pattern) is recovered by **power-cycling it at the PSU**,
      which is also why the IaC masks sleep/hibernate (HD-364) instead of trusting defaults. Confirm the 240 W PSU
      sits on covered UPS outlets. · [hardware-spark.md](docs/hardware-spark.md) · runbook: [deployment-manual.md](deployment-manual.md) §Phase 4b

---

## Phase 5 — GitOps Deploy Button (Forgejo Actions → Ansible) — Doco-CD removed (HD-150)

> **Depends on:** Phase 3 (Forgejo + services live, Renovate running), Phase 4 (HA live).
> **1Password prerequisites:** `forgejo_api` + `op_api`. Doco-CD + `doco-cd_password` are **removed** (HD-150) —
> single Ansible-only deploy path; the deploy button runs Ansible (not a webhook agent).
> **Status (2026-09-19):** ⏳ **the deploy button does not exist yet.** `docs/services-vps.md` lists Forgejo as
> `⏳ pending`, so Phase 5 is still the one unbuilt leg of the deploy pipeline, while `vps.yml` has converged
> **manually** many times since 2026-08-22. Two premises this phase used to state as fact are **unverified from the
> repo** and are now questions, not steps: (1) the `op_api`-as-runner-secret arrangement — **HD-396** is open, no
> `.forgejo/` workflow exists in this repo, and no IaC file reads that item as a runner token; and the SA token was
> rotated 2026-09-19, so IF a runner exists its token is dead until renewed; (2) the Victoria-metrics scrape-set
> tail of step 5 (closed 2026-09-08 — see Phase 6).
> **Continuation:** once active, merges are applied via the Forgejo Actions deploy button instead of manual Ansible runs.

- [ ] **Forgejo Actions deploy workflow** — add `.forgejo/workflows/deploy.yml` (manual `workflow_dispatch`,
   `--tags` selector); the runner SSHes to the target host(s) and runs `ansible-playbook`
   (`vps.yml` for VPS, `home_servers.yml` for oldsrv).
- [ ] ⏳ **1Password for the runner** — **unverified premise (HD-396)**: `op_api` as a Forgejo secret, runner
   resolving secrets at render time. Confirm the runner exists at all before wiring it; after the 2026-09-19 SA
   rotation, renew whatever token it does hold or its vault access 403s.
- [ ] **Trigger** — no webhook; you click the **deploy button** on Forgejo (Dependency Dashboard / Actions tab).
- [ ] **Deploy-button wiring for Renovate PRs** — Renovate itself is live (Phase 3) and opens PRs; what is missing is applying them through the button.
- [ ] **Metrics** — none from the deploy path (no Doco-CD exporter). The **VictoriaMetrics** scrape set
   (Traefik/CrowdSec + services, Alloy as the single shipper) is **live since 2026-09-08** (HD-341/342) — see Phase 6.
- [ ] **Post-deploy hooks** — Ansible regenerates Homepage config + `services-inventory-generated.md` → commit+push.

**Verify:** a Renovate PR → merge → Forgejo **deploy button** → service updated with **no manual Ansible run**.

---

## Phase 6 — Observability & Alerting Hardening

> **Depends on:** Phase 3 (monitoring role — VictoriaMetrics/VictoriaLogs/Grafana central, HD-342), Phase 4 (HA exporter).
> **1Password prerequisites:** existing — `ha_api` (HA bearer), `smtp_login`,
> `signal_api` (Signal notify via n8n). **Runs in parallel with Phase 5+.
> **Victoria* migration (HD-341/342) is DONE + LIVE (2026-09-08):** VM/VL replaced Prometheus/Loki, Alloy is
> the single scrape tier on all four home hosts + spark, retention 365d/90d, datasources/dashboards/alerts
> re-pointed. **Still open in this phase:** HD-344 (register the MCP endpoints — servers live on :8083/:8084),
> HD-343 (dashboard render-verify, owner), HD-345 (`ifOperStatus` SNMP), HD-14/HD-19 (HA exporter + recorder).
> See `todo.md` + `docs/observability.md`.

- UPS metrics + alerts in Grafana (Critical battery/runtime, Warning on-battery, Info transitions) — **HD-08**
- HA entity list export (Prometheus exporter) for the HA Dashboard (lovelace) + Grafana — **HD-14**
- HA recorder trim (`purge_keep_days`) to protect the Pi SD — **HD-19**
- Grafana Alerting tiers (Critical/Warning/Info), self-monitoring, n8n + signal-cli-routing (details: `docs/observability.md`)
- ~~Victoria backend~~ — ✅ LIVE 2026-09-08 (HD-341/342); the Prometheus/Loki rule set is gone (HD-347 swept the orphans)

**Deploy-gated verification (Phase 6):** ✅ the migration itself is **done** — VictoriaMetrics + VictoriaLogs run
on the VPS, Pi and oldsrv ship Alloy + network-clients + syslog, Grafana is the single UI.
- [ ] **HD-14** — enable the HA Prometheus exporter (seed `ha_api` + flip `prometheus_ha_exporter` + re-enable the
      scrape job **together**, or the converge breaks), then the HA dashboard and Grafana panels. · [smart-home.md](docs/smart-home.md)
- [ ] **Pi recorder trim** (`purge_keep_days: 2`) + log strategy to protect the Pi SD — planned in
      [observability.md](docs/observability.md) §Log strategy but **has no `todo.md` row** (the old HD-19 lineage);
      register a row when it is actually scheduled. · [observability.md](docs/observability.md)
- [ ] **HD-343** — the network-clients exporter: verify the live wifi path (`/interface/wifi/registration-table`
      vs the legacy API) + **[MANUAL, owner]** render-verify the panels on `stats.kogler.si`. · [observability.md](docs/observability.md)
- [ ] **HD-344** — register the Victoria MCP endpoints in pi / Open WebUI / OpenClaw (the servers are live); the
      tailnet redo is an owner call. · [observability.md](docs/observability.md)
- [ ] **HD-345** — `ifOperStatus` is still 0 in VM (the SNMP walk is not arriving); verify the interface rules and
      fire a test alert once SNMP data lands. · [observability.md](docs/observability.md)
- [ ] alerting tails are tracked where their hosts are: **HD-159** (Phase 1, prove `wg-s2s-down` fires) and
      **HD-347** (Phase 3, the Signal group UUID in SSOT).


---

## Phase 7 — Smart Home Enhancements

> **Depends on:** Phase 4 (HA primary stable), Homematic HmIP-RFUSB stick available (human action).
> **1Password prerequisites:** existing — `authentik_login`, `authentik_db` (SSO), `ha_api`, `signal_api`.
> Items are tracked in `todo.md` (HD-XX) — execute per-item, don't restate here.

1. Homematic full-local (HmIP-RFUSB + RaspberryMatic, local XML-RPC; human moves/fits the stick) — **HD-13**
   (**parked**; the stick is unpurchased, the CCU rows in `network_static_hosts` stay dormant)
2. Single failover button + `ha-failover.sh` — **HD-17** + the Homepage gate **HD-217** (both tracked in Phase 4)
3. KNX render + dashboard tail — **HD-319** (Phase 4)

> Retired from this list on 2026-09-19 because the rows no longer exist: **HD-15** (HACS confirm),
> **HD-16** (Authentik OIDC for downstreams — superseded by the HD-141 epic on the VPS), **HD-18** (the HmIP-RFUSB
> stick was REJECTED), **HD-27** (voice pipeline — superseded by the pinned-AI stack, `docs/smart-home-voice.md`).
> HA local login, not SSO, is also settled here (owner declined OIDC for HA — `todo.md` §2.1a Pkg E).**
7. Office AI stack (Ollama models, n8n, Office MCP path per HD-108/111 — AnythingLLM/LocPilot retired, ONLYOFFICE) — **HD-28**

**Deploy-gated verification (Phase 7):**
- [ ] **HD-28** — Office AI stack: **⛔ blocked, do not start.** The Ollama half is superseded twice over
      (spark is the generation tier per decision #24, the pinned-AI legs per #25 → shipped as HD-391, closed) and the MCP half waits
      on HD-111; AnythingLLM + LocPilot are superseded. · [services-office.md](docs/services-office.md)
- [ ] **Local Homematic RF** — parked by decision (the old HD-13 lineage; **no `todo.md` row**): re-add
      `raspberrymatic` + an HmIP-RFUSB **only** when local RF is purchased — until then HmIP stays on the HAP in
      cloud mode. · [smart-home.md](docs/smart-home.md)
- [ ] **HD-17 / HD-217** — the failover button: tracked in Phase 4 (its host is the Pi).
- [ ] **HD-319** — the KNX bus tail (rekuperator group addresses) is tracked in Phase 4.


---

## Phase 8 — Backup & DR

> **Depends on:** Phase 1 (VPS Kopia → backup Box), Phase 2 (NAS ZFS datasets), Phase 3 (oldsrv kopia agent).
> **1Password prerequisites:** existing — `kopia_password`, `Hertzner-SB-Backup` (SSH/SFTP port 23, **not S3/SO**).
> **Off-site = two Hetzner Storage Boxes (bought 2026-08-18, HD-29/31):** live (Immich originals+encoded-video,
> OpenCloud files, CIFS) + backup (Kopia repo, SSH/SFTP port 23). **iDrive e2 dropped.**
>
> - Wire **VPS Kopia agent → backup Box** (SSH/SFTP, port 23) + **oldsrv agent → backup Box** (Kopia on both hosts).
> - Confirm VPS NVMe (DBs/thumbs/service state) is in Kopia scope; live-Box originals off-site via Kopia.
> - Kopia: server + per-host agents; verify policies/retention.
> - Assess Kopia Web GUI vs CLI at first restore drill — **HD-34**
> - Sign up Infomaniak kSuite (email, CalDAV, catch-all) — **HD-30**

**Deploy-gated verification (Phase 8):** ✅ repo + policy + schedules are live (retention policy = the SSOT in
`docs/backup.md`).
      (a lost identity key means rejoining every federation partner). Scope resolved 2026-09-21: it is **one
      path**, `/srv/docker/matrix` (RocksDB + `media/` + `archive/`; no separate key file exists, so the signing
      identity lives inside the same store) — restore it as one unit. ⏳ Blocked on the host-level gap: the VPS
      has **no backup client**, so no `/srv/docker/*` path is in any off-site snapshot
      (backup.md §VPS-side coverage gap). · [services-matrix.md](docs/services-matrix.md)
- [ ] **HD-34** — **[MANUAL, owner]** assess Kopia Web GUI vs CLI during the first human-run restore drill. · [backup.md](docs/backup.md)


---

## Phase 9 — Documentation & Polish

> **Depends on:** services live (Phase 3+) to document accurately.
> **1Password prerequisites:** `mikrotik-admin_login` (export the live config).

- Write family guides `docs/manual/*` (10 Slovenian files, `status: wip`) — **HD-32**

---

## Phase 10 — Deferred (Phase 2 hardware / Proxmox)

> **Trigger:** new bare-metal hardware available (→ Proxmox host, HD-41/42). The VPS edge is **already live**
> (Phase 1) — it is **not** deferred here.
> **1Password prerequisites (future):** `proxmox_login` (VM lab), etc.

- Proxmox role + VM lab (bridges, storage, VMs) — **HD-41**
- Phase-2 hardware build (Ryzen 9, open-frame chassis) — **HD-42** (**superseded 2026-09-06** by the ThinkStation PGX purchase, HD-335 / `hardware-spark.md`; archived)

---

## Continuation Dependency Graph

```
Phase 0 (bootstrap + 1Password/ssh keys + op_api)
   │
   ▼
Phase 1 — VPS PUBLIC EDGE (Traefik+CrowdSec+Authentik+public apps+DBs)   ◀── needed BEFORE Phase 2
   │      independent public tier — depends on Phase 0 only (public IP ~ DNS ~ internet);
   │      runs before / in parallel with the LAN track (it is public, not LAN)
   │
   ▼
Phase 1.5 — Network Redo (Router RB4011 + Switch CRS328)   ◀── IRREVERSIBLE CUTOVER (VLANs 10/20/30/40/50/99; 21 deleted HD-325)
   │          (WG S2S peer lives here — HD-03)
   ▼
Phase 2 (nas: storage + NUT master)
   │
   ▼
Phase 3 (oldsrv: internal/GPU host — ollama/immich-ml/jellyfin, DNS, media, HA standby)
   │        (WG S2S tunnel now lets Phase 1 VPS reach oldsrv GPU backends: litellm→ollama, immich-app→immich-ml)
   ▼
Phase 4 (pi: HA primary + VIP, Technitium DNS tertiary; RaspberryMatic parked HD-13)
   │
   ▼
Phase 5 (GitOps: Forgejo Actions deploy button → Ansible)
   ▼
Phase 6-9 (observability, smart-home, backup, docs) ── can run in parallel
   ▼
Phase 10 (deferred: Phase-2 Proxmox hardware, HD-41/42)
```

**Phase prerequisites (1Password) recap — what must exist before you start:**
Full authority = `docs/deployment-secrets.md` + `scripts/check-vault-items.sh --strict`; this recap is the
**human-gated** subset only (catalog-generated items are seeded by `scripts/provision-vault.sh --create`).
- **Phase 0:** `laptop-domen_ssh`, `ansible-admin_ssh`, `ai_ssh`, `op_api` (read-scoped runner token),
  `kopia_password` (seed), `laptop-domen-wsl-debian_login` (the WSL user password — **Homelab (human)** vault)
- **Phase 1 (VPS):** + `netcup-ccp_login`, `netcup-scp_login`, `netcup-vps_login` (Homelab (human) vault),
  `Hertzner-SB-Data`, `Hertzner-SB-Backup`, `op-write_api`, `cloudflare_api`, `authentik_login`,
  `grafana_login`, `forgejo_api`, `headscale_api`, `tailscale-sidecar_api`, `crowdsec-bouncer_api`,
  **`technitium_login`** (set the app's `admin` to it before the first seed) — plus the catalog DB items
  `authentik_db`/`opencloud_db`/`immich_db`/`forgejo_db`/`qdrant_db`/`onlyoffice_db`/`zipline_db`/`litellm_db`
- **Phase 1.5 (network):** + `mikrotik-admin_login`, `pppoe_login`, **`wg_password` AND `wg_password_vps`**,
  the 3 live `wifi-kogler*_password`, `network-snmp_api`
- **Phase 2:** + `nut_password`, `smtp_login`
- **Phase 3:** + `signal_api`, `ha-vrrp_password`, the placeholder-then-swap app keys
  (`sonarr_api`/`radarr_api`/`lidarr_api`, `slskd_login`/`soulseek_api`, `privado-vpn_api`)
- **spark:** + `spark-llm_api` (engine bearer, coupled consumers) and the human-vault `spark_login`
- **Phase 4 / 6–10:** no new human-gated items except `ha_api` when HD-14 (HA exporter) is picked up
- **Phase 5 specifically:** the `op_api`-as-runner-secret premise is **unverified** (HD-396) — see table A;
  Doco-CD `doco-cd_password` retired (HD-150)
- **Phase 8 (backup):** no S3 items — Kopia = backup Box via **SSH/SFTP** (`kopia_password` + SSH key `Hertzner-SB-Backup`); `kopia-server_fingerprint` is deploy-provisioned
- **Phase 10:** future (`proxmox_login`, etc.)

---

## Host → Playbook → VLAN Mapping

| Host | FQDN | VLANs | Playbook | Key roles (order) |
|------|------|-------|----------|-------------------|
| router | `router.kogler.si` | L3 — all VLANs | `router.yml` | `router` (identity assert → `api_modify` → `vlan-filtering` enable LAST) |
| switch | `switch.kogler.si` | L2 trunk; Mgmt 99 | `switch.yml` (+ bootstrap / converge `.rsc` for the escape path) | `switch` |
| nas | `nas.kogler.si` | 10 untagged + 99 tagged | `storage.yml` | common → ai_diag → network → storage → nut(**master**) → cockpit → monitoring(alloy) |
| oldsrv | `oldsrv.kogler.si` | 10 untagged + 99 tagged (same NIC) | `home_servers.yml` | common → ai_diag → docker → network → storage → nut(client) → cockpit → amd_rocm → desktop → office → proxmox(gated, inert) → docker_services → home_assistant(standby) → monitoring |
| spark | `spark.kogler.si` | 10 untagged + 99 tagged (same NIC, `enP7s7`) | `spark.yml` | common → network → docker → spark (NVMe/XFS) → spark-artifacts → monitoring(alloy) → docker_services(`spark-ai`) |
| pi | `pi.kogler.si` | 10 untagged + 99 tagged | `raspberry_pi.yml` | common → ai_diag → network → nut(client) → docker → **home_assistant(primary+keepalived) → docker_services(pi)** → monitoring(alloy) |
| vps | `vps.kogler.si` | public | `vps.yml` (**Phase 1**) | common → docker → vps-hardening → network → cifs → wireguard(cond.) → docker_services → monitoring |
| — | all | — | `all.yml` | `/etc/hosts` sync |
| laptop | control | 10 (Mgmt 99 via the Windows vNIC) | `render-docs.yml` + `dns.yml` | renders `docs/network-addresses-generated.md`; maintains Cloudflare public DNS records |

> **Order of record = the playbook files**, not this table — read `IaC/ansible/playbooks/<name>.yml` before
> quoting a role order (two rows here were wrong for exactly that reason). **VLAN membership of record =**
> `network_static_hosts` in `group_vars/all/main.yml` + `docs/network-vlans.md` (all four LAN nodes ride
> **Home 10 untagged + Mgmt 99 tagged on one port**).
>
> **Control-plane playbooks** (laptop/runner-side, no host target group): `render-routeros.yml` (secrets-injected
> `.rsc`), `render-converge.yml` + `apply-converge.yml` (full steady-state `.rsc` escape), `dns-seed.yml`
> (Technitium split-horizon), `authentik-blueprints.yml` (OIDC/forward-auth blueprints), `nut-deploy.yml`
> (NUT-only run), `render-docs.yml`, `dns.yml`.

> Static IPs: [`docs/network-addresses-generated.md`](docs/network-addresses-generated.md) (SSOT).

---

## Validation Gates (Human)

| Gate | After | Check |
|------|-------|-------|
| **VPS public edge** | Phase 1 | `sso.kogler.si` (Authentik) reachable via VPS Traefik + wildcard cert; crowdsec active; `vps` public records live; VPS NVMe < 80% |
| Network cutover | Phase 1.5 | all VLANs up, DHCP per VLAN, inter-VLAN firewall matrix, CAPsMAN SSIDs, WireGuard up |
| NAS + UPS master | Phase 2 | `zpool status` healthy, `upsc powerwalker@nas` live, cockpit reachable |
| oldsrv services | Phase 3 | internal/GPU subset healthy (`docker compose ps`); HA standby + GPU backends up; WG S2S lets VPS reach ollama/immich-ml |
| HA VIP | Phase 4 | `ha.kogler.si`→VIP (`ha-vip`), keepalived MASTER on Pi, manual failover works |
| GitOps | Phase 5 | Renovate PR → merge → deployed with no manual Ansible run |
| Restore drill | Phase 8 | Kopia restores a test dataset to an alternate location |

---

## Notes

- **Service list source of truth:** `group_vars/home_servers.yml` (not this doc) — `docker_services` loop.
- **Generated docs (never hand-edit):** `docs/network-addresses-generated.md`, `docs/services-inventory-generated.md` (rendered by `render-docs.yml`).
- **Secrets source of truth:** `docs/deployment-secrets.md` (type map, master list, rename map).
- **Kopia off-site transport (decided HD-31/HD-135):** Hetzner Storage Box **backup** supports **SSH/SFTP only**
  (port 23, `u653424`, SSH-key auth via `Hertzner-SB-Backup`) — **NOT S3**. iDrive e2 S3 dropped. Backend config:
  `kopia_sftp_*` in `group_vars/all/main.yml`; repo password `kopia_password`; `~~kopia-s3_api~~` retired.
- **Architecture rationale:** `docs/hardware.md`, `docs/services.md`, `docs/observability.md`,
  `docs/deployment.md`, `docs/network-vlans.md`, `docs/smart-home-failover.md`.
- **Per-item status / difficulty:** [`todo.md`](todo.md) (HD-XX IDs referenced above) — the lifecycle SSOT; a
  closed row is deleted there, so a bare `HD-xxx` here with no todo row means **done or renamed**, not "open".
