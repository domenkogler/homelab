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
(harness state in [docs/harness-pi-engines.md](docs/harness-pi-engines.md)). ⚠ **The delegation-plane check — run it BEFORE routing any lane, on the seat you are on**: start the session on that
seat, launch ONE `async: true` child, and require it to **yield a child session file**. That is the whole test, and no
`--check` substitutes for it: pi 1.3.0 neither ships nor declares `@earendil-works/chord` while an older `pi-subagents`
requires it for the detached background runner, so an `async: true` launch dies at start with 0 s of work and no child
session file while a FOREGROUND child on the same seat runs normally — and every seat plane still reads `OK`.
`pi_host_subagents_npm_version` now pins a release whose alias map asks for chord only when the host manifest declares
it, **and a pin reaches no seat**: the seat legs (`pi-settings-config.sh --push`, then `pi install` of the pinned
version, run FROM each seat) are in [todo.md](todo.md)'s **HD-1180** tail. ✅ **On this seat (`oldsrv`) the check PASSES (2026-10-21)** —
`pi list` reads `npm:pi-subagents@0.80.0` under pi 1.3.0, and ONE `async: true` launch yielded a child session file, ran
to completion and returned its result to the parent: **O11 is met HERE, so lanes launched from oldsrv run `async: true`.**
⚠ The verdict is **per seat**, and the legs are now uneven: **`wsl`** has its declaration pushed green and
`pi list` reading `npm:pi-subagents@0.80.0`, so **one `async: true` launch there is the whole remaining act**;
**`win11`** now reads green on its own `settings` plane from that seat (two pushes, `win11 settings OK` twice, `--check
--strict` rc 0) and its `pi list` carries `npm:pi-subagents@0.80.0` with a path under it, so declaration AND bytes are in
place there too: on both laptop seats the single remaining act is **one `async: true` launch**. The empty read-back that
made win11's declaration unwitnessed is closed — a seat plane now gates its verdict on its **state word**, not on the bytes
that arrived, so a lost or truncated pipe read is `NO VERDICT` (rc 2) and never a state about `settings.json`. A pass on oldsrv certifies only oldsrv. On any seat where the check has not passed, lanes run **foreground-sequential, one at a time**: a stated DEVIATION from O11 that ends seat by seat as **HD-1180**'s fix lands, never a new rule, and never to be
written into [docs/orchestration.md](docs/orchestration.md) or a brief as the contract. ⚠ **On the laptop, grade from the WSL
Debian clone and not the Win11 shell** — three gate items are red or blind on that seat (**HD-1177**), so a Win11
green is a *partial* result and must be reported as one, never as the gate. **Pushing is not that station's exclusive
job: every station pushes after it merges** (the rule is [docs/orchestration.md](docs/orchestration.md) §4 step 5 — an
unpushed `main` is one disk between the work and the fleet). The laptop's WSL Debian clone is **retained, and
now has a job: it is the designated runner station for externally-served runs** — off-box for every converge target, not the
engine host, owner of no converge slot (the 2026-10-09 “retained but rarely used as a seat” ruling still stands for the
pi-dev-seat question, which is a different one; the rule is [todo-table.md](todo-table.md) §C rule 9 and the state is
[docs/harness-pi-seat-identity.md](docs/harness-pi-seat-identity.md) §5a). It stays in `pi-seat-sync.sh`'s `SEATS`, so a fan-out still names it and keeps reporting its real state — its own seat
planes are green (`pi-seat-sync.sh --check`: every `wsl` line OK; the one problem is the oldsrv cockpit's `STALE-CLONE`, and that `ok=` count is a function of THAT seat's clone lagging `main` — with oldsrv current the same command prints `ok=18 problems=0`, so re-derive it, never copy it). Two refs were unique to that box and both are closed: the `never_evict` stash was dropped (main
rejected the pin — `group_vars/spark.yml` §never-evict), and the arr-door branch's content is on `main`
with its object pinned as **`rescue/arr-door-20261006`** — re-derive the rescue set with
`git for-each-ref "refs/*/rescue/*"`, never from this sentence. The station checkout there is clean, one worktree, skills synced, tmux 3.5a.
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
The only vault item left in this area is **`GitHub auth`**, the transport key; `GitHub sign` is deleted and
`git-bootstrap.sh --ssh-auth` treats it as optional — the reason is that script's own comment, and the
mechanism is [docs/1password.md](docs/1password.md) §GitHub signing + auth keys. Seat file map — Windows uses
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
   — **✅ RULED 2026-10-20 (owner): ONE tier-wide upstream; the per-policy claim is dropped** (quote the mechanism from
   the row, never a letter — the two views lettered the options differently). So the device-level Kids/IoT acceptance in
   HD-481/482 is not owed by any settings change: filtering, where the family needs it, is a device-side act.
   **HD-1160** is now ONE item and it is not AI: the retag LANDED — [network-dns.md](docs/network-dns.md)
   §What the pin can and cannot enforce, [network-rejected.md](docs/network-rejected.md) and the router role's comment —
   and **no converge is owed**, because the tier already runs the one shared forwarder list. What remains is the
   converge template's twin of that retagged router comment: the `#`-line in
   `IaC/router/templates/rb4011_converge.rsc.j2` is RENDERED output (HD-1167's class), so it moves only inside an
   **owner-present router window** (the global slot; ⛔ never from a docs lane, never `--diff`). The rules' own
   `comment=` strings are live device state and stay as they are. Also open on the same tier, unbriefed: **HD-1152**'s prune leg has been proved
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
   `[monitoring]`) are landed, and **the PAGING half is authored, LOADED on the backend and watched red** — the
   generated `absent_over_time`-per-host form was chosen over the anti-join (an anti-join needs a publisher nothing
   publishes, so its failure direction is silence), one rule per `[monitoring]` host, `noDataState: OK` with
   `execErrState: Alerting`, proven at 16:30 on the box that has published nothing since its collector began
   crash-looping. The proof is the loaded set (`GET /api/v1/provisioning/alert-rules` → 32 rules, `provenance: file`),
   never the repo file, because **a rule that is authored is not a rule that is loaded** — and the one-word reason it
   used to be unverifiable was a provisioning task with no `tags:` of its own: the ROLE is tagged `monitoring` and
   Ansible inherits role tags onto every task, so `--tags monitoring` always selected it, while **`--tags grafana`
   silently dropped it** and still recapped `failed=0` (measured both ways on the backend: no task line at all, then
   the task line and `changed=2` once the tag was added). The task carries `[monitoring, grafana]` now, so either filter
   loads rules; that is also why no row is minted for "write the paging rule in a grafana window".
   **HD-1166** is the reachability half of the same sweep and it is a FINDING about a rule we already ship:
   `host-unreachable` cannot name the host that is down, because `probe_success{job="blackbox_icmp"}` carries the
   EXPORTER's address (`127.0.0.1:9115`) as `instance` for all five targets — `__param_target` is a query parameter and
   never becomes a label — and `ha-unreachable`'s `instance="https://ha.kogler.si"` filter can therefore never match a
      series at all. **The read ran, the premise held, and the fix is live**: through the 2026-10-20 `oldsrv` outage
   `probe_success{job="blackbox_icmp"}` read `1` for all 271 samples — four live hosts masking the dead one — so
   `host-unreachable` could neither fire nor name a host, and the relabel that makes each target name itself in
   `instance` is what made that visible. ⚠ **Retiring a probe target can be the cheaper half of a fix — check what the
   rule was actually watching.** `ha.kogler.si` is `internal: true` with no public record, so the backend host cannot
   resolve it and `ha-unreachable` had never matched a series; giving the series a real `instance` made the target fail
   and a CRITICAL page that describes a healthy HA. The target and the rule are retired, and the honest consequence is
   that **HA liveness has no firing rule** until the gated `ha_exporter` job → **HD-1182**; one owner-present VPS
   `--tags monitoring` converge applies the retirement, and that apply is the row's only live tail.
   **HD-1164** is why `nas` is the blind host — the
   collector dies ~5 s after every start with `fatal error: traceback did not unwind completely` on Go 1.26.7, with the
   repo, the backend and the DMAR lines all excluded, so the acceptance is a firmware/kernel look plus a memory test the
   owner schedules and the unit stays **stopped on purpose** meanwhile. ⚠ `check_host_reporting.py --check` reads RED for
   `nas` and that is the instrument working — do not soften the expected set to make it green. **`oldsrv` is the
   second blind host and it is an incident, not a rule defect** — every job it publishes stopped at the same minute
   on 2026-10-20, it answers on no leg while the three other hosts ride the same tunnel peer, and there is no
   out-of-band power path (HD-454's posture), so the first act was an owner at its console → **HD-1175**, which is
   **recovered but not closed**: its telemetry is proven, not assumed — all four of its jobs `up`, `check_host_reporting.py --check`
   reports its series, the exported units all read `success`, and the store excludes a thermal, memory, load or disk
   excursion — a clean hard stop. What the row still owes is the root-only read (the previous boot's journal and
   `pstore`), because the cause is still unexplained and no rule can reach it from a user session. The same reboot
   surfaced a boot-time DB-dump push race that no rule can see → **HD-1183**.
   **What arrives in the channel is a separate design question from what fires.** A still-firing alert now
   re-sends at most every **24 h** (`repeat_interval` in the notification policy `roles/monitoring` renders;
   `group_wait: 2m` and `group_interval: 10m` are untouched, so the FIRST send is not delayed). At 30 min a
   finding that is parked for days by design — a host in an owner hardware window, a host off its pin — was
   a page ~48 times a day, which is how an alert channel stops carrying information. ⛔ **HD-1174** is
   registered and open: kopia's `repository connect server` echoes the URL it was handed, so the
   `kopia-server-internal_api` credential sits in plaintext in the agent's container log and in the log store
   for the retention window — scrub the connect line, then rotate with the agent **re-connected** (its
   `repository.config` caches the credential). →
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
   in Prowlarr's own UI. **HD-1091** is authored and **ARMED**, not OFF: `templates/docker_services/soularr/` +
   `soularr_version: "1.2.2"`, `enabled: true` on the oldsrv Home leg, and ONE vault item (`soulseek-internal_api`)
   rendered into **both** ends — `SLSKD_API_KEY` in slskd's env and `[Slskd] api_key` in soularr's rendered
   `config.ini` — so neither side can be armed alone. The arm is proven in the order that matters: the internal key
   answers `200` on `GET /api/v0/options`, the UI password answers `401` there, and `POST /api/v0/session` with the UI
   password still returns a JWT, so the owner's login survives the arm. That item was **rotated twice**, once for each
   of two leaks of its own making, and the read pattern that caused the second is now written into
   [deployment-secrets.md](docs/deployment-secrets.md) — the key was never absent, it was never *rendered*, which is
   why the row's earlier "this box has no slskd API key" was true when written and is not true now. What the row owes
   is not a seed: **one album crossed end-to-end**, which needs a peer to finish one inside the poll window (the last
   attempt crossed everything but soularr's final rename, and the `remote_queue_timeout` that cut it is measured and
   raised), and the **`lidarr_api` rotation**, which `provision-secrets.py` refuses to auto-rotate and which moves
   four copies in a forced order. The `SLSKD_DOWNLOADS_DIR` retarget is decided as NONE (soularr renames in place and fires `DownloadedAlbumsScan`, so the
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
   1110 · 1138 · 1139 · 1140 · 1161 · **1173**) with its owner-gated tails intact, plus **HD-1180** (unbriefed — its AI
   half is one pin line in `IaC/ansible/group_vars/all/versions.yml`, its acceptance half is a hand on each seat).
   ⚠ **Pull the DRIVER clone first: at `main~2` the pre-flight calls two current seats `STALE-CLONE**, and the remediation it
   prints then points at the two boxes that needed nothing). **HD-1173 is registered and
   UNIMPLEMENTED** — the parked `dsh` + `pi-dev` harness IaC is to be removed and `pi-dev.ts.kogler.si` made a
   second name on the existing `pi-oldsrv-backend` (`pi-oldsrv.ts.kogler.si` stays canonical); only the row landed,
   so its four lanes and its live tails are all still open. Sequence note UPDATED: the fleet pi pin moved to 1.3.0 on 2026-10-21 with **both** vars moved together (`pi_host_npm_version` and `pi_dev_npm_version` MUST stay equal), so what this row still owes on the pin side is the deletion half — dropping `pi_dev_npm_version` and its `image-pin-probe.py` row is what leaves the repo with one pi pin instead of two. **The laptop↔oldsrv coding leg closed
   2026-10-16:** the alias contract is LAN-direct by default with `<node>-vps` as the opt-in hop, all three seats
   carry one contract digest, and VS Code connects over `oldsrv-domen`; what is left in that cluster is the
   away-case spelling in the scripts that shell out (`1138`) and the VS Code server-install leg it gates. **HD-1139**
   closed its own premise 2026-10-19: the prefix read ran from the router and there is NO dead prefix class — one
   global /64 plus an active `::/0`, and every destination that HAS a `AAAA` answers over v6; what failed fast
   (`http=000` in 15–140 ms, not a timeout) are **A-only hostnames** that answer nothing at our resolvers or at a
   public one, so no rule change is warranted and none was made. **HD-1140** is **ruled 2026-10-20 (owner): the ledger owns
   the laptop's Home reservation** — a `network_static_hosts` row plus a find-guarded `rb4011_*_delta` in the Pi's shape, so
   the apply rides an existing router window rather than needing one of its own; the lease read it needed already ran. **HD-495**: its
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
⚠ The first attempt died in `ansible-run.sh`'s self-update with no `PLAY RECAP`: the failure shape and the
launcher's own diagnosis are [docs/deployment-ansible.md](docs/deployment-ansible.md) §Runner placement.
Read [docs/1password.md](docs/1password.md) §1
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
   days of RAM read twice, nothing was changed, and the trigger read is **ruled closed 2026-10-20 (owner)**: a volatile
   journal cannot prove a 30-day silence, so the `admin` revoke proceeds on the neutralized state plus the fingerprint
   match, behind the order that keeps the door open (`ansible-admin` and `domen` proven first). ⛔ A raw journal grep
   for the phrase also **matches the probe that greps for it** — filter on `sshd-session[…]` / `-u ssh.service`.
   ⚠ Never re-add `git commit -s`; signing is retired. **HD-1110**: `scripts/harness/pi-seat-sync.sh` is
   the one deploy path; its 2026-10-08 "oldsrv closed on all eight planes" reading is VOID. Current reading: the driver
   run **FROM the Win11 seat** reaches all three seats → **`RESULT ok=29 problems=0`**, `pi-self` OK everywhere at the
   **1.3.0** pin (win11 volta, wsl the pinned npm prefix, oldsrv `pi update` — pi's managed layout, which
   `pi-self-update.sh` refuses to npm-install under, and `pi update` on the win11 layout refuses too). ⚠ A plane
   command executes in the SEAT's shell, so its python launcher resolves there —
   [docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1. Earlier readings stay as seat-local truth: `--check
   --seat wsl` FROM the wsl seat → `RESULT ok=10 problems=0`, `models` reporting **no drift** because that seat's
   `pi_auth` entries really are `type: api_key` as `scripts/harness/pi/models-spec.yml` declares. The row's own tail closed tonight: `install-pi-wsl.sh` now **owns
   PATH persistence** (`persist_path()` writes the node `current` bin dir and pi's entrypoint dir under its own marks,
   distinct from `install-pi-debian.sh`'s, and `verify_login_path()` then asks a LOGIN shell and fails if a `/mnt/c`
   copy wins) instead of printing a NOTE about `~/.bashrc`. **The Win11 seat leg is paid** (2026-10-21, FROM that seat — the fan-out reading above).
   What remains: the OAuth-vs-`api_key` call on the
   `pi_auth` providers — **ruled 2026-10-20 (owner): `api_key` is the fleet spelling**, an OAuth entry on a seat is drift,
   and it is never cured by overwriting a live credential: the plane reads the live `type` and reports the mismatch instead
   of rewriting. Mint through the `pi_auth` vendor lane of
   [`scripts/harness/render-pi-config.py`](scripts/harness/render-pi-config.py) (§4 of [docs/harness-pi-models.md](docs/harness-pi-models.md)) and
   never overwrite a live token to green a check. **The seat legs run FROM their own seat, oldsrv included**:
   `run_on_seat oldsrv` has two arms and the box's own hostname picks one — the local arm when this host IS the oldsrv
   seat (so `--seat oldsrv` there reads the clone you are standing in and the pre-flight certifies it), the ssh arm
   first everywhere else (`oldsrv-domen`, `oldsrv-domen-vps` included) — proved by two `--self-test` arms that shim
   `hostname` and record which leg ran; run from any OTHER host the pre-flight still compares the seat clone with the
   checkout the driver runs from, so a session branch that is not on `origin/main` reads `STALE-CLONE` there.
   The matrix and the seat-side rule:
   [docs/harness-pi-seat-identity.md](docs/harness-pi-seat-identity.md) §5a. Its sibling **HD-1161** is the same class
   one file over: `install-pi-wsl.sh`'s pi leg is `curl … https://pi.dev/install.sh | sh`
   with no version at all while its Debian sibling installs `"${PI_PKG}@${PI_V}"` from the pin — the seat's own smoke
   test printed `expected 1.3.0` against `pi_host_npm_version: 1.1.0`, and `pi-self-update.sh` REFUSES the managed layout
   that installer creates. ⚠ The seat planes are also how the `subagent` payload drift reached two boxes: the compare now
   ignores `_note` (prose) and the push still writes the whole block, with four mutation-proven arms in
   `pi-subagent-config.sh --self-test`. ⚠ **HD-1180 is the delegation plane the pi 1.3.0 bump took away** —
   pi-subagents 0.76.1 requires `@earendil-works/chord` from any host that is not a pre-chord `0.<minor>.<patch>`, and
   pi 1.3.0 ships and declares neither, so EVERY `async: true` launch fails at start (a foreground child on the same
   seat runs normally) while `pi-seat-sync.sh --check` reads all-OK: O11 was unmet on all three seats and no plane check
   could see it. ✅ **The AI half is DONE 2026-10-21:** `npm view pi-subagents version` re-probed → 0.80.0 and
   `pi_host_subagents_npm_version` moved 0.76.1 → 0.80.0 in [`IaC/ansible/group_vars/all/versions.yml`](IaC/ansible/group_vars/all/versions.yml)
   (0.80.0 requires chord only when the host manifest declares it) — a pin reaches no host, so nothing changed on any
   seat by that commit; ✅ **the oldsrv leg is DONE + PROVEN 2026-10-21** — that seat's `pi list` reads `pi-subagents@0.80.0`
   under pi 1.3.0 and ONE `async: true` launch yielded a child session file, completed, and returned its result (the row's
   own acceptance form, met on that box — §1 launches async there now). ⏳ **owner, two seats left** — the `settings` plane
   pushed and `pi install npm:pi-subagents@0.80.0` run FROM win11 and FROM wsl, each accepted by **its own** `async: true`
   launch that yields a child session file (a green plane matrix proves none of it, and a pass on oldsrv certifies only oldsrv).
   ⛔ never by npm-installing chord under a managed seat tree. Until a seat's own leg runs, the foreground-sequential
   deviation in §1 binds THAT seat. → [prompt-seat-cockpit-grants.md](prompt-seat-cockpit-grants.md)
6. ⏳ **Storage, backup, the DR story** — **HD-191**'s ZFS policy units (**HD-1107**: the policy snapshots do exist
   on every configured dataset — `@autosnap_*_hourly|daily|weekly|monthly`, the row's original "zero snapshots" read
   grepped `@hourly.`, which sanoid's naming can never match — and retention is **43 / 24 / 24**, not the "~100" the
   prose carried; the package's own `/etc/cron.d/sanoid` self-skips on a systemd boot, so the generated timer is the only
   scheduler, and sanoid keeps no `sanoid.log` here, so the deferral line exists only in a manual
   `sanoid --prune-snapshots --readonly --verbose` run. Its replication half was measured 2026-10-19 and **both causes
   in the row were void as written**: `storage-syncoid.service` is not failing, it sits in `activating (start)` since
   2026-10-18 06:45 with `NRestarts=0` and `JobTimeoutUSec=infinity`, **no `zfs receive` is running**, and the wedge is
   `pv` spinning on a pipe whose reader exited (`rchar 4980`, `wchar 0` frozen across two reads) so `sh` never reaps and
   the oneshot never finishes — the stream was 23 KB. **✅ Ruled 2026-10-20 (owner): take the replica datasets out of the
   snapshotting template — the retag, never a hand-destroy of the 66.** A `zfs receive` target takes no autosnapshots of its
   own and the rollback targets of record are the source-side `tank/data/*` snapshots; the act is AI work on the `nas` slot
   and is sequenced in the row — kill the wedged pipeline's shell wrapper first, or sanoid's `iszfsbusy()` defers every
   prune and the retag looks like it did nothing), **HD-1105** (three enabled-but-dead units on nas — all three ruled, `--failed`
   now lists 0), **HD-1106** (re-derived read-only 2026-10-19: the live count is **37**, not 20, 644 MB, every one
   attributed to recreate-churn or a one-off `docker run postgres` whose user db is template1-sized, and absent compose
   labels prove nothing because Docker labels only a compose's **named** volumes — nothing was deleted; the owner half
   is the prune itself plus the two state-in-anonymous-volume paths, `onlyoffice-docs`' `/var/www/onlyoffice/Data` pair
   whose WOPI/JWT keypair is **re-minted at every recreate**), **HD-1093** (⏳ land the rotated family SMB passwords on the NAS with `storage_samba_password_force` —
   ✅ the **owner**'s own rotate happened on 2026-10-08, so the rotate is not owed here and a vault rotate alone changes
   nothing on the box), **HD-207** and **HD-238**. → [prompt-storage-backup.md](prompt-storage-backup.md)
7. ⏳ **The Pi's own box** — **HD-418** (✅ **reconciled at both ends and owned in IaC** — `roles/home_assistant/tasks/pi.yml`,
   tag **`hd418`**: `.storage/http` now carries `oldsrv_home_ip`/32 in `stable` AND `pending`, `--check ok=27 changed=1`
   → apply `ok=32 changed=3 failed=0` → the same apply again `ok=26 changed=0`, no second restart. The proof is
   BEHAVIOUR and not the YAML, because on this instance the list HA **enforces** is the `.storage/http` object
   (`yaml_migration_done: true`) and `grep -A6 trusted_proxies configuration.yaml` can neither prove nor fix a `400`:
   HA's own log shows the real client address honoured through the Pi's `traefik-ha` edge, and a forged XFF sent straight to `VIP:8123` still draws
   `[http.forwarded] Received X-Forwarded-For header from an untrusted proxy …` + `400 Bad Request` — enforcement, not
   an echo. The read the row names as still owed is the **XFF-present → 200 through the `traefik-internal`
   middleware**, which its own note in `routes.yml.j2` now records. ⏳ what that does not buy is the takeover-shaped request sent **from the oldsrv edge** (another lane's
   host), and the standby-shaped case has **no subject** while HD-1109 stands), **HD-1103** (the cause was a **tmpfs
   mounted without `mode=`**, not a mode that drifted — the mount owns the `1777`, `mount -o remount,mode=0755` returns
   0 and leaves it `1777`, and the fleet value logrotate's secure-parent check accepts is `755 root:adm`. The logrotate
   half is now **proven by a real rotation**: `systemctl start logrotate.service` → rc 0, `Result=success`, the `.1`
   files on disk stamped in the same second as `/var/lib/logrotate/status`, and `systemctl --failed` is down to
   **`smartmontools` alone**. Two halves remain and both are choices, not commands: `/var/log` is a **100 MB tmpfs** on
   `weekly` + `rotate 4` with **no `compress`** — 77 M of 100 M was in use, so rotating only moved bytes within the
   same filesystem — so either `compress` + `delaycompress` (four periods inside 100 MB, at the cost of recompressing
   a ~75 MB `syslog` every rotation) or `rotate 1` + `maxsize` (trivial arithmetic, one period of local history on a
   box whose durable log store is VictoriaLogs on the VPS); **the first act is `logrotate -d` plus `df -h /var/log`,
   and the repo owns no logrotate config at all today**, so whichever wins is a NEW file sized against `size=100m`, not
   an edit. The other half is the smartd park, measured to the end: smartmontools **7.4-3** cannot address this card by
   any type (`-d scamm` → `Unknown device type 'scamm'`, `scsi` → "Both 36 and 64 byte INQUIRY failed", `sat` → "Read
   Device Identity failed", `smartd -q onecheck` exits 17 with nothing to monitor), so the choice is a ≥7.5 source or
   the mask `roles/ai_diag` **derives** from an empty `smartctl --scan` — a designed converge outcome the next
   UNTAGGED converge applies in an owner window, and a lane hand-disabling the unit by hand would be the actual defect.
   The fstab `mode=0755` becomes true on the mount at the **next boot**, not from a converge; ⛔ never
   `mount -o remount` as the fix), **HD-1167** (a comment in a template can rewrite a running box's addressing file:
   `Render Pi eth0 NetworkManager keyfile` reports `changed` on EVERY converge while every functional line already
   matches, because `#`-lines in a `.j2` are literal OUTPUT rather than `{# … #}` Jinja comments — and `changed` is
   what notifies `reload NetworkManager` on a box of the DNS tier. First act is the stripped comparison, both sides
   (`grep -v '^#'` on the host file against the template's non-comment lines); the fix belongs in `roles/network`,
   never on the host; the one-time re-render that brings an existing box in line is an owner-window act with HD-1101's
   rollback standing by, and `spark` uses the same render unmeasured), **HD-1109** (⚠ **the standby is UNDEPLOYED, not
   cold-deployed** — oldsrv runs **39 containers and none of them is `home-assistant-standby` or `keepalived`**, and
   the render pins `home-assistant:2026.9.4` which that host does not hold, so `compose up` has never run against it
   and HD-418's standby-edge proof and HD-434's standby KNX tunnel have **no subject**. ⚠ **and half of the first
   correction was itself wrong**: `ha-config-sync.timer` is not missing — on the Pi it is `enabled` + `active`, fires
   every ~15 min and its last run finished clean in 2 s (`Finished ha-config-sync.service — Push Pi HA config →
   oldsrv standby`); the `not-found` was read on **oldsrv**, the wrong host, which is exactly
   the class this row exists for (a systemd/file-presence probe answers about the box you ran it on). Probe the standby
   with `docker compose -f /opt/home-assistant-standby/docker-compose.yml ps`, NEVER `systemctl is-active keepalived`:
   its `inactive` is the CORRECT read, because the VRRP half is the container that compose does not have),
   **HD-1101** (**fixed and APPLIED on both hosts** — the fail-loud assert is keyed on `host_resolver_dns` alone with a
   per-host `set_fact` naming the profile THIS host writes (`nm_oldsrv_profile` → the nmcli leg, `nm_pi_profile` +
   `nm_parent_iface` → the keyfile leg), so the Pi's resolver list is finally checked and the committed fixture fails
   the guard both ways. Pi: `--check ok=22 changed=0` then apply `ok=22 changed=0` — the guard RAN and PASSED and
   nothing was written, because the Pi was already correct; oldsrv: `ok=33 changed=0`. ⚠ tag class, so nobody
   re-derives it wrong: on a keyfile host the write leg is **`nm-pi`**; `--tags nm-resolver` there selects the guard
   and proves the check, and writes nothing), plus **HD-04 · 434 · 438 · 439 · 319 · 17**.
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
   New in this lane, **unbriefed**: **HD-1178** — the oldsrv `embed` leg's next model gets chosen by a bench, not
   by a leaderboard. Nothing is measured yet; the corpus, both gates and the probe commands are in
   [docs/services-ai-bench.md](docs/services-ai-bench.md) §3d, and the bench's first act is a `server-vulkan` pin
   bump that recreates the **reranker** leg with it. `EmbeddingGemma 2` is rejected for the RAG leg and stays in
   scope only as the code-retrieval candidate inside that bench (OQ-14 is open on that axis, and its docs half
   still stands parked on the measured recall floor).
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
   converges from its own clone and the station cannot speak for a seat's PATH. ⚠ **One correction to that sentence**:
   it was measured false for `oldsrv` (HD-1118's 2026-10-19 tail — one transport, `ssh -n … oldsrv-domen`, no local arm
   beside the `win11`/`wsl` fallbacks), and the driver now carries that local arm, chosen by the box's own hostname
   ([docs/harness-pi-seat-identity.md](docs/harness-pi-seat-identity.md) §5a), so `--seat oldsrv` run FROM oldsrv reads
   the clone you are standing in. **The `wsl -d Debian` seat is
   done 2026-10-17, run from that seat**: three planes had sat red there (the tmux target still carried the
   pre-move marker, the skills plane had never been pushed since the self-learn landed, and the settings plane
   had nothing to merge into), one pass of the three owners turned them green, and `pi-seat-sync.sh --seat wsl
   --check` now reports every declared plane OK; `install-pi-debian.sh --check` on a clean Debian seat is the
   third leg and it is **parked** — no host in the fleet is a spare clean Debian box to run it on. The `harness`
   docs domain is REGISTERED, not missing: its five-way split, its checker and the taxonomy call are
   [prompt-scripts.md](prompt-scripts.md) §The taxonomy call and the hub [docs/harness.md](docs/harness.md), and
   the verdict count is that checker's own output. ⚠ **The `check_mode: false` rule now sees the line as this repo
   writes it**: `check_self_converge_guard.py`'s detector carries the trailing comment YAML allows
   (`check_mode: false   # read-back` IS false), and the site is then classified by its carrying task — a read-only
   module (`stat`/`slurp`/`find`/`get_state`/`*_facts`) or a `command`/`shell` declaring `changed_when: false` is a
   read-back, anything else (an unknown module, a `command` with no `changed_when`) is a WRITE and reddens naming
   `file:line`. cockpit reads **0 write / 8 read-back**, so its `check_safe: true` is a gate verdict now and not an
   accident; ⛔ the wrong fix would be declaring cockpit `check_safe: false`, which would refuse the very
   `--check` HD-361 exists to make possible. The verdict table is
   [docs/deployment-ansible.md](docs/deployment-ansible.md) §Self-converge guardrail. **The
   child-lane contract is a rule with a ceiling and a gate now** — O10/O11 in
   [docs/orchestration.md](docs/orchestration.md) §4 and `subagents.modelScope` in
   [`pi-agent/settings-ssot.json`](pi-agent/settings-ssot.json), held by
   [`scripts/gate/check_subagent_contract.py`](scripts/gate/check_subagent_contract.py). The arm is landed: the `subagent` seat plane ([`scripts/harness/pi-subagent-config.sh`](scripts/harness/pi-subagent-config.sh)) writes `_subagentConfig` → `~/.pi/agent/extensions/subagent/config.json` on every seat, the win11 leg is converged, and the Debian seats converge the payload on the next per-seat `pi-seat-sync.sh --push` — until a seat's own `--check` prints `OK` for that file, the seat runs the harness defaults and a run must pass the values on the launch ([docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1). **The registry's own prose is now a rule with a checker** —
   [`gate/check_registry_prose.py`](scripts/gate/check_registry_prose.py) runs in `validate-all.sh` with its `--self-test` and prints
   `registry: 120 linked rows, 0 state-date exempt site(s), 0 finding(s)` (`--show` prints the live count, never a number typed
   into a handoff), so `scripts/README.md` is a facts-only map: a row states what its script does — flags, verdicts, exit
   contract, declared limits — and names the doc that owns the detail. → [prompt-scripts.md](prompt-scripts.md)
12. ⏳ **Owner-gated tails** (exact steps in the rows): **377** the Grafana render re-do · **444** the phone-crossing
    drill · **1103 + 1167** one Pi visit — the boot that makes the fstab `mode=` true on the mount, and the one-time
    re-render of `pi-eth0.nmconnection` that notifies `reload NetworkManager` (HD-418's HA restart window was spent in
    the reconcile apply, so it is no longer gated) · **HD-06** the UPS drill · **411** the cockpit resume word ·
    **HD-230/207** the decisions taken at the drill · **1175** a human at `oldsrv`'s console — there is no
    out-of-band power path at all (the posture **HD-454** rules; its WoL re-test has never been run), so the
    box is read by eye · **1170 · 1171 · 1150** the three secret-close windows: rotate
    `spark-llm_api` (published in a tracked bench capture of the public repo — the blob is still reachable from a ref,
    so only rotation closes it) and rule on `radarr_api`/`sonarr_api` (same publication class, `NOT_AUTO_ROTATABLE`);
    rotate `op_api` and re-seat all four installs; re-seat `vps:/etc/op/provision-token` with the `matrix_password`
    ruling — none of these closes with a repo change. **HD-1181** extends that list to **14 CURRENT vault values** this
    seat's pi transcripts hold: the rotation is the owner's and it differs per item — a vault edit + re-render
    (`cockpit-pi-web_api`, the two Victoria basic auths, the three CAPsMAN PSKs), rotate **in the app first** for the two
    app admin logins and `bazarr_api`, **coupled** for `n8n_password` (= `N8N_ENCRYPTION_KEY`, so stored credentials must
    be re-encrypted) and the kopia repo password (HD-1174's rotate-and-reconnect window, or backups stop quietly), the
    unix `domen` password on `oldsrv` (lanes read it through `op read … | sudo -S -p ""`), and the provider side for the
    VPN key. ⚠ **`check_secret_leak.py` — and with it `validate-all.sh` — is RED at the tip here BY DESIGN until that
    rotation lands**: no ledger line was added and the checker was not edited to quiet a live value, so a green leak read
    on this seat would mean the register was muted, not that the exposure is gone. Deleting or shredding transcripts closes
    nothing — a rotated value stops being a finding, an unrotated one never does; the register is per seat, so win11 and
    wsl owe the same read. **HD-1160** owes one owner-present **router window** (global slot): the converge template's
    twin of the retagged router comment, `IaC/router/templates/rb4011_converge.rsc.j2` — a `#`-line that IS rendered
    output, so it moves with a render + `routeros-apply-delta.sh` inside the window and never from a docs lane, never
    `--diff`. ⏸ **HD-454 is ruled, not pending** (nothing is purchased and no
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
    that same read, never from this sentence). It is QUIET, and that is the fleet reading, not a mute:
    the last `--tags docker` apply landed on `pi` (`ok=35 changed=3 failed=0`; docker-ce/-cli/rootless-extras
    `5:29.8.2`, containerd.io `2.3.6`, buildx `0.37.1`, compose `5.5.1`, re-held in the same play, every
    rule `inactive` afterwards), so **no apply is owed on the docker leg anywhere** — `oldsrv` never was, `nas`
    runs no docker role, and the row is deleted with its last ⏳ emptied. What the leg taught stays put: one
    list (`docker_ce_suite_packages`) drives the apt call, the hold lift and the read-back, and every host
    that carries the suite is on its pin. →
    [docs/observability.md](docs/observability.md) §Pin-lag report.
14. **Decisions the last wave left open** (none has a domain brief; each is one call, and the evidence that makes it
    actionable is named with it). The gates named here are indexed in [scripts/README.md](scripts/README.md)
    §Validation gate, and every count a gate prints is re-derived by running it here, never quoted.
    - ✅ **The 2026-10-20 owner round — nine rulings, one sitting.** **HD-1160** one tier-wide DNS upstream, a retag,
      no converge owed · **HD-1107** the replica datasets leave the snapshotting template, never a hand-destroy ·
      **HD-1106** prune by name, the onlyoffice named volume first · **HD-1103** `rotate 1` + `maxsize`, a new
      role-owned file · **HD-1140** the ledger owns the laptop's Home reservation, riding an existing router window ·
      **HD-357** `seerrng` stays tailnet-only, its tile linked-not-probed · **HD-443** revoke the Pi's `admin` on the
      neutralized state · **HD-1110** `api_key` is the fleet spelling, report drift, never overwrite it ·
      **HD-448/460** KEEP-THE-PARITY stands, "chase inbound IPv6" answered no → [todo-table.md](todo-table.md) §A1's
      2026-10-20 block, and each row's `RULED 2026-10-20` note in [todo.md](todo.md).
    - ✅ **The gate calls.** `corpus_diff.py`'s purge audit lives in-tree on a pinned window with a signed accepts
      list · the mint space reserves `9000–9999` for tool-fixture tokens, held in both directions by a gate · every
      station pushes after it merges → [scripts/README.md](scripts/README.md) §Validation gate (what the pool holds is
      `--list`, never this sentence) · [CONVENTIONS.md](CONVENTIONS.md) §1 + [todo.md](todo.md) §0 ·
      [docs/orchestration.md](docs/orchestration.md) §4 step 5.
    - ✅ **The router and edge calls.** The converge's spelling is canonical for the IoT DoT-bypass pair · `trusted-ha`
      is DERIVED and the Pi is a member · the NAT reconcile deletes what its own `data:` does not list, so both writers
      must list the row (the live apply is owed in [todo.md](todo.md) HD-1142) · `tailscale-sidecar_api` is rotated and
      the leaked key is expired · `metabase` is revived on oldsrv and the VPS copy is gone →
      [docs/network-ops.md](docs/network-ops.md) §Rsc authoring conventions rule 11 ·
      [docs/network-vlans.md](docs/network-vlans.md) §Proving the KNX reply rule ·
      [docs/deployment-secrets.md](docs/deployment-secrets.md) · [docs/network-vpn.md](docs/network-vpn.md)
      §Tailnet-exposed services · [docs/services.md](docs/services.md) · [docs/services-admin.md](docs/services-admin.md) §Metabase.
    - ⏳ The owner still runs the **secret rotations** (`HD-1170` · `HD-1171` · `HD-1150` · `HD-1181`, the last of them
      this seat's own pi transcript store, which keeps `check_secret_leak.py` red on the pi-dev seat and nowhere else
      until it is rotated). The `oldsrv` console look (`HD-1175`) ran when the box came back.

    - **Register the heading gate, price it, or leave it a tool.** `scripts/gate/check_doc_headings.py` exists and carries
      `--self-test`, and it IS registered now, alongside `check_doc_path_refs.py`: `--list` prints both its run and its
      `--self-test`, and the anchor half runs against a frozen baseline (`gate/doc_headings_baseline.txt`),
      so growth is what reddens a commit — re-derive the count by running it, never by quoting it. The size of
      the debt is the last line of its own run, and the same tool copied into a worktree checked out at an earlier
      revision shows which way the trend moves; the three lawful answers are register it with a frozen baseline and
      refuse growth, run a clearing campaign, or keep it a tool and say so in the index. Ruled 2026-10-13: option (a) — registered with the frozen baseline, growth refused; no clearing
      campaign is owed. (Owning index: [scripts/README.md](scripts/README.md) §Validation gate)
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

    Standing on top of those, and not another decision: **the twins baseline moved again at the 2026-10-21
    seat-python commit** — one side of the `$(uname -s 2>/dev/null)` group left the plane COMPOSER for the resolver
    that now runs it, which is the MOVE case the file records, and the population grew (2,612 → 2,668, re-derive with
    `--show-baseline`); a baseline still never ages past one wave.
    `scripts/gate/twin_baseline.txt` pins the revision the population is read from, and the run compares how far `HEAD`
    has moved from it against its own staleness constant, so re-derive the distance with
    `git rev-list --count $(awk '/^baseline_rev/{print $2}' scripts/gate/twin_baseline.txt)..HEAD` and publish the three
    values with `python3 scripts/gate/check_string_twins.py --show-baseline` in the commit that moves the baseline. That
    act is now safe to perform anywhere in a wave, because HD-1118 pinned the gate's own positive control to a
    population of its own (`CONTROL_BASE_REV`) and made the divergent-family witness a fixture — before that, moving
    `baseline_rev` past `8b28edd3` made case (v) measure backwards, which is why an earlier attempt was backed out.

    - ⏳ **Prove the compose-boot verdict idempotent with one real converge.** The new
      `/usr/local/sbin/docker-compose-ensure` and the rewritten `docker-compose@.service` reached vps/oldsrv/pi/spark
      through task-level template runs, so one `--tags docker_services` pass must return those two legs
      `ok`/unchanged and every service's new reachability check green — the leg that proves IaC and the hosts agree.
      (Owning: [docs/deployment-compose.md](docs/deployment-compose.md) §Boot auto-start (docker-compose@))

15. ⏳ **The gate's own speed on a Windows seat — and, since 2026-10-20, its trustworthiness there** — **HD-1135** landed the fork diet (gate 134 s → 78 s measured
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
    that seat, so the 398 ms-per-pin numbers still stand for it. **And that seat cannot be trusted to grade itself
    (**HD-1177**)**: measured in the primary checkout, `check_secret_leak.py` dies in a cp1252 `UnicodeDecodeError`
    inside a subprocess reader thread (rc 1 direct, rc 127 inside the gate, where no `~/ansible-venv` exists),
    `check_self_converge_guard.py`'s `check_mode` fixture calls all five role dirs `INVISIBLE` here while the same
    commit is green in WSL, and `check_doc_path_refs.py` reds on citations to paths `.gitignore` excludes — so two
    clones of one commit reach opposite verdicts, and HD-1117's `POOL DIAGNOSTIC` cannot say so on that seat because
    `-v load=` is a gawk fatal. ⏳ **in order from there:** the gawk rename (one variable, prove the block prints on a
    forced red run), the UTF-8 pin in `check_secret_leak.py`, then the fix-or-`SKIP` call on the converge-guard
    fixture and the ledger-or-rescope call on the generated-path citations. The seat's DNS plane settled the same day
    (**HD-1176** — the mechanism is in place on the seat: internal names routed to the MagicDNS loop per-link and
    re-asserted by a timer, the Windows adapter's registration read back as effective, the WSL seat's drifted
    `models.json` re-rendered), and the row stays **open** for what it still owes: that the four seat artifacts have
    **no repo owner** (the `wsl` seat plane in
    `scripts/harness/`), the headscale-side call on MagicDNS `SERVFAIL`ing most of `zone_kogler_si`, and the
    suspend/resume + away-from-home re-measure. Record: [scripts/README.md](scripts/README.md)
    `validate-all.sh` + `sync-skills.sh` rows · [docs/network-dns.md](docs/network-dns.md) §Host-side resolver.

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
call · **the docker-family apply landed on `pi`**, which was the last one owed (`vps` and `spark` landed
earlier, so no daemon restart is owed on any host now) — the shape stays the rule for the next pin bump:
one host at a time, detached, `--check` first, never behind a timeout, ⛔ not overnight, and the §1.10
survivor restart after it, because a live-restore survivor keeps the OLD `docker.sock` inode. `oldsrv`
owes no apply and `nas` runs
no docker role at all. An apply lifts the hold for exactly the suite names it moves and re-holds them in the same play,
so there is no manual `apt-mark` dance and no `--allow-change-held-packages`; when a host does read `differ`,
that is the gap being reported, not a false positive. Six more parks carry exactly one blocked action
each, all measured into their rows on 2026-10-19 — **⚠ read this list with the 2026-10-20 owner round applied: the
`HD-1107`, `HD-1106`, `HD-1103`-retention, `HD-1140`, `HD-357`, `HD-443` and `HD-1110` entries below are
RULED and their remaining work is AI work, so the owner act they describe no longer exists** (the ruling and the ordered
act are in the rows and in §14); what is genuinely owner-blocked in this paragraph is `HD-1122`, `HD-1088`, `HD-1091`,
`HD-1093`, `HD-1164`, `HD-1143`, `HD-1152`, `HD-1160`'s router window and the Pi-visit bundle. ⚠ **`oldsrv` is back and
its parked acts are un-parked**, with one exception that is not about presence: a lockout-class role (`network`,
`storage`, `wireguard`, `tailscale-node`, `cockpit`) applied to `oldsrv` is refused by the self-converge guard while
`oldsrv` is itself the controller, so those legs still need another control node or an in-band console. **HD-1160** — the ruling landed and the retag
with it, so what is left is one owner-present **router window** for the converge template's twin of the retagged
`#`-comment (`IaC/router/templates/rb4011_converge.rsc.j2`; a `#`-line IS rendered output — HD-1167's class, global
router slot, never `--diff`, never from a docs lane). Nothing else in that row is owed and **no converge is behind it**
(⛔ shipping a resolver instance, a listener address or a `:53` dst-nat target to buy per-policy filtering stays refused
permanently) ·
**HD-1122** — flip `ai_tier_metrics_publish: true` and converge **oldsrv** `--tags docker_services,monitoring`: the
flag, the `127.0.0.1` publish and the `prometheus.scrape "llama_cpp"` leg are ONE change that recreates two serving
containers · **HD-1088** — ONE act: register oldsrv's public key on the live Box in the storage provider's console
(port 23 is key-auth-only, and `Hertzner-SB-Data` holds only a CIFS/WebDAV password, so there is no other way in).
The two seed halves are **already done on oldsrv and verified there** — `/root/.ssh/livebox_push` `0600`, its public
half re-derived from the private key with `ssh-keygen -yf` and diffed against the stored `.pub`, and
`/etc/storage/box_known_hosts` `0600` carrying the Box's three host keys for the `:23` endpoint — so no seed step is
owed here. Then set `storage_push_music.enabled: true`, converge `--tags storage --limit oldsrv.kogler.si`,
`systemctl start push-music.service` once · **HD-1091** — rotate `lidarr_api` in an owner window: it is
`NOT_AUTO_ROTATABLE`, the order is forced (mint → write Lidarr's own `config.xml` → restart lidarr → re-render
soularr's `config.ini` → re-point Seerr), and missing a step 401s every consumer while the vault looks correct; blast
radius lidarr/soularr/seerr. Then the one-album proof, which waits on a peer finishing a transfer inside the poll
window rather than on an act here. Seeding the slskd API key is **done** — soularr is `enabled: true` and both ends
already hash to the same credential — so do not re-open that half · **HD-1107** — the parked `systemctl stop storage-syncoid.service` on `nas` was RUN
and the wedged tree died, but the authorised re-fire failed a different way: **66 snapshots on the destination are newer
than the send base and every one is a sanoid `@autosnap_*` the replica takes for itself** (`use_template = data` on
`bulk/data/*`), and an incremental `-F` receive cannot land on a target holding snapshots the stream does not contain —
`cannot restore to bulk/data/services@autosnap_2026-10-08_21:05:07_monthly: destination already exists`, twice,
identically. So either the replica's own post-base rollback history is destroyed (that snapshot plus 65 more) or the
replica datasets come out of `sanoid.conf.j2`'s `data` template and the 66 age out; ⛔ neither is an overnight act, and
pruning stays blocked meanwhile because sanoid's `iszfsbusy()` greps the process table for a `zfs send`/`zfs receive`
line that only the wedged pipeline's **shell wrapper** still carries ·
**HD-1106** — the prune itself, one `docker volume rm` per row the table marks `prune`, and a named volume or bind for
the two `onlyoffice-docs` paths · **HD-1164** — an `intel_iommu=off` experiment plus a memory test on the HP Gen8 in a
window the owner schedules (the box holds the NFS media export, the Kopia agent and HD-1107's stuck `zfs receive`, so
nobody reboots it overnight); the restore line is `systemctl start alloy` on `nas`, and the unit stays stopped until
then · **HD-1143** — exactly one KNX `GroupValueRead` from the Pi with the reverse rule's counters read either side,
which needs a privileged act (`docker exec` into the HA container, or an integration reload) · **HD-1152** — the first
REAL `playbooks/dns-seed.yml` apply per instance, and only after its two defects are repaired, because `--check` skips
the whole Technitium block and can never name candidates · **HD-1103 + HD-1167** — one owner-window Pi visit carrying
the boot that makes the fstab `mode=` true on the running mount, the UNTAGGED converge that applies `ai_diag`'s derived
smartd mask, and the one-time re-render of `pi-eth0.nmconnection` (⛔ the `nm-resolver` applies and HD-418's reconcile
are DONE on both hosts — do not re-run them; on a keyfile host the write leg is `nm-pi`) ·
**HD-443** — either a host whose journal actually covers the claimed interval, or the owner's ruling that the Pi's
volatile journal cannot prove a 30-day silence and the `admin` revoke proceeds on nine old acceptances plus the
neutralized state · **HD-1110** — the OAuth-vs-`api_key` call on the seat's `pi_auth` providers, which a `--push` must
not settle by rewriting a working login.

**✅ 2026-10-20 owner round — what stopped being an owner act.** The rulings live in the rows and in [todo-table.md](todo-table.md) §A1, and this file restates none of them.
> **What §D of the human table carries that the parked list above does not**, so the two lists are not mistaken for each
> other: §D is everything genuinely left; the parked list above is only the part of it with an authored act queued behind the
> owner. The rest is owner eyes and hands with nothing authored waiting — the one visual pass over the boards
> (**HD-316 · 315 · 343 · 377 · 319**), the browser-login seats still owed (**HD-147** with **HD-141**'s tail), the
> physical windows (**HD-06 · 288 · 194 · 34 · 191**, and the two drill-time decisions **HD-230 · HD-207**), the
> on-site matrix and `Mgmt99` tail (**HD-397**), the JupyterLab LAN edge deliberately untouched on instruction
> (**HD-366**), the Immich family-library seat question (**HD-457**), the enrolment sessions (**HD-412**), the WoL
> ruling (**HD-454**), the Jellyfin-login eyeball (**HD-353**) and the `opensubtitles_login` fix (**HD-1096**). They are
> parked too, but with no half-written change behind them — so a lane reading only this file should not go looking for
> an authored act to flip, and a lane reading only §D should not assume the acts above are already written.

**Unbriefed open rows** — no session launches from them; they live in [todo.md](todo.md) and every view, and the full
list is **derived** in [todo-table.md](todo-table.md) §B0. Two ids must not be lost: **HD-357** (the launchpad tiles —
the family-surface brief was retired and no successor took the row; it wants a promoting decision, not a re-scope) and
**HD-1100** (the PG legs — owner-paced, one cluster per window, spanning every host so no one domain brief owns it).
One thing carries neither a row nor a brief, so it is named rather than re-derived: **the ghost CCU reservations** stay
parked — their two entries are commented out in `network_static_hosts`
(`IaC/ansible/group_vars/all/main.yml`), not deleted, and the generated address doc no longer publishes them.
