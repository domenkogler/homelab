"""R3 — the step-14 reads, in the base image, read-only.

The evidence README.md §7b's R3 row quotes, in one act: what the day-0 gate of
`patch_low_latency_gemm_sm12x.py` finds in this base's own `qwen4_exp` file, what shape that file's
gate has instead, where the same predicate does live at this base, and whether the
`QWEN38NEXT_LOW_LATENCY_GEMM` dial has a reader here. Nothing is written.

Run inside the base image at the pin digest (see ../raw/r3-step14-base-reads.txt for the command):

    python3 r3_step14_reads.py
"""
import glob

SP = "/usr/local/lib/python3.12/dist-packages/vllm"

# Anchors the day-0 patchers name, counted where they must hold. The first three files are the §7b
# rows for steps 10 and 13; the last two are R3.
CHECKS = [
    ("v1/worker/gpu/model_runner.py", ["class GPUModelRunner", "_step_profile"]),
    ("v1/worker/gpu/spec_decode/rejection_sampler.py",
     ["class RejectionSampler:", "processed_logits = self.sampler.apply_sampling_params(",
      "return processed_logits, sampled, num_sampled"]),
    ("model_executor/layers/fused_moe/experts/marlin_moe.py",
     ["sorted_token_ids, expert_ids, num_tokens_post_padded = moe_align_block_size(",
      "def fused_marlin_moe("]),
    ("model_executor/kernels/linear/cute_dsl/skinny_gemm.py",
     ["warmup_configs: set[SkinnyGemmConfig] = set()", "warmup_configs.update(plan.values())",
      "_cutedsl_available: bool | None = None"]),
    ("models/qwen4_exp/nvidia/low_latency_gemm.py",
     ["def _is_sm103() -> bool:", "if dtype != torch.bfloat16 or not _is_sm103():",
      "_llg_sm12x = _llg_sm12x_enabled()", "enable_qwen4_exp_low_latency_gemm",
      "QWEN38NEXT_LOW_LATENCY_GEMM"]),
]

# The lines R3's two dispositions quote: the base's gate, and the plan table that replaced the
# capability predicate.
GATE_MARKS = ("GEMM_PLANS", "get_device_capability", "def _runtime_ok", "torch.bfloat16",
              "DGX Spark", "def enable_qwen4_exp_low_latency_gemm", "if dtype != torch.bfloat16",
              "plan = plans.get(")

for rel, anchors in CHECKS:
    try:
        with open(f"{SP}/{rel}", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        print(f"--- {rel}  MISSING")
        continue
    print(f"--- {rel}")
    for anchor in anchors:
        print(f"  {text.count(anchor):>3}  {anchor[:70]}")

print("\n--- models/qwen4_exp/nvidia/low_latency_gemm.py, the gate and its plan table")
with open(f"{SP}/models/qwen4_exp/nvidia/low_latency_gemm.py", encoding="utf-8",
          errors="replace") as fh:
    for num, line in enumerate(fh.read().splitlines(), 1):
        if any(mark in line for mark in GATE_MARKS):
            print(f"  {num:5}  {line.rstrip()[:110]}")

print("\n--- where the day-0 predicate shape lives at this base (sibling model packages)")
hits = 0
for path in glob.glob(f"{SP}/models/*/nvidia/*low_latency_gemm*.py"):
    with open(path, encoding="utf-8", errors="replace") as fh:
        for num, line in enumerate(fh.read().splitlines(), 1):
            if "_is_sm103" in line or "_llg_sm12x" in line:
                hits += 1
                print(f"  {path.replace(SP + '/', '')}:{num}: {line.strip()[:88]}")
print(f"  {hits} lines across the model packages; the qwen4_exp file contributes none of them")

print("\n--- the dial, tree-wide")
readers = []
for path in glob.glob(f"{SP}/**/*.py", recursive=True):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            if "QWEN38NEXT_LOW_LATENCY_GEMM" in fh.read():
                readers.append(path)
    except OSError:
        pass
print(f"  files reading QWEN38NEXT_LOW_LATENCY_GEMM: {len(readers)} {readers[:5]}")
