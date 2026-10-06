> **Role:** entry point for the next session — a **lean handoff**, a pointer index and nothing else. Every item's authority
> is its [todo.md](todo.md) row; permanent knowledge is the owning doc ([docs/index.md](docs/index.md) map); the permanent
> process contract (working rules, orchestrator mode O1–O8, launch, merge/cleanup) is
> [docs/orchestration.md](docs/orchestration.md) §4; the planning view for the human is [todo-table.md](todo-table.md).
> **No history lives here** — session accounts live in owning-doc status blocks + git history (archive-only:
> `reports/changelog.md`, `reports/deployment-journal.md`). A `prompt-*.md` brief carries a lane's contract and order of
> work; it never restates a row.
> **Linked from:** [README.md](README.md) §0/§2 · [CONVENTIONS.md](CONVENTIONS.md) §4/§6 · [todo.md](todo.md) ·
> [todo-table.md](todo-table.md) · [docs/orchestration.md](docs/orchestration.md)

---

## 1. Environment

WSL Debian primary, ext4 (the repo runs from the WSL Debian primary, not Windows). `python3`/bash/LF/UTF-8 no-BOM.
Secrets → 1Password `Homelab-ansible` `item.field` only, `>-` for YAML renders. Multi-line bash heredocs with
backslashes/backticks get mangled through `bash -c` — write script bodies to a temp file and run them.
**Signed-commit gotcha:** keys `~/.ssh/github_signing` / `github_auth`, both in `Homelab-ansible` (HD-495), so
`git-bootstrap.sh --ssh-auth` needs no `op signin`. On the **oldsrv seat** `user.signingkey` is the key FILE, not
`key::<pub>` — the `key::` form needs `SSH_AUTH_SOCK` and fails `Couldn't get agent socket?` in a non-interactive
shell, which is how an agent runs here. `Couldn't find key in agent` on a `key::` config →
`ssh-add ~/.ssh/github_signing ~/.ssh/github_auth`.

**Reachability is settled — read the one SSOT, do not re-derive it:**
[network-vpn.md](docs/network-vpn.md) §Reaching LAN nodes when away (measured matrix + traps) and §The laptop alias
contract (the only alias table; governs BOTH `~/.ssh/config` files). In one line: behind-NAT hosts
(`pi`/`nas`/`oldsrv`/`spark`) are reached over the VPS jump onto their **Home leg**; the **Mgmt plane (VLAN 99) is
same-site only** (`router`/`switch`/`ap-*`/`pi99`/`oldsrv99`/`nas99` — never a `ProxyJump`). `ssh oldsrv` = the Home address.

## 2. Next tasks (the rows are the authority; this is only the ranked pointer list)

1. ⏳ **HD-469** — spark LLM profile switch: take the **under-cap baseline** trace (only a sustained `clocks.sm` trace under
   load proves the clock regime on GB10), then `reasoning` gates 5–7. Run it from a session whose own model is **not**
   spark (rule 0). Split out of it: ⏳ **HD-475** (`fast`'s triton fix — code-first) and ⛔ **HD-473**
   (engine pin, upstream-blocked, ~40 s re-check). → [prompt-llm.md](prompt-llm.md)
2. ⏳ **HD-489 tail** — the winner is live and every leg ran; two certificate items remain: **read the gate-7 memory-curve
   day** accruing since 2026-10-06 11:19Z · then rewrite `fast.certified_evidence` and delete the row. `fast`'s **gate 6**
   was taken 2026-10-06 on the live 20 GB shape ([`spark/reports/hd489-tail-gate6-20261006-2349/`](spark/reports/hd489-tail-gate6-20261006-2349/RESULTS.md))
   — PASS, with the battery's `max_tokens 1024` vs reasoning-on confound named in it: deciding that battery budget is an
   owner call, not a quiet edit to `spark/bench/accuracy-gate.sh`. ⛔ B10's gates 6/8/9 were **declined by owner** and B9 · B5 · B8
   are closed — do not re-run any of them. → [prompt-remaining-bench.md](prompt-remaining-bench.md)
3. ⏳ **HD-436** — the transport lane's hinge: the derived `zone_kogler_si` list is already on `main`; switch the two
   consumers that still hand-author (`vps.yml`'s two subdomain lists, `roles/cloudflare_dns/vars`
   `cloudflare_dns_records`). Re-renders live edge routing → owner-present. → [prompt-436.md](prompt-436.md)
4. ⏳ **HD-470** — the VPS's own state has one copy on one disk.
5. ⏳ **HD-450** — nothing watches cert pair age at a consumer; the Signal alert channel exists, only the age probe is owed
   (and it now also owes the NUT client→master leg probe, the class the 2026-10-07 UPS fix left standing).
6. ⏳ Cockpit / coding-seat / grants cluster → [prompt-361.md](prompt-361.md) (rows 361 · 411 · 465 · 444; of the
   the 442–444 block, whose rows keep owner-gated tails).
   ⏳ **HD-495**: role-own the oldsrv seat's git plumbing (a rebuild still loses signing silently). The seat's
   **venv is not the gap** the row claimed — ansible core 2.21.5 is installed in `~/ansible-venv`, and the
   playbook syntax gate runs green there now that `validate-all.sh` activates the venv itself.
7. Owner-gated tails (exact steps in the rows): 377 Grafana render re-do · 444 the phone-crossing drill · 418 the HA restart
   window · HD-06 the UPS drill · HD-47 the federation join · 454 the human's own buy decision · 411 the cockpit resume word.

**Unbriefed open rows** (no session launches from them; the rows live in [todo.md](todo.md) +
[todo-table.md](todo-table.md) §B): 360 · 103 · 238 · 421 · 459 · 461 · 448 · **472** · **477** (make the resolver actually
float with the VIP — premise measured green, the row carries the three gates and its place in the sequence) · **488** (the same host-resolver class on the Pi, where two docs already
work around it) · **487** (finish oldsrv's config-manager decision — lockout-class, so it runs off-box) · **494** (only the
re-derive of the global host-floor ceiling — with the 2026-10-06 transient burst as its reserve evidence — and HD-380's
`gpu_top_mib` growth check are left, the gate-7 window accruing since 11:19Z; the gate-4/gate-5 legs closed inside the
**spark** slot of the HD-489 tail lane, so do not open a second writer there) · **1085** (the tmux seat harness: one
owner act — mouse-drag text inside a tmux pane on oldsrv and paste it where you typed, which is the OSC 52 leg no in-repo
probe can reach — plus one `--push` wired into `install-pi-debian.sh`; mechanism and traps in
[docs/pi-harness.md](docs/pi-harness.md) §5b, do not edit `~/.tmux.conf` by hand). · **1082** (Prowlarr carries no torrent download client while three torrent indexers are enabled — one registration at `gluetun:8080`, then one traced grab; procedure in [deployment-manual.md](deployment-manual.md) §P3.6) · **362 tail** (the Lidarr credential is fixed and authenticates, but nobody has pushed an album through `lidarr-ydl` or exercised Aurral's add path since — verify the legs, do not re-litigate the key) · **1083** (loopback-only publishing for the routed group — an owner call; if taken it is ONE converge of every routed service plus the edge's routes)

**Every DNS lane must obey this and no row can re-derive it** — it is in **HD-480's row**:
480/481/482/483 are one lane with one writer on `technitium-seed.yml`, converging `dns-pi` **once**
(HD-488 rides it); **HD-477 runs after**; **HD-487 runs alone**; and the acceptance includes the pi-web seat loading **with
Technitium stopped**. The owner rulings behind it (2026-10-01: 480 · 481 · 482 · 483 · 487 · 488 · 454 · 465) are recorded
**once** in the owning docs — [network-dns.md](docs/network-dns.md) §The tier policy the owner ruled +
[network-rejected.md](docs/network-rejected.md).

**Whoever takes the VPS-hygiene residue forms the next VPS + nas lane** — **HD-472 + HD-421** are what is left of the
Docling cluster (HD-471 + HD-103 closed 2026-10-07: the `/cache` bind is live, a 300 dpi image-only Slovenian scan
returns `status: success` with real markdown, and the 6 GiB ceiling is read back on the container), still converging
the `docling` container alone. Before touching ANY Authentik OIDC client, read
[services-authentik.md](docs/services-authentik.md) §Blueprint authoring notes, facts 7 + 9.

## 3. Lane map

One brief = one session = one worktree; rules in [docs/orchestration.md](docs/orchestration.md) §4. Launch **one brief per
lane**; never two briefs on one converge host; never a pair marked *never with*.

| Wave | Brief | Rows it carries | Converge host | Pairing |
|---|---|---|---|---|
| **1 — ready** | [prompt-llm.md](prompt-llm.md) | ⏳ **469** · **473** (⛔ upstream-blocked, 40 s re-check) · **475** | **spark**, engine restarts per flip | ⛔ never with prompt-remaining-bench or prompt-376 (same host) · ⚠ **the operator's model must not be spark** (rule 0) |
| **1 — ready** | [prompt-remaining-bench.md](prompt-remaining-bench.md) | ⏳ **489** tail: gate 6 on the live shape + read the gate-7 day (B9 · B5 · B8 closed, B10's gates declined; **494**'s legs landed) | **spark**, boots owner-gated | ⛔ rule 0 — timed legs from a client **outside** the served loop, stamped `--client`. Timed harness = [`spark/bench/run-scenario.sh`](spark/bench/run-scenario.sh) (+ `vm-window.sh`, `snapshot-metrics.sh`, `stress-oom.sh`, `accuracy-gate.sh`); pass/fail ladder = [spark/llm-profiles/README.md](spark/llm-profiles/README.md) (gates 0–9); evidence under `spark/reports/` |
| **1 — laptop seat** | [prompt-lmstudio.md](prompt-lmstudio.md) | ⏳ **474** (owner hands: `op signin` → render → `probe-client` PASS) · **476** · **486** (needle at ≥90 % of the 150 016 window + the prefill ladder) | **the laptop, in Windows** — no Ansible converge, no shared host | rule 0 only; can run alongside the spark/oldsrv lanes |
| **2** | [prompt-384.md](prompt-384.md) | **384 · 403 · 387 · 373 · 249** | oldsrv + VPS `docker_services` | ⛔ never with 357 / 361 (oldsrv slot) |
| **2** | [prompt-376.md](prompt-376.md) | **376 · 400 · 359 · 367 · 380** | **spark**, owner bench window | with 384 **only** in an open bench window, else alone · ⛔ never with the 469 lane |
| **3** | [prompt-357.md](prompt-357.md) | **357 · 17 · 217 · 418** (window-gated) | **oldsrv** | runs when the oldsrv slot is free · ⛔ never with 384 / 361 |
| **3** | [prompt-436.md](prompt-436.md) | **436 · 435 · 460** | oldsrv + VPS + Cloudflare (no router slot) | owner-present window — it re-renders live edge routing |
| **3** | [prompt-361.md](prompt-361.md) | **361 · 411 · 442–444 · 465** | **oldsrv** (nas/pi read-back only) | ⛔ never with 384 / 357 (oldsrv slot) |

Lane sessions: read [docs/orchestration.md](docs/orchestration.md) §4 **first** — it overrides README §4 / CONVENTIONS §6 at
O1–O8. A lane touches only its own rows + owning docs + runbook lines; `prompt.md` and `todo-table.md` are
orchestrator-only (O2).

## 4. Contract (pointers — the text lives in [docs/orchestration.md](docs/orchestration.md))

- **Step-0 ritual, in order:** conventions map (`grep -n "^#\|^## \|^### " CONVENTIONS.md | head -40`) → `git status` →
  fresh session worktree (`git worktree add ../homelab-wt-<date>-<HHMM>`, guard-enforced).
- **Prior-art sweep** before any new row (todo + owning docs + `<domain>-rejected.md` + `git log -S`) — re-decide ban.
- **Green before finish:** `bash scripts/validate-all.sh`.
- **Lifecycle:** a fully-done row is deleted, the record goes to the owning doc + commit; a deploy-gated row keeps a ⏳ tail.
  **A brief dies with its lane** (O7): the orchestrator deletes it in the same commit as its link fixes.
- **Close-out:** owning doc + row tail + runbook line (if a manual step ran) + this handoff; signed commit.
