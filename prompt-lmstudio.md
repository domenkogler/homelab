# `prompt-lmstudio.md` — Lane brief · certify the laptop's two serving legs (HD-474 / HD-476 / HD-486) · runs on **Win11**

> **STATUS 2026-09-30, overnight run — lane closed on the GPU side.** Worktree `D:\source\domenkogler\homelab-wt-hd474`, branch `session/hd474-win11-certify-2`, **nothing committed** (the owner asked for the worktree to be left for review). Both legs are `certified: true`, `gate` is green unaided (13 invariants, 13/13 canaries fire), `probe-client` PASSes against a live server, recall passed at 28 984 tokens, and the three prompt shapes are measured. Report: [`reports/hd474-laptop-leg/README.md`](reports/hd474-laptop-leg/README.md). Three claims **in this brief** did not survive the box and are corrected below: §0's "the gate list **is** the task list" (a green gate coexisted with a client audit that had never run), §1's `--host DomenP14s` (the box reports `Domen_P14s`), and §2.B's "`probe-tools` already passes" (it passed for the harness, not for the profile flag).

> **Entry:** the owner says **"read prompt-lmstudio and run it"** — you are the operator, running
> **on the laptop, in Windows** (`pi.dev` on Win11), because that is where the engine lives.
> The catalogue, the arithmetic, the gate, the applier and the client contract are merged
> (`7f77042`) **and the runtime is now pinned and booted**. What is left: finish the measurement set,
> land the **two-leg split**, wire the client, and merge — or report exactly where it stopped.
>
> **Read first, in this order:** this file §0 → §1 (the overnight job that may still be running) →
> [README.md](README.md) §0 + §1 → [CONVENTIONS.md](CONVENTIONS.md) §6 (secrets) / §7 (pins) / §15 (SSOT) →
> [docs/hardware-workstation.md](docs/hardware-workstation.md) §Served leg + §Memory & residency →
> [scripts/laptop-llm/profiles.yml](scripts/laptop-llm/profiles.yml) (top to bottom — it *is* the spec) →
> the `HD-474` / `HD-476` / `HD-486` rows in [todo.md](todo.md) §2 →
> [`reports/hd474-laptop-leg/`](reports/hd474-laptop-leg/) `raw/00-SESSION-STATE.md`.
>
> **Linked from:** [todo.md](todo.md) HD-474 · HD-476 · HD-486 ·
> [docs/hardware-workstation.md](docs/hardware-workstation.md) · [prompt.md](prompt.md)

## 0 · Already settled — do not spend your window re-deriving it

| Thing | State | Where |
|---|---|---|
| **Runtime pinned:** LM Studio **`0.4.25+1`** (package.json + exe FileVersion + uninstall registry all agree), `lms.exe` **commit `69d945a`**. The 2026-09-28 "auto-update means no pin" blocker is closed; nothing sits in `lm-studio-updater\pending\`. | pinned | `runtime.version` in [profiles.yml](scripts/laptop-llm/profiles.yml) |
| **Two legs, one GPU** (owner ruling 2026-09-29): **Gemma 4 26B A4B = the agent leg**, **Qwen3-VL-30B-A3B-Instruct = the vision leg**. Not one model doing both. The reason is §2, not taste. | owner decision | [todo.md](todo.md) HD-476 |
| **Gemma's vision has a hard ceiling at ~1120 px long side.** Anything above it **kills the runtime** (engine exit `3221226505` = `STATUS_STACK_BUFFER_OVERRUN`; server replies `{"error":"terminated"}`). Reproduced on **two weight files** (community Q4_K_M *and* unsloth QAT `UD-Q4_K_XL`) and on **2000×160 (0.32 MP)**, which is a *quarter* the pixels of the failing 1280×960 — so it is **not** the quant, not the file size, not total pixels: it is **max side length**. 320 / 640 / 896 / 1120 answer; 1280 and 2000 die. | measured | `raw/62,64,66,72` in [reports/hd474-laptop-leg/](reports/hd474-laptop-leg/) |
| **Qwen3-VL eats what Gemma cannot.** It answered the untouched **8160×6120 / 10.6 MB rack photo** (`prompt_tokens=4060`, engine still IDLE afterwards) and OCR'd `CRS328-24P-4S+RM` + `CAT6` + `PATCH CABLE 4PAIR ISO/IEC11801 TIA/EIA568B` — corroborated against [docs/network-rack.md](docs/network-rack.md), which lists that exact model string. That is ground truth, not a caption. | measured | `raw/73-original-photo.txt` |
| **Measured numbers (this engine, this carve).** Gemma: decode **17.5–17.8 t/s** (engine agrees: `17.54 / 17.46`), cold prefill **~250 t/s** at 1.8–2.2k tokens, warm **TTFT 0.4 s** on a prefix-cache hit (`f_sim_best = 1.000`), GPU dedicated **+16.78 GiB** at `-c 32768 --parallel 1` with the projector. Qwen-VL: decode **23.84 t/s**, **image prefill 61.2 t/s** (66 s for one full-res photo), `31 809` tokens **accepted** at `-c 32768 --parallel 1` but at **915 s of prefill**, `23.92 GiB`. | measured | `raw/69–73`, `raw/ctx32k.out` |
| **KV math that decides window size.** Qwen3-VL and Qwen3-30B-A3B-2507 both: 48 layers × 4 KV heads × head_dim 128, **no sliding window** = **96 KiB/token** at f16 → 32k costs **3.0 GiB**; both train at **262 144**, this box never gets near it. Gemma's hybrid (30 layers, **5 global**, sliding 1024) is ~**10–20 KiB/token marginal** → window is cheap, which is why *it* is the long-context leg. | header-read | `raw/gguf_keys.py` (works over an HTTP range request — no download needed) |
| **The text-only Gemma variant exists and costs nothing on disk.** `lms load` has **no** vision flag (`--gpu --identifier -c -y --parallel --ttl --estimate-only --speculative-*` are all of them) and the adapter attaches because it sits in the folder, so the variant was imported with `lms import --hard-link` → indexes as **`gemma-4-26b-a4b-textonly`**, 16.80 GB, **same inode**. Projector cost measured: **1.11 GiB resident at idle** (the mmproj file itself; the ViT adds ~nothing until an image arrives). | measured | HD-486, `raw/80-hd477-gemma-textonly.txt` |
| **`gate` today has exactly three complaints, all on `agent-gemma-26b`:** `vision_probe=pending`, `tool_probe=pending`, `certified=false`” — and they are closed, but **“nothing else” was the wrong half**: a green gate was not evidence the laptop was ready. The gate read placeholder model keys as real ones, and `probe-client` SKIPped forever because the spec's hostname did not match the hostname Windows reports. Both are fixed; `gate` now passes unaided and `probe-client` passes against a live server | measured | `python scripts/laptop-llm.py gate` |
| **The seat is Windows-native** (owner 2026-09-29). Local models serve **pi.dev on Win11**; WSL2 stays `networkingMode=Nat` on purpose, `providers.laptop-lmstudio` carries `native_only: true`. Never "fix" a WSL probe by reconfiguring the guest. | merged | [scripts/pi-config/models-spec.yml](scripts/pi-config/models-spec.yml) |
| **LM Studio's server ignores `chat_template_kwargs` / `enable_thinking`** (all four spellings tested; reasoning persisted). `--chat-template-kwargs` is a *llama-server* flag. **Consequence:** thinking is on by default, so any probe with a small `max_tokens` gets its budget eaten by `reasoning_content` and returns **empty `content`** — which is a test bug, not a model failure. Budget **≥ 1024** for anything on a reasoning model. | measured | `raw/63-thinking-toggle.txt` |

**Rule 0 — and it is live right now.** If your own `pi.dev` session is served by `laptop-lmstudio`
(`active: agent-gemma-26b` in the dial and the model resident), you **may not take timed numbers** —
`probe-speed`, `probe-ctx`, TTFT, any tok/s. Read-only state, `lms ps`, `/v1/models` and the gate are
fine. Hand timed legs to the owner or run the session off a remote model, and say which you did.

## 1 · The overnight job is **yours to run** — nothing is measuring right now

The previous session aborted its own HD-486 run at 01:16 (numbered `HD-477` when it ran) on the owner's instruction, so the GPU is
free and the ladder is **incomplete**. Do not assume any of it ran; run it yourself:

```powershell
& "$env:USERPROFILE\.lmstudio\bin\lms.exe" ps          # must say "No models are currently loaded"
python -X utf8 reports\hd474-laptop-leg\raw\hd477_run.py
```

It writes per-phase to `80-hd477-gemma-textonly.txt` (append, with phase markers) and never edits repo
config. Phases 0–2 already have one capture each — baseline 32k **with** projector (+16.78 GiB),
text-only 32k (+16.65 GiB, i.e. **the projector is 1.11 GiB resident and the ViT costs ~nothing until
an image arrives**) — re-running them costs about a minute and is worth it for a second sample.
**What has never run:** the **49 152 / 65 536** ladder and the **buried-needle recall probe** at ~28k
tokens of real repo prose (needle at 92 % depth, `KR-7391-QX`). Budget real time: a 31.2k-token
prefill on the text-only Gemma leg ran **13+ minutes** before it was killed, and the Qwen-VL leg took
**915 s** for 31 809 tokens. Prefill is the wall here, not memory.

Recall is the point: `probe-ctx` already returned **32 768 accepted, 16/16 binary-search steps**, so
length is *not* the open question. A bounded hybrid window can serve a long context and still remember
like a short one. If the needle comes back wrong, `client_context_window` comes **down**, not up.

## 2 · The lane, in order

**A · Certify `agent-gemma-26b` (HD-474).** Three things, in this order, each with its evidence file:
1. `probe-vision` — **fix the probe first if it is still `max_tokens: 80`** (see the thinking trap in §0;
   that is exactly the false negative this session found). Pass criterion stays strict: a correct reading
   of something only the image contains, **and** the client contract may only advertise `input: [text, image]`
   if it passes. Because of the 1120 px ceiling, either (a) keep `input: [text]` on this profile and let
   the vision leg own images, or (b) keep `[text, image]` **and** put the resize rule in the contract.
   Pick one, do not straddle it.
2. `probe-tools` — already passes on Gemma (well-formed call); record it with the evidence path.
3. `probe-speed` — **rule 0.** Record cold prefill, warm TTFT, decode, *and the prompt shape*, at
   1.8k / 8k / 24k tokens in. HD-401 gate 3 is what this feeds.
4. Then: `certified: true`, `certified_evidence: reports/hd474-laptop-leg`, `gate` **green on its own**.

**B · Land the vision leg (HD-476).** Add the Qwen3-VL rows to [profiles.yml](scripts/laptop-llm/profiles.yml):
model `qwen3-vl-30b-a3b-instruct` (`unsloth/Qwen3-VL-30B-A3B-Instruct-GGUF`, file
`Qwen3-VL-30B-A3B-Instruct-UD-Q4_K_XL.gguf` **17 716 000 000-ish B** + `mmproj-BF16.gguf`), profile
`vision-qwen3vl-30b`, `num_ctx: 32768`, `kv_cache_type: f16` (**owner declined q8_0 on this model**),
`parallel: 1`, `capabilities: [tool]`, `input: [text, image]`, and the measured facts in the row:
`23.84 t/s`, image prefill `61.2 t/s`, `23.92 GiB` at 32k, one full-res photo = `4060` tokens.
Run `probe-vision` against **the real rack photo at its real size** (this is the leg that can take it)
and `probe-tools` (**it passed for the harness, not for the profile flag** — a passing probe and a red gate were both true at once; `passed` on both legs now), then certify. The budget row must add: **96 KiB/token**, so a 32k
vision leg holds **3.0 GiB of KV** — no room for a second resident model.

**C · Wire the client — LAST, never first (HD-474).**

```powershell
python scripts\laptop-llm.py budget --profile agent-gemma-26b
python scripts\laptop-llm.py gate
python scripts\render-pi-config.py pi --host Domen_P14s --check    # drift only, writes nothing
#   ^ this line used to read `--host domenp14s`. The box reports `Domen_P14s`; `render()` matched hostnames
#     exactly, matched nothing, and returned a config with NO laptop-lmstudio provider - silently. Fixed:
#     host_norm()/host_matches() canonicalise (`Domen_P14s` == `domenp14s`) and an unknown host is loud.
python scripts\laptop-llm.py probe-client                          # must PASS, not SKIP
```

`contextWindow` in `models-spec.yml` and `num_ctx` in the profile must agree in the same commit;
`probe-client` fails if they drift and pi 400s mid-session if you ship it anyway. If the vision leg is
a second provider/row, the picker gets both — say so in the docs, and make the image-size rule visible
to whoever picks the wrong one.

**D · Close out.** Full validator in a **WSL worktree of the same branch** (never the primary
checkout), signed commit, merge **only if green**. Then sweep every claim the run made stale:
§Served leg, §Leg 1, §Leg 2, the budget table, decision #28 in
[services-ai.md](docs/services-ai.md), and the three `todo.md` rows.

## 3 · Traps that cost this session real hours

* **`lms load` syntax:** `lms load <key> --gpu max -c <N> --identifier <name> -y`. It is **`-c`**, not
  `--context`; there is **no** `--pub`, no `--kv-cache-type`, no `--threads`, no `--chat-template`, no
  `--batch-size`, no `--temperature` in 0.4.25 (verified against `load --help`). **`-y` is mandatory** —
  without it an unmatched key hangs on an interactive TTY picker.
* **`lms get <resolve-url>` still fetches the whole repo.** It pulled `mmproj-F32.gguf` (2.29 GB) twice
  while asked for `mmproj-BF16`. For exact files use `huggingface_hub.snapshot_download(..., allow_patterns=[...])`.
* **LM Studio's downloader is ~50 Mbps on a 1 Gbps link**; `huggingface_hub` saturates the link (17.7 GB
  in 214 s). Use the hub library.
* **A folder you place by hand is NOT indexed** — `lms ls` does not rescan. Use
  `lms import --hard-link --user-repo <u>/<repo> [--dry-run]`. JIT loading is **off** here: `/v1/models`
  lists only resident models, so the client must load explicitly.
* **`daemon` is a hidden subcommand.** The GUI is closed; **`llmster v0.0.25+1` is the service**
  (`lms daemon status`, `lms daemon up`, `lms server start`). Verify with `daemon status` before
  concluding "the server died" — and never conclude it from a missing tray icon.
* **Never trust the engine's `offloaded N/N layers` line here** — it is absent at verbosity 3 on the
  Vulkan runtime. GPU residency is proven with the PDH counter, in **bytes**:
  `\GPU Adapter Memory(luid_0x00000000_0x0001a051_phys_0)\Dedicated Usage` (≈24 GiB adapter of a 32 GiB
  carve; idle desktop measured **3.12 GiB**, which is why `held_floor_bytes` moved up from the 3.00 the
  file used to claim).
* **Token arithmetic in probes lies.** `/v1/tokenize` is not served, so anything using chars/4 is a
  guess: a run of `xxxx` tokenizes at **~2:1** and `word word word` at **~3 tokens/word**, which made
  two probes here test half, and three times, the window they claimed. Word-shape your prompts and
  **always report `usage.prompt_tokens`**, never your own estimate.
* **`/api/v0/fim/completions` was removed in 0.4.25.** FIM rides the chat template
  (`fim_surface: instruction-fenced` on coder-3B, 6/6 canaries in `probe-fim --self-test`).
* **A 4xx is a *contract* error, not a model-capability failure.** This session mis-attributed that
  three times: `tool_choice:"auto"` 400s (the server rejects it — removed from the probe), a 400
  "no models loaded" is not a projector failure, and a 400 `{"error":"terminated"}` **is** the crash
  signature. `probe-tools` / `probe-vision` now distinguish the classes; keep that distinction.
* **Output discipline:** strip ANSI (`sed -e 's/\x1b\[[0-9;]*m//g'`), pipe to files, bound everything,
  `PYTHONUTF8=1` in child envs. The driver and `.ps1` already carry the Windows encoding fixes
  (UTF-8 `read_text`, stdout/stderr reconfigure, `.ps1` saved with a BOM for PS 5.1,
  `$ErrorActionPreference = 'Continue'`) — do not "tidy" them away.

- **The endpoint does not police the `model` field.** With only the vision leg resident, a chat request naming `no-such-model-here` was answered — `'PONG'`, 0.4 s — **by the resident model**. So a stale row in `models-spec.yml`, or the wrong leg loaded, is not a 400: you are silently served the other model. Images are the one path that IS policed (`400 "does not support image inputs"` in 0 s). `probe-client` now reads `/v1/models` and FAILs when the row it certifies is not resident — that check is load-bearing, delete it and the contract goes quiet again.
- **Greedy agreement proves stability, not perception.** Five asks of one rack photo — three at the file's sampling, two greedy at `temperature 0` — all returned `CRS326-24G-2S+RM` where `docs/network-rack.md` says `CRS328-24P-4S+`. That looked like a perception floor and was **wrong**: cropping the same photo into a grid chosen blind produced `CRS328-24P-4S-RM`, and the repo's own label photo came back character-perfect (`CRS328-24P-4S+RM`, 528 tokens, 3.9 s) — see `raw/96`. The trap that produced the wrong conclusion was trusting repeatability as evidence of sight. Test a reading you distrust by **changing what is in the frame** and by feeding the model **one image whose answer you already know**; and remember image tokens saturate (~4.1 k for the full frame and for a quarter of it alike), so **crop, never shrink**.
- **Ask a photo once, or ask it identically.** Same question again = 2.0 s; any *new* question = ~60 s again, because the text precedes the image in the message and invalidates the cached image tokens. Put the image first in multi-question seams.
- **`flush=True` is not a `log()` kwarg.** The 2026-09-29 ladder died with `TypeError: 'flush' is an invalid keyword argument for BufferedWriter.write` one step into its most expensive phase; the raw log ended mid-run and the next session read that silence as a decision. Log unbuffered (`LOG.flush()` per line), and never interpret a missing measurement as a negative result.

## Non-negotiables

* **Worktree before writes:** `D:\source\domenkogler\homelab-wt-hd474`, branch
  `session/hd474-win11-certify`. `git worktree remove` at the end.
* **Never edit an assert, a gate invariant or a budget constant to make it pass.** Record the
  measurement instead. `held_floor_bytes` moves only from a **measured** dedicated-memory reading.
* **One model resident.** `lms unload --all` before every load. Two residents on one carve is the
  documented amdgpu failure mode — and after the 32k vision leg there is no room for a third.
* **Secrets (§6):** `~\.lmstudio\settings.json` holds `hfDownloadToken` / `useHFProxy` — never
  committed, only merged by the applier (which backs up first). `apiKey: lmstudio-local` is a
  placeholder **because the listener has no auth**.
* **Do not expose `:1234`** and do not add a firewall rule. `networkInterface: 0.0.0.0` is an **owner
  decision that is still outstanding**, not a convenience.
* **No silent downloads.** The applier reports a missing file; you fetch it deliberately and verify
  byte sizes against the Hub's declared size (both QAT and Qwen-VL files were verified that way).

## Offline checks (Windows has no ansible — run the subset that exists natively)

```powershell
python scripts\laptop-llm.py gate --self-test        # must be 13/13
python scripts\check_secrets.py
python scripts\check_placeholders.py
python -m py_compile scripts\laptop-llm.py scripts\render-pi-config.py
```

Full `bash scripts/validate-all.sh` runs **in a WSL worktree of the same branch**. If bash/ansible are
unavailable, say so and let the owner decide — do not call the lane green on the subset.

## Report

Append to [`reports/hd474-laptop-leg/README.md`](reports/) as **measurements, not narrative**: engine
and `llmster` versions, every probe command with verbatim output, PDH dedicated-memory figures per
load, tok/s + TTFT with the prompt shape and cache state, the image-size boundary table (which file,
which pixels, which outcome), and the OCR corroboration against `docs/network-rack.md`. Raw captures
live in `raw/` with the numeric prefixes; `raw/00-SESSION-STATE.md` is the recovery note — keep it
current, because the next session starts blind.

**Rollback** is boring, which is the point: `lms unload --all`, `active: fim-coder-3b` (the cheap leg),
or `lms server stop`. Nothing in the client config is live until step C, so a failed session leaves the
harness exactly where it is now.
