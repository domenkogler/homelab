# 00 · SESSION STATE — recovery note for the next session

Written 2026-09-30 ~01:12 by the session that ran 2026-09-29 late evening. **Read this before
touching the GPU.** The lane brief was the `prompt-lmstudio` lane brief, since retired; this file is
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


## FINAL STATE — 2026-09-30 ~04:55Z (overnight run, by `pi` on spark/qwen3.8-flash-next)

Lane **closed on the GPU side**. Worktree `D:\source\domenkogler\homelab-wt-hd474`,
branch `session/hd474-win11-certify-2`. **Nothing committed, nothing pushed** — the owner said
"work in your own worktree, dont commit", so `git commit` never ran here.

### Rules honoured

| Rule | How |
|---|---|
| Rule 0 — the model taking numbers must not be served by the laptop | this session is served by remote `spark`; `lms ps` before every timed block, recorded in `raw/88-certify.txt` and `raw/90-speed.txt` |
| Rule 1 — the session that wakes up finishes the job | the 2026-09-29 log ended mid-phase; I found the real cause (a `TypeError` in the logger, not the owner's kill) and finished phases 3–4 + the 49k/65k ladder |
| GPU idle before you trust a number | `lms ps` + PDH idle baseline (2.15–2.28 GiB) captured before every load; one leg resident, `unload --all` between legs |
| Never lower a constant to get green | `ceiling_bytes` and `held_floor_bytes` untouched; the gate's invariants untouched; the pre-existing `check_merge_markers` self-test failure left for the owner |
| A probe that cannot fail is not evidence | `gate --self-test` 13/13, `probe-vision --self-test` 6/6, `probe-fim --self-test` 6/6, `render-pi-config.py --self-test` 3/3, and the new residency check was **watched failing** (vision leg loaded, agent row named) before it was watched passing |

### What the record now says (the short version)

- **Recall at 32k passes.** 28 984-token prompt, needle at 92 % depth, returned verbatim.
- **Decode is not a constant:** 21.1 / 18.3 / 8.3 t/s at 2 462 / 10 610 / 31 137 tokens.
- **Cold prefill is not even repeatable:** 259.15 s vs 69.42 s for identical 10 610-token bytes.
- **The projector costs 1.00–1.11 GiB** and `--jails 0` does not load at all.
- **Gemma is text-only** and the server enforces it (`400 "does not support image inputs"`, 0 s).
- **The endpoint does not police the `model` field** — silent substitution, proven; `probe-client`
  now checks `/v1/models`.
- **The vision leg sees but does not transcribe** — five greedy passes, `CRS326-24G-2S+RM`, against
  the rack doc's `CRS328-24P-4S+`. This corrected claims in `todo.md` HD-476,
  `docs/hardware-workstation.md` and `docs/services-ai.md` #28.
- **Ask a photo once:** same question 2.0 s, new question ~60 s (image sits behind the text).

### Validators (last state)

| Check | Result |
|---|---|
| `python -X utf8 scripts/laptop-llm.py gate` | **PASS** (13 invariants, active=agent-gemma-26b) — green unaided |
| `gate --self-test` / `probe-vision --self-test` / `probe-fim --self-test` | 13/13 · 6/6 · 6/6 |
| `probe-client` (live, agent leg resident) | **PASS** + residency confirmed (`['agent-gemma-26b']`) |
| `check_todo_done` / `check_md_tables` / `check_placeholders` / `check_secrets` | OK · OK (152 files) · OK (797) · OK (1202) |
| `render-pi-config.py --self-test` | 3/3 |
| `render-pi-config.py check --host Domen_P14s` | **blocked**: `op` account not signed in — human step |
| `bash scripts/validate-all.sh` (git-bash) | one failure: `check_merge_markers.py --self-test`, **pre-existing on clean `main`**, deliberately untouched |
| `wsl.exe -d Debian -- bash scripts/validate-all.sh` | **could not run**: a Windows-created worktree's `.git` pointer is `gitdir: D:/source/...`, which git inside WSL cannot resolve, so `guard-session.sh` correctly refused ("not inside a git work tree"). Debian also has no PyYAML. Trap recorded in `raw/93-wsl-validate-all.txt`; the git-bash run above is the reference |

### Engine state left behind

`lms unload --all` — as found (nothing loaded). To bring the agent leg up:
`powershell -File scripts\win\lmstudio-llm.ps1 switch -Profile agent-gemma-26b`.

### The four things I did not get to

1. **`render-pi-config.py --check`** — needs `op signin`. The client contract is verified by
   `probe-client` (field-level) and **not** by a byte-level render diff. Do not call this lane green
   on the subset.
2. **`--jails 0` memory test** — the load fails ("Missing multimodal projector"), so the question
   "does the ViT reserve VRAM with no vision slot" is answered NO by the loader rather than by a
   counter. Recorded in `raw/79-no-jails.txt`.
3. **A cropped full-res photo** to see whether the SKU misread is a resolution problem or a
   perception floor. Until then the rack doc's label photo is the authority.
4. **Q4_K_S → does `budget` stay honest for the vision leg at 32k with two images in context** —
   the arithmetic (23.51 GiB declared) has never been exercised with an image resident in the KV.

### Note for whoever picks this up

The injected reminder to "read `skills/md-tables/SKILL.md` before writing a markdown table" points
at a file that **does not exist on this box** (`~/.pi/agent/skills` has only mikrotik, platform-env,
shelly; the repo has no `skills/`). The repo's real equivalent is `scripts/check_md_tables.py`,
which I ran after every doc edit.

---

## EVENING SESSION — 2026-09-30 ~21:30Z (`session/rack-sku-crop-20260930`, worktree `homelab-wt-20260930-2117`)

Two owner-asked items, both small, one of which overturned this report's own morning conclusion.

**`nul` deleted** from the primary checkout (0-byte Windows junk from a `2>nul`, dated 2026-09-19). One of
the two untracked files that made `guard-session.sh` refuse `validate-all` there; the other,
`docs/assets/images/20260812_185130.jpg`, is the owner's call (possibly the source of
`original8160.jpg`).

**The SKU question, closed by `raw/96`.** Morning's conclusion ("the vision leg sees but does not
transcribe; perception, not sampling") was **wrong**, and the way it was wrong is the lesson: five greedy
answers proved *stability*, and stability was read as *sight*. Cutting the same photo into a 2×3 grid
chosen without looking at it settled it in one pass —

| input | tokens | answer |
|---|---|---|
| whole 8160×6120 frame (`raw/91`, `raw/92`) | 4042–4060 | `CRS326-24G-2S+RM` ×5 |
| top-left quarter `96-tile-r0c0.jpg` | 4065 | **`CRS328-24P-4S-RM`** ×4 |
| other five tiles | 4065 | `NOT VISIBLE` (correct — no label in frame) |
| whole frame at 1/5 | 1983 | `NOT VISIBLE` (shrinking is strictly worse) |
| `docs/assets/images/CRS328.png` (known answer) | **528** | **`CRS328-24P-4S+RM`, perfect, `+` included**, 3.9 s |

Image tokens **saturate at ~4.1 k**: the full frame and a 3264×3672 quarter cost the same. So the rule for
any seam reading small text is **crop, never shrink** — a crop is free relative to the big photo and it
reads. Docs updated in the same change: `docs/hardware-workstation.md`, `docs/services-ai.md` #28,
the `prompt-lmstudio` lane brief, the profile's `vision_caveat`, and the vision todo row. The 2026-09-29 "OCR'd it
verbatim" claim stays corrected — it was never reproducible *on the frame it named*.

**Kept / deleted artifacts:** `96_crop.ps1`, `96_probe.py`, `96-crop-probe.txt` and `96-tile-r0c0.jpg`
committed; the other six crops deleted — `96_crop.ps1` regenerates them from the committed photo, and 7 MB
of derived JPEGs in git is a worse record than a deterministic script.

**Engine left unloaded** (`lms unload --all`), as found.

**Blocker worth not rediscovering:** the oldsrv/VPS clone probe for the missing `20b49f4` (cited by the
`zone_kogler_si` row) could not run: `SSH_AUTH_SOCK` is empty in git-bash, so ssh offers only `.pub` files
and auth fails (`Permission denied (publickey)`). Same root cause as the signing failure earlier in the
day. Run it from a shell where the 1Password agent is visible.

**Also still standing, unchanged:** the `HD-476`/`HD-477` duplicate row ids (see report §8) — this session
deliberately minted no new references to either id for the laptop legs.
