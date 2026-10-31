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
- **Per-lane execution state — the shas, the parks, the measurements — is [`plan/tasks-update-window-20261028.md`](plan/tasks-update-window-20261028.md)**, the window's work package. The boxes here say what is owed; that file carries what each lane proved and what it parked, and it dies in the same commit as this one (Phase 8).

## 1. State this brief was written against

- Pin SSOT: [`IaC/ansible/group_vars/all/versions.yml`](IaC/ansible/group_vars/all/versions.yml); rule [CONVENTIONS.md](CONVENTIONS.md) §7; mechanism [`IaC/ansible/roles/common/tasks/apt-holds.yml`](IaC/ansible/roles/common/tasks/apt-holds.yml). No host has an automated upgrade phase — a refresh is a hand edit plus a deliberate converge, and Renovate still points at a test repo (HD-264).
- Every Debian host sits at its pin with the whole set held (`hi` in `dpkg -l`, live-verified on all five): oldsrv 8, pi 8, vps 7, spark 7, nas 1 (`alloy` only — `nas` runs no Docker), so `homelab_pkg_pin_result{result="differ"}` is empty before the window ([docs/observability.md](docs/observability.md) §Pin-lag report).
- spark: kernel `7.0.0-1019-nvidia`, driver `580.178.04`, DGX OS OTA level 7.6.0, `/` 165 G free, up 5+ weeks. The offered OTA `OTA2610` moves no kernel image and no GPU driver; its delta is `dgx-dashboard`, `dgx-oobe{,-desktop}`, `nvidia-dgx-telemetry`, `nvidia-spark-mlnx-firmware-manager`, `nvidia-disable-aqc-nic` + two NEW packages (`nvidia-spark-grub-kho` adds `kho=off` to the kernel command line; `nvidia-spark-cloud-init` configures a NoCloud `OEMDATA` datasource). A reboot-scoped platform act.
- **The v0.32 lineage is built and pinned** — `spark_vllm_ultrafast_v32_image` = `sha256:72eb432f…`, `spark_llm_fp8_kv_capable_images` = `[ultrafast-v32]`, so `fast8` and `fast-v32-bf16` boot today and what is owed on them is certification, not a build (HD-1206, [spark/reports/hd1206-v32-port-20261026/](spark/reports/hd1206-v32-port-20261026/README.md)). It was built on the toolchain this window replaces: **ruled (owner) — use it as built, no rebuild here**; the certification measures the platform, not the build toolchain.
- **The prerequisites are in the tree** — §2(a), §2(b) and §4 — and the §3 pin commit is on `main`: the hold-lift legs in
  `roles/monitoring` + `roles/tailscale-node`, the `image-pin-probe.py` root fix with `SOURCES` rows for the four
  docker-family vars, the `dgx-dashboard` mask with its registry entry deleted, and the pin set at the §3 targets with
  `tailscale_host_deb_sha256_by_arch` re-fetched in the same change. What is left of §4 is the mask **on the box**,
  which is a spark converge (Phase 6).
- **Four of the five hosts are converged** — `pi`, `vps`, `nas`, `oldsrv`: the docker family, `alloy`, and the
  `tailscale-node` deb where the role applies, with the holds re-asserted by the role's own assert. **spark carries the
  `monitoring`/`alloy` legs only** (ruling S8), so it publishes the NEW pin map over OLD packages: six `differ` rows,
  all docker family, plus `tailscale` = `missing`. That is the parked Phase-6 apply made visible by a render, not drift,
  and `--tags hygiene` is the leg that bakes a host's pin map — a `differ` row is a statement about a render, never
  about packages ([docs/observability.md](docs/observability.md) §Pin-lag report).
- **Phase 5 (router/switch) and Phase 6 (spark) have not run**, Phase 7 ran its re-seats but not its ledger commit,
  Phase 8 is owed. The `wsl` delegation plane is answered FROM that seat (HD-1180: background children launched there
  yield child session files), so lanes launched from `wsl` run `async: true`; `win11` still owes its own launch. A
  spark-served sitting bars its own Phase 6 (Rule 0).
- **Rotated — ⛔ do not rotate again inside this window:** `radarr_api`, `sonarr_api`, `lidarr_api`, `bazarr_api`,
  `soulseek_api` + `soulseek-internal_api`, `qbittorrent_api`, `op_api`, `entrim_api`, `openrouter_api`,
  `opencode-go_api`, `litellm_api`, the NUT pair (`nut_password` + `nut-exporter_password`, one act across the three
  hosts), `authentik_db`, `forgejo_db`, `immich_db`, `onlyoffice_db`, `kopia-server-internal_api`,
  `kopia-server_fingerprint`, `crowdsec-bouncer_api`, `headplane_api`, `signal-internal_api`,
  `victoria-metrics_api` + `victoria-logs_api`, `grafana_login`, `opencloud-collab_password`, `technitium_login` with
  its `admin @dns.kogler.si` copy, `ha_api`, and `privado-vpn_api` with its `privado_vpn_*` fields landed in
  `group_vars`. Each moved at the end that ISSUES it, propagated, and was proved new→accepted / superseded→refused;
  the mechanics and per-item far ends are §5a/§5b. `grafana_login` is the case where the render is NOT the far end —
  `grafana cli admin reset-admin-password` moves the app, `GF_SECURITY_ADMIN_PASSWORD` only seeds it.
  **Rotated with the residue elsewhere:** `ha_api` propagates to nothing and owes one click in HA (prune the
  long-lived-token list); `op_api` is fully propagated — four installs re-seated, no Actions-store holder, no stale
  root-side install (docs/1password.md §Where a token is installed); `kopia-server_fingerprint`'s current
  value is a TLS cert fingerprint, so its ledger line stays (ruling S7).
  **Not rotatable, recorded:** `pppoe_login` (ISP-provisioned), `slskd_login` / `soulseek_login` (no reset e-mail).
  **Parked, with the reason in the row:** `immich-ml-internal_api` and `n8n-webhook_api` (nothing enforces the
  credential, so a rotation buys nothing), `immich_oidc` (an owner call — ruling S4), `pgvector_db` (retired service:
  delete the item WITH its parked cluster dirs), `opencloud_login` and `openclaw_gateway_token` (the probe answered
  "no far-end path", §5c), the two media web-auth users and `jellyfin-seer_api` (UI-only, no machine mint),
  `network-snmp_api` (a router/switch write — Phase 5), `spark-llm_api` + `litellm-engine_api` (Phase 6), and the two
  re-keys `kopia_password` + `n8n_password`, whose consequences must fit the same sitting.

## 2. Prerequisites — the pins session's deliverable (the window does not run without them)

**(a) Two pinned-and-held packages needed a lift leg, or a pin bump dies in apt.** The `apt` module always
passes `-y`, and apt refuses to move a held package under `-y`:

```
apt-get -s -y install alloy=1.21.0-1   →  E: Held packages were changed and -y was used without --allow-change-held-packages
apt-get -s     install alloy=1.21.0-1  →  Inst alloy [1.20.1-1] (1.21.0-1 …)
```

The shape is `roles/docker`'s (unhold → versioned install → re-hold in `always`, asserted), ported — lifting
**only** the names the run moves, re-holding in `always`, asserting `apt-mark showhold` in both directions — into:

- [`IaC/ansible/roles/monitoring/tasks/main.yml`](IaC/ansible/roles/monitoring/tasks/main.yml) — `name: "alloy={{ alloy_version }}"`
- [`IaC/ansible/roles/tailscale-node/tasks/main.yml`](IaC/ansible/roles/tailscale-node/tasks/main.yml) — `apt: deb: …tailscale_<ver>_<arch>.deb`

⚠ **Tag vocabulary, or the port defeats itself:** `home_servers.yml` / `storage.yml` / `raspberry_pi.yml` list
`monitoring` as a **bare role entry with no role-level tag** (`vps.yml` gives it `tags: [monitoring]`), so those
tasks carry `tags: [monitoring, alloy]` explicitly — otherwise a `--tags monitoring` run drops the lift silently and
dies at apt's `-y` refusal (the "scoped deploys need BOTH tags" trap, [scripts/README.md](scripts/README.md)) — and
the both-directions assert `roles/docker` carries is there too. `tailscale-node` keeps its single role tag on
purpose: widening it would have to enter `homelab_guard_tags` AND the guard task's own `tags:` in one change
(`scripts/gate/check_self_converge_guard.py`), and both playbooks already tag the role, so nothing was repaired by
the extra tag. ⛔ Never
`--allow-change-held-packages`, never a blanket `apt-mark unhold $(apt-mark showhold)` — documented refusals in
[docs/deployment-ansible.md](docs/deployment-ansible.md) §Role Catalog.

**(b) `scripts/ansible/image-pin-probe.py` finds the pin file, and the host-APT family.** `DEFAULT_ROOT` joined one
`os.pardir` where the `scripts/` foldering needs two, so every documented invocation died on `FileNotFoundError` —
including `--debs`, the tool that fetches the tailscale digests — and there is no `--file` workaround left. Its
`SOURCES` table now carries the four `docker_*`/`containerd_io` vars, and those rows print `PIN EXISTS = feed-only`:
the tool sees the pin but has no upstream index to re-derive it from, so a docker-family value stays a vendor-index
read.

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
from the vendor index, not from a repo listing here; the fixed probe's `--verify` reads it as published, which is as
far as a deb pin is provable offline.

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
docker family and spark does not, which is the six `differ` rows §1 names.

## 4. The tombstone (spark) — ruled (owner): mask, then delete

`group_vars/spark.yml` carries no `dgx-dashboard` entry, the `spark` role masks
`docker-compose@dgx-dashboard.service` (it already masked other units with `systemctl mask --now`, and masking, not
disabling, survives a package upgrade), and the
[docs/hardware-spark.md](docs/hardware-spark.md) §Remote management sentence names the mask as the guard. The box
still holds `/opt/dgx-dashboard/{docker-compose.yml,.j2}` (regenerated by the vendor package, not owned by it), and
the mask is inert until a spark converge applies it (Phase 6). Generalizing the mask to every `enabled: false` entry
was offered and not taken. ⛔ Do not delete
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
3. **Write the vault.** The write is `OP_SERVICE_ACCOUNT_TOKEN="$(op read
   'op://Homelab-ansible/op-write_api/credential' </dev/null)" python3 scripts/secrets/provision-secrets.py --rotate
   <item> --yes` — the one-shot env form is the runner's route because the seat's ambient token is **read**-scoped and
   `require_write_token()` refuses the script otherwise; `--rotate` also refuses every `NOT_AUTO_ROTATABLE` name — that
   refusal is correct and is not an invitation to hand-generate.
   ⚠ **`--rotate` is only the write when the vault is the issuer.** It MINTS a value, so a far-end-first rotation (the
   step-2 shape: the app's `config.xml`, a device, a provider) must NOT use it — the far end already holds a specific
   value and writing a second one is the divergence step 2 exists to prevent. The write there, and for any hand-seeded
   item with no CATALOG row, is the round-trip:
   `op item get <item> --format json` → set `value` on the fields whose **`id`** already exists → `op item edit <item>`
   with that JSON **on a pipe** (`op item get … | op item edit <item>`). ⛔ Not `op item edit <item> --template -`:
   CLI 2.39 answers `cannot edit an item from template and stdin at the same time`, because the piped body IS the
   template. ⛔ Never a template file in `/tmp`, and never a fields-only `--template`: that shape
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
**owner-set** grace window, so every converge here is safe and the four re-seats batch in Phase 7. Prove each
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
- `opencloud_login` — **moved here by probe**, and the probe is the reason: the compose renders `IDM_ADMIN_PASSWORD`,
  which the identity provider applies at **init**, so a re-render does not move a live admin password and a vault write
  alone is the divergence §5a names. The IdP's own admin-password path is the far end.
- `openclaw_gateway_token` — **moved here by probe**: the value is generated on the gateway host by `openclaw onboard`,
  and the gateway was never onboarded, so there is no far end to move until that service exists.
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
- [x] `~/ansible-venv` present and `ansible-playbook` on PATH — **true on the WSL seat**, so that SKIP names the
  other seats only; `ansible all -m ping` answered from the driver, since every Phase-4 leg ran from it.
- [x] `echo "seat=$(uname -n) provider=$PI_PROVIDER"` — the sittings read **spark**, so Phase 6 could not run in them
  (Rule 0: no engine restart, no `spark-ai` re-render): take it in an externally-served session, stated by the owner
  in-session (README §3).
- [x] Delegation plane: `wsl` is answered FROM this seat — background children launched here yield their child session files, so lanes run `async: true` (HD-1180). `win11` is the one seat that still owes its own `async: true` launch.
- [x] ⏭ `python3 scripts/gate/check_secret_leak.py` **from this seat** — read taken (HD-1181 leg 3); with the oldsrv and win11 reads it is the rotation list for Phase 2.
- [x] **The model-path verdict, read before every converge act in this window:** `bash scripts/harness/seat-llm-path.sh --check`.
  This window read **`path=lan`** ⇒ a VPS edge/sidecar act cannot cut the session's own inference lane (the §7 trap is
  armed but not loaded). `path=lan` = the seat's inference lane is `seat → spark Home :443`; `path=edge` =
  the lane rides the tailnet edge and a VPS edge/sidecar restart **will** cut it mid-request (the 2026-10-28 loss class, HD-1212/HD-1213).
  The verdict is read, never assumed, and it is read again after any act that moves an answer.
- [ ] `sudo bash scripts/harness/seat-llm-path.sh --push` — land the pin for this sitting (the push half is a root act; `--check` needs no privilege).
  ⛔ Never by hand: the name and the address are read from `zone_kogler_si` and `network_static_hosts`, the pin exists only while that address answers TCP/443,
  and the plane removes it the moment it stops. One name only — the zone-wide "ask the home resolver at home" shape is rejected (HD-1212), and the seat's
  resolver artifacts and re-assert timer (HD-1176) are outside this plane and stay untouched.
- [x] `todo.md`: record the window start (one line in the rows this file rides; no new ids).

### Phase 1 — prerequisites (the pins session's commits, consumed here)

- [x] §2(a) lift legs in `roles/monitoring` + `roles/tailscale-node`, with the `[monitoring, alloy]` tag vocabulary and the both-directions assert.
- [x] §2(b) `image-pin-probe.py` `DEFAULT_ROOT` fix (+ a note if the `docker_*` SOURCES entries stay absent) — they were added, and they report `PIN EXISTS = feed-only`.
- [x] §4 tombstone mask, registry entry deleted, `docs/hardware-spark.md` sentence rewritten. ⏭ the mask ON the box rides the spark converge (Phase 6).
- [x] §3 pin commit — versions plus the re-fetched `tailscale_host_deb_sha256_by_arch` in the same change.
- [x] `bash scripts/validate-all.sh` green **except the named leak-gate reds**: the live-value debts the seats' own
  transcripts still hold, which only the remaining rotations close (HD-1181) — today that set is the `wifi-kogler*`
  PSKs, `jellyfin-seer_api` (no machine mint), `spark-llm_api`/`litellm-engine_api` (Phase 6), `kopia_password` and
  `n8n_password` (the unstarted re-keys), the two host credentials, and `pppoe_login`/Soulseek (not rotatable). A seat whose reader has no
  SDK spends ~143 vault requests per gate run instead of 4 — the seat act is `python3
  scripts/lib/vault_read.py --install-sdk` ([docs/1password.md](docs/1password.md) §What a gate run costs the vault).
  The size halves of the backlog/handoff/doc gates never belong in that red list: they print a reminder and exit
  green, so a brief or row that grew with real content changes the item count by nothing
  ([CONVENTIONS.md](CONVENTIONS.md) §6.4).
- [x] `todo.md` — only if a prerequisite row of its own exists; otherwise nothing. Nothing was owed.

### Phase 2 — rotations that need no device in front (pile 1 + `op_api`)

- [x] `op_api` **rotated — done**; re-seats deferred to Phase 7 (the owner-set grace covers the window — 3 days for this rotation). Re-confirm the Forgejo Actions holder on the day.
- [x] The pile-1 items the register still names — `litellm_api`, `nut_password`, `nut-exporter_password` — one by
  one, `--rotate <item> --yes`. `entrim_api`/`openrouter_api`/`opencode-go_api` are rotated already: they owe the
  harness re-render, not another rotation.
- [x] The exposed `db_role_sync: true` items — `authentik_db`, `forgejo_db`, `immich_db` (and `onlyoffice_db`) — a vault
  write only (⛔ `--rotate` refuses them, they are `NOT_AUTO_ROTATABLE`); the converge did the `ALTER ROLE` against its
  own `pgsync:<sha256>` marker, and a hand-run `ALTER ROLE` desyncs that marker. `pgvector_db` has no IaC consumer:
  **owner act** — delete the item WITH `/opt/.retired-pgvector` + `/srv/docker/.retired-pgvector` on `vps`.
- [x] NUT as one act across `nas` + `oldsrv` + `pi` (a vault-only edit loses the clients the master).
- [x] `todo.md` — the rows whose rotation landed.

### Phase 3 — rotations with an app or device at the other end (§5b lanes; §5c is the human residue)

Every box below is a **lane** act unless it names the owner: far end first → vault → converge → both-directions proof
(§5a). The window-bound ones are taken in their window, not here — `spark-llm_api` in Phase 6, `wg_password` with the
router items in Phase 5, and the two re-keys (`kopia_password`, `n8n_password`) as their own sittings.

- [x] The arr instance keys: mint → the instance's `config.xml` → restart → re-render the consumers. ✅ `radarr_api` /
  `sonarr_api` / `lidarr_api` / `bazarr_api` **done** — the instance issued each key and the vault holds the copy, so
  ⛔ nothing re-rotates them for this window; `lidarr_api` moved in HD-1091's forced order and its three holders
  (`lidarr-ydl` env, soularr `config.ini`, SeerrNG `settings.json`) were re-taught. ⏭ the two `admin @…` web-auth
  users and `jellyfin-seer_api` have **no machine path** (hashed-in-DB / UI-only mint) — owner act, in their rows.
- [ ] The §5b device/API far ends, each in its row's order — three of the four landed: `kopia-server_fingerprint` (cert, then
  `kopia-fingerprint-sync.yml` + both pins), `crowdsec-bouncer_api` (`cscli` + both Traefik edges), `headplane_api`
  (headscale mint + expire, `guarded-converge.sh`). ⏭ `network-snmp_api` is **parked** — it is a router + switch
  `/snmp community` write and the router/switch acts are out of this run (Phase 5). ⚠ Two owner-visible residues
  came out of this box: `headscale apikeys list` holds **two live keys (ids 1 and 2, expiring 2050) that no vault
  item or rendered config matches** — revoking them is an owner call — and `provision-secrets.py` judged a landed
  write by a spurious `op` rc, since fixed by re-reading.
- [x] The probe-first trio — the probes answered, so none of the three is a vault-only write: `technitium_login`
  (+ its `admin @dns.kogler.si` copy, moved with it) is **one credential held three times** and rotated as three acts
  on the vps primary, the oldsrv secondary and the pi tertiary; `opencloud_login` and `openclaw_gateway_token` are
  **parked to §5c** — the probe found no far-end path that a lane can drive (the IdP applies `IDM_ADMIN_PASSWORD` at
  init; `openclaw onboard` never ran here), which is the answer this box asked for.
- [x] `privado-vpn_api` — **rotated**; the paired `privado_vpn_public_key` / `privado_vpn_address` / endpoint are in
  `IaC/ansible/group_vars/home_servers.yml`, read field-wise out of the item's `notes` (the note body carries a
  `[Interface] PrivateKey` line and was never printed), both gluetun renders re-rendered, the egress IP proved.
- [ ] `kopia_password` — rotate **and re-connect** the agent, then verify the repository (HD-1174). ⏭ **not started**:
  a re-key whose consequences did not run in the same sitting is a broken backup, not a partial success.
- [ ] `n8n_password` (`N8N_ENCRYPTION_KEY`) with the stored workflow credentials re-entered. ⏭ **not started** — the
  export-under-the-old-key gate has to precede any vault write.
- [ ] `oldsrv-domen_login` on the host + in the vault together, second session open. ⏭ **parked on the owner** — a
  lockout-class mistake here breaks the seat that every other leg authenticates through.
- [ ] `privado-vpn_api` at the provider, written back — **done, including the `group_vars` half**. `openrouter_api`/`entrim_api`/`opencode-go_api` are **rotated and in the vault**; what they owe is **every** harness client re-rendered, not just LiteLLM restarted — a converge leg, not a rotation. ⏭ that re-render is owed on the seats, not proved here.
- [x] Soulseek: ⛔ the **network** login stays blocked — the upstream reset e-mail never arrives, the record is [docs/services-rejected.md](docs/services-rejected.md) and the exposure stays a ledger debt. `soulseek_api` + `soulseek-internal_api` (the slskd web-UI password) moved with the render as the far end, and HD-1091's one-album proof stays after it.
- [ ] `spark_login` — the act (`sudo passwd admin` over the `ansible-admin` SSH) is a lane act, the vault write is not:
  the item lives in the **human** vault and the runner's token is scoped to `Homelab-ansible`. Fresh `ssh spark` proven
  in a second session before anyone reboots.
- [ ] **Owner batch, one sitting (§5c)** — the whole human residue of this window: revoke the superseded `ha_api` token
  in HA's long-lived list (nothing propagates it, so the rotation is not closed until the old token is gone); the
  `spark_login` write into the human vault; `pppoe_login` and the Soulseek network login stay **not rotatable** and
  stay ledger debt, with no box to tick.
- [x] `todo.md` — the rotation rows' `⏳` tails, once.

### Phase 4 — the converges, one host at a time, canary first

Detached form, every leg: `nohup bash scripts/ansible/ansible-run.sh playbooks/<x>.yml --tags <t> >
/tmp/converge-<host>-$(date +%Y%m%d-%H%M).log 2>&1 &`, then poll the log. `--check` first, in the foreground, and ⛔
never `--diff` (§7).

- [x] **pi** (canary): `docker` → `monitoring` → `tailscale-node`. Then read the fleet gauge back (§8) and watch `RestartCount`. Pi fold-ins per §11 — **none of them landed**, so the Pi visit is still owed.
- [x] **vps**: `docker` → `monitoring`; then the guarded legs per §11 (`guarded-converge.sh` for headscale/headplane — `Running=true` between crashes is not liveness). ⚠ the `docker` leg restarts the tailnet sidecar and Traefik: on `vps` those acts go **LAST**, or the converge kills the channel it runs on (measured the hard way — both Phase-4 lanes died on it once).
- [x] **nas**: the monitoring leg with `--skip-tags alloy` + the storage legs; the `alloy` re-render followed in its own lane, so `nas` reports (§11).
- [x] **oldsrv**: `docker` → `monitoring` → `tailscale-node` — **from this seat only**, the guard refuses the `tailscale-node` leg from oldsrv. Read back: docker family at the pins, `alloy 1.21.2-1`, `tailscale 1.104.2`, the same 8 holds, `match 8 / differ 0`, `RestartCount` sum 0. Fold-ins per §11.
- [ ] **spark**: docker family **after** the OTA in Phase 6 (§7: the toolchain, then the flip). ⏭ not this run — the `monitoring`/`alloy` legs are the S8 exception and they landed, which is why spark publishes the new pin map over old packages (§1).
- [ ] ⏭ **owed on the next VPS pass — HD-191's VPS `kopia-agent` leg** (ridden, not carried: the row owns itself):
  first the sizes — `du -sh` over `/opt`, the `db-backup` dump volume and `/srv/docker/*`, plus one snapshot of
  one small state dir from a throwaway client, written back to [docs/backup.md](docs/backup.md) before any include
  list is authored — then the registry row + compose and its `docker_services` converge in this host's leg, LAST
  for the sidecar/Traefik reason above. ⛔ `db-backup` stays the Postgres restore path; the exclusions oldsrv's
  agent carries are re-declared, not inherited.
- [ ] ⏭ **owed on the next VPS pass — the `docker_services` pin propagation never ran on `vps`**: deployed there is
  open-webui `0.11.4`, authentik `2026.8.3`, immich `v3.2.4`, tuwunel `v1.9.3`, element-web `v1.12.30`, while
  [`IaC/ansible/group_vars/all/versions.yml`](IaC/ansible/group_vars/all/versions.yml) pins `0.12.3`, `2026.8.5`,
  `v3.3.5`, `v1.9.4`, `v1.12.32` — the `vps` leg above ran `docker` → `monitoring` only, so no compose render ever
  moved. Consequence for any later scoped act on that host: touching either service recreates it at the pin, so an
  identity or routing fix must **hold** the versions (`-e openwebui_version=0.11.4 -e authentik_version=2026.8.3`) to
  stay one act — and prove the hold with `--check` both ways. The propagation itself is an **IdP recreate with
  migrations**, so it is an owner-present act, LAST for the sidecar/Traefik reason above.
- [x] Per host after it converges: the roster is up, `RestartCount` flat, and the role's own `apt-mark showhold` assert passed.
- [x] `todo.md` — the fold-in rows this phase proved, once.

### Phase 5 — router / switch items (global slot, after the Debian hosts)

- [ ] ⏭ **parked (ruling N3 — no router/switch act this run).** WG / PPPoE / NUT-client / SNMP re-apply legs that the router or switch must see (the VPS `wireguard` leg restarts the tunnel every off-box converge rides — run it **last**, then re-verify every tunnel path).
- [ ] ⏭ **parked (N3)** — anything needing a router window (HD-1160, HD-1142, HD-1140) is taken here or explicitly parked in its row; ⛔ never `--diff` on that playbook (it dumps the PPPoE password).
- [ ] `todo.md` — the network rows, once (nothing to fold in while Phase 5 is parked).

### Phase 6 — spark, last and solo (one slot; not in a spark-served session)

- [ ] **Phase 6 is unrun** — no OTA, no spark docker-family apply, no engine-key rotation, no profile flip. Preflight:
  no other converge in flight, every lane worktree idle, `/` free-space number recorded. It needs an
  **externally-served** session (Rule 0) and the owner present. The one spark act that did run is the
  `monitoring`/`alloy` pair ruling S8 allows, with the engine id / `StartedAt` / `RestartCount` read either side.
- [ ] OTA `OTA2610` → **reboot** → the boot checks: `kho=off` in `/proc/cmdline`, the `nvidia-spark-cloud-init` drop-ins, `nvidia-spark-mlnx-firmware-manager` ran its boot pass, the headless masks and `multi-user.target` survived, `spark-gpu-clock-cap.service` ran, `jupyterlab_ports.yaml` still maps admin → `11002`, and `dgx-dashboard.service` is still the only dashboard unit, loopback-bound and now **masked**.
- [ ] Re-derive [docs/hardware-spark.md](docs/hardware-spark.md) §Identity from the box: kernel, OTA level, dashboard version, UEFI date, QSFP delta #2.
- [ ] The pin converge (`docker`), then `curl -sf localhost:8000/health` **on the box** — the edge 502s for reasons that are not the engine's, and `traefik-spark` restarts with the daemon regardless of its restart-guard exclusion.
- [ ] **spark joins headscale as the THIRD home node** — the IaC is already on `main` (`tailnet_spark_ip` + `tag:spark` + the address-scoped `tcp/443` grant + the `lm-ts` entrypoint), and every bit of it is inert while the var is empty. In this order: mint the key (`docker exec headscale headscale preauthkeys create --tags tag:spark --reusable --expiration 8760h -o json`, the value is under the JSON key `key`) → store it as `tailscale-spark_api` → the join leg **off-box** (`--tags tailscale-node`; the self-converge guard refuses it on-box) → read the tag AND the address back from `headscale nodes list -o json` → set `tailnet_spark_ip` and commit → the vps `headscale` policy converge → the spark `spark-dashboard` converge. ⚠ The tag is read back, never trusted from the mint command, and `tag:dev`/`tag:home-edge` are refused — a borrowed tag is by-tag widening ([docs/network-rejected.md](docs/network-rejected.md)).
- [ ] Its read-back: `ss -ltnp | grep ':443'` on spark lists `spark_home_ip` and the node address and **never** `0.0.0.0`; `curl -sk --resolve llm.kogler.si:443:<tailnet_spark_ip> https://llm.kogler.si/v1/models` answers with the bearer and 401s without it; `tailscale status --json` keeps `PrimaryRoutes` empty on every peer — the boundary must not have moved because a third node arrived.
- [ ] ⛔ **The `llm.kogler.si` answer flip is NOT in this window.** It needs BOTH halves on the zone entry — `tailnet: node`/`dual` **and** an explicit `tailnet_ip:`, since the class default for those is oldsrv's node — it moves the answer for every client, and `node`/`dual` publish the `.ts` twin only. It lands on the converge that re-renders headscale's `config.yaml`. Tonight the node answers the **port**, not the **name**: prove it with the `--resolve` form above, not with `dig`.
- [ ] `spark-llm_api` + `litellm-engine_api` rotation → spark converge carries the new accepted list → prove the second key live **by hand** (`scripts/secrets/rotate-spark-llm-key.sh` does not know it) → HD-384 step 2: converge `lan-litellm` + `litellm`. ⛔ Inverting this order 401s every upstream call.
- [ ] The A+ **runtime dispatch check**: does a real bf16 GEMM land on a `(12, 1)` plan rather than the `F.linear` fallback. No build can answer this.
- [ ] Flip `fast-v32-bf16` (`-e spark_llm_profile=fast-v32-bf16 -e spark_llm_allow_uncertified=true`, detached; ~20 min cold boot) and read the engine's `GPU KV cache size` line — expecting **644,599 slots / 2.46×**. Another number means the pool arithmetic moved under the port.
- [ ] Gates 0–7, then flip `fast8`, then the dtype gates 8–9. Rollback at any point: `-e spark_llm_profile=fast` plus a detached converge (`spark-rollback:fast` = `4900c13edab9…`, archived twice on the NAS).
- [ ] ⛔ Never rebuild the lineage in this window, never retag `qwen38-flash-dgx:iter6c|iter6d`, never prune the build cache — report the free-bytes number instead. The post-build CPU gates assert day-0 bytes: on v32 their red is not a verdict and their green would not be one either (HD-1210) — read the artifact markers.
- [ ] **HD-494's rest-floor measurement** (ridden, not carried): `bash scripts/bench/spark/usable-sampler.sh` takes
  1 s `usable` across one heavy prefill **in this boot window**, on an externally-served session (it refuses a
  spark-served seat on its own first line — `--self-test` proves that offline), and prints the delta against the
  ledger's rest prediction. The owner's ruling is that **the delta picks the floor** (CRIT vs WARN) — so the
  number is taken before anything is written to IaC, and the detached pin converge above is what boots the
  profiles against the floor that follows from it.
- [ ] `todo.md` — HD-1206's window tail and HD-384, once.

### Phase 7 — re-seat and re-check

- [x] Re-seat every `op_api` consumer: all four Debian installs — oldsrv control node, oldsrv seat `domen`, this laptop, and
  the `vps` control account `ansible-admin` — are re-seated with the **pipe form**, proved by Integration ID + `sha256[:12]`
  on the file route AND in a fresh interactive shell (a running shell's exported value beats the file, and
  `bootstrap-runner.sh` is create-only). ⏭ nothing owner-side is left on `op_api`: the integration's scope, the Actions
  secret/runner stores, and `oldsrv`'s root account are settled facts in
  [docs/1password.md](docs/1password.md) §Credential source / §Where a token is installed.
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
(§3) · rotate everything the gate names, the n8n/kopia consequences scheduled rather than avoided (§5) — a re-key
starts only when its consequences fit the same sitting · the unattended sittings run **no router/switch act** and
**no spark act**, narrowed for spark to the `monitoring`/`alloy` scope that cannot touch the engine or the network
(Phase 5/6) · `op_api`
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
| **pi** | HD-443, HD-1103 · HD-1167 · HD-1109 | the pin legs ran; ⏭ **none of the fold-ins landed** — `access_admit_extra` still lists `admin` in `host_vars/pi.kogler.si.yml`, the ruled `rotate 1` + `maxsize` logrotate file is not in the tree, `pi-eth0.nmconnection` is unedited, so the Pi visit is still owed (fstab `mode=`, the boot that makes it true, the one-time re-render, the UNTAGGED leg applying `ai_diag`'s derived smartd mask). ⛔ the `nm-resolver` applies and HD-418's reconcile are done |
| **vps** | HD-1166, HD-1173, HD-1106, HD-487, HD-191 | HD-1166's page is closed on the box (one `--tags monitoring`, no UI mute); HD-1106's named-volume fix applied **before** any `docker volume rm`, so the WOPI keypair survived the recreate; the headscale records-file re-render is live with the parsed delta empty both ways. ⏭ HD-487 parked by ruling — `--check` shows one `20-eno1.netdev` removal, and a networkd apply does not ride the act that costs the control channel; the `op-write_api` host render is issued **from this laptop** (`self-converge-guard.yml`); HD-1173 needs the VPS converge that drops the routers + MagicDNS records; **HD-191**’s VPS `kopia-agent` leg is owed here — the sizes first, then the container + include list, LAST in this host’s leg order |
| **nas** | the rotated SMB pair (its row is closed) | `storage_samba_password_force` landed the pair and the passdb was re-read **over SMB** — authenticated tree connects, cross-share denied, anonymous refused; a vault edit alone changes nothing on the box. The replica retag and the wedge reap are in [docs/storage.md](docs/storage.md) §A |
| **oldsrv** | HD-1122, HD-1088, HD-1175 | HD-1122: ⚠ **no flip was owed** — `ai_tier_metrics_publish` is already `true` and both llama.cpp legs are scraped, so the owed half is an authored `llamacpp:*` panel. HD-1088 needs the Box key registered in the Hetzner console first (port 23, key-auth-only). HD-1175's root-only journal/`pstore` read ran: one boot ended in a `crash`, `/sys/fs/pstore` empty, only `efi_pstore` (no ERST/ramoops/`memmap=`), no mcelog/EDAC ⇒ no cause is recoverable and the box is structurally un-instrumented for the next one |
| **spark** | HD-1206, HD-384, HD-473, HD-1210, HD-494 | the dispatch check → `fast-v32-bf16` → gates 0–7 → `fast8` → gates 8–9, one boot shared with the rotation. ⏭ only the `monitoring`/`alloy` legs landed (ruling S8); everything else here waits for Phase 6 |
| **router** | HD-1160, HD-1142, HD-1140, HD-1136 | the global slot, and none of them is a converge. ⏭ **nothing ran** (ruling N3): no router or switch act, no WG / PPPoE / device-SNMP write |

**Held out, on purpose:** the Wi-Fi PSKs (`wifi-kogler*` — live PSKs, every device rejoins by hand, the Shellys
re-provisioned one by one, and nothing in IaC writes them because `routeros_capsman_enabled: false` leaves the rendered
rsc as the delivery path) ⇒ the leak gate stays red on exactly those items; `alloy` on `nas` was held out of the
monitoring leg (`--skip-tags alloy`, another session was debugging that collector) and the collector has since been
re-rendered and reports, so that gauge exception is **closed** — `nas` needs no `differ` exception; the 7 majors + 4 downgrades, hence HD-1100's PG 18 legs; `ollama`'s `-rocm` alias;
`home_assistant` minors; every digest-pinned image; and the §D owner-eyes items (visual passes, device walks, drills),
which need neither a converge nor this window.

