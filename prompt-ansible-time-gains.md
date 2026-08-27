# prompt-ansible-time-gains.md — HD-269 Ansible deploy runtime optimisation (brainstorm → measured → modularise)

> **Active lane:** HD-269 **BRAINSTORM → TARGETED DEPLOY-SPEED WORK** (2026-08-27, after HD-268 went live). The VPS full converge is ~204s (baseline captured 2026-08-27); ~35s of that is **three serial `op`/`docker exec` glue loops** (Authentik 22s, LiteLLM 8s, op-vault-export 5s). The surgical/deploy-tier tooling is **mostly in place** (`docker_services_scope`, role tags, externalized blueprints) but is **not yet used as the default iteration path**, and true **multi-service scope is unimplemented**. This lane is: gather more timing data (incl. a measured single-service scoped run), then land concrete time-gain optimisations (parallelize glue, batch scope, tier gate the rarely-changing roles).

> **Role:** Entry point for the next session — continue HD-269. Predecessor: handoff #24b (`prompt-FULL_CONVERGE.md`, HD-268 — now CLOSED into this lane). **Linked from:** README.md §0/§2 · CONVENTIONS.md §4/§6 · [`changelog.md`](changelog.md) (HD-269 row) · [`docs/deployment-ansible.md`](docs/deployment-ansible.md) (§tags/surgical runs, the SCOPE mechanism) · [`deployment-journal.md`](deployment-journal.md) (this session's baseline evidence) · [`todo.md`](todo.md) HD-269 · prior speed work: HD-257, HD-258, HD-259 (`op-vault-export` bulk pre-pass), HD-260 (derive mode).

---

## 0. Mandatory context (read in this order)

1. [CONVENTIONS.md](CONVENTIONS.md) — §6 worktree discipline (**mechanically enforced**), §4 journal loop + post-task housekeeping, §2 secret hygiene, §5 service-onboarding.
2. [docs/deployment-ansible.md](docs/deployment-ansible.md) — **THE operational doc for this lane**: §"Tags & surgical runs (HD-220)" — the role-tag wiring, the `docker_services_scope` var (HD-255/HD-260), canonical invocation table, the include_tasks tag-inheritance gotcha. This is where the modularisation must be documented.
3. [deployment-journal.md](deployment-journal.md) — the 2026-08-27 HD-268 full-converge + baseline entry (ok=311 changed=45 failed=0, ~203s; per-task TASKS RECAP timings) = the before-image for this lane.
4. [changelog.md](changelog.md) — HD-257/258/259/260 (prior deploy-speed work) + HD-269 row.
5. [todo.md](todo.md) — HD-269 row (this lane) + HD-268 tail (deploy-gated items, continue in parallel if touching dsh/qdrant).

## 1. Environment (same runner as #24a / FULL_CONVERGE)

- Platform: **Debian-13/trixie in WSL2, bash**. CWD pinned `/home/domen/source/homelab`; `python3` = `/home/domen/ansible-venv/bin/python3`; UTF-8/LF.
- Windows/WSL gotchas: write multi-line scripts to a temp file (not heredoc-through-`bash -c`); `MSYS_NO_PATHCONV=1` if ever invoking `wsl.exe` from git-bash (not needed inside WSL).
- Deploy runner: `bash scripts/ansible-run.sh playbooks/vps.yml [--tags …] [-e docker_services_scope=<svc>]` (sets ANSIBLE_CONFIG/ROLES_PATH + 1P SA token + venv). **Never edit on primary+main** — always a fresh `git worktree add ../homelab-wt-<ts>` (CONVENTIONS §6, mechanically enforced).
- Ad-hoc verification (the converge proved this SSH works): `ansible vps.kogler.si -i inventory.ini -m raw -a '<cmd>'` after sourcing the runner env. ⚠️ Avoid `{{ }}` in the `-a` string — Ansible Jinja-templates ad-hoc args and blows up on `.Names` style format braces; use brace-free commands (plain `docker ps -a --filter name=dsh`).

## 2. State snapshot (start of next session)

- **State:** primary @ `d964882`; session branch `session/hd269-scope-transitive-deps` carries the scoped+multi-service fix (see changelog.md HD-269).
- This lane's measured baseline (2026-08-27, full converge `playbooks/vps.yml`): `ok=311 changed=45 failed=0`, **~204s** (two identical static runs). Steady-state costs: Authentik secret-egress glue **~21-22s** · LiteLLM bulk prep + compose-up **~8s** · op-vault-export derive **~4.5-5s** · rest = Ansible-serial machinery (~150 sub-1s tasks).
- **(a) single-service surgical run — DONE & live-validated:** `scope=pi-dev` now converges `ok=20 failed=0` ~5-6s wall (was fail-open on the litellm-scoped key `pi-harness_openai_api`).
- **(c) multi-service scope — DONE:** `docker_services_scope` is now a comma-string; role defaults compute `scope_is_all`/`scope_list`; validated live `scope=qdrant,docling`.
- **(d) surgical op pre-pass + conditional glue — DONE:** scoped derive is scoped; op pre-pass ~5.79 → 0.78s on a scoped run; authentik-first deploy gated.
- **Remaining surgical gaps (now only):** parallelize the two serial glue loops (#b); rare bootstrap tier (#e); measure-permutations runbook (#f).

## 3. Next-session execution order (only glue-parallelize + tier + runbook remain)

### Step 0/2/3 — DONE last session (do not redo):
- (a) single-service scope measured & fixed: `scope=pi-dev` → `ok=20 failed=0` ~5-6s | op pre-pass ~5.79→0.78s.
- (c) multi-service scope: comma-string scope via `scope_is_all`/`scope_list`; live-validated `scope=qdrant,docling`.
- (d) surgical op pre-pass + gated authentik-first deploy.

### Step 1 — parallelize the two serial glue loops — **DONE; live re-baseline CLOSED (2026-08-28, commits dd98d50 → 027c0de → 3e94bf4)**
- **Authentik glue (`authentik-secret-egress.sh`)** — per-provider worker (own distinct 1P item) via `xargs -P "${OP_PARALLEL:-6}"`; write-only-if-changed; worker failure aborts (xargs nonzero); result serialized. **LIVE: 21-22s → 11.94s — shipped, real win** (workers only `curl`/`op read`, never feed stdin).
- **litellm glue (`litellm-bootstrap-keys.sh`)** — parallel read+probe via `xargs -P` was attempted but **FAILED live (rc 3, 12 retries)** — `probe_key` reads its probe via a `docker exec -i … <<'PYEOF'` heredoc whose stdin is a broken pipe under `xargs -P` → probe returns 000/hangs. **Reverted to the serial main loop (2026-08-27 version).** If ever parallelized again, the probe must be stdin-neutral (no docker-exec heredoc).
- **Validate (live, closed 2026-08-28):** full converge `ok=311 changed=45 failed=0`, wall ~3:13; authentik glue 11.94s ✓ (21-22s baseline); litellm glue serial (secrets already seeded → ~0.8s no-op this run).
- Guard: 1P rate-limit ≤4-6 op workers; only curl/docker exec probes may go wider.
⚠️ ⚠️ both scripts write secrets — the serialized/ordered writes + glue ordering (never render a consumer with an empty secret) are preserved. Live re-baseline was a NO-OP-deploy (idempotent) on the current stack; warning scan /tmp/fullconverge2.log filed HD-270 + HD-271.


### Step 2 — multi-service scope — **DONE (session 2026-08-27)**

### Step 3 — surgical op pre-pass + conditional glue lanes — **DONE (session 2026-08-27)**

### Step 4 — decide the rare/base tier (final modulariser)

### Step 5 — close-out (CONVENTIONS §4)
- Append the 2026-08-27 session's measured numbers + parallelization deltas to `deployment-journal.md` (still pending).
- `todo.md` HD-269 tail mark complete/remaining; fold this lane's identity into `prompt.md` at HD-269 close.
- Do NOT delete HD-268 line yet — its tail is still ⏳ deploy-gated.

## 4. Secrets / 1P / platform notes for this lane
- op pre-pass + glue = host-side SA token `/etc/op/provision-token` remote; control node op for lookups. Never echo secret values (`no_log` stays).
- Glue scripts are vault-state-first and idempotent — safe to parallelize reads; writes only-if-changed (never auto-delete/mint-over an existing secret).
- 1P rate-limit: earlier 15→6-worker change was cheap insurance; keep parallel `op` bounded (≤8-12 concurrent), only widen the `docker exec`/curl HTTP probes.

## 5. What NOT to re-decide
- **`docker_services_scope` is the surgical mechanism** (HD-255/HD-260) — extend it (multi), don't replace it.
- **Blueprints stay externalized** (`authentik-blueprints.yml`) — do not pull them back into the routine lane (that was the 2026-08-27 HD-268 decision).
- **op-vault-export bulk pre-pass is the right pattern** (HD-257/258) — keep bulk-export-per-item, just scope it.
- **Glue ordering is sacred** (HD-146/HD-162): consumers always render after their secrets exist; every your parallelization must PRESERVE that (reads parallel, writes ordered).

## 6. Did-not-close / session-sandbox note
- **This handoff still names Step 1 (parallelize glue), Step 4 (tier) and the runbook as open** — the scoped+multi-service surgery (Session 2026-08-27) is done and validated live.
- `prompt-FULL_CONVERGE.md` was a CLOSED HD-268 handoff — its open tail (tailnet sidecar, Qdrant live-verify) lives in todo HD-268 ⏳.