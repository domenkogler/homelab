> **Role:** entry point for the next session — a **lean handoff**, a pointer index and nothing else. Every item's authority
> is its [todo.md](todo.md) row; permanent knowledge is the owning doc ([docs/index.md](docs/index.md) map); the permanent
> process contract (working rules, orchestrator mode O1–O11, launch, merge/cleanup) is
> [docs/orchestration.md](docs/orchestration.md) §4; the planning view for the human is [todo-table.md](todo-table.md).
> **This file states current facts only** — no session accounts, no landing stories, no event dates: git is the only
> changelog (CONVENTIONS §6). A `prompt-*.md` brief carries a lane's contract and order of work; it never restates a row.
> **Briefs are named for a host + domain, never for an HD** (CONVENTIONS §6), so every pointer below is a domain brief and
> the row stays the authority for what is owed.
> **Linked from:** [README.md](README.md) §0/§2 · [CONVENTIONS.md](CONVENTIONS.md) §4/§6 · [todo.md](todo.md) ·
> [todo-table.md](todo-table.md) · [docs/orchestration.md](docs/orchestration.md)

---

## 1. Environment

**Seats and stations.** Three seats run the harness, and two of them are merge stations.

| seat | what it is | what it proves |
|---|---|---|
| `oldsrv` | the pi-dev seat; its clone `domen@oldsrv:~/source/homelab` is the **merge station** — merges land there, `scripts/validate-all.sh` runs there, and `git worktree list` there is the fleet's live set ([docs/harness-pi-engines.md](docs/harness-pi-engines.md)) | a full Debian verdict |
| `wsl` (the laptop's WSL Debian clone) | the **runner station** for externally-served runs: off-box for every converge target, never the engine host, owner of no converge slot ([todo-table.md](todo-table.md) §C rule 9; state: [docs/harness-pi-seat-identity.md](docs/harness-pi-seat-identity.md) §5a; the legs only that box may drive: [prompt-wsl.md](prompt-wsl.md) §2) | a full Debian verdict |
| `win11` (Git-Bash) | an owner/cleanup seat, and a merge station too | `PARTIAL` by construction — see the grading rule below |

Re-derive a seat's `ok=`/`problems=` count **on that seat**, never copy it from a handoff; derive rescue refs with
`git for-each-ref "refs/*/rescue/*"`.

**The delegation-plane check — run it BEFORE routing any lane, on the seat you are on**: launch ONE `async: true` child
and require it to **yield a child session file**; no `--check` substitutes for it, and a pass certifies only the seat it
ran on. All three seats are licensed, so lanes run `async: true` everywhere. Where a seat has not passed, its lanes run
**foreground-sequential, one at a time** — a stated DEVIATION from O11 that ends seat by seat as that seat's own launch
passes, never a new rule, and never to be written into [docs/orchestration.md](docs/orchestration.md) or a brief as the
contract. ⛔ Never by npm-installing chord under a managed seat tree. Mechanism and the per-seat state:
[docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1.

**Grade from a Debian clone, not the Win11 shell** — a Win11 `OK` is a *partial* result, never "the gate" (**HD-1202**;
what that seat proves and what it names as unproven is [docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1). Three
things from that seat bind a probe: MSYS `grep` misses the CR of a CRLF pair (`grep -U` is mandatory in encoding guards,
and the same CR reaches a bash comparison through a pipe), `git` lives in `/mingw64/bin` not `/usr/bin`, and a case that
cannot run there prints SKIP, not a verdict — the named SKIPs are tmux, the font plane, `ansible-playbook`, `rsync` and
the symlink-requiring venv arms.

**Push after you merge** — the station that merged is the station that pushes; an unpushed `main` is one disk between the
work and the fleet. A `remote: fatal error in commit_refs` reject is GitHub-side: re-prove the ACL with
`git push --dry-run`, then retry, and never conclude the commit is lost
([docs/orchestration.md](docs/orchestration.md) §4 step 5).

**Git identity and the vault legs.** Signing is retired — commit plainly, ⛔ never `git commit -s` (it adds a
`Signed-off-by` trailer, which signs nothing), and `git log -1 --format='%G?'` → `N` is the expected value.
The Win11 seat signs and pushes without a 1Password window once
`bash scripts/git/git-bootstrap-win11.sh --git-identity` has run (`--check` shows the route, `--1password` opts back);
its **vault** legs are modal-free too and address items **by ID** (`scripts/lib/vault-env.sh --check`, `--map <vault>`) —
a NAME-addressed `op item get` costs 3 of the ACCOUNT's 1000 requests/24 h where the ID form costs 1, so ask
`op service-account ratelimit` before chasing transport ([docs/1password.md](docs/1password.md) §What a gate run costs
the vault). The two `.env.op` files reference items and hold no values, so they are TRACKED and a clone loses nothing
([docs/deployment-secrets.md](docs/deployment-secrets.md) §Secret Naming Convention). **Away from the LAN** the two home
targets move to the `-vps` jump aliases for the token legs (`RESEAT_TARGETS="wsl oldsrv-domen-vps vps oldsrv-vps"`, and
`HOLDERS_TARGETS="…"` for the holder sweep), because the plain home aliases time out off-network and print `UNREACHABLE`.
⚠ **`op daemon stop` is not a verb** on this CLI family — `op daemon <arg>` prints the daemon help and exits 0 — so a
daemon that has to be restarted is `kill`ed as its owner and respawns on the next `op` call with that caller's value.
The seat file map and the one vault item left in this area (`GitHub auth`, the transport key):
[docs/deployment-secrets.md](docs/deployment-secrets.md) §What actually raises a 1Password prompt and
[docs/1password.md](docs/1password.md) §GitHub signing + auth keys.

**Secrets:** 1Password `Homelab-ansible` `item.field` only, `>-` for YAML renders, and never a value printed anywhere —
lengths, prefixes, item ids and hashes only ([docs/1password.md](docs/1password.md)). Multi-line bash heredocs with
backslashes/backticks get mangled through `bash -c`: write the body to a temp file and run it.

**Reachability is settled — read the one SSOT, do not re-derive it:**
[network-vpn.md](docs/network-vpn.md) §Reaching LAN nodes when away (the measured matrix + traps) and §The laptop alias
contract (the only alias table; it governs BOTH `~/.ssh/config` files). In one line: behind-NAT hosts
(`pi`/`nas`/`oldsrv`/`spark`) are reached over the VPS jump onto their **Home leg**; the **Mgmt plane (VLAN 99) is
same-site only** (`router`/`switch`/`ap-*`/`pi99`/`oldsrv99`/`nas99` — never a `ProxyJump`); `ssh oldsrv` is the Home
address. `python3`/bash/LF/UTF-8 no-BOM everywhere (`.gitattributes` pins `eol=lf`, so a checkout is LF on Windows too).

**Docs hygiene:** [CONVENTIONS.md](CONVENTIONS.md) §8.6 (`sensitivity:` + the egress rule) and §8.3 (open questions are
`Options` sections keyed `OQ-<n>`). A size-ratchet growth red means the station owes `--reseal`. Open: **HD-1197**
(the launch-time read-list check, `scripts/harness/`).

## 2. Next tasks (the rows are the authority; this is only the ranked pointer list)

> **Dispatch, for a session running as the orchestrator.** Delegate the work instead of performing it (O10): the parent
> launches children, reads evidence, merges, runs `validate-all.sh` and owns acceptance — it does not investigate the tree
> to decide what to delegate. **≤2 children live at a time**, `async: true`, this session's own model, **2 h per child**,
> and a minutes-long silence is a compaction pause rather than a stall (O11; the numbers are in
> [`pi-agent/settings-ssot.json`](pi-agent/settings-ssot.json), held by [`scripts/gate/check_subagent_contract.py`](scripts/gate/check_subagent_contract.py)).
>
> **Read `echo $PI_PROVIDER` before routing.** On a spark-served seat the spark engine brief and every timed/engine leg
> are excluded **for the whole run**, for children as well as the parent (todo-table.md §C rule 2): no bench, no profile
> flip, no deliberate engine recycle. The one door that stays open is the owner's narrowing of that rule — such a session
> MAY converge `spark` when the change provably cannot touch the inference engine (`--tags monitoring`, the `spark-dcgm`
> sidecar, file-provider route edits, `--tags spark,watchdog`), provided it records `docker inspect … vllm-qwen-spark`
> (id + `StartedAt` + `RestartCount`) before and after and shows `llm.kogler.si` still answers 200. Anything that recreates
> `spark-ai`, any deliberate engine recycle, and every bench stay outside. A spark-served seat may build and probe but
> **must stop at the dial** — a model served by the engine cannot hold the one lever that stops it.
> `bash scripts/harness/seat-llm-path.sh --check` says which path the inference lane travels (`path=lan` = seat →
> inference host, `path=edge` = through the tailnet edge); read it together with `$PI_PROVIDER`, because the session
> converges things over that path and a leg that restarts the edge or the host the lane rides ends the run that launched
> it ([docs/orchestration.md](docs/orchestration.md) §3 item 9).
>
> **Read the seat too, not only the model.** A lockout-class leg (`network`, `storage`, `wireguard`, `tailscale-node`,
> `cockpit`) is gated by **which box drives** — the self-converge guard fires when the target is the controller — and that
> has nothing to do with which model serves the session; the two axes are stated separately in
> [docs/orchestration.md](docs/orchestration.md) §4. Which rows are AI-doable with no owner step in front is the `Who`
> column of [todo-table.md](todo-table.md) §B/§B9, never this list.

**Seat brief (not a wave):** [prompt-wsl.md](prompt-wsl.md) — the WSL Debian runner station: its §0
pre-flight (this box's own gate green before you edit — re-derive the count with `--list | wc -l` and read the SKIPs by
name), the legs only that box may drive (§2), what a spark-served session must not start there (§3), and the
rehearse-everything rule for owner windows (§4). It claims **legs, not rows**, so it never takes a row out of the brief
that owns it.

**Model brief (not a seat):** [prompt-external.md](prompt-external.md) — work gated by *which model serves the session*,
not by the box: the Rule-0 legs a spark-served session may not run (**HD-1169 · 1157 · 1156 · 1117** are the
whole-corpus rows a locally-served 262k context cannot hold), and the timed spark legs that belong to one bench window.

**The gate's two faces (a seat fact, not a brief):** the win11 seat grades the same registry in two faces — `face tree`
legs in a commit-stamped snapshot on the engine's ext4, moved **with git** because history is a dependency of four of
them, and `face seat` legs native on win11 where `~/.pi` and the vault can be seen; a leg whose subject spans both is
`face joined` and runs native, because in a snapshot it proves neither side. The face is a word at the registration line
beside the profile marks, so there is still **ONE item list**, and `--face tree|seat|both|auto` says which half a run
grades — an un-flagged run grades all of it, exactly as before. Facts, the driver and both re-derive commands are in
[docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1 and
[`scripts/harness/gate-snapshot.sh`](scripts/harness/gate-snapshot.sh). A leg declares the engine tools it shells out to
and an absent one answers `CANNOT RUN` (rc 2) rather than a green, with
[`scripts/gate/check-leg-contract.sh`](scripts/gate/check-leg-contract.sh) holding the crossing conjunction and
[`scripts/gate/leg_contract_boundaries.txt`](scripts/gate/leg_contract_boundaries.txt) reddening a stale accepted
boundary. The parity harness ([`scripts/bench/win/gate-parity.sh`](scripts/bench/win/gate-parity.sh)) proves its own
crossing: a run whose engine side never crossed answers rc 2. Attach the run's own `ms/exec` line to every timing and read
older figures against the host-cost note in that doc.

**MCP-config brief:** [prompt-mcp.md](prompt-mcp.md) — the seat's `~/.pi/agent/mcp.json`, the one harness artifact no
plane reads: measure what each seat actually holds, build the plane shape the registry already expects, and put the
fleet-vs-`localhost` question to the owner instead of shipping both entries. It carries **HD-1238**'s open half; the
row's `lsp-binaries` and win11-carrier legs are state in the row and in
[docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1 — do not re-open them. ⛔ a `url` entry is connected, never
launched, so the drift read is the port and not the file.

**Window brief (not a wave):** [prompt-update.md](prompt-update.md) — the fleet pin bump + host-package window: phases
0–8 driven from the runner station, the secret rotations scheduled into it, no rows carried, and it dies with the window.

**Leak-debt brief:** [prompt-secrets.md](prompt-secrets.md) — the four leak tools (the tool-result masker, the debt
register that answers *did it rotate*, the containment tool, the pre-push gate), the register read that generates the
list, and the rotations that close a capture leak. ⛔ no lane rotates a vault item and no transcript is deleted to make a
check green. ⚠ Read `NOT_AUTO_ROTATABLE` in [`scripts/secrets/provision-secrets.py`](scripts/secrets/provision-secrets.py)
as the auto-rotation guard it is: it means *a vault-only `--rotate` would leave the far end on the old value*, so those
items are rotated by AI work — far end first, then the vault write, then the converge; only the no-machine-channel and
human-vault ones (`op_api`'s console re-issue) or the ones outside our scope (`pppoe_login`, the Soulseek network account)
wait for a person. Containment is for that last set alone and lowers the copy count rather than closing anything; the
no-path ruling is held equal by two surfaces — the register's `path:` column and `NOT_ROTATABLE`. Who holds a value is
mechanical: `scripts/secrets/check-token-holders.sh` answers it across the plane in one vault read, digests only, and
names the restart each superseded holder owes.

**The dependency ladder — the order these pointers actually run in.** The list below ranks by what unblocks the most; a
rank is not an order. Only step 3 needs an external model, and it is the owner's call stated in-session (README §3),
never an agent's fallback:

| # | step | from | why it sits there |
|---|---|---|---|
| 0 | the seat pre-flight + that seat's delegation plane — [prompt-wsl.md](prompt-wsl.md) §0 | the runner station | every converge in the window is driven **off-box** from there; an unverified delegation plane makes the run foreground-sequential |
| 1 | the in-repo leak tools (**HD-1219 → HD-1216 → HD-1218**, the order is a dependency) + the whole-corpus gates — [prompt-secrets.md](prompt-secrets.md) §3, [prompt-external.md](prompt-external.md) | any seat, no converge host | they stop the *next* run-capture debt before the next window creates one. What is left is **per-seat legs run FROM those seats** — a read here certifies nothing there — and **HD-1228**'s per-seat re-derive, whose list is the **union** of the seat reads |
| 2 | the rotations a ledger re-derive cannot go past — the residue of [prompt-update.md](prompt-update.md) Phase 3, driven from the briefs that own each item | one converge per host | Phase 7 is ONE commit and it drops only the lines whose **far end** moved |
| 3 | **[prompt-update.md](prompt-update.md) Phase 6 — spark, last and solo** (OTA → pin converge → the third tailnet node → the engine-key rotation → HD-1206's flips) | an externally-served session on the station, owner present | the only Rule-0-gated step in the fleet; its legs are the card's order + HD-1206's row order, and its boot windows are ~20 min each |
| 4 | Phase 7 (re-derive the leak ledger) → Phase 8 (the docs pass, then `prompt-update.md` dies) | the station | that one commit is what turns `check_secret_leak.py` green again |

⛔ Never inside that window: the router/switch items (ruling N3, global slot), the `llm.kogler.si` answer flip, the five
`pin-major-*.md` majors, and any spark hunk of the observability lane **inside a bench window**.

Ranked by what unblocks the most. Each line is the item + **the domain brief that carries its order of work** — the brief,
not this list, holds the steps, the file ownership and the converge host. Waves, pairing and the host/slot rule are
[docs/orchestration.md](docs/orchestration.md) §4 (O1–O11); the row→brief index is [todo-table.md](todo-table.md) §B0.

1. ⏳ **The spark engine lane** — its legs are **scripted**, so an externally-served session runs them: `hd469-baseline.sh`
   (**HD-469** — only a sustained under-load `clocks.sm` trace proves the regime), `gate6-couple.sh` (**HD-489** — the
   battery at `max_tokens 16,384` AND the B1 baseline in one act; exit 4 breaks a broken pairing, `accuracy-gate.sh`'s
   default stays 1024), `usable-sampler.sh` (**HD-494** — ruled: the delta picks the CRIT-vs-WARN floor, so the number is
   taken before anything lands in IaC, and the run rides the pin window's spark phase), `needle-window.sh` (**HD-376**),
   `text-only-preflight.sh` (**HD-400** — a read, legal from any seat; the profile stays NOT applied). Run order, exit
   codes and rollback: [spark/reports/external-window-card.md](spark/reports/external-window-card.md). **HD-473** waits on
   the ref choice and the re-cert it costs, not on upstream; **HD-380** needs no external model — it is a `/metrics` read
   plus a standing watch on the growth curve. ⛔ Gates 7, B10's 6/8/9 and B9 · B5 · B8 are closed — do not re-run.
   **HD-1206**: the v32 lineage is built, pinned and fp8-capable but `certified: false`, so what remains is the owner
   window in the row's order (the runtime dispatch check → `fast-v32-bf16` as the base-lineage control → `fast8` fp8 KV),
   each leg detached and from a seat spark does not serve; rollback is one `-e spark_llm_profile=fast` plus a detached
   converge with `spark-rollback:fast` held locally and archived on the NAS. ⛔ Never retag `qwen38-flash-dgx:iter6c|iter6d`;
   never prune the build cache; read the artifact markers rather than the CPU self-test gates, whose verdict is not about
   the patch set.
   → [prompt-spark-llm.md](prompt-spark-llm.md) (one spark slot; HD-473 + the capacity-axis and radix rows ride it)
2. ⏳ **The transport / answer plane** — **HD-435**: the `ha` `tailnet: dual` publish is live and inert; the answer half is
   settled by the client's code, which answers ONE A record, so what is owed is a decision — close on the per-node-names
   story or drop `ha` back to `node` — plus the owner-present fall-over drill. ⛔ Keeping `dual` is the shape that ships an
   order nothing declares. **HD-477** — make the resolver actually float with the VIP; the row carries the three gates.
   **HD-487** — config-manager truth is DECLARED per host in `host_vars/<host>.yml`, held by
   [`scripts/gate/check_net_manager.py`](scripts/gate/check_net_manager.py) and read with
   `scripts/ansible/probe-net-manager.sh`; the one act owed is the **VPS** delete of the dead
   `/etc/systemd/network/20-eno1.netdev` (parked below). **HD-480 · 481 · 482 · 483** — the Pi instances are seeded; the VPS
   and oldsrv instances pick it up in their own owner-present slots. ⛔ never buy per-policy filtering with a resolver
   instance, a listener address or a `:53` dst-nat target — ONE tier-wide upstream is the ruling (quote the mechanism from
   the row, never a letter); device-level Kids/IoT filtering is a device-side act. **HD-1160** is not AI work and no
   converge is owed; its one item is the converge template's twin of the retagged `#`-comment in
   `IaC/router/templates/rb4011_converge.rsc.j2`, which is RENDERED output, so it moves only inside an **owner-present
   router window** (global slot, ⛔ never `--diff`). **HD-1152** (unbriefed) — the seed's prune leg has never run: its two
   defects (no query string on the read; a Jinja list comprehension in the candidate build) are the AI half, and
   `--check` can never name candidates, so the first real apply is owner-present.
   → [prompt-dns-transport.md](prompt-dns-transport.md)
3. ⏳ **Silent-failure alerting** — **HD-450**'s collector legs are live and read back per host; the row's one re-point is
   the delivery leg under **HD-1108**, whose delivery proof is real traffic already read back from the room — the parked
   half is the deliberate canary (an owner yes: firing it pages Signal) and **demoting Signal**, which stays in the path
   and stops the workflow before the Matrix node if it fails. The **Alloy fleet pin** is settled state
   ([docs/observability.md](docs/observability.md) §The Alloy pin; ⛔ never `--allow-downgrades`).
   **LLM token accounting HD-1120 · 1121 · 1122** — **HD-1120** is parked in full (every step needs a `traefik-spark`
   restart or a spark-slot converge); attribution comes from the **edge access log** (spec + the XFF trap:
   [docs/observability.md](docs/observability.md) §LLM token accounting). **HD-1121** owes the gateway's `prometheus`
   callback, the auth form and the VPS loopback publish — a **gateway** recreate, not a monitoring one. **HD-1122**'s
   engine telemetry is live on both legs; what remains is the board render, which is HD-377's owner sign-off.
   ⚠ **A rule that is authored is not a rule that is loaded** — prove it with `GET /api/v1/provisioning/alert-rules`,
   never the repo file. ⚠ **Retiring a probe target can be the cheaper half of a fix: check what the rule was watching.**
   The `ha-unreachable` target and rule are retired, so **HA liveness has no firing rule** until the gated `ha_exporter`
   job — **HD-1182**, whose premise the box falsified: HA answers behind the VIP, so the chain starts with **HD-14**
   enabling the exporter on the HA instance, then `alloy_ha_exporter`, then the oldsrv `--tags monitoring` leg, then the
   rule. ⛔ The blind-host expected set is the inventory's `[monitoring]` group and
   `check_host_reporting.py --check` reads against it. The boot-catch-up unit's paging half — putting it on
   `monitoring_hygiene_units` — is this lane's rule; the fix itself is item 6's. A still-firing alert re-sends at most every
   **24 h** (`repeat_interval` in the notification policy `roles/monitoring` renders; the first send is not delayed).
   → [prompt-observability-alerting.md](prompt-observability-alerting.md)
4. ⏳ **The media / music ladder** — **HD-362**: what Lidarr is missing is APP state, not a secret — one indexer and one
   download-client entry, and the `path.repo` fix applied inside the ES container's `elasticsearch.yml` directly before TA
   goes back on. Aurral → Lidarr is a **browser** leg (the add is a click on a recommendation card; its URL+key are
   encrypted inside `aurral.db` and the API 404s on the obvious routes). ⛔ probe slskd with
   `docker exec slskd /slskd/slskd --envars`, never by grepping a rendered compose; the Soulseek **network** login is
   **not rotatable from a seat** — risk accepted, do not re-open. **HD-1091** is authored and **ARMED** (one vault item
   renders into both ends, so neither side can be armed alone); what it owes is one album crossed end-to-end, which waits
   on a peer finishing a transfer inside the poll window, and the `lidarr_api` rotation (`NOT_AUTO_ROTATABLE`, parked).
   **HD-1088** renders on oldsrv with its guards proven (⚠ `--max-delete` is a **CAP, not an abort** —
   [docs/storage.md](docs/storage.md) and the fixture [`scripts/testdata/rsync-max-delete/run.sh`](scripts/testdata/rsync-max-delete/run.sh));
   one owner action gates the end-to-end proof: register oldsrv's public key on the live Box (parked below).
   **HD-1092** is void as written; what remains is one credential-bearing leg on a second host
   (`smbclient //nas/domen -A creds`), parked. **HD-1172** is an oldsrv `arr-seed.yml` leg: make the declared root set in
   `roles/docker_services/defaults/main.yml` match the live roots. (**HD-1089**, the SABnzbd locality read, is in the
   unbriefed list below.) → [prompt-media-arrs.md](prompt-media-arrs.md)
5. ⏳ **Cockpit, the coding seats, grants** — **HD-361**'s authenticated pane in a browser per host (only
   `GET /cockpit/login` + Basic tells the truth from a CLI), **HD-465** = deploy the `cockpit-nas-ts` router then that
   browser load, **HD-442**'s value-identity half (hash the rendered `/etc/op/provision-token` against the vault's
   `ansible_provision_token`, lengths only, owner-present; read [docs/1password.md](docs/1password.md) §1 first and prove
   scope with the `op whoami` **Integration ID** — `op vault list` cannot tell the scopes apart), **HD-443**'s Pi `admin`
   revoke behind the order that keeps the door open (`ansible-admin` and `domen` proven first; ⛔ a raw journal grep for
   the phrase also matches the probe that greps for it — filter on `sshd-session[…]` / `-u ssh.service`), **HD-495**'s
   hand-planted `~/.ssh` keys (`--ssh-auth` raises them; ⛔ never re-add `git commit -s`), **HD-1126**'s Debian-seat
   assertion on the modal-free route (`scripts/git/` only), **HD-1227**'s one SSOT edit in
   [`pi-agent/tmux/tmux.conf`](pi-agent/tmux/tmux.conf) with the installer's load probe and canaries moved in the same
   change (⛔ parity is bought by taking, not adding — the Win11 host has no tmux setup and stays that way), **HD-1110**'s
   `api_key`-is-the-fleet-spelling drift read in `scripts/harness/pi-seat-sync.sh --check`, and **HD-1161**'s unpinned pi
   leg in `install-pi-wsl.sh`. Seat legs run **FROM their own seat**, oldsrv included
   ([docs/harness-pi-seat-identity.md](docs/harness-pi-seat-identity.md) §5a), and a plane command executes in the SEAT's
   shell ([docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1) — so pull the driver clone before blaming a seat.
   → [prompt-seat-cockpit-grants.md](prompt-seat-cockpit-grants.md)
6. ⏳ **Storage, backup, the DR story** — **HD-191**: the `bulk/data/*` replicas sit on the no-autosnap template; the
   invariant, the `zfs send -I` subtlety and the proof reads are [storage.md](docs/storage.md) §Snapshot & Replication, and
   the VPS-side client's shape is ruled and its roots priced ([backup.md](docs/backup.md) §VPS-side backup client) —
   ⛔ a hand-`zfs destroy` of replica snapshots stays out. **HD-1105**: the nas units' `--failed` read is 0; if the
   `zfs-share` red returns it arrived through `PartOf=nfs-server.service smb.service`, and the durable cure
   (`sharesmb=off` on the `bulk/migrate/**` remnants) is an unnominated property change on a 2.33 TB tree. **HD-1106**: the
   prune itself is owed — one `docker volume rm` per row the table marks `prune`. **HD-207 · HD-238** are the drill-time
   decisions. **HD-1174**: kopia's `repository connect server` echoes the URL it was handed, so the
   `kopia-server-internal_api` credential sits in plaintext in the agent's container log for the retention window — the
   rotate and the re-connect are ONE window, because `repository.config` caches the credential. **HD-1183** is an
   **oldsrv** `--tags storage` act run **off-box** (the self-converge guardrail refuses it FROM the host); its paging half
   is item 3's. → [prompt-storage-backup.md](prompt-storage-backup.md)
7. ⏳ **The Pi's own box** — **HD-418** is reconciled at both ends and owned in IaC (`roles/home_assistant/tasks/pi.yml`,
   tag **`hd418`**); the proof is BEHAVIOUR, not the YAML — the list HA enforces is the `.storage/http` object, so
   `grep -A6 trusted_proxies configuration.yaml` can neither prove nor fix a `400`. What it owes is the takeover-shaped
   request taken **from the oldsrv edge** and the XFF-present read through the `traefik-internal` middleware; the
   standby-shaped case has no subject while **HD-1109** stands. **HD-1109**: the standby is **UNDEPLOYED** — oldsrv runs no
   `home-assistant-standby` and no `keepalived`, and the render pins a tag that host does not hold. Probe the standby with
   `docker compose -f /opt/home-assistant-standby/docker-compose.yml ps`, NEVER `systemctl is-active keepalived` (its
   `inactive` is the correct read — the VRRP half is the container compose does not have), and probe on the host that owns
   the unit. **HD-1103**: both halves are owned in IaC and the smartd half is ruled (dropped from the Pi's health surface,
   declared `ai_diag_smartd_managed: false`, unit left exactly as found); what is left is one boot that makes the fstab
   `mode=0755` true on the mount — ⛔ never `mount -o remount`, which returns 0 and changes nothing. **HD-1167**: a
   `#`-line in a `.j2` is literal OUTPUT, so `Render Pi eth0 NetworkManager keyfile` can report `changed` while every
   functional line matches — and `changed` is what notifies `reload NetworkManager` on a DNS-tier box. First act is the
   stripped comparison both sides (`grep -v '^#'` the host file against the template's non-comment lines) and the same read
   on `spark`; the fix belongs in `roles/network`, never on the host; the one-time re-render is an owner-window act with
   **HD-1101**'s rollback standing by (that row's own debt is to re-read the `dns=` pair after that re-render).
   Plus **HD-04 · 434 · 438 · 439 · 319 · 1205 · 1127**. → [prompt-smart-home.md](prompt-smart-home.md)
8. ⏳ **Edge and identity** — **HD-147**'s browser-login tail, **HD-457** (the SSO seat owns the family library — ruled;
   what is left is the per-user/shared-album shape), **HD-458 · 459** (zipline, the published names), **HD-112** (Zipline
   seeding), and **HD-357**'s launchpad tiles. ⏸ **HD-47** stays an owner act: the external-room join is unscheduled;
   everything publishable is published. → [prompt-edge-identity.md](prompt-edge-identity.md)
9. ⏳ **The LiteLLM consumer chain** — one ordered pair left (**HD-384**): `litellm-engine_api` is minted and rendered into
   spark's accepted-key list, and the gateways may be pointed at it only **after** spark reboots with it, so step 2 is
   parked rather than slipped in. **HD-1178**: the oldsrv `embed` leg's next model is chosen by a bench, not a leaderboard
   — corpus, both gates and probe commands in [docs/services-ai-bench.md](docs/services-ai-bench.md) §3d; its first act is
   a `server-vulkan` pin bump that recreates the **reranker** leg, so ⛔ never inside a bench window and never from a
   spark-served session. Settled state lives in the owning docs, not here: thinking control
   ([docs/services-ai.md](docs/services-ai.md) §9d), the `/ui/login` deep link (§4c), voice
   ([docs/smart-home-voice.md](docs/smart-home-voice.md)), the plaintext-replication ruling
   ([docs/deployment-secrets.md](docs/deployment-secrets.md) §Runtime plaintext that leaves the vault), and n8n audited
   shut with no AI node ([docs/services-utilities.md](docs/services-utilities.md)). OQ-14 stays open on the code axis and
   is called at the memory plane's build, which HD-1178 rides. → [prompt-litellm-consumers.md](prompt-litellm-consumers.md)
10. ⏳ **The Win11 seat's serving legs** — **HD-474**: what is left are two owner hands — `probe-client` **PASS**, never SKIP,
    which needs the resident leg moved first (`lmstudio-llm.ps1 switch -Profile <name>`), and the call on Continue's tab path
    against its own 150–400 ms budget: cap the shipped prompt, or the leg stays out. The render drift check is a **repo leg**
    that seat answers unattended (`--vendor pi --host Domen_P14s --check`, route quoted beside the verdict; no token is
    installed here and the read crosses the WSL door, [docs/1password.md](docs/1password.md)). The laptop's local **agent** leg
    is retired and the brief claims no converge host, which is why it can run beside anything except a live pi-seat lane.
    → [prompt-win11.md](prompt-win11.md)
11. ⏳ **The `scripts/` tree and the seat legs it still owes** — the tree is `lib/ gate/ ansible/ secrets/ git/ harness/
    bench/ hardware/ testdata/` with `validate-all.sh` + `render_all.py` at the root, root resolution is structural, and
    `gate/check_script_layout.py` holds it from inside `validate-all.sh`. ⏳ The legs: one seat read, `pi-seat-sync.sh --check`
    run **FROM the `wsl` seat** (`oldsrv` and `win11` are read at the tip, and what blocks `wsl` is that clone's reconciliation
    with `main`, not a fast-forward); `install-pi-debian.sh --check` on a clean Debian seat — **PARKED**, no host in the fleet
    is a spare one. The tmux plane owes nothing: `install-tmux-conf.sh --check --strict` reads
    `SAME: byte-identical to the SSOT` and a tmux-less seat answers a named `SKIP`. **HD-1138** rides here:
    the away-case spelling in the scripts that shell out to bare `ssh <name>`, and the VS Code server-install leg it gates.
    **HD-1125** is the same file family: the bare-`ssh` token leg in `scripts/secrets/provision-vault.sh` and its two
    companions. ⚠ **The `check_mode: false` rule reads the line as this repo writes it** (`check_mode: false   # read-back`
    IS false) and classifies the site by its carrying task: a read-only module (`stat`/`slurp`/`find`/`get_state`/
    `*_facts`) or a `command`/`shell` declaring `changed_when: false` is a read-back, anything else is a WRITE and reddens
    naming `file:line` ([docs/deployment-ansible.md](docs/deployment-ansible.md) §Self-converge guardrail); ⛔ the wrong fix
    would be declaring cockpit `check_safe: false`, which would refuse the `--check` that same row exists to keep possible.
    **The child-lane contract is a rule with a ceiling and a gate** — O10/O11 in
    [docs/orchestration.md](docs/orchestration.md) §4 and `subagents.modelScope` in
    [`pi-agent/settings-ssot.json`](pi-agent/settings-ssot.json), held by
    [`scripts/gate/check_subagent_contract.py`](scripts/gate/check_subagent_contract.py).
    **The registry's prose is a rule with a checker** — [`gate/check_registry_prose.py`](scripts/gate/check_registry_prose.py)
    — so `scripts/README.md` is a facts-only map; print its count with `--show`, never a number typed into a handoff.
    The `harness` docs domain is REGISTERED: [prompt-scripts.md](prompt-scripts.md) §The taxonomy call and the hub
    [docs/harness.md](docs/harness.md). **The `lsp-binaries` plane is live on all three seats** — its reads, its owner
    legs, and the arms its mutation driver proves are [docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1 and row
    **HD-1238**; re-derive the proof on the engine with `python3 scripts/bench/win/lsp-mutation-proof.py`. The plane
    writes neither a Windows image nor a profile, so that seat's installs stay owner legs, not lane legs.
12. ⏳ **Owner-gated tails** (exact steps in the rows): **HD-377** the Grafana render re-do · **HD-1103 + HD-1167** one Pi
    visit — the boot that makes the fstab `mode=` true, and the one-time re-render of `pi-eth0.nmconnection` that notifies
    `reload NetworkManager` · **HD-06** the UPS drill · **HD-411** the tailnet pairing and the two elevated Windows acts · **HD-230 · HD-207** the
    decisions taken at the drill · **HD-1173** the live tails (the parked `dsh` + `pi-dev` harness IaC comes out, and
    `pi-dev.ts.kogler.si` leaves with the cockpit backend it was a second name on (HD-1240 retires it)) · **HD-1140**: the ledger owns the laptop's Home reservation, a
    `network_static_hosts` row plus a find-guarded `rb4011_*_delta` in the Pi's shape, so the apply rides an existing router
    window · **HD-1175** owes the root-only read of the previous boot's journal and `pstore`, which no rule reaches from a
    user session, and there is no out-of-band power path at all (**HD-454**'s posture; its WoL re-test is unrun) · **HD-1170**
    rotate `spark-llm_api`, an owner-only channel that closes with no repo change (`op_api` needs nothing further — see
    [docs/1password.md](docs/1password.md) §Where a token is installed) · **HD-1181** the vault values the seats' pi
    transcripts hold: the rotation is the owner's and it **differs per item**, so act from the row's per-item list, not from
    memory. ⚠ **The leak gate's exit code is not the finding**: pairs are carried in
    `scripts/gate/secret_leak_ledger.txt`, a ledgered hit prints `KNOWN-EXPOSED` and exits 0, a line another seat recorded
    prints `CARRIED` and closes nothing here, and the register is **per seat** — the list is the union of the seat reads. A
    rotated value stops being a finding; an unrotated one never does. **HD-1160** owes one owner-present router window
    (global slot) — ⛔ never from a docs lane, never `--diff`. ⏸ **HD-454 is ruled, not pending**: nothing is purchased and no
    out-of-band path is scheduled, so a switched-off `oldsrv` waits for presence, and the owner-side leg is a WoL re-test at
    a planned power-off.
13. ⏳ **Unbriefed, but not free** — no session launches from these; they live in [todo.md](todo.md) and every view, and the
    full list is derived in [todo-table.md](todo-table.md) §B0. The ids worth naming: **HD-1100** (the PG 16→18 legs —
    owner-paced, one cluster per window, spanning every host so no one domain brief owns it), **HD-1228** (re-derive the
    ledger's STALE block ON EACH SEAT and commit the union — the deletion commit is [prompt-update.md](prompt-update.md)
    Phase 7's), **HD-1083** (the edge routes still waiting on an owner
    eyeball), **HD-1176** (the WSL seat's artifacts, now with a `dns-route` plane, plus the headscale MagicDNS `SERVFAIL`
    question and the suspend/resume + away re-measure), and **HD-454 · 406 · 412** ([todo-table.md](todo-table.md) §D — hands and plain rows). Re-derive the count with the command in
    [todo-table.md](todo-table.md) §B0 rather than a number typed here.
14. **Decisions the fleet leaves open** (none has a domain brief; each is one call, and the evidence that makes it
    actionable is named with it). The gates named here are indexed in [scripts/README.md](scripts/README.md)
    §Validation gate, and every count a gate prints is re-derived by running it, never quoted.
    - ⛔ **Ruled — do not re-decide:** HD-1160 · 1106 · 1103 · 1140 · 357 · 443 · 1110 · 448/460 and the gate/router/edge
      calls: [todo-table.md](todo-table.md) §A1 and each row's `RULED` note.
    - ⏳ The owner runs the **secret rotations** (**HD-1170 · HD-1181**). HD-1170's history half is ruled — rotate, keep
      history as-is, no `git filter-repo`, no force-push, so the window is all that is left. Contract:
      [docs/deployment-ai-stack-secrets.md](docs/deployment-ai-stack-secrets.md).
    - ⛔ The heading gate is registered and priced — growth refused, no clearing campaign owed (index:
      [scripts/README.md](scripts/README.md) §Validation gate).
    - ⏳ **Retire the RB4011 deltas — ruled: yes, scheduled, not executed.** The retire procedure and its proof order are written
      into [network-ops.md](docs/network-ops.md); the window is owner-set (on-site, WinBox on the Home leg, state read back
      through the API), and until it runs the four `comment=` match keys stay untouched. ⚠ The `find where comment="…"`
      guards are why the ids cannot come out: editing one side makes a guard ADD a second rule or makes a `remove` stop
      matching. Proof order and the rule: [network-ops.md](docs/network-ops.md) §Rsc authoring conventions rule 11; owed
      legs: [todo.md](todo.md) **HD-1136**.
    - ⏳ **The compose-boot verdict:** one `--tags docker_services` pass must return `/usr/local/sbin/docker-compose-ensure`
      and the rewritten `docker-compose@.service` `ok`/unchanged, with every service's reachability check green — the leg
      that proves IaC and the hosts agree. Owning: [docs/deployment-compose.md](docs/deployment-compose.md) §Boot auto-start.

    Standing rule, not another decision: the twins baseline never ages past one wave — `scripts/gate/twin_baseline.txt`
    pins the revision the population is read from, and the run compares how far `HEAD` has moved against its own staleness
    constant. Re-derive the distance with
    `git rev-list --count $(awk '/^baseline_rev/{print $2}' scripts/gate/twin_baseline.txt)..HEAD` and publish the values
    with `python3 scripts/gate/check_string_twins.py --show-baseline` in the commit that moves the baseline. The act is safe
    anywhere in a wave, because the gate's positive control is pinned to a population of its own (`CONTROL_BASE_REV`).

15. ⏳ **Gate legs must ask the same question on the Win11 Git-Bash seat as on the Debian seats** — **HD-1202**.
    The face axis says where each leg runs and [docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1 carries the seat's
    verdict; `jq` is a bootstrap prereq on the Debian seats and a hand package on the Windows one
    (`deployment-manual.md` §0.2), and the pool bound — `wall` set by the heaviest leg once the pool is wider than the
    legs that can run at once — is in [`scripts/README.md`](scripts/README.md). What the row keeps is one unattributed
    site: a lane root that grows header-line-named files nobody staged. Grade from a Debian clone, report a Win11 `OK`
    as partial, and take the seat's own half with `bash scripts/validate-all.sh --face seat` at session close.
    **HD-1176**'s mechanism is in place on the WSL seat; what its row owes is the headscale-side call on MagicDNS
    `SERVFAIL`ing most of `zone_kogler_si` and the suspend/resume + away-from-home re-measure. The runner seat answers
    `path=lan` for the inference name, so its converge legs do not cross the tailnet edge;
    `scripts/harness/seat-llm-path-timer.sh` owns the `seat-llm-path.service` + `.timer` pair. Record:
    [scripts/README.md](scripts/README.md) `validate-all.sh` + `lib/python.sh` + `lib/repo_root.py` ·
    [docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1.

**Parked on an owner-present window** — authored work with exactly one blocked action in front of it, named with that
action so no lane re-derives it. An entry marked RULED is AI work, not an owner act — the rulings are the rows' and
[todo-table.md](todo-table.md) §A1's, and this file restates none.

| HD | the one blocked action | slot / host | 📋 brief |
|----|------------------------|-------------|----------|
| **HD-487** | the narrow `--tags netd` delete of `/etc/systemd/network/20-eno1.netdev` — only the role's removal leg reaches it | **VPS** | [prompt-dns-transport.md](prompt-dns-transport.md) |
| **HD-1152** | the first REAL `playbooks/dns-seed.yml` apply per instance, and only after its two defects are repaired — `--check` can never name candidates | vps · oldsrv · pi | [prompt-dns-transport.md](prompt-dns-transport.md) |
| **HD-1160** | render + `routeros-apply-delta.sh` for the converge template's twin of the retagged `#`-comment (a `#`-line IS rendered output); ⛔ never `--diff`, never from a docs lane, and no converge is behind it | router window, global slot | [prompt-dns-transport.md](prompt-dns-transport.md) |
| **HD-384** step 2 | point the two LiteLLM gateways at `litellm-engine_api` — only AFTER spark reboots with it in its accepted-key list; inverting the order 401s every upstream call | spark window (PLE load, ~20 min) | [prompt-litellm-consumers.md](prompt-litellm-consumers.md) |
| **HD-1122** | add the authored `llamacpp:*` panel to `homelab-llm` through `scripts/ansible/build-llm-dashboard.py` — the flag is already true and both legs are scraped, so no flip and no recreate is owed | **oldsrv** | [prompt-observability-alerting.md](prompt-observability-alerting.md) |
| **HD-1088** | register oldsrv's public key on the live Box — port 23 is key-auth-only, there is no other way in; then `storage_push_music.enabled: true`, converge `--tags storage --limit oldsrv.kogler.si`, `systemctl start push-music.service` once | **oldsrv** | [prompt-media-arrs.md](prompt-media-arrs.md) |
| **HD-1091** | rotate `lidarr_api` in the forced order (mint → Lidarr's `config.xml` → restart lidarr → re-render soularr's `config.ini` → re-point Seerr); the one-album end-to-end proof waits on a peer, not on an act here | **oldsrv** | [prompt-media-arrs.md](prompt-media-arrs.md) |
| **HD-1106** RULED | the prune — one `docker volume rm` per row the table marks `prune`; the `onlyoffice-docs` paths are on named volumes, which is what the ruling gated the set on | **VPS** | [prompt-storage-backup.md](prompt-storage-backup.md) |
| **HD-1103 · HD-1167 · HD-1109** | ONE owner-window Pi visit: the boot that makes the fstab `mode=0755` true on the mount, the one-time re-render of `pi-eth0.nmconnection`, and the standby's cold create (`--tags ha_failover`, it writes SSH keys) — a separate window. ⛔ the `nm-resolver` applies and HD-418's reconcile are DONE; on a keyfile host the write leg is `nm-pi` | **pi** | [prompt-smart-home.md](prompt-smart-home.md) |
| **HD-1143** | one privileged act (`docker exec` into the HA container, or a KNX integration reload) so exactly one `GroupValueRead` leaves the Pi, with the reverse rule's counters read either side | oldsrv + **pi** | — |
| **HD-443** RULED | revoke the Pi's `admin` on the neutralized state — a volatile journal cannot prove a 30-day silence | **pi** | [prompt-seat-cockpit-grants.md](prompt-seat-cockpit-grants.md) |
| **HD-1110** RULED | the OAuth-vs-`api_key` call on each seat's `pi_auth` providers; a `--push` must not settle it by rewriting a working login | every seat | [prompt-seat-cockpit-grants.md](prompt-seat-cockpit-grants.md) |
| **HD-1140** RULED | the laptop's Home reservation apply, which rides an existing router window rather than needing one of its own | router window | — |
| **HD-357** RULED | `seerrng` stays tailnet-only, its tile linked-not-probed | — | [prompt-edge-identity.md](prompt-edge-identity.md) |
| **HD-454** ⏸ RULED | nothing is purchased and no out-of-band path is scheduled, so a switched-off `oldsrv` waits for presence; ⏳ one WoL re-test at a planned power-off | **oldsrv** | — |

**Parity with [todo-table.md](todo-table.md) §D** — §D is everything genuinely left; this table is only the part of it with
an authored act queued behind the owner. Two rows here (**HD-357**, **HD-1140**) are no longer §D rows at all: their owner
act became AI work, and they stay here so no park is silently dropped. What §D carries and this table does not is owner eyes
and hands with nothing authored waiting: the visual pass over the boards (**HD-316 · 315 · 343 · 377 · 319**), the
browser-login seats still owed (**HD-147** with **HD-141**'s tail), the physical windows (**HD-06 · 288 · 194 · 34 · 191**)
and the two drill-time decisions (**HD-230 · HD-207**), the on-site matrix and `Mgmt99` tail (**HD-397**), the JupyterLab
LAN edge (**HD-366**), the Immich family-library seat question (**HD-457**), the enrolment sessions (**HD-412**), the
Jellyfin-login eyeball (**HD-353**), the device walks (**HD-1095 · HD-1097**) and the `opensubtitles_login` fix
(**HD-1096**). A lane reading only this file should not go looking for an authored act to flip, and a lane reading only
[todo-table.md](todo-table.md) §D should not assume these acts are already written.

**Unbriefed open rows** — no session launches from them; they live in [todo.md](todo.md) and every view, and the full list
is derived in [todo-table.md](todo-table.md) §B0. One id must not be lost: **HD-1100** (the PG legs — owner-paced, one
cluster per window, spanning every host so no one domain brief owns it). One thing carries neither a row nor a brief, so it
is named rather than re-derived: **the ghost CCU reservations** stay parked — their entries are commented out in
`network_static_hosts` (`IaC/ansible/group_vars/all/main.yml`), not deleted, and the generated address doc no longer
publishes them.
