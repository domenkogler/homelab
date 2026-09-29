# 00 · SESSION STATE — recovery note for the next session

Written 2026-09-30 ~01:12 by the session that ran 2026-09-29 late evening. **Read this before
touching the GPU.** The lane brief is [`prompt-lmstudio.md`](../../../prompt-lmstudio.md); this file is
only "what is true on this box right now".

## Live right now

* **Nothing is loaded and nothing is running.** The previous session started an HD-477 run at 01:02 and
  **killed it at 01:16 on the owner's instruction**, so the fresh session owns the whole measurement.
  Phases 0–2 have one capture each in `80-hd477-gemma-textonly.txt`; the 49 152 / 65 536 ladder and the
  recall probe **never ran**. Run them: `python -X utf8 hd477_run.py` (appends per-phase, edits nothing).
* **Service:** the **LM Studio GUI app is closed** (owner closed it at ~01:00).
  **`llmster v0.0.25+1` is the service**, PID 45904, serving `:1234`. `lms daemon status` confirms;
  `lms daemon up` / `lms server start` recover it. A missing tray icon means nothing.
* **Dial:** `active: agent-gemma-26b` → **rule 0 is in force**: a session served by this laptop leg may
  not take timed numbers. The owner intends to start the next session **off a remote model** for that
  reason.
* **Log:** `80-hd477-gemma-textonly.txt` (phases) · `81-overnight-wrapper.txt` (cutover) ·
  re-run with `python -X utf8 hd477_run.py` if it died; it writes per-phase and edits no repo config.

## Settled by measurement (each has a file in this directory)

| Fact | Number | File |
|---|---|---|
| Runtime pinned | LM Studio `0.4.25+1`, `lms` commit `69d945a`, llmster `0.0.25+1` | profiles.yml `runtime` |
| Gemma decode | **17.5–17.8 t/s** (engine's own `print_timing` agrees) | `69`,`71` + owner's log |
| Gemma cold prefill | **~250 t/s** at 1.8–2.2k tokens (derived by subtracting decode from wall) | `69` |
| Gemma warm TTFT | **0.4 s** for 2176 tokens — prefix-cache hit (`f_sim_best = 1.000`, engine evaluated **1** token) | `71` |
| `probe-ctx` | **32 768 accepted, 16/16 steps.** No clamp (spark's precedent was 20 468/32 768). Measures *acceptance*, not recall | `65` |
| `probe-tools` on Gemma | **passed** | session (record in profile row) |
| Gemma image ceiling | **dies above ~1120 px long side**; 320/640/896/1120 OK, 1280 and 2000×160 kill the engine (`3221226505`). Same on Q4_K_M **and** QAT → not the quant | `62`,`64`,`66` |
| Qwen-VL vision | takes **8160×6120 / 10.6 MB** (`prompt_tokens=4060`, engine survives) and OCR'd `CRS328-24P-4S+RM`, matching `docs/network-rack.md` | `72`,`73` |
| Qwen-VL speed | decode **23.84 t/s**; **image prefill 61.2 t/s** = 66 s for one full-res photo | `68`,`73` |
| Qwen-VL 32k | `31 809` tokens **accepted**, **915 s** prefill, **23.92 GiB**. Over-window requests refused in 0 s (clean 400, no crash) | `ctx32k.out` |
| KV per token | Qwen3-VL / Qwen3-30B-A3B-2507: 48 L × 4 KV heads × 128, no sliding = **96 KiB/token f16** (32k = 3.0 GiB); both train at **262 144**. Gemma hybrid: ~10–20 KiB/token marginal | `gguf_keys.py` |
| Projector cost | text-only variant loads **1.11 GiB lighter** at idle (the mmproj itself; ViT adds ~nothing until an image arrives) | `80` phases 1–2 |
| Idle desktop GPU floor | **3.12 GiB** measured (the file used to claim 3.00) | session |

## Decisions taken (owner)

1. **Two legs.** Gemma 4 26B A4B = agentic/text. Qwen3-VL-30B-A3B-Instruct = images. New rows
   **HD-476** (vision leg) and **HD-477** (text-only Gemma + larger ctx) are in `todo.md`.
2. **No q8_0 KV on the Qwen leg** for now (it also needs `flash_attention: true`, unproven on Vulkan).
3. **LAN exposure of `:1234` is still an open owner gate.** Not to be enabled as a side effect.
4. QAT (`unsloth/gemma-4-26B-A4B-it-qat-GGUF`, `UD-Q4_K_XL` 14.25 GB + `mmproj-BF16`) is **on disk but
   uncertified** — it did *not* fix the image ceiling, so it is a 2.4 GiB saving, not a capability.

## Not done — the actual task list

1. `gate` has exactly three complaints, all on `agent-gemma-26b`: `vision_probe=pending`,
   `tool_probe=pending`, `certified=false`.
2. **`probe-vision` is still `max_tokens: 80`** → on a reasoning model the budget is eaten by
   `reasoning_content`, `content` comes back empty, and the probe reports a false failure. Fix the
   probe (≥1024), then decide whether this profile keeps `input: [text, image]` (and must carry the
   **long side ≤ 1120 px** resize rule) or drops to `[text]` and lets the vision leg own images.
3. Add the Qwen3-VL model row + `vision-qwen3vl-30b` profile with the measured numbers above
   (`num_ctx: 32768`, `kv_cache_type: f16`, `parallel: 1`), certify it against the real rack photo.
4. `probe-speed` at 1.8k / 8k / 24k shapes — **rule 0**, hand it to the owner or run off a remote model.
5. Render + `probe-client` **last**, full validator in a **WSL worktree**, signed commit, merge only if green.

## Traps, condensed (full list in the brief §3)

* `lms load <key> --gpu max -c <N> --identifier <name> -y` — `-y` or it hangs on a TTY picker; no
  `--context`, no `--kv-cache-type`, no `--threads`, no `--chat-template`, no `--temperature`.
* Hand-placed model folders are **not** indexed → `lms import --hard-link` (zero-copy, 16.8 GB for free).
* `lms get <file-url>` still pulls the whole repo (grabbed `mmproj-F32` 2.29 GB twice). Use
  `huggingface_hub` `allow_patterns`; LM Studio's own downloader is ~50 Mbps, the hub library is ~1 Gbps.
* chars/4 token arithmetic lies: `xxxx` ≈ 2:1, `word ` ≈ 3 tokens/word. Two probes silently tested a
  fraction of the window they claimed. Always report `usage.prompt_tokens`.
* A 4xx is a **contract** error, not a model failure. `tool_choice:"auto"` 400s; "no models loaded" is
  not a projector failure; `{"error":"terminated"}` **is** the crash signature.
* Strip ANSI, bound all output, `PYTHONUTF8=1` in child envs. Do not "tidy" the driver/`.ps1` encoding
  fixes (UTF-8 `read_text`, stdout reconfigure, `.ps1` BOM for PS 5.1, `$ErrorActionPreference='Continue'`).

## Housekeeping

* `D:\llm\models\domen\gemma-4-26b-a4b-textonly\` is a **hard link** (same inode as
  `lmstudio-community/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-Q4_K_M.gguf`). Deleting it frees nothing.
* Downloads this session: unsloth QAT Gemma (~15.4 GB), unsloth Qwen3-VL-30B-A3B (~18.8 GB).
  D: free was 191 GB at 00:57.
* Untracked junk in the repo, leave alone: `nul`, `docs/assets/images/20260812_185130.jpg`.
* The rack photo used for vision evidence is copied to `raw/original8160.jpg` so the worktree is self-contained.
