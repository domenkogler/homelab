---
title: Voice Pipeline
role: detail
domain: smart-home
status: active
tags: [smart-home, voice, whisper, piper]
---
# Voice Pipeline

> **Role:** Detail — Whisper STT, LLM, Piper TTS pipeline.
> **Links to:** `hardware-gpu.md`, `services-office.md`
> **Linked from:** `smart-home.md`
>
> **Shape (decision #24):** Whisper STT runs on the **oldsrv RX 7600**, Piper TTS on **CPU**, and the LLM
> leg (intent/response) is meant to be a **gateway model** reached through LiteLLM like every other
> simple querier — never a direct engine URL. See [services-ai.md](services-ai.md) §Architecture for the
> routing model and §9c for the GPU model.
>
> ✅ **The leg is LIVE (2026-10-09, HD-403) — voice has an LLM to call.** The LAN gateway already had the scoped
> key (`home-assistant_api`, minted 2026-09-27) and Home Assistant already shipped the surface; what was missing
> was the config entry, and that is now in place on the Pi primary:
>
> | Piece | Value (as read back live 2026-10-09) |
> |---|---|
> | config entry | `litellm` domain, `entry_id 01M4GR0Y3WZTVFPX5DCCYMF235`, title `llitellm.kogler.si`, state `loaded`, source `user` |
> | entry data | `url = https://llitellm.kogler.si/v1` (the integration appends `/v1` itself) + the scoped `api_key` — in `.storage/core.config_entries`, **no template involved** |
> | conversation agent | subentry `spark/qwen3.8-flash-next` → entity **`conversation.spark_qwen3_8_flash_next`**, `llm_hass_api: [assist]`, prompt asks for one short Slovenian sentence |
> | Assist wire | the default pipeline `01m1k4tamb53mwh074jt2n9sfg` now has `conversation_engine: conversation.spark_qwen3_8_flash_next` (was `conversation.home_assistant`) |
> | acceptance | one Slovenian turn through the pipeline: *"Živjo, kolikšno temperaturo ima dnevna soba?"* → the agent called `homeassistant__GetLiveContext` three times and answered **"Trenutna temperatura v dnevni sobi je -10,0 °C."** (`intent-end`, `processed_locally: false`) |
> | reachability | the HA container resolves `llitellm.kogler.si` to the oldsrv home-leg address (see [network-addresses-generated.md](network-addresses-generated.md)) and TLS-validates it (`ssl_verify_result=0`, `401` without a key), so **no `extra_hosts` fallback was needed** |
> | replication | the standby copy on oldsrv carries the entry within one sync cycle — the plaintext-replication ruling in [deployment-secrets.md](deployment-secrets.md) §Runtime plaintext that leaves the vault is **not theoretical**, it was verified on the file |
>
> **Two honest caveats from the same run.** (a) The answer was *wrong*: there is **no exposed entity for the living
> room and no area named "Dnevna soba"**, so the agent settled on `Rekuperator Room Temperature` (-10 °C, the
> ventilation unit's outside-facing reading). The LLM leg works; the **entity/area exposure is the gap** — minted
> as its own row, not folded in here. (b) `language`/`conversation_language` on the pipeline are still **`en`** —
> the Slovenian reply came from the agent's prompt, which is fine for a text turn but will matter for the STT/TTS
> legs (they read the pipeline language), so that value belongs to the voice-hardware work, not this row.
> **Rollback (one line, no converge):** set `conversation_engine` back to `conversation.home_assistant` on the same
> pipeline — the built-in intent agent stays installed and needs no LLM.
>
> **How the entry was created without a browser** (the row said "config-flow only", which is true — it does **not**
> mean "a human must click"): `POST /api/config/config_entries/flow {"handler":"litellm"}` → progress with
> `{"url":…,"api_key":…}`; the agent itself is a **subentry**, started with
> `POST /api/config/config_entries/subentries/flow {"handler":["<entry_id>","conversation"]}` (the handler field is a
> **2-tuple**, not a name — anything else returns 500) and progressed with `model`/`llm_hass_api`/`prompt`. Pipelines
> are **websocket-only** in this build (`components/config/assist_pipeline.py` does not exist): `assist_pipeline/pipeline/list`
> then `assist_pipeline/pipeline/update` with the item's fields plus **`pipeline_id`** — ⚠ do **not** send the item's
> own `id` key, it collides with the websocket **message** id and the reply then carries the pipeline id, which makes a
> naive "wait for my id" loop hang forever. A text-only pipeline run is `assist_pipeline/run` with
> `start_stage: intent`, `end_stage: intent`, `input: {text, language}` — that is the shape that proves an Assist turn
> without anyone speaking to a satellite.
>
> ✅ **The HA-side surface is stock and already in the pinned version — no vendored component, no HA bump, and
> decision #24 stays intact** (measured from primary sources 2026-09-26). Home Assistant ships a `litellm`
> **conversation** integration: ha-core PR
> [#172960](https://github.com/home-assistant/core/pull/172960) **merged 2026-07-17**, first released in
> **2026.8.0** — probed at the release tags, `homeassistant/components/litellm/manifest.json` is **404 at 2026.7.0
> and 200 at 2026.8.0 / 2026.8.1** — and this repo pins `home_assistant_version` (`2026.9.4` since 2026-10-08, moved into `group_vars/all/versions.yml`), so the pin already
> carries it. It is the exact shape #24 asks for: **the URL of any LiteLLM proxy + an optional virtual key**, and
> the agent is usable in Assist like any other conversation agent
> ([integration docs](https://www.home-assistant.io/integrations/litellm/)). Read from the **2026.8.1 source**, not
> only the docs: `config_flow.py` takes `CONF_URL` (required; the OpenAI `/v1` path is appended if missing) +
> `CONF_API_KEY` (optional — placeholder `sk-no-key-required` when empty); the agent itself is a config-entry
> subentry holding `CONF_MODEL` / `CONF_PROMPT` / `CONF_LLM_HASS_API` (`LLM_API_ASSIST` is the recommended
> default); `requirements: ["openai==2.45.0"]` is bundled in the image, so nothing is installed at runtime;
> quality scale **bronze**. One delta vs the current release, non-blocking: reconfiguring an agent to have **no**
> tools does not stick until 2026.9 (#178490, a two-line `is None` fix).
> `openai_conversation` remains the wrong tool and is not a near-term option either — it targets only OpenAI's
> hosted endpoint, and upstream **closed** ha-core
> [#137087](https://github.com/home-assistant/core/issues/137087) (2025-03-27, `balloob`: *"not planning on
> implementing this"*), choosing a dedicated integration over a base-URL field.
>
> **Four constraints that therefore fix the order of work:**
> **(1)** the config flow calls `/v1/models` **before it creates the entry** (10 s timeout), so the gateway must be
> up and the key minted before HA can hold an entry — `oldsrv` → `bootstrap_keys` → mint `home-assistant_api` →
> HA entry → conversation agent → Assist pipeline;
> **(2)** the model picker is fed by `/v1/models` **as the scoped key**, so the allow-list row
> `spark/qwen3.8-flash-next` must be visible **to that key** — the same endpoint the bootstrap glue probes
> ([services-ai.md](services-ai.md) §4);
> **(3)** URL + key go into **HA's config entry** (`.storage/core.config_entries`); HA reads **no
> `LITELLM_BASE_URL` env var** and the integration has no YAML import, so
> `templates/docker_services/home-assistant-primary/**` needs no change and **no Pi converge is gated on the vault
> item** (the old fail-closed-render worry was aimed at a render that should never have existed);
> **(4)** ⚠ the same storage means the minted **virtual key sits in plaintext** in `/config/.storage/`, and the
> standby sync (`roles/home_assistant/templates/ha-config-sync.sh.j2` — `rsync --delete`, excluding only
> `secrets.yaml`) **replicates it to oldsrv**. ✅ That placement is **ruled and recorded** in
> [deployment-secrets.md](deployment-secrets.md) §Runtime plaintext that leaves the vault (ACCEPT, 2026-10-09, with
> the reopen trigger) — and the entry now exists, so the ruling is in effect.
> Tracked in **HD-403** (closed 2026-10-09), whose owner call (vendor / wait / relax #24) was
> **answered by the stock integration** — see [smart-home-rejected.md](smart-home-rejected.md).
>
> **Engine = `whisper.cpp` `main-vulkan`, digest-pinned** (decision #27) — RADV, native RDNA3, no ROCm
> userspace. Two earlier recipes were ruled out by evidence, not preference: a ROCm/`GGML_HIP` build
> (correct in theory, **no published artifact**) and PyTorch ROCm images (wrong target + heavy). The chain
> and its sources live in [services-ai.md](services-ai.md) §9 and
> [services-rejected.md](services-rejected.md). Two consequences worth carrying: **a build recipe nobody
> publishes is not an option**, and with Vulkan the weight lives on the card, so container RSS (~34 MiB) is
> **not** "VRAM used".
>
> Measured on this card: `large-v3-turbo` **0.40 s** per 11 s WAV at **1.72 GiB** VRAM; CPU fallback
> **17.5 s** — and that fallback is **native**, decided at init, so a container that never touches the GPU
> never notices. Numbers: [services-ai-bench.md](services-ai-bench.md) §2.

---

## Pipeline Flow

```
Microphone → Wake Word Detection → Whisper STT → LLM → Piper TTS → Speaker
   (ESP32)      (microWakeWord)      (RX 7600)   (spark)    (CPU)      (WiiM Bar)
```

---

## Wake Word Detection

### ESP32-S3 (Kitchen Display)
- **microWakeWord** — open-source, ESP32-compatible, Wyoming protocol
- **ESP-SR** (Espressif Speech Recognition) — built-in, free, custom wake words
- Limitation: ESP32-S3 limited RAM; ~2-word English wake words feasible

### Android Phones (Satellites)
- **Willow** (open-source) or **Home Assistant Companion** with Assist
- Far better microphones and noise cancellation than ESP32
- On-device wake word detection — no server load

> **Recommendation:** microWakeWord on ESP32-S3 for kitchen (fixed location, known acoustics). HA Assist on Android phones for other rooms. Both feed same central STT pipeline.

---

## Components

| Stage | Software | Hardware | Notes |
|-------|----------|----------|-------|
| **Wake Word** | microWakeWord / HA Assist | ESP32-S3 / Android | "Hey, assistant" |
| **STT** | **`whisper.cpp` `main-vulkan`** (`whisper-server`, digest-pinned) — **not** faster-whisper (CTranslate2 is CUDA-only) | **oldsrv RX 7600** (Vulkan/RADV — no `/dev/kfd`, no `HSA_*`) | **Slovenian** + English → text (multilingual GGML, measured `n_langs = 100`). **No OpenAI-compat wrapper needed**: `--inference-path /v1/audio/transcriptions` — measured, see [services-ai-bench.md](services-ai-bench.md) §2 |
| **LLM** | Gateway model via LiteLLM — `openai/spark/qwen3.8-flash-next` (fast) or `openai/spark/qwen3.6-27b` (reasoning) | **spark GB10**, through the gateway | Intent parsing, response generation |
| **TTS** | Piper TTS | **CPU** (decision #24 — CPU-only engine) | Text → Slovenian speech |

---

## GPU VRAM for Voice

When voice is active, GPU runs in **Pinned-AI** mode (decision #24):

| Model | VRAM |
|-------|------|
| Whisper STT (`large-v3-turbo` GGML) | ~2 GB → **measured 1.79 GiB fp16 / 0.77 GiB q5_0** ([services-ai-bench.md](services-ai-bench.md) §2) |
| bge-m3 embed (RAG, co-resident) | ~1–2 GB |
| bge-reranker (RAG, co-resident) | ~0.5 GiB **on the GPU** — the CPU detour was a stale-table artifact (#25) |
| **Total (pinned-AI)** | **2475 MiB measured all-three warm** (of 8 GB) — [hardware-gpu.md](hardware-gpu.md) |
| Piper TTS | **CPU** (~0.5 GB RAM, instant) |
| LLM (intent/response) | **spark GB10** (big-model tier) |

> **Why Vulkan and not ROCm:** `whisper.cpp` ships a ROCm Dockerfile but **publishes no ROCm artifact**
> (no ghcr tag, Docker Hub 404), so the ROCm route means owning a `GGML_HIP` + native-`gfx1102` build in
> this repo — a private compile-and-publish pipeline for a card whose real profile is RADV desktop graphics +
> compute. Also rejected: PyTorch ROCm images (they force `HSA_OVERRIDE_GFX_VERSION=10.3.0` = gfx1030 code
> paths on RDNA3, drag gradio/demucs/stable-ts, and want `seccomp=unconfined` + `SYS_PTRACE` + host IPC) and
> faster-whisper (CTranslate2 has no ROCm backend). The Vulkan image needs only `/dev/dri/renderD128` +
> `video`/`render` group membership. Decision chain + evidence:
> [services-ai.md](services-ai.md) §9 · [hardware-gpu.md](hardware-gpu.md).

> **VRAM priority (decision #24):** gaming > pinned-AI (voice/embed/rerank) > immich-ML. Pinned-AI measures
> **2475 MiB** all-three warm, so pinned-AI + immich-ML fit under 8 GB and immich-ML does not have to be
> paused for voice — and `pause` would not free VRAM anyway ([hardware-gpu.md](hardware-gpu.md)).

See [`hardware-gpu.md`](hardware-gpu.md) for the full VRAM management table.

---

## Language Pipeline

- **Wake word:** English (2 words — wider tool support)
- **STT:** English (Whisper supports multilingual, but English best accuracy)
- **LLM:** Slovenian response generation (spark big-model — Qwen3-Coder-Next-80B / Nemotron support Slovenian)
- **TTS:** Slovenian output (Piper has Slovenian voice models)

---

## Not Yet Implemented

Depends on:
1. oldsrv with GPU operational (RX 7600, pinned-AI mode)
2. Whisper (faster-whisper) + bge-m3/bge-reranker containers on oldsrv (decision #24)
3. Piper TTS on CPU
4. ESP32-S3 flashed with ESPHome + microWakeWord
5. HA Assist configured on family phones