# HD-469 `graded` profile — fp8 KV: the boot failure, and what it actually proved

Profile: `graded` — AWQ W4A16 + PLE INT4 + MTP3, **fp8 KV** (`--kv-cache-dtype fp8`,
`kv_cache_memory: 16,000,000,000 B`). Same weights, same engine, one variable.

Run book (commands, in order):

1. Gate (read-only, pre-boot): `ansible-playbook -i inventory.ini playbooks/spark.yml
   --limit spark --tags spark-llm-profile --check --diff` → `certified: false` + the
   override accepted, KV math closed.
2. Converge detached (engine swap): `nohup bash scripts/ansible-run.sh playbooks/spark.yml
   --limit spark --no-pull >/tmp/hd469-graded.log 2>&1 &` → then the boot below.
3. Gates 1–7 per [`../../llm-profiles/README.md`](../../llm-profiles/README.md) — never
   reached; the engine did not come up.
4. Rollback: `spark_llm_profile: reasoning` + converge detached.

## Gate results (as measured; rows 3–7 never ran)

| Gate | Measure | Result |
|------|---------|--------|
| 0 render | `validate-docker-services.py --only spark-ai` + probe `profile graded` | PASS (the probe printed 1,031,326 slots — a **wrong** number, see §Arithmetic below; the corrected projection is 876,664) |
| 1 boot | `/health` 200 + `RestartCount=0` | **FAIL — the engine never reached a healthy state.** It crash-looped at `EngineCore` init with `NotImplementedError: Qwen3.8-Flash-Next QSA requires a BF16 main KV cache` |
| 2 non-interference | probe `health` + `reasoning` at idle; `usable` ≥ floor | **not run: engine did not boot** |
| 3 real depth | probe `ctx 262144` | **not run: engine did not boot** |
| 4 concurrency | probe `concurrent 4` | **not run: engine did not boot** |
| 5 needle at ≥ 90 % depth | 3/3 | **not run: engine did not boot** |
| 6 accuracy | fixed 15-prompt battery, engine/template/effort recorded | **not run: engine did not boot** |
| 7 memory curve | one working day of watchdog samples | **not run: engine did not boot** |

Metrics snapshots: baseline (pre-swap, `reasoning`) `num_preemptions_total=29` cumulative,
running=0. Post-boot `graded`: **none — there was no post-boot.**

## The boot failure (verbatim)

```
NotImplementedError: Qwen3.8-Flash-Next QSA requires a BF16 main KV cache
  (vllm/models/qwen3_8_flash_next/nvidia/qsa.py, Qwen3_8FlashNextQSAAttention.__init__)
```

## What run #1 concluded, and what is corrected

Run #1 (2026-09-28, session `spark-llm-cert-1445`) concluded: *"fp8 KV is architecturally
impossible on this model/build — do not re-attempt."* **That generalisation was false**, and
it was written into four places, where it would have talked the next agent out of the lane
(it is corrected in all four in the same change that adds this note).

What the measurement supports:

* **The guard is in the build we pin, not in the model.** Read-only probe of the image's own
  source ([`image-probe-20260928.md`](image-probe-20260928.md)): `qsa.py:70` declares
  `supported_kv_cache_dtypes = ["auto", "bfloat16"]` and the raise sits at lines **109 and
  188**, while `kv_quant_mode` plumbing is already wired (lines 52, 344) — which is the
  pre-fix state that vllm **PR #55557** (`[Model] fp8_e4m3 main KV cache on the QSA path`)
  describes and completes.
* **#55557 merged 2026-09-16.** Our pin self-reports `vllm-0.1.dev20073+g8e685d198` and its
  tag was **last pushed 2026-08-26** (registry-verified, digest unchanged since we pinned
  it): the pin predates the merge by three weeks, and **no newer tag of this model exists**
  in the registry. It is not in the vLLM v0.30.0 release either (v0.30 carries the
  *indexer*-side fp8 #54890).
* fp8 main KV has since been reproduced on **GB10 / sm_121** by third parties (TP2 across two
  Sparks, MTP active) — so this is an image problem with a measured existence proof.

So: `graded` is **blocked on the pinned image**, which is an engine-pin lane with its own
re-cert, registered as **HD-471**, not a config flip. Do not vendor the AGPL overlay patch
and do not hand-edit a container's site-packages: that is unreproducible from IaC.

## Arithmetic — the number this report originally carried was wrong

Header said `16 GB = 1,031,326 slots = 3.93 × window`. That used a flat **2×** for fp8.
fp8 halves the **main K/V only**; the QSA indexer side-caches (raw-key ring, compressed
keys) and the GDN state stay bf16, so the measured gain on this model is **1.70–1.89×**
(1.77 SM120 spec-off · 1.89 · 1.70 2×Spark GB10 · 1.85 1×Spark GB10; the shape arithmetic
agrees: main KV ≈ 24,576 B of ≈ 29,294 B/token ⇒ 1/(1 − 0.84/2) ≈ 1.72×).

At the conservative 1.70× the same pool is **876,664 slots = 3.34 × window**, not 3.93 ×.
`spark_llm_kv_bytes_per_token.fp8` in `group_vars/spark.yml` now carries 18,251 B/token and
the gate + [`scripts/check_spark_llm_gate.py`](../../../scripts/check_spark_llm_gate.py)
enforce it. Rule for the next run: **never quote a projection where the engine prints the
number** — take `Available KV cache memory` + `GPU KV cache size` from the container log.

## Defects this run found (all committed, in `b1c7572`)

1. **spark-artifacts idempotency** — the tables `creates:` guard checked the transient
   NESTED dir, so every flip re-ran `hf download` (~60 GB). Fixed to the flat installed
   marker `local_dir/META.json`, with the flatten hardened for the empty-nested case.
2. **probe `health`** crashed json-loading the empty-body `/health` this build returns
   (HTTP 200, empty), and `reasoning_text` read the legacy `reasoning_content` field while
   this build emits `reasoning`.
3. **vLLM's usage-stats writer** hit the read-only `/root/.config` mount →
   `VLLM_NO_USAGE_STATS=1` (profile-agnostic hardening).

## Still owed on `graded`

* Nothing on this box until an image exists. When one does: pin it (registry-verified arm64
  digest, `group_vars/all/versions.yml`), re-certify the `reasoning` lane against it (the
  PLE overlay's anchors are image-specific), then run gates 0–9 — **8 and 9 are the ones a
  dtype change must not skip** (MTP acceptance bf16-vs-fp8, and parity against the model's
  own noise floor rather than a needle run):
  [`../../llm-profiles/README.md`](../../llm-profiles/README.md).
