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

- **main @ `e201ceb`** (docs close-out HD-268 + HD-269 handoff). Pushed.
- This lane's measured baseline (all 2026-08-27, full converge `playbooks/vps.yml`):
  - Run 1 (post-dsh-fix, image land): `ok=311 changed=60 failed=0`, ~203s* — dsh now renders+starts.
  - Run 2 (dsh home-volume fix): `ok=311 changed=48 failed=0` — dsh crash-loop fixed, `Up`.
  - Run 3 = **baseline #1 (static)**: `ok=311 changed=45 failed=0`, **~203s**.
  - Run 4 = **baseline #2 (static)**: `ok=311 changed=45 failed=0`, **~204s**. (Two identical-config static runs within 1s.)
  - **Steady-state costs (top, both baselines):** Authentik secret-egress glue **~21–22s** · LiteLLM bulk prep + compose-up **~8s** · op-vault-export derive **~4.5–5s** · Authentik OIDC Forgejo register **~2.8s** · CIFS creds **~2.9s** · ~15× docker compose-up **1.4–2.5s** each · rest = Ansible-serial SSH/template/task machinery (~150 sub-1s tasks).
- **op_vault_export is READY for surgical scope** but NOT wired: `op-vault-export.py --derive` already takes a `services` list (`--spec-file`) → exports only those items' vault dict. The `docker_services_scope` var collapses the deploy loop, but the **static pre-pass still exports ALL enabled services' items** (5s) even for a scoped run, and the **Authentik/LiteLLM glue lanes still fire on `scope=all`** — so a single-service run is not yet truly minimal.
- **What the surgical machinery ALREADY supports (do not re-engineer, USE):**
  - Role tags on `vps.yml`: `common, docker, hardening, network, cifs, wireguard, docker_services, monitoring`.
  - **`docker_services_scope=<svc>`** (HD-255/HD-260): true single-service converge — collapses the loop so only that service iterates; also gates the platform tasks (networks/teardown/homepage) behind `scope==all`.
  - Externalized blueprints: `playbooks/authentik-blueprints.yml` (NOT in routine converge).
  - **Gap:** `scope` is a single-value **equality** check (`svc_entry.name == scope`), so **multi-service scope (`forgejo,traefik`) is NOT implemented** and a scoped run still pays the full static pre-pass + (on `scope=all`) the glue lanes.

## 3. Next-session execution order (the ONLY remaining path — data first, then surgery)

### Step 0 — pickup + validate the surgical primitive WORKS
- `git fetch origin && git status` (main → `2026…`/`e201ceb`).
- **Measure a real single-service scoped run** — the missing number for the whole lane (the "upgrade one service" time). Use the canonical form:
  ```bash
  bash scripts/ansible-run.sh playbooks/vps.yml --tags docker_services -e docker_services_scope=pi-dev
  ```
  Record: `PLAY RECAP`, `TASKS RECAP`, total wall time. **Expect ~30–70s** (still pays static pre-pass ~5s + per-service render/compose-up/systemd). This is the single most load-bearing measurement for the plan.
- **Measure a sensitive service** (the worst case): `... -e docker_services_scope=litellm` (its 8s glue is in-the-loop) and `... -e docker_services_scope=authentik` (OIDC lane). Compare.

### Step 1 — parallelize the two serial glue loops (~35s → target ~15s across the full converge)
Both are embarrassingly parallel (sub-ops independent).
- **Authentik glue (`authentik-secret-egress.sh`)** — the **21–22s** block: 9 providers × (1 curl API + 2 `op read`); writes are write-only-if-changed and serialize AFTER (safe). Parallelize the per-provider fetch+compare with `xargs -P` (keep the write step serialized per provider).
- **litellm glue (`litellm-bootstrap-keys.sh`)** — the **8s** block: 8 keys × (1 `op item get` + 1 `docker exec` HTTP probe). Parallelize the **probe** fast-path always (safe); keep the **mint/store** path serial (avoid `_enforce_unique_key_alias` races). `xargs -P` or background subshells.
- **Validate:** rerun the two static baselines → Authentik glue ≈ 22 → ≤8s; LiteLLM glue ≈ 8 → ≤4s; full converge wall ≈ 204 → **≤180s**. Exact TASKS RECAP timings post-change.
- Guard: 1P rate-limit (the HD-268 15→6 workers lesson) — keep `P` ≤ 4-6 on the op calls; only docker exec/curl probes may go wider.

### Step 2 — make multi-service scope real (the "update several at once" case)
- Interpret `docker_services_scope` as a **list** (`[forgejo,traefik]` or comma string) in `deploy-service.yml` (set-membership: `svc_entry.name in scope_list`), and gate the `docker_services == all` var accordingly. Keep `all` ⇒ everything.
- Update `docs/deployment-ansible.md` §tags/surgical: add the multi-service canonical invocation + the measured single-service number.
- Validate: `--tags docker_services -e docker_services_scope="forgejo,traefik"` only iterates those two (TASKS RECAP shows no other service).

### Step 3 — wire the surgical op pre-pass + conditional glue lanes
- **op-vault-export derive already supports surgical** (the `services` list) — pass the *scoped* needed set when scope != all (so a single-service run does NOT pay the ~5s all-items export). Guard carefully: the GLUE-seeded items (litellm scoped, authentik OIDC) must still be fetched when the corresponding lane runs.
- **Conditional glue:** run Authentik glue only when `authentik` is in scope **or** scope == all AND an OIDC consumer is in the loop; run LiteLLM glue only when `litellm` is in scope **or** a scoped-key consumer is. Default = the glue is skipped when its trigger service isn't in the run.
- Keep the **fail-closed** contract: no consumer ever renders with an empty/placeholder secret (the whole point of the glue ordering).

### Step 4 — decide the rare/base tier (final modulariser)
- The `common/docker/hardening/network/cifs/wireguard` roles are **bootstrap/tier-0** (rare — only change on infra reconfiguration). Options (pick in-session, do NOT decide now): (a) a `--tier bootstrap` arg switch; (b) a separate `playbooks/vps-bootstrap.yml`; (c) keep `--tags <role>` as the switch (already works). The LAST thing before declaring full modularisation: a **one-page runbook** in `docs/deployment-ansible.md` mapping "how long to [single service / several / full]" from the measured numbers.

### Step 5 — close-out (CONVENTIONS §4)
- Append `deployment-journal.md` entry: the measured single-service numbers, the parallelization deltas, the multi-service scope + surgical op-pre-pass evidence, and the new tier decision if one was made.
- Update `todo.md` HD-269 tail → done/wip. Meanwhile its sign-off: fold this lane's handoff into `prompt.md` at close (rename/merge).
- **Do NOT delete HD-268 line yet** — its tail is still ⏳ deploy-gated (see below).

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
- The dropping sourful (earlier brainstorm) parallelize-glue-suggestion is now Steps 1 in this deck — this session opted to (a) gather one more measured scoped run and (b) file this disciplined HD-lane rather than immediately patch glue.
- `prompt-FULL_CONVERGE.md` was a CLOSED HD-268 handoff — its remaining open tail (tailnet sidecar, Qdrant live-verify) is folded into the todo HD-268 **⏳** and this deck. Deleting that file, and documenting instead of running further glue-patch.
- (mark:) roll this handoff into `prompt.md` at HD-269 close.