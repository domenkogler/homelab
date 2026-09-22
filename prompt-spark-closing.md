# `prompt-spark-closing.md` — close the HD-420 thread: read the delivery, finish the rows, retire the views

> **Role:** closing brief for the HD-420 / HD-377(b) / HD-345 / HD-395 thread. You are **the parent**
> for this close-out: the owner authorised the merge-and-cleanup sequence, so **you may write
> `prompt.md` and `todo-table.md`** — that exception is yours alone and it dies with this commit.
> **Read me + `spark-420-delivery.md` + `todo.md`; nothing else to start.**
> **Linked from:** [prompt.md](prompt.md) §4 · [`prompt-spark-external.md`](prompt-spark-external.md)

## 0. Open like this

```bash
cd /home/domen/source/homelab && git fetch --all --prune && git status --short && git log --oneline -3
git worktree list                       # know what is in flight BEFORE you touch anything
git branch --sort=-committerdate | head  # find the session/420-spark-* branch
```
Read the delivery from the external lane's branch (it committed there):
```bash
git show <external-branch>:spark-420-delivery.md      # or read it in its worktree
```
If the file is missing, look at `/home/domen/source/spark-420-delivery.md`, then say so and stop —
a close-out without the delivery is a guess.

## 1. Do not trust the delivery — spot-check it (5 minutes, all read-only)

Every claim below is checkable; a close-out that pastes unverified numbers into the SSOT is exactly
what the "a claim needs the implementation read, not a matched line" rule is about.

| Delivery claim | Check |
|---|---|
| J1 pre-flight PASS with numbers | re-read the sidecar: `ssh spark 'docker stats --no-stream …'` + the cgroup `memory.stat` anon |
| J2 converges `failed=0` | the logs it names exist and their `PLAY RECAP` matches what it pasted |
| J3 `count_over_time(…[1m])` = 12 | re-run the two queries against VM on the VPS (creds from `/etc/alloy/config.alloy`, lengths only, never printed) |
| J3 rows/s ≈ +9 not +125 | re-query `sum(rate(vm_rows_inserted_total[5m]))` — a ~10× delta means the cold `drop`s are not matching and the row is **not** done |
| J4 self-test | run `bash roles/spark/files/spark-oom-watchdog.sh self-test` yourself (it stubs `docker`); a self-test you did not run is not evidence |
| anything "PARKED" | verify it is genuinely blocked, not just unfinished |

Refuse the parts that fail: fix them yourself if they are in the monitoring/spark file set,
otherwise reopen the row with the exact blocked action.

## 2. Already true before the delivery (do not re-do, do not re-write)

Merged in `a30a0b4`+`dfdc723`+`2c9ed4e`+`a9ce3dc` (the `420-cadence` lane, merged 2026-09-22):
* **LIVE on the VPS:** the `prometheus` datasource `jsonData.timeInterval = "5s"` (idempotent task —
  converge #1 `changed=3`, converge #2 `changed=0` with the task `skipping`), the re-derived
  `homelab-llm.json` (**53 panels**, the three `DCGM_FI_PROF_*` panels deleted, six real DCGM
  signals + XID readiness), and `Cached Token Stats` on `rate()`.
* **Authored, awaiting the spark converge:** the hot/cold Alloy jobs (one Jinja matcher, `keep` hot
  / `drop` cold, spark-gated; vps/nas/pi render **byte-identical to HEAD**) and
  `DCGM_EXPORTER_INTERVAL: "5000"` (a coupled pair with the dcgm `scrape_interval`).
* **Findings already recorded in the docs** (do not re-add them): HD-345 is a LABEL fault not a walk
  fault; `--diff` is banned on the `monitoring` role for the same reason as `docker_services`; the
  VPS `config.alloy` + alert-rules had drifted from `main`; the brief's `config.alloy`/"R2 branch"
  and "14 vllm names" claims were stale; the `[5m]` gauge lives only on the retired
  `vllm-master-v2.json` and dies with HD-377(a); **HD-342's kopia tail is HD-191's work, not ours**
  (the VPS has a kopia server and no client).

## 3. The close-out, in order (this is §4 "Merge + cleanup" — you are the parent)

1. **Merge the external branch.** If `main` moved since it branched: `git rebase main` **inside its
   worktree**, re-run `bash scripts/validate-all.sh` there, then FF-merge into `main` from the
   primary and validate again. **Never a merge commit on `main`** (O1).
2. **Rows in `todo.md`** (CONVENTIONS §4(a) — a fully-done row is **deleted**, the record is the
   owning doc + the commit):
   * **HD-420** — delete if J1–J3 all passed and the acceptance reads 12/+9. If J3 failed, keep it
     with the exact remaining action, not a narrative.
   * **HD-395** — delete if J4's fix is deployed **and** the live baseline behaviour is proven;
     otherwise keep with the blocked action.
   * **HD-377** — stays: only (a), the owner's render/sign-off, remains. Its tail must read as one
     owner action, nothing else.
   * **HD-345** — stays until someone converges **oldsrv** and reads
       `up{job="alloy-snmp", instance="router"}`. If that converge happened in this thread, delete it.
   * **HD-342** — its kopia tail now names **HD-191**; the row stays for whatever else it still carries.
3. **Ledger (`deployment-tasks.md`)** — every `- [ ]` line whose work is finished becomes
   `- [x]` **with its date**; every closed row's line is deleted; no line may reference a row that
   is gone (`check_ledger_state.py` will fail you). Lines you own: HD-420, HD-377, HD-345, HD-395.
4. **Docs** — write the delivery's `## DOCS` after-numbers into `docs/observability.md`
   §Scrape cadence (its "State" block must say LIVE, with the measured numbers, not ⏳) and
   §LLM Dashboard / §Host sensors if the GPU row numbers changed. Docs are wished state: no dated
   diary, no "as executed" narrative.
5. **Views — the whole point of this brief.** Re-derive from the merged `todo.md`, never from
   prose:
   * `todo-table.md`: §B0 brief-index row for `prompt-420` → gone (brief dead); §B rows for
     HD-420 / HD-395 / HD-345 / HD-377 updated or removed; the §0 **registry size stays derived**
     (`grep -c` / `sort` on `todo.md`, never a typed number); §D Table Human gains **HD-377(a)** (the
     board sign-off) if it is not already there; the ⚠ watch-list gains — if not there already —
     *"`--diff` on `monitoring` is safe"* (it is not) and *"the SNMP panels are empty because SNMP
     is off"* (the labels were the fault).
   * `prompt.md`: §2 — the **HD-420** bullet becomes a closed pointer (the answer + where the
     numbers live) or is deleted if the row is gone; the **HD-395**, **HD-345**, **HD-377** bullets
     updated to their real remaining tail; §4 wave table — drop the `prompt-420` row and the two
     `prompt-spark-*` briefs from it. Keep `check_todo_done.py` happy: every open/done claim in
     `prompt.md` must match a live/absent `todo.md` row.
6. **Brief deaths in ONE commit (O7):** `git rm prompt-420.md prompt-spark-external.md
   prompt-spark-closing.md` **together with** every link to them in `prompt.md`, `todo.md` and
   `todo-table.md`. A dangling link from those three files fails the gate; a link between briefs is
   not checked at all — so grep for all three names before you commit:
   `grep -rn "prompt-420\|prompt-spark-external\|prompt-spark-closing" *.md docs/*.md`
7. **Delivery file dies too:** `git rm spark-420-delivery.md` in the same cleanup commit — it is a
   handoff artefact, not a durable doc; its durable content is now in the owning doc + the rows.
8. **Runbook:** `deployment-manual.md` gains an imperative line **only** if a hand-repeatable step
   was actually performed and is not already covered. The converged-VPS procedure and the VM query
   recipe already live in `docs/observability.md` §Scrape cadence and `scripts/README.md`, so the
   expected answer is "untouched". Justify it in the commit message if you leave it alone.
9. **Make the cleanup commit in YOUR OWN worktree/branch (O5)** — `guard-session.sh` refuses edits
   while the primary sits on `main`, and `validate-all.sh` hard-fails on primary+main+dirty. Then
   FF-merge it, validate, `git push`.
10. **Sweep (O8):** `git worktree remove` each finished lane worktree **by name**, `git worktree
    prune`, `git branch -d` the lane branches — **never `-D`, never remove a worktree you did not
    create**. Prove it: primary on `main`, `git status` empty, `git worktree list` shows one entry,
    `bash scripts/validate-all.sh` green.
11. **Report:** rows deleted, rows kept (with the exact blocked action), the owner's remaining
    hands, and every row still without a brief.

## 4. Things in the station that are NOT yours

* `/home/domen/source/homelab-wt-20260922-ha416` on `session/hd416-host-rule-whitespace` appeared
  during the 420 lane, off the parent-created naming convention and carrying a **prompt-407** row
  (HD-416). **Do not delete or rebase it** (O8) — report it to the owner.
* The **oldsrv** converge slot: HD-345's relabel and HD-386's `failed=0` sighting both wait on it.
  Whoever holds it converges `home_servers.yml --limit oldsrv.kogler.si --tags monitoring`.
* `main` may still be **ahead of `origin/main`** — the lane merges were not all pushed. `git push`
  is part of step 9.
