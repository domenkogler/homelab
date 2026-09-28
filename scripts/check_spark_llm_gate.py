#!/usr/bin/env python3
"""
check_spark_llm_gate.py — prove the spark LLM profile gate OFFLINE (HD-469).

WHY THIS EXISTS. `roles/spark-llm-profile` is the thing standing between a one-var flip
and (a) a kernel global OOM on a box where Docker reports `OOMKilled: false`, (b) a
served window smaller than the client contract promises, (c) a 47.7 GiB PLE table pinned
into the same 121.62 GiB pool as the weights. Its real tests need the box — and the box
is one ~20-minute engine boot away from being the thing you broke. CONVENTIONS §6:
"a test that cannot fail is not evidence". So the gate carries its own canary.

What it evaluates is NOT a re-typed copy of the rules: the SGLang flag REGEXES are read
out of the role's own task file, the numeric constants out of group_vars/spark.yml, and
the same `re` engine Ansible's `regex_findall` uses does the matching. A pattern edited
in the role is automatically the pattern under test here.

Two halves, both required:
  * catalogue matrix — every authored profile must satisfy every invariant it is under.
  * canary — profiles bred to breach each invariant must be REJECTED. If a check goes
    green on its canary, this script fails: a gate that cannot fail is not a gate.

Needs python3 + PyYAML only (same floor as check_self_converge_guard.py): no Ansible,
no network, no vault, no box. Exit 0 = coherent; 1 = breach or canary escape; 2 = could
not evaluate (which is never a pass).
"""
import copy
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    print("ERROR: PyYAML missing (same floor as check_self_converge_guard.py)", file=sys.stderr)
    sys.exit(2)

ROOT = Path(__file__).resolve().parent.parent
CATALOGUE = ROOT / "IaC" / "ansible" / "group_vars" / "spark.yml"
ROLE = ROOT / "IaC" / "ansible" / "roles" / "spark-llm-profile" / "tasks" / "main.yml"

# The SGLang invariants, keyed by the flag each one reads. The role's pattern is matched
# to the key by the flag LITERAL, so renaming a flag here is a loud failure, not a silent
# skip (see sglang_verdicts: a missing pattern returns all-FAIL).
SGLANG_CHECKS = {
    "mem-fraction": ("--mem-fraction-static", "le0.80"),
    "max-total-tokens": ("--max-total-tokens", "ge_max_model_len"),
    "ple-offload-backend": ("--ple-offload-backend", "is_file_when_offload"),
}
FAILS = []
NOTES = []


def fail(msg):
    FAILS.append(msg)
    print(f"  FAIL  {msg}")


def ok(msg):
    print(f"  OK    {msg}")


def load_yaml(path):
    if not path.is_file():
        print(f"ERROR: {path} not found — this is not a pass", file=sys.stderr)
        sys.exit(2)
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def patterns_from_role():
    """Pull the regex_findall() patterns the role itself uses, plus its sglang assert."""
    if not ROLE.is_file():
        print(f"ERROR: {ROLE} not found", file=sys.stderr)
        sys.exit(2)
    text = ROLE.read_text(encoding="utf-8")
    pats = re.findall(r"regex_findall\('([^']+)'", text)
    if not pats:
        print(f"ERROR: no regex_findall patterns in {ROLE.relative_to(ROOT)} — did the "
              "sglang invariants move? Silence is not a pass.", file=sys.stderr)
        sys.exit(2)
    if "spark_llm.engine == 'sglang'" not in text:
        print("ERROR: the role no longer gates anything on engine == 'sglang'", file=sys.stderr)
        sys.exit(2)
    return pats


def sglang_verdicts(profile, pats):
    """{name: (ok, detail)} for one sglang profile, using the ROLE's own patterns."""
    args = [str(a) for a in (profile.get("args_extra") or [])]
    joined = " ".join(args)
    window = int(profile["max_model_len"])
    out = {}
    for name, (flag, rule) in SGLANG_CHECKS.items():
        mine = [p for p in pats if flag in p]
        if not mine:
            return {n: (False, f"the role has no regex for {flag}") for n in SGLANG_CHECKS}
        hits = re.findall(mine[0], joined)
        val = hits[0] if hits else None
        if rule == "le0.80":
            v = float(val) if val is not None else 1.0     # unset = sglang's own default, which is worse
            out[name] = (v <= 0.80, f"{flag}={val} must be ≤ 0.80 (0.85 = the earlyoom threshold)")
        elif rule == "ge_max_model_len":
            v = int(val) if val is not None else window
            out[name] = (v >= window, f"{flag}={val} must be ≥ max_model_len={window}")
        else:
            offload = "--ple-offload-embedding" in joined
            v = val if val is not None else "pinned"
            out[name] = ((not offload) or v == "file",
                         f"{flag}={v} while --ple-offload-embedding is present")
    return out


def vllm_verdicts(profile, cat):
    """The numeric invariants the role asserts for a vLLM profile."""
    per_tok = cat["spark_llm_kv_bytes_per_token"]
    pool_ceil = int(cat["spark_llm_pool_ceiling_bytes"])
    hold_ceil = int(cat["spark_llm_device_hold_ceiling_bytes"])
    dtype = profile["kv_cache_dtype"]
    pool = int(profile["kv_cache_memory"])
    window = int(profile["max_model_len"])
    out = {}
    out["dtype-known"] = (dtype in per_tok, f"kv_cache_dtype={dtype} is not in the constants map")
    slots = 0
    if dtype in per_tok:
        slots = pool // int(per_tok[dtype])
        out["pool-holds-window"] = (slots >= window,
                                    f"{pool} B / {per_tok[dtype]} B/token = {slots} slots < window {window}")
    out["pool-ceiling"] = (pool <= pool_ceil, f"pool {pool} B > the certified ceiling {pool_ceil} B")
    fc = profile.get("fixed_cost_bytes")
    if fc is None:
        out["host-floor"] = (False, "fixed_cost_bytes undeclared (fail-loud: no default)")
    else:
        hold = int(fc) + pool
        out["host-floor"] = (hold <= hold_ceil,
                             f"fixed {fc} + pool {pool} = {hold} B > the host-floor ceiling {hold_ceil} B")
    out["_projection"] = f"{slots} slots = {slots / window:.2f} × the {window} window"
    return out


def verdict_table(cat, pats, label):
    print(f"\n[{label}] every profile under the invariants the role asserts")
    for name, prof in cat["spark_llm_profiles"].items():
        engine = prof.get("engine")
        verdicts = (vllm_verdicts(prof, cat) if engine == "vllm"
                    else sglang_verdicts(prof, pats))
        cells = []
        for key, passed in ((k, v[0]) for k, v in verdicts.items() if not k.startswith("_")):
            cells.append(f"{key}={'✓' if passed else '✗'}")
            if not passed and label == "catalogue":
                fail(f"{name}/{engine}/{key}: {verdicts[key][1]}")
        extra = verdicts.get("_projection", "")
        print(f"  ·  {name:12s} {engine:6s} " + " ".join(cells) + (f"   ({extra})" if extra else ""))
        if extra and label == "catalogue":
            NOTES.append(f"{name}: {extra}")


def canary(cat, pats):
    """Breed one profile per invariant and require a REJECTION of each."""
    print("\n[canary] each invariant must REJECT a profile bred to breach it")
    vllm_breaches = [
        # The real historical shape: NVFP4's heavier weights + the OLD 16.5 GB pool.
        ("host-floor", lambda p: p.update(fixed_cost_bytes="92100000000",
                                          kv_cache_memory="16500000000")),
        ("host-floor-declared", lambda p: p.pop("fixed_cost_bytes", None)),
        ("pool-ceiling", lambda p: p.update(kv_cache_memory="18000000000")),
        ("pool-holds-window", lambda p: p.update(kv_cache_memory="100000000")),
        ("dtype-known", lambda p: p.update(kv_cache_dtype="nvfp4-kv")),
    ]
    for expect, mutate in vllm_breaches:
        prof = copy.deepcopy(cat["spark_llm_profiles"]["reasoning"])
        mutate(prof)
        verdicts = vllm_verdicts(prof, cat)
        key = "host-floor" if expect.startswith("host-floor") else expect
        rejected = key in verdicts and not verdicts[key][0]
        if rejected:
            ok(f"canary {expect}: REJECTED — {verdicts[key][1]}")
        else:
            fail(f"canary {expect}: NOT rejected — the gate would converge it. "
                 f"{ {k: v[0] for k, v in verdicts.items() if not k.startswith('_')} }")
    sg = cat["spark_llm_profiles"].get("fast-sglang")
    if sg is None:
        fail("canary: no fast-sglang profile to mutate — the sglang invariants are untested")
        return
    sg_breaches = [
        ("mem-fraction", lambda p: p.__setitem__(
            "args_extra", ["0.85" if a == "0.80" else a for a in p["args_extra"]])),
        ("max-total-tokens", lambda p: p.__setitem__(
            "args_extra", ["65536" if a == str(p["max_model_len"]) else a for a in p["args_extra"]])),
        ("ple-offload-backend", lambda p: p.__setitem__(
            "args_extra", [a for a in p["args_extra"] if a not in ("--ple-offload-backend", "file")])),
    ]
    for expect, mutate in sg_breaches:
        prof = copy.deepcopy(sg)
        mutate(prof)
        verdicts = sglang_verdicts(prof, pats)
        if not verdicts[expect][0]:
            ok(f"canary sglang/{expect}: REJECTED — {verdicts[expect][1]}")
        else:
            fail(f"canary sglang/{expect}: NOT rejected — args tail "
                 f"{prof['args_extra'][-6:]}")


def main():
    cat = load_yaml(CATALOGUE)
    pats = patterns_from_role()
    for key in ("spark_llm_profiles", "spark_llm_kv_bytes_per_token",
                "spark_llm_pool_ceiling_bytes", "spark_llm_device_hold_ceiling_bytes"):
        if key not in cat:
            print(f"ERROR: {key} missing from {CATALOGUE.relative_to(ROOT)}", file=sys.stderr)
            return 2
    print(f"role patterns under test: {len(set(pats))}")
    verdict_table(cat, pats, "catalogue")
    canary(cat, pats)
    if NOTES:
        print("\nprojections (planning numbers only — the engine's own log line wins):")
        for n in NOTES:
            print(f"  ·  {n}")
    print(f"\n{len(FAILS)} failure(s)")
    if FAILS:
        return 1
    print("OK: the spark LLM profile gate is coherent and provably fatal to the shapes it refuses")
    return 0


if __name__ == "__main__":
    sys.exit(main())
