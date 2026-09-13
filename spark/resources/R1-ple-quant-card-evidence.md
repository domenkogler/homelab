# R1 capture — primitive-ai/Qwen3.8-Flash-Next-PLE-quant model card (R1-relevant extraction)

Source URL: https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant
Captured: 2026-09 (pre-existing local capture `primitive-aiQwen3.8-Flash-Next-PLE.md`; this file extracts only R1 weight-provenance content, verbatim where quoted)
Note: lane had no web tools; text below is from the saved capture, not a live fetch.

## R1-relevant passages (verbatim)

> "The 51.2B-parameter n-gram (PLE) table is the reason this model wants ~100 GB of free host RAM: the CPU-offload worker holds it in BF16 (95.4 GB). This repo ships the same table quantized — FP8 per-row (49 GB), INT4 group-16 (32 GB), and NVFP4-style group-16 e2m1 (28.8 GB) — plus a two-file overlay for the `vllm/vllm-openai:qwen38-flash-next` image that serves them memory-mapped straight from disk."

> "Built from the original BF16 tables, so it works with any checkpoint of this model: our mixed NVFP4/FP8 build, our plain NVFP4, **the original model**, and, since 2026-09-06, checkpoints that ship their own table in FP8. The overlay stubs the table parameter and serves gathers from the sidecar, so the checkpoint's own table tensors are dropped before they load. That turns the table format into a non-issue: nvidia's NVFP4 build, whose card documents an 8-GPU deployment because its FP8 table cannot use vLLM's BF16-only host offload, boots on one 96 GB card this way (234 s, 88,828 MiB, 348k-token KV pool)... Its 53.7 GB table-and-MTP shard can be skipped at download time."

> Format section: "Sidecars are 128 shard files (`shard_N.safetensors`, 2,500,012 rows each, concatenated in shard order) plus `META.json`. Row width 160."
> dequant examples: FP8 `row = fp8 * scale[row]`; INT4 `row[c] = (nibble - 8) * scale[row, c // 16]`.

> Notes: "the offload PR branch (#53899) loads FP8 and NVFP4 global-scale tables since 2026-08-30, and #54129 memory-maps the FP8 table out of the checkpoint shards. Both work at one scale per table; the sidecars here are per-row (FP8) or per-16-column group (INT4, NVFP4) and **attach to any BF16-table checkpoint**."

> "Two other community packagings of the table exist: edougawa carries it as per-row INT4 with FP16 scales inside the checkpoint (needs their vLLM patch), and HamboneLabs-AI maps a raw BF16 file the way the disk overlay here does (their patch set). Neither was measured here."

## R1 deductions (researcher inference, clearly labeled)

- "The original model" + "original BF16 tables" ⇒ an upstream BF16 checkpoint of Qwen3.8-Flash-Next exists; the BF16 PLE table measures 95.4 GB (~51.2B params × ~1.86 bytes — slight compression vs 2.0 bytes/param is within rounding/measurement, exact composition unverified).
- The overlay "attaches to any BF16-table checkpoint" ⇒ multiple checkpoints ship the table in BF16; nvidia's ships FP8; primitive-ai's own repos ship `ple-bf16-*` shards (see R1-nvfp4-shard-structure.md).
- Identity of the canonical repo (org, id, license) is NOT stated in this card — parent must verify on HF.
