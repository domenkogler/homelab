# prompt.md — Deployment Execution Handoff #2 — continue the halted Phase 1 deploy (2026-08-23 session)

> **Role:** Entry point for continuing the **Phase 1 VPS deploy** that was halted mid-run on 2026-08-22.
> The predecessor session bootstrapped the true-zero runner, re-provisioned the VPS, fixed seven live
> defects, and got the stack as far as the Authentik secret-egress glue (which cannot reach the API on
> host loopback — **first diagnostic step below**).
> **Linked from:** [README.md](README.md) §2 · plan: [deployment-tasks.md](deployment-tasks.md) ·
> as-built log: [deployment-journal.md](deployment-journal.md) · human feed: [prompt-journal.md](prompt-journal.md)

---

## 0. Mandatory context (read in this order)

1. [CONVENTIONS.md](CONVENTIONS.md) §4 (Deployment ledger & journal) — journaling loop is binding
2. [deployment-tasks.md](deployment-tasks.md) Phase 1 (the plan + Verify block)
3. **[deployment-journal.md](deployment-journal.md) Phase 1 entries from 2026-08-22** — the attempt log:
   every failure→fix of the previous session, plus the exact re-run recipe from true zero
4. [scripts/README.md](scripts/README.md) §runner tooling (`ansible-run.sh`, `provision-vault.sh`,
   `restore-runner-key.sh`, `check-vault-items.sh`)

## 1. Environment (Windows 11 laptop)

- Repo ops + validators: **git-bash**, forward-slash paths, `py -3`, UTF-8 no-BOM, LF.
- Ansible runner: **WSL Debian** (rebuilt true-zero 2026-08-22; user `domen`; canonical key restored).
  Playbooks are run ONLY via **`scripts/ansible-run.sh`** through wsl.exe script-file indirection:
  ```bash
  cmd //c "wsl -d Debian -- bash /mnt/d/source/domenkogler/homelab/scripts/ansible-run.sh playbooks/vps.yml"
  ```
  NEVER pass inline commands to wsl.exe from git-bash (MSYS mangles args); never use %TEMP% wrappers.
- Interactive SSH to the VPS: `ssh vps` / `ssh vps-ansible` (aliases in `~/.ssh/config`, 1Password agent
  + `.pub` hints; Homelab-ansible must stay allowlisted in 1Password's agent toml).
- ⚠ **9P STALE-CACHE RISK:** the runner reads the repo over `/mnt/d`. Files written Windows-side were
  served stale to WSL for minutes twice on 2026-08-22 (provisioner ran an old catalog; a render used an
  old template). Before any playbook run after repo edits: verify the file WSL sees matches
  (`md5sum` both sides), or migrate the runner clone natively into WSL (see todo HD-212).

## 2. State snapshot (halt point, end of 2026-08-22 session)

- **VPS `vps.kogler.si`** — re-provisioned 2026-08-22 (Debian 13 minimal, netcup Custom Script);
  SSH no/no/3 + fail2ban + nftables default-deny (**with :22** — the original ruleset omitted it and
  caused a lockout, fixed); Docker installed; all 4 networks up; CIFS `/mnt/storagebox` mounted;
  authentik project containers created but **authentik-server flapping and NOT listening on
  127.0.0.1:9000** at halt; deploy aborted at the HD-143 glue task (fail-closed by design).
- **Vault**: `authentik-provision_api` created (write-scoped SA token) — ⚠ **token was pasted into chat
  logs → ROTATE after deploy goes green** (rotate = new SA → update item → re-run playbook, which
  redeploys `/etc/op/provision-token`). All 8 render-blocking items seeded via provisioner
  (`authentik_login`, `authentik-ldap_bind`, `opencloud_login`, `forgejo_api`, `openrouter_api`,
  `cohere_api`, `openclaw_gateway_token`, `openclaw-opencloud_api`) — ⚠ `openrouter_api`/`cohere_api`
  hold PLACEHOLDER values (swap for real provider keys later); `forgejo_api` placeholder until the
  Forgejo UI issues the real token. `openclaw-opencloud_api` username=`openclaw`.
- **Fixes landed & committed on 2026-08-22** (details in the journal attempt log): bootstrap chmod 700,
  group_vars/all.yml→all/main.yml shadowing fix (HD-210 closed), python3-debian prereq,
  op-guard delegate_to localhost + become:false, vps-hardening restarts docker after nftables load,
  postgres+redis caps/tmpfs across templates, authentik-server loopback API publish (127.0.0.1:9000),
  glue counter vs Jinja `{#`, provisioner stdin=DEVNULL fix, ansible-run.sh runner.

## 3. Next-session execution order

1. **Diagnose the glue halt** (first action):
   - `ssh vps` then: `sudo docker ps --filter name=authentik --format '{{.Names}}: {{.Status}}'`;
     `sudo docker port authentik-server 9000`; `curl -s --max-time 3 http://127.0.0.1:9000/-/health/`;
     `sudo docker logs authentik-server --tail 20`.
   - Expected healthy end-state: server Up + port published + health 200. If the port is missing while
     the container runs, compare the deployed compose against the repo template (9P staleness check!).
   - Likely candidates: redis still unhealthy (cascade-aborts server), or first-boot migrations simply
     need more than the retry window (retries now 30×10 s).
   - NOTE: `sudo` prints "unable to resolve host vps" — harmless noise; candidate small common-role
     fix (/etc/hosts entry), not blocking.
2. Once the API answers: re-run `ansible-run.sh playbooks/vps.yml` → completes the service loop
   (traefik, crowdsec, opencloud, immich, forgejo, AI stack, matrix, monitoring…).
3. **Phase 1 Verify block** (deployment-tasks): sso reachable via Traefik + wildcard cert (DNS-01),
   CrowdSec decisions active, CIFS round-trip, hardening evidence (`fail2ban-client status sshd`,
   `nft list ruleset` incl. :22, `sshd -T` = 3/no/no, `docker info` daemon settings).
4. **Deploy-gated verification rows**: HD-40A, HD-135 (partial), HD-149, HD-143, HD-144, HD-146,
   HD-166, HD-159 — tick + journal each as its evidence lands.
5. **Hygiene**: rotate the exposed provision SA token; swap placeholder `openrouter_api`/`cohere_api`/
   `forgejo_api` values for real ones; consider HD-212 (native WSL clone) before the next big deploy;
   write the `deployment-manual.md` §Phase 1 section once the Phase 1 Verify block is green
   (Phases 0/0.5 already documented).

## 4. Working rules (unchanged, binding)

- Validate green → commit; journal append-only; corrections = new entries; feed raw notes via
  [prompt-journal.md](prompt-journal.md) DATA ("read prompt-journal.md" triggers the conversion loop).
- Secrets: 1Password item+field names only — never values, never in Git or chat.
- Decisions made during deploy → owning doc + changelog row in the same change; permanent divergences
  update the owning doc (`doc updated: <file>` noted in the journal entry).
- No cosmetic edits; English technical prose; relative links.
