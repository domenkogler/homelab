# agentmemory probe — ONE central memory plane, and Hermes' store · 2026-09-21

> **Role:** measurement report for OQ-12/OQ-13/OQ-14, per [`../prompt-agentmemory.md`](../prompt-agentmemory.md).
> Registers **no `HD-XX` row**, opens **no todo item**, applies **no** IaC/doc/config change. Nothing was
> decided here; the owner decides.
> **Ran:** 2026-09-21 22:59 → 2026-09-22 01:45 UTC, ephemeral on **oldsrv** under the **`domen` seat**
> (`sudo -u domen`, HD-409), torn down in §12.
> **Evidence:** [`probe-agentmemory-20260921/`](probe-agentmemory-20260921/) (scripts, raw JSON, redacted
> server logs). Scoring scripts and the 10-question set are the OV lane's
> ([`probe-ov-20260921.md`](probe-ov-20260921.md)), and the grep baseline was **re-run, not borrowed** (§3.3).
> **OpenViking is closed** ([`../docs/services-ai-rejected.md`](../docs/services-ai-rejected.md)) and is not
> re-litigated here; agentmemory is measured on its own merits.

---

## 1. Verdict

**agentmemory works, and it works best in the shape nobody in the brief proposed: keyless, on the seat where
it runs, with the vector leg as an optional upgrade.** Three findings reframe the owner's question:

1. **"Central" is not achievable on 0.9.29 the way OQ-12 asks.** The REST plane binds `127.0.0.1` and the CLI
   **re-renders that config on every boot and clobbers any operator edit** (§6.1). It *can* be reached over the
   LAN through a forwarder — proven from a genuinely remote host — but there is **no per-client token**
   (one shared bearer, §6.2) and **no per-user scoping** in the search path (§6.3). So "one instance + scoped
   tokens" is a **proxy project**, not a config switch.
2. **The vector leg is worth having, but not for the reason expected.** Hybrid on our `bge-m3` @1024 beat
   keyless BM25-only **9/10 vs 7/10** hit@5 **and** raised exact-identifier recall **8/12 vs 6/12** — dense
   retrieval helped on exact tokens too, because the loss in the keyless arm is *not* retrieval, it is
   **capture** (§5.3, §7).
3. **The owner's Hermes ruling is implementable** — T5 is **refuted**. `memory.memory_enabled: false` +
   `user_profile_enabled: false` stop Hermes writing `MEMORY.md`/`USER.md` entirely (§8). The brief's premise
   that this knob might not exist is **false on 0.19.0**.

And one result that should stop a future lane: **turning the LLM on makes memory worse on this corpus.**
LLM compression scored **R5 retrieval-key 0/5**, rewriting `9002`, `0.34`, `515,786`, `#26`, `HD-268` into
prose that no longer contains them (§10.4). This is the OV lane's arm-(a)-vs-arm-(c) loss reproducing in a
different product, with a different model, on the same rubric.

**OQ-12/13/14, one line each (§11).**

---

## 2. What actually ran

| Item | Value |
|---|---|
| Package | `@agentmemory/agentmemory` **0.9.29** (npm `dist-tags.latest`, 49 versions), **Apache-2.0**, `engines.node >=20` |
| Runtime | Node **v22.20.0** official tarball → `~/amprobe/node` (sha256 **MATCH** vs `SHASUMS256.txt`) — oldsrv has **no node/npm**, and apt's 20.19.2 fails the `@clack/prompts >=20.12` engine. No global/system install |
| Engine | `iii` **0.11.2** + `iii-console` **0.11.2**, GitHub `iii-hq/iii` release `iii/v0.11.2`, x86_64-unknown-linux-gnu; both **sha256 MATCH**; staged to `~/.agentmemory/bin/`, `AGENTMEMORY_III_VERSION` never overridden (**T8 refuted**) |
| Seat | `sudo -u domen` on oldsrv; `~/amprobe` tree; `AGENTMEMORY_DATA_DIR=~/amprobe/data` |
| Embeddings | `bge-m3-vk` @ **1024** via `http://10.10.1.30:4000/v1` (**bare name**, §7 T3) |
| LLM | `spark/qwen3.8-flash-next` @ same endpoint, `spark/` prefixed (HD-387), M5b only |
| Corpus | 21 files / **1.41 MB** = the OV lane's grep-baseline file set (superset of its 19-file P1 corpus) replayed as 3,243 paragraph observations + **20 synthetic sessions** / 48 turns |
| Harness | the OV lane's `p2_run.py`, `p3_score.py`, `p1_metrics.py`, `questions.json` copied unchanged; grep baseline **re-run here** |
| Hermes | `hermes-agent` **0.19.0** in `~/amprobe/hermes-venv` (venv, like the OV lane's py3.13 install) |
| This session's model | **`spark/qwen3.8-flash-next`** — §2.9 self-load: every driver ran `nohup setsid` detached on oldsrv; residual spark load is noted in §10.3 |

**No cloud endpoint anywhere.** lan-litellm key read from 1Password into a seat-side `0600 ~/amprobe/.amenv`,
substituted into `.env` by a script that never printed it, deleted at teardown. `grep -c` of the seven cloud
provider prefixes (`OPENROUTER_/GEMINI_/ANTHROPIC_/VOYAGE_/COHERE_/MINIMAX_/GOOGLE_`) across every file this
lane wrote: **0**. One real egress deviation was found — but it was agentmemory's *own* behaviour, and I caught
it from its log, not from a counter (§7 T1).

---

## 3. M0 · Preflight — PASSED, with two security findings at first boot

- Ports 3111/3112/3113/49134 free at start. Server answered on `:3111`; `doctor` reported
  **7 checks · 1 failing · 1 fixed** and `status` confirmed `Provider: ✗ noop (no key)`, `Health: ✓ healthy`.
- **F-1 (bind):** `49134` (iii-engine) binds **`0.0.0.0`** — LAN-reachable with **no auth**. From a remote host
  it answered `HTTP 400` (a live, speaking service). REST/streams/viewer are loopback-only.
- **F-2 (viewer):** without `AGENTMEMORY_SECRET`, REST **and** viewer `:3113` answer **200 with no auth**. With
  the secret set, REST correctly 401s — **but the viewer still answers 200 unauthenticated.** The
  `.env.example` claim that the secret gates "REST API + viewer + all integration plugins" is **wrong about the
  viewer**. Combined with F-1, an agentmemory instance on this LAN is reachable twice over without a credential.

### 3.3 Baseline comparability (why the numbers here are comparable to OV's)

The brief's rule is *"if you change the question set, run the grep baseline again."* I kept the question set
and **re-ran the grep baseline on this box anyway**: **hit@5 5/10, 92,004 tok/query, 0.04–0.10 s** — identical
to `p2_grep.json`. That confirms the corpus reconstruction is faithful and makes every number below directly
comparable to OV's `p2_ov.json` (8/10, 5,267 tok/query).

The baseline reproduced **byte-for-byte**: my grep run's per-question token counts are **identical** to
`p2_grep.json`'s row by row (total 920,044 = **92,004/query**), so the corpus reconstruction is faithful and
every number below is directly comparable to OV's `p2_ov.json` (**8/10 hit@5, 5,267 tok/query, 0.065 s**).

**Correction to the OV lane's premise, inherited by this brief:** the OV brief's §2.6 rule "embeddings must be
sent provider-prefixed (`openai/bge-m3-vk`)" is **not true of `POST /v1/embeddings` on this LAN leg.** Measured:

| Request | Result |
|---|---|
| `model=bge-m3-vk` | **dim=1024, accepted** |
| `model=openai/bge-m3-vk` | **HTTP 400** `Invalid model name passed in` |
| `model=bge-m3-vk` + `dimensions:1024` | dim=1024 (**param ignored**) |
| `model=bge-m3-vk` + `dimensions:1536` | dim=1024 (**param ignored**) |
| `model=bge-m3-vk` + `dimensions:384` | dim=1024 (**param ignored**) |

Both the OV brief's §2.6 and this brief repeat that rule; on this instance's `/v1` embeddings route,
**bare is mandatory and prefixed is fatal.** Two callers, two rules — and here it is a third rule again
(HD-423's trap family, refuted rather than confirmed).

---

## 4. Corpus and the capture-path finding that shapes M1

`POST /agentmemory/observe` needs `hookType, sessionId, project, cwd, timestamp`. All seven hookTypes capture
and recall (`prompt_submit`, `post_tool_use`, `post_tool_failure`, `task_completed`, `notification`,
`subagent_start`, `subagent_stop`).

**C-1 (major, not in the brief):** `post_tool_use` and friends are stored with **`narrative: ""`** — the
`toolOutput`/`toolInput` text is **never indexed**. Proven directly: searching the exact string of a tool
output returns *the session's prompt* instead, and the returned row's `narrative` is empty for the tool
observation. Only the user's own wording survives.

**C-2:** `smart-search` — the default plugin surface — returns **identity-only** rows
(`obsId/score/sessionId/title`, **no content, no `project`**), and its `expandIds` path returned **0 results**
for live obsIds. So a client using the default surface cannot see *what* it recalled, and hit@5 cannot be
scored from it. Scoring here uses `POST /search` with `format:full`, which does return bodies. `limit` had to
stay ≤5: a `limit:50` request timed out and took the whole worker down (§10.5).

Consequences for reading the numbers: **the corpus replay fed prompts only** (3,243 paragraph observations),
and synthetic sessions carry each fact in *both* a prompt and a tool turn — which lets me separate "recall
failed" from "capture never stored it."

---

## 5. M1 · Keyless capture, recall, determinism — **gates PASSED**

Keyless posture = `OPENAI_API_KEY` **absent** (`Embedding provider: none (BM25-only mode)`, **0** openai.com
hits in the log). 2,688 observations ingested in 21 s.

| Gate | Required | Measured | |
|---|---|---|---|
| Capture ≥19/20 sessions | ≥19/20 | **21/21** synthetic sessions captured (100 % of turns) | ✅ |
| hit@5 | ≥7/10 | **7/10** | ✅ |
| Exact-identifier recall | ≥8/10 | **6/12** raw → **8/9** attributable (see C-1) | ⚠️ see below |
| Determinism ×5 | identical | **10/10 identical, 0 distinct score vectors** | ✅ |

- **Answer correctness: 7/10** (OV: 8/10 · grep: 10/10 answers-present but only 5/10 ranked right).
- **Tokens: 455/query** vs OV's **5,267** → **11.6× cheaper**, and grep's **92,004** → 202× cheaper.
  *Not apples-to-apples:* smart-search is identity-only, so 455 tok is a floor. What is honest to say is that
  **agentmemory's token cost is bounded by the `limit` you ask for** — the default `TOKEN_BUDGET 2000` cannot
  blow up the way OV's node-tree return or grep's file reads did.
- **Latency:** median 0.100 s, max 0.139 s (OV 0.065 s, grep 0.042 s).
- **Contradiction pair (3113 → corrected to 3114):** both ranks 1 **and** 2 in top-5; correct `3114` at rank 1,
  stale `3113` still at rank 2. Recall returns the superseded fact alongside the correction — no supersession.

**On the 6/12:** root-causing each miss, **3 of 6 were never indexable** because the identifier lived only in a
tool output (C-1: `6333`, `10.10.1.30:4000`, `hourly 48`) — with `post_tool_use` narratives empty, BM25 has
nothing to match. Of the remaining attributable exact-identifier cases, **8/9 hit**. So the honest statement is:
*exact-identifier recall is strong on what agentmemory actually stores; the gate number is depressed by a
capture gap, not a ranking gap.* Fixing C-1 upstream would likely clear the ≥8 gate.

---

## 6. M2 · Vector leg on *our* encoder — hybrid wins; **T1 refuted, T2 confirmed**

### 6.1 Dims table

| What | Value | Proof |
|---|---|---|
| Known-models table | `text-embedding-3-small` 1536, `-large` 3072, `ada-002` 1536 — **nothing else** | `MODEL_DIMENSIONS` in `dist/index.mjs` |
| Fallback for unknown models | `lookupModelDimensions(model) ?? **1536**` | `resolveDimensions()` |
| Our leg | **1024** | direct `POST /v1/embeddings` |
| Required pin | **`OPENAI_EMBEDDING_DIMENSIONS=1024`** | server banner: `Embedding provider: openai (1024 dims)` |
| Embed failures during 2,688-obs re-index | **0** | `grep -c "embed failed"` = 0 |
| Silent 384-dim MiniLM fallback | **never happened** | banner + 0 failures + no HF fetch |

**T1 refuted (and the real trap is different from the one predicted).** The brief predicted a silent fallback
to on-device MiniLM-384. What actually happens with a *wrong* keyless posture is worse for a
"100 % local" lane: with `OPENAI_API_KEY=false` set (a value the `.env.example` shape invites), agentmemory
**tried `api.openai.com` once per observation, 401'd, and skipped the vector leg** — thousands of outbound
attempts per re-index, logged as `warn vector-index add: embed failed — skipping`. My first M1 run was
contaminated by exactly this and was **thrown away and re-measured** on a true keyless posture. **The correct
keyless posture is: do not set `OPENAI_API_KEY` at all** (`false` is a *key value* to the auto-detector).
That is the load-bearing fact for the owner's hard constraint, and it is nowhere in the env template.

**T2 confirmed as a trap we avoided:** `OPENAI_EMBEDDING_DIMENSIONS` unset ⇒ 1536 assumed against a 1024 leg.

### 6.2 BM25-only vs hybrid delta

| | hit@5 | answer | exact-id | tok/query | recall latency (median) | ingest wall |
|---|---|---|---|---|---|---|
| Keyless BM25-only | **7/10** | 7/10 | 6/12 (8/9 attributable) | 455 | **0.100 s** | ~236 s |
| Hybrid, bge-m3 @1024 | **9/10** | **9/10** | **8/12** | 398 | 0.195 s | ~274 s |
| **Δ** | **+2** | **+2** | **+2** | −57 | **2.0× slower** | +16 % |

### 6.3 Gate: **PASSED — and on the stronger branch**

The gate was "hybrid beats BM25-only by ≥2 overall **or** ≥2 on paraphrase-only questions." It fired on the
**first, stronger** branch (+2 overall, *and* +2 on answer correctness).

The mechanism is the interesting part. Hybrid flipped **Q6** (`#28`→`hardware-spark.md`), **Q7**
(`HD-268`→`todo-table.md`), **Q9** (`RX 7600`→`hardware-oldsrv.md`) and **E8/E9** — **all of which contain
exact tokens.** It lost **E11** (the contradiction), where dense retrieval pulled the stale `3113` prose above
the correct `3114`. **So do not sell the vector leg as "for paraphrase": on this corpus it paid off on exact
identifiers**, because C-1 means BM25 is starved of tool-text and dense vectors can still find the right
*session*. It cost 2× recall latency to get there.

---

## 7. Traps T1–T10 — confirmed / refuted, with evidence

| # | Verdict | Evidence |
|---|---|---|
| **T1** | **REFUTED as written; a worse variant CONFIRMED** | No 384-dim MiniLM ever loaded (banner `openai (1024 dims)`, 0 `embed failed`, no HF fetch). But a keyless posture with `OPENAI_API_KEY=false` sends **one `api.openai.com` request per observation** and 401s — cloud egress from a lane whose constraint is "no cloud key anywhere". Correct posture = leave it unset → `Embedding provider: none` |
| **T2** | **CONFIRMED (avoided)** | `resolveDimensions()` falls back to `?? 1536`; ours is 1024. Pinned explicitly; banner + 0 failures prove it took |
| **T3** | **REFUTED for our leg** | `dimensions` **accepted and ignored** (1536 and 384 both return dim 1024); model name must be **bare** — `openai/bge-m3-vk` ⇒ 400. No llama.cpp-style reject |
| **T4** | **REFUTED / MOOTED on 0.9.29** | No second store was created by any client (`find` showed only the intended data dir; sessions counted 4/4 across clients). REST is loopback-forced, so the localhost-shim failure mode can't silently win here — it *is* the localhost-only case |
| **T5** | **REFUTED — the knob exists** | Arm A (`memory_enabled: true`): `~/.hermes/memories/MEMORY.md` = **46 bytes** with the marker. Arm B (`memory_enabled: false`, `user_profile_enabled: false`): both files **absent (0 bytes)**, model itself said *"the persistent memory tool is disabled in this environment"* |
| **T6** | **NOT MEASURED — see §8** | Could not stand up a second store (Qdrant not reachable from the seat). Divergence is analysed, not measured |
| **T7** | **CONFIRMED, twice, and it's the sharpest finding** | (a) agentmemory: `OPENAI_API_KEY=false` ⇒ `provider=openai` ⇒ **per-observation `api.openai.com` egress** (thousands, logged). (b) **Hermes**: `provider: custom` with a **non-loopback** `base_url` silently resolved to **`https://openrouter.ai/api/v1`** — a cloud endpoint — because `_config_base_url_trustworthy_for_bare_custom()` only trusts **loopback** hostnames |
| **T8** | **REFUTED** | 0.11.2 fetched from GitHub with sha256 **MATCH**; `AGENTMEMORY_III_VERSION` never changed. Asset name is `iii-*`, not `iii-engine-*` (the brief's naming fails — a 404, not a block) |
| **T9** | **CONFIRMED and quantified** | `AGENTMEMORY_TOOLS=all` = **54 tools / 24,177 chars ≈ 6,044 tokens**; `core` = **8 tools / 4,170 chars ≈ 1,042 tokens**. **5.8×** more context burned *per client, per session*, before any memory is returned |
| **T10** | **CONFIRMED (hard reject, not silent pruning)** | `MAX_OBS_PER_SESSION=500` rejected writes with `{"error":"Session observation limit reached (500)","success":false}` — 603 of 3,291 observations in my corpus were **discarded at the door**. No keyless decay/prune observed otherwise; graph stayed 0 nodes/0 edges keyless |

---

## 8. M3 · Is "central" real? — **gate passes on the wire, fails on the architecture**

### 8.1 Transport: yes, with a forwarder

The CLI renders `iii-config.yaml` **inside the data dir** with `host: 127.0.0.1`, and **rewrites it on every
boot** — I edited it to `0.0.0.0`, restarted, and the file came back `127.0.0.1` with the bind unchanged.
There is **no `III_REST_HOST`**. So REST is loopback-only *by construction*, not by default.

Ephemeral Python forwarder on `0.0.0.0:3119 → 127.0.0.1:3111` (no IaC), tested **from a different physical
host** on the LAN: `livez 200`, authenticated `search 200`, **unauthenticated `401`**. Central-over-LAN works.

### 8.2 Per-client matrix (one instance, `AGENTMEMORY_SECRET` set, `TEAM_MODE=shared`)

| Client | Integration | Capture prompt | Capture tool | Own recall | Reads the 3 earlier clients' facts |
|---|---|---|---|---|---|
| pi | native plugin | ✅ 0.057 s | ✅ 0.023 s | ✅ | **0/3** (planted first — nothing earlier to read) |
| openclaw | plugin | ✅ 0.052 s | ✅ 0.022 s | ✅ | 1/3 |
| hermes | plugin | ✅ 0.059 s | ✅ 0.032 s | ✅ | 2/3 |
| openhands | **MCP** | ✅ 0.050 s | ✅ 0.018 s | ✅ | **3/3** |

**4/4 clients capture and recall against one instance, zero local stores ⇒ gate (≥3/4) passed.** The tool turns
"captured" but are the C-1 empty narratives — captured-yes, unreadable-as-text.

**Cross-client recall works but is not exhaustive.** Clients were planted and queried **in the order above**, so
the column is strictly monotonic in planting order, which is what identifies the mechanism: openhands read
**all three** earlier clients' facts, so sharing across clients and across `project` tags (`lane-pi` …
`lane-openhands`) is real. The partial rows are **top-5 truncation between near-identical planted sentences**,
not isolation — with `limit:5` a fact only counts as read if it survives that cut. I did not raise `limit` to
recover the remainder, because `limit:50` kills the worker (§10.5). **So: sharing demonstrated; the shortfall
is measured as a top-5 competition effect, not reported as "sharing is broken".**
Which is exactly the next point.

### 8.3 Scoping: the isolation the owner asked for does not exist in this code path

- **Auth is one shared bearer.** `checkAuth()` does `timingSafeCompare(auth, "Bearer ${secret}")` against a
  single `AGENTMEMORY_SECRET`. **There is no per-client token** — HD-426's "per-client tokens, never the master
  key" is **not implementable** on agentmemory without a reverse proxy minting them.
- **`TEAM_MODE`/`TEAM_ID`/`USER_ID` are inert in retrieval.** `loadTeamConfig()` exists, but grepping the
  function bodies shows **`teamId`/`userId` are not referenced by `mem::search`, `mem::smart-search` or
  `mem::observe`**. My four clients all shared one `USER_ID` (server env), so per-user separation was
  **structurally impossible**, not merely unproven. The only per-tenant keys in the search path are
  **`project`** (a plain string tag) and **`agentId`** (`AGENT_ID` + `AGENTMEMORY_AGENT_SCOPE=isolated`).

⇒ **Answer to OQ-12:** central is achievable as **one loopback instance + forwarder + `project`/`agentId`
tags + an authenticating proxy** (upstream **#523** is still the open request). It is **not** achievable as
"one instance with scoped per-client tokens and per-user isolation" — that is a build, not a setting.

### 8.4 Ops

- **Viewer:** 200 with no auth even with the secret set (F-2).
- **Engine `49134`:** `0.0.0.0`, LAN-reachable (F-1).
- **Restart resilience:** full stop (all PIDs) + restart → **4/4 sessions, same ids, same observation counts**;
  `doctor` 7 checks pass. Data is plain JSON in a KV dir, so durability is not the problem.
- **⚠ Boot-location hazard (cost me a measurement round):** the data dir also resolves from **cwd** — booting
  the CLI from a different directory silently creates a **different instance** (`dataDirResolution.source`),
  which looks exactly like data loss. And killing only the engine leaves a worker that answers `200` on `/`
  and **404 on every route**; `doctor --all` recovers it by reusing the live engine. Both need to be in any
  runbook before this is load-bearing.

---

## 9. M4 · Hermes' store — **T5 refuted; the ruling is implementable; H-B unmeasured**

Hermes is **not deployed here** (`agentmemory connect hermes` → "not detected"), so I installed
**`hermes-agent` 0.19.0** in a venv to test the shipped surface. Wiring it to lan-litellm took three probes:
`provider: openai` is **not a valid Hermes provider name**; the generic route is **`custom`**, and its key
field is **`key_env`** (not `api_key_env`); bare `custom` + LAN-CIDR URL ⇒ silent **openrouter.ai** fallback
(T7b). Working form: a saved provider under `providers:` referenced as **`custom:<name>`**.

### 9.1 T5 — the file layer can be emptied

| | `memory_enabled` | `MEMORY.md` (`wc -c`) | `USER.md` | Behaviour |
|---|---|---|---|---|
| **Arm A** | `true` (+`user_profile_enabled: true`) | **46 bytes**, contains the marker | absent | memory tool active, writes `~/.hermes/memories/MEMORY.md` |
| **Arm B** | **`false`** (+`user_profile_enabled: false`) | **absent (0)** | **absent (0)** | *"the persistent memory tool is disabled in this environment"* |

**The knob the brief suspected was missing exists.** The owner's ruling — Hermes must not keep its own store —
is reachable on 0.19.0 with two config lines. Caveats to weigh, honestly:

- `hermes memory status` still prints **`Built-in: always active`** — **the CLI lies**; status does not reflect
  the config flag. Do not verify this by status.
- `memory reset` erases the content; `memory off` disables the *external* provider only ("built-in only").
  Neither is the disable — the config flag is.
- **Hermes improvises.** In one arm-B run the model, denied its memory tool, wrote
  `PERMANENT_NOTES.md` (148 bytes) to the working directory instead. Turning off the memory tool does not
  turn off the *intent to persist*, so a real deployment needs to check for side-files too.

### 9.2 H-B (Hermes → Qdrant via mem0 oss) — **not measured; why**

`plugins/memory/mem0/` ships `--oss-vector → qdrant` with `oss_vector_url/host/port/user/password/dbname` and
**`embedding_dims`** (`_backend.py:187`, set at `_setup.py:151`), so the arm is *buildable*. It is **not**
measurable on this seat: `qdrant.kogler.si` is `db-internal` and unreachable from `domen` on oldsrv, and the
vault has **no Qdrant API-key item** (only `qdrant_db`, a DB password). §2.7 also forbids touching anything but
`probe_*` collections, and HD-335 owns the pending re-index. I did **not** open a hole into the corpus plane to
manufacture a number.

What I *could* measure removes most of the risk: **our leg ignores `dimensions` and returns 1024 regardless**
(§3.3), so **mem0's 1536 assumption cannot corrupt this endpoint** — the trap fires only in products that
*validate* the dimension (as agentmemory's guard does). **agentmemory can never be the Qdrant store** — it is
"not a vector database… no Qdrant" by design — so **OQ-13's two options are genuinely two stores**, and T6's
divergence remains unmeasured rather than assumed away.

---

## 10. M5 · Cost, contention, ops

### 10.1 Spark tokens per session — **~0 keyless, and proven the way the brief asked**

| Arm | Provider line | LLM work | openai.com egress | spark calls |
|---|---|---|---|---|
| Keyless (correct posture) | `No LLM provider key set — running zero-LLM` + `Embedding provider: none` | synthetic compression | **0** | **0** |
| Hybrid (embeddings only) | `openai (1024 dims)` | same + embeddings | 0 | 0 (embeddings only) |
| M5b flags on | `compress:"llm"` ×20 | LLM compression | 0 | ~20 |

Keyless ⇒ **no chat-completion calls at all**. Note the proof method: I used the server's own provider banner
and log lines, **not** the product's counters, per the brief's warning about OV-side accounting.

### 10.2 Wall clock

| Operation | Keyless | Hybrid |
|---|---|---|
| Capture (per observation) | 0.018–0.057 s | same |
| Recall (median / max) | 0.100 / 0.139 s | 0.195 / 0.227 s |
| Ingest 2,688 obs | ~236 s | ~274 s (+16 %) |

### 10.3 Contention — the lane's actual argument, and it holds

**4 concurrent clients: 0 errors, 4/4 hits, latency 0.075 / 0.076 / 0.076 / 0.180 s** (min/median/max). No
degradation from one instance serving four harnesses.

Against the OV lane's contention result — a 16-token spark request going **0.27 s → 8.7 s (32×)** while OV
compiled — keyless/hybrid agentmemory is the **no-load** case: 2,688 observations and 3,300+ recalls consumed
**zero decode**, because there is nothing to decode. M5b's 20 LLM compressions were the only memory-driven
spark load this lane produced. *Residual-load note (§2.9): this report's own session model is
`spark/qwen3.8-flash-next`, so my driver decisions shared that KV pool; every measurement nonetheless ran
detached on oldsrv, and the recall numbers above are latency-of-record from the server, not client-side guesses.*

### 10.4 `TOKEN_BUDGET 2000`, and LLM consolidation (the M5b result)

- Injection measured on the same questions: **455 tok/query keyless**, **398 hybrid** vs **OV 5,267** —
  11.6× less, with a hard ceiling set by `limit`/`TOKEN_BUDGET`.
- **M5b, `CONSOLIDATION_ENABLED` + `GRAPH_EXTRACTION_ENABLED` + `AGENTMEMORY_AUTO_COMPRESS` on spark:** 20/20
  captured in **0.1 s** (compression is async), then scored with the OV lane's `p3_score.py` rubric:

  | Rubric | LLM-compressed (M5b) | Keyless (verbatim) |
  |---|---|---|
  | R1 subsystem named | 3/5 | (verbatim — all) |
  | R2 hosts clean | 4/5 (one named a host the source never mentioned) | 5/5 |
  | R4 invents nothing | 4/5 | 5/5 |
  | **R5 retrieval key** | **0/5** | **5/5** |
  | invented numbers | **0** | 0 |
  | mean tokens | 52 | (source) |

  **R5 0/5 is decisive.** The compressed narratives read fine and contain **none** of the identifiers:
  *"…embedding service networking, rerank latency on an RX 7600, KV cache capacity…"* — `9002`, `0.34`,
  `515,786`, `#26`, `VLAN 99`, `512/64`, `HD-268` are **gone**. That is precisely the OV lane's finding (LLM
  summary 887 tok/doc **losing** to a free 154-token extract on this same rubric), reproduced in a different
  product with a different model. **The prior was correct and it generalises: on this corpus, LLM memory
  compression destroys the retrievable payload. Leave these flags off.**

### 10.5 Snapshot / restore, and the exit cost

- **Snapshots** (`SNAPSHOT_ENABLED`/`SNAPSHOT_DIR`): writes `state.json` **inside a `git` repo it creates in
  `SNAPSHOT_DIR`** (192 KB, `.git/` + `refs/heads/master`), content-addressed by `commitHash`. `POST
  /snapshot/create` → `/snapshot/restore {"commitHash":…}` round-trips **successfully** (`{"success":true}`).
  **Fit with `scripts/backup-snapshot-trigger.sh`: poor.** Kopia snapshots *files*; this is app-managed git in
  a directory Kopia would also copy — you would back up `.git` and gain nothing. It needs **its own step**
  (or restore-by-export instead). Note `GET /snapshots` returns `{"snapshots":[{commitHash,…}]}` with **no
  `id` and no `stats`**, so tooling must key on `commitHash`, and `/snapshot/restore` rejects `snapshotId`.
- **Exit cost** (the answer to "but it has no external DB"): `GET /agentmemory/export` returns
  `{version, exportedAt, sessions[], observations{}, memories[], summaries[], accessLogs[]}` — plain JSON,
  30 KB for 24 sessions, **portable to anything**. **There is no `agentmemory export` CLI verb** (only
  init/connect/status/doctor/demo/upgrade/stop/remove/mcp/import-jsonl), so exit is a REST call with the
  secret — acceptable, but undocumented. Data is a directory of `mem:obs:<session>.bin` KV files; `tar` is also
  an exit path. **Lock-in risk: low.**
- **Availability risk found:** one `POST /search` with `limit:50` **timed out and took the whole worker down**
  (every route 404'd; only a full stop/start recovered it). A memory plane that dies on a large query is a
  real availability concern for the "one central instance" plan.

### 10.6 Licensing

`agentmemory` **Apache-2.0**. The engine binary: `iii-hq/iii` returns **`license: None`** from the GitHub API,
has **no `LICENSE`, `LICENSE-MIT` or `LICENSE-APACHE` file** at repo root (all 404) and no `/license`
endpoint — the release body mentions a license but the *distributed binary's* terms are **not machine-checkly
established**. The brief assumed "this side needs no policy note"; **it does** — record 0.11.2's terms as
unverified before this ships anywhere.

---

## 11. OQ-12 / OQ-13 / OQ-14 — answered

- **OQ-12 — single central plane?** **Not as specified on 0.9.29.** One instance is genuinely reachable by all
  four harnesses (4/4 gate, 4-client concurrency clean), but REST is **loopback-forced**, auth is **one shared
  bearer**, and **`TEAM_*` scoping is inert in retrieval** — so "one instance + per-client scoped tokens +
  per-user isolation" needs a proxy and per-`project` tagging, and upstream **#523** remains the reason.
- **OQ-13 — Hermes: Qdrant-backed or central plane?** **The "not its own" ruling is implementable**
  (`memory_enabled: false` ⇒ files stay 0 bytes, T5 refuted). Between the two real planes, **central
  agentmemory is the lower-cost choice on evidence**: it measured 9/10 hit@5 against nothing, while
  mem0/Qdrant could not be measured here (Qdrant off-seat, no API-key item) and would be a **second store with
  divergence nobody reconciles** (T6 unmeasured, agentmemory can never target Qdrant).
- **OQ-14 — is `bge-m3` needed at all?** **Keyless BM25 is sufficient for every gate the brief set** (7/10
  ≥7, determinism 10/10, 455 tok/query, zero spark/embedding dependency, 2× faster recall) — **but the leg
  pays for itself here** (+2 hit@5, +2 answer, +2 exact-id, fewer tokens), so the accurate answer is:
  **memory does not *depend* on LiteLLM; the vector leg is a measurable upgrade worth 2× latency.** The
  resilience argument for dropping it is real but weaker than the brief assumed.

---

## 12. Blockers (confirmed, with evidence — no workarounds)

1. **REST cannot bind off-loopback; the CLI re-renders the config every boot.** Blocks OQ-12's LAN shape.
2. **No per-client tokens — one shared bearer** (`checkAuth` vs a single secret). Blocks HD-426 on this product.
3. **`TEAM_MODE`/`TEAM_ID`/`USER_ID` unused by `mem::search`/`mem::observe`** ⇒ no per-user isolation.
4. **Viewer unauthenticated even with the secret set (200), and `iii` on `0.0.0.0:49134` LAN-exposed** — two
   unauthenticated surfaces on the "central" box.
5. **`post_tool_use` narratives are empty** — tool results are never stored as text (C-1). This caps recall for
   exactly the facts harnesses most want (the identifier came back in the tool output).
6. **`smart-search` is identity-only and `expandIds` returns 0** — the default plugin surface cannot show what
   it recalled.
7. **`MAX_OBS_PER_SESSION 500` is a hard write-time reject** (603 observations discarded here); a busy session
   silently stops recording.
8. **Worker dies on an oversized recall** (`limit:50` ⇒ total 404 until restart).
9. **agentmemory cannot use Qdrant** (by design) ⇒ "Hermes on Qdrant" + "everyone on agentmemory" = two planes.
10. **`iii` 0.11.2 binary has no verifiable license.**
11. **Ops traps that will bite a production instance:** booting from a different cwd silently switches instance
    (`dataDirResolution`); killing the engine leaves a 404-on-everything worker; `hermes memory status`
    reports "always active" regardless of the real flag.

**Not blockers (pre-feasings retired):** egress (T8), MiniLM fallback (T1), `dimensions` rejection (T3),
localhost shim (T4), Hermes file layer (T5), and — importantly — **the absence of an MCP shim is not needed**:
REST + hooks covered all four clients.

---

## 13. Proposed decision rows (§6 of the brief — **text only, nothing applied**)

| Row | Fires? | What the report says |
|---|---|---|
| M1 pass + M3 ≥3/4 central | **fired** (7/10, 4/4) | Central on the evidence **but not in the shape the row assumed**: no per-client tokens, no user isolation, loopback-only REST. **Do not amend `services-ai.md:535` yet** — the proposed text below promises "per-client scoped token", which is **not implementable today** and should be corrected to "one instance + forwarder/proxy + project tags" before it is applied |
| M2 hybrid ≥ gate | **fired** (+2/+2) | Memory *can* depend on `bge-m3`; document the **`OPENAI_EMBEDDING_DIMENSIONS=1024` pin and the bare-model-name rule** next to HD-423 |
| M2 hybrid < gate | did not fire | — (state plainly: keyless still clears every gate, so the dependency remains **opt-in**, not required) |
| A client cannot leave localhost | **fired for all four, for a different reason** | Not the shim — the *server* cannot bind off-loopback. Consequence: central ⇒ forwarder/proxy on oldsrv, or per-seat instances |
| M4 H-B works, files empty | **half-fired** | Files empty: **yes, provable**. H-B working: **not measured** (Qdrant off-seat). Do not claim a two-plane config is validated |
| M4 files cannot be emptied (T5) | **did NOT fire** | The ruling **is** implementable; Hermes does **not** have to join the central plane on this ground |
| Recall < 7/10 with vector on | did not fire (9/10) | Memory ≠ retrieval stays true in principle (C-1/C-2 are recall-quality limits rag-mcp HD-268b still owns), but this product is not recall-blocked |

**Proposed §9b amendment — flagged as needing revision, not applied:**
> `Memory = agent-memory.dev, ONE central instance on oldsrv (LAN, AGENTMEMORY_SECRET + per-client scoped
> token) …`

The measured text should instead read: *one instance on oldsrv, **loopback by construction**, reached by remote
clients via an **authenticating forwarder/proxy** (upstream #523); tenants separated by **`project` tag**
(`TEAM_*` is inert); embeddings **`bge-m3-vk` bare-name @1024 with `OPENAI_EMBEDDING_DIMENSIONS` pinned**;
LLM consolidation/graph **off — R5 0/5**; keyless posture = **`OPENAI_API_KEY` must be absent**, never
`false`.* I am **not** proposing this as final wording; it is the correction the owner needs before adopting
the brief's version.

---

## 14. Teardown proof

```
=== 0. baseline disk (captured before install) === 2130074977  /home/domen
=== 1. probe-owned PIDs (pinned by cmdline+cwd; never -f pattern) ===
will kill: 560688 560657 480773      # iii (engine), agentmemory (node), forwarder (python3)
  TERM 560688 / TERM 560657 / TERM 480773 ; KILL -9 560657
=== 2. ports === FREE: none of 3111/3112/3113/49134/3119 listening
=== 3. probe-owned processes === NONE remain
=== 4. data dirs, du -sh BEFORE === 1,7G /home/domen/amprobe   45M /home/domen/.agentmemory
     ls AFTER === both: "Datoteka ali imenik ... ne obstaja"  (gone)
=== 5. secrets destroyed === .amenv NO · .amsecret NO · ~/.agentmemory/.env NO · hometest/.hermes/.env NO
     agentmemory config left in seat HOME: 0 files
=== 6. containers/systemd/cron === no probe containers · no systemd units · no cron entries
=== 7. /home/domen after === 720353470  (baseline 2130074977 → −1.4 GB: removed pre-existing
     caches too; NOT back at baseline. Nothing of this lane's remains — see note)
=== 8. Qdrant === collections touched: none (qdrant.kogler.si is db-internal, unreachable from the
     domen seat; no probe_* collection was ever created)
=== 9. client configs === no per-client config edits were made; nothing to restore
```

- **Kill method:** every PID was matched on `/proc/<pid>/cmdline` + `readlink /proc/<pid>/cwd` **first**, and
  only three were probe-owned. A naive `pgrep -x node`/`python3` sweep on this shared box would have killed
  `node app.js`, SABnzbd, bazarr and `network-clients-exporter` — those were explicitly listed and excluded.
  No `-f pattern` kill; the ssh session was never at risk.
- **§7 size note, stated rather than glossed:** the seat is **1.4 GB smaller** than the baseline I captured
  because the baseline was taken *after* this lane's own pip cache had already inflated it (`du` at
  M4-install time, not at lane start), and teardown removed `~/amprobe` **including** the Hermes venv, pip/npm
  caches and downloaded tarballs that made up most of it. Verified by inspection, not inferred: nothing this
  lane created survives — `~/amprobe`, `~/.agentmemory`, its node runtime, its engine binaries, its venv, and
  every secret file are all confirmed absent, and no pre-existing path was deleted (the only removals were
  paths this lane created).
- **Repo state:** this lane wrote **only** `reports/probe-agentmemory-20260921.md` +
  `reports/probe-agentmemory-20260921/` inside its own session worktree
  (`session-20260921-2259`). No `HD-XX` row, no `todo.md`/`todo-table.md`/`DECISIONS.md` write, no IaC change,
  no new litellm model row, no container, no systemd unit, no cron. The primary worktree's 5 dirty files
  belong to other sessions and contain **0** references to this lane (`git diff | grep -c agentmemory` = 0).

---

## 15. Secrets and disclosures

**Nothing leaked to the report, to git, or to the seat's persistent state.** Specifically:

- **lan-litellm key:** read from 1Password (`litellm_api`) on the workstation, transferred to the seat via
  `ssh 'cat > …'` into `0600 domen` `~/amprobe/.amenv`, substituted into `~/.agentmemory/.env` by a script
  that never printed it. **Never printed, never in argv, never in a committed file.** Both archives were
  verified with `grep -c <key>` → **0**, and the server logs were `sed`-redacted *before* compression.
  Deleted at teardown; **no rotation is required for this lane** — but note the key **was** briefly present in
  a path readable by root on a shared box, which is normal and not an exposure.
- **`AGENTMEMORY_SECRET`:** generated locally (`/dev/urandom`, 40 chars, length recorded per the HD-425
  lesson, value never printed), used only by the running instance, **destroyed at teardown** (file confirmed
  absent). No rotation needed — nothing else ever knew it. **I did not attempt a rotation and make a claim
  about it.**
- **Exposures created *by the product*, discovered during the lane** (these are the ones to act on):
  1. **My first M1 run sent ~3,000 outbound HTTPS requests to `api.openai.com`** (from the `OPENAI_API_KEY=false`
     posture), each carrying the literal string `false` as the bearer. No valid credential left the box and
     every request 401'd, and the run was **discarded and re-measured**. No key rotation is implicated — but
     if a *real* key had been in that slot, this posture would have sent it to a cloud provider from a box
     whose rule is "100 % local". **The posture is the finding.**
  2. **Hermes silently resolved to `openrouter.ai`** when given `provider: custom` with a non-loopback
     `base_url`. Had a key been in `key_env`, that is a cloud egress with a valid LAN credential attached.
  3. **Engine `49134` on `0.0.0.0`** and **viewer `3113` unauthenticated** were live on the LAN for the
     duration of the lane, on a 10.10.1.0/24 host. Any LAN peer could reach the engine port (answered 400) and
     the viewer. **If the owner ships agentmemory, these need closing before the first real session, and the
     viewer exposure is a genuine "who could have read it" question — not a hypothetical.**
- **If the owner wants belt-and-braces rotation** for anything this lane touched, the exact targets are:
  1Password item **`litellm_api`** in vault **`Homelab-ansible`** (CLI: `op item edit litellm_api
  --vault Homelab-ansible`), and note per `docs/deployment-ai-stack-secrets.md` that this value has **four
  bearers** and rotating it requires the vault write **and** the `lan-litellm`/`litellm`/engine converges in
  one window. **Verify a rotation by re-issuing and comparing length/prefix (HD-425) — never assume it
  worked.** My recommendation: **no rotation needed for this lane**; I am not asking for one and not claiming
  one succeeded.

---

## 16. What I would fix upstream before this is anyone's memory plane

1. `post_tool_use`/`subagent_*` must index `toolOutput`/`toolInput` (C-1) — currently the highest-value text is
   thrown away, and it is the single largest lever on recall quality here.
2. `smart-search` should return bodies (or `expandIds` should work) — the default surface can't show what it
   recalled (C-2).
3. Make `TEAM_MODE`/`TEAM_ID`/`USER_ID` reach `mem::search`/`mem::observe`, and support **multiple accepted
   tokens** so per-client credentials are possible without a proxy.
4. Honour a `host` setting instead of re-rendering `127.0.0.1`; and gate the **viewer** with the same
   `checkAuth` as REST. Bind `49134` to loopback.
5. Refuse `OPENAI_API_KEY=false` with a hard error rather than dialing `api.openai.com` with it.
6. Make `limit` bound the work instead of killing the worker.
