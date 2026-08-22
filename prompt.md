# prompt.md — Deployment Execution Handoff #2 — continue the halted Phase 1 deploy (2026-08-22 session)

> **Role:** Entry point for continuing the **Phase 1 VPS deploy** that was halted mid-run on 2026-08-22.
> The predecessor session bootstrapped the true-zero runner, re-provisioned the VPS, fixed seven live
> defects, and got the stack as far as the Authentik secret-egress glue (which cannot reach the API on
> host loopback — **first diagnostic step below**).
> **Linked from:** [README.md](README.md) §2 · plan: [deployment-tasks.md](deployment-tasks.md) ·
> as-built log: [deployment-journal.md](deployment-journal.md) · redeploy runbook:
> [deployment-manual.md](deployment-manual.md) · human feed: [prompt-journal.md](prompt-journal.md)

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
- ⚠ **9P STALE-CACHE RISK — sync gate MANDATORY before every playbook run (HD-212, decided 2026-08-22):**
  the runner reads the repo over `/mnt/d`; files written Windows-side were served stale to WSL for
  minutes twice on 2026-08-22 (provisioner ran an old catalog; a render used an old template).
  Owner decision: **stay on `/mnt/d` (Option A)** behind this gate —
  1. Whole-tree hash compare from the repo root on BOTH sides — must be equal:
     `git ls-files -z | xargs -0 md5sum --text | md5sum`
  2. On mismatch, force-invalidate (in order, re-hash after each):
     ① `wsl -d Debian -u root -- bash -c 'echo 3 > /proc/sys/vm/drop_caches'`
     ② still stale → inside WSL: `sudo umount /mnt/d && sudo mount -t drvfs D: /mnt/d`
  3. If BOTH mechanisms fail to clear a mismatch → autonomously migrate the runner clone natively
     into WSL (Option B / HD-212 proper) **without asking** — pre-authorized by the owner.

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
- **New since the halt (2026-08-22 session, HD-213/214):** [deployment-manual.md](deployment-manual.md)
  — imperative redeploy runbook; Phase 0 (runner) + Phase 0.5 (netcup SCP reinstall incl. the
  field-by-field settings, moved here from `docs/deployment-preseed.md`) are documented;
  its §Phase 1 is deliberately stubbed until the first green Verify block. No impact on the
  execution order below. Also 2026-08-22 (Q/A session): owner locked the execution parameters in
  §3 (incl. the HD-212 sync-gate decision in §1); two-vault model (`Homelab` = human/break-glass,
  `Homelab-ansible` = automation) documented in `docs/deployment-secrets.md`.
- **Fixes landed & committed on 2026-08-22** (details in the journal attempt log): bootstrap chmod 700,
  group_vars/all.yml→all/main.yml shadowing fix (HD-210 closed), python3-debian prereq,
  op-guard delegate_to localhost + become:false, vps-hardening restarts docker after nftables load,
  postgres+redis caps/tmpfs across templates, authentik-server loopback API publish (127.0.0.1:9000),
  glue counter vs Jinja `{#`, provisioner stdin=DEVNULL fix, ansible-run.sh runner.

## 3. Next-session execution order

**Execution parameters (owner sign-off, 2026-08-22 Q/A session — binding):**
- Work **autonomously** through the order below; stop only at failures or human gates.
- Strategy: **full idempotent `vps.yml` re-run first**; `--start-at-task` only for fast iterations after it.
- Pre-flight: run `scripts/check-vault-items.sh`; create any missing **generated** items autonomously via
  `scripts/provision-vault.sh` (create-only, never overwrites — safe). Manual secret work stays POST-GREEN
  only: real values into the `forgejo_api`/`openrouter_api`/`cohere_api` placeholders + rotate
  `authentik-provision_api` (HD-211).
- **HD-159 stays ⏳ deploy-gated until Phase 1.5** (the WG S2S tunnel does not exist yet) — do NOT tick
  it during Phase 1.

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
   Quicker turnover: resume mid-play with
   `--start-at-task="Authentik OIDC secret-egress pre-pass (render + token)"` — exact-name match,
   lands inside `docker_services`; the earlier roles are already applied/live so skipping them only
   skips their handler flushes (fine). Per the execution parameters above: full re-run first, this
   for fast iterations after; the §1 sync gate is mandatory either way.
3. **Phase 1 Verify block** (deployment-tasks): sso reachable via Traefik + wildcard cert (DNS-01),
   CrowdSec decisions active, CIFS round-trip, hardening evidence (`fail2ban-client status sshd`,
   `nft list ruleset` incl. :22, `sshd -T` = 3/no/no, `docker info` daemon settings).
4. **Deploy-gated verification rows**: HD-40A, HD-135 (partial), HD-149, HD-143, HD-144, HD-146,
   HD-166, HD-159 — tick + journal each as its evidence lands.
5. **Hygiene**: rotate the exposed provision SA token; swap placeholder `openrouter_api`/`cohere_api`/
   `forgejo_api` values for real ones; HD-212 is handled by the §1 sync-gate decision (native clone
   only as the pre-authorized fallback); write the `deployment-manual.md` §Phase 1 section once the
   Phase 1 Verify block is green (Phases 0/0.5 already documented).

## 4. Working rules (unchanged, binding)

- Validate green → commit; journal append-only; corrections = new entries; feed raw notes via
  [prompt-journal.md](prompt-journal.md) DATA ("read prompt-journal.md" triggers the conversion loop).
- Secrets: 1Password item+field names only — never values, never in Git or chat.
- Decisions made during deploy → owning doc + changelog row in the same change; permanent divergences
  update the owning doc (`doc updated: <file>` noted in the journal entry).
- No cosmetic edits; English technical prose; relative links.
