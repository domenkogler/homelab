# HD-474 / HD-476 / HD-486 — the laptop's two serving legs, certified by measurement

**Box:** `Domen_P14s` (measured `socket.gethostname()`; the docs said `DomenP14s` — see §Defects).
AMD Ryzen AI 9 HX PRO 370, Radeon 890M (`gfx1150` family), 32 GiB BIOS UMA carve, Win11 Pro.
**Runtime:** LM Studio **`0.4.25+1`**, `lms` CLI commit **`69d945a`**, service **`llmster v0.0.25+1`**
(GUI closed, `lms daemon status` = running). Engine: llama.cpp **Vulkan** (no Windows ROCm path for
this APU).
**Sessions:** 2026-09-29 → 2026-09-30 (overnight). Lane brief: the `prompt-lmstudio` lane brief, since retired (the laptop's serving legs now run from the domain brief named in [../../todo-table.md](../../todo-table.md) §B0).
**Rule 0** (no timed numbers from a session the engine itself serves): this run was driven from a
pi.dev session served by **`spark/qwen3.8-flash-next`** (remote GB10), not by `laptop-lmstudio`, so
timed measurement was permitted. Stated here because the brief requires the session to say which it did.

Everything below is a number, a command, or a verdict. No narrative. Raw captures are in
[`raw/`](raw/) with numeric prefixes; `raw/00-SESSION-STATE.md` is the recovery note.

---

## 1 · Instruments (so the numbers mean what they claim)

| Quantity | Instrument | Why not the obvious one |
|---|---|---|
| GPU residency | PDH counter `\GPU Adapter Memory(luid_0x00000000_0x0001a051_phys_0)\Dedicated Usage`, **bytes**, read with `Get-Counter` | The engine's `offloaded N/N layers` line is **absent at verbosity 3** on this Vulkan build; `AdapterRAM` via WMI is capped at 4 GiB; Task Manager is not scriptable here |
| Token counts | `usage.prompt_tokens` from the server | `/v1/tokenize` is not served. chars/4 lies: a run of `xxxx` hits ~2:1, `word word` ~3 tokens/word, real prose ~4.5:1. Two probes on this box measured half and three times the window they claimed |
| Prompt shape | `raw/87_speed_shapes.py` → real repo prose from `docs/*.md`, de-duplicated | `"You are a coding agent. " * 300` is a degenerate repeat: prefix-cache-swallowed and token-density-flattered |
| Prefill vs decode | `--ttft` (streaming, first token timed) | Non-streaming wall conflates them; TTFT is what a user feels, and `prompt_tokens / TTFT` gives prefill without assuming any decode rate |
| Recall | `raw/80` phase 4 — needle at 92 % depth of ~110 kB of real docs prose | `probe-ctx` measures *acceptance*, not memory. A bounded window can serve long context and still remember like a short one — or not |

Idle desktop under a load, PDH dedicated: **2.15 / 2.15 / 2.21 / 2.28 GiB** on 2026-09-30 and
**3.12 GiB** on 2026-09-29. `held_floor_bytes` in the catalogue **stays 3.00 GiB** — a measured
reading may move it, and the honest reading is that 3.00 is a rounded-up floor that also covers
activation/compute buffers. It was not lowered to buy window margin.

---

## 2 · HD-486 (was `HD-477`) — the projector, the window ladder, and recall

Driver: [`raw/hd477_run.py`](raw/hd477_run.py), log [`raw/80-hd477-gemma-textonly.txt`](raw/80-hd477-gemma-textonly.txt).

### 2a · What the projector costs

| Load (`-c 32768 --parallel 1`) | weights on disk | PDH dedicated after load | idle before |
|---|---|---|---|
| `google/gemma-4-26b-a4b` (mmproj attached) | 17.99 GB (16 796 015 040 B + 1 194 827 744 B) | **19.81 GiB** (prev. session: 19.78) | 2.15 GiB |
| `gemma-4-26b-a4b-textonly` (hard link, no mmproj) | 16.80 GB, **same inode** `5764607523036758544` | **18.81 GiB** (prev. session: 18.74) | 2.15 GiB |

**Projector = 1.00–1.11 GiB resident** (two days agreeing), and it is the mmproj file's own bytes:
the ViT adds ~nothing until an image arrives. `lms import --hard-link` cost **zero extra disk**.

### 2b · The context ladder (text-only leg, same 20 816-token prompt at every step)

| `num_ctx` | PDH dedicated after load | cold accept (`max_tokens=1`) | warm/short probe |
|---|---|---|---|
| 32 768 | 18.87 GiB (idle 2.21) | **20 816 tokens in 359 s** | 2 616 tokens in 23 s |
| 49 152 | 19.18 GiB (idle 2.21) | **20 816 tokens in 899 s** | 2 616 tokens in 23 s |
| 65 536 | 19.31 GiB (idle 2.28) | **20 816 tokens in 277 s** | 2 616 tokens in 19 s |

Readings, in order, with the mechanism left alone:

* **Memory is cheap and linear:** +0.31 GiB for +16 k tokens of window ≈ **20 KiB/token**, which is
  the header-derived number (30 layers, 5 global, 2 KV heads, key_length 512). 65 536 fits with
  ~5 GiB of adapter to spare.
* **Prefill is the wall and it is erratic:** the *same* prompt spans **277–899 s** across three fresh
  loads (3.3×). Do not read the 899 as "bigger window costs more" — 65 536 was the *fastest*. What
  is defensible is that cold-prefilling ≥20 k tokens on 16 CU takes minutes and is not repeatable
  enough to plan a session around.
* Therefore `num_ctx` / `client_context_window` **stay 32 768**. Not for GiB. For latency.
* Every step ran `lms unload --all` → reload, and the counter returned to the idle floor each time:
  **unloading really does return the allocation** (this was §Memory & residency's open question).
* `10 400` repeated words = **20 816 tokens** (~2 tokens/word). Recorded so nobody re-derives it.

### 2c · Recall — the question this lane was actually about

`probe-ctx` had already returned 32 768 accepted with 16/16 binary-search steps, which proves the
window is *accepted*, not that anything is *remembered*. So: ~100 000 characters of real repository
prose (`docs/*.md`, de-duplicated), needle `The service tag for this host is KR-7391-QX.` inserted at
**92 % depth**, then one question at the end, on the text-only leg at `num_ctx 32 768`.

| Pass | Budget | Result |
|---|---|---|
| first | `max_tokens: 64` | `prompt_tokens=31 761`, wall 1984 s, `completion_tokens=64` of which **`reasoning_tokens=61`** → `content` EMPTY, needle "not found". **A test bug, not a model failure** — the same thinking-budget trap that made `probe-vision` call a working projector blind |
| second (fixed: budget 1024, body trimmed so reply + prompt fit the window) | `max_tokens: 1024` | `prompt_tokens=**28 984**`, wall **1658 s**, `completion_tokens=391` (reasoning 378), **`content = "KR-7391-QX"` — needle found** |

**Verdict: the hybrid recalls.** 5 global layers out of 30 with a 1024-token sliding window, 29 k
tokens in, the needle at 92 % depth returned verbatim. So `client_context_window` **stays
32 768** — the brief's "if the needle comes back wrong, it comes down" branch did not trigger.
The cost, recorded honestly: that one cold turn took **27.6 minutes** (28 984 tokens ÷ 1658 s =
**17.5 t/s effective**), which is the same order as decode. Filling this window on this box is a
coffee-break operation, and that is the real argument for keeping the client window modest.

---

## 3 · HD-474 — the agent leg (`agent-gemma-26b`, text-only)

Catalogue row: [`../../scripts/laptop-llm/profiles.yml`](../../scripts/laptop-llm/profiles.yml)
→ `profiles.agent-gemma-26b`, model `gemma4-26b-a4b-textonly`.

| Item | Value | Source |
|---|---|---|
| Decode | **21.1 / 18.3 / 8.3 t/s** at 2 462 / 10 610 / 31 137 prompt tokens — decode is **not a constant**, it falls with context (§3b). For reference, the 2026-09-29 first pass measured **17.5–17.8 t/s** (engine `print_timing` 17.54 / 17.46) at ~2 k depth on the projector-equipped load | `raw/90`, `raw/88`, `raw/69`, `raw/71` |
| Cold prefill | **256 / 153 / 17 t/s** at those same three sizes — and the same 10 610-token prompt cost **259.15 s** on one load and **69.42 s** on another, so cold prefill past ~10 k tokens is not a repeatable number at all (§3b, §6b). First pass: ~250 t/s at 1.8–2.2 k, 58 t/s at 20 816 tokens | `raw/90`, `raw/88`, `raw/80`, `raw/69` |
| Warm TTFT | **0.30–0.38 s** at any of the three sizes on a prefix-cache hit — the cache, not the window size, decides first-token time. The 2026-09-29 measurement stands (`f_sim_best = 1.000`, engine evaluated **1** token): it is a cache hit and was never a prefill rate | `raw/90`, `raw/71` |
| `probe-ctx` | **32 768 accepted**, 16/16 binary-search steps, no clamp | `raw/65` |
| Window ladder | see §2b | `raw/80` |
| Thinking | **cannot be switched off** — `chat_template_kwargs` / `enable_thinking` ignored in all four spellings; budget ≥ 1024 reply tokens or `content` returns empty | `raw/63` |
| Vision | **not offered, and the server enforces it**: `probe-vision` against this load returns `400 "agent-gemma-26b does not support image inputs"` in **0 s** because no projector is attached — the loud failure the contract wants. The underlying reason is the ~1120 px ceiling: above it the engine exits `3221226505` (`STATUS_STACK_BUFFER_OVERRUN`) and the server answers `{"error":"terminated"}`. Reproduced on two weight files and on a 2000×160 strip (¼ the pixels of a failing 1280×960) | `raw/88`, `raw/62`, `raw/64`, `raw/66` |
| `probe-tools` | **passed** on this load — well-formed `tool_calls` (`{"command":"ls /tmp"}`), with `tool_choice` deliberately not sent because 0.4.25 400s on it | `raw/88` |

### 3b · tok/s and TTFT at the shapes an agent really sends (`raw/90-speed.txt`)

Real repository prose (`raw/87-shape-*.txt`), streamed with `--ttft`, one resident text-only leg,
thinking ON (it cannot be off), `max_tokens 256`:

| `prompt_tokens` (server-reported) | cold TTFT | cold prefill | decode | warm TTFT (same prompt again) |
|---|---|---|---|---|
| 2 462 | 9.63 s | **256 t/s** | **21.1 t/s** | 0.30 s |
| 10 610 | 69.42 s | **153 t/s** | **18.3 t/s** | 0.38 s |
| 31 137 | 1806.83 s | **17 t/s** | **8.3 t/s** | not run |

Three things fall out that no model card mentions:

1. **Decode is not a constant:** 21.1 → 18.3 → 8.3 t/s as context grows. One "this box does 17 t/s"
   figure is wrong at both ends of the range.
2. **Cold prefill varies ~4× run to run on the SAME prompt:** the 10 610-token prompt measured
   **259.15 s** in `raw/88` and **69.42 s** in `raw/90` — same bytes, same load. `raw/80` showed the
   same shape (277 / 899 / 359 s for one 20 816-token prompt). Measured twice, independently: this
   is a property of the box, so prefill past 20 k tokens is budgeted for pessimistically, not planned.
3. **The prefix cache is the only fast path:** warm TTFT is ~0.3 s whether the prompt is 2.5 k or
   10.6 k tokens. Whatever the harness sends repeatedly belongs in a frozen prefix.

`probe-tools` on this load: **passed** — well-formed `tool_calls` (`{"command":"ls /tmp"}`), with
`tool_choice` deliberately not sent because 0.4.25 400s on it. Full verbatim output:
`raw/88-certify.txt`.

---

## 4 · HD-476 — the vision leg (`vision-qwen3vl-30b`)

| Item | Value | Source |
|---|---|---|
| Weights / projector | `Qwen3-VL-30B-A3B-Instruct-UD-Q4_K_XL.gguf` **17 715 664 608 B** + `mmproj-BF16.gguf` **1 087 039 168 B** (NOT `mmproj-F32`, 2.29 GB) | measured on `D:` |
| Header (`raw/84-qwenvl-header.txt`) | `qwen3vlmoe`, 48 blocks, 32 heads / **4 KV heads**, key_length 128, `context_length 262144`, `expert_used_count 8`, sampling 0.7 / 0.8 / 20, **no sliding-window key**, **no vision keys** in the main file | `raw/gguf_hdr.py` |
| KV arithmetic | 2 × 48 × 4 × 128 × 2 B = **98 304 B/token = 96 KiB** → 32 k = **3.0 GiB** (5× Gemma's 20 KiB) | header, not the model card |
| Decode | **23.84 t/s** — faster than the agent leg | `raw/68` |
| Boot + image cost | `lms load … -c 32768 --identifier vision-qwen3vl-30b -y --parallel 1` ready in **28 s**, **23.12 GiB** dedicated under a 2.28 GiB desktop. 8160×6120 photo: **4042–4060 prompt_tokens, 61–72 s** (≈56–66 t/s); 1120 px variant **937 tokens / 13.6 s** | `raw/68`, `raw/73`, `raw/88` |
| **It transcribes — when the target fills the frame** | Settled by cropping the same photo into a 2×3 grid chosen without looking at it, plus a known-answer control (`docs/assets/images/CRS328.png`, the repo's own label photo). Result: the wide 8160×6120 frame reads **`CRS326-24G-2S+RM`** five greedy times; the top-left quarter reads **`CRS328-24P-4S-RM`** four times; the label photo reads **`CRS328-24P-4S+RM`** — character-perfect against `docs/network-rack.md` U15, `+` included, for **528 tokens in 3.9 s**. Five of the other five tiles answered **`NOT VISIBLE`**, so it does not decorate empty frame with a plausible SKU | `raw/96-crop-probe.txt` |
| So the earlier "perception floor" reading was wrong | Written at 04:12Z from `raw/91`/`raw/92` and overturned by `raw/96` at 21:30Z: greedy agreement across five wide-frame answers proved the answer was *stable*, not that it was *perceived*. The correct statement is a pixel-allocation limit with a known fix, not a broken organ — and the 2026-09-29 "OCR'd it verbatim" claim stays corrected either way, because it was never reproducible **on the frame it claimed** | `raw/91`, `raw/92`, `raw/96` |
| **CROP, do not shrink (the cost rule)** | Image tokens **saturate**: full frame **4042–4060**, a 3264×3672 quarter **4065** — the same cap; 1120 px variant **937**; label closeup **528**. Past ~3 MP you pay the cap and discard detail, so a crop costs the same and reads. Shrinking was tested and is strictly worse: whole frame at 1/5 → `NOT VISIBLE` | `raw/96` |
| **The image-cache rule** | same question twice on one image costs **2.0 s** the second time; **any new question re-pays ~60 s** — the text part precedes the image in the message, so changing it invalidates the cached image tokens. Ask several things of one photo → put the image first or freeze the question | `raw/92` |
| 32 k window | **31 809 tokens accepted in 915 s**, **23.92 GiB** dedicated; over-window requests refused in 0 s (clean 400, no crash) | `raw/ctx32k.out` |
| Budget | 16.50 + 1.01 + 3.00 KV + 0 + 3.00 floor = **23.51 of 32 GiB**, margin +8.49 | `laptop-llm.py budget` |
| Owner rulings | **f16 KV** (q8_0 declined 2026-09-30 — and it would need `flash_attention: true`, unproven for this arch on Vulkan); one resident model | [`../../todo.md`](../../todo.md) HD-476 |

---

## 5 · Gate, budget, client

Commands and verbatim output are in [`raw/88-certify.txt`](raw/88-certify.txt) (certification probes)
and inline below.

```
$ python scripts/laptop-llm.py gate --self-test    → self-test: 13/13 canaries caught
$ python scripts/laptop-llm.py probe-vision --image x --self-test → vision self-test: 6/6 verdicts correct
$ python scripts/laptop-llm.py probe-fim --self-test             → fim self-test: 6/6 verdicts correct
$ python scripts/check_secrets.py                   → OK: no secret shapes in 1204 files
$ python scripts/check_placeholders.py              → OK: no placeholder tokens outside designated files
$ python -m py_compile scripts/laptop-llm.py scripts/render-pi-config.py → clean
$ bash scripts/validate-all.sh (git-bash, Windows)   → EXIT=1, ONE failure, pre-existing (§7)
$ python scripts/laptop-llm.py gate                → laptop-llm-gate: PASS (13 invariants, 1 profile,
                                                        active=agent-gemma-26b)
$ python scripts/laptop-llm.py probe-client        → client drift: PASS — laptop-lmstudio/agent-gemma-26b
                                                        matches profile 'agent-gemma-26b'
                                                        (contextWindow=32768, maxTokens=8192,
                                                         input=['text'], reasoning=True) — and the
                                                        engine is serving it: ['agent-gemma-26b']
$ powershell -File scripts\win\lmstudio-llm.ps1 switch -Profile agent-gemma-26b
                                                   → loaded in 15.98 s, serving id agent-gemma-26b
                                                        (raw/89-applier.txt — the proof for D3)
$ python scripts\render-pi-config.py --vendor pi --host Domen_P14s --out <scratch path>
                                                   → providers: ['entrim', 'spark', 'laptop-lmstudio']
                                                   → laptop models: ['agent-gemma-26b',
                                                        'vision-qwen3vl-30b',
                                                        'qwen/qwen2.5-coder-3b-instruct']
                                                        This is the D2 proof: the same render before
                                                        the hostname fix produced NO laptop-lmstudio
                                                        provider at all. Rendered to a scratch path,
                                                        NOT committed - a stale copy of a client's
                                                        model list in git is a drift hazard, and your
                                                        live ~/.pi/agent/models.json still carries
                                                        zero laptop rows (dated 2026-09-19). The
                                                        render into your config is your step, and
                                                        --check still needs `op signin`.
```

Both serving legs now report **CERTIFIED** in `matrix`; the four Qwen3.6/FIM arms still fail the gate,
which is correct — no weights on disk (the three `agent-unified*`) and unmeasured trigger latency
(`fim-coder-3b`). `probe-client` says **PASS**, not **SKIP**, which it had never done on this box
before this run (D2), and it now also refuses to pass when the named leg is not resident (D8).

Refusing-to-pass is not hypothetical — it fired for real while this run was finishing: with the
vision leg loaded, `probe-client` correctly failed the agent row:

```
client drift: FAIL — the client names 'agent-gemma-26b' but the engine serves ['vision-qwen3vl-30b'].
```

**The Debian suite did not run, and the reason is a trap, not an omission**
(`raw/93-wsl-validate-all.txt`). A Windows-created linked worktree writes its `.git` pointer as
`gitdir: D:/source/...`; git inside WSL cannot resolve that, so `guard-session.sh` reported *"not
inside a git work tree"* and stopped — **correctly**, rather than validating nothing and calling it
green. Debian's `python3` (3.13.5) also has no PyYAML, so `gate` and `render-pi-config.py` could not
have run there anyway, and installing into the system interpreter is a machine change nobody asked
for. The reference run for this lane is therefore the **git-bash** `scripts/validate-all.sh`: real
bash, real Python 3.13.13 + PyYAML, one failure, pre-existing (§7a).

---

## 6 · Defects found and fixed by this run

Each is listed with the wrong behaviour it produced, because "fixed a bug" without the symptom is
the same kind of claim this repo refuses to accept from a model.

| # | Defect | Wrong output it produced | Fix + proof |
|---|---|---|---|
| D1 | `reports/.../raw/hd477_run.py` called `say(msg, flush=True)` against `def say(s)` | Crashed with `TypeError` **after** the first 32 k prefill had burned ~8 minutes. The 2026-09-30 01:03 ladder "killed on the owner's instruction at 01:16" died of this bug on its own — a phase header with no body line is a crashed driver, not a thinking model. Both sessions lost the ladder to it | `say(s, flush=True)` + `LOG.flush()` per line + a `python hd477_run.py 3` phase-band argv. Phases 3–4 then completed |
| D2 | `hosts:` matching compared `gethostname().lower()` against the spec's `domenp14s`, but the box reports **`Domen_P14s`** | **Both** failure modes at once: `render-pi-config.py` **dropped the whole `laptop-lmstudio` provider** from the Windows render (so pi never saw it), and `probe-client` **SKIPped** instead of checking the drift it exists to check. Passing `--host DomenP14s` by hand masked it | `render-pi-config.py:host_norm()` / `host_matches()` — lowercase, first label, drop `_`/`-`/`.`. `probe-client` **imports** that matcher (importlib; a failed import is fatal, no fallback copy) so there is one opinion. Proved by contrast: this host → rendered, `oldsrv` → still skipped |
| D3 | `scripts/win/lmstudio-llm.ps1 switch` ran `lms load <key> --pub --gpu max --context <N>` | `--pub` and `--context` **do not exist in 0.4.25**: `switch` could never have worked, and without `-y` an unmatched key hangs on an interactive picker. No `--identifier` either, so nothing enforced the id the client contract names | Verified set from `load --help`: `--gpu --identifier -c -y --parallel --ttl --estimate-only --speculative-*`. Loads `<key> --gpu max -c <ctx> --identifier <profile> -y [--parallel N]`, then **proves** the served id via `lms ps` and refuses if it is absent. Refuses a fetch-hint identifier (`":" in ident`) |
| D4 | `probe-vision` hardcoded `max_tokens: 80` and read `msg["content"]` only | A **false negative on a working model**: thinking cannot be disabled server-side, so 80 tokens all go to `reasoning_content`, `content` is empty, and the probe reported "the projector cannot load". This is the exact bug the brief warned about, still in the file | `--max-tokens 1024` default, `msg_text()` (reads `reasoning_content`), `--expect <string only the image can supply>` for a mechanical verdict, `--self-test` 6/6 (empty / refusal / wrong reading / control-token leak / no-`--expect` all caught), and **HTTP class separation**: `{"error":"terminated"}` = engine crash (exit 1, a real capability verdict), other 4xx = contract error (exit 3, never a verdict) |
| D5 | `probe-speed`'s default prompt was a 300× repeat and non-streaming wall only | Measured a shape nobody sends, could not separate prefill from decode, and printed `t/s` derived from chars/4 assumptions | `--prompt-file` (real prose), `--label`, `--ttft` (streaming first token → `prompt_tokens / TTFT` for prefill, `completion / (wall − TTFT)` for decode). No decode-rate constant hardcoded in the print |
| D6 | `raw/gguf_hdr.py` read a GGUF array's element type as `uint8` | The reader desynced at the first array key and printed an **empty** metadata set for the Qwen-VL file — i.e. the KV arithmetic looked unreadable and would have been copied from the model card instead | Element type is `uint32`; the header now parses all 48 keys and `98 304 B/token` is derived from the file (`raw/84-qwenvl-header.txt`) |
| D7 | `scripts/pi-config/models-spec.yml` named `qwen/qwen3.6-35b-a3b-mtp` as the laptop's row while the dial was on `agent-gemma-26b` | The contract pointed at a model that is not on disk and never booted; pi would have 400'd on the first call. Nothing caught it because `probe-client` SKIPped (D2) | Rows are now the two legs that exist, keyed by **served identifier = profile name** (`--identifier <profile>`), with the image-size and one-resident rules written next to them |
| D8 | **LM Studio's endpoint does not police the `model` field.** With only the vision leg resident, a chat request naming `no-such-model-here` was answered — `'PONG'`, 0.4 s — **by the resident model** | A wrong or stale row in `models-spec.yml`, or the wrong leg loaded, is not a 400: the harness is silently served a DIFFERENT MODEL than the picker claims. (Images *are* policed: 400 *"does not support image inputs"* in 0 s — so the text-only leg fails loudly, which is the half of the contract that already worked.) This invalidated a claim this very report was about to make ("a dead row is loud") | `probe-client` now reads `/v1/models` and FAILs when the row it is certifying is not resident. Proven by the real transition: FAIL with the vision leg loaded → PASS after `switch -Profile agent-gemma-26b` |
| D9 | The repo's own claim that the vision leg "OCR'd `CRS328-24P-4S+RM` verbatim" was **not reproducible on the frame it named** | Not a code defect — a measurement claim that would have propagated into `network-rack.md` and been trusted. The new strict verdict (`--expect`, D4) is what caught it: five greedy passes on that frame answered `CRS326-24G-2S+RM`. **The evening follow-up (`raw/96`) refined the cause**: a blind quarter-crop read `CRS328-24P-4S-RM` and the known-answer label photo read it perfectly, so the limit is pixel allocation, not sight — the claim was still unreproducible *as written*, and the strict verdict was still right to fire | Recorded in §4, §6b and the profile row as `vision_caveat`, with the operative rule: **crop, do not shrink**, and re-ask of a crop before believing a disagreement |

### 6b · Things this run measured that contradict what this repo (or the previous session) said

| Claim before | Measured |
|---|---|
| "`probe-client` must PASS, not SKIP" was assumed achievable | On this box it could not: the hostname mismatch (D2) made it SKIP forever |
| Vision leg OCR'd the switch SKU and corroborated the rack doc | On that frame, five greedy passes said `CRS326-24G-2S+RM` — so the claim was corrected. Then `raw/96` cropped the photo and the SAME leg read `CRS328-24P-4S-RM`, and read the label photo character-perfect with the `+`. Both halves are true: the 09-29 claim was unreproducible **as written**, and the leg is not blind — it is frame-limited |
| "Two resident models fit, three do not" (§Memory & residency) | **One** 30B-class leg fits: the vision leg alone is 23.12–23.92 GiB of a ~24 GiB adapter |
| Decode ≈ 17.5 t/s, one number for the box | 21.1 / 18.3 / 8.3 t/s at 2.5 k / 10.6 k / 31 k tokens of context |
| Cold prefill ~250 t/s (small) — implied stable | At 10.6 k tokens the same prompt cost 259 s once and 69 s another time; at 20.8 k, 277–899 s across three loads |
| The ladder would show "bigger window costs more" | Memory: linear and cheap (~20 KiB/token). Time: not monotonic at all (359 / 899 / 277 s for one prompt) |
| Recall at 32 k was the open question | Answered: needle at 92 % depth returned at 28 984 tokens (§2c) |

---

## 7 · What this run did NOT close

* **Closed while you were asleep**, so it is stated here rather than buried: both legs are
  `certified: true` from `raw/88-certify.txt` + `raw/90-speed.txt` + `raw/91/92`, `gate` is green
  unaided, and `probe-client` PASSes against a live server. What follows is genuinely left over.
* **FIM trigger latency** (HD-401 gate 5) — `fim_probe` is passed (3/3 on the instruction-fenced
  surface, 6/6 self-test), but the 150–400 ms tab budget has never been measured on this model.
* **`render-pi-config.py --check`** — **blocked**: `op` reports *"account is not signed in"*. Reading
  `Homelab-ansible` is a human step (CONVENTIONS §6). The client contract is therefore verified by
  `probe-client` (field-level drift) and NOT by a byte-level render diff. Do not call the lane green
  on the subset.
* **LLVM target `gfx1150` vs `gfx1151`** — still unconfirmed for this APU. It does not block this
  lane (nothing here names a target), it blocks any future build or driver pin.
* **`:1234` LAN exposure** — untouched, still an owner decision, no firewall rule added.
* **`agent-unified*` (Qwen3.6-35B-A3B)** — still no weights on disk, still uncertified. The agent leg
  now beats it on margin without a 21 GB download; whether it beats it on *quality* is unmeasured.
* **The recall probe (§2c)** — **closed**: needle returned at 28 984 tokens, 92 % depth.
* **Streaming `usage` in `probe-speed --ttft`** — the server does not put `prompt_tokens` /
  `completion_tokens` in the stream unless asked (`stream_options.include_usage`), so the first
  pass of the shape sweep recorded TTFT with `prompt 0 tok`. Fixed and re-run; a number whose token
  count is 0 is not a measurement and the probe now says so instead of printing one.

---

## 8 · Coordination notes for the next session (written 2026-09-30 evening)

**9a · The duplicate `HD-477` is reconciled: the laptop row is now HD-486.** Two rows carried `HD-477` through a merge with nothing complaining — this lane's *"Gemma text-only load + larger context"* and the DNS lane's *"The DNS resolver does NOT float with the VIP"*. **The DNS lane keeps 477**: it is cited by `network-dns.md` (twice), `network-rejected.md` and `IaC/ansible/group_vars/all/main.yml`, and it is still active work, while every inbound reference to the laptop row sat inside this lane's own files. The laptop row therefore moved to the number `scripts/next-hd.sh` granted (`HD-486`), and its `todo.md` row carries that provenance in the tail. Earlier the same evening `HD-476` had the same problem, resolved from the other side: the DNS lane closed its row and minted `HD-480`…`HD-484`, which is why `HD-476` now reads unambiguously as this lane's vision leg. **Two things this does not fix.** The class of failure stays open as `HD-485` (*"`check_todo_done.py` is not duplicate-ID aware"*) — nothing stops two lanes branching from different bases and taking the same number again. And the raw captures keep the old digits in their filenames (`raw/80-hd477-gemma-textonly.txt`, `raw/hd477_run.py`), because a log that silently renames itself stops being evidence.

**9b · What the evening session (`raw/96`) changed.** The vision leg's inability to read the rack SKU
was reported here at 04:12Z as a perception limit and is now corrected to a frame/pixel-allocation
limit with a measured workaround (crop, don't shrink; token cost saturates ~4.1 k). `todo.md`,
`profiles.yml`, `docs/hardware-workstation.md` and `docs/services-ai.md` #28 all carried the earlier
wording and were updated in the same change. Lesson worth keeping: **greedy agreement proves
stability, not perception** — the way to test a reading you distrust is to change what is in the
frame, and to feed it one image whose answer you already know.

---

## 9 · State left behind

* Worktree **`D:\source\domenkogler\homelab-wt-hd474`**, branch `session/hd474-win11-certify-2`.
  The branch name from the brief (`session/hd474-win11-certify`) already exists **and is merged**
  (`5f1115f6`), so it could not be reused for a new worktree.
* **Nothing is committed** — owner instruction for this session was *"work in your own worktree,
  don't commit"*. Every file this run changed is dirty in that worktree, so the worktree is **kept**
  (a `git worktree remove` here would delete the lane's output, which is what the brief's cleanup
  step would otherwise do at a green merge).
* GPU left as found: `lms unload --all`.
* Rollback if anything is doubted: `lms unload --all`; the dial still reads `active:
  agent-gemma-26b`; `lms server stop`. Nothing in the client config is live until the owner renders
  it, and the render is gated on `op` anyway.
* **To re-verify this report in four commands** (≈4 minutes plus a 16 s load):
  `powershell -File scripts\win\lmstudio-llm.ps1 switch -Profile agent-gemma-26b` ·
  `python -X utf8 scripts/laptop-llm.py gate` · `python -X utf8 scripts/laptop-llm.py probe-client`
  · `python -X utf8 scripts/laptop-llm.py matrix`. The three timed shapes cost another ~2.5 minutes
  via `reports/hd474-laptop-leg/raw/90_speed_run.py`; the recall probe (§2c) is a 28-minute run and
  is not something to re-take casually.
* Files this run touched: 14 modified, 17 new under `reports/hd474-laptop-leg/` (`git status
  --porcelain` in the worktree is the exact list).
