# fp8 KV reachability — read-only image probe, 2026-09-28 (HD-469 step 2 / HD-471 input)

Produced by `scripts/spark-fp8-image-probe.py --tag-filter 'qwen|flash'` at
2026-09-28 ≈18:55 CEST from the workstation, against the box over ssh for Leg B only.
No converge, no engine restart, no GPU, no pull (`docker run --rm -m 4g --entrypoint sh`
against the LOCAL image; `pgrep` refused-guard was armed). Re-run it verbatim to reproduce.

```

── Leg A · registry (read-only, anonymous) ─────────────────────────────
pinned image (versions.yml): vllm/vllm-openai:qwen38-flash-next@sha256:fc120ece0a388cc0aa1caad4a9f1cd92113484ab7ec2fd0efadd62585be05bf8
  pin parses as repo=vllm/vllm-openai tag=qwen38-flash-next digest=sha256:fc120ece0a38…
  tags matching /qwen|flash/ in the first 5 page(s): 29, newest:
    2026-09-10T06:47:58.803361Z  deepseekv41-flash-0909-cu129                 sha256:4a4431d6a283…  [amd64, arm64]
    2026-09-10T06:47:50.258356Z  deepseekv41-flash-0909                       sha256:00d577a6a632…  [amd64, arm64]
    2026-09-10T06:47:27.376416Z  deepseekv41-flash-0909-cu129-arm64           sha256:cbb6e77f340e…  [arm64]
    2026-09-10T06:47:20.434513Z  deepseekv41-flash-0909-cu129-amd64           sha256:af36b3aac947…  [amd64]
    2026-09-10T06:47:14.109314Z  deepseekv41-flash-0909-arm64                 sha256:d84a123255b8…  [arm64]
    2026-09-10T06:47:07.468784Z  deepseekv41-flash-0909-amd64                 sha256:4f3c8bcf6328…  [amd64]
    2026-09-09T13:32:06.031224Z  glm53-flash                                  sha256:819ec9c06341…  [amd64, arm64]
    2026-09-09T13:31:53.739285Z  glm53-flash-cu129                            sha256:2b84cf23f140…  [amd64, arm64]
    2026-09-09T13:31:25.42925Z  glm53-flash-arm64-cu130                      sha256:b0501f99fec5…  [arm64]
    2026-09-09T13:31:22.992674Z  glm53-flash-x86_64-cu130                     sha256:0674a3ea3c97…  [amd64]
    2026-09-09T13:31:20.509513Z  glm53-flash-arm64-cu129                      sha256:58326f1225ac…  [arm64]
    2026-09-09T13:31:17.894154Z  glm53-flash-x86_64-cu129                     sha256:f8649f17426c…  [amd64]
  qwen38-flash-next: last_updated=2026-08-26T13:06:10.219275Z full_digest=sha256:fc120ece0a38… architectures=[amd64, arm64] (2 entries)  ← IS our pin
      · amd64/linux sha256:0aea30240f3e… size=8634450611
      · arm64/linux sha256:3b0e188ffceb… size=9702868146
  qwen38-flash-next-arm64-cu130: last_updated=2026-08-26T13:04:17.794978Z full_digest=sha256:3b0e188ffceb… architectures=[arm64] (1 entries)
      · arm64/linux sha256:3b0e188ffceb… size=9702868146

── Leg B · the image's own source (no GPU, no writes, NO PULL) ─────────
  what this box actually runs for that ref: arm64/linux   (versions.yml claims multi-arch; THIS is what spark executes)
  docker run --rm -m 4g --entrypoint sh <image> -c '…grep 5 marks…'
  VLLM_DIR=/usr/local/lib/python3.12/dist-packages/vllm
  QSA_FILES=/usr/local/lib/python3.12/dist-packages/vllm/models/qwen3_8_flash_next/nvidia/qsa.py
  vllm.__version__ = 0.1.dev20073+g8e685d198
  HIT  supported_kv_cache_dtypes: 1 line(s)
        70:    supported_kv_cache_dtypes: ClassVar[list[CacheDType]] = ["auto", "bfloat16"]
  —    IS_FP8: 0 line(s)
  HIT  BF16 main KV: 2 line(s)
        109:                "Qwen3.8-Flash-Next QSA requires a BF16 main KV cache"
        188:                "Qwen3.8-Flash-Next QSA requires a BF16 main KV cache"
  —    fp8_e4m3: 0 line(s)
  HIT  kv_quant_mode: 2 line(s)
        52:    get_kv_quant_mode,
        344:            kv_quant_mode=get_kv_quant_mode(self.kv_cache_dtype),
  DECLARED supported_kv_cache_dtypes = ["auto", "bfloat16"]

── Verdict ─────────────────────────────────────────────────────────────
BLOCKED-ON-IMAGE — the pinned build carries no fp8 main-KV read path.
  · `graded` is therefore an ENGINE-PIN question (todo.md HD-471), not a config
    flip; it stays uncertified and nothing on this box needs to change.
  · fp8 KV merged upstream as vllm#55557 (2026-09-16) and is NOT in vLLM v0.30.0;
    the only refs that can carry it are a rebuilt qwen38-flash-next tag or a
    nightly — and CONVENTIONS §7 needs a REGISTRY-VERIFIED ARM64 digest of it.
  · if Leg A above printed no arm64 entry, that is the finding, verbatim.
```

## What this settles

| Question the brief left open | Registry-verified / source-verified answer |
|---|---|
| Is the `qwen38-flash-next` tag mutable under us? | The tag's current full digest is `sha256:fc120ece…` = **exactly our pin**; last pushed **2026-08-26T13:06:10Z**. It has not moved since we pinned it. |
| Is the pin multi-arch (CONVENTIONS §7 claim)? | Yes: the pinned digest is the **index**, carrying `amd64/linux sha256:0aea3024…` and `arm64/linux sha256:3b0e188f…`. `docker image inspect` on spark reports **`arm64/linux`** — the arm64 entry is what runs, and it equals the separate `qwen38-flash-next-arm64-cu130` tag (`sha256:3b0e188f…`, pushed 2026-08-26T13:04:17Z). |
| Is there any NEWER tag of this model we could pin? | Not in the repo's newest 500 tags: 29 tags match `/qwen|flash/`, newest 2026-09-10, and every one of them is a **different model** (`deepseekv41-flash-0909`, `glm53-flash`). The newest `qwen38-flash-next*` is still 2026-08-26. |
| Does the pinned build carry the fp8 main-KV read path? | **No.** Its own `models/qwen3_8_flash_next/nvidia/qsa.py` declares `supported_kv_cache_dtypes = ["auto", "bfloat16"]` (line 70) and raises *"Qwen3.8-Flash-Next QSA requires a BF16 main KV cache"* at **lines 109 and 188** (run #1 cited :187 — the raise appears twice). `vllm.__version__` self-reports `0.1.dev20073+g8e685d198`. |
| Is the surrounding fp8 plumbing there? | Partly: `get_kv_quant_mode` is imported (line 52) and `kv_quant_mode=get_kv_quant_mode(...)` is passed (line 344), while `IS_FP8` / `fp8_e4m3` are absent. That matches vllm#55557's own description of the pre-fix state ("the write path, the KV spec (`kv_quant_mode`) and the per-layer scales are already in place"; only the read side was missing). |

## The verdict, stated as the lane needs it

`graded` (and the fp8 half of any profile) is **blocked on the pinned image, not on the
model** — and not merely on "an image exists upstream":

* the merge that adds it (vllm#55557) landed **2026-09-16**, three weeks **after** the last
  push of this model's tag (2026-08-26), and it is not in the vLLM v0.30.0 release either;
* so reaching fp8 main KV on this box requires a **rebuilt `qwen38-flash-next` image**
  (or an equivalent nightly) whose **arm64** manifest we have digest-verified — an
  engine-pin lane with its own re-cert, registered as **HD-471**;
* the two third-party recipes that make it work today do it by **patching the container's
  site-packages** (`MiaAI-Lab/Qwen3.8-Flash-Next-{Single,Dual}-DGX-Spark`,
  `files/patch_qsa_fp8_kv.py`, AGPL-3.0-or-later). This lane rejects that: a patched
  container is unreproducible from IaC and is exactly what `certified_evidence:` exists to
  prevent.

Nothing in this probe required the GPU, the engine, or a converge. Cost: ~40 s.
