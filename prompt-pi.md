# Lane brief — move the pi dev seat to oldsrv (wave 3)

> **Role:** dispatch brief for the session that makes **oldsrv the day-to-day pi dev seat** instead of this WSL
> box. It **carries** the two seat-shaped rows no brief held — [todo.md](todo.md) **HD-492** (the seat's SSH door)
> and **HD-493** (seat parity) — and **sequences** the rows the move also needs: HD-442 · HD-443 · HD-445 · HD-446
> stay owned by [prompt-361.md](prompt-361.md), and HD-484 stays unbriefed. Every row is the authority for WHAT is
> missing; this brief carries the ordering, the state measured 2026-10-05 that a re-run must not re-derive, and the
> traps. Design SSOTs:
> [docs/services-ai.md](docs/services-ai.md) §9b-1 (the seat plane), [docs/pi-harness.md](docs/pi-harness.md) §1/§4/§5,
> [docs/deployment-secrets.md](docs/deployment-secrets.md) §Who is authorized where,
> [docs/network-dns.md](docs/network-dns.md) §The answer-plane model, [docs/network-vpn.md](docs/network-vpn.md)
> §The laptop alias contract, [deployment-manual.md](deployment-manual.md) Phase 4c.
> **Dies with the lane** ([docs/orchestration.md](docs/orchestration.md) O7): last row closes → orchestrator deletes
> this file with its link fixes; residue folds back into the rows.

**Converge host:** **oldsrv** (`roles/cockpit/**`, seat units + drop-ins, `/home/domen/.pi/agent/**`, sshd gate) —
one converge in flight (O3); ⛔ never in the same window as [prompt-384.md](prompt-384.md) / [prompt-357.md](prompt-357.md)
(same slot) or **HD-487** (oldsrv lockout-class — it edits the leg the converge rides). Because **HD-442/443/445/446**
are the 361 lane's rows, this brief and [prompt-361.md](prompt-361.md) are **the same slot — run one of the two**,
not both; this file is the seat-shaped cut of that lane, not a parallel lane. nas / pi read-back only.
Owner-gated rows follow O4: park and continue, name the exact blocked action (the phone drill **HD-444** and the
1Password stub rename inside **HD-443** are the two here).

## 1. Order of work

| # | Row | What it buys the move | Gate / how it was measured 2026-10-05 |
|---|---|---|---|
| — | *(nothing — already live)* | The cockpit seat works from the laptop today: `curl https://pi-oldsrv.ts.kogler.si/` → **HTTP 401 served from oldsrv's tailnet address**, LE `*.ts.kogler.si` pair validates without `-k`; `GET /api/models` 401 too | do not "fix" what is reachable |
| 1 | **HD-442** | Read-only damage audit of the oldsrv-side glue / key-provisioning passes — tells 443 what is actually missing instead of guessing | ⚠ its own trap: `ssh oldsrv` lands as **ansible-admin**, not `domen`; assert LENGTH before hashing anything |
| 2 | **HD-443** | A **role** converges users + `authorized_keys`; `domen` gets its `domen_ssh` key everywhere the ruling says | `domen` has **no** `/home/domen/.ssh/authorized_keys` on oldsrv; `check_ssh_grants.py --hosts oldsrv` exits 0 **because the grant is absent**, not because it is right |
| 3 | **HD-492** | The seat **SSH door**: `AllowUsers` admits `domen` + both workstation alias blocks work | `sshd -T`: `allowusers ansible-admin` + `ai-debug`, `passwordauthentication no`, `kbdinteractive no`; `ssh oldsrv-domen` → `Permission denied (publickey)`, the `ProxyJump vps` hop itself succeeds |
| 4 | **HD-445** | Cockpit gets its owning role — unit, drop-ins (`loopback-bind.conf`, `pi-on-path.conf`), env, linger, `tmux` — rendered from vars instead of hand-kept | seat is hand-kept; `tmux` absent; `pi-web` runs as `domen` on `127.0.0.1:31415` behind the `pi-oldsrv-ts` router |
| 5 | **HD-484** | The seat pi bump (its only remaining tail) — and fix the row's stale version text in the same change | seat **pi 0.99.2 / pi-web beta.38**, laptop **pi 1.0.2**; row still names 0.87.1 / 0.99.2 |
| 6 | **HD-493** | Seat **parity**: `packages`, the §5 settings block, signed commits, `skills/` on **both** seats, clone tidy | seat `packages:` = `@ygncode/pi-web@beta` only; seat `%G?` = `N`; `sync-skills.sh --check` → "deploy target missing" on **both** seats; seat clone 1 behind + leftover `homelab-wt-20261001-1315-1315` |
| 7 | **HD-446** | `scripts/install-pi-debian.sh` — the seat becomes rebuildable; its own trigger ("write it before the **third** pi host") is already met | the laptop has `install-pi-wsl.sh`; the debian twin does not exist yet |
| ‖ | **HD-436** (+HD-435) | *Different lane* (router + Cloudflare, owner-present): the generated alias artifact that finally makes `*.ts.kogler.si` resolve from WSL, and deletes the unversioned workstation resolver drop-in | WSL: `NXDOMAIN` from Technitium, answer only from `100.100.100.100`; ⛔ must not touch the `pi-oldsrv` `extra_record` — acceptance includes the seat still loading |
| ‖ | **HD-444 → HD-411** | *Owner hand, from day 1:* drive the cockpit from the phone over the tailnet **with the laptop shut**; that verdict is what un-parks the Paseo window | HD-444 never performed; HD-411 parked, `paseo_port 6767` unconsumed, real install `npm i -g @getpaseo/cli` (bare `paseo` is the name-squatted trap) |

**Why this order:** 442 → 443 → 492 is the only sequence that ends with a working `domen@oldsrv` shell — a key
without an admitted user is a 255, and an admitted user without a key is a lockout candidate. 445 makes the seat
convergent rather than hand-kept, which is the precondition for trusting it as the primary box. 484 → 493 then bring
it to parity with this workstation, and 446 makes the result rebuildable instead of remembered. Nothing here needs
HD-436 — the cockpit plane is already reachable; 436 only removes the last workstation-side annoyance.

## 2. State measured 2026-10-05 — do not re-derive

- **Seat surface:** `pi-web` under a `domen` user unit on `127.0.0.1:31415`, fronted by oldsrv's own
  `websecure-ts` listener via router `pi-oldsrv-ts` (`Host(\`pi-oldsrv.ts.kogler.si\`)`); drop-ins
  `loopback-bind.conf` + `pi-on-path.conf` exist under `~/.config/systemd/user/pi-web.service.d/`.
- **Name plane:** MagicDNS answers the `.ts` `extra_records`; Technitium answers the plain names and **NXDOMAIN**
  for all of `*.ts.kogler.si`. Forwarder-based clients (WSL) cannot resolve `.ts` — mechanism and consequences in
  [docs/network-dns.md](docs/network-dns.md) §The answer-plane model.
- **Seat vs laptop:** seat pi 0.99.2 (laptop 1.0.2); seat model leg correct (`spark │ spark/qwen3.8-flash-next`);
  gaps listed in HD-493.
- **Windows side:** `C:\Users\domen\.ssh\config` has a `Host oldsrv-domen` block pointed at oldsrv's LAN address via
  `ProxyJump vps`, with pubkey and the working auth order both switched off; WSL's `~/.ssh/config` has `oldsrv`
  (→ `ansible-admin`) and **no** seat alias.
- **Vault:** item `domen_ssh` (public fingerprint `SHA256:XTmK3tR59IMnok1HbEW7n3ZK0v4bd7miPS+0r7lSPTA`); the
  Windows agent stub is still named `laptop-domen_ssh.pub` — the rename is HD-443's owner step.

## 3. Traps that cost rounds

1. ⛔ **Never flip `PasswordAuthentication` to open the seat door** — key-only is the policy; a password door on a
   box with a public jump hop is a second, worse door (HD-413 lockout set).
2. ⛔ **Tailnet ≠ SSH.** The ACL grants `tag:dev:443`; port 22 on oldsrv is reachable **only** through
   `ProxyJump vps`. Do not "simplify" the alias by dropping the jump.
3. ⛔ **`ssh oldsrv` is the runner identity.** Probes about the seat must run as `domen` or via
   `sudo -u domen`; the ansible-admin leg proves nothing about `/home/domen`.
4. ⛔ **HD-445's `--check` is never green** on hand-kept drop-ins (cockpit-lane lesson) — read the diff, do not
   infer "no changes needed".
5. ⛔ **Settings are hand-written from [pi-harness.md](docs/pi-harness.md) §5**, never copied from the laptop:
   `packages` is a workstation key, `models.json`/`auth.json` are rendered (HD-388), and §5 — not any seat file —
   is where `defaultThinkingLevel` is decided.
6. ⛔ **Do not hand-type `/etc/hosts` or a new resolver drop-in** to fix `.ts` on a workstation: that is the fourth
   source HD-436 deletes, and HD-432 already refused the routing-domain alternative.
7. ⚠ The auditor's green exit means *no contradiction found*, not *the grant exists* — verify by presence.

## 4. Acceptance — the seat is moved when all of these hold

1. `ssh oldsrv-domen` from **both** workstations lands a `domen@oldsrv` shell on the first try, key-only,
   `check_ssh_grants.py` names the `domen_ssh`→`domen` grant, and `ansible-admin` is proven working after the change.
2. `pi` on the seat is at the laptop's version, `pi --list-models` still shows the spark leg first, and a session
   starts with §5's defaults (thinking per §5, not the seat's leftover value).
3. `git log --show-signature` on a seat commit verifies, `sync-skills.sh --check` is green on **both** seats, and a
   seat converge (`--check` then real) changes nothing about the unit/drop-ins afterwards (HD-445's proof).
4. The owner has driven a chat round-trip from the phone with the laptop shut (HD-444) — that is the difference
   between "the seat moved" and "the seat moved and is actually usable away from the desk".
