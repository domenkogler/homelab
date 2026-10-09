# `prompt-laptop-legs.md` — Lane brief · the Win11 seat: FIM + vision, nothing else

> **Role:** dispatch note for **one** lane session on the laptop's serving legs. **The rows are the authority** for what is
> missing and how to do it — this file carries the contract, the order of work and the traps, nothing else:
> [todo.md](todo.md) **HD-474 · HD-476** (row ids as of `16177f19` — re-derive with `grep -c "^| HD-<id> " todo.md` before
> quoting one).
> **Linked from:** [todo-table.md](todo-table.md) §B0 · [todo.md](todo.md)

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O9) — read it once; it overrides README §4 and
CONVENTIONS §6 at the items it numbers and this brief deliberately restates none of them.

**Host + slots (O3):** the **Win11 seat**, provider-scoped `domenp14s` (`native_only: true` keeps it out of the WSL render —
both seats report the same hostname, which is why it is a flag and not a second host name). **This lane claims no converge
slot and runs no ansible**: the legs are a local runtime + two render files. ⛔ **Do not share a wave with a live pi-seat
lane** — `scripts/pi-config/models-spec.yml` is the file both would edit, so `git worktree list` + `git log --oneline -3 --
scripts/pi-config` before any render hunk. The owner hands are single-seat by definition: one hand on the laptop at a time.

**What this lane is not:** there is **no agent leg on this runtime** — the four `agent-*` profiles are out of the catalogue,
`client_context_window: 150016` is deleted, the context windows are pinned FIM **8 192** / vision **32 768**
(`scripts/laptop-llm/profiles.yml:294`, `:303` and `:256`; mirrored in `scripts/pi-config/models-spec.yml:196`, `:208` for the
`laptop-lmstudio` provider at `scripts/pi-config/models-spec.yml:152`), and the slot does **not** fall back to spark. The
ruling and its measurements are in [docs/hardware-workstation.md](docs/hardware-workstation.md) §Served leg and the retired leg
is logged in [docs/services-ai-rejected.md](docs/services-ai-rejected.md) — do not restate or re-decide it here.

**Read first:** [docs/hardware-workstation.md](docs/hardware-workstation.md) §Served leg ·
[docs/services-ai.md](docs/services-ai.md) #28 · [docs/services-ai-rejected.md](docs/services-ai-rejected.md) →
`scripts/laptop-llm/profiles.yml` (the dial) → [reports/hd474-laptop-leg/](reports/hd474-laptop-leg/README.md) for the raw
measurements behind the numbers you will re-take.

## Order of work

| # | Row | Do | Gate / trap |
|---|-----|----|-------------|
| 1 | **HD-474** | Two owner hands **on the Win11 seat**, in order: (1) `op signin`, then `python scripts\render-pi-config.py pi --host Domen_P14s --check` — the render must carry exactly the vision + FIM rows and **no agent row**; (2) `lmstudio-llm.ps1 switch -Profile vision-qwen3vl-30b`, then `python scripts\laptop-llm.py probe-client` | `probe-client` must **PASS, not SKIP** — a SKIP run taken from oldsrv is correct and proves nothing. Its residency half is load-bearing because the endpoint does **not** police the `model` field: with one leg resident, a request naming the other leg is answered by the resident one, so a stale row is silent, not loud. ⚠ Hostnames canonicalise (`Domen_P14s` == `domenp14s`). ⏳ AI-side and still unmeasured: the FIM leg's **trigger latency** inside Continue's 150–400 ms budget — `probe-fim` resolves that leg by its `insert` capability, not by the dial's name |
| 2 | **HD-476** | Take the one number this leg owes: exercise the 32k window with image tokens **actually resident** in the KV — `python scripts\laptop-llm.py probe-vision --image <the 8160x6120 rack photo> --expect CAT6` against the loaded leg, reading the PDH **dedicated-memory** counter through the prefill | `--expect CAT6` is a whole-frame string the model supplies reliably; the switch **part number** is not (a wide-frame misread, since pixel allocation, not sight). The declared 23.51 GiB budget is header arithmetic plus a text-only 32k load today — ~4 k image tokens land in the same KV, so without this the budget is unproven |

## ⛔ Traps that cost a round (re-grounded at this `HEAD`)

* **Crop, do not shrink.** Image tokens **saturate** (~4.1 k for the full frame and for a quarter of it alike; 1120 px → 937;
  a label close-up → 528), so downscaling a wide frame takes the detail away from the answer while keeping the cost.
* **The cache rule comes with the image:** the identical question again costs ~2 s, any *new* question re-pays the ~60 s prefill,
  because the text precedes the image in the message. A seam that asks one photo several things must put the image first or freeze
  the question.
* **Greedy agreement proves stability, not perception.** Two identical answers at `temperature 0` rule out sampling noise and
  nothing else; confirm a read against a second instrument (a crop, or the repo's own label photo).
* **Weight files**: LM Studio's downloader auto-pulls the **mmproj-F32** and `lms get <file-url>` fetches the whole repo — always
  fetch exactly the two files (`huggingface_hub` `allow_patterns`), and use **mmproj-BF16**, never F32.
* **Do not re-run the class of probe that produced the Gemma finding**: the max-side-length crash (>~1120 px, engine exit
  `3221226505`) is measured twice and is the reason the leg is Qwen3-VL. Re-running it costs an engine crash, not information.
* ⛔ `networkingMode=mirrored` is **owner-rejected** — WSL2 stays `Nat` on purpose, so `127.0.0.1` inside the guest is the guest
  and the seat for local models is pi.dev on Win11. Never "fix" the loopback by changing the WSL network mode.
* The runtime is pinned in the **dial, not in `versions.yml`** (LM Studio has no Renovate datasource there): `version:
  "0.4.25+1"` at `scripts/laptop-llm/profiles.yml:75` and `lms_cli_commit: "69d945a"` at `:76`. Quote `runtime.version` from the
  dial; never describe behaviour from an unpinned install, and never let an auto-update make the dial describe something other
  than what the seat runs.
* `scripts/laptop-llm.py gate --self-test` is the offline canary and is the only part of the tool that can run away from the seat
  — say which of `gate` / `probe-*` you actually ran.

## Owns / never touches

**Owns:** `scripts/laptop-llm.py`, `scripts/laptop-llm/**`, `scripts/win/lmstudio-llm.ps1`, the `laptop-lmstudio` provider and
its `hosts:` / `native_only:` scoping in `scripts/render-pi-config.py` and `scripts/pi-config/models-spec.yml`,
`docs/hardware-workstation.md`, the laptop-leg sections of `docs/services-ai.md` and `docs/services-ai-rejected.md`,
`reports/hd474-laptop-leg/**` (new evidence files only — never rewrite a dated record's prose), and your own `todo.md` rows.
**Never:** `prompt.md` / `todo-table.md` (O2) or another brief's rows; the spark engine, its profiles and bench (the spark lane —
this lane has no spark leg and no spark fallback); the pi harness render planes other than the two provider rows named above;
the LiteLLM gateway and its keys; the seat/cockpit grants and tailnet policy; `roles/monitoring/**`; anything under `IaC/` —
this lane runs no converge; the frozen archives and generated `*-generated.md`.

## Acceptance

Every item returns `PASS` / `FAIL` / `BLOCKED` / `PARKED` + the number + the evidence path; a claim with no path counts as
not run. Concretely: the render `--check` output on the seat showing exactly the vision + FIM rows and no agent row · `probe-client`
**PASS** (never SKIP) with the residency half quoted · the FIM trigger latency measured against Continue's 150–400 ms budget, or
`BLOCKED` naming the seam that hides it · `probe-vision --expect CAT6` with the PDH dedicated-memory counter read during the
prefill, so the 32k + image budget is exercised rather than asserted · `gate --self-test` green and quoted, with the tool form
(`gate` vs `probe-*`) named · rows trimmed to their tails or deleted, no history in the row · `bash scripts/validate-all.sh` green
**in this worktree** → **stop**.
