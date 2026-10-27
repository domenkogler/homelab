# HD-1206 — the v0.32 lineage: what porting the UltraFast patch stack actually means

> **Role:** evidence + build-order — the patch-by-patch map between the recipe we pin and a v0.32 base, the
> role properties a rebuild depends on and where each one lives, and the rollback state of the box as it stands.
> **Linked from:** [`todo.md`](../../../todo.md) HD-1206 · [`docs/spark-llm-profiles.md`](../../../docs/spark-llm-profiles.md)

The profile `fast8` (`image: ultrafast-v32`) is authored and **gate-blocked on an empty pin**: the lineage it names
is the upstream patch stack *rebuilt on a v0.32 base*, and that build does not exist yet. This file is the survey
of what stands between here and there, taken read-only from the checkout on spark, from upstream source at the tag
and — for the base-image half — from inside the pulled base image at the pin digest.

## 1. What the recipe is (read from the box, not from the README)

Checkout: `/opt/homelab/ultrafast-src` on spark @ `0c391a3` (the pin in `group_vars/all/versions.yml`).

| file:line | what it does | why it matters for a v32 rebuild |
|---|---|---|
| `recipe/build/image/build.sh:15-16` | `iter6c='qwen38-flash-dgx:iter6c-20260909'`, `iter6d='qwen38-flash-dgx:iter6d-20260910'` | **hardcoded tags** — a v32 build rebuilds OVER the tag that is the only reference to the live `fast` image |
| `build.sh:65-66,74-75` | `docker build --network none --pull=false -f Dockerfile.iter6c` then `-f Dockerfile.iter6d` | `--pull=false` ⇒ the base image must **already be in that host's store** (pull it first); `--network none` ⇒ nothing is fetched during the build |
| `Dockerfile.iter6c:2` | `FROM vllm/vllm-openai:qwen38-flash-next@sha256:fc120ece…` | the base is **baked into the Dockerfile**, no env/arg override ⇒ a v32 build is a *file edit*, not a variable |
| `Dockerfile.iter6c:4-5` | `ARG SP=/usr/local/lib/python3.12/dist-packages`, `ARG PLE=${SP}/vllm/models/qwen3_8_flash_next/nvidia/ple_layer.py` | the path anchor below |
| `Dockerfile.iter6c:7-23`, `:31-68`, `Dockerfile.iter6d:4-8` | ~16 patches: `COPY src/*.py ${SP}/…`, python patchers run from `/tmp`, appends into `${PLE}` / `${GPTQ_PY}` / `${MTP_PY}`, and **two `sed -i` string substitutions** | each is anchored on a path or a symbol of the **day-0 build** |

`iter6c` is the layer that installs the PLE-mmap hook (`vllm_ple_mmap.py` + the append to `ple_layer.py`) and the
hybrid dispatch (`vllm_fp8_hybrid.py` + the append to the GPTQ loader) — i.e. the two things `fast`/`fast8` cannot
boot without (`ple_mmap: true`, `ple_dispatch: true`; `ar-blk-lean` is the measured proof).

## 2. What changed upstream between the day-0 build and `v0.32.0`

Read from `raw.githubusercontent.com/vllm-project/vllm/v0.32.0/…` (HTTP status + the named symbols):

| fact at `v0.32.0` | evidence |
|---|---|
| the model package is **`vllm/models/qwen4_exp/…`**; `…/models/qwen3_8_flash_next/nvidia/ple_layer.py` returns **404**, `…/qwen4_exp/nvidia/ple_layer.py` returns 200 | HTTP status of both paths |
| classes are `Qwen4ExpForCausalLM`, `Qwen4ExpForConditionalGeneration`, **`Qwen4ExpMTP`** in `vllm.models.qwen4_exp` | `vllm/model_executor/models/registry.py:113,600,696` |
| there is **no `vllm/v1/ple_offload/`** package (worker.py / connector.py both 404) | HTTP status — the primitive-ai CPU-offload path is not in stock upstream, which is why `spark_llm_overlays` names paths of the fork build |
| PLE/n-gram storage in stock upstream is **Engram** (`vllm/config/engram.py`: `cpu_offload` default `true`, `dp_shared_memory`, `use_thp`), keyed to `ple_layer_ids` of `Qwen4Exp*` | file exists, 200 |
| **fp8 main KV exists**: `vllm/models/qwen4_exp/nvidia/qsa.py` lists `"fp8_e4m3"` in `supported_kv_cache_dtypes` (:154-158) with fp8 branches at :236/:299 and **no BF16-only raise** | source at the tag (the merge is vllm#55557; [`../hd473-pin-check-20261025/`](../hd473-pin-check-20261025/README.md)) |
| CUDA **13.0.3**, Python **3.12** | `docker/Dockerfile:25-26` — so `${SP}`'s `python3.12` prefix still matches |

### The patch map this forces

| anchor in the recipe | at v0.32 | kind of failure if left alone |
|---|---|---|
| `…/qwen3_8_flash_next/nvidia/ple_layer.py` | `…/qwen4_exp/nvidia/ple_layer.py` | **loud** — `cp ${PLE} ${PLE}.orig` has no such file, the build stops at step 1 |
| `_ple_mmap_apply(Qwen3_8FlashNextNGramEmbedding)` appended to `${PLE}` | the n-gram class lives in `qwen4_exp` under a `Qwen4Exp*` name | **loud at import** — NameError inside the patched module |
| `_mtp_draft_vocab_apply(Qwen3_8FlashNextMTP)` appended to `${MTP_PY}` | `Qwen4ExpMTP` | loud at import |
| `sed -i 's\|DEFAULT = 102400\|DEFAULT = 101376 …\|'` (GB10 shmem fix) and `sed -i 's\|for num_warps in \[2, 4\]\|for num_warps in [2]\|'` (Blackwell `tl.dot` race) | source strings may have moved | **SILENT** — `sed` exits 0 on no match; a build can "succeed" with both GB10 fixes absent. Verify by reading the two files, never by the build's exit code |
| the never-evict patcher (`src/patch_never_evict.py` → `arg_utils.py`, `config/cache.py`, `v1/core/block_pool.py`, `v1/core/sched/scheduler.py`) | those files exist at the tag, but the patcher's first edit matches a **two-line** sequence and `v1/core/sched/scheduler.py:342` no longer has the closing paren on the next line | **decided by the build, loudly**: `anchor found 0 times (want 1)`. The patcher is dropped, with a guard — the flag is REJECTED and no lineage but `ultrafast` may carry it (§7, [box-build-20261027.md](box-build-20261027.md)) |

## 3. Upstream has not ported it

`api.github.com/repos/dime-online/qwen3.8-Flash-DGX-UltraFast/commits` HEAD = **`0c391a3e7` (2026-09-29)** — the
commit this repo already pins. There is **no upstream revision that bases on v0.31/v0.32**, so the port is either
ours (a fork or branch with a commit we can pin) or it does not happen. Editing the checkout by hand is the shape
to refuse: `roles/spark-ultrafast-build/tasks/checkout_pinned.yml` proves provenance with `git rev-parse HEAD`, and
**editing tracked files does not change HEAD** — a hand-patched tree passes that assert silently and produces an
image nobody can rebuild. That file therefore asserts `git status --porcelain -uno` clean as well — tracked files,
the bytes a build compiles; the untracked residue a build leaves beside its sources reaches no layer — and the port
itself is a patch set in this repository (§6 step 0), never an edit in the checkout.

## 4. What the roles guarantee, and the failure each guarantee exists to prevent

A lineage is **data**: its own `(image pin, build tag, upstream commit, patch set)` dict, driving one shared
build body. `roles/spark-ultrafast-build/tasks/build_lineage.yml` is that body — the inspect/skip, the build, the
re-read and the assert pair, once — and `tasks/checkout_pinned.yml` is the provenance proof. Both are driven by
vars, so a second lineage cannot inherit the first one's values by accident. The live lineage's dict is
`spark_ultrafast_lineage` (`roles/spark-ultrafast-build/defaults/main.yml`), the v32 lineage's is
`spark_profile_fast8_lineage` (`roles/spark-profile-fast8/defaults/main.yml`).

| the failure | what now prevents it |
|---|---|
| a second lineage **skipped** because another lineage's image is present | the inspect reads `bl_pin` — the lineage's own pin — and nothing else; `spark_vllm_ultrafast_image` appears in the live lineage's dict only |
| a red that reads like a mistake instead of like "wrong artifact" | the assert pair compares the built ID with **that lineage's** pin and names the var to record (`bl_pin_var`) |
| a rebuild **retagging the live `fast` image** | a lineage declares `reserved_tags` and the build refuses if its own tag is one of them; `port_v32.py` deletes upstream's `build.sh`/`Dockerfile.iter6c`/`Dockerfile.iter6d` from the v32 build directory (they hardcode both live tags), and after the build every reserved tag is re-read and must still resolve |
| a **hand-edited checkout** passing `HEAD == pin` | `git status --porcelain -uno` must be clean in the checkout (`checkout_pinned.yml`) — tracked files, because those are what the build compiles and untracked residue is not — and the port is applied to a staged copy under `/opt/homelab/ultrafast-v32-build` |
| a **`sed` that matched nothing** shipping a green build | every `sed` in `Dockerfile.v32` counts its anchor before (`test "$(grep -c …)" -eq 1`) and greps its marker after; the `Qwen4Exp*` names, their module paths and the three `sed` source constants are also grepped **inside the base image** before the build, and **inside the built image** after it the seven artifact-marker reads (`spark-fla-shmem`, `spark-fla-warps`, `_ple_mmap_apply(Qwen4ExpNGramEmbedding)`, `_mtp_draft_vocab_apply(Qwen4ExpMTP)`, `quant_config=vllm_config.quant_config` in each of `model.py` and `mtp.py`, `guard_hits` in `v1/worker/mamba_utils.py`) plus the **absence** of the day-0 `Qwen3_8FlashNext` symbol in the installed `vllm_ple_mmap.py`; `port_v32.py` fails on an anchor whose occurrence count is not the expected one |
| upstream's source set silently drifting | `port_v32.py` runs the checkout's own `md5sum --check` / `sha256sum --check` blocks (the same eleven + two lists `recipe/build/image/build.sh` enforces) before it stages anything |

## 5. Rollback state of the box, as it stands now

* Local tags on spark: **`spark-rollback:fast` → `4900c13edab9…`** (the image the live `fast` profile boots) and
  `spark-rollback:reasoning → fc120ece0a38…`. They exist to keep both images referenced against a prune and to make
  the rollback pointer readable; `docker images` confirms both.
* Off-box archives on the NAS (`tank/data/host-images/spark/`, i.e. oldsrv's `/mnt/nas/data/host-images/spark`):
  `spark-fast-4900c13e.tar.zst` (9,567,717,777 B) and `spark-reasoning-fc120ece.tar.zst` (9,567,372,199 B), each with a
  `.sha256` sidecar, `zstd -t` clean and `sha256sum -c` clean; restore with `zstd -dc <file> | docker load`.
  Each sidecar records the **NAS-native absolute path** (`/tank/data/host-images/spark/…`), so `sha256sum -c
  <file>.sha256` verifies only when run ON the nas; from another host the file sits at `/mnt/nas/…` and the
  same command fails on the PATH, not on the bytes — there, compare `sha256sum <file>` against the sidecar's
  hash instead. Only the **engine images** are archived: the checkpoints and PLE tables are HF artifacts pinned by revision in
  `group_vars/all/versions.yml` (sets `b1-awq`, `ple-int4`, `ar-hybrid`, `ple-fp8`) and re-fetchable.
* The archive is a copy, not a second engine: nothing about it changes what boots. Rollback is still
  `spark_llm_profile: fast` + a detached converge (~20 min cold boot).

## 6. Build order (each step one act, none of them a gamble on `fast`)

0. **Ruled (owner): the port lives in this repository, as the lineage `spark-profile-fast8` — an in-repo patch
   set the role applies to a staged copy of the pinned checkout. Not a fork, and not a hand-edit of the checkout
   (§3).** The recipe stays pinned at `spark_ultrafast_upstream_commit`; the port is the lineage's own
   `files/Dockerfile.v32` + `files/port_v32.py`, so the pinnable artifact is this repository's own commit.
1. ✅ Done offline: `roles/spark-ultrafast-build` parameterized (§4), the v32 lineage authored, offline gates green.
   What that cannot settle is in §7.
2. ✅ **Done: the base is in spark's store** — `vllm/vllm-openai:v0.32.0-aarch64@sha256:6ff5ff0ddf3658d2c2d677dac5ca2d4726ce0156b4371166d918181b210bd4bc`,
   image ID `6ff5ff0ddf36`, `arm64`/`linux`, 35.3 GB on disk (`spark_vllm_v32_base_image`; the registry manifest for that
   digest is a single `arm64/linux` image, never a `-cu129` tag). Headroom after it: 188 G free of 442 G on spark
   (measured 2026-10-27) — the build adds layers on top of this. Downtime: none, and `--pull=false` means this step
   is the whole of the base's availability — the role's own pull leg is a no-op while it holds.
3. ✅ **Done: the read-only pre-flight inside that image** — the `ple_layer.py` path, the `Qwen4Exp*` names, the two
   `sed` anchor strings and the `mamba_utils` step, all read at the digest (§7). These are
   `spark_profile_fast8_base_probes`, so they also run before the build and stop it.
   `scripts/bench/spark-fp8-image-probe.py` still owns the fp8-KV half of this leg (§7).
4. Build detached (`--tags spark-profile-fast8 -e spark_profile_fast8_build=true`, async), with upstream's own CPU
   self-tests re-run against the built tag, then let the role **fail on purpose** after printing the ID — the pin
   is a human commit. Its `mamba_utils` step ports the guard onto the base with anchored insertions
   (§7) and needs no build-arg; `spark_profile_fast8_mamba_guard` is `patch`, and `apply` — the
   whole-file copy — stays unset because it is a three-layer reversion.
   Every post-build leg runs `docker run --rm --network none --memory 8g` on the **same unified pool the live
   engine serves from**, so this step is scheduled inside the owner window and not beside serving: an 8 GiB CPU
   gate competes with the engine for the pool it budgets.
5. Enter `ultrafast-v32` in `spark_llm_fp8_kv_capable_images` **only on the probe's `REACHABLE` verdict** — the
   list is `[]` until then, because that list is the fp8 claim's evidence and a pre-registered name turns every
   offline gate green by assertion (§7 box leg step 4). The arm reads GATED while it is empty, not broken.
6. Offline: `check_spark_llm_gate.py`, `spark-llm-render-matrix.py`, `spark-llm-probe.py matrix`.
7. Owner window: flip `spark_llm_profile: fast8` with a per-run `-e spark_llm_allow_uncertified=true`, converged
   **detached**; read the engine's own `GPU KV cache size` line (the projection is 1,095,830 slots = 4.18 ×); then
   gates 0–7 and the dtype gates 8–9. Rollback = `spark_llm_profile: fast` + detached converge.

## 7. Anchors: what was proven at the tag, what was not, and the box leg in order

Read from `raw.githubusercontent.com/vllm-project/vllm/v0.32.0/<path>`; the day-0 side from the pinned checkout
on spark, read-only. "Proven" means the exact string or path was found at the tag with the expected count. A row
marked **box** was settled the stronger way: read inside the pulled base image at the pin digest, which is where
the build's own greps run (*The base-image read*, below).

| anchor | v0.32.0 evidence | proven |
|---|---|---|
| model package `vllm/models/qwen4_exp/…` | `…/qwen3_8_flash_next/nvidia/ple_layer.py` → **404**, `…/qwen4_exp/nvidia/ple_layer.py` → **200** | yes |
| `Qwen4ExpPLELayer` (the append's pre-grep) | `…/qwen4_exp/nvidia/ple_layer.py:65` | yes |
| `Qwen4ExpNGramEmbedding` (the class `vllm_ple_mmap.apply` wraps) | `…/nvidia/ple_layer.py:29` imports it into that module's own namespace | yes |
| `Qwen4ExpModelState` (the prefetch hook, imported inside a `try/except ImportError` that only **warns**) | `…/nvidia/model_state.py:17`, `prepare_inputs:95` | yes |
| `Qwen4ExpMTP` (the draft-vocab append) | `…/nvidia/mtp.py:400`, `vllm/model_executor/models/registry.py:696` | yes |
| the `lm_head` sed line, once per file | `…/nvidia/model.py:740` (12-space), `…/nvidia/mtp.py:432` (20-space) | yes |
| `DEFAULT = 102400` (the GB10 shmem sed source) | `vllm/third_party/flash_linear_attention/ops/utils.py:183`, and `ADA = 101376` at `:180` is the value it becomes | yes |
| `for num_warps in [2, 4]` (the Blackwell `tl.dot` sed source) | `…/flash_linear_attention/ops/chunk_delta_h.py:37`, one occurrence | yes |
| `auto_gptq.py`, `mamba_utils.py`, `low_latency_gemm.py`, `skinny_gemm.py`, `qwen_gdn_linear_attn.py`, `short_conv_attn.py`, `model_state.py`, `registry.py`, `engine/arg_utils.py` (the patchers' targets) | HTTP 200 each; `vllm/arg_utils.py` is **404** — the file is `vllm/engine/arg_utils.py`, which is what `patch_never_evict.py` already opens | yes |
| `QwenGatedDeltaNetAttention` (the in-proj GEMV append) | `vllm/model_executor/layers/mamba/gdn/qwen_gdn_linear_attn.py:454` | yes |
| `patch_short_conv_async_h2d.py` is **not needed** | `vllm/v1/attention/backends/short_conv_attn.py:334,337` — both transfers are `async_tensor_h2d(` at the tag, so the day-0 anchor is gone. `Dockerfile.v32` step 12 greps this, so the claim cannot rot silently | yes (dropped, with a guard) |
| `patch_never_evict.py` is **not applied** | its first edit counts a two-line sequence: `vllm/v1/core/sched/scheduler.py:342` still carries `watermark=self.scheduler_config.watermark,` (**1** hit) but v0.32.0 inserted `enable_mamba_shared_prefix_checkpoint=(…)` before the closing paren, so the sequence occurs **0** times — read inside `6ff5ff0d…`'s own copy. Nothing reads the flag it would install: rejected in [services-ai-rejected.md](../../../docs/services-ai-rejected.md), every `never_evict_prompt` is empty, and `spark_llm_never_evict_capable_images` names only `ultrafast` | yes (box, dropped with a guard — [box-build-20261027.md](box-build-20261027.md)) |
| the day-0 marker comment text (`# --- qwen38-flash-dgx: …`) | `tests/test_iter6_patches_image.py:129` splits on it, so it is an anchor: kept byte-identical, only class names change | yes |
| the `${SP}` prefix **inside the release image** | all 8 `spark_profile_fast8_base_probes` are absolute paths under `/usr/local/lib/python3.12/dist-packages` and all 8 return `rc 0` in `vllm/vllm-openai:v0.32.0-aarch64@sha256:6ff5ff0d…` | yes (box) |
| the two GB10 `sed` source constants **inside the release image** | same read: `DEFAULT = 102400` → 1, `for num_warps in [2, 4]` → 1 — each `sed` has exactly its one source string to match, so neither GB10 fix can be a silent no-op | yes (box) |
| the `lm_head` sed line, once **per file**, inside the image | `…/nvidia/model.py` → 1 (probe 5), `…/nvidia/mtp.py` → 1 (not a base probe; `Dockerfile.v32` step 6 counts each file separately, and each file carries its own **artifact** probe for the `quant_config=` line the sed writes) | yes (box) |
| the `mamba_utils` whole-file step, **read** rather than inferred | 329 changed lines over 39 hunks against the image's own copy, and the three layers that diff mixes are separated below | yes (box) |
| the 13 anchors of the guard patch, **inside the release image** | `vllm/v1/worker/mamba_utils.py:207, 251, 262+313, 352, 391, 565, 494+625, 795, 830, 891, 1008, 1192+1239+1291, 1244` — every one occurs exactly its expected count in `6ff5ff0d…`'s own copy, which is the file `patch_mamba_guard_v32.py` is anchored on | yes (box) |

⏳ **Still unproven anchors** — not decidable from raw source at the tag **or** from a read of the base image;
each one is loud at build time (upstream's patchers all assert `n == 1` per anchor) or is named below, so none of
them can pass silently:

* every **multi-line code anchor** inside the unchanged patchers (`patch_block_drop.py`,
  `patch_measure_draft_mass.py`, `patch_verify_topk_pivot.py`, …). The files they edit exist at the tag and in the
  image; the exact surrounding text is not something a read of the base can settle. The build decides, and it
  fails loudly — which is how `patch_never_evict.py` was settled (row above). **§7b now settles the whole
  set in one read instead of one build attempt per surprise.**
* the `vllm_inproj_ba_gemv.py` docstring's `model.py:208-212` / `:636` **line pointers**: the module path is
  re-anchored, the numbers are day-0.
* the **fp8-KV half of this lineage**: `scripts/bench/spark-fp8-image-probe.py`'s box leg must read the built
  image's own `qsa.py` before `ultrafast-v32` may enter `spark_llm_fp8_kv_capable_images`.

### The base-image read, at the pin digest

**The base, in spark's store.** `vllm/vllm-openai:v0.32.0-aarch64@sha256:6ff5ff0ddf3658d2c2d677dac5ca2d4726ce0156b4371166d918181b210bd4bc`
resolves to image ID `6ff5ff0ddf36`, `arm64`/`linux`, `35.3 GB` (`Size`; `10.3 GB` of it reported as shared with
other images in this store). The registry half of the arm64 claim is the `curl …/tags/v0.32.0-aarch64 | jq …`
command in that pin's own comment: one image in the manifest, `arm64/linux`, digest `sha256:6ff5ff0d…` — it is the
digest and not the tag name that excludes the CUDA 12.9 `-cu129` line (CONVENTIONS §7), and because the build runs
`--pull=false`, this is the only base it can resolve.

**The 8 base probes**, each run exactly as `tasks/main.yml:78-93` builds it
(`docker run --rm --network none --memory 2g --entrypoint grep <base> -F -c <pattern> <path>`):

| path | pattern | count | rc |
|---|---|---|---|
| `…/vllm/models/qwen4_exp/nvidia/ple_layer.py` | `class Qwen4ExpPLELayer` | 1 | 0 |
| `…/vllm/models/qwen4_exp/nvidia/ple_layer.py` | `Qwen4ExpNGramEmbedding` | 2 | 0 |
| `…/vllm/models/qwen4_exp/nvidia/mtp.py` | `class Qwen4ExpMTP` | 1 | 0 |
| `…/vllm/models/qwen4_exp/nvidia/model_state.py` | `class Qwen4ExpModelState` | 1 | 0 |
| `…/vllm/models/qwen4_exp/nvidia/model.py` | `prefix=maybe_prefix(prefix, "lm_head"),` | 1 | 0 |
| `…/vllm/third_party/flash_linear_attention/ops/utils.py` | `DEFAULT = 102400` | 1 | 0 |
| `…/vllm/third_party/flash_linear_attention/ops/chunk_delta_h.py` | `for num_warps in [2, 4]` | 1 | 0 |
| `…/vllm/v1/attention/backends/short_conv_attn.py` | `spec_req_idx = async_tensor_h2d(` | 2 | 0 |

All 8 `rc 0`, so the assert at `tasks/main.yml:95` cannot fire on this base: the `${SP}` prefix, the four
`qwen4_exp` module paths, both `sed` source constants and `short_conv_attn.py`'s two transfers exist **inside the
release image**, not merely at the tag.
Two counts are 2 and both are the evidence's own prediction, not a drift: `Qwen4ExpNGramEmbedding` (the import at
`ple_layer.py:29` plus its use site) and `spec_req_idx = async_tensor_h2d(` (`short_conv_attn.py:334,337` — the
reason `patch_short_conv_async_h2d.py` is dropped). `mtp.py`'s `lm_head` line, which the probe list does not carry
but `Dockerfile.v32` step 6 counts per file, is there exactly once too.

**The porter's plan, against the real recipe.** `port_v32.py --checkout <the pinned checkout>/recipe/build/image
--stage <fresh directory> --check-only`, run on spark against the checkout at `0c391a3e…`: `rc 0`, and it
prints `port_v32: 9 anchors verified against the checkout /opt/homelab/ultrafast-src/recipe/build/image` after
`md5sum block dc4600f12b19… verified (11 files)` and `sha256sum block 956a7ec1fad9… verified (2 files)`. No
`ANCHOR` and no `MISSING` line. Nothing was written: the stage directory stayed empty and the checkout's
path+mtime+size fingerprint over its 149 files is identical before and after, with `git status --porcelain` clean.
So the `--check-only` fix (`5bd0efbc`) holds against the real recipe, and the porter's nine day-0-side anchors are
proven — which leaves the unchanged patchers' internal anchors as the only anchors the build still decides.

**The `mamba_utils` diff, read inside the base image** — the command, run with the
checkout's file bind-mounted read-only where the staged copy would be (`port_v32.py` has no mamba anchor entry, so
the staged bytes are the checkout's bytes):

```text
docker run --rm --network none --memory 2g \
  -v <checkout>/src/mamba_utils_guarded.py:/tmp/mamba_utils_guarded.py:ro \
  --entrypoint bash <base> -c 'diff -u /tmp/mamba_utils_guarded.py ${MAMBA_UTILS}'
```

**329 changed lines** — the `^[+-]` count step 7 records as `DRIFT`; 633 lines of unified diff over **39 hunks**,
+170 / −157, the snapshot's 1641 lines against the image's 1654. Not a reorder: 37 of the 39 hunks are ≤ 20 lines
of ±1–3. And the diff is not one delta but three, which is what makes the step a decision and not a formality:

| layer | day-0 base `fc120ece…` | this base `6ff5ff0d…` | live artifact `4900c13e…` |
|---|---|---|---|
| the guard: `guard_hits` / `state_num_blocks` | 0 / 0 | **0 / 0** | 19 / 12 |
| the day-0 pair: `postprocess_mamba_all` / `preprocess_mamba_all_specdec` | 1 / 1 | **0 / 0** | 1 / 1 |
| v0.32's multi-group read: `get_aligned_state_indices_multi_group_kernel` | 0 | **2** | 0 |

(`grep -c -F <name>` against each image's own `vllm/v1/worker/mamba_utils.py`; `fast`'s copy is 1641 lines, which
is the snapshot's size — step 7's whole-file copy is exactly what the live lineage boots today.)

1. **The guard is the recipe's own** and is in neither base image: 31 changed lines name it (`^[+-]` lines
   carrying `guard_hits` or `state_num_blocks`), all on the snapshot side. The base will not supply it.
2. **The `*_mamba_all*` pair is day-0 *base* code, not recipe code** — `fc120ece…` carries both, stock v0.32
   carries neither, so the copy moves fork-side code into a stock base.
3. **v0.32 adds a kernel the snapshot has never seen**: `get_aligned_state_indices_multi_group_kernel`,
   `_reinterpret_u64_as_i64`, `compute_aligned_state_indices` (a 64-line hunk and a 59-line one).
4. **v0.32 deleted code the snapshot still carries** — the `*_mamba_all*` pair, in the 60→13-line hunk.
5. **One signature change rides along**: `postprocess_mamba_align_gpu`'s `input_batch` is `InputBatch` at v0.32
   where the snapshot says `GPUInputBatch`, and the `CachedRequestState` import leaves with it.

So `apply` would add the guard (wanted), reinstall day-0 fork code (not wanted) and delete upstream's v0.32
multi-group path and its `InputBatch` re-typing (not wanted). The shape that keeps only the guard is an anchored
patch of those lines, and that is what ships: **the guard is ported, not copied** —
`roles/spark-profile-fast8/files/patch_mamba_guard_v32.py`, 13 anchors read out of this base's own file, run by
step 7 under the shipped `spark_profile_fast8_mamba_guard: patch`. `apply` stays as the revert-to-copy hatch and
prints those three layers before it copies — its `DRIFT` line re-measures the 329 offline — and `refuse`, or any
value that is neither, stops the build.

| the insertion | anchored at v0.32.0 | expected count |
|---|---|---|
| `state_num_blocks_ptr`, `guard_hits_ptr` on `_copy_mamba_state_block`, after `tile_idx,` — the position its two call sites pass them in | `mamba_utils.py:207-208` | 1 |
| the bounds check on each of the four block ids the kernel dereferences: `dest_block_id` (where `num_blocks` is also read), the two `src_block_id` paths, `actual_src_block_id` | `:251`, `:262`, `:313`, `:352` | 1, 2, 1 |
| the same two parameters on `postprocess_mamba_fused_kernel` and `precopy_mamba_align_fused_kernel`, and the two arguments at their `_copy_mamba_state_block` calls | `:391` (def `:369`), `:565` (def `:549`), `:494`, `:625` | 1, 1, 2 |
| the two context fields, the three telemetry fields, their `create()` initialisers | `:795`, `:830`, `:891-893` | 1 each |
| `state_num_blocks[idx] = state.size(0) if state.dim() > 1 else 1`, beside v0.32's own `_reinterpret_u64_as_i64(state.data_ptr())` line | `:1008-1010` | 1 |
| the two arguments at the three launches, and the reporter at the tail of `run_fused_precopy` | `:1192`, `:1239`, `:1291`, `:1244-1246` | 3, 1 |

Two of those are where a careless port loses something. `preprocess_mamba_align_fused_kernel` (`:503`) takes
neither parameter and is not touched; and the `_populate_metadata` line is not cosmetic — `create()` zeroes
`state_num_blocks`, so a port that skips it leaves every pool with a valid-block count of 0 and the guard then
skips **every** copy: a green build serving stale mamba state. The two patched kernels have no other referent in
the image — `v1/worker/gpu/model_states/mamba_hybrid.py` names `_copy_mamba_state_block` only in a comment and
reaches the launches through `run_fused_precopy` (:222) and `run_fused_postprocess_align` (:396), whose
signatures this patch does not change — so nothing outside `mamba_utils.py` passes them arguments.

**Byte-identity is not slot-identity.** The kernels take these arguments POSITIONALLY, so a def anchor and its
call anchor can both match byte-for-byte, all eight greps can land, `ast.parse` can be clean, and the two
parameters can still sit at different indices in the two signatures. `precopy_mamba_align_fused_kernel` is the
one insertion whose two anchors are not the same slot by their own text: in the def, `state_dim_row_stride_ptr,`
is followed by `idx_mapping_ptr,  # [num_reqs] batch_idx -> req_state_idx (-1 to skip)`, while the launch passes
`self.state_dim_row_stride,` and then `idx_mapping,`. An insertion anchored on the def *pair* and applied after
it sits one slot below the insertion anchored on `self.state_dim_row_stride,`, and then the launch's
`self.state_num_blocks` binds to `idx_mapping_ptr`, its `self.guard_hits` binds to `state_num_blocks_ptr` and
`idx_mapping` binds to `guard_hits_ptr` — `tl.atomic_add(guard_hits_ptr, 1)` writes into the batch
index-mapping tensor. Nothing raises: both sides pass the same number of arguments, so there is no
`TypeError`, the counts are the correct ones, and the damage is a step that faults on the box instead of a
build that stops. The anchor disambiguates on that following line without consuming it, so both sides insert
at the same index.

What closes the class is not a count. `patch_mamba_guard_v32.py` reads the patched text back through `ast` and
pairs every inserted parameter with the argument the call passes at the same positional index, for every def the
patch touches (`SLOT_PAIRS` / `slot_problems`), and exits 1 with nothing written when the two indices differ — a
skew is a step-7 build failure, not a boot failure. The pairing on the patched file: `_copy_mamba_state_block`
#16 and #17 against its two call sites, `postprocess_mamba_fused_kernel` #15 and #16 against its two launches,
`precopy_mamba_align_fused_kernel` #13 and #14 against its one launch. Call-site completeness rides along in the
same read — the expected number of call sites is part of the pairing — and `_copy_mamba_state_block` itself
(1 def, 2 call sites, 1 docstring mention = 4 lines) sits in `MUST_STAY` beside v0.32's own kernels, so a third,
differently-shaped call reddens the build rather than reaching a boot.

What lands is byte-identical to the guard in the snapshot: the 31 lines naming `guard_hits` or `state_num_blocks`
appear in both files and in neither direction, so `grep -c -F guard_hits` = **19** and `state_num_blocks` = **12**,
the same two numbers the live `fast` artifact answers — which is what makes the two lineages' guards comparable
instead of mutually trusted. The patcher's contract is `port_v32.py`'s shape: `rc 0` patched · `rc 1` an anchor
did not match, or the result does not parse, with the `file:line` evidence printed and **nothing written** (every
count is measured before the first substitution) · `rc 2` refused, the target already carries a guard · `rc 3`
usage. Read offline against the file extracted read-only from the base at the pin digest: apply `rc 0`, second
apply `rc 2`, one perturbed anchor `rc 1` naming `:262`/`:313` with the target byte-identical afterwards, and
step 7's eight greps land on 19 / 12 / 4 / 0 / 0 / 0 / 2 / 2 with `ast.parse` clean, `py_compile` clean on the
patcher and `sh -n` clean on all 20 RUN bodies of `Dockerfile.v32`. The slot check exits 1 on the file the
pre-fix anchors produce, naming the def index and the call index that disagree, and exits 1 on a mutant that
swaps the two launch arguments — it reports the skew in both directions, not just the one this file had. The
same read on the same file with the def anchor applied after the `idx_mapping_ptr,` pair instead of before it
names the skew and writes nothing, which is the construction that proves the check has teeth.

**Three counts that make the remaining claims claims.** Two names the guard's lines use are not proven by any
anchor count, because no anchor contains them: `state_idx`, which the bounds check reads from
`_copy_mamba_state_block`'s own parameter list (`:192`), answers `grep -F -c state_idx` = **76** lines in the base,
and `logger.`, which the reporter calls, answers **2** (`logger = init_logger(__name__)` at `:31`). Both are
recorded beside their anchors in `files/patch_mamba_guard_v32.py`. `_copy_mamba_state_block` answers **4** —
1 def (`:191`), 2 call sites (`:479`, `:610`) and one docstring mention (`:581`) — and that is the number
`MUST_STAY` carries, so a third call site on a newer base reddens the build instead of reaching a boot.
`quant_config=vllm_config.quant_config`, which two `spark_profile_fast8_artifact_probes` read in the finished
image, answers **0** in `model.py` and **0** in `mtp.py` in the base image at the pin digest: those two rows are
claims about the sed, not presence-only reads over a whole file.

Two reads in the role changed shape rather than being added. `Dockerfile.v32` step 7 now deletes
`/tmp/mamba_utils_guarded.py` in the step that copied it, so a `patch` layer carries no snapshot it never reads,
and its `apply` branch `test -f`s the snapshot before copying it; a `COPY` cannot be gated on an ARG, so a
`patch` build still stops if the checkout drops that file — nothing in the step reads it in `patch` mode, and
deleting the `apply` hatch in its own commit is the fix when that day comes. And the `Qwen3_8FlashNext` absence
read (`tasks/main.yml`) no longer rides on `will_build`: the installed artifact is exactly what a run that skipped
the build boots, so the read now runs on every converge (`check_mode: false`, `--rm`, `--network none`,
`--entrypoint grep` — no engine touched), and its assert wants `rc == 1`: the image answered and the answer was
"no such name". `rc 0` is the day-0 name still installed; `rc 125` (tag not in this store) and `rc 2` (file not
in the image) prove nothing, which is why the assert does not accept "not 0".

What the build session no longer owes on this step: no `--build-arg MAMBA_UTILS_GUARD`, no diff read inside the
base (the file the build patches is the one just read, at the same digest) and no decision commit — the port is
this repository's own code, so `git log` on the patcher is its provenance. What is still **not** proven here:
nothing has been built or booted, so the patched kernel has never been compiled by Triton and the guard has never
run a step. Added kernel parameters are a compile-time contract that only the build reads, which is §6 step 4's
leg, not this one.

**The box leg, in order** (all of it from a session that is not spark-served; the build legs are long, so run
them detached):

1. ✅ **Done: the read-only pre-flight.** The base is in spark's store at the digest, all 8
   `spark_profile_fast8_base_probes` return `rc 0` with the counts above, and `port_v32.py --check-only` reports
   **9 anchors verified** with both of the checkout's own hash blocks green. What no read above substitutes for is
   the role's own provenance assert (`checkout_pinned`: `HEAD == pin` and a clean `git status --porcelain -uno`),
   so one `--check` run of `-e spark_profile_fast8_build=true` is still worth having — now to confirm, not to
   discover.
2. the same command without `--check`, detached: greps the base, stages and re-anchors, builds. Its pull leg is a
   no-op on this host — the base is already in the store at that digest — and the build then prints the new image
   ID and fails on purpose (§6 step 4).
3. ✅ **the `mamba_utils` read, and the port it fed** (above: the three-layer table, the command, the anchor
   table). Step 7 ports the guard, so this leg needs no build-arg and no decision commit. `apply` reverts
   upstream's multi-group kernel and its `InputBatch` re-typing and reinstalls day-0 fork code, so a commit that
   sets it carries the 329-line count and the three layers.
4. `python3 scripts/bench/spark-fp8-image-probe.py --image <built tag> --skip-registry` (the box leg — a built
   image has no registry digest, and **`--image` is required**: the bare form resolves `spark_vllm_image`, the
   BASE pin, and would hand a verdict about the wrong lineage). Only on its `REACHABLE` verdict comes the pin
   commit: `spark_vllm_ultrafast_v32_image` **and** the `ultrafast-v32` name in `spark_llm_fp8_kv_capable_images`
   in the same change. No `spark_llm_overlays` re-anchoring belongs in this step: `fast8` sets
   `ple_overlay: false`, so its module paths arrive through the build and not through a bind over
   `models/qwen3_8_flash_next/…`; overlays matter only to an arm that binds them, if that base is ever bumped.
5. `python3 scripts/gate/check_spark_llm_gate.py && python3 scripts/bench/spark-llm-render-matrix.py && \
   python3 scripts/bench/spark-llm-probe.py matrix`.
6. the owner-window flip and the gate order: §6 step 7.

## 7b. The anchor census: every unchanged patcher, read at the base in one act

Two build attempts proved the build is a **serial oracle**: it answers one anchor per run, costs
~2–6 min and ~12 G of build cache each time, and the disk moves 188 G → 176 G → 164 G free. The census
answers all of them in one read-only act inside the base image, and it is the instrument that decides
what the remaining port work is. For that claim to hold, the census has to walk the patch set the
build walks, which is why the set is read out of `Dockerfile.v32` rather than kept beside it.

`anchor_census.py` reads the staged day-0 patchers, pulls their anchors out of the source with `ast`
(the `edit()` call arguments and the `EDITS = [(PATH, sentinel, [(old, new), …]), …]` tables), and
counts each one against the base image's own copy of that file. Nothing is written; the patchers are
mounted `:ro` and only `str.count` runs.

**Which patchers get walked is derived, not listed.** The set comes out of `Dockerfile.v32` itself: the
`COPY src/patch_*.py` lines stage — the destination name is remembered, so a patcher COPYed under
another name still counts as the run it feeds — the `RUN python3 /tmp/patch_*.py` lines apply, and a
step that names a patcher only in its prose is `guard-only`, which is step 12's shape. An integrity
check reddens when the derived set and the staged `src/` disagree in either direction, so a patcher
added upstream cannot be invisible to the census; `--self-test` breeds exactly that miss and requires
the redden. The set is **13 names in step order — 12 applied, 1 guard-only** — and 12 of them are the
day-0 patchers whose anchors are countable: `patch_mamba_guard_v32.py` is step 7's in-repo port, staged
at the build-dir root and self-measured over its own 13 anchors (§7), not a day-0 file. A hand-kept
table cannot say any of that, and the one this section carried held 11 names: step 14's
`patch_low_latency_gemm_sm12x` was in no row at all, so "census clean" could not certify a build.

```bash
# on spark. Stage first: the census reads the patchers this repository's port_v32.py produces, not the
# day-0 copies an earlier build attempt left in /opt/homelab/ultrafast-v32-build/src.
python3 port_v32.py --checkout /opt/homelab/ultrafast-src/recipe/build/image \
    --stage /tmp/hd1206-census/stage                    # 23 anchors verified, the checkout untouched
# The base sits in spark's store by DIGEST only: the tag form of the pin does not resolve under
# --network none, so the reference below is the digest half of spark_vllm_v32_base_image.
docker run --rm --network none --memory 2g \
    -v $PWD/anchor_census.py:/census.py:ro \
    -v /tmp/hd1206-census/stage/src:/src:ro \
    -v IaC/ansible/roles/spark-profile-fast8/files/Dockerfile.v32:/Dockerfile:ro \
    --entrypoint python3 vllm/vllm-openai@sha256:6ff5ff0ddf36… /census.py /src
```

| step | patcher, as the Dockerfile names it | anchors | hold | already there | absent | not unique | disposition |
|---|---|---|---|---|---|---|---|
| 5 | `patch_never_evict` | 15 | 13 | 0 | 0 | 2 | **re-anchored ×1** — `port_v32.py` → `vllm/v1/core/sched/scheduler.py:342-345` (count 2 = the pair's two sides). The dial stays `""` and rejected, so this is plumbing, not a revived flag |
| 7 | `patch_mamba_guard_v32` | — | — | — | — | — | in-repo port, 13 anchors self-measured (`files/patch_mamba_guard_v32.py`); not a day-0 file, so the census lists it and reads no rows |
| 8–10 | `patch_hit_debug` | 7 | 4 | 0 | 0 | 3 | **introduced ×1** — the base has no module logger in `v1/core/kv_cache_coordinator.py`, so `port_v32.py` introduces one on that file's own `from vllm.v1.request import Request` (:30); the `single_type_kv_cache_manager.py` half already introduces its own |
| 8–10 | `patch_mamba_align_split` | 2 | 2 | 0 | 0 | 0 | **re-anchored ×2** — the worker half is upstream at `v1/worker/gpu/model_states/mamba_hybrid.py:121-124`, so the pair became a post-state guard there; the scheduler half still holds at `v1/core/sched/scheduler.py:469` |
| 8–10 | `patch_step_profile` | 1 | 0 | 0 | 1 | 0 | applies as written — append-plus-assert, no anchor the census can read; the precondition is `class GPUModelRunner` **1** and `_step_profile` **0** in `v1/worker/gpu/model_runner.py` |
| 12 | `patch_short_conv_async_h2d` | 16 | 5 | 0 | 11 | 0 | **base already holds the post-state, guard only** — `vllm/v1/attention/backends/short_conv_attn.py:334` and `:337` are both `async_tensor_h2d(`, so the step greps instead of applying (rule 1 below) |
| 13–17 | `patch_measure_draft_mass` | 6 | 2 | 0 | 3 | 1 | applies as written — its five named anchors (`RS_ANCHORS`/`MM_ANCHORS`) each count **1** in `v1/worker/gpu/spec_decode/rejection_sampler.py` and `model_executor/layers/fused_moe/experts/marlin_moe.py`; its 3 `absent` rows are `MODULE_SRC` prose of the module it installs, not base anchors |
| 13–17 | `patch_low_latency_gemm_sm12x` | 13 | 2 | 0 | 8 | 3 | **R3 — awaiting owner ruling.** Only the target-path constant is re-anchored (`qwen3_8_flash_next` → `qwen4_exp`); the gate and its plumbing are a different shape at this base. Evidence and both dispositions below |
| 13–17 | `patch_in_proj_ba_gemv` | 4 | 3 | 0 | 0 | 1 | applies as written — every base anchor holds; `qwen_gdn_linear_attn.py:454` carries the class it wraps |
| 13–17 | `patch_ple_rendezvous` | 10 | 0 | 0 | 10 | 0 | **census blind spot, not a verdict** — its target is `${SP}/vllm_ple_mmap.py`, a file this build installs at step 1, so nothing can be counted in the base image. Read against the staged artifact instead: all 6 anchors **1** each there |
| 13–17 | `patch_verify_topk_pivot` | 6 | 6 | 0 | 0 | 0 | **re-anchored ×5 entries** — `vllm/sample/ops/topk_topp_sampler.py:466` (the `logits.shape[0] >= 8` heuristic is gone) and `:469-470` (`allow_cpu_sync`), `v1/worker/gpu/sample/sampler.py:234-236` and `v1/worker/gpu/spec_decode/rejection_sampler.py:265-266` (`seq_lens_upper_bound_np`) |
| 18–19 | `patch_block_drop` | 16 | 7 | 1 | 8 | 0 | **re-anchored ×5** — `config/speculative.py:452`, `:1948-1954`, `v1/core/single_type_kv_cache_manager.py:973-975`, `…/mooncake/store/worker.py:1512`, `:1660-1663`. The 8 remaining `absent` rows are day-0 pairs upstream merged instead (vllm#53388): `use_eagle_block_drop` is already read at `v1/core/sched/scheduler.py:287,316-317,333`, `v1/core/kv_cache_utils.py:2066`, `v1/simple_kv_offload/manager.py:204-211` and the offloading connector's `:232-236`, and the patcher's own sentinels skip a file that already reads it |
| 18–19 | `patch_r7_logger` | 5 | 0 | 0 | 4 | 1 | same blind spot as step 16 — both targets (`vllm_inproj_ba_gemv.py`, `vllm_ple_mmap.py`) are files this build COPYs, not base content; `logger = init_logger(__name__)` counts **1** in the staged `vllm_inproj_ba_gemv.py` |

101 anchors, 44 holding, 1 already present, 45 absent, 11 not unique at `6ff5ff0d…`, over 12 of the 13
derived patchers. Raw rows, commands and the self-test transcript:
[`raw/anchor-census-derived-20261027.txt`](raw/anchor-census-derived-20261027.txt);
[`raw/anchor-census-20261027.txt`](raw/anchor-census-20261027.txt) is the same base read with the
earlier hand-listed 11-name set and is kept because its `patch_low_latency_gemm_sm12x` rows are the
ones the derived census re-derives.

**The two weaknesses to read before using a row.** (1) Where a patcher applies the same edit through a
loop (`for path in FILES.values(): add_gate(path)`), the census cannot resolve which file a call means
and counts over the whole installed tree — such a row is marked `(loop-built target)` and is NOT a
verdict. `patch_hit_debug` is that shape, so its five target files were counted by hand at the base:
the day-0 `logger = init_logger(__name__)` line is present in `kv_cache_manager.py`, `block_pool.py`
and `sched/scheduler.py` (1 each) and **absent in `kv_cache_coordinator.py` and
`single_type_kv_cache_manager.py` (0 each)** — the first of those is the `[14/38]` red. (2) A patcher
whose target is a file **this build installs** — steps 1 and 11 COPY `vllm_ple_mmap.py`,
`vllm_inproj_ba_gemv.py`, `vllm_measure_draft_mass.py` — has nothing to count in the base image, so
its `absent` rows say "not in the base", which is true and irrelevant; those anchors must be counted
against the staged artifact, and the numbers above are that second read. An `absent` count is
therefore never by itself a prediction of where the build stops: of the 45, 18 are targets this build
writes itself or prose the patcher carries (`patch_ple_rendezvous`, `patch_r7_logger`,
`patch_measure_draft_mass`, `patch_step_profile`), 11 are the post-state rows inside the guard-only
step 12, 8 are the `patch_block_drop` day-0 pairs upstream merged under another name, and the last 8
are step 14 — R3, the one open question left.

### The disposition rule the census feeds — RULED (owner, 2026-10-27): **port everything, drop nothing**

The artifact ships the whole day-0 patch set on the v0.32 base. Two dispositions are left, and neither is
a judgement about whether a patcher is wanted:

1. **the base already has the post-state** → the patcher applies nothing here, and its step guards the
   **post**-state instead of the day-0 anchor. The effect ships; nothing is dropped.
   (`patch_short_conv_async_h2d`, done — `short_conv_attn.py:334,337` are both `async_tensor_h2d(` at the base.)
2. **the anchor is absent** → re-anchor it in the in-repo patch set (`port_v32.py` anchor entries, counted
   before and against the base), never in `/opt/homelab/ultrafast-src`, whose clean `git status
   --porcelain -uno` is the provenance proof.

**This reverses `f42638e2`.** `patch_never_evict` was dropped there as "class 3, with a ruling" — but
[`services-ai-rejected.md`](../../../docs/services-ai-rejected.md) rejects the **dial**
(`spark_llm_never_evict_prompt: ""`), not the patcher, so under this ruling the patcher goes back in
`Dockerfile.v32` step 5 re-anchored, and the flag stays empty and still rejected: the built image carries
the plumbing, and nothing renders it. `patch_hit_debug`'s `[14/38]` red is therefore a re-anchor too, not
an open question: `logger = init_logger(__name__)` has to be introduced where the base lacks it
(`kv_cache_coordinator.py`, `single_type_kv_cache_manager.py`) instead of being searched for.

What the ruling does **not** buy: any anchor re-anchored from a count rather than from a read of the
base's own text. A `sed`-shaped no-op that matches nothing is the failure this census exists to make
loud, and it is silent in exactly the two GB10 constants §2 names.

#### R3 — step 14's `patch_low_latency_gemm_sm12x`: the fatal row, left open — **awaiting owner ruling**

`Dockerfile.v32` step 14 runs the patcher, so a build with R3 unanswered stops there and prints no
image ID. The step stays fatal rather than guessed at: of the §7b ruling's two dispositions, rule 1
needs a read of the base's post-state and rule 2 needs to re-decide what upstream has already
decided, and this row is where that line falls. The one build this lineage owes is the build with R3
answered, not a build that discovers R3 for 12 G of cache.

The evidence, every line of it read in the base image at `6ff5ff0d…` by
[`r3_step14_reads.py`](r3_step14_reads.py) — one read-only `docker run`, output in
[`raw/r3-step14-base-reads.txt`](raw/r3-step14-base-reads.txt):

| read at the base | result |
|---|---|
| the day-0 gate — `def _is_sm103() -> bool:`, `_llg_sm12x = _llg_sm12x_enabled()`, `if dtype != torch.bfloat16 or not _is_sm103():` | **0 each** in `vllm/models/qwen4_exp/nvidia/low_latency_gemm.py`: the predicate the day-0 patcher hooks is not in this file. It is not an invented shape either — the same idiom is upstream's own in two sibling packages, `vllm/models/deepseek_v32/nvidia/glm52_low_latency_gemm.py:88` (gate at `:147`, `:180`) and `vllm/models/kimi_k3/nvidia/low_latency_gemm.py:662`. `qwen4_exp` is the one file that moved to the plan table |
| the base's own gate | `enable_qwen4_exp_low_latency_gemm` at `:375`, its condition at `:382` — `if dtype != torch.bfloat16 or not plans:` — bf16-only, exactly like the day-0 one |
| what stands in place of the capability predicate | a **plan table keyed by device capability**: `QWEN4_EXP_GEMM_PLANS_BY_CAPABILITY:294-300`, whose `(12, 1)` entry is `QWEN4_EXP_SM121_GEMM_PLANS` (`:172`, introduced at `:171` as "DGX Spark (GB10) plans for TP=1 and TP=2 local shapes"), reached through `_runtime_ok:308-317` — `x.dtype == torch.bfloat16` and `weight.dtype == torch.bfloat16` |
| the second target, `model_executor/kernels/linear/cute_dsl/skinny_gemm.py` | `warmup_configs: set[SkinnyGemmConfig] = set()` **0**, `warmup_configs.update(plan.values())` **0**, `_cutedsl_available: bool \| None = None` **1** — the warm-up block the day-0 patcher appends to is a plan dict here |
| the dial | `grep -rl QWEN38NEXT_LOW_LATENCY_GEMM` over the installed tree: **0 files**. `IaC/ansible/group_vars/spark.yml:1379` renders it in `spark_llm_ple_dispatch_env`, which reaches a container only when the profile sets `ple_dispatch: true` (`IaC/ansible/templates/docker_services/spark-ai/docker-compose.yml.j2:141-144`; `fast8` does, `group_vars/spark.yml:1076`; `:1130-1131` records the `ple_dispatch: false` arm rendering none of it) — the knob is set and unread |

**Both dispositions, since neither is decided here:**

1. **Subsumed — apply nothing, guard the post-state.** The base gates the same effect on device
   capability and the GB10 plan the day-0 patcher existed to install is already in the table, so step
   14 becomes step 12's shape: grep the `(12, 1): QWEN4_EXP_SM121_GEMM_PLANS` entry and the bf16
   condition at `:382`, and a base that ever drops the Spark plan stops the build. This is the shape
   the evidence points at, it keeps the one re-anchor the file already carries (the `qwen3_8_flash_next`
   → `qwen4_exp` path constant), and it writes no new anchor.
2. **Ported — re-anchor the day-0 gate onto the base's own gate.** `_is_sm103()` becomes the capability
   lookup at `:348-351`/`:379-382`, the `_llg_sm12x_enabled()` latch goes where that table is read, and
   the `skinny_gemm.py` warm-up pair moves onto the plan dict. Four or five new `port_v32.py` anchors,
   each readable at the base — with `glm52_low_latency_gemm.py:88,147` as the in-tree template for the
   predicate's shape — and each one a place to re-decide a shape upstream chose, the class of error
   §7b exists to make loud.

What is **not** a third disposition: the env route. Rendering `QWEN38NEXT_LOW_LATENCY_GEMM=1` cannot
re-create a gate nothing reads at this base — the knob's meaning is a property of the patched build,
which is what the `ar-blk-lean` arm measures by removing it.
