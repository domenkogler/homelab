# Docs vs IaC — Contradiction Report (Audit Round 2)

> **Role:** Audit deliverable — contradictions between `docs/*.md` claims and the actual Ansible IaC
> (`group_vars`, `host_vars`, playbooks, roles, templates), plus cross-doc contradictions that block
> correct IaC work. Produced 2026-08-21 per `prompt.md`.
> **Linked from:** `prompt.md` task list; sibling reports: `docs-changes.md`, `iac-changes.md`,
> `conventions-sugestions.md`, `tracking-sugestions.md`, `architecture.md`, `security.md`.
> **Precedent:** a first audit round existed at root and was folded into canonical docs, then deleted
> (changelog HD-153). This is round 2 against the current tree; adoption of each fix is a human call.
>
> **Evidence style:** `doc claim` → `IaC reality (file)`. No internal IP literals are quoted (SSOT rule);
> hosts/services are named, values live in `group_vars/all.yml` / `host_vars`.

---

## Severity legend

- **[H]** — would mislead a deploy or rebuild if followed as written.
- **[M]** — stale or contradictory; confuses maintenance, no immediate deploy risk.
- **[L]** — cosmetic drift, duplicated lines, naming inconsistencies.

---

## A. Service placement & catalog (HD-135 split not fully propagated)

| # | Sev | Doc claim | IaC reality |
|---|-----|-----------|-------------|
| A1 | **H** | `IaC/README.md` §Service Definitions: home sample lists traefik, crowdsec, authentik, opencloud, immich-app, forgejo, grafana, n8n, kopia-server, db-backup, headscale, raspberrymatic-standby on oldsrv, and states "**In Phase 1 all run on oldsrv**"; VPS list shown as "Phase 2, reference only" with every service `enabled: false`. | `group_vars/home_servers.yml` is the post-HD-135 GPU/LAN subset (20 entries, none of the listed public apps); `group_vars/vps.yml` has 26 entries **all `enabled: true`** and the VPS is already provisioned (Phase 1, HD-40A). The README's own header comment even cites the HD-135 split it then contradicts. |
| A2 | **H** | `docs/deployment-ansible.md` §Group Vars: home_servers.yml sample = pre-HD-135 list (authentik, opencloud, immich-app, forgejo, grafana→stats, n8n→auto, kopia-server, db-backup, headscale, **raspberrymatic-standby**, …). | Actual `group_vars/home_servers.yml` contains none of those public apps and **no raspberrymatic-standby at all** (removed with HD-13 parking). The doc's inline disclaimer ("illustrative only, may drift") does not cover being two architecture generations old. |
| A3 | **H** | `deployment-tasks.md` Phase 3 step 3: oldsrv subset includes "headscale, kopia-server/agent, n8n, homepage, metabase, signal-cli-rest-api …" and says "remove/downgrade them here per the HD-135 enabled: split". | The split is already applied in `group_vars/home_servers.yml`: headscale/kopia-server/n8n/metabase are **not on oldsrv** (all on VPS). Nothing left to "remove". |
| A4 | **H** | `deployment-tasks.md` Phase 4 step 2: Pi docker_services = "technitium DNS, pihole, raspberrymatic", deployed **after** `home_assistant`; step 3 instructs installing local Homematic (HD-13). | `group_vars/raspberry_pi.yml` = home-assistant-primary, technitium-secondary, traefik-ha (**no pihole, no raspberrymatic**); `playbooks/raspberry_pi.yml` deliberately runs docker_services **before** home_assistant (KOPS-063/HD-117 comment); HD-13 is parked — no local Homematic step exists. |
| A5 | **H** | `docs/services-matrix.md`: "Runs on `oldsrv` (Phase 1) alongside every other service… homeserver + Element Web on oldsrv… WAN firewall must allow 443 to oldsrv". | `group_vars/vps.yml` runs `matrix` + `chat` (element-web) **on the VPS**, next to the public edge (HD-135 deliberations comment). Storage path `/srv/docker/matrix` on oldsrv is likewise stale. |
| A6 | **M** | `docs/services.md` "Standalone" section + public table: Homepage is public at root+`home` behind Forward-Auth. | Homepage deploys on **oldsrv** (`group_vars/home_servers.yml`) while the public edge is the VPS Traefik. No route/backends entry explains how VPS edge reaches the oldsrv homepage (WG? which backend address?). Under-specified in both `services.md` URL→backend table and the traefik routes template. |
| A7 | **M** | `docs/deployment-tasks.md` Host→Playbook mapping: vps chain "common → docker → network → docker_services → monitoring"; nas chain omits `storage`; pi chain shows home_assistant before docker_services. | Actual: vps = common→docker→vps-hardening→network→cifs→wireguard(cond)→docker_services→monitoring (`playbooks/vps.yml`); storage.yml includes the `storage` role; raspberry_pi.yml order reversed (KOPS-063). The same file's Phase 1 text has the correct chain — the table contradicts its own body. |
| A8 | **M** | `playbooks/storage.yml` header comment: "The observability stack (Prometheus/Grafana/n8n) lives on oldsrv and scrapes nas's nut_exporter remotely". | Observability backend moved to the VPS (HD-135); scrape crosses the WG tunnel, not the Home VLAN. Same stale phrasing in `group_vars/all.yml` nut_exporter comment ("scraped by Prometheus (on oldsrv)"). |

## B. Public DNS record set (three different lists, none matches IaC)

| # | Sev | Doc claim | IaC reality |
|---|-----|-----------|-------------|
| B1 | **H** | Four docs give four "public record subsets": `services.md` = root+home, sso, foto, file, office, ai, git, ha, vpn, matrix, chat · `network-dns.md` + `services-traefik.md` = root, foto, file, git, sso, ha, vpn, matrix, chat (no office/ai/home) · `services-matrix.md` = root, home, sso, foto, file, git, ha, vpn (+matrix/chat added). | SSOT `roles/cloudflare_dns/vars/main.yml` currently manages **only** the `vps` A/AAAA + three SMTP2Go CNAMEs; all service records exist as commented examples. The file itself flags "live zone and this file are two sources of truth — keep in sync by hand". Docs describe an end-state the IaC does not yet declare, and disagree among themselves about the end-state. |
| B2 | **M** | `network-dns.md` internal-only list mentions subdomain `bck`. | No service defines `bck` anywhere in group_vars (kopia-server has no subdomain). Ghost record name. |

## C. TLS / ACME issuer ambiguity

| # | Sev | Doc claim | IaC reality |
|---|-----|-----------|-------------|
| C1 | **H** | `deployment-tasks.md` Phase 1 + Phase 3: wildcard cert issued by **VPS Traefik**; oldsrv serves "internal-only". | `group_vars/all.yml` letsencrypt_email comment: wildcard issued via DNS-01 "**on oldsrv's traefik**"; `docs/smart-home-failover.md`: cert pair "**synced from oldsrv's traefik** (single ACME issuer)" to the Pi edge; `IaC/README.md` DNS/TLS model implies the same. Two mutually exclusive issuer stories; the Pi cert-sync design depends on which one is true. One decision must be recorded (changelog) and the losing text fixed. |

## D. Version pinning (law vs templates)

| # | Sev | Doc claim | IaC reality |
|---|-----|-----------|-------------|
| D1 | **H** | `CONVENTIONS.md` §7 + `docs/security.md` §2 law: never bare `latest`, never mutable alias; `todo.md` HD-134 marked "✅ Done"; `docs/security.md` says "Traefik — pin (currently latest)" (stale the other way — traefik IS pinned). | `versions.yml` pins 26 core images ✓, but **21 services still ship bare `:latest`** in their compose templates (*arr stack ×7 linuxserver images, jellyfin, seerr, dozzle, element-web, homepage, metabase, pihole, profilarr + parser, gluetun, raspberrymatic, recyclarr, renovate, sabnzbd, signal-cli-rest-api, sunshine, technitium), plus mutable aliases: `ollama/ollama:rocm` (explicitly named by security.md Flaw B — still unfixed), `home_assistant_version` default `stable`, immich default `release`. `docs/deployment-compose.md` *arr section openly says "`latest` tags, Renovate-tracked" — contradicting the law it is owned by. |
| D2 | **M** | `scripts/README.md`: validator checks "all **41** docker_services templates". | 49 template dirs (post-HD-166). Count is derived data — quote the directory, not a number. |
| D3 | **M** | `docs/security.md` §2: "Every `:latest` across the **42** compose templates → pinned (HD-61)". | Same drift; also HD-61 closed only the Traefik pin. |

## E. Vault & secrets naming

| # | Sev | Doc claim | IaC reality |
|---|-----|-----------|-------------|
| E1 | **M** | Vault called `Homelab` in: `IaC/README.md` (§nut secrets, §1Password table intro), `IaC/router/README.md`, `playbooks/dns.yml` + `playbooks/render-routeros.yml` comments, `scripts/README.md` ("No secrets outside 1Password Homelab"), `docs/1password.md` troubleshooting example. | `op_vault: Homelab-ansible` (`group_vars/all.yml`) is the single vault everywhere else (CONVENTIONS §1, deployment-secrets). All stray `Homelab` strings should become `Homelab-ansible` (or reference `op_vault`). |
| E2 | **M** | `IaC/README.md` 1Password table lists `router_login` as a live item. | Renamed long ago: `router_login` → `mikrotik-admin_login` (deployment-secrets rename map). |
| E3 | **M** | `deployment-tasks.md` Phase 0/5: `op_api` item marked "✓ In OP" and used as the Actions runner token. | `docs/1password.md` (HD-140): the `op_api` item is **intentionally NOT created**; the runner uses `Service Account Auth Token: ansible` from a Private vault. `deployment-secrets.md` keeps the `op_api` row with a partial note. Three documents, three different stories. |
| E4 | **L** | `docs/deployment-secrets.md` master list: entity count hand-stated as "**44 items**". | Table rows (incl. retired) exceed that; counts are derived data per CONVENTIONS §2 — drop the number or generate it. Also `openwebui_api` appears twice in the list; `opencloud_login` is referenced by the opencloud compose template but has no master-list row (only a passing mention). |

## F. Role / playbook / layout inventories

| # | Sev | Doc claim | IaC reality |
|---|-----|-----------|-------------|
| F1 | **M** | Role counts: `IaC/README.md` "(18)" implemented + proxmox stub; `docs/deployment.md` repository layout "roles/ # **12** roles". | 20 role dirs on disk (incl. `vps-hardening`, absent from the README list entirely). Counts are derived data (CONVENTIONS §2) — point at `roles/` instead of numbers. |
| F2 | **M** | `IaC/README.md` Implementation Status: RouterOS scripts "(2)". | Three `.rsc.j2` templates (rb4011, crs328, ap) rendered by `render-routeros.yml`; files moved to `IaC/router/templates/*.j2` while README/`network-ops.md` still reference `IaC/router/rb4011_initial.rsc`. |
| F3 | **M** | `docs/deployment-ansible.md` File Layout: playbooks tree missing switch/storage/dns/render-docs/render-routeros; lists `docker/tasks/main.yml` and `router/tasks/main.yml` twice each; shows `templates/nut/` (nut templates actually live in `roles/nut/templates/`); role tree omits cifs/cloudflare_dns/cockpit/switch/wireguard/vps-hardening/monitoring/docker_services positions. | Tree is decorative but wrong; a rebuild author would miss half the playbooks. |
| F4 | **M** | `docs/deployment-ansible.md` Execution Modes: guard whitelist "(`ansible-admin`, `pi`)". | `group_vars/all.yml` `ansible_admin_users: [ansible-admin]` only. |
| F5 | **L** | `IaC/README.md` contains literal duplicate lines: the `network` role TODO note appears twice back-to-back; `router/tasks/main.yml` twice in the tree. `docs/deployment-ansible.md` header has a mangled doubled sentence about native-Windows Ansible crashing; `docs/deployment-compose.md` duplicates the Grafana login-form bullet; `docs/security.md` §9 has a duplicated fragment line. | Copy/paste artifacts — safe bulk cleanup. |

## G. Backup / storage placement (VPS era)

| # | Sev | Doc claim | IaC reality |
|---|-----|-----------|-------------|
| G1 | **H** | `docs/backup.md` "What Gets Backed Up": PostgreSQL DBs (Authentik, Immich, Forgejo, PGVector) located "oldsrv NVMe"; excluded TSDB "lives on oldsrv local disk"; Kopia sources cite `/var/lib/forgejo-dump`, n8n sqlite on oldsrv. | Post-HD-135 those DBs and Prometheus/Loki live on the **VPS** (`group_vars/vps.yml`, `docs/storage.md` placement table, `hardware-oldsrv.md`). backup.md was partially updated (Kopia target, Boxes) but the location columns still describe the pre-split world. |
| G2 | **M** | `docs/hardware-nas.md` "TODO (IaC): nas storage role … doc-only in the planning phase". | `roles/storage/tasks/nas.yml` implements pool import/datasets/sanoid/NFS/Samba; todo HD-06/128 reflect it. Stale TODO box. |
| G3 | **M** | `docs/storage.md` final section "Proposed IaC (`storage` role — stub)": says "Proposed", contains typo "**3879** oldsrv `/etc/fstab` mounts". | Role implemented; section should be deleted (the real spec is `roles/storage/defaults/main.yml` + the doc's own dataset tables). |
| G4 | **M** | `docs/observability.md` Pi SD-card section: "Alloy ships logs → Loki (14d, **oldsrv NVMe**)". | Same doc's Placement section (and hardware-oldsrv.md) put the backend on the VPS. Internal contradiction inside one file. |

## H. Router / network

| # | Sev | Doc claim | IaC reality |
|---|-----|-----------|-------------|
| H1 | **M** | `docs/network-vlans.md` CAPsMAN table + `deployment-tasks.md` Phase 1.5 imply SSIDs/WPA provisioning ships with the redo. | `roles/router/tasks/main.yml` CAPsMAN section is a scoped TODO ("pending secrets"); APs boot into CAP mode with no controller config (also flagged in `IaC/router/README.md`). Docs should mark CAPsMAN ⏳ deploy-gated like other pending items. |
| H2 | **M** | VLAN map maintained as three parallel lists: `all.yml network_vlans` (subnets+pools+ssids), `router.yml vlans` (+Blackhole), `switch.yml switch_vlans` — kept equal only by "must match" comments. | No single-source derivation; a VLAN edit must touch three files. Either derive router/switch views from `network_vlans` at render time, or delete the duplicates and reference the SSOT. |
| H3 | **L** | `docs/network-ops.md` lifecycle step 1 says import `IaC/router/rb4011_initial.rsc`. | File lives at `IaC/router/templates/rb4011_initial.rsc.j2` and is rendered (secrets-injected) into gitignored `IaC/router/rendered/` — the committed template is never imported raw. |

## I. Tracking docs vs IaC (summary — details in `tracking-sugestions.md`)

| # | Sev | Doc claim | IaC reality |
|---|-----|-----------|-------------|
| I1 | **M** | `CONVENTIONS.md` §1: backlog "next free = `HD-114`". | todo uses up to HD-166, changelog to HD-174 → next free ≈ HD-175. Hand-entered derived number, guaranteed to rot — point at todo.md instead. |
| I2 | **M** | `deployment-tasks.md` Phase 6/7/9 rows reference TileBoard (HD-14 row), AnythingLLM + LocPilot (HD-28), watchtower-vs-Renovate (HD-39), broken network-devices link (HD-35) as open work. | All four decided/closed in changelog (HD-24, HD-108, HD-39, HD-35). Phase text was never swept after the decisions landed. |
| I3 | **M** | `todo.md` §2.4 contains a duplicated table-header row; §2.6 table is split by a blank line so HD-14…HD-27 render as loose paragraphs, not table rows. | Markdown defects that hide backlog rows in any renderer. |
| I4 | **M** | `docs/security.md` decision-log entries dated 2025-08-16 (also services-ai.md decision table, deployment-tasks header, changelog HD-51/92/93 rationale lines). | Repo timeline is 2026; these are typos that make the decision log look a year older than it is. Sweep all `2025-08` occurrences. |

---

## Verdict

The IaC itself is internally consistent and ahead of the docs: group_vars/host_vars/playbooks agree
with each other and with the generated views. The contradictions are almost entirely **docs lagging
the two big recent decisions** (HD-135 VPS split, HD-13 Homematic parking) plus **derived counts and
names hand-entered in prose** (role/template counts, vault name, next-HD, item counts) — exactly the
class CONVENTIONS §2 already declares a defect. Recommended order of attack:

1. Fix [H] items first (A1–A5, B1, C1, D1, G1) — each can mislead an actual deploy.
2. Sweep [M] inventory/naming drift in one pass (E, F, H, I).
3. Add the missing convention: *counts and ID pointers are never hand-entered in prose* is already
   law — extend enforcement (doc-map linter or a grep gate) to root/IaC README files, not just `docs/`.

> Cross-refs: structural fixes → `iac-changes.md`; doc consolidation → `docs-changes.md`; security
> detail → `security.md`; phase/tracking restructure → `tracking-sugestions.md`.

---

## Deep-dive addendum (round 2, same day) — role/template verification pass

Follow-up pass that read `roles/router` + `roles/switch` in full, the `docker_services` deploy role,
and all 49 compose templates line-by-line. New contradictions found (verified against source):

| # | Sev | Finding |
|---|-----|---------|
| J1 | **H** | **Immich ML URL points at a container name that cannot resolve.** `immich-app/docker-compose.yml.j2` sets `IMMICH_MACHINE_LEARNING_URL: "http://immich-ml:3003"` — but immich-ml deploys on **oldsrv**; immich-app on the **VPS**. Docker DNS cannot cross hosts; the comment right above says "ML on oldsrv GPU (WG tunnel)". The value must be the oldsrv address reachable over `wg-vps-services` (derived from SSOT, like `alloy_backend_host`). ML is broken on first VPS deploy as written. |
| J2 | **H** | **Pi first-deploy ordering bug (docker_services vs home_assistant).** `playbooks/raspberry_pi.yml` runs docker_services **before** home_assistant (KOPS-063/HD-117), but `roles/home_assistant/tasks/pi.yml` header still says "renders its config/keepalived files first (playbook order: home_assistant → docker_services)" — the reverse. At first `docker compose up` for home-assistant-primary, Docker auto-creates missing bind sources `./config`, `./secrets.yaml`, `./keepalived.conf` as **empty directories**; the HA role's subsequent `copy keepalived.master.conf → keepalived.conf` then fails (destination is a directory) and the HA container keeps running default config with no restart handler. Deploy-blocking on the Pi path. |
| J3 | **H** | **ACME dual-issuer is an IaC bug, not just a doc ambiguity (escalates §C1).** `traefik/docker-compose.yml.j2` self-describes as "THE ACME issuer for the wildcard" (DNS-01 + acme.json + certs-dumper sidecar) — and the same unmodified template deploys on **both** oldsrv and the VPS (`group_vars/vps.yml` enables traefik). Two ACME clients issuing the same wildcard via DNS-01 = Let's Encrypt rate-limit collisions and divergent `acme.json`/certs-dumper outputs on two hosts; the Pi cert-sync contract ("reads /opt/traefik/certs on oldsrv") silently breaks if the VPS copy wins. Needs an explicit issuer parameter (ACME enabled on exactly one host; the other consumes synced certs). |
| J4 | **M** | **Pi-hole conditional forwarding points at the HA VIP.** `pihole/docker-compose.yml.j2`: `CONDITIONAL_FORWARDING_IP: "{{ ha_vip }}"` — the keepalived VIP serves HA/traefik-ha (:8123/:443), **not DNS**. Local-name resolution via Pi-hole is broken as written; should be the Technitium primary IP (`dns_primary_ip`). |
| J5 | **M** | **oldsrv has no Kopia agent.** `backup.md` (Kopia path) says agents run on **VPS + oldsrv** (sources: `/srv/dumps`, service state, face thumbs, `/opt/*` configs); `group_vars/home_servers.yml` contains **no kopia entry** — only the VPS runs `kopia-server`/`db-backup`. oldsrv-local state therefore has no off-site backup path in the SSOT. Either add a kopia agent service for oldsrv or rewrite backup.md to the VPS-agent-only reality. |
| J6 | **M** | **Kids VLAN firewall is a debug placeholder.** `roles/router/tasks/main.yml`: `debug: msg="Kids VLAN bedtime restriction ... Pending implementation."` — no Kids→Home drop, no DNS-force-to-filter rule, no time-based WAN block. `network-vlans.md` documents all three as part of the firewall matrix and `deployment-tasks.md` Phase 1.5 verifies "inter-VLAN reachability matches the firewall matrix". Docs must mark Kids rules ⏳ (or the role must implement them) before Phase 1.5 verification can pass. |
| J7 | **M** | **DNS parity gaps (router role vs network-dns.md).** (a) DHCP hands out primary+secondary Technitium to **every** VLAN, but the forward firewall rule only permits cross-VLAN DNS to `dns_primary_ip` — a failover to the **secondary on pi** is unreachable from IoT/Kids/Guest (the exact scenario the secondary exists for). (b) The doc's "router /ip dns as tertiary fallback" is not configured in IaC (DHCP `dns-server` = primary+secondary only). |
| J8 | **M** | **`trusted-ha` address-list is created but never used.** The Home→IoT new-connection rule uses `trusted-admin` (which also contains **nas**), so nas gains new-connection reach into IoT beyond what the doc matrix describes, and the documented `trusted-ha` list role (smart-home-failover.md §Decided) doesn't match the IaC. Functional overlap masks it today (both lists contain oldsrv+ha-vip). |
| J9 | **M** | **Cockpit routes: zero edge middleware + hardcoded IPs.** `roles/cockpit/templates/cockpit-routes.yml.j2` renders `cockpit-nas`/`cockpit-oldsrv` with **no middleware at all** (not even `crowdsec-only@file` — the §1 law's minimum) and hardcodes the nas/oldsrv Home-IP literals, violating the never-hardcode-IPs convention (`services.md` says "IP per SSOT"). |
| J10 | **M** | **Homepage public-root mechanism missing on the VPS.** The homepage Traefik labels are Docker-provider labels — they only work on the Traefik sharing its network (oldsrv). `kogler.si`/`home` therefore has **no route on the VPS public edge**; the doc claim "public at root behind Forward-Auth" has no VPS-side implementation (confirms §A6 with the mechanism). Also `HOMEPAGE_ALLOWED_HOSTS: {{ domain_local }}` omits the `home.` alias → Host-header rejection on `home.kogler.si`. |
| J11 | **L** | **Master-list gaps confirmed by matrix sweep:** `privado-vpn_api` (gluetun) appears in the type-map examples but has **no master-list row**; `opencloud_login` is consumed by the opencloud compose and also missing. 45 distinct 1Password items are referenced across templates+roles; all provisioner-catalog items are consumed (no catalog orphans). db-backup DB01–04 (authentik/forgejo/immich/pgvector) all present ✓; `ks-oidc.yml` declares exactly the 8 documented providers ✓. |
| J12 | **L** | **Post-deploy Git hook is doc-only.** `interfaces.md` pipeline step 5 ("commit + push updated docs to Git") has no counterpart task in the `docker_services` role (it renders the inventory doc into the repo checkout, nothing more). |
| J13 | **L** | **storage.md claims `nvme/docker/services` daily(7) snapshots; `storage_sanoid` has no nvme/* entries** — the oldsrv-side snapshot documented in storage.md is not implemented (nas-side cadences match storage.md exactly; datasets/properties otherwise verified in full parity ✓). |

**Verified-good in the same pass (no action):** HD-155 RouterOS ACL fully implemented (`vps_s2s_peer` accept→`vps_scoped_home`, then DROP-all-else, fail-closed pubkey assert); INPUT-chain mgmt gating + SNMP Mgmt-only ACL exactly as documented; WG S2S peer/allowed-addresses/route; storage role dataset/property/sanoid parity with storage.md; middleware law enforced on every labelled route except the two documented exceptions below; Alloy per-host instance label (HD-116) present; `network-snmp_api` fail-loud; alert tiers cover the documented Critical/Warning classes (plus WG-tunnel-down).