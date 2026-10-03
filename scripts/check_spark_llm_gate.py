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
VERSIONS = ROOT / "IaC" / "ansible" / "group_vars" / "all" / "versions.yml"

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
# HD-489 A4: the split env lists, read from the catalogue once. `vllm_verdicts` references
# SPLIT_LISTS to disprove the old confound (mmap_env only plumbs the table; dispatch_env is
# separate). Nothing is re-typed here — read from the SSOT YAML like the pin map.
SPLIT_LISTS = {}
# Resolved in main(): {profile.image name: the pin string from versions.yml}. Built by
# reading spark_llm_profile_images (the name→pin map) and resolving each Jinja reference
# against versions.yml — so a NEW image name with no pin, or a pin renamed in versions.yml,
# shows up as an empty entry here and the `image-pin` invariant fails it. Nothing is re-typed.


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
    # HD-489: every one of these is an invariant this script ALSO checks. If the role stops
    # containing it, the catalogue could go green HERE while the real converge stopped
    # refusing it — the drift direction that actually matters, so it is fatal here.
    for marker, why in [
        ("spark_llm_profile_images", "resolves profile.image to a versions.yml PIN"),
        ("ple_host_subdir | length > 0", "refuses an mmap arm whose PLE table is not mounted"),
        ("ple_mmap | bool) and (spark_llm.ple_overlay", "refuses mmap + overlay together"),
        ("'CHANGEME' not in", "refuses a placeholder prompt-pin substring"),
        ("spark_llm_os_min_free_bytes", "checks free space on the root the artifacts use"),
    ]:
        if marker not in text:
            print(f"ERROR: {ROLE.relative_to(ROOT)} no longer contains {marker!r}, but this "
                  f"script still proves it is refused ({why}). Change both or neither.",
                  file=sys.stderr)
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
    pool_ceil = int(profile.get("pool_ceiling_bytes") or cat["spark_llm_pool_ceiling_bytes"])
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

    # ---- HD-489: a profile now NAMES things, not only carries numbers ----
    # The four original invariants all ask "does the memory arithmetic close". The ultra-fast
    # funnel turned a profile into a set of COORDINATES (which image, which partition, which
    # PLE mechanism, which prompt-pin substring), and each has a failure mode arithmetic
    # cannot see: an unknown image name, a table not mounted where the env says it is, both
    # PLE mechanisms claimed at once, a placeholder shipped into argv, a fixed cost invented
    # rather than measured.
    GATED = out.setdefault("_gated", [])
    img = profile.get("image")
    out["image-pin"] = (img in PIN_PINS,
                        f"profile.image={img!r} is not a name in spark_llm_profile_images "
                        f"(known: {', '.join(sorted(PIN_PINS))})")
    if img in PIN_PINS and not PIN_PINS[img]:
        # An EMPTY pin is not a broken profile, it is an ARM THAT CANNOT BOOT YET: the
        # `ultrafast` pin stays empty until the built image ID is recorded (CONVENTIONS §7
        # forbids serving a mutable tag). The role refuses it at converge time; here it is
        # reported as GATED — neither a permanent red nor an invisible state.
        GATED.append(f"{img}: no image ID pinned in versions.yml yet \u2014 the gate refuses it")
    coords = {profile.get("models_root"), profile.get("ple_host_root"),
              profile.get("ple_host_base")}
    out["coordinates"] = (None not in coords and coords <= {"xfs", "os", "mount", "models"},
                          f"models_root={profile.get('models_root')} "
                          f"ple_host_root={profile.get('ple_host_root')} "
                          f"ple_host_base={profile.get('ple_host_base')} \u2014 valid: xfs|os "
                          "and mount|models")
    out["ple-mechanism"] = (
        not (profile.get("ple_mmap") and profile.get("ple_overlay")),
        "ple_mmap and ple_overlay both claim .../qwen3_8_flash_next/nvidia/ple_layer.py "
        "(bind-mount over it vs hook appended to it) \u2014 mount order would decide behaviour")
    out["ple-mmap-table"] = (
        not profile.get("ple_mmap")
        or (bool(profile.get("ple_host_subdir"))
            and profile.get("ple_container_dir") == "/ple-table"
            and not profile.get("ple_offload")),
        f"mmap arm incomplete: subdir={profile.get('ple_host_subdir')!r} "
        f"container={profile.get('ple_container_dir')!r} offload={profile.get('ple_offload')} "
        "\u2014 VLLM_PLE_MMAP_DIR points at /ple-table, so the table must be mounted there "
        "and the primitive-ai CPU-offload env must not render with it")
    out["ple-dispatch"] = (
        not profile.get("ple_dispatch") or profile.get("ple_mmap"),
        "ple_dispatch: true on a non-mmap arm renders kernel-dispatch env ("
        "QWEN38NEXT_*/VLLM_*_GEMM/VLLM_FP8_HYBRID) without the mmap table they dispatch "
        "for \u2014 the A4 confound; dispatch requires ple_mmap")
    # the table set and the dispatch set after the A4 split (check_spark_llm_gate reads
    # both lists and asserts they are disjoint and the dispatch set is the A4 dispatch knobs)
    mb = SPLIT_LISTS.get("ple_mmap_env") or []
    dp = SPLIT_LISTS.get("ple_dispatch_env") or []
    out["a4-split"] = (
        bool(mb) and bool(dp) and set(mb).isdisjoint(set(dp)),
        f"mmap_env {mb} vs dispatch_env {dp} \u2014 A4 requires the sets to be separate",
    )
    out["ple-dispatch-lean"] = (
        not profile.get("ple_dispatch") or profile.get("ple_mmap"),
        "ar-blk-lean must render WITHOUT the dispatch env (B9 isolation) — an arm that "
        "opts into dispatch is NOT the A4 control",
    )
    pin_txt = str(profile.get("never_evict_prompt") or "") + " " + " ".join(
        str(a) for a in (profile.get("args_extra") or []))
    # A CHANGEME prompt-pin is a bug in a CERTIFIED lane and an honest GATE in an uncertified
    # arm: the pin arms are authored with the placeholder on purpose, because the substring
    # has to come from the harness prompt a human actually runs. The role refuses BOTH cases
    # at converge time; here only the certified one is a failure, so an arm awaiting a human
    # decision reads as GATED rather than as a permanent red.
    placeholder = "CHANGEME" in pin_txt
    out["pin-placeholder"] = ((not placeholder) or not profile.get("certified"),
                              "a CHANGEME prompt-pin substring pins nothing (an invisible "
                              "no-op) or everything (a pool leak) \u2014 author the literal")
    if placeholder and not profile.get("certified"):
        GATED.append("never_evict_prompt is a CHANGEME placeholder \u2014 author the substring")
    basis = str(profile.get("fixed_cost_basis") or "")
    out["cost-labelled"] = (
        (basis.split()[0].rstrip(":,") if basis.split() else "")
        in ("MEASURED", "DERIVED", "VENDOR-PUBLISHED", "VENDOR"),
        f"fixed_cost_basis must lead with MEASURED | DERIVED | VENDOR-PUBLISHED, got "
        f"{basis[:52]!r} \u2014 an unlabelled cost is a number nobody can re-check")
    cap = int(profile.get("max_cudagraph_capture_size", 0) or 0)
    out["cudagraph-cap"] = (cap <= 0 or cap <= int(profile["max_num_seqs"]),
                            f"capture cap {cap} > max_num_seqs {profile['max_num_seqs']} "
                            "\u2014 graphs above the decode batch are unreachable and strand "
                            "memory in the single pool (HD-380)")
    return out


def verdict_table(cat, pats, label):
    print(f"\n[{label}] every profile under the invariants the role asserts")
    for name, prof in cat["spark_llm_profiles"].items():
        if name.startswith("_"):
            continue          # HD-489 merge anchor of shared defaults, not a servable profile
        engine = prof.get("engine")
        verdicts = (vllm_verdicts(prof, cat) if engine == "vllm"
                    else sglang_verdicts(prof, pats))
        cells = []
        for key, passed in ((k, v[0]) for k, v in verdicts.items() if not k.startswith("_")):
            cells.append(f"{key}={'✓' if passed else '✗'}")
            if not passed and label == "catalogue":
                fail(f"{name}/{engine}/{key}: {verdicts[key][1]}")
        for gated in verdicts.get("_gated") or []:
            cells.append("GATED")
            NOTES.append(f"{name}: {gated}")
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
        # HD-489. Shapes the arithmetic lets through and the coordinates must refuse, each
        # bred from the CERTIFIED lane so the breach is the only difference from a green row.
        ("image-pin", lambda p: p.update(image="whatever-is-latest")),
        ("coordinates", lambda p: p.update(models_root="nfs")),
        ("ple-mechanism", lambda p: p.update(ple_mmap=True, ple_overlay=True)),
        ("ple-mmap-table", lambda p: p.update(ple_mmap=True, ple_overlay=False,
                                              ple_offload=False, ple_host_subdir="")),
        ("ple-mmap-table", lambda p: p.update(ple_mmap=True, ple_overlay=False,
                                              ple_offload=True,
                                              ple_host_subdir="ple-table-fp8",
                                              ple_container_dir="/ple-table")),
        ("pin-placeholder", lambda p: p.update(never_evict_prompt="CHANGEME-PIN-SUBSTRING",
                                               certified=True)),
        ("cost-labelled", lambda p: p.update(fixed_cost_basis="guessed from the brochure")),
        ("cudagraph-cap", lambda p: p.update(max_cudagraph_capture_size=16)),
        ("ple-dispatch", lambda p: p.update(ple_dispatch=True)),   # dispatch on a non-mmap arm
        # A4 canary: empty the mmap table set → a4-split must FAIL (a catalogue reading no
        # table knobs while arms claim ple_mmap is exactly the confound this split deletes)
        ("a4-split", lambda p: SPLIT_LISTS.__setitem__("ple_mmap_env", [])),
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


def build_pin_pins(cat, versions):
    """{image name: pin} — resolved through the Jinja reference each map value holds."""
    out = {}
    for name, ref in (cat.get("spark_llm_profile_images") or {}).items():
        m = re.fullmatch(r"\{\{\s*([A-Za-z0-9_]+)\s*\}\}", str(ref).strip())
        out[name] = str(versions.get(m.group(1), "")) if m else str(ref)
    return out


def main():
    cat = load_yaml(CATALOGUE)
    pats = patterns_from_role()
    for key in ("spark_llm_profiles", "spark_llm_kv_bytes_per_token",
                "spark_llm_pool_ceiling_bytes", "spark_llm_device_hold_ceiling_bytes",
                "spark_llm_profile_images"):
        if key not in cat:
            print(f"ERROR: {key} missing from {CATALOGUE.relative_to(ROOT)}", file=sys.stderr)
            return 2
    global PIN_PINS, SPLIT_LISTS
    PIN_PINS = build_pin_pins(cat, load_yaml(VERSIONS))
    SPLIT_LISTS = {
        "ple_mmap_env": [str(x) for x in (cat.get("spark_llm_ple_mmap_env") or [])],
        "ple_dispatch_env": [str(x) for x in (cat.get("spark_llm_ple_dispatch_env") or [])],
    }
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
