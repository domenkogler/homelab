# fast-v33 — first boot of the rc3 artifact (`sha256:023a9f57…`)

The artifact `spark_vllm_fast_v33_image` pins booted on this box for the first time, both arms, eager.
Nothing here certifies either arm: gibberish or a regression would be a boot-time fact, and certification is
a scheduled window. Both arms remain `certified: false` and only `spark_llm_allow_uncertified=true` opens the
boot — the single refusal either one carries.

Every number below is a log line or an engine line. Where a value has no line behind it, it is marked
NOT MEASURED rather than computed.

## The two boots

| | `fast-v33-bf16` (control) | `fast-v33-fp8` (capacity) |
|---|---|---|
| image (engine's own) | `sha256:023a9f57…` — the pin | `sha256:023a9f57…` — the pin |
| engine `Id` | `eb87fdb296177740…` | `272b807d0996e6d9…` |
| `StartedAt` | `2026-11-07T08:02:55.13560031Z` | `2026-11-07T08:18:35.487225375Z` |
| `RestartCount` | **0** | **0** |
| health | healthy | healthy |
| `kv_cache_dtype` | `auto` (bf16) | `fp8` |
| `GPU KV cache size` | `631,087 tokens … 2.41x` | `1,080,425 tokens … 4.12x` |
| `Model loading took` | `68.26 GiB memory and 81.341540 seconds` | `68.26 GiB memory and 70.608703 seconds` |
| attention block size | `1600 tokens` | `3200 tokens` |
| init engine | `50.44 s` | `45.71 s` |
| server up | `08:05:59` (03:04 after `StartedAt`) | `08:21:04` (02:29 after `StartedAt`) |

Boot logs: [`boot-bf16.log`](boot-bf16.log), [`boot-fp8.log`](boot-fp8.log).

The kernel now speaks both surfaces the earlier artifacts could not: `vllm 0.33.0`, and the container
carries `vllm/models/qwen4_exp` — the module the day-0 tree did not have.

## The KV line is the one acceptance that does NOT match

Step 5's acceptance was that the control print `fast`'s line. It does not:

| | `GPU KV cache size` | concurrency | attention block | pool |
|---|---|---|---|---|
| `fast` (live, 4900c13e) | `644,732 tokens` | `2.46x` | 1600 tokens | `20000000000` B |
| `fast-v33-bf16` | `631,087 tokens` | `2.41x` | 1600 tokens | `20000000000` B |
| `fast-v33-fp8` | `1,080,425 tokens` | `4.12x` | 3200 tokens | `20000000000` B |

Same pool (`reserved 18.63 GiB memory for KV Cache` in both logs), same block size on the control, so the
13,645-token gap on bf16 is a per-page byte difference of the v0.33 engine (~31,691 B/token effective
against the catalogue's `spark_llm_kv_bytes_per_token` of 31,027; the probe's projection still prints
`644,599` because it reads that constant). What this is NOT: a moved pool, a moved ceiling or a different
weights set — those are identical. It is the engine build, which is the only variable these arms change, so
the finding belongs against the *falsification* gate-2/7 note the arm's own `uncertified_reason` (b) already
carries. It is recorded here and not interpreted further.

The fp8 arm's 4.12× is the first measurement of any fp8 KV line on this box; `docs/spark-llm-profiles.md`
had only the projection for it.

## The acceptance that DID match

* `RestartCount=0` on both arms after the 30-minute read, both healthy.
* No draft-side `TypeError`, no `Detected some but not all shards` `ValueError` — the two failures that
  killed `883128e0` and `1df406bc`. Both fixes are in the artifact and both now stand up.
* Boot time, this lane's headline claim: **03:04** (bf16) and **02:29** (fp8) from `StartedAt` to
  `Starting vLLM server`. `Model loading` is 81.3 s / 70.6 s against `fast`'s 527–547 s on the same
  weights — the v0.33 loader, not the checkpoint, is what moved.

## Quick tier — `spark-llm-probe.py all --profile <arm>`

Both arms, 6/6:

| leg | bf16 | fp8 |
|---|---|---|
| `health` | PASS 200 | PASS 200 |
| `auth+completion` | PASS off=200 on=200 | PASS off=200 on=200 |
| thinking OFF | PASS reasoning_len=0 content_len=213 | PASS reasoning_len=0 content_len=213 |
| thinking ON | PASS reasoning_len=174 | PASS reasoning_len=174 |
| `ctx 262144` | PASS prompt=258863, 24 completion, **100.0 s** | PASS prompt=258863, 24 completion, **97.2 s** |
| `concurrency 8` | PASS 8/8 wall=**4.2 s**, lat 3.7/4.1/4.2 | PASS 8/8 wall=**3.1 s**, lat 2.4/2.6/3.1 |

The `ctx` and `concurrent` legs are timed, and were taken from a seat whose model is not spark
(`PI_PROVIDER=entrim`), per the gate README's rule 0.

**Determinism leg** (identical prompt twice, first-token logprobs compared, `temperature=0`, `seed=1234`):
bf16 `' L' -0.4588409662246704` twice; fp8 `' L' -0.5236154198646545` twice. Both byte-equal, and the
five-entry `top_logprobs` lists are identical within each arm. The two arms differ from each other at the
first token (`-0.4588` vs `-0.5236`) — expected between a bf16 and an fp8 KV path, and it is a single
observation, not an accuracy verdict.

## `runtime_dispatch.py` (HD-1206 step 2) — PLAN, all three shapes

Run inside the running fp8 container, since `vllm.models.qwen4_exp` exists in this engine and did not in the
older one:

```
LEG1 capability  = DeviceCapability(major=12, minor=1)   measured
LEG4 is_available = True                                  measured
(1280, 2560): PLAN   _runtime_ok True   maxdiff vs F.linear 0.000000  allclose True
(640,  2560): PLAN   _runtime_ok True   maxdiff vs F.linear 0.000000  allclose True
(1,    2560): PLAN   _runtime_ok True   maxdiff vs F.linear 0.000000  allclose True
```

`_runtime_ok` is now OBSERVED rather than inferred, which is the gap `todo.md` recorded against it.

## Pool ladder — NOT RUN, on the owner's instruction

The ladder exists to answer "what pool still boots", and the question it answers has no cheap rung upward:
`pool_ceiling_bytes` is `20000000000` on both arms, identical to the pool they booted, and the profile's
own host-floor arithmetic closes exactly there — `fixed_cost 92,130,000,000 + pool 20,000,000,000 =
112,130,000,000` against `device_hold_ceiling_bytes 112,700,000,000` leaves **570,000,000 B**. The next
2 GB step up would need `114,130,000,000`, i.e. 1.43 GB through a ceiling that is the certified part. So the
arms are AT the ceiling and a ladder can only go down, which the owner declined: both arms boot at 20 GB and
neither errored.

One step was taken before that instruction arrived and is kept as a datapoint, not as a rung:

| pool | engine line |
|---|---|
| `18000000000` B | `GPU KV cache size: 567,285 tokens … 2.16x`, `reserved 16.76 GiB`, `RestartCount=0`, engine `c1e351a4…` |

## Capture attempt — BLOCKED, pending an owner decision

The v0.33 image's hook registers `vllm::ple_mmap_lookup_ids`, and in eager mode the engine reports
`'splitting_ops': []`. Flipping `enforce_eager: false` alone would capture with **no splitting-ops list**,
which is the illegal shape — a capture that names no op is not the shape the hook needs. The list that
names the op arrives only through `lineage_env: blazux`, which also swaps the entire env block; neither arm
sets it (`docker-compose.yml.j2` adds a splitting list only via `cudagraph_piecewise` or `lineage_env:
blazux`). That is an owner decision, not a flip-time improvisation, so both arms were booted eager and no
capture was attempted.

## End state

`fast-v33-fp8` is serving: engine `272b807d0996e6d9…`, image `sha256:023a9f57…` (the pin), `RestartCount=0`,
healthy, `20000000000` B pool. `/` free: **110,043,045,888 B** — under the 150 GB profile floor, which is
why every `os`-rooted converge in this window carried `-e spark_llm_os_free_gate_exempt=true`. Rollback
insurance untouched: `spark-rollback:fast` → `sha256:4900c13e…`, nas
`/tank/data/host-images/spark/spark-fast-4900c13e.tar.zst`.

## What the certification window still owes

1. The 13,645-token bf16 KV gap against `fast` — decide whether it is accepted as the v0.33 engine's page
   accounting or a regression, and re-derive `spark_llm_kv_bytes_per_token` for the v33 lineage if it is
   the former. The fp8 arm's projections inherit whichever answer.
2. The accuracy battery and the needle at depth on fp8 (the arm that would serve) — the quick tier is
   liveness and timing, not quality.
3. A capture decision: whether these arms take `lineage_env: blazux` (and therefore its whole env block) or
   stay eager with the splitting-ops list authored some other way.
4. The host-floor re-derive for both arms: `fixed_cost_bytes` is explicitly inherited from `fast` and was
   never re-measured on a re-anchored patch stack.
5. `certified: false` / `certified_evidence: ""` are untouched by this window, by design.
