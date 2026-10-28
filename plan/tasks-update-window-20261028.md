# tasks-update-window-20261028 — execution state of the `prompt-update.md` overnight window

> **Role:** the parent's work package for the unattended 2026-10-28 run of [`prompt-update.md`](../prompt-update.md)
> (fleet pin sweep + host-APT bump, exposed-secret rotations, converges, docs pass). It carries §A, the rules every
> child reads INSTEAD of receiving them in its launch text, §B the launch template, §C the per-task state, §D the
> report format, §E the merge log. Execution state for rows that already exist — never a second backlog.
> **Linked from:** [prompt-update.md](../prompt-update.md) (the runbook; it outranks this file on any fact),
> [todo.md](../todo.md) (the rows).
> **Writer:** the orchestrator only (O2). A lane never edits this file — it reports, the parent writes.
> **Death:** deleted in the commit that closes the window's last act (Phase 8).

## 0. The sitting

Seat: **WSL Debian, laptop** (`DomenP14s`), off-box for every target, `ansible-playbook` + `op` present.
`echo $PI_PROVIDER` → **`spark`** ⇒ Rule 0 binds the whole run, children included. Merge station
`/home/domen/source/homelab` at `668e5872`, clean. Child runtime as installed: `asyncByDefault: true`,
`timeoutMs: 7200000` (2 h), `globalConcurrencyLimit: 2`, `checkpointBeforeDeadlineMs: 600000`
(`~/.pi/agent/extensions/subagent/config.json` — effective, not authored).

Owner rulings for this sitting (2026-10-28 01:00, in-session):

| # | Ruling |
|---|---|
| N1 | Run **unattended**, converges included — a stuck host is acceptable, it gets named and left for the owner |
| N2 | **kopia_password + n8n_password re-keys: RUN** (the owner overrode the hold-default) |
| N3 | **router / switch: nothing tonight** — no router or switch act, no router converge, no WG / PPPoE / device-SNMP write. Everything Phase 5 names is parked with its exact blocked action |
| N4 | **spark: nothing tonight** — the whole of Phase 6 is out of the run (`provider=spark` + owner instruction) |
| N5 | Commit often per lane; **push at phase boundaries** from the station, with `todo.md` / `prompt.md` / `prompt-update.md` updated in the same phase commit |
| N6 | Accepted end-state: the leak gate stays red on the Wi-Fi PSKs, on `spark-llm_api`/`litellm-engine_api` (Phase 6 not run) and on `pppoe_login`/Soulseek (not rotatable) — named, dated, not a failure |
| N7 | Row/line-count size reminders: **ignore** — write what matters, facts not history; no changelog prose anywhere |

## A. Night rules — READ THIS INSTEAD OF BEING TOLD TWICE

Repo SSOT `/home/domen/source/homelab` is the **merge station — never edit it**. You work only in the worktree your
launch names, on your branch. Ritual first: `grep -n "^#\|^## \|^### " CONVENTIONS.md | head -40`, then
`CONVENTIONS.md`, [`docs/orchestration.md`](../docs/orchestration.md) §4 (O1–O11),
[`prompt-update.md`](../prompt-update.md) (§5a/§5b/§5c + §6/§7 as your task names).

1. **No spark acts at all** (N4): no spark converge, no engine restart, no `spark-ai` / `lan-litellm` / spark-side
   `litellm` re-render, no OTA, no profile flip, no `spark-llm_api` / `litellm-engine_api` rotation, no spark build or
   prune. Editing IaC that merely mentions spark is allowed. An item whose far end or proof needs spark ⇒ **park** it,
   with the exact blocked action in the row's ⏳ tail (O4) — never a vault-only write for it.
2. **No router/switch acts** (N3), no `/import`, no WG / PPPoE / SNMP-community write, ⛔ never `--diff` on the router
   playbook (it dumps the PPPoE password). Park, do not stall.
3. **Converges are DETACHED**: `nohup bash scripts/ansible/ansible-run.sh playbooks/<x>.yml --tags <t> > /tmp/converge-<host>-$(date +%Y%m%d-%H%M).log 2>&1 &`, then poll the log.
   `--check` first in the foreground proves **scoping only**, never a verdict, and on a held suite it skips the apt leg.
   ⛔ never `--diff` anywhere (it renders vault secrets — `alloy.river.j2` included). One converge in flight per host
   (O3): converge **only** the hosts your launch names; another host's need becomes an ⏳ plus a line in your report.
   `nas` converges always carry `--skip-tags alloy`.
4. ⛔ never `--allow-change-held-packages`; never a blanket `apt-mark unhold $(apt-mark showhold)`. A held package is
   not a pinned package — the role asserts it.
5. **Secrets (§5a, CONVENTIONS §3):** never a value, length, prefix, hash-of-value, or captured line — ids, item titles,
   Integration IDs only. Far end **first**, then the vault, then propagate by converge, then prove **both directions**
   (new accepted, superseded refused) printing nothing. ⛔ never a hand-run `ALTER ROLE` (desyncs the
   `pgsync:<sha256>` marker); never `env` / `set` / `/proc/<pid>/environ`; never a transcript deleted or shredded
   (HD-1181). `--rotate` refusing a `NOT_AUTO_ROTATABLE` name is correct, not an invitation to hand-generate.
6. **Do NOT run `check_secret_leak.py --update-ledger`** — the ledger is one commit in Phase 7 by the parent.
7. Commit after **each** deliverable, before starting the next; plain `git commit` (signing retired, never `-s`).
   2 h deadline — checkpoint and report rather than being cut off; a killed lane commits nothing and is lost.
8. Do NOT edit `prompt.md` or `todo-table.md` (O2). `todo.md`: row-local hunks/⏳ tails only, never re-sort or reflow.
   ⛔ mint no new HD ids; a closed row is deleted, a doc states facts and never session history (N7).
9. Leave no residue: no uncommitted tree, no `ssh -N/-L/-D` you opened, no listener. Kill it in your own lane.

## B. Launch template (the parent fills `<…>`; keep the launch under ~25 lines)

```
Lane <id> of the 2026-10-28 update window. Worktree <path>, branch <branch>.
READ FIRST: plan/tasks-update-window-20261028.md §A and §D (they ARE the rules), then
prompt-update.md <sections>, todo.md rows <ids>.
TASK: <one deliverable + the exact evidence that proves it>
HOST SLOTS YOU OWN: <hosts>  (O3 — nothing else gets converged by you)
WRITES YOU OWN: <disjoint file list>   (nothing else; a file you must touch but do not own: report it)
PARKS: spark (N4) and router/switch (N3) are out — park with the exact blocked action, keep going (O4).
```

Then `async: true`, `agent: worker`, `cwd: <worktree>`, `options: {checkpointBeforeDeadlineMs: 600000}`.

## C. Work packages

State: `[ ]` open · `[~]` in flight · `[!]` partial (resume sha) · `[?]` parked on owner/Phase-6 · `[=]` absorbed · `[X]` done.

| id | deliverable | writes (disjoint) | hosts | state |
|---|---|---|---|---|
| P1-a | §2(a) hold-lift legs into `roles/monitoring` (`alloy`) + `roles/tailscale-node` (deb), with the `[monitoring, alloy]` tag vocabulary + both-directions assert | `IaC/ansible/roles/monitoring/tasks/main.yml`, `IaC/ansible/roles/tailscale-node/tasks/main.yml` | — | `[~]` lane `prereq-code` / wt-0105 / `session/prereq-code-20261028-0105` (a1be8165) |
| P1-b | §2(b) `image-pin-probe.py` `DEFAULT_ROOT` fix; `--verify` + `--debs` proven; report derived pins + tailscale digests (no `versions.yml` edit) | `scripts/ansible/image-pin-probe.py`, `scripts/README.md` | — | `[~]` same lane, same commit series |
| P1-c | §4 tombstone: mask `docker-compose@dgx-dashboard.service` in the spark role, delete the registry entry, rewrite the `docs/hardware-spark.md` sentence | `IaC/ansible/group_vars/spark.yml`, `IaC/ansible/roles/spark/**`, `docs/hardware-spark.md` | none (author-only; applying the mask is a spark converge ⇒ `[?]` Phase 6) | `[ ]` |
| P1-d | §3 pin commit: host-APT family + patch/minor containers + re-fetched `tailscale_host_deb_sha256_by_arch`, one change; excludes majors, date-downgrades, digest-pinned images, keepalived/technitium/headscale/ollama/home_assistant | `IaC/ansible/group_vars/all/versions.yml` | none | `[ ]` after P1-a/P1-b merge |
| P2 | Phase 2 rotations: `litellm_api`, NUT pair as one act (nas master + oldsrv + pi clients), `authentik_db`/`forgejo_db`/`immich_db` vault-only writes, `pgvector_db` verdict | `IaC/ansible/group_vars/**`, `IaC/ansible/host_vars/**`, `docs/1password.md`, `docs/deployment-secrets.md`, `todo.md` | vps, nas, oldsrv, pi | `[~]` lane `rot-p2` / wt-0106 / `session/rot-p2-20261028-0106` (8a404a30) |
| P3-a | Phase 3 §5b device/API far ends, **non-router**: `kopia-server_fingerprint` (cert → `kopia-fingerprint-sync.yml` → both pinning sides), `crowdsec-bouncer_api` (`cscli` + both Traefik edges), `headplane_api` (headscale mint + expire, `guarded-converge.sh`) | `IaC/ansible/group_vars/**`, `docs/network-vpn.md`, `docs/services-traefik.md`, `docs/backup.md` | vps, oldsrv | `[ ]` |
| P3-b | Phase 3 probe-first trio: `technitium_login` (+ its `admin @dns.kogler.si` copy), `opencloud_login`, `openclaw_gateway_token` — prove the far-end path answers **before** any write; no answer ⇒ it becomes §5c with a line in its row, never a vault-only write | `IaC/ansible/group_vars/**`, `docs/network-dns.md`, `docs/services-*.md` | vps (Technitium primary; secondary/tertiary on oldsrv + pi) | `[ ]` |
| P3-c | `lidarr_api` in HD-1091's forced order (mint → Lidarr `config.xml` → restart → soularr `config.ini` → Seerr), `bazarr_api`, the `admin @media.kogler.si` + `admin @radarr.kogler.si` web-auth users | `IaC/ansible/group_vars/**`, `docs/services-media.md` | nas | `[ ]` |
| P3-d | `soulseek_api` (slskd web UI) + `qbittorrent_api` + the already-rotated `privado-vpn_api` **propagation** (the `privado_vpn_*` edit in `group_vars/home_servers.yml`, read field-wise from the item's notes, then the oldsrv `docker_services` leg, then prove the egress IP + one qbit/slskd connect) | `IaC/ansible/group_vars/home_servers.yml`, `docs/services-rejected.md` | oldsrv, nas | `[ ]` |
| P3-e | The two re-keys **with their consequences scheduled** (N2): `kopia_password` (re-key + agent reconnect + repository verify + one restore listing — backups must not stop quietly) and `n8n_password` (`N8N_ENCRYPTION_KEY`: export under the old key **as the gate**, re-import under the new, then the vault write) | `docs/backup.md`, `docs/services-automation.md`, `IaC/ansible/group_vars/**` | nas (kopia), oldsrv/vps (n86 — as IaC says) | `[ ]` |
| P3-f | `oldsrv-domen_login` (host + vault together, second session open, prove `sudo -l -U domen` + one root read), `cockpit-pi-web_api` (⚠ not from a cockpit seat), `grafana_login`, `opencloud-collab_password`, `immich-ml-internal_api`, `n8n-webhook_api`, `signal-internal_api`, `victoria-metrics_api`, `victoria-logs_api` — the render-is-the-far-end set the register still names | `IaC/ansible/group_vars/**`, `docs/1password.md` | oldsrv, pi, vps | `[ ]` |
| P4 | Phase 4 converges, canary first, one host at a time, detached: **pi → vps → nas (`--skip-tags alloy`) → oldsrv** (`docker` → `monitoring` → `tailscale-node`; oldsrv's tailscale leg from this station only; vps's headscale/headplane behind `guarded-converge.sh`). Per host after: roster up, `RestartCount` flat, the role's own `apt-mark showhold` assert green, pin gauge read back | `todo.md`, `deployment-tasks.md`, `docs/observability.md` | pi, vps, nas, oldsrv | `[ ]` after P1-d |
| P5 | Phase 5 | — | router/switch | `[?]` **not tonight** (N3) |
| P6 | Phase 6 (OTA, spark pin converge, engine-key rotation, dispatch check, profile flips, gates) | — | spark | `[?]` **not this run** (N4 + Rule 0) |
| P7 | Phase 7: re-seat every `op_api` consumer (oldsrv control node, oldsrv seat `domen`, this laptop, Forgejo Actions) proven by Integration ID + `sha256[:12]`; then **parent** runs `--update-ledger --class run-capture`, deletes STALE lines, commits the shrunk ledger | `scripts/gate/secret_leak_ledger*`, `todo.md` | vps, oldsrv, laptop | `[ ]` |
| P8 | Phase 8: `todo.md` + owning docs for everything proved; `prompt.md` + affected briefs brought in line; `todo-table.md` §B0 wiring; **delete `prompt-update.md` and this file** in the same commit | views + briefs + `todo.md` | — | `[ ]` |

## D. Report format (a lane's whole deliverable)

Evidence, never prose: branch + sha per commit · `git log --oneline main..HEAD` · `git show --stat` per commit ·
`file:line` per claim · a per-item/per-leg table with a verdict column · `bash scripts/validate-all.sh; rc=$?` **rc**
plus the failure list (pre-existing named reds: `check_secret_leak.py --self-test` = HD-1211, live-value debts =
HD-1181, Wi-Fi PSKs = N6 — do not "fix" them) · the **parks**, each with the exact blocked action · the exit check:
`git status --porcelain` empty, `ps -eo args | grep -E 'ssh .*(-N|-L|-D)'` and `ss -ltn` showing nothing you opened.
A report with no commit is a report of nothing; the parent trusts `git log`, not the prose.

## E. Merge log (parent)

- station `668e5872` clean; baseline `validate-all.sh` run at the clean tip before any lane.
- lanes live: `prereq-code` (wt-0105), `rot-p2` (wt-0106) — ≤2 at a time (O11), disjoint hosts and writes.
