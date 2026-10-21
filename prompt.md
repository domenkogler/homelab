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

**Seat and merge station.** The pi-dev seat is `oldsrv`, and its clone `domen@oldsrv:~/source/homelab` is the merging
station: merges land there, `scripts/validate-all.sh` runs there, and `git worktree list` on that host is the fleet's live
set (harness state in [docs/harness-pi-engines.md](docs/harness-pi-engines.md)). Owner/cleanup sessions also run from the
**Win11 Git-Bash** seat. The laptop's **WSL Debian** clone is retained and has a job: it is the designated runner station
for externally-served runs — off-box for every converge target, never the engine host, owner of no converge slot (the
rule is [todo-table.md](todo-table.md) §C rule 9, the state is
[docs/harness-pi-seat-identity.md](docs/harness-pi-seat-identity.md) §5a, and the legs only that box may drive are
[prompt-laptop-wsl.md](prompt-laptop-wsl.md) §2). It stays in `pi-seat-sync.sh`'s `SEATS`, so a fan-out still names it and
keeps reporting its real state — re-derive its `ok=`/`problems=` count there, never copy it from a handoff. Rescue refs
are likewise derived: `git for-each-ref "refs/*/rescue/*"`.

**The delegation-plane check — a rule, run it BEFORE routing any lane, on the seat you are on**: start the session on
that seat, launch ONE `async: true` child, and require it to **yield a child session file**. That is the whole test and no
`--check` substitutes for it; a pass certifies only the seat it ran on. Where a seat has not passed, lanes run
**foreground-sequential, one at a time** — a stated DEVIATION from O11 that ends seat by seat as **HD-1180**'s fix
lands, never a new rule, and never to be written into [docs/orchestration.md](docs/orchestration.md) or a brief as the
contract.

| seat | delegation-plane verdict | the one act left |
|------|--------------------------|------------------|
| `oldsrv` | **PASSES** — one `async: true` launch yielded a child session file, completed and returned its result | none: **lanes launched from oldsrv run `async: true`** |
| `win11` | not verified from that seat | ⏳ owner: push the `settings` plane and `pi install npm:pi-subagents@0.80.0` FROM the seat, then accept it with **its own** `async: true` launch |
| `wsl` | not verified from that seat | ⏳ owner: the same two acts, run FROM that seat |

⛔ Never by npm-installing chord under a managed seat tree. Mechanism and legs: **HD-1180** in [todo.md](todo.md) and
[prompt-seat-cockpit-grants.md](prompt-seat-cockpit-grants.md).

**Grade from the WSL Debian clone, not the Win11 shell** — gate items are red or blind on that seat (**HD-1117**,
**HD-1177**), so a Win11 green is a *partial* result and must be reported as one, never as the gate. Three reasons from
that seat still bind a probe: MSYS `grep` misses the CR of a CRLF pair (`grep -U` is mandatory in encoding guards),
`git` lives in `/mingw64/bin` not `/usr/bin`, and a case ending in a tmux/ansible probe must print SKIP, not a verdict
(CONVENTIONS §6).

**Push after you merge** — the station that merged is the station that pushes; an unpushed `main` is one disk between the
work and the fleet. That rule and the transient-failure note (a `remote: fatal error in commit_refs` reject is
GitHub-side: re-prove the ACL with `git push --dry-run`, then retry, and never conclude the commit is lost) are both
[docs/orchestration.md](docs/orchestration.md) §4 step 5.

**Git identity:** signing is RETIRED (**HD-1116**) — commit plainly, ⛔ never `git commit -s`;
`git log -1 --format='%G?'` → `N` is the expected value and is not a failure. A Win11 seat signs and pushes without a
1Password window once `bash scripts/git/git-bootstrap-win11.sh --git-identity` has run (`--check` shows the route,
`--1password` opts back). The seat file map and the one vault item left in this area (`GitHub auth`, the transport key)
are in [docs/deployment-secrets.md](docs/deployment-secrets.md) §What actually raises a 1Password prompt and
[docs/1password.md](docs/1password.md) §GitHub signing + auth keys. The two `.env.op` files that reference items and hold
no values are TRACKED, so a clone elsewhere loses nothing —
[docs/deployment-secrets.md](docs/deployment-secrets.md) §Secret Naming Convention.

**Secrets:** 1Password `Homelab-ansible` `item.field` only, `>-` for YAML renders, and never a value printed anywhere —
[docs/1password.md](docs/1password.md). Multi-line bash heredocs with backslashes/backticks get mangled through
`bash -c`: write the body to a temp file and run it.

**Reachability is settled — read the one SSOT, do not re-derive it:** [network-vpn.md](docs/network-vpn.md)
§Reaching LAN nodes when away (measured matrix + traps) and §The laptop alias contract (the only alias table; governs
BOTH `~/.ssh/config` files). In one line: behind-NAT hosts (`pi`/`nas`/`oldsrv`/`spark`) are reached over the VPS jump
onto their **Home leg**; the **Mgmt plane (VLAN 99) is same-site only** (`router`/`switch`/`ap-*`/`pi99`/`oldsrv99`/
`nas99` — never a `ProxyJump`). `ssh oldsrv` = the Home address. `python3`/bash/LF/UTF-8 no-BOM everywhere
(`.gitattributes` pins `eol=lf`, so a checkout is LF on Windows too).

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
2. ⏳ **The transport / answer plane** — **HD-436**: the repo-side hinge is CLOSED (one derived list, both consumers
   read it, parity-proven on all six surfaces); the row owes ONLY the live half — the two converges in the parked table
   below, both still PARKED. **HD-477** make the resolver actually float with the VIP: premise measured green, the row
   carries the three gates. **HD-487** config-manager truth is DECLARED per host in `host_vars/<host>.yml`, held by
   [`scripts/gate/check_net_manager.py`](scripts/gate/check_net_manager.py) and read with
   `scripts/ansible/probe-net-manager.sh`; the ONE thing owed is the **VPS** delete of the dead
   `/etc/systemd/network/20-eno1.netdev`, which only the role's removal leg reaches (parked). **HD-480 · 481 · 482 ·
   483**: the landable half — one SSOT `technitium_dns_policy` list plus the `technitium_resolver_settings` tuning dict
   from ONE seed step with an asserted read-back, `enableBlocking` DERIVED from the list, and
   [`scripts/gate/check_dns_policy_drift.py`](scripts/gate/check_dns_policy_drift.py) in the gate — LANDED and
   converged on the Pi; the VPS and oldsrv instances pick it up in their own slots. **✅ RULED 2026-10-20 (owner): ONE
   tier-wide upstream, the per-policy claim is DROPPED** — quote the mechanism from the row, never a letter (the two
   views lettered the options differently); ⛔ never buy per-policy filtering with a resolver instance, a listener
   address or a `:53` dst-nat target. So the device-level Kids/IoT acceptance in HD-481/482 is not owed by any settings
   change: filtering, where the family needs it, is a device-side act. **HD-1160** is not AI and **no converge is
   owed** ([network-dns.md](docs/network-dns.md) §What the pin can and cannot enforce,
   [network-rejected.md](docs/network-rejected.md)); what remains is the converge template's twin of the retagged router
   comment — the `#`-line in `IaC/router/templates/rb4011_converge.rsc.j2` is RENDERED output (HD-1167's class), so it
   moves only inside an **owner-present router window** (the global slot; ⛔ never from a docs lane, never `--diff`). The
   rules' own `comment=` strings are live device state and stay as they are. **HD-1152** (unbriefed) has its prune leg
   proved UN-RUNNABLE rather than un-run — both defects are invisible to `--syntax-check`, so `--check` can never name
   candidates; the repair is AI work, the first real apply is parked.
   → [prompt-dns-transport.md](prompt-dns-transport.md)
3. ⏳ **Silent-failure alerting** — **HD-450**'s collector legs are LIVE and read back per host; the row owes ONE
   re-point: alert delivery moves to Matrix under **HD-1108**, and until that leg is proven Signal stays the path
   alerts are read on. ⚠ A transient unit outside `monitoring_hygiene_units` is invisible to the exporter — use the
   trigger the doc carries, never a hand-made one. The **Alloy fleet pin** is settled state, not an open question:
   [docs/observability.md](docs/observability.md) §The Alloy pin (⛔ never `--allow-downgrades`).
   **LLM token accounting HD-1120 · 1121 · 1122** — **HD-1121** is a FINDING, not a job: `/metrics` answers `401`
   unauthenticated and `404` **with a valid admin bearer**, so no scrape was added; the row owes the gateway's
   `prometheus` callback + the auth form + the VPS loopback publish, which is a **gateway** recreate, not a monitoring
   one. **HD-1122**'s GPU half is live; its ENGINE half is authored behind `ai_tier_metrics_publish: false`
   (`group_vars/home_servers.yml`) — the flag, the `127.0.0.1` publish and the `prometheus.scrape "llama_cpp"` leg are
   ONE change that recreates two serving containers, so it waits an owner window. **HD-1120** is unchanged: totals are
   known for every caller and attribution comes from the **edge access log** (spec + the XFF trap:
   [docs/observability.md](docs/observability.md) §LLM token accounting).
   **HD-1163** names a dark monitoring host instead of discovering it in a forum post: the `curl 127.0.0.1:12345/metrics`
   probe + conditional restart leg in `roles/monitoring` and
   [`scripts/gate/check_host_reporting.py`](scripts/gate/check_host_reporting.py) are landed, and the paging half is
   authored, LOADED and watched red. ⚠ **A rule that is authored is not a rule that is loaded** — prove it with
   `GET /api/v1/provisioning/alert-rules`, never the repo file; a provisioning task with no `tags:` of its own was the
   shape that hid it (`--tags grafana` silently dropped it and still recapped `failed=0`).
   **HD-1166** is landed — every probe target now names itself in `instance`. ⚠ **Retiring a probe target can be the
   cheaper half of a fix: check what the rule was actually watching.** `ha-unreachable` could never match a series, so
   target and rule are retired, and the honest consequence is that **HA liveness has no firing rule** until the gated
   `ha_exporter` job → **HD-1182**; one owner-present VPS `--tags monitoring` converge applies the retirement and that
   apply is the row's only live tail. **HD-1164** is a firmware/kernel question, not a repo question: the `nas` unit
   stays **stopped on purpose** until the owner schedules the look plus a memory test. ⚠
   `check_host_reporting.py --check` reads RED for `nas` and that is the instrument working — do not soften the expected
   set to make it green. **HD-1175** (`oldsrv`) is **recovered, not closed**: the cause is unexplained, so the row owes
   the root-only read of the previous boot's journal and `pstore`, which no rule can reach from a user session; the same
   reboot surfaced a boot-time DB-dump push race → **HD-1183**. What *arrives* in the channel is a separate design
   question from what *fires*: a still-firing alert re-sends at most every **24 h** (`repeat_interval` in the
   notification policy `roles/monitoring` renders; the first send is not delayed).
   ⛔ **HD-1174** is registered and open: kopia's `repository connect server` echoes the URL it was handed, so the
   `kopia-server-internal_api` credential sits in plaintext in the agent's container log and in the log store for the
   retention window — scrub the connect line, then rotate with the agent **re-connected** (its `repository.config`
   caches the credential). → [prompt-observability-alerting.md](prompt-observability-alerting.md)
4. ⏳ **The media / music ladder** — **HD-362**: what Lidarr is missing is APP state, not a secret — one indexer and one
   download-client entry (the seed-in-IaC question); Aurral → Lidarr is a **browser** leg (the add is a click on a
   recommendation card; its URL+key are encrypted inside `aurral.db` and the API 404s on the obvious routes). The Tube
   Archivist `path.repo` note stays; the slskd login question is CLOSED (⛔ probe with `docker exec slskd
   /slskd/slskd --envars`, never by grepping a rendered compose) and the Soulseek password rotation is **DECLINED and
   risk-accepted on record** — do not re-open either. **HD-1090** owes one grab started in Prowlarr's own UI.
   **HD-1091** is authored and **ARMED**, not OFF: one vault item (`soulseek-internal_api`) renders into BOTH ends, so
   neither side can be armed alone. What it owes is not a seed: **one album crossed end-to-end**, which needs a peer to
   finish one inside the poll window, and the **`lidarr_api` rotation** (`NOT_AUTO_ROTATABLE`, four copies, a forced
   order — parked). The `SLSKD_DOWNLOADS_DIR` retarget is decided as NONE. **HD-1088** now RENDERS on oldsrv with its
   guard proven before any push (⚠ `--max-delete` is a **CAP, not an abort** — [docs/storage.md](docs/storage.md) and
   the fixture [`scripts/testdata/rsync-max-delete/run.sh`](scripts/testdata/rsync-max-delete/run.sh) — and with no
   identity the script aborts at its OWN identity assert before the mount assert). **One owner action gates every
   end-to-end proof: register oldsrv's public key on the live Box.** **HD-1092** is void as written — the Authentik→NAS
   glue is gone from BOTH sides and `op` on the NAS is unwanted rather than missing, gid 1005 is supplementary BY
   DESIGN; what remains is one credential-bearing leg on a second host (`smbclient //nas/domen -A creds`), parked.
   (**HD-1089**, the SABnzbd locality read, is the same lane's subject but no brief claims the row — it is in the
   unbriefed list below.) → [prompt-media-arrs.md](prompt-media-arrs.md)
5. ⏳ **Cockpit, the coding seats, grants** — the cluster (**HD-361 · 411 · 442 · 443 · 444 · 465 · 495 · 1085 ·
   1110 · 1138 · 1139 · 1140 · 1161 · 1173**) with its owner-gated tails intact, plus **HD-1180** (unbriefed — its AI
   half is one pin line in `IaC/ansible/group_vars/all/versions.yml`, its acceptance half is a hand on each seat).
   ⚠ **Pull the DRIVER clone first: at `main~2` the pre-flight calls two current seats `STALE-CLONE**, and the
   remediation it prints then points at the two boxes that needed nothing.
   **HD-1173** — repo side landed, so what is open is its **live tails** (parked, owner-present): remove the parked
   `dsh` + `pi-dev` harness IaC and make `pi-dev.ts.kogler.si` a second name on the existing `pi-oldsrv-backend`
   (`pi-oldsrv.ts.kogler.si` stays canonical). The repo carries **one** pi pin now
   ([docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1), so there is no deletion half left here.
   **HD-1138** — the away-case spelling in the scripts that shell out to bare `ssh <name>`, and the VS Code
   server-install leg it gates. **HD-1139** found NO dead prefix class and no rule change is warranted.
   **HD-1140** is **ruled 2026-10-20 (owner): the ledger owns the laptop's Home reservation** — a
   `network_static_hosts` row plus a find-guarded `rb4011_*_delta` in the Pi's shape, so the apply rides an existing
   router window rather than needing one of its own.
   **HD-495**: `git-bootstrap.sh --git-identity` (and `--git-identity --check`, read-only) owns the three lines a Debian
   seat needs OUTSIDE any clone, reported through `git config --global --get`; what is left is the two hand-planted
   `~/.ssh` keys — the script reads them back and prints `ssh keys present = …`, it does not raise them, raising them is
   `--ssh-auth`, so no converge asserts the payload exists. ⚠ Never re-add `git commit -s`; signing is retired.
   **HD-442** still waits the value-identity half — hash the rendered `/etc/op/provision-token` against the vault's
   `ansible_provision_token`, lengths only — in an owner-present sitting. Read [docs/1password.md](docs/1password.md) §1
   first: prove scope with the `op whoami` **Integration ID**, `op vault list` cannot tell the scopes apart.
   **HD-443** is **ruled 2026-10-20 (owner)**: a volatile journal cannot prove a 30-day silence, so the `admin` revoke
   proceeds on the neutralized state plus the fingerprint match, behind the order that keeps the door open
   (`ansible-admin` and `domen` proven first). ⛔ A raw journal grep for the phrase also **matches the probe that greps
   for it** — filter on `sshd-session[…]` / `-u ssh.service`.
   **HD-1110**: `scripts/harness/pi-seat-sync.sh` is the one deploy path and **the seat legs run FROM their own seat,
   oldsrv included** — the matrix and the seat-side rule are
   [docs/harness-pi-seat-identity.md](docs/harness-pi-seat-identity.md) §5a, and a plane command executes in the SEAT's
   shell, so its python launcher resolves there ([docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1). The
   OAuth-vs-`api_key` call is **ruled 2026-10-20 (owner): `api_key` is the fleet spelling**, an OAuth entry on a seat is
   drift, and it is never cured by overwriting a live credential: mint through the `pi_auth` vendor lane of
   [`scripts/harness/render-pi-config.py`](scripts/harness/render-pi-config.py)
   (§4 of [docs/harness-pi-models.md](docs/harness-pi-models.md)) and report the mismatch instead. Its sibling
   **HD-1161**: `install-pi-wsl.sh`'s pi leg is `curl … https://pi.dev/install.sh | sh` with no version at all while its
   Debian sibling installs from the pin, and `pi-self-update.sh` REFUSES the managed layout that installer creates.
   ⚠ **HD-1180 is the delegation plane the pi 1.3.0 bump took away** — an `async: true` launch dies at start with 0 s of
   work and no child session file while a FOREGROUND child on the same seat runs normally, and the seat plane still
   reads `OK`. The AI half (the `pi_host_subagents_npm_version` move) is DONE; a pin reaches no seat by itself.
   **Per-seat verdict, and a pass on one seat certifies only that seat:** `oldsrv` — **PASSES**, lanes launched from
   here run `async: true`; `win11` and `wsl` — ⏳ **owner, one act each**: the `settings` plane pushed and
   `pi install npm:pi-subagents@0.80.0` run FROM that seat, each accepted by **its own** `async: true` launch that
   yields a child session file (a green plane matrix proves none of it). ⛔ never by npm-installing chord under a
   managed seat tree. Until a seat's own leg runs, the foreground-sequential deviation in §1 binds THAT seat.
   → [prompt-seat-cockpit-grants.md](prompt-seat-cockpit-grants.md)
6. ⏳ **Storage, backup, the DR story** — **HD-191**'s ZFS policy units. **HD-1107**: **ruled 2026-10-20 (owner) — take
   the replica datasets out of the snapshotting template (the `data` template in `sanoid.conf.j2`); the retag, never a
   hand-destroy of the 66** — a `zfs receive` target takes no autosnapshots of its own and the rollback targets of
   record are the source-side `tank/data/*` snapshots. The act is AI work on the `nas` slot and the sequence matters:
   kill the wedged pipeline's shell wrapper first, or sanoid's `iszfsbusy()` defers every prune and the retag looks like
   it did nothing. **HD-1105** — the three enabled-but-dead nas units are all ruled and `--failed` lists 0.
   **HD-1106** — the prune itself is owed: one `docker volume rm` per row the table marks `prune`, plus a named volume
   or bind for the two `onlyoffice-docs` paths, whose WOPI/JWT keypair is **re-minted at every recreate**.
   **HD-1093** ⏳ land the rotated family SMB passwords on the NAS with `storage_samba_password_force` — a vault rotate
   alone changes nothing on the box. Plus **HD-207** and **HD-238**. → [prompt-storage-backup.md](prompt-storage-backup.md)
   nothing on the box), **HD-207** and **HD-238**. → [prompt-storage-backup.md](prompt-storage-backup.md)
7. ⏳ **The Pi's own box** — **HD-418**: reconciled at both ends and owned in IaC
   (`roles/home_assistant/tasks/pi.yml`, tag **`hd418`**). ⚠ The proof is BEHAVIOUR, not the YAML: the list HA
   **enforces** is the `.storage/http` object, so `grep -A6 trusted_proxies configuration.yaml` can neither prove nor
   fix a `400`. ⏳ What that does not buy is the takeover-shaped request sent **from the oldsrv edge** (another lane's
   host), and the standby-shaped case has **no subject** while HD-1109 stands.
   **HD-1103** — the cause was a **tmpfs mounted without `mode=`**, not a mode that drifted (the mount owns the `1777`,
   and the fleet value logrotate's secure-parent check accepts is `755 root:adm`). Two halves remain and both are
   choices, not commands: `/var/log` is a **100 MB tmpfs** on `weekly` + `rotate 4` with **no `compress`**, so either
   `compress` + `delaycompress` or `rotate 1` + `maxsize` — ⚠ **the repo owns no logrotate config today, so whichever
   wins is a NEW file sized against `size=100m`, not an edit**; and the smartd park (smartmontools 7.4-3 cannot address
   this card by any type) is a ≥7.5 source or the mask `roles/ai_diag` **derives** from an empty `smartctl --scan` — a
   designed converge outcome the next UNTAGGED converge applies in an owner window, and a lane hand-disabling the unit
   by hand would be the actual defect. The fstab `mode=0755` becomes true on the mount at the **next boot**, not from a
   converge; ⛔ never `mount -o remount` as the fix.
   **HD-1167** — a comment in a template can rewrite a running box's addressing file: `#`-lines in a `.j2` are literal
   OUTPUT, so `Render Pi eth0 NetworkManager keyfile` reports `changed` on EVERY converge while every functional line
   matches, and `changed` is what notifies `reload NetworkManager` on a box of the DNS tier. First act is the stripped
   comparison, both sides (`grep -v '^#'` on the host file against the template's non-comment lines); the fix belongs in
   `roles/network`, never on the host; the one-time re-render is an owner-window act with HD-1101's rollback standing
   by, and `spark` uses the same render unmeasured.
   **HD-1109** — the standby is **UNDEPLOYED**, not cold-deployed: oldsrv runs no `home-assistant-standby` and no
   `keepalived`, and the render pins `home-assistant:2026.9.4` which that host does not hold, so HD-418's standby-edge
   proof and HD-434's standby KNX tunnel have **no subject**. Probe the standby with
   `docker compose -f /opt/home-assistant-standby/docker-compose.yml ps`, NEVER `systemctl is-active keepalived` — its
   `inactive` is the CORRECT read, because the VRRP half is the container that compose does not have — and probe on the
   host that owns the unit: a systemd/file-presence probe answers about the box you ran it on.
   **HD-1101** — the fail-loud resolver guard is keyed on `host_resolver_dns` alone with a per-host `set_fact` naming
   the profile THIS host writes, and it is fixed and applied on both hosts. ⚠ tag class, so nobody re-derives it wrong:
   on a keyfile host the write leg is **`nm-pi`**; `--tags nm-resolver` there selects the guard and proves the check, and
   writes nothing. Plus **HD-04 · 434 · 438 · 439 · 319 · 17**. → [prompt-smart-home.md](prompt-smart-home.md)
8. ⏳ **Edge and identity** — **HD-147**'s browser-login tail, **HD-457** (the SSO seat owns the family library — ruled; what is left is the per-user/shared-album shape, read at implementation time), **HD-458 · 459** (zipline, the published names), **HD-112**, and **HD-357** — the launchpad tiles, promoted onto this brief 2026-10-13 (its family-surface brief was retired and no successor took the row). ⏸ **HD-47** stays an owner act,
   **Deferred by owner 2026-10-08**: the external-room join is unscheduled; everything publishable is published and
   measured. → [prompt-edge-identity.md](prompt-edge-identity.md)
9. ⏳ **The LiteLLM consumer chain** — one ordered pair left (**HD-384**), and what remains is **sequencing, not
   thinking**: `litellm-engine_api` is minted and rendered into spark's accepted-key list, and the gateways may be
   pointed at it only **after** spark reboots with it — a spark engine restart is an owner-window action (PLE load,
   ~20 min), so step 2 is parked rather than slipped in. Settled state lives in its owning docs, not here: thinking
   control ([docs/services-ai.md](docs/services-ai.md) §9d), the `/ui/login` deep link (§4c), voice
   ([docs/smart-home-voice.md](docs/smart-home-voice.md); the plaintext-replication ruling in
   [docs/deployment-secrets.md](docs/deployment-secrets.md) §Runtime plaintext that leaves the vault), and n8n audited
   shut with no AI node, so no key to mint ([docs/services-utilities.md](docs/services-utilities.md)). One defect from
   that turn is NOT the gateway's: Assist cannot resolve "dnevna soba" (**HD-1127**). **HD-1178** (new in this lane,
   **unbriefed**): the oldsrv `embed` leg's next model is chosen by a bench, not a leaderboard — nothing measured yet,
   and the corpus, both gates and the probe commands are in
   [docs/services-ai-bench.md](docs/services-ai-bench.md) §3d; the bench's first act is a `server-vulkan` pin bump that
   recreates the **reranker** leg with it. `EmbeddingGemma 2` stays rejected for the RAG leg and in scope only as the
   code-retrieval candidate inside that bench (OQ-14 is open on that axis, and its docs half still stands parked on the
   measured recall floor). → [prompt-litellm-consumers.md](prompt-litellm-consumers.md)
10. ⏳ **The Win11 seat's serving legs** — **HD-474** FIM latency and **HD-476** the VL `mmproj` on the iGPU. The
    laptop's local **agent** leg is retired (owner ruling 2026-10-09), so this brief is FIM + vision only and claims
    no converge host — which is why it can run beside anything except a live pi-seat lane. →
    [prompt-laptop-legs.md](prompt-laptop-legs.md)
11. ⏳ **The `scripts/` restructure** — **landed**: `scripts/` is now `lib/ gate/ ansible/ secrets/ git/ harness/ bench/
   hardware/ testdata/` with `validate-all.sh` + `render_all.py` at root, root resolution is structural, and
   `gate/check_script_layout.py` holds the tree from inside `validate-all.sh`. **Three live legs stay in the row — the
   two seat legs and the from-zero leg.** ⏳ **The seat legs are run FROM the seat** —
   `bash scripts/harness/pi-seat-sync.sh --check` and `install-tmux-conf.sh --push` on the win11 seat, in its own
   session — because a seat plane converges from its own clone and the station cannot speak for a seat's PATH;
   `run_on_seat oldsrv` carries a local arm chosen by the box's own hostname
   ([docs/harness-pi-seat-identity.md](docs/harness-pi-seat-identity.md) §5a). `install-pi-debian.sh --check` on a clean
   Debian seat is the third leg and it is **PARKED** — no host in the fleet is a spare clean Debian box to run it on.
   The `harness` docs domain is REGISTERED, not missing: [prompt-scripts.md](prompt-scripts.md) §The taxonomy call and
   the hub [docs/harness.md](docs/harness.md), and the verdict count is that checker's own output.
   ⚠ **The `check_mode: false` rule reads the line as this repo writes it** (`check_mode: false   # read-back` IS
   false) and classifies the site by its carrying task: a read-only module (`stat`/`slurp`/`find`/`get_state`/
   `*_facts`) or a `command`/`shell` declaring `changed_when: false` is a read-back, anything else is a WRITE and
   reddens naming `file:line`. The verdict table is
   [docs/deployment-ansible.md](docs/deployment-ansible.md) §Self-converge guardrail; ⛔ the wrong fix would be
   declaring cockpit `check_safe: false`, which would refuse the very `--check` HD-361 exists to make possible.
   **The child-lane contract is a rule with a ceiling and a gate** — O10/O11 in [docs/orchestration.md](docs/orchestration.md)
   §4 and `subagents.modelScope` in [`pi-agent/settings-ssot.json`](pi-agent/settings-ssot.json), held by
   [`scripts/gate/check_subagent_contract.py`](scripts/gate/check_subagent_contract.py). Until a seat's own `subagent`
   plane `--check` prints `OK` for `~/.pi/agent/extensions/subagent/config.json`, that seat runs the harness defaults
   and a run must pass the values on the launch ([docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1).
   **The registry's prose is a rule with a checker** —
   [`gate/check_registry_prose.py`](scripts/gate/check_registry_prose.py) — so `scripts/README.md` is a facts-only map;
   print its count with `--show`, never a number typed into a handoff. → [prompt-scripts.md](prompt-scripts.md)
12. ⏳ **Owner-gated tails** (exact steps in the rows): **377** the Grafana render re-do · **444** the phone→oldsrv
    cockpit crossing · **1103 + 1167** one Pi visit — the boot that makes the fstab `mode=` true on the mount, and the
    one-time re-render of `pi-eth0.nmconnection` that notifies `reload NetworkManager` · **HD-06** the UPS drill ·
    **411** the cockpit resume word · **HD-230 · 207** the decisions taken at the drill · **1175** a human at `oldsrv`'s
    console, because there is no out-of-band power path at all (the posture **HD-454** rules; its WoL re-test has never
    been run) · **1170 · 1171 · 1150** the three secret-close windows: rotate `spark-llm_api` and rule on
    `radarr_api`/`sonarr_api`; rotate `op_api` and re-seat all four installs; re-seat `vps:/etc/op/provision-token` with
    the `matrix_password` ruling — none of these closes with a repo change · **HD-1181** the **14 CURRENT vault values**
    this seat's pi transcripts hold: the rotation is the owner's and it **differs per item**, so act from the row's
    per-item list, not from memory (some are a vault edit + re-render, some must be rotated **in the app first**, some
    are coupled, one is the provider side). ⚠ **`check_secret_leak.py` — and with it `validate-all.sh` — is RED at the
    tip here BY DESIGN until that rotation lands**: no ledger line was added and the checker was not edited to quiet a
    live value, so a green leak read on this seat would mean the register was muted, not that the exposure is gone.
    Deleting or shredding transcripts closes nothing — a rotated value stops being a finding, an unrotated one never
    does — and the register is **per seat**, so win11 and wsl owe the same read. **HD-1160** owes one owner-present
    **router window** (global slot) for the converge template's twin of the retagged router comment in
    `IaC/router/templates/rb4011_converge.rsc.j2` — a `#`-line that IS rendered output, so it moves with a render +
    `routeros-apply-delta.sh` inside the window; ⛔ never from a docs lane, never `--diff`. ⏸ **HD-454 is ruled, not
    pending** — nothing is purchased and no out-of-band path is scheduled, so a switched-off `oldsrv` waits for
    presence, and the one owner-side leg left is a WoL re-test at a planned power-off — and **HD-47** above.
13. ⏳ **Unrowed, but not free** — **HD-1100**'s held legs: four middle PG legs stay held by owner ruling — run one
    cluster per window on the owner's word, each proved by its `pg_control` + key-table read and by the next `db-backup`
    run that dumps it. ⚠ The `wireguard` leg this line used to owe on **oldsrv does not exist there**:
    `home_servers.yml` carries no `wireguard` role, so `--tags wireguard` there selects zero role tasks; the only wg leg
    in the tree is the **VPS** side, and it restarts the tunnel every off-box converge rides — owner-present, detached,
    run **last**, then re-verify every tunnel path. The **apt upgrade phase** stays OUT of the converge wave — ruled
    2026-10-12 (option A), `roles/updates` is DECLINED and not pending, and the `apt-mark hold` that ruling required is
    live on all five hosts (`roles/common/tasks/apt-holds.yml`, read back with `apt-mark showhold`), so `apt upgrade` can
    no longer move a pinned HOST package anywhere in the fleet (`kopia` ships as a pinned CONTAINER image, so there is
    no apt state there). What that leaves is the pin **LAG**, not the pin, and it is reported — so count it from the
    ruler API and never from this file:
    `count by (instance) (homelab_pkg_pin_result{result="differ"})` on
    [docs/observability.md](docs/observability.md) §Pin-lag report, where the per-host read lives. A host that reads
    `differ` is reporting the gap, not a false positive. No `--tags docker` apply is owed anywhere (`oldsrv` never was,
    `nas` runs no docker role), and one list — `docker_ce_suite_packages` — drives the apt call, the hold lift and the
    read-back on every host that carries the suite.
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

15. ⏳ **The gate's own speed and trustworthiness on a Windows seat** — **HD-1135** landed the fork diet and gave
    `sync-skills.sh` the `--self-test` its encoding guard was waiting on; ⏳ what is left is that **the win11 side of
    that change has never been re-run on that seat**, so its per-`pin()` cost figures still stand for it. The timings are
    the row's and the registry's business, not this file's: [scripts/README.md](scripts/README.md) `validate-all.sh` +
    `sync-skills.sh`. **That seat cannot be trusted to grade itself (**HD-1177**)**: gate items there read red or blind
    while the same commit is green in WSL, so two clones of one commit reach opposite verdicts — **grade from the WSL
    Debian clone, and a Win11 green is a *partial* result that must be reported as one**, never as the gate.
    ⏳ **In order from there:** the gawk rename (one variable, prove the block prints on a forced red run), the UTF-8 pin
    in `check_secret_leak.py`, then the fix-or-`SKIP` call on the converge-guard fixture and the ledger-or-rescope call
    on the generated-path citations. **HD-1176**'s mechanism is in place on the seat and the row stays **open** for what
    it still owes: the four seat artifacts have **no repo owner** (the `wsl` seat plane in `scripts/harness/`), the
    headscale-side call on MagicDNS `SERVFAIL`ing most of `zone_kogler_si`, and the suspend/resume + away-from-home
    re-measure. Record: [scripts/README.md](scripts/README.md) `validate-all.sh` + `sync-skills.sh` rows ·
    [docs/network-dns.md](docs/network-dns.md) §Host-side resolver.
**Parked on an owner-present window** — authored work with exactly one blocked action in front of it, named with that
action so no lane re-derives it. **The 2026-10-20 owner round is applied throughout: an entry marked RULED is AI work,
not an owner act** — the rulings are the rows' and [todo-table.md](todo-table.md) §A1's, and this file restates none.

| HD | the one blocked action | slot / host | 📋 brief |
|----|------------------------|-------------|----------|
| **HD-436** (a) | ONE guarded converge re-rendering headscale's `config.yaml` — the answer set is identical and the FILE is not, so it reports changed and restarts the control plane: sampled liveness probe, never a one-shot inspect | **VPS** slot | [prompt-dns-transport.md](prompt-dns-transport.md) |
| **HD-436** (b) | `IaC/ansible/playbooks/dns.yml` run where the Cloudflare token is IP-filtered; expected to report no record change | home control plane | [prompt-dns-transport.md](prompt-dns-transport.md) |
| **HD-436** step 2 | the `extra_records_path` swap that **HD-435**'s `tailnet: dual` publish rides | **VPS** | [prompt-dns-transport.md](prompt-dns-transport.md) |
| **HD-487** | the narrow `--tags netd` delete of `/etc/systemd/network/20-eno1.netdev` — only the role's removal leg reaches it, because vps declares no `netd_phys_name` | **VPS** | [prompt-dns-transport.md](prompt-dns-transport.md) |
| **HD-1152** | the first REAL `playbooks/dns-seed.yml` apply per instance, and only after its two defects are repaired — `--check` skips the whole Technitium block and can never name candidates | vps · oldsrv · pi | [prompt-dns-transport.md](prompt-dns-transport.md) |
| **HD-1160** | render + `routeros-apply-delta.sh` for the converge template's twin of the retagged `#`-comment (a `#`-line IS rendered output — HD-1167's class); ⛔ never `--diff`, never from a docs lane, and **no converge is behind it** | router window, global slot | [prompt-dns-transport.md](prompt-dns-transport.md) |
| **HD-384** step 2 | point the two LiteLLM gateways at `litellm-engine_api` — only AFTER spark reboots with it in its accepted-key list; inverting the order 401s every upstream call | spark window (PLE load, ~20 min) | [prompt-litellm-consumers.md](prompt-litellm-consumers.md) |
| **HD-1122** | flip `ai_tier_metrics_publish: true` and converge `--tags docker_services,monitoring` — ONE change that recreates two serving containers, so not at night | **oldsrv** | [prompt-observability-alerting.md](prompt-observability-alerting.md) |
| **HD-1164** | an `intel_iommu=off` experiment plus a memory test; the restore line is `systemctl start alloy` and the unit stays stopped until then | **nas** (HP Gen8) | [prompt-observability-alerting.md](prompt-observability-alerting.md) |
| **HD-1088** | register oldsrv's public key on the live Box (port 23 is key-auth-only and `Hertzner-SB-Data` holds only a CIFS/WebDAV password, so there is no other way in); then `storage_push_music.enabled: true`, converge `--tags storage --limit oldsrv.kogler.si`, `systemctl start push-music.service` once | **oldsrv** | [prompt-media-arrs.md](prompt-media-arrs.md) |
| **HD-1091** | rotate `lidarr_api` — `NOT_AUTO_ROTATABLE`, and the order is forced: mint → Lidarr's own `config.xml` → restart lidarr → re-render soularr's `config.ini` → re-point Seerr | **oldsrv** | [prompt-media-arrs.md](prompt-media-arrs.md) |
| **HD-1093** | land the rotated family SMB passwords with `storage_samba_password_force` — a vault rotate alone changes nothing on the box | **nas** | [prompt-storage-backup.md](prompt-storage-backup.md) |
| **HD-1107** RULED | the retag: the replica datasets leave `sanoid.conf.j2`'s `data` template, never a hand-destroy of the 66. Kill the wedged pipeline's shell wrapper first, or `iszfsbusy()` defers every prune and the retag reads as doing nothing | **nas** | [prompt-storage-backup.md](prompt-storage-backup.md) |
| **HD-1106** RULED | the prune — one `docker volume rm` per row the table marks `prune`, plus a named volume or bind for the two `onlyoffice-docs` paths | **VPS** | [prompt-storage-backup.md](prompt-storage-backup.md) |
| **HD-1103 · HD-1167 · HD-1109** | ONE owner-window Pi visit: the boot that makes the fstab `mode=0755` true on the mount, the UNTAGGED converge that applies `ai_diag`'s derived smartd mask, and the one-time re-render of `pi-eth0.nmconnection`. ⛔ the `nm-resolver` applies and HD-418's reconcile are DONE on both hosts — do not re-run them; on a keyfile host the write leg is `nm-pi` | **pi** | [prompt-smart-home.md](prompt-smart-home.md) |
| **HD-1143** | one privileged act (`docker exec` into the HA container, or a KNX integration reload) so exactly one `GroupValueRead` leaves the Pi, with the reverse rule's counters read either side | oldsrv + **pi** | [prompt-smart-home.md](prompt-smart-home.md) |
| **HD-443** RULED | revoke the Pi's `admin` on the neutralized state — the volatile journal cannot prove a 30-day silence | **pi** | [prompt-seat-cockpit-grants.md](prompt-seat-cockpit-grants.md) |
| **HD-1110** RULED | the OAuth-vs-`api_key` call on each seat's `pi_auth` providers; a `--push` must not settle it by rewriting a working login | every seat | [prompt-seat-cockpit-grants.md](prompt-seat-cockpit-grants.md) |
| **HD-1140** RULED | the laptop's Home reservation apply, which rides an existing router window rather than needing one of its own | router window | [prompt-seat-cockpit-grants.md](prompt-seat-cockpit-grants.md) |
| **HD-357** RULED | `seerrng` stays tailnet-only, its tile linked-not-probed | — | unbriefed |
| **HD-454** ⏸ | ruled and not pending — a switched-off `oldsrv` waits for presence; the one owner-side leg left is a WoL re-test at a planned power-off | **oldsrv** | — |

⚠ **`oldsrv` is back and its parked acts are un-parked**, with one exception that is not about presence: a
lockout-class role (`network`, `storage`, `wireguard`, `tailscale-node`, `cockpit`) applied to `oldsrv` is refused by the
self-converge guard `IaC/ansible/playbooks/tasks/self-converge-guard.yml` while `oldsrv` is itself the controller, so
those legs still need another control node or an in-band console — run **alone** and off the box with a console
reachable ([docs/deployment-ansible.md](docs/deployment-ansible.md) §Runner placement). The docker-family apply shape
stays the rule for the next pin bump (no apply is owed anywhere now): one host at a time, detached, `--check` first,
never behind a timeout, ⛔ not overnight, and the §1.10 survivor restart after it — a live-restore survivor keeps the
OLD `docker.sock` inode. An apply lifts the hold for exactly the suite names it moves and re-holds them in the same play.

**Parity with [todo-table.md](todo-table.md) §D** — §D is everything genuinely left; this table is only the part of it
with an authored act queued behind the owner. Two rows here (**HD-357**, **HD-1140**) are no longer §D rows at all: the
2026-10-20 ruling turned their owner act into AI work, and they are kept in this table so no park is silently dropped. What §D carries and this table does not is owner eyes and hands with
nothing authored waiting: the one visual pass over the boards (**HD-316 · 315 · 343 · 377 · 319**), the browser-login
seats still owed (**HD-147** with **HD-141**'s tail), the physical windows (**HD-06 · 288 · 194 · 34 · 191**) and the two
drill-time decisions (**HD-230 · HD-207**), the on-site matrix and `Mgmt99` tail (**HD-397**), the JupyterLab LAN edge
left untouched on instruction (**HD-366**), the Immich family-library seat question (**HD-457**), the enrolment sessions
(**HD-412**), the Jellyfin-login eyeball (**HD-353**) and the `opensubtitles_login` fix (**HD-1096**). A lane reading
only this file should not go looking for an authored act to flip, and a lane reading only §D should not assume these
acts are already written.

**Unbriefed open rows** — no session launches from them; they live in [todo.md](todo.md) and every view, and the full
list is **derived** in [todo-table.md](todo-table.md) §B0. Two ids must not be lost: **HD-357** (the launchpad tiles —
the family-surface brief was retired and no successor took the row; it wants a promoting decision, not a re-scope) and
**HD-1100** (the PG legs — owner-paced, one cluster per window, spanning every host so no one domain brief owns it).
One thing carries neither a row nor a brief, so it is named rather than re-derived: **the ghost CCU reservations** stay
parked — their two entries are commented out in `network_static_hosts`
(`IaC/ansible/group_vars/all/main.yml`), not deleted, and the generated address doc no longer publishes them.
