---
title: pi.dev Harness — Client-Side Model Config (spark provider)
role: detail
domain: services
status: active
tags: [ai, pi, agent-harness, spark, llm, tuning]
---
# pi.dev Harness — Client-Side Model Config

> **Role:** Detail doc — the **pi.dev coding-agent harness** config on the admin workstation
> (`~/.pi/agent/models.json` + `~/.pi/agent/settings.json`) for the spark provider
> (`https://llm.kogler.si/v1` → served-model `spark/qwen3.8-flash-next`). Owning doc for the
> **harness-side** context window, thinking control, timeouts and compaction numbers, and for the
> measured engine facts behind them. Server-side (vLLM on spark) numbers stay in
> [`hardware-spark.md`](hardware-spark.md) — direction of truth: engine → harness, never the reverse.
> **Linked from:** [`index.md`](index.md) (Document Map + dispatcher) ·
> [`services-ai.md`](services-ai.md) §pi.dev + DSH · [`../todo.md`](../todo.md) HD-376
> **Engine-side owner (NOT this doc):** [`hardware-spark.md`](hardware-spark.md) — vLLM args, unified-memory
> governance, S1 certification; incident history in [`spark-incidents.md`](spark-incidents.md).

---

## 1. Scope and deploy direction

| Item | Where it lives | Managed by |
|------|----------------|-----------|
| `~/.pi/agent/models.json` | **rendered**, per machine, by [`../scripts/render-pi-config.py`](../scripts/render-pi-config.py) from the SSOT [`../scripts/pi-config/models-spec.yml`](../scripts/pi-config/models-spec.yml) | git (the spec) — **not the JSON**; the render carries the bearer key, so it is 0600 and never committed. Was: "this doc is the reference copy" (HD-388 closed that) |
| `~/.pi/agent/auth.json` | **rendered** (vendor `pi-auth`) from the same spec | git — the built-in-provider auth (`openrouter`, `opencode-go`) was the last hand-kept credential file on the client; proven byte-identical to the render 2026-09-23 |
| `~/.pi/agent/settings.json` | admin workstation only | this doc is the reference copy (§5) — deliberately NOT rendered: theme/packages/`lastChangelogVersion` are workstation-local |
| `AGENTS.md`, `prompts/`, `extensions/`, `skills/` | repo `pi-agent/` + `skills/` → deployed by [`../scripts/install-pi-wsl.sh`](../scripts/install-pi-wsl.sh) | git (repo → `~/.pi/agent`) |
| spark engine (`--max-model-len`, KV pool) | repo IaC `IaC/ansible/group_vars/spark.yml` | Ansible (SSOT, HD-374) |

- The harness talks **directly to the spark edge** (`llm.kogler.si`, HD-370), not through LiteLLM. That
  is a DECIDED boundary as of **decision #26**, [services-ai.md](services-ai.md) §9 row 26 +
  the evidence appendix §9d), not an accident of history — see **§1b** below. The LAN/VPS LiteLLM
  instances (HD-356) front the same engine for the **simple-querier tier** (HomeAssistant, Docling,
  Open WebUI) — the model id `spark/qwen3.8-flash-next` is deliberately stable across every path.
- **Secret:** the provider `apiKey` is the `spark-llm_api` credential (1Password `Homelab-ansible`
  vault, HD-370). Never commit the literal and never print its value (CONVENTIONS §6).
- Reload: `models.json` is re-read every time `/model` is opened in a running session; a new session
  picks it up at start. `settings.json` is read at start → restart pi.

---

## 1b. Why the harness does NOT go through LiteLLM (decision #26)

The question "can't the gateway just hand my parameters to every client?" has a split answer, and the
split is the whole reason for this boundary. LiteLLM **can** hand out *values on the wire*; it cannot
hand out *client-side semantics*, because `pi` reads its model contract from a local `models.json`
(`pi-coding-agent/docs/models.md`) and has no way to consume a proxy's `model_info`.

| Part of §4 | Through the gateway? | Note |
|---|---|---|
| `contextWindow`, `maxTokens`, `input` | Partially — as LiteLLM `model_info` (`max_input_tokens` / `max_output_tokens`, live in both DBs since HD-382) | **pi does not read it** — the field must still be in `models.json`; and the numbers differ on purpose: the DB carries 245,760 = window − reserve, pi needs the engine ceiling 262,144 |
| `samplingParams` (temperature/top_p) | Yes, if put in the DB entry's `litellm_params` | But `top_k` is **not** on the `openai/` provider allow-list → silently dropped |
| `compat.thinkingFormat` → `chat_template_kwargs.enable_thinking` | ⚠ **Unverified on the pinned image** — HD-387 | Not on the `openai/` allow-list on `main`; if dropped, the failure mode is thinking **ON** with HTTP 200 |
| `compat.thinkingTokenBudgetField` → `thinking_token_budget` | ⚠ Same open question (HD-387) | `main` handles it for Bedrock only |
| `reasoning`, `thinkingLevelMap`, `supportsUsageInStreaming`, `maxTokensField`, `supportsDeveloperRole`, `supportsStrictMode`, `supportsReasoningEffort`, `cost` | **No — never** | These describe how *pi* speaks and how *pi* renders; a proxy cannot transmit them |
| timeouts / compaction (§5) | **No — never** | Harness-side policy |

So a gateway hop buys a harness **no** configuration relief for the eight fields that cost the effort,
while putting the three that matter most at risk of silent loss. Two further reasons, both measured on
this box rather than argued: a proxy **retry/fallback** reproduces the incident-#6 memory spike
automatically (162k-token session, 0 % prefix hit, 17,008 tok/s re-prefill, 21.5 → 12.6 GiB in 22 s —
[spark-incidents.md](spark-incidents.md)), and a **fallback that swaps the model** silently invalidates
§3 (pi keeps compacting against the old window) and the tool-call parser assumption. Fallback therefore
lives **here**, as a second provider entry whose `contextWindow` is also correct:

```json
"spark-dr": {
  "baseUrl": "https://litellm.kogler.si/v1",
  "api": "openai-completions",
  "apiKey": "(litellm master key, or a scoped key once HD-384 grants one)",
  "models": [ { "id": "spark/qwen3.8-flash-next", "name": "spark via VPS gateway (backup leg)",
                "contextWindow": 262144, "maxTokens": 16384, "reasoning": true } ]
}
```

`spark-lane` (§6) and `spark-dr` are the same trick twice: **same endpoint id in, different
harness-side budget/route** — which is only possible because the harness is the one holding the truth.

> **What the gateway IS for (decision #26):** the simple queriers (HomeAssistant, Docling, Open WebUI,
> OpenClaw) and the pinned-AI legs (decision #25) — consumers that must not hold an upstream credential,
> that want one dropdown, and that gain from per-key budgets/spend records. A `pi`-class consumer gains
> none of that and loses determinism.


## 2. Engine facts (measured live, against `https://llm.kogler.si/v1`)

Engine build: `vllm-0.1.dev20073+g8e685d198` (`system_fingerprint` in responses).

| Probe | Result | Consequence for the harness |
|-------|--------|-----------------------------|
| `GET /v1/models` | `max_model_len: 262144` | hard per-request ceiling — `contextWindow` = 262144 |
| bare request | thinking **ON by default** — `reasoning` field populated, `completion_tokens_details.reasoning_tokens: 23` | pi must send an explicit switch, or every turn pays for hidden reasoning |
| `chat_template_kwargs: {enable_thinking: false}` | 200, `reasoning_tokens: 0`, prompt 57 → 17 tok | `compat.thinkingFormat: "qwen-chat-template"` is the correct control |
| `chat_template_kwargs: {enable_thinking, preserve_thinking}` | 200 (extra kwarg ignored cleanly) | pi's `qwen-chat-template` shape is safe |
| `thinking_token_budget: 96` | 200, reasoning capped at 82 (same prompt uncapped = 121) | `compat.thinkingTokenBudgetField: "thinking_token_budget"` is honored |
| `reasoning_effort: "low"` | 200 but reasoning still ran | not the control here → `supportsReasoningEffort: false` |
| tools (`--tool-call-parser qwen3_coder`) | `tool_calls` returned with valid JSON args | agentic use OK; leave `supportsStrictMode: false` |
| replay assistant msg with `reasoning` / `reasoning_content` | both 200 | multi-turn thinking replay is safe (no `requiresReasoningContentOnAssistantMessages` needed) |
| `stream_options: {include_usage: true}` | 200 | `supportsUsageInStreaming: true` — pi needs usage for the ctx % + compaction trigger |
| unknown body field | 200 (tolerated) | extras in `samplingParams` cannot break the endpoint |
| decode throughput (single stream, thinking on) | ~11 tok/s (129 tok / 11.5 s) | long outputs are minutes-long — see §5 timeouts |

---

## 3. Why 262144 and not "273k"

Three different numbers get conflated; only one of them is servable context:

1. **262,144** = `--max-model-len` (`spark_vllm_max_model_len`, = model native
   `max_position_embeddings`). This is the **per-request ceiling**: prompt + completion in ONE sequence
   cannot exceed it, and the engine answers `400` when it does. It is a boot-gate, not an allocation
   ([`hardware-spark.md`](hardware-spark.md) §Unified-memory budget, point 1).
2. **~268–275k** = KV-pool capacity in *token slots*: `spark_vllm_kv_cache_memory: 8800000000` ≈
   8.2 GiB ÷ ~32 KiB/token. **Aggregate across all concurrent sequences**, not per session.
3. **273 GB/s** = LPDDR5x memory bandwidth of the GB10. Not a context number at all.

Putting `273000` (or `300000`) into `contextWindow` does not buy context — it makes the harness fill
the transcript past the engine's gate and hard-fail the request minutes into a session. Exceeding
262k would need `VLLM_ALLOW_LONG_MAX_MODEL_LEN=1` + YaRN rope scaling + the pending needle test
(gated, see [`hardware-spark.md`](hardware-spark.md)); it is not a harness-side decision.

---

## 4. The rendered `~/.pi/agent/models.json` (generated — edit the spec)

**This block is an OUTPUT, not the thing to edit.** The editable form is
[`../scripts/pi-config/models-spec.yml`](../scripts/pi-config/models-spec.yml) (HD-388); the field-by-field
rationale below still explains every value, because the spec carries the same reasoning in its comments.

```bash
python3 scripts/render-pi-config.py --check     # drift gate: exit 1 when a machine diverged
python3 scripts/render-pi-config.py             # render (0600, timestamped backup of the previous file)
```

Two properties worth knowing before you reach for the file:
* **The render is a proven no-op on the machine that had the hand-kept copy** — `--check` reports
  `matches the spec (byte-identical: True)` against the laptop's live file, which is what makes it safe
  to switch a workstation from hand-maintenance to rendering. Verified 2026-09-23.
* **Credentials are resolved at render time**, so no key is in git, in the spec, or in the `--check` output
  (masked): `models.json` ← `spark-llm_api` + `entrim_api`; `auth.json` (vendor `pi-auth`) ←
  `openrouter_api` + `opencode-go`. Both items classes were minted 2026-09-23 and **every one of them
  hash-matched what the machine already held**, which is why adopting the render was a no-op rather
  than an event. `--check` covers both files: `--vendor all` renders them together.
* **Takeover rule for a credential file**: if the target holds a provider the spec does not name, the
  render **preserves it and prints why**. A silent drop in `auth.json` is a lockout you discover by
  being locked out; a printed NOTE is a task someone can finish.

```json
{
  "providers": {
    "spark": {
      "baseUrl": "https://llm.kogler.si/v1",
      "api": "openai-completions",
      "apiKey": "(spark-llm_api credential — Homelab-ansible vault, never committed)",
      "compat": {
        "supportsUsageInStreaming": true,
        "supportsFinishReason": true,
        "maxTokensField": "max_tokens",
        "supportsDeveloperRole": true,
        "supportsReasoningEffort": false,
        "supportsStrictMode": false,
        "thinkingFormat": "qwen-chat-template",
        "thinkingTokenBudgetField": "thinking_token_budget"
      },
      "models": [
        {
          "id": "spark/qwen3.8-flash-next",
          "name": "Qwen 3.8 Flash Next (spark GB10, 262k)",
          "reasoning": true,
          "input": ["text"],
          "contextWindow": 262144,
          "maxTokens": 16384,
          "thinkingLevelMap": {
            "minimal": null,
            "low": null,
            "medium": null,
            "xhigh": null,
            "max": null
          },
          "samplingParams": {
            "temperature": 1.0,
            "top_p": 0.95,
            "top_k": 20
          },
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
        }
      ]
    }
  }
}
```

Field rationale (defaults in parentheses come from `pi-coding-agent/docs/models.md`):

| Field | Value | Why |
|-------|-------|-----|
| `contextWindow` | **262144** (default 128000) | the actual servable window — without it pi compacts at ~112k and throws away half the engine |
| `reasoning` | `true` (default false) | grants pi the thinking switch; with it OFF pi sends no control and the template thinks on every turn anyway (§2) |
| `compat.thinkingFormat` | `qwen-chat-template` | sends `chat_template_kwargs.enable_thinking` — the only control this engine honors (§2) |
| `compat.thinkingTokenBudgetField` | `thinking_token_budget` | vLLM-native cap, verified honored (§2); keeps "thinking on" affordable |
| `thinkingLevelMap` | nulls everything except `off`/`high` | this engine is **binary** (thinking on/off); the map stops the UI offering five fake effort levels |
| `maxTokens` | 16384 | pi sends `max_tokens` only on compaction/branch summaries (`0.8 × reserveTokens`); 16384 keeps the summary cap at 13,107 — see §7 for capping normal turns |
| `samplingParams` | temp 1.0 / top_p 0.95 / top_k 20 | mirrors the engine's `--override-generation-config` so the harness, not the server default, is the stated source of truth; change only with a measurement |
| `supportsDeveloperRole` | `true` | probed: the Qwen template renders a `developer` role (200) |
| `supportsReasoningEffort` | `false` | accepted-but-ignored by this build (§2) |
| `supportsUsageInStreaming` | `true` | required for the footer ctx % and the compaction trigger |
| `input` | `["text"]` | no vision path in this build — declaring `image` would only burn KV |
| `cost` | all zeros | self-hosted: no monetary rate; `0` keeps `/usage` honest (tokens still reported) |

---

## 4b. The same spec, second vendor (Continue.dev) — why it is a *block*, not a config

HD-388's premise is that the model contract has exactly one editable form, and that adding a client
means adding a vendor rather than copying numbers. `--vendor continue` renders the same models into a
Continue-shaped `models:` block at `~/.continue/homelab-models.generated.yaml`:

```bash
python3 scripts/render-pi-config.py --vendor continue          # writes the generated block only
```

Three decisions in that shape, each because the alternative loses something:
* **It never merges into a workstation's `~/.continue/config.yaml`.** A generated block written over
  user-authored keys is a data-loss bug, and "we'll merge carefully" is not a mechanism. So the render
  lands beside it and wiring it in (import or manual merge) stays a per-machine step.
* **The `apiKey` line is a placeholder string, not the secret.** Continue keeps its own secret store;
  resolving 1Password into a second app's config file would widen the file's blast radius for no gain.
* **`capabilities` is per-model in the spec (`continue:`), not derived.** `reasoning`/`tool` claims are
  what the harness asks the vendor for; inferring them from `compat` would couple two different
  protocols and then silently disagree. Unverified claims are worse than empty ones — the entrim rows
  claim `tool` only, the spark row claims `tool, reasoning`, matching §2's probe table.

⏳ **Honest scope note:** the `pi` vendor is proven against a live file (§4). The `continue` vendor is
*rendered and shape-checked*, not proven against a running Continue instance, because no client is
installed on a machine in this fleet yet. Whoever installs the first one owns that verification; the
row stays open until it happens.

## 5. Reference `~/.pi/agent/settings.json` (harness tuning)

```json
{
  "defaultProvider": "spark",
  "defaultModel": "spark/qwen3.8-flash-next",
  "defaultThinkingLevel": "off",
  "showCacheMissNotices": true,
  "httpIdleTimeoutMs": 900000,
  "retry": {
    "enabled": true,
    "maxRetries": 3,
    "baseDelayMs": 2000,
    "provider": { "timeoutMs": 1800000, "maxRetries": 0, "maxRetryDelayMs": 60000 }
  },
  "compaction": { "enabled": true, "reserveTokens": 16384, "keepRecentTokens": 32768 },
  "thinkingBudgets": { "minimal": 1024, "low": 2048, "medium": 4096, "high": 8192 }
}
```

Other keys in the real file (`theme`, `packages`, `lastChangelogVersion`) are workstation state, not
spec — the block above is the part that must match.

| Setting | Value | Why on this box |
|---------|-------|-----------------|
| `defaultThinkingLevel` | `off` | preserves the pre-change behavior, but now it actually reaches the engine (saves ~20–120 hidden reasoning tokens + latency per turn) |
| `compaction.reserveTokens` | 16384 | pi compacts when context > `contextWindow − reserveTokens` = **245,760**; this is the "use the whole window" dial |
| `compaction.keepRecentTokens` | 32768 (default 20000) | larger verbatim tail survives a compaction — cheaper to keep when the window is 262k |
| `httpIdleTimeoutMs` | 900000 (default 300000) | a cold prefill of a large prompt emits no tokens until the first token; the 5-min default can kill the turn mid-prefill |
| `retry.provider.timeoutMs` | 1800000 | same reason, per-request ceiling (SDK default is far below a 200k cold prefill) |
| `showCacheMissNotices` | `true` | server-side `--enable-prefix-caching` is the only reason a 200k turn is cheap — the notice shows when the harness broke a cached prefix |
| `thinkingBudgets` | 1k/2k/4k/8k | only applied when thinking is ON (needs `thinkingTokenBudgetField`); bounds what "high" can spend |

---

## 6. KV-pool contention — the parallel-lane rule (read before running subagents)

The pool is **one shared budget of ~262–268k token slots** (`spark_vllm_kv_cache_memory`), while
`spark_vllm_max_num_seqs: 4`. A single parent session configured at the full 262,144 window can
therefore occupy **100% of the pool**. A concurrent lane (pi subagent, a second pi session, Open
WebUI, the voice/RAG consumers) then competes for the same blocks → preemption + recompute, which is
the failure family recorded in [`spark-incidents.md`](spark-incidents.md).

For orchestrator/subagent runs (README §4 item 7), give lanes a smaller window by declaring a second
provider entry for the **same** endpoint + **same** model id — the id sent to the API is unchanged,
only the harness-side budget differs:

```json
"spark-lane": {
  "baseUrl": "https://llm.kogler.si/v1",
  "api": "openai-completions",
  "apiKey": "(spark-llm_api credential)",
  "models": [
    {
      "id": "spark/qwen3.8-flash-next",
      "name": "Qwen 3.8 Flash Next — lane (64k, shared KV pool)",
      "contextWindow": 65536,
      "maxTokens": 8192,
      "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
    }
  ]
}
```

Children then run on `spark-lane/spark/qwen3.8-flash-next` (`pi -p --model …`), and parent + up to
~3 lanes fit the pool. Not enabled by default — one lane costs 4× less context, so it is a
per-run choice, not a global default.

---

## 7. Optional knobs (documented, NOT enabled)

| Knob | How | Trade-off |
|------|-----|-----------|
| Cap normal-turn output | add `"max_tokens": 8192` to `samplingParams` | pi sends **no** `max_tokens` on normal turns, so the model may decode to the window end (~11 tok/s → tens of minutes). A key here wins over pi's own caps, including the compaction-summary cap — size it above `0.8 × reserveTokens` |
| Agentic sampling preset | `"temperature": 0.6, "top_p": 0.95, "top_k": 20` | greedier → more reliable tool-call JSON, worse divergent reasoning; needs an A/B on a real task before switching |
| fp8 KV cache (SERVER) | `spark_vllm_kv_cache_dtype: "fp8"` | ~halves bytes/token → ~2× pool → real concurrency for lanes; gated on the long-context needle test in [`hardware-spark.md`](hardware-spark.md) |
| Bigger prefill chunk (SERVER) | `spark_vllm_max_num_batched_tokens: 32768` | halves chunked-prefill iterations on 200k prompts, spikes activation memory — re-measure against the HD-374 governor |
| Beyond 262k (SERVER) | `VLLM_ALLOW_LONG_MAX_MODEL_LEN=1` + YaRN | already rejected as ungated ([`hardware-spark.md`](hardware-spark.md)); needle test first |
| Vision input | `"input": ["text","image"]` | do NOT — no vision path in this build |

---

## 8. Apply and verify

```bash
python3 -c "import json;[json.load(open(p)) for p in \
  ('/home/domen/.pi/agent/models.json','/home/domen/.pi/agent/settings.json')]" && echo "json ok"
pi --list-models | awk '$1=="spark"'
# expect: spark  spark/qwen3.8-flash-next  262.1K  16.4K  yes  no
pi -p --model spark/qwen3.8-flash-next "Reply with exactly: SMOKE_OK"
```

Verified: the row renders `262.1K / 16.4K / thinking yes`, and the smoke test returns
`SMOKE_OK` (rc=0) through the new compat block. Footer should read the window as 262.1K.

---

## 9. Open tails

- ✅ **CLOSED:** the "`pi-dev` re-point" tail is **moot** — `dsh`/`pi-dev` are PARKED as
  services (HD-386) and per decision #26 the harnesses reach the engine directly, so there is nothing
  left to re-point. The LAN model entry itself landed (HD-382) and stays for the
  simple-querier tier.
- ⏳ **HD-387:** re-measure whether the thinking control (`chat_template_kwargs.enable_thinking` +
  `thinking_token_budget`) actually survives the LiteLLM path on the **pinned** image. It does not
  change the harness's route (direct, decision #26) — it decides whether the *simple queriers* may rely
  on thinking being off.
- ⏳ Long-context needle test at 262k (agentic/max-context work is gated on it,
  [`hardware-spark.md`](hardware-spark.md)) — until it passes, treat the top ~20% of the window as
  experimental.
- ⏳ `spark-lane` profile (§6) is authored-on-paper only; promote it into the reference config once a
  real orchestrator run measures lane-vs-preemption behavior.
- **Pointer (not a tail):** the workstation's two other local model legs — **FIM autocomplete** and **Qwen3-VL visual judgment** (vision reaches spark only as *text*; the engine is text-only) — are owned by [`hardware-workstation.md`](hardware-workstation.md) + decision #28 in [`services-ai.md`](services-ai.md) §9 (HD-401). Nothing here changes; the harness stays direct-to-engine (decision #26).
