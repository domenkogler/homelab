#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""patch_mamba_guard_v32.py — the mamba state-copy guard, ported onto v0.32's own mamba_utils.py.

WHAT THIS IS. The recipe's `src/mamba_utils_guarded.py` is the DAY-0 `mamba_utils.py` plus a guard:
every block id read from a block table is bounds-checked against the owning state tensor's block
count before the copy, an out-of-range id skips the copy and bumps a counter instead of writing
through a wild address (observed as Xid 31 MMU faults on GB10), and the counter is reported off a
pinned mirror so no serving step ever blocks on the GPU. None of that exists in this base — 0
occurrences of `guard_hits` and 0 of `state_num_blocks` in `vllm/v1/worker/mamba_utils.py` at
v0.32.0 — so the guard is owed, and the base will not supply it. This script is how it is paid.

WHY A PATCH AND NOT THE FILE COPY. The snapshot is 1641 lines against this base's 1654, and the
delta is three layers, not one: the guard (snapshot side only), the day-0 `postprocess_mamba_all` /
`preprocess_mamba_all_specdec` pair that v0.32 deleted, and v0.32's own additions —
`get_aligned_state_indices_multi_group_kernel`, `_reinterpret_u64_as_i64`,
`compute_aligned_state_indices` — that the snapshot has never seen, plus one re-typed signature
(`postprocess_mamba_align_gpu`'s `input_batch` is `InputBatch` at v0.32, `GPUInputBatch` in the
snapshot). Copying the file over this base would revert two of those layers silently. So only the
guard is ported, as anchored insertions, and the two directions are asserted afterwards: the guard
constructs reach their counts AND the day-0 pair stays absent AND this base's new kernels survive.

CONTRACT. Every anchor is a text span read out of THIS base's file, with the `file:line` it was read
at beside it, and must occur EXACTLY the stated number of times. All counts are measured on the
unmodified file before anything is written, so a moved anchor leaves the target untouched. The
inserted lines are byte-identical to the guard's lines in the snapshot, which is why the post-apply
counts below are the day-0 artifact's counts: a reader can diff this lineage's guard against the one
the live `fast` engine runs on and find the same bytes.

EXIT: 0 = patched · 1 = an anchor did not match, or the result does not parse (nothing was written) ·
2 = refused: the target already carries a guard, so this is a second apply · 3 = usage.

Usage: patch_mamba_guard_v32.py [--target <path>]        (default: this image's own mamba_utils.py)
"""

from __future__ import annotations

import argparse
import ast
import sys
from pathlib import Path

# This lineage's base image keeps site-packages under python3.12 (docker/Dockerfile:25-26 pins
# CUDA 13.0.3 / Python 3.12), the same prefix Dockerfile.v32's ${SP} carries.
TARGET = "/usr/local/lib/python3.12/dist-packages/vllm/v1/worker/mamba_utils.py"

# (anchor text in this base, text inserted AFTER it, expected occurrences, evidence at v0.32.0)
#
# "Evidence" is the file:line this table was read at, in the pulled base image at the pin digest —
# the same read the build's own greps run. A guard line that belongs to a pair (a kernel parameter
# and its call site) is anchored with the following line included, because `state_dim_row_stride_ptr,`
# alone occurs 5 times in this file and only its two call sites want the guard arguments.
ANCHORS: list[tuple[str, str, int, str]] = [
    (
        "    state_dim_row_stride_ptr,\n    tile_idx,\n",
        "    # qwen38-flash-dgx guard: valid block count per state pool + skip counter\n"
        "    state_num_blocks_ptr,\n"
        "    guard_hits_ptr,\n",
        1,
        "mamba_utils.py:207-208 — `_copy_mamba_state_block`'s parameter list (def at :191). The two "
        "parameters land between `state_dim_row_stride_ptr,` and `tile_idx,`, which is the order both "
        "call sites pass them in (:494, :625), and the kernels take these positionally.",
    ),
    (
        "    dest_block_id = tl.load(block_table_base + dst_col).to(tl.int64)\n",
        "    # Guard: a corrupt/stale block id would send the copy through a wild\n"
        "    # address (observed as Xid 31 MMU faults on GB10). Skipping the copy\n"
        "    # leaves one request with a stale mamba state — recoverable — instead\n"
        "    # of killing the CUDA context. The counter is reported asynchronously.\n"
        "    num_blocks = tl.load(state_num_blocks_ptr + state_idx)\n"
        "    if dest_block_id < 0 or dest_block_id >= num_blocks:\n"
        "        tl.atomic_add(guard_hits_ptr, 1)\n"
        "        return\n",
        1,
        "mamba_utils.py:251 — the file's only destination-block-id load, and the definition of "
        "`num_blocks` that the three source-side checks below reuse.",
    ),
    (
        "        src_block_id = tl.load(block_table_base + src_col).to(tl.int64)\n",
        "        if src_block_id < 0 or src_block_id >= num_blocks:\n"
        "            tl.atomic_add(guard_hits_ptr, 1)\n"
        "            return\n",
        2,
        "mamba_utils.py:262 (the DS-conv row path) and :313 (the conv-slide path) — the two source-"
        "side block-id loads inside `_copy_mamba_state_block`. Both want the check; a patch that "
        "lands in one and misses the other guards half the copies.",
    ),
    (
        "    actual_src_block_id = tl.load(block_table_base + src_col + token_bias).to(tl.int64)\n",
        "    if actual_src_block_id < 0 or actual_src_block_id >= num_blocks:\n"
        "        tl.atomic_add(guard_hits_ptr, 1)\n"
        "        return\n",
        1,
        "mamba_utils.py:352 — the temporal-body block-id load, the fourth and last block id the "
        "kernel dereferences.",
    ),
    (
        "    state_dim_row_stride_ptr,  # int64: bytes between rows for DS conv\n",
        "    state_num_blocks_ptr,  # int64: valid block count per state pool (guard)\n"
        "    guard_hits_ptr,  # int32[1]: skipped out-of-range copies (guard)\n",
        1,
        "mamba_utils.py:391 — `postprocess_mamba_fused_kernel`'s parameter list (def at :369). Its "
        "two launches are mamba_utils.py:1177 and :1276, both in this file.",
    ),
    (
        "    state_dim_row_stride_ptr,\n"
        "    idx_mapping_ptr,  # [num_reqs] batch_idx -> req_state_idx (-1 to skip)\n",
        "    state_num_blocks_ptr,  # int64: valid block count per state pool (guard)\n"
        "    guard_hits_ptr,  # int32[1]: skipped out-of-range copies (guard)\n",
        1,
        "mamba_utils.py:565-566 — `precopy_mamba_align_fused_kernel`'s parameter list (def at :549), "
        "launched once from this file at :1226. `preprocess_mamba_align_fused_kernel` (:503) takes "
        "neither parameter and is not touched.",
    ),
    (
        "        state_dim_row_stride_ptr,\n        tile_idx,\n",
        "        state_num_blocks_ptr,\n        guard_hits_ptr,\n",
        2,
        "mamba_utils.py:494 and :625 — the two `_copy_mamba_state_block(` call sites (at :479 and "
        ":610). They pass these positionally, so a count of 1 means one copy site is unguarded.",
    ),
    (
        "    state_dim_row_stride: torch.Tensor  # int64: bytes between rows\n",
        "    # Guard: valid block count per state pool + skipped-copy counter\n"
        "    state_num_blocks: torch.Tensor  # int64: shape[0] of each state tensor\n"
        "    guard_hits: torch.Tensor  # int32[1], GPU: out-of-range copies skipped\n",
        1,
        "mamba_utils.py:795 — the tail of `MambaSpecDecodeGPUContext`'s state-metadata fields, the "
        "block `create()` below passes them into.",
    ),
    (
        "    is_initialized: bool = False\n",
        "\n"
        "    # Guard telemetry (sync-free: pinned mirror is refreshed asynchronously\n"
        "    # and read one reporting round late)\n"
        "    guard_hits_cpu: torch.Tensor | None = None\n"
        "    guard_step: int = 0\n"
        "    guard_reported: int = 0\n",
        1,
        "mamba_utils.py:830 — the context's last field, immediately before `@classmethod create` "
        "at :833. The three guard fields carry defaults, so they must land AFTER the non-defaulted "
        "ones or the dataclass definition itself fails.",
    ),
    (
        "            state_dim_row_stride=torch.zeros(\n"
        "                total_states, dtype=torch.int64, device=device\n"
        "            ),\n",
        "            state_num_blocks=torch.zeros(\n"
        "                total_states, dtype=torch.int64, device=device\n"
        "            ),\n"
        "            guard_hits=torch.zeros(1, dtype=torch.int32, device=device),\n"
        "            guard_hits_cpu=torch.zeros(1, dtype=torch.int32, pin_memory=True),\n",
        1,
        "mamba_utils.py:891-893 — `MambaSpecDecodeGPUContext.create`'s per-state zero table, the "
        "same `total_states` the kernel indexes `state_num_blocks_ptr` with.",
    ),
    (
        "                    self.state_base_addrs[idx] = _reinterpret_u64_as_i64(\n"
        "                        state.data_ptr()\n"
        "                    )\n",
        "                    self.state_num_blocks[idx] = (\n"
        "                        state.size(0) if state.dim() > 1 else 1\n"
        "                    )\n",
        1,
        "mamba_utils.py:1008-1010 — `_populate_metadata`'s base-address line, which v0.32 rewrote to "
        "thread the pointer through `_reinterpret_u64_as_i64`. This is the anchor the guard cannot do "
        "without: `create()` zeroes `state_num_blocks`, and a pool whose count is never written makes "
        "the guard skip EVERY copy. The address line itself keeps v0.32's form.",
    ),
    (
        "            self.state_dim_row_stride,\n",
        "            self.state_num_blocks,\n            self.guard_hits,\n",
        3,
        "mamba_utils.py:1192 (`run_fused_postprocess`), :1239 (`run_fused_precopy`) and :1291 "
        "(`run_fused_postprocess_align`) — the three launches of the two patched kernels. A count of "
        "2 would leave one kernel launched with too few arguments, which is a Triton TypeError on the "
        "first step that reaches it.",
    ),
    (
        "            HAS_IDX_MAPPING=idx_mapping is not None,\n"
        "            TEMPORAL_TILES=_TEMPORAL_TILES,\n"
        "        )\n",
        "        # Guard telemetry: refresh a pinned mirror of guard_hits every 512\n"
        "        # steps and report the value captured by the PREVIOUS refresh, so no\n"
        "        # step ever blocks on the GPU (async-scheduling safe).\n"
        "        self.guard_step += 1\n"
        "        if self.guard_step % 512 == 0:\n"
        "            hits = int(self.guard_hits_cpu[0])\n"
        "            if hits > self.guard_reported:\n"
        "                # Root cause of these was fixed (mamba block-size seed,\n"
        "                # blazux/qwen3.8-Flash-DGX#2 / 8347e7c): the guard is now a\n"
        "                # tripwire, any hit indicates a NEW bug worth reporting.\n"
        "                logger.error(\n"
        '                    "mamba state-copy guard: %d out-of-range block id(s) "\n'
        '                    "skipped (would have been an illegal memory access). "\n'
        '                    "Expected 0 since the mamba block-size seed fix - "\n'
        '                    "this indicates a new bug, please report it.",\n'
        "                    hits,\n"
        "                )\n"
        "                self.guard_reported = hits\n"
        "            self.guard_hits_cpu.copy_(self.guard_hits, non_blocking=True)\n",
        1,
        "mamba_utils.py:1244-1246 — the tail of the `precopy_mamba_align_fused_kernel` launch that "
        "closes `run_fused_precopy` (`def` at :1202), the step that runs on every forward pass of "
        "this box's align + spec-decode arm. That 3-line tail occurs exactly once in the file, so the "
        "reporter lands in the method that was read instead of in whichever launch shares the shape.",
    ),
]

# What the patched file must look like. Every count below is a LINE count — the same thing
# `grep -c -F <pattern>` reports, which is how step 7 re-checks the finished layer and how the report
# records the base. The two MUST_APPEAR numbers are the day-0 artifact's own counts
# (`grep -c -F guard_hits` = 19, `state_num_blocks` = 12), which is the check that the port is the
# whole guard and not part of it.
MUST_APPEAR = {
    "guard_hits": 19,
    "state_num_blocks": 12,
    "tl.atomic_add(guard_hits_ptr, 1)": 4,
    "num_blocks = tl.load(state_num_blocks_ptr + state_idx)": 1,
}
# What this base adds and the port must leave alone — the reason `apply` (the whole-file copy) is the
# escape hatch and not the default.
MUST_STAY = {
    "get_aligned_state_indices_multi_group_kernel": 2,
    "_reinterpret_u64_as_i64": 4,
    "compute_aligned_state_indices": 2,
}
# What must stay absent: the day-0 fork pair the snapshot still carries, and the day-0 batch class
# the snapshot's signature names. This base has none of them; a hit here means a copy, not a patch.
MUST_STAY_ABSENT = [
    "postprocess_mamba_all",
    "preprocess_mamba_all_specdec",
    "GPUInputBatch",
]
# The guard's own vocabulary: any occurrence before the patch means the target is already guarded.
GUARD_MARKERS = ["guard_hits", "state_num_blocks"]


def fail(code: int, message: str) -> None:
    print(f"patch_mamba_guard_v32: {message}", file=sys.stderr)
    sys.exit(code)


def count_lines(text: str, pattern: str) -> int:
    """`grep -c -F <pattern>`: lines containing the pattern, not occurrences.

    The two differ here: `self.guard_hits_cpu.copy_(self.guard_hits, …)` names the guard twice on one
    line, so an occurrence count reads 20 where the build's grep reads 19.
    """
    return sum(1 for line in text.splitlines() if pattern in line)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", type=Path, default=Path(TARGET),
                    help="the mamba_utils.py to patch (default: this image's own)")
    args = ap.parse_args()

    path = args.target
    if not path.is_file():
        fail(3, f"{path} is not a file — pass --target <path> to the mamba_utils.py to patch")
    src = path.read_text(encoding="utf-8")

    hits = {m: count_lines(src, m) for m in GUARD_MARKERS}
    if any(n for n in hits.values()):
        print("patch_mamba_guard_v32: REFUSED — this target already carries a mamba state-copy guard.",
              file=sys.stderr)
        print(f"patch_mamba_guard_v32:          {path}", file=sys.stderr)
        print("patch_mamba_guard_v32:          " +
              ", ".join(f"{m}={n}" for m, n in hits.items()), file=sys.stderr)
        print("patch_mamba_guard_v32: Either this layer already applied the patch (then there is "
              "nothing to do and this run must not re-apply it), or a newer base added the guard "
              "upstream — in which case step 7 and this patcher are dead code: delete them in their "
              "own commit, do not let a second copy of the guard in.", file=sys.stderr)
        return 2

    bad = 0
    for anchor, _insert, expected, evidence in ANCHORS:
        found = src.count(anchor)
        if found != expected:
            line = src.count("\n", 0, src.find(anchor)) + 1 if found else 0
            print(f"patch_mamba_guard_v32: ANCHOR   {path}\n"
                  f"          wanted {expected} occurrence(s), found {found}"
                  + (f" (first at line {line})" if found else "") + "\n"
                  f"          anchor: {anchor[:72]!r}\n"
                  f"          evidence at v0.32.0: {evidence}\n"
                  f"          this base's mamba_utils.py is not the file the guard was ported "
                  f"against — read it at that line before patching.", file=sys.stderr)
            bad += 1
    if bad:
        print(f"patch_mamba_guard_v32: {bad} of {len(ANCHORS)} anchors did not match. Nothing was "
              "written; do NOT loosen an anchor to make the build pass.", file=sys.stderr)
        return 1

    for anchor, insert, _expected, _evidence in ANCHORS:
        src = src.replace(anchor, anchor + insert)

    try:
        ast.parse(src)
    except SyntaxError as exc:
        fail(1, f"the patched {path} does not parse ({exc}). Nothing was written — an anchor "
                "landed inside an expression or split a block.")

    for pattern, want in MUST_APPEAR.items():
        got = count_lines(src, pattern)
        if got != want:
            fail(1, f"the patch applied but {pattern!r} is on {got} line(s), want {want}, in "
                    f"{path}. Nothing was written.")
    for pattern, want in MUST_STAY.items():
        got = count_lines(src, pattern)
        if got != want:
            fail(1, f"the patch applied but this base's own {pattern!r} is now on {got} line(s), "
                    f"want {want}, in {path} — the port damaged upstream code. Nothing was written.")
    for pattern in MUST_STAY_ABSENT:
        got = count_lines(src, pattern)
        if got:
            fail(1, f"{pattern!r} is on {got} line(s) of the result, want 0 — that is day-0 code, "
                    "so this is a file copy and not a port. Nothing was written.")

    path.write_text(src, encoding="utf-8")
    print(f"patch_mamba_guard_v32: {len(ANCHORS)} anchors applied to {path}")
    print(f"patch_mamba_guard_v32: guard present — " +
          ", ".join(f"{k}={v}" for k, v in MUST_APPEAR.items()))
    print("patch_mamba_guard_v32: day-0 pair absent — " + ", ".join(MUST_STAY_ABSENT))
    print("patch_mamba_guard_v32: v0.32's own kernels intact — " +
          ", ".join(f"{k}={v}" for k, v in MUST_STAY.items()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
