---
title: pi.dev Harness — The rendered models.json (the model contract)
role: detail
domain: harness
status: active
tags: [ai, pi, agent-harness, harness, spark, entrim, llm, model-contract]
---

# pi.dev Harness — The Model Contract

> **Role:** detail — the **model contract in prose**: the field-by-field rationale for
> `~/.pi/agent/models.json`, plus the Continue.dev vendor block. **The SSOT is the spec, not this doc** —
> [`../scripts/harness/pi/models-spec.yml`](../scripts/harness/pi/models-spec.yml), rendered by
> [`../scripts/harness/render-pi-config.py`](../scripts/harness/render-pi-config.py).
> The block in §4 below is that render's OUTPUT, not its source: CONVENTIONS §8.5 puts the values in the
> SSOT and the reasoning in the doc, and this doc is the reasoning.
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
* **The fleet spelling for a seat credential is `type: api_key`.** An entry authorised by an interactive
  login (`oauth`) is seat drift, not an alternative shape: it cannot be re-rendered from the vault, it
  expires on its own schedule, and a rebuilt seat cannot reproduce it. But **the drift is never fixed by
  overwriting a live credential** — a render that replaced a working login to make a check read green
  destroys the only path the human has back into the machine. So the rule is paired: `--check` reports the
  entry's live `type` per seat, a mismatch is a named drift line rather than a silent rewrite, and the
  credential itself is minted through the vendor lane and installed while someone can re-login.

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
  protocols and then silently disagree. Unverified claims are worse than empty ones — each row's claim
  is the probe result for THAT model (§4c), so the two reasoning-capable hosted rows and the spark row
  claim `tool, reasoning` while a non-reasoning hosted row claims `tool` only; the spark numbers behind
  its claim are [`harness-pi-engines.md`](harness-pi-engines.md) §2's probe table.

⏳ **Honest scope note:** the `pi` vendor is proven against a live file (§4). The `continue` vendor is
*rendered and shape-checked*, not proven against a running Continue instance, because no client is
installed on a machine in this fleet yet. Whoever installs the first one owns that verification.

---
## 4c. The hosted provider's rows — what the endpoint, not a doc, decides

`providers.entrim` is the fleet's cost-bearing external lane, and its rows are the only part of the
picker this repo controls but does not serve. What keeps them honest is one rule and a probe per claim.

**The endpoint's own `GET /v1/models` is the authority on which rows exist** and on the two numbers a
row must carry (`max_input_tokens` → `contextWindow`, `max_output_tokens` → `maxTokens`). It is the
only source that cannot lag the provider, and a row whose id is absent there is a **dead pick**: it
stays selectable and answers `400 Invalid model name`. A row that cannot be served is worse than no
row, because it is chosen in good faith and fails mid-task. Retire on the catalog, in the same change
that lands the successor.
A row can also be **served but unlisted** — a model can leave the catalog and keep answering completions.
That is a heads-up, not a removal trigger: deleting a row that answers is an outage for whoever has it
selected, so the successor is an owner call, probed like any other row.

**Capabilities are probed, per model, never inherited from the provider or copied from a vendor page:**

| Claim | Probe | What a pass looks like |
|---|---|---|
| `tool` | one real `tools:` call against a trivial function | `finish_reason: tool_calls` with a well-formed `tool_calls` entry |
| `image` | a solid-magenta 256×256 PNG plus "name the colour" | names it ("Magenta", "Purple" — a dropped image cannot guess a hue), **and** `prompt_tokens` jumps over the figure for the SAME prompt with no image (GLM 126 vs 24, DeepSeek 200 vs 16, Qwen 130 vs 64) — the token jump is the half that proves the image was read rather than dropped |
| `reasoning` | plain completion | `reasoning_content` in the message and non-zero `usage.completion_tokens_details.reasoning_tokens` |
| thinking **off** | the same prompt with `reasoning_effort: "none"` | `reasoning_tokens` absent/0 **and** an answer. This is where the hosted rows differ from each other (below) |
| streaming usage | `stream: true` + `stream_options.include_usage` | a final chunk carrying `usage` — pi's ctx % and compaction trigger depend on it, and it is why no hosted row needs a `compat:` block |

**Thinking-off is not a capability a provider has; it is a capability each model has.** Measured row by
row: `deepseek-ai/DeepSeek-V4.1-Flash` and `Qwen/Qwen3.8-27B` answer `none` with zero reasoning tokens
and a direct reply, so their `thinkingLevelMap` carries `"off"` and `/thinking off` means what it says;
`zai-org/GLM-5.3-Flash` accepts `none`
with a 200, thinks anyway, and spends its whole response budget thinking — 3002 reasoning tokens, empty
`content`. For that row the honest spec declares **no** `off` key at all: an entry promising a state the
endpoint cannot produce is a dial that lies, and selecting it buys silence. pi's graded levels
(`minimal`…`max`) are accepted verbatim by every hosted row, so nothing else is mapped — a map that restates
pass-through only invites someone to "fix" its numbers.

**The trap in this shape:**

* A bare `off:` key in a `thinkingLevelMap` is **YAML 1.1 for `false`**, so it renders as the JSON key
  `"false"`, pi finds no `off` entry, sends no `reasoning_effort`, and thinking stays ON — while the
  spec still reads correctly and `--check` reports a match, because the check compares spec against
  target and both sides carry the same wrong key. Quote the key; the renderer now aborts on any level
  name outside pi's own set, since a gate that cannot see the defect cannot fail either.

**What the external lane is FOR is not capacity.** A hosted row is *selectable*
because the contract renders it; it becomes *authorized* only when the owner explicitly asks for an
external model in the session. It is never the answer to a busy, slow, or down spark — no automatic
fallback, no queued work that quietly changes provider, no benchmark to justify one (there is no
external-lane bench and none is wanted). The rule lives in the root `README.md` §3: switching provider
mid-task moves both money and prompt text off the premises, which is a decision and not an
optimization.

**The hosted rows carry their published prices (`cost:`, USD per million tokens).** Without it pi
prices a paid external call at `0` in `/usage` and in the footer, which is worse than an honest unknown
because it looks measured. `cacheWrite: 0` is a stated fact rather than a gap: the lane caches
implicitly and publishes a read price and no write tier. Prices are the provider's, not estimates — a
row whose price nobody can cite should carry no `cost:` at all.

