#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""port_v32.py — stage the UltraFast patch stack for the v0.32 lineage, re-anchored, with proof.

WHAT THIS IS. The v0.32 lineage ports a third-party recipe that was written against a different
upstream revision. The recipe lives in a pinned git checkout and is NOT edited there: a hand-edited
checkout still has the pinned HEAD, so the role's `HEAD == pin` provenance assert would pass while
the build compiled an unreviewable local edit — an image nobody can rebuild. This script therefore
copies the patch sources OUT of the checkout into a build directory and re-anchors the COPY. The
checkout stays byte-for-byte the pin, which is what keeps "we built what they measured" checkable.

WHAT IT DOES, in order, each step loud:
  1. Verifies the pristine checkout against the checkout's OWN md5/sha256 lists (the same lists
     upstream's recipe/build/image/build.sh checks). This is the provenance half: the patch sources
     this lineage is about to modify are byte-for-byte the ones upstream measured.
  2. Stages `src/` and `tests/` into the build directory, fresh, from the pinned checkout.
  3. Removes the day-0 build definition (`build.sh`, `Dockerfile.iter6c`, `Dockerfile.iter6d`) from
     the staged copy. They hardcode the tags that are the only names the LIVE `fast` image has, so a
     v32 build directory that can run them is a directory where the live lineage's tags can be
     overwritten by accident.
  4. Applies the anchor table below. Every entry must be found EXACTLY the expected number of times
     BEFORE the substitution and the new text must be present, and the old text absent, AFTER it.
     A moved anchor is a hard failure naming the file and the evidence, never a silent no-op.

EXIT: 0 = staged and re-anchored · 1 = an anchor did not match · 2 = a source hash did not match ·
3 = usage / refusing to touch the checkout.

--check-only is the pre-build read: nothing is staged yet, so it inspects the CHECKOUT — the tree the
port is about to be derived from — and never the (still nearly empty) build directory.

Usage: port_v32.py --checkout <path>/recipe/build/image --stage <build dir> [--check-only]
"""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

# (file in the staged tree, text to find, text to write, expected occurrences, evidence at v0.32.0)
#
# "Evidence" is the upstream tag source this table was read from, as `path:line` (or the HTTP status
# of the path at the tag). Anchors that could not be proven from the tag are NOT here — they are
# listed in spark/reports/hd1206-v32-port-20261026/README.md, and a step that depends on one either
# fails loudly in the image build or is guarded by a grep in Dockerfile.v32.
ANCHORS: list[tuple[str, str, str, int, str]] = [
    (
        "src/vllm_ple_mmap.py",
        "from vllm.models.qwen3_8_flash_next.nvidia.model_state import (",
        "from vllm.models.qwen4_exp.nvidia.model_state import (",
        1,
        "vllm/models/qwen4_exp/nvidia/model_state.py:17 (class Qwen4ExpModelState), "
        "prepare_inputs at :95",
    ),
    (
        "src/vllm_ple_mmap.py",
        "Qwen3_8FlashNextModelState",
        "Qwen4ExpModelState",
        4,
        "vllm/models/qwen4_exp/nvidia/model_state.py:17 — the three other occurrences are the "
        "call sites in this file, so a partial rename leaves a NameError behind",
    ),
    (
        "src/vllm_ple_mmap.py",
        "``vllm/models/qwen3_8_flash_next/nvidia/ple_layer.py``",
        "``vllm/models/qwen4_exp/nvidia/ple_layer.py``",
        1,
        "HTTP 404 for the qwen3_8_flash_next path at the tag, 200 for qwen4_exp — the docstring "
        "must not point at a module this image does not contain",
    ),
    (
        "src/vllm_ple_mmap.py",
        "Qwen3_8FlashNextNGramEmbedding",
        "Qwen4ExpNGramEmbedding",
        3,
        "vllm/models/qwen4_exp/nvidia/ple_layer.py:29 (imported into that module's namespace); "
        "docstring-only in this file — the class reaches the hook via Dockerfile.v32 step 1",
    ),
    (
        "src/vllm_ple_mmap.py",
        "Qwen3_8FlashNextPLELayer",
        "Qwen4ExpPLELayer",
        2,
        "vllm/models/qwen4_exp/nvidia/ple_layer.py:65 (class Qwen4ExpPLELayer)",
    ),
    (
        "src/vllm_mtp_draft_vocab.py",
        "Qwen3_8FlashNextMTP",
        "Qwen4ExpMTP",
        3,
        "vllm/models/qwen4_exp/nvidia/mtp.py:400 (class Qwen4ExpMTP) and "
        "vllm/model_executor/models/registry.py:696; docstring-only in this file",
    ),
    (
        "src/vllm_inproj_ba_gemv.py",
        "models/qwen3_8_flash_next/nvidia/model.py",
        "models/qwen4_exp/nvidia/model.py",
        2,
        "HTTP 200 for vllm/models/qwen4_exp/nvidia/model.py at the tag; the LINE NUMBERS quoted "
        "beside these pointers are day-0 and are NOT re-derived here",
    ),
    (
        "src/patch_low_latency_gemm_sm12x.py",
        '"qwen3_8_flash_next/nvidia/low_latency_gemm.py"',
        '"qwen4_exp/nvidia/low_latency_gemm.py"',
        1,
        "HTTP 200 for vllm/models/qwen4_exp/nvidia/low_latency_gemm.py at the tag",
    ),
    (
        "tests/test_iter6_patches_image.py",
        'LLG = SP + "/vllm/models/qwen3_8_flash_next/nvidia/low_latency_gemm.py"',
        'LLG = SP + "/vllm/models/qwen4_exp/nvidia/low_latency_gemm.py"',
        1,
        "the CPU self-test's own target path; HTTP 200 for the qwen4_exp file at the tag",
    ),

# patch_never_evict.py -- Dockerfile.v32 step 5, restored by the port-everything ruling
# (2026-10-27), which reverses the f42638e2 drop. Only the scheduler call site moved:
# v0.32 inserted enable_mamba_shared_prefix_checkpoint=( … ), between the watermark
# argument and the closing paren, so the patcher's two-line anchor is a five-line one.
# The flag itself stays REJECTED and every spark_llm_never_evict_prompt stays empty:
# the image carries the plumbing, nothing renders the dial
# (docs/services-ai-rejected.md, IaC/ansible/group_vars/spark.yml).
    (
        "src/patch_never_evict.py",
        (
        '            watermark=self.scheduler_config.watermark,\n' +
        '        )\n' +
        ''
    ),
        (
        '            watermark=self.scheduler_config.watermark,\n' +
        '            enable_mamba_shared_prefix_checkpoint=(\n' +
        '                self.cache_config.enable_mamba_shared_prefix_checkpoint\n' +
        '            ),\n' +
        '        )\n' +
        ''
    ),
        2,
        "vllm/v1/core/sched/scheduler.py:342-345 -- v0.32 inserted the mamba shared-prefix kwarg between the watermark argument and the closing paren, so the day-0 two-line sequence is now a five-line one; 2 = the patcher's old side and its new side",
    ),


# patch_hit_debug.py -- Dockerfile.v32 step 8. Two of the four gate targets carry no
# module logger at this base, so for kv_cache_coordinator.py the logger is INTRODUCED
# rather than searched for: grep -F -c 'logger = init_logger(__name__)' answers 0 in
# v1/core/kv_cache_coordinator.py and in v1/core/single_type_kv_cache_manager.py at
# 6ff5ff0d, while block_pool.py, kv_cache_manager.py and sched/scheduler.py answer 1
# (README 7b: the [14/38] red). The single_type target already introduced its own.
    (
        "src/patch_hit_debug.py",
        (
        'for key in ("coord", "pool", "sched"):\n' +
        '    add_gate(FILES[key])\n' +
        ''
    ),
        (
        'for key in ("pool", "sched"):\n' +
        '    add_gate(FILES[key])\n' +
        '\n' +
        '# spark-v32 re-anchor: kv_cache_coordinator.py carries no module logger at this\n' +
        '# base -- no `logger = init_logger(__name__)` line and no vllm.logger import -- so\n' +
        "# the gate is INTRODUCED here instead of searched for. The anchor is the file's own\n" +
        '# import of Request (v1/core/kv_cache_coordinator.py:30, one occurrence).\n' +
        'edit(\n' +
        '    FILES["coord"],\n' +
        '    """from vllm.v1.request import Request\n' +
        '""",\n' +
        '    """from vllm.v1.request import Request\n' +
        '\n' +
        'from vllm.logger import init_logger\n' +
        '\n' +
        'logger = init_logger(__name__)\n' +
        '"""\n' +
        '    + GATE,\n' +
        ')\n' +
        ''
    ),
        1,
        "vllm/v1/core/kv_cache_coordinator.py:30 (from vllm.v1.request import Request, 1 hit; grep -F -c 'logger = init_logger(__name__)' answers 0 in that file at 6ff5ff0d)",
    ),

]

# Removed from the staged tree, with the reason each one is dangerous in a v32 build directory.
REMOVED = [
    ("build.sh", "hardcodes the iter6c/iter6d tags and pulls/builds the day-0 lineage"),
    ("Dockerfile.iter6c", "FROM the day-0 parent digest, with the day-0 path anchors"),
    ("Dockerfile.iter6d", "FROM qwen38-flash-dgx:iter6c-20260909, the live lineage's intermediate"),
]

# Upstream runs its checks as `if ! (cd "$here" && md5sum --check --status <<'MD5' … MD5`, so the
# command is matched anywhere on the line and the block runs to the closing tag on its own line.
HASH_BLOCK = re.compile(r"(md5sum|sha256sum)\s+--check\s+--status\s+<<'([A-Z0-9]+)'")


def fail(code: int, message: str) -> None:
    print(f"port_v32: {message}", file=sys.stderr)
    sys.exit(code)


def hash_lists(checkout: Path) -> list[tuple[str, str, str]]:
    """The checksum blocks upstream's own build.sh enforces, as (algorithm, block text, digest)."""
    build_sh = checkout / "build.sh"
    if not build_sh.is_file():
        fail(2, f"{build_sh} is missing — the checkout is not the recipe this lineage ports")
    lines = build_sh.read_text(encoding="utf-8").splitlines()
    blocks: list[tuple[str, str, str]] = []
    i = 0
    while i < len(lines):
        m = HASH_BLOCK.search(lines[i])
        if not m:
            i += 1
            continue
        algo, tag = m.group(1), m.group(2)
        body: list[str] = []
        i += 1
        while i < len(lines) and lines[i].strip() != tag:
            body.append(lines[i])
            i += 1
        digest = hashlib.sha256("\n".join(body).encode()).hexdigest()
        blocks.append((algo, "\n".join(body) + "\n", digest))
    if not blocks:
        fail(2, f"{build_sh} carries no md5sum/sha256sum --check block; the source gate is gone")
    return blocks


def verify_hashes(checkout: Path) -> list[str]:
    printed: list[str] = []
    for algo, block, digest in hash_lists(checkout):
        proc = subprocess.run(
            [algo, "--check"], input=block, cwd=checkout,
            capture_output=True, text=True, check=False,
        )
        if proc.returncode != 0:
            bad = [ln.split()[-1] for ln in proc.stdout.splitlines() if "FAILED" in ln]
            fail(2, f"{algo} gate failed in {checkout} for the files: {', '.join(bad) or proc.stderr.strip()}\n"
                    "     The pinned checkout is not the source set upstream measured; do not build.")
        printed.append(f"{algo} block {digest[:12]}… verified ({len(block.splitlines())} files)")
    return printed


def apply_anchors(tree: Path, check_only: bool) -> int:
    failures = 0
    for rel, old, new, expected, evidence in ANCHORS:
        path = tree / rel
        if not path.is_file():
            print(f"port_v32: MISSING  {rel} — {tree} does not contain it", file=sys.stderr)
            failures += 1
            continue
        src = path.read_text(encoding="utf-8")
        found = src.count(old)
        if found != expected:
            print(f"port_v32: ANCHOR   {rel}\n"
                  f"          wanted {expected} occurrence(s) of {old[:70]!r}, found {found}\n"
                  f"          evidence at the tag: {evidence}\n"
                  f"          the day-0 anchor moved — read the file at the tag before porting it.",
                  file=sys.stderr)
            failures += 1
            continue
        if not check_only:
            path.write_text(src.replace(old, new), encoding="utf-8")
        after = path.read_text(encoding="utf-8")
        if check_only:
            after = after.replace(old, new)
        if after.count(new) != expected or after.count(old) != 0:
            print(f"port_v32: VERIFY   {rel}: {new[:70]!r} not present as expected after the "
                  "substitution — the port did not land", file=sys.stderr)
            failures += 1
            continue
        print(f"port_v32: anchor ok  {rel}: {expected}x {old[:48]!r} -> {new[:48]!r}")
    return failures


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkout", required=True, type=Path)
    ap.add_argument("--stage", required=True, type=Path)
    ap.add_argument("--check-only", action="store_true",
                    help="verify the hashes and every anchor against the CHECKOUT, writing nothing")
    args = ap.parse_args()

    checkout = args.checkout.resolve()
    stage = args.stage.resolve()
    if not checkout.is_dir():
        fail(3, f"{checkout} is not a directory — the recipe checkout is missing")
    # Either tree containing the other is the same accident the equality clause refuses: staging INTO
    # the checkout is how the tree stops being the pin it claims to be, and a checkout nested INSIDE
    # the build directory is deleted by the same cleanup that empties that directory before it copies.
    if stage == checkout or checkout in stage.parents or stage in checkout.parents:
        fail(3, f"refusing to stage into {stage}: the checkout ({checkout}) must stay byte-for-byte "
                "the pin, and neither tree may contain the other")

    for line in verify_hashes(checkout):
        print(f"port_v32: {line}")

    if not args.check_only:
        for name in ("src", "tests"):
            target = stage / name
            if target.exists():
                shutil.rmtree(target)
            shutil.copytree(checkout / name, target)
            print(f"port_v32: staged     {name}/ from {checkout}")
        for name, reason in REMOVED:
            victim = stage / name
            if victim.exists():
                victim.unlink()
                print(f"port_v32: removed    {name} — {reason}")
        # Verify the deletion instead of assuming it: `if exists` + `unlink()` prints the same line for
        # "there was nothing there" and "nothing was actually removed", and a build directory that can
        # still run upstream's build.sh is a directory that can retag the live `fast` image. A day-0
        # file that reached here under a name this table does not list is NOT caught by this read;
        # what catches the damage it could do is the assert that re-reads every reserved tag after
        # the build.
        left = [name for name, _ in REMOVED if (stage / name).exists()]
        if left:
            fail(1, f"{', '.join(left)} still in {stage} after the removal step — this build "
                    "directory can still write the live lineage's tags. If upstream renamed the file, "
                    "read the recipe at the pin and extend REMOVED in its own commit.")

    # --check-only runs BEFORE anything is staged, and the build directory at that point holds only
    # this script and Dockerfile.v32. Reading it would report every anchor MISSING and hand the role a
    # --check verdict about a tree that is not the port's source, so this mode reads the checkout.
    tree = checkout if args.check_only else stage
    label = "checkout" if args.check_only else "staged tree"
    bad = apply_anchors(tree, args.check_only)
    if bad:
        print(f"port_v32: {bad} anchor(s) did not match — see the evidence lines above. Nothing was "
              "built; do not loosen an anchor to make this pass.", file=sys.stderr)
        return 1
    print(f"port_v32: {len(ANCHORS)} anchors verified against the {label} {tree}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
