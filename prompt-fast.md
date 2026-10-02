# Brief: HD-489 — the ultra-fast profile funnel (upstream v16b → our dial)

> **Rule 0 first.** Do not run timed legs with a model served by the engine under test.
> This session ran on a pi served by `spark/qwen3.8-flash-next`, so it could author the
> funnel and prove it OFFLINE — and it did. Every minute number in this lane comes from a
> client OUTSIDE the loop: the WSL runner (`http://spark.kogler.si:8000/v1`), or
> `scripts/llm_serving_bench.py` on a box that is not the engine. See
> [docs/services-ai.md](docs/services-ai.md) §0.

## What this lane is

Integrate the upstream [dime-online/qwen3.8-Flash-DGX-UltraFast](https://github.com/dime-online/qwen3.8-Flash-DGX-UltraFast)
v16b recipe (Apache-2.0, pinned at `0c391a3`) as **candidate profiles on our dial** — not as
a fork, not as a shadow stack. It is the single largest speed claim ever made against this
box (+15 % decode vs the base image, +40 % against an earlier upstream, 486k in, 246 ms to
first character, 256k window, `seqs=8`, `gpu_mem=0.01`), and the first claim of that size
that arrives with a pinned digest, an md5-gated build and a licence we can ship.

The funnel is 16 profiles: 4 already certified (untouched), 12 arms. The dial is still
**one var** (`spark_llm_profile`), still behind the same gate, still
[docs/spark-llm-profiles.md](docs/spark-llm-profiles.md).

## What is already done (the offline half — do not re-do it)

| Deliverable | State |
|---|---|
| 12 candidate arms in `spark_llm_profiles` | ✅ authored, `certified: false` |
| Profile → image / partition / PLE mechanism by NAME | ✅ `_x` anchor + per-arm overrides |
| Template composes those names into paths | ✅ + `scripts/spark-llm-render-matrix.py` renders all 16 offline |
| Gate: image pin, coordinates, PLE-mechanism exclusivity, placeholder refusal, root free-space | ✅ `roles/spark-llm-profile`, canaried in `scripts/check_spark_llm_gate.py` |
| Artifacts: `repo-root` / `asset` / `built` kinds, revision pins, sha256 + line-count checks | ✅ `roles/spark-artifacts` |
| Upstream build + T80 drafter conversion | ✅ `roles/spark-ultrafast-build` (opt-in, `--tags spark-ultrafast-build`) |
| Disk decision | ✅ **nothing deleted.** Second root: `/` has 345 G (measured 2026-10-02) vs XFS 185 G; upstream arms stage under `/opt/homelab/models`, XFS keeps its 505 GB + the two candidates. RadixArk stays. |
| Gate green | ✅ `validate-all` including ansible `--syntax-check` |

**Nothing was booted, built, or downloaded.** The `ultrafast` image pin is empty ON PURPOSE;
`roles/spark-llm-profile` refuses those profiles until a human records the built ID.

## The order of work (each step is its own commit; `todo.md` is the queue)

1. **Staging pull** — `--tags spark-artifacts` in an artifact window, with
   `spark_llm_profile_skip_artifact_check: true`: the AR-hybrid checkpoint (~130 GB) and the
   FP8 PLE table (~4 GB) into `/opt/homelab/models`. Verify the table's `.hf-staged` names
   the pinned revision.
2. **Build** — `spark_ultrafast_build: true` + `--tags spark-ultrafast-build`. Upstream's
   builder refuses itself unless 11 md5s and 2 sha256s match; the build runs `--network none`.
   **It then FAILS on purpose** and prints the image ID → record it in
   `group_vars/all/versions.yml` in its own commit (CONVENTIONS §7: no lane pins itself by
   accident). Then convert the drafter (`recipe/build/model/build.sh --run`, no GPU).
3. **Author `v16b-pin`'s substring** — the `CHANGEME` in `never_evict_prompt` is the mark of
   a human decision, not a bug: pick a literal substring of the harness system prompt
   (`scripts/pi-config/`), and say in the commit what fraction of the pool it can pin
   (`--never-evict-kv-cache-max-fraction` is a fraction OF THE POOL).
4. **Legs** — tier 1 first (`u1-patch`, `u2-blk`, `u3-s8` — AWQ weights, already staged, so
   one build and no download separates them from the certified lane), then tier 2 (`ar-*`),
   then tier 3 (`v16b*`). Each leg: `scripts/llm_serving_bench.py` +
   `spark/llm-profiles/acceptance/`, and the leg log must record **per-pid GPU memory at
   rest** for the seqs=8/piecewise arms (§6.2: oversized capture strands memory in the one
   pool; the engine's own `Available KV cache memory` line is authoritative).
5. **Fidelity gates before any speed claim** — Slovenian accepted-length (the draft
   vocabulary is English/code weighted — upstream says so), tool-calling XML, reasoning
   surface per §1.1. A decode win that fails the Slovenian leg is not a win.
6. **Converge** — only when a winner is declared; then the §5 orphan-container question
   applies (image changed ⇒ `docker rm -f vllm-engine`, never `--force-recreate`).

## Hard rules this lane must not break

* `image:` names a **pin**, never a tag. The build tag is a mutable local alias; the profiles
  serve the ID. Empty pin = the profile is refused, and that is the designed state.
* The four client anchors do not move (container `vllm-engine`, port `:8000`, served id
  `spark/qwen3.8-flash-next`, token name). The arms keep `qwen3_coder` for exactly that
  reason — upstream's `qwen3_xml` is a **third leg**, not a default.
* `fp8` KV stays false and `graded` stays `blocked`: upstream runs `--kv-cache-dtype auto`.
  Its `gpu_mem=0.01` is not evidence for fp8; it is evidence its PLE table is no longer in
  the CUDA pool. Say that in any report that quotes the number.
* No profile may claim `ple_mmap` and `ple_overlay` at once (they fight over the same
  `ple_layer.py`), and no arm ships without its PLE table mounted where its env says.
* Retire by measurement, not by affection: arms that lose get deleted in a commit that
  names what beat them. Keepers become `certified: true` only after
  `spark/llm-profiles/acceptance/` passes on the box.

## Definition of done

Two or three profiles survive, one of them `certified: true` and re-proven end-to-end
(pi → engine), the rest deleted, and [docs/hardware-spark.md](docs/hardware-spark.md)
§LLM serving profiles + [docs/services-ai.md](docs/services-ai.md) §9 re-measured against
the survivor — plus a paragraph in `docs/services-ai-rejected.md` for every arm that lost
and the number that killed it.
