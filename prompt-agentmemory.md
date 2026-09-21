# `prompt-agentmemory.md` — Probe brief · agentmemory as the **one central** memory plane, and Hermes' store (no HD row; measurement only)

> **Role:** self-sufficient lane brief. It carries **all** context needed to run the probes and report, so
> **read this file and nothing else** (the Step-0 ritual of [README.md](README.md) §0 still applies:
> `git status` + a fresh session worktree before any write). It registers **no new `HD-XX` row** and opens
> **no todo.md work item** — this is **not part of the todo tasks**. It produces a *measurement report* the
> owner uses to decide the architecture. Do not implement, do not deploy permanently, do not decide.
> **Linked from:** owner's direct request (2026-09-21), immediately after the OpenViking lane
> (`reports/probe-ov-20260921.md`). Deliberately **not** listed in `prompt.md` §2 yet — it is a probe, not a
> build lane; add the line only when the owner accepts the outcome.
> **Owner rulings this brief carries (2026-09-21, verbatim intent):** (a) **one central instance**, not one
> per project — this *amends* `docs/services-ai.md:535` ("One instance per project …"), and the amendment is
> **proposed text in §6 of this brief, not an applied change**; (b) **"quadrant" meant [Qdrant](https://qdrant.tech/)**
> — the vector store already live here, not a host; (c) **Hermes must not keep its own memory store** — the
> candidates are Qdrant-backed or the central plane. Measure both; **do not decide**.
> **Hard constraint (owner's, unchanged): 100 % local.** spark + the oldsrv dGPU legs only. **No paid or
> external endpoint anywhere in this lane.** This is load-bearing *specifically here*, because agentmemory's
> provider auto-detection is cloud-first (`OPENROUTER_*`, `GEMINI_*`, `ANTHROPIC_*`, `VOYAGE_*`, `COHERE_*`):
> **no cloud key may appear in any `.env` this lane writes.** The only permitted endpoints are
> `http://10.10.1.30:4000/v1` (lan-litellm) and its `/v1/models` rows. If a measurement cannot be made
> locally, **stop and ask**; do not spend, do not substitute.
> **Excluded from validators by design:** `check_doc_map.py`, `check_doc_ips.py`, `check_placeholders.py`
> all skip root `prompt-*` handoffs, so this file may name hosts and paths freely.

---

## 0. What to do, in one paragraph

Stand up **agentmemory** (`agent-memory.dev`, Apache-2.0) ephemerally on **oldsrv** under the **`domen` seat**
(HD-409; HD-336's placement is already "oldsrv + ZeroClaw runner") as **one central instance**, keyless for
LLM, embeddings pointed at the **existing local `bge-m3` leg**, then wire **pi.dev · OpenClaw · Hermes ·
OpenHands** as clients and answer five measured questions: **M1** does it capture and recall **with zero LLM
in the hot path**, is recall **deterministic** (same query ×5 → identical ranking) and does it hold **exact
identifiers**; **M2** does its vector leg actually work on *our* encoder at **1024** (it is not in
agentmemory's known-models table — the 1536-default trap) and how much does hybrid beat BM25-only; **M3** can
it really be **central** (one instance, LAN-reachable, per-user/per-client scoping, auth, 4 concurrent
clients, cross-client recall); **M4** can **Hermes** put its memory in **Qdrant** with its own
`MEMORY.md`/`USER.md` **empty**, and what does a second plane cost versus Hermes joining the central instance;
**M5** cost/contention/ops (spark tokens per session — should be ~0; wall-clock; snapshots/restore; exit
cost). Score recall against the **baseline already in the tree** so the numbers are comparable (§5.6).
Budget: **M0+M1+M2 ≈ 2 h; all five ≈ 4–5 h.**

---

## 1. The decision this feeds (and what it must NOT decide)

| ID | Question | Owner decides after this report |
|----|----------|--------------------------------|
| **OQ-12** | Is agentmemory the **single central memory plane** for pi/OpenClaw/Hermes/OpenHands/ZeroClaw, replacing "one instance per project" in `docs/services-ai.md:535` with "one instance + project/repo tags"? | yes |
| **OQ-13** | **Hermes' memory store**: Qdrant-backed (a `mem0 --mode oss --oss-vector qdrant`-class provider), the central plane, or its own files (which the owner has ruled out)? Measured, then reported. | yes |
| **OQ-14** | Does memory need the **`bge-m3` leg at all**, or is keyless BM25 (+ graph pass) enough on this corpus — i.e. does the memory plane depend on LiteLLM? | yes |

**Out of scope / must not decide:** the harness bake-off itself (which harness wins — `prompt.md` §4 owns it);
`rag-mcp` (HD-268b) and whether Qdrant is the **corpus** plane (HD-335 owns that, including the pending
re-index); VPS anything; converging/benchmarking spark (HD-397/417 — never from a session whose model is
spark). This lane must also **not quietly create a second memory plane**: if Hermes ends up on Qdrant while the
others are on agentmemory, the report states the divergence cost explicitly (§6 rows 4–5).

---

## 2. Non-negotiables (the guard, same as the OV lane)

1. **Step-0**: `git status`; fresh session worktree `../homelab-wt-$(date +%Y%m%d-%H%M)`; `bash
   scripts/guard-session.sh` before any write.
2. **Nothing permanent.** No `HD-XX` row, no `todo.md`/`todo-table.md` write, no `DECISIONS.md`, no IaC change,
   no new model row in lan-litellm, no container, no systemd unit, no cron. Ephemeral + torn down with proof (§8).
3. **Seat**: `domen` on oldsrv via `sudo -u domen` (HD-409). `/home/domen` is `0700`, so *every* path under it
   needs `sudo -u domen`; nested `sudo` inside a `domen` shell fails. AI never runs as root/`ansible-admin`.
   **No global npm installs**: use `~/amprobe/prefix` (`npm_config_prefix=…`) or `npx -y
   @agentmemory/agentmemory@latest` inside `~/amprobe` — the OV lane's venv rule, Node edition. Note npx
   caches per-version and can serve a stale release: pin or force `@latest` and record the version you ran.
4. **Egress must be logged, not assumed.** agentmemory downloads a **pinned `iii-engine` binary** (default
   `0.11.2`, `AGENTMEMORY_III_VERSION`) and, in `EMBEDDING_PROVIDER=local`, **`Xenova/all-MiniLM-L6-v2`** from
   HF. Record what it fetched and from where; if the engine download is blocked on the seat, **that is a
   finding, stop and report it**. ⚠ Never let MiniLM load and then report recall as if it were bge-m3 (§4 T1).
5. **Secrets**: lan-litellm key read from 1Password into a `0600 ~/amprobe/.amenv`, exported as env only, never
   written into a config file, never in argv, never in the report (`grep -c` output only). `AGENTMEMORY_SECRET`
   is generated locally for the probe and destroyed at teardown. **Do not `docker inspect` a container's env
   unfiltered** — the lane before this one leaked a DB password that way (`reports/probe-ov-20260921.md` §10).
   Per-client tokens, never the master key (HD-426). A token is not rotated until you **re-issue and compare
   length/prefix** (142-char check, HD-425 lesson).
6. **Models**: only rows present in `/v1/models` (`spark/qwen3.8-flash-next`, `bge-m3-vk`, `local-rerank`,
   `local-stt`). If you point the LLM slot at LiteLLM at all (only needed for optional consolidation tests),
   **`spark/` is mandatory** (HD-387) and thinking off is **`extra_request_body`-shaped config, not a flag**.
   Embeddings/rerank must be sent **provider-prefixed** (`openai/bge-m3-vk`, `jina_ai/local-rerank`) — verified
   by the OV lane — while **open-webui must keep sending them bare** (HD-423). Two callers, two rules; verify
   which one agentmemory is in and record it.
7. **Qdrant is live** (`https://qdrant.kogler.si`, `/srv/docker/qdrant`, HD-267/268). Touch **only** collections
   you name `probe_*`, delete them at teardown, and **do not re-index anything** (HD-335 owns the re-index after
   the bge-m3/1024 cutover). Do not write into `qdrant_db` or any existing collection.
8. **Process hygiene**: never kill by `-f pattern` (it kills your own ssh session) — `pgrep -f <name> | head -1`
   then `sudo kill <PID>`, then `-9` if shutdown hangs. The measurement driver runs **detached on oldsrv**
   (`nohup setsid`) so a stalled API cannot wedge the session.
9. **Self-load**: do not drive spark-heavy work from a spark-backed session; if this session's own model is
   spark, run drivers detached and note the residual load in the report.

---

## 3. Facts already true — do not re-derive them

**From the OpenViking lane (same box, same models, 2026-09-21).** Scripts + raw outputs are in
`reports/probe-ov-20260921/`; reuse them rather than writing new ones.
- **Baselines to beat** (10 known-answer questions, 51-file / 1.9 MB slice): `p2_ov.json` → OV **hit@5 8/10,
  5,267 tok/query, 0.065 s**; `p2_grep.json` → grep **hit@5 5/10, 92,004 tok/query, 0.042 s**.
  Rubric and question set: `questions.json`, `p2_run.py` (score mode), `p3_score.py` (R1/R2/R4/R5),
  `p1_metrics.py` (fidelity). If you change the question set, **run the grep baseline again** — never compare
  against a different corpus.
- **Contention**: 16-token spark request **0.27 s idle → 8.7 s (32×)** during an OV compile; aggregate decode
  ~45 tok/s at `max_concurrent=3`. A memory plane that adds **zero** spark decode is the whole argument.
- **Tokenizer trap**: OV's estimator ran ~40 % low against bge-m3 and llama.cpp (`n_batch 2048`) silently
  rejected 91/510 chunks. Any long *observation* path here must be measured for rejects, not assumed safe.
- `split DNS`: **`llitellm.kogler.si` does not resolve on oldsrv** — use `http://10.10.1.30:4000/v1`.
- Token accounting on the OV side was fragile; **use lan-litellm's own metrics** to prove "zero LLM calls in the
  hot path" (per-model usage before/after), not the product's counters.

**About agentmemory (verified 2026-09-21, its own docs + repo).**
- Apache-2.0; local-first; **no external DB by design** ("It is not a vector database. There is no Qdrant") —
  so **agentmemory can never use Qdrant as *its* store**. Qdrant-backed memory necessarily means a *different*
  provider (e.g. `mem0` in oss mode). Say so in the report if you find yourself assuming otherwise.
- **Keyless by default**: capture, indexing and recall run with no key. `EMBEDDING_PROVIDER` ∈
  `local · openai · voyage · cohere · gemini · openrouter`; `OPENAI_BASE_URL` overrides the endpoint
  (LiteLLM/vLLM/LM Studio/Ollama via `/v1`); `OPENAI_EMBEDDING_MODEL` + **`OPENAI_EMBEDDING_DIMENSIONS` is
  required for any model not in its table** (default assumption 1536 — ours is **1024**). Without a key, hybrid
  runs **BM25-only** unless `EMBEDDING_PROVIDER=local` (on-device `all-MiniLM-L6-v2`, 384-dim).
  `OPENAI_API_KEY_FOR_LLM=false` keeps a key for embeddings while skipping LLM auto-detection.
- Weights `BM25_WEIGHT 0.4` / `VECTOR_WEIGHT 0.6` / `AGENTMEMORY_GRAPH_WEIGHT 0.2`; injection
  `TOKEN_BUDGET 2000` via `mem::context`; `MAX_OBS_PER_SESSION 500`.
- LLM is used only by opt-in paths: `CONSOLIDATION_ENABLED`, `AGENTMEMORY_AUTO_COMPRESS`,
  `GRAPH_EXTRACTION_ENABLED`, `AGENTMEMORY_REFLECT`, chunked summarize (`SUMMARIZE_CHUNK_*`),
  `AGENTMEMORY_LLM_NOTHINK=1` exists for local reasoners. **A keyless structural graph pass always runs at
  session end** — measure it, don't assume "keyless = no work".
- Ports `3111` REST/MCP (`III_REST_PORT`, viewer at +2 → `3113`), `3112` streams, `49134` iii-engine
  (`III_ENGINE_URL=ws://localhost:49134`). Data dir: `AGENTMEMORY_DATA_DIR` / `--data-dir`, default
  `~/.agentmemory`. ⚠ **Verify the on-disk layout empirically** — `services-ai.md` §9b types
  `~/.agentmemory/<project>`; confirm whether the per-project split is a directory, a tag, or neither, and
  report the corrected path rather than repeating either claim.
  `AGENTMEMORY_SECRET` gates REST+viewer+plugins; **without it they are open on loopback** — and the viewer is
  on `+2`, so a LAN bind leaks it too.
- **Central is not first-class upstream**: open issue **#523** requests exactly "one server, LAN clients";
  the MCP shim hardcoded `localhost:3111` until **#386/#460** made it inherit `AGENTMEMORY_URL`/
  `AGENTMEMORY_SECRET`. ⇒ **check the installed version's behavior empirically**, and keep `STANDALONE_MCP=1`
  as the fallback for a client that insists on localhost. Multi-tenant scoping exists: `TEAM_MODE=shared` +
  `TEAM_ID` + `USER_ID`.
- Client surface: **native plugins for pi, Hermes, OpenClaw**, 19 adapters + generic MCP; **OpenHands is not an
  adapter** → MCP path only, and you must verify its capture actually fires (prompts *and* tool results).
  `AGENTMEMORY_TOOLS=all` (54) vs `core` (8) — record the **MCP tool-schema token cost** you pay per client.

**About Hermes' memory (verified in the OV brief's candidate table, re-verify on the shipped build).**
Built-in memory providers: `openviking · honcho · mem0 · hindsight · holographic · retaindb · byterover ·
supermemory` — **one active at a time** — and **`MEMORY.md`/`USER.md` are always on**. ⇒ the owner's "Hermes
should use Qdrant, not its own" is reachable only *through* a Qdrant-capable provider (`mem0 --mode oss
--oss-vector qdrant`) **and only if the file layer can be emptied/disabled**. Whether that knob exists is
M4's central question; if it does not, that is a **blocker to report, not a thing to work around**.
⚠ Mem0's dims trap (OV brief §4): its `openai` embedder sends `dimensions` **only if you set
`embedding_dims`**, and llama.cpp/vLLM-class backends **reject** that parameter; unset ⇒ it assumes **1536**
while our leg is **1024**. Probe before wiring anything.

---

## 4. Traps, pre-registered (confirm or refute each with evidence, in the report)

| # | Trap | What "confirmed" looks like |
|---|---|---|
| **T1** | Silent fallback to `all-MiniLM-L6-v2` **384-dim** when the embedding provider line is wrong | keyless "hybrid" is really BM25-only; index dims ≠ 1024. Prove by reading dims, not flags |
| **T2** | **1024 vs 1536**: `OPENAI_EMBEDDING_DIMENSIONS` unset for a model not in the table | dimension-guard error, or `AGENTMEMORY_DROP_STALE_INDEX=true` silently wiping an index |
| **T3** | The embedder sends a `dimensions` param our llama.cpp-class leg rejects (HD-423's trap family) | raw `POST /v1/embeddings` with and without the param, recorded |
| **T4** | MCP shim wants `localhost:3111` (pre-#386/#460 behavior) → a client silently memories into a **local** store while you think it's central | two stores alive at once; detect by comparing each client's recall against the central instance |
| **T5** | Hermes keeps `MEMORY.md`/`USER.md` regardless | the files are non-empty at the end of an M4 run |
| **T6** | A second plane (Hermes→Qdrant/mem0) silently diverges from the central one | same question answered differently by the two stores — measure it, quote both |
| **T7** | LLM auto-detection firing (any cloud key present, or `OPENAI_BASE_URL` pointing somewhere else) | lan-litellm metrics show calls you did not intend; or egress to a cloud host |
| **T8** | `iii-engine` pinned-binary download blocked / version drift | install fails or `AGENTMEMORY_III_VERSION` had to change to proceed |
| **T9** | `AGENTMEMORY_TOOLS=all` (54 tools) blowing the client's context with tool schemas | token cost per client, measured — `core` (8) is the control |
| **T10** | Keyless graph pass or `MAX_OBS_PER_SESSION`/decay silently pruning | observations disappear between sessions without an LLM call |

---

## 5. The probes

### M0 · Preflight (≈20 min)
`~/amprobe` under `domen`; pinned version recorded; engine binary fetch logged; ports 3111/3112/3113/49134
free (`ss -ltnp`); `agentmemory doctor` output saved verbatim; REST + viewer bind address recorded
(loopback vs LAN). **Gate:** server answers on 3111 and `doctor` agrees with the env you wrote.

### M1 · Keyless capture, recall, determinism (≈40 min) — the headline
Keyless: **no** LLM key, `EMBEDDING_PROVIDER` unset (BM25-only control). Feed **20 synthetic sessions** built
from this repo's real shapes and containing **exact identifiers** — ports (`9002`, `3111`, `6333`), numbers
(`515,786`, `0.34`, `512/64`), row ids (`HD-268`, `HD-387`, `#26`, `#28`), Slovene strings, and one
contradiction pair (fact X, later corrected) to see how superseded versions behave. Record:
capture rate (observations per session), recall hit@5 for 10 known-answer queries, **exact-identifier** recall
separately (this is where BM25 should beat a dense-only engine), latency, **determinism** = the same query 5×
→ identical ranking (and 2× after a restart), and **zero** spark calls proven from lan-litellm metrics.
**Gate:** capture ≥ 19/20 sessions; hit@5 ≥ 7/10; exact-identifier recall ≥ 8/10; ranking identical ×5.

### M2 · Vector leg on *our* encoder (≈30 min)
Raw probe first (§2.6 style): `POST http://10.10.1.30:4000/v1/embeddings` with `openai/bge-m3-vk` bare vs
prefixed, with and without `dimensions` → record which combos the leg accepts. Then set
`EMBEDDING_PROVIDER=openai`, `OPENAI_BASE_URL=http://10.10.1.30:4000/v1`, `OPENAI_EMBEDDING_MODEL=openai/bge-m3-vk`,
`OPENAI_EMBEDDING_DIMENSIONS=1024`, re-index the M1 corpus, confirm **dims=1024 in the index**, and re-run
M1's 10 questions. Report **BM25-only vs hybrid as a delta table** (hit@5, exact-id, latency, embedding tokens).
**Gate for "the leg is justified":** hybrid beats BM25-only by ≥ 2 hits overall **or** ≥ 2 on paraphrased
(no-exact-token) questions; otherwise recommend keyless and say the memory plane does not need LiteLLM (OQ-14).

### M3 · Is "central" real? (≈60–90 min) — the owner's actual question
One instance, **LAN-reachable** (ephemeral forwarder only — no IaC), `AGENTMEMORY_SECRET` set, `TEAM_MODE=shared`
with per-client `TEAM_ID`/`USER_ID`. Wire, in this order: **pi** (native), **OpenClaw** (plugin), **Hermes**
(plugin), **OpenHands** (MCP). Per client record: does capture fire (prompts **and** tool calls), what is the
tool-schema token cost (`all` vs `core`), can client A recall what client B captured, does scoping actually
separate users, and what happens with **4 concurrent clients** (latency, errors, interleaved sessions).
Also: viewer on 3113 reachable without auth? (T-class finding if yes.) And one **reboot/pkill resilience**
check: restart the instance, confirm nothing is lost and `doctor` still passes.
**Gate:** ≥ 3 of 4 clients capture-and-recall against the central instance with zero local stores. If a client
cannot be pointed off localhost, say which and why (T4) — that is the answer to OQ-12, not a footnote.

### M4 · Hermes' store (≈45 min)
Arm **H-A**: Hermes → central agentmemory instance. Arm **H-B**: Hermes → **Qdrant** via a Qdrant-capable
provider (`mem0` oss, or whichever provider the shipped build exposes; probe collections named `probe_hermes_*`).
For both: does Hermes **stop** writing its own `MEMORY.md`/`USER.md` (T5 — size them at the end, `wc -c`),
same 10 questions, and the **divergence test** (T6: does H-B answer something H-A cannot, and vice versa).
Record the dims trap outcome (T3/Mem0 1536 assumption) and the fact that **agentmemory itself can never target
Qdrant**. **Gate:** the owner's requirement ("not its own") is met only if the files stay empty — report the
exact knob or the absence of one.

### M5 · Cost, contention, ops (≈30 min)
Spark tokens per session (expect ~0 keyless; measure with any consolidation flags **on** as a separate row),
wall-clock per capture and per recall, latency under the M3 4-client load, `TOKEN_BUDGET 2000` injection
measured against **OV's 5,267 tok/query** on the same questions, snapshot/restore drill
(`SNAPSHOT_ENABLED`/`SNAPSHOT_DIR`, and whether it fits `scripts/backup-snapshot-trigger.sh` or needs its own
step), and the **exit cost**: what `agentmemory export` gives you and how you would rebuild the same memory in
another product (this is the answer to the "but it has no external DB" objection).

### M5b · Optional, only if time remains
`CONSOLIDATION_ENABLED` / `GRAPH_EXTRACTION_ENABLED` with the LLM on **spark** (thinking off, `spark/`
prefixed): tokens and wall-clock per 20 sessions, and whether quality (R1/R2/R4/R5 from `p3_score.py`) justifies
it. The OV lane's arm (a) vs arm (c) result — 887 tok/doc LLM summary losing to a free 154-token extract on the
retrieval-key rubric — is the prior to test, not to assume.

---

## 6. Decision rows — pre-registered, so the report cannot drift

| Outcome | What it means (write this in the report if the row fires) |
|---|---|
| M1 gates pass, M3 ≥ 3/4 clients central | agentmemory **is** the central memory plane; `services-ai.md:535` amended from "one instance per project" to **one instance + project/repo tags** (proposed text below); HD-336's placement (oldsrv) stands |
| M2 hybrid ≥ gate | memory depends on the `bge-m3` leg; document the dims pin in `docs/services-ai.md` next to HD-423's bare-name rule |
| M2 hybrid < gate | **keyless BM25 + graph** is the memory plane; memory stops depending on LiteLLM — a resilience win worth saying plainly |
| M3: a client cannot leave localhost | "central" fails for that client → per-seat instances + **no** cross-harness sharing; the per-project shape survives; file the upstream blocker (#523) as the reason |
| M4 H-B works, files stay empty | Hermes' memory = **Qdrant**; we now run **two** planes (agentmemory + mem0/Qdrant) and the report must state what they diverge on (T6) and who reconciles |
| M4 files cannot be emptied (T5) | the owner's ruling is **not implementable** on the shipped Hermes → Hermes joins the central plane (one plane) **or** the ruling is revisited; do not pick silently |
| Recall < 7/10 with the vector leg on | memory plane stays agentmemory **and** recall quality stays `rag-mcp`'s job (HD-268b unchanged) — i.e. memory ≠ retrieval |

**Proposed §9b amendment text (proposed only; do not apply):**
> `Memory = agent-memory.dev, ONE central instance on oldsrv (LAN, AGENTMEMORY_SECRET + per-client scoped
> token), records tagged project+repo; cross-project recall is a filter, not a second instance. Embeddings:
> bge-m3-vk @1024 via lan-litellm with OPENAI_EMBEDDING_DIMENSIONS pinned; LLM paths (consolidation/graph) stay
> off unless measured. OpenViking is deferred (lossy markdown index + LLM-tax per commit,
> reports/probe-ov-20260921.md); Mem0 stays in the OWUI plane.`

---

## 7. Blockers likely (report "confirmed/refuted + evidence", never a workaround)

1. **Egress** for the pinned `iii-engine` binary from the seat → if blocked, the lane cannot run (T8).
2. **MCP shim localhost hardcoding** on the installed version (T4) → central topology not achievable today.
3. **Hermes' always-on `MEMORY.md`/`USER.md`** (T5) → the owner's ruling has no knob.
4. **agentmemory cannot use Qdrant** at all (by design) → "Hermes on Qdrant" and "everyone on agentmemory" are
   **two stores**, not one plane; the brief does not get to pretend otherwise.
5. **Dims/param traps** (T1/T2/T3, and Mem0's 1536 assumption) — same family as HD-423/425; expect one of them.
6. **Licensing/policy note**: agentmemory is Apache-2.0 (unlike OV's AGPL) — if anything, this side needs no
   policy note; still record the version and the engine binary's own license.

## 8. Teardown (must be provable)

`pkill` by PID (then `-9`) for agentmemory + engine + any forwarder; `ss` shows 3111/3112/3113/49134 free;
`rm -rf ~/amprobe` and the real data dir (`AGENTMEMORY_DATA_DIR` / `~/.agentmemory`) — print `du -sh` before and
`ls` after; `probe_*` Qdrant collections deleted (list before/after); every per-client config edit restored
from the timestamped backup the connector made (and `git diff` clean in the repo); `AGENTMEMORY_SECRET` and the
`.amenv` deleted (`grep -c` for a zero count, no contents); `home/domen` size back to baseline; nothing in IaC,
no container, no systemd, no cron. Paste all of it into the report.

## 9. Report format (write it, commit it, then summarize in chat)

`reports/probe-agentmemory-<YYYYMMDD>.md`, evidence in `reports/probe-agentmemory-<YYYYMMDD>/` (configs with
secrets redacted, `doctor` output, the synthetic session set, per-client configs, M1/M2/M3/M4 raw JSON, and
**the same scoring scripts** so the numbers stay comparable). Sections: verdict · what ran · M1 (with the
determinism table) · M2 (dims table + BM25-vs-hybrid delta) · M3 (per-client matrix: capture / tool-token cost /
cross-client recall / concurrency) · M4 (H-A vs H-B + `wc -c` of Hermes' files) · M5 (cost, contention,
snapshot-restore, exit cost) · traps T1–T10 confirmed-or-refuted · OQ-12/13/14 answered in one line each ·
blockers · proposed decision rows (§6 table, text only) · teardown proof · **§ secrets and disclosures — say
what leaked, name the exact `vault kv put` / 1Password field to fix it, and never assume a rotation worked**.
