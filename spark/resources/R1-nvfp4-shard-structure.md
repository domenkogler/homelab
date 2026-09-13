# R1 capture — primitive-ai/Qwen3.8-Flash-Next-NVFP4 repo structure (R1-relevant extraction from r/LocalLLaMA 170K post)

Source URL: https://www.reddit.com/r/LocalLLaMA/comments/1w2b2j0/qwen38flashnext_at_170k_context_on_a_single_96_gb/
Posted by u/UltrMgns, 2026-08-30. Pre-existing local capture "Qwen3.8-Flash-Next at 170K context on a single 96 GB card 110 t-s.md"; this file extracts R1 weight-provenance content. Lane had no web tools; text from saved capture.

## OP's download + index-trim snippet (verbatim — proves BF16 table shards inside the NVFP4 repo)

```
hf download primitive-ai/Qwen3.8-Flash-Next-NVFP4 \
  --exclude "ple-bf16-*" --local-dir ./flash-next
```

> Skipping `ple-bf16-*` (saves 100 GB but breaks the index. So we trim that index):

```python
import json
p='model.safetensors.index.json'; d=json.load(open(p)); wm=d['weight_map']
drop=[k for k,v in wm.items() if v.startswith('ple-bf16-')]
assert len(drop)==128 and all('ngram_embedding' in k for k in drop)
for k in drop: del wm[k]
json.dump(d, open(p,'w'))
```

## Dull-Giraffe's budget breakdown (verbatim, comment)

> "GPU: 78.2 GiB of the 96 GB card — 68 GB NVFP4 routed experts + 16 GB BF16 everything-else — leaving ~17 GiB for KV + GDN state at 196K context."
> "Host: ~51.2 GB of pinned memory for the FP8 n-gram table via --ple-offload-embedding (that flag is load-bearing...)."
> "the MTP head lands at 0.51 GB in VRAM and the KV pool is unchanged"

## madbrain1976 reproduction log (verbatim, comment — core checkpoint shard counts)

> "All three attempts loaded the 52 core checkpoint shards and the INT4 PLE sidecar."
> "the 78.23 GiB core checkpoint"

## R1 deductions (researcher inference, clearly labeled)

- Repo layout of primitive-ai/Qwen3.8-Flash-Next-NVFP4: 52 core shards (78.23 GiB total: ~68 GB NVFP4 routed experts + ~16 GB BF16 non-expert weights incl. attention/GDN/MTP) + 128 `ple-bf16-*` shards (~100 GB) all named `ngram_embedding.*` (the BF16 PLE table) + `model.safetensors.index.json` referencing them.
- The BF16 PLE table is thus obtainable WITHOUT the canonical checkpoint — but at ~95–100 GB it cannot coexist with weights + KV in a 128 GB GB10 pool; quantized sidecars (ples_int4 32 GB) are the practical choice.
- Canonical repo id, license, and config.json remain unverified (see digest open gaps). The captured SGLang recipe in "Fastest setup" thread uses `--served-model-name Qwen/Qwen3.8-Flash-Next`, hinting the canonical id is `Qwen/Qwen3.8-Flash-Next` [unverified].
- Scale cross-check: branch name `qwen3-8-flash-next-125b-a6b` (ninfer) ⇒ ~125B total / 6B active; BF16 full weights ≈ 250 GB [inference] — does not fit GB10.
