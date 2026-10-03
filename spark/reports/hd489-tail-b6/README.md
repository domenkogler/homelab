# HD-489 tail — B6: fp8 KV on the built image

Measured 2026-10-03 via `scripts/spark-fp8-image-probe.py` leg B against the **built
ultrafast image** (`sha256:4900c13e…`, the one `versions.yml:311` pins), on spark.

## Verdict

**BLOCKED-ON-IMAGE — PASS of the probe (the pin is the finding).** fp8 main KV is **not
reachable even on the patched lineage**: the image's own `qsa.py:70` still declares
`supported_kv_cache_dtypes = ["auto", "bfloat16"]` and raises `Qwen3.8-Flash-Next QSA
requires a BF16 main KV cache` at qsa.py:109/:188. The HD-489 patch stack did **not**
add the fp8 KV read path.

This means the brief's "3.34× ctx for free" (fp8 KV = 876,664 slots) is **not
available on this image either**: the fp8 KV merge is vllm#55557 (upstream, 2026-09-16),
absent from both the base tag and the built lineage. **`graded` stays on HD-473** (engine
pin), and every ctx answer below stays at 1.97×.

## Why this is the right answer

- The probe ran the image's **own source** (`docker run --rm --entrypoint sh <image>
  -c 'grep …qsa.py'`), no GPU, no writes, no pull — read-only, ~40 s.
- Image arch confirmed `arm64/linux` (what spark actually executes); version
  `0.1.dev20073+g8e685d198` (same day-0 build lineage as the base).
- So B6 = PASS (the check ran and produced a number/verdict), and the verdict is
  **BLOCKED-ON-IMAGE**, not a config flip.

## Evidence

- Probe output (Verdict + DECLARED dtypes + HIT/BF16 lines) is the record.
- Command: `python3 scripts/spark-fp8-image-probe.py --skip-registry --image
  sha256:4900c13… --ssh-host spark`

## Consequence

- Do **not** attempt fp8 KV via container edits or overlays (Do-not-do).
- `graded` + the 3.34× pool remain HD-473 (pin) work; B7's pool decision stays at the
  bf16 16.27e9 B ceiling (2.00×), which still needs the owner call.