# prompt-hd185 — Fix Pi first-deploy ordering (docker_services vs home_assistant)

> **Role:** Task handoff for **HD-185** (todo.md §2.6). **AI + gate**: confirm the chosen option
> with the human before rewriting playbook order — it touches the KOPS-063/HD-117 decision.
> **Linked from:** [todo.md](todo.md) (HD-185); audit evidence: `docs-vs-iac.md` §J2, `iac-changes.md` §11 D2.

## Problem

`playbooks/raspberry_pi.yml` runs `docker_services` **before** `home_assistant` (KOPS-063/HD-117:
"HA containers up before config keepalived/VIP renders"). But
`roles/home_assistant/tasks/pi.yml` renders `config/configuration.yaml`, `keepalived.master.conf`
and (pending) `secrets.yaml` — and its header still claims the opposite order.

At first `docker compose up -d` for `home-assistant-primary`, Docker bind-mount sources
`./config`, `./secrets.yaml`, `./keepalived.conf` do not exist → **Docker auto-creates each as an
empty directory**. Then:

- the HA container starts with an empty `/config` (default config generated, never restarted), and
- `home_assistant` later fails: `copy keepalived.master.conf → /opt/home-assistant-primary/keepalived.conf`
  hits an existing **directory** (and its `force: false` would also skip a pre-created *empty file*).

Net: Pi deploy blocked / HA silently mis-configured. The standby is safe (`enabled: false` — its
compose never runs via the loop; `ha-failover.sh` creates `keepalived.conf` at takeover).

## Options (pick one, confirm at the gate)

- **A. Render-first (recommended):** on the Pi, run `home_assistant` before `docker_services`
  (revert KOPS-063 for this host). Config/keepalived exist before first `up`; containers start
  already configured. Update the KOPS-063 comment to the new rationale + note in changelog that
  HD-117's ordering decision is superseded **for the Pi**.
- **B. Pre-create real files before `up`:** keep order; have the docker_services copy step (or an
  early home_assistant "render-only" tag) place real files first. Watch the `force: false`
  semantics on `keepalived.conf` — an empty placeholder would suppress the master-conf copy.
- **C. Fail-loud mounts:** long-syntax volumes with `create_host_path: false` so a missing file
  aborts `up` instead of mkdir-ing. Honest, but breaks the deploy loop at first run by design.

## Steps (for any option)

1. Read the KOPS-063/HD-117 changelog entries first; state which option and why in the PR/commit.
2. Implement; make the role-header comment in `pi.yml` match reality.
3. Add a first-boot guard regardless of option: assert on the Pi that
   `/opt/home-assistant-primary/keepalived.conf` is a **regular file** before `docker compose up`
   (fail loud with a remediation hint) — belt-and-braces against future reorders.
4. `bash scripts/validate-all.sh` green (no template changes expected → validator unaffected).
5. todo.md: HD-185 ✅ with `⏳ Deploy-gated:` tail (first real Pi deploy, Phase 4); changelog row.

## References

- `docs/smart-home-failover.md` (config-sync + keepalived contract)
- `roles/home_assistant/tasks/pi.yml`, `tasks/main.yml` (order comments to fix)
- `docs-vs-iac.md` §J2 for the full failure trace

**Cleanup:** delete this handoff (`prompt-hd185.md`) in the same closing change (A3 lifecycle, CONVENTIONS §4; HD-203 sweeps any leftovers).
