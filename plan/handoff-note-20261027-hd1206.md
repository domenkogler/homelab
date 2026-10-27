# Handoff notes — HD-1206 v32 lineage (closed session, 2026-10-27)

Closed at `main = 5d111935`; gate ends at the designed `check_secret_leak.py` HD-1181 failure. No child
sessions, no detached processes, no tunnels, no worktrees owned by this session left.

## State of the work

- **The v32 lineage is built and pinned.** `spark_vllm_ultrafast_v32_image = sha256:72eb432fd87c…`
  (`spark-ultrafast:v32-iter6d`, 35.3 GB, 49 instructions over base `6ff5ff0d…`), and
  `spark_llm_fp8_kv_capable_images` went `[]` → `[ultrafast-v32]` on
  `spark-fp8-image-probe.py --image spark-ultrafast:v32-iter6d --skip-registry` →
  `REACHABLE-ON-THIS-PIN`. Record: `spark/reports/hd1206-v32-port-20261026/build-20261027.md`.
- **R3 ruled A+** — step 14 applies nothing and guards the base's plan table (GB10 reports compute
  capability `12.1`; the day-0 predicate was `(10,3)`, so `fast` has always taken the `F.linear`
  fallback there and the v32 base runs the plan path). The runtime dispatch check is **owed in the window**.
- **New arm `fast-v32-bf16`** — `fast`'s coordinates on the same artifact, 644,599 slots = 2.46×, the base-
  lineage control; `certified: false`. Nomenclature is documented in `docs/spark-llm-profiles.md`
  §Nomenclature: the day-0 base is `0.1.dev20073+g8e685d198`, **not v0.30**, so the base token is `day0`;
  the `reasoning-v32-*` arms buy no slots and were not authored. Additive naming only — a live dial rename
  would break `check_spark_llm_gate.py`'s canary, the render matrix's parity guard, and `spark-rollback:fast`.
- **HD-1210, P1** (minted at merge) — the build's post-build CPU gates assert day-0 bytes, so on v32 they
  certify nothing either way; re-anchor them off the pristine base file, never off the artifact.

## Next session

1. **The owner window** (owner present, a seat spark does not serve): the A+ dispatch check → flip
   `fast-v32-bf16` per-run with `-e spark_llm_allow_uncertified=true`, expecting `fast`'s 644,599-slot /
   2.46× line → gates 0–7 → then `fast8` and dtype gates 8–9. Rollback is one `-e spark_llm_profile=fast`
   plus a detached converge (`spark-rollback:fast` = `4900c13edab9…`).
2. **HD-1210** in its own lane.
3. `../homelab-wt-20261027-1405` (`session/pkg-pin-window-20261027-1405`) belongs to another station —
   never `git worktree remove` it (O8).
4. Reads of the live engine from a spark-served seat are legal; the flip is not (rule 0 / O11).
