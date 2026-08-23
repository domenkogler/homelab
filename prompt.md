# prompt.md — Deployment Execution Handoff #4 — Phase 1 stack LIVE → Verify block + two owner inputs

> **Role:** Entry point for continuing the **Phase 1 VPS deploy**. Predecessor sessions took the stack
> from true-zero through the crash-loop triage waves to: **all 27 enabled services deployed and LIVE
> behind real Let's Encrypt TLS** (wildcard `*.kogler.si` issued + installed), forward-auth edge wired,
> authentik admin operational. First tasks on resume: read the tail of the async convergence run, then
> the Phase-1 **Verify block** ([deployment-tasks.md](deployment-tasks.md)) — most evidence is already
> collected. Two owner inputs may still be outstanding (see §2).
> **Linked from:** [README.md](README.md) §2 · plan: [deployment-tasks.md](deployment-tasks.md) ·
> as-built log: [deployment-journal.md](deployment-journal.md) · redeploy runbook:
> [deployment-manual.md](deployment-manual.md) §Phase 1 · human feed: [prompt-journal.md](prompt-journal.md)

---

## 0. Mandatory context (read in this order)

1. [CONVENTIONS.md](CONVENTIONS.md) §4 (ledger & journal loop is binding)
2. [deployment-journal.md](deployment-journal.md) — journal entries **2026-08-22/23**: Wave 1/2 triage
   (HD-218), Waves R4/R5 (traefik engine-29 fix, plugin chain, CF token closure, wildcard issuance,
   headscale schema chain, akadmin sync), edge forward-auth wiring (HD-219), AND §Phase 1a
   (parallel track: oldsrv reinstall)
3. [deployment-manual.md](deployment-manual.md) **§Phase 1** — the settled redeploy path is NOW
   WRITTEN (1.1–1.9); follow it for any reinstall instead of re-deriving
4. [todo.md](todo.md) HD-217/218/219 + [changelog.md](changelog.md) same IDs
5. [scripts/README.md](scripts/README.md) — runner tooling; note `ak-shell.sh`: **arg mode reliable,
   stdin mode flaky** through cmd→wsl

## 1. Environment (Windows 11 laptop)

- Repo ops + validators: **git-bash**, forward-slash paths, `py -3`, UTF-8 no-BOM, LF.
- Ansible runner: **WSL Debian** via script-file indirection ONLY:
  ```bash
  cmd //c "wsl -d Debian -- bash /mnt/d/source/domenkogler/homelab/scripts/ansible-run.sh playbooks/vps.yml"
  ```
  NEVER inline commands through wsl.exe (MSYS mangling). Read-only VPS probes also go through
  script files (pattern proven all session). Interactive git-bash ssh was flaky (1Password agent);
  WSL key-file path (`ansible-admin@vps.kogler.si`, BatchMode) stayed green throughout.
- Async long runs: launch INSIDE WSL with `setsid nohup … > /tmp/<log> 2>&1 &` via a script file —
  survives session teardown (plain git-bash `&` does NOT survive the cmd→wsl boundary).
- ⚠ **9P STALE-CACHE SYNC GATE MANDATORY before every playbook run** (HD-212):
  `git ls-files -z | xargs -0 md5sum --text | md5sum` on BOTH sides must be EQUAL. On mismatch:
  drop_caches → remount drvfs → full `wsl --terminate Debian`; else migrate clone into WSL
  (pre-authorized).

## 2. State snapshot (end of session, night of 2026-08-22/23)

- **Stack LIVE:** all 27 enabled services deployed; **33–34/35 Up**; every public route serves real
  LE TLS (wildcard `*.kogler.si` + apex cert issued, installed to `/opt/traefik/certs/kogler.si{,-key}.pem`).
- **Auth edge live:** `ks-forward-auth.yml` blueprint applied — 9 proxy providers (forward_single) +
  edge applications bound to the Embedded Outpost; unauthenticated requests redirect to sso.
  Excluded tiers per labels: native-OIDC (ai/foto/file + headscale→`crowdsec-only` after owner-approved
  middleware fix), Matrix-native SSO (matrix/chat), WOPI-only office, IdP itself.
- **Authentik:** owner logged in as `akadmin` (email corrected to `admin@kogler.si`), WebAuthn + TOTP
  enrolled. Finding recorded: `AUTHENTIK_BOOTSTRAP_*` applies ONLY at user creation — fresh installs
  are unaffected (env pinned from first boot). Rotation caveat documented in
  [deployment-secrets.md](docs/deployment-secrets.md) philosophy block.
- **Traefik:** pinned **v3.7.11** (Engine 29 min client API 1.40 killed v3.5's docker provider);
  bouncer plugin **v1.7.1** (`maxlerebourg/…`, registry-verified) with LAPI key from NEW vault item
  **`crowdsec-bouncer_api`**; `/plugins-storage` tmpfs required under read_only.
- **DNS published** (`dns.yml`): `vps` A/AAAA + apex + 14 app CNAMEs (SSOT:
  `roles/cloudflare_dns/vars/main.yml`). `ha` withheld until Phase 4. Gotcha encoded: netcup
  resolvers negative-cache NXDOMAIN past record TTL → traefik + headscale pin public resolvers.
- **CF token:** rolled to exact-IP filter (CIDR entries unreliable); old value BURNED in session
  transcript — include in HD-211 rotations.
- **Loops remaining (owner-gated):**
  - `renovate` — owner reports `forgejo_api` UPDATED; convergence run at handoff was mid-flight
    (fatal-count=0 through kopia-server templates) — **first task: confirm recap + renovate Up**.
  - `kopia-server` — needs `/srv/docker/kopia-server/config/{sftp_key,known_hosts}` seeded
    (sftp_key from backup-box private key in 1P; known_hosts via `ssh-keyscan -p 23 …`).
- **Phase 1a (parallel session, same night): oldsrv REINSTALLED — Debian 13.6, interactive**
  (preseed bypassed after four delivery failures; root causes journaled: d-i udev creates no
  nvme-eui.* links → partman matched nothing; WLAN NIC auto-picked; a rogue Kingston stick was
  being booted — quarantined). Verified live (site-LAN address, SSOT: [network-addresses-generated.md](docs/network-addresses-generated.md)): `ansible-admin` + `ai-debug` +
  sshd hardening drop-in + sudo NOPASSWD ✓. `storage_nvme_data_by_id` eui target confirmed on
  the installed system (970 EVO untouched, NTFS until pool-create). **NAS install still pending**;
  HDD SMART-hour re-read deferred to Phase 2. Docs updated by that session: preseed.cfg
  (model_serial switch + early_command resolver + wifi-blacklist), deployment-preseed,
  check_placeholders allowlist, scripts/README collect-disk-facts row, hardware-oldsrv current-state.
  ⚠ `oldsrv.kogler.si` does NOT resolve from the runner — target its site-LAN address from
  [network-addresses-generated.md](docs/network-addresses-generated.md) directly (or add a home-DNS/hosts
  entry when Phase 1a continues).
- **Post-green health checks pending:** `authentik-ldap` unhealthy, `chat` unhealthy (both Up).
- **HD-211 rotation batch additions** (values transited session transcripts): old CF_DNS_API_TOKEN,
  GF admin+smtp, N8N encryption+basic-auth, RENOVATE_TOKEN, OPENCLAW_GATEWAY_TOKEN,
  OPENCLOUD_WEBDAV_PASSWORD, db-backup DB01–04, forgejo_db.
- **netcup platform fact:** outbound SMTP 25/465/587 DROPped → VPS alert mail must use SMTP relay
  port **2525** (documented in [services-vps.md](docs/services-vps.md)).
- Open investigation **HD-216** unchanged (offline analysis only). **HD-159** stays ⏳ until Phase 1.5.

## 3. Next-session execution order

### 3a. Settle the convergence run
1. Convergence run COMPLETED GREEN before handoff (recap: `ok=264 changed=35 failed=0`) —
   recap archived in `/tmp/vps-converge.log` (WSL) if still present.
2. First check: `renovate` Up with the real token (was mid-render at handoff) — if still
   auth-failing, token value/scope needs owner re-check (Forgejo audit log).
3. Full roster sample: expect only `kopia-server` looping (+ ldap/chat unhealthy checks).

### 3b. Kopia seed (if owner hasn't)
`sftp_key` + `known_hosts` into `/srv/docker/kopia-server/config/` → restart kopia-server.

### 3b-II. Phase 1a continuation (separate track)
NAS install still pending — follow [deployment-journal.md](deployment-journal.md) §Phase 1a +
[deployment-manual.md](deployment-manual.md) §Phase 1a. Optional quick win: add an `oldsrv`
DNS/hosts entry so the runner stops needing the raw IP.

### 3c. Phase 1 Verify block ([deployment-tasks.md](deployment-tasks.md))
Evidence mostly pre-collected this session: wildcard TLS served on every host ✓, DNS records live ✓,
forward-auth chain ✓, homepage gate off ✓. Still to capture: crowdsec decisions (`cscli decisions`),
CIFS round-trip, hardening evidence (`sshd -T` 3/no/no incl. `:22` ruleset, fail2ban, docker info),
NVMe <80%. Tick + journal each: HD-40A, HD-135 (partial), HD-143 (ephemeral-token re-scope note),
HD-144, HD-146, HD-149, HD-166 — HD-159 stays ⏳ until Phase 1.5.

### 3d. Hygiene
- HD-211 rotation batch (list above) — owner executes, playbook re-renders consumers.
- Grafana/NUT SMTP config → port 2525 (netcup blocks 587).
- `authentik-ldap` + `chat` health investigations.

### 3e. Docs
- [deployment-manual.md](deployment-manual.md) §Phase 1 exists — append Verify-block evidence
  addendum if the formal pass surfaces gaps.

## 4. Working rules (binding)

- **Use a new worktree before changing any files** — per the Git-worktrees convention in
  [CONVENTIONS.md](CONVENTIONS.md) §6: fresh worktree named `../homelab-wt-<date>-<HHMM>` for the
  session, all edits applied and validated there, merge back only committed, green results;
  the primary checkout stays untouched.
- Validate green → commit; journal append-only; corrections = new entries; feed raw notes via
  [prompt-journal.md](prompt-journal.md) DATA ("read prompt-journal.md" triggers the conversion loop).
- Secrets: 1Password item+field names only — never values, never in Git or chat.
- Decisions made during deploy → owning doc + changelog row in the same change; permanent divergences
  update the owning doc (`doc updated: <file>` noted in the journal entry).
- No cosmetic edits; English technical prose; relative links.
- Live-system debugging stays read-only or goes through IaC — no hand-run SQL against managed
  databases (2026-08-22 incident precedent). Authentik data fixes go through `ak-shell.sh`
  (arg mode) ORM one-shots.
