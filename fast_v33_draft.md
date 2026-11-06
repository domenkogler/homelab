# `fast_v33_draft.md` — draft brief: `fast-v33-*`, the live `fast` weights on a v0.33 build

> **Role:** the draft a lane session picks up to build ONE arm that keeps `fast`'s weights and takes the
> speed work that exists elsewhere: the AR-hybrid checkpoint on `spark_vllm_v33_base_image`, carrying the
> loader patches, the v0.33+-layout PLE hook, fp8 KV and CUDA graphs. It is a **draft plan, not a decision
> log**: the rulings it executes are recorded with their date and their landing place, and the durable
> facts belong in the owning docs named in the last section, not here.
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
| the day-0 UltraFast patch stack, re-anchored | `spark_ultrafast_upstream_commit` (`0c391a3`, which **is** the tip — upstream has not moved since 2026-09-29) | Apache-2.0 | `roles/spark-profile-<v33-lineage>/files/` (new dir, created in the same commit as this plan's first build act) | a marker per patched step, read in the built image |
| the PLE mmap install hook for the `qwen4_exp` class layout | blazux `vllm_ple_mmap.py::_install()` at `spark_blazux_upstream_commit` | Apache-2.0 (attribute the file) | the same `files/` dir | `_install()` present + the hook's own anchor names grepped out of the built image |
| loader patches: MoE clone-before-copy, `pread` for small tensors, expert names by index, chunked embed/lm_head copies | blazux patchers `patch_moe_load_clone.py`, `patch_load_pread.py`, `patch_moe_name_index.py`, `patch_embed_chunked_copy.py` (their MTP prefilter also targets the v0.33 MTP module path — smallest prize, last) | Apache-2.0 | same dir, re-anchored (see the trap in section 5) | each patcher asserts its own site count, and the build re-reads the marker |
| CUDA graphs (PIECEWISE) instead of `enforce_eager` | the graph-capturable hook from the survey in section 4 | depends on survey | the profile key `enforce_eager` | `nvidia-smi`-free: the boot log's capture lines + a timed leg |
| fp8 KV | already in the base (the upstream read path ships since vLLM v0.31) | n/a | `spark_llm_fp8_kv_capable_images` in `IaC/ansible/group_vars/spark.yml` | **only** on the box leg of `scripts/bench/spark-fp8-image-probe.py` printing `REACHABLE-ON-THIS-PIN` on the built ID, in the same change |
| the client contract | unchanged | n/a | unchanged | `python3 scripts/bench/spark-llm-render-matrix.py` shows the four anchors unmoved |

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
| `/` free | **174,712,012,800 B**; the floor is 150,000,000,000 B ⇒ **24.7 GB of headroom** | `df -P -B1 /` |
| XFS free | **394,993,770,496 B** | `df -P -B1 /mnt/spark_nvme` |
| `/` consumers | `models` 124 GiB (on `/`), containerd 88 GiB, docker 20 GiB; everything else is MB-scale (`/var/log` 922 MB, apt cache 591 MB, journal 312 MB) | `du` reads |
| the hard-link finding | under the os-rooted models dir: **132,710,444,790 B unique**, of which **70.1 GB is shared** between the AR checkpoint and the derived dense-drafter dir (77 of its 81 files are hard links into the checkpoint, all 67 shards). Exclusive bytes: PLE table 52.3 GB, AR checkpoint 5.2 GB, drafter 5.1 GB | inode-level walk |
| `nvfp4-nvidia` (the other lane's weights) | staged, 25 files / **132,734,506,847 B**; its hybrid twin absent | `find` + a byte sum |
| AR checkpoint shape | 68 shards, **224,454 tensors** (223,060 expert tensors) | the staged `model.safetensors.index.json` |
| v33 base pin | `vllm/vllm-openai:v0.33.0@sha256:d825baf9…` — registry answers the same manifest-list digest, with an **arm64/linux** child `sha256:e3481489…`, updated 2026-11-02 | hub API |
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

Two public leads may already contain the work this draft would otherwise hand-port. Record what is found in
`docs/services-ai-rejected.md` / the owning doc — an answered question leaves no options behind.

| lead | what to read | the verdict to write down |
|---|---|---|
| the AutoRound recipe's active branch (`magi-v5-public`) — its main branch says development moved there and names a vLLM 0.32 stack with a **graph-capturable host function for local-SSD PLE**, an fp8-KV/drafter investigation and a 1M-context recipe | the hook implementation, the graph-capture claim, its licence, its pin | does the hook work **with CUDA graphs on**? that single answer decides `enforce_eager` in the new profile |
| `fastsafetensors` / InstantTensor-style bulk loading | what it patches and at which layer | is it an **alternative** to the four loader patchers (one dependency) or **additive** to them (both)? price the boot either way |
| the day-0 UltraFast base | confirm again at run time that our pin is still the tip | if upstream moved, re-anchor against the new tip and say which commit in the build record |

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

Carried forward from the v32 window, unchanged: the checkout must be clean (`git status --porcelain -uno`),
the build writes exactly **one** new tag in its own repository, every other lineage's tags are re-read after
it and must still resolve, the lineage's own pin is what the built artifact is asserted against (never
another lineage's), and the artifact lands under a **new tag — never in place**, because `fast` is the
rollback and `spark-rollback:fast` is archived on the nas.

---

## 6. The runbook (ordered; who may run what)

Rule 0 binds the whole run wherever it sits: **no timed leg from a seat that spark serves**, children
included (`docs/orchestration.md`). Steps 1–4 are reads/builds and need no external seat; step 5 onward
does (`spark/reports/external-window-card.md`). Every live converge runs **detached** — `nohup … &` + a log
file + poll; `--check` is the only safe foreground form.

| # | act | form | acceptance, one line |
|---|---|---|---|
| 1 | the disk act (section 3) | owner-present, one converge of the affected profile, detached | `df -P -B1 /` reads above the floor **after** the container recreates, and the boot's `GPU KV cache size` line matches `fast`'s |
| 2 | author the lineage (census + patchers + role data + tag + pin placeholder) | a lane, offline | `python3 scripts/gate/check_spark_llm_gate.py` green; the new arm renders `GATED` (empty pin) in the render matrix, not broken |
| 3 | the build | `nohup bash scripts/ansible/ansible-run.sh IaC/ansible/playbooks/spark.yml --limit spark -e '{"spark_profile_fast_v33_build":true}' --tags spark-profile-<v33-lineage> --no-pull > /tmp/fastv33-build-$(date +%Y%m%d-%H%M).log 2>&1 &` | the run ends RED on the unpinned-ID fail **by design** and prints the immutable ID; every marker probe returned 0 |
| 4 | pin + fp8 admission | commit the printed ID in `IaC/ansible/group_vars/all/versions.yml` alone; then `python3 scripts/bench/spark-fp8-image-probe.py --image <ID> --skip-registry` | the probe prints `REACHABLE-ON-THIS-PIN`; the capable-list entry lands in that same change (an `UNDECIDED` run is not a verdict) |
| 5 | flip the control arm | detached, `-e spark_llm_profile=fast-v33-bf16 -e spark_llm_allow_uncertified=true --skip-tags tailscale-node` | `RestartCount=0` after 30 min **and** the boot prints the same token count `fast` prints; read the timestamps — boot time is this arm's headline measurement |
| 6 | quick tier | `python3 scripts/bench/spark-llm-probe.py all --profile fast-v33-bf16` + one determinism leg (identical prompt twice, first-token logprobs compared) | health/reasoning/ctx/concurrent pass; logprobs byte-equal across the two runs |
| 7 | official gates 0–2 | `scripts/bench/spark/hd469-baseline.sh`, `scripts/bench/spark/usable-sampler.sh` | host floor curve prices the arm's real `fixed_cost_bytes` (the declared one is derived until this leg replaces it) |
| 8 | the fp8 arm | same flip with `fast-v33-fp8`, then gates 0–2 + the dtype gates against the bf16 control | `GPU KV cache size` ≈ 1.09 M slots (the fp8 projection — the engine's line wins); MTP acceptance within noise |
| 9 | gate 7 | one working day of watchdog samples while the arm serves | no growth above 2 GiB/h under traffic that fails to return at idle |
| — | rollback | `-e spark_llm_profile=fast`, detached | the box serves `fast` again; never a restart loop left running |

---

## 7. Certification: what carries over from `fast`, and what must be re-taken

Because R1 keeps the **weights** identical, the accuracy evidence carries; everything about the **build**
must be re-read. The split below is the honest minimum — and `certified: true` stays binary and
gate-enforced, so a quick pass is recorded as evidence text, never as a certification.

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
| the hook is not graph-capturable | graph capture fails or the arm boots eager | the survey answers this before authoring; `enforce_eager: true` remains a legal first build |
| graphs × the mmap hook (the reason `fast` is eager) | restart loop with `RestartCount` climbing, `OOMKilled: false` | boot the **bf16 control** first, read `RestartCount` before any timer |
| `/` ends below the floor and a rollback is needed | the rollback converge dies at the disk assert | the named exemption exists (R3); the nas archive is the deeper rollback |
| fp8 admitted on an `UNDECIDED` probe | the arm boots into the BF16-only QSA guard | the capable-list entry requires `REACHABLE-ON-THIS-PIN`, same change |
| the tailscale leg aborts a whole-playbook run | the run dies at the tailscale role's vault lookup | carry `--skip-tags tailscale-node`; mint `tailscale-spark_api` as its own owner act |
| build cache pruned to make room | the rollback image's layers are gone | ⛔ never prune; report the free-bytes number instead |
| a rebuilt `fast` in place | the rollback pair splits (`spark-rollback:fast` + the dial) | new tag, new arm, always |

---

## 9. Unresolved — for the owner, before step 5

Two questions are genuinely open and this draft does not decide them. Each belongs in
`docs/spark-llm-profiles.md` as an `Options` row with the shape the conventions require (the derived id
space currently tops at OQ-17, so the next is **OQ-18**) — mint them there, not here:

1. **Graphs or eager** on the v33 AR arm, if the survey shows the hook is not graph-capturable.
   Cheap test: boot the control arm eager, then once with capture, comparing `RestartCount` and one timed leg.
2. **Whether the MTP prefilter patch is worth its re-anchor cost** (it targets the v0.33 MTP module path and
   upstream's own table prices it at 32 s → 1.2 s of a 46 s drafter load).
   Cheap test: count the tensors the drafter reads on a boot without it.

## 10. What this draft deliberately does not do

It does not build, converge, flip, boot or touch spark; it does not edit `todo.md` rows, the catalogue or
the floor value; it does not open an `Options` section (section 9 names where those rows belong); and it
does not schedule the blazux arm — that lane keeps its own row and its own dependencies.
