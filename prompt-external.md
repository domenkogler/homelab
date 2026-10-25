# `prompt-external.md` — Lane brief · the **model axis**: any box, a NON-spark model · five whole-corpus rows + the Rule-0 spark window

> **Role:** dispatch note for **one** session whose own model is NOT served by the spark engine. Every item here is
> selected by *which model serves the session*, never by *which box it stands on* — the two axes are separate and a
> launch states both ([docs/orchestration.md](docs/orchestration.md) §4). Two halves, and they are not the same kind
> of claim: **(1) five rows this brief owns** — work that must hold the whole corpus in view at once, which a
> locally-served 262 144-token context at ~11 tok/s cannot carry across a compaction boundary; **the rows are the
> authority** for what is missing and how to do it, this file carries only the contract, the order and the traps:
> [todo.md](todo.md) **HD-1169 · HD-1157 · HD-1156 · HD-1117 · HD-1149**
> (row ids as of `dc890c67` — re-derive with `grep -c "^| HD-<id> " todo.md` before quoting one).
> **(2) legs this brief does NOT own** — the timed spark engine legs Rule 0 bars a spark-served session from running.
> Those rows stay on the spark brief's §B0 cell and in its card; this file adds the seat rule and the run order and
> nothing else ([prompt-spark-llm.md](prompt-spark-llm.md), [spark/reports/external-window-card.md](spark/reports/external-window-card.md)).
> **Linked from:** [todo-table.md](todo-table.md) §B0 · [todo.md](todo.md) · [prompt.md](prompt.md) §2

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O11) — read it once; it overrides README §4 and
CONVENTIONS §6 at the items it numbers, and this brief deliberately restates none of them.

**Converge host + slot (O3):** **none of its own** — the five rows are in-repo (gate + docs + one `scripts/` cache).
Its timed legs sit inside the **one** spark bench window — read `scripts/bench/spark/metrics-window.sh --status` first:
at `dc890c67` a 9 h window was accruing, and a later sitting may find it closed, in which case report the closed window
and park the leg. ⛔ never start a second window, never run the sampler's start line (parent-only, a lane may not leave
a process behind), never beside
a spark-slot converge or a probe lane standing things up on that box. HD-1149's `samba.yml` check-mode half is a **NAS
host-present leg → park it (O4)**, it is not this lane's converge.

## 0. Before anything timed or claimed (the seat question, answered mechanically)

| # | act | why it is first |
|---|-----|-----------------|
| 1 | `echo "seat=$(uname -n) provider=$PI_PROVIDER model=$PI_MODEL"` | Rule 0 in one line. Expect a provider that is **not** the spark engine. Four drivers refuse you with **exit 3** otherwise, and there is no `--whoami`: a refused driver is the only mechanical seat answer. |
| 2 | an externally-served run is **a model switch, not a config change** | both provider blocks are already rendered into the seat from [scripts/harness/pi/models-spec.yml](scripts/harness/pi/models-spec.yml); the picker's external rows are the cost-bearing hosted ones. `/model` re-reads mid-run; a new session picks it up at start. |
| 3 | **do not export `PI_PROVIDER`/`PI_MODEL` to pass a guard** | the repo documents only the READ of those two variables — the only assignments anywhere are `--self-test` fixtures. Forging them is a seat-side lie the provenance gate cannot see ([scripts/gate/check_bench_provenance.py](scripts/gate/check_bench_provenance.py)), and it invalidates every number you then quote. |
| 4 | children **inherit** the model, they cannot switch | `subagents.modelScope` is inherit-only, so Rule 0 binds the whole run wherever it sits — including every child you launch. |
| 5 | `git status --short && git worktree list`, then your own worktree; `bash scripts/validate-all.sh` once, record the item count with `--list \| wc -l` | the standing contract (§6, O5); the count is the command, never a typed number. |

**Why this lane exists at all, in three measured numbers:** harness decode on the local engine is ~11 tok/s with a
262 144-token ceiling and compaction at 245 760 ([docs/harness-pi-engines.md](docs/harness-pi-engines.md)); a full
lane session pays a ~60 k-token boot ritual before its first read
([docs/orchestration.md](docs/orchestration.md) O9); and the corpus these five rows must hold at once is 710 files /
8.7 MB of the text the doc gates read. That is the whole case for hiring a different model — not for a bigger prompt.

## Order of work — the five rows this brief owns

| # | Row | Do | Gate / trap |
|---|-----|----|-------------|
| 1 | **HD-1169** | clear or land here the **19 carried citations** in [scripts/gate/path_refs_baseline.txt](scripts/gate/path_refs_baseline.txt) — the ten `spark/reports/hd489-*/README.md` sites and the two spark playbooks are the cheap ones; keep the ledger's stale half at zero | `python3 scripts/gate/check_doc_path_refs.py` and `--self-test`; re-derive the ledger with `--show-baseline` **in the same commit** as any matcher change (a growth-only ratchet reddens the whole suite when its body drifts). Trap: the two spark playbooks' vault group_vars pair is a question for the spark lane, not a blind fix; the row's 1 259-target figure is 1 293 on this tree — re-measure, never quote it |
| 2 | **HD-1157** | (a) a state-word read over the vault item table: parse §Master Secret List of [docs/deployment-secrets.md](docs/deployment-secrets.md) row by row and FAIL when a `field=` cell is prose or a state claim, and widen the derived set to the `group_vars` `*_item:` scalars; (b) resolve the Owning-spec link in [scripts/gate/check_registry_prose.py](scripts/gate/check_registry_prose.py) with the same resolution `check_doc_path_refs.py` already implements | `check_vault_docs.py` (it has **no** `--self-test` arm), `check_registry_prose.py --self-test`; both are ratchet changes — land with the finding count **at rest, measured in this commit** (the `check_md_tables.py` one-finding-at-rest lesson). Trap: the *anchor* half of that cell is HD-1156's hole, its own row — do not fix a source set twice |
| 3 | **HD-1156** | make a bare number stop matching a lettered sub-number (refuse a prefix hit whose remainder starts with a LETTER) while keeping the spelled-name tie-break and the retried token window green; then the two measured holes — the retried window that never asks `inside_a_number()`, and the source set that makes no root-level `.md` and nothing under `scripts/**` a source at all | `python3 scripts/gate/check_doc_headings.py --self-test`, then `--show-baseline` for [scripts/gate/doc_headings_baseline.txt](scripts/gate/doc_headings_baseline.txt) **in the same commit**. Trap: all 31 green-but-wrong pointers were already repointed when the row was minted — do not re-repoint; the scale is whatever the plain `python3 scripts/gate/check_doc_headings.py` summary prints at your commit (468 files / 807 target docs / 1 127 refs were true at `dc890c67` and are stale by the time you arrive) — and that scale is exactly why this row is here and not in a spark-served lane |
| 4 | **HD-1117** | the one real code leg: a content-hash cache over the corpus `check_secrets.py` walks (~1.5 k files today, ~5 s of the 12 s wall), keyed ALSO on the scanner version; keep the six pool-flaking items as measured state with their `POOL DIAGNOSTIC`, not as speculative fixes | `python3 scripts/gate/check_secrets.py`, `python3 scripts/render_all.py --check --no-write`, and `bash scripts/validate-all.sh --list \| wc -l` diffed against an earlier commit. Trap: **a cached green is not a green**; the gawk half belongs to **HD-1202**, and the `item_x` arms never run alone, so a full-profile run is the only honest witness |
| 5 | **HD-1149** | answer the two audit questions, and they are two different mechanisms: `home_assistant` is pulled **bare** by both playbooks that use it, so its Pi/standby sub-files ride the include line's own tag, while `cockpit` is pulled **with** a `roles:` tag, where dropping that tag is what would silently unreach its children — do not carry one answer for both. Then the `samba.yml` check-mode assert that fails because the lookup above it is skipped in check mode | `python3 scripts/gate/check_tag_coverage.py --self-test`; the 8-leg live witness is full-profile-only and pays for an ansible venv — buy it when a tag or an include line changes, not per keystroke. Trap: the NAS `--check` half is owner-present (O4 park), and [docs/deployment-ansible.md](docs/deployment-ansible.md) still calls the gate's registration "the owner's checkpoint" when it is a normal item — fix that stale line in the same change |

## Order of work — the spark window (legs only; the rows are the spark brief's)

Run order is the card's, and the card is the authority: reads first (they cost nothing and can invalidate a later
leg), then legs on the profile already serving, then anything needing a flip, grouped **one profile per boot window**
(~20 min cold). Exit contract, shared: `0 captured · 1 unparseable · 2 usage · 3 RULE 0 · 4 pairing, attribution,
window-thin or prefill-failed · 5 depth above the servable ceiling refused · 6 engine container not running`.

| leg | row | the act, in one clause | gate / trap |
|---|---|---|---|
| `scripts/bench/spark/metrics-window.sh --report` (poll with `--status`) | HD-380 | read the accruing window's prefix-hit + preemption delta beside the pre-raise numbers | `--status` before anything else: at `dc890c67` a 9 h window was accruing, and if the sampler has exited you report the closed window and park (exit 4 = too thin to judge). Never start a second sampler; the start line stays parent-only; no Rule 0 code by design |
| `scripts/bench/spark/text-only-preflight.sh` | HD-400 | the four reads + the A/B the row owes | legal from any seat; "the ViT is loaded" is a FINDING, not a failure; the IaC line stays NOT applied (owner window) |
| `scripts/bench/spark-fp8-image-probe.py` | HD-473 | a verdict on fp8 main KV in the pin | answers `BLOCKED-ON-IMAGE` at this HEAD — re-running re-proves the verdict and does not open the row; refuses a converge in flight (exit 2) |
| `scripts/bench/spark/gate6-couple.sh --max-tokens 16384` | HD-489 | both legs graded at one budget read back off the wire | **must ship with the B1 baseline re-run in the same act** (exit 4 breaks a broken pairing); `--battery-only` is refused always; never `accuracy-gate.sh` alone at 16 384 |
| `scripts/bench/spark/usable-sampler.sh` | HD-494 | the floor of `MemAvailable − CmaFree` across one heavy prefill | a missing field is not a zero; the floor CHOICE stays the owner's |
| `scripts/bench/spark/needle-window.sh --profile <name>` | HD-376 | PASS-DEPTH per profile: HTTP 200 **and** `prompt_tokens` ≥ 80 % of that profile's own window | run it **detached** and poll (cold prefill is NVMe-bound); an uncertified arm needs the owner's per-run opt-in flag; never ask above 262 144 |
| `scripts/bench/spark/hd469-baseline.sh` | HD-469 | the `clocks.sm` trace ACROSS the window with usable memory read at both ends | waits on an owner-window profile flip — the live host dial says `fast`, the leg wants `reasoning`; a probe FAIL is a RESULT, not an exit code |
| the flip converge, then `spark-llm-probe.py ctx 262144` / `concurrent 4` | HD-475 | gate 3's full-window leg answers 200 instead of 502-ing at ~105 s | no wrapper, so no exit contract; never re-fetch the staged set, never `--quantization`, never raise a ceiling; the flip is an owner-window engine recreate |

## ⛔ Traps that cost a round (re-grounded at this `HEAD`)

* **Rule 0 is about pollution, not speed.** A spark-served session's own tokens land in the pool and the counters it
  would then quote — that is why these legs are here. Standing on the designated runner station does **not** lift it.
* **Closed is closed.** Gate 7 CLOSED on two reads; B10's gates 6/8/9 declined by the owner (the row stays
  `UNVERIFIED`, no flag opens it); B9 · B5 · B8 closed; LMCache KV offload is in the rejected log. A third read of a
  closed gate measures a different window and is not evidence.
* **Silence is not a hang.** On a locally-served model a child compacts for minutes; the clock-based steer timer was
  retired. Act on a needs-attention notice, a repeated tool failure, or the 2 h deadline — never on quiet.
* **Ledgers move atomically.** HD-1169 and HD-1156 both re-derive a baseline in the SAME commit as the matcher change;
  a stale carried line is a free pass for the next wrong path at that key. Measure the finding count at rest.
* **The engine dials are not yours.** `IaC/ansible/host_vars/spark.kogler.si.yml` and the profile defaults belong to
  the spark lane and to an owner window; never `reboot spark` — whoever stops the engine owns bringing it back.
* **External is a harness-side choice only.** A session may route *its own* model off-box; it may not make the
  gateway fall back to an external API for engine traffic (decision #26, [docs/services-ai.md](docs/services-ai.md) —
  see its rejected log). And the hosted rows cost money: say so before a long run, and never present a paper-only
  provider alias as an available row.
* **Numbers are re-derived, never copied.** File counts, item counts and gate verdicts in this file were measured at
  `dc890c67`; quote the command that prints them, not the number.

## Owns / never touches

**Owns:** the five rows and their `todo.md` rows (row-local hunks only, never a re-flow); the gate files those rows
name — `scripts/gate/check_doc_path_refs.py`, `check_doc_headings.py`, `check_vault_docs.py`,
`check_registry_prose.py`, `check_secrets.py`, `check_tag_coverage.py`, `scripts/validate-all.sh`,
`scripts/render_all.py` — their two ledgers; in `scripts/README.md` only the **registry rows of these five gates**,
one physical line each, because the scripts lane owns that file's prose; the lines `CONVENTIONS.md` §8.5 and
`docs/deployment-ansible.md` carry for these rows; and new evidence FILES in one NEW dated directory under
`spark/reports/` — never the prose of an existing dated record, which is the spark lane's.
**Never:** `prompt.md` or `todo-table.md` (O2 — the parent owns those, and this brief's own §B0 cell is its
registration); another brief's rows — the spark rows, their card and their IaC profiles are the spark lane's, and the
`scripts/**` rows already carried elsewhere are not yours to re-take; **`roles/**`** — row 5 investigates `roles/home_assistant`,
`roles/cockpit` and `roles/storage/tasks/samba.yml`, and all three belong to other lanes, so answer the question,
report it, then hand any tag or include edit to the owning lane; generated `*-generated.md`; the frozen
`reports/` archives; any secret value (1Password refs only, never a literal, never a `default('')` fallback).

## Acceptance

Every item returns `PASS` / `FAIL` / `BLOCKED` / `PARKED` + the number + the evidence path; a claim with no path
counts as not run. Concretely: the five rows' own gate commands from the table above, each with its printed verdict
line; `git log --stat` proving which commit moved which ledger; `spark/reports/` + a
`python3 scripts/gate/check_bench_provenance.py` read naming the `client` stamp of every timed leg you ran; and
`bash scripts/validate-all.sh` green **in this worktree** → **stop**. Anything you parked, name it and the owner act
it waits on — a park is a verdict, not a failure.
