# prompt.md — Deployment Execution Handoff #3 — continue Phase 1: crash-loop triage → Verify block

> **Role:** Entry point for continuing the **Phase 1 VPS deploy**. The predecessor sessions took the
> stack from true-zero through the authentik/glue saga to: **all 27 enabled VPS services deployed;
> ~11 up & healthy; ~17 containers crash-looping with most causes already diagnosed**. First blocker
> on resume is small (monitoring role / homepage failover buttons); the bulk of remaining work is
> per-service triage, then the Phase 1 Verify block.
> **Linked from:** [README.md](README.md) §2 · plan: [deployment-tasks.md](deployment-tasks.md) ·
> as-built log: [deployment-journal.md](deployment-journal.md) · redeploy runbook:
> [deployment-manual.md](deployment-manual.md) · human feed: [prompt-journal.md](prompt-journal.md)

---

## 0. Mandatory context (read in this order)

1. [CONVENTIONS.md](CONVENTIONS.md) §4 (Deployment ledger & journal) — journaling loop is binding
2. [deployment-tasks.md](deployment-tasks.md) Phase 1 (plan + Verify block + deploy-gated rows)
3. **[deployment-journal.md](deployment-journal.md) — ALL Phase 1 entries from 2026-08-22** (five
   layers of glue fixes, two-token architecture, out-of-band SQL incident, session-pause snapshot)
4. [scripts/README.md](scripts/README.md) — runner tooling (`ansible-run.sh`, `ak-shell.sh`,
   `provision-vault.sh`, `check-vault-items.sh` — note check-vault-items missed
   `kopia-server_internal_api`; blind spot to fix)
5. [docs/services-authentik.md](docs/services-authentik.md) §live-deploy findings — REQUIRED before
   touching authentik again (image quirks, API paths, token architecture)

## 1. Environment (Windows 11 laptop)

- Repo ops + validators: **git-bash**, forward-slash paths, `py -3`, UTF-8 no-BOM, LF.
- Ansible runner: **WSL Debian** via script-file indirection ONLY:
  ```bash
  cmd //c "wsl -d Debian -- bash /mnt/d/source/domenkogler/homelab/scripts/ansible-run.sh playbooks/vps.yml"
  ```
  NEVER inline commands through wsl.exe from git-bash (MSYS mangling). Interactive SSH from
  git-bash was FLAKY last session (Windows 1Password agent wedged post-kex): prefer the WSL
  key-file path (`wsl -d Debian -- ssh ansible-admin@vps.kogler.si`, BatchMode) or
  `scripts/ak-shell.sh` for authentik container work. Restart/unlock the 1Password app first.
- ⚠ **9P STALE-CACHE SYNC GATE MANDATORY before every playbook run** (HD-212):
  `git ls-files -z | xargs -0 md5sum --text | md5sum` on BOTH sides must be EQUAL
  (`--text` is REQUIRED — MSYS vs GNU md5sum output formats differ otherwise). On mismatch:
  ① drop_caches as root in WSL ② remount drvfs ③ full `wsl --terminate Debian`. If all fail:
  migrate runner clone natively into WSL WITHOUT asking (pre-authorized).

## 2. State snapshot (pause, end of 2026-08-22)

- **Authentik: FULLY PROVISIONED.** Blueprint applied live (8 OIDC providers + 8 apps);
  secret-egress glue PASSES with **ephemeral per-run tokens** (mint via ak-shell, revoke on exit —
  Option A after HD-216 rotator mystery); `authentik-provision_api` vault item RETIRED;
  `vps-op-write_api` (owner-created write-scoped SA) drives host-side op. Server/worker/pg healthy;
  LDAP outpost up-but-unhealthy (recheck after server stable).
- **All 27 enabled services rendered & deployed** (`ok=207 changed=83`). Up & healthy (~11):
  traefik, authentik×4, homepage, docling, litellm, open-webui, pgvector, onlyoffice-docs,
  forgejo-db, immich-postgres+valkey, blackbox-exporter, loki. Crash-looping (~14 services /
  17 containers) with DIAGNOSED causes — see journal session-pause entry for the ordered list:
  crowdsec collection name, opencloud :ro config mount, grafana volume ownership, tuwunel config
  schema, n8n module error + 6 unsampled.
- **Halt point:** `monitoring` role — homepage_services.yaml.j2 needs `'failover_api_url'`
  (undefined anywhere) + `ha-failover_api` item (Phase-4/HD-17 scope, not in vault).
  ⏳ Proposal awaiting owner sign-off: gate those homepage buttons behind
  `homepage_failover_button: false` until HD-17.
- **Vault:** `vps-op-write_api` active; 30 generated items seeded; glue seeded the 8 OIDC items
  (`*_api` from Authentik). Placeholders still pending real values: `openrouter_api`,
  `cohere_api`, `forgejo_api` (post-green manual swaps).
- **Hygiene debt (post-green, HD-211 batch):** rotate provision-era secrets exposed in session
  logs: rendered compose env block (authentik_db, authentik_password SECRET_KEY, authentik_login
  bootstrap, ldap bind), one invalidated ephemeral key printed, old mis-filed SA value. See
  journal layer-3–5 + session-pause entries for the full list.
- **Open investigations:** HD-216 (background token rotator — OFFLINE analysis only; live-DB
  probing is banned after the out-of-band SQL incident, artifacts removed & verified).
- **Owed:** `dns.yml` re-run (idempotent; owner confirmed it ran once undocumented) before Verify.

## 3. Next-session execution order

### 3a. Crash-loop triage — PARALLEL WAVE PATTERN (owner-approved)
1. **Wave 1, parallel + read-only:** one diagnostic worker per crash-looping service (~14): pull
   `docker logs`/`inspect` (script-file ssh, no mutation), read its own template, return a
   structured report: root cause + proposed concrete patch. NO repo writes, NO VPS mutation.
   Orchestrator merges reports and flags shared root causes / shared-file conflicts.
2. **Wave 2, serial application (single writer = orchestrator):** apply patches in one editing
   pass; independent per-template fixes batch into ONE commit; shared-file changes (group_vars,
   versions.yml, role defaults) applied by the orchestrator only.
3. **Wave 3, combined verification loop:** validate-all green -> commit -> sync gate -> ONE
   playbook run covering all batched fixes -> re-sample container states; failing services loop
   back to Wave 1 individually. Expect 2-3 combined runs total, not one per service.
4. Authentik stays SPECIAL: shared dependency - any fix touching it is applied and verified alone,
   never inside a batch.

### 3b. After triage converges
1. **Owner sign-off:** homepage failover-button gating var (unblocks monitoring role).
2. **Full green `vps.yml`** (anchor run until clean, then one full idempotent run).
3. **`dns.yml`** re-run (vps A/AAAA + sso + public apps as live), journal evidence.
4. **Phase 1 Verify block** (deployment-tasks): sso via Traefik + wildcard cert (DNS-01),
   crowdsec decisions, CIFS round-trip, hardening evidence (sshd -T 3/no/no incl. :22 ruleset,
   fail2ban, docker info), NVMe <80%.
5. **Tick deploy-gated rows**: HD-40A, HD-135 (partial), HD-149, HD-143 (re-scope note: ephemeral
   token design), HD-144, HD-146, HD-166 — tick + journal each as evidence lands. HD-159 stays ⏳
   until Phase 1.5.
6. **Hygiene:** HD-211 rotation batch + session-exposure list above; swap placeholder provider keys.
7. Write **[deployment-manual.md](deployment-manual.md) §Phase 1** once Verify is green
   (Phases 0/0.5 already documented).

## 4. Working rules (unchanged, binding)

- Validate green → commit; journal append-only; corrections = new entries; feed raw notes via
  [prompt-journal.md](prompt-journal.md) DATA ("read prompt-journal.md" triggers the conversion loop).
- Secrets: 1Password item+field names only — never values, never in Git or chat.
- Decisions made during deploy → owning doc + changelog row in the same change; permanent divergences
  update the owning doc (`doc updated: <file>` noted in the journal entry).
- No cosmetic edits; English technical prose; relative links.
- Live-system debugging stays read-only or goes through IaC — no hand-run SQL against managed
  databases (2026-08-22 incident precedent).
