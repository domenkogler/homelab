# Lane brief — HD-361 cockpit / coding-seat / grants lane (wave 3)

> **Role:** dispatch brief for one lane session on `oldsrv`: the Cockpit break-glass hosts, the coding-cockpit
> seat daemons, and the SSH-grant plumbing. The rows ([todo.md](todo.md) HD-361 · HD-411 · HD-442 · HD-443 ·
> HD-444 · HD-445 · HD-446 · HD-465) stay the authority for WHAT is missing; this brief carries the lane
> contract, the landed state a re-run must not redo, and the traps that cost rounds. Design SSOTs:
> [docs/security.md](docs/security.md) (cockpit `maint`, grants rulings),
> [docs/services-traefik.md](docs/services-traefik.md) §Cockpit Routes,
> [docs/services-ai.md](docs/services-ai.md) §9b (the seat plane), [docs/pi-harness.md](docs/pi-harness.md) §1/§4,
> [docs/deployment-secrets.md](docs/deployment-secrets.md), [deployment-manual.md](deployment-manual.md) Phase 4c.
> **Dies with the lane** ([docs/orchestration.md](docs/orchestration.md) O7): last row closes → orchestrator
> deletes this file with its link fixes; residue folds back into the rows.

**Converge host:** **oldsrv** (`roles/cockpit/**`, `/opt/traefik-internal`, seat units) — one converge in
flight (O3); ⛔ never pair with [prompt-384.md](prompt-384.md) or [prompt-357.md](prompt-357.md) (same slot).
nas / pi are read-back only. Owner-gated rows (411 phone hands, 444 the phone crossing) follow O4: park and
continue, name the exact blocked action.

## Landed — do not redo (measured, 2026-09-28 unless noted)

- **HD-361:** `--tags cockpit` from the laptop → `ok=50 changed=6 failed=0`; acceptance passed — `GET /cockpit/login`
  with Basic auth = **200** for `maint`, groups exactly `maint sudo cockpit-session`, gate line at
  `/etc/pam.d/cockpit:3` BEFORE `substack common-auth` at :5, installed hash byte-matches the vault.
- **HD-442:** the vault pre-pass replaced the stale `/etc/op/provision-token` (probe ok, `op item list` rc 0
  by hand); `cockpit-pi-web_api` minted carrying the SAME bearer, proven by fingerprint
  (`sha256[:16]=b774df36bb26144c` seat == vault, length 55, read back through the READ-scoped SA).
- **HD-445 route+bind half:** `pi-oldsrv-ts` + `pi-oldsrv-backend` live in `/opt/traefik-internal/dynamic/routes.yml`;
  Phase 4c step 6 ran — `tailnet-bind.conf` → `loopback-bind.conf`, `31415` listens on **127.0.0.1 ONLY**, edge
  answers HTTP/2 `401`/`302` with token while the LAN entrypoint keeps answering 404 — tailnet-only by
  construction; `cockpit_pi_web_port` is now consumed by the backend (port edit = one change).
- **HD-443 gate:** `scripts/check_ssh_grants.py` green on the live set (rc 0, 17 grants / 5 hosts) after the
  per-(key, host, account) + violation-KIND fix with `--self-test` both directions.
- **HD-465 premise twice dead:** the `.ts` name IS published (since `97d9fbf`; live headscale config read
  2026-09-26 contains it) AND oldsrv answers again. Do not re-open without a new fact.

## Remaining per row (row = authority; this is the lane map)

- **HD-361** — authenticated pane in a browser per host. Probe truth: `GET /` answers 200 UNAUTHENTICATED,
  `POST /cockpit/login` is 405, only `GET /cockpit/login` + Basic yields a truth-telling 401/200 — and even 200
  leaves cockpit's real Origin check (WebSocket handshake) unproven: that is what the browser load is for.
  The nas-from-away half is blocked by HD-465, not by cockpit.
- **HD-465** — the missing piece is a DEPLOYED router: oldsrv's `/opt/traefik/dynamic/cockpit.yml` is the
  2026-09-03 render (two LAN `Host()` rules only), so `Host: cockpit-nas.ts.kogler.si` on the tailnet listener
  404s. ⛔ The converge alone is NOT sufficient: `roles/cockpit` hardcodes that path — a dead render on oldsrv
  (it is the VPS traefik's file); the `cockpit-nas-ts` router authored 2026-09-24 in
  `roles/cockpit/templates/cockpit-routes.yml.j2` has never reached any live edge. ⛔ A read-back from the Pi
  proves nothing (`/etc/resolv.conf` is `1.1.1.1`, cannot resolve `.ts`). Being away is not the blocker — being
  off the tailnet is. Owner call stands: which node OWNS Cockpit.
- **HD-442** — the damage audit: what the oldsrv-side glue and key-provisioning passes were supposed to write
  since the token went stale and never did, verified one by one. ⛔ Any consumer treating a token file's
  *existence* as its *validity* must fail loud on 403 — a provisioner that ignores rc is how a dead credential
  survived eight green converges. ⚠ Mint trap (real failure): `ssh oldsrv` = the **ansible-admin** seat, not
  `domen` (alias contract), and `/home/domen/.config/pi-web/env` is `0600 domen` — an unprivileged read yields
  EMPTY, and hash-vs-hash "matches" empty-against-empty: assert LENGTH before comparing fingerprints
  (CONVENTIONS §6: two identical failures compared against each other are not evidence).
- **HD-443** — order of work: own users + `authorized_keys` in a role (`--check`-safe first try; today
  preseed/`first-boot-config.sh` write them imperatively = the HD-445 class) → converge `ansible-admin` +
  `domen` + `ai-debug` on reachable nodes → re-run the auditor. The Pi `admin` retirement was **attempted and
  reverted 2026-09-28**: the consumer of `admin` was the operator's own `~/.ssh/config` (`Host pi` →
  `User admin`) — 90 accepted admin logins vs 16 ansible-admin in 30 days; re-read the revert first. ⛔ The
  order is the safety property: prove `ansible-admin` logs in → comment the line out with a dated marker →
  prove the dependent paths → only then remove (HD-413 lockout set). Owner 30 s laptop rename of the
  SSH-agent stub stays in the row. HA guests (`haos-vm-1`, `haos-mininta`) are a declared scope limit, never
  "clean". ⛔ The auditor never touches an `authorized_keys`; a gate that goes green by calling reality
  intentional is not a gate.
- **HD-445** — decide the home (host-level role; `docker_services` is wrong — not containers, owner-decided),
  render unit + drop-in + env path + linger from the vars; `paseo_port` stays an unconsumed reservation while
  HD-411 is parked; `tmux` on oldsrv is the owning role's package decision, not a hand `apt install`.
  ⚠ Manual defects found by PERFORMING Phase 4c (owed back to the manual): the derive one-liner awk prints
  NOTHING (match starts after the colon, `.*` eats the value — silently empty `$PORT` until a length assertion
  caught it); `systemctl --user enable --now` does NOT restart a running unit — the act is `restart`.
- **HD-444** — owner hand only: PWA on the phone over the tailnet, token gate + session list + one chat
  round-trip **with the laptop shut**. Every node reachable from the laptop session is itself ACL-scoped away
  from oldsrv (the VPS sidecar answers `no matching peer` — the ACL WORKING), so no test has yet crossed the
  headscale policy the phone will cross; if it denies phone → oldsrv on the cockpit port, record the exact
  denied pair (transport lane's file), do not edit it here. This gates HD-411's comparison window.
- **HD-411** — PARKED 2026-09-23 (browser cockpit is primary by design; Paseo acceptance needs a hand on the
  phone; a second unattended third-party daemon stood up at 02:30 that nothing can end-to-end-test is worse
  judgment than parking). Resume facts: the real install is `npm install -g @getpaseo/cli` then `paseo` —
  bare `npm i paseo` is a **name-squatted Next.js scaffold** and `@paseo/cli` / `paseo-ai` / `@getpaseo/daemon`
  do not exist. Posture: bind the daemon to the tailnet address only, bcrypt password, `daemon.hostnames`
  allowlisted, optional E2E relay OFF; `remote-pi` (mandatory non-E2E relay) is declined and logged. Shared
  blockers inherited from HD-445 (no owning role) and the vault (password cannot be minted until the seat's
  write path is used — see [docs/deployment-secrets.md](docs/deployment-secrets.md)). Verdict lands in
  [docs/services-ai.md](docs/services-ai.md) §9b either way; the browser cockpit stays primary regardless.
- **HD-446** — sibling, not fork, of `install-pi-wsl.sh`: Node ≥ 22.19.0 vs Debian 13's apt candidate 20.19.2
  (apt install = a harness that cannot start) → pinned official tarball under `~/.local/share/pi-node/`, then
  `npm install -g @earendil-works/pi-coding-agent`; encode the measured traps. Write it before the THIRD pi
  host, not before.

## Traps that apply lane-wide

- ⚠ `--tags cockpit --check` can never be green on ANY host: every read-back is a `command`/`shell` task
  skipped under `--check`, so asserts read empty stdout and scream `group-set-not-exactly-as-decided` /
  `sshd-has-no-allowusers-gate` / `pam-gate-missing-or-ordered-after-common-auth` on a healthy box. The fix
  shape is `check_mode: false` on those read-back tasks (precedent + rationale: the `docker_services` op bulk
  pre-pass); `check_self_converge_guard.py` permits it for a guarded, non-`check_safe` role.
- ⚠ `cockpit` is in the HD-413 lockout set — drive it off-box.
- ⚠ The seat is `domen` + linger; a rebuild of oldsrv today loses the cockpit silently until HD-445 lands.

## Acceptance

Each row's ⏳ list empty → row deleted (record in the owning doc + commit); cockpit-nas answers from away in a
browser (HD-465), the phone crossing recorded honestly (HD-444), grants owned by a role and re-audited
(HD-443), seat owned by a role (HD-445). When the last row closes: this brief dies in the orchestrator's
cleanup commit (O7).

## Lane rules

Full contract: [docs/orchestration.md](docs/orchestration.md) §4 (O1–O8). Touch only your own rows; never edit
`prompt.md` / `todo-table.md`; write the manual line for any hand-repeatable step you performed (O6).
