> **Role:** entry point for the next session — a **lean handoff**, a pointer index and nothing else. Every item's authority
> is its [todo.md](todo.md) row; permanent knowledge is the owning doc ([docs/index.md](docs/index.md) map); the permanent
> process contract (working rules, orchestrator mode O1–O9, launch, merge/cleanup) is
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
land, `main` is pushed and `scripts/validate-all.sh` runs there, so `git worktree list` on that host is the
fleet's live set (harness state in [docs/pi-harness.md](docs/pi-harness.md)). The laptop's WSL Debian clone is **retained but
rarely used as a seat (owner ruling 2026-10-09, which supersedes the 2026-10-07 “retired” wording)** —
it stays in `pi-seat-sync.sh`'s `SEATS`, so a fan-out still names it and keeps reporting its real state. Two refs were unique to that box — a stash (`On main: never_evict
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

Ranked by what unblocks the most. Each line is the item + **the domain brief that carries its order of work** —
the brief, not this list, holds the steps, the file ownership and the converge host. Waves, pairing and the
host/slot rule that decides what may run together are [docs/orchestration.md](docs/orchestration.md) §4 (O1–O9);
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
2. ⏳ **The transport / answer plane** — **HD-436**'s hinge: the derived `zone_kogler_si` list is on `main`; switch
   the two consumers that still hand-author (`vps.yml`'s subdomain lists, `roles/cloudflare_dns/vars`). The
   blocker that was mechanical is gone — the seat drives the RouterOS API now (**HD-495**, 2026-10-08) — so what
   remains is the owner-present window, not the tooling. Alongside it: **HD-477** (make the resolver actually float
   with the VIP; premise measured green, the row carries the three gates), **HD-487** (config-manager truth per host
   — `scripts/ansible/probe-net-manager.sh` reads the verdict off the interface the default route rides: oldsrv/pi =
   NetworkManager with dead networkd renders on disk, vps = networkd, **spark = both managers on one box**,
   **nas = neither**), **HD-488** (the same host-resolver class beyond oldsrv — the **Pi leg landed and was verified
   2026-10-08**; spark still waits on a spark-slot converge, nas on HD-487), and the DNS-policy rows **HD-480–483**.
   → [prompt-dns-transport.md](prompt-dns-transport.md)
3. ⏳ **Silent-failure alerting** — **HD-450**'s rules are live and proven end to end (the alert read closed
   2026-10-09); two things are owed: leg (c), the NUT client→master **metric**, and exporting the VPS **box** cert,
   which has no series at all. ⚠ The canary recipe this handoff used to carry could not fire — a transient unit
   outside `monitoring_hygiene_units` is invisible to the exporter; the working trigger is in the doc. **HD-1094**
   is **proof-owed, not closed**: the fleet pin IS `alloy_version: "1.20.1-1"`
   (`IaC/ansible/group_vars/all/versions.yml:347`) with no per-host override left, so the decision is taken — what
   remains is reading each monitoring host's **running** version against the pin and quoting `up{job="alloy"}` after
   its restart. A `dpkg` read is not a health read, and ⛔ never add `--allow-downgrades`. **LLM token accounting
   (HD-1120 · 1121 · 1122, minted 2026-10-09)** is now in the same brief: the engine counters report for **every**
   caller (totals known, attribution not), the two LiteLLM gateways and the oldsrv serving tier report **nothing**, and
   attribution is taken from the **edge access log** — a metering proxy hop was ruled out because it re-buys the hop
   decision #26 removed. Spec + the XFF trap: [docs/observability.md](docs/observability.md) §LLM token accounting. →
   [prompt-observability-alerting.md](prompt-observability-alerting.md)
4. ⏳ **The media / music ladder** — **HD-362** keeps two Lidarr legs to verify (one album through `lidarr-ydl`,
   one Aurral → Lidarr add) and the Tube Archivist `path.repo` note; the slskd login question is CLOSED (the vault
   was right; the compose carried four env names slskd does not read — probe with
   `docker exec slskd /slskd/slskd --envars`, never by grepping a rendered compose) and the Soulseek password
   rotation is **DECLINED and risk-accepted on record** — do not re-open either. **HD-1090** owes one grab started
   in Prowlarr's own UI, **HD-1091** the Soulseek→Lidarr bridge (Lidarr 3.1 has no Slskd download client at all),
   **HD-1088** the `music → Storage Box` leg, **HD-1092** the Authentik→NAS provisioning run that has never
   completed. (**HD-1089**, the SABnzbd locality read, is the same lane's subject but no brief claims the row —
   it is in the unbriefed list below.) → [prompt-media-arrs.md](prompt-media-arrs.md)
5. ⏳ **Cockpit, the coding seats, grants** — the cluster (**HD-361 · 411 · 442 · 443 · 444 · 465 · 495 · 1085 ·
   1110 · 1115**) with its owner-gated tails intact. **HD-495**: role-own the oldsrv seat's git plumbing — its
   **signing** half was retired 2026-10-08 by HD-1116, so a rebuild now recovers `gpgsign=false` instead of hanging;
   what is left to own is the transport key and the global `~/.gitconfig`. Its **SA-token leg** closed on 2026-10-09:
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
   ⚠ Never re-add `git commit -s`; signing is retired. **HD-1110**: `scripts/harness/pi-seat-sync.sh` is
   the one deploy path; its 2026-10-08 "oldsrv closed on all eight planes" reading is VOID — the driver ran only
   its first plane on an ssh leg until `bcf776ab` (HD-1110), and the cockpit re-verified genuinely green 8/8 on
   2026-10-09, so what remains is `install-pi-wsl.sh` **owning PATH persistence** (the WSL seat's own pi is
   fixed — `4677cd05` found a dead PATH shim hiding a healthy pinned-prefix pi 1.1.0, so the old "Volta shim"
   premise is history, not a task) and the Win11 `pi_auth` drift — the seat holds
   an **OAuth** openrouter entry where the spec renders `api_key`; mint it through the `pi_auth` vendor lane of
   [`scripts/harness/render-pi-config.py`](scripts/harness/render-pi-config.py) (§4 of [docs/pi-harness.md](docs/pi-harness.md)) and
   never overwrite a live token to green a check. → [prompt-seat-cockpit-grants.md](prompt-seat-cockpit-grants.md)
6. ⏳ **Storage, backup, the DR story** — **HD-191**'s ZFS policy units (**HD-1107**: the policy snapshots exist
   on every configured dataset and the generated unit's last fire is `Result=success`; the package's own
   `/etc/cron.d/sanoid` self-skips on a systemd boot, so the timer is the only scheduler. What that row owes is now
   the REPLICATION leg: `storage-syncoid.service` sits in `activating` on `destination already exists`, and sanoid
   defers pruning while a dataset is in send/receive), **HD-1105** (three enabled-but-dead units on nas), **HD-1106**
   (20 dangling VPS volumes, two with unverified provenance — not deleted), **HD-1093** (**owner**: rotate both
   family SMB passwords, then land them with `storage_samba_password_force` — a vault rotate alone changes nothing
   on the box), **HD-207** and **HD-238**. → [prompt-storage-backup.md](prompt-storage-backup.md)
7. ⏳ **The Pi's own box** — **HD-418** (the HA restart window, owner-gated; pair it with **HD-1103** so the box
   reboots once: `/var/log` is mode `1777`, so logrotate refuses every file nightly and no role owns the path),
   **HD-1109** (the HA standby IS cold-deployed; what has no proof is the takeover that promotes it),
   **HD-1101** (**open, not fixed** — the pi's resolver leg still has no shape guard of its own; the fail-loud
   assertion that landed with the oldsrv host-resolver leg is oldsrv-shaped and reads `nm_oldsrv_profile`, so
   nothing checks the resolver list the Pi writes ([docs/network-dns.md](docs/network-dns.md) §Host-side resolver)),
   plus **HD-04 · 434 · 438 · 439 · 319 · 17 · 217**. → [prompt-smart-home.md](prompt-smart-home.md)
8. ⏳ **Edge and identity** — **HD-147**'s browser-login tail, **HD-457** (which seat owns the family Immich library
   — an owner pick), **HD-458 · 459** (zipline, the published names), **HD-112**. ⏸ **HD-47** stays an owner act,
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
   legs stay in the row; **the two seat legs are run FROM the seats — `bash scripts/harness/pi-seat-sync.sh
   --check` and `install-tmux-conf.sh --push` on the win11 and `wsl -d Debian` seats, in their own sessions
   (2026-10-12)** — because a seat plane converges from its own clone and the station cannot speak for a seat's
   PATH; `install-pi-debian.sh --check` on a clean Debian seat is the third. **HD-1119** — the missing `harness`
   docs domain — is the only authored work the brief still carries, and it no longer gates the tree: folders are
   named for the toolchain each script drives, and the `gate/`/`lib/` exception is written into
   [scripts/README.md](scripts/README.md). **The registry's own prose is now a rule with a checker** —
   [`gate/check_registry_prose.py`](scripts/gate/check_registry_prose.py) is built and self-tested but left unwired while the
   rows still carry the ids and dates it refuses (`--show` prints the live count, never a number typed into a handoff), so the
   work is one sweep: clear the rows — ids, dates, diary tenses, the six rows that dropped their **Owning spec** cell, the
   `check_merge_markers.py` row's mangled divider span that leaves an unescaped pipe in the cell, the 42 Portability rows still
   naming pre-move paths, the stale `Layout` note and the `Last updated` footer — then add the `item_q` lines at floor 0 **in the
   same commit** that clears them. → [prompt-scripts.md](prompt-scripts.md)
12. ⏳ **Owner-gated tails** (exact steps in the rows): **377** the Grafana render re-do · **444** the phone-crossing
    drill · **418** the HA restart window · **HD-06** the UPS drill · **411** the cockpit resume word ·
    **HD-230/207** the decisions taken at the drill. ⏸ **HD-454 is ruled, not pending** (nothing is purchased and no
    out-of-band path is scheduled, so a switched-off `oldsrv` waits for presence; the one owner-side leg left is a WoL
    re-test at a planned power-off) and **HD-47** above.
13. ⏳ **Unrowed, but not free** — **HD-1100**'s held legs: both owner-authorized PG legs are DONE and verified
    (`litellm-db`, `authentik-postgres`), four middle legs stay held by owner ruling, and two things are still owed —
    the next `db-backup` run is the end-to-end proof the migrated clusters still dump, and **oldsrv still owes its
    `wireguard` leg** (it restarts the tunnel server, so run it alone, last, then re-verify every tunnel path).
    Rowless but not free: the **apt upgrade phase** stays OUT of the converge wave — ruled 2026-10-12 (option A), with
    `roles/common/tasks/apt-holds.yml` landing the `apt-mark hold` in IaC for the pinned packages (`alloy`, `tailscale`
    and the `docker-ce` suite; `kopia` ships as a pinned CONTAINER image, so there is no apt state to hold), and the
    `roles/updates` design is DECLINED, not pending. What is left is the live apply, one host at a time — until a host
    has run it, `apt upgrade` can still move its pinned packages there. → [todo.md](todo.md) HD-1146 · HD-1147.
14. **Decisions the last wave left open** (none has a domain brief; each is one call, and the evidence that makes it
    actionable is named with it). The gates named here are indexed in [scripts/README.md](scripts/README.md)
    §Validation gate, and every count a gate prints is re-derived by running it here, never quoted.
    - **Register the heading gate, price it, or leave it a tool.** `scripts/gate/check_doc_headings.py` exists and carries
      `--self-test`, and `bash scripts/validate-all.sh --list` prints no item for it, so a `§Heading` pointer that
      dangles reddens nothing at commit time while its path half (`check_doc_path_refs.py`) IS registered. The size of
      the debt is the last line of its own run, and the same tool copied into a worktree checked out at an earlier
      revision shows which way the trend moves; the three lawful answers are register it with a frozen baseline and
      refuse growth, run a clearing campaign, or keep it a tool and say so in the index. The owner picks: a lane that
      registers it has chosen for everyone. (Owning index: [scripts/README.md](scripts/README.md) §Validation gate)
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
      the 2026-09-23 Pi widening included. The live proof (a KNX `GroupValueRead` from the Pi plus the KNX reverse
      rule's counter) is owed in [todo.md](todo.md) HD-1143.
    - ✅ **The NAT reconcile, and what it removes — ANSWERED: list it.** The reconcile runs with
      `handle_absent_entries: remove` and `restrict: [srcnat, dstnat]`, so anything its own `data:` does not list comes
      off the device — and the Comtrend modem `srcnat` row is now LISTED there, as the byte-twin of the converge's, so
      neither writer can drop it. Narrowing `restrict:` was weighed and declined. What remains is the live apply
      (merge-only so far, the router slot is global) in [todo.md](todo.md) HD-1142 — read the before/after from the
      device, never from the import's exit code.
    - **Promote the string-purge gate, or keep calling it advisory.** `corpus_diff.py` and its signed accepts list
      live OUTSIDE this repository, so `validate-all.sh` cannot register them and deleting an accept entry narrows the
      check while the suite stays green. Re-derive that for yourself: `bash scripts/validate-all.sh --list` grepped for
      corpus answers nothing, and `scripts/corpus_diff.py` does not exist in this tree, because the tool and its
      accepts list run from a lane directory a fresh clone does not have. Promotion takes three things, in this order:
      the tool in-tree with both its run and its `--self-test` registered; a pinned baseline naming the compared
      revision and carrying a digest of what was compared, with the staleness refusal `scripts/gate/check_string_twins.py`
      already has; and the accepts list in-tree under the canary discipline of
      `scripts/gate/iac_identifier_allowlist.txt`, so that deleting an entry reddens instead of quietly narrowing. Until all
      three land, a corpus-diff verdict is per-commit and hand-run, and a green one is evidence about that run only -
      it is not a gate the suite ran. (Owning index: [scripts/README.md](scripts/README.md) §Validation gate)
    - **Retire the RB4011 deltas — the only act that frees the `comment=` strings still carrying ticket ids.**
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

15. ⏳ **The gate's own speed on a Windows seat** — **HD-1135** landed the fork diet (gate 134 s → 78 s measured
    interleaved on the Win11 git-bash seat, `$(<file)` proven to be as blind to CR as plain `grep` was) and gave
    `sync-skills.sh` the `--self-test` its encoding guard had been waiting on (teeth proven by mutation, both
    siblings now share one guard). **Tails:** the string-twins leg reads green at the merged tree —
    `scripts/gate/twin_baseline.txt` was re-published at the HD-1118 × HD-1135 merge, the wave boundary both lanes
    waited on (2289 → 2300 groups, 12 added / 1 dropped), an act that became safe anywhere in a wave when that lane
    gave the gate's own positive control a `CONTROL_BASE_REV` of its own — and the diet itself stayed. What that merge
    *adds* is the opposite bill: `scripts/lib/pi-seat.sh`'s single `pin()` is the fork-based body and
    `hl_owner_path()` runs a `find` per plane, so part of the diet is re-bought (`pi-seat-sync --self-test` 46 s,
    `pi-settings-config --self-test` 97 s, whole gate 398 s on that seat) — and `check_doc_path_refs.py` still crashes
    when a human runs it with `py -3` on that seat while staying green inside the gate. Record: [scripts/README.md](scripts/README.md)
    `validate-all.sh` + `sync-skills.sh` rows.

**Unbriefed open rows** — no session launches from them; they live in [todo.md](todo.md) and every view. The full
list is **derived** in [todo-table.md](todo-table.md) §B0, so only the ones an owner or a
lane should not lose are named here: **HD-357** (the launchpad tiles — the family-surface brief was retired and
**no domain brief took this row**; the work is wiring, and it wants a promoting decision, not a re-scope) ·
**HD-1083** (the routed group's routes→`*_url` half, owner-present edge window — read §Reachability rule in
[docs/services-traefik.md](docs/services-traefik.md) before touching a route or a publish) · **HD-1089** (one read
from a real tailnet client; the fix is live) · **HD-1116** / **HD-1117** (the two gate halves of the same hygiene
pass: the non-`oldsrv` Debian seats still carry `gpgsign=true` until they converge, and
`render_network_addresses.py` stamps a wall clock into a tracked file so its `--check` can never be clean) ·
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
