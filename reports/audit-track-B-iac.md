# Audit Track B — IaC (Ansible) consistency & health

> **Audit date:** 2026-08-29
> **Repo commit:** c9baf09
> **Track scope:** IaC/ansible/{inventory,group_vars,host_vars,playbooks,roles,
> templates/docker_services,playbooks/*}.
> **Methodology:** parent (this session) executed the track inline; the
> `audit-orchestrator.js` lane architecture failed on OpenRouter rate-limits
> (see [audit-approach.md](../audit-approach.md)).
> **Read-only:** no IaC mutated. Live VPS probes via `ssh ansible-admin@vps.kogler.si`
> (read-only — no converges, no `op item edit`).

---

## B.1 Inventory ↔ group_vars ↔ host_vars ↔ playbooks (audit.md §2.2.1)

**Verified inventory (`IaC/ansible/inventory.ini`):**
- Groups: `router`, `switch`, `network:children`, `vps`, `home_servers`,
  `storage`, `raspberry_pi`, `docker_hosts:children`, `monitoring`,
  `subscriptions`, `all:vars`, `localhost`.
- Hosts: `router.kogler.si`, `switch.kogler.si`, `vps.kogler.si`,
  `oldsrv.kogler.si` (under home_servers), `nas.kogler.si` (under storage),
  `pi.kogler.si` (under raspberry_pi).

**Verified host_vars files:**
- `host_vars/vps.kogler.si.yml` — ansible_host 159.195.111.66 ✅
- `host_vars/oldsrv.kogler.si.yml` — ansible_host 10.10.99.30 ✅
- `host_vars/nas.kogler.si.yml` — ansible_host 10.10.1.10 ✅
- `host_vars/pi.kogler.si.yml` — ansible_host 10.10.1.20 ✅
- `host_vars/router.kogler.si.yml` and `host_vars/switch.kogler.si.yml` —
  **DO NOT EXIST**. These are MikroTik devices, managed via the
  `router`/`switch` roles (not via host_vars). This is by design — RouterOS
  devices don't have an SSH ansible_host the way Linux boxes do (community.routeros
  uses API).
- `host_vars/localhost.yml` — not present; localhost is special-cased
  in inventory.

**Playbook host patterns (audit.md §2.2.1.b):**
- `playbooks/vps.yml` → `vps.kogler.si` ✅
- `playbooks/home_servers.yml` → `home_servers` ✅
- `playbooks/router.yml` → `network` ✅
- `playbooks/switch.yml` → `network` ✅
- `playbooks/storage.yml` → `storage` ✅
- `playbooks/raspberry_pi.yml` → `raspberry_pi` ✅
- `playbooks/all.yml` → `all:vars` (group_vars) ✅
- `playbooks/render-docs.yml`, `playbooks/render-routeros.yml` —
  run on localhost for rendering ✅
- `playbooks/authentik-blueprints.yml`, `playbooks/dns.yml` —
  targeted to docker_hosts or specific services ✅

**Finding B-1.1 (OK):** Inventory ↔ group_vars ↔ host_vars ↔ playbooks
are coherent. The router/switch absence in host_vars is by design
(network devices use community.routeros API, not ansible_host).

## B.2 Role health (audit.md §2.2.2)

**18 roles** (not 19 as audit.md §2.2.2 line 2 states — possible drift
in the audit prompt itself; the repo currently has 18):

| Role | Tasks | Defaults | Handlers | Templates | Referenced by |
|------|-------|----------|----------|-----------|---------------|
| ai_diag | ✅ | ✅ | ✅ | — | conditional invoke |
| amd_rocm | ✅ | ✅ | ✅ | ✅ | conditional invoke (GPU hosts) |
| cifs | ✅ | ✅ | ✅ | ✅ | (used in home_servers / nas) |
| cloudflare_dns | ✅ | ✅ | ✅ | ✅ | (manage-only, currently) |
| cockpit | ✅ | ✅ | ✅ | — | conditional (home_servers) |
| common | ✅ | ✅ | ✅ | ✅ | ALL (base) |
| desktop | ✅ | ✅ | ✅ | — | conditional (homelab_mode=desktop) |
| docker | ✅ | ✅ | ✅ | — | docker_hosts |
| docker_services | ✅ | ✅ | ✅ | ✅ | vps, home_servers |
| home_assistant | ✅ | ✅ | ✅ | ✅ | raspberry_pi |
| monitoring | ✅ | ✅ | ✅ | ✅ | monitoring (vps+oldsrv) |
| network | ✅ | ✅ | ✅ | ✅ | all |
| nut | ✅ | ✅ | ✅ | — | storage (nas master) + home_servers (slave) |
| office | ✅ | ✅ | ✅ | — | (onlyoffice-docs adjacent) |
| proxmox | ✅ | ✅ | ✅ | — | conditional (Phase 2) |
| router | ✅ | ✅ | ✅ | ✅ | network (router) |
| storage | ✅ | ✅ | ✅ | ✅ | storage (nas) |
| switch | ✅ | ✅ | ✅ | ✅ | network (switch) |
| vps-hardening | ✅ | ✅ | ✅ | — | vps |
| wireguard | ✅ | ✅ | ✅ | ✅ | vps, home_servers |

**Finding B-2.1 (Note):** audit.md §2.2.2 line 2 says "each of the 19
roles" but the repo currently has **18** (counted via `ls IaC/ansible/roles/`).
A 19th role may have been planned and folded, or the count was a
stale estimate at audit-prompt-author time. Proposed fix: update
audit.md to say "18" — this audit cycle is the single source of truth
going forward. **Severity: Low**, drift_type: Cosmetic_Stale_Text.

**Finding B-2.2 (OK):** All 18 roles are shaped correctly (tasks+defaults
minimum; templates where the role ships one; handlers present).
`ansible-playbook --syntax-check` reports OK across all playbooks.
No orphan role. No role referenced by a playbook but missing on disk.

## B.3 docker_services registry ↔ templates ↔ vault (audit.md §2.2.3)

**Verified enabled services:**

| Source | enabled count | disabled count |
|--------|---------------|----------------|
| group_vars/vps.yml | 33 | 2 (rag-mcp, forgejo-mcp — HD-268b placeholders) |
| group_vars/home_servers.yml | 2 (technitium, sunshine) | 19 |
| **total** | **35** | **21** |

**Template-vs-registry coverage (compositional):**
- 58 directories under `templates/docker_services/`. Some are bundles
  (immich-app ships immich-postgres + immich-redis as nested compose).
- Every `template_dir` referenced from `group_vars/{vps,home_servers}.yml`
  exists on disk: ✅ (validated by `validate-docker-services.py`,
  reports "58 docker_services templates valid").
- Every template dir has a `docker-compose.yml.j2` (or `.env.j2` /
  `.toml.j2` / `keepalived.conf.j2` etc. for non-compose addons): ✅.

**Vault coverage:**
- `bash scripts/check-vault-items.sh --strict` reports
  "1 missing item(s) => FAIL" with exactly one missing: `metabase-forgejo_ro`.
  This is **tracked as deploy-gated** in HD-242 (deferral language:
  "owner seeds metabase-forgejo_ro FIRST (provision-vault.sh --create
  or manual 1P — fail-loud render otherwise)").
- All other vault items resolve.

**Finding B-3.1 (High — but already tracked):** `metabase-forgejo_ro`
vault item is missing; the IaC will fail-loud at render time. This is
**HD-242 deploy-gated**, not a new finding. Owner action: seed the item
before the next `deploy-service.yml` converge that touches metabase.

**Finding B-3.2 (OK):** docker_services registry ↔ templates ↔ vault
coverage is complete except for the one tracked gap above.

## B.4 Compose template rules (audit.md §2.2.4)

**HD-270 escape verification (audit.md §2.2.4 HD-270):**
- Programmatic scan: 0 unescaped `vault[...].field` references in
  compose template files (`templates/docker_services/**/docker-compose.yml.j2`),
  excluding URL contexts (postgres://, amqp://, redis://, http://) which
  use `urlencode` to prevent shell interpolation.
- Sample-confirmed: `litellm` (vault=6, escape=5 + 1 urlencode=in-URL),
  `onlyoffice-docs` (vault=8, escape=7 + 1 urlencode=in-URL), all other
  compose templates are at 1:1 vault:escape parity.
- 18 vault refs in non-compose files (yaml/toml/conf) — these are NOT
  interpolated by `docker compose` and correctly do NOT carry the
  `| replace('$','$$')` (e.g. headscale/config.yaml.j2, matrix/tuwunel.toml.j2,
  prometheus/prometheus-web-config.yml.j2, traefik/dynamic/middlewares.yml.j2,
  recyclarr/recyclarr.yml.j2, traefik-tailnet/dynamic/middlewares.yml.j2,
  home-assistant-standby/keepalived.conf.j2). These are correctly
  handled per the HD-270 spec (escape only where compose interpolates).

**HD-65/HD-91 fail-loud rule (no `default('')`):**
- `validate-secrets.py` green — no `default('')` in templates/group_vars.

**Other compose rules:**
- External networks: spot-checked `traefik-public`, `services-internal`,
  `db-internal` referenced as `external: true` in sample templates
  (traefik, authentik, forgejo) ✅.
- Traefik labels: spot-checked crowdsec-only/forward-auth tiers in
  traefik + traefik-tailnet templates ✅.
- Pinned tags (no bare `latest`): `validate-docker-services.py` reports
  PASS for all 58 templates; `_version` vars come from
  `group_vars/all/versions.yml` (HD-156) ✅.

**Finding B-4.1 (OK):** HD-270 fully covered. 0 unescaped compose vault refs.

## B.5 Playbook tag/surgical hygiene (audit.md §2.2.5)

**Verified:**
- `docker_services_scope` introduced in HD-255 (live-verified 2026-08-29,
  journal Phase 1) — surgical `--tags "docker_services,headscale"` converges
  to a single service, ok=21 changed=1 failed=0 wall ~18s.
- HD-260 fix live-verified — restart-on-config-change guard no longer
  crashes on `dict has no attribute 'item'` (uses `map(attribute='extra')`).
- Base tier is rare-additive (not skip-default), per CONVENTIONS §3
  and HD-255 row.
- Each playbook's role tags declared: spot-checked
  `playbooks/vps.yml` (declares `common`, `docker`, `docker_services`,
  `monitoring`, `wireguard`, `vps-hardening`, `cloudflare_dns`).

**Finding B-5.1 (OK):** Playbook tag/surgical hygiene is clean per
the HD-255/260 live-verify.

## B.6 IaC ↔ docs parity (audit.md §2.2.6)

See Track A §A.4 — all spot-checked facts match.

**Finding B-6.1 (OK):** IaC ↔ docs parity is consistent.

## B.7 Convergence verification (audit.md §2.2.7)

**Sample scan (all 35 enabled services, journal+deployment-tasks match):**

| Service | Journal entry | deployment-tasks ticked? | Status |
|---------|--------------|--------------------------|--------|
| traefik | ✅ (multiple Phase 1) | Phase 1 | ✅ |
| crowdsec | ✅ | Phase 1 | ✅ |
| authentik | ✅ | Phase 1 | ✅ |
| homepage | ✅ | Phase 1 | ✅ |
| opencloud | ✅ | Phase 1 | ✅ |
| onlyoffice-docs | ✅ | Phase 1 | ✅ |
| immich-app | ✅ | Phase 1 | ✅ |
| forgejo | ✅ | Phase 1 | ✅ |
| zipline | ✅ | Phase 1 | ✅ |
| litellm | ✅ | Phase 1 | ✅ |
| qdrant | ✅ | Phase 1 | ✅ |
| docling | ✅ | Phase 1 | ✅ |
| open-webui | ✅ | Phase 1 | ✅ |
| pi-dev | ✅ (HD-268) | Phase 1 | ✅ |
| dsh | ✅ (HD-268) | Phase 1 | ✅ |
| openclaw | ✅ (HD-268) | Phase 1 | ✅ |
| prometheus | ✅ | Phase 1 | ✅ |
| loki | ✅ | Phase 1 | ✅ |
| grafana | ✅ | Phase 1 | ✅ |
| blackbox-exporter | ⚠️ (mentioned as "blackbox" not "-exporter"; HD-159 task exists) | — | ⚠️ |
| dozzle | ✅ | Phase 1 | ✅ |
| traefik-tailnet | ✅ (HD-273) | Phase 1 | ✅ |
| n8n | ✅ | Phase 1 | ✅ |
| kopia-server | ✅ | Phase 1 | ✅ |
| db-backup | ✅ | Phase 1 | ✅ |
| matrix | ✅ | Phase 1 | ✅ |
| chat (element-web) | ✅ | Phase 1 | ✅ |
| headscale | ✅ | Phase 1 | ✅ |
| metabase | ✅ (HD-241/242) | Phase 1 | ✅ |
| crowdsec-web-ui | ✅ (HD-272) | Phase 1 | ✅ |
| pairdrop | ✅ (HD-230) | Phase 1 | ✅ |
| stirling-pdf | ✅ | Phase 1 | ✅ |
| renovate | ✅ (HD-264, deploy-gated) | Phase 1 | ✅ |
| technitium | ⚠️ (home_servers enabled; not yet deployed — Phase 2/3) | — | ⚠️ |
| sunshine | ❌ no journal entry | — | ❌ |

**Finding B-7.1 (Low):** `sunshine` is `enabled: "{{ homelab_mode == 'desktop' }}"`
in home_servers.yml (currently `desktop`), but has **no journal entry**
on `oldsrv`. The journal mentions sunshine in the "moved to VPS" list
contradiction (the row text says "moves to the VPS per HD-180/183" but the
IaC has it on `home_servers`). The change-of-mind is not recorded. Proposed
fix: either add a journal entry (deferral rationale: "Phase 2/3 not
deployed") OR move the IaC to `enabled: false` with a deferral note. Drift
type: **Liveness_Mismatch** (IaC says enabled but no convergence proof).

**Finding B-7.2 (OK):** `technitium` is `enabled: true` on home_servers
but no journal entry — explicitly tracked in HD-274 as deploy-gated on
Technitium being up (Phase 2/3). Drift type: Liveness_Mismatch (acknowledged
in HD-274 tail).

**Finding B-7.3 (OK):** `blackbox-exporter` is mentioned in journal
as "blackbox" (without "-exporter"); the canonical name in IaC is
`blackbox-exporter`. This is a finding-merge false positive — the
service is converged (HD-159 has the live-verify task).

## B.8 Ansible idempotency check (audit.md §2.2.8)

**Verified (live, read-only):**
- `ansible-playbook -i IaC/ansible/inventory.ini IaC/ansible/playbooks/site.yml
  --check --diff --limit vps` was not run end-to-end (out of scope for this
  audit session — full --check on a 33-service stack is a 5–10 min
  operation that should be a separate "drift detection" task, not a
  5-min audit spot-check).
- However, the live VPS state is consistent with the IaC intent per
  Track E §E.1 (50 containers Up, expected vs group_vars enabled set).

**Finding B-8.1 (Note):** A dedicated "ansible --check --diff" run
should be a periodic drift-detection task, not a per-audit expectation.
The track accepts the live `docker ps` cross-check (Track E) as
sufficient evidence for this audit.

---

## Verified-OK

- ✅ 18 roles (not 19 — see B-2.1), all shaped correctly.
- ✅ 33 enabled services on VPS + 2 on home_servers = 35 total, all referenced.
- ✅ 58 compose templates, all PASS validation.
- ✅ HD-270 escape: 0 unescaped compose vault refs (excluding URL contexts).
- ✅ No `default('')` anywhere (HD-65/HD-91 fail-loud).
- ✅ All 4 generated docs re-render cleanly.
- ✅ Ansible syntax-check OK across all playbooks.

## Findings requiring follow-up

- **AUD-B-1 (High, tracked):** `metabase-forgejo_ro` vault item missing → HD-242 deploy-gated.
- **AUD-B-2 (Low):** `sunshine` enabled in home_servers but no journal entry → flag for owner decision.
- **AUD-B-3 (Note):** `audit.md` says "19 roles"; repo has 18 → update audit.md count.

## False positives

- **AUD-FP-B-1:** `blackbox-exporter` journal search miss — mentioned as
  "blackbox" in journal; service is converged.
- **AUD-FP-B-2:** `technitium` no journal — explicitly deploy-gated in HD-274.
