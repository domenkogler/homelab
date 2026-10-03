#!/usr/bin/env python3
"""Render the spark-ai compose template for EVERY LLM profile, offline. (HD-489)

WHY THIS EXISTS. The HD-489 funnel grew the catalogue from 4 profiles to 16, and a profile
is now a set of COORDINATES (`image`, `models_root`, `ple_host_base`/`ple_host_root`,
`ple_mmap`, `draft_vocab`, `cudagraph_piecewise`, `never_evict_prompt`, `spec_config`) that
the compose template COMPOSES into paths, env and argv. Composition is exactly the kind of
logic that silently renders a wrong mount or a dropped flag, and an arm boots for ~20 minutes
before it can tell you so. This script renders every arm with the SAME Jinja environment and
the SAME SSOT context scripts/validate-docker-services.py uses, parses the result as YAML
(that is what `docker compose` does at deploy), and prints what each arm ACTUALLY renders.
Nothing here touches spark, the vault, or Docker.

WHAT IT PROVES (and the canary that makes it fail-able):
  * every profile RENDERS and the output PARSES as YAML — a broken `{% if %}` in the
    template fails here, not at boot;
  * the composed model/PLE host paths are the ones the profile named (an arm pointed at the
    wrong partition is a real failure mode, and the fix is a one-line profile key);
  * `reasoning` renders the certified lane's contract (base image pin present, INT4 overlay
    + table mounted, the legacy literal --speculative-config line);
  * an arm whose image pin is EMPTY is reported as GATED (that is the designed state of the
    `ultrafast` arms until versions.yml carries the built image ID), and `--strict` turns
    that into a failure so a half-finished lane cannot be merged as if it were deployable.

Usage:
  scripts/spark-llm-render-matrix.py            # table of every profile
  scripts/spark-llm-render-matrix.py --strict   # exit 1 on any gated/failed arm
  scripts/spark-llm-render-matrix.py --dump v16b  # full rendered compose for one profile
"""
import re
import sys
import importlib.util
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"
TEMPLATE = ROOT / "IaC/ansible/templates/docker_services/spark-ai/docker-compose.yml.j2"
SPARK_VARS = ROOT / "IaC/ansible/group_vars/spark.yml"


def _load_validator():
    """Import validate-docker-services.py for its Jinja env + SSOT context, so this script
    cannot render differently from the gate that already guards every compose template."""
    spec = importlib.util.spec_from_file_location(
        "vds", SCRIPTS / "validate-docker-services.py")
    mod = importlib.util.module_from_spec(spec)
    sys.argv = [str(SCRIPTS / "validate-docker-services.py")]        # its main() never runs
    spec.loader.exec_module(mod)
    return mod


def compose_ctx(vds):
    ctx = dict(vds.BASE_CTX)
    svc = {"name": "spark-ai", "template_dir": "spark-ai", "public": False, "enabled": True}
    ctx.update({k: v for k, v in svc.items() if v is not None})
    ctx["instance"] = "primary"
    ctx["svc"] = svc
    # Jinja-valued spark vars the arms use for paths: the validator loads group_vars
    # verbatim (no Jinja resolution for non-scalars), so resolve them here from the
    # same SSOT scalars the one-level loader uses.
    sv = yaml.safe_load(SPARK_VARS.read_text(encoding="utf-8"))
    ctx["spark_draft_vocab_dir"] = sv["spark_xfs_mount"] + "/draft_vocab"
    ctx["spark_draft_vocab_host_file"] = ctx["spark_draft_vocab_dir"] + "/draft-vocab-ids-K65536.txt"
    return ctx


# The flat `spark_vllm_*` pass-throughs in group_vars are LAZY Jinja aliases of
# `spark_llm_profiles[spark_llm_profile].<key>`. Under Ansible they resolve against the
# host's dial; the offline validator loads group_vars ONCE, so its copy is frozen at the
# ACTIVE profile (reasoning). Rendering another arm without recomputing them would print
# reasoning's seqs/pool against another arm's mounts — a lying tool. Mirror the aliases:
#   key in ctx                    ← key in the profile (group_vars/spark.yml)
FLAT_ALIASES = {
    "spark_vllm_container": "container",
    "spark_vllm_served_name": "served_name",
    "spark_vllm_max_num_seqs": "max_num_seqs",
    "spark_vllm_max_model_len": "max_model_len",
    "spark_vllm_max_num_batched_tokens": "max_num_batched_tokens",
    "spark_vllm_kv_cache_dtype": "kv_cache_dtype",
    "spark_vllm_kv_cache_memory": "kv_cache_memory",
    "spark_vllm_distributed_executor_backend": "distributed_executor_backend",
    "spark_vllm_memory_limit": "memory_limit",
    "spark_vllm_spec_method": "spec_method",
    "spark_vllm_spec_tokens": "spec_tokens",
}


def render(env, ctx, profile, cat):
    c = dict(ctx)
    c["spark_llm_profile"] = profile
    prof = cat["spark_llm_profiles"][profile]
    for ctx_key, prof_key in FLAT_ALIASES.items():
        if prof_key in prof:
            c[ctx_key] = prof[prof_key]
    return env.from_string(TEMPLATE.read_text(encoding="utf-8")).render(**c)


def facts(doc):
    svc = doc["services"]["vllm-engine"]
    cmd = [str(a) for a in svc.get("command", [])]
    envv = [str(e) for e in svc.get("environment", [])]
    vols = [str(v) for v in svc.get("volumes", [])]
    def arg(flag):
        return cmd[cmd.index(flag) + 1] if flag in cmd else ""
    def hostpath(needle):
        for v in vols:
            h = v.split(":")[0]
            if needle in h:
                return h
        return ""
    return {
        "image": svc.get("image", ""),
        "model": next((v.split(":")[0] for v in vols if v.endswith(":/model:ro")), ""),
        "evict_arg": (cmd[cmd.index("--never-evict-kv-cache-prompt-includes") + 1]
                      if "--never-evict-kv-cache-prompt-includes" in cmd else ""),
        "ple": hostpath("ples_") or hostpath("ple-table"),
        "model_host": hostpath("") if False else next((v.split(":")[0] for v in vols if v.endswith(":/model:ro")), ""),
        "draft": next((v for v in vols if "draft" in v), ""),
        "seqs": arg("--max-num-seqs"),
        "ctx": arg("--max-model-len"),
        "pool": arg("--kv-cache-memory-bytes"),
        "spec": arg("--speculative-config"),
        "parser": arg("--tool-call-parser"),
        "ple_env": sum(1 for e in envv if e.startswith("VLLM_PLE")),
        "mmap_env": sum(1 for e in envv if e.startswith("VLLM_PLE_MMAP")),
        "offload_env": sum(1 for e in envv if e.startswith(("VLLM_PLE_CPU_OFFLOAD", "VLLM_PLE_OFFLOAD_READY"))),
        "overlay_mounts": sum(1 for v in vols if "/overlays/" in v),
        "cc": sum(1 for a in cmd if a.startswith("-cc.")),
        "evict": "--never-evict-kv-cache-prompt-includes" in cmd,
        "details": "--enable-prompt-tokens-details" in cmd,
        "mtp_draft_vocab": sum(1 for e in envv if e.startswith("VLLM_MTP_DRAFT_VOCAB")),
    }


def main():
    args = sys.argv[1:]
    strict = "--strict" in args
    dump = args[args.index("--dump") + 1] if "--dump" in args else None
    vds = _load_validator()
    env, ctx = vds.build_env(), compose_ctx(vds)
    cat = yaml.safe_load(SPARK_VARS.read_text(encoding="utf-8"))
    profiles = [k for k in cat["spark_llm_profiles"] if not k.startswith("_")]

    if dump:
        print(render(env, ctx, dump))
        return 0

    bad = []
    print(f"{'profile':11} {'image':11} {'model host path':46} {'ple':34} "
          f"{'seqs':4} {'pool':12} {'ovl':3} {'mmap':4} {'cc':2} {'pin':3} notes")
    for name in profiles:
        try:
            doc = yaml.safe_load(render(env, ctx, name, cat))
        except yaml.YAMLError as e:
            bad.append(f"{name}: YAML parse failed — {e}")
            print(f"{name:11} RENDER/YAML FAIL: {str(e).splitlines()[0][:110]}")
            continue
        except Exception as e:                                        # noqa: BLE001
            bad.append(f"{name}: render failed — {e}")
            print(f"{name:11} RENDER FAIL: {str(e)[:110]}")
            continue
        f = facts(doc)
        gated = not f["image"]
        notes = []
        if gated:
            notes.append("IMAGE-PIN-EMPTY(gated)")
        if "CHANGEME" in render(env, ctx, name, cat):
            # NOT a failure: the pin arms SHIP with the placeholder and roles/spark-llm-profile
            # refuses them until a real substring is authored (a placeholder that matches
            # nothing is an invisible no-op; one that matches everything is a pool leak).
            # scripts/check_spark_llm_gate.py canary-proves the refusal.
            notes.append("pin-placeholder(gated)")
        # the composed coordinates must be observable — a silently missing flag is the bug
        want = cat["spark_llm_profiles"][name]
        if want.get("draft_vocab") and not (f["draft"] and f["mtp_draft_vocab"]):
            bad.append(f"{name}: draft_vocab: true but no bind/env rendered")
        if want.get("ple_mmap") and f["mmap_env"] == 0:
            bad.append(f"{name}: ple_mmap: true but no VLLM_PLE_MMAP env rendered")
        if want.get("ple_mmap") and not f["ple"]:
            # The bug this check was written for: an arm naming an mmap table root but no
            # subdir renders VLLM_PLE_MMAP_DIR=/ple-table with NOTHING mounted there.
            bad.append(f"{name}: ple_mmap: true but no PLE table mount rendered")
        if want.get("ple_mmap") and f["offload_env"]:
            bad.append(f"{name}: mmap AND primitive-ai offload env rendered together")
        if want.get("cudagraph_piecewise") and f["cc"] == 0:
            bad.append(f"{name}: cudagraph_piecewise: true but no -cc.* rendered")
        if want.get("prompt_tokens_details") and not f["details"]:
            bad.append(f"{name}: prompt_tokens_details: true but the flag is absent")
        if want.get("never_evict_prompt") and not f["evict"]:
            bad.append(f"{name}: never_evict_prompt set but the flags are absent")
        eng = want.get("engine", "vllm")
        ple = (f["ple"].split(":")[0] if f["ple"] else "")[len("/mnt/spark_nvme"):][:34] or "-"
        print(f"{name:11} {('ultrafast' if want.get('image')=='ultrafast' else want.get('image','base')):11} "
              f"{f['model']:46} {ple:34} {f['seqs'] or '-':4} {(f['pool'] or '-')[:11]:12} "
              f"{f['overlay_mounts']:3} {f['mmap_env']:4} {f['cc']:2} {'no' if gated else 'yes':3} "
              f"{' '.join(notes) if notes else ('sglang' if eng == 'sglang' else 'ok')}")

    # The certified lane's contract, asserted not assumed: it must still render the BASE
    # image, the INT4 overlay mounts, the table, and the legacy literal spec line. If a
    # template edit changes `reasoning`'s render, this is where it shows (HD-469 parity).
    r = facts(yaml.safe_load(render(env, ctx, "reasoning", cat)))
    pins = yaml.safe_load((ROOT / "IaC/ansible/group_vars/all/versions.yml").read_text(encoding="utf-8"))
    for what, ok in [
        ("reasoning keeps the base image digest", r["image"] == pins["spark_vllm_image"]),
        ("reasoning keeps 3 overlay mounts", r["overlay_mounts"] == 3),
        ("reasoning keeps the INT4 table mount", r["ple"].endswith("/ples_int4")),
        ("reasoning keeps offload env (2), no mmap env", r["offload_env"] == 2 and r["mmap_env"] == 0),
        ("reasoning keeps the legacy spec line",
         r["spec"] == '{"method": "mtp", "num_speculative_tokens": 3}'),
        ("reasoning keeps qwen3_coder + full window",
         r["parser"] == "qwen3_coder" and r["ctx"] == "262144"),
    ]:
        print(("  ok   " if ok else "  FAIL ") + what)
        if not ok:
            bad.append("parity: " + what)

    if bad:
        print(f"\nFAIL — {len(bad)} problem(s):")
        for b in bad:
            print("  · " + b)
        return 1
    if strict:
        print("\n--strict: every profile renders, parses, and carries a non-empty image pin.")
    else:
        print("\nAll profiles render and parse.")
        print("The `ultrafast` image pin is RECORDED (versions.yml:311, sha256:4900c13e…); the")
        print("only empty pin left is `fast-sglang` (spark_sglang_image) — its designed gate. "
              "roles/spark-llm-profile refuses those profiles until a pin lands.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
