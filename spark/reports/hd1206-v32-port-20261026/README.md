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
| the never-evict patcher (`src/patch_never_evict.py` → `arg_utils.py`, `config/cache.py`, `v1/core/block_pool.py`) | those files exist at the tag | re-verify the patch still applies; the flag itself stays REJECTED (`spark_llm_never_evict_prompt: ""`), this is about not breaking the build |

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
| a **`sed` that matched nothing** shipping a green build | every `sed` in `Dockerfile.v32` counts its anchor before (`test "$(grep -c …)" -eq 1`) and greps its marker after; the `Qwen4Exp*` names, their module paths and the three `sed` source constants are also grepped **inside the base image** before the build, and **inside the built image** after it the four step markers (`spark-fla-shmem`, `spark-fla-warps`, `_ple_mmap_apply(Qwen4ExpNGramEmbedding)`, `_mtp_draft_vocab_apply(Qwen4ExpMTP)`) plus the **absence** of the day-0 `Qwen3_8FlashNext` symbol in the installed `vllm_ple_mmap.py`; `port_v32.py` fails on an anchor whose occurrence count is not the expected one |
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
   image ID `6ff5ff0ddf36`, `arm64`/`linux`, 35.3 GB (`spark_vllm_v32_base_image`; the registry manifest for that
   digest is a single `arm64/linux` image, never a `-cu129` tag). Downtime: none, and `--pull=false` means this step
   is the whole of the base's availability — the role's own pull leg is a no-op while it holds.
3. ✅ **Done: the read-only pre-flight inside that image** — the `ple_layer.py` path, the `Qwen4Exp*` names, the two
   `sed` anchor strings and the `mamba_utils` step, all read at the digest (§7). These are
   `spark_profile_fast8_base_probes`, so they also run before the build and stop it.
   `scripts/bench/spark-fp8-image-probe.py` still owns the fp8-KV half of this leg (§7).
4. Build detached (`--tags spark-profile-fast8 -e spark_profile_fast8_build=true`, async), with upstream's own CPU
   self-tests re-run against the built tag, then let the role **fail on purpose** after printing the ID — the pin
   is a human commit. The `mamba_utils` step refuses while the guard is undecided (§7): its diff is read, and
   `apply` is a three-layer reversion, so the choice is an anchored patch of the guard or an owner commit that
   sets `spark_profile_fast8_mamba_guard: apply`.
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
| the day-0 marker comment text (`# --- qwen38-flash-dgx: …`) | `tests/test_iter6_patches_image.py:129` splits on it, so it is an anchor: kept byte-identical, only class names change | yes |
| the `${SP}` prefix **inside the release image** | all 8 `spark_profile_fast8_base_probes` are absolute paths under `/usr/local/lib/python3.12/dist-packages` and all 8 return `rc 0` in `vllm/vllm-openai:v0.32.0-aarch64@sha256:6ff5ff0d…` | yes (box) |
| the two GB10 `sed` source constants **inside the release image** | same read: `DEFAULT = 102400` → 1, `for num_warps in [2, 4]` → 1 — each `sed` has exactly its one source string to match, so neither GB10 fix can be a silent no-op | yes (box) |
| the `lm_head` sed line, once **per file**, inside the image | `…/nvidia/model.py` → 1 (probe 5), `…/nvidia/mtp.py` → 1 (not in the probe list; `Dockerfile.v32` step 6 counts each file separately) | yes (box) |
| the `mamba_utils` whole-file step, **read** rather than inferred | 329 changed lines over 39 hunks against the image's own copy, and the three layers that diff mixes are separated below | yes (box) |

⏳ **Still unproven anchors** — not decidable from raw source at the tag **or** from a read of the base image;
each one is loud at build time (upstream's patchers all assert `n == 1` per anchor) or is named below, so none of
them can pass silently:

* every **multi-line code anchor** inside the twelve unchanged patchers (`patch_block_drop.py`,
  `patch_measure_draft_mass.py`, `patch_verify_topk_pivot.py`, …). The files they edit exist at the tag and in the
  image; the exact surrounding text is not something a read of the base can settle. The build decides, and it
  fails loudly.
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
proven — which leaves the twelve unchanged patchers' internal anchors as the only anchors the build still decides.

**The `mamba_utils` diff, read inside the base image** — step 7's own refusal message is the command, run with the
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

1. **The guard is the recipe's own** and is in neither base image (40 changed lines name it, all on the snapshot
   side): it is still owed, and the base will not supply it.
2. **The `*_mamba_all*` pair is day-0 *base* code, not recipe code** — `fc120ece…` carries both, stock v0.32
   carries neither, so the copy moves fork-side code into a stock base.
3. **v0.32 adds a kernel the snapshot has never seen**: `get_aligned_state_indices_multi_group_kernel`,
   `_reinterpret_u64_as_i64`, `compute_aligned_state_indices` (a 64-line hunk and a 59-line one).
4. **v0.32 deleted code the snapshot still carries** — the `*_mamba_all*` pair, in the 60→13-line hunk.
5. **One signature change rides along**: `postprocess_mamba_align_gpu`'s `input_batch` is `InputBatch` at v0.32
   where the snapshot says `GPUInputBatch`, and the `CachedRequestState` import leaves with it.

So `apply` would add the guard (wanted), reinstall day-0 fork code (not wanted) and delete upstream's v0.32
multi-group path and its `InputBatch` re-typing (not wanted). The shape that keeps only the guard is an anchored
patch of those 40 lines. Until that is decided and committed, `spark_profile_fast8_mamba_guard: refuse` stands and
step 7 stops the build, which is the designed state.

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
3. ✅ **the `mamba_utils` read** (above, with the three-layer table and the command). What is owed is the decision
   it feeds, not another read: port the guard as an anchored patch, or set
   `spark_profile_fast8_mamba_guard: apply` deliberately. `apply` reverts upstream's multi-group kernel and its
   `InputBatch` re-typing and reinstalls day-0 fork code, so the commit that sets it carries the 329-line count and
   the three layers.
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
