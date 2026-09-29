# `prompt-lmstudio.md` — Lane brief · boot the laptop's LM Studio leg and certify it (HD-474) · runs on **Win11**

> **Entry:** the owner says **"read prompt-lmstudio and run it"** — you are the operator, and you are
> running **on the laptop, in Windows** (`pi.dev` on Win11), because that is where the engine lives.
> Everything that could be settled from the repo is settled: the catalogue, the arithmetic, the gate,
> the applier and the client contract are **already merged** (`7f77042`). What is left needs the box:
> **make it true**, or report exactly where it stopped and why.
>
> **Read first, in this order:** this file §0 → [README.md](README.md) §0 + §1 →
> [CONVENTIONS.md](CONVENTIONS.md) §6 (secrets) / §7 (pins) / §15 (SSOT) →
> [docs/hardware-workstation.md](docs/hardware-workstation.md) §Served leg (the decision, the
> arithmetic, what is unproven) + §Memory & residency + §Leg 1 + §Leg 2 →
> [scripts/laptop-llm/profiles.yml](scripts/laptop-llm/profiles.yml) (read it top to bottom — it *is*
> the spec) → the `HD-474` / `HD-401` / `HD-409` rows in [todo.md](todo.md) §2.
>
> **Linked from:** [todo.md](todo.md) HD-474 · [docs/hardware-workstation.md](docs/hardware-workstation.md) ·
> [prompt.md](prompt.md)

## 0 · Already settled — do not spend your window re-deriving it

| Thing | State | Where |
|---|---|---|
| **Runtime = LM Studio, not Ollama.** Both wrappers run the same llama.cpp **Vulkan** engine on `gfx1150` (no Windows ROCm for this APU), so the wrapper is worth ≈0 t/s. It was decided on **vision**: LM Studio loads `--mmproj` today; Ollama's Modelfile has no projector instruction, `ADAPTER mmproj` 500s (#15346), two `FROM` hang (#17491), and `qwen35moe` was unknown to its vendored llama.cpp until #15899/#16031. Plus Ollama skips iGPUs without `OLLAMA_IGPU_ENABLE=1` and 0.30 dropped `gfx1150` → silent CPU (#16690/#16701). | merged | [docs/hardware-workstation.md](docs/hardware-workstation.md) §Served leg |
| **Models are fixed.** `unsloth/Qwen3.6-35B-A3B-MTP-GGUF` Q4_K_M + `mmproj-BF16.gguf` (text **and** vision), `lmstudio-community/Qwen2.5-Coder-3B-Instruct-GGUF` Q4_K_M (FIM). Owner decision: no further model exploration. The library on `D:\llm\models` (~152 GB) is reused; **nothing re-downloads** except the one ~21 GB gap. | catalogue | [scripts/laptop-llm/profiles.yml](scripts/laptop-llm/profiles.yml) |
| **This family's KV is 20 KiB/token, not 96.** Hybrid arch: 40 layers as 10 × (3 × Gated DeltaNet → 1 × Gated Attention) ⇒ only **10** layers hold KV, 2 KV heads × head_dim 256 ⇒ `2·10·2·256·2 = 20 480 B/token`; the 30 linear layers hold a **constant** state per sequence. So 32k f16 KV costs **0.62 GiB** and q8_0 buys 0.31 GiB — which is why `agent-unified` runs f16 KV (a quantized KV cache needs flash attention, unproven for this arch on Vulkan). | merged | same, §Served leg |
| **MTP and vision cannot share a load** (unsloth's own README; tracker #1951 shows zero/negative gain on 35B MoE). Two profiles, same weights: `agent-unified` (vision) vs `agent-unified-mtp` (text). | gate invariant 9 | [scripts/laptop-llm.py](scripts/laptop-llm.py) |
| **Budget against the 32 GiB carve:** `agent-unified` 18.63 + 0.93 + 0.62 + 0.06 + 3.00 = **23.25 → +8.75 margin**; `fim-coder-3b` **4.94 → +27.06**. | computed + `budget` | `python scripts/laptop-llm.py budget --profile agent-unified` |
| **The gate is proven offline.** `gate --self-test` breeds **13 canaries**, one per invariant, and refuses any canary that passes. It is validate-all item 23. | merged | `bash scripts/validate-all.sh` |
| **The seat is Windows-native** (owner, 2026-09-29). Local models are served to **pi.dev on Win11**. **`/etc/wsl.conf` is not to be touched** — WSL2 is `networkingMode=Nat` deliberately, so `127.0.0.1` inside the guest is the guest, and `providers.laptop-lmstudio` carries `native_only: true` so the WSL render omits it. Never "fix" a WSL probe by reconfiguring the guest. | merged | [scripts/pi-config/models-spec.yml](scripts/pi-config/models-spec.yml) |

**The FIM contradiction is still open on paper and is yours to close:** this doc's §Leg 1 requires a
FIM-trained model and states Instruct variants "do not do it", while Qwen2.5-Coder's own card
documents chat-template FIM on the Instruct weights. `probe-fim` settles it with a cursor-shaped
completion. Do not resolve it by reading harder — one probe answers it.

**Rule 0, same class as spark's:** if your own `pi.dev` session is served by `laptop-lmstudio`, you
may not take timed numbers (`probe-speed`, `probe-ctx` timings) — you would be measuring a leg that is
answering you. Read-only state and `/v1/models` are fine. Either run the timed legs from a session on a
remote model, or hand them to the owner.

**Measured for you so you do not rediscover it:** the Windows seat has **Python 3.13.13 + PyYAML
6.0.3** at `C:\Users\domen\AppData\Local\Programs\Python\Python313\python.exe` (verified from WSL
interop on 2026-09-29), so `python scripts\laptop-llm.py …` runs natively — the driver's stdlib-only
core plus `yaml` is all it needs. If a future run finds it missing, `pip install pyyaml` is the whole
fix; do not route the driver through `wsl python3` to avoid that, because then it is reading Windows
paths (`D:\llm\models`) from the guest, which is how a file check starts lying.

## Non-negotiables

* **Worktree before writes** (§6, README §4):
  `git worktree add ..\homelab-wt-hd474 -b session\hd474-win11-certify main`, work there, `git worktree remove` at the end.
* **Never edit an assert, a gate invariant or a budget constant to make it pass.** The measurement is
  the thing to change. `held_floor_bytes` may only move **down**, and only from a measured
  Task-Manager *GPU → dedicated-memory* peak — never from optimism.
* **No silent 20 GB.** The applier reports a missing file; you fetch it deliberately (LM Studio search →
  `unsloth/Qwen3.6-35B-A3B-MTP-GGUF`: the Q4_K_M shard set **and** `mmproj-BF16.gguf`), into the exact
  path the catalogue prints. Verify sizes afterwards — a partial download presents as a valid directory.
* **One model resident.** `lms unload --all` before every load (the applier does this first, on purpose).
  Two residents on one carve is the documented amdgpu failure mode.
* **Secrets (§6):** `~\.lmstudio\settings.json` carries `hfDownloadToken` and `useHFProxy` — it is
  **never** committed, only merged by the applier (it makes a timestamped backup). `.lmstudio\credentials\`
  is never synced. The `apiKey: lmstudio-local` in the spec is a placeholder for a listener with no auth —
  if `:1234` ever leaves loopback it stops being a placeholder and needs a vault credential.
* **Do not expose `:1234`** to the LAN, and do not add a firewall rule for it. An unauthenticated
  inference endpoint on your wifi is a decision, not a side effect.
* **Pin before you time (§7).** LM Studio auto-updates; `runtime.version` is `null` in git, which is why
  the gate refuses certification. Record the real version **first**, or every number you collect is
  unattributable to a build.
* **`certified: true` requires an evidence directory**, not prose ([`reports/hd474-laptop-leg/`](reports/)).

## The switch you are testing

```powershell
cd <repo>\homelab-wt-hd474
# offline, no engine, no download — read the whole catalogue before you touch anything:
python scripts\laptop-llm.py matrix
python scripts\laptop-llm.py budget --profile agent-unified
python scripts\laptop-llm.py gate                     # FAILS today, by design: read the reasons
# the applier (never elevated; LM Studio's store and presets are per-user):
powershell -File scripts\win\lmstudio-llm.ps1 init
powershell -File scripts\win\lmstudio-llm.ps1 status
powershell -File scripts\win\lmstudio-llm.ps1 switch -Profile agent-unified -AllowUncertified
powershell -File scripts\win\lmstudio-llm.ps1 verify
```
Read the gate's four complaints before using `-AllowUncertified`: unpinned engine version, pending
vision probe, pending tool probe, nothing certified. That list **is** your task list, and the flag only
buys you permission to boot something in order to prove it — never to mark it certified.

## Sequence

**0 · Version first.** `& "$env:USERPROFILE\.lmstudio\bin\lms.exe" version` **and** the in-app
*About* string; if they disagree, believe the in-app string and say so. Put it in
`runtime.version` in the catalogue. Check `lm-studio-updater\pending\` — an update sitting there means
the number you just recorded is about to be a lie; either let it update and then pin, or pin and
disable auto-update for the session, and write down which you did.

**1 · `init`.** Merges the catalogue-owned keys into `settings.json` (backup first), writes
`config-presets\homelab-*.json`, and checks `D:\llm\models` by presence/size. `downloadsFolder` must
land on the existing library — that single key is the difference between reusing 152 GB and
re-downloading it into `C:`.

**2 · Fetch the gap, once.** ~21 GB: Q4_K_M + `mmproj-BF16.gguf`. After it lands, set `on_disk: true`
on the model row and re-run `matrix` until the row stops complaining.

**3 · Boot + `probe-health`.** Everything downstream depends on this one. If the server answers but
`lms ls` shows the model on **CPU**, that is the finding — check the carve is still 32 GiB in BIOS and
read the load log's `offloaded N/N layers` line. Copy that line into the report; it is the only
evidence that "100 % GPU" is true.

**4 · `probe-ctx --profile agent-unified`.** The **load-time clamp**, not the app's slider, bounds the
window — spark's precedent is 20 468 usable against a nominal 32 768 (HD-376). Whatever number it
prints becomes **both** the profile's `context_length` **and** `models-spec.yml`'s `contextWindow`, in
the same commit — `probe-client` fails if they disagree, and pi 400s mid-session if you ship it anyway.

**5 · `probe-tools`, then `probe-vision --image <real photo>`.**
* `probe-tools` failing is a **fork in the road, not a bug to fix**: without reliable tool calls the
  laptop is **not** an agent leg — it is vision + judgment (decision #28's original wording). Then
  `capabilities: [tool]` comes out of `models-spec.yml`, the docs and the row get rewritten, and
  `agent-unified` stops claiming it. Report the failure shape (refused? malformed? truncated?) — that
  decides whether it is the server or the parser.
* `probe-vision` must record **where the projector ran**, not just that a caption came back: a
  CPU-resident mmproj answers, slowly, and you would certify a lie. The pass criterion is a correct
  reading of something only the image contains (text in the photo), plus the load log showing the
  projector's layers on the GPU.

**6 · `probe-fim --profile fim-coder-3b`.** Passes only on a real infill: it must bridge a
cursor-marked gap (`before ·<cursor>· after`) with the connecting token, not continue the text or
echo the whole file. If it fails, the FIM row changes model — the named pair in §Leg 1 is the
reference — and you record that the Qwen card was wrong for these quantised weights.

**7 · `probe-speed`** (rule 0 applies). Record tok/s **and TTFT** at the agent's real prompt shape
(~15–20k tokens in), not a 40-token hello. HD-401's gate 3 is what this feeds: a leg that answers at
30 t/s on a toy prompt and 0.5 tokens/s to first token on a real one is not an agent leg.

**8 · Certify, then wire the client — in that order.** Flip `tool_probe` / `vision_probe` /
`fim_probe` to `passed` **with the evidence path in the row**, set `certified: true` on what actually
passed, run `gate` (it must go green on its own), then:
```powershell
python scripts\render-pi-config.py pi --host DomenP14s --check     # drift only, writes nothing
python scripts\laptop-llm.py probe-client                          # must PASS, not SKIP
```
Rendering is what puts the laptop in the model picker — do it last, never first.

## Offline checks (Windows has no ansible — run the subset that exists natively)

```powershell
python scripts\laptop-llm.py gate --self-test        # 13/13
python scripts\check_secrets.py                     # §6 sweep
python scripts\check_placeholders.py
python -m py_compile scripts\laptop-llm.py scripts\render-pi-config.py
```
Full `bash scripts/validate-all.sh` (CONVENTIONS §6 wants it green before merge) needs bash + ansible:
run it **in a WSL worktree of the same branch** — a *worktree*, never the primary checkout, which
`guard-session` will (rightly) refuse to validate while dirty. If bash/ansible genuinely aren't
available, say so in the report and let the owner decide; do not declare the lane green on the subset.

## Report + commit

Write [`reports/hd474-laptop-leg/README.md`](reports/) as measurements, not narrative: engine version +
where you read it, the load log's `offloaded` and KV-buffer lines, every probe command with its output
verbatim, tok/s + TTFT with the prompt shape, Task-Manager GPU dedicated-memory peak, and the **exact**
BIOS carve read-back. Then: cite that directory from the catalogue's `certified_evidence`, shorten the
`HD-474` row to what you proved and keep what you did not, sweep every claim your run made stale
(§Served leg, §Leg 1, the budget table), sign the commit, and **merge only if the full validator is
green** — otherwise stop and report.

**Rollback** is boring, which is the point: `lms unload --all`, `active: fim-coder-3b` (the cheap leg),
or just stop the Local Server. Nothing in the repo's client config is live until step 8, so a failed
session leaves the harness exactly where it is now.
