# `prompt-smart-home.md` — Lane brief · HA primary/standby, KNX, failover, the Pi's box hygiene

> **Role:** dispatch note for **one** lane session on the smart-home domain. **The rows are the authority** for what is
> missing and how to do it — this file carries the contract, the order of work and the traps, nothing else:
> [todo.md](todo.md) **HD-04 · HD-418 · HD-434 · HD-438 · HD-439 · HD-319 · HD-1109 · HD-1103 · HD-1101 · HD-1167 · HD-1127 · HD-1205**
> (row ids as of `c13e30f6` — re-derive with `grep -c "^| HD-<id> " todo.md` before quoting one).
> **Linked from:** [todo-table.md](todo-table.md) §B0 · [todo.md](todo.md)

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O11) — read it once; it overrides README §4 and
CONVENTIONS §6 at the items it numbers and this brief deliberately restates none of them.

**Converge hosts + slots (O3):** the **Pi** (the only HA that exists today, plus its box hygiene) and **oldsrv** (the standby
+ the edges) — one converge in flight per host, detached, **never `--diff`**. HD-438's firewall delta needs the **router**
slot, which is **global**: holding it blocks every other router change, so sequence it rather than bundling it.
⛔ **Do not share a wave with another oldsrv lane** (same containers, same `home_assistant` converge). **One Pi window carries
the Pi's whole residue**: the boot that makes the fstab `mode=` true on the mount line (HD-1103), the **UNTAGGED** `ai_diag`
leg that applies the derived smartd mask, HD-1167's one-time keyfile re-render, and HD-443's Pi `admin` revoke —
`access_admit_extra` still lists `admin` in `host_vars/pi.kogler.si.yml`, so that revoke rides the same visit (the row stays
the seat lane's). ⛔ The `nm-resolver` applies (HD-1101) and HD-418's reconcile have already run: do not re-run them.

**Read first:** [docs/smart-home.md](docs/smart-home.md) → [docs/smart-home-failover.md](docs/smart-home-failover.md)
(gaps + the drill record) → [docs/smart-home-rejected.md](docs/smart-home-rejected.md) before re-proposing anything →
[docs/home-assistant-current.md](docs/home-assistant-current.md) → [docs/hardware.md](docs/hardware.md) for the Pi's SD budget.

## Order of work

| # | Row | Do | Gate / trap |
|---|-----|----|-------------|
| 1 | **HD-1109** | The standby is **UNDEPLOYED**, not cold-deployed. Read what `roles/home_assistant` **intends** against what the `ha_standby_*` vars render, then run the cold create: `… playbooks/home_servers.yml --limit oldsrv --tags ha_failover`, detached, owner-scheduled (its `authorized_key` task writes SSH keys). ⛔ Probe it with `docker compose -f /opt/home-assistant-standby/docker-compose.yml ps`, never `systemctl is-active keepalived` — that unit's `inactive` is the CORRECT read, the VRRP half is the container | State the host before a standby result means anything: a systemd or file-presence probe answers about the box you ran it on, and this contract has two. `ha-failover.sh forward` does not start a standby, it **creates one under outage conditions** — so never describe failover as live from the recorded drill; no direction has ever been executed. While the standby is the live node it is not converge-safe (`docker_services` runs `compose down` on that path) |
| 2 | **HD-418** | Reconciled at both ends and **owned in IaC** (`roles/home_assistant/tasks/pi.yml`, tag `hd418`): the write compares the `.storage/http` object HA actually enforces against the rendered list. The **request** is the instrument (`200` = trusted, `400 untrusted proxy X` = the missing address), never the YAML. Two reads are owed, both shape-dependent: the takeover-shaped request **taken from the oldsrv edge**, and the XFF-present → `200` read through the `traefik-internal` middleware (`ha-ts-strip-forwarded` stays until that read is taken) | ⛔ It restarts the smart-home controller (voice outage): authorised **unattended in the overnight window**, with one read of HA's active conversations first. The takeover-shaped read is **PARKED** (O4): it waits HD-1109's cold create, because there is no takeover to shape a request while no standby exists. ⛔ The reconcile is done — do not re-run it, and do not "correct" `routes.yml.j2`, whose comment already says what the object carries |
| 3 | **HD-1103** | The mount and the mode are **owned in IaC** already (`roles/home_assistant/tasks/pi.yml`: the fstab line carries `size=100m,mode=0755`, the applied mount is read with `findmnt --target` under `check_mode: false`, the directory is reconciled to `0755 root:adm` only when the measurement disagrees). The ruled retention leg is **the role renders the file that owns these paths and asserts it is the file in force** — `/etc/logrotate.d/rsyslog`, the packaged rsyslog Conffile, with only `weekly`→`daily`, `rotate 4`→`rotate 1` and `maxsize 25M` changed (`logrotate-rsyslog.j2`, tags `pi_sd_trim,hd1103`), proved by a real `systemctl start logrotate.service` whose `.1` files land inside the mount | live-verified 2026-10-30: dry run `(4 rotations)`+`weekly` → `(1 rotations)`+`daily`+`log files >= 26214400`, one real rotation reclaimed 14M → 6.0M, second `--check` `changed=0`. ⛔ The `mode=` becomes true on the mount line at the **next boot** — never from a converge, never via `mount -o remount`. A SECOND role-owned logrotate file is not an option: logrotate refuses a path two stanzas name (`duplicate log entry`, exit 1, `logrotate.service` failed). The packaged stanza DID carry `compress` + `delaycompress`, and the bound it misses is the newest generation, not the copy count: `delaycompress` keeps `.1` uncompressed beside a live file of the same size, and one period's raw `syslog` here is 75,454,651 bytes against a 100 MB tmpfs (this period measures ~1M/day, 14M of 100M). `journalctl` silence is not proof; logrotate fails while exiting invisibly to `systemd-analyze` |
| 4 | **HD-1101** | Fixed **and applied on both hosts** — `--tags nm-resolver` ran on oldsrv and on the Pi, guard executing, `changed=0` both. On a keyfile host the **write** leg is `nm-pi`; `--tags nm-resolver` selects the guard, proves the check and writes nothing. ⛔ Do not re-run the applies | What this row still owes is ONE act, and it is another row's trigger: HD-1167's one-time re-render rewrites the file this guard checks, so when that owner-window act runs, re-read the `dns=` pair on the Pi and prove the SSOT pair survived it (`getent hosts ha.kogler.si` → the VIP, `getent hosts github.com` → a public answer), with the row's one-line `sed` + `nmcli connection reload && nmcli device reapply eth0` rollback standing by. ⚠ `dig` and `resolvectl` are BOTH absent on that box — `getent` is the resolver instrument. ⚠ Pass the fixture as `-e @"$PWD/scripts/…"`: `ansible-run.sh` cds to `IaC/ansible`, so a bare relative path is parsed as inventory and the guard is never reached |
| 5 | **HD-438** | Settle KNX end-to-end with a **positive instrument** — an entity that changes in the HA UI or the HA API — and account for the 2026-09-20 10:16 boundary (gate entered the template 2026-09-10, live rows dated later) | The `trusted-ha` widening is already folded into `IaC/router/templates/rb4011_converge.rsc.j2`; reachability was proven and is **not** the service. Never conclude from the absence of xknx timeouts, and never from raw UDP probes: the tunnel authenticates with a `user_id`, so unauthenticated `SEARCH`/`CONNECT` returns nothing from the healthy primary too |
| 6 | **HD-439** | The address-audit half is **closed by measurement** and shipped as `scripts/ansible/knx-hass-gen.py --check` / `--self-test` — keep that comparison honest, do not re-run the audit. What the row still asks is the **detection** half: alert on growth of the KNX interface's telegram counters, with the half-open interface (forwarded nothing while HA reported everything OK) as the incident it must catch | The detection leg cannot be wired while the HA exporter scrape is switched off (`alloy_ha_exporter`) — an alert today would be green-by-absence; the gating token belongs to **HD-04**'s tail. ⛔ A count quoted without the comparison that produces it is not a finding. Live acceptance is a HA reload with eyes on Settings → Devices, an owner-at-the-keyboard step |
| 7 | **HD-434** | Owner-present takeover-drill retest of KNX on the standby, once HD-1109 says a standby exists: bring it up, confirm a live tunnel via an entity that moves with the bus, and on failure read `xknx` for authorization vs no-channel vs no-route | The GIRA-router explanation was withdrawn — oldsrv has always been in `trusted-ha`. Do not re-run the probe class that produced it |
| 8 | **HD-04** | The two owner legs that remain: the GIRA-side KNX allowlist check on the standby, and the `ha.kogler.si` HTTPS-with-Pi-down gap | The forward takeover is proven; what no converge can prove is the standby driving the bus and an edge that survives the Pi |
| 9 | **HD-319** | Owner/verify: confirm the three rekuperator group addresses (12/1/*) answer on the bus (the `GroupValueRead` warnings are the only signal so far) | One positive read closes it; a warning count going down is not a read |
| 10 | **HD-1167** | First act is the read-only, both-sides, one-sitting comparison: `grep -v '^#' /etc/NetworkManager/system-connections/pi-eth0.nmconnection` against the non-comment lines of `IaC/ansible/roles/network/templates/pi-eth0.nmconnection.j2` with `host_vars/pi.kogler.si.yml` + `group_vars/all/main.yml` resolved — identical bodies means the `changed` is prose, which is the finding. Then make the render a no-op **in `roles/network`**, never on the host | ⛔ A `#`-line in a `.j2` is literal **output**, not a Jinja comment, so a reworded comment reports `changed` and fires the handler's `reload NetworkManager` on a DNS-tier box. A task that can only re-state an address must not be able to report `changed`. The one-time re-render is an **owner-window** act, never unattended, never `--diff`, with **HD-1101's written rollback standing by**. Read the same render on **spark** before calling the class closed — `nm_pi_profile` names `spark-eth0.nmconnection` there and it is unmeasured. The only file here is that Pi keyfile — `roles/network/**` otherwise stays the dns-transport lane's, so land it in this window rather than as a role sweep |
| 11 | **HD-1127** (P1) | Repair **entity exposure** on the HA that answers (the **Pi**; oldsrv only if a standby exists per HD-1109): check whether an area for the living room exists at all, define/repair the areas, and expose the room's actual temperature sensor(s) so a place-name question resolves | ⛔ The LLM leg works — do not re-litigate the gateway; the LiteLLM/voice leg is the litellm-consumers lane's and is referenced here, not carried. Acceptance is Assist answering with the right number, not a `GetLiveContext` that found candidates |
| 12 | **HD-1205** | Deploy the **ruled** Wyoming fronts — whisper.cpp STT (the same model file + sha256 the `whisper` leg already holds) and Piper on CPU, on **oldsrv** — name the network leg (unauthenticated TCP, `llm-backend`, publishes nothing today), then the two `wyoming` config entries and `stt_engine`/`tts_engine`/`tts_voice` on the pipeline; with the front proven, the `whisper` registry row and the `local-stt` row drop **in the same converge** | ⛔ The ruling **retires** the `whisper`/`local-stt` leg rather than running beside it (co-resident they cost ~3.6 GiB of 8); no other STT image is a candidate, and a Vulkan miss lands on the CPU rung, not on a re-decide. The Vulkan leg's acceptance is a timing number plus the ICD name, never a container that is `Up`; the `local-stt` row sits in the litellm-consumers lane's file, so name it rather than editing it |

## ⛔ Traps that cost a round

* **HA's header trust is exact-match, and it fails loud-but-confusing:** any request carrying `X-Forwarded-For` from a peer
  outside `ha_trusted_proxies` gets a `400` from aiohttp, while the same request without the header gets `200`. The tailnet
  router only works because it **strips** the forwarding headers — so a green tailnet path proves nothing about the home edge.
* **Do not "add `oldsrv_home_ip`" from the row's wording.** `ha_trusted_proxies` in `IaC/ansible/group_vars/all/main.yml`
  already carries the oldsrv Home `/32`, and the Pi's enforced list is reconciled from it in IaC (HD-418). When you need what
  HA enforces, read the `.storage/http` object — the rendered YAML is not the source while `yaml_migration_done` is true.
  Keep the overlay-wide list in sync with the edge IP pin it mirrors.
* **KNX is authenticated.** Never infer reachability from unauthenticated `SEARCH`/`CONNECT` or from raw UDP; settle it with
  an entity that moves. Home→IoT (VLAN 20) is gated on the `trusted-ha` address list — HA tunnels from its own address
  (`local_ip: null`), so the HA host itself must be in it.
* **Positive instruments only** across this whole lane: a container being `Up`, a timer being enabled, a counter advancing, or
  log silence are all states that coexist with a broken service.
* A **router** delta goes alone (global slot) and arrives widening-only; the RB4011 import is device-wide, so never bundle it
  with an oldsrv or Pi converge.
* Converge the `home_assistant` role on the **active** HA host, detached, guarded, never with `--diff`; the standby stays cold
  until a takeover is the point of the run.

## Owns / never touches

**Owns:** `IaC/ansible/roles/home_assistant/**` (incl. `files/knx-entities.yaml` + `scripts/ansible/knx-hass-gen.py`), the `ha_*`
regions of `group_vars/all/main.yml` (`ha_trusted_proxies`, `ha_vip`) and of `host_vars/pi.kogler.si.yml` /
`host_vars/oldsrv.kogler.si.yml`, the keepalived + resolver legs on the Pi, the `trusted-ha` line in
`IaC/router/templates/rb4011_converge.rsc.j2` (router slot global), `docs/smart-home*.md`, `docs/home-assistant-current.md`,
and your own `todo.md` rows.
**Never:** `prompt.md` / `todo-table.md` (O2) or another brief's rows; the LiteLLM gateway, its keys and
`templates/docker_services/{lan-litellm,litellm}/**` (the litellm-consumers lane owns HA's LLM leg and the voice chain);
traefik edge/route work beyond the `ha` router your rows name (the transport lane); `roles/router/**` generally and the DNS
answer plane; `roles/monitoring/**`; the NAS/ZFS and backup rows; the frozen archives and generated `*-generated.md`.

## Acceptance

Every item returns `PASS` / `FAIL` / `BLOCKED` / `PARKED` + the number + the evidence path; a claim with no path counts as
not run. Concretely: the standby's state named from `docker compose … ps` **on oldsrv**, and the cold create either run or
parked with its exact blocked action · HD-418's two owed reads taken, or parked naming what each waits on (the
standby-shaped one waits HD-1109's cold create) · the new logrotate file in the role, rotation proven on the Pi by a real
`systemctl start logrotate.service`, the fstab `mode=` named as waiting the next boot, and `systemctl --failed` clean · the
resolver fixture still breeding a red on the Pi · KNX proven by an entity that moves, with the 09-20 boundary explained or
explicitly left unexplained · the render-vs-`.knxproj` comparison in tree · the drill legs either run and recorded or parked
as owner-present · every standby state read taken on the host that owns the unit — compose, not `systemctl` ·
rows deleted or trimmed to their tails, no history in the row · `bash scripts/validate-all.sh` green **in this worktree** → **stop**.
