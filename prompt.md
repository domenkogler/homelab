# prompt.md — Deployment Execution Handoff #16 — HD-240 stats.kogler.si SSO dead-end fixed LIVE (edge pin + datasource auth chain + UPS rules); owner browser check pending

> **Role:** Entry point for the next session. This session (2026-08-24 late night → 08-25)
> diagnosed and LIVE-fixed the "Grafana on the SSO dashboard lands on a logo-only bare `/login`"
> dead-end (HD-240). Three stacked root causes: ① traefik edge container IP had drifted off the
> whitelisted `traefik_edge_ips` /32 → now PINNED via compose `ipv4_address` = new
> `traefik_edge_ip_pin` group_var; ② grafana datasource never sent basic-auth (`basicAuth: true`
> flag missing since birth) AND grafana 13.2.0 file-provisioning stores an unresolvable
> secureJsonData blob → Prometheus datasource moved to idempotent **API seeding** in the
> monitoring role; ③ UPS alert rules used invalid PromQL bitwise-& → modulo bitmask tests.
> Owner mapped into Grafana as Admin via break-glass API (email matches Authentik identity).
> Verified live: forged-header rejection (**HD-190 deploy-gate CLOSED**), ds-health 200, real
> query data through proxy, zero eval errors. ⏳ One owner step left: logged-in browser click
> sso → stats must land IN Grafana.
> **Linked from:** [README.md](README.md) §2 · owning doc:
> [docs/observability.md](docs/observability.md) (new *Access & login path* section) ·
> changelog row **HD-240** · journal entry 2026-08-24/25 Phase 1.

---

## 0. Mandatory context (read in this order)

1. [CONVENTIONS.md](CONVENTIONS.md) — §2 secret-output hygiene + secret→YAML `>-` rendering,
   §4 journal loop + post-task housekeeping, §5 service-onboarding checklist, §6 worktree discipline.
2. [docs/observability.md](docs/observability.md) — **Access & login path** section: how
   stats.kogler.si auth works (forward-auth → `[auth.proxy]` header trust from the pinned edge IP),
   why a bare logo-only `/login` means rejection, and the two operational caveats learned live.
3. [changelog.md](changelog.md) — **HD-240** row (+ carried **HD-112**, **HD-57**, **HD-239**).
4. [deployment-journal.md](deployment-journal.md) — 2026-08-24/25 Phase-1 entry (evidence +
   both incidents, incl. a self-reported secret exposure → HD-211 priority).
5. [docs/services-authentik.md](docs/services-authentik.md) — *API-token auto-rotation* (HD-216).

## 1. Environment (Windows 11 laptop)

- Repo ops + validators: **git-bash**, forward-slash paths, `py -3`, UTF-8 no-BOM, LF.
- Ansible runner: **WSL Debian** via script-file indirection ONLY (`scripts/ansible-run.sh`,
  `scripts/ak-shell.sh`); NEVER inline through wsl.exe from git-bash (MSYS mangles leading-`/`
  args); probes = throwaway temp script outside all checkouts → delete after capture.
- ⚠ **9P gate MANDATORY before every playbook run**: `git ls-files -z | xargs -0 md5sum --text |
  md5sum` EQUAL on BOTH sides (worktree gitdir translation per deployment-manual if needed).
- Read-only probes: `ssh -o BatchMode=yes vps` (config alias! bare hostnames offer too many
  agent keys); sudo via stdin-fed scripts (`ssh vps 'sudo -n bash -s' < script`) — **never pass
  secrets through argv/quoting layers** (HD-240 Incident B: one broken inline probe echoed
  `prometheus-internal_api` into a transcript; stdin-scripts only since).
- ⚠ Template comments/tasks must not contain literal `{{` Go-template sequences where Ansible
  parses them (docker `--format` needs indirection — use `hostname -i` style instead).

## 2. State snapshot (end of session)

- **main == origin/main? verify at close** @ handoff #16 closing commit (worktree
  `homelab-wt-20260824-2321`, branch `session/stats-grafana-fix`, merged back green ×4 merges;
  note: three OTHER lanes also merged during this session — hd112 closeout et al. — no conflicts).
- Closed tonight: **HD-240 Done (IaC + live)** with a tight ⏳ tail (owner browser round-trip) ·
  **HD-190 deploy-gate closed** (forged-header rejection verified live; row deleted from todo,
  closure recorded in the HD-240 changelog row).
- **Live changes made:** traefik recreated at pinned `.2` (~2 min edge flap during first attempt,
  see journal Incident A) · grafana restarted several times during datasource surgery · grafana
  DB `data_source` row for prometheus replaced by API-seeded equivalent (uid/name/url unchanged;
  dashboards + alert rules unaffected) · new user `domen` (org Admin).
- Parallel lane same night (HD-241/242/243): Metabase operationalized — env-driven smtp2go SMTP
  (IaC SSOT), CrowdSec-SQLite + Forgejo-PG read-only data sources (`db_ro_sync` mechanism, new
  `metabase-forgejo_ro` vault item), LDAP option parked; ⏳ converge-gated tails in todo §2.4.
- **Still open at next converge (ride-along checks, no standalone session needed):**
  ① zero spurious restarts on unchanged extras / exactly one per changed extra (HD-236 guard);
  ② direct per-run proof that `apply-authentik-blueprints.yml` fired green.
- **ID registry:** next free = **HD-244** (max(changelog)=HD-243; re-derive at write time per
  CONVENTIONS §1 — never re-type this pointer).
- **Coordination:** do NOT touch headplane/headscale (separate lane). Primary checkout owns main.

## 3. Next-session execution order

### 3a. Owner-action chase (reminders, not blockers)
- **NEW — HD-240 final leg:** logged-in browser test — sso dashboard → Grafana tile → must land
  in the Grafana UI (not the logo-only `/login`). If it still bounces: check grafana logs for
  `auth.proxy` lines, confirm edge IP still `.2`, confirm the `domen` user exists
  (`GET /api/users` via break-glass). Then trim the HD-240 ⏳ tail + delete the todo row.
- **PRIORITY — HD-211 rotation batch grew:** `prometheus-internal_api` password was exposed into
  an agent transcript TWICE now (2026-08-23 probe + 2026-08-24 quoting failure). Rotation is
  trivial post-HD-240: rotate the vault item → re-run `--tags monitoring` (API seed task only
  fires when DS absent → delete the DS first via UI/API, or extend the task with a rotate mode).
  Also still open from before: `openrouter_api`, `cohere_api`, `forgejo_api`,
  `opencloud-collab_password` window, persisted-Authentik-token `expiring=False` sweep.
- **Zipline pre-deploy:** seed the vault items by script — `bash scripts/provision-vault.sh`
  creates `zipline_password` + `zipline_db`; owner input = starting guestbin quota (~100 MB).
- **After first Zipline converge:** walk the compose-header deploy gate (`/auth/setup` admin →
  OIDC verify → flip bypass-local-login → seed `guestbin` + `dropzone`) → anonymous round-trip →
  6h sweep → family drop script + guide. Trim the HD-112 ⏳ tail.
- Carried: Kopia `/backup` source-wiring decision; LDAP **HD-132** authoring; Forgejo
  `domen/homelab` repo creation (renovate flip); Phase 1.5 cutover (dnevna/garage swaps + capsman
  rsc); HD-57 human legs (bank tokens / Enable-Banking app).

### 3b. Remaining engineering queue
- **HD-238** oldsrv→VPS DR runbook for non-GPU services (todo §2.9) — laptop-doable authoring task;
  pairs naturally with the next backup.md touch (which now also carries the HD-112 uploads-
  exclusion row).
- **HD-112 go-live rides the NEXT Phase-1 converge — full sequence:** ① `bash
  scripts/provision-vault.sh` (seeds `zipline_password` + `zipline_db`; render fails loud without)
  ② 9P gate → human-gated dry-run → converge `vps.yml` — plain registry entry, authentik
  precedence guarantees blueprint + glue fire ③ **run `dns.yml` too** — the `bin` CNAME is
  IaC-tracked but applied ONLY by dns.yml; without it `bin.kogler.si` does not resolve ④ walk the
  compose-header checklist (`/auth/setup` admin → OIDC verify → flip bypass-local-login → seed
  `guestbin` + `dropzone`) ⑤ anonymous round-trip + 6h sweep verify → trim the HD-112 ⏳ tail.
  Journal the post-up steps as-run.
- Converge ride-along checks (fold into any upcoming docker_services converge): observe residual ①
  (extras restart guard behavior) + confirm blueprint one-shot task output green in the same run;
  journal both, then trim the ⏳ tails via an append-only R-row.
- Phase-2 backlog note: Zipline `/drop` static glue page (Traefik PathPrefix-priority router,
  same-origin) — only if the owner asks; NOT queued.
- Headplane hardening (separate lane — only if its owning session asks).

## 4. Working rules (binding)

- Fresh worktree per session before ANY edit (`../homelab-wt-<date>-<HHMM>`); merge back only
  committed+green; primary checkout owns main; remove own worktree via `git worktree remove`.
- Converges: 9P gate first, surgical `--tags` preferred — canonical tables in
  [deployment-manual.md](deployment-manual.md)/[docs/deployment-ansible.md] (role+service tags BOTH
  required; traefik dynamic-file changes need the `traefik` tag too). Handlers always carry
  `tags: always` (HD-237 invariant).
- Secrets: 1Password item.field names only — NEVER values anywhere; `>-` block scalar for ALL
  1P-sourced YAML/compose-env renders. Probes print hashes/lengths/prefixes only — feed anything
  secret-touching via stdin scripts, never argv.
- **Persisted Authentik API tokens: ALWAYS `expiring=False`** (HD-216).
- Journal append-only; owning doc + changelog row(s) in the same change; English prose; relative links.
- Authentik blueprint: pin array attrs (HD-231). Do not touch headplane/headscale unless asked.
