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
> [`services-ai.md`](services-ai.md) §pi.dev + DSH
> **Engine-side owner (NOT this doc):** [`hardware-spark.md`](hardware-spark.md) — vLLM args, unified-memory
> governance, S1 certification; incident history in [`spark-incidents.md`](spark-incidents.md).

---

## 1. Scope and deploy direction

| Item | Where it lives | Managed by |
|------|----------------|-----------|
| `~/.pi/agent/models.json` | **rendered**, per machine, by [`../scripts/render-pi-config.py`](../scripts/render-pi-config.py) from the SSOT [`../scripts/pi-config/models-spec.yml`](../scripts/pi-config/models-spec.yml) | git (the spec) — **not the JSON**; the render carries the bearer key, so it is 0600 and never committed. Rendered on **two** machines: the laptop, and oldsrv's cockpit account `domen` — the harness is therefore not "admin workstation only", and a second machine is contracted through `--out` + scp, not a copied file |
| `~/.pi/agent/auth.json` | **rendered** (vendor `pi-auth`) from the same spec | git — the built-in-provider auth (`openrouter`, `opencode-go`); the client's file is byte-identical to the render |
| `~/.pi/agent/settings.json` | the admin workstation **and** oldsrv's cockpit seat (`domen`) | **§5's harness block is a repo file** — [`../pi-agent/settings-ssot.json`](../pi-agent/settings-ssot.json), merged into each seat's file by [`../scripts/pi-settings-config.sh`](../scripts/pi-settings-config.sh): the merge owns the harness keys and the `packages` list (composed from the `versions.yml` pins, §7); `externalEditor` / `lastChangelogVersion` / `tuiMode` stay machine-local and §5 remains the place that says WHY each key is what it is |
| pi packages (`pi install npm:…`), **the pi build itself** + the seat TUI font | every pi.dev seat | git — the pin pairs `pi_host_tui_npm_*` / `pi_host_web_npm_*` / `pi_host_subagents_npm_*` / `pi_host_deepseek_npm_*` / `nerd_fonts_*` in `IaC/ansible/group_vars/all/versions.yml`, installed by the two `install-pi-*.sh` scripts and re-converged by [`../scripts/pi-seat-sync.sh`](../scripts/pi-seat-sync.sh) (the fan-out driver: seat × plane matrix, unreachable seat = failed run, and a seat whose declared planes did not all run fails as `coverage` — a bare `ssh` inside the plane loop eats the loop's stdin) |
| `AGENTS.md`, `prompts/`, `extensions/`, `skills/` | repo `pi-agent/` + `skills/` → deployed by both installers: skills via [`../scripts/sync-skills.sh`](../scripts/sync-skills.sh), `extensions/` via [`../scripts/sync-extensions.sh`](../scripts/sync-extensions.sh) | git (repo → `~/.pi/agent`), drift-gated by `validate-all.sh` items 13 + 27 |
| `~/.tmux.conf` (the seat's terminal harness) | repo [`../pi-agent/tmux/tmux.conf`](../pi-agent/tmux/tmux.conf) → installed by [`../scripts/install-tmux-conf.sh`](../scripts/install-tmux-conf.sh) | git (the SSOT) — **not** the file in `$HOME`; it carries a `managed-by:` line so an installed copy is nameable, and a foreign `~/.tmux.conf` is a REFUSAL rather than a silent overwrite. Mouse + OSC 52 clipboard: **§5b**. Not yet called by the seat installer |
| spark engine (`--max-model-len`, KV pool) | repo IaC `IaC/ansible/group_vars/spark.yml` | Ansible (SSOT) |

- The harness talks **directly to the spark edge** (`llm.kogler.si`), not through LiteLLM. That
  is a DECIDED boundary (**decision #26**, [services-ai.md](services-ai.md) §9 row 26 +
  the evidence appendix §9d), not an accident of history — see **§1b** below. The LAN/VPS LiteLLM
  instances front the same engine for the **simple-querier tier** (HomeAssistant, Docling,
  Open WebUI) — the model id `spark/qwen3.8-flash-next` is deliberately stable across every path.
- **Secret:** the provider `apiKey` is the `spark-llm_api` credential (1Password `Homelab-ansible`
  vault). Never commit the literal and never print its value (CONVENTIONS §6).
- Reload: `models.json` is re-read every time `/model` is opened in a running session; a new session
  picks it up at start. `settings.json` is read at start → restart pi.
- **Where the pi BINARY lives — two layouts, one PATH.** `npm -g`
  installs it as a symlink at `<pi-node prefix>/bin/pi` next to the pinned node (what
  [`../scripts/install-pi-debian.sh`](../scripts/install-pi-debian.sh) does); pi's own installer writes a
  launcher at `~/.pi/agent/bin/pi` over `~/.pi/agent/install/releases/<ver>/` (`layout: releases-v1`).
  **`pi update` run inside a session migrates the first layout into the second and deletes the
  node-dir symlink** (1.1.0's own CHANGELOG recommends the migration), so a seat can lose `pi` from
  PATH on the day it updates while pi itself runs perfectly — the cockpit then dies with
  `exec: "pi": executable file not found in $PATH`.
  Three places carry **both** dirs: the seat's `.bashrc`/`.profile`
  (`install-pi-debian.sh --path-only` is the repair for a seat whose block predates it), the cockpit
  unit (`roles/seat` → `pi-on-path.conf`, `seat_pi_bin` + `seat_pi_node_bin`, asserted in the live
  unit), and every probe (`pi_bin()` / `pi_candidate()`) — a probe that reads only PATH reports
  "no pi here" for a seat that has one. `pi update self` installs the LATEST release and takes no version
  flag, so a managed seat off its pin is an **owner** action — move `pi_host_npm_version` +
  `pi_dev_npm_version` to what it reports, or move the seat back to the pinned layout with
  `install-pi-debian.sh --pi-only`; the script refuses to npm-install a second layout underneath it.

---

## 1b. Why the harness does NOT go through LiteLLM (decision #26)

The question "can't the gateway just hand my parameters to every client?" has a split answer, and the
split is the whole reason for this boundary. LiteLLM **can** hand out *values on the wire*; it cannot
hand out *client-side semantics*, because `pi` reads its model contract from a local `models.json`
(`pi-coding-agent/docs/models.md`) and has no way to consume a proxy's `model_info`.

| Part of §4 | Through the gateway? | Note |
|---|---|---|
| `contextWindow`, `maxTokens`, `input` | Partially — as LiteLLM `model_info` (`max_input_tokens` / `max_output_tokens`, live in both DBs) | **pi does not read it** — the field must still be in `models.json`; and the numbers differ on purpose: the DB carries 245,760 = window − reserve, pi needs the engine ceiling 262,144 |
| `samplingParams` (temperature/top_p) | Yes, if put in the DB entry's `litellm_params` | But `top_k` is **not** on the `openai/` provider allow-list → silently dropped |
| `compat.thinkingFormat` → `chat_template_kwargs.enable_thinking` | ⚠ **Unverified on the pinned image** | Not on the `openai/` allow-list on `main`; if dropped, the failure mode is thinking **ON** with HTTP 200 |
| `compat.thinkingTokenBudgetField` → `thinking_token_budget` | ⚠ Same open question | `main` handles it for Bedrock only |
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
  "apiKey": "(litellm master key, or a scoped key once the gateway leg grants one)",
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
[`../scripts/pi-config/models-spec.yml`](../scripts/pi-config/models-spec.yml); the field-by-field
rationale below still explains every value, because the spec carries the same reasoning in its comments.

```bash
python3 scripts/render-pi-config.py --check     # drift gate: exit 1 when a machine diverged
python3 scripts/render-pi-config.py             # render (0600, timestamped backup of the previous file)
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

The model contract has exactly one editable form, and adding a client means adding a vendor rather
than copying numbers. `--vendor continue` renders the same models into a
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
  "defaultThinkingLevel": "high",
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

Other keys in the real file (`lastChangelogVersion`, `externalEditor`, `tuiMode`) are workstation
state, not spec — the block above plus `theme` and `packages` is the part that must match, and that
"must" is enforced rather than asserted: the keys live in
[`../pi-agent/settings-ssot.json`](../pi-agent/settings-ssot.json) and
[`../scripts/pi-settings-config.sh`](../scripts/pi-settings-config.sh) merges them into each seat's
file (owned keys replaced, everything else preserved, timestamped backup, an unparseable file is a
REFUSAL; `packages` is composed from the `versions.yml` pins and a seat-local package the repo does
not name — the cockpit's pi-web — is KEPT and printed, never deleted).

**The owned package set.** The set this plane writes is `pi-web-access` + `pi-open-tui` + `pi-subagents` +
`pi-deepseek-optimized`, each at its pin. `seat-local` is where an unmanaged package hides: a package named
only in an unversioned installer line is classified seat-local and **kept**, which reads as "fine, nothing to
do" while nothing converges it, no version is recorded anywhere, and a seat carries it only because someone
hand-ran `pi install` there. So every package a seat is meant to run is pinned and owned: the plane fails
(`--check --strict`) when a seat is missing one and `--push` restores it at the pin — an arm of `--self-test`
proves that half, and another proves the cockpit's pi-web still survives the same write.
`@season179/pi-worktree` and `@ogulcancelik/pi-ssh-tools` are NOT in the set: they are unversioned lines in
[`../scripts/install-pi-wsl.sh`](../scripts/install-pi-wsl.sh) owned by no plane — residue, not a ruling that
they are seat-only. What stays seat-local is exactly the placement a fleet key must not own: the cockpit's
`@ygncode/pi-web` (`--with-package`). A seat-local entry is retired on the seat with `pi remove` — the sync
never deletes one.

**Which pi build a seat runs is a pinned value too** (`pi_host_npm_version`, and `pi_dev_npm_version` must equal it — both are `1.1.0`, and the reasoning lives in the `versions.yml` pin lines, not in prose). Every other plane compares files, so without a binary plane a seat quietly runs a pi release the repo has not reviewed. [`../scripts/pi-self-update.sh`](../scripts/pi-self-update.sh) is that plane: `BEHIND` and `AHEAD` are both drift, an already-correct seat runs nothing, and `--push` re-probes the binary instead of trusting the installer.

**One rule about that `packages` list:** an
extension package must NOT list a host-provided module in `dependencies`. pi's loader compares each
installed manifest's `dependencies` against `HOST_PROVIDED_EXTENSION_PACKAGES` (`typebox`,
`@sinclair/typebox`, the `pi-ai` / `pi-tui` / `pi-coding-agent` families) and prints on every start:
`Host-provided extension packages must be declared in peerDependencies with a "*" range, not
dependencies`. Not style: an extension that installs its OWN `typebox` gets a second runtime module
beside the host's, bypassing the extension loader — a **pin** problem wearing an extension's clothes.
The fix is the pin, never an edit into someone's `node_modules`, and no pin has to move:
`pi_web_access_version` is `0.36.0`, whose installed manifest declares `peerDependencies.typebox: "*"`
and carries no `typebox` entry in `dependencies` (upstream moved the declaration in 0.32.0,
registry-verified across all 46 published versions). The value of a pin is its `versions.yml` line, not a
number quoted in prose. The predicate is one read of a
manifest, so `pi list` plus a manifest scan proves it, and deleting a hoisted copy is undone by the
next install.

**There is no settings VENDOR in `render-pi-config.py`, and that boundary holds — but §5 is
not the only source.** `render-pi-config.py --vendor` speaks `pi` / `pi_auth` / `continue` /
`all`; the spec renders the **model contract**, never someone's editor settings
([`../scripts/pi-config/models-spec.yml`](../scripts/pi-config/models-spec.yml) says so in its own
comment). The harness keys are a repo file plus a merge script, not a hand-copied doc block — the
re-decision is recorded here, not buried in an edit. `models-spec.yml` names `settings.json` as
machine-local, and the keys it names are machine-local; the harness block is not. "Render
`settings.json` from the spec" names a command that does not exist and must not be revived:
a vendor would rewrite the whole file and delete a seat's own packages. Both carriers today: the laptop, and
oldsrv's seat (the §5 block + `packages`, live 2026-10-01).

**`defaultThinkingLevel: high` — thinking ON from the first turn.** What the setting actually does, read off
pi's own resolver and compat code rather than inferred from a UI label: the startup level comes from
**settings.json only**
(`modelThinkingLevels["<provider>/<modelId>"]` → `defaultThinkingLevel` → pi's built-in `medium`) —
**models.json has no default-thinking field**; its `ModelDefinitionSchema` carries `reasoning` /
`thinkingLevelMap` / `samplingParams*`, which decide which levels *exist* and what each *sends*, never
which one starts a session. And because §4's `thinkingLevelMap` nulls every level except `off`/`high`,
**`high` is the only ON level this model has** — `medium`/`xhigh` clamp *up* to it — so `high` is the one
correct spelling of "thinking on by default". Cost, in the currencies §2 measures: every turn sends
`chat_template_kwargs.enable_thinking: true` plus `thinking_token_budget: 8192`
(`thinkingBudgets.high`); the *uncontrolled* template would spend 23–121 hidden reasoning tokens/turn,
thinking-on decode is ~11 tok/s, and reasoning tokens occupy blocks in the shared ~262k KV pool — so a long
turn is minutes and a concurrent lane feels it (§6). Rows with
`reasoning: false` (the laptop's vision + FIM legs) are untouched; pi clamps them to `off`.
**Seat state:** all three seats read `high`. The `--check` drift gate cannot see this key because
settings.json sits deliberately outside the render — a seat can disagree with §5 in silence, and only a
`pi-settings-config.sh` merge (or a human) proves it. The seat's own file is 0600 `domen`, so the runner key
cannot read it; an owner session on the box can.

**`theme` — why an unset `theme` makes two seats look different.**
pi's default theme is `system`: it queries the terminal's background and 16 ANSI colors and rebuilds its
palette from the answer, so an unset `theme` key means *the terminal decides*. pi's truecolor hint is
`COLORTERM=truecolor|24bit` or `TERM=*-direct` (read off `detectCapabilitiesFromEnvironment` in pi's own
bundle, not inferred from a UI label); the seat's leg is plain SSH with **`COLORTERM` unset** and
`TERM=xterm-256color`, so pi gamut-maps the derived palette down to the 256-color
set — a visibly flatter picture than the laptop's seat in the same session. Set it on a seat with
`"theme": "dark"` (pi's built-in terminal-independent palette; `/reload` to apply).
**The boundary does not move.** `render-pi-config.py --vendor` still has no settings vendor and
`models-spec.yml` still forbids `theme` in the spec, so this stays a hand-written per-machine key with
this section as its source — and the drift gate remains blind to it, the same blindness that lets the
`defaultThinkingLevel` halves divide. **Seat state:** all three seats read `dark` at rest; the laptop half is
owner-REPORTED, not measured. There is no oldsrv→laptop leg (`domenp14s` is a `hosts:`
label for the renderer, not an ssh target), so nothing on this box can read that half, and §5 has no
renderer to check it with either. If they diverge, the only detector is a human running
`grep '"theme"' ~/.pi/agent/settings.json` on each machine — the standing cost of keeping this key outside
the render.

| Setting | Value | Why on this box |
|---------|-------|-----------------|
| `defaultThinkingLevel` | `high` | thinking ON from the first turn: `enable_thinking: true` + the 8192-token `thinkingBudgets.high` cap. `high` is the only ON level the §4 map leaves, so any other spelling clamps to this anyway. The ≈20–120 hidden reasoning tokens/turn that `off` would save are a deliberate cost — see the note above |
| `compaction.reserveTokens` | 16384 | pi compacts when context > `contextWindow − reserveTokens` = **245,760**; this is the "use the whole window" dial |
| `compaction.keepRecentTokens` | 32768 (default 20000) | larger verbatim tail survives a compaction — cheaper to keep when the window is 262k |
| `httpIdleTimeoutMs` | 900000 (default 300000) | a cold prefill of a large prompt emits no tokens until the first token; the 5-min default can kill the turn mid-prefill |
| `retry.provider.timeoutMs` | 1800000 | same reason, per-request ceiling (SDK default is far below a 200k cold prefill) |
| `showCacheMissNotices` | `true` | server-side `--enable-prefix-caching` is the only reason a 200k turn is cheap — the notice shows when the harness broke a cached prefix |
| `thinkingBudgets` | 1k/2k/4k/8k | only applied when thinking is ON (needs `thinkingTokenBudgetField`); bounds what "high" can spend |
| `theme` | `dark` | `dark` is terminal-independent, and absence is not neutral: it selects pi's `system` theme, which paints from the terminal's own palette — over the seat's SSH leg (`COLORTERM` unset) that lands on the 256-color approximation, so the cockpit and the laptop do not match. All three seats read `dark`; the laptop half is owner-reported, not measured. Still NOT rendered (§1, `models-spec.yml`) |

---

**Carriers.** No renderer exists for `settings.json` by design ("render settings.json from the spec" names a
command that must not be revived), so §5 is the source and the seat's block is written **from this section**,
not copied off the laptop; a seat's own extra `modelThinkingLevels` / `lastChangelogVersion`-class keys are
workstation state and are preserved by the merge. The host-side bootstrap for a bare Debian seat is
[`../scripts/install-pi-debian.sh`](../scripts/install-pi-debian.sh) — it installs the pinned
Node tarball + the pinned pi and reads its pins from
`IaC/ansible/group_vars/all/versions.yml`, the same `pi_host_*` pins that keep a seat from trailing the
laptop (§1).

## 5a. Seat identity — which box the footer names

Three seats exist and two run this harness daily — **Win11** and **the oldsrv cockpit**. The WSL Debian
seat is **retained but rarely used**, and it stays in `pi-seat-sync.sh`'s `SEATS` on purpose: a
fan-out must still name it, and it will keep reporting `UNREACHABLE`/drift honestly until
`install-pi-wsl.sh` has been run there (its `pi` on PATH is the Windows Volta shim). That is also why the
"two seats on ONE machine" case below is occasional rather than daily. **Pi has no setting for footer
content** — `settings.md` §Terminal and display carries `theme`/`tuiMode`/`terminal.*` and nothing else,
and the default footer shows folder / model / context / cost. So "which machine am I typing to" is only
answerable from an extension, and this section is the only place that fact is written down.

- **The mechanism:** the pi package `pi-open-tui` (pin
  `pi_host_tui_npm_*`) draws the whole footer, and its `footerSegments.hostname` segment prints
  `os.hostname()` in short form. The hand-written `pi-agent/extensions/host-status.ts` is **retired**
  with it — a `ctx.ui.setStatus` line under a package-drawn footer is two sources of truth for one
  line, and the package owns the line. Retirement is a MECHANISM, not a deletion:
  `sync-extensions.sh --push` never deletes a deployed-only file, so without the script's
  `RETIRED` list a deleted extension stays loaded on every seat forever, invisible to a gate that
  compares only repo-side files. Also on that list: `remote-bash.ts`
  (Windows `sshpass.exe` + drive-letter paths, never in the repo by design).
- **The trap that makes this a script and not a note:** pi-open-tui's `DEFAULT_CONFIG` ships
  `footerSegments.hostname: false`. A seat that only ran `pi install npm:pi-open-tui` therefore has
  an **anonymous footer** — precisely the regression retiring the extension would have caused, and
  it lands where nobody looks (the SSH legs, where the prompt is gone). So
  [`../scripts/pi-tui-config.sh`](../scripts/pi-tui-config.sh) asserts that ONE key: it creates the
  minimal override file when absent, preserves every other key the operator tuned through
  `/open-tui`, and REFUSES to rewrite an unparseable file. Both installers call it; `validate-all.sh`
  gates it (self-test + `--check --strict`).
- **Deploy direction:** repo `pi-agent/` + `skills/` is SSOT → `bash scripts/pi-seat-sync.sh --push`
  runs every plane on every seat,
  and per plane `sync-skills.sh` / [`sync-extensions.sh`](../scripts/sync-extensions.sh) (item 27).
  A **deployed-only** extension is still deliberately NOT drift — it is reported `LOCAL`, never
  deleted, never imported; only a name on the `RETIRED` list is removed. The self-test asserts both
  halves, so the retirement rule cannot quietly swallow the `LOCAL` rule.
- **Keyboard, not just mouse:** inside tmux pi 1.1.0 runs `tmux show -gv extended-keys` at start-up and warns unless the answer is `on`/`always`, then warns AGAIN when `extended-keys-format` is `xterm`, because pi speaks CSI-u. On tmux 3.5a the defaults are `extended-keys=off` AND `extended-keys-format=xterm` — tmux still defaults the FORMAT to xterm, so setting only the first option swaps one warning for the other. Both lines live in `pi-agent/tmux/tmux.conf`; `install-tmux-conf.sh --reload` sources the RUNNING server, because a server that was already up keeps its old values whatever the file says — and on tmux < 3.3 neither option exists, where pi stays silent too, so an option-absent answer is reported and never failed.
- **The font is part of this, not a nicety:** pi-open-tui's icons are Nerd Font private-use glyphs,
  and its `icons.mode: auto` chooses them from the TERMINAL ENVIRONMENT, never from the installed
  font file. The release is pinned (`nerd_fonts_version`) and installed by
  [`../scripts/install-nerd-font.sh`](../scripts/install-nerd-font.sh) on the Debian seats and by
  [`../scripts/win/install-nerd-font.ps1`](../scripts/win/install-nerd-font.ps1) per-user on the
  Windows one — and **the Windows leg is the one that draws** (on this workstation that leg is already satisfied **machine-wide**: JetBrainsMono is installed globally and `install-nerd-font.ps1 -Check` reports `OK (machine-wide)` rather than nagging for a duplicate per-user install — an operator who already did the thing is DONE, not drift), because on WSL and on every SSH leg
  the terminal runs on the machine you type from. Having the font installed is not the same as the
  terminal selecting it: that stays a `fontFace` choice in the terminal profile, and `unicode` mode
  is the documented fallback when a box has no patched font.
- **Under `pipefail`, never `producer | grep -q`** — the early exit is a bug in the probe, never news about
  the producer. `grep -q` exits at the FIRST match while `fc-list` is still writing, so `fc-list` dies of
  SIGPIPE (rc **141**) and `set -o pipefail` promotes the dead producer to a failed pipeline even though grep
  found the family and returned 0 — a red font plane on a seat whose font is placed, hashed AND registered.
  It bites well under the 64 KiB pipe, because `fc-list` emits in chunks across its cache scan. The fix is to
  capture the listing and search the captured text: the producer is finished before grep starts, so there is
  no race. A self-test whose fake producer prints one line cannot see this — the same "a test that cannot
  fail is not evidence" trap as §5b's `-eq 1` (CONVENTIONS §6) — so self-test arm 8 breeds it (family first,
  ~160 KB of filler after it, counting chunks so a GREEN can tell "drained" from "this host's buffer
  absorbed it").
  **Seat state:** the fixed driver run from the cockpit gives 8/8 green including `pi-self` (1.1.0 == the
  `pi_host_npm_version` pin), and `validate-all.sh` exits 0 there. The retired `host-status.ts` is gone from
  every seat — the Win11 copy is removed by that seat's own `--push` — so the retirement mechanism has
  reached every seat and `validate-all.sh`'s RETIRED arm has nothing left to fail on.
- **Running the driver ON the oldsrv box (seat == host):** all three of
  [`../scripts/pi-seat-sync.sh`](../scripts/pi-seat-sync.sh)'s legs are laptop-side — `win11` is "this
  shell" only on the Windows workstation, `wsl` needs `wsl.exe`, and `oldsrv` sshes to `oldsrv-domen`,
  an alias that exists in the *workstation's* ssh config. Run the driver on oldsrv itself and every
  leg reads `UNREACHABLE` (rc 1) with three different true reasons, which is the fail-closed contract
  working, not a broken seat. From the seat, run that seat's own plane list locally instead — the same
  seven commands `planes_for_seat oldsrv` prints, in the same order, from the same clone (pre-flight
  still applies: the clone must be at `origin/main`). One seat-side failure is NOT the repo's fault:
  the `models` plane resolves credentials at render time, so a `TLS handshake timeout` from `op` is a
  transient 1Password/network fault — retry it, and never reach for `--keep-legacy-credentials`, which
  would paper over a provider the spec expects to be managed.
- **The laptop seat is the only leg nothing on the oldsrv box can reach:** one
  `bash scripts/sync-extensions.sh --push` there, then `/reload`, and the footer reads **`@ DomenP14s`**.
  The same kind of run takes `bash scripts/validate-all.sh` **non-interactively** to `OK: all validators
  passed` with the `launcher: ~/ansible-venv activated` line.
- **Bonus invariant, not decoration:** the token the footer prints is the one `host_norm()`
  (`../scripts/render-pi-config.py`) uses for a provider's `hosts:` scope — `DomenP14s` normalises to the
  spec row `domenp14s`. A case/SEPARATOR mismatch there silently
  drops a provider from the picker in both directions; the footer makes that invariant visible, so the
  wrong machine shows up before it becomes a missing provider.
- **What it does NOT distinguish is two seats on ONE machine** — Win11 and WSL Debian report the same
  Windows-derived hostname. It answers "which box" (the cockpit-vs-laptop question over SSH, where the
  prompt is gone), not "which seat". The WSL marker is available (`/proc/version` carries `microsoft`, which
  `laptop-llm.py` already reads) and deliberately NOT used here: a second host-identity signal invented in
  a footer would drift from the one `host_norm()` owns.

## 5b. The seat's terminal harness — tmux mouse + OSC 52 clipboard

pi runs inside tmux on the Debian seats — **one in active use**, oldsrv — and two things a
session touches every minute are **terminal-level, not pi-level**: the mouse and the clipboard. Repo
SSOT [`../pi-agent/tmux/tmux.conf`](../pi-agent/tmux/tmux.conf) → `~/.tmux.conf`, installed and *proved*
by [`../scripts/install-tmux-conf.sh`](../scripts/install-tmux-conf.sh), drift-gated by
[`../scripts/README.md`](../scripts/README.md) → validate-all item 29.

| Action | Result on the seat |
|---|---|
| click pane / click status / drag border | focus pane / switch window / resize pane |
| drag text, double- or triple-click | selection → tmux buffer **and** the outer clipboard |
| wheel in a shell pane | history scroll (`history-limit 100000`, 5 lines/notch) |
| wheel over a TUI that grabs the mouse (pi, vim, htop) | passed through raw — tmux never intercepts it |
| `prefix m` | toggle mouse off/on without editing the file — the escape hatch when capture gets in the way |
| SHIFT held while dragging | the outer terminal's own selection, bypassing tmux |

### Why the installer loads the file instead of comparing it

`cmp` proves the right bytes are on disk. It cannot prove tmux obeyed them, and the failure mode is
silent: **a config that errors mid-load leaves the options at their DEFAULTS and the caller still gets
exit 0 with empty stderr** (tmux reports a config failure as a client *message*; a detached
`new-session` has no client to print it to). Measured on tmux 3.5a, six fixtures, each loaded with
`tmux -L <sock> -f <conf> new-session -d` and read back with `tmux show -g …`:

| fixture appended to a working config | reads back | verdict |
|---|---|---|
| *(nothing — the SSOT as-is)* | `mouse on`, `history-limit 100000`, `mode-keys vi` | EFFECTIVE |
| block opened at end of a line, closed on its own line | same | EFFECTIVE |
| backslash-continued command | same | EFFECTIVE |
| one bad command (`select-pane -t = extra extra extra`) | `mouse off`, `2000`, `emacs` | **INERT** |
| unknown command | same defaults | **INERT** |
| nested wrapped `if-shell { } { }` | same defaults | **INERT** |
| unterminated quote at the end | `mouse on`, `mode-keys emacs` | **PARTIAL** |

Two conclusions, both load-bearing: **which part** of a file survives an error is not predictable from
the parser (last row — a later option applied while an earlier one did not), and a static "looks like a
bad block" rule cannot be written honestly, because the first two wrapped shapes load fine while the
nested one does not. So the gate starts a throwaway server on a private socket and **reads the options
back** — and its own canaries mutate the fixture, not the checker (CONVENTIONS §6: a test that cannot
fail is not evidence). The probe must not key on a raw failure *count*: two failed assertions read as `2`,
which is also the SKIP code, so a count-shaped verdict can print green over inert canaries.

### The clipboard leg — OSC 52, measured

oldsrv is headless: no `xclip`, no `xsel`, no `wl-clipboard`, and the clipboard lives on the machine
you typed into. The only path is an **OSC 52 escape sequence written to the outer terminal through
SSH**, which tmux emits only when the client terminal is credited with the capability — either by
tmux's built-in terminal-NAME table (`xterm*`/`vte`: credited; `screen`, `tmux`, `vt220`, `linux`: not)
or by an `Ms` terminfo capability. **No terminfo entry on this box carries `Ms`** — `infocmp -1 <term>`
shows none for `xterm-256color`, `screen-256color`, `tmux-256color`, `vt100`, `vt220` or `linux` — so the
SSOT's `terminal-overrides ',*:Ms=\E]52;%p1%s;%p2%s\7'` is what earns the sequence on a
non-`xterm`-classified seat:

| probe client `TERM` | `Ms` override present | OSC 52 sequences on the wire |
|---|---|---|
| `xterm-256color` | yes | 1 |
| `screen-256color` | yes | **1** |
| `screen-256color` | no | **0** ← the canary |
| `vt100` | no | 0 |

Three facts that are easy to get wrong, each measured here rather than assumed:

- **A `set-buffer` emits nothing.** Only a **selection** (`copy-mode` → `begin-selection` →
  `copy-selection-and-cancel`, i.e. what a mouse drag or `y` does) produces the sequence. A probe built
  on `set-buffer` reports a working clipboard no user can reach.
- **`#{client_termfeatures}` is a belief about the terminal's NAME, not a capability read.** Its
  `clipboard` flag tracks the wire in the rows above but is not a read of the capability: a probe
  client with `TERM=tmux-256color` reports no `clipboard` while tmux emits OSC 52 for it. The gate reads
  the **bytes** (attach a `script(1)` pty client, capture, grep for `\033]52;`); the flag is printed as
  information only.
- **`set-clipboard on`, not the default `external`**: `external` lets tmux's own commands and key
  bindings set the outer clipboard but ignores one written by a program running *inside* tmux, and a
  coding agent is exactly such a program.

### Apply and verify

```bash
bash scripts/install-tmux-conf.sh --check          # SSOT vs ~/.tmux.conf + load probe (report-only)
bash scripts/install-tmux-conf.sh --push           # install; a foreign ~/.tmux.conf is a REFUSAL (+ --force, backup kept)
bash scripts/install-tmux-conf.sh --reload         # install + source into the RUNNING server + read it back
bash scripts/install-tmux-conf.sh --verify         # load probe + OSC 52 emission on the wire + live server
```

`--check` exits 0 on drift unless `--strict` (the `sync-skills.sh`/`sync-extensions.sh` contract: the
gate owns the decision to fail), but an **ineffective** config fails in every mode — that is a defect,
not a seat state. `--self-test` runs seven canaries (rest green, missing, drift, foreign-refusal +
backup, **two inert-config arms that are byte-identical by construction**, the `Ms` removal, and
`set-clipboard off`) and is wired into `validate-all.sh` item 29.

End-to-end by hand, the way a person notices it: select text with the mouse in a tmux pane, then paste
it on the machine you are sitting at. If nothing arrives, the seat's config is fine and the **outer
terminal is refusing OSC 52** — `xterm` needs the `allowWindowOps: true` resource; VTE ≥ 0.60, kitty,
wezterm, foot and alacritty accept by default. Nothing inside tmux can fix that leg, which is why it is
an ⏳ owner-gated tail and not a bug in the script.

**Not wired yet:** neither [`../scripts/install-pi-debian.sh`](../scripts/install-pi-debian.sh) nor
[`../scripts/install-pi-wsl.sh`](../scripts/install-pi-wsl.sh) calls this installer, so a freshly
bootstrapped seat still gets no `~/.tmux.conf`. Run it once
per seat until that step lands.

### The three ways this plane's own scripts can lie

All three are the CONVENTIONS §6 class — a verdict printed at an environment boundary. The rescue path that
surfaced two of them is [orchestration.md](orchestration.md) §4 step 5: a lane branch can already be an
ancestor of `main`, so `git branch -d` succeeds and uncommitted work dies with the directory — only
`git status --porcelain` inside the lane sees it.

1. **The installer collapsed a three-state rc into one note.** `install-tmux-conf.sh --push` ends in the load
   probe, so **0 = installed AND effective, 1 = a real defect** (refusal / CRLF / inert file), **2 = installed
   but UNPROVEN** (no tmux binary here). `… --push || info "…reported a problem"` printed rc 1 as a note, so a
   genuinely broken seat harness configured GREEN. `install-pi-debian.sh` `case`s all three.
2. **`check()` aborted at the first drift and printed nothing.** Under `set -euo pipefail` a bare
   `X --check 2>&1 | tail -2` is a failing pipeline, so `set -e` killed the script at that line: the settings,
   font, tmux and tui legs and the `check: GREEN|DRIFT` summary never ran — the first skill drift made the
   whole seat gate go silent. Proved both ways: `set -euo pipefail; false 2>&1 | tail -2; echo REACHED` prints
   **nothing**; with `|| bad=1` it prints `REACHED` and `bad=1`. Three sites carry the pattern — the
   `sync-skills`, `sync-extensions` and `install-nerd-font` checks in `install-pi-debian.sh` — and every one
   of them needs the `|| bad=1` guard.
3. **`--check` must not say "and effective" while printing SKIP.** With no tmux the load probe returns 2, the
   byte-compare passes, and the verdict line can print `OK: … == repo SSOT and effective` two lines after an
   honest SKIP. The two arms are: tmux present → `load probe OK … and effective`; a
   tmux-less seat → `SKIP: … IN PLACE; effectiveness UNPROVEN — a SKIP, not a pass`. Same rc, honest words:
   **in place ≠ effective**.

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
- ⏳ `spark-lane` profile (§6) is authored-on-paper only; promote it into the reference config once a
  real orchestrator run measures lane-vs-preemption behavior.
- **Pointer (not a tail):** the workstation's two other local model legs — **FIM autocomplete** and **Qwen3-VL visual judgment** (vision reaches spark only as *text*; the engine is text-only) — are owned by [`hardware-workstation.md`](hardware-workstation.md) + decision #28 in [`services-ai.md`](services-ai.md) §9. Nothing here changes; the harness stays direct-to-engine (decision #26).
