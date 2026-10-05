# `prompt-lmstudio.md` — Lane brief · the laptop's two serving legs (HD-474 · HD-476 · HD-486) — runs on **Win11**

> **Role:** dispatch note for **one** session on the laptop. **The rows are the authority** for what is missing and how to do
> it: [todo.md](todo.md) HD-474 · HD-476 · HD-486. The measurement record + every durable number and tool trap is
> [docs/hardware-workstation.md](docs/hardware-workstation.md) §Served leg + the dial
> [`scripts/laptop-llm/profiles.yml`](scripts/laptop-llm/profiles.yml), which *is* the spec. This file carries the contract,
> the order of work and the non-negotiables — nothing else.
> **Entry:** the owner says **"read prompt-lmstudio and run it"** — you are the operator, **on the laptop, in Windows**
> (`pi.dev` on Win11), because that is where the engine lives.
> **Linked from:** [prompt.md](prompt.md) §3 · [todo.md](todo.md) · [docs/hardware-workstation.md](docs/hardware-workstation.md)

**Contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O8). One session, one branch, one worktree
(`D:\source\domenkogler\homelab-wt-hd474`, branch `session/hd474-win11-certify-<n>`), `git worktree remove` at the end.
Never edit `prompt.md` / `todo-table.md` (O2); edit **only your own `todo.md` rows**. Owner gate → **park and continue** (O4).
**No Ansible converge here** — this lane has no shared host and can run beside the spark/oldsrv lanes.

**Rule 0, live right now:** if your own `pi.dev` session is served by `laptop-lmstudio` (`active: agent-gemma-26b` in the dial
and the model resident), you may take **no timed number** — `probe-speed`, `probe-ctx`, TTFT, any tok/s. Read-only state,
`lms ps`, `/v1/models` and `gate` are fine. Hand timed legs to the owner or run the session off a remote model, and say which.

**Read first:** [README.md](README.md) §0 + §1 → [CONVENTIONS.md](CONVENTIONS.md) §6/§7/§15 →
[docs/hardware-workstation.md](docs/hardware-workstation.md) §Served leg + §Memory & residency (incl. the **tool traps**) →
[`scripts/laptop-llm/profiles.yml`](scripts/laptop-llm/profiles.yml) top to bottom → the three rows →
[`reports/hd474-laptop-leg/`](reports/hd474-laptop-leg/) `raw/00-SESSION-STATE.md`.

## Order of work

| # | Row | Do | Note |
|---|-----|----|------|
| 1 | **HD-486** | Take the two numbers that `certified: true` on the agent leg is waiting for: **a recall needle at ≥ 90 % of 150 016 tokens, 3/3**, and **the cold-prefill ladder at the new window** | The 28 984-token pass was 92 % of the *old* window and proves nothing at 135 k. Unattended ladder work: `python -X utf8 reports\hd474-laptop-leg\raw\hd477_run.py [startPhase]` (phase bands, appends per phase, edits no config). **Budget real time — prefill is the wall, not memory**, and it is erratic (same 20 816-token prompt: 359 / 899 / 277 s across three loads). If the needle comes back wrong, `client_context_window` comes **down**, not up |
| 2 | **HD-476** | Exercise the vision leg's declared budget **with an image resident in the KV of a 32k window** | That 23.51 GiB has only ever been arithmetic plus a text-only 32k load. One load, one full-resolution photo, PDH dedicated-memory reading — the ~4 k image tokens land in the same KV |
| 3 | **HD-474** | ⏳ **owner hands only** (the lane is merged): `op signin` → `render-pi-config.py pi --host Domen_P14s --check` → `laptop-llm.py probe-client` must **PASS, not SKIP** | The row carries the four steps and why the residency check is load-bearing. `networkingMode=mirrored` is **rejected** — never "fix" a WSL probe by reconfiguring the guest |

## Non-negotiables

* **Never edit an assert, a gate invariant or a budget constant to make it pass** — record the measurement.
  `held_floor_bytes` moves only from a **measured** PDH dedicated-memory reading.
* **One model resident.** `lms unload --all` before every load; two residents on one carve is the documented amdgpu
  failure mode, and after a 32k vision leg there is no room for a third.
* **`:1234` stays unexposed** and no firewall rule is added as a side effect — `networkInterface: 0.0.0.0` is an **owner
  decision still outstanding**. Secrets: `~\.lmstudio\settings.json` holds `hfDownloadToken` / `useHFProxy` — never
  committed, merged only by the applier (which backs up first); `apiKey: lmstudio-local` is a placeholder **because the
  listener has no auth**. **No silent downloads** — fetch deliberately and verify byte sizes against the Hub.
* Windows output discipline (`PYTHONUTF8=1`, ANSI stripping, `.ps1` saved with a BOM for PS 5.1) already lives in the
  driver and `scripts/win/lmstudio-llm.ps1` — do not "tidy" it away.

## Offline checks (Windows has no Ansible — run the native subset)

```powershell
python scripts\laptop-llm.py gate --self-test        # must be 13/13
python scripts\check_secrets.py
python scripts\check_placeholders.py
python -m py_compile scripts\laptop-llm.py scripts\render-pi-config.py
```

Full `bash scripts/validate-all.sh` runs **in a WSL worktree of the same branch** — a Windows-created worktree's `.git`
pointer is unreadable from WSL git, so create the worktree in WSL if you need both sides. If bash/ansible are unavailable,
say so and let the owner decide; never call the lane green on the subset.

## Report

Append to [`reports/hd474-laptop-leg/README.md`](reports/hd474-laptop-leg/README.md) as **measurements, not narrative**:
engine + `llmster` versions, every probe command with verbatim output, PDH dedicated-memory figures per load, tok/s + TTFT
with the prompt shape and cache state, the image-size boundary table, and the OCR corroboration against
[docs/network-rack.md](docs/network-rack.md). Keep `raw/00-SESSION-STATE.md` current — the next session starts blind. Then
sweep whatever the run made stale (§Served leg, the budget table, the profile's `vision_caveat`, decision #28 in
[docs/services-ai.md](docs/services-ai.md), and the three rows), sign the commit, **stop**.

**Rollback** is boring, which is the point: `lms unload --all`, `active: fim-coder-3b`, or `lms server stop`.
