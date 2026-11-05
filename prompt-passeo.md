# `prompt-passeo.md` — Lane brief · the Paseo coding seats (win11 · wsl · oldsrv), and the cockpit they retire

> **Role:** dispatch note for **one** lane session on the Paseo seat domain. **The rows are the authority**
> for what is missing and how to do it — this file carries the contract, the order of work, the measured seat
> state and the traps, nothing else: [todo.md](todo.md) **HD-411 · HD-1240** (row ids as of this brief —
> re-derive with `grep -c "^| HD-<id> " todo.md` before quoting one).
> **Linked from:** [todo-table.md](todo-table.md) §B0 · [todo.md](todo.md)

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O11) — read it once; it overrides README §4
and CONVENTIONS §6 at the items it numbers, and this brief restates none of them.

**Converge hosts + slots (O3):** **oldsrv** only — `roles/seat` (the seat's host side) and `traefik-internal`'s
`websecure-ts` listener (the `.ts` router). Neither is in the SSH/PAM lockout class, so `--check` and apply both run
from the controller; ⛔ never converge the seat role *from* oldsrv's `domen` home. `win11` and `wsl` are **not**
converge hosts: their seat state lands through the seat × plane matrix (`scripts/harness/pi-seat-sync.sh` +
`scripts/lib/seat-planes.yml`), and the Windows acts need elevation, so they are owner legs (O4), not lane legs.
Before any `scripts/harness/**` hunk: `git worktree list` + `git log --oneline -3 -- scripts/harness` — a live
pi-seat lane edits the same directory.

**Read first:** [docs/services-ai.md](docs/services-ai.md) §9b-1 (the placement decision this lane supersedes) →
[docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1 (the plane matrix + which shell answers on win11) →
[docs/1password.md](docs/1password.md) §1 for the `op` scope read (prove it with the Integration ID), then the
`cockpit-pi-web_api` row in [docs/deployment-secrets.md](docs/deployment-secrets.md) that this lane closes → [docs/network-dns.md](docs/network-dns.md) §The answer-plane model (why a `.ts` name answers
on Windows and nowhere in WSL) → [docs/security.md](docs/security.md) (the tailnet grant) → upstream:
<https://paseo.sh/docs/connectivity>, <https://paseo.sh/docs/configuration.md>, <https://paseo.sh/docs/cli>.

## Seat state, measured 2026-11-05 (re-derive every line; none of it is a verdict)

| | **win11** | **wsl** (Debian) | **oldsrv** (`ssh oldsrv-domen`) |
|---|---|---|---|
| CLI | 0.15.0, bundled: `AppData\Local\Programs\paseo\resources\bin\paseo.cmd` | 0.15.0, `~/.local/share/pi-node/current/bin/paseo` | **same path**, invisible to a non-login shell |
| `~/.paseo` | present | present | present — the rendered unit runs the daemon there |
| `daemon.listen` | `0.0.0.0:6767` | `0.0.0.0:6768` — file and running process agree, and the process answers `127.0.0.1:6768` too | the unit's `PASEO_LISTEN` drop-in: `127.0.0.1:6769` |
| daemon | running, `desktopManaged: true`, `daemonNode` the app's own `%LOCALAPPDATA%\Programs\Paseo\Paseo.exe` — which daemon answers 6767 is `settings.daemon.manageBuiltInDaemon`, see row 2 | running, **hand-started**: `paseo.service` `not-found` at user and system level, `Linger=no`, no `user@.service.d` drop-in, so nothing restarts it — the boot carrier is the open leg | running under `paseo.service` (`ActiveState=active`, `PASEO_RELAY_ENABLED=false`) |
| relay | off | off | off |
| password | the `paseo_password` bcrypt hash in `config.json` | the same hash in `config.json`, read by the running daemon: an unauthenticated `GET /api/agents` answers `401` | the item's plaintext in the unit's 0600 env file |
| transport facts | tailnet node `domen-p14s` (`tailscale ip -4`), the Tailscale adapter lands in the **Private** profile; both door rules scope to the tailnet `/10`, the portproxy targets loopback, and a non-tailnet source gets nothing | NAT address from `hostname -I`, **no tailnet inside the distro**; Windows reaches it at that address *and* at `localhost` | tailnet node `oldsrv` (`tag:dev`); loopback `:6767` is **Bazarr**, `:31415` is `pi-web`, Paseo binds `:6769` |

```bash
P=~/AppData/Local/Programs/paseo/resources/bin/paseo.cmd; cmd //c "$(cygpath -w "$P") daemon status"   # win11
wsl -d Debian -- bash -lc 'paseo status; cat ~/.paseo/config.json'                                     # wsl
ssh oldsrv-domen 'bash -lc "paseo status; ss -ltnH | awk \"{print \$4}\" | tr \"\\n\" \" \"\n"'         # oldsrv: login shell or bust
```

## Order of work

| # | Row | Do | Gate / trap |
|---|-----|----|-------------|
| 1 | **HD-411** | **oldsrv daemon, as repo state.** Per-seat port map in `group_vars/all/main.yml` (the single `paseo_port: 6767` is dead on arrival there — see the traps), then `roles/seat` gains the paseo leg: a systemd **user** unit, a loopback-bind drop-in, a PATH drop-in, the password env file, linger — mirroring the pi-web legs it replaces | ⛔ A systemd **user** unit reads neither `~/.bashrc` nor `~/.profile`: on oldsrv `paseo`, `claude` and `pi` are all invisible to a non-interactive login shell, so the unit dies on PATH unless it carries `Environment=PATH=` with **both** pi dirs (`seat_pi_bin` + `seat_pi_node_bin` — the lesson pi-web's `pi-on-path.conf` exists to teach). Prove it the way the unit sees it: `systemctl --user show -p Environment`, not `bash -lc which` |
| 2 | **HD-411** | **win11 daemon: `listen: "0.0.0.0:6767"`, relay off.** `daemon.listen` is a single string (schema), so a tailnet-IP bind is one listener that **cannot bind when Tailscale is down** — and `manageBuiltInDaemon: true` means the desktop app loses its own daemon with it | The tailnet-only boundary therefore moves into the **firewall rule**: inbound tcp 6767 for `%LOCALAPPDATA%\Programs\Paseo\Paseo.exe`, **remote address `100.64.0.0/10`**, so the LAN never gets a socket. `Host: <ip>:6767` → **200**, `Host: whatever.invalid` → **403**, so a direct-IP pairing needs no `daemon.hostnames` entry. Which daemon owns 6767 is one read: `paseo daemon status` answering `desktopManaged: true` with `daemonNode` under `%LOCALAPPDATA%\Programs\Paseo\Paseo.exe` is the app's built-in one, and `settings.daemon.manageBuiltInDaemon` (+ `keepRunningAfterQuit`) in `%APPDATA%\Paseo\desktop-settings.json` is what decides it — nothing on this box starts the CLI daemon at sign-in (no Run key, no Startup entry, no scheduled task, no service, no autostart verb in `paseo daemon --help`), so keeping the built-in daemon first is that setting and not an uninstall. ⛔ Never bind the tailnet IP on a laptop, and ⛔ `paseo daemon start` / `paseo daemon run` on this seat — the two share one `~/.paseo` home and one listener |
| 3 | **HD-411** | **wsl daemon: `listen: "0.0.0.0:6768"`, relay off, a systemd user unit** (`[boot] systemd=true` is already set). Desktop reaches it at `localhost:6768`, tailnet down included — the answer to "can I still run both laptop seats from the app off the tailnet" | Phone leg = a Windows portproxy from the laptop's tailnet address on `:6768` to **`127.0.0.1:6768`** (target **loopback**, not the WSL address: `localhostForwarding` finishes the hop, so the rule survives a reboot where an address-targeted one does not). Verify that target once when you run the elevated command, then read the leg at its end: `netstat -an \| findstr <tailnet-ip>:6768` → `LISTENING` and one unauthenticated `GET http://<tailnet-ip>:6768/api/agents` → `401`; the table alone is not that answer (see the traps). `bash scripts/harness/seat-paseo.sh --check --strict` → `OK: seat wsl` grades the seat's **file**, so it says nothing about either socket. The open leg is the boot carrier: `paseo.service` `not-found` at user and system level and `Linger=no`, with no `user@.service.d` drop-in. ⛔ Do not switch the distro to mirrored networking to dodge this: the `dns-route` and `llm-path` planes derive the WSL NAT gateway from `ip route` |
| 4 | **HD-411** | **The `.ts` door on oldsrv**: one zone row + a `paseo-oldsrv-ts` router + backend on `websecure-ts`, exactly the `pi-oldsrv-ts` shape | The ACL grants peers **`tag:dev:443` and nothing else**, so the oldsrv node's tailnet address on `:6769` from the phone is a timeout by design. ⛔ Never a `tailscale0`-address bind (rejected: plain HTTP, no cert, `no matching peer`). Behind Traefik, set `daemon.hostnames` + `trustedProxies`, or the Host check 403s what the ACL allowed |
| 5 | **HD-411** | Pair: the desktop app adds `ssh://domen@oldsrv-domen?daemonPort=<port>` (SSH transport expects the far daemon on `127.0.0.1:6767` and does **not** start it) and `localhost:6768` for the WSL seat; the phone adds the three daemons directly | Mobile has **no Remote SSH** (upstream discussion #4800) — only desktop and CLI. So the phone must reach a *reachable* daemon per seat; "pair once to the laptop, see everything" is unproven, and whether a mobile client inherits a daemon's `paseo host` entries is undocumented — **test it before designing around it**. Your own nodes are ACL-granted on every port (`dst: ["domen@kogler.si:*"]`); `oldsrv → the laptop's tailnet address` was measured as a timeout |
| 6 | **HD-411** | Owner verdict, from cellular, per seat: auth gate, agent list, one round-trip. Lands in [docs/services-ai.md](docs/services-ai.md) §9b either way | Both laptop seats answer from cellular across the tailnet: `win11 <tailnet-ip>:6767`, and `wsl <tailnet-ip>:6768` through that one portproxy. **The `oldsrv` round-trip is the leg not taken**, and HD-1240's delete waits behind it. ⛔ A phone leg with no read is not a denial (CONVENTIONS §6) |
| 7 | **HD-1240** | **Retire `@ygncode/pi-web`** once step 6 passed on oldsrv: `roles/seat` (unit, both drop-ins, token env, the `--cockpit` assert and handler), `install-pi-debian.sh --cockpit`, the `settings` plane's `--with-package npm:@ygncode/pi-web` record, the seat-local fixture arms in `pi-settings-config.sh`, `pi_host_web_npm_*` + `pi_pkg_web_*`, the `pi-oldsrv-ts` router + backend, the `pi-oldsrv`/`pi-dev` zone rows, `pi-oldsrv-backend`, and the `cockpit-pi-web_api` row → **revoke the item** (that is HD-442's open decision, answered by this ruling) | ⛔ `pi_web_access_version` / `pi_pkg_web_access_*` is the **`pi-web-access`** extension (in-session web search) — **it stays**, owner-ruled. And `IaC/ansible/templates/docker_services/bazarr/docker-compose.yml.j2` carries a comment asserting paseo binds the tailnet address, so 6767 "cannot conflict": that claim is **false on oldsrv**, and the comment is the thing that made the collision invisible |
| 8 | **HD-1240** | **Retire `pi-web-ui`** — two lines: the `pi_web_ui_version` pin and its `scripts/ansible/image-pin-probe.py` entry | Nothing installs it: no consumer, no unit, no door. A pin with no reader is retired by deleting the pin, not by searching for a leg |
| 9 | **HD-1240** | Docs as state: [services-ai.md](docs/services-ai.md) §9b-1's two surface rows and its §10 open-work item, `docs/network-dns.md`'s `pi-oldsrv.ts` paragraph, `deployment-manual.md` + `deployment-tasks.md` Phase 4c, the secrets rows | ⛔ No session narrative in any of them (CONVENTIONS §6); the seat's `import` of old `~/.pi/agent/sessions/` corpora is a fact for that section, not a milestone here |
| 10 | **HD-1240** | A `paseo` plane in `scripts/lib/seat-planes.yml` with an owner script under `scripts/harness/`, so a reimaged seat comes back with the same `config.json` instead of the same folklore | The registry refuses an owner that is not under `scripts/` and an unknown key — `bash scripts/lib/pi-seat.sh --self-test` is the gate, and `pi-seat-sync.sh --check` is the per-seat verdict |

## ⛔ Traps that cost a round

* **`paseo` is a name-squatted npm package.** The real install is `@getpaseo/cli`. A bare `npm i -g paseo` is not this tool.
* **A seat without a login shell has no PATH.** Every "it is not installed there" reading this session produced was
  a probe shape, not a fact: `ssh host cmd` reads neither startup file. Ask `bash -lc`, then ask the unit.
* **`~/.pi/agent/sessions/` is a prerequisite of pi-web only.** Do not carry that install step into a paseo leg.
* **The ACL is not the phone's blocker and never will be.** Own nodes are open on every port; tagged devices reach
  `:443`. If a phone leg times out on a non-443 port against oldsrv, the answer is a router, not an ACL widening.
* **Windows firewall rules bind to the process image.** The desktop-managed daemon's image is `Paseo.exe`, so the
  pile of `node.exe` allow rules on this box proves nothing about it.
* **`op` reads: prove scope with the Integration ID, and check the **field** name.** A lookup on an absent field
  renders an empty file and the failure surfaces as an auth error on the far side — the `cockpit-pi-web_api` row is
  that bug already written down. Report lengths, never values (§6).
* **Seat legs run FROM their own seat** and an unreachable seat **fails** the run; a clone behind this commit is
  `STALE-CLONE` and its planes do not run. On win11 run harness legs from Git-Bash (`System32\bash.exe` is the WSL
  launcher wearing the name `bash`).
* **A portproxy row is configuration; only its socket is a path.** `netsh interface portproxy show` — what
  `scripts/harness/win/paseo-seat-door.ps1 -Check` reads — keeps printing an entry whose listen address was absent
  when IP Helper read the table, so the seat reads configured and the phone gets nothing. The elevated `-Push`
  (delete, then add) is what binds it; `netstat -an | findstr <tailnet-ip>:6768` → `LISTENING` and one
  `GET /api/agents` there → `401` are the two reads that settle it
  ([docs/services-ai.md](docs/services-ai.md) §9b-1).
* **A seat checkout behind main runs an older copy of its own reader.** `100.64.0.0/255.192.0.0` IS
  `100.64.0.0/10` and a `netsh portproxy show` output is a column table with no `ip:port` token in it, so a reader
  that text-compares either prints a confident red on a correct box — pull the seat's checkout, then
  `scripts/harness/win/paseo-seat-door.ps1 -SelfTest`, before believing a red from it, and let the socket be the
  last word ([docs/services-ai.md](docs/services-ai.md) §9b-1).

## Owns / never touches

**Owns:** `IaC/ansible/roles/seat/**`, `IaC/ansible/group_vars/all/seat.yml`, the Paseo port block in
`group_vars/all/main.yml`, the `paseo-*`/`pi-oldsrv-*` routers in `traefik-internal/dynamic/routes.yml.j2`, the
`pi-oldsrv`/`pi-dev`/`paseo-oldsrv` rows in `zone_kogler_si`, `IaC/ansible/group_vars/all/versions.yml` (the four
pins this lane retires and the pin it adds), `scripts/harness/{install-pi-debian.sh,pi-settings-config.sh,seat-paseo.sh}`,
`scripts/lib/seat-planes.yml`, `scripts/harness/win/` (the portproxy + firewall carrier),
`scripts/ansible/image-pin-probe.py`, the seat surface of `docs/services-ai.md` §9b/§9b-1/§10,
`docs/deployment-secrets.md`'s cockpit row, `deployment-manual.md` + `deployment-tasks.md` Phase 4c, and your own
`todo.md` rows.
**Never:** `prompt.md` / `todo-table.md` (O2) or another brief's rows; headscale policy and the DNS answer plane (the
transport lane); traefik work beyond this lane's two routers; the Authentik clients (edge-identity lane); the
`roles/cockpit` console (a different "cockpit" entirely — see [services-ai.md](docs/services-ai.md) §9b-1's disambiguation note); `pi-web-access` in any
form; the Kopia/backup rows; the frozen archives and any generated `*-generated.md`.

## Acceptance

Every item returns `PASS` / `FAIL` / `BLOCKED` / `PARKED` + the number + the evidence path; a claim with no path
counts as not run. Concretely: the oldsrv daemon **running under a unit the repo renders**, its bind and its PATH
quoted from `systemctl --user show`; win11 answering across the tailnet with the LAN leg closed and the rule quoted;
the WSL seat reachable from the app with the tailnet **down** and from the phone over the one portproxy; the `.ts`
door loaded from **off** the tailnet; the phone verdict per seat quoted, not assumed; the retired legs gone from
**both** faces of every claim they lived in (role, pins, plane registry, routers, zone rows, docs) with
`pi-web-access` unharmed and `check_dns_seed_drift.py` + `check_zone_kogler_si_parity.py` green; rows trimmed to their
tails or deleted, no history in the row → `bash scripts/harness/gate-snapshot.sh --run` green in this worktree → **stop**.
