# `prompt-laptop-wsl.md` — Seat brief · the WSL Debian laptop seat: the neutral runner station

> **Role:** dispatch note for a session that runs **on the laptop's WSL Debian seat** (`DomenP14s`, WSL2, `~/source/homelab`).
> This is a **seat** brief, not a domain brief: it claims **legs, not rows** — every row it touches stays owned by the domain
> brief that carries it in [todo-table.md](todo-table.md) §B0, and this file says **which legs only this box may drive** and
> **which model may take them**. The rows are the authority for what is owed; the permanent rule is
> [docs/orchestration.md](docs/orchestration.md) §4 + [todo-table.md](todo-table.md) §C rule 9; the seat-role facts are
> [docs/harness-pi.md](docs/harness-pi.md) §5a. Registering the station is [todo.md](todo.md) HD-1154.
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

**What this seat is, measured (re-measure; do not trust this list):**

| Fact | State at this commit |
|---|---|
| It is a control node | `~/ansible-venv` + `~/.config/op/homelab-sa-token` present; `ansible all -m ping` answers for `vps nas spark oldsrv pi`; `librouteros` imports, so the RouterOS API path works from here — the API port answered on the Mgmt address and **not** on the Home one (addresses: [docs/network-addresses-generated.md](docs/network-addresses-generated.md)) |
| It is **off-box** for every target | the inventory carries the VPS jump (`group_vars/{home_servers,storage,raspberry_pi,spark}.yml`), and no converge target is the controller → `IaC/ansible/playbooks/tasks/self-converge-guard.yml` never fires here. This is the whole reason the seat exists as a dispatch target |
| Its own git transport | `origin` is SSH and `git ls-remote origin` answers. `commit.gpgsign` reads `false` in the clone config and the effective value is `false`, and `git log -1 --format='%G?'` is `N` — signing is retired, so committing here needs nothing and there is no hang on this box. HD-1116's **seat payload** is paid here: `~/.gitconfig-github` reads `gpgsign = false` under `[commit]`, so both files a github-remote clone resolves — that seat file, included through `includeIf "hasconfig:remote.*.url:*github.com*/**"`, and the clone's own config — print `false` in `git config --list --show-origin`. `git-bootstrap.sh --ssh-auth` never writes that file (its signing block writes the clone's config and says so on screen), so it was a hand edit run FROM this box; the seats HD-1116 still owes are Win11-local per §1.4 |
| Its gate is green **before you start** — re-measure anyway | run `bash scripts/validate-all.sh --list \| wc -l` and read the verdicts by name: at `02721b29` this box is **green**, and the three seat items that used to redden it now pass — `pi-settings-config.sh --check --strict` OK, `sync-skills.sh --check --strict` OK, and `install-tmux-conf.sh --check --strict` exits 0 (`SAME` + `IN PLACE`) with its load probe printing `SKIP: no tmux on PATH`. Three items still print **SKIP** here, and a SKIP is not a pass (CONVENTIONS §6): the tmux **load probe**, and the two Windows-only arms — `scripts/harness/seat-ssh-build.sh --check --strict` (not a Windows seat) and `probe-client` in `scripts/bench/laptop-llm.py` (a `native_only` client contract that lives on the Win11 seat). So the one live caveat that belongs to THIS seat is not your gate, it is the **binary**: `tmux` is absent here, therefore every load-probe leg on this box prints **SKIP, not a verdict**, and a green tmux plane proves the config, never the effect |
| Both models are already rendered | `providers.entrim` (`deepseek-ai/DeepSeek-V4-Flash`, 1 M ctx; `Qwen/Qwen3.6-27B`) **and** `providers.spark` (262 144) come from `scripts/harness/pi/models-spec.yml`; the default is spark. An externally-served run is a model switch, not a config change |

**Fix your own seat first** (⛔ every one of these legs must be run **from** this box — the station cannot speak for a seat's
PATH). At `02721b29` this box's own nine planes are `OK`, so do **not** run `pi-seat-sync.sh --push` to repair a red that is not
there: `--check` here prints `RESULT ok=9 problems=1 skipped=0` with every `wsl` line `OK`, and the single problem is the
**oldsrv** seat's `STALE-CLONE` — that seat's clone, not this box's — fixed on oldsrv (`git -C ~/source/homelab fetch origin
&& git -C ~/source/homelab merge --ff-only origin/main`) and not from here; while that clone lags, the driver skips oldsrv's
planes, so the `ok=` count names the `wsl` half only and the same command prints `ok=18 problems=0` once it is current. What
this box still owes is **one** thing, named in [todo.md](todo.md) HD-1154: the **`tmux` binary** — the config plane is
`IN PLACE`, so `install-tmux-conf.sh --push` buys nothing until the binary exists, and installing it is a host change with no
in-repo path, because `roles/seat`'s `seat_packages` reaches only hosts in
[`IaC/ansible/inventory.ini`](IaC/ansible/inventory.ini) and this laptop is not one of them. Park it with the exact command —
`sudo apt-get install -y tmux`, then `bash scripts/harness/install-tmux-conf.sh --reload` to turn the SKIP into a verdict —
and say **SKIP-until-installed**, never a pass, for every load-probe leg until then.
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
| **HD-487** | the `--tags network` legs — oldsrv **alone and off-box** with a console reachable, the spark networkd disarm, the pi dead-unit removals; `scripts/ansible/probe-net-manager.sh <host>` for the per-host verdict | the guard refuses the oldsrv leg from oldsrv; and the spark leg is a network converge on the engine host, which a spark-served session should not drive blind |
| **HD-488** | spark's one-line `host_resolver_dns` pair + its converge | same slot, same reason |
| **HD-1100** | oldsrv's `wireguard` leg — alone, **last**, then re-verify every tunnel path | `wireguard` is a guard-listed role on the seat's own box |
| **HD-1148** | the `--tags docker` applies (vps, pi; the spark host is an owner window because dockerd restarts the engine) — `--check` first, detached, one host at a time | daemon restarts are a maintenance action; rehearsal is this seat's job, the apply is the owner's window |
| **HD-1142** | the NAT reconcile apply (`playbooks/router.yml --check`, then the real run) + the before/after read **from the device** | the router slot is global and the doc wants an on-site station with WinBox on the Home leg — this laptop is that box |
| **HD-1136** | its host-side half that is not blocked by the router window (the `monitoring` converge on oldsrv, the per-seat model-contract re-render, the runner `~/.bashrc` block) | the re-render is a seat leg; the converge is off-box |
| **HD-1152** | the DNS seed's record-prune apply across the three Technitium instances, detached | owner-present apply; never `--diff` on `docker_services` |
| **HD-1128** | the Pi exit-node advertisement + the headscale route, converge Pi + VPS, then prove egress from a tailnet client | `tailscale-node` is guard-listed on the Pi's own box |
| **HD-1116** | this box's git identity/config leg (§0) | only this box can write its own seat config |
| **HD-1110** · **HD-1115** · **HD-1153** · **HD-1085** | this box's own seat planes are `OK` at `02721b29` (`--check`, not `--push` — there is nothing here to push), so what is left in this lane is HD-1085's tmux **effectiveness** leg, which cannot be closed until the binary exists (§0); the Win11 legs of the other three rows stay Win11-local per §1.4 | a seat plane converges from its own clone, and from inside WSL the driver cannot certify the Win11 seat |
| **HD-1123** · **HD-1125** · **HD-1138** | the alias-plane legs that must be run from a laptop class, and the four callers that reach the VPS by bare FQDN | the seat's own `~/.ssh/config` and its own callers |

⛔ **Never** a second session on one converge host at the same time (O3), and **never** a timed spark leg from this session
if `$PI_PROVIDER=spark`. Rehearse-everything rule in §4.

## 3. Bucket A — what a spark-served session on this seat must not start

The spark engine lane is not this brief's work and is barred for the whole run by Rule 0, children included: the
`reasoning` under-cap baseline, every gate that produces `tok/s`/TTFT/ITL, the `spark-ai` re-renders and the engine-boot
converges carried by [prompt-spark-llm.md](prompt-spark-llm.md) (HD-469 · HD-473 · HD-475 · HD-489 · HD-494 · HD-376 ·
HD-400 · HD-359 · HD-367 · HD-380 — re-derive the ids there). What *is* allowed from a spark-served session on this box is
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
