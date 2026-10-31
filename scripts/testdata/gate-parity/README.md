# `scripts/testdata/gate-parity/` — the planted legs the parity runner is proved against

> **Role:** fixtures for [`../../bench/win/gate-parity.sh`](../../bench/win/gate-parity.sh) `--self-test`.
> A fixture tree, so `gate/check_script_layout.py` keeps it out of the registry table.
> **Linked from:** that runner's `--self-test` and its registry row.

Each file is a LEG, not a test: it prints verdict lines and an exit code the way a wrapped gate leg
does, and each one plants exactly ONE difference between the native answer and the engine answer, so the
runner is graded against a known difference rather than against the luck of a real leg. The guest half of
every difference is taken when `HL_PARITY_GUEST` is set, which the self-test's stub door sets and the
runner itself clears on the native side — so a flavour cannot be taken by accident in a real run.

| File | The planted difference | What the runner must answer |
|---|---|---|
| `loses-an-arm.sh` | one arm prints nothing on the engine instead of `SKIP` | rc 1, both arm counts named |
| `path-spelling.sh` | the same three arms, spelled the way each seat spells a path | rc 0 |
| `cannot-run.sh` | the engine side exits 2 with one `SKIP` (the shape `testdata/rsync-max-delete/run.sh` uses for a tool this seat lacks) | rc 2, no parity word |
| `no-tool-here.sh` | BOTH sides exit 2 | rc 2 |
| `silent.sh` | a side that produced no bytes and exited 0 | rc 2 |
| `no-verdict-words.sh` | rc 0 and three lines of prose that carry no verdict word | rc 2, with the recognizer printed so the reader EXTENDS it instead of muting the leg |
| `exit-codes-differ.sh` | three identical arms on both sides, the engine side exits 1 — only the rc moves | rc 1, both exit codes named (`native 0, engine 1`); the rc rule has no other witness, so deleting it turns THIS fixture green |
| `portable.sh` | nothing — it spells its own tree and temp paths as wherever it runs | rc 0 across the real door |
