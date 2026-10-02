> **Role:** entry point for the next session — a **lean handoff**, a pointer index and nothing else. Every
> item's authority is its [todo.md](todo.md) row; permanent knowledge is the owning doc
> ([docs/index.md](docs/index.md) map); the permanent process contract (working rules, orchestrator mode
> O1–O8, launch, merge/cleanup) is [docs/orchestration.md](docs/orchestration.md); the planning view for the
> human is [todo-table.md](todo-table.md). History is not kept here: session accounts live in owning-doc
> status blocks + git history (archive-only: `reports/changelog.md`, `reports/deployment-journal.md`).
> **Linked from:** [README.md](README.md) §0/§2 · [CONVENTIONS.md](CONVENTIONS.md) §4/§6 · [todo.md](todo.md) · [todo-table.md](todo-table.md) · [docs/orchestration.md](docs/orchestration.md)

---

## 1. Environment

WSL Debian primary, ext4 (repo runs from the WSL Debian primary, not Windows). `python3`/bash/LF/UTF-8 no-BOM. Secrets → 1Password `Homelab-ansible` item.field only, `>-` for YAML renders. Multi-line bash heredocs with backslashes/backticks get mangled through `bash -c` — write script bodies to a temp file and run them. **Signed-commit gotcha:** keys in `~/.ssh/github_signing`/`github_auth`; `Couldn't find key in agent` → `ssh-add ~/.ssh/github_signing ~/.ssh/github_auth`.

**Reachability is settled (HD-397 + HD-398 decision A) — read the one SSOT, do not re-derive it:** [network-vpn.md](docs/network-vpn.md) §Reaching LAN nodes when away (measured matrix + traps) and §The laptop alias contract (the only alias table; governs BOTH `~/.ssh/config` files). In one line: behind-NAT hosts (`pi`/`nas`/`oldsrv`/`spark`) are reached over the VPS jump onto their **Home leg**; the **Mgmt plane (VLAN 99) is same-site only** (`router`/`switch`/`ap-*`/`pi99`/`oldsrv99`/`nas99` — never a `ProxyJump`). `ssh oldsrv` = the Home address.

---

## 2. Next tasks (the rows are the authority; this is only the ranked pointer list)

1. ⏳ **HD-469** — spark LLM profile switch. Run #3 is closed and merged: the clock cap **converged**, `fast` **booted then rolled back** on a gate-3 finding, `graded` re-confirmed BLOCKED-ON-IMAGE. **Run #4 is ready and the operator's own model must not be spark** (rule 0 — a spark-served session cannot take a timed leg, which is why this leg is still open): the valuable thing is the **under-cap baseline**, which no run has ever recorded, because no `nvidia-smi` field proves the clock regime on GB10 — only a sustained `clocks.sm` trace under load does (`clocks.max.sm` is a capability field; the role's read-back assert was removed 2026-09-29 by owner ruling). Split out of it: **HD-475** (`fast` must drop `VLLM_GDN_DECODE_KERNEL=triton` for the plain mixed-NVFP4 build, then re-cert). When 469/475 land they unblock the NVFP4 half of the 376 bench row.
2. ⏳ **HD-436** — the transport thread's hinge: rebase `session/hd436-zone-derived-wip` onto main, then switch the last two hand-authoring consumers (`vps.yml` headscale/traefik lists + the Cloudflare vars). Re-renders live edge routing — owner-present window. Detail: `prompt-436.md`.
3. ⏳ **HD-467** — P1: `upsd` binds loopback only, so no home host is UPS-protected and nothing can see a mains loss; the bind + listener fix is in the row.
4. ⏳ **HD-471** — P1, the VPS-hygiene lane's new head: **Docling answers HTTP 200 with empty markdown for every real
   scan** (`read_only: true` + `tmpfs: /tmp` = **noexec** → the torch-inductor layout stage dies; canary already run:
   the same image converts the same pages with `--tmpfs /tmp:rw,exec`). Fix + warm-up + a memory limit, then
   re-POST a real scan and read `status`, never the HTTP code.
5. ⏳ **HD-470** — the VPS's own state has one copy on one disk (id re-minted 2026-09-28; it had collided with 469).
6. ⏳ **HD-450** — nothing watches cert pair age at a consumer; the Signal alert channel exists now, only the age probe is owed.
7. ⏳ Cockpit/seat cluster → `prompt-361.md` (brief carried rows 361 · 411 · 442 · 443 · 444 · 445 · 446 · 465).
8. Owner-gated tails (exact steps in the rows): 377(a) Grafana render re-do · 444 phone-crossing drill · 418 restart window · 06 UPS drill · 47 federation join · 454 power-path buy/accept call · **480/481** the DNS filtering intent — which block lists for Home, and whether Kids filtering covers VLAN-40 only or the two Home-VLAN tablets too (✅ **476** answered 2026-09-30: all three Technitium instances now forward — VPS cold-name p50 39 → ~18 ms, oldsrv 85 → ~40 ms).

Unbriefed open rows (no session launches from them; the rows live in [todo.md](todo.md) + [todo-table.md](todo-table.md) §B): 360 · 402 · 103 · 238 · 421 · 459 · 461 · 448 · **472** · **477** (make the DNS resolver actually float with the VIP — the premise is already measured green, the row carries the three gates) · **484** (what is LEFT of it is the seat's pi version bump — both halves the row existed for are CLOSED + LIVE 2026-10-01: the DNS leg (`llm.kogler.si` resolves, engine leg proven from the box), and the seat's pi defaults, where the phone's `no model available` / `Update failed: exec: "pi" …` turned out to be one missing systemd drop-in, not a missing pi install — A/B + the traps in [docs/services-ai.md](docs/services-ai.md) §9b-1) · **488** (the same host-resolver class on the Pi, where two docs already work around it, plus nas/spark unmeasured) · **487** (finish oldsrv's config-manager decision — the role renders networkd units on a box where networkd is disabled and names a NIC it does not have; lockout-class, so it runs off-box with the self-converge guardrail) · **485** (`check_todo_done.py` is not duplicate-ID aware — the reason the DNS lane minted from 480). Whoever takes the VPS-hygiene residue forms the next **VPS + nas** lane (HD-471 + HD-472 + HD-421 + HD-103 are now one Docling cluster, all converging the `docling` container alone); before touching ANY Authentik OIDC client read [docs/services-authentik.md](docs/services-authentik.md) §Blueprint authoring notes facts 7 + 9.

---

## 3. Live lane map (waves)

One brief = one session = one worktree; rules in [docs/orchestration.md](docs/orchestration.md) §4. Launch **one brief per lane**; never two briefs from one converge host; never a pair marked *never with*.

| Wave | Brief | Rows it carries | Converge host | Pairing |
|---|---|---|---|---|
| **1 — ready; nobody running it** | [prompt-llm.md](prompt-llm.md) | ⏳ **469** (the under-cap baseline trace + `reasoning` re-cert) · **473** (engine pin, ⛔ upstream-blocked, 40 s re-check) · **475** (`fast` triton fix → gates 0–7); `fast-sglang` gate-blocked by design | **spark**, engine restarts each flip | ⛔ never with 376; run **before** re-dispatching 376's NVFP4 half; ⚠ **the operator's model must not be spark** (gate rule 0 — run #3 could not take its own timed legs) |
| **1 — ready; nobody running it** | [prompt-fast.md](prompt-fast.md) | **489** (upstream v16b funnel: 12 candidate profiles on the same dial — offline half DONE, 2 gates open on purpose) | **spark**, offline until the build leg | ⛔ rule 0 again — timed legs from a client outside the served loop; ⚠ nothing deleted for disk, the ~130 GB stages on `/` |
| **1 — laptop seat** | [prompt-lmstudio.md](prompt-lmstudio.md) | ⏳ **474** (owner-side only now: merge the lane, `op signin` then render the client, and rule on `networkingMode=mirrored` + the broken `check_merge_markers` canary) · ⏳ **476** — its SKU question **closed 2026-09-30 evening**: a blind quarter-crop of the same rack photo read `CRS328-24P-4S-RM` and the repo's label photo read it character-perfect, so the misread was pixel allocation, not sight, and the rule for any seam reading small text is **crop, never shrink** (image tokens saturate at ~4.1 k whether the input is the full frame or a quarter of it); what is left on that row is that the 23.51 GiB declared budget has never been exercised with an image resident in the KV of a 32k window · ⏳ **HD-486** — the *"Gemma text-only load + larger context"* row (**renumbered from 477 on 2026-09-30**; that id is now unambiguously the DNS VIP row, cited by `network-dns.md`, `network-rejected.md` and `IaC/ansible/group_vars/all/main.yml`), whose un-taken lever is 8-bit KV — needs `flash_attention` proven on Vulkan) — **both legs are measured and `certified: true`, gate green; evidence in [reports/hd474-laptop-leg/](reports/hd474-laptop-leg/)** | **the laptop, in Windows** — no Ansible converge, no shared host | only rule 0: a session served by `laptop-lmstudio` may not take its own timed numbers · can run alongside the spark/oldsrv lanes |
| **2** | [prompt-384.md](prompt-384.md) | 384 · 403 · 387 · 373 · 249 | oldsrv + VPS `docker_services` | ⛔ never with 357 / 361 (all converge oldsrv) |
| **2** | [prompt-376.md](prompt-376.md) | 376 · 400 · 359 · 367 · 380 | **spark**, owner bench window | with 384 **only in an open bench window**, else alone · ⛔ never with 469-lane |
| **3** | [prompt-357.md](prompt-357.md) | 357 · 17 · 217 · 358 · 418 (window-gated) | **oldsrv** | runs when the oldsrv slot is free · ⛔ never with 384 / 361 |
| **3** | [prompt-436.md](prompt-436.md) | 436 · 435 · 460 | router slot + Cloudflare | owner-present window (live edge routing) |
| **3** | [prompt-361.md](prompt-361.md) | 361 · 411 · 442 · 443 · 444 · 445 · 446 · 465 | **oldsrv** (+nas/pi read-back) | ⛔ never with 384 / 357 (oldsrv slot) |

Lane sessions: read [docs/orchestration.md](docs/orchestration.md) §4 **first** — it overrides README §4 / CONVENTIONS §6 at O1–O8. A lane touches only its own rows + owning docs + runbook lines; `prompt.md` and `todo-table.md` are orchestrator-only (O2).

---

## 4. Contract (pointers — the text lives in [docs/orchestration.md](docs/orchestration.md))

- **Step-0 ritual, in order:** conventions map (`grep -n "^#\|^## \|^### " CONVENTIONS.md | head -40`) → `git status` → fresh session worktree (`git worktree add ../homelab-wt-<date>-<HHMM>`, guard-enforced).
- **Prior-art sweep** before new rows (todo + owning docs + rejected logs + `git log -S`) — re-decide ban.
- **Green before finish:** `bash scripts/validate-all.sh`.
- **Lifecycle:** fully-done row deleted, record in owning doc + commit; deploy-gated row keeps a ⏳ tail.
- **Close-out:** owning doc + row tail + runbook line (if a manual step ran) + this handoff; signed commit.
