# `prompt-laptop-wsl.md` — Seat brief · the WSL Debian laptop seat: the neutral runner station

> **Role:** dispatch note for a session that runs **on the laptop's WSL Debian seat** (`DomenP14s`, WSL2, `~/source/homelab`).
> This is a **seat** brief, not a domain brief: it claims **legs, not rows** — every row it touches stays owned by the domain
> brief that carries it in [todo-table.md](todo-table.md) §B0, and this file says **which legs only this box may drive** and
> **which model may take them**. The rows are the authority for what is owed; the permanent rule is
> [docs/orchestration.md](docs/orchestration.md) §4 + [todo-table.md](todo-table.md) §C rule 9; the seat-role facts are
> [docs/harness-pi-seat-identity.md](docs/harness-pi-seat-identity.md) §5a. Registering the station is [todo.md](todo.md) HD-1154.
> **Linked from:** [todo-table.md](todo-table.md) §B0 · [todo.md](todo.md) HD-1154 · [prompt.md](prompt.md) §2
> **Rows named as of** `02721b29` — re-derive every id at your own `HEAD` before quoting one (CONVENTIONS §4).

**Contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O11) + README §4. One session, one worktree, one branch.
⛔ Never edit `prompt.md` or `todo-table.md` from a lane (O2) — the session running *this* file as a lane included.

---

## 0. Pre-flight — run all of it, in this order, before touching a file

```bash
echo "seat=$(uname -n) provider=$PI_PROVIDER model=$PI_MODEL"
git status --short && git worktree list && git fetch origin && git log --oneline -1 origin/main
bash scripts/harness/pi-seat-sync.sh --check            # this box's own planes
bash scripts/harness/pi-settings-config.sh --check      # settings vs pi-agent/settings-ssot.json
git log -1 --format='%G?'                               # expect N (signing retired, nothing to verify)
bash scripts/validate-all.sh                            # the seat's own baseline, BEFORE your edits
for h in vps oldsrv spark pi nas; do printf '%-7s ' "$h"; timeout 15 ssh -o BatchMode=yes -o ConnectTimeout=6 "$h" 'uname -n' || echo UNREACHABLE; done
```

Then the CONVENTIONS §0 ritual (the `CONVENTIONS.md` outline grep, `git status`, **your own worktree** — the guard refuses
edits while the primary sits on `main`) and the prior-art sweep for whatever you are about to touch.

**What this seat is (re-measure; do not trust this list):**

| Fact | State (re-measure at your own `HEAD`) |
|---|---|
| It is a control node | `~/ansible-venv` + `~/.config/op/homelab-sa-token` present; `ansible all -m ping` answers for `vps nas spark oldsrv pi`; `librouteros` imports, so the RouterOS API path works from here — the API port answered on the Mgmt address and **not** on the Home one (addresses: [docs/network-addresses-generated.md](docs/network-addresses-generated.md)) |
| It is **off-box** for every target | the inventory carries the VPS jump (`group_vars/{home_servers,storage,raspberry_pi,spark}.yml`), and no converge target is the controller → `IaC/ansible/playbooks/tasks/self-converge-guard.yml` never fires here. This is the whole reason the seat exists as a dispatch target |
| Its own git transport | `origin` is SSH and `git ls-remote origin` answers. `commit.gpgsign` reads `false` in the clone config and the effective value is `false`, and `git log -1 --format='%G?'` is `N` — signing is retired, so committing here needs nothing and there is no hang on this box. The **seat payload** HD-495 still owes is paid here: `~/.gitconfig-github` reads `gpgsign = false` under `[commit]`, so both files a github-remote clone resolves — that seat file, included through `includeIf "hasconfig:remote.*.url:*github.com*/**"`, and the clone's own config — print `false` in `git config --list --show-origin`. `git-bootstrap.sh --ssh-auth` never writes that file (its signing block writes the clone's config and says so on screen), so a seat missing it is a hand edit run FROM this box; the seats that leg still owes are Win11-local per §1.4 |
| Its gate is green **before you start** — re-measure anyway | run `bash scripts/validate-all.sh --list \| wc -l` and read the verdicts by name: this box is expected **green**, with `pi-settings-config.sh --check --strict` OK, `sync-skills.sh --check --strict` OK, and `install-tmux-conf.sh --check --strict` exiting 0 (`SAME` + `IN PLACE`) with its load probe printing a **verdict** — the tmux **binary** is installed on this seat and the load probe prints `OK — the SSOT parses AND applies`. Two items still print **SKIP** here, and a SKIP is not a pass (CONVENTIONS §6): the two Windows-only arms — `scripts/harness/seat-ssh-build.sh --check --strict` (not a Windows seat) and `probe-client` in `scripts/bench/laptop-llm.py` (a `native_only` client contract that lives on the Win11 seat) |
| Both providers are already rendered | `providers.entrim` (hosted, cost-bearing — read its live rows with `pi --list-models entrim`, because the provider retires ids without asking anyone) **and** `providers.spark` (262 144) come from `scripts/harness/pi/models-spec.yml`; the default is spark. An externally-served run is a model switch, not a config change |

**Fix your own seat first** (⛔ every one of these legs must be run **from** this box — the station cannot speak for a seat's
PATH). Run `pi-seat-sync.sh --check` and read its verdict before anything else: a red on **this box's** planes is what
`--push` repairs — do not run `--push` to fix a red that is not here. The single problem this seat normally reports is the
**oldsrv** seat's `STALE-CLONE` — that seat's clone, not this box's — fixed on oldsrv (`git -C ~/source/homelab fetch origin
&& git -C ~/source/homelab merge --ff-only origin/main`) and not from here; while that clone lags, the driver skips oldsrv's
planes, so the `ok=` count names the `wsl` half only. The **`tmux` binary** is installed on this seat (`command -v tmux` →
`/usr/bin/tmux`, tmux 3.5a) and `bash scripts/harness/install-tmux-conf.sh --check --strict` prints `SAME` + a load-probe
verdict, not a SKIP. (The binary is a host change with no in-repo path: `roles/seat`'s
`seat_packages` reaches only hosts in
[`IaC/ansible/inventory.ini`](IaC/ansible/inventory.ini) and this laptop is not one of them — a rebuilt WSL seat replays
`sudo apt-get install -y tmux`, then `install-tmux-conf.sh --reload`.)
Re-run `bash scripts/validate-all.sh` afterwards: **record the item count with `--list | wc -l`, never a number typed into a report.**

## 1. The runner rule (one sentence each, no re-derivation later)

1. **The seat unlocks converges.** A lockout-class leg on a host you are not standing on is legal from here and refused
   from that host's own seat — so those legs belong to this seat, whatever model is serving the session.
2. **The model unlocks timing.** If `$PI_PROVIDER` is `spark`, Rule 0 binds the whole run, children included: **no timed
   spark number, no engine restart, no `spark-ai` re-render** — counter/log/`/metrics`/`docker inspect` reads stay legal.
   Being on this box changes nothing about that. See `spark/llm-profiles/README.md` Rule 0 and §C2.
3. **An externally-served run belongs here.** The station for every externally-served session is this seat
   ([todo-table.md](todo-table.md) §C rule 9): off-box for every host, not the engine host, owner of no converge slot. Take a
   timed leg from anywhere else and `scripts/bench/spark/run-scenario.sh` still stamps the hostname into the leg — the CSV
   proves afterwards that it was taken off-station.
4. **Win11-local legs stay Win11-local.** From inside WSL `pi-seat-sync.sh` names only the `wsl` and `oldsrv` seats
   (`scripts/harness/pi-seat-sync.sh` `SEATS`), so a WSL session cannot certify the Win11 seat: the runtime legs and the
   Win11 `~/.ssh` retirement items are run in a Win11 session ([prompt-laptop-legs.md](prompt-laptop-legs.md) is a
   different brief on a different seat — do not merge them).

## 2. Bucket B — run here now, on a spark-served session

Everything in this section is **off-box-class or seat-local**, therefore outside a spark-served session's reach on the
oldsrv seat and inside this box's reach. Row ownership does not move (O3 is about hosts, §B0 is about rows).

| Row | The leg this seat runs | Why only here |
|---|---|---|
| **HD-487** | **one act left: the VPS `--tags netd` delete of the dead `/etc/systemd/network/20-eno1.netdev`**, owner-present, `--check` scoping already done; `scripts/ansible/probe-net-manager.sh <host>` is the read-only verdict | the guard refuses the act from the box itself, and the remaining delete sits in the netd namespace on the VPS — the oldsrv, spark and Pi legs and the spark resolver pair are landed and every host reads settled |
| **HD-1100** | the four held Postgres legs on the owner's word, one cluster per window; and the **VPS** `wireguard` leg — `playbooks/vps.yml --limit vps.kogler.si --tags wireguard`, detached, **last**, never alongside another converge, then re-verify every tunnel path | ⛔ the oldsrv `--tags wireguard` leg this cell used to name selects **zero** role tasks — `home_servers.yml` carries no `wireguard` role (HD-1100's own row says so); the VPS leg restarts the tunnel every off-box converge rides, which is why it is last and alone |
| **HD-1142** | the NAT reconcile apply (`playbooks/router.yml --check`, then the real run) + the before/after read **from the device** | the router slot is global and the doc wants an on-site station with WinBox on the Home leg — this laptop is that box |
| **HD-1136** | the host-side half that is not blocked by the router window: the per-seat model-contract re-render (`scripts/harness/render-pi-config.py --vendor continue`), the one hand-edit of the runner's `~/.bashrc` block, and the three `>>> … <<<` managed-block markers the scripts match on | the re-render is a seat leg; the marker edit owes a migration step for the copies already seated, so it is a repo act with a host tail |
| **HD-1152** | fix BOTH defects in the prune leg first (the `url_query` read the API only answers as a form body, and the Jinja list comprehension in the candidate build), then the DNS seed's record-prune apply across the three Technitium instances, detached | owner-present apply; a real run today dies at the read task with the seed's own legs green, so the RECAP red is the defect, not the prune; never `--diff` on `docker_services` |
| **HD-1128** | the Pi exit-node advertisement + the headscale route, converge Pi + VPS, then prove egress from a tailnet client | `tailscale-node` is guard-listed on the Pi's own box |
| HD-495 | this box's git identity/config leg (§0) | only this box can write its own seat config |
| **HD-1110** · **HD-1085** | this box's own seat planes read `OK` on `--check` (not `--push` — there is nothing here to push), so what is left in this lane is HD-1085's tmux **effectiveness** leg, now closeable because the binary is on the box (§0); the other rows' Win11 legs stay Win11-local per §1.4 | a seat plane converges from its own clone, and from inside WSL the driver cannot certify the Win11 seat |
| **HD-1123** · **HD-1125** · **HD-1138** | the alias-plane legs that must be run from a laptop class, and the four callers that reach the VPS by bare FQDN | the seat's own `~/.ssh/config` and its own callers |

⛔ **Never** a second session on one converge host at the same time (O3), and **never** a timed spark leg from this session
if `$PI_PROVIDER=spark`. Rehearse-everything rule in §4.

## 3. Bucket A — what a spark-served session on this seat must not start

The spark engine lane is not this brief's work and is barred for the whole run by the spark-served dispatch filter,
children included: the `reasoning` under-cap baseline, every gate that produces `tok/s`/TTFT/ITL, the `spark-ai`
re-renders and the engine-boot converges carried by [prompt-spark-llm.md](prompt-spark-llm.md) — today
HD-469 · HD-473 · HD-475 · HD-489 · HD-494 · HD-376 · HD-400 · HD-359 · HD-367 · HD-380 plus the v32 lineage rows
HD-1206 · HD-1214 · HD-1215 · HD-1220 · HD-1221 · HD-1222, whose flips are engine recreates (re-derive the ids there;
this list is a pointer, never the authority). What *is* allowed from a spark-served session on this box is
the provably engine-safe door in §C2 — with the engine's id + `StartedAt` + `RestartCount` read before and after and
`llm.kogler.si` proven 200 afterwards. If the session is externally served, that lane is dispatched from
[prompt-spark-llm.md](prompt-spark-llm.md) and this brief contributes only its legs from §2.

## 4. Owner windows: rehearse everything, run nothing you were not told to run

The owner is **not present in-session**. So for every leg in §2 and every apply that a row marks owner-present:

1. run the read-only form (`--check`, `--list-tasks`, `--list-hosts`, `probe-net-manager.sh`, `render-converge.yml`,
   `routeros-apply-delta.sh` in its dry form, the renderers' `--check`) and **save the output**;
2. write the exact one command that remains into the row's ⏳ tail — host, playbook, tags, `-e` vars, the detached form, and
   the read-back that proves it landed;
3. return `PARKED — <the single blocked action>`. Do not stall the lane, and do not treat `--check` as a live verdict: a
   converge's deploy loop skips in check mode, so check-mode proves scoping only.

## 5. Owns / never touches

**Owns:** this file; `todo.md` rows **only** where the row's remaining work is a leg named in §2; the seat-side artifacts
this box writes (its own `~/.ssh/config` is not in the tree, `ssh/aliases.tmpl` is the plane that renders it).
**Never:** `prompt.md`, `todo-table.md` (O2), another brief's rows or files (O3: `docs/services-ai*.md`,
`templates/docker_services/**` per service directory), the frozen `reports/` archives, generated `*-generated.md`,
`roles/router/**` (the router slot is global — name it in the report before you touch it), and any `spark-ai` engine dial.

## 6. Acceptance

- the §0 pre-flight printed in the report, with the re-derived gate item count and any SKIP named as a SKIP;
- every §2 leg either **rehearsed with its saved output + the remaining command written into the row**, or run and proven
  by the row's own read-back — `PARKED` is a passing verdict here, a silent stall is not;
- no timed number appears anywhere in the report if `$PI_PROVIDER=spark`;
- `bash scripts/validate-all.sh` green **in this worktree** — name the item count you derived with `--list | wc -l`, name every
  SKIP as a SKIP and the leg that would turn it into a verdict (a SKIP is not a pass, CONVENTIONS §6), then commit, push,
  **stop** — merge, views and brief-death belong to the parent (O1/O7).
