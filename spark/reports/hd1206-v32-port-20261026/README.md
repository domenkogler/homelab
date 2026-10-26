# HD-1206 — the v0.32 lineage: what porting the UltraFast patch stack actually means

> **Role:** evidence + build-order — the patch-by-patch map between the recipe we pin and a v0.32 base, the role
> gaps that make a rebuild unsafe as written, and the rollback state of the box as it stands.
> **Linked from:** [`todo.md`](../../../todo.md) HD-1206 · [`docs/spark-llm-profiles.md`](../../../docs/spark-llm-profiles.md)

The profile `fast8` (`image: ultrafast-v32`) is authored and **gate-blocked on an empty pin**: the lineage it names
is the upstream patch stack *rebuilt on a v0.32 base*, and that build does not exist yet. This file is the survey
of what stands between here and there, taken read-only from the checkout on spark and from upstream source at the tag.

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
to refuse: `roles/spark-ultrafast-build` proves provenance with `git rev-parse HEAD`, and **editing tracked files
does not change HEAD** — a hand-patched tree passes the provenance assert silently and produces an image nobody
can rebuild.

## 4. Role gaps that make a naive rebuild unsafe (`roles/spark-ultrafast-build`)

| line | as written | effect on a second lineage |
|---|---|---|
| `tasks/main.yml:66-73` | "is the built image ID already present?" inspects **`spark_vllm_ultrafast_image`** | with the old pin non-empty the v32 build is **skipped** and the run reports success |
| `:88-97` | runs `recipe/build/image/build.sh --run`, no base/tag passed from IaC | builds over `iter6c`/`iter6d` — the tag that names the **live** `fast` image, leaving `4900c13e…` untagged and therefore `docker image prune -a`-able |
| `:125-133` | asserts `docker image inspect <spark_vllm_ultrafast_tag> == spark_vllm_ultrafast_image` | compares the NEW build against the OLD pin → a red that reads like a mistake, not like "this role is single-lineage" |
| `:52-58` | provenance = `HEAD == pinned commit` | blind to a dirty tree (§3) |

Fix before any rebuild: a per-lineage `(image pin, build tag, upstream commit)` set, the inspect/assert pair
reading the **lineage's own** pin, and a `git status --porcelain`-clean assert.

## 5. Rollback state of the box, as it stands now

* Local tags on spark: **`spark-rollback:fast` → `4900c13edab9…`** (the image the live `fast` profile boots) and
  `spark-rollback:reasoning → fc120ece0a38…`. They exist to keep both images referenced against a prune and to make
  the rollback pointer readable; `docker images` confirms both.
* Off-box archives on the NAS (`tank/data/host-images/spark/`, i.e. oldsrv's `/mnt/nas/data/host-images/spark`):
  `spark-fast-4900c13e.tar.zst` (9,567,717,777 B) and `spark-reasoning-fc120ece.tar.zst` (9,567,372,199 B), each with a
  `.sha256` sidecar, `zstd -t` clean and `sha256sum -c` clean; restore with `zstd -dc <file> | docker load`.
  Only the **engine images** are archived: the checkpoints and PLE tables are HF artifacts pinned by revision in
  `group_vars/all/versions.yml` (sets `b1-awq`, `ple-int4`, `ar-hybrid`, `ple-fp8`) and re-fetchable.
* The archive is a copy, not a second engine: nothing about it changes what boots. Rollback is still
  `spark_llm_profile: fast` + a detached converge (~20 min cold boot).
* Serving was never touched by any of this: `vllm-qwen-spark` read `img=4900c13edab9… started=2026-10-18T03:36:16Z
  restarts=0 running=true` before the first `docker tag` and after the last byte landed.

## 6. Build order (each step one act, none of them a gamble on `fast`)

0. **Owner:** rule the fork — a repo/commit we can pin, or an explicit in-repo patch set that the role applies on
   top of the checkout. Everything after depends on this, and the answer is not a hand-edit of the checkout (§3).
1. Parameterize `roles/spark-ultrafast-build` (§4) and re-run the offline gates.
2. Pull the base **on spark**: `vllm/vllm-openai:v0.32.0-aarch64@sha256:6ff5ff0ddf3658d2c2d677dac5ca2d4726ce0156b4371166d918181b210bd4bc`
   (`spark_vllm_v32_base_image`; arm64, never a `-cu129` tag). Downtime: none — it is a pull.
3. Read-only pre-flight **inside that image** before building: the `ple_layer.py` path, the `Qwen4Exp*` names, and
   the two `sed` anchor strings. `scripts/bench/spark-fp8-image-probe.py` covers the fp8 half of this leg; the two
   `sed` anchors need a `grep`, because a silent no-match is the only failure mode that survives a green build.
4. Port the patch set (§2), build detached (`--tags spark-ultrafast-build`, async; upstream's own CPU self-tests
   decide), and let the role **fail on purpose** after printing the ID — the pin is a human commit.
5. Record the built ID as `spark_vllm_ultrafast_v32_image` **and** add `ultrafast-v32` to
   `spark_llm_fp8_kv_capable_images` in the same change (that list is what makes an fp8 profile legal at all).
6. Offline: `check_spark_llm_gate.py`, `spark-llm-render-matrix.py`, `spark-llm-probe.py matrix`.
7. Owner window: flip `spark_llm_profile: fast8` with a per-run `-e spark_llm_allow_uncertified=true`, converged
   **detached**; read the engine's own `GPU KV cache size` line (the projection is 1,095,830 slots = 4.18 ×); then
   gates 0–7 and the dtype gates 8–9. Rollback = `spark_llm_profile: fast` + detached converge.
