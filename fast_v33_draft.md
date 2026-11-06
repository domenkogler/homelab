# `fast_v33_draft.md` — draft brief: `fast-v33-*`, the live `fast` weights on a v0.33 build

> **Role:** the brief the **autonomous** build-and-measure session picks up to build ONE arm that keeps
> `fast`'s weights and takes the speed work that exists elsewhere: the AR-hybrid checkpoint on
> `spark_vllm_v33_base_image`, carrying the loader patches, the v0.33+-layout PLE hook, fp8 KV and CUDA
> graphs. It is a **draft plan, not a decision log**: the rulings it executes are recorded with their date
> and their landing place, and the durable facts belong in the owning docs named there, not here. The one
> exception is deliberate: the **survey verdicts stay in this file** (R12), because they are decision input
> for this window and not knowledge the docs should carry.
> **Linked from:** `todo.md` rows HD-1206 and HD-1242, `prompt-spark-llm.md`
> **Authority: none.** `docs/spark-llm-profiles.md` owns the catalogue and the arithmetic;
> `spark/llm-profiles/README.md` owns the gate ladder; `docs/hardware-spark.md` owns the memory budget.
> Where this page disagrees with one of them, that page is right and this one is the defect.

---

## 0. The rulings this draft executes (owner, 2026-11-06)

| # | Ruling | Where it must land permanently |
|---|---|---|
| R1 | The next speed arm keeps **`fast`'s weights unchanged** (the AR AutoRound W4A16 hybrid checkpoint + the FP8 PLE table) and moves the **engine build** to the v0.33 base. New checkpoint families are off this lane's critical path | `docs/spark-llm-profiles.md` — the six-arm grid gains `fast-v33-bf16` / `fast-v33-fp8` and the v32 arms retire to evidence rows |
| R2 | **No GPU-clock change.** `spark_gpu_clock_cap_mhz` stays `300,2418`: the box already runs warm and the ceiling buys idle behaviour a 24/7 agent seat needs. The ~20 % clock headroom is spent on heat, not on speed | `docs/hardware-spark.md` §GPU clock cap — one sentence naming the thermal reason, so nobody re-derives it as an easy win |
| R3 | The root-partition free-space assert is **bypassed by a named, per-run exemption — not by editing the floor**. `spark_llm_os_min_free_bytes` keeps its value and its meaning; the exemption is opt-in, per-run, echoed loudly with the measured number, and it is a ruling with a date, not a default | `IaC/ansible/group_vars/spark.yml` (the flag, default `false`) + the assert in `IaC/ansible/roles/spark-llm-profile/tasks/main.yml` + `docs/hardware-spark.md` (the reason it is allowed to be off) |
| R4 | **One autonomous session runs the ladder it is allowed to run — pin, fp8 admission, flip, measure — with the build carved out into its own Paseo-bound session (R13)** (re-ruled by the owner 2026-11-06; it supersedes this row's earlier split, which kept the build in the preparing session). The preparing session authors and commits and **touches nothing**. The executing session is launched **independent** of any parent — an agent launched the ordinary way is that parent's **child**, same workspace, injected context, and it dies when the converge restarts the engine that serves the parent — and it runs on the row the owner named: `entrim` / `deepseek-ai/DeepSeek-V4.1-Flash-1017`, with **both** `--env` pairs, because a row delivered only through `--model` leaves `PI_MODEL` telling the provenance gate the local engine. The prompt carries the worktree act ([`CONVENTIONS.md`](CONVENTIONS.md) §6) before any edit | [`paseo-readme.md`](paseo-readme.md) section 3 (the independent shape) · section 4 (the env pair is the ledger's truth) · section 5 (workspace binding) — the commands and the four verification reads live there, not here |
| R5 | The arm **boots eager first**, then is re-booted **with CUDA-graph capture** in the same window. If capture does not hold, the answer is **a smaller KV pool, never a bigger ceiling** (step 6a) | `docs/spark-llm-profiles.md` §7 (the flip order) + `docs/hardware-spark.md` §Unified-memory budget (the pool arithmetic that prices it) |
| R6 | **The engine ladder, and the end state:** `fast-v33-bf16` + its quick tier, then `fast-v33-fp8` + its quick tier, and the window **ends with `fast-v33-fp8` serving**. The bf16 arm is a step on the way, not the destination | `docs/spark-llm-profiles.md` §7 (the flip order) |
| R7 | **The fallback ladder is two steps, in one pass each:** if fp8 will not hold, step back to `fast-v33-bf16`; if that will not hold, step back to `fast`. Each step is one detached converge; a second attempt at any rung is not authorized and a restart loop is never left running | `docs/spark-llm-profiles.md` §7 |
| R8 | **Small pools are a test axis, not only a failure plan:** step the KV pool down in 2 GB steps **as far as 12 GB**, reading the engine's own `GPU KV cache size` line and `RestartCount` at every step. Long boots are accepted — this window measures the arm, it does not yet serve from it | `docs/hardware-spark.md` §Unified-memory budget (the arithmetic and the governor: the pool is the knob, the ceilings are not) |
| R9 | **Up to three build attempts, run by worker children**, then stop and report. A failed attempt is *read* before it is rebuilt — the trap in section 5 is answered by reading the sites, never by widening an assert — and the reading lands in the port file with the rebuild | [`docs/orchestration.md`](docs/orchestration.md) §4 (O10, the child-lane contract this exercises) |
| R10 | **The MTP prefilter patch is carried in build #1** — a fifth patcher, same marker rule and same counted-site rule as the other four (this draft's open question, now ruled; the measurement is still taken, see section 9) | this file only (a build instruction for this window, per R12) |
| R11 | **The `/` → XFS relocation is deferred** out of this window; the R3 per-run exemption is how every `os`-rooted converge in the window — the flips and any rollback included — carries the below-the-floor state, printing the number it accepted | the flag lands in `IaC/ansible/group_vars/spark.yml` and `docs/hardware-spark.md` states the reason it may be off; the deferred act itself stays in the disk section of this file |
| R12 | **Survey output and this window's build decisions stay in this draft** — they are guidance for the next session, not permanent knowledge, so they are not written to `docs/` or to a `-rejected` log. R1–R5's own landing places are unchanged; this row governs everything else | this file |
| R13 | **The build is its own session, and it runs on the spark-served row.** Rule 0 bars timed numbers, not builds; and this build converge is *provably* engine-safe, proved rather than argued: `--list-tasks` under `--tags spark-profile-fast-v33` answers with this role's tasks and the `always` guards and nothing else — no `spark-llm-profile` render, no compose, and the role has no `notify`, so no handler can restart anything. It therefore needs no external model, while every flip and every timed leg still does (the rest of R4). It is launched through Paseo bound to a **derived** workspace (`--workspace`, never a remembered id) so it shows in `paseo ls` and can be attached to | [`paseo-readme.md`](paseo-readme.md) §3 (the independent shape) and §5 (workspace binding) for the mechanics; the standing engine-safe-converge exception is `docs/orchestration.md` §4 |

R4 is why the ladder below is one column and not two: the split existed to keep a dependent agent from being
killed by its own converge, and an independent launch answers that directly. The cost of the new shape is
named so nobody rediscovers it: the build legs now run on a paid external row.

R3 is the one that cuts against a standing instruction in the assert's own `fail_msg` ("never lower the
floor to make this line green"). It is honoured: **the floor is not lowered.** What changes is that a human
can, once, for one converge, state that they accept the measured free-space state — and the run prints the
number it accepted. A bypass that goes quiet is the failure mode; a bypass that prints is an audit trail.

---

## 1. The target artifact

**One lineage, two arms.** `fast-v33-bf16` is the control (it must print the SAME `GPU KV cache size`
line `fast` prints, which is what makes any later fp8 regression attributable to the dtype alone),
`fast-v33-fp8` is the capacity arm. Weights, served id, port, service and bearer are unchanged, so
`scripts/harness/pi/models-spec.yml` needs no edit.

| part | comes from | licence | where it lands | proof it landed |
|---|---|---|---|---|
| the day-0 UltraFast patch stack, re-anchored | `spark_ultrafast_upstream_commit` (`0c391a3`, which **is** the tip — upstream has not moved since 2026-09-29) | Apache-2.0 | `roles/spark-profile-fast-v33/files/` (new dir — it does not exist yet; the authoring act creates it) | a marker per patched step, read in the built image |
| the PLE mmap install hook for the `qwen4_exp` class layout | blazux `vllm_ple_mmap.py::_install()` at `spark_blazux_upstream_commit` | Apache-2.0 (attribute the file) | the same `files/` dir | `_install()` present + the hook's own anchor names grepped out of the built image |
| loader patches: MoE clone-before-copy, `pread` for small tensors, expert names by index, chunked embed/lm_head copies | blazux patchers `patch_moe_load_clone.py`, `patch_load_pread.py`, `patch_moe_name_index.py`, `patch_embed_chunked_copy.py` (their MTP prefilter also targets the v0.33 MTP module path — smallest prize, last) | Apache-2.0 | same dir, re-anchored (see the trap in section 5) | each patcher asserts its own site count, and the build re-reads the marker |
| CUDA graphs (PIECEWISE) instead of `enforce_eager` | the graph-capturable hook from the survey in section 4 | depends on survey | the profile key `enforce_eager` | `nvidia-smi`-free: the boot log's capture lines + a timed leg |
| fp8 KV | already in the base (the upstream read path ships since vLLM v0.31) | n/a | `spark_llm_fp8_kv_capable_images` in `IaC/ansible/group_vars/spark.yml` | **only** on the box leg of `scripts/bench/spark-fp8-image-probe.py` printing `REACHABLE-ON-THIS-PIN` on the built ID, in the same change |
| the client contract | unchanged | n/a | unchanged | `python3 scripts/bench/spark-llm-render-matrix.py` shows the four anchors unmoved |

**The names this lineage carries** (decided with the owner, and they are what the preparing session
authors): role `IaC/ansible/roles/spark-profile-fast-v33`, its build flag `spark_profile_fast_v33_build`,
tag `spark-fast:v33-<sha>` in its own repository, image name `ultrafast-v33` pinning
`spark_vllm_fast_v33_image` (empty until the build prints an ID) with `ultrafast-v33: v33` added to
`spark_llm_base_tokens`, and arms `fast-v33-bf16` / `fast-v33-fp8` whose pool is one knob
(`kv_cache_memory`, overridable per run) so R8's ladder never mints an arm name per pool size.

**What this lane is NOT:** the blazux arm (`bz-v33-*` in `todo.md` HD-1242, `docs/spark-llm-profiles.md`)
is a different checkpoint family with W4A4 activations and is not this lane's dependency; a hardware clock
change (R2); the `magi`/DFlash drafter axis (survey output decides whether it becomes its own HD row).

---

## 2. State as read on 2026-11-06 (read-only; nothing in this session wrote anything)

| fact | value | how it was read |
|---|---|---|
| serving profile | `fast` (`IaC/ansible/host_vars/spark.kogler.si.yml`), engine healthy, `restarts=0`, up since 2026-11-03 | `docker inspect` on spark |
| kernel / KHO | `7.0.0-1024-nvidia`, `kho=off` on the cmdline | `uname -r` + `/proc/cmdline` |
| clocks | `clocks.current.sm` 2405 MHz, `clocks.max.sm` 3003 MHz, `power.limit` N/A — the cap `300,2418` from `IaC/ansible/roles/spark/defaults/main.yml` | `nvidia-smi --query-gpu=…` |
| `/` free | **174,708,527,104 B**; the floor is 150,000,000,000 B ⇒ **24.7 GB of headroom** | `df -P -B1 /` |
| XFS free | **394,993,770,496 B** | `df -P -B1 /mnt/spark_nvme` |
| `/` consumers | `models` 124 GiB (on `/`), containerd 88 GiB, docker 20 GiB; everything else is MB-scale (`/var/log` 922 MB, apt cache 591 MB, journal 312 MB) | `du` reads |
| the hard-link finding | under the os-rooted models dir: **132,710,444,790 B unique**, of which **70.1 GB is shared** between the AR checkpoint and the derived dense-drafter dir (77 of its 81 files are hard links into the checkpoint, all 67 shards). Exclusive bytes: PLE table 52.3 GB, AR checkpoint 5.2 GB, drafter 5.1 GB | inode-level walk |
| `nvfp4-nvidia` (the other lane's weights) | staged, 25 files / **132,734,506,847 B**; its hybrid twin absent | `find` + a byte sum |
| AR checkpoint shape | 68 shards, **224,454 tensors** (223,060 expert tensors) | the staged `model.safetensors.index.json` |
| v33 base pin | `vllm/vllm-openai:v0.33.0@sha256:d825baf9…` — registry answers the same manifest-list digest, with an **arm64/linux** child `sha256:e3481489…`, updated 2026-11-02 | `docker manifest inspect` on the pinned digest, run on spark |
| v33 base **on the box** | **NOT pulled.** The pinned digest answers `No such image`, and the two `vllm/vllm-openai` images present are the day-0 base (`fc120ece…`, which is also what `spark-rollback` holds) and the **v32** base (`6ff5ff0d…`). So the ~48 GB pull is owed by this window rather than inherited from the blazux lane — and it is the act that takes `/` from ~174.7 GB to roughly 127 GB, which is the state R3's exemption exists to carry | `docker image inspect` on the pinned digest + `docker images --digests` |
| what serves now | the certified `fast` shape, confirmed from the container's own argv: `--max-model-len 262144`, `--kv-cache-dtype auto`, `--kv-cache-memory-bytes 20000000000`; `restarts=0`, up since 2026-11-03; `spark-rollback:fast` and `:reasoning` both tagged; the AR checkpoint, its drafter dir and `ple-table-fp8` all present under `/opt/homelab/models` | `docker inspect` on `vllm-qwen-spark` + `ls` |
| blazux recipe at the pin | the commit resolves; **exactly one `FROM`, byte-equal to the base pin**; `tools/fp8_convert.py` and the patcher files present | raw fetch at the pinned sha |
| the loader patchers' first assert, against our images | our live image carries **5** `expert_data.copy_(loaded_weight)` sites, the v32 image **4**; upstream's patcher asserts **exactly 2** | read-only `docker run --rm … grep -c` |
| `ep_weight_filter` | present in both our day-0 and v32 images | same read |
| boot, our own record | ~14 min to healthy on the AR lane; ~13 min cold on the 2026-11-03 rollback (`spark/reports/hd469-fast/README.md`, `spark/reports/hd1206-v32-port-20261026/window-20261103.md`) | reports |
| boot, upstream's own record | weight-load 450–541 s → 150 s (their patch 14) → 35.5 s (14–18); startup ~11 min → 4 min 32 s → **2 min 8 s** | their README's startup table |
| v32 lineage | built, pinned, **does not boot**: `cls.forward_impl` is absent at that layout; `RestartCount` 25 → 38 during the failed window | `spark/reports/hd1206-v32-port-20261026/window-20261103.md` |
| tailscale leg | `tailscaled` active but **`Logged out.`**, `tailnet_spark_ip` empty, the `tailscale-spark_api` vault item unminted ⇒ converges in this lane carry `--skip-tags tailscale-node` | `tailscale status`, `IaC/ansible/host_vars/spark.kogler.si.yml` |
| rollback insurance | `tank/data/host-images/spark/spark-fast-4900c13e.tar.zst` + its `.sha256`; `/tank` 3.5 TB free | `ls` on nas |
| repo verdict | `bash scripts/validate-all.sh --profile quick` → all validators passed (quick skips the seat/joined legs) | this session |

---

## 3. Prerequisite A — the disk act, and R3's bypass, exactly

**Ruled (R11, owner 2026-11-06): the relocation is deferred out of this window.** What follows is why that
is safe and where the exemption ends, kept because the next session re-reads it before it re-derives it.

**What the floor actually gates.** The only consumer is one assert in
`IaC/ansible/roles/spark-llm-profile/tasks/main.yml`, and it runs **only when the profile being converged
is an `os`-rooted vLLM profile**. The build path (`IaC/ansible/roles/spark-ultrafast-build/tasks/build_lineage.yml`
and the blazux role) never reads `df`, and a v33 arm rooted on XFS does not evaluate it either. So:

* a build today would **succeed** physically (174.7 GB free, ≤ ~48 GB consumed by the v33 base pull + the
  built image), and
* after it, `/` would read **~127–137 GB**, i.e. below the floor — and the next `os`-rooted converge,
  **including the documented rollback to `fast`**, would be refused until bytes are freed.

**The move that fixes it cheaply, and the one that does not.** Moving the PLE table alone (52.3 GB of
exclusive bytes) already buys room, but it is on `fast`'s serving path, so the bytes only release when the
container recreates — one boot either way. Moving only the checkpoint + the table does **not** free 127.6
GB: the dense-drafter directory hard-links every shard, so the rest stays pinned until that directory moves
in the **same** tree move. Any move must therefore be link-preserving (one tree, or `cp -al` + verify the
link counts on the target) and must be verified before the source is unlinked.

**The bypass, as code.** Default `spark_llm_os_free_gate_exempt: false` in `IaC/ansible/group_vars/spark.yml`;
the assert becomes "at or above the floor, **or** exempt"; an exempt run prints one loud line with the
measured free bytes, the floor, and the ruling reference. It is passed per run
(`-e spark_llm_os_free_gate_exempt=true`), **never committed true**, and the render/gate offline checks keep
grading the floor as if it were armed. `--check` must still answer the disk question (the read stays
`check_mode: false`, for the reason already written in that task's comment).

---

## 4. Prerequisite B — survey before authoring (a lane, ≤2 children, reads only)

Two public leads may already contain the work this draft would otherwise hand-port. **Write the verdicts in
the last column of this table — not in `docs/` and not in a `-rejected` log** (R12): they are decision input
for this window, and the durable rulings already have their owning docs.

**Status: both lanes answered** — `GRAPHS-LEGAL` and `ADDITIVE`, each with its citations in the table
below. Read the graphs verdict before touching `enforce_eager`, because it replaces the question this section
was asking; read the loader verdict before reaching for a `--load-format` flag that `fast` does not render
today. One ref mapping was corrected on the way: `v0.33.0` is commit `4ba787ec9959e566d3b587a796dff07673324da5`
(`git ls-remote --tags … v0.33.0^{}`), which is what the build record should carry.

The hypothesis that was posed: `fast` is eager because the day-0 hook copies an **unpinned** CPU tensor
during capture (`spark/reports/hd489-ar-mmap/README.md`), and the v0.32+ class layout the hook is being
ported onto builds its table through a **pinned-host** embedding — so legality would follow from the hook
pinning its table. **The answer came back different in a way that matters more than the verdict word:**
legality is real, but reaching it through a pinned host table is the wrong door on this box, and the door
that is actually open is the recipe's mmap host function. The arithmetic is in the verdict row and in the
risk register; the short of it is that our table is 48.67 GiB, `pin_memory=True` rounds a pinned allocation
up to the next power of two, and the fix for that upstream is still an open pull request.

| lead | what to read | the verdict to write down | verdict (write here, with its citation) |
|---|---|---|---|
| the AutoRound recipe's active branch (`magi-v5-public`) — its main branch says development moved there and names a vLLM 0.32 stack with a **graph-capturable host function for local-SSD PLE**, an fp8-KV/drafter investigation and a 1M-context recipe | the hook implementation, the graph-capture claim, its licence, its pin | does the hook work **with CUDA graphs on**? that single answer decides `enforce_eager` in the new profile | **GRAPHS-LEGAL — and get there through the mmap host function, not a pinned host table.** The branch lives on `Saren-Arterius/qwen3.8-Flash-DGX-AutoRound` (`magi-v3-public`, renamed `magi-v5-public`); [`338282c`](https://github.com/Saren-Arterius/qwen3.8-Flash-DGX-AutoRound/commit/338282cb0fb09abe3f98c47529ad03418c5ab638) ships `ple_mmap_graph.c`: the FP8 n-gram rows are copied from **mmap'd** safetensors shards inside a `cuLaunchHostFunc`, described in the commit as FULL_AND_PIECEWISE-safe with **no CPU copy in capture**, fanned across `VLLM_PLE_MMAP_WORKERS` at `VLLM_PLE_MMAP_CHUNK` rows, wired by `vllm_ple_mmap_v032.py` behind the RDMA backend (`VLLM_PLE_RDMA` — irrelevant here, no RDMA on this box). That is exactly the day-0 failure's shape reversed: the copy leaves the capture region and becomes a host function the graph launches, so the graph needs no pageable CPU read. The same branch family records full-graph == piecewise within noise ([`e21ced2`](https://github.com/Saren-Arterius/qwen3.8-Flash-DGX-AutoRound/commit/e21ced26f04b360a99f42eafeac9dd48f156cc4d)), an upstream measurement of "no cost" where this box's own measurement was a cost, which is a disagreement the capture attempt on the new build settles rather than this table. **The trap: do not buy legality with `pin_memory=True`.** vLLM's `Qwen4ExpPinnedHostEmbedding.materialize_tables` routes through torch's `CachingHostAllocator`, which rounds a pinned allocation up to the next power of two, and vllm-project/vllm#59848 — pin it at its exact size — is OPEN, not merged. Our table is **52,259,886,995 B = 48.67 GiB** (`du -sb /opt/homelab/models/ple-table-fp8`), so pinning it whole page-locks **64 GiB** on a 121 GiB box that reads ~17 GB available with `fast` serving. Port the mmap host func; leave the pinned embedding alone. |
| `fastsafetensors` / InstantTensor-style bulk loading | what it patches and at which layer | is it an **alternative** to the four loader patchers (one dependency) or **additive** to them (both)? price the boot either way | **ADDITIVE, and on the facts, not on taste — so do not switch `load_format`.** A bulk loader is an *iterator inside* `DefaultModelLoader`, not a replacement for it: `load_format` names `"fastsafetensors"` / `"instanttensor"` and both map back to that same loader, so what changes is how bytes arrive, never what the model does with them. Of the five carried loader patchers, three lose their reason if tensors arrive device-resident, one is already native in the v0.33 base for unrelated reasons, and the fifth — the **MTP name prefilter (R10)** — keeps its need but loses the mechanism that delivers it, because the prefilter hooks the name-stream the bulk iterator bypasses. That is a regression bought with a dependency. **Installability is moot anyway:** both are **core** CUDA requirements of vLLM v0.33.0 (`requirements/cuda.txt:22-23` at that tag: `fastsafetensors >= 0.3.3`, `instanttensor >= 0.2.2`, no `extra ==` marker in the published wheel metadata either), so they are already in the image we patch and adding a wheel is not the question — flipping a flag is, and `fast` renders no `--load-format` at all today, so the default path is what the patchers were written against. The arm64 story is fine (`fastsafetensors-0.5.0-cp312-cp312-manylinux_2_26_aarch64…whl` on PyPI, and its `"unified"` copier is documented for shared CPU/GPU systems — this hardware class). **The price, priced honestly:** upstream's own table for the stack we carry shows main-model weight load 450–541 s → 150 s → 35.5 s and startup ~11 min → 4 min 32 s → 2 min 8 s ([blazux `README.md:705,712,714` at `17b025f8`](https://github.com/blazux/qwen3.8-Flash-DGX/blob/17b025f89788a614e8c1ed2a8976ce986ac614fd/README.md)) — the patches already in build #1 capture that, so the loader would be buying the *same* seconds twice. **Our own weight-load-only time has never been recorded** (`Model loading took` appears in `docs/` as a byte count, `hardware-spark.md`'s boot-log line, never a duration): read it off the boot log at step 5 and the comparison stops being inherited from a third party. |
| the day-0 UltraFast base | confirm again at run time that our pin is still the tip | if upstream moved, re-anchor against the new tip and say which commit in the build record | tip confirmed twice: `git ls-remote https://github.com/dime-online/qwen3.8-Flash-DGX-UltraFast.git HEAD main` answers `0c391a3e74b6a775cfe248691ca7fd855b1876a5` for both, which is the pin in `group_vars/all/versions.yml`. No re-anchor owed; re-read at run time anyway, since the answer has a shelf life. |

**Two things the table cannot hold.** First, that branch's speculative drafter is **DFlash2 ×3**
(`spec=dflash/3`, its own capture hook and allow-list), not MTP — so the graph-capturable PLE lookup is
**separable from its drafter**, which is what makes it portable into a lineage whose arm is certified on
MTP-3. Port the host func and its wiring; leave their launcher's defaults (a 18 GB KV pool, their
capture mode, their drafter) behind, because `fast`'s client contract and pool come from `group_vars`, not
from a third party's script. Second, the pinned-host arithmetic above: legality and the pinned route are
different decisions, and only one of them fits in 121 GiB.

---

## 5. The port, and the one trap that will bite

Order: **census → patchers → build definition → build → read the markers.** `spark/reports/hd1206-v32-port-20261026/anchor_census.py`
is the census tool and `IaC/ansible/roles/spark-profile-fast8/files/port_v32.py` is the pattern to copy
(counted before/after against the base's text, never a snapshot of the day-0 file dropped on the new one).

**The trap, measured:** the upstream MoE clone patcher asserts **exactly two** `expert_data.copy_(loaded_weight)`
sites; our live image has **5** and the v32 image **4**. Do not widen the count to make it pass — read each
site, keep the ones that are host-to-device copies of expert weights, and record in the port file why the
others are left alone. Related standing rule: a `sed -i` exits 0 when it matches nothing, so **every**
patcher must leave a marker string that the build re-reads inside the built image, exactly as
`IaC/ansible/roles/spark-profile-blazux/tasks/main.yml` does for its six probes.

**R10 makes the MTP prefilter a fifth patcher in build #1**, so census its site the same way: it targets
the v0.33 MTP module path, which is exactly the kind of moved file a `sed` survives by matching nothing.

Carried forward from the v32 window, unchanged: the checkout must be clean (`git status --porcelain -uno`),
the build writes exactly **one** new tag in its own repository, every other lineage's tags are re-read after
it and must still resolve, the lineage's own pin is what the built artifact is asserted against (never
another lineage's), and the artifact lands under a **new tag — never in place**, because `fast` is the
rollback and `spark-rollback:fast` is archived on the nas.

---

## 6. The runbook (ordered; who may run what)

Rule 0 binds the whole run: **no timed leg from a seat that spark serves**, children included
(`docs/orchestration.md`). **One session runs all of it (R4)** and it is **autonomous — the owner is not
present**, so section 0 and the stop conditions below are the whole authority it needs; anything they do not
cover is a stop, not an improvisation. It is launched **independent** of any parent per
[`paseo-readme.md`](paseo-readme.md) section 3 (the flip restarts the engine that serves the box, and a
dependent agent dies doing it), on the `entrim` row named in R4, with both `--env` pairs, and its prompt
carries the worktree act before its first edit. Every live converge runs **detached** — `nohup … &` + a log
file + poll; `--check` is the only safe foreground form. Every converge of an `os`-rooted profile carries
`--skip-tags tailscale-node` (§2's tailscale row) and, once `/` sits under the floor, the R3 exemption flag.

**Two sessions, one line of division (R13).** Steps 1–4 belong to the **build session**: the census, the patch
plan, the base pull, the build, the pin commit, the fp8 probe verdict. It runs on the spark-served row,
because that sequence provably cannot touch the engine (R13's `--list-tasks` proof), and it is bound to a
derived Paseo workspace so it is visible and attachable. Steps 5–10 belong to the **converge session**: the
flips, the memory ladder, every timed number — R4's remaining scope, on the external row, launched by the
owner once a built ID is pinned. Nothing crosses the line in either direction: a build session that converges
a profile has taken the one act that can kill the engine serving it, and a flip that happens off the external
row produces numbers the provenance gate cannot stamp.

**Delegation (R9).** Worker children take the build legs and any bounded read, under
[`docs/orchestration.md`](docs/orchestration.md) §4 (O1–O11: ≤2 concurrent, `model:` never named, a
per-child deadline, silence read as compaction not a hang). Two consequences
[`paseo-readme.md`](paseo-readme.md) section 8 states: a child of this session runs on the **same external
provider**, so the lane's read list is what [`CONVENTIONS.md`](CONVENTIONS.md) §8.6 grades — keep it off the
`secret-bearing` and `personal` docs — and timed legs run **after** the lanes close, never beside them.

| # | act | form | acceptance, one line |
|---|---|---|---|
| 0 | open the session's own worktree, then **re-read** §2 read-only | `git worktree add ../homelab-wt-<date>-<HHMM>`, then the §2 reads again | the tree is clean and the free-bytes / serving-profile / clock lines are today's, not this file's date |
| 1 | **prerequisite B is DONE** — both survey verdicts are in §4 (`GRAPHS-LEGAL` via the mmap host func; bulk loading `ADDITIVE`) | read them, then carry their consequences into the patch plan: the graph-capturable host func and its wiring join the census, no `--load-format` flip, no pinned host table | the plan names the host func's anchors, and nothing in it pins the 48.67 GiB table |
| 2 | **the lineage is already authored** by the preparing session (census, five patchers incl. the R10 prefilter, role data, tag, empty pin, the R3 flag) | verify offline, do not re-author | `python3 scripts/gate/check_spark_llm_gate.py` green and the new arms render `GATED` (empty pin) in `python3 scripts/bench/spark-llm-render-matrix.py`, not broken |
| 3 | the build, by a worker child (R9: **≤3 attempts**) — **and the base pull comes first**: the pinned v33 digest is NOT on this box (§2's on-the-box row), and the role only inspects it, so run `docker pull <spark_vllm_v33_base_image>`, re-read `df -P -B1 /`, and write the new number down before the role is called | `nohup bash scripts/ansible/ansible-run.sh IaC/ansible/playbooks/spark.yml --limit spark -e '{"spark_profile_fast_v33_build":true}' --tags spark-profile-fast-v33 --no-pull > /tmp/fastv33-build-$(date +%Y%m%d-%H%M).log 2>&1 &` | the run ends RED on the unpinned-ID fail **by design** and prints the immutable ID; every marker probe returned 0. A failed attempt is read and its reading written before any rebuild. The pull is expected to leave `/` under the 150 GB floor — from then on every `os`-rooted converge carries the R3 exemption flag, and ⛔ nothing is pruned to make the number look better |
| 4 | pin + fp8 admission | commit the printed ID in `IaC/ansible/group_vars/all/versions.yml` alone; then `python3 scripts/bench/spark-fp8-image-probe.py --image <ID> --skip-registry` | the probe prints `REACHABLE-ON-THIS-PIN`; the capable-list entry lands in that same change (an `UNDECIDED` run is not a verdict, and without it the fp8 flip is not authorized) |
| 5 | flip the control arm | detached, `-e spark_llm_profile=fast-v33-bf16 -e spark_llm_allow_uncertified=true --skip-tags tailscale-node` (+ the exemption flag if `/` is under the floor) | `RestartCount=0` after 30 min **and** the boot prints the same token count `fast` prints; read the timestamps — boot time is this arm's headline measurement; **and read the dispatch** with `python3 spark/reports/hd1206-v32-port-20261026/runtime_dispatch.py` against the running container, the first engine ever to construct the MoE class (item 3 of section 9); **and copy the boot log's `Model loading took …s` line** — the first weight-load-only number this repo will own, which is what makes §4's loader comparison ours instead of a third party's |
| 6 | quick tier on the control | `python3 scripts/bench/spark-llm-probe.py all --profile fast-v33-bf16` + one determinism leg (identical prompt twice, first-token logprobs compared) | health/reasoning/ctx/concurrent pass; logprobs byte-equal across the two runs |
| 6a | the capture attempt, and its price (R5) | once eager reads `RestartCount=0`: `enforce_eager: false`, the piecewise capture form, re-converged detached, `RestartCount` and the capture lines read **before** any timed leg | graphs hold and the leg stands — or they do not, which is a result to write down, not a bug to chase. The knob is the pool (6b); `spark_llm_device_hold_ceiling_bytes`, the pool ceiling and the clocks are **not** knobs (§4's governor, and R2) |
| 6b | the memory ladder (R8) | one boot + quick tier per step, `kv_cache_memory` down in 2 GB steps **to 12 GB**, each run as its own detached converge with the pool named on the command line | at every step the engine's own `GPU KV cache size` line and `RestartCount` are read before any timed leg; the ladder stops at 12 GB — never below, and never by raising a ceiling |
| 7 | flip the fp8 arm (R6) | as step 5 with `fast-v33-fp8`, only after step 4 returned `REACHABLE-ON-THIS-PIN` | the boot prints its fp8 line (the engine's number is the number of record, not the projection) and `RestartCount=0` after 30 min |
| 8 | quick tier on fp8, then the memory ladder on it | as steps 6 and 6b against the arm that will serve | health/reasoning/ctx/concurrent pass; each pool step read the same way |
| 9 | **end state: leave `fast-v33-fp8` serving** (R6) | no further converge | the arm is live and `RestartCount=0`; if the ladder took a step back, the ladder's own end state applies (R7) |
| 10 | write the window down | a report dir under `spark/reports/`, the boot-time and pool-step reads in it, the row and §4 updated, the draft retired with its row | every claim points at a log line or an engine line; the docs gain only what outlives the window |
| — | the fallback ladder (R7) | `-e spark_llm_profile=fast-v33-bf16`, then `-e spark_llm_profile=fast`, each detached | one pass per rung, in order; the window ends with the box serving and never in a restart loop |

**This window is not a certification window.** Official gates 0–2, gate 7 and the dtype gates 8–9 are out
of scope (they need the owner's scheduling, and gate 7 needs a working day of samples); `certified: false`
stands on both arms, `fixed_cost_bytes` stays DERIVED until gate 2 replaces it, and §7 is what a later
certification window owes.

**Stop conditions — where the autonomy ends.** Three build attempts, then stop and report (R9). One pass per
rung of the fallback ladder, ending at `fast` (R7). The memory ladder stops at 12 GB (R8). Never raise a
ceiling, never touch the clocks (R2), never prune the build cache — report the free-bytes number instead.
`/` free below ~80 GB at any pre-flight read: stop and report. No fp8 flip without `REACHABLE-ON-THIS-PIN`
(step 4). And a run that cannot leave the box serving stops at the last rung it can hold.

**The build session's launch line** (steps 1–4 only, on the spark-served row, bound to a derived workspace —
`--workspace` replaces `--cwd` because a bound workspace's path wins, which is why the prompt carries the
worktree act itself):

```bash
WKS=$(python3 -c "
import json,os
d=json.load(open(os.path.expanduser('~/.paseo/projects/workspaces.json')))
c=[w for w in d if w['cwd']=='/home/domen/source/homelab' and not w.get('archivedAt')]
print(sorted(c,key=lambda w:w['updatedAt'])[-1]['workspaceId'])")
env -u PASEO_AGENT_ID -u PASEO_AGENT_CWD -u PI_SESSION_ID -u PI_SESSION_FILE -u PI_PROVIDER -u PI_MODEL \
  paseo run --no-wait -q --provider pi \
    --model spark/spark/qwen3.8-flash-next \
    --env PI_PROVIDER=spark --env PI_MODEL=spark/qwen3.8-flash-next \
    --workspace "$WKS" \
    --title fast-v33-build --label lane=spark-llm --label phase=build \
    "Read fast_v33_draft.md. Run steps 1-4 ONLY: census, fill the patch plan, pull the v33 base, build,\
     pin the printed ID, run the fp8 probe. Then STOP and report - no profile converge, no flip, no boot,\
     no timed number; that is the converge session's work (R13). First act, before any edit: git worktree\
     add ../homelab-wt-\$(date +%Y%m%d-%H%M) (CONVENTIONS §6). Before and after every converge, read\
     docker inspect of vllm-qwen-spark (Id, StartedAt, RestartCount) and show the engine never moved."
```

**The converge session's launch card** (steps 5–10). The shape, the four verification reads and the traps are
[`paseo-readme.md`](paseo-readme.md) §3/§6 — this is only the data this window launches with, so the line
is not re-derived at launch time (§2: a re-typed copy is a second source; a re-typed *command* is the same
thing wearing a shell): the row the owner named, an independent launch (no `PASEO_AGENT_ID`, no
`PASEO_*SESSION*`), both env pairs, and a cwd that is **this repository with a worktree act in the
prompt** — the daemon-owned workspace would otherwise land in the merge station.

```bash
env -u PASEO_AGENT_ID -u PASEO_AGENT_CWD -u PI_SESSION_ID -u PI_SESSION_FILE -u PI_PROVIDER -u PI_MODEL \
  paseo run --no-wait -q --provider pi \
    --model entrim/deepseek-ai/DeepSeek-V4.1-Flash-1017 \
    --env PI_PROVIDER=entrim --env PI_MODEL=deepseek-ai/DeepSeek-V4.1-Flash-1017 \
    --cwd <absolute path of the homelab checkout> \
    --title fast-v33-window --label lane=spark-llm \
    "Read fast_v33_draft.md and run its ladder. First act, before any edit: \
     git worktree add ../homelab-wt-$(date +%Y%m%d-%H%M) (CONVENTIONS §6). \
     You are autonomous: §0's rulings and §6's stop conditions are your whole authority, and anything \
     they do not cover is a stop, not an improvisation."
```

Then prove the launch before believing it: `paseo inspect` for `ParentAgentId = null`, the `Model` /
`Provider` pair, and the `Cwd` — and read `LastUsage.CachedTokens` to see whether the checkout's context
came along, because that is the §8.6 question answered rather than assumed.

---

## 6b. What the preparing session left done, and where each piece lives

Everything below is committed on the branch this brief was merged from; the window starts at step 1 and
finds no authoring left to do.

| piece | where it lives | what the window must still do to it |
|---|---|---|
| the lineage | `IaC/ansible/roles/spark-profile-fast-v33/` (defaults = the plan and the lineage data, tasks = the order, files = `port_v33.py` + `Dockerfile.v33`, templates = the rendered plan) | fill `spark_profile_fast_v33_patch_plan` from the census; the role refuses to build until it is filled |
| the two arms | `IaC/ansible/group_vars/spark.yml` (`fast-v33-bf16` / `fast-v33-fp8`), pin name `spark_vllm_fast_v33_image` in `group_vars/all/versions.yml`, image name and base token in the two maps at the foot of the same file | pin the ID the build prints; nothing else changes them |
| the pool knob (R8) | `spark_llm_kv_pool_bytes` in `group_vars/spark.yml` — empty means the arm's own value, and `roles/spark-llm-profile` grades the EFFECTIVE pool, so a ladder step cannot boot past the ceiling or below the window | pass it per run: `-e spark_llm_kv_pool_bytes=12000000000` |
| the disk exemption (R3, R11) | `spark_llm_os_free_gate_exempt` (default `false`) and the assert that reads it, which prints the accepted number | pass it per run once `/` is under the floor; never commit it `true` |
| the render branch that makes an empty pin a refusal | `IaC/ansible/templates/docker_services/spark-ai/docker-compose.yml.j2`, the `ultrafast-v33` arm of `engine_image` | nothing — but read the render matrix before the first flip: an arm that renders an image instead of `IMAGE-PIN-EMPTY` is a fall-through, and this lineage's argv would boot and serve the wrong engine |
| the catalogue | `docs/spark-llm-profiles.md` — both arms, the retired v32 rows, the flip order and the fallback ladder | update the rows with what the boots actually printed |
| the queue | `todo.md` HD-1206 (this lane), HD-1242 (the blazux lane, un-parked and sharing the base pull) | trim HD-1206 as each ⏳ item lands; delete nothing else |
| the survey (§4) | this file's §4 verdict column and §9b | carry it into the patch plan: the graph-capturable mmap host func gets anchored and marker-probed, the pinned host table stays out, no `--load-format` flip |

---

## 7. Certification: what carries over from `fast`, and what must be re-taken

Because R1 keeps the **weights** identical, the accuracy evidence carries; everything about the **build**
must be re-read. The split below is the honest minimum — and `certified: true` stays binary and
gate-enforced, so a quick pass is recorded as evidence text, never as a certification. **The R6 window runs
steps 0–6 of this table and nothing above it**: gates 2, 7, 8 and 9 wait for a scheduled window, which is
why the arms end the window UNCERTIFIED and serving, on purpose.

| gate | verdict | why |
|---|---|---|
| 0 render | re-run, cheap | the arm is new; the parity guard proves the *unchanged* profiles did not move |
| 1 boot | **re-take — this is the arm's point** | boot time and `RestartCount` are the claim |
| 2 non-interference | re-take | graphs + fp8 move the host hold; the derived `fixed_cost_bytes` must be replaced |
| 3 depth / 4 concurrency | re-take (concurrency especially) | graphs and the chunk size are what this arm is testing |
| 5 needle at depth | re-take once, on the bf16 control | weights unchanged ⇒ a failure means the build moved something |
| 6 accuracy | **carries** from `fast` for the bf16 arm; fp8 re-takes it only if gate 9 opens | same checkpoint, same tokenizer, same template |
| 7 memory curve | re-take | the watchdog curve is the only thing that prices a new build's hold |
| 8 MTP acceptance | bf16-vs-bf16 comparison against `fast` (drafters differ if graphs change the spec path) | the drafter's numerics are unchanged, the runner may not be |
| 9 quality vs the noise floor | only on the fp8 arm, against `fast-v33-bf16` | dtype-only comparison, which is the cleanest fp8 read this box can make |

---

## 8. Risk register

| risk | how it shows | the move |
|---|---|---|
| a patcher silently matched nothing | the built image lacks the marker; boot looks normal | the marker read is mandatory, per patcher (section 5) |
| the hook is not graph-capturable | graph capture fails or the arm boots eager | ANSWERED: carry the recipe's `cuLaunchHostFunc` mmap form (§4 lead 1) and the answer is yes; `enforce_eager` is the dial, not a build property, so try `false` and fall back to `true` without rebuilding |
| graphs × the mmap hook (the reason `fast` is eager) | restart loop with `RestartCount` climbing, `OOMKilled: false` | boot the **bf16 control** first, read `RestartCount` before any timer — with one change: the host func is what makes the first capture legal, so the capture attempt is no longer a coin flip (§4 lead 1). Boot eager, then try capture. |
| `/` ends below the floor and a rollback is needed | the rollback converge dies at the disk assert | the named exemption exists (R3); the nas archive is the deeper rollback |
| a **pinned host table** smuggled in by the qwen4_exp embedding | boot dies on allocation, or `MemAvailable` collapses to single-digit GB and the watchdog arms: 48.67 GiB pinned becomes 64 GiB page-locked, because torch rounds a pinned allocation to the next power of two and the upstream fix (vllm-project/vllm#59848) is an open pull request | grep the built image for `pin_memory=True` in the PLE path before the first boot, and read `MemAvailable`/`CmaFree` during it — `usable-sampler.sh` catches the collapse, the question is only how expensive the lesson is |
| fp8 admitted on an `UNDECIDED` probe | the arm boots into the BF16-only QSA guard | the capable-list entry requires `REACHABLE-ON-THIS-PIN`, same change |
| the tailscale leg aborts a whole-playbook run | the run dies at the tailscale role's vault lookup | carry `--skip-tags tailscale-node`; mint `tailscale-spark_api` as its own owner act |
| build cache pruned to make room | the rollback image's layers are gone | ⛔ never prune; report the free-bytes number instead |
| a rebuilt `fast` in place | the rollback pair splits (`spark-rollback:fast` + the dial) | new tag, new arm, always |

---

## 9. Answered, and what is still open

**Both questions this draft opened are ruled, so it owes no `Options` row anywhere** — a ruled question
leaves no `Options` section behind (`CONVENTIONS.md` §8.3). Note about the id arithmetic an earlier revision
of this file carried: do not re-derive it from a `git grep` of `OQ-…` while this file still mentions an id
in prose, because a draft that names an id invents one; the rule is the derivation, and the mention is what
made it lie.

1. **Ruled (owner) — eager first, then capture, and a smaller pool is the failure plan.** Recorded as R5,
   and widened by R8: the small pools are a measurement axis in their own right, not only the capture
   failure plan. The survey's answer is now in §4 and it does not change that order — eager boots first,
   capture is tried after — but it does change what the capture attempt is expected to do: the verdict is
   GRAPHS-LEGAL provided the hook reaches for the mmap host function rather than a pinned host table, so a
   failed capture on the new build is a porting bug to read, not a property of the model to accept.
2. **Ruled (owner) — the MTP prefilter patch is carried in build #1** (R10), with its own marker and its own
   counted site. The measurement the open question asked for is still taken — what the drafter actually
   reads on a boot — and if it contradicts upstream's price, the finding goes **here**, not into the docs
   (R12).
3. **Carried over, not dropped: the runtime dispatch read.** Capability `(12, 1)`, the 16-shape SM121 plan
   table and `is_available() = True` are measured in the artifact, but no engine ever booted that constructed the
   model class, so `_runtime_ok` stays **inferred rather than observed** — UNRESOLVED, not failed. The reader is
   [`spark/reports/hd1206-v32-port-20261026/runtime_dispatch.py`](spark/reports/hd1206-v32-port-20261026/runtime_dispatch.py)
   and step 5 is the first boot that can run it. It survives the v32 row's retirement because the question was
   never about the base: it is about whether `fast`'s loader dispatches the experts or falls back to `F.linear`.

4. **The relocation question, answered with the box's own bytes, so nobody re-derives it.** The build does
   **not** need it: `/` reads 174,712,012,800 B, the v33 base pull plus the built image costs ≤ ~48 GB, and
   the build path never evaluates `df` at all. What the build does is leave `/` at **~127–137 GB — under the
   150,000,000,000 B floor yet not short of space**, which is exactly the state R3's named per-run exemption
   is for, and the state every later `os`-rooted converge (the flip included, and the rollback to `fast`)
   carries until bytes are freed. So the relocation is not a prerequisite of this window — it is what buys
   the armed floor back. Do it when a second ~48 GB pull has to land (that is `/` at ~80–90 GB free, where
   the margin stops being arithmetic and starts being luck), and then as one **link-preserving** tree move of
   the checkpoint pair to XFS: the drafter directory hard-links every shard, so a partial move frees nothing
   (section 3). The levers that free nothing, re-stated so they are not re-tried: build-cache prune (⛔, and
   its reclaimable figure is layer storage shared with live images), inactive images (736 MB between all of
   them), and staging on XFS (the engine boots images from the container store, and the store is on `/`).

## 9b. What the survey leaves open, in its own words

Three reads the survey could not do from a checkout, each with the act that settles it:

1. **Our own weight-load duration.** Every number in §4 is someone else's; `Model loading took` has never
   been recorded here as a duration, only as a byte count in a boot-log quote. Step 5 copies it, and the
   whole loader/boot comparison stops being inherited at that moment.
2. **Whether the base image carries the two loader libraries.** Both are core requirements of vLLM v0.33.0
   upstream, but "the base is not pulled" was the state when that was read, so the claim is about the
   release, not about this box. The first `docker run … python -c "import fastsafetensors, instanttensor"`
   on the built image settles it — and it matters only for knowing what a `--load-format` flip would do,
   since the verdict is not to flip one.
3. **Whether our patched hook is the graph-legal form, not upstream's.** §4 read upstream code at pinned
   commits; it cannot read the artifact until the artifact exists. The marker probe on `ple_mmap_graph.c`
   (or the Python form, wherever the census lands it) is the read that says so, and it is already in step 3.

One ref correction worth keeping: vLLM tag `v0.33.0` is commit
`4ba787ec9959e566d3b587a796dff07673324da5` (`git ls-remote --tags … 'refs/tags/v0.33.0^{}'`), not the sha a
survey lane first reported — the tag-to-commit mapping in the build record should come from that command.

## 10. What this draft deliberately does not do

It restates no part of the Paseo launch contract: the dependent/independent distinction, the workspace
binding, the model-proof reads and the traps are [`paseo-readme.md`](paseo-readme.md)'s, and the kick line
in section 6 carries only this window's data on top of that shape — the row, the title, and the worktree
act the prompt must carry because the daemon owns the cwd (`CONVENTIONS.md` §2: a re-typed copy is a
second source, which is why the shape is pointed at and only the arguments are written here).

It does not build, converge, flip, boot or touch spark; it does not edit the floor value; it does not open
an `Options` section (section 9 says why none is owed); and it does not schedule the blazux arm — that lane
keeps its own row and its own dependencies. What it does carry is this window's own guidance: rulings R6–R12
and the survey verdicts in §4 live here and nowhere else, by R12's choice and for R4's reason.
