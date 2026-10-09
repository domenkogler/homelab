---
title: AI Platform — Rejected / Dropped Decision Log
role: log
domain: services
status: active
tags: [services, ai, rejected, decision-log, rag, memory]
---
# AI Platform — Rejected / Dropped

> **Role:** Decision log for the **AI platform plane** (gateway / RAG / memory / agent harnesses) — the
> candidates the `services-ai` domain evaluated and declined, with the measured result that closed each one.
> This log is that plane's decision-log SSOT (`CONVENTIONS.md` §8.3).
> **Links to:** [`services-ai.md`](services-ai.md), [`../reports/probe-ov-20260921.md`](../reports/probe-ov-20260921.md),
> [`../reports/probe-agentmemory-20260921.md`](../reports/probe-agentmemory-20260921.md),
> [`CONVENTIONS.md`](../CONVENTIONS.md) §8.3
> **Linked from:** [`index.md`](index.md), [`services-ai.md`](services-ai.md)

> ⚠️ **Append-only.** Do not edit a landed decision; a changed decision is a **new row**, left alongside the old
> one — never a strike/replace. One row per subject, sorted by subject. Each row:
> `| <subject> | <rejected|dropped|superseded> | <why, max ~12 words> |`.
> A re-review is allowed **only with an exception note** ("re-evaluating X because Y changed"), per §8.3.

## Decisions

| Subject | Status | Why |
|---------|--------|-----|
| A wrapper service for OpenAI-shaped STT | rejected | `--inference-path` relocates the route; HA Assist needs no glue |
| `agentmemory` central instance as briefed | rejected | Loopback REST, one shared bearer, no per-user isolation |
| `agentmemory` LLM compression (consolidation, graph extraction) | rejected | Drops every identifier: retrieval-key 0/5 |
| `ar-dv` (AR-hybrid + draft-vocab slice) | rejected | Slice lowers MTP acceptance 54.7 to 36.8 %, slows decode |
| `ar-mmap` (AR-hybrid + FP8 PLE mmap) | rejected | Control arm, on par with tier-1, not a candidate |
| `awq-mmap` / B10 (AWQ on the winner's machinery) | dropped | Owner certified the AR-hybrid winner instead |
| Bigger window or smaller quant to reopen the agent leg | rejected | The wall is cold prefill, not the carve or context |
| Coding harnesses behind the LAN LiteLLM hop | rejected | Decision #26 puts harnesses direct on the spark name edge |
| Coding-seat surfaces in a container | rejected | Would mount the whole watched home tree: theatre |
| Copying a laptop settings.json to a seat | rejected | Settings have no renderer; pi-harness §5 is the source |
| CrewAI pilot | dropped | Parked until one real multi-agent epic mishandles a lane |
| Cross-encoder rerank computed from `/api/embed` embeddings | rejected | A cross-encoder cannot be rebuilt from two embeddings |
| Dedicated exporter or scrape target for the pinned AI legs | dropped | Alloy host metrics plus `amdgpu` sysfs counters cover them |
| Docling `/tmp:exec` | rejected | Makes a `read_only` container's tmpfs writable plus executable |
| Docling `do_ocr=false` on scans | rejected | A scanner's own text layer carries no diacritics |
| Docling `HF_HOME` repoint | rejected | `artifacts_path` is set: the served path never downloads |
| Docling on the RX 7600 | rejected | Accelerator set has no Vulkan/ROCm; CPU only |
| Docling tesseract for Slovenian | rejected | The image ships only `eng` + `osd` traineddata |
| `dsh` / `pi-dev` as `docker_services` entries | superseded | Dedicated deployments now; their routes answer 502 by design |
| `dsh_api` scoped consumer | rejected | Harnesses go direct (#26); the record is not restored |
| EasyOCR as the Docling OCR engine | rejected | 3.2–3.4× slower, with its own diacritic and merge defects |
| External APIs as a proxy fallback | rejected | A harness-side fallback, never a gateway fallback |
| `fallback/login` as the LiteLLM login path | rejected | `/ui/login` resolves on the pinned build |
| `fast` NVFP4 profile (mixed NVFP4/FP8 weights) | superseded | JIT-compiles QSA/GDN kernels; the name now marks the winner |
| `fast-sglang` (SGLang + RadixArk NVFP4) | rejected | No arm64 digest, pool too small, PLE bind unwired |
| forward-auth on LiteLLM `/ui/*` route-wide | rejected | Breaks the same-host API bearer consumers |
| `graded` (fp8 main KV cache, same AWQ weights) | rejected | Pinned build has no fp8 KV; needs the engine-pin lane |
| Hand-typed `hosts` entries for `.ts.kogler.si` names | rejected | Forbidden form; the generated alias artifact is sanctioned |
| Hermes keeping its own memory store | rejected | Owner ruling: one memory plane, not a second store |
| `insanely-fast-whisper-rocm` | rejected | gfx1030 override, unconfined seccomp, unused feature set |
| LM Studio as a local AGENT runtime on the workstation | dropped | Cold prefill, minutes per turn; laptop serves FIM + vision only |
| MCP on a shared literal port | superseded | Ports are vars, never literals (`cockpit_pi_web_port`) |
| `never-evict` prompt pin (`--never-evict-kv-cache-*`) | rejected | Zero blocks reserved; prefix caching already serves 95.1 % |
| nginx sidecar for `/ui/<route>/<id>` deep links | rejected | Defect measures absent; a sidecar invents its own failure surface |
| `nv-patch` (NVFP4 + patches) | rejected | PLE table lacks ngram_embedding keys; crash-restart loop |
| Ollama as the primary embed engine | superseded | The llama.cpp Vulkan leg is the row; Ollama stays the fallback |
| Ollama as the rerank host | rejected | No rerank API at any released version |
| ONNX Runtime GPU on RDNA3 | rejected | ROCm/MIGraphX is Instinct-only (gfx942, gfx950) |
| Open WebUI built-in RAG as the retrieval plane | rejected | The vector store stays independent of any UI shell |
| `openai/` provider for the embed row | rejected | Forwards `encoding_format: null`; llama.cpp rejects null |
| OpenViking as the corpus / knowledge index | rejected | 12/51 byte-identical; H1-slug directories, not reversible |
| OpenViking as the memory plane | rejected | LLM-bound write path taxes the shared KV pool |
| OpenViking deferred as 'Docker-only' | rejected | False: venv-native install in about 2 minutes |
| `os.environ/` references in DB `litellm_params` | rejected | Not expanded; the literal string reaches the engine |
| Paseo coding seat on oldsrv | dropped | Parked; acceptance needs a hand on the phone |
| PGVector as the vector store | superseded | Qdrant stands alone, hybrid dense + sparse |
| Phase-2 Ryzen 9 9900X / R9700 build | superseded | spark (ThinkStation PGX / GB10) replaces it (#22) |
| `pi` shim in `~/.local/bin` for the pi-web PATH | rejected | Node's bin dir must be on PATH, not a login-shell path |
| `pi-agent/extensions/host-status.ts` seat-identity footer | superseded | `pi-open-tui` footer `hostname` segment is the single source |
| `pi-web` behind gateway-auth | rejected | Phone-driven cockpit: no browser for an Authentik flow |
| `pi-web` on a `tailscale0` address bind | rejected | Plain HTTP, no cert, unreachable from every other node |
| `pi.kogler.si` as the oldsrv seat URL | rejected | That FQDN is the RPi4 node; hence the `-oldsrv` suffix |
| Pinned legs on the flat `services-internal` network | rejected | The network is the boundary; LiteLLM alone reaches them |
| Raising the LiteLLM proxy log level to see dropped params | rejected | It logs token-bearing request bodies |
| Reflex key rotation after a partial-value leak | rejected | The documented rotation procedure carries it |
| Routing-domain split for `.ts.kogler.si` names | rejected | Ruled out; the generated alias artifact is the remedy |
| TEI (text-embeddings-inference) on the RX 7600 | rejected | No RDNA3 path; a 7-step self-build, flash-attn dropped |
| `u1-patch` (patched lineage + AWQ, no spec decode) | rejected | Isolation control, beat by ar-blk |
| `u3-s8` (u2-blk + seqs=8 + piecewise graphs) | rejected | No speed win; the +40 GB stranding claim was a PID misread |
| `u4-pin` (u2-blk + never-evict 0.03) | rejected | Neutral: identical recompute delta, zero preemptions |
| `v16b` (full upstream recipe) | rejected | Below ar-blk and memory-infeasible at C2L |
| `v16b-pin` (`v16b-s4` + never-evict 0.03) | rejected | Pin neutral; recipe below ar-blk (MTP 19.3 %) |
| `v16b-s4` (`v16b` at seqs=4) | rejected | Ran, but −17 % vs ar-blk: the draft-vocab drag |
| Vision on spark | rejected | spark runs a text-only engine (#28) |
| Vision-LLM leg on the RX 7600 | rejected | Vision is a workstation text cascade (#28) |
| `whisper.cpp` HIP/ROCm image for STT | rejected | No published ROCm artifact; self-build, no digest trail |
| ZeroClaw on the VPS | rejected | Fleet credentials on an internet-facing host |

## What would reopen OV

A re-review needs an exception note naming what changed (§8.3). The changes that would move this decision:

1. **Fidelity** — a mode that stores source documents verbatim and reversibly (filename preserved), passing the
   same 8-check rubric in
   [`../reports/probe-ov-20260921/p1_metrics.py`](../reports/probe-ov-20260921/p1_metrics.py) at **≥ 45/51**
   byte-identical on this repo's 51-file slice.
2. **Write path** — an **LLM-free capture/commit mode** (or a documented way to run the commit path on a
   non-shared engine), so a memory plane stops taxing the KV pool the agent is talking on.
3. **Compile cost** — ingest throughput better than **~740 prompt + 250 completion tokens per KB** of docs
   (measured: ~14 min per 163 KB at `max_concurrent=3`; the whole repo extrapolates to ≈ 3.8 M prompt /
   1.25 M completion tokens and 7–30 h).
4. **A requirement we do not have today** — one plane across harnesses *including* a hosted tier, with
   per-user/agent ACL as a hard need. That is the only axis where OV's scope/ACL model beat the alternatives.

Not rejections, and therefore not rows above:

- `local-rerank` keeps a real consumer class (Jina-format rerank callers).
- The **OV-vs-grep retrieval baseline** — **8/10 hit@5 at 5,267 tokens** per question vs grep **5/10 at
  92,004** — is the number `rag-mcp` is on the hook to match: retrieval efficiency was OV's genuine strength,
  fidelity and cost were not.
