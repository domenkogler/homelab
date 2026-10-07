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

**The pi-dev seat is `oldsrv`** (the primary coding seat — harness state in [docs/pi-harness.md](docs/pi-harness.md)); the
laptop's WSL Debian clone is the durable **runner**, and owner/cleanup sessions also run from the **Win11 Git-Bash** seat.
`python3`/bash/LF/UTF-8 no-BOM (`.gitattributes` pins `eol=lf`, so a checkout is LF on Windows too). On a Win11 seat four
gates were silently blind or misleadingly red until 2026-10-07 — MSYS text mode makes `grep` miss the CR of a CRLF pair
(`grep -U` is mandatory in encoding guards), `git` lives in `/mingw64/bin` not `/usr/bin`, and a case ending in a tmux/ansible
probe must print SKIP, not a verdict (CONVENTIONS §6; the sweep rule is [docs/orchestration.md](docs/orchestration.md) §4 step 5).
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
2. ⏳ **HD-489 tail** — the winner is live, every leg ran, and **one** certificate item is left: the owner ruled
   gate 6's battery up to `max_tokens 16,384` (16 × 2^10) on 2026-10-07 — **recorded, not applied** — and applying it
   means re-running the **B1 baseline in the same change**, because grading the reasoning arm against a baseline made
   under the old 1024 budget is not a measurement. **Gate 7 is CLOSED**: read twice on 2026-10-07 over the accruing
   window and PASS both times — a bounded fill, one +5,626 MiB step then flat at 99,649 MiB, 0.0 MiB/h tail, 0 restarts
   ([`spark/reports/hd489-tail-gate7-20261007/`](spark/reports/hd489-tail-gate7-20261007/RESULTS.md));
   `fast.certified_evidence` now says the shape's real history, so the row can go once the battery lands. The gate-6
   confound it replaces is in [`spark/reports/hd489-tail-gate6-20261006-2349/`](spark/reports/hd489-tail-gate6-20261006-2349/RESULTS.md).
   ⛔ B10's gates 6/8/9 were **declined by owner** and B9 · B5 · B8 are closed — do not re-run any of them. → [prompt-remaining-bench.md](prompt-remaining-bench.md)
3. ⏳ **HD-436** — the transport lane's hinge: the derived `zone_kogler_si` list is already on `main`; switch the two
   consumers that still hand-author (`vps.yml`'s two subdomain lists, `roles/cloudflare_dns/vars`
   `cloudflare_dns_records`). Re-renders live edge routing → owner-present. → [prompt-436.md](prompt-436.md)
4. ⏳ **HD-450** — nothing watches cert pair age at a consumer; the Signal alert channel exists, only the age probe is owed
   (and it now also owes the NUT client→master leg probe, the class the 2026-10-07 UPS fix left standing).
5. ⏳ Cockpit / coding-seat / grants cluster → [prompt-361.md](prompt-361.md) (rows 361 · 411 · 442–444 · 465 — the 442–444
   rows keep owner-gated tails).
   ⏳ **HD-495**: role-own the oldsrv seat's git plumbing (a rebuild still loses signing silently). The seat's
   **venv is not the gap** the row claimed — ansible core 2.21.5 is installed in `~/ansible-venv`, and the
   playbook syntax gate runs green there now that `validate-all.sh` activates the venv itself. The row now also carries the
   **Win11 sibling**: the unattended signing identity works but lives in no script, so a laptop rebuild loses it the same way
   (measured dialog timings + the two traps in [docs/deployment-secrets.md](docs/deployment-secrets.md)
   §What actually raises a 1Password prompt).
6. Owner-gated tails (exact steps in the rows): 377 Grafana render re-do · 444 the phone-crossing drill · 418 the HA restart
   window · HD-06 the UPS drill · HD-47 the federation join · 454 the human's own buy decision · 411 the cockpit resume word.

**Unbriefed open rows** (no session launches from them; the rows live in [todo.md](todo.md) +
[todo-table.md](todo-table.md) §B): 360 · 238 · 421 · 459 · 461 · 448 · **472** *(103 left this list 2026-10-07 — its conversion gate closed with HD-471)* · **477** (make the resolver actually
float with the VIP — premise measured green, the row carries the three gates and its place in the sequence) · **488** (the same host-resolver class on the Pi, where two docs already
work around it) · **487** (finish oldsrv's config-manager decision — lockout-class, so it runs off-box) · **494** (only the
re-derive of the global host-floor ceiling — with the 2026-10-06 transient burst as its reserve evidence — is left:
HD-380's `gpu_top_mib` growth check (gate 7) **closed 2026-10-07**, read over the full working day and PASS twice — a
bounded fill, one +5,626 MiB step then flat at **99,649 MiB for 19 of 22 hours** at 0.0 MiB/h tail and 0 restarts. The
**peak** for that arithmetic is measured, not inferred: 6,558 MiB over the watchdog's committed baseline and 1,634 MiB
under the recycle trigger; the gate-4/gate-5 legs closed inside the
**spark** slot of the HD-489 tail lane, so do not open a second writer there) · **1085** (the tmux seat harness: one
owner act — mouse-drag text inside a tmux pane on oldsrv and paste it where you typed, which is the OSC 52 leg no in-repo
probe can reach — plus one `--push` wired into `install-pi-debian.sh`; mechanism and traps in
[docs/pi-harness.md](docs/pi-harness.md) §5b, do not edit `~/.tmux.conf` by hand). · **1086** (the torrent leg is LIVE
— qBittorrent registered in all three arrs and one movie traced end-to-end into Jellyfin — but an arr cannot
hardlink between `/downloads` and `/media` (`ln` → EXDEV across the two binds), so Radarr 6.3 moves the file and the
torrent stops seeding: owner call between one shared bind mount and a qBittorrent seeding goal; procedure +
measurements in [deployment-manual.md](deployment-manual.md) §P3.6.8 and
[docs/services-downloads.md](docs/services-downloads.md) §Hardlink import is impossible…) · **362 tail** (the Lidarr credential is fixed and authenticates, but nobody has pushed an album through `lidarr-ydl` or exercised Aurral's add path since — verify the legs, do not re-litigate the key) · **1083** (loopback-only publishing for the routed group — an owner call; if taken it is ONE converge of every routed service plus the edge's routes) · **1087** (the trio's door + the home `.ts` leg are AUTHORED (translated from `18913c63`; the branch is deleted and its superseded hunks are in the rejected log) — what is left is ONE owner-present `oldsrv` converge plus the DNS seed on all three instances, and proving each leg by HTTP code against the `lidarr` control; no `*_bind` movement, that is HD-1083; the VPS-side `music` route is deliberately not in it) not in it) 