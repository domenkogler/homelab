# prompt-update.md — the fleet pin bump + host-package window

> **Rows it carries:** none. This brief carries a maintenance window, not a queue. The rows named below are
> **ridden, not carried** — each keeps its own owner and its own brief (§11); no row is minted for the act, and no
> ownership moves here. The `todo-table.md` §B0 wiring is part of the final `prompt-*.md` pass (Phase 8).
> **Role:** the runbook for the fleet-wide pin refresh (container + host-APT), the exposed-secret rotations that
> precede it, the converges that apply it, and the spark platform update + profile flip that close it — executed
> **phase by phase from the WSL Debian seat** (§10) with the owner present. Every act is a box; Phase 8 ends with
> this file deleted.
> **Linked from:** nothing yet — the owner's entry point for this window.

---

## 0. How to run this file

- A phase is **done** when every box in it is ticked; tick a box only on its own host/slot, and never tick a converge box on a `--check` verdict (§7). One converge in flight per host (O3); live ones run **detached**, `--check` first, ⛔ never `--diff` (§7).
- **`todo.md` is updated once per phase**, after that phase's last box — the fold-in rows' `⏳` tails and the rotation ledger, not per task. ⛔ No `HD-` is minted for anything in this file (§7).
- The **last content act, before this file dies, is the `prompt-*.md` pass** (`prompt.md` + the briefs whose rows the window touched) — once, at the end, not per task. Phase 8 holds the order, ending with this file deleted.

## 1. State this brief was written against

- Pin SSOT: [`IaC/ansible/group_vars/all/versions.yml`](IaC/ansible/group_vars/all/versions.yml); rule [CONVENTIONS.md](CONVENTIONS.md) §7; mechanism [`IaC/ansible/roles/common/tasks/apt-holds.yml`](IaC/ansible/roles/common/tasks/apt-holds.yml). No host has an automated upgrade phase — a refresh is a hand edit plus a deliberate converge, and Renovate still points at a test repo (HD-264).
- Every Debian host sits at its pin with the whole set held (`hi` in `dpkg -l`, live-verified on all five): oldsrv 8, pi 8, vps 7, spark 7, nas 1 (`alloy` only — `nas` runs no Docker), so `homelab_pkg_pin_result{result="differ"}` is empty before the window ([docs/observability.md](docs/observability.md) §Pin-lag report).
- spark: kernel `7.0.0-1019-nvidia`, driver `580.178.04`, DGX OS OTA level 7.6.0, `/` 165 G free, up 5+ weeks. The offered OTA `OTA2610` moves no kernel image and no GPU driver; its delta is `dgx-dashboard`, `dgx-oobe{,-desktop}`, `nvidia-dgx-telemetry`, `nvidia-spark-mlnx-firmware-manager`, `nvidia-disable-aqc-nic` + two NEW packages (`nvidia-spark-grub-kho` adds `kho=off` to the kernel command line; `nvidia-spark-cloud-init` configures a NoCloud `OEMDATA` datasource). A reboot-scoped platform act.
- **The v0.32 lineage is built and pinned** — `spark_vllm_ultrafast_v32_image` = `sha256:72eb432f…`, `spark_llm_fp8_kv_capable_images` = `[ultrafast-v32]`, so `fast8` and `fast-v32-bf16` boot today and what is owed on them is certification, not a build (HD-1206, [spark/reports/hd1206-v32-port-20261026/](spark/reports/hd1206-v32-port-20261026/README.md)). It was built on the toolchain this window replaces: **ruled (owner) — use it as built, no rebuild here**; the certification measures the platform, not the build toolchain.
- ⚠ §2 and §4 are **not implemented**; §3 is **not committed**. Phases 0–1 exist to close that.
- **No phase of this window has run** — nothing converged, `versions.yml` untouched. One sitting on the WSL seat
  proved the legs that need no apply: every one of the five hosts answers SSH, and `~/ansible-venv` +
  `ansible-playbook` are present there, so that SKIP names the other seats and not this one (live-verified
  2026-10-27). The `wsl` delegation plane is still unverified (HD-1180), and a spark-served sitting bars its own
  Phase 6 (Rule 0).
- **Rotated already — ⛔ do not rotate again inside this window:** `radarr_api` + `sonarr_api` (the instance's own
  `config.xml` issued the key, the vault holds the copy), `op_api`, `entrim_api`, `openrouter_api`,
  `opencode-go_api`. What they owe is **propagation**: `litellm` + `lan-litellm` render a retired openrouter value
  until they converge, the harness renders still hold the old provider keys, and four `op_api` installs wait a
  re-seat ([docs/1password.md](docs/1password.md) §Rotating the control-node token). Of the 19 items the register
  still names, these need no device in front: `litellm_api`, the NUT pair, `authentik_db`/`forgejo_db`/`immich_db`.
  Not rotatable, recorded: `pppoe_login` (ISP-provisioned) and `slskd_login`/`soulseek_login` (no reset e-mail).
  `ha_api` and `privado-vpn_api` are rotated too and neither is a second rotation: `ha_api` propagates to nothing
  (its only write path is the disabled `alloy_ha_exporter` leg) and owes one human click in HA, and
  `privado-vpn_api` owes the paired `privado_vpn_*` edit in `group_vars` plus a converge — §5b/§5c carry both.

## 2. Prerequisites — the pins session's deliverable (the window does not run without them)

**(a) Two pinned-and-held packages have no lift leg, so a pin bump fails the converge.** The `apt` module always
passes `-y`, and apt refuses to move a held package under `-y`:

```
apt-get -s -y install alloy=1.21.0-1   →  E: Held packages were changed and -y was used without --allow-change-held-packages
apt-get -s     install alloy=1.21.0-1  →  Inst alloy [1.20.1-1] (1.21.0-1 …)
```

`roles/docker` is the only role that lifts (unhold → versioned install → re-hold in `always`, asserted). Port
that block — lift **only** the names the run moves, re-hold in `always`, assert `apt-mark showhold` — into:

- [`IaC/ansible/roles/monitoring/tasks/main.yml`](IaC/ansible/roles/monitoring/tasks/main.yml) — `name: "alloy={{ alloy_version }}"`
- [`IaC/ansible/roles/tailscale-node/tasks/main.yml`](IaC/ansible/roles/tailscale-node/tasks/main.yml) — `apt: deb: …tailscale_<ver>_<arch>.deb`

⚠ **Tag vocabulary, or the port defeats itself:** `home_servers.yml` / `storage.yml` / `raspberry_pi.yml` list
`monitoring` as a **bare role entry with no role-level tag** (`vps.yml` gives it `tags: [monitoring]`), so the new
tasks in that role must carry `tags: [monitoring, alloy]` explicitly — otherwise a `--tags monitoring` run drops the
lift silently and dies at apt's `-y` refusal (the "scoped deploys need BOTH tags" trap,
[scripts/README.md](scripts/README.md)). Add the both-directions assert `roles/docker` carries. ⛔ Never
`--allow-change-held-packages`, never a blanket `apt-mark unhold $(apt-mark showhold)` — documented refusals in
[docs/deployment-ansible.md](docs/deployment-ansible.md) §Role Catalog.

**(b) `scripts/ansible/image-pin-probe.py` cannot find the pin file.** `DEFAULT_ROOT` joins one `os.pardir` where the
`scripts/` foldering needs two, so every documented invocation dies on `FileNotFoundError` — including `--debs`, the
tool that fetches the tailscale digests this window needs. One-line fix; workaround meanwhile `--file
IaC/ansible/group_vars/all/versions.yml`. Its `SOURCES` table has no entry for the four `docker_*`/`containerd_io`
vars, so the tool is blind to this window's host-APT family and those values came from the vendor indexes.

## 3. The pin set

Derive, do not remember: `python3 scripts/ansible/image-pin-probe.py --verify` (3-day hold, mirrors `renovate.json`,
[docs/deployment-renovate.md](docs/deployment-renovate.md) §Manual pin refresh). Buckets: 23 current, 16 patch, 34
minor, 7 major, 4 date-ordered **downgrades**.

**Host-APT (the window part; each value verified published for the suites the fleet runs):**

| var | now | target | live read on the fleet |
|---|---|---|---|
| `docker_ce_version` | `5:29.8.2` | `5:29.9.2` | all four docker hosts |
| `containerd_io_version` | `2.3.6` | `2.4.2` | the four docker hosts |
| `docker_buildx_plugin_version` | `0.37.1` | `0.38.1` | the four docker hosts |
| `docker_compose_plugin_version` | `5.5.1` | `5.6.1` | the four docker hosts |
| `alloy_version` (deb pin — the hyphen means an EXACT compare) | `1.20.1-1` | `1.21.2-1` | **all five** |
| `tailscale_version` **and** `tailscale_host_version` | `v1.102.5` / `1.102.5` | `v1.104.2` / `1.104.2` | oldsrv + pi (deb) |

⚠ `tailscale_host_version` moves **only** with `tailscale_host_deb_sha256_by_arch` re-fetched in the same commit
(`image-pin-probe.py --debs` after the bump); a transcribed or neighbour-release digest passes every offline gate and
dies at `get_url`'s checksum gate mid-play. Verified published, both arches: amd64 `4c342bec…`, arm64 `a093315c…`. The
two versions are one fact: a host node and a sidecar must not speak different wire versions. ⚠ `alloy 1.21.2-1` came
from the vendor index, not from a repo listing here — re-derive it with the fixed probe before the commit.

**Container pins — ruled (owner): patch + minor, flagged rows one by one.** Take the 16 patch + 34 minor rows,
**excluding** every flag below; `keepalived` and `technitium` run as their own mini-windows (VIP and DNS, three live
seeded instances), `headscale`/`headplane` behind `scripts/ansible/guarded-converge.sh`, `ollama -rocm` as its own
mutable-alias decision, `home_assistant` only after the breaking changes for the releases crossed are read.

**Do not touch, in this commit or any other:** the 7 majors (`forgejo 16→17`, `onlyoffice 9→10`, the three postgres
`16.15→18.4`, `onlyoffice_rabbitmq 3→4`, `tube_archivist_redis 7→8` — a data-format major is a migration, and each
carries its own session brief outside this window: [pin-major-onlyoffice.md](pin-major-onlyoffice.md) ·
[pin-major-redis.md](pin-major-redis.md) · [pin-major-rabbitmq.md](pin-major-rabbitmq.md) ·
[pin-major-forgejo.md](pin-major-forgejo.md) · [pin-major-postgres.md](pin-major-postgres.md)); the four
date-downgrades (`authentik_db`, `litellm_db`, `radarr`, `pairdrop`); every digest-pinned `*_image` (CONVENTIONS §7 —
this is why `spark_vllm_ultrafast_v32_image` and `spark_sglang_image` stay put); ⛔ `--allow-downgrades` anywhere. A
pin value is the HIGHEST release already running in the fleet, not the newest upstream — no box runs the `29.9.x`
docker family yet, so this bump is first contact for the whole fleet at once.

## 4. The tombstone (spark) — ruled (owner): mask, then delete

`group_vars/spark.yml` carries a `dgx-dashboard` entry with `enabled: false`, and the box holds no container, no
`docker-compose@dgx-dashboard` symlink, the unit `disabled`, and `/opt/dgx-dashboard/{docker-compose.yml,.j2}`
still present (regenerated by the vendor package, not owned by it). Add a mask of
`docker-compose@dgx-dashboard.service` to the `spark` role — it already masks with `systemctl mask --now`, and
masking, not disabling, survives a package upgrade — then delete the registry entry and rewrite the
[docs/hardware-spark.md](docs/hardware-spark.md) §Remote management sentence so the mask is the named guard and
the ⏳ is gone. Generalizing the mask to every `enabled: false` entry was offered and not taken. ⛔ Do not delete
`/opt/dgx-dashboard` while the unit is merely disabled: a re-enabled unit with no directory fails at `CHDIR` on
every boot, forever.

## 5. Rotation of the exposed secrets — by agency (what a lane does alone, what waits for a human)

Contract: [docs/deployment-secrets.md](docs/deployment-secrets.md) §Creation & Rotation Workflow; the hygiene rule is
CONVENTIONS §6 (never a VALUE to stdout / chat / git / transcripts).

⚠ **`NOT_AUTO_ROTATABLE` is an ORDERING list, not an agency list.** Its own comment reads "externally-coupled item …
rotate manually", and the piles this section replaces inherited the word "hand". What the list actually asserts is:
*a vault-only write here leaves the far end running the old value.* For most of those items the far end is a command a
lane already has a channel to — `ssh`, the RouterOS API, `docker exec`, the app's own config file, the converge itself.
A human is genuinely required in exactly three shapes: **no machine channel exists** (a provider console, a
browser-only token mint, a confirmation e-mail that never arrives), or **the write target is the human vault**, or the
item is **ruled not rotatable**. "Needs a window" (inference down, a backup re-key) is the owner's scheduling call and
is *not* the same thing as "by hand" — those are marked **window** below.

### 5a. The mechanism — one shape for every rotation a lane performs

1. **Derive the list, never recite it.** `python3 scripts/gate/check_secret_leak.py` **on each of the three seats**
   (win11 / wsl / oldsrv-domen); the actionable set is the union of the reads' `FAIL: … outside the ledger` plus
   `KNOWN-EXPOSED` lines — ids and item titles only, never a value, never a length, never a captured line. A rotated
   value stops being a finding because the check compares **current** vault values, so the register is a book of what
   is still true, not a history. ⛔ Deleting, shredding or `git rm`-ing a transcript closes nothing (HD-1181) — it
   removes evidence and leaves the value live.
2. **Far end first.** Issue or change the value where it is authoritative: the app's `config.xml`, `cscli`,
   `headscale apikeys create`, RouterOS `/snmp community`, the kopia cert, the Postgres role (by converge), the unix
   account. ⛔ Never the vault first — that is precisely the divergence the blocklist names, and it fails as a silent
   401 at the next consumer rather than as an error now.
3. **Write the vault.** Catalog item → `OP_SERVICE_ACCOUNT_TOKEN="$(op read
   'op://Homelab-ansible/op-write_api/credential' </dev/null)" python3 scripts/secrets/provision-secrets.py --rotate
   <item> --yes` (the one-shot env form is the runner's route because the seat's ambient token is **read**-scoped and
   `require_write_token()` refuses the script otherwise; `--rotate` also refuses every `NOT_AUTO_ROTATABLE` name — that
   refusal is correct and is not an invitation to hand-generate). Hand-seeded item (no CATALOG row) → the round-trip:
   `op item get <item> --format json` → set `value` on the fields whose **`id`** already exists → `op item edit <item>
   --template -` **on a pipe**. ⛔ Never a template file in `/tmp`, and never a fields-only `--template`: that shape
   APPENDS a duplicate empty field and every label-based read then resolves the empty one.
4. **Propagate.** The converge that renders the item is the propagation: for a `db_role_sync: true` service the role's
   `COMMENT ON ROLE` marker (`pgsync:<sha256>`) does the `ALTER ROLE` — ⛔ a hand-run `ALTER ROLE` desyncs that marker
   and is never repaired; for a compose/env consumer the host's `docker_services` leg recreates the container. Detached
   form, `--check` first, ⛔ never `--diff` (§7 — it prints rendered secrets).
5. **Prove both directions and print nothing.** New value accepted at the consumer **and** the superseded value refused
   at the same endpoint; where two ends must agree, pull each value into a shell variable and compare `sha256sum |
   cut -c1-12` plus a `wc -c` — never `diff` two rendered files, never `cat` one, never `env` / `set` /
   `/proc/<pid>/environ` (a diagnostic that lists "interesting" env vars is a secret read wearing a lab coat). Prove a
   token re-seat by the `op whoami` **Integration ID** + `sha256(token)[:12]`, never by `[ -f ]`.
6. **Then, and only then, the book:** `python3 scripts/gate/check_secret_leak.py --update-ledger --class run-capture`
   from a seat that has the store, delete the STALE lines by hand, and commit the shrunk ledger — that commit is what
   turns `validate-all.sh` green again. A deleted item cannot be rotated: its hit stops matching, the line goes STALE,
   and the commit says so (closed by definition, not by a change).

Every channel named in 5b is in the tree or in the doc cited beside it. Where a line says **probe first**, no such
channel exists in the tree yet — that step is a question, not a plan.

### 5b. Lane-rotatable — no human in the loop

| item | the far-end act that must come first | then |
|---|---|---|
| the CATALOG set: `litellm_api`, `nut_password` + `nut-exporter_password` (NUT is **one** act: master `nas`, clients oldsrv + pi), `victoria-metrics_api`, `victoria-logs_api`, `immich-ml-internal_api`, `n8n-webhook_api`, `signal-internal_api`, `grafana_login`, `opencloud-collab_password`, `kopia-server-internal_api`, `soulseek-internal_api`, `qbittorrent_api`, `crowdsec-bouncer_api`* | none — the render is the far end | `--rotate <item> --yes` + that host's converge. `opencloud-collab_password` re-renders BOTH compose files and users must re-login; `kopia-server-internal_api` rewrites `server.htpasswd`, which the agent identities share |
| `authentik_db`, `forgejo_db`, `immich_db`, `onlyoffice_db` (and `zipline_db`, `litellm_db` if the register names them) | the converge's `db_role_sync` ALTER | **vault write only** — `--rotate` refuses them by design; ⛔ never `ALTER` by hand. `pgvector_db` has no IaC consumer at all: retire the item or name what reads it |
| `wg_password` | `wg genkey` on both sides, exchange the new public keys | write `wg_password` **and** `wg_password_vps` (the role renders `private-key` from the vault), converge router + vps — seconds of S2S down, so it rides Phase 5's router window |
| `network-snmp_api` | RouterOS `/snmp community set` on router **and** switch over the API (no console step exists) | vault write + the monitoring leg that renders `snmp.yml.j2`, in the same window — the exporter and the device must not sit on different communities |
| `privado-vpn_api` | the item's **notes** field carries the whole provider config — pull **only** the non-secret fields (`[Peer] PublicKey`, `[Interface] Address`, `Endpoint`) into variables; ⛔ never print the note body, because a WireGuard config note also contains the `[Interface] PrivateKey` line and dumping it is the leak class §5a exists to stop | the new non-secret values go into `group_vars/home_servers.yml` (`privado_vpn_public_key`, `privado_vpn_address`, `privado_vpn_endpoint_ip` — CONVENTIONS §2: the note is where the value came from, IaC is the SSOT that renders), the private key goes into the vault, and the oldsrv `docker_services` converge recreates **both** gluetun renders (`qbittorrent`, `slskd`). A WireGuard pair that does not match never handshakes, so the proof is the egress IP and one qbit/slskd connect — `Up` proves nothing |
| `crowdsec-bouncer_api` | `cscli bouncers add traefik-bouncer` in the CrowdSec container ([services-traefik.md](docs/services-traefik.md) §Bouncer) | vault write + re-render **both** edges — `traefik` and `traefik-tailnet` read the one item (* this item is catalog-*created* but has no CATALOG row for rotation: the vault write is the `item edit` path) |
| `headplane_api` | `docker exec headscale headscale apikeys create --expiration 8760d`, then expire the old key ([network-vpn.md](docs/network-vpn.md) §Headplane) | vault write + the headplane leg behind `guarded-converge.sh` (`Running=true` between crashes is not liveness) |
| `lidarr_api` | a fresh key written into the instance's own `config.xml` `<ApiKey>` + restart — the same file `roles/docker_services/tasks/arr-seed.yml` already reads | vault write + re-render the consumers (`lidarr-ydl` env, soularr's `config.ini`, then Seerr) in HD-1091's order |
| `bazarr_api`, `admin @media.kogler.si` | the app's own path: Bazarr's `auth.apikey` in its config, Jellyfin's password change (its endpoint needs the current value, which the vault holds) | vault write; re-converge only where a template reads the item. ⛔ `--rotate` here writes a value the app never issued |
| `admin @radarr.kogler.si` | Radarr stores the web-auth user **hashed in its DB** and exposes no endpoint to set it → stop the service, write the hash, start (**window**) | vault write in the same sitting |
| `kopia-server_fingerprint` | regenerate the kopia-server TLS cert | `roles/docker_services/tasks/kopia-fingerprint-sync.yml` reads the live cert **into** the item — the task is the propagation — then re-render both pinning sides |
| `cockpit-pi-web_api` | none (`roles/seat` renders it and the `pi-oldsrv-ts` router's middleware validates the same bearer — both halves move together) | vault write + converge. ⚠ every paired cockpit client re-pairs and the oldsrv cockpit session drops: do not rotate it from the cockpit seat mid-lane |
| `oldsrv-domen_login` | `passwd` / ansible `user` on oldsrv with a **second session open** — this is the `op read … \| sudo -S` path lanes authenticate root reads with | vault write in the same act, then prove `sudo -l -U domen` and one root read |
| `technitium_login` + `admin @dns.kogler.si` | the Technitium password-change endpoint, on **all three** seeded instances (vps primary, oldsrv secondary, pi tertiary) — **probe first**: nothing in the tree calls it, only the seed's login. ⚠ the second item is a second copy of the same credential; leaving it stale reads as a broken DNS seed | vault write to **both** items + the seed converge |
| `openclaw_gateway_token` | the value is generated on the gateway host by `openclaw onboard` — regenerate there (**probe** that it runs non-interactively) | vault write + that service's converge |
| `opencloud_login` | the compose renders `IDM_ADMIN_PASSWORD`, which an identity provider applies at **init** — whether a re-render moves a live admin password is unproven: **probe**, and if it does not, use the IdP's own admin-password path | vault write + converge |
| `n8n_password` | the stored workflow credentials must be re-wrapped — export under the old `N8N_ENCRYPTION_KEY`, re-import/save under the new (**window**). ⛔ A vault write alone leaves n8n unable to decrypt its own credentials, so take the export as the gate **before** the write | vault write + converge, one sitting |
| `kopia_password` | the repo master password is also what the kopia server user authenticates with (docs/backup.md §Layer 2 — the kopia quirk), so the re-key and the server-user password move together, then the agent reconnects (`repository.config` caches the credential) — **window** (HD-1174) | vault write + verify the repository and one restore listing; backups must not stop quietly |
| `spark-llm_api` (and `litellm-engine_api`) | the accepted-key list lives in the **vLLM argv**: rotate, converge spark (engine restart, inference down — **window**), then prove the second accepted key live by hand | converge `litellm` **and** `lan-litellm`, then the seats' rendered `models.json` — the harness authenticates with the engine key, so a missed seat quietly loses its spark lane. Phase 6's slot, never in a spark-served session (HD-384, HD-1170). `scripts/secrets/rotate-spark-llm-key.sh` predates the second key and is not the whole act |

`op_api` stays the first act of the whole window and is already done: a superseded token stays live through an
**owner-set** grace window, so every converge here is safe and the four re-seats batch in Phase 7 (HD-1171). Prove each
re-seat the way 5a step 5 says — `bootstrap-runner.sh` is create-only and a running shell's exported value beats the
file, so a fresh file and a `403` are compatible observations.

### 5c. Waits for a human — no machine channel, or the write is in the human vault

- `ha_api` — the vault half is **done**. A Home Assistant long-lived token is minted in the user-profile UI and a vault
  write does **not** revoke its predecessor, so the whole remainder is one click: HA → user profile → Security →
  **Long-lived access tokens** must list exactly one token (they never expire, so an unpruned list is a standing
  accumulation for the next leak). Nothing else propagates it: `alloy_ha_exporter: false`, `/etc/prometheus/ha_token`
  does not exist on `vps`, and `alloy.river.j2` renders no `bearer_token_file` — the day that HA scrape is enabled the
  write path becomes the `monitoring` / `ha_token` tag on `vps` and this item grows a propagation half (the catalogue
  row's "Traefik/Companion + Prometheus bearer" names consumers that do not exist in the tree).
- `spark_login` — the act is machine-doable (`sudo passwd admin` over the `ansible-admin` SSH), but under the two-vault
  model the item lives in the **human** vault and the runner's write token is scoped to `Homelab-ansible` ⇒ the vault
  half is a human act. Prove a fresh `ssh spark` in a second session before anyone reboots.
- `slskd_login` / `soulseek_login` / `slskd slskd@kogler.si` — the **Soulseek network** account: hand-seeded (no
  CATALOG row), and the only change path is the upstream web reset whose confirmation e-mail never arrives here ⇒
  **not rotatable from a seat**, recorded in [docs/services-rejected.md](docs/services-rejected.md), exposure stays a
  ledger debt. Soulseek **recycles usernames after 30 days without a successful login**, so a login that cannot be
  changed must at least stay connected: prove slskd is on the network, and probe it with `docker exec slskd
  /slskd/slskd --envars`, never by grepping a rendered compose. `soulseek_api` (the slskd web-UI password) is a
  different item and is ours — its converge recreates the container and drops the session, so HD-1091's one-album proof
  comes after it.
- `pppoe_login` — ISP-provisioned, not rotatable from here ([docs/network-rejected.md](docs/network-rejected.md)).
- The provider keys the register still may name (`openrouter_api`, `entrim_api`, `opencode-go_api`) are rotated at
  their consoles already: what they owe is **every** harness client re-rendered — a converge leg, not a rotation, and
  not a human.

**After the rotations:** `python3 scripts/gate/check_secret_leak.py --update-ledger --class run-capture`, delete the
STALE lines by hand, commit the shrunk ledger — that commit is what makes the gate green again. A deleted item
(`wifi-kogler-iot-wan_password`) cannot be rotated: its hit stops matching, the line goes STALE, and the commit says so —
closed by definition, not by a change. ⛔ Never shred or delete a transcript (HD-1181).

## 6. The window, phase by phase

### Phase 0 — the seat (WSL Debian clone on the laptop)

- [ ] `prompt-laptop-wsl.md` §0 pre-flight in full; record the gate count with `validate-all.sh --list | wc -l` and name every SKIP (tmux, the font plane, `ansible-playbook`, `rsync`, the venv symlink arms — HD-1202).
- [ ] Driver clone fast-forwarded: `git fetch origin && git merge --ff-only origin/main`. oldsrv will report `STALE-CLONE` from here until its **own** clone is fast-forwarded on oldsrv — not fixed from the laptop.
- [ ] `~/ansible-venv` present and `ansible-playbook` on PATH — **true on the WSL seat**, so that SKIP names the
  other seats only (live-verified 2026-10-27, together with SSH reachability to all five hosts); `ansible all -m
  ping` still has to answer from the driver before any apply.
- [ ] `echo "seat=$(uname -n) provider=$PI_PROVIDER"` — if the session is **spark-served**, Phase 6 cannot run in it (Rule 0: no engine restart, no `spark-ai` re-render): take it in an externally-served session, stated by the owner in-session (README §3).
- [ ] Delegation plane: `wsl` is unverified (HD-1180) ⇒ lanes run **foreground-sequential**, or pay the two acts (push the `settings` plane + `pi install npm:pi-subagents@0.80.0` FROM this seat, accepted by its own `async: true` launch).
- [x] ⏭ `python3 scripts/gate/check_secret_leak.py` **from this seat** — read taken (HD-1181 leg 3); with the oldsrv and win11 reads it is the rotation list for Phase 2.
- [ ] **The model-path verdict, read before every converge act in this window:** `bash scripts/harness/seat-llm-path.sh --check`.
  `path=lan` = the seat's inference lane is `seat → spark Home :443`, so an act on the VPS edge cannot cut it; `path=edge` =
  the lane rides the tailnet edge and a VPS edge/sidecar restart **will** cut it mid-request (the 2026-10-28 loss class, HD-1212/HD-1213).
  The verdict is read, never assumed, and it is read again after any act that moves an answer.
- [ ] `sudo bash scripts/harness/seat-llm-path.sh --push` — land the pin for this sitting (the push half is a root act; `--check` needs no privilege).
  ⛔ Never by hand: the name and the address are read from `zone_kogler_si` and `network_static_hosts`, the pin exists only while that address answers TCP/443,
  and the plane removes it the moment it stops. One name only — the zone-wide "ask the home resolver at home" shape is rejected (HD-1212), and the seat's
  resolver artifacts and re-assert timer (HD-1176) are outside this plane and stay untouched.
- [ ] `todo.md`: record the window start (one line in the rows this file rides; no new ids).

### Phase 1 — prerequisites (the pins session's commits, consumed here)

- [ ] §2(a) lift legs in `roles/monitoring` + `roles/tailscale-node`, with the `[monitoring, alloy]` tag vocabulary and the both-directions assert.
- [ ] §2(b) `image-pin-probe.py` `DEFAULT_ROOT` fix (+ a note if the `docker_*` SOURCES entries stay absent).
- [ ] §4 tombstone mask, registry entry deleted, `docs/hardware-spark.md` sentence rewritten.
- [ ] §3 pin commit — versions plus the re-fetched `tailscale_host_deb_sha256_by_arch` in the same change.
- [ ] `bash scripts/validate-all.sh` green **except the named leak-gate red**: the live-value debts the
  pi-dev seat's own transcripts hold, which only those rotations close (HD-1181). A seat whose reader has no
  SDK spends ~143 vault requests per gate run instead of 4 — the seat act is `python3
  scripts/lib/vault_read.py --install-sdk` ([docs/1password.md](docs/1password.md) §What a gate run costs the vault).
  The size halves of the backlog/handoff/doc gates never belong in that red list: they print a reminder and exit
  green, so a brief or row that grew with real content changes the item count by nothing
  ([CONVENTIONS.md](CONVENTIONS.md) §6.4).
- [ ] `todo.md` — only if a prerequisite row of its own exists; otherwise nothing.

### Phase 2 — rotations that need no device in front (pile 1 + `op_api`)

- [x] `op_api` **rotated — done**; re-seats deferred to Phase 7 (the owner-set grace covers the window — 3 days for this rotation). Re-confirm the Forgejo Actions holder on the day.
- [ ] The pile-1 items the register still names — `litellm_api`, `nut_password`, `nut-exporter_password` — one by
  one, `--rotate <item> --yes`. `entrim_api`/`openrouter_api`/`opencode-go_api` are rotated already: they owe the
  harness re-render, not another rotation.
- [ ] The exposed `db_role_sync: true` items — `authentik_db`, `forgejo_db`, `immich_db` — a vault write only (⛔
  `--rotate` refuses them, they are `NOT_AUTO_ROTATABLE`); the converge does the `ALTER ROLE` against its own
  `pgsync:<sha256>` marker, and a hand-run `ALTER ROLE` desyncs that marker. `pgvector_db` has no IaC consumer:
  retire the item or name what reads it.
- [ ] NUT as one act across `nas` + `oldsrv` + `pi` (a vault-only edit loses the clients the master).
- [ ] `todo.md` — the rows whose rotation landed.

### Phase 3 — rotations with an app or device at the other end (§5b lanes; §5c is the human residue)

Every box below is a **lane** act unless it names the owner: far end first → vault → converge → both-directions proof
(§5a). The window-bound ones are taken in their window, not here — `spark-llm_api` in Phase 6, `wg_password` with the
router items in Phase 5, and the two re-keys (`kopia_password`, `n8n_password`) as their own sittings.

- [ ] The arr instance keys: mint → the instance's `config.xml` → restart → re-render the consumers. ✅ `radarr_api` / `sonarr_api` **done** — the instance issued the key and the vault holds the copy, so ⛔ nothing re-rotates them for this window. ⏭ `lidarr_api` — in the window, forced order (HD-1091): mint → Lidarr `config.xml` → restart → soularr `config.ini` → Seerr.
- [ ] The §5b device/API far ends, each in its row's order: `network-snmp_api` (router + switch `/snmp community` over
  the API, in the same window as the monitoring render), `kopia-server_fingerprint` (cert, then
  `kopia-fingerprint-sync.yml` + both pins), `crowdsec-bouncer_api` (`cscli` + both Traefik edges), `headplane_api`
  (headscale mint + expire, `guarded-converge.sh`). All four are lane acts, not owner acts — the "by hand" wording
  this file carried was about ORDER, not about agency.
- [ ] The probe-first trio — `technitium_login` (+ its `admin @dns.kogler.si` copy, which must move with it),
  `opencloud_login`, `openclaw_gateway_token`: prove the far-end change path answers before scheduling anything; if it
  does not answer, the item moves to §5c with a line in its row rather than becoming a vault-only write.
- [ ] `privado-vpn_api` — **rotated**; what is left is the paired `privado_vpn_public_key` / `privado_vpn_address`
  (endpoint if it moved) edit in `IaC/ansible/group_vars/home_servers.yml` from the item's `notes` field, read
  field-wise (§5b), then Phase 4's oldsrv leg proves the egress IP.
- [ ] `kopia_password` — rotate **and re-connect** the agent, then verify the repository (HD-1174).
- [ ] `n8n_password` (`N8N_ENCRYPTION_KEY`) with the stored workflow credentials re-entered.
- [ ] `oldsrv-domen_login` on the host + in the vault together, second session open.
- [ ] `privado-vpn_api` at the provider, written back. `openrouter_api`/`entrim_api`/`opencode-go_api` are **rotated and in the vault**; what they owe is **every** harness client re-rendered, not just LiteLLM restarted — a converge leg, not a rotation.
- [ ] Soulseek: ⛔ blocked — the upstream reset e-mail never arrives, so the network login cannot change here; the record is [docs/services-rejected.md](docs/services-rejected.md) and the exposure stays a ledger debt. `soulseek_api` (the slskd web-UI password) is still ours: a write + converge, with HD-1091's album proof after it.
- [ ] `spark_login` — the act (`sudo passwd admin` over the `ansible-admin` SSH) is a lane act, the vault write is not:
  the item lives in the **human** vault and the runner's token is scoped to `Homelab-ansible`. Fresh `ssh spark` proven
  in a second session before anyone reboots.
- [ ] **Owner batch, one sitting (§5c)** — the whole human residue of this window: revoke the superseded `ha_api` token
  in HA's long-lived list (nothing propagates it, so the rotation is not closed until the old token is gone); the
  `spark_login` write into the human vault; `pppoe_login` and the Soulseek network login stay **not rotatable** and
  stay ledger debt, with no box to tick.
- [ ] `todo.md` — the rotation rows' `⏳` tails, once.

### Phase 4 — the converges, one host at a time, canary first

Detached form, every leg: `nohup bash scripts/ansible/ansible-run.sh playbooks/<x>.yml --tags <t> >
/tmp/converge-<host>-$(date +%Y%m%d-%H%M).log 2>&1 &`, then poll the log. `--check` first, in the foreground, and ⛔
never `--diff` (§7).

- [ ] **pi** (canary): `docker` → `monitoring` → `tailscale-node`. Then read the fleet gauge back (§8) and watch `RestartCount`. Pi fold-ins per §11.
- [ ] **vps**: `docker` → `monitoring`; then the guarded legs per §11 (`guarded-converge.sh` for headscale/headplane — `Running=true` between crashes is not liveness).
- [ ] **nas**: `--skip-tags alloy` (that collector is under debugging in another session — §11) + the storage legs.
- [ ] **oldsrv**: `docker` → `monitoring` → `tailscale-node` — **from this seat only**, the guard refuses the `tailscale-node` leg from oldsrv. Fold-ins per §11.
- [ ] **spark**: docker family **after** the OTA in Phase 6 (§7: the toolchain, then the flip).
- [ ] Per host after it converges: the roster is up, `RestartCount` flat, and the role's own `apt-mark showhold` assert passed.
- [ ] `todo.md` — the fold-in rows this phase proved, once.

### Phase 5 — router / switch items (global slot, after the Debian hosts)

- [ ] WG / PPPoE / NUT-client / SNMP re-apply legs that the router or switch must see (the VPS `wireguard` leg restarts the tunnel every off-box converge rides — run it **last**, then re-verify every tunnel path).
- [ ] Anything needing a router window (HD-1160, HD-1142, HD-1140) is taken here or explicitly parked in its row; ⛔ never `--diff` on that playbook (it dumps the PPPoE password).
- [ ] `todo.md` — the network rows, once.

### Phase 6 — spark, last and solo (one slot; not in a spark-served session)

- [ ] Preflight: no other converge in flight, every lane worktree idle, `/` free-space number recorded. **Phase 6
  is unrun** — `spark-llm_api` and `litellm-engine_api` are still the values the fleet runs, and the engine's
  accepted-key list means neither can be rotated without this phase.
- [ ] OTA `OTA2610` → **reboot** → the boot checks: `kho=off` in `/proc/cmdline`, the `nvidia-spark-cloud-init` drop-ins, `nvidia-spark-mlnx-firmware-manager` ran its boot pass, the headless masks and `multi-user.target` survived, `spark-gpu-clock-cap.service` ran, `jupyterlab_ports.yaml` still maps admin → `11002`, and `dgx-dashboard.service` is still the only dashboard unit, loopback-bound and now **masked**.
- [ ] Re-derive [docs/hardware-spark.md](docs/hardware-spark.md) §Identity from the box: kernel, OTA level, dashboard version, UEFI date, QSFP delta #2.
- [ ] The pin converge (`docker`), then `curl -sf localhost:8000/health` **on the box** — the edge 502s for reasons that are not the engine's, and `traefik-spark` restarts with the daemon regardless of its restart-guard exclusion.
- [ ] **spark joins headscale as the THIRD home node** — the IaC is already on `main` (`tailnet_spark_ip` + `tag:spark` + the address-scoped `tcp/443` grant + the `lm-ts` entrypoint), and every bit of it is inert while the var is empty. In this order: mint the key (`docker exec headscale headscale preauthkeys create --tags tag:spark --reusable --expiration 8760h -o json`, the value is under the JSON key `key`) → store it as `tailscale-spark_api` → the join leg **off-box** (`--tags tailscale-node`; the self-converge guard refuses it on-box) → read the tag AND the address back from `headscale nodes list -o json` → set `tailnet_spark_ip` and commit → the vps `headscale` policy converge → the spark `spark-dashboard` converge. ⚠ The tag is read back, never trusted from the mint command, and `tag:dev`/`tag:home-edge` are refused — a borrowed tag is by-tag widening ([docs/network-rejected.md](docs/network-rejected.md)).
- [ ] Its read-back: `ss -ltnp | grep ':443'` on spark lists `spark_home_ip` and the node address and **never** `0.0.0.0`; `curl -sk --resolve llm.kogler.si:443:<tailnet_spark_ip> https://llm.kogler.si/v1/models` answers with the bearer and 401s without it; `tailscale status --json` keeps `PrimaryRoutes` empty on every peer — the boundary must not have moved because a third node arrived.
- [ ] ⛔ **The `llm.kogler.si` answer flip is NOT in this window.** It needs BOTH halves on the zone entry — `tailnet: node`/`dual` **and** an explicit `tailnet_ip:`, since the class default for those is oldsrv's node — it moves the answer for every client, and `node`/`dual` publish the `.ts` twin only. It rides HD-436's owner-present converge. Tonight the node answers the **port**, not the **name**: prove it with the `--resolve` form above, not with `dig`.
- [ ] `spark-llm_api` + `litellm-engine_api` rotation → spark converge carries the new accepted list → prove the second key live **by hand** (`scripts/secrets/rotate-spark-llm-key.sh` does not know it) → HD-384 step 2: converge `lan-litellm` + `litellm`. ⛔ Inverting this order 401s every upstream call.
- [ ] The A+ **runtime dispatch check**: does a real bf16 GEMM land on a `(12, 1)` plan rather than the `F.linear` fallback. No build can answer this.
- [ ] Flip `fast-v32-bf16` (`-e spark_llm_profile=fast-v32-bf16 -e spark_llm_allow_uncertified=true`, detached; ~20 min cold boot) and read the engine's `GPU KV cache size` line — expecting **644,599 slots / 2.46×**. Another number means the pool arithmetic moved under the port.
- [ ] Gates 0–7, then flip `fast8`, then the dtype gates 8–9. Rollback at any point: `-e spark_llm_profile=fast` plus a detached converge (`spark-rollback:fast` = `4900c13edab9…`, archived twice on the NAS).
- [ ] ⛔ Never rebuild the lineage in this window, never retag `qwen38-flash-dgx:iter6c|iter6d`, never prune the build cache — report the free-bytes number instead. The post-build CPU gates assert day-0 bytes: on v32 their red is not a verdict and their green would not be one either (HD-1210) — read the artifact markers.
- [ ] `todo.md` — HD-1206's window tail and HD-384, once.

### Phase 7 — re-seat and re-check

- [ ] Re-seat every `op_api` consumer: oldsrv control node, oldsrv seat `domen`, this laptop, and (re-confirmed) Forgejo Actions; prove by Integration ID + `sha256[:12]`.
- [ ] `python3 scripts/gate/check_secret_leak.py --update-ledger --class run-capture`; delete the STALE lines by hand; commit the shrunk ledger — the commit that turns the gate green.
- [ ] The leak read is green on every seat **except the named Wi-Fi items** (§11) — the window's accepted end-state (HD-1181).
- [ ] `todo.md` — the rotation rows close or shrink here.

### Phase 8 — the documentation pass, then this file dies

- [ ] `todo.md` + the owning docs, once, for everything the window proved.
- [ ] `prompt.md` and the affected `prompt-*.md` briefs brought in line (the parked table, the fold-in rows, the `todo-table.md` §B0 wiring for this brief's ids). **This is the last content act.**
- [ ] `bash scripts/validate-all.sh` green (or red only on a named, dated exception).
- [ ] Commit, merge, push.
- [ ] Delete `prompt-update.md` in that same change. ⛔ No row is minted for any of it; the `check_backlog_prose` NOTE for a dead brief is the lifecycle working, not a finding.

## 7. Traps (each one costs a lane a window)

- **⛔ Two lanes on one converge slot** (O3). On spark the OTA, the pin converge, the rotation and the flip are the **same** slot; the flip stays last and solo, so the certification measures the final platform ([docs/spark-llm-profiles.md](docs/spark-llm-profiles.md) §7) — and the arm is never flipped to certify a package bump, which is a restart, not a certification.
- **`--check` is not a verdict**: the deploy loop skips in check mode, so it proves scoping only — and on a held suite it leaves the package held, so the apt leg is skipped rather than run (the play says so).
- **`--diff` is a secret dump**, on `monitoring` as much as on `docker_services`: `alloy.river.j2` renders the Victoria `basic_auth` values out of the vault into the diff. `--check` is fine; the diff is not.
- **A timeout-killed converge dies mid-restart** and leaves siblings `Exited` (`cannot join network namespace of a non running container`). Detached + log + poll; re-running is idempotent.
- **spark**: engine cold boot ~20 min (`start_period: 1200s`) — the OTA reboot and the flip's converge are two of them; a build that reaches the layer steps costs ~12 G on `/`, so read `df -h /` and `docker system df` and expect the containerd bump to change what buildkit keeps.
- **The tailnet is two acts**: `tailscaled` on oldsrv + pi, `headscale`/`headplane` on the VPS behind `guarded-converge.sh` (the pinned headscale crash-loops when `dns.extra_records` and `dns.extra_records_path` are both set).
- **`home_assistant` minors are release-train jumps** — read the breaking changes for every version crossed; its config entry holds plaintext that rsyncs to the oldsrv standby.
- **A held package is not a pinned package.** The role asserts it; a hand check on oldsrv needs the `sudo -S` pipe form (§8) — and ⛔ never a `NOPASSWD` added to make a verification loop quiet.
- **The gauge goes red on purpose** between the pin commit and the last converge; `differ` non-empty is the window in flight, and an empty read is not fleet health — a host that publishes nothing contributes no rows ([docs/observability.md](docs/observability.md) §Silent-failure hygiene).
- **A VPS edge/sidecar act is a MODEL-LANE act.** Unless the seat's answer for the inference name is the Home address, the session's own
  inference path is `llm.kogler.si` → the tailnet edge → WG S2S → spark — so restarting that edge ends the session that is converging it.
  Read `bash scripts/harness/seat-llm-path.sh --check` before an act on the vps edge, and keep edge/sidecar restarts LAST in a host's leg order (HD-1213).
- **No new row for this work.** If the window mints anything it is a `⏳` on a row that already exists (§0).

## 8. Verify before closing the window

```bash
python3 scripts/ansible/image-pin-probe.py --verify      # every pin vs its registry
python3 scripts/ansible/image-pin-probe.py --debs        # tailscale digests vs the vendor .sha256
bash scripts/validate-all.sh                             # from the worktree
for h in oldsrv vps nas pi spark; do printf '%-8s ' $h; ssh -n $h 'sudo -n apt-mark showhold 2>/dev/null | tr "\n" " "; echo' || echo 'sudo -n unavailable'; done
```

`oldsrv` does not give this seat passwordless sudo, so the loop prints a **named gap**, never a false empty list;
the hold is proven on that host by the role's own root-side assert (`apt-holds.yml`, `roles/docker`'s re-hold
check), and a hand read there uses the sanctioned `op read … | sudo -S -p "" apt-mark showhold` — after that
credential's own rotation, and never in a form that prints a value. Then per host: the roster up, `RestartCount`
flat, the pin gauge `match`, and the pin-lag alert cleared on **five** reporting instances. On spark additionally:
`/proc/cmdline`, `nvidia-smi` driver unchanged, masks + `multi-user.target`, the clock-cap unit ran, the
tombstone's boot unit masked, `llm.kogler.si/health` 200.

## 9. Rulings (owner) — do not re-decide

Mask-then-delete for the tombstone (§4) · patch + minor for the pin sweep with the flagged rows decided individually
(§3) · rotate everything the gate names, the n8n/kopia consequences scheduled rather than avoided (§5) · `op_api`
rotated first, re-seats batched at the end, on the owner-set grace window (§5) · `radarr_api`/`sonarr_api`/
`lidarr_api`/`n8n_password` **in** this window (§3, Phase 3) · the v32 artifact **used as built** on the pre-bump
toolchain, no rebuild (§1) · converges driven from the WSL seat (§10) · **Wi-Fi PSKs out of this window** (§11), with
the accepted consequence that the leak gate stays red on exactly those items (§0, Phase 7) · spark joins the tailnet as the THIRD home node, its
grant written on its node **address** with its own `tag:spark` granting nothing (§6 Phase 6) · the seat pins ONE name's answer through the `llm-path`
plane rather than re-pointing the whole zone at the home resolver (§6 Phase 0) · no row minted for any of
it (§7).

## 10. Driver and seat contract

The driver is the **WSL Debian clone on the laptop**: off-box for every target, so the self-converge guard never fires
there, and [docs/deployment-ansible.md](docs/deployment-ansible.md) §Runner placement records that a **self-target**
run from a seat dies at the transport (ProxyJump hop-back + `IdentitiesOnly`) — the oldsrv case. Lockout-class legs
therefore belong to this seat whatever the model is (`prompt-laptop-wsl.md` §1). Read `echo $PI_PROVIDER` before Phase
6: spark-served ⇒ Rule 0 binds the whole run, children included, and the flip is not available; the legs only that box
may drive are its §2. That brief's §4 rehearse-everything rule is lifted **in this window only**, because the owner is
present; nothing else in it changes.

## 11. Fold-ins, and what is held out

| host | rows this window's converge carries | notes |
|---|---|---|
| **pi** | HD-443, HD-1103 · HD-1167 · HD-1109 | revoke `admin` after `ansible-admin` + `domen` are proven; pair the converge with the Pi visit so the box boots once (fstab `mode=`, the ruled `rotate 1` + `maxsize` logrotate file, the one-time `pi-eth0.nmconnection` re-render, the UNTAGGED leg applying `ai_diag`'s derived smartd mask). ⛔ the `nm-resolver` applies and HD-418's reconcile are done |
| **vps** | HD-1166, HD-1173, HD-1106, HD-436, HD-487, HD-1150 | HD-1166's page is the ticket — one `--tags monitoring`, no UI mute; HD-1106 fixes the `onlyoffice-docs` named volume **before** any `docker volume rm` by name; HD-436 behind `guarded-converge.sh`; HD-487 `--tags netd`; HD-1150's token re-seat is issued **from this laptop** |
| **nas** | HD-1093 | `storage_samba_password_force` lands the already-rotated SMB pair — a vault edit alone changes nothing on the box; the replica retag and the wedge reap are in [docs/storage.md](docs/storage.md) §A |
| **oldsrv** | HD-1122, HD-1088, HD-1175 | HD-1122 flips `ai_tier_metrics_publish` and recreates two serving containers (engine panel 1 → 3); HD-1088 needs the Box key registered first; HD-1175 is a root-only journal/`pstore` read while you are at that box |
| **spark** | HD-1206, HD-384, HD-473, HD-1210, HD-436 | the dispatch check → `fast-v32-bf16` → gates 0–7 → `fast8` → gates 8–9, one boot shared with the rotation |
| **router** | HD-1160, HD-1142, HD-1140, HD-1136 | the global slot, and none of them is a converge |

**Held out, on purpose:** the Wi-Fi PSKs (`wifi-kogler*` — live PSKs, every device rejoins by hand, the Shellys
re-provisioned one by one, and nothing in IaC writes them because `routeros_capsman_enabled: false` leaves the rendered
rsc as the delivery path) ⇒ the leak gate stays red on exactly those items; `alloy` on `nas` (another session is
debugging that collector — converge nas with `--skip-tags alloy` and name `differ{instance="nas"}` as the window's one
live gauge exception); the 7 majors + 4 downgrades, hence HD-1100's PG 18 legs; `ollama`'s `-rocm` alias;
`home_assistant` minors; every digest-pinned image; and the §D owner-eyes items (visual passes, device walks, drills),
which need neither a converge nor this window.

