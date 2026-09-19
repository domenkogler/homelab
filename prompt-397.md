> **Role:** single-lane handoff for **HD-397 — off-LAN access parity** (behind-NAT LAN hosts must be reachable/convergible from anywhere without ad-hoc overrides). Read this file and you can start: every number and command below was measured, and the links are only for close-out records.
> **Linked from:** [`prompt.md`](prompt.md) §2 · [todo.md](todo.md) HD-397 · siblings [`prompt-398.md`](prompt-398.md) (the mgmt-plane seal — HD-397's owner gate) and [`prompt-391.md`](prompt-391.md) (the lane that wants a working oldsrv converge).
> **Baseline:** authored on `main` at `47a71c7`, 2026-09-19.

---

## 0. Start here (5 minutes, non-negotiable)

1. **Fresh session worktree BEFORE any edit** (CONVENTIONS §6, enforced by `scripts/guard-session.sh`):
   `git worktree add ../homelab-wt-$(date +%Y%m%d-%H%M)` — the primary checkout is a **merge station**.
2. **Environment:** WSL Debian, ext4. Ansible always through the wrapper (venv + 1Password read-scope SA token):
   `bash scripts/ansible-run.sh playbooks/<play>.yml --limit <host> [--check]`.
3. **Converge hygiene (each one is a live incident, not style):**
   - **Never `--diff` on a `docker_services` converge** — the rendered compose diff prints live API keys to the run log (`--check` alone is safe).
   - **Real converges run DETACHED** (`nohup … > /tmp/converge-<host>-<ts>.log 2>&1 &`, then poll). A foreground run behind an outer timeout gets killed mid-restart.
   - **A scoped service deploy needs BOTH tags**: `--tags docker_services,<svc>`; `-e docker_services_scope=<svc>` with only `--tags docker_services` tag-filters every inner task and reports `changed=0, failed=0` while the host stays stale.
4. **Never print a secret value** — hashes/lengths/item-IDs only (CONVENTIONS §6).
5. **Finish with** `bash scripts/validate-all.sh` green, commit signed (`Couldn't find key in agent` → `ssh-add ~/.ssh/github_signing ~/.ssh/github_auth`).

**Do not re-derive:** the away-access matrix, the three traps and the "dead address ≠ dead host" rule are already written in [docs/network-vpn.md](docs/network-vpn.md) §Reaching LAN nodes when away. **Do not re-decide:** LAN hosts do **not** join the tailnet (§Tailnet boundary, 2026-09-10) — today's measurements re-proved the jump was never the failure.

---

## Lane coordination — read before starting

**Run this brief together with [`prompt-398.md`](prompt-398.md), in ONE session.** HD-398's answer *is* step 2 of §3 below, and both write the same section of [docs/network-vpn.md](docs/network-vpn.md); splitting them guarantees a conflict and hands an owner decision across a session boundary. **And do not run the hotspot re-measure (§3 step 5) while any other session has a converge in flight** — you will kill it mid-restart (the HD-370 failure) and the matrix reading will be meaningless.

- **Docs this session owns:** [docs/network-vpn.md](docs/network-vpn.md) §Reaching LAN nodes when away · [docs/deployment-ansible.md](docs/deployment-ansible.md) §Jump-host execution.
- **Do not touch:** `docs/services-ai.md`, `docs/services-ai-bench.md`, `IaC/ansible/templates/docker_services/**` — that is the HD-391 lane.
- **Shared file, split by hunk:** `IaC/ansible/group_vars/home_servers.yml`. You add the top-level `ansible_ssh_common_args` key; HD-391 appends three registry lines near the `ollama` entry. Different hunks — land yours first if you can, and rebase if they beat you to it.
- **todo.md:** edit only HD-397 (plus HD-398 / HD-392 if you are running the pair, as intended). Never renumber, never edit another lane's row, never re-add a row another lane deleted as done.
- **Cadence:** `git pull --ff-only origin main` before you start **and** before every commit; land small validated slices instead of one big merge at the end. If `main` moved under you, merge it into your session branch, re-run `validate-all.sh`, then fast-forward.

---

## 1. Mission + definition of done

**Mission:** make every behind-NAT LAN host (`oldsrv`, `nas`, `pi`, `spark`) reachable by `ssh` and convergible by Ansible **from any network, with no ad-hoc flags and no laptop-local hacks**, and mark the genuinely on-site-only hosts as what they are.

Today only `spark` meets that bar, because its playbook says so out loud (`IaC/ansible/playbooks/spark.yml`: `ansible_ssh_common_args: "-o ProxyJump=vps"` — "keep it here so ANY runner converges spark"). Nothing else carries the jump, so off-LAN work has been improvised with `-e ansible_host=…` and hand-added `Host <ip>` blocks — both of which are traps (§4).

**Done when all of these are true and recorded:**

- [ ] `group_vars` for `home_servers`, `storage` and `raspberry_pi` carry `ansible_ssh_common_args: "-o ProxyJump=vps"` (spark keeps its play-level copy — same value, no conflict).
- [ ] `bash scripts/ansible-run.sh playbooks/home_servers.yml --limit oldsrv.kogler.si --check` runs green from an **off-LAN** station **without** any `-e` override, and the RECAP touches oldsrv (not "skipping: UNREACHABLE").
- [ ] `ssh nas` works from a hotspot (it has **no `ProxyJump` at all** today).
- [ ] Every behind-NAT node has a `Host <ip>` block in the ssh config (OpenSSH matches the name ACTUALLY TYPED, and Ansible types the `ansible_host` value), and that block list is documented in the owning doc rather than existing only on this laptop.
- [ ] `router` / `switch` / the AP aliases / `pi99` are documented as **on-site admin paths**, not given a fake jump that cannot work.
- [ ] The matrix table in [docs/network-vpn.md](docs/network-vpn.md) §Reaching LAN nodes when away is re-measured and re-dated (no aspirational ✅).
- [ ] `scripts/rotate-spark-llm-key.sh`'s `lan-litellm` audit leg reads a real hash off-LAN (see §3 step 6).

---

## 2. Live state as measured 2026-09-19 (all repro-able)

**Reachability matrix** (from this WSL station; `✓` = proven by a command, not by config):

| Node | inventory `ansible_host` (host_vars) | ssh alias today | off-LAN status |
|---|---|---|---|
| `vps` | public `159.195.111.66` | direct | ✓ the jump host itself |
| `spark` | derived Home IP | `Host spark` → `ProxyJump vps` **+ the play carries the jump** | ✓ `ssh spark` works anywhere |
| `pi` | Home `10.10.1.20` | `Host pi` → `ProxyJump vps` | ✓ alias works; the **playbooks do not carry the jump** |
| `nas` | Home `10.10.1.10` | `Host nas` → **no `ProxyJump`** | ✗ cannot route from a hotspot |
| `oldsrv` | **mgmt `10.10.99.30`** | `Host oldsrv` → mgmt + `ProxyJump vps` (the jump line is a 2026-09-19 addition — `~/.ssh/config.bak-20260918-103530` shows the alias was direct and jump-less) | ✗ points at a plane sealed from the tunnel ([`prompt-398.md`](prompt-398.md)) |
| `router`/`switch`/APs | mgmt `10.10.99.x` | no jump | on-site only by design (VLAN 99 = admin plane) |

**Working forms, measured today** (Home leg of oldsrv, jump = `vps`):

```bash
# ~1 s, no banner stall:  REMOTE_OK oldsrv
ssh -o BatchMode=yes -o ProxyCommand="ssh -W %h:%p vps" ansible-admin@10.10.1.30 'echo REMOTE_OK $(hostname)'

# pong — but this -e form is probe-only, see §4 trap 1
cd IaC/ansible && ansible oldsrv.kogler.si -i inventory.ini -m ansible.builtin.ping -e ansible_host=10.10.1.30
```

**Other facts you would otherwise re-discover:**

- `oldsrv.kogler.si` **does not resolve from the station at all** (the station resolver answers `llm`/`litellm` over the tailnet, not `oldsrv`/`llitellm`/`spark`) — so anything keyed on that name fails at resolution, long before auth. The 2026-09-18 claim "the Home-leg name does not authenticate as `ansible-admin`" was this, not sshd.
- A `ProxyJump` to a sealed address does not fail fast: the client waits and reports **`Connection timed out during banner exchange`**. That string means *dead next-hop*, not "sshd is broken".
- oldsrv itself is healthy: up 9 d 21 h, **34 containers running / 0 exited / 0 unhealthy**, its own `enp0s31f6.99` is `UP` with the right address.
- The Windows side matters: `vEthernet (Mgmt99)` was **Disconnected** and WSL carried only `eth0`. The documented "Mgmt direct" path is only testable after `wsl-nat-resolv.ps1 -EnableMgmt99` actually has link — check before blaming the router.
- `scripts/rotate-spark-llm-key.sh` was hardened today by the closing session: its LAN leg now takes an `OLDSRV_SSH` override and prints **`UNREADABLE`** (never a verdict) when the station cannot reach the host. So the remaining work is *making the station path work*, not re-labelling the failure.

---

## 3. The work, in order

1. **Group vars carry the jump** (the actual fix; 3 small edits): add to `IaC/ansible/group_vars/home_servers.yml`, `group_vars/storage.yml`, `group_vars/raspberry_pi.yml`:
   ```yaml
   # Reachability: this host sits behind the home NAT. From any runner that is not LAN-attached
   # it is reachable ONLY via the VPS jump. From a LAN-attached runner this is a harmless no-op
   # (same doctrine as playbooks/spark.yml: "so ANY runner converges <host>").
   ansible_ssh_common_args: "-o ProxyJump=vps"
   ```
   Group vars beat play vars nowhere in a way that matters here, but **check** `playbooks/home_servers.yml`, `storage.yml`, `raspberry_pi.yml`, `nut-deploy.yml`, `dns-seed.yml`, `all.yml` for play-level `vars:` that would shadow them, and confirm with `--check` runs rather than by reading.
2. **Leg decision for `oldsrv` (coupled to HD-398 — do not decide it alone).** If the owner keeps the mgmt plane sealed from the tunnel (HD-398's likely answer), the Home leg becomes the away admin path and `host_vars/oldsrv.kogler.si.yml` must stop hard-coding the mgmt address. **Safe mechanism** (avoids §4 trap 1): the host_vars file already defines `mgmt_ip` and `home_ip`, so express the leg as a *host-scoped* switch, e.g.
   ```yaml
   ansible_host: "{{ (offlan_admin_home | default(false)) | ternary(home_ip, mgmt_ip) }}"
   ```
   and run off-LAN with `-e offlan_admin_home=true`. A global extra-var that only this host_vars file reads cannot hijack a `delegate_to:` target the way `-e ansible_host=` does — **prove that** with a `--check` run of a play containing a `delegate_to:` task (the recorded victim is the `ha-sync.pub` task, `delegate_to: pi`) before recommending it.
3. **ssh alias map** (workstation, but the *spec* belongs in the owning doc so the next laptop can rebuild it): every behind-NAT node gets both an alias and a `Host <ip>` block on the leg that is reachable from afar; `router`/`switch`/AP/`pi99` keep jump-less mgmt aliases and get a comment saying "on-site only". Fix `nas` (add the jump). If HD-398 says "sealed stays", `Host oldsrv` must stop pairing a mgmt address with `ProxyJump vps`.
4. **Document the map, don't just apply it** — [docs/network-vpn.md](docs/network-vpn.md) §Reaching LAN nodes when away is the SSOT for the laptop contract (a laptop-local `~/.ssh/config` is not a durable artifact).
5. **Re-measure and re-date the matrix.** For each node record the command + result; mark on-site-only rows honestly. Prefer one hotspot pass and one LAN pass; if you can only do one, say which in the table.
6. **Close the tooling tail:** once the station path needs no override, re-run the rotation audit leg and confirm it prints a hash rather than `UNREADABLE`:
   `OLDSRV_SSH="-o ProxyCommand=ssh\ -W\ %h:%p\ vps\ ansible-admin@10.10.1.30" bash scripts/rotate-spark-llm-key.sh` (read-only path) — or simply `ssh oldsrv` once the alias is fixed. Update the script's comment when the override is no longer the documented form.
7. **Optional but valuable:** a cheap validator that fails when a behind-NAT inventory host has no carried jump (the class of bug that made only `spark` work). If you add it to `scripts/validate-all.sh`, list it in `scripts/README.md` (their comment blocks are kept in sync).

---

## 4. Traps (each one cost someone time — all measured)

1. **`-e ansible_host=<ip>` is a GLOBAL extra-var.** It overrode the delegate target too and made a `delegate_to: pi` task look for `/root/.ssh/ha-sync.pub` on **oldsrv** (`ok=367 changed=52 failed=1`). Probe-only at best; recorded in [docs/deployment-ansible.md](docs/deployment-ansible.md).
2. **OpenSSH matches the name ACTUALLY TYPED.** An alias block does nothing when Ansible types an IP; behind-NAT nodes need a `Host <ip>` block **and** the jump in the play/group_vars.
3. **Banner timeout ≠ sshd fault.** With a jump at a sealed address you get `timed out during banner exchange` after 25–95 s.
4. **A dead address is not a dead host.** Test the other leg and one hop that must work before writing "host down" anywhere.
5. **`pgrep -f ansible-playbook` matches its own argv** — it falsely claimed "a converge is already running" three times. A check that cannot tell "nothing running" from "I am running" is not a gate.
6. **There is no `tailscale` CLI on the VPS host** (the edge runs it in a sidecar) — empty `tailscale status` output there is the wrong instrument, not "no peers".
7. **Do not** join LAN hosts to the tailnet as the fix (decided boundary 2026-09-10).
8. **Do not** add `ProxyJump` to aliases that target the mgmt plane — it cannot work while HD-398's seal stands; it converts a fast failure into a 90-second mystery.

---

## 5. Owner gates / routing

- **HD-398 decides the leg** (keep VLAN 99 sealed from the tunnel vs deliberately widen it). Your step 2 waits on that answer; if it has not landed, ship steps 1, 3–6 with the *jump carried* and the leg unchanged, and say so in the row.
- Any widening of `wg_s2s_vps.allowed_ips` or the router's `available-from` scope is an **owner decision** (least-access + admin-plane boundaries). Route it; do not fold it in as a side effect.

---

## 6. Close-out

1. Update [docs/network-vpn.md](docs/network-vpn.md) §Reaching LAN nodes when away (matrix, dates, the laptop alias contract).
2. Update [docs/deployment-ansible.md](docs/deployment-ansible.md) §Jump-host execution if the documented invocation changed.
3. `todo.md` HD-397: trim to whatever genuinely remains (a fully-done row is **deleted** — the record is the owning doc + git; CONVENTIONS §4(a), linter `check_todo_done.py`).
4. `bash scripts/validate-all.sh` green → commit signed on the session branch → fast-forward into `main` (merge station).
5. If you changed a rendered-doc input, regenerate (`scripts/render_all.py`) — never hand-edit `*-generated.md`.
