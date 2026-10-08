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

**Seat git writes can fail transiently — retry before believing it.** A `git push` from the seat was rejected with
`remote: fatal error in commit_refs` on BOTH `main` and a fresh branch, while `git push --dry-run` and `git fetch`
succeeded and `ssh -T` authenticated — GitHub-side, not a key/ACL problem (the ACL proof is the dry-run: it does
request `git-receive-pack`). A retry a few minutes later pushed clean. So on that exact message: re-verify ACL with
`--dry-run`, then retry; do not go hunting for a permissions cause, and never conclude the commit is lost — it is on
`main` locally the moment you merge.

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
   `cloudflare_dns_records`). Re-renders live edge routing → owner-present. ⚠ **The blocker that was mechanical is gone**: the
   seat drives the RouterOS API now (HD-495, 2026-10-08 — `librouteros` + the interpreter pinned for the `network` group; router
   and switch both read 7.24.4), so what remains is the owner window, not the tooling. → [prompt-436.md](prompt-436.md)
4. ⏳ **HD-450** — the silent-failure rules are **live**: the VPS + nas monitoring converges landed 2026-10-08 (`failed=0`),
   the five `homelab_*` rules read back through the Grafana ruler API and the exporter answers on **all five** hosts (`spark`
   joined 2026-10-08, heartbeats 12–51 s). What is owed is now four things, not a probe: **(1)** the end-to-end Signal
   acceptance read — **parked by the owner 2026-10-08** because a deliberate failure pages the family group, so it runs with
   them awake (command in the row); **(2)** ⏳ **a VPS `monitoring` converge (detached)** to load the corrected
   `hygiene-collector-stale` expression — the version live in Grafana right now pages the family every 30 min **while every
   collector is healthy** (~19 h on 2026-10-08: a filtered-empty result and a missing series are the same NoData state, so
   `noDataState: Alerting` + `> 900` inside the PromQL fires on green; the fix moves the comparison to the threshold and ages
   the metric through `max_over_time[6h]` — shape and proof in the doc), and until that converge the alert is noise, not a
   signal; **(3)** leg (c), the NUT client→master **metric**, untouched — unit results are not
   "this client can reach the master"; **(4)** export the VPS **box** cert (acme.sh) — it has no series at all, so no rule can
   exist for it yet (measured at the `__name__` level; the trap of writing a rule against an imagined metric is in the doc).
   → [docs/observability.md](docs/observability.md) §Silent-failure hygiene, §Alerting
5. ⏳ Cockpit / coding-seat / grants cluster → [prompt-361.md](prompt-361.md) (rows 361 · 411 · 442–444 · 465 — the 442–444
   rows keep owner-gated tails).
   ⏳ **HD-495**: role-own the oldsrv seat's git plumbing (a rebuild still loses signing silently). The seat's
   **venv is not the gap** the row claimed — ansible core 2.21.5 is installed in `~/ansible-venv`, and the
   playbook syntax gate runs green there now that `validate-all.sh` activates the venv itself. The same session also gave the
   seat its RouterOS API path (dep in the venv + `bootstrap-runner.sh`, `ansible_python_interpreter` pinned for the `network`
   group) and wrote the four probes-that-lie into [deployment-ansible.md](docs/deployment-ansible.md) §Network devices. The row now also carries the
   **Win11 sibling**: the modal-free signing identity is now the *seat default* — `scripts/git/gitconfig-nightly`, installed
   and included last by `git-bootstrap-win11.sh --git-identity` — so a rebuild recovers it instead of losing it
   (measured dialog timings + the traps in [docs/deployment-secrets.md](docs/deployment-secrets.md)
   §What actually raises a 1Password prompt).
6. Owner-gated tails (exact steps in the rows): 377 Grafana render re-do · 444 the phone-crossing drill · 418 the HA restart
   window · HD-06 the UPS drill · HD-47 the federation join · 454 the human's own buy decision · 411 the cockpit resume word.
7. ✅ **HD-1099** — fleet image-pin refresh is **live on all five hosts** (converged from the VPS runner 2026-10-08:
   `ok=377/162/159/178/624`, `failed=0`, zero restarting or unhealthy containers; `alloy 1.20.1-1` fleet-wide, which also
   closed **1094**). It left three tails: **1100** (the Postgres/broker migrations, now the top task below), **1101** (the
   HD-484 assert gate + corrupted tailscale `.deb` digests — fixed and vendor-verified, `image-pin-probe.py --debs` now
   covers deb pins), and **1107** (sanoid). Two lessons worth keeping: a **phantom pin** is invisible to every gate in the
   repo — only `python3 scripts/image-pin-probe.py --verify` sees one; and a `*_image` digest pin is the load-bearing
   value, never bump the tag under it.
8. ⏳ **HD-1100** — **the next live work: Postgres 16 → 18.** The model is proven and the blocker is gone; the runbook is
   [docs/backup.md](docs/backup.md) §Postgres major upgrades. Order by blast radius: `litellm-db` (re-run as the proof that
   the version-conditional mount works) → `onlyoffice-postgres` (+ the RabbitMQ 3.13→4.x question, in the same window) →
   `forgejo-db` → `zipline-db` → `lan-litellm-db` on oldsrv → **`authentik-postgres` last** (fleet SSO). Owner holds the four
   middle legs until legs 1 and 5 prove the model. **What the first leg cost, so nobody repeats it:** 18 images run
   `PGDATA=/var/lib/postgresql/18/docker` and refuse a cluster at the old path, so a pin bump alone crash-loops the DB —
   the bind target moves with the major via `pg_data_mount`; and rollback is datadir **and** pin together. Oldsrv separately
   owes its **`wireguard`** leg (restarts the tunnel server; run it alone, last, then re-verify every tunnel path).
9. ⏳ **apt upgrade phase** — deliberately left OUT of the converge wave. Needs `apt-mark hold` for Ansible-pinned packages
   (`alloy`, `tailscale`, `docker-ce`, `kopia`) landed in IaC first, or a bare `apt upgrade` re-creates the HD-1094 drift and
   stacks kernel reboots onto a DB-migration window. The `roles/updates` design (visibility → unattended security pocket →
   gated full upgrade with holds) is still an owner go/no-go.

**New unbriefed rows from the 2026-10-08 maintenance window** (no session launches from them): **HD-1107**
(nas ZFS **policy** snapshots never ran — our own generated `sanoid.service` said `/usr/local/bin/sanoid`, the package
installs `/usr/sbin/sanoid`, so every timer fire died `203/EXEC`; fixed, ran `exit=0`, first `hourly.*` still pending a tick)
· **HD-1105** (three enabled-but-dead units on nas: `zfs-share`, `winbind` with `smb` enabled, and `sync-authentik-users`
with an EMPTY `ExecStart`) · **HD-1106** (20 dangling VPS volumes, 644 MB, two of them 47 MB with unverified provenance —
not deleted; the HD-247 volume→bind pattern is the suspect) · **HD-1103 tail** (`/var/log` on pi is mode `1777`, so
logrotate fails nightly; no role owns that path, which is why it drifted — needs an owning-role decision before IaC sets it).

**Unbriefed open rows** (no session launches from them; the rows live in [todo.md](todo.md) +
[todo-table.md](todo-table.md) §B): **1094** *(minted 2026-10-07 by the same session that shipped HD-450's exporter: `alloy_version` pins 1.19.2-1 while oldsrv had drifted to 1.20.1-1, which made every monitoring converge there die in apt. Resolved for that host; the fleet bump is the owner's call and until it is decided, the four hosts still on the pin will tell you the same way.)* · **1093** *(owner tail: rotate both SMB passwords, then land them with `storage_samba_password_force`)* · 238 · 421 · 459 · 461 · 448 · **472** *(103 left this list 2026-10-07 — its conversion gate closed with HD-471)* · **477** (make the resolver actually
float with the VIP — premise measured green, the row carries the three gates and its place in the sequence) · **488** (the same host-resolver class beyond oldsrv: **the Pi leg landed and was verified 2026-10-08** — it resolves internal
names on the box now, and the two documents that carried workarounds for the broken state were corrected in the same change.
⏳ spark waits on a spark-slot converge (its keyfile still says `dns=1.1.1.1;`) and nas waits on HD-487, because no manager owns
its uplink) · **487** (config-manager truth per host, now a command instead of folklore — `scripts/probe-net-manager.sh`, verdict read off the
interface the default route rides: oldsrv/pi = NetworkManager with dead networkd renders on disk, vps = networkd, **spark = both
managers on one box**, **nas = neither**. ⏳ oldsrv's dead renders go (ruled, lockout-class, off-box, run alone); spark needs a
ruling it never had; nas needs its owner found before any address/DNS leg converges there) · **494** (the re-derive of the global host-floor ceiling is **arithmetic-complete 2026-10-08, value deliberately unchanged** —
read the four priced candidates in [docs/hardware-spark.md](docs/hardware-spark.md) before touching the var, and note the
precondition: the global was restated in four places, so a re-derive would have changed nothing until those copies went.
Pricing the 2026-10-06 transient burst moves the ceiling DOWN, not up, so "raise it and delete `fast`'s exception" and "price
the transient" cannot both be true. ⏳ one 1 s `usable` sampler across one heavy prefill, then the owner picks the floor:

HD-380's `gpu_top_mib` growth check (gate 7) **closed 2026-10-07** and the **peak** for that arithmetic is measured, not
inferred (99,649 MiB flat — 6,558 MiB over the watchdog's committed baseline, 1,634 MiB under the recycle trigger); the
gate-4/gate-5 legs closed inside the **spark** slot of the HD-489 tail lane, so do not open a second writer there · **1085** (the tmux seat harness: one
owner act — mouse-drag text inside a tmux pane on oldsrv and paste it where you typed, which is the OSC 52 leg no in-repo
probe can reach — plus one `--push` wired into `install-pi-debian.sh`; mechanism and traps in
[docs/pi-harness.md](docs/pi-harness.md) §5b, do not edit `~/.tmux.conf` by hand). · **1086** (ruled and landed 2026-10-07: the mount shape stays, seeding now ends at **ratio 2 → pause**, owned in
IaC and read back from the client. ⚠ The import itself is unchanged — an arr still MOVES the file (`ln` → EXDEV
across the two binds, Radarr 6.3 removed Import Mode / Link Type), so an imported torrent stops seeding at the import
whatever the goal says; that is the accepted cost, not an open question. ⏳ Left: the Jellyfin/Radarr ID disagreement
on `Svadba.2026`, and the import path's own procedure in [deployment-manual.md](deployment-manual.md) §P3.6 step 8 — the section number is P3.6; there is no P3.6.8 ·
[docs/services-downloads.md](docs/services-downloads.md) §Hardlink import is impossible…) · **1089** (`sab.ts.kogler.si` answers 403 because SABnzbd counts tailnet IPs as the internet — seed the tailnet range into its locality option; the router and the LAN leg are fine, do not re-open them) · **362 tail** (the Lidarr credential is fixed and authenticates, but nobody has pushed an album through `lidarr-ydl` or exercised Aurral's add path since — verify the legs, do not re-litigate the key. The slskd login question is CLOSED: the vault was right all along, the compose carried four env names slskd 0.26 does not read — probe with `docker exec slskd /slskd/slskd --envars`, never by grepping a rendered compose. ⏳ What the fix left standing: **nothing imports a completed Soulseek album, because Lidarr 3.1 has no Slskd download client at all** (its own `downloadclient/schema`: 18 types, usenet/torrent only) — so the ladder's "#2 Soulseek" is a human rule until a bridge is wired — **minted as HD-1091** (`mrusse/soularr`). The `\\nas\music` share now **mounts** — ruled again the same day and implemented: local tdbsam accounts, SSOT = `storage_samba_users` in `host_vars/nas.kogler.si.yml`, and `music` is mounted with the **`shared`** service account (**HD-1093**; LDAP/`ldapsam` retired, evidence in [docs/storage-rejected.md](docs/storage-rejected.md)) The owner still owes the Soulseek password rotation. See [docs/services-media.md](docs/services-media.md) §Music Pillar and [docs/storage.md](docs/storage.md) §Samba (SMB) shares on the NAS) · **1083** (ruled and landed 2026-10-07 for the routed group — binds, publish and edge URLs moved in one render. ✅ 2026-10-08: `lan_litellm_url` minted and referenced, render-proven identical, nothing converged. ⚠ The music trio's "var exists but the publish hard-codes the address" premise no longer describes the tree — read §Reachability rule in the doc below BEFORE editing routes or publishes. ⏳ the routes→`*_url` half in an owner-present edge window (it strands containers whose labels were already rewritten), plus `llogs`' inline literal; `dozzle` stays a compose-DNS service name on purpose. [docs/services-traefik.md](docs/services-traefik.md) §Reachability rule)  · **1090** (the IaC is done and needs no re-derivation: Prowlarr now gets the same qBittorrent client the three arrs carry, plus a `prowlarr` category with its own save path. ⏳ One oldsrv converge under `qbittorrent_seed` + `arr_client_seed` — the qbit half restarts the container once — then `POST /api/v1/downloadclient/test` → 200 and one Prowlarr-side grab lands in `complete/prowlarr`. Do not touch the arr-side clients: Prowlarr syncs indexers, never download clients) 
