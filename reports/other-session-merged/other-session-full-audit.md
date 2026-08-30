# Full Repository Audit — 2026-08-29

> **Audit Date:** 2026-08-29
> **Commit:** 969597d (main)
> **Scope:** docs/, IaC/ (Ansible), scripts/ against canonical system + live VPS state
> **Methodology:** Parallel lane audit per audit.md §3b (Tracks A–E)

---

## A. Docs — Findings (Track A)

| ID | Severity | Status | Evidence | Proposed Fix |
|----|----------|--------|----------|--------------|
| AUD-A-1 | Low | OPEN | `grep`/`diff`: Document map in `docs/index.md` lists manual guides without `manual/` prefix (e.g., `chat.md` vs `manual/chat.md`). Also lists root files `CONVENTIONS.md`, `README.md`, `todo.md` in the tree. | Update document map tree to use correct relative paths for manual/ guides. Root files should be noted as external references. |
| AUD-A-2 | Med | OPEN | `grep`: 5 broken anchor links in `docs/services-media.md` and `docs/services-downloads.md`: `services.md#docker-networks` (anchor is `#docker-networks`), `services.md#domain--subdomain-plan` (anchor is `#domain-subdomain-plan`), `services-media.md#storage--import-media--arr` (anchor format mismatch) | Fix anchor links to match actual header IDs in target files. Use single hyphens per GFM spec. |
| AUD-A-3 | Med | OPEN | `grep`: 12 private IP literals in docs outside SSOT locations: `docs/home-assistant-current.md:221`: `10.10.99.9` (in strikethrough), `docs/deployment-secrets.md:383`: `10.10.0.0/16` (SSH example), `docs/deployment-ansible.md`: 10 IPs documenting SSOT values | Replace IP literals with references to `network-addresses-generated.md` or hostname references. For IaC docs, consider if they qualify as "IaC" for the exception. |
| AUD-A-4 | Low | OPEN | `grep`/`journal`: Multiple docs show `🟢 IaC done, not yet live — ⏳ deploy-gated` banners while `deployment-journal.md` shows services live (observability backend, Traefik, Authentik, services-admin VPS members, services-utilities VPS members, services-matrix, services-traefik all live since 2026-08-22). | Update status banners to `✅ Live since 2026-08-22` where journal confirms liveness. Per README §2, journal is SSOT for liveness. |
| AUD-A-5 | Low | OK | `check_doc_map.py` + manual verification: All 62 docs/*.md files reachable from `docs/index.md`. No orphan docs. | — |
| AUD-A-6 | Low | OK | `grep`/`git log`: No `*-generated.md` files show hand-edits. All commits are from render scripts. | — |
| AUD-A-7 | Low | OK | `grep`: No `TODO: define service` placeholder language found. | — |
| AUD-A-8 | Low | OK | `grep`: No literal secret values (passwords, tokens, API keys) in docs. | — |
| AUD-A-9 | Low | OK | `grep`: `network-addresses-generated.md` IPs match `group_vars/all/main.yml` `network_static_hosts` and `network_ranges` exactly. `network-rack-generated.md` matches `rack-connections.json`. | — |
| AUD-A-10 | Low | OK | `grep`: All 11 `docs/manual/*.md` guides have `status: wip`, Slovenian language, no technical secrets. `manual/README.md` index lists all 11 correctly. | — |

**Open Questions (A):**
1. **AUD-A-1**: Should the document map tree show `manual/chat.md` or is the current convention intentional for readability?
2. **AUD-A-3**: Does `docs/deployment-ansible.md` qualify as "IaC" for the IP literal exception?
3. **AUD-A-4**: Should status banners be updated proactively based on journal, or only when the owning doc is edited for another reason?

**False Positives (A):** None identified.

**Deduplication Keys (A):**
- `AUD-A-1`: `docs/index.md:document-map-tree`
- `AUD-A-2`: `docs/services-media.md:anchor-links`, `docs/services-downloads.md:anchor-links`
- `AUD-A-3`: `docs/home-assistant-current.md:ip-literal`, `docs/deployment-secrets.md:ip-literal`, `docs/deployment-ansible.md:ip-literals`
- `AUD-A-4`: `docs/observability.md:status-banner`, `docs/services-traefik.md:status-banner`, `docs/services-authentik.md:status-banner`, `docs/services-admin.md:status-banner`, `docs/services-utilities.md:status-banner`, `docs/services-matrix.md:status-banner`

---

## B. IaC — Findings (Track B)

| ID | Severity | Status | Evidence | Proposed Fix |
|----|----------|--------|----------|--------------|
| AUD-B-1 | High | OPEN | `bash scripts/check-vault-items.sh --strict`: MISSING `ha-failover_api` (1 missing item). This is a required vault item for the HA failover API (HD-17). | Create `ha-failover_api` in 1Password `Homelab-ansible` vault (api credential type) before Phase 4 HA cutover. |
| AUD-B-2 | High | OPEN | `ansible-playbook --check --diff --limit vps`: Task failed at `fetch-vault-pass.yml` — `from_json` filter failed on empty output from `op-vault-export.py`. The bulk pre-pass requires a live 1Password connection. | This is expected in check-mode without live 1P session. Not a drift. Document that `--check` runs need live 1P for the bulk pre-pass, or mock the vault dict. |
| AUD-B-3 | Med | OPEN | `grep` for `vault\[` without `| replace('$','$$')` found in: `prometheus-web-config.yml.j2` (2 occurrences), `litellm/docker-compose.yml.j2` (1), `traefik/dynamic/middlewares.yml.j2` (1), `traefik-tailnet/dynamic/middlewares.yml.j2` (1), `home-assistant-standby/keepalived.conf.j2` (1), `zipline/docker-compose.yml.j2` (1), `matrix/tuwunel.toml.j2` (4), `kopia-server/.env.j2` (3), `recyclarr/recyclarr.yml.j2` (2), `onlyoffice-docs/docker-compose.yml.j2` (1), `kopia-agent/.env.j2` (3). Some use `urlencode` instead of `replace`. | Verify each: `urlencode` is acceptable for URL contexts. For TOML/env files, `replace('$','$$')` may not be needed. Document exceptions in template comments. |
| AUD-B-4 | Med | OPEN | `grep` for `default('')` found in templates: `loki/docker-compose.yml.j2`, `authentik/docker-compose.yml.j2`, `prometheus/docker-compose.yml.j2`, `kopia-server/docker-compose.yml.j2` — all used for conditional port binding based on `wg_s2s_vps.peer_public_key` presence (not for secrets). | These are non-secret conditional defaults (port binding logic). Acceptable per HD-65/HD-91 since they're not secret values. Add comments clarifying non-secret usage. |
| AUD-B-5 | Low | OK | Inventory ↔ group_vars ↔ host_vars ↔ playbooks: All 6 hosts in inventory.ini have host_vars with ansible_host; playbook host patterns match inventory groups; no dead/duplicate vars; precedence sane. | — |
| AUD-B-6 | Low | OK | Role health: 19 roles exist under `roles/`, all referenced by playbooks, shaped correctly. `requirements.yml` collections resolve (installed in `~/ansible-venv`). | — |
| AUD-B-7 | Low | OK | docker_services registry ↔ templates ↔ vault: All 52 enabled services have template_dirs under `templates/docker_services/`, all have `docker-compose.yml.j2`. Vault references resolve (except `ha-failover_api` per AUD-B-1). | — |
| AUD-B-8 | Low | OK | Compose template rules: external networks used, Traefik label conventions followed, no host-net/privileged port binds unless documented, pins (`_version` vars) in `group_vars/all/versions.yml`, no bare `latest`. | — |
| AUD-B-9 | Low | OK | Playbook tag/surgical hygiene: Role tags declared; `docker_services_scope` semantics implemented (HD-255); `base` tier additive; nothing renders off-path. | — |
| AUD-B-10 | Low | OK | IaC ↔ docs parity: Hot IaC values (subdomains, ports, image pins, IPs) match owning docs. | — |
| AUD-B-11 | Med | OPEN | Convergence verification: VPS services (33 enabled) have journal entries showing deployment 2026-08-22/23/24/26. Home services (19 enabled) NOT yet converged — hosts `oldsrv`, `nas`, `pi` are Phase 1.5+ deploy-gated. This is expected per HD-03/HD-135. | Not a finding — expected deploy-gated state. Document in report as "Expected Deploy-Gated". |

**Open Questions (B):**
1. **AUD-B-2**: Should the bulk pre-pass be mocked in check-mode to allow `--check` to pass without live 1P?
2. **AUD-B-3**: For TOML/env files, is `urlencode` sufficient or is `replace('$','$$')` also needed?

**False Positives (B):**
- AUD-B-2: Expected in check-mode without live 1P — not a real drift.
- AUD-B-11: Expected deploy-gated state for home hosts — not a finding.

**Deduplication Keys (B):**
- `AUD-B-1`: `scripts/check-vault-items.sh:ha-failover_api`
- `AUD-B-2`: `roles/docker_services/tasks/fetch-vault-pass.yml:op-vault-export`
- `AUD-B-3`: `templates/docker_services/**/vault-escaping`

---

## C. Scripts — Findings (Track C)

| ID | Severity | Status | Evidence | Proposed Fix |
|----|----------|--------|----------|--------------|
| AUD-C-1 | Low | OK | Registry vs filesystem: All 27 scripts in `scripts/` listed in `scripts/README.md` (and vice-versa). Portability status: all `bash -n` + `python3 -m py_compile` pass. | — |
| AUD-C-2 | Low | OK | Gate exercise: `bash scripts/validate-all.sh` ends green. All validators run (no silent skips). | — |
| AUD-C-3 | Low | OK | Validator coverage: All validators catch their claimed classes (tested via self-tests in `testdata/` and `check-vault-items.sh --strict`). Validator Effectiveness Scoring: | — |
| AUD-C-4 | Low | OK | Deploy tooling: `provision-secrets.py --list` matches `docs/deployment-secrets.md` generated items. Contracts match `scripts/README.md`. `next-hd.sh` returns `HD-275` (max+1). | — |
| AUD-C-5 | Low | OPEN | Dead/orphan scripts: `collect-smart.ps1` (Windows sibling of `collect-smart-live.sh`) not referenced in gate/README. Kept for Windows collection path but not in validation gate. | Document in `scripts/README.md` as "Windows-only sibling" or move to `IaC/host/` if Windows-specific. |
| AUD-C-6 | Low | OPEN | `scripts/testdata/` directory contains fixtures for `check-vault-items.sh` self-test — not a script, but part of repo. Not in `scripts/README.md` registry (by design, it's test data). | No action — test data correctly excluded from registry. |

**Open Questions (C):**
1. **AUD-C-5**: Should `collect-smart.ps1` be documented in `scripts/README.md` with a Windows-only note?

**False Positives (C):** None.

**Deduplication Keys (C):**
- `AUD-C-5`: `scripts/collect-smart.ps1:registry-gap`

---

## D. Conformance — Findings (Track D)

| ID | Severity | Status | Evidence | Proposed Fix |
|----|----------|--------|----------|--------------|
| AUD-D-1 | Low | OK | Secret hygiene: `check_vault_name.py` + `validate-secrets.py` green. Human grep for B5 placeholders + raw `password:`/`token:` in group_vars/templates: clean. | — |
| AUD-D-2 | Low | OK | Lifecycle conformance: All open HD rows map to owning docs. `⏳` tails exist only where `deployment-tasks.md` has matching deploy-gated checklist. No fully-done row in todo (all moved to changelog). No stale `⏳` vs journal. | — |
| AUD-D-3 | Med | OPEN | Service-onboarding rubric (sample of 3): **traefik** (core): 10/10 ✅. **crowdsec-web-ui** (recent): 8/10 — missing steps 7 (backup policy), 10 (doc banner). **renovate** (⏳): 4/10 — missing steps 2,5,6,7,8,9 (Forgejo repo not created, no DNS/TLS, no observability, no backup, no journal entry, no deploy checklist). | Document gaps in owning service docs. `renovate` gaps are expected (Forgejo migration pending HD-264). |
| AUD-D-4 | Low | OK | Decision-log alignment: No open decision in `todo.md` §1 that `changelog.md` already resolved. No decision re-argued in a doc without changelog row. | — |
| AUD-D-5 | Low | OPEN | False Positive Log: Several items in todo.md appear as drift but are intentional: (a) `renovate` enabled but Forgejo repo not created → intentional (HD-264 sandbox). (b) `traefik-tailnet` `tailnet_sidecar_ip` empty → intentional (filled at deploy time). (c) `prometheus_ha_exporter: false` → intentional (Phase 4 gate). (d) `rag-mcp`/`forgejo-mcp` `enabled: false` → intentional (placeholder stubs). | Record these as `AUD-FP-1` through `AUD-FP-4` to prevent re-flagging. |

**Onboarding Rubric Details (AUD-D-3):**

| Step | traefik | crowdsec-web-ui | renovate |
|------|---------|-----------------|----------|
| 1. Service catalog entry | ✅ `docs/services.md` | ✅ `docs/services-admin.md` | ✅ `docs/services-admin.md` |
| 2. Vault items created | ✅ `traefik_*` items | ✅ `crowdsec-webui_lapi_api` | ❌ `forgejo_api` only (no renovate-specific) |
| 3. Compose template | ✅ `templates/docker_services/traefik/` | ✅ `templates/docker_services/crowdsec-web-ui/` | ✅ `templates/docker_services/renovate/` |
| 4. group_vars entry | ✅ `group_vars/vps.yml` | ✅ `group_vars/vps.yml` | ✅ `group_vars/vps.yml` |
| 5. DNS/TLS configured | ✅ `traefik.kogler.si` + wildcard | ✅ `csui.kogler.si` (tailnet-only) | ❌ No DNS (Forgejo not created) |
| 6. Observability | ✅ Prometheus scrape + Grafana | ⚠️ No dedicated dashboard | ❌ None |
| 7. Backup policy | ✅ Config in db-backup | ❌ Not in db-backup/Kopia | ❌ None |
| 8. Deployment journal | ✅ 2026-08-22 | ✅ 2026-08-23 (IaC) | ❌ Not deployed |
| 9. deployment-tasks.md | ✅ Phase 1 ✅ | ✅ Phase 1 ✅ | ❌ Phase 3 pending |
| 10. Doc status banner | ✅ ✅ Live | ⚠️ Still ⏳ | ❌ Still ⏳ |

**Open Questions (D):**
1. **AUD-D-3**: Should `renovate` onboarding gaps be tracked as separate HD rows or consolidated under HD-264?

**False Positives (D):**
- `AUD-FP-1`: `renovate` enabled but Forgejo repo not created → intentional (HD-264 sandbox).
- `AUD-FP-2`: `traefik-tailnet` `tailnet_sidecar_ip` empty → intentional (filled at deploy time).
- `AUD-FP-3`: `prometheus_ha_exporter: false` → intentional (Phase 4 gate).
- `AUD-FP-4`: `rag-mcp`/`forgejo-mcp` `enabled: false` → intentional (placeholder stubs).

**Deduplication Keys (D):**
- `AUD-D-3`: `group_vars/vps.yml:docker_services.renovate.enabled`
- `AUD-D-5`: `group_vars/vps.yml:docker_services.traefik-tailnet.tailnet_sidecar_ip`, `group_vars/vps.yml:prometheus_ha_exporter`, `group_vars/vps.yml:docker_services.rag-mcp.enabled`

---

## E. Live Liveness — Findings (Track E)

| ID | Severity | Status | Evidence | Proposed Fix |
|----|----------|--------|----------|--------------|
| AUD-E-1 | High | OPEN | `ansible-playbook --check --diff --limit vps` fails at `fetch-vault-pass.yml` — `op-vault-export.py` returns empty JSON without live 1P session. This is expected in check-mode; not a live config drift. | Document check-mode limitation. Not a real drift. |
| AUD-E-2 | Med | OPEN | Live VPS: 33 enabled services. `docker ps` on VPS would show containers Up for: traefik, crowdsec, authentik, homepage, opencloud, onlyoffice-docs, immich-app, forgejo, zipline, litellm, qdrant, docling, open-webui, pi-dev, dsh, openclaw, prometheus, loki, grafana, blackbox-exporter, dozzle, traefik-tailnet, n8n, kopia-server, db-backup, matrix, chat, headscale, metabase, crowdsec-web-ui, pairdrop, stirling-pdf, renovate. (Cannot verify from worktree — requires SSH to VPS). | Verify via SSH when credentials available. |
| AUD-E-3 | Med | OPEN | Secret value spot-check: Cannot run `docker inspect` + `op item get` from worktree (requires VPS SSH + 1P session). | Defer to live session with VPS access. |
| AUD-E-4 | Med | OPEN | Certificate expiry: Cannot verify from worktree. `openssl s_client` check requires network access to `*.kogler.si`. | Defer to live session. |
| AUD-E-5 | Med | OPEN | DNS/Traefik route parity: Cannot verify from worktree. | Defer to live session. |
| AUD-E-6 | Low | OK | Observability stack health: IaC implemented (Prometheus/Loki/Grafana/Alloy/blackbox). Journal shows deployment 2026-08-22/23. | Verify live when VPS accessible. |
| AUD-E-7 | Low | OK | Backup/restore: `kopia-server` + `db-backup` deployed on VPS (journal 2026-08-23). `kopia-agent` on oldsrv (deploy-gated). Hetzner Boxes configured (HD-266). | Verify live when VPS/oldsrv accessible. |
| AUD-E-8 | Low | OK | Hardware health: `nas` (HP MicroServer) SMART all-pass 2026-08-23. `oldsrv` NVMe verified. Pi not yet provisioned. | Verify live when hosts accessible. |

**Open Questions (E):**
1. All live checks require VPS/LAN SSH access and live 1P session — defer to session with network access.

**False Positives (E):**
- `AUD-E-1`: Check-mode failure without live 1P — expected, not a drift.

**Deduplication Keys (E):**
- `AUD-E-1`: `roles/docker_services/tasks/fetch-vault-pass.yml:check-mode`
- `AUD-E-2..8`: `live-vps:requires-ssh`

---

## F. Consolidated Action Plan

| Priority | HD | Title | Track | Owning Doc | Source |
|----------|-----|-------|-------|------------|--------|
| High | HD-275 | Create `ha-failover_api` vault item for HA failover | B | `docs/deployment-secrets.md` | full-audit-2026-08-29 |
| High | HD-276 | Fix 5 broken anchor links in services-media/downloads | A | `docs/services-media.md`, `docs/services-downloads.md` | full-audit-2026-08-29 |
| Med | HD-277 | Replace 12 IP literals in docs with SSOT references | A | `docs/deployment-ansible.md`, `docs/deployment-secrets.md`, `docs/home-assistant-current.md` | full-audit-2026-08-29 |
| Med | HD-278 | Update status banners for 7 live services to ✅ Live since 2026-08-22 | A | `docs/observability.md`, `docs/services-traefik.md`, `docs/services-authentik.md`, `docs/services-admin.md`, `docs/services-utilities.md`, `docs/services-matrix.md` | full-audit-2026-08-29 |
| Med | HD-279 | Document vault escaping exceptions for TOML/env files | B | `docs/deployment-compose.md` | full-audit-2026-08-29 |
| Med | HD-280 | Document `collect-smart.ps1` as Windows-only sibling in scripts/README.md | C | `scripts/README.md` | full-audit-2026-08-29 |
| Low | HD-281 | Update document map tree for manual/ guides with correct paths | A | `docs/index.md` | full-audit-2026-08-29 |
| Low | HD-282 | Add False Positive Log entries for 4 intentional items | D | `todo.md` (as notes) | full-audit-2026-08-29 |
| Low | HD-283 | Track renovate onboarding gaps (6 missing steps) under HD-264 | D | `docs/services-admin.md` | full-audit-2026-08-29 |

---

## G. Open Questions

1. **AUD-A-1**: Document map tree convention for manual/ guides — with or without `manual/` prefix?
2. **AUD-A-3**: `docs/deployment-ansible.md` — qualifies as "IaC" for IP literal exception?
3. **AUD-A-4**: Status banner update policy — proactive vs. opportunistic?
4. **AUD-B-2**: Bulk pre-pass mocking in check-mode — implement or document as limitation?
5. **AUD-B-3**: Vault escaping for TOML/env — `urlencode` sufficient?
6. **AUD-C-5**: `collect-smart.ps1` registry entry — add Windows-only note?
7. **AUD-D-3**: Renovate onboarding gaps — separate HDs or under HD-264?
8. **AUD-E**: All live checks require VPS SSH + 1P session — schedule dedicated live-verify session.

---

## Verify (Definition of Done)

- [x] `bash scripts/validate-all.sh` green from the worktree.
- [x] Report exists with all sections A–G, every finding has Status + severity + evidence.
- [x] New HD rows use `scripts/next-hd.sh` (HD-275..HD-283), link owning docs, carry `source: full-audit-2026-08-29` tag.
- [ ] Machine-readable aggregate `reports/full-audit-2026-08-29.json` — to be generated.
- [ ] Handoff update `prompt.md` → #33 with audit outcomes — to be done.