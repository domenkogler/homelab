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

1. ⏳ **HD-469** — spark LLM profile switch: certification still running in the live session (worktree per §3); when it lands it unblocks the NVFP4 half of the 376 bench row.
2. ⏳ **HD-436** — the transport thread's hinge: rebase `session/hd436-zone-derived-wip` onto main, then switch the last two hand-authoring consumers (`vps.yml` headscale/traefik lists + the Cloudflare vars). Re-renders live edge routing — owner-present window. Detail: `prompt-436.md`.
3. ⏳ **HD-467** — P1: `upsd` binds loopback only, so no home host is UPS-protected and nothing can see a mains loss; the bind + listener fix is in the row.
4. ⏳ **HD-470** — the VPS's own state has one copy on one disk (id re-minted 2026-09-28; it had collided with 469).
5. ⏳ **HD-450** — nothing watches cert pair age at a consumer; the Signal alert channel exists now, only the age probe is owed.
6. ⏳ Cockpit/seat cluster → `prompt-361.md` (brief carried rows 361 · 411 · 442 · 443 · 444 · 445 · 446 · 465).
7. Owner-gated tails (exact steps in the rows): 377(a) Grafana render re-do · 444 phone-crossing drill · 418 restart window · 06 UPS drill · 47 federation join · 454 power-path buy/accept call.

Unbriefed open rows (no session launches from them; the rows live in [todo.md](todo.md) + [todo-table.md](todo-table.md) §B): 360 · 402 · 103 · 238 · 421 · 459 · 461 · 448. Whoever takes the VPS-hygiene residue forms the next **VPS + nas** lane; before touching ANY Authentik OIDC client read [docs/services-authentik.md](docs/services-authentik.md) §Blueprint authoring notes facts 7 + 9.

---

## 3. Live lane map (waves)

One brief = one session = one worktree; rules in [docs/orchestration.md](docs/orchestration.md) §4. Launch **one brief per lane**; never two briefs from one converge host; never a pair marked *never with*.

| Wave | Brief | Rows it carries | Converge host | Pairing |
|---|---|---|---|---|
| **1 — running now** | [prompt-llm.md](prompt-llm.md) | ⏳ **469** (converge + certify `spark_llm_profile`: `reasoning` → `graded` → `fast`; `fast-sglang` gate-blocked by design) | **spark**, engine restarts each flip | ⛔ never with 376; run **before** re-dispatching 376's NVFP4 half |
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
