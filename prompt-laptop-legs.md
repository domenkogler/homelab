# `prompt-laptop-legs.md` — Lane brief · the Win11 seat: FIM + vision, nothing else

> **Role:** dispatch note for **one** lane session on the laptop's serving legs. **The rows are the authority** for what is
> missing and how to do it — this file carries the contract, the order of work and the traps, nothing else:
> [todo.md](todo.md) **HD-474** (row ids as of `16177f19` — re-derive with `grep -c "^| HD-<id> " todo.md` before
> quoting one).
> **Linked from:** [todo-table.md](todo-table.md) §B0 · [todo.md](todo.md)

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O11) — read it once; it overrides README §4 and
CONVENTIONS §6 at the items it numbers and this brief deliberately restates none of them.

**Host + slots (O3):** the **Win11 seat**, provider-scoped `domenp14s` (`native_only: true` keeps it out of the WSL render —
both seats report the same hostname, which is why it is a flag and not a second host name). **This lane claims no converge
slot and runs no ansible**: the legs are a local runtime + two render files. ⛔ **Do not share a wave with a live pi-seat
lane** — `scripts/harness/pi/models-spec.yml` is the file both would edit, so `git worktree list` + `git log --oneline -3 --
scripts/harness/pi` before any render hunk. The owner hands are single-seat by definition: one hand on the laptop at a time.

**What this lane is not:** there is **no agent leg on this runtime** — the four `agent-*` profiles are out of the catalogue,
`client_context_window: 150016` is deleted, the context windows are pinned FIM **8 192** / vision **32 768**
(the `client_context_window` of each profile in `scripts/bench/laptop/profiles.yml`; mirrored as the two
`contextWindow` values of the `laptop-lmstudio` provider in `scripts/harness/pi/models-spec.yml`), and the slot
does **not** fall back to spark. The
ruling and its measurements are in [docs/hardware-workstation.md](docs/hardware-workstation.md) §Served leg and the retired leg
is logged in [docs/services-ai-rejected.md](docs/services-ai-rejected.md) — do not restate or re-decide it here.

**Read first:** [docs/hardware-workstation.md](docs/hardware-workstation.md) §Served leg ·
[docs/services-ai.md](docs/services-ai.md) #28 · [docs/services-ai-rejected.md](docs/services-ai-rejected.md) →
`scripts/bench/laptop/profiles.yml` (the dial) → [reports/hd474-laptop-leg/](reports/hd474-laptop-leg/README.md) for the raw
measurements behind the numbers you will re-take.

## Order of work

| # | Row | Do | Gate / trap |
|---|-----|----|-------------|
| 1 | **HD-474** | Two owner hands **on the Win11 seat**, in order: (1) `op signin`, then `python scripts\harness\render-pi-config.py --vendor pi --host Domen_P14s --check` — the render must carry exactly the vision + FIM rows and **no agent row**; (2) `powershell -File scripts\bench\laptop\win\lmstudio-llm.ps1 switch -Profile vision-qwen3vl-30b`, then `python scripts\bench\laptop-llm.py probe-client` | `probe-client` must **PASS, not SKIP** — a SKIP run taken from oldsrv is correct and proves nothing, and the same SKIP comes from a Windows interpreter run with a WSL working directory, so quote the interpreter and the cwd beside the verdict. Its residency half is load-bearing because the endpoint does **not** police the `model` field: with one leg resident, a request naming the other leg is answered by the resident one, so a stale row is silent, not loud. ⚠ Hostnames canonicalise (`Domen_P14s` == `domenp14s`). The FIM leg's **trigger latency** is measured and sits outside Continue's 150–400 ms budget above ~300–450 prompt tokens (`raw/100-fim-latency.txt`); what the row still owes is the owner's call on how much context the tab ships, not another measurement — `probe-fim` resolves the leg by its `insert` capability, not by the dial's name, and `probe-speed --ttft --prompt-file <real prose>` is the shape that measures it. While the call is open `fim-coder-3b` stays `certified: false` and the dial keeps `allow_uncertified: true` for that reason and no other |

## ⛔ Traps that cost a round

* **Crop, do not shrink.** Image tokens **saturate** (~4.1 k for the full frame and for a quarter of it alike; 1120 px → 937;
  a label close-up → 528), so downscaling a wide frame takes the detail away from the answer while keeping the cost.
* **The cache rule comes with the image:** the identical question again costs ~2 s, any *new* question re-pays the ~60 s prefill,
  because the text precedes the image in the message. A seam that asks one photo several things must put the image first or freeze
  the question.
* **Greedy agreement proves stability, not perception.** Two identical answers at `temperature 0` rule out sampling noise and
  nothing else; confirm a read against a second instrument (a crop, or the repo's own label photo).
* **Weight files**: LM Studio's downloader auto-pulls the **mmproj-F32** and `lms get <file-url>` fetches the whole repo — always
  fetch exactly the two files (`huggingface_hub` `allow_patterns`), and use **mmproj-BF16**, never F32.
* **Do not re-run the max-side-length probe class**: a frame wider than ~1120 px crashes the engine (exit
  `3221226505`) — that is why the leg is Qwen3-VL. Re-running it costs an engine crash, not information.
* ⛔ `networkingMode=mirrored` is **owner-rejected** — WSL2 stays `Nat` on purpose, so `127.0.0.1` inside the guest is the guest
  and the seat for local models is pi.dev on Win11. Never "fix" the loopback by changing the WSL network mode.
* The runtime is pinned in the **dial, not in `versions.yml`** (LM Studio has no Renovate datasource there):
  `runtime.version` and `runtime.lms_cli_commit` in `scripts/bench/laptop/profiles.yml`. Quote `runtime.version` from the
  dial; never describe behaviour from an unpinned install, and never let an auto-update make the dial describe something other
  than what the seat runs. `lms load` has no flag for `kv_cache_type`/`flash_attention`, so those dial fields are budget
  arithmetic until something reads the running load.
* `scripts/bench/laptop-llm.py gate --self-test` is the offline canary and is the only part of the tool that can run away from the seat
  — say which of `gate` / `probe-*` you actually ran.
* **A `contextWindow` in `scripts/harness/pi/models-spec.yml` and a `num_ctx` in the dial that ship in DIFFERENT commits 400s
  mid-session.** Nothing in the stack catches that drift except `probe-client`, so a window change is one commit touching both
  files — and that is also why this brief names the two keys rather than their line numbers.

## Owns / never touches

**Owns:** `scripts/bench/laptop-llm.py`, `scripts/bench/laptop/**`, `scripts/bench/laptop/win/lmstudio-llm.ps1`, the `laptop-lmstudio` provider and
its `hosts:` / `native_only:` scoping in `scripts/harness/render-pi-config.py` and `scripts/harness/pi/models-spec.yml`,
`docs/hardware-workstation.md`, the laptop-leg sections of `docs/services-ai.md` and `docs/services-ai-rejected.md`,
`reports/hd474-laptop-leg/**` (new evidence files only — never rewrite a dated record's prose), and your own `todo.md` rows.
**Never:** `prompt.md` / `todo-table.md` (O2) or another brief's rows; the spark engine, its profiles and bench (the spark lane —
this lane has no spark leg and no spark fallback); the pi harness render planes other than the two provider rows named above;
the LiteLLM gateway and its keys; the seat/cockpit grants and tailnet policy; `roles/monitoring/**`; anything under `IaC/` —
this lane runs no converge; the frozen archives and generated `*-generated.md`.

## Acceptance

Every item returns `PASS` / `FAIL` / `BLOCKED` / `PARKED` + the number + the evidence path; a claim with no path counts as
not run. Concretely: the render `--check` output on the seat showing exactly the vision + FIM rows and no agent row · `probe-client`
**PASS** (never SKIP) with the residency half quoted · the FIM trigger latency stated against Continue's 150–400 ms budget at
real prompt sizes, not at a toy prompt · `gate --self-test` green and quoted, with the tool form
(`gate` vs `probe-*`) named · rows trimmed to their tails or deleted, no history in the row · `bash scripts/validate-all.sh` green
**in this worktree** → **stop**.
