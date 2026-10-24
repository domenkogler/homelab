---
title: pi.dev Harness — Engines (decision #26, engine facts, KV-pool contention, knobs)
role: detail
domain: harness
status: active
sensitivity: infra
tags: [ai, pi, agent-harness, harness, spark, llm, engines]
---

# pi.dev Harness — Client-Side Model Config: Engines

> **Role:** Detail doc — the **pi.dev coding-agent harness** engine side: why the harness goes direct to the spark edge (decision #26), the measured engine facts behind the model contract, the 262144 ceiling arithmetic, the KV-pool contention rule, the optional knobs, apply-and-verify, and the open tails.
> **Linked from:** [`index.md`](index.md) (Document Map + dispatcher) ·
> [`harness.md`](harness.md) (the `harness` domain hub — placement map).

---
## 1b. Why the harness does NOT go through LiteLLM (decision #26)

The question "can't the gateway just hand my parameters to every client?" has a split answer, and the
split is the whole reason for this boundary. LiteLLM **can** hand out *values on the wire*; it cannot
hand out *client-side semantics*, because `pi` reads its model contract from a local `models.json`
(`pi-coding-agent/docs/models.md`) and has no way to consume a proxy's `model_info`.

| Part of [`harness-pi-models.md`](harness-pi-models.md) §4 | Through the gateway? | Note |
|---|---|---|
| `contextWindow`, `maxTokens`, `input` | Partially — as LiteLLM `model_info` (`max_input_tokens` / `max_output_tokens`, live in both DBs) | **pi does not read it** — the field must still be in `models.json`; and the numbers differ on purpose: the DB carries 245,760 = window − reserve, pi needs the engine ceiling 262,144 |
| `samplingParams` (temperature/top_p) | Yes, if put in the DB entry's `litellm_params` | But `top_k` is **not** on the `openai/` provider allow-list → silently dropped |
| `compat.thinkingFormat` → `chat_template_kwargs.enable_thinking` | ⚠ **Unverified on the pinned image** | Not on the `openai/` allow-list on `main`; if dropped, the failure mode is thinking **ON** with HTTP 200 |
| `compat.thinkingTokenBudgetField` → `thinking_token_budget` | ⚠ Same open question | `main` handles it for Bedrock only |
| `reasoning`, `thinkingLevelMap`, `supportsUsageInStreaming`, `maxTokensField`, `supportsDeveloperRole`, `supportsStrictMode`, `supportsReasoningEffort`, `cost` | **No — never** | These describe how *pi* speaks and how *pi* renders; a proxy cannot transmit them |
| timeouts / compaction ([`harness-pi-seats.md`](harness-pi-seats.md) §5) | **No — never** | Harness-side policy |

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
  "apiKey": "(litellm master key, or a scoped key once the gateway leg grants one)",
  "models": [ { "id": "spark/qwen3.8-flash-next", "name": "spark via VPS gateway (backup leg)",
                "contextWindow": 262144, "maxTokens": 16384, "reasoning": true } ]
}
```

`spark-lane` (§6) and `spark-dr` are the same trick twice: **same endpoint id in, different
harness-side budget/route** — which is only possible because the harness is the one holding the truth.

> **What the gateway IS for (decision #26):** the simple queriers (HomeAssistant, Docling, Open WebUI,
> OpenClaw) and the pinned-AI legs (decision #24) — consumers that must not hold an upstream credential,
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
| decode throughput (single stream, thinking on) | ~11 tok/s (129 tok / 11.5 s) | long outputs are minutes-long — see [`harness-pi-seats.md`](harness-pi-seats.md) §5 timeouts |

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

**The arithmetic, settled as a ceiling** (`spark_vllm_max_num_seqs` is the second term, and it is the
engine's, not the harness's): **4 sequences − 1 parent − 1 reserved for the always-on consumers (voice,
LiteLLM, RAG) = 2 live children.** A third child does not queue behind the other two; it preempts a live
prefix and pays the recompute, which is the failure family this section records. The ceiling is contract —
[orchestration.md](orchestration.md) §4's child-lane rules (O11) — and `scripts/gate/check_subagent_contract.py`
holds the settings file and the rule docs to the same number.

**Why the lane alias is NOT how the ceiling is enforced here.** The repo policy is inherit-only: a child
runs the session model, enforced by `subagents.modelScope` (`allow: ["inherit"]`) in
[`../pi-agent/settings-ssot.json`](../pi-agent/settings-ssot.json), and the model spec declares no `spark-*`
alias — so `--model spark-lane/…` is refused at launch, and the way a child costs less KV is a *bounded
prompt*, not a smaller profile. Landing the alias later is a legitimate move, but it owes three edits in
one change: the spec client, the widened `allow`, and O11's wording (the twin gate would otherwise be
silent and the scope would silently reject the alias).

---
## 7. Optional knobs (documented, NOT enabled)

| Knob | How | Trade-off |
|------|-----|-----------|
| Cap normal-turn output | add `"max_tokens": 8192` to `samplingParams` | pi sends **no** `max_tokens` on normal turns, so the model may decode to the window end (~11 tok/s → tens of minutes). A key here wins over pi's own caps, including the compaction-summary cap — size it above `0.8 × reserveTokens` |
| Agentic sampling preset | `"temperature": 0.6, "top_p": 0.95, "top_k": 20` | greedier → more reliable tool-call JSON, worse divergent reasoning; needs an A/B on a real task before switching |
| fp8 KV cache (SERVER) | `spark_llm_profiles.graded` (`--kv-cache-dtype fp8`) | **blocked on the image, not on the model**: the pinned build's QSA kernel declares `["auto","bfloat16"]` and raises, so it will not boot here — and fp8 buys **1.70–1.89×** tokens, not ~2× (main K/V only; the QSA side-caches + GDN state stay bf16). Upstream merged it as vllm#55557 after our tag was built ⇒ an engine-pin lane, then re-cert, then the long-context needle + MTP-acceptance gates in [`spark-llm-profiles.md`](spark-llm-profiles.md) / [`../spark/llm-profiles/README.md`](../spark/llm-profiles/README.md) |
| Bigger prefill chunk (SERVER) | `spark_vllm_max_num_batched_tokens: 32768` | halves chunked-prefill iterations on 200k prompts, spikes activation memory — re-measure against the memory governor ([`hardware-spark.md`](hardware-spark.md) §Unified-memory budget) |
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
`SMOKE_OK` (rc=0) through the compat block. Footer should read the window as 262.1K.

---
## 9. Open tails

- ⏳ Re-measure whether the thinking control (`chat_template_kwargs.enable_thinking` +
  `thinking_token_budget`) actually survives the LiteLLM path on the **pinned** image. It does not
  change the harness's route (direct, decision #26) — it decides whether the *simple queriers* may rely
  on thinking being off.
- ⏳ Long-context needle test at 262k (agentic/max-context work is gated on it,
  [`hardware-spark.md`](hardware-spark.md)) — until it passes, treat the top ~20% of the window as
  experimental.
- ⏳ `spark-lane` profile (§6) is authored-on-paper only; promoting it also owes widening
  `subagents.modelScope` and restating O11, all in the same change.
- ⏳ The child-runtime knobs (`timeoutMs`, the two concurrency caps, the pre-deadline checkpoint) are
  authored in [`../pi-agent/settings-ssot.json`](../pi-agent/settings-ssot.json) as `_subagentConfig` — the
  payload for the extension's own `~/.pi/agent/extensions/subagent/config.json`, the file the seat × plane
  matrix owns (**[`harness-pi-seats.md`](harness-pi-seats.md) §1**, the `subagent` registry record + [`../scripts/harness/pi-subagent-config.sh`](../scripts/harness/pi-subagent-config.sh)). **The win11 leg is converged; the Debian seats (WSL + cockpit) converge on the next per-seat `pi-seat-sync --push`** — until a seat's own `--check` prints `OK` for `~/.pi/agent/extensions/subagent/config.json`, that seat runs the harness's own defaults (a 30-minute run backstop, up to 20 concurrent children) and a run must pass the values on the launch. The settings plane merges un-prefixed keys only, which is why this payload sits under an underscore rather than pretending to be converged.
- **Pointer (not a tail):** the workstation's two other local model legs — **FIM autocomplete** and **Qwen3-VL visual judgment** (vision reaches spark only as *text*; the engine is text-only) — are owned by [`hardware-workstation.md`](hardware-workstation.md) + decision #28 in [`services-ai.md`](services-ai.md) §9. Nothing here changes; the harness stays direct-to-engine (decision #26).
