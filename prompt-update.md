# prompt-update.md — the fleet pin bump + host-package window

> **Rows it carries:** none. This brief carries a maintenance window, not a queue — the work it orders
> belongs to the rows already open in the lane briefs it cites below, and no row is minted for the act.

> **Role:** the handoff for the fleet-wide pin refresh (container + host-APT) and the DGX Spark platform
> update that must land **before** the `fast8` arm is certified — the two enabling IaC fixes, the order the
> converges go in, the secret-rotation act that precedes them, and every trap named so a lane does not
> meet one cold. Named by the owner for the window; do not rename it under the §6 brief-naming rule.
> **Linked from:** nothing yet — the owner's entry point for this window. If a lane launches from it, its
> id set goes into [todo-table.md](todo-table.md) §B0 in the same change ([scripts/gate/check_brief_coverage.py](scripts/gate/check_brief_coverage.py)).

---

## 1. State this brief was written against

- The pin SSOT is [`IaC/ansible/group_vars/all/versions.yml`](IaC/ansible/group_vars/all/versions.yml); the
  rule is [CONVENTIONS.md](CONVENTIONS.md) §7 and the mechanism is
  [`IaC/ansible/roles/common/tasks/apt-holds.yml`](IaC/ansible/roles/common/tasks/apt-holds.yml). There is no
  automated upgrade phase on any host — a refresh is a hand edit + a deliberate converge, and Renovate still
  points at a test repo ([todo.md](todo.md) HD-264).
- Live held sets: oldsrv 8, pi 8 (`alloy`, `tailscale`, the six-package docker family), vps 7, spark 7,
  nas 1 (`alloy` only). Every box sits at its pin, so the fleet is in sync before the window and
  `homelab_pkg_pin_result{result="differ"}` is empty ([docs/observability.md](docs/observability.md) §Pin-lag report).
- spark sits at kernel `7.0.0-1019-nvidia` / driver `580.178.04` / DGX OS OTA level 7.6.0, and the offered
  OTA `OTA2610` moves **no kernel image and no GPU driver** on this box: its real delta is `dgx-dashboard`,
  `dgx-oobe{,-desktop}`, `nvidia-dgx-telemetry`, `nvidia-spark-mlnx-firmware-manager`,
  `nvidia-disable-aqc-nic` plus two NEW packages (`nvidia-spark-grub-kho` adds `kho=off` to the kernel
  command line; `nvidia-spark-cloud-init` configures a NoCloud `OEMDATA` datasource). It is a reboot-scoped
  platform act, not an engine act.
- The `fast8` arm is still gate-blocked on the empty `spark_vllm_ultrafast_v32_image`; its next act is the
  §7b anchor census of [spark/reports/hd1206-v32-port-20261026/README.md](spark/reports/hd1206-v32-port-20261026/README.md),
  not another build attempt ([todo.md](todo.md) HD-1206, [prompt-spark-llm.md](prompt-spark-llm.md)).

## 2. Fix these two FIRST — the window is not runnable without them

**(a) Two pinned-and-held packages have no lift leg, so a pin bump fails the converge.** The `apt` module
always passes `-y`, and apt refuses to move a held package under `-y`:

```
apt-get -s -y install alloy=1.21.0-1   →  E: Held packages were changed and -y was used without --allow-change-held-packages
apt-get -s     install alloy=1.21.0-1  →  Inst alloy [1.20.1-1] (1.21.0-1 …)
```

`roles/docker` is the only role that lifts (unhold → versioned install → re-hold in `always`, asserted):
[`IaC/ansible/roles/docker/tasks/main.yml`](IaC/ansible/roles/docker/tasks/main.yml). The other two name the
package at a pin and never lift:

- [`IaC/ansible/roles/monitoring/tasks/main.yml`](IaC/ansible/roles/monitoring/tasks/main.yml) — `name: "alloy={{ alloy_version }}"`
- [`IaC/ansible/roles/tailscale-node/tasks/main.yml`](IaC/ansible/roles/tailscale-node/tasks/main.yml) — `apt: deb: …tailscale_<ver>_<arch>.deb`

Port the docker block (lift **only** the names this run moves, re-hold in `always`, assert `apt-mark showhold`)
into both roles, and add the both-directions assert `roles/docker` carries so a future pin cannot again be
held by a role that cannot move it. ⛔ Never `--allow-change-held-packages`, never a blanket
`apt-mark unhold $(apt-mark showhold)` — both are documented refusals in
[docs/deployment-ansible.md](docs/deployment-ansible.md) §Role Catalog.

**(b) `scripts/ansible/image-pin-probe.py` cannot find the pin file.** `DEFAULT_ROOT` joins one `os.pardir`
where the `scripts/` foldering needs two, so every documented invocation dies with
`FileNotFoundError: <repo>/scripts/IaC/ansible/group_vars/all/versions.yml` — including `--debs`, which is
the tool that fetches the tailscale digests this window needs. One-line fix in that file. Workaround for a
run in the meantime: `--file IaC/ansible/group_vars/all/versions.yml`.

Also unaddressed and worth a follow-up: the probe's `SOURCES` table has no entry for
`docker_ce_version`, `containerd_io_version`, `docker_buildx_plugin_version`, `docker_compose_plugin_version`,
so the tool is blind to exactly the host-APT family this window moves. Their values came from the vendor
indexes instead (download.docker.com `trixie/{amd64,arm64}` + `noble/arm64`, apt.grafana.com
`{amd64,arm64}`, pkgs.tailscale.com).

## 3. The pin set

Derive, do not remember: `python3 scripts/ansible/image-pin-probe.py --verify` (3-day hold, mirrors
`renovate.json`, [docs/deployment-renovate.md](docs/deployment-renovate.md) §Manual pin refresh). Buckets at
the last derivation: 23 current, 16 patch, 34 minor, 7 major, 4 date-ordered **downgrades**.

**Host-APT (the maintenance-window part; every value verified published for all three suites in the fleet):**

| var | now | target |
|---|---|---|
| `docker_ce_version` | `5:29.8.2` | `5:29.9.2` |
| `containerd_io_version` | `2.3.6` | `2.4.2` |
| `docker_buildx_plugin_version` | `0.37.1` | `0.38.1` |
| `docker_compose_plugin_version` | `5.5.1` | `5.6.1` |
| `alloy_version` (deb pin — the hyphen means an EXACT compare) | `1.20.1-1` | `1.21.2-1` |
| `tailscale_version` **and** `tailscale_host_version` | `v1.102.5` / `1.102.5` | `v1.104.2` / `1.104.2` |

⚠ `tailscale_host_version` moves **only** with `tailscale_host_deb_sha256_by_arch` re-fetched in the same
commit (`image-pin-probe.py --debs` after the bump); a transcribed or neighbour-release digest passes every
offline gate and dies at `get_url`'s checksum gate mid-play. The two versions are one fact: a host node and a
sidecar must not speak different wire versions.

**Container pins — ruled (owner): patch + minor, flagged rows named one by one.** Take the 16 patch + 34
minor rows, **excluding** every one flagged in §5; `keepalived` and `technitium` run as their own mini-windows
(VIP and DNS), `headscale`/`headplane` behind `scripts/ansible/guarded-converge.sh`, `ollama -rocm` as its own
mutable-alias decision, `home_assistant` only after the breaking changes for the releases crossed are read.

**Do not touch, in the same commit or any other:**

- the 7 majors — `forgejo 16→17`, `onlyoffice 9→10`, `forgejo_db`/`onlyoffice_pg`/`zipline_db` postgres
  `16.15→18.4`, `onlyoffice_rabbitmq 3→4`, `tube_archivist_redis 7→8`. A data-format major is a migration,
  not a restart.
- the 4 downgrades the probe reports because it orders by date: `authentik_db 18.6→18.4`,
  `litellm_db 18.6→18.4`, `radarr 6.4.4→6.3.0`, `pairdrop 1.11.2→1.11.1`. Pinning a downgrade is refused
  anyway (`--allow-downgrades` is forbidden), so leaving them is the only correct move.
- every digest-pinned `*_image` (`spark_vllm_image`, `spark_vllm_ultrafast_image`,
  `spark_vllm_v32_base_image`, the dcgm/llama.cpp/whisper images) — CONVENTIONS §7.
- `spark_vllm_ultrafast_v32_image` and `spark_sglang_image`: an EMPTY pin IS the gate. A refresh that
  "fills in" an empty pin has opened an uncertified engine arm.
- ⚠ A pin value is the HIGHEST release already running somewhere in the fleet, not the newest upstream
  (the header comment in `versions.yml`). No box runs the docker `29.9.x` family yet, so this bump is first
  contact for the whole fleet at once — which is exactly why §6 converges one host before the others.

## 4. The tombstone (spark)

`group_vars/spark.yml` carries a `dgx-dashboard` entry with `enabled: false` so the teardown and
disable-boot legs keep the retired socat stack dead; the ⏳ in [docs/hardware-spark.md](docs/hardware-spark.md)
§Remote management says delete it once the teardown has run green twice. Live on the box: no dgx container,
no `docker-compose@dgx-dashboard` symlink in `multi-user.target.wants`, the unit reads `disabled` through the
Ansible-managed template — and `/opt/dgx-dashboard/{docker-compose.yml,.j2}` still exists, regenerated by the
vendor package rather than owned by it.

**Ruled (owner): mask, then delete.** Add a mask of `docker-compose@dgx-dashboard.service` to the `spark`
role — the role already masks with `systemctl mask --now`; masking, not disabling, is what survives a package
upgrade ([docs/deployment-ansible.md](docs/deployment-ansible.md) §Role Catalog) — then delete the registry
entry and rewrite the doc sentence so the mask is the named guard and the ⏳ is gone. Generalizing the mask to
every `enabled: false` entry in `docker_services` was offered and not taken: that is a design change, not a
tombstone fix. Nothing in §2 or §4 is implemented yet — **this brief is an instruction, not a record**; the
next session writes both, in one gated change.

⛔ Do not delete `/opt/dgx-dashboard` while the unit is merely disabled: a re-enabled unit whose directory is
gone fails at `CHDIR` on every boot, forever. Masking is what makes that state harmless.

## 5. Owner rotation of the exposed secrets — before the converge, in this order

The contract is [docs/deployment-secrets.md](docs/deployment-secrets.md) §Creation & Rotation Workflow.
**Derive the list from the gate, not from the ledger:** the ledger is a debt register of what was seen where,
and the live run carries both halves the book has not caught up with — `python3 scripts/gate/check_secret_leak.py`
prints `KNOWN-EXPOSED` (ledgered), **`STALE ledger lines`** (the hit is gone; only deleting the line ends that
report, `--update-ledger` will not drop a line it cannot prove), and **`FAIL: … hit(s) outside the ledger`**,
which is the actionable list. The window starts with that item RED, so `validate-all.sh` cannot go green until
the rotations land: schedule it that way, do not chase it as a regression of the pin change.

Rotating "everything exposed" as one act is not safe, because a vault write propagates only where propagation
exists. Sort it into three piles before touching anything:

1. **Vault + converge is enough** (catalog items, propagation exists): the arr/media tokens, the Victoria
   basic-auth pair, `soulseek-internal_api`, `qbittorrent_api`, `crowdsec-*`, `immich-ml-internal_api`,
   `n8n-webhook_api`. Rotate with `provision-secrets.py --rotate <item> --yes`, then converge the service.
2. **Vault-only rotations that silently diverge** — `NOT_AUTO_ROTATABLE` in
   [`scripts/secrets/provision-secrets.py`](scripts/secrets/provision-secrets.py). These need the value
   changed at the OTHER end first, by a human, per item: the arr instance keys (`sonarr_api`, `radarr_api`,
   `lidarr_api` — the instance's own `config.xml` `ApiKey`), `network-snmp_api` (re-apply on router + switch by
   hand), `kopia-server_fingerprint` (regenerate the cert and re-pin both sides), `pppoe_login` (ISP side),
   `openrouter_api`/`entrim_api`/`opencode-go` (provider console, then re-render **every** harness client, not
   just restart LiteLLM), `wg_password` (a `wg genkey` value, never a generated password), the Soulseek
   network login. Rotating any of these vault-only breaks the consumer until the device/app is re-keyed.
3. **Ordered fleet items** — see the ladder below; they cannot be rotated "just before" anything.

The un-ledgered set the live run names, with what each rotation actually costs — read this before choosing a
time, because two of these are not secrets you can simply re-issue:

| item | rotation costs |
|---|---|
| `victoria-metrics_api`, `victoria-logs_api` | rotatable (catalog), but every consumer re-renders: Alloy `remote_write` + log push, both Victoria MCP servers, and the **Grafana datasources**, whose password lives in Grafana's own store — verify whether those datasources are file-provisioned here before calling the rotate done |
| `cockpit-pi-web_api`, `ha_api`, `privado-vpn_api` | pi Cockpit grant / HA long-lived token / an external VPN account: HA's token and the VPN account are re-entered at their end, not generated |
| `admin @media.kogler.si`, `admin @radarr.kogler.si`, `bazarr_api` | instance-side logins and a consumer-side copy of Bazarr's `auth.apikey` — change it inside the app, then the vault, then re-converge (`--rotate` on these writes a value the app never issued) |
| `n8n_password` | **`N8N_ENCRYPTION_KEY`, documented immutable**: rotating it invalidates every credential stored in n8n's DB unless they are re-encrypted. Rotate it only as a deliberate act with the workflows re-entered |
| `kopia_password` | the **repo master password on a live repo** — rotation is a re-key of the backup chain and every client, not a password change |
| `oldsrv-domen_login` | a human account password on a box: rotate on the host and in the vault together, with a second live session open, and never as the last act before an unattended reboot |
| `wifi-kogler_password`, `wifi-kogler-guest_password` | **live PSKs** on VLAN 10 / VLAN 30 — rotating re-joins every device on those SSIDs, family-wide, and the kids' devices ride `Kogler`. `routeros_capsman_enabled` is `false`, so nothing in IaC writes these values: it is a hand edit on the router plus the vault, on its own day, not a window step |
| `wifi-kogler-iot_password` | a **live** PSK on VLAN 20 — the Gen1 Shellys live there, and every one of them is re-provisioned by hand or over its own app |
| `wifi-kogler-iot-wan_password` | the VLAN-21 SSID is deleted and the item is referenced by no config ("do not re-mint"): rotating it changes nothing on the fleet — say so in the ledger line instead |

**Ruled (owner): rotate everything the gate names**, the 15 un-ledgered items included — so the three
expensive ones are scheduled, not skipped: re-enter n8n's stored workflow credentials around the
`N8N_ENCRYPTION_KEY` change, treat `kopia_password` as a backup-chain re-key across the server and every
client with the repository verified afterwards, and give the live Wi-Fi PSKs their own hour because every
device on those SSIDs rejoins by hand. Then `check_secret_leak.py --update-ledger`, delete the STALE lines by
hand, and commit the shrunk ledger — that commit is what makes `validate-all.sh` green again.

The ladder, in the order that works:

- `op_api` first or last, never in the middle: it is the read credential every control node and seat uses for
  every vault lookup. Rotating it before a converge without re-seating every seat and control node makes the
  converge fail at the lookup, and the ledger pair for it closes only when every seat has re-seated.
- `spark-llm_api` / `litellm-engine_api` (the git-history exposure) are **guard-listed**: the engine's
  accepted-key list lives in vLLM's argv, so the order is rotate → converge spark (engine restart carries the
  new accepted list) → only then re-render both gateways. Inverting it 401s every gateway call upstream
  ([todo.md](todo.md) HD-384, [docs/services-ai.md](docs/services-ai.md) §4). It also means this rotation and
  the `fast8` flip should be **the same spark act**, not two engine restarts.
- `*_db` items whose service carries `db_role_sync: true` (all of: `authentik_db`, `onlyoffice_db`,
  `immich_db`, `forgejo_db`, `zipline_db`, `litellm_db`) DO propagate: the converge compares the role's
  `COMMENT ON ROLE` marker against `pgsync:<sha256>` and ALTERs. Rotate in the vault, converge the VPS once.
  ⛔ A hand-run `ALTER ROLE` is out of band and is NOT repaired — it desyncs the marker.
- `pgvector_db` has no IaC consumer today; immich's cluster is role-synced under `immich_db`. Confirm which
  item the live role actually carries before rotating this one.
- `spark_login` is the DGX console/break-glass password and is not consumed by Ansible. Rotating it is a
  console act on the box, it belongs to the human vault, and it must not be rotated on the same day the box
  is expected to boot unattended.
- NUT (`nut_password`, `nut-exporter_password`): master is `nas`, clients are oldsrv + pi — one act, all
  hosts, or the clients lose the master mid-window.
- After the rotations: `python3 scripts/gate/check_secret_leak.py --update-ledger`, then commit the shrunk
  ledger. Un-rotated lines print STALE on every run, and a line whose hit is gone prints stale until it is
  removed — that is the proof, not a mute.

## 6. Order of the window

1. Run `python3 scripts/gate/check_secret_leak.py` and read its `FAIL:` block: that is the rotation list, and
   the leak item is RED until it is done — so it leads the window rather than trailing it.
2. Land §2 (both lift legs + the probe fix) and §4 (tombstone) in one gated change; `bash scripts/validate-all.sh`
   green except the leak item until step 4.
3. The pin commit (§3) — a version edit, reviewable on its own.
4. The rotations (§5), in its ladder order; then `check_secret_leak.py --update-ledger`, delete the STALE lines,
   and commit the shrunk ledger in the same change. Only now is the fleet renderable against final values.
5. Converge the canary docker host (pi or vps), read the fleet gauge back to empty, watch `RestartCount`;
   then oldsrv, then nas, then **spark**. Moving the docker family restarts the daemon, so every container on
   that host moves with it — one host at a time, never an incidental side effect of another run.
6. Router/switch items (SNMP, WG, PPPoE, NUT clients) after the Debian hosts, on the router slot, which is global.
7. **spark last, in this order: OTA → reboot → the pin converge → the lineage build → the probe → the flip →
   gates.** The swap that matters: the build is a `docker build`, so run it on the bumped
   `docker-buildx-plugin`/`containerd.io`, not on the toolchain that is about to be replaced. The flip stays
   the last and solo act so the certification measures the final platform ([docs/spark-llm-profiles.md](docs/spark-llm-profiles.md) §7).
8. Only after gates: revisit `spark_llm_profile` and the bench numbers. A later platform change re-opens the
   question the gates closed.

## 7. Traps (each one costs a lane a window)

- **⛔ Two lanes on the spark converge slot.** `docs/orchestration.md` §4 O3: one converge in flight per
  host. The `spark-v32-build` lane holds it; the pin converge and the OTA-then-converge are the same slot.
- **spark's engine cold boot is ~20 min** (`start_period: 1200s`, first PLE-table load). The OTA reboot and
  the flip's converge are two of them; probe **on the box** (`curl -sf localhost:8000/health`), never through
  the edge, which 502s for reasons that are not the engine's.
- **`traefik-spark` is the `llm.kogler.si` name edge** and is in the restart-guard exclusion list because a
  restart is a 502 window on inference. A docker-daemon upgrade restarts it regardless of that exclusion —
  schedule it, do not discover it.
- **spark's build cache**: each build attempt that reaches the layer steps costs ~12 G of cache on `/`, and
  nothing has been pruned. Re-read `df -h /` and `docker system df` before another attempt, and expect the
  containerd bump to change what buildkit keeps.
- **spark's post-OTA boot checks** (the OTA is invisible to `--check`, because it is outside IaC): the kernel
  command line gains `kho=off` from `nvidia-spark-grub-kho`; `nvidia-spark-cloud-init` writes
  `cloud.cfg.d` drop-ins that read a USB volume labelled `OEMDATA`; `nvidia-spark-mlnx-firmware-manager` is
  `enabled` and its 6.x bump runs a firmware pass at boot; the headless masks and `multi-user.target` must
  survive; the GPU clock cap re-applies via `spark-gpu-clock-cap.service`; `jupyterlab_ports.yaml` must still
  map admin → `11002`, which is the port the published route forwards; `dgx-dashboard.service` must stay the
  only dashboard unit and must stay loopback-bound. Re-derive [docs/hardware-spark.md](docs/hardware-spark.md)
  §Identity from the box after the reboot — kernel, OTA level, dashboard version, UEFI date, and QSFP delta #2.
- **nas's Alloy is stopped on purpose** ([todo.md](todo.md) HD-1164) and `roles/monitoring` ends with "Ensure
  Alloy service is running". The pin converge will start the collector that dies in seconds. Decide before
  the converge: converge nas's monitoring role and stop the unit again, or hold nas out of the alloy leg.
  `check_host_reporting.py --check` reads red for nas either way; that red is the instrument working.
- **The tailnet is two acts, not one**: `tailscaled` on oldsrv + pi, and `headscale`/`headplane` on the VPS.
  Run the headscale/headplane leg behind `scripts/ansible/guarded-converge.sh` (the pinned headscale
  crash-loops when `dns.extra_records` and `dns.extra_records_path` are both set, and `Running=true` between
  crashes is not liveness). `keepalived` and `technitium` each move a control plane of their own — VIP and DNS
  respectively, three live seeded instances on the DNS side.
- **`home_assistant`** minors are release-train jumps: read the breaking changes for the versions crossed
  before the pin moves, and remember its config entry holds plaintext that rsyncs to the oldsrv standby
  ([todo.md](todo.md) HD-1093's neighbour; [docs/smart-home-voice.md](docs/smart-home-voice.md) §Runtime plaintext).
- **`ollama_version` is a fluid `-rocm` alias** and the jump is large: §7 allows a mutable alias only with a
  recorded MUST-pin + verified semver. Treat it as its own decision, not part of the sweep.
- **A held package is not a pinned package.** After each host converges, assert `apt-mark showhold` still
  lists the whole set for that host; a suite left unheld converges green and drifts on the next `apt upgrade`.
- **The gauge goes red on purpose between the commit and the converges.** `homelab_pkg_pin_result{result="differ"}`
  non-empty is the window in flight, and an empty read is not fleet health — a host that publishes nothing
  contributes no rows ([docs/observability.md](docs/observability.md) §Silent-failure hygiene).
- **The engine arm must not be flipped to certify a package bump.** The flip is one ~20-min boot and the only
  downtime in the spark sequence; rollback is `spark_llm_profile: fast` + a detached converge, with the
  rollback images held by `spark-rollback:fast` and archived on the nas.
- **Live converges run detached** (`nohup … &` + a log, then poll). A foreground run behind an outer timeout
  gets killed mid-restart and leaves siblings `Exited`; `--check` is the only safe foreground form
  ([scripts/README.md](scripts/README.md) Notes & conventions).
- **The window is not green when it starts.** `check_secret_leak.py` fails at the tip with current values
  readable in old session transcripts, and no amount of editing a transcript closes it — only rotating does.
  Do not mute it, do not `shred` the capture, do not call the window done with that item red.
- **No new row for this work.** If the window mints anything, it is a `⏳` on a row that already exists, not a
  fresh `HD-`; the register's mint space is derived, never typed ([todo.md](todo.md) §0).

## 8. Verify before closing the window

```bash
python3 scripts/ansible/image-pin-probe.py --verify      # every pin vs its registry, current tag exists
python3 scripts/ansible/image-pin-probe.py --debs        # tailscale digests vs the vendor .sha256
bash scripts/validate-all.sh                             # green, from the worktree
for h in oldsrv vps nas pi spark; do ssh $h 'hostname; sudo -n apt-mark showhold | tr "\n" " "; echo'; done
```

Then, per host: the service roster is up, `RestartCount` is flat, the pin gauge is `match`, and the pin-lag
alert (`homelab_pkg_pin_result{result="differ"}`, 30 m) has cleared. On spark additionally: `/proc/cmdline`,
`nvidia-smi` driver version unchanged, masks + `multi-user.target`, the clock-cap unit ran, the tombstone's
boot unit is masked, `llm.kogler.si/health` 200.

## 9. What the next session must not re-decide

Ruled (owner), do not re-open: **mask-then-delete** for the tombstone (§4); **patch + minor** for the pin
sweep with the flagged rows decided individually (§3); **rotate everything the gate names**, with the n8n,
kopia and Wi-Fi consequences scheduled rather than avoided (§5). No row is minted for any of it (§7).

- The fleet pins one value per package across suites; a per-host override is drift, not a second shape.
- Majors and downgrades are OUT of this window (§3), by the rule, not by omission.
- Masking replaces the tombstone (§4); deleting the registry entry without naming the guard is the half-fix.
- Rotating a `NOT_AUTO_ROTATABLE` item vault-only is a divergence, not a rotation (§5).
- The spark sequence is OTA → converge → build → flip (§6); the build never runs on a toolchain that is about
  to be replaced, and no platform change lands after the gates.
