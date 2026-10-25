# HD-473 — are the fp8 main-KV PRs merged, and does a pinnable build carry them?

> **Role:** evidence — a read-only upstream + registry re-check of the engine-pin blocker, the cheap
> half of the pin lane (no boot, no GPU, no pull, no converge).
> **Linked from:** [`todo.md`](../../../todo.md) HD-473 · [`docs/spark-llm-profiles.md`](../../../docs/spark-llm-profiles.md)

The standing verdict was `BLOCKED-ON-IMAGE`, proved 2026-09-28 by
[`../hd469-graded/image-probe-20260928.md`](../hd469-graded/image-probe-20260928.md): the pinned tag
carries no fp8 read path, no newer tag of that ref exists, and vLLM v0.30.0 lacks the merge too. All
three halves are still true **as stated**. What changed is the fourth thing none of them measured:
**the merge is now inside a vLLM *release*, and releases publish arm64 digests.**

## Verdict

**The upstream blocker is gone; the pin decision is what remains.** vllm#55557 is merged (2026-09-16)
and is an ancestor of **v0.31.0** and **v0.32.0**; both release images exist as **arm64** manifests and
build on **CUDA 13.0.3**. Our own ref has **not** moved — `qwen38-flash-next` is still `last_updated`
2026-08-26, still our pinned digest. So `graded` is no longer blocked on an upstream build: it is
blocked on **choosing a ref and re-deriving the built lineage under it**.

## PR state (the question as asked)

| PR | what | state | merged | in v0.31.0 / v0.32.0 |
|---|---|---|---|---|
| vllm#55557 | fp8_e4m3 **main KV** on the QSA path — the blocker | **merged** | 2026-09-16 | **yes / yes** (v0.30.0: no) |
| vllm#54846 | fp8_e4m3 + **nvfp4** KV | **open** | — | nvfp4 stays off this lane |
| vllm#54371 | UVA PLE offload / `--engram-config` | merged | 2026-09-09 | yes / yes |
| vllm#54890 | FP8 **indexer** cache (the one v0.30 *does* carry) | merged | 2026-09-07 | yes / yes |
| vllm#54517 · #54513 · #54873 · #55309 | fused PLE · split QSA indexer · sparse-GQA · fused residual+gate | merged | Sep 2–14 | yes / yes |
| sglang#36644 | fp8 KV in QSA — the `fast-sglang` gap | **open** | — | the sglang blocker stands |
| sglang#37068 · #38121 | file-backed PLE table · NVFP4 MIXED loader | merged | 2026-09-05 | not pinned (`spark_sglang_image: ""`) |

Containment was read with GitHub's own compare, not by date arithmetic: `compare/<tag>...<merge_sha>`
returns `behind` when the merge commit **is** an ancestor of the tag, `diverged` when it is not.
`raw/containment.txt` shows `#55557` as `diverged` against v0.30.0 — which is the repo's existing
"v0.30.0 does not carry it" claim, reproduced — and `behind` against both newer tags.

## The discriminating read: the dtype declaration at the tag

The same marks [`spark-fp8-image-probe.py`](../../../scripts/bench/spark-fp8-image-probe.py) greps in a
container, read instead from the source at each release tag (`raw/upstream-source.txt`):

| tag | `vllm/models/qwen4_exp/nvidia/qsa.py` |
|---|---|
| v0.30.0 | `supported_kv_cache_dtypes = ["auto", "bfloat16"]` (:67) + `raise NotImplementedError("Qwen4Exp QSA requires a BF16 main KV cache")` at :110 and :189 |
| v0.31.0 | `supported_kv_cache_dtypes` **includes `"fp8_e4m3"`** (:72–76), fp8 branches at :154/:217/:278, **no BF16-only raise** |
| v0.32.0 | same shape (:154–158, :236/:299/:360), guard absent |

v0.30.0's two raise sites are the exact failure recorded in
[`hd469-graded/README.md`](../hd469-graded/README.md) — the guard we hit is the pre-fix upstream
shape, not a NVIDIA fork quirk. Note the module path: **`models/qwen4_exp/…`**, where the pinned
day-0 build had `models/qwen3_8_flash_next/…`. The probe's `q*/nvidia/qsa.py` glob already tolerates
it; a bind-mount or overlay patch does not, and that is the re-anchor the pin lane owes.

## Registry (anonymous, read-only — `raw/registry.txt`)

| ref | last_updated | arches |
|---|---|---|
| `qwen38-flash-next` (our pin) | 2026-08-26 | amd64, arm64 — unchanged, still `fc120ece…` |
| `v0.31.0` / `v0.31.0-aarch64` | 2026-10-04 | amd64+arm64 / arm64 |
| `v0.32.0` / `v0.32.0-aarch64` | 2026-10-18 | amd64+arm64 / arm64 |

`docker/Dockerfile` at both release tags: `ARG CUDA_VERSION=13.0.3` — CUDA 13, the family our own tag
needed (`qwen38-flash-next-arm64-cu130`). Each release also publishes **`-cu129`** variants: those are
the CUDA-12 line and are the wrong choice for GB10/sm_121 — a pin must take the default or `-aarch64`.

## What this does NOT prove

* **Leg B against a candidate is still owed.** Everything here reads *upstream source at a tag* and the
  *registry manifest*; it is not the pinned container's own `qsa.py`. The probe's verdict at this HEAD
  is **`UNDECIDED`** (`raw/probe-legA.txt`) because only Leg A ran — and an undecided probe is not a
  verdict, so it must not be recorded as one.
* **The model-specific fixes may not be in a release build.** The `qwen38-flash-next` tag was cut for
  this model; whether a stock release serves it identically (kernels, PLE hooks) is an engine question
  answered by booting it, not by grepping `main`.
* **`fast` runs a built image, not the base.** `VLLM_FP8_HYBRID` and the drafter-expert flag dispatch
  through `vllm_fp8_hybrid.py`, which the ultrafast lineage installs and the base image does not — so
  moving the base means rebuilding that lineage on it and re-proving the knobs still bind.
* fp8 buys **1.70–1.89×** slots, not 2×; and gates 8–9 (MTP acceptance, quality vs the model's own
  noise floor) still gate the dtype change even once it boots.

## Re-derive (read-only, ~2 min total)

```bash
python3 scripts/bench/spark-fp8-image-probe.py --skip-box --tag-filter 'qwen38|flash'   # Leg A only
curl -s "https://api.github.com/repos/vllm-project/vllm/pulls/55557" | jq '.state,.merged,.merged_at'
curl -s "https://api.github.com/repos/vllm-project/vllm/compare/v0.32.0...dff1bde84dd6e34a49c150116d0f212507280910" | jq .status
curl -s "https://raw.githubusercontent.com/vllm-project/vllm/v0.32.0/vllm/models/qwen4_exp/nvidia/qsa.py" | grep -nE 'supported_kv_cache_dtypes|fp8_e4m3|BF16 main KV'
curl -s "https://hub.docker.com/v2/repositories/vllm/vllm-openai/tags/v0.32.0-aarch64" | jq '.last_updated,.digest,[.images[].architecture]'
```

`raw/`: `pr-status.txt` · `containment.txt` · `upstream-source.txt` · `registry.txt` · `probe-legA.txt`.
