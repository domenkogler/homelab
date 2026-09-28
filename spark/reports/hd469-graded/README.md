# HD-469 graded profile — certification run (2026-09-28)

Profile: `graded` — AWQ W4A16 + PLE INT4 + MTP3, **fp8 KV** (`--kv-cache-dtype fp8`,
16,000,000,000 B pool = 1,031,326 slots = 3.93 × the 262,144 window).
Engine: digest-pinned vLLM fork (same as `reasoning`). This is the **first live run of
fp8 KV on this hybrid-GDN + MTP build** — the exact "unvalidated" path
(docs/hardware-spark.md §Unified-memory budget:302-303) this cert exists to measure.

Run book (commands, in order):
1. Gate (read-only, pre-boot): `ansible-playbook -i inventory.ini playbooks/spark.yml
   --limit spark --tags spark-llm-profile --check --diff` → `certified: false` +
   override accepted, KV math closes (fp8 16 GB = 1,031,326 slots < 16 GiB ceiling).
2. Artifact-staging defect found + fixed in the worktree (spark-artifacts idempotency:
   the tables `creates:` guard checked the transient NESTED dir, so every flip re-ran
   `hf download` (~60 GB). Fixed to the flat installed marker `local_dir/META.json`;
   flatten hardened for the empty-nested case. https://homelab.kogler.si/... (link TBD)
3. Converge detached (engine swap): `nohup bash scripts/ansible-run.sh playbooks/spark.yml
   --limit spark --no-pull >/tmp/hd469-graded.log 2>&1 &` → cold boot ~20 min.
4. Gates 1–7 per spark/llm-profiles/README.md.

## Gate results (filled as measured)

| Gate | Measure | Result |
|------|---------|--------|
| 0 | render parity + probe `profile graded` | probes print fp8 1,031,326 slots; `validate-docker-services.py --only spark-ai` PASS |
| 1 | boot | `/health` 200 + `RestartCount=0` after 30 min |
| 2 | non-interference | probe `health` + `reasoning` while idle; host MemAvailable ≥ floor (18.12 GiB certified) |
| 3 | real depth | **VERDICT: fp8 KV NOT CERTIFIABLE on this model.** The engine
   fails to boot at EngineCore init with
   `NotImplementedError: Qwen3.8-Flash-Next QSA requires a BF16 main KV cache`
   (vllm/models/qwen3_8_flash_next/nvidia/qsa.py:187). The Qwen3.8-Flash-Next
   hybrid's QSA (Sparse Attention) layer HARD-REQUIRES a BF16 main KV cache; fp8 KV
   is incompatible with the model's own attention implementation. This is a
   measured architectural fact, not a config defect — the fp8 KB path is
   impossible on this model / build. `graded` stays UNCERTIFIED with this
   measurement recorded (brief §3 fallback: "the profile stays uncertified with
   the measurement recorded").
| 4 | concurrency | probe `concurrent 4` → all 200 |
| 5 | needle | needle at ≥ 90 % depth, 3/3 |
| 6 | accuracy | fixed 15-prompt battery, engine/effort/template recorded |
| 7 | memory curve | 1 day of oom-watchdog samples, no growth > 2 GiB/h under traffic |

## Metrics snapshots (from `/metrics`)

- Baseline (pre-swap, `reasoning`): `num_preemptions_total=29` cumulative, running=0.
- Post-boot `graded`: TBD.

## Notes / defects found

1. **spark-artifacts idempotency defect (fixed, uncommitted):** the tables download
   `creates:` guard checked the transient nested path → re-downloaded ~60 GB on every
   flip. Flat-marker fix + flatten hardening (see the role change in this branch).
2. **spark-llm-probe.py defects (fixed, uncommitted):** (a) `health` crashed
   json-loading the empty-body `/health` that this vLLM build returns (HTTP 200, body
   empty); (b) `reasoning_text` read the legacy `reasoning_content` field while this
   build emits `reasoning`. Fixed; `all --profile reasoning` now passes 6/6 against the
   live engine.
7. **fp8 KV hard-incompatibility with this model (the decisive verdict):** the
   `graded` profile cannot boot. After the usage-stats blocker was fixed, the
   worker still died at EngineCore init:
   ```
   NotImplementedError: Qwen3.8-Flash-Next QSA requires a BF16 main KV cache
   (vllm/models/qwen3_8_flash_next/nvidia/qsa.py:187, Qwen3_8FlashNextQSAAttention.__init__)
   ```
   Qwen3.8-Flash-Next is a hybrid GDN model whose QSA (sparse attention) layer
   hard-requires a BF16 main KV cache. fp8 KV is therefore architecturally
   impossible on this model/build — the exact "unvalidated on this hybrid+MTP
   build" risk the profile's `uncertified_reason` and docs/hardware-spark.md
   §Unified-memory budget flagged. Rolled back to `reasoning` (certified).