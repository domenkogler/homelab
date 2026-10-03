# HD-489 — T80 drafter conversion: upstream build workaround

The tier-3 `v16b*` arms need `Qwen3.8-Flash-Next-W4A16-AutoRound-hybrid-mtpdense-g32`
(+4.8 GiB drafter side modules) which `spark-ultrafast-build`'s
`Convert the T80 drafter directory` task produces by running upstream
`recipe/build/model/build.sh --run`.

**Upstream defect found:** `build.sh` mounts its own source dir `-v $here:/work:ro`
(read-only) and runs the self-test `test_rtn_int4_gptq.py` with CWD `/work`; that test
writes `_iter4_st_test.safetensors` (its hardcoded relative tmp, `test_rtn_int4_gptq.py:497`)
into CWD → `OSError: [Errno 30] Read-only file system`. The container image's own `/work`
default is `drwxrwxr-x` (writable) — the `:ro` mount overrides it. Upstream's own test
cannot pass on their own mount.

**Workaround applied (no pinned-code change):** ran the same docker steps manually with
`-v $here:/work` (rw, matching the image default). All three CPU self-tests passed, the
drafter build ran to completion (`9 converted side modules, 68 shards, 340 copied tensors
byte-identical, verify OK`), and upstream's own script wrote
`dense-mtp-build-report.json` (the marker `spark-ultrafast-build` checks).

**Candidate upstream fix (not applied here):** drop the `:ro` from build.sh's `/work` mount,
or make the test write to `$TMPDIR`. If this repo ever re-pins a newer upstream commit,
re-check whether they fixed it.
