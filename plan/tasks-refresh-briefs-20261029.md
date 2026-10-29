# tasks-refresh-briefs-20261029 — execution state of the brief-refresh run

> **Role:** the parent's work package for [`prompt-refresh.md`](../prompt-refresh.md) — the author-only pass that
> brings the `prompt-*.md` family back in line with `todo.md` after the pin window falsified its cells. It carries
> §A the rules every child reads INSTEAD of receiving them in its launch text, **and the per-file evidence table**
> (which cell is stale, what it must say, and the row or commit that made it stale), §B the launch template, §C the
> per-task state, §D the report format, §E the merge log. Execution state for work that already has owners —
> never a second backlog.
> **Linked from:** [prompt-refresh.md](../prompt-refresh.md) (the runbook; it outranks this file on any fact),
> [todo.md](../todo.md) (the rows, which no lane edits in this run).
> **Writer:** the orchestrator only (O2). A lane never edits this file — it reports, the parent writes.
> **Death:** deleted in the commit that closes the run's last act (Phase 4), the same commit that deletes
> `prompt-refresh.md`.

## 0. The sitting

Seat: **WSL Debian, laptop** (`DomenP14s`), `provider=spark`, `seat-llm-path.sh --check` → **`path=lan`**.
Station `/home/domen/source/homelab` at `fe3cd5c1`, clean, `validate-all.sh` green. Child runtime **effective**
(not merely authored): `asyncByDefault: true`, `timeoutMs: 7200000`, `globalConcurrencyLimit: 2`,
`checkpointBeforeDeadlineMs: 600000`.

**A sibling session's lane is unmerged here** — `session/20261029-hd435` @ `94bbcdde`, worktree
`../homelab-wt-20261029-2232`, touching `prompt-dns-transport.md` + `todo.md` + `todo-table.md` + the network docs.
It is not this run's to remove (O8), and it is the sole reason `prompt-dns-transport.md` is out of scope.

Rulings for this sitting (the owner's, in-session 2026-10-29):

| # | Ruling |
|---|---|
| F1 | **author-only**: no converge, no host act, no secret act, in this run or in any lane |
| F2 | the two lanes are **stopped** at the end of the launching session and the next session takes the worktrees over — they are left in place, clean, no commit |
| F3 | `prompt-dns-transport.md` waits for `session/20261029-hd435` to land (Phase 3), rather than putting two writers on one brief |
| F4 | lanes touch **no** registry file — not `todo.md`, not `todo-table.md`, not `prompt.md`, not `plan/` |

## A. Rules — READ THIS INSTEAD OF BEING TOLD TWICE

Repo root `/home/domen/source/homelab` is the **merge station — never edit it**. You work only in the worktree your
launch names, on your branch. Ritual first: `grep -n "^#\|^## \|^### " CONVENTIONS.md | head -40`, then
`CONVENTIONS.md` §4/§6/§6.4, then [`docs/orchestration.md`](../docs/orchestration.md) §4 (O1–O11).

1. **Edit only the files your launch lists**, in your worktree. ⛔ Not `todo.md`, not `todo-table.md`, not
   `prompt.md`, not `prompt-update.md`, not `plan/` (the parent owns the views — O2). A lane that touches a view
   hands the parent a red gate instead of a fix.
2. ⛔ Do **not** change the `Rows it carries` id list in a brief's dispatch header. That triple
   (`todo-table.md` §B0 ↔ brief header ↔ `prompt.md`) is held equal by
   `python3 scripts/gate/check_brief_coverage.py`; moving it in a lane reddens the run.
3. **`todo.md` is the authority and it is current.** For each row your brief dispatches: read the row, read the
   brief's cell, keep what the row still asks. Where the evidence table below and the tree disagree, **the tree
   wins** — say so in your report and leave the brief matching the tree.
4. **No session narrative** (CONVENTIONS §6/§6.4): no "this session found", no dated results, no changelog — a
   sentence that reports an event belongs to the commit message. Dates stay where the date IS state
   (`live-verified`, expiry, pin date). ⛔ No typed count a command can print — print the command.
5. ⛔ No dated record under `spark/reports/hd*/`, nothing under `reports/`, no `*-generated.md`, no IaC, no secret.
   The **card** (`spark/reports/external-window-card.md`) is a dispatcher page, in scope; a dated result is not.
6. Where the truth is "this waits for a person", write the **exact** blocked action into the brief cell and say
   `PARKED` (O4). Do not invent work around an owner gate, and do not stall.
7. Commit after **each** deliverable, before starting the next; plain `git commit` (signing retired, never `-s`).
   2 h deadline — checkpoint and report rather than being cut off; a killed lane that committed nothing is lost.
8. No new `HD-` id. No view reseal (a size reminder a lane prints is the parent's to clear).
9. Leave no residue: no uncommitted tree, no `ssh -N/-L/-D` you opened, no listener. Exit check before reporting:
   `git status --porcelain` · `ps -eo args | grep -E 'ssh .*(-N|-L|-D)'` · `ss -ltn`.
10. Then **stop**. The merge, the views and this package's bookkeeping belong to the parent.

### What made the staleness (state it once, correctly)

The fleet pin window ([`prompt-update.md`](../prompt-update.md)) ran 2026-10-28/29 from this station under rulings
N1–N7 / S1–S10. Phases 1–4 landed (the pin commit, the rotations, and the `pi`/`vps`/`nas`/`oldsrv` converges);
**Phase 5 (router/switch) and Phase 6 (spark) did not run**; Phases 7–8 are owed. Consequences a brief must carry:
four Debian hosts are at the NEW pins while spark publishes the new pin map over old packages (six `differ` rows =
the parked Phase-6 apply, not drift); most exposed secrets are already rotated; `spark-llm_api` +
`litellm-engine_api` are **not** (they close in Phase 6, never in a spark-served session); no router/switch act ran;
the Pi's fold-ins landed none of their acts. Execution state:
[`tasks-update-window-20261028.md`](tasks-update-window-20261028.md) §C/§E/§F/§H and
[`prompt-update.md`](../prompt-update.md) §1 + §11.

### Deliberately OUT of this run

- `prompt-dns-transport.md` — the sibling lane named in §0 holds it (F3). If a DNS/answer-plane fact sits inside
  one of YOUR files, correct your file and report the cross-reference; do not open the dns brief.
- `prompt.md`, `todo-table.md`, `prompt-update.md`, `plan/` — the parent's.
- `prompt-external.md`, `prompt-secrets.md`, `prompt-laptop-wsl.md`, `prompt-laptop-legs.md`,
  `prompt-edge-identity.md`, `prompt-litellm-consumers.md` — the parent checked them current for this run;
  Phase 3 of the runbook re-verifies them.

## B. Launch template (the parent fills `<…>`; keep it under ~25 lines)

```
Lane <A|B> of an AUTHOR-ONLY brief refresh. Worktree <abs path>, branch <branch>, forked at <sha>.
READ FIRST: plan/tasks-refresh-briefs-20261029.md §A + the evidence table (they ARE the rules),
then docs/orchestration.md §4 (O1–O11).
SITTING CONSTRAINTS: no converge, no host act, no secret act (F1); main is <sha>; this seat reads
provider=spark and path=lan.
FILES YOU OWN: <disjoint list>   (nothing else; a file you must touch but do not own: report it)
TASK: correct the stale cells to what todo.md says — verify every claim in the table against the row itself.
⛔ no todo.md / todo-table.md / prompt*.md / plan/ edits (F4); ⛔ no header row-id changes; commit per file.
```

Then `async: true`, `agent: worker`, `cwd: <worktree>`, `options: {checkpointBeforeDeadlineMs: 600000}`.

## C. Work packages

State: `[ ]` open · `[~]` in flight · `[!]` partial (resume sha) · `[?]` parked · `[=]` absorbed · `[X]` done.

| id | deliverable | writes (disjoint) | hosts | state |
|---|---|---|---|---|
| A | correct `prompt-observability-alerting.md`, `prompt-storage-backup.md`, `prompt-spark-llm.md`, `spark/reports/external-window-card.md` | those four files | none (author-only) | `[ ]` — children launched 2026-10-29 22:15, **stopped 22:32 by the owner**, wrote nothing; worktree `../homelab-wt-20261029-2309` clean at `fe3cd5c1`, branch `session/briefs-net-obsv-stor-20261029-2309` is empty — **take the worktree, do not recreate it** |
| B | correct `prompt-smart-home.md`, `prompt-media-arrs.md`, `prompt-seat-cockpit-grants.md`, `prompt-scripts.md` | those four files | none (package + `prompt.md` + `todo-table.md` are the parent's) | `[ ]` — same: stopped at 22:32, wrote nothing; worktree `../homelab-wt-20261029-2310` clean, branch `session/briefs-home-media-seat-20261029-2309` |
| P | the runbook + this package + the `prompt.md` dependency ladder | `prompt-refresh.md`, `plan/tasks-refresh-briefs-20261029.md`, `prompt.md` | — | `[X]` landed by the launching session in `../homelab-wt-parent-20261029-2309` (`session/handoff-runorder-20261029-2309`) |

## D. Evidence table — per file, what to correct (verify each against the row before editing)

### `prompt-observability-alerting.md`
- Acceptance line still says the host's running Alloy `== 1.20.1-1`. The fleet moved to the `alloy_version` pin
  (`1.21.2-1`) in Phase 4. Per the window's pin-quote sweep, name the **var**, not the number.
- HD-1122: the brief asks for the `--metrics` flag + a flip. Measured state (`prompt-update.md` §11 oldsrv):
  **no flip is owed** — `ai_tier_metrics_publish` is already `true` and both llama.cpp legs are scraped; what is
  owed is an authored `llamacpp:*` panel on `homelab-llm` via `scripts/ansible/build-llm-dashboard.py`.
- HD-1166: `prompt-update.md` §11 says the page is **closed on the box** (one `--tags monitoring`, no UI mute);
  what remains is the owner-present VPS converge that applies the retired target/rule.
- HD-1120's spark `--accesslog` hunk and HD-1121/HD-1122's oldsrv legs: state that they must land in a **clean**
  window — never inside a spark bench window — and that the spark-slot half rides Phase 6 or a window after it.
- HD-1182/HD-14: HA has **no firing liveness rule** while the `ha_exporter` job is gated; the `ha_api`
  long-lived-token prune is an owner leg (park with the exact action).

### `prompt-storage-backup.md`
- HD-1106: RULED, and the two `onlyoffice-docs` paths sit in **named volumes now** — that fix was applied
  **before** the VPS `docker` converge (`prompt-update.md` §11 vps), so the WOPI/JWT keypair survives the
  recreate and the owed act is the prune itself, one `docker volume rm` per row the table marks `prune`.
- HD-191: **the VPS still has no backup client** — no binary, no client config, no `kopia-agent` entry — and the
  shape is now ruled in `docs/backup.md` §VPS-side backup client. Price it first (`du -sh` over `/opt`, the
  `db-backup` dump volume, `/srv/docker/*`, plus one throwaway snapshot of one small state dir), write the sizes
  back to the doc BEFORE authoring an include list, and its converge rides the pin window's **VPS leg, LAST**
  (the sidecar/Traefik reason). `db-backup` stays the Postgres restore path.
- HD-1105: all three enabled-but-dead nas units are ruled and `--failed` lists 0 — state the ruling, keep the
  `systemctl list-units --failed` acceptance, drop the "decide per unit" framing.
- HD-1174: keep the scrub-then-rotate-with-agent-reconnected order, and add the measured fact that
  `kopia-server_fingerprint`'s current value is a TLS **cert fingerprint**, so its ledger line stays even after
  the cert moves (that is a named debt, not a reopened rotation).
- If `docs/backup.md` carries the kopia-server **loopback-only SAN** trap and the owed template assert, name the
  assert as owed on a kopia converge leg (it needs a converge to prove, so it is not a quiet fix).

### `prompt-spark-llm.md`
- HD-494 now has a ruling (just landed in `prompt.md` §2 item 1): the **delta picks the floor** (CRIT vs WARN),
  so the number is taken before anything lands in IaC, and the measurement rides the pin window's spark phase
  (`usable-sampler.sh` in that boot window, externally served — it refuses a spark-served seat on its first line).
- HD-1206: the artifact is built + pinned + fp8-capable, so what is owed is the **owner window in this order**:
  A+ runtime dispatch check → `fast-v32-bf16` → gates 0–7 → `fast8` → dtype gates 8–9. Say plainly that the
  post-build CPU gates assert day-0 bytes and certify nothing on v32 (HD-1210), and that rollback is one
  `-e spark_llm_profile=fast` plus a detached converge.

### `spark/reports/external-window-card.md` (the dispatcher page only — no dated record)
- Title says "one ordered run over **eight** rows"; `prompt-spark-llm.md` now carries sixteen ids — the v32 arms
  (HD-1206 · HD-1214 · HD-1215 · HD-1220 · HD-1221 · HD-1222) and HD-359/HD-367 arrived after the page was written.
- §6 states a sampler is running. Measured 2026-10-29: `metrics-window.sh --status` prints `sampler: not running`,
  `no rows yet`. Restate it as state, not as a live claim, and keep the parent-only start-line rule.
- The HD-469 leg still says it waits on a flip to `reasoning`. Reconcile with HD-1206's Phase-6 order: the flips
  in the next window are the v32 arms, so group the legs one-profile-per-boot-window around THAT order and keep
  the page's own "Authority: none" line and its reads-first rule.
- ⛔ do not touch any `spark/reports/hd*/` dated record.

### `prompt-smart-home.md`
- HD-418: reconciled at **both** ends and owned in IaC (`roles/home_assistant/tasks/pi.yml`, tag `hd418`); the
  proof is BEHAVIOUR (the `.storage/http` object HA enforces), not the YAML; the standby-shaped case has **no
  subject** while HD-1109 stands. The brief's "PARKED — the Pi is not reachable from this seat" and its
  "correct the sentence in `traefik-internal/dynamic/routes.yml.j2`" are both stale.
- HD-1101: fixed AND applied on both hosts. On a keyfile host the write leg is **`nm-pi`**; `--tags nm-resolver`
  selects the guard, proves the check, and writes nothing. ⛔ do not re-run the applies.
- HD-1103: the choice is **decided** — `rotate 1` + `maxsize` in a NEW role-owned logrotate file sized against
  `size=100m` (the repo owned no logrotate config before it); the fstab `mode=0755` becomes true on the mount at
  the **next boot**, never from a converge and never via `mount -o remount`; the smartd park is the `ai_diag`
  **derived** mask applied by an UNTAGGED converge — a hand-disabled unit is the defect.
- HD-1167: first act is the stripped `grep -v '^#'` comparison both sides; the fix belongs in `roles/network`,
  never on the host; the one-time re-render is an owner-window act with HD-1101's rollback standing by.
- HD-1109: the standby is **UNDEPLOYED**, not cold-deployed; probe with `docker compose -f
  /opt/home-assistant-standby/docker-compose.yml ps`, NEVER `systemctl is-active keepalived` (its `inactive` is
  correct), and on the host that owns the unit.
- The one Pi window now carries: the boot that makes the fstab `mode=` true, the UNTAGGED `ai_diag` leg, and
  HD-1167's re-render — and `access_admit_extra` still lists `admin` in `host_vars/pi.kogler.si.yml`, so HD-443's
  Pi revoke rides that same visit. ⛔ the `nm-resolver` applies and HD-418's reconcile are DONE.

### `prompt-media-arrs.md`
- HD-1091: `lidarr_api` is **rotated** (window commit `b951e9c9`) in the row's forced order — mint → Lidarr's
  `config.xml` → restart → soularr `config.ini` → SeerrNG — with its three holders re-taught, and
  `soulseek_api`/`soulseek-internal_api`/`qbittorrent_api` moved with the render as the far end. What the row owes
  is **one album crossed end-to-end** (needs a peer to finish one inside the poll window). Do not restate the
  rotation as owed.
- The two media web-auth users and `jellyfin-seer_api` are **parked on the owner with no machine path** — that
  Jellyfin answers 403 on `POST /Users/<id>/Password` and has no ApiKeys endpoint at all, that Radarr build has
  no user store, and `admin @radarr.kogler.si` carries the **same** value as `admin @media.kogler.si`, so it is
  one UI change plus both vault writes and the two Seerr keys move with it. The issuer/holder map is in
  `docs/services-media.md` §Credential rotation — point at it, do not restate it.
- HD-1088: the single blocked action is registering oldsrv's key (`storage-push-music@oldsrv`) on the live Box in
  the **Hetzner console** (port 23, key-auth-only, no other way in); then `storage_push_music.enabled: true`, a
  `--tags storage --limit oldsrv.kogler.si` converge, one `systemctl start push-music.service`. Keep the
  `--max-delete` = CAP-not-abort warning.
- HD-1092: void as written — the Authentik→NAS glue is gone from BOTH sides and the family list is
  `storage_samba_users`; what remains is one credential-bearing leg on a second host, parked. Install nothing on
  the NAS from this brief.
- ⛔ probe slskd with `docker exec slskd /slskd/slskd --envars`, never by grepping a rendered compose; the
  Soulseek **network** login is not rotatable from a seat and stays a ledger debt — do not re-open it.

### `prompt-seat-cockpit-grants.md`
- HD-443: RULED — revoke the Pi's `admin` on the **neutralized** state, because a `Storage=volatile` journal
  cannot prove a 30-day silence. The brief's "read the journal and revoke when it reads 0" is superseded; the
  seat-side `laptop-domen_ssh.pub` → `domen_ssh.pub` move and the `IdentityFile` repoint are landed on both
  laptop seats; the vault item is titled `domen_ssh` and the matcher reads key BYTES, not file names. The Pi half
  waits the Pi window (`access_admit_extra` still lists `admin`).
- HD-1110: the seat legs run FROM their own seat (oldsrv included); the OAuth-vs-`api_key` call is ruled —
  **`api_key` is the fleet spelling**, a seat's OAuth entry is drift and is never cured by overwriting a live login.
- HD-1180: the per-seat verdicts and the one act left per seat are in `prompt.md` §1's table — the pin records an
  observation and moves no seat, so the plane is never reported restored from the pin alone.
- HD-495 / HD-1126 / HD-1161 / HD-465 / HD-361 / HD-442: verify each cell against its row and against
  `prompt.md` §2 item 5 + §1; ⛔ never re-add `git commit -s`; a raw journal grep for a phrase also matches the
  probe that greps for it — filter on `sshd-session[…]` / `-u ssh.service`.

### `prompt-scripts.md`
- Replace the typed verdicts in the Status block (`120 linked rows`, `88 docs, 10 domains`) with the commands that
  print them (`check_registry_prose.py --show`, `check_doc_domain.py`) — the brief's own rule.
- The `scripts/` tree, the harness split, the domain checker and the prose sweep are **landed** — that belongs in
  the docs and git, not in the brief; shrink those paragraphs to the fact + the checker that holds it.
- Keep live: HD-1118's two seat legs (run FROM the seat) + its **parked** from-zero leg, HD-1125's caller sweep
  (callers must name an `IdentityFile` BEFORE any default-path key is renamed), HD-1138's bare-`ssh <name>`
  consumers. Nothing else in this brief moves a file.


## E. Report format (a lane's whole deliverable), and the merge log

A lane closes with evidence, never prose: `git log --oneline main..HEAD` + `git show --stat` per commit; one row per
file — **what was stale → what it says now → the row or commit that made it stale**; anything stale that the
evidence table did not name (that is the point of the run); anything the table claims that the tree contradicts
(name the contradiction, leave the brief matching the tree); `bash scripts/validate-all.sh; rc=$?` **in the lane
worktree** plus the failure list; then the three-command exit check. The only acceptable red is a live-value leak
debt already on record (`wifi-kogler*`, `spark-llm_api`/`litellm-engine_api`, `pppoe_login`/Soulseek,
`jellyfin-seer_api`) — name it, never "fix" it, and never delete a transcript. Then stop: no merge, no push, no
view edit.

**Merge log (parent):** station `fe3cd5c1`; the fan-out ran 22:15→22:32 and was **stopped by the owner** with both
lane worktrees clean and no commit, so nothing landed from Phases 1–2; both lane worktrees and both empty branches
are left in place for the next session to take (§0, §C). `../homelab-wt-20261029-2232` is a **sibling's** — never
remove it (O8).

### Acceptance (every child, same shape)

- `git log --oneline main..HEAD` + `git show --stat` per commit;
- one row per file: what was stale → what it says now → the **row or commit** that made it stale;
- anything you found stale that is NOT in my table: name it and fix it (that is the point of the run);
  anything in my table the tree contradicts: name the contradiction and leave the brief matching the tree;
- `bash scripts/validate-all.sh; rc=$?` in YOUR worktree, plus the named failure list. The only acceptable red is
  a live-value leak debt already on record (`wifi-kogler*`, `spark-llm_api`/`litellm-engine_api`,
  `pppoe_login`/Soulseek, `jellyfin-seer_api`) — name it, never "fix" it, and never delete a transcript;
- the three-command exit check;
- then **stop**. Do not merge, do not push, do not touch the views.
