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

**The pi-dev seat is `oldsrv`, and its clone `domen@oldsrv:~/source/homelab` is the merging station** — merges
land, `main` is pushed and `scripts/validate-all.sh` runs there, so `git worktree list` on that host is the
fleet's live set (harness state in [docs/pi-harness.md](docs/pi-harness.md)). The laptop's WSL Debian clone
is **retired as a seat (owner, 2026-10-07)**. Two refs were unique to that box — a stash (`On main: never_evict
pin experiment`, 2026-10-03) and `session/arr-door-20261006`, whose remote ref the arr-door lane had deleted
after landing its work. Neither is live, and both are closed: the stash re-armed a flag main REJECTED on
2026-10-05 (`group_vars/spark.yml` §never-evict — the pin held 0 blocks, and `check_spark_llm_gate.py` refuses
it) and was dropped with its diff recorded in the commit that dropped it; the branch's content IS on `main` (the
trio routers, the `.ts` twins, its `*_url` vars, its zone names) and its commit object `18913c63` is pinned as
**`rescue/arr-door-20261006` on the seat** — local, in the existing `rescue/*` habit, so that object now lives
where the box that survives does. The station checkout there is clean, one worktree, skills synced, tmux 3.5a.
Its one non-derived gitignored file, `skills/mikrotik/.env.op` (`op://` references, no
values), is TRACKED from this commit, so a clone elsewhere loses nothing. Read the inventory's `laptop-wsl` role
("durable runner state = NAT + auto-resolv") as that host's **network** mode, not as a job runner: nothing
is scheduled on it (no crontab, stock Debian timers only). No command changes, because the seat's clone sits
at the same `~/source/homelab`. What the seat does buy: HD-1085's canary prints SKIP for its load-probe legs
where the `tmux` binary is missing — five of them did on WSL (`validate-all.sh` there is GREEN but partly
unmeasured) — while on the seat, which runs tmux 3.5a, they execute. Owner/cleanup sessions also run from
the **Win11 Git-Bash** seat.
`python3`/bash/LF/UTF-8 no-BOM (`.gitattributes` pins `eol=lf`, so a checkout is LF on Windows too). On a Win11 seat four
gates were silently blind or misleadingly red until 2026-10-07 — MSYS text mode makes `grep` miss the CR of a CRLF pair
(`grep -U` is mandatory in encoding guards), `git` lives in `/mingw64/bin` not `/usr/bin`, and a case ending in a tmux/ansible
probe must print SKIP, not a verdict (CONVENTIONS §6; the sweep rule is [docs/orchestration.md](docs/orchestration.md) §4 step 5).
**A Win11 seat signs and pushes without a 1Password window**: `bash scripts/git-bootstrap-win11.sh --git-identity` makes the
file-path identity the seat default (`--check` shows the route, `--1password` opts back) — see
[docs/deployment-secrets.md](docs/deployment-secrets.md) §What actually raises a 1Password prompt.
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
   **Win11 sibling**: the modal-free signing identity is now the *seat default* — `scripts/git/gitconfig-nightly`, installed
   and included last by `git-bootstrap-win11.sh --git-identity` — so a rebuild recovers it instead of losing it
   (measured dialog timings + the traps in [docs/deployment-secrets.md](docs/deployment-secrets.md)
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
[docs/pi-harness.md](docs/pi-harness.md) §5b, do not edit `~/.tmux.conf` by hand). · **1086** (ruled and landed 2026-10-07: the mount shape stays, seeding now ends at **ratio 2 → pause**, owned in
IaC and read back from the client. ⚠ The import itself is unchanged — an arr still MOVES the file (`ln` → EXDEV
across the two binds, Radarr 6.3 removed Import Mode / Link Type), so an imported torrent stops seeding at the import
whatever the goal says; that is the accepted cost, not an open question. ⏳ Left: the Jellyfin/Radarr ID disagreement
on `Svadba.2026`, and the import path's own procedure in [deployment-manual.md](deployment-manual.md) §P3.6 step 8 — the section number is P3.6; there is no P3.6.8 ·
[docs/services-downloads.md](docs/services-downloads.md) §Hardlink import is impossible…) · **1089** (`sab.ts.kogler.si` answers 403 because SABnzbd counts tailnet IPs as the internet — seed the tailnet range into its locality option; the router and the LAN leg are fine, do not re-open them) · **362 tail** (the Lidarr credential is fixed and authenticates, but nobody has pushed an album through `lidarr-ydl` or exercised Aurral's add path since — verify the legs, do not re-litigate the key. The slskd login question is CLOSED: the vault was right all along, the compose carried four env names slskd 0.26 does not read — probe with `docker exec slskd /slskd/slskd --envars`, never by grepping a rendered compose. ⏳ What the fix left standing: **nothing imports a completed Soulseek album, because Lidarr 3.1 has no Slskd download client at all** (its own `downloadclient/schema`: 18 types, usenet/torrent only) — so the ladder's "#2 Soulseek" is a human rule until a bridge is wired — **minted as HD-1091** (`mrusse/soularr`). The new `\\nas\music` share is served but **un-authenticatable** (`pdbedit -L` empty): the owner ruled 2026-10-07 that Samba accounts live in **Authentik**, so the path is **HD-360** (`ldapsam` — HD-132 is only its origin) — and HD-360 has a second blocker found here, **HD-1092**: the Authentik→NAS provisioning glue exits 127 every hour (`op` not installed on the NAS; 823 failures since 2026-09-03), so no family unix account exists to map an LDAP bind to. The owner still owes the Soulseek password rotation. See [docs/services-media.md](docs/services-media.md) §Music Pillar and [docs/storage.md](docs/storage.md) §Samba (SMB) shares on the NAS) · **1083** (ruled and landed 2026-10-07 for the routed group — binds, publish and edge URLs moved in one render. ⏳ Five names left in the tail, in two opposite shapes: `lan-litellm` :4000 and `dozzle` :8081 have no `*_url` var yet (the edge dials them as literals), while the music trio has the var but a **compose publish that hard-codes `oldsrv_home_ip`** — flip only its bind and you move the dial, strand the socket and reproduce the `38f918c` 502 on six hostnames. Thread the var through the publish in the same change; `lan-litellm` wants its own window. [docs/services-traefik.md](docs/services-traefik.md) §Reachability rule)  · **1090** (the IaC is done and needs no re-derivation: Prowlarr now gets the same qBittorrent client the three arrs carry, plus a `prowlarr` category with its own save path. ⏳ One oldsrv converge under `qbittorrent_seed` + `arr_client_seed` — the qbit half restarts the container once — then `POST /api/v1/downloadclient/test` → 200 and one Prowlarr-side grab lands in `complete/prowlarr`. Do not touch the arr-side clients: Prowlarr syncs indexers, never download clients) 
