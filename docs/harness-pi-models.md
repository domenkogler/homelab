---
title: pi.dev Harness — The rendered models.json (spark provider)
role: ssot
domain: harness
status: active
tags: [ai, pi, agent-harness, harness, spark, llm, model-contract]
---

# pi.dev Harness — The Model Contract

> **Role:** SSOT — the **rendered model contract**: `~/.pi/agent/models.json` is generated from [`../scripts/harness/pi/models-spec.yml`](../scripts/harness/pi/models-spec.yml); this doc is the field-by-field rationale plus the Continue.dev vendor block.
> **Linked from:** [`index.md`](index.md) (Document Map + dispatcher) ·
> [`harness.md`](harness.md) (the `harness` domain hub — placement map).

---
## 4. The rendered `~/.pi/agent/models.json` (generated — edit the spec)

**This block is an OUTPUT, not the thing to edit.** The editable form is
[`../scripts/harness/pi/models-spec.yml`](../scripts/harness/pi/models-spec.yml); the field-by-field
rationale below still explains every value, because the spec carries the same reasoning in its comments.

```bash
python3 scripts/harness/render-pi-config.py --check     # drift gate: exit 1 when a machine diverged
python3 scripts/harness/render-pi-config.py             # render (0600, timestamped backup of the previous file)
```

Two properties worth knowing before you reach for the file:
* **The render is a proven no-op** — `--check` reports
  `matches the spec (byte-identical: True)` against the laptop's live file, which is what makes it safe
  to switch a workstation from hand-maintenance to rendering.
* **Credentials are resolved at render time**, so no key is in git, in the spec, or in the `--check` output
  (masked): `models.json` ← `spark-llm_api` + `entrim_api`; `auth.json` (vendor `pi-auth`) ←
  `openrouter_api` + `opencode-go`. Every one of those items hash-matches what the machine already holds,
  which is why adopting the render is a no-op rather than an event. `--check` covers both files:
  `--vendor all` renders them together.
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
| `reasoning` | `true` (default false) | grants pi the thinking switch; with it OFF pi sends no control and the template thinks on every turn anyway ([`harness-pi-engines.md`](harness-pi-engines.md) §2) |
| `compat.thinkingFormat` | `qwen-chat-template` | sends `chat_template_kwargs.enable_thinking` — the only control this engine honors ([`harness-pi-engines.md`](harness-pi-engines.md) §2) |
| `compat.thinkingTokenBudgetField` | `thinking_token_budget` | vLLM-native cap, verified honored ([`harness-pi-engines.md`](harness-pi-engines.md) §2); keeps "thinking on" affordable |
| `thinkingLevelMap` | nulls everything except `off`/`high` | this engine is **binary** (thinking on/off); the map stops the UI offering five fake effort levels |
| `maxTokens` | 16384 | pi sends `max_tokens` only on compaction/branch summaries (`0.8 × reserveTokens`); 16384 keeps the summary cap at 13,107 — see [`harness-pi-engines.md`](harness-pi-engines.md) §7 for capping normal turns |
| `samplingParams` | temp 1.0 / top_p 0.95 / top_k 20 | mirrors the engine's `--override-generation-config` so the harness, not the server default, is the stated source of truth; change only with a measurement |
| `supportsDeveloperRole` | `true` | probed: the Qwen template renders a `developer` role (200) |
| `supportsReasoningEffort` | `false` | accepted-but-ignored by this build ([`harness-pi-engines.md`](harness-pi-engines.md) §2) |
| `supportsUsageInStreaming` | `true` | required for the footer ctx % and the compaction trigger |
| `input` | `["text"]` | no vision path in this build — declaring `image` would only burn KV |
| `cost` | all zeros | self-hosted: no monetary rate; `0` keeps `/usage` honest (tokens still reported) |

---
## 4b. The same spec, second vendor (Continue.dev) — why it is a *block*, not a config

The model contract has exactly one editable form, and adding a client means adding a vendor rather
than copying numbers. `--vendor continue` renders the same models into a
Continue-shaped `models:` block at `~/.continue/homelab-models.generated.yaml`:

```bash
python3 scripts/harness/render-pi-config.py --vendor continue          # writes the generated block only
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
  claim `tool` only, the spark row claims `tool, reasoning`, matching [`harness-pi-engines.md`](harness-pi-engines.md) §2's probe table.

⏳ **Honest scope note:** the `pi` vendor is proven against a live file (§4). The `continue` vendor is
*rendered and shape-checked*, not proven against a running Continue instance, because no client is
installed on a machine in this fleet yet. Whoever installs the first one owns that verification; the
row stays open until it happens.
