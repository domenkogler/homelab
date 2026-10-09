> **Role:** one-time work plan — replace the eight `prompt-<HD>.md` lane briefs with ten **domain** briefs,
> add the context-budget rule the current rulebook lacks, and retire the laptop's LM Studio agent leg.
> It is a **dispatch plan for several sessions**, not a lane brief: no HD row is owned here, nothing is
> executed from it beyond the phase it names.
> **Linked from:** [prompt.md](prompt.md) §2 · [todo-table.md](todo-table.md) §B0
> **Status:** active from P0; **delete this file in P4's cleanup commit** (the last phase that needs it).

**Plan pinned at:** `main` = `2d1c107d` (2026-10-08 22:47). Every phase re-derives the HD ids at its own
`HEAD` before writing — ids **moved under this plan** (see §1), so an id typed from memory is a defect.

---

## 0. Why this rework exists (three findings, measured 2026-10-08)

1. **The briefs are grouped by the first HD that was minted in the lane, not by the context the work
   needs.** `prompt-357.md` is the family-surface lane; `prompt-376.md`/`prompt-llm.md`/`prompt-remaining-bench.md`
   are three briefs for **one** converge slot, which per O3 can never run in parallel. The naming tells a
   session nothing about which domain it is entering, and three of the eight had drifted into
   contradicting their own rows.
2. **Nothing in the rulebook bounds concurrency by context.** O3 caps *converge slots*, not sessions, so a
   parent could legitimately launch eight lanes; each full lane session needs the §0/§1 boot ritual
   (~60 k tokens of `todo.md` alone). The owner's budget is **≤ 8 sessions, but only 2–4 full contexts**.
3. **The laptop's third serving leg is dead in practice.** Prefill on LM Studio here is minutes per prompt
   (measured: 20 816 tokens → 359 / 899 / 277 s across three loads), so no real agent work is possible on
   it. What works is FIM and vision — so the agent-leg rows are retired, not deferred.

---

## 1. State at planning time — what `main` did while this was being planned

Twelve merges landed in ~1 h (`aa89d54f` → `2d1c107d`). What changes about the plan:

| Change | Consequence for the rework |
|---|---|
| **`85a1b3fc` renumbered rows HD-1093…1096 → HD-1110…1113** (a collision with the live SMB/alloy rows) | An id is **not** stable prose. Phases P2/P3 write row lists only from their own `HEAD`, and P4 re-checks every id before the switch. Do not copy an id list from this file into a brief without re-deriving it |
| **PG 16→18 legs 1 + 2 are done** (`litellm-db`, `authentik-postgres`); the `PGDATA` pin replaced the version-conditional bind target (`efd111c0`) | `prompt-384.md`'s "measured, do not re-derive" list cites LiteLLM **v1.83.10** while the fleet pin is **v1.104.0** (`versions.yml:227`, bumped by `c959a7b8`) — the spark/litellm briefs must be re-grounded, not just renamed |
| **`291b504e` put the corrected `hygiene-collector-stale` rule live**; HD-450's converge tail closed | The observability brief's tail is now three items, not four |
| **A whole new domain landed: the pi.dev seat plane** (`scripts/pi-seat-sync.sh`, `pi-settings-config.sh`, `pi-tui-config.sh`, `install-nerd-font.*`, `RETIRED` list in `sync-extensions.sh`; rows HD-1110…1113; root `update_pi.cmd` deleted) | Goes to the **seat** brief (it is the same host and the same files: `pi-agent/**`, `scripts/install-pi-*`, `docs/pi-harness.md` §1/§5/§5a). It also means **P1 and a live seat lane both edit `scripts/pi-config/`** — see the hazard in §5 |
| **`b0816936` deleted four zero-byte junk files `git add -A` had swept in**; `validate-all.sh` grew to **item 30** (`check_yaml_dup_keys.py`) | Numbered gate items are cited in prose elsewhere (`todo.md` HD-1085 names "item 29" for the tmux gate — right today, brittle by construction), so the new briefs name a gate, never number it |

**The structural consequence:** `todo.md` (130 open rows) and `prompt.md` are **hot files right now** — every
live lane writes its own rows, and the orchestrator alone writes the views. Therefore the rework must do all
its `todo.md`/`todo-table.md`/`prompt.md` surgery **last, in one session** (P4), and every earlier phase must
be able to finish while those views move underneath it.

---

## 2. Target end-state (agreed 2026-10-08)

Ten briefs, named for the **host + domain**, keeping the `prompt-` prefix on purpose: `check_doc_map.py`,
`check_doc_ips.py`, `check_placeholders.py` and `check_vault_name.py` all skip `prompt-*`, so a `lanes/`
directory would pull the briefs into four fail-closed linters for no benefit.

| New brief | Domain / slot | Rows it carries |
|---|---|---|
| `prompt-spark-llm.md` | the GB10 engine + profiles + bench evidence (spark slot) | 469 · 473 · 475 · 489 · 494 · 376 · 400 · 359 · 367 · 380 |
| `prompt-dns-transport.md` | answer plane + DNS policy + VPS v6 (oldsrv/VPS/router) | 436 · 435 · 480 · 481 · 482 · 483 · 477 · 488 · 487 · 460 · 448 · 461 · 1095 · 1097 |
| `prompt-media-arrs.md` | media, music ladder, subtitles, downloads (oldsrv) | 362 · 1088 · 1090 · 1091 · 1092 · 1096 · 353 · 354 · 230 |
| `prompt-litellm-consumers.md` | scoped keys, the thinking control, voice, n8n, `/ui` | 384 · 403 · 387 · 373 · 249 |
| `prompt-smart-home.md` | HA primary/standby, KNX, failover, the Pi's box hygiene | 04 · 418 · 434 · 438 · 439 · 319 · 1109 · 1103 · 1101 · 17 · 217 |
| `prompt-edge-identity.md` | SSO tails, Matrix, zipline, published names (VPS) | 147 · 457 · 458 · 459 · 112 · 47 |
| `prompt-seat-cockpit-grants.md` | cockpit, the coding seat, grants, signing, **the seat plane** | 361 · 442 · 443 · 465 · 444 · 411 · 495 · 1085 · **1110–1113** |
| `prompt-observability-alerting.md` | silent-failure rules, Matrix alerting, boards | 450 · 1108 · 342 · 344 · 315 · 343 · 377 · 1094 |
| `prompt-storage-backup.md` | nas/ZFS/NUT units, Kopia, DR | 06 · 207 · 1105 · 1106 · 1107 · 191 · 238 · 1093 |
| `prompt-laptop-legs.md` | Win11 seat: **FIM + vision only** | 474 · 476 |

**Deliberately brief-less** (the §B0 "unbriefed" concept is still legal work): **1100** (PG 16→18 — owner-paced,
one leg per window, and it spans every host so no single domain owns it), 32 · 57 · 133 · 412 · 421 · 459 · 461 ·
472 · 474-tail. If that list keeps growing, P4 (or any later view edit) may promote an **11th brief**
(`prompt-platform-upgrades.md` = 1100 + the apt-hold wave + 1094) — adding a brief is a view edit, not a
contract change, so do not treat the roster of ten as sacred.

**The rule that makes the roster usable (O9, drafted in P0, verbatim target):**

> **O9 — context budget.** Sessions are cheap, **contexts are not**. A run may have at most **8 concurrent
> agent sessions** and at most **2 full-context sessions — the orchestrator counts as one**. The default shape
> is therefore *orchestrator + one lane*; a **third** is allowed only when the other two are near done, and
> **4 is the ceiling, never exceeded**. Anything beyond that must be a **narrow-context child** (a bounded
> single-deliverable subagent with its own fresh, small context — README §4 "Orchestrator + reviewer
> discipline") and never a second full lane wearing a brief. The brief pool is a **dispatch queue, not a
> parallelism licence**: rows queued behind an occupied host slot (O3) are waiting, not missing.

---

## 3. Phases

Six phases, sized for **250 k-token sessions**. Each phase is one session; ⫫ marks the two that may overlap.

| Ph | Goal | Write set (exclusive) | Exit gate | Depends on |
|---|---|---|---|---|
| **P0** | The rulebook: O9, brief-naming rule, the dead `prompt.md §3` pointers | `docs/orchestration.md`, `CONVENTIONS.md`, `README.md` | `validate-all.sh` green | — |
| **P1** ⫫ | Retire the laptop **agent** leg; pin FIM 8k / vision 32768; close the rows | `docs/hardware-workstation.md`, `docs/services-ai.md` (#28), `docs/services-ai-rejected.md`, `scripts/laptop-llm.py`, `scripts/laptop-llm/profiles.yml`, `scripts/pi-config/models-spec.yml`, `todo.md` **rows 474/476/486 only** | `laptop-llm.py gate --self-test` 13/13 + `probe-client` + `validate-all.sh` | — |
| **P2** ⫫ | Draft 5 briefs (spark, dns-transport, media-arrs, litellm-consumers, smart-home) | the 5 new `prompt-*.md` files **only** | each brief passes a self-check list (below); old briefs **stay put** | P0 |
| **P3** ⫫ | Draft 5 briefs (edge-identity, seat-cockpit-grants, observability-alerting, storage-backup, laptop-legs) | the other 5 new files **only** | same | P0, P1 (for `prompt-laptop-legs.md`) |
| **P4** | **The switch.** Delete the 8 old briefs, re-point every inbound ref, rewrite `todo-table.md` §B0 into the row→brief index, rewrite `prompt.md` §2, fix the phantom ids | `todo.md` (link hunks), `todo-table.md`, `prompt.md`, `README.md`, `docs/*` link hunks, `scripts/{laptop-llm.py,spark-fp8-image-probe.py}` prose, 4 evidence files, `git rm` × 8, delete `prompt-tasks-rework.md` | `check_doc_path_refs.py` green **is** the proof of the switch; then full `validate-all.sh` | P0+P1+P2+P3 merged |
| **P5** | The missing gate: every `HD-xxxx` named in any `prompt*.md` must exist as a `todo.md` row | `scripts/check_todo_done.py`, `scripts/validate-all.sh`, `scripts/README.md` | new check + its `--self-test` (must breed a red) | P4 (it would be red before: `prompt-361.md` names the deleted **445/446**) |

**Two-context schedule** (P0 → then P2∥P3 → then P4 → then P5): 4 sessions, of which only ever 2 are live.
P1 may run beside P2/P3 because its write set is disjoint from the brief files — but it must **not** run
beside a live pi-seat lane (see §5). P4 runs alone, always: it is a view rewrite and O2 makes views
orchestrator-only.

**Context math that sets the phase sizes** (`bytes / ~3.6 ≈ tokens`):

| Read | ≈ tok |
|---|---|
| `todo.md` read whole | **60 k** ← the thing that kills sessions |
| `todo-table.md` whole | 35 k |
| all 8 old briefs | 20 k |
| `CONVENTIONS.md` | 11 k |
| `docs/orchestration.md` | 4 k |
| one owning doc (typical) | 5–12 k |
| `docs/*.md` total | ~500 k — **never** bulk-read |

So: **no phase reads `todo.md` whole.** Extract with
`grep -n "^| HD-<id> " todo.md` → `sed -n '<a>,<b>p'`, one row per read, and open the *cited sections* of the
owning docs. A brief-drafting phase should land at **80–140 k used**, leaving room for the writing itself.

---

## 4. What each phase actually changes

### P0 — contract, before anyone drafts (1 session, ~50 k)

- [ ] `docs/orchestration.md` §4: add **O9** (§2 above) to the override table; fix the opening line
      "Read this first if you were launched from a `prompt-<HD>.md` brief" → `prompt-<domain>.md`;
      fix "The live lane map (waves) … lives in **prompt.md §3**" → `todo-table.md` §B0 (prompt.md has no §3);
      O7's brief-deletion wording stays true but must say *domain* briefs.
- [ ] `CONVENTIONS.md` §6 (brief row) + §4: briefs are named for **domain/host**, never an HD; a brief names
      its rows **as of its worktree's commit**; ids are re-derived, never copied.
- [ ] `README.md`: §2's handoff-family note (the `prompt.md §3 wave table` claim and the retired-brief
      archaeology), and the `State of the world (as of 2026-09-08)` banner — restate to "as of the rows;
      check `deployment-tasks.md`", since the phase prose there is a month old.
- [ ] Do **not** touch `todo.md` / `todo-table.md` / `prompt.md` in this phase (they are hot; P4 owns them).

### P1 — the laptop legs, decided not deferred (1 session, ~120 k)

Owner ruling 2026-10-08, to be written **once** into the owning doc + the decision log, then reflected in the
tools, then in the rows:

- [ ] **LM Studio serves FIM and vision only.** The **agent** leg is retired — the `agent-gemma-26b` profile
      leaves the catalogue, `client_context_window: 150016` is deleted, and the agent slot does **not** fall
      back to spark: the laptop's provider entry stops offering an agent model (spark is reached by the
      harness directly, per decision #26, not through this runtime).
- [ ] Windows: **FIM 8 192 / vision 32 768** — in `scripts/laptop-llm/profiles.yml` (`-c`) and
      `scripts/pi-config/models-spec.yml` (`contextWindow`) in the **same commit** (`probe-client` fails on
      drift; the row says why).
- [ ] `scripts/laptop-llm.py`: the agent-leg profile's gate/probe paths go with the profile — do not leave a
      gate asserting a leg that no longer exists (the 13-canary count and item 23/24 of `validate-all.sh`
      must agree with what is left; re-run both, do not edit the assert to pass).
- [ ] Rows: **delete HD-486** (its two owed numbers — the ≥90 % needle at 150 016 and the cold-prefill ladder
      — are unmeasurable because the leg is gone: that is a retirement, and CONVENTIONS §4 puts a retired
      rationale in the owning doc / rejected log, not in the row); **rewrite HD-474** to FIM + vision with its
      owner hands re-scoped; **keep HD-476** (vision is exactly what stays, and its one owed number — an image
      resident in the KV of a 32 k window — is now *the* measurement that matters).
- [ ] Decision log: one row in `docs/services-ai.md` §9 (#28 amended) **and** the rejected-log line for the
      agent leg, so nobody re-proposes a 150 k local agent (CONVENTIONS §8.3).
- [ ] ⚠ `scripts/install-pi-wsl.sh` / `pi-seat-sync.sh` deploy the seat render — if a live seat lane
      (HD-1110's tails) is in flight, **park P1's `models-spec.yml` hunk** and note it; do not race it.

### P2 / P3 — draft the ten briefs (1 session each, ~100–140 k each)

Additive only: write the new file, **leave the old one in place** (so no link breaks and the views stay
honest until P4). Per brief, the required content — and nothing else:

1. **Header** as the existing briefs do: `Role` (dispatch note for one lane session) · the rows it carries,
   each as a link to `todo.md` **plus "rows as of `<commit>`"** · `Linked from: todo-table.md §B0 · todo.md`.
2. **The lane contract, one line** pointing at `docs/orchestration.md` §4 (O1–O9). Do **not** restate O1–O8
   per brief — that is how the old set accumulated five copies of the pairing rules and drifted.
3. **Converge host + slot** (O3) and the **do-not-share-a-wave** line, derived from the host, not from habit.
4. **Order of work** — one row per line, `Do` = the *action*, `Note` = the gate/trap in ≤ 2 lines. Everything
   longer than that belongs to the row or the doc (that is exactly the sentence that made the old briefs lie).
5. **Traps that cost a round** — carried over from the old briefs, deduplicated, and **re-grounded against
   the current tree**: at minimum re-check every pinned version, path and script name cited
   (`check_doc_path_refs.py` will prove the paths in P4, prose claims it will not).
6. **Owns / never touches** and **Acceptance** (the micro-format: `PASS/FAIL/BLOCKED/PARKED` + number +
   evidence path).
7. **A "closed since this brief was written" line is forbidden** — a brief that narrates history is the
   failure mode this rewrite exists to end.

Known grounding fixes to land while drafting (found 2026-10-08, verify each before writing it in):

- `prompt-384` material: the LiteLLM constants were taken on **v1.83.10**; the pin is **v1.104.0**. Re-read
  §4a of `services-ai.md` and re-measure before restating any of them.
- `prompt-361` material: the "oldsrv owns Cockpit" ruling is **superseded** (both nodes serve the tailnet
  cockpit surfaces); **HD-445 and HD-446 no longer exist** as rows — do not carry them.
- `prompt-357` material: HD-418 is **authorized unattended** and pairs with **HD-1103** in the **Pi** window,
  so the brief's converge host is the **Pi** for that row, not oldsrv. ⚠ Before writing "add `oldsrv_home_ip`
  to `ha_trusted_proxies`": `group_vars/all/main.yml:455` has listed `10.10.1.30/32` (= `oldsrv_home_ip`)
  since `c9c36f23` (2026-09-11), while the row and `traefik-internal/routes.yml.j2:22‑33` say it does not —
  measure the Pi's rendered `configuration.yaml` first and record which premise is wrong.
- `prompt-376`/`prompt-llm`/`prompt-remaining-bench` material: merge the three (one spark slot), state once
  that `spark_llm_pool_ceiling_bytes` is 16 GiB with `fast` overriding to 20 GB, that **gate 7 is closed**,
  and that the remaining certificate item is gate 6's battery at `max_tokens 16 384` **with the B1 baseline
  re-run in the same change**. Drop the `ple-bf16-*` verify that contradicts HD-475's staged state.
- `prompt-436` material: add the 2026-10-08 ruling (unattended = **dry-diff only**), and the RouterOS-API
  fact (HD-495) that removed the mechanical blocker.

**Per-brief self-check before a drafting phase commits:** every named row exists in `todo.md`
(`grep -c "^| HD-<id> "`); every path exists (`python3 scripts/check_doc_path_refs.py` on the new file, or
manually); no pinned version quoted without a `versions.yml` line; no "done/closed" narration; ≤ ~450 lines.

### P4 — the switch (1 session, ~180 k; runs alone, last)

- [ ] Rebase onto current `main`, **re-derive every HD id** the new briefs name (see §1's renumber), and fix
      the briefs that moved.
- [ ] `git rm` the 8 old briefs **in the same commit as** every link fix (O7). Inbound link inventory,
      measured at plan time: `todo.md` **28**, `todo-table.md` **26**, `prompt.md` **4**,
      `docs/spark-llm-profiles.md` 2, `docs/orchestration.md` 1, `docs/hardware-workstation.md` 1,
      `docs/deployment-secrets.md` 1, `docs/services-authentik.md` 1.
- [ ] **Evidence files** (`spark/llm-profiles/README.md`, `spark/reports/hd489-overnight-20261004-0804/README.md`,
      `reports/hd474-laptop-leg/README.md`, `reports/hd474-laptop-leg/raw/00-SESSION-STATE.md`) link brief
      names and are **not** in `check_doc_path_refs.py`'s FROZEN set. Rule: in **dated evidence**, turn the
      link into plain text (the record keeps its wording and stops making a path promise); in **live docs**,
      re-point to the new brief. Never rewrite a dated record's prose.
- [ ] Prose cites that are not links but still lie: `scripts/laptop-llm.py:189` ("`prompt-llm.md` §6"),
      `scripts/spark-fp8-image-probe.py:4`, and `todo.md`'s HD-440 reference to the deleted `prompt-407.md`.
- [ ] `todo-table.md` §B0 becomes the **row→brief index + waves** (the thing `prompt.md §3` used to be), with
      10 rows and the host/slot column; fix the §A2/§D owner lists; delete the **HD-445/HD-446** phantom rows.
- [ ] `prompt.md` §2 rewritten as the ranked pointer list: new brief names, the **audit fixes** still open
      (`1094` is closed by the fleet pin — the row must go; `1101` is open but the handoff describes it as
      fixed; the `47`/`454` owner tails are `⏸ Deferred`; the `1089`/`1090`/`1093`/`362-tail` unbriefed blurbs
      describe work that has since landed), and the list-numbering wrinkle where a `7.` restarts after prose.
- [ ] Delete `prompt-tasks-rework.md`. Exit: `check_doc_path_refs.py` **and** `validate-all.sh` green.

### P5 — the gate that would have caught this (1 session, ~40 k)

Extend `check_todo_done.py` (it already parses row ids, and already reads only `prompt.md` for status claims —
keep that asymmetry) with a **reference-existence** pass over `prompt*.md`: every `HD-<digits>` named in any
brief must exist in `todo.md`, else FAIL and name the file:line. Register it as a numbered
`validate-all.sh` item with the usual `--self-test` that breeds a red. This is the check that would have
flagged HD-445/446 in `prompt-361.md` and `todo-table.md` §B0 the day those rows closed.

---

## 5. Hazards to respect (each is a rule, not advice)

- **Views are single-writer and last.** Everything that touches `prompt.md` / `todo-table.md` is P4 (O2). A
  phase that "just fixes one line" in a view will collide with the orchestrator's own rewrite.
- **`todo.md` edits are row-local hunks.** Never re-sort, re-flow or renumber a table; two phases editing
  different sections rebase cleanly, two phases re-flowing the same table do not.
- **Rebase and re-derive, every phase, immediately before committing** — ids moved once already
  (`85a1b3fc`), and the fleet merges several times an hour.
- **P1 vs the live seat lane**: both want `scripts/pi-config/` + `install-pi-wsl.sh`. Check
  `git log --oneline -3 -- scripts/pi-config` and any open session worktree before P1's seat-render hunk; if a
  seat lane is open, P1 lands its doc/row half and leaves the render hunk staged with the exact diff in the
  row's ⏳ tail (O4 form).
- **Do not mint HDs anywhere in this rework.** It is a rename + two closures; a new id here is a false
  record of new work.
- **No history in the new briefs.** Sessions live in owning-doc status blocks + git; if a sentence reads like
  a diary, it belongs in a commit message.

---

## 6. Resume lines (if a phase runs out of context)

Each phase ends by writing, into this file's **Status** line, the phase id, the worktree/branch, and the
next unwritten item — then committing. The next session starts from `prompt.md` §2 → this file:

- **Status:** P0 · P1 · P2 · P3 · P4 · P5 — all open · plan pinned at `2d1c107d`
- **P0 resume:** `docs/orchestration.md` §4 O9 → O7/§wave-pointer → `CONVENTIONS.md` §6/§4 → `README.md` §2
- **P1 resume:** profiles + models-spec (same commit) → `laptop-llm.py` → docs/log → rows 486/474/476
- **P2 resume:** spark, dns-transport, media-arrs, litellm-consumers, smart-home (in that order)
- **P3 resume:** edge-identity, seat-cockpit-grants, observability-alerting, storage-backup, laptop-legs
- **P4 resume:** ids re-derived → `git rm` × 8 + link fixes (one commit) → §B0 → `prompt.md` → delete this file
- **P5 resume:** `check_todo_done.py` pass + self-test → `validate-all.sh` item → `scripts/README.md` row

**Out of scope for this rework:** any IaC change, any converge, any doc rewrite beyond link/rule fixes, and
re-deciding anything in a `<domain>-rejected.md` log (CONVENTIONS §8.3). The only decisions written here are
the two the owner already made: the **context budget** (§2 O9) and the **laptop's legs** (§4 P1).
