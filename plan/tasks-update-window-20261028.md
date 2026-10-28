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
| P1-a | §2(a) hold-lift legs into `roles/monitoring` (`alloy`) + `roles/tailscale-node` (deb), with the `[monitoring, alloy]` tag vocabulary + both-directions assert | `IaC/ansible/roles/monitoring/tasks/main.yml`, `IaC/ansible/roles/tailscale-node/tasks/main.yml` | — | `[X]` merged `aec5eb68`. **Ruling (parent):** the tailscale leg keeps `tags: [tailscale-node]` only — a new tag over a lockout role would have to enter `homelab_guard_tags` and the guard task's own `tags:` together (`check_self_converge_guard.py`), and both playbooks already tag the role, so nothing was being repaired by widening it. `monitoring` carries `[monitoring, alloy]` (bare role entry in 4 playbooks) |
| P1-b | §2(b) `image-pin-probe.py` `DEFAULT_ROOT` fix; `--verify` + `--debs` proven; report derived pins + tailscale digests (no `versions.yml` edit) | `scripts/ansible/image-pin-probe.py`, `scripts/README.md` | — | `[X]` merged `aec5eb68` — `--verify` 104 rows, `--debs` OK both arches, the four docker-family pins got `SOURCES` rows (`PIN EXISTS = feed-only` for those). `versions.yml` untouched; values moved into P1-d |
| P1-c | §4 tombstone: mask `docker-compose@dgx-dashboard.service` in the spark role, delete the registry entry, rewrite the `docs/hardware-spark.md` sentence | `IaC/ansible/group_vars/spark.yml`, `IaC/ansible/roles/spark/**`, `docs/hardware-spark.md` | none (author-only; applying the mask is a spark converge ⇒ `[?]` Phase 6) | `[ ]` |
| P1-d | §3 pin commit: host-APT family + patch/minor containers + re-fetched `tailscale_host_deb_sha256_by_arch`, one change; excludes majors, date-downgrades, digest-pinned images, keepalived/technitium/headscale/ollama/home_assistant. Also clears the stale `5:29.8.2` literals in `roles/docker`'s `versions.yml` comments and the now-incomplete "`roles/docker` is the only role that lifts" sentences (`IaC/ansible/roles/common/tasks/apt-holds.yml`, `docs/deployment-ansible.md`) | `IaC/ansible/group_vars/all/versions.yml`, `IaC/ansible/roles/common/tasks/apt-holds.yml`, `docs/deployment-ansible.md` | none | `[X]` merged `75ae63a3`. 7 host-APT rows + `tailscale_host_deb_sha256_by_arch` fetched in-commit + 36 container patch/minor rows; post-edit `--verify` 43/43 moved rows CUR == ELIGIBLE, `--debs` OK, gate rc 0, syntax-check green. **Not taken:** 3 pi seat pins (seat-class: applied by the seat plane / `pi-self-update.sh --push`, never by this window -> parked for the seat lane), 6 flagged rows (keepalived, technitium, headscale, headplane, ollama `-rocm`, home_assistant), 7 majors, 3 date-downgrades, all digest pins, plus `openclaw`/`zipline` declined on the live-failure record their own rows carry |
| P2 | Phase 2 rotations: `litellm_api`, NUT pair as one act (nas master + oldsrv + pi clients), `authentik_db`/`forgejo_db`/`immich_db` vault-only writes, `pgvector_db` verdict | `IaC/ansible/group_vars/**`, `IaC/ansible/host_vars/**`, `docs/1password.md`, `docs/deployment-secrets.md`, `todo.md` | vps, nas, oldsrv, pi | `[X]` merged `5720db66`. Rotated + propagated + proved both directions: `litellm_api` (vps `litellm` + oldsrv `lan-litellm`; new→200, superseded→401), `nut_password`+`nut-exporter_password` (nas master → oldsrv → pi; superseded `ERR ACCESS-DENIED`, both clients `OL`), `authentik_db`/`forgejo_db`/`immich_db` (vault-only writes; the vps `db_role_sync` ALTER against its own `pgsync:<sha256>` marker — all three markers == `sha256(vault)`). `pgvector_db` **parked on the owner**: delete item `zymyueiv` TOGETHER with `/opt/.retired-pgvector` + `/srv/docker/.retired-pgvector` on vps — a vault write there is the `NOT_AUTO_ROTATABLE` divergence class. KNOWN-EXPOSED 20 → 14 pairs; 6 ledger lines now read STALE and wait Phase 7 |
| P3-a | Phase 3 §5b device/API far ends, **non-router**: `kopia-server_fingerprint` (cert → `kopia-fingerprint-sync.yml` → both pinning sides), `crowdsec-bouncer_api` (`cscli` + both Traefik edges), `headplane_api` (headscale mint + expire, `guarded-converge.sh`) | `IaC/ansible/group_vars/**`, `docs/network-vpn.md`, `docs/services-traefik.md`, `docs/backup.md` | vps, nas (slot corrected: kopia-server is on nas; `oldsrv` is a later lane) | `[X]` merged `6d77778c` (finisher run 167c0b00). Rotated + propagated + proved: `crowdsec-bouncer_api` (new LAPI row `traefik-bouncer-20261028`, both edges re-rendered, old rows 15 -> 1, new 200 / superseded 403), `headplane_api` (mint + expire-by-proven-id, guard green, `RestartCount` 0), `kopia-server_fingerprint` (cert retired + minted with the SSOT SAN, sync task wrote the item, oldsrv agent re-connected; live pin rc 0 / superseded rc 1), and `kopia-server-internal_api` (the leak close - `server.htpasswd` for BOTH identities, live 403 vs superseded 401). Backup coverage confirmed: boot-pass snapshot 06:19, loop re-armed from a success. Act 5 fixed the `elif op item create` duplicate-mint bug with a stub-`op` harness over all six paths |
| P3-b | Phase 3 probe-first trio: `technitium_login` (+ its `admin @dns.kogler.si` copy), `opencloud_login`, `openclaw_gateway_token` — prove the far-end path answers **before** any write; no answer ⇒ it becomes §5c with a line in its row, never a vault-only write | `IaC/ansible/group_vars/**`, `docs/network-dns.md`, `docs/services-utilities.md` | vps (Technitium primary; secondary/tertiary on oldsrv + pi) | `[ ]` |
| P3-c | `lidarr_api` in HD-1091's forced order (mint → Lidarr `config.xml` → restart → soularr `config.ini` → Seerr), `bazarr_api`, the `admin @media.kogler.si` + `admin @radarr.kogler.si` web-auth users | `IaC/ansible/group_vars/**`, `docs/services-media.md` | nas | `[ ]` |
| P3-d | `soulseek_api` (slskd web UI) + `qbittorrent_api` + the already-rotated `privado-vpn_api` **propagation** (the `privado_vpn_*` edit in `group_vars/home_servers.yml`, read field-wise from the item's notes, then the oldsrv `docker_services` leg, then prove the egress IP + one qbit/slskd connect) | `IaC/ansible/group_vars/home_servers.yml`, `docs/services-rejected.md` | oldsrv, nas | `[ ]` |
| P3-e | The two re-keys **with their consequences scheduled** (N2): `kopia_password` (re-key + agent reconnect + repository verify + one restore listing — backups must not stop quietly) and `n8n_password` (`N8N_ENCRYPTION_KEY`: export under the old key **as the gate**, re-import under the new, then the vault write) | `docs/backup.md`, `docs/services-utilities.md`, `IaC/ansible/group_vars/**` | nas (kopia), oldsrv/vps (n86 — as IaC says) | `[ ]` |
| P3-f | `oldsrv-domen_login` (host + vault together, second session open, prove `sudo -l -U domen` + one root read), `cockpit-pi-web_api` (⚠ not from a cockpit seat), `grafana_login`, `opencloud-collab_password`, `immich-ml-internal_api`, `n8n-webhook_api`, `signal-internal_api`, `victoria-metrics_api`, `victoria-logs_api` — the render-is-the-far-end set the register still names | `IaC/ansible/group_vars/**`, `docs/1password.md` | oldsrv, pi, vps | `[ ]` |
| P4 | Phase 4 converges, canary first, one host at a time, detached: **pi → vps → nas (`--skip-tags alloy`) → oldsrv** (`docker` → `monitoring` → `tailscale-node`; oldsrv's tailscale leg from this station only; vps's headscale/headplane behind `guarded-converge.sh`). Per host after: roster up, `RestartCount` flat, the role's own `apt-mark showhold` assert green, pin gauge read back | `todo.md`, `deployment-tasks.md`, `docs/observability.md` | pi, vps, nas, oldsrv | `[~]` **Debian hosts converged**: pi `63e64432`, oldsrv+nas (this phase, `d816d9dc`), vps `d816d9dc`. vps: alloy 1.21.2-1 with its hold re-asserted, docker family already at the pins, the tailnet **sidecar** `v1.102.5 -> v1.104.2` via the `traefik-tailnet` scope (the only tree site for the container tag), HD-1166's page closed on the box, HD-1106's named-volume fix applied (WOPI keypair digest identical across the recreate). **spark is NOT converged** (P6) - it stays on the old docker family and publishes its old pin map; name it in Phase 8 like the nas alloy exception. **Gauge fact, sharper than §F:** a converged host publishes BOTH pin maps for one lookback window (`match 8 / differ 6 / missing 2` caught mid-decay), and on vps the container-side tailscale pin is invisible to the gauge (`missing`, no deb) - the only proof is `docker exec tailscale-sidecar tailscale version`. |
| P5 | Phase 5 | — | router/switch | `[?]` **not tonight** (N3) |
| P6 | Phase 6 (OTA, spark pin converge, engine-key rotation, dispatch check, profile flips, gates) | — | spark | `[?]` **not this run** (N4 + Rule 0) |
| P7 | Phase 7: re-seat every `op_api` consumer (oldsrv control node, oldsrv seat `domen`, this laptop, Forgejo Actions) proven by Integration ID + `sha256[:12]`; then **parent** runs `--update-ledger --class run-capture`, deletes STALE lines, commits the shrunk ledger | `scripts/gate/secret_leak_ledger*`, `todo.md` | vps, oldsrv, laptop | `[ ]` |
| P8 | Phase 8: `todo.md` + owning docs for everything proved; `prompt.md` + affected briefs brought in line; `todo-table.md` §B0 wiring; **delete `prompt-update.md` and this file** in the same commit | views + briefs + `todo.md` | — | `[ ]` |

## D. Report format (a lane's whole deliverable)

Evidence, never prose: branch + sha per commit · `git log --oneline main..HEAD` · `git show --stat` per commit ·
`file:line` per claim · a per-item/per-leg table with a verdict column · `bash scripts/validate-all.sh; rc=$?` **rc**
plus the failure list. On this seat `validate-all.sh` is **green at the merged tip** (the leak gate's
SDK-seat arm was fixed upstream and its row closed); a red you may see on another seat is a live-value debt — the
Wi-Fi PSKs (N6), `spark-llm_api`/`litellm-engine_api` (P6 not run), `pppoe_login` and the Soulseek login (not
rotatable). Name such a red, never "fix" it · the **parks**, each with the exact blocked action · the exit check:
`git status --porcelain` empty, `ps -eo args | grep -E 'ssh .*(-N|-L|-D)'` and `ss -ltn` showing nothing you opened.
A report with no commit is a report of nothing; the parent trusts `git log`, not the prose.

## E. Merge log (parent)

- station `668e5872` clean; baseline `validate-all.sh` at the clean tip: **134 items, 1 red = the leak gate's
  vault-unreachable self-test arm**, the window's named exception at dispatch time — fixed upstream later the same
  night, so the tip is green now.
- `session/prereq-code-20261028-0105` rebased onto `32d283df`, gated in its worktree (1 red = HD-1211), **FF-merged as `aec5eb68`** (P1-a + P1-b). Lift legs proven offline (11 assertions + mutation runs), no converge run — the legs are live-unverified until Phase 4.
- `origin/main` had moved (the leak gate's SDK-seat arm fixed and its row closed upstream, plus the re-seal). The window's six unpushed commits were **rebased onto `origin/main`** at a clean station; `todo.md` merged row-wise where the HD-1181 row collided (union: main's text + the lane's register tail; the row upstream closed stayed closed). Row-id sets proven identical with `comm -3` before the FF-merge.
- `session/rot-p2-20261028-0106` rebased, gated green in its worktree, **FF-merged as `5720db66`**, worktree removed, branch deleted. Pushed: station level with `origin/main`, gate rc 0.
- lanes live: **none** - the session closes here with the window INCOMPLETE: R2 (media), R3 (the two re-keys), R4 (the two-host pairs), R5 (host credentials), R6 (probe-first trio), R7 (Phase 7: `op_api` re-seats + the ledger commit), R8 (Phase 8: docs pass, `prompt.md`/`todo-table.md`, delete this file and `prompt-update.md`) are all still open.
- merged: P1-a/b `aec5eb68`, P1-d `75ae63a3`, P2 `5720db66`, P4-pi `63e64432`, doc-values `2da225aa`, P3-a `6d77778c`, R1b/R1a `d816d9dc`. Station clean, gate rc 0, pushed, one worktree, no lane process left holding a host.
- merged so far: P1-a/b `aec5eb68`, P1-d `75ae63a3`, P2 `5720db66`, P4-pi `63e64432`, doc-values `2da225aa`, P3-a `6d77778c` (+ bookkeeping). FF only, gate rc 0, pushed.
- merged so far: P1-a/b `aec5eb68`, P1-d `75ae63a3`, P2 `5720db66`, P4-pi `63e64432` (+ bookkeeping). Every merge FF, gate rc 0, pushed.

## F. Carried findings (not a lane's work, not a row)

- The pin commit moved values that other docs quote as examples — `roles/docker/tasks/main.yml:106-113`, `roles/monitoring/templates/homelab-hygiene.py.j2:403,410`, `docs/observability.md` (pin-lag + the "roles/docker lifts" sentence), `docs/security.md`, `docs/services-{traefik,authentik,matrix,admin,media,ai}.md`, `docs/hardware-nas.md`. Phase 8's doc pass reconciles them against `versions.yml`; a quoted example that contradicts the SSOT is a defect, not a style note.
- `keepalived_version`'s comment still says the newer release "sits inside the hold"; it is eligible and was skipped for its VIP mini-window. For the keepalived lane, not for this window.
- kopia-agent on oldsrv logs pre-existing permission-denied paths (`/mnt/src/signal-cli-data/{stickers,avatars,data}`, `/mnt/src/opt/soularr/config/config.ini`) during snapshot — a real backup gap, unrelated to P3-a, belongs in its owning doc/row.
- **Gauge semantics, measured by the pi canary (changes §7's assumption).** `homelab_pkg_pin_result` compares against each host's **last-rendered** pin map, so an un-converged host publishes `match` at its OLD pins and the pin-lag rule stays quiet — an empty `differ` read is NOT evidence the fleet moved, and the window in flight is invisible to that gauge. A transient `differ` appears between a host's package apply and its `monitoring` re-render. Written once in `docs/observability.md` §Pin-lag report.
- **Spark's end-state deviation must be named in Phase 8** (P6 parked): spark converges nothing tonight, so it runs the old docker family and publishes its old pin map. Phase 8's exception list should read like the `nas` alloy one — a named host, a named reason, no narrative.
- **Queued for the oldsrv converge lane:** the tailscale-node arch read has no `check_mode: false`, so `--tags tailscale-node --check` aborts at the digest assert with `architecture ''` (HD-1128's ⚠, re-measured on pi). The fix is one task attribute; it belongs with a run that needs the leg, not with the doc sweep.
- **Run-capture leak, `rot-devices` lane (2026-10-28 ~05:5x):** `docker logs --since 2m kopia-agent` on oldsrv put kopia's own connect line — server URL **with userinfo** — into the lane transcript, i.e. the current `kopia-server-internal_api` credential and the `oldsrv-agent@…` identity. Remedy granted in-lane: rotate `kopia-server-internal_api` (act 4) with its `server.htpasswd` propagation on both identities; ⛔ no transcript deletion, no `--update-ledger` (Phase 7's book re-derivation drops the rotated pair by itself). The lane's stdout rule from now on: kopia invocations discard stdout/stderr, verdicts are exit codes only. Commit-message fact, not a doc sentence.
- **Vault defect found (fixed in-lane, act 5):** `roles/docker_services/tasks/kopia-fingerprint-sync.yml`'s `elif op item create` branch mints a **duplicate** vault item when `op item edit` returns op-2.39's spurious HTTP error. One duplicate `kopia-server_fingerprint` was created during the converge and deleted by id; the fix is re-read-and-verify after a non-zero edit rc, create only when the title is proven absent.

## G. Remaining dispatch plan (scout-derived, 2026-10-28 ~07:00)

Scout read (one seat): `check_secret_leak.py` → **0 FAIL**, 14 KNOWN-EXPOSED; the 6 rotated pairs are STALE awaiting Phase 7. Of the 18 open Phase-3 items **none is genuinely blocked on a human** — spark and the router/switch touch none of them. Four items span two host slots, so a half-moved pair reads green while every call 401s; those must be ONE lane. Register-named among these: `lidarr_api`, `soulseek_api` (the rest are named by the pi-dev seat's read, whose union §5a step 3 requires).

Serial, because nearly everything lands on vps/oldsrv and O3 allows one converge per host. Max 2 children, but only one may hold a host.

| # | lane | items | hosts | notes from the scout |
|---|---|---|---|---|
| R1 | **Phase 4 converges** | the pin apply | vps → nas (`--skip-tags alloy`) → oldsrv | vps fold-ins §11 (HD-1166 one `--tags monitoring`, HD-1106 the `onlyoffice-docs` named volume BEFORE any `docker volume rm`, HD-436 behind `guarded-converge.sh`, HD-487 `--tags netd`); oldsrv needs the tailscale arch-read `check_mode:false` fix (HD-1128) in the same lane |
| R2 | media lane | `lidarr_api` (HD-1091 order: mint → Lidarr `config.xml` → restart → soularr `config.ini` → Seerr), `bazarr_api` (⛔ `--rotate` — app first, then the item round-trip; **no IaC render at all**), `admin @media.kogler.si` (Jellyfin endpoint), `admin @radarr.kogler.si` (**probe-first**: DB vs `config.xml`, stop→hash→start), `soulseek_api` (slskd session proof new→200/old→401, then on-network), `qbittorrent_api` (`--rotate` + `qbittorrent-seed.yml`, consumers are the four arrs) | oldsrv (the P3-c row's `nas` is wrong — media far ends are oldsrv per `home_servers.yml:279-304`) | register-named pair lives here |
| R3 | re-keys | `kopia_password` (re-key + agent reconnect + repository verify + one restore listing), `n8n_password` (`N8N_ENCRYPTION_KEY`: export under the old key **as the gate**, re-import under the new) | vps, oldsrv (nas for the kopia repo side) | consequences scheduled, not avoided (N2) |
| R4 | the two-host pairs | `victoria-metrics_api` + `victoria-logs_api` (username+password in lockstep, one Alloy restart; the **datasource-delete** step is load-bearing — Grafana datasources are create-only, so without a delete the row is a silent half-rotation), `immich-ml-internal_api` (vps+oldsrv), `signal-internal_api` (vps+oldsrv), `n8n-webhook_api` (vps compose + the Grafana contactpoint), `opencloud-collab_password` (four sites across two compose files; users re-login), `grafana_login` (probe the `grafana-cli reset-admin-password` path; a render-only rotation can leave the datasource seeded with a stale value) | vps + oldsrv | |
| R5 | host credentials | `oldsrv-domen_login` (host + vault in the SAME act, second session open, prove `sudo -l -U domen` + one root read before closing), `cockpit-pi-web_api` (renders on oldsrv via `roles/seat` → `pi-web-env.j2`; every paired cockpit client re-pairs — ⚠ doc defect: `docs/deployment-secrets.md:387` describes a Traefik middleware half IaC does not implement) | oldsrv, pi | |
| R6 | probe-first trio | `technitium_login` **+** `admin @dns.kogler.si` (a second copy with no sync in the tree — move both or the DNS seed breaks; prove the endpoint accepts the old vault value first), `opencloud_login` (`IDM_ADMIN_PASSWORD` applies at init — prove a re-render moves a live password), `openclaw_gateway_token` (`openclaw onboard` non-interactive? else `docker exec` the generated `openclaw.json`) | vps + oldsrv + pi | no answer ⇒ the item becomes §5c with a line in its row, never a vault-only write |
| R7 | Phase 7 | re-seat every `op_api` consumer (oldsrv control node, oldsrv seat `domen`, this laptop, Forgejo Actions) by Integration ID + `sha256[:12]`; **then the ledger commit** (`--update-ledger --class run-capture`, delete STALE by hand) | vps, oldsrv, laptop | the commit that turns the gate green |
| R8 | Phase 8 | `todo.md` + owning docs; `prompt.md` + affected briefs; `todo-table.md` §B0; **name the exceptions** (`nas` alloy, spark-not-converged, Wi-Fi PSKs, P5 router); delete `prompt-update.md` + this file | — | last content act |
- **Owner call, no lane may act on it:** `headscale apikeys list` shows rows **id 1 and id 2** (created 2026-08-24, expiring 2050-08-18) whose public prefixes match nothing in the vault or in any rendered config — live API keys with no owner in the tree. The vault's key was id 3 and was expired by proof. Revoking 1 and 2 is an owner decision; nothing found so far authenticates with them.
- **`provision-secrets.py --rotate` misreports a landed write as FAILED** when `op item edit` returns the op-2.39 spurious HTTP error (measured in act 4; the re-read proved the value in). Same root cause the fingerprint-sync fix removed — the re-read-and-verify belongs in the provisioner too. Queued as **R9** (file-only, with a stub-`op` self-test arm), not done inside a converge lane.
- **kopia-server's compose renders no `env_file:`**, so the boot command's `${KOPIA_SERVER_ADDR_HOST:-127.0.0.1}` falls back and a fresh-volume boot or a cert regen produces a **loopback-only SAN** while the agent dials `wg_s2s_vps.ip`. The trap is written in `docs/backup.md`; the assert belongs in the template — R9, and it needs a converge to prove, so it is not a quiet fix.
- Two docs still name the bare `traefik-bouncer` row (`docs/deployment-secrets.md:419`, `deployment-manual.md:890`) — the live row is `traefik-bouncer-20261028`. R9.
- **Transport kill, 2026-10-28 ~07:0x (both Phase-4 lanes).** The vps `docker` leg restarts the tailnet sidecar and Traefik; that dropped the parent's SSH path and both children died on a request timeout mid-run. Nothing was lost that a log cannot show: `--tags docker` on **vps** applied (`ok=34 changed=3 failed=0`), and on **nas** `--tags monitoring --skip-tags alloy` (`ok=34 changed=2 failed=0`) plus the HD-1093 SMB leg (`ok=40 changed=1 failed=0`) applied. The `tailscale-node` check-mode fix is committed (`dc398c67`). **No oldsrv leg had started.** vps came back (`traefik` 18 min, `tailscale-sidecar` 17 min, rest `Up 8 hours`); the sidecar still reports `1.102.5`, so the container-side tailscale tag move is still owed and it is the one act on that host that costs connectivity.
  **Rule learned, applies to every later lane:** on `vps`, any act that restarts the tailnet sidecar or Traefik goes LAST, and the tailnet path is re-proved before another host's leg starts. A vps edge act in the middle of a multi-host lane is how a window loses its own control channel.
- Finishers launched in the same worktrees from these measurements: `conv-vps` run d08dbed3 (wt-0120), `conv-nas-oldsrv` run 0a6daff5 (wt-0121).
- **Phase 4, second half (nas + oldsrv) landed.** oldsrv: docker family `5:29.9.2`/`2.4.2`/`0.38.1`/`5.6.1`, `alloy 1.21.2-1`, `tailscale 1.104.2`; 40 containers identical, `RestartCount` sum 0, same 8 holds, `match=8 differ=0`, all 5 hosts reporting. nas: SMB pair landed and proved over the wire (4 authenticated tree connects, cross-share denied, anonymous refused). Two IaC fixes came out of the legs: `check_mode: false` on the tailscale-node arch read **and** on the tailnet-IPv4 read (a not-yet-joined node is a state, not a failure) — without the second, `--check` died at the assert.
- **§11 fold-ins as measured:** HD-1122 — **no act existed** (`ai_tier_metrics_publish` has been true since `ed4cf4e2`; both llama.cpp legs are scraped and the panel expression already counts 3), the owed half is an authored `llamacpp:*` panel. HD-1175 — the read ran: boot -1 ended in a `crash` on 2026-10-20, `/sys/fs/pstore` empty, only `efi_pstore` backend, no ERST/ramoops/`memmap=`, no mcelog/EDAC ⇒ no cause available and the box is structurally un-instrumented for the next one (owner call: a crash recorder is a kernel-cmdline change + reboot window). HD-1088 — parked: register the `storage-push-music@oldsrv` key on the Box in the Hetzner console (port 23, key-auth-only), then `storage_push_music.enabled: true` + `--tags storage --limit oldsrv.kogler.si`.
- **HD-487 parked by ruling, not by failure:** the row says "owner-present", `--check` shows one change (`rm /etc/systemd/network/20-eno1.netdev`, no reload notified), and a network apply leg does not get pulled into the act that costs the control channel. Command in the row tail. **HD-436**: the guarded re-render is live (36/36 delta both directions); owed halves = `playbooks/dns.yml`, the `extra_records_path` swap, HD-435's `tailnet: dual`.
- **Row-loss catch at a rebase (the `comm -3` proof earning its keep).** Resolving the `todo.md` hunk between R1a and R1b mechanically dropped **three** rows (`HD-1166`, `HD-1175`, `HD-1182`) with no conflict left behind; the both-directions id-set diff against pre-merge `main` and the lane tip found it and the union was rebuilt (lane's HD-1166, main's HD-1175/HD-1182), then re-proven empty. The lesson is the one §Merge already states: a `todo.md` hunk is resolved by reading **both sides against the rows**, never by slicing lines.
- **Owner-visible counts, recorded not judged:** `headscale` `RestartCount=469` and `tailscale-sidecar` `RestartCount=461`, cumulative since creation, stable across four samples, last state change before the window - consistent with HD-1213's cascade. `/etc/systemd/network/` on vps also holds `wg-s2s.netdev.bak-1788367733`, `wg-s2s.netdev.bak2`, `wg-s2s.network.bak` outside the `netd_unit_namespace`, so HD-487's run will not remove them. `docs/services-vps.md`'s dangling-volume table's "what serves that path today" column now contradicts the box for the six onlyoffice rows (the named volumes serve them) - Phase 8 or the HD-1106 owner.
- **Unexplained, not caused by the window:** plain `https://csui.kogler.si/` answers 404 through the tailnet edge while `csui.ts.kogler.si` answers 200 and the app answers 200 on its own :3000; the two routers differ only by `authentik-forward-auth`, and the rendered `routes.yml`/`middlewares.yml` are dated 05:23 and were not rewritten - config-shaped, not recreate-shaped.
- **A disclosure that needs no rotation:** a lane read the WOPI discovery XML, which put a fragment of the **public** WOPI key (served unauthenticated at `office.kogler.si/hosting/discovery`) into its transcript. Not a vault value, nothing rotates.
