> **Role:** entry point for the next session — a **lean handoff**, a pointer index and nothing else. Every item's authority
> is its [todo.md](todo.md) row; permanent knowledge is the owning doc ([docs/index.md](docs/index.md) map); the permanent
> process contract (working rules, orchestrator mode O1–O11, launch, merge/cleanup) is
> [docs/orchestration.md](docs/orchestration.md) §4; the planning view for the human is [todo-table.md](todo-table.md).
> **No history lives here** — session accounts live in owning-doc status blocks + git history (archive-only:
> `reports/changelog.md`, `reports/deployment-journal.md`). A `prompt-*.md` brief carries a lane's contract and order of
> work; it never restates a row. **Briefs are named for a host + domain, never for an HD** (CONVENTIONS §6), so every
> pointer below is a domain brief and the row stays the authority for what is owed.
> **Linked from:** [README.md](README.md) §0/§2 · [CONVENTIONS.md](CONVENTIONS.md) §4/§6 · [todo.md](todo.md) ·
> [todo-table.md](todo-table.md) · [docs/orchestration.md](docs/orchestration.md)

---

## 1. Environment

**The pi-dev seat is `oldsrv`, and its clone `domen@oldsrv:~/source/homelab` is the merging station** — merges
land there, `scripts/validate-all.sh` runs there, and `git worktree list` on that host is the fleet's live set
(harness state in [docs/harness-pi-engines.md](docs/harness-pi-engines.md)). **Pushing is not that station's exclusive
job: every station pushes after it merges** (the rule is [docs/orchestration.md](docs/orchestration.md) §4 step 5 — an
unpushed `main` is one disk between the work and the fleet). The laptop's WSL Debian clone is **retained, and
now has a job: it is the designated runner station for externally-served runs** — off-box for every converge target, not the
engine host, owner of no converge slot (the 2026-10-09 “retained but rarely used as a seat” ruling still stands for the
pi-dev-seat question, which is a different one; the rule is [todo-table.md](todo-table.md) §C rule 9 and the state is
[docs/harness-pi-seat-identity.md](docs/harness-pi-seat-identity.md) §5a). It stays in `pi-seat-sync.sh`'s `SEATS`, so a fan-out still names it and keeps reporting its real state — its own seat
planes are green (`pi-seat-sync.sh --check`: every `wsl` line OK; the one problem is the oldsrv cockpit's `STALE-CLONE`, and that `ok=` count is a function of THAT seat's clone lagging `main` — with oldsrv current the same command prints `ok=18 problems=0`, so re-derive it, never copy it). Two refs were unique to that box — a stash (`On main: never_evict
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
at the same `~/source/homelab`. What the seat does buy: HD-1085's canary and its load-probe legs execute here —
tmux 3.5a is installed on this seat, so the load probe prints a **verdict**, not a SKIP. Owner/cleanup sessions also run from
the **Win11 Git-Bash** seat.
`python3`/bash/LF/UTF-8 no-BOM (`.gitattributes` pins `eol=lf`, so a checkout is LF on Windows too). On a Win11 seat four
gates were silently blind or misleadingly red until 2026-10-07 — MSYS text mode makes `grep` miss the CR of a CRLF pair
(`grep -U` is mandatory in encoding guards), `git` lives in `/mingw64/bin` not `/usr/bin`, and a case ending in a tmux/ansible
probe must print SKIP, not a verdict (CONVENTIONS §6; the sweep rule is [docs/orchestration.md](docs/orchestration.md) §4 step 5).
**A Win11 seat signs and pushes without a 1Password window**: `bash scripts/git/git-bootstrap-win11.sh --git-identity` makes the
file-path identity the seat default (`--check` shows the route, `--1password` opts back) — see
[docs/deployment-secrets.md](docs/deployment-secrets.md) §What actually raises a 1Password prompt.
Secrets → 1Password `Homelab-ansible` `item.field` only, `>-` for YAML renders. Multi-line bash heredocs with
backslashes/backticks get mangled through `bash -c` — write script bodies to a temp file and run them.
**Git identity on a seat — signing is RETIRED (HD-1116), so commit plainly.** `git log -1 --format='%G?'` → `N`
is the expected value on every commit and is not a failure; never `git commit -s` (that trailer signs nothing).
The only vault item left in this area is **`GitHub auth`**, the transport key — `GitHub sign` was deleted
2026-10-09 and `git-bootstrap.sh --ssh-auth` now treats it as optional, because requiring it used to abort the
run before it pulled the auth key, which is the part a seat actually needs. `commit.gpgsign=false` is written
explicitly by that path and by the seat template, and `%G?` on the OLD commits still verifies via
`~/.ssh/allowed_signers` (the public half stays for exactly that). Seat file map — Windows uses
`~/.gitconfig-github` + `~/.gitconfig-nightly`, a DEBIAN seat has only `~/.gitconfig` — is in
[docs/deployment-secrets.md](docs/deployment-secrets.md) §6.

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

> **Dispatch, for a session running as the orchestrator.** Delegate the work instead of performing it (O10):
> the parent launches children, reads evidence, merges, runs `validate-all.sh` and owns acceptance — it does not
> investigate the tree to decide what to delegate. **≤2 children live at a time**, `async: true`, this session's
> own model, **2 h per child**, and a minutes-long silence is a compaction pause rather than a stall (O11, and the
> numbers in `pi-agent/settings-ssot.json`). Read `echo $PI_PROVIDER` **before routing**: on a spark-served seat the
> spark engine brief and every timed/engine leg are excluded for the whole run, for children as well as the parent
> (standing rule 2 in [todo-table.md](todo-table.md) §C). Which rows are AI-doable with no owner step in front is the
> `Who` column of [todo-table.md](todo-table.md) §B/§B9, never this list.
>
> **Read the seat too, not only the model.** A lockout-class leg is gated by *which box drives* (the self-converge guard fires
> when the target is the controller) and that has nothing to do with which model is serving the session; the two axes are
> stated separately in [docs/orchestration.md](docs/orchestration.md) §4. Externally-served runs belong on the WSL Debian
> station, and the legs only that box may drive are listed in [prompt-laptop-wsl.md](prompt-laptop-wsl.md) §2.

**Seat brief (not a wave):** [prompt-laptop-wsl.md](prompt-laptop-wsl.md) — the WSL Debian laptop seat as the neutral runner
station: its §0 pre-flight (this box's own gate is **green** before you edit anything — re-derive the count with `--list | wc -l` and read the SKIPs by name: the tmux load probe has no binary here, and the two Windows-only arms are not this seat), the legs only that box may drive (§2), what a
spark-served session must not start there (§3), and the rehearse-everything rule for owner windows (§4). It claims **legs, not
rows**, so it never takes a row out of the brief that owns it.

Ranked by what unblocks the most. Each line is the item + **the domain brief that carries its order of work** —
the brief, not this list, holds the steps, the file ownership and the converge host. Waves, pairing and the
host/slot rule that decides what may run together are [docs/orchestration.md](docs/orchestration.md) §4 (O1–O11);
the row→brief index is [todo-table.md](todo-table.md) §B0. A brief is named for a host + domain, never for an HD
(CONVENTIONS §6), so nothing here points at a per-HD brief any more.

1. ⏳ **The spark engine lane** — the under-cap `clocks.sm` baseline for **HD-469** (only a sustained trace under
   load proves the regime; run it from a session whose own model is **not** spark — rule 0), `fast`'s triton fix
   (**HD-475**), the upstream-blocked engine pin (**HD-473**), and **HD-489**'s last certificate item: gate 6's
   battery at `max_tokens 16,384` is **recorded, not applied**, and applying it means re-running the B1 baseline
   in the same change. Gate 7 is CLOSED (read twice 2026-10-07, PASS both); B10's gates 6/8/9 were declined by
   owner and B9 · B5 · B8 are closed — do not re-run any of them. **HD-494**'s re-derive is arithmetic-complete
   with the value deliberately unchanged — price the 2026-10-06 transient before touching the var, and read
   [docs/hardware-spark.md](docs/hardware-spark.md) first. →
   [prompt-spark-llm.md](prompt-spark-llm.md) (one spark slot; HD-376 · 400 · 359 · 367 · 380 ride it too)
2. ⏳ **The transport / answer plane** — **HD-436**'s hinge has closed on the repo side: `zone_kogler_si` is the one
   derived list and BOTH remaining consumers read it (`vps.yml`'s two tailnet lists are aliases of its views, the
   headscale template loops them by FQDN, and `roles/cloudflare_dns` loops the public view with its vars file now a
   pointer) — parity-proven on all six surfaces, so nothing hand-authors a subdomain list any more. Its dry-diff
   artifact was taken read-only 2026-10-19 and it says the answer plane needs nothing: headscale's deployed
   `dns.extra_records` holds 38 pairs, the derived render 39, and the single delta is the ADD of
   `metabase.ts.kogler.si` — no existing name changes address; on the Pi tertiary `dig metabase.kogler.si` already
   answers with the oldsrv Home address, so the Technitium leg is a no-op on the instance that was read. What the row
   owes is ONLY the live half — the two converges named in the parked list below, both still PARKED. Alongside it:
   **HD-477** (make the resolver actually float with the VIP; premise measured green, the row carries the three gates), **HD-487** (the
   config-manager truth is now DECLARED per host in `host_vars/<host>.yml` — oldsrv/pi/spark/nas = NetworkManager, vps =
   systemd-networkd; the `ifupdown` third state is off the fleet, nas having adopted NM on `eno1` (2026-10-18, read back:
   NM enabled, `networking` disabled, the `nas-eth0` keyfile up) — held down by
   [`scripts/gate/check_net_manager.py`](scripts/gate/check_net_manager.py) and read per host with
   `scripts/ansible/probe-net-manager.sh`; every dead `eno1` netd render is off the fleet — pi/oldsrv/nas removals landed,
   and spark's `/etc/systemd/network` read **empty** on 2026-10-18 with networkd `disabled`. The fleet probe settled the
   question the row used to carry: four hosts are clean, and the ONE thing owed moved to the **VPS** — a dead
   `/etc/systemd/network/20-eno1.netdev` only the role's removal leg can delete), **the
   host-resolver class beyond oldsrv** (the Pi leg landed and was verified 2026-10-08; spark's converge closed it
   2026-10-18 — resolver pair + networkd disarm via the spark slot), and the
   DNS-policy rows **HD-480 · 481 · 482 · 483**, whose landable half LANDED 2026-10-19: one SSOT policy list
   `technitium_dns_policy` + the tuning dict `technitium_resolver_settings` written by ONE seed step with an asserted
   read-back, `enableBlocking` DERIVED from the list so "blocking on, nothing loaded" is unrepresentable, `logQueries`
   on the Pi tertiary with its `maxLogFileDays: 14` rendered instead of inherited from Technitium's 365-day default, and
   [`scripts/gate/check_dns_policy_drift.py`](scripts/gate/check_dns_policy_drift.py) in the gate. Converged on the Pi;
   the VPS and oldsrv instances pick it up in their own slots. **What did not land is not an unbuilt feature:**
   Technitium 15.6 answers **404** on every per-client/per-group endpoint on the pin and upstream alike, so a per-policy
   upstream has nowhere to live and the router's one `:53` dst-nat pair aims every policy at ONE shared resolver address
   — that decision is **HD-1160** (owner: A/B/C/D), and until it is made the device-level Kids/IoT acceptance in
   HD-481/482 cannot be met by any settings change. Also open on the same tier, unbriefed: **HD-1152**'s prune leg has been proved
   un-runnable rather than un-run — the read uses a query-string shape this API does not answer, and the candidate build
   uses a Jinja list comprehension that dies at render; both are invisible to `--syntax-check` because the block is
   gated `not ansible_check_mode`. → [prompt-dns-transport.md](prompt-dns-transport.md)
3. ⏳ **Silent-failure alerting** — **HD-450**'s collector legs are LIVE and read back per host 2026-10-17: the NUT
   client→master metric with `nut-master-unreachable` loaded, and the VPS's own on-disk cert pair exported. The
   `acme.sh` premise this handoff used to carry is dead — that box's Traefik IS the ACME issuer and its age was
   already a series; the missing half was the on-disk pair. What the row still owes is one re-point: alert delivery
   moves to Matrix under **HD-1108**, and until that leg is proven Signal stays the path alerts are read on.
   ⚠ The canary recipe this handoff used to carry could not fire — a transient unit outside
   `monitoring_hygiene_units` is invisible to the exporter; the working trigger is in the doc. The **Alloy fleet
   pin** is settled state, not an open question: `alloy_version: "1.20.1-1"`
   (`IaC/ansible/group_vars/all/versions.yml`) with no per-host override and all five monitoring hosts on it — the
   reads, the apt failure shape and the ⛔ never-`--allow-downgrades` rule are in
   [docs/observability.md](docs/observability.md) §The Alloy pin. **LLM token accounting
   (HD-1120 · 1121 · 1122, minted 2026-10-09)** is now in the same brief, and 2026-10-19 settled what each half is:
   **HD-1121** is a FINDING, not a job — `/metrics` answers `401` unauthenticated and `404` **with a valid admin
   bearer** on both gateways (pin `v1.104.0`) because the image mounts the endpoint only when the `prometheus`
   callback is configured, so no scrape was added; the row now owes the callback + the auth form + the VPS loopback
   publish, which is a **gateway** recreate, not a monitoring one. **HD-1122** reports the RX 7600 now
   (`homelab_gpu_vram_used_bytes` / `_vram_total_bytes` / `_busy_percent`, `gpu="rx7600"`, boarded in `homelab-llm`
   by its generator) and its ENGINE half is authored behind `ai_tier_metrics_publish: false`
   (`group_vars/home_servers.yml`) — the flag, the `127.0.0.1` publish and the `prometheus.scrape "llama_cpp"` leg are
   ONE change that recreates two serving containers, so it waits an owner window. **HD-1120** is unchanged: totals
   are known for every caller, attribution comes from the **edge access log** — a metering proxy hop was ruled out
   because it re-buys the hop decision #26 removed. Spec + the XFF trap:
   [docs/observability.md](docs/observability.md) §LLM token accounting. Two new rows came out of the same night:
   **HD-1163** names a dark monitoring host instead of discovering it in a forum post — the `curl 127.0.0.1:12345/metrics`
   probe + conditional restart leg in `roles/monitoring` and
   [`scripts/gate/check_host_reporting.py`](scripts/gate/check_host_reporting.py) (four verdicts, expected set read from
   `[monitoring]`) are landed, and the PAGING half is deliberately unwritten because a ruler rule can only compare values
   the backend holds, which needs a VPS `--tags monitoring` window; and **HD-1164** is why `nas` is the blind host — the
   collector dies ~5 s after every start with `fatal error: traceback did not unwind completely` on Go 1.26.7, with the
   repo, the backend and the DMAR lines all excluded, so the acceptance is a firmware/kernel look plus a memory test the
   owner schedules and the unit stays **stopped on purpose** meanwhile. ⚠ `check_host_reporting.py --check` reads RED for
   `nas` and that is the instrument working — do not soften the expected set to make it green. →
   [prompt-observability-alerting.md](prompt-observability-alerting.md)
4. ⏳ **The media / music ladder** — **HD-362**'s two Lidarr legs were measured 2026-10-19 and neither is the
   credential the row assumed: `lidarr-ydl` authenticates fine (its log reads `Lidarr sync complete: 3 albums cached`,
   matching `wanted/missing` = 3) but **Lidarr has no route to it** — its indexers are the three Prowlarr-sourced ones,
   its download clients are qBittorrent + SABnzbd, and `download_queue` / `track_downloads` / `download_client_jobs`
   are all 0 rows, so the missing piece is APP state (one indexer + one download-client entry, the seed-in-IaC
   question), not a secret; Aurral → Lidarr is a **browser** leg (the add is a click on a recommendation card, its
   URL+key encrypted inside `aurral.db`, the API 404s on the obvious routes). The Tube Archivist `path.repo` note stays;
   the slskd login question is CLOSED (the vault was right; the compose carried four env names slskd does not read —
   probe with `docker exec slskd /slskd/slskd --envars`, never by grepping a rendered compose) and the Soulseek password
   rotation is **DECLINED and risk-accepted on record** — do not re-open either. **HD-1090** owes one grab started
   in Prowlarr's own UI. **HD-1091** is authored and deliberately OFF: `templates/docker_services/soularr/` +
   `soularr_version: "1.2.2"` + both vault items landed, and the entry ships `enabled: false` because **this box has no
   slskd API key** — `/api/v0/options` answers `401` for every key tried, `soulseek_api` included (that value is the UI
   password → JWT). Its one blocked action is seeding that key, which recreates slskd and drops the session; the
   `SLSKD_DOWNLOADS_DIR` retarget is decided as NONE (soularr renames in place and fires `DownloadedAlbumsScan`, so the
   import still moves the file and seeding stops at import). **HD-1088** now RENDERS on oldsrv (`--tags storage` →
   `ok=46 changed=2 failed=0`: script + service + timer, timer **disabled** while `storage_push_music.enabled` is
   false), its guard was proven before any push, and two of its premises were corrected: `--max-delete` is a **CAP,
   not an abort** (measured on rsync 3.5.0: 50 of 100 pending deletions executed, rc 25) — the weight sits on the two
   asserts that run before rsync, and the shape now has a pool fixture in
   [`scripts/testdata/rsync-max-delete/run.sh`](scripts/testdata/rsync-max-delete/run.sh) — and with no identity the
   script aborts at its OWN identity assert before the mount assert. One owner action gates every end-to-end proof:
   register oldsrv's public key on the live Box. **HD-1092** is void as written — the Authentik→NAS glue is gone from
   BOTH sides (no script, no units, `roles/storage/tasks/samba.yml` carries only its teardown), `op` on the NAS is now
   unwanted rather than missing, `/tank/data/users` exists with `domen`'s drive, both members are real unix users and
   gid 1005 is supplementary BY DESIGN; what remains is one credential-bearing leg on a second host
   (`smbclient //nas/domen -A creds`), parked. (**HD-1089**, the SABnzbd locality read, is the same lane's subject but
   no brief claims the row — it is in the unbriefed list below.) → [prompt-media-arrs.md](prompt-media-arrs.md)
5. ⏳ **Cockpit, the coding seats, grants** — the cluster (**HD-361 · 411 · 442 · 443 · 444 · 465 · 495 · 1085 ·
   1110 · 1138 · 1139 · 1140 · 1161 · 1162**) with its owner-gated tails intact. **The laptop↔oldsrv coding leg closed
   2026-10-16:** the alias contract is LAN-direct by default with `<node>-vps` as the opt-in hop, all three seats
   carry one contract digest, and VS Code connects over `oldsrv-domen`; what is left in that cluster is the
   away-case spelling in the scripts that shell out (`1138`) and the VS Code server-install leg it gates. **HD-1139**
   closed its own premise 2026-10-19: the prefix read ran from the router and there is NO dead prefix class — one
   global /64 plus an active `::/0`, and every destination that HAS a `AAAA` answers over v6; what failed fast
   (`http=000` in 15–140 ms, not a timeout) are **A-only hostnames** that answer nothing at our resolvers or at a
   public one, so no rule change is warranted and none was made. **HD-1140**'s lease read ran too and the gap is now
   stated where a rebuild would look for it; the parked half is the owner's call — a `network_static_hosts` row plus a
   find-guarded router delta, or no reservation at all with the alias contract resting on the name. **HD-495**: its
   role-ownership tail — the row's actual ⏳ — landed 2026-10-19 as a SCRIPTED mode, not a runbook line:
   `git-bootstrap.sh --git-identity` (and `--git-identity --check`, read-only) owns the three lines a Debian seat needs
   OUTSIDE any clone — `commit.gpgsign=false` **explicit** (an inherited `true` is a hang where there is no tty),
   `gpg.format=ssh`, `gpg.ssh.allowedSignersFile=$HOME/.ssh/allowed_signers` — reported through
   `git config --global --get` so git's own precedence is what is reported. The **signing** half had been retired
   2026-10-08 by HD-1116, so a rebuild now recovers `gpgsign=false` instead of hanging. What is left is the two
   hand-planted `~/.ssh` keys — `--git-identity` reads them back and prints `ssh keys present = …`, it does not raise
   them, and raising them is `--ssh-auth` — so no converge asserts the payload exists. Its **SA-token leg** closed on 2026-10-09:
both service accounts are rotated and all three Debian installs (laptop, oldsrv runner, oldsrv seat) are re-seated to
the read-scoped `op_api` and proven by an `op item list` that answers rows; the Win11 seat is confirmed to hold no SA
token at all, which is its designed state. ✅ **Closed the same evening:** the **`/etc/op/provision-token`** hosts (`oldsrv`, `vps`) were refreshed by a full
`docker_services` converge (`scope_is_all`) issued FROM the laptop — both re-hash to the current `op-write_api` value,
the run's "Probe the deployed token is actually accepted" task green on both, no container left `unhealthy`/`exited`.
⚠ The first attempt (18:37) died in `ansible-run.sh`'s self-update with `fatal: Cannot fast-forward to multiple
branches.` and no `PLAY RECAP`; this handoff blamed that clone's merge refs, and **that was wrong** — `git config
--get-all branch.main.merge` prints exactly one ref, and the same launcher succeeded at 21:26 with no config change.
The git-side cause is therefore unidentified; what was durable is the launcher fix, which now prints the branch, its
upstream and the merge refs **at the moment of failure**, so the next occurrence arrives with its own diagnosis. Read [docs/1password.md](docs/1password.md) §1
first: the leak response killed the "two-token finding" as a **mis-seed** — both seats were running the *write*-scoped
item, and `op vault list` cannot tell the scopes apart, so prove scope with the `op whoami` **Integration ID**.
   **HD-442**'s owed read ran 2026-10-19 from this seat (`op whoami` → `SERVICE_ACCOUNT`, counts and lengths only):
   the catalog is **54** names, not the 75 this row used to quote, `op item list` answers **140** items, and
   **catalog − vault = 0** with `op item get` green on all 54 — so nothing was revoked, which closes that half; the
   vault−catalog 86 are the expected classes. What still waits is the value-identity half (hash the rendered
   `/etc/op/provision-token` against the vault's `ansible_provision_token`, lengths only) in an owner-present sitting.
   **HD-443**'s premise is now measured rather than assumed: the Pi's journal is `Storage=volatile`, so it reaches back
   exactly one boot, and that window **contains nine** `Accepted publickey for admin` from 2026-10-05 and none since —
   while the neutralization is real (`/home/admin/.ssh/authorized_keys` holds no key; the dated `.disabled-20261005`
   copy carries exactly the fingerprint those nine logged). So the row's 14-day and 30-day windows were the same seven
   days of RAM read twice, nothing was changed, and the trigger read can only be closed on a host whose journal covers
   the interval or by the owner accepting that a volatile journal cannot prove a 30-day silence. ⛔ A raw journal grep
   for the phrase also **matches the probe that greps for it** — filter on `sshd-session[…]` / `-u ssh.service`.
   ⚠ Never re-add `git commit -s`; signing is retired. **HD-1110**: `scripts/harness/pi-seat-sync.sh` is
   the one deploy path; its 2026-10-08 "oldsrv closed on all eight planes" reading is VOID, and the
   2026-10-19 re-read from the `wsl` seat is the current one: `--check --seat wsl` → **`RESULT ok=10 problems=0`**,
   every declared plane OK (`pi-self skills extensions settings models tui tmux font subagent` + the pre-flight), the
   `models` line reporting **no drift** because this seat's `pi_auth` entries really are `type: api_key` as
   `scripts/harness/pi/models-spec.yml` declares. The row's own tail closed tonight: `install-pi-wsl.sh` now **owns
   PATH persistence** (`persist_path()` writes the node `current` bin dir and pi's entrypoint dir under its own marks,
   distinct from `install-pi-debian.sh`'s, and `verify_login_path()` then asks a LOGIN shell and fails if a `/mnt/c`
   copy wins) instead of printing a NOTE about `~/.bashrc`. Two things remain: the **Win11** seat leg, which no leg from
   this box reaches (inside WSL the driver's seat list is `wsl oldsrv`), and the parked OAuth-vs-`api_key` call on the
   `pi_auth` providers — a `--push` on a seat authorised by OAuth would replace a working login with a key entry, so it
   is an owner decision, never a rewrite until a line reads green. Mint through the `pi_auth` vendor lane of
   [`scripts/harness/render-pi-config.py`](scripts/harness/render-pi-config.py) (§4 of [docs/harness-pi-models.md](docs/harness-pi-models.md)) and
   never overwrite a live token to green a check. **The seat legs do NOT run FROM the `oldsrv` seat** — that sentence
   held for `win11` and `wsl` and is now measured false for oldsrv (HD-1118's tail): `run_on_seat oldsrv` has one
   transport, `ssh -n … oldsrv-domen`, with no local arm, so `--seat oldsrv` on that box dies at `Could not resolve
   hostname` and with `PI_OLDSRV_TARGET=localhost` at `Host key verification failed`; from any other host the pre-flight
   compares the seat clone with the checkout the driver runs from, so a session branch that is not on `origin/main`
   reads `STALE-CLONE` forever and the planes can only be run **in place** in that clone. That gap is **HD-1162**
   (add the local arm, proved by a `--self-test` arm whose stub transport records whether it was called), and its
   sibling **HD-1161** is the same class one file over: `install-pi-wsl.sh`'s pi leg is `curl … https://pi.dev/install.sh | sh`
   with no version at all while its Debian sibling installs `"${PI_PKG}@${PI_V}"` from the pin — the seat's own smoke
   test printed `expected 1.3.0` against `pi_host_npm_version: 1.1.0`, and `pi-self-update.sh` REFUSES the managed layout
   that installer creates. ⚠ The seat planes are also how the `subagent` payload drift reached two boxes: the compare now
   ignores `_note` (prose) and the push still writes the whole block, with four mutation-proven arms in
   `pi-subagent-config.sh --self-test`. → [prompt-seat-cockpit-grants.md](prompt-seat-cockpit-grants.md)
6. ⏳ **Storage, backup, the DR story** — **HD-191**'s ZFS policy units (**HD-1107**: the policy snapshots do exist
   on every configured dataset — `@autosnap_*_hourly|daily|weekly|monthly`, the row's original "zero snapshots" read
   grepped `@hourly.`, which sanoid's naming can never match — and retention is **43 / 24 / 24**, not the "~100" the
   prose carried; the package's own `/etc/cron.d/sanoid` self-skips on a systemd boot, so the generated timer is the only
   scheduler, and sanoid keeps no `sanoid.log` here, so the deferral line exists only in a manual
   `sanoid --prune-snapshots --readonly --verbose` run. Its replication half was measured 2026-10-19 and **both causes
   in the row were void as written**: `storage-syncoid.service` is not failing, it sits in `activating (start)` since
   2026-10-18 06:45 with `NRestarts=0` and `JobTimeoutUSec=infinity`, **no `zfs receive` is running**, and the wedge is
   `pv` spinning on a pipe whose reader exited (`rchar 4980`, `wchar 0` frozen across two reads) so `sh` never reaps and
   the oneshot never finishes — the stream was 23 KB. One parked owner act: `systemctl stop storage-syncoid.service`
   and then watch a full timer cycle), **HD-1105** (three enabled-but-dead units on nas — all three ruled, `--failed`
   now lists 0), **HD-1106** (re-derived read-only 2026-10-19: the live count is **37**, not 20, 644 MB, every one
   attributed to recreate-churn or a one-off `docker run postgres` whose user db is template1-sized, and absent compose
   labels prove nothing because Docker labels only a compose's **named** volumes — nothing was deleted; the owner half
   is the prune itself plus the two state-in-anonymous-volume paths, `onlyoffice-docs`' `/var/www/onlyoffice/Data` pair
   whose WOPI/JWT keypair is **re-minted at every recreate**), **HD-1093** (**owner**: rotate both
   family SMB passwords, then land them with `storage_samba_password_force` — a vault rotate alone changes nothing
   on the box), **HD-207** and **HD-238**. → [prompt-storage-backup.md](prompt-storage-backup.md)
7. ⏳ **The Pi's own box** — **HD-418** (pair it with **HD-1103** so the box reboots once, and read the premise first:
   on this instance the trust list HA **enforces** is the `.storage/http` object, not the rendered YAML —
   `yaml_migration_done: true`, `stable` and `pending` each carry two entries with `pending.error = "not_promoted"`
   while the rendered `configuration.yaml` lists a third, so `grep -A6 trusted_proxies configuration.yaml` — the read
   this handoff used to tell the next session to take — can neither prove nor fix the `400 untrusted proxy`, and
   neither can a converge of the YAML. The instrument is the **request** (`200` = trusted, `400` names the missing
   address); reconcile BOTH halves on the ACTIVE node and restart in the window the owner authorized 2026-10-08),
   **HD-1103** (the cause is a **tmpfs mounted without `mode=`**, not a mode that drifted — the mount owns the `1777`,
   `mount -o remount,mode=0755` returns 0 and leaves it `1777`, and the fleet value logrotate's secure-parent check
   accepts is `755 root:adm`, not the row's `0755 root:root`. Both halves landed 2026-10-19 in
   `roles/home_assistant/tasks/pi.yml` — fstab `…size=100m,mode=0755,uid=0,gid=0`, the APPLIED mount read with
   `findmnt --target` under `check_mode: false`, the directory reconciled only when the measurement disagrees, plus the
   `ai_diag` `smartctl --scan` probe that starts or masks `smartd` symmetrically — and `logrotate -d` on the Pi now
   prints no `insecure permissions` line at all. The running mount stays without `mode=` until the next boot, and the
   three units still in `systemctl --failed` are each named: logrotate's entry predates the write and clears itself
   tonight, `smartmontools` waits the same untagged `ai_diag` leg, `ha-cert-sync` is the HD-418-family `ha-sync`
   authorisation half), **HD-1109** (⚠ **corrected 2026-10-19: the standby is not cold-deployed, it is UNDEPLOYED** —
   oldsrv runs **39 containers and none of them is `home-assistant-standby` or `keepalived`**, running or stopped; the
   render pins `home-assistant:2026.9.4` and the host holds only `2026.8.1`/`latest`, so `compose up` has never run
   against the current render; `ha-config-sync.timer` is `not-found` and `/usr/local/sbin/ha-config-sync.sh` does not
   exist, so the ~15-min config sync is not installed either; and the VIP is held by the Pi with no live outage. So
   HD-418's standby-edge proof and HD-434's standby KNX tunnel have **no subject** until that cold leg runs — and probe
   the standby with `docker compose -f /opt/home-assistant-standby/docker-compose.yml ps`, NEVER with
   `systemctl is-active keepalived`: its `inactive`/`not-found` is the CORRECT read, because the VRRP half is the
   container that compose does not have), **HD-1101** (**fixed, teeth measured 2026-10-19** — the fail-loud assert is
   keyed on `host_resolver_dns` alone with a per-host `set_fact` naming the profile THIS host writes (`nm_oldsrv_profile`
   → the nmcli leg, `nm_pi_profile` + `nm_parent_iface` → the keyfile leg), so the Pi's resolver list is finally checked
   and `--check --tags nm-resolver` fails on the committed fixture both ways; what remains is the **apply** of that tag
   on pi and oldsrv, the same owner-window Pi apply HD-1103's legs wait in), plus **HD-04 · 434 · 438 · 439 · 319 · 17**.
   → [prompt-smart-home.md](prompt-smart-home.md)
8. ⏳ **Edge and identity** — **HD-147**'s browser-login tail, **HD-457** (the SSO seat owns the family library — ruled; what is left is the per-user/shared-album shape, read at implementation time), **HD-458 · 459** (zipline, the published names), **HD-112**, and **HD-357** — the launchpad tiles, promoted onto this brief 2026-10-13 (its family-surface brief was retired and no successor took the row). ⏸ **HD-47** stays an owner act,
   **Deferred by owner 2026-10-08**: the external-room join is unscheduled; everything publishable is published and
   measured. → [prompt-edge-identity.md](prompt-edge-identity.md)
9. ⏳ **The LiteLLM consumer chain** — one ordered pair left (**HD-384**).
   The rows this brief no longer carries reached ground 2026-10-09: the thinking control IS honoured through both gateways on
   the pinned image ([docs/services-ai.md](docs/services-ai.md) §9d); the `/ui/login` deep-link defect did not
   survive the 2026-10-08 pin (§4c); **voice has an LLM to call** — HA's `litellm` entry, its conversation agent
   and the Assist wire are live, proven by a Slovenian turn end to end
   ([docs/smart-home-voice.md](docs/smart-home-voice.md) header table; the plaintext-replication ruling it required
   is in [docs/deployment-secrets.md](docs/deployment-secrets.md) §Runtime plaintext that leaves the vault); and
   **n8n is audited shut** — one workflow, one webhook called by Grafana on the docker network, tailnet-only, and
   **no AI node**, so there is no key to mint yet
   ([docs/services-utilities.md](docs/services-utilities.md)). That turn also surfaced a defect that is NOT the
   gateway's: Assist cannot resolve "dnevna soba" (**HD-1127**).
   What remains is **sequencing, not thinking**: `litellm-engine_api` is minted and rendered into spark's
   accepted-key list, and the gateways may only be pointed at it **after** spark reboots with it — a spark engine
   restart is an owner-window action (PLE load, ~20 min), so step 2 is parked rather than slipped in.
   → [prompt-litellm-consumers.md](prompt-litellm-consumers.md)
10. ⏳ **The Win11 seat's serving legs** — **HD-474** FIM latency and **HD-476** the VL `mmproj` on the iGPU. The
    laptop's local **agent** leg is retired (owner ruling 2026-10-09), so this brief is FIM + vision only and claims
    no converge host — which is why it can run beside anything except a live pi-seat lane. →
    [prompt-laptop-legs.md](prompt-laptop-legs.md)
11. ⏳ **The `scripts/` restructure** — **landed 2026-10-12**, by re-deriving the 2026-10-09 lane at the tip
   rather than replaying it: `scripts/` is now `lib/ gate/ ansible/ secrets/ git/ harness/ bench/ hardware/
   testdata/` with `validate-all.sh` + `render_all.py` at root, root resolution is structural, and
   `gate/check_script_layout.py` holds the tree from inside `validate-all.sh`. The lane's 13 commits were not
   replayable (0/13 applied across 676 commits of drift) and are pinned as `rescue/hd1118-20261011`. Three live
   legs stay in the row — the two seat legs and the from-zero leg; **the seat legs are run FROM the seat —
   `bash scripts/harness/pi-seat-sync.sh
   --check` and `install-tmux-conf.sh --push` on the win11 seat, in its own session** — because a seat plane
   converges from its own clone and the station cannot speak for a seat's PATH. ⚠ **That sentence is measured false
   for `oldsrv`** (HD-1118's 2026-10-19 tail): `run_on_seat oldsrv` has one transport, `ssh -n … oldsrv-domen`, and no
   local arm beside the `win11`/`wsl` fallbacks, so the driver cannot reach the seat it is standing on — run it from a
   host that resolves the alias, or read the planes in place. That gap has its own row now, **HD-1162**. **The `wsl -d Debian` seat is
   done 2026-10-17, run from that seat**: three planes had sat red there (the tmux target still carried the
   pre-move marker, the skills plane had never been pushed since the self-learn landed, and the settings plane
   had nothing to merge into), one pass of the three owners turned them green, and `pi-seat-sync.sh --seat wsl
   --check` now reports every declared plane OK; `install-pi-debian.sh --check` on a clean Debian seat is the
   third leg and it is **parked** — no host in the fleet is a spare clean Debian box to run it on. The `harness` docs
   domain is registered rather than missing — its row closed 2026-10-19, so the record is the docs and git, not a
   pointer: the hub [docs/harness.md](docs/harness.md) and its §8.3 review/rejected pair exist,
   the one-file harness body is now five subject docs — [docs/harness-pi-engines.md](docs/harness-pi-engines.md),
   [docs/harness-pi-models.md](docs/harness-pi-models.md), [docs/harness-pi-seats.md](docs/harness-pi-seats.md),
   [docs/harness-pi-seat-identity.md](docs/harness-pi-seat-identity.md), [docs/harness-pi-terminal.md](docs/harness-pi-terminal.md) —
   with the whole-tree reference sweep in the same change, and
   [`scripts/gate/check_doc_domain.py`](scripts/gate/check_doc_domain.py) runs in `validate-all.sh` (run + `--self-test`) and prints
   `OK: 88 docs, 10 domains, each with one claimed home`. The taxonomy call it was told about is recorded in
   [prompt-scripts.md](prompt-scripts.md) §The taxonomy call (domain set
   derived from frontmatter; hub required only at ≥2 non-pair docs; a `-review`/`-rejected` pair cannot create a
   domain, so `storage` is not one and its pair retags to `domain: deployment`; `orchestration.md` → `meta`,
   `spark-llm-profiles.md` → `hardware`, `manual/README.md` → `role: index`; §8.1's role vocabulary admits
   `log`/`queue`/`evidence`/`incident-log`). Of its three prose tails, two landed 2026-10-19 and the third landed with
   this commit: the one lane brief whose ownership list named a single harness doc "(split docs: … etc.)" now names all
   five, so a lane's file set can no longer exclude four of them by prose. ⚠ **HD-1165** is a gate blind spot found
   while making `--check` usable: `check_self_converge_guard.py`'s check-5 detector is anchored
   `^\s*check_mode:\s*false\s*$`, so a `check_mode: false` line that carries a trailing comment — all eight in
   `roles/cockpit/tasks/maint-user.yml` — is invisible to the rule that demands `check_safe: false`, and the claim is
   true today by accident rather than by gate. The row names the fix, the read-back (cockpit 0 visible files → 1) and
   the classification step; ⛔ the wrong fix is declaring cockpit `check_safe: false`, which would refuse the very
   `--check` HD-361 exists to make possible. **The
   child-lane contract is a rule with a ceiling and a gate now** — O10/O11 in
   [docs/orchestration.md](docs/orchestration.md) §4 and `subagents.modelScope` in
   [`pi-agent/settings-ssot.json`](pi-agent/settings-ssot.json), held by
   [`scripts/gate/check_subagent_contract.py`](scripts/gate/check_subagent_contract.py). The arm is landed: the `subagent` seat plane ([`scripts/harness/pi-subagent-config.sh`](scripts/harness/pi-subagent-config.sh)) writes `_subagentConfig` → `~/.pi/agent/extensions/subagent/config.json` on every seat, the win11 leg is converged, and the Debian seats converge the payload on the next per-seat `pi-seat-sync.sh --push` — until a seat's own `--check` prints `OK` for that file, the seat runs the harness defaults and a run must pass the values on the launch ([docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1). **The registry's own prose is now a rule with a checker** —
   [`gate/check_registry_prose.py`](scripts/gate/check_registry_prose.py) runs in `validate-all.sh` with its `--self-test` and prints
   `registry: 120 linked rows, 0 state-date exempt site(s), 0 finding(s)` (`--show` prints the live count, never a number typed
   into a handoff), so `scripts/README.md` is a facts-only map: a row states what its script does — flags, verdicts, exit
   contract, declared limits — and names the doc that owns the detail. → [prompt-scripts.md](prompt-scripts.md)
12. ⏳ **Owner-gated tails** (exact steps in the rows): **377** the Grafana render re-do · **444** the phone-crossing
    drill · **418** the HA restart window · **HD-06** the UPS drill · **411** the cockpit resume word ·
    **HD-230/207** the decisions taken at the drill. ⏸ **HD-454 is ruled, not pending** (nothing is purchased and no
    out-of-band path is scheduled, so a switched-off `oldsrv` waits for presence; the one owner-side leg left is a WoL
    re-test at a planned power-off) and **HD-47** above.
13. ⏳ **Unrowed, but not free** — **HD-1100**'s held legs: both owner-authorized PG legs are DONE and verified
    (`litellm-db`, `authentik-postgres`), four middle legs stay held by owner ruling — run one cluster per window on the
    owner's word, each proved by its `pg_control` + key-table read and by the next `db-backup` run that dumps it. ⚠ The
    `wireguard` leg this line used to owe on **oldsrv does not exist there**: `home_servers.yml` carries no `wireguard` role,
    so `--tags wireguard` there selects zero role tasks; the only wg leg in the tree is the **VPS** side, and it restarts the
    tunnel every off-box converge rides — owner-present, detached, run **last**, then re-verify every tunnel path.
    Rowless but not free: the **apt upgrade phase** stays OUT of the converge wave — ruled 2026-10-12 (option A), the
    `roles/updates` design is DECLINED and not pending, and the `apt-mark hold` that ruling required is now live on
    all five hosts (`roles/common/tasks/apt-holds.yml`, read back with `apt-mark showhold`), so `apt upgrade` can no
    longer move a pinned HOST package anywhere in the fleet (`kopia` ships as a pinned CONTAINER image, so there is
    no apt state there). What that leaves is the pin LAG, not the pin, and it is reported: the read-only
    pin-lag series are live on all five hosts and the `pkg-pin-drift` rule is in the ruler (read from
    the ruler API, not from the repo: it sits in `Homelab · Warning` on `count by (instance)
    (homelab_pkg_pin_result{result="differ"})`, `for: 30m`, `noDataState: OK` — count what loads with
    that same read, never from this sentence). It reads RED on `pi` and `spark` and that is true
    drift, not noise: **HD-1148**'s unrun `--tags docker` applies (vps is landed), which is now the only thing left on
    the docker leg — the one pinned package that no task could reach is named in
    `docker_ce_suite_packages`, so one list drives the apt call, the hold lift and the read-back, and an
    apply moves the family to its pin by lifting the hold for exactly the names it touches. →
    [todo.md](todo.md) HD-1148 ·
    [docs/observability.md](docs/observability.md) §Pin-lag report.
14. **Decisions the last wave left open** (none has a domain brief; each is one call, and the evidence that makes it
    actionable is named with it). The gates named here are indexed in [scripts/README.md](scripts/README.md)
    §Validation gate, and every count a gate prints is re-derived by running it here, never quoted.
    - ✅ **`corpus_diff.py --gate` in the pool, or a hand-run wave audit — ANSWERED: it is a pool item now, and
      the rule that kept it out is the rule that changed.** Both halves are registered (`--list` prints the run and
      its `--self-test`). What held it out was that its verdict is a function of a pinned window: measured at one tip
      it printed 203 REJECTs, 194 of them the add/drop-line rule firing on ordinary development and 7 losing a token
      at all — a window green only in the commit that signed it, which is the definition of an item this pool cannot
      hold. The fix was not the constant. `audit_text()`'s add/drop-line rule now carries the same token anchor
      `audit_line()` got, and walking a length-changed file by opcode closed a real hole beside it: an aligned
      in-place rewrite in any file that had also grown or shrunk went unjudged entirely. The same window after:
      17 REJECTs, every one signed by name in [`scripts/gate/corpus_diff_accepts.txt`](scripts/gate/corpus_diff_accepts.txt)
      with the change that made it named in the reason. The pinned pair is immutable, so the item reads the same at
      every commit until `STALE_AFTER_COMMITS` trips it — and that red is the re-sign being owed, not a regression.
      Re-derive every count by running it (`--gate --show-baseline`, plus the closed-window recipe in the NOTE beside
      the registration), never from this sentence. · [scripts/README.md](scripts/README.md) §Validation gate
    - ✅ **The mint space is poisoned by test fixtures — ANSWERED: `9000–9999` is the fixture block, and a gate holds it**
      (owner ruling, A1). A per-id exclusion list was the first answer and it went stale the day a fixture was added:
      `corpus_diff.py`'s classifier fixtures must mint ids that look real, and `scripts/next-hd.sh` scans the whole tree
      on purpose, so the minter handed out an id four orders of magnitude above the registry top. The reservation is a
      RANGE now — `RESERVED_RANGES` in `scripts/next-hd.sh` — stated in [CONVENTIONS.md](CONVENTIONS.md) §1 and
      [todo.md](todo.md) §0, and held in BOTH directions by
      [`scripts/gate/check_hd_mint_space.py`](scripts/gate/check_hd_mint_space.py) (registered: a fixture id outside the
      block reddens, a registry row inside it reddens, prose that disagrees with the tool reddens, a minter that declares
      no block refuses to run). Its ceiling is the **registry rows**, not the token max — a token-based ceiling is a test
      the poison passes by existing, which is how the minter was fooled. Re-derive with `bash scripts/next-hd.sh`; every
      count is that command's output, never this sentence. Of the two findings this line kept un-rowed, the reserved-range
      prose is this change; the `git-bootstrap.sh --self-test` `signedout` arm (it keys on a string its own fixture
      writes, so it proves branch logic and not the `op` contract) is now row **HD-1159** — minted from the clean space,
      which is what made rowing it trustworthy possible.
    - ✅ **Does this station have to push? — ANSWERED: yes, every station pushes after it merges** (option B3).
      The old wording made the push another station's job, which left the fleet's only copy of merged work on one
      disk. So: merge → `git push` → and the check is `git status -sb` reading **level with** `origin/main` (re-derive
      it, never copy a count). A session closing with a count above zero has left a step undone, not skipped one on
      request. On `remote: fatal error in commit_refs` the answer is the §1 retry (`--dry-run` to re-prove ACL, then
      push again), not a permissions hunt — and the commit is never lost, it is on `main` locally the moment you merge.

    - **Register the heading gate, price it, or leave it a tool.** `scripts/gate/check_doc_headings.py` exists and carries
      `--self-test`, and it IS registered now, alongside `check_doc_path_refs.py`: `--list` prints both its run and its
      `--self-test`, and the anchor half runs against a frozen baseline (`gate/doc_headings_baseline.txt`),
      so growth is what reddens a commit — re-derive the count by running it, never by quoting it. The size of
      the debt is the last line of its own run, and the same tool copied into a worktree checked out at an earlier
      revision shows which way the trend moves; the three lawful answers are register it with a frozen baseline and
      refuse growth, run a clearing campaign, or keep it a tool and say so in the index. Ruled 2026-10-13: option (a) — registered with the frozen baseline, growth refused; no clearing
      campaign is owed. (Owning index: [scripts/README.md](scripts/README.md) §Validation gate)
    - ✅ **Which spelling of the IoT DoT-bypass drop is canonical — ANSWERED: the converge's.** The converge writes
      `IoT -> DoT bypass drop tcp (HD-342)` / `… udp (HD-342)` at `IaC/router/templates/rb4011_converge.rsc.j2:441,442`,
      the role's `api_modify` twins at `IaC/ansible/roles/router/tasks/main.yml:793,799` now carry that same pair, and
      the delta's guards compare on it (`rb4011_hd326_fix_delta.rsc.j2:71,74`), so the re-add-a-second-rule shape is
      gone and nothing is owed live — the device pair already read this way, and the folded `iot_off_mgmt` delta that
      used to carry those rows is retired. What the reading taught stays true and general: `community.routeros` has no `key:` parameter
      and pairs device rows to data rows by minimum diff weight, so `comment` is one weighted field and not an
      identifier, and renaming one side of a pair is what `check_string_twins.py` reddens. The remaining `comment=` ids
      come out only with the deltas (the bullet below), which is rule 11 of
      [network-ops.md](docs/network-ops.md) §Rsc authoring conventions.
    - ✅ **`trusted-ha` membership, stated three ways — ANSWERED: the Pi IS a member, and the list is DERIVED.** The
      role and the converge now carry the same expression — the inventory hosts that run HA (`raspberry_pi` +
      `home_servers`, trimmed to short names) plus the VIP — and [network-vlans.md](docs/network-vlans.md) states the
      derivation instead of enumerating it; the read-only render proved the derived set is the live list byte for byte,
      the 2026-09-23 Pi widening included. ✅ **The device read followed on 2026-10-19:** `/ip firewall address-list
      print where list=trusted-ha` holds **5 rows** (`oldsrv`×2, `pi`×2, `ha-vip`) and deriving the set from the inventory
      + `network_static_hosts` reproduces exactly those 5 addresses with those 5 comments; the reverse rule's counter
      reads 1 packet / 53 bytes against the forward rule's 36 / 1 934, which is what first-match-wins expects above an
      `established,related` acceptor, and HA's `sensor.knx_interface_telegrams` was live at 3 611 — so the half-open
      symptom is not present. ⚠ One probe this line assumed is a **no-op**: `homeassistant.update_entity` on a KNX entity
      returns `200` with `[]` in 5 ms and moves neither `last_updated` nor either counter (KNX entities are non-polling).
      The remaining proof is exactly one `GroupValueRead` from the Pi with the counters read either side, which needs a
      privileged act (`docker exec` into the HA container — the socket is `root:docker` — or an integration reload), so at
      night it is an owner act: [todo.md](todo.md) HD-1143.
    - ✅ **The NAT reconcile, and what it removes — ANSWERED: list it.** The reconcile runs with
      `handle_absent_entries: remove` and `restrict: [srcnat, dstnat]`, so anything its own `data:` does not list comes
      off the device — and the Comtrend modem `srcnat` row is now LISTED there, as the byte-twin of the converge's, so
      neither writer can drop it. Narrowing `restrict:` was weighed and declined. What remains is the live apply
      (merge-only so far, the router slot is global) in [todo.md](todo.md) HD-1142 — read the before/after from the
      device, never from the import's exit code.
    - ✅ **Promote the string-purge gate, or keep calling it advisory — ANSWERED 2026-10-13: promoted, in-tree; SUPERSEDED — the run half left the pool, the `--self-test` stayed.** `corpus_diff.py` and its signed accepts list
      live OUTSIDE this repository, so `validate-all.sh` cannot register them and deleting an accept entry narrows the
      check while the suite stays green. Re-derive it: `--list` now prints items for the run and for its
      `--self-test`, and `scripts/gate/corpus_diff.py`, `gate/corpus_baseline.txt` and
      `gate/corpus_diff_accepts.txt` all live in this tree. Promotion takes three things, in this order:
      the tool in-tree with both its run and its `--self-test` registered; a pinned baseline naming the compared
      revision and carrying a digest of what was compared, with the staleness refusal `scripts/gate/check_string_twins.py`
      already has; and the accepts list in-tree under the canary discipline of
      `scripts/gate/iac_identifier_allowlist.txt`, so that deleting an entry reddens instead of quietly narrowing. All three landed together; the run half was later taken out of the pool, because its verdict is a function of the window it pins and a pool item must read the same way at every commit. Its self-test still shows by mutation that deleting an accept entry
      reddens the run instead of quietly narrowing it — so deleting an entry remains an act the suite notices. (Owning index: [scripts/README.md](scripts/README.md) §Validation gate)
    - ⏸ **Retire the RB4011 deltas — RULED 2026-10-13: yes, and scheduled, not executed.** The retire procedure and its
      proof order are written into [network-ops.md](docs/network-ops.md); the window is owner-set (on-site, WinBox on the
      Home leg, read state back through the API), and until it runs the four `comment=` match keys stay untouched.
      `IaC/router/templates/rb4011_converge.rsc.j2:314,315,370,449` remove both nat chains and both filter chains and
      rewrite them in template order, and at this tip every firewall rule the surviving `rb4011_*_delta.rsc.j2` /
      `rb4011_ha_iot_repair.rsc.j2` files add is already written by the converge (measured by comparing rule attributes
      with the comment text ignored; the hd326 pair that reads `to-addresses=$vip` is `:local vip {{ dns_primary_ip }}`
      at `rb4011_hd326_fix_delta.rsc.j2:88` — the same literal the converge writes). So the deltas are redundant for
      firewall state, and their `find where comment="…"` guards are exactly why the ids cannot come out: editing one
      side makes a guard ADD a second rule (`Mgmt -> Home`) or a `remove` stop matching (the `comment~` prefix deletes).
      Proof order and the rule: [network-ops.md](docs/network-ops.md) §Rsc authoring conventions rule 11; owed legs:
      [todo.md](todo.md) HD-1136. ⚠ A full converge is also the one operation §Mgmt-plane caution refuses for
      mgmt-sensitive changes — run it from an on-site station with WinBox reachable on the Home leg, and read the live
      state back through the API rather than trusting the import's exit code.

    Standing on top of those, and not another decision: **no wave owes the twins re-baseline right now — it landed
    at the HD-1118 × HD-1135 merge tip**, and a baseline still never ages past one wave.
    `scripts/gate/twin_baseline.txt` pins the revision the population is read from, and the run compares how far `HEAD`
    has moved from it against its own staleness constant, so re-derive the distance with
    `git rev-list --count $(awk '/^baseline_rev/{print $2}' scripts/gate/twin_baseline.txt)..HEAD` and publish the three
    values with `python3 scripts/gate/check_string_twins.py --show-baseline` in the commit that moves the baseline. That
    act is now safe to perform anywhere in a wave, because HD-1118 pinned the gate's own positive control to a
    population of its own (`CONTROL_BASE_REV`) and made the divergent-family witness a fixture — before that, moving
    `baseline_rev` past `8b28edd3` made case (v) measure backwards, which is why an earlier attempt was backed out.
    - ✅ **Rotate the tailnet sidecar's pre-auth key (`tailscale-sidecar_api`) — ANSWERED 2026-10-18: rotated, and the
      key that leaked is expired.** headscale minted a replacement (`tag:sidecar`, reusable), the vault item points at
      it, and the rendered compose and the live container env both carry it; the leaked key was expired afterwards with
      `vps-obs` still `online`, its tags unchanged, the peer roster identical and a `tailscale ping` ponging. What that
      did NOT prove is the new key's power to register a REPLACEMENT node — `TS_AUTH_ONCE: "true"` means containerboot
      authenticates only when the node is not already logged in, so the new key still reads `Used=false`, and exercising
      it needs a genuine re-registration window, which drops every tailnet dashboard and is an owner-present act. The
      leak class is worth remembering: a redactor that matches `KEY=value` does not match `KEY: "value"`.
      (Owning: [docs/deployment-secrets.md](docs/deployment-secrets.md) · [docs/network-vpn.md](docs/network-vpn.md)
      §Tailnet-exposed services)
    - ✅ **`metabase`: retire the entry or enable it — ANSWERED 2026-10-18: revived on OLDSRV, and the VPS copy is
      gone.** The owner ruled the revival (native login, since Metabase OSS has no OIDC; `sec.kogler.si` stays retired
      forever), so it now runs on oldsrv at `metabase.kogler.si` — a loopback publish, `metabase` + `metabase-ts`
      routers in oldsrv's own `traefik-internal`, no Authentik anywhere, both names answering 200 — and the VPS's
      `/opt/metabase` is removed (16K of two September-2025 renders, no containers, no data volume: nothing to
      preserve). Two hands: the DNS seed converge (`playbooks/dns-seed.yml`, owner-present under HD-436) — until it
      runs the name does not resolve, and every doc says so rather than claiming a live service — and the browser
      first-run wizard plus the `metabase_login` vault item, both in `deployment-manual.md` §P3.7.
      (Owning: [docs/services.md](docs/services.md) · [docs/services-admin.md](docs/services-admin.md) §Metabase)
    - ⏳ **Prove the compose-boot verdict idempotent with one real converge.** The new
      `/usr/local/sbin/docker-compose-ensure` and the rewritten `docker-compose@.service` reached vps/oldsrv/pi/spark
      through task-level template runs, so one `--tags docker_services` pass must return those two legs
      `ok`/unchanged and every service's new reachability check green — the leg that proves IaC and the hosts agree.
      (Owning: [docs/deployment-compose.md](docs/deployment-compose.md) §Boot auto-start (docker-compose@))

15. ⏳ **The gate's own speed on a Windows seat** — **HD-1135** landed the fork diet (gate 134 s → 78 s measured
    interleaved on the Win11 git-bash seat, `$(<file)` proven to be as blind to CR as plain `grep` was) and gave
    `sync-skills.sh` the `--self-test` its encoding guard had been waiting on (teeth proven by mutation, both
    siblings now share one guard). **The bill the folder move re-bought is now paid**: `scripts/lib/pi-seat.sh`'s single
    `pin()` is one `IFS=: read` pass into a `declare -gA` cache (ZERO execs where a `grep|head|sed|tr` call cost 398 ms
    on the Windows seat) and `hl_owner_path()` resolves by ONE `globstar` walk per process as an out parameter, so
    `$( )` cannot swallow its rc. Measured on the Debian seat, interleaved, three rounds: `seat_pkg_rows` went from 82
    execs per inventory walk to 1 with byte-identical output, `pi-settings-config --self-test` 1.11 s → 0.71 s,
    `pi-seat.sh --self-test` 1.06 s → 0.95 s with three EXTRA arms, and the whole `validate-all.sh` 24.1 s → 24.1 s —
    **flat**, which is the honest Debian reading: process creation is not the cost here, so the win11 figures were never
    a Debian forecast. A new counting arm (arm 8) is what catches the regression arm 6 could not — a `sed|head` body
    compares sed with sed and prints GREEN. ⏳ **What is left:** the win11 side of THIS change has not been re-run on
    that seat, so the 398 ms-per-pin numbers still stand for it. Record: [scripts/README.md](scripts/README.md)
    `validate-all.sh` + `sync-skills.sh` rows.

**Parked on an owner-present window** — authored work with exactly one blocked action in front of it, named with that
action so no lane re-derives it: **HD-436** (a) re-render headscale's `config.yaml` on the **VPS** slot, ONE guarded
converge — the answer set is identical, the FILE is not (entry order + comments), so it reports changed and restarts
the control plane: sampled liveness probe, never a one-shot inspect; (b) `IaC/ansible/playbooks/dns.yml` from the **home control
plane**, because the Cloudflare token is IP-filtered there, expected to report no record change; and its step 2 (the
`extra_records_path` swap) is the converge **HD-435**'s `tailnet: dual` publish rides · **the one network leg**
HD-487's row still names — the narrow `--tags netd` delete of `/etc/systemd/network/20-eno1.netdev` **on the VPS**
(vps declares no `netd_phys_name`, so only the role's removal leg reaches it; `wg-s2s.*` and the OS units sit outside the
namespace pattern). The spark networkd disarm, the pi removals (three unread units) and the nas removals (four) are
**landed** — and the nas box settled on NetworkManager on 2026-10-18, so its address and resolver legs are no longer
frozen — and
oldsrv's own lockout-class run **alone**
and off the box with a console reachable (driven FROM the oldsrv controller its `network` tag is refused by the
self-converge guard `IaC/ansible/playbooks/tasks/self-converge-guard.yml`, by design; and a self-target run dies at
the transport before the guard is even reached — the inventory's `ProxyJump=vps` makes the last hop authenticate
against the bare `ansible_host`, where the seat's own alias block pins the operator key — so drive it from another
controller, or use one of the two forms that section measures:
[docs/deployment-ansible.md](docs/deployment-ansible.md) §Runner placement) ·
**HD-384 step 2** — the
two LiteLLM gateways may be pointed at `litellm-engine_api` only AFTER spark reboots with it in its accepted-key
list, and a spark engine restart is an owner window (PLE load, ~20 min); inverting the order 401s every upstream
call · **the docker-family applies** **HD-1148** owes on `pi` and on `spark` (vps is landed) — the daemon restart takes every
container on the host with it, so one host at a time, detached, `--check` first, never behind a
timeout, ⛔ not overnight, and spark is an owner window (vLLM serving state). `oldsrv` owes no apply and `nas` runs
no docker role at all. An apply lifts the hold for exactly the suite names it moves and re-holds them in the same play,
so there is no manual `apt-mark` dance and no `--allow-change-held-packages`; the rule stays RED on `pi`/`spark`
until these run, which is the gap being reported, not a false positive. Six more parks carry exactly one blocked action
each, all measured into their rows on 2026-10-19: **HD-1160** — the owner chooses A/B/C/D for where a per-policy DNS
upstream may live at all (Technitium 15.6 has no such surface and the router's one `:53` dst-nat pair aims every policy
at one shared address; ⛔ shipping a fourth resolver instance as a side effect of a DNS row is what the row forbids) ·
**HD-1122** — flip `ai_tier_metrics_publish: true` and converge **oldsrv** `--tags docker_services,monitoring`: the
flag, the `127.0.0.1` publish and the `prometheus.scrape "llama_cpp"` leg are ONE change that recreates two serving
containers · **HD-1088** — register oldsrv's public key on the live Box (port 23 is key-auth-only; `Hertzner-SB-Data`
holds only a CIFS/WebDAV password), seed `/root/.ssh/livebox_push` 0600 + `/etc/storage/box_known_hosts`, set
`storage_push_music.enabled: true`, converge `--tags storage --limit oldsrv.kogler.si`, `systemctl start
push-music.service` once · **HD-1091** — seed `SLSKD_API_KEY` on slskd (or mint `soulseek-internal_api` and point both
templates at it), confirm `GET /api/v0/options` → `200`, flip `enabled: true`, converge
`--tags docker_services,slskd,soularr --limit oldsrv.kogler.si`, then the one-album proof — seeding the key recreates
slskd and drops the Soulseek session · **HD-1107** — `systemctl stop storage-syncoid.service` on nas to reap the
spinning `pv` and its tree, then watch one full timer cycle; nothing was signalled on the host from the read ·
**HD-1106** — the prune itself, one `docker volume rm` per row the table marks `prune`, and a named volume or bind for
the two `onlyoffice-docs` paths · **HD-1164** — an `intel_iommu=off` experiment plus a memory test on the HP Gen8 in a
window the owner schedules (the box holds the NFS media export, the Kopia agent and HD-1107's stuck `zfs receive`, so
nobody reboots it overnight); the restore line is `systemctl start alloy` on `nas`, and the unit stays stopped until
then · **HD-1143** — exactly one KNX `GroupValueRead` from the Pi with the reverse rule's counters read either side,
which needs a privileged act (`docker exec` into the HA container, or an integration reload) · **HD-1152** — the first
REAL `playbooks/dns-seed.yml` apply per instance, and only after its two defects are repaired, because `--check` skips
the whole Technitium block and can never name candidates · **HD-1101 + HD-1103** — one owner-window Pi apply carrying
`--tags nm-resolver` and the untagged `ai_diag` leg, which is where both rows' remaining halves land ·
**HD-443** — either a host whose journal actually covers the claimed interval, or the owner's ruling that the Pi's
volatile journal cannot prove a 30-day silence and the `admin` revoke proceeds on nine old acceptances plus the
neutralized state · **HD-1110** — the OAuth-vs-`api_key` call on the seat's `pi_auth` providers, which a `--push` must
not settle by rewriting a working login.

**Unbriefed open rows** — no session launches from them; they live in [todo.md](todo.md) and every view. The full
list is **derived** in [todo-table.md](todo-table.md) §B0, so only the ones an owner or a
lane should not lose are named here: **HD-357** (the launchpad tiles — the family-surface brief was retired and
**no domain brief took this row**; the work is wiring, and it wants a promoting decision, not a re-scope) ·
**HD-1083** (the routed group's routes→`*_url` half, owner-present edge window — read §Reachability rule in
[docs/services-traefik.md](docs/services-traefik.md) before touching a route or a publish) · **HD-1089** (one read
from a real tailnet client; the fix is live) · **HD-1116** / **HD-1117** (the two gate halves of the same hygiene
pass: both payloads are paid — Win11, and the WSL seat's own `~/.gitconfig-github` 2026-10-17 run FROM that box — and the
generated-doc drift check is wired as `render_all.py --check --no-write`, because the in-place form truncates `docs/`
and raced every doc-reading checker in the pool. HD-1116's Debian-seat leg is paid — the explicit `commit.gpgsign =
false` was installed and read back FROM `oldsrv`, `vps` and `spark` (the runner accounts; the rest of the Debian seats
are provably not git seats) — and what is left of that row is the owner's `GitHub sign` 1Password deletion. **HD-1117**
carries tonight's pool flake as MEASURED state, not as a fix: three lanes independently watched
`scripts/git/git-bootstrap.sh --self-test` fail inside the `validate-all` pool while passing 5/5 and 10/10 alone on this
WSL Debian seat — it reddened the full gate at a tip tonight and passed every solo repeat, so the row keeps the
reproduction note (red in the pool, green solo, and the arm reaches no real `op` because every fixture dir is first on
PATH) and stays open until someone catches it in the red with the leg's own output) ·
**HD-1130** (a service `enabled: true` in IaC that is **deployed nowhere** — the probe that does not lie is
`ss -ltn | grep 11434` on every host plus the absence of `/srv/docker/<svc>`; decide converge-or-delete, and if delete,
scrub the `ollama/*` wildcards from the VPS key model lists) ·
**HD-1131** (a name answered from a **stale row in the Technitium DNSDB** although no zone and no
`tailnet_subdomains` entry exists — deleting it is an owner act on the DNS tier, then confirm NXDOMAIN on both resolvers) ·
**the ghost CCU reservations are parked** (two address reservations for **hardware never bought** had the generated
address doc publishing ghost CCUs — now commented out in the ledger, not deleted; the parked local-HomeMatic
failover variant itself stays; nothing left to do here) ·
**HD-421** (a pre-seeded writable Docling artifacts bind — chowning `/models` cannot work, the mechanism is in
[docs/services-ai.md](docs/services-ai.md)) · **HD-412** (two enrolment sessions, and ⛔ never on oldsrv: a rescue
tool behind the thing it rescues is not a rescue) · **HD-406** · **HD-440** · **HD-472** · **HD-454** (⏸ owner) ·
and the long tail in §B0.
