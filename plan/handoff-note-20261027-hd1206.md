# Handoff notes — HD-1206 v32 lineage (orchestrator session, 2026-10-27)

- `main` tip when the lanes were launched: `b577e723` (HD-1207 vault-ID fix landed from another station).
- Live children of the closing session (2 h each, checkpointed):
  - Lane D `9ee0843a` · wt `../homelab-wt-20261027-1620` · branch `session/v32-r3-guard-build-20261027-1620`:
    R3 ruled **A+** (step 14 becomes a post-state guard, applies nothing; GB10 compute_cap `12.1` vs the day-0
    `(10,3)` predicate), then census-clean → ONE detached build →
    `scripts/bench/spark-fp8-image-probe.py --image <tag> --skip-registry` → on `REACHABLE`, one commit setting
    `spark_vllm_ultrafast_v32_image` and adding `ultrafast-v32` to `spark_llm_fp8_kv_capable_images` → offline trio.
    No flip.
  - Lane E `a72f0f04` · wt `../homelab-wt-20261027-1705` · branch `session/v32-profile-nomenclature-20261027-1705`:
    profile-nomenclature memo — verify the day-0 base's vLLM version inside the image before any `v30` label;
    additive naming only (a live dial rename would break the rollback string `spark_llm_profile: fast`);
    author `fast-v32-bf16` (renders GATED while the pin is empty); price the six candidate arms incl.
    `reasoning-v32-bf16` / `reasoning-v32-fp8`.
- Parent merge order (O1): first lane FF-merged; second rebased inside its worktree and re-gated there; then the
  parent cleanup commit — `prompt.md` §2 spark item to the post-merge state, `todo-table.md` §B9/§B0 re-sync, mint
  the rows Lane E names (lanes do not mint), reseal with `check_handoff_size.py --reseal` and
  `check_backlog_prose.py --reseal`.
- Gates: the designed red is `check_secret_leak.py` in the HD-1181 class, all hits under
  `~/.pi/agent/sessions/**/*.jsonl`; a SKIP there is not a verdict.
- Engine baseline: `vllm-qwen-spark` Id `4adcf1166276cc59…`, `StartedAt 2026-10-18T03:36:16Z`, `RestartCount 0`,
  health 200; spark ~164 G free. Never prune build cache, never retag `iter6c|iter6d`, never touch
  `spark-rollback:*`.
- Open at handoff: HD-1206 stays open — R3, the build, the pin, then the flip and gates 0–7 then 8–9 in a
  non-spark-served owner window. The flip was NOT run.
- Next-session notes: `../homelab-wt-20261027-1405` (`session/pkg-pin-window-20261027-1405`) belongs to another
  station — leave it; never `git worktree remove` a worktree this session did not create (O8).
