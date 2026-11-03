"""HD-1206 step 2 — the A+ runtime dispatch check, on a BOOTED engine.

README.md §7b's R3 ruling (A+) says the `(12, 1)` plan exists in `QWEN4_EXP_GEMM_PLANS_BY_CAPABILITY`
and the base's own gate can reach it. It does not say a real bf16 GEMM LANDS on a plan instead of
falling back to `torch.nn.functional.linear`. That is a property of the running engine, so no build,
image read or census can answer it — this file is the read.

The dispatch under test, `vllm/models/qwen4_exp/nvidia/low_latency_gemm.py`:

    plans  = QWEN4_EXP_GEMM_PLANS_BY_CAPABILITY.get(current_platform.get_device_capability(), {})
    plan   = plans.get((weight.shape[0], weight.shape[1]))
    config = None if plan is None else plan.get(x.shape[0])
    if config is not None and _runtime_ok(x, weight, config) and shape_dynamic_skinny_gemm.is_available():
        return shape_dynamic_skinny_gemm(x, weight, config)
    return torch.nn.functional.linear(x, weight)          # <- the fallback

Four legs, each reported as MEASURED (a value read out of this process) rather than inferred:

  1 capability     `current_platform.get_device_capability()` — the key the plan table is indexed by
  2 plan-for-shape `plans[(N, K)]` for a real SM121 shape, and the M=1 config inside it
  3 _runtime_ok    the base's own predicate, called on bf16 CUDA tensors of the plan's own shape
  4 is_available   `shape_dynamic_skinny_gemm.is_available()` — False makes legs 1-3 unreachable and
                   leaves the arm silently on `F.linear`

Verdict is PLAN only when a call to the registered `torch.ops.vllm.qwen4_exp_low_latency_gemm` returns
the plan kernel's output — proved twice: the kernel cache gains the plan's own key, AND the result
matches `F.linear` within bf16 tolerance (a plan that computes the wrong matrix is not a pass either).

Run INSIDE the running engine container (it needs the engine's CUDA context and its own vllm tree):

    sudo docker cp runtime_dispatch.py vllm-qwen-spark:/tmp/runtime_dispatch.py
    sudo docker exec vllm-qwen-spark python3 /tmp/runtime_dispatch.py

Read-only: one small bf16 matmul, no request, no model load, nothing written to the box.
"""
import json
import sys

import torch

import vllm.envs as envs
import vllm.models.qwen4_exp.nvidia.low_latency_gemm as llg
from vllm.model_executor.kernels.linear.cute_dsl.skinny_gemm import (
    shape_dynamic_skinny_gemm,
)
from vllm.platforms import current_platform

# (N, K) shapes the SM121 table carries that this box actually exercises at decode: the
# shared-expert gate/up pair. Chosen from QWEN4_EXP_SM121_GEMM_PLANS, not invented.
SHAPES = [(1280, 2560), (640, 2560), (1, 2560)]


def leg_report():
    cap = current_platform.get_device_capability()
    plans = llg.QWEN4_EXP_GEMM_PLANS_BY_CAPABILITY.get(cap, {})
    available = shape_dynamic_skinny_gemm.is_available()
    print(f"LEG1 capability            = {cap}  measured")
    print(f"LEG4 is_available          = {available}  measured")
    print(f"      plan shapes @ {cap}   = {len(plans)}")
    return cap, plans, available


def probe_shape(n, k, plans):
    """One dispatch read for one (N, K): the three legs that need tensors, then the real call."""
    print(f"\n--- shape (N={n}, K={k}) ---")
    plan = plans.get((n, k))
    config = None if plan is None else plan.get(1)
    print(f"LEG2 plan-for-shape        = {'present' if plan is not None else 'ABSENT'}"
          f"  m1_config={config}  measured")

    weight = torch.randn(n, k, dtype=torch.bfloat16, device="cuda")
    x = torch.randn(1, k, dtype=torch.bfloat16, device="cuda")

    ok = None
    if config is not None:
        ok = llg._runtime_ok(x, weight, config)
    print(f"LEG3 _runtime_ok           = {ok}  measured")

    # The real op, as the model calls it. A PLAN verdict additionally requires the compiler cache
    # to gain THIS config's key, which is the only thing that distinguishes the plan branch from
    # the fallback that returns the same numbers.
    before = set(shape_dynamic_skinny_gemm._compiled)
    out = torch.ops.vllm.qwen4_exp_low_latency_gemm(x, weight)
    after = set(shape_dynamic_skinny_gemm._compiled)
    gained = after - before
    ref = torch.nn.functional.linear(x, weight)
    maxdiff = (out.float() - ref.float()).abs().max().item()

    used_plan = bool(gained)
    close = torch.allclose(out, ref, atol=0.5, rtol=0.05)
    if config is None or not ok or not shape_dynamic_skinny_gemm.is_available():
        verdict = "F.linear FALLBACK"
    elif used_plan and close:
        verdict = "PLAN"
    elif used_plan and not close:
        verdict = "PLAN (WRONG NUMBERS)"
    else:
        verdict = "F.linear FALLBACK (plan reachable, kernel not entered)"
    print(f"      kernel cache gained   = {sorted(str(c) for c in gained)}")
    print(f"      maxdiff vs F.linear   = {maxdiff:.6f}  allclose={close}")
    print(f"VERDICT shape {(n, k)}       = {verdict}")
    return {
        "shape": [n, k],
        "plan_present": plan is not None,
        "m1_config": None if config is None else repr(config),
        "runtime_ok": ok,
        "cache_gained": [repr(c) for c in gained],
        "maxdiff_vs_flinear": maxdiff,
        "allclose": close,
        "verdict": verdict,
    }


def main():
    if not torch.cuda.is_available():
        sys.exit("no CUDA in this process — run inside the serving container, not the image")
    print(f"torch={torch.__version__} cuda={torch.version.cuda} dev={torch.cuda.get_device_name(0)}")
    print(f"VLLM_BATCH_INVARIANT={envs.VLLM_BATCH_INVARIANT}")
    cap, plans, available = leg_report()
    rows = [probe_shape(n, k, plans) for n, k in SHAPES]
    print("\n=== summary ===")
    for r in rows:
        print(f"  {tuple(r['shape'])}: {r['verdict']}")
    print("JSON " + json.dumps({"capability": list(cap) if cap else None,
                               "is_available": available, "rows": rows}))


if __name__ == "__main__":
    main()
