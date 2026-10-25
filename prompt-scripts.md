# `prompt-scripts.md` — Lane brief · the `scripts/` restructure (HD-1118) and the rows that ride it

> **Role:** dispatch note for **one** lane session: the `scripts/` restructure — reorganise `scripts/` into named folders
> **without changing what any script does** — is **landed**; what this brief dispatches now is its remaining legs and riders.
> The rows are the authority for what is missing: [todo.md](todo.md) **HD-1118 · HD-1125 · HD-1138**
> (row ids as of `c13e30f6` — re-derive with `grep -c "^| HD-<id> " todo.md` before quoting one); the landed half's record is
> the docs themselves plus git, never a pointer. **HD-1125** and **HD-1138** are carried here because every remaining leg of
> each of them edits `scripts/**`; their hosts, slots and traps are in §What is open.
> The structure is **agreed with the owner as the target, not as a doc** — this file is the only place the agreed tree + the
> stage order are written down. Design context: [docs/harness-pi-seats.md](docs/harness-pi-seats.md)
> §1 (the seat planes and the deploy direction — the split doc that carries what `harness-pi.md`'s §1 used to) and its §5
> (the reference `settings.json` block), [CONVENTIONS.md](CONVENTIONS.md) §6 (worktree/gate discipline), [`scripts/README.md`](scripts/README.md) (the registry).
> **Linked from:** [todo.md](todo.md) HD-1118
> **Status:** the tree is foldered and `gate/check_script_layout.py` is wired; Stages 1–4 below are the tree's
> provenance, not work, and the unreplayable lane tree is pinned as `rescue/hd1118-20261011`. HD-1118 carries
> **three live legs** — the two seat legs run FROM the seats (`pi-seat-sync.sh --check` per seat, `install-tmux-conf.sh
> --push` on the win11 seat) plus the from-zero `install-pi-debian.sh --check` leg, **parked** for want of a clean Debian box.
> **The `scripts/README.md` prose sweep is landed**: [`scripts/gate/check_registry_prose.py`](scripts/gate/check_registry_prose.py)
> prints `registry: 120 linked rows, 0 state-date exempt site(s), 0 finding(s)` and runs in `validate-all.sh` with its
> `--self-test`. **The `harness-pi.md` split is landed**: the split was of `harness-pi.md` — not of
> [`docs/harness-pi-engines.md`](docs/harness-pi-engines.md),
> which is one of the five children it produced alongside [`docs/harness-pi-models.md`](docs/harness-pi-models.md), [`docs/harness-pi-seats.md`](docs/harness-pi-seats.md),
> [`docs/harness-pi-seat-identity.md`](docs/harness-pi-seat-identity.md), [`docs/harness-pi-terminal.md`](docs/harness-pi-terminal.md) — with its
> reference sweep and hub-map repair. **The domain checker is landed**: [`scripts/gate/check_doc_domain.py`](scripts/gate/check_doc_domain.py) exists, runs in
> `validate-all.sh` (run + `--self-test`) and prints `OK: 88 docs, 10 domains, each with one claimed home`.
> Read §What is open first.

**Contract:** README §4 (this is a normal lane, not an §4-orchestrator lane): one session, one worktree, one branch, edits to
`todo.md` limited to **this row**. No live converges — the live legs are seat-side, and the parked from-zero check waits on a
host this lane does not own. `bash scripts/validate-all.sh` green
**in this worktree** before every commit; close-out = commit, row tail, stop.

**Who runs this brief (lane C — the context-bound lane).** The rows here are *theoretically* engine-neutral work with no host
risk, which is exactly why they read as spark-doable; the binding term is not the host, it is the **working set**. Take the
number instead of trusting this sentence: `wc -c scripts/README.md todo.md CONVENTIONS.md docs/index.md`, and
`python3 scripts/gate/check_registry_prose.py --show` for what the prose sweep actually covers. What that arithmetic says: the
file this lane must hold in one pass is a large fraction of a locally-served lane's rendered window (262 144 with
`compaction.reserveTokens` 16 384 — [pi-agent/settings-ssot.json](pi-agent/settings-ssot.json)), and the mandatory reading sits
on top of it. A lane that reads its contract and then sweeps that file does so with its own contract already compacted — the
failure [`spark/llm-profiles/README.md`](spark/llm-profiles/README.md) records for the small local model, at a larger number. So:

| Part of this brief | Serve it from |
|---|---|
| the **campaign** items — the landed `scripts/README.md` prose sweep, held by `scripts/gate/check_registry_prose.py`, and the landed `docs/harness-pi-*.md` split with its reference sweep (row closed), and the gate legs that must compare whole-corpus behaviour (HD-1117's `render_all.py --check` wiring, HD-1137's quick-subset comparison) | the **designated runner station** with an externally-served model — [prompt-laptop-wsl.md](prompt-laptop-wsl.md) §0/§1, and the rule in [todo-table.md](todo-table.md) §C rule 9 |
| the **prep** for the campaign legs still live — measure the corpus, list the cells that must change, print the live count `check_registry_prose.py --show` prints (0 findings, so the six rows that lacked the third column are repaired, not owed) | any seat, spark-served: it is read-only arithmetic and it is what makes the campaign one pass instead of a re-measurement |

Row ownership does not move: this brief keeps the rows (§B0 is the index), the station brief claims **legs, not rows**.

**Why stages, not one move commit:** ~1,500 literal `scripts/<name>` references across 173 tracked files, and — the part that
would have bitten first — **the scripts do not know where the repo root is, they assume a fixed depth.** Fix that before any
file changes directory, or the move turns validators green-while-checking-nothing (Stage 1 is the whole reason Stage 3 is safe).

## What is open

Nothing in this brief moves a file any more. Stages 1-4 are provenance, **and Stage 2's tail landed too**: `IaC/ansible/group_vars/all/versions.yml` carries the `pi_pkg_*` inventory with `scope: fleet | seat` and a registry-verified version on every name, and `install-pi-wsl.sh` installs the fleet set by discovery rather than a bare literal list — so no package is unversioned and unowned.

| Leg | State | Who may run it |
|---|---|---|
| HD-1118 **(b)** — `install-pi-debian.sh --check` on a from-zero Debian seat | **PARKED, not open.** It is the only proof that the from-zero path converges the foldered tree, and it needs a clean Debian box: there is no in-lane command and no host in this repo that is a spare Debian box. Do not re-derive it here; the row closes when someone runs it in the seat lane | a clean Debian box, not this lane |
| the **harness split** (a) — split `harness-pi.md` by subject | **landed, row closed.** Five children now carry the content — [`docs/harness-pi-engines.md`](docs/harness-pi-engines.md), [`docs/harness-pi-models.md`](docs/harness-pi-models.md), [`docs/harness-pi-seats.md`](docs/harness-pi-seats.md), [`docs/harness-pi-seat-identity.md`](docs/harness-pi-seat-identity.md), [`docs/harness-pi-terminal.md`](docs/harness-pi-terminal.md) — with the whole-tree reference sweep and the hub-map repair in the same wave; every lane brief's ownership list names all five | nobody — landed |
| the **domain checker** (b) — [`scripts/gate/check_doc_domain.py`](scripts/gate/check_doc_domain.py) | **landed and wired.** The run and its `--self-test` are `validate-all.sh` items; the verdict is `OK: 88 docs, 10 domains, each with one claimed home`. The domain set stays derived from `docs/**/*.md` frontmatter, so a retag moves the rule and not the code — the six floor-0 files in §The taxonomy call are what it was told about | nobody — retags are frontmatter edits, not a lane |
| The `scripts/README.md` prose sweep — wire `check_registry_prose.py` | **landed.** `python3 scripts/gate/check_registry_prose.py --show` prints `registry: 120 linked rows, 0 state-date exempt site(s), 0 finding(s)` and the checker + `--self-test` run as gate items, so the registry stays a facts-only file | nobody — `scripts/gate/check_registry_prose.py` holds the rule in `validate-all.sh` |
| **HD-1125** — the fleet automation key sits at ssh's DEFAULT path (`~/.ssh/id_ed25519`) on the WSL and cockpit seats, byte-identical to `ansible-admin_ssh`, so HD-1123's retirement rule cannot close | **open, and every remaining move edits `scripts/**`** — which is why the row is here. In this order: `-o IdentityFile=~/.ssh/ansible-admin_ssh` on `scripts/ansible/ak-shell.sh` and `scripts/secrets/provision-vault.sh`, then `scripts/ansible/seed-runner-ssh.sh`'s default → the canonical file, then `scripts/ansible/restore-runner-key.sh`'s target, and only then the `.kogler.si` spellings on the laptop classes in `ssh/aliases.tmpl`, so a bare FQDN stops being an alias gap at all | the lane for the `scripts/**` hunks; **on each seat** for the rename itself — ⛔ never rename before every caller names an `IdentityFile` and BOTH legs are re-proved with the file aside. No converge; the cockpit seat's copy is the retirement list's step-6 measurement and is not observable from the box running this |
| **HD-1138** — the alias contract now defaults to LAN-direct: a plain `<node>` name takes the Home leg with no jump, `<node>-vps` is the opt-in hop | **landed; one consumer sweep left.** `seed-seat-ssh-config.sh` enforces rule 1 mechanically (a `ProxyJump` may sit only in an all-`-vps` block) plus the five names and a count, and the jump Ansible uses is the inventory's, so no converge is touched. The remaining consumers are the scripts that shell out to bare `ssh <name>` — this brief's file set | the lane for the script sweep; the seat premise (the Home-leg binding inside WSL, where the interface carries a NAT address) is a router-slot leg and is **not** this lane's |

**Ordering inside this brief:** the prose sweep and the **harness split**'s sweep are both landed, so no ordering between
them is left to declare. The live work this brief carries is **HD-1118's seat legs, run FROM the seats**
(`pi-seat-sync.sh --check`, `install-tmux-conf.sh --push` on the win11 seat) and its **parked** from-zero leg, plus the two
rows that joined it because their remaining legs edit `scripts/**` — **HD-1125**'s callers, which must name an
`IdentityFile` before the default-path key can be renamed, and **HD-1138**'s scripts that still shell out to bare
`ssh <name>`; the `scripts/**` order above is the order. Nothing in this brief has a file-moving order dependency left, and
`gate/`'s and `lib/`'s exception note in the registry header stays the only registry text a domain-set change may touch.

## The agreed target tree

```
scripts/
├── README.md                      registry, restructured into one section per folder
├── validate-all.sh                ┐ the two umbrella entry points stay at root: they are what
├── render_all.py                  ┘ a human, cron or the gate invokes by name
├── next-hd.sh                     repo-contract utility, no domain
├── lib/                           repo-root helper · pin() ×1 (was 5 copies) · sync-tree engine · plane registry
├── gate/        (27)              every check_*.py + validate*.py + check-vault-items.sh + guard-session.sh
├── ansible/     (19)              control node + runner + the Ansible-driven render twins
├── secrets/     (8)               1Password provisioning + the key-injecting generators
├── git/         (2 + data)        git-bootstrap{,-win11}.sh + data/gitconfig-nightly
├── harness/     (12 + data)       seat planes, driver, installers, the models plane, win/ twin
├── bench/       (5 + spark data)  serving-leg instruments, incl. scripts/bench/spark moved in
├── hardware/    (4)               run-it-on-the-box / live-ISO collectors + the WSL net fix
└── testdata/                      unchanged; the future registry checker EXCLUDES testdata/**
```

Per-file assignment (the numbers above are exact; the tree was walked file-by-file and this is the whole corpus, no residue
except the one deleted file):

| Folder | Files |
|---|---|
| `lib/` | `repo-root.sh` + `repo_root.py` (new), `pi-seat.sh` (new), `sync-tree.sh` (new), `seat-planes.yml` (new) |
| `gate/` | `check_{dns_seed_drift,doc_ips,doc_map,doc_path_refs,generated_suffix,iac_backend_strings,ledger_state,md_tables,merge_markers,placeholders,runbook_purity,secrets,self_converge_guard,spark_llm_gate,ssh_grants,todo_done,traefik_host_rules,vault_docs,vault_name,yaml_dup_keys,zone_kogler_si_parity}.py`, `check-vault-items.sh`, `guard-session.sh`, `validate_blueprints.py`, `validate-docker-services.py`, `validate_doc_templates.py`, `validate-secrets.py`, + the new `check_script_layout.py` (Stage 4) |
| `ansible/` | `ansible-run.sh`, `ansible_query.py`, `guarded-converge.sh`, `restart-watchdog.sh`, `ak-shell.sh`, `probe-net-manager.sh`, `bootstrap-runner.sh`, `restore-runner-key.sh`, `seed-runner-ssh.sh`, `seed-seat-deploy-key.sh`, `render_network_addresses.py`, `render_rack_connections.py`, `zone_kogler_si_render.py`, `capture_zone_kogler_si_golden.py`, `knx-hass-gen.py`, `adapt-vllm-dashboards.py`, `build-llm-dashboard.py`, `routeros-apply-delta.sh`, `image-pin-probe.py` · **delete** `ansible-network-hop.sh` (headed OBSOLETE; history is git) |
| `secrets/` | `provision-secrets.py`, `provision-vault.sh`, `op-vault-export.py`, `gen-htpasswd.py`, `get-bootstrap-keys.sh`, `rotate-spark-llm-key.sh`, `gen-custom-script.sh`, `gen-media-post-install.sh` |
| `git/` | `git-bootstrap.sh`, `git-bootstrap-win11.sh`, `data/gitconfig-nightly` (today's `scripts/git/` holds only that data file, with its two installers elsewhere — the folder becomes what a reader assumes it is) |
| `harness/` | `pi-seat-sync.sh`, `pi-self-update.sh`, `pi-settings-config.sh`, `pi-tui-config.sh`, `sync-skills.sh`, `sync-extensions.sh`, `install-nerd-font.sh`, `install-tmux-conf.sh`, `install-pi-debian.sh`, `install-pi-wsl.sh`, `render-pi-config.py`, `win/install-nerd-font.ps1`, `pi/models-spec.yml` (was `pi-config/`) |
| `bench/` | `spark-llm-probe.py`, `spark-fp8-image-probe.py`, `spark-llm-render-matrix.py`, `laptop-llm.py`, `laptop/profiles.yml` (was `laptop-llm/`), `laptop/win/lmstudio-llm.ps1`, **`scripts/bench/spark/*.sh` moved in** → `bench/spark/` (owner ruling: one instrument, one home; `spark/reports/` keeps the artifacts) |
| `hardware/` | `collect-disk-facts.sh`, `collect-smart-live.sh`, `collect-smart.ps1`, `wsl-nat-resolv.ps1` |

Folder-name rule the owner set: **name the folder after the toolchain the scripts actually drive** (`ansible`, not the doc
domain `deployment`), following `docs/index.md`'s vocabulary where a domain and a toolchain agree, and declaring the two
non-domain folders as exceptions in the registry header: `gate/` (its owning doc is CONVENTIONS.md — cross-cutting, like
CONVENTIONS itself) and `lib/` (not runnable).

## Stage 1 — structure-neutral, zero moves (the safety property; landed)

Stage 1 landed, and Stage 3 was unsafe without it. `lib/repo-root.sh` + `lib/repo_root.py` resolve the repo root by walking
up to the git toplevel (`git rev-parse --show-toplevel`, with an upward-scan fallback for a tarball checkout), every
fixed-depth root assumption outside `lib/` was converted, and the corpus-non-empty assertions are in every checker that
walks a tree. Standing rules this stage left behind:

* **A checker that walks a tree must assert the corpus is non-empty** (the `check_md_tables.py` model: assert >N files
  walked) — a broken root can otherwise print `OK: 0 files` green. This is what turns a tree move from a gamble into a
  mechanical sweep.
* **A root-resolution change proves itself before anything moves:** the self-test arm asserts the resolved root contains
  `IaC/ansible/` and `docs/index.md` — a wrong root is otherwise silent.
* `lib/pi-seat.sh`'s `pin()` is the one pin helper, replacing the per-script copies, and it carries the `$()`-subshell
  caveat: `pin()`'s `exit 1` inside `$( )` cannot stop the caller, and the shape is still live in `install-pi-debian.sh` /
  `pi-settings-config.sh`. Self-test both halves: a missing pin stops the caller; a present pin returns the value.
* **Registry hygiene stays a rule, not a one-off:** every script has exactly one `scripts/README.md` row, and duplicate rows
  in the cross-platform table are invisible to `check_md_tables.py`'s duplicate-identity half when they are plain-text keys
  (it fires on link-headed rows only).
* **`scripts/utils.txt` — that file does not exist in the tree any more** (deleted when `scripts/` was foldered; its four
  one-liners are folded into their owning docs, each re-read here by `git grep`:
  [docs/hardware-spark.md](docs/hardware-spark.md); `upsc powerwalker@localhost` → [docs/hardware-ups.md](docs/hardware-ups.md);
  the `powercfg` standby-disable → [docs/hardware-workstation.md](docs/hardware-workstation.md); `tailscale up --login-server` →
  [docs/network-vpn.md](docs/network-vpn.md)).
* `ansible-network-hop.sh` is deleted; its `scripts/README.md` row is a one-line retired note (history is git).

Commit discipline: one commit, `validate-all` green. **Never start a tree move in the same session's first commit.**

## Stage 2 — one plane registry + packages from pins (landed)

Stage 2 landed. `lib/seat-planes.yml` declares the plane set ONCE and is read by `pi-seat-sync.sh` (`planes_for_seat()`),
`install-pi-debian.sh`'s config stage and `install-pi-wsl.sh`'s config stage — per entry: plane, harness (`pi | all`),
owner script + check/push argv, applicable seats, with a `harness:` axis (the spec already renders a second harness —
`vendors: continue:` in the models spec) so the next harness is a row and not a restructure. The package inventory lives in
`IaC/ansible/group_vars/all/versions.yml` with **name + version + scope for every `pi_pkg_*` row** (the version is either
literal or a `version_pin:` reference to an existing pin), `pi-settings-config.sh` composes the settings `packages` array
from the `scope: fleet` rows by **discovery**, and `install-pi-wsl.sh` names no package literally. Standing rules this
stage left behind:

* **A from-zero `--check` must exercise the same plane set its `--push` does** — a config stage that pipes a plane through
  `tail -2` without `--strict` and without setting `bad=1`, or that omits a plane's `--check` entirely, can report a seat
  GREEN with planes never checked.
* **Every package a seat needs is versioned and owned** — a package named in one executable line with no version gets
  whatever its registry answers at install time; the pin inventory is the fix. The one `mutable: true` row
  (`pi_pkg_web_*`, `scope: seat`) is the documented exception — the cockpit self-updates inside a dist-tag — do not "fix" it
  by pinning it.
* Converge the seats with `bash scripts/harness/pi-seat-sync.sh --push` only **after** the paths a change moves are already
  in place — the driver's command strings are literal and the pre-flight compares each seat's
  `git rev-parse HEAD` with this checkout, so a seat on an old commit is `STALE-CLONE` by design, not a bug.

## Stage 3 — the moves (landed; the discipline and the traps stay)

Stage 3 landed: the tree was foldered one commit per folder, ordered by risk — `harness/` → `git/` → `hardware/` →
`secrets/` → `bench/` → `ansible/` → `gate/` → `lib/` already there — `git mv` only. The discipline is the standing rule for
any future move: one folder per commit; after the move, fix every intra-repo path reference (`validate-all.sh`, the driver's
plane argv, the installers' `"$REPO/scripts/…"` lines, docs, IaC comments) and re-run the two cheap witnesses before
committing:

```bash
bash scripts/validate-all.sh > /tmp/v.log 2>&1; echo "exit=$?"; grep -iE 'FAIL|OK: all' /tmp/v.log
git grep -n 'scripts/<moved-file>' -- . ':!reports'   # must print nothing
```

⛔ Never bundle two folders in one commit — a bad rebase here is how the merge-marker class happens, the
one `scripts/gate/check_merge_markers.py` now refuses.

**Standing traps for anyone who touches the foldered tree (each one is silent or expensive):**

- `IaC/ansible/roles/docker_services/defaults/main.yml:17` —
  `op_export_script: "{{ role_path }}/../../../../scripts/secrets/op-vault-export.py"`. It resolves by **relative depth**: keep
  the depth or change the IaC value **in the same commit** and re-converge `docker_services` once. A wrong depth here is a
  broken bulk 1P pre-pass at the next converge, not a broken doc link.
- `render_all.py` imports its renderers **by module name** (`importlib.import_module("render_network_addresses")`), i.e. it
  depends on them living in its own directory — it carries an explicit name→path map (`lib/repo_root.py` makes it trivial);
  a moved renderer otherwise makes the umbrella silently stop rendering what moved. `render_all --check` is wired into
  `validate-all.sh`, so the failure mode is a red gate at worst, a stale generated doc at best.
- IaC **comments** name scripts (`IaC/router/templates/*.rsc.j2` → `routeros-apply-delta.sh`;
  `roles/docker_services/tasks/main.yml:642` → `render_all.py`; `technitium-seed.yml:210` → `check_dns_seed_drift.py`).
  `check_doc_path_refs.py` catches dangling ones — treat a green there as necessary, not sufficient, for comments that are
  only prose-quoted.
- The seat driver (`pi-seat-sync.sh`) and both installers carry **literal command strings**; after any move, run
  `bash scripts/harness/pi-seat-sync.sh --self-test` (stubbed seats) **and** `--list` — at wherever the tree leaves the driver
  — and confirm every plane still reports a verdict rather than `FAILED` with `No such file`.
- `install-pi-wsl.sh` / `install-pi-debian.sh` are invoked by the runbook with paths in `deployment-manual.md` Phase 0/4c —
  sweep that file too (`check_runbook_purity.py` keeps it honest but does not check path existence beyond the ref checker).
- `scripts/bench/spark/*.sh` reference `results-v2.csv`, `raw/`, `accuracy/` **relative to their own location** while the
  artifacts stay in `spark/reports/` — auditing every one of their path derivations before a move is why they moved last
  inside the bench commit, with a read of `run-scenario.sh` before it.

## Stage 4 — the checker that makes the tree stay (landed)

`gate/check_script_layout.py` is landed and wired into `validate-all.sh`, asserting:

1. every tracked file under `scripts/` has exactly one row in `scripts/README.md`, and every row names an existing path;
2. `scripts/<path>` literals across the repo resolve (overlaps `check_doc_path_refs.py` deliberately — one of them is
   fail-closed on links, this one on commands);
3. **the depth ratchet**: no `parent.parent` / `SCRIPT_DIR/..` root derivation survives outside `lib/` — this is what keeps
   the root-resolution fix from regrowing one file at a time;
4. no second `pin()` / second tree-sync engine outside `lib/` (a ratchet with floor 1 — the width-rule lesson
   `scripts/gate/check_md_tables.py` carries: one finding at rest, not 41);
5. no `.ps1` and no data file at `scripts/` top level; `testdata/**` excluded from the registry requirement.

The registry is restructured into one section per folder, and [docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1 + [docs/harness-pi-seats.md](docs/harness-pi-seats.md) §5 +
[docs/deployment-ansible.md](docs/deployment-ansible.md) §Runner placement carry the new paths.

## The `harness` docs domain (landed; the `docs/`-wide move stays out of scope)

The `harness` domain exists and both legs are landed, so nothing is left to dispatch from here.
**(a)** `harness-pi.md` was split by subject into the five `docs/harness-pi-*.md` children, as its own change with its
own reference sweep — a `docs/<file>.md` split has call sites across the whole tree, which is why it is never folded into a
stage commit here. **(b)** [`scripts/gate/check_doc_domain.py`](scripts/gate/check_doc_domain.py) is written, wired into
`validate-all.sh` with its `--self-test`, and green at floor 0. **The taxonomy call stands** (owner-accepted defaults) and
the rules below are what it was built from — they stay the binding reading of the domain set for whoever
retags a doc, because the set is derived and the checker carries no list.

### The taxonomy call (binding for the checker and for the docs it checks)

The domain set is **derived from the tree** (`domain:` over tracked `docs/**/*.md`), never a list in the checker's source — that
is why the call below changes only doc frontmatter and why a new domain is a frontmatter edit, not a code change.

1. **A domain needs a hub only when it has ≥2 non-pair docs.** Hub = `role: index | broad`. A domain whose whole non-log body
   is one doc **is** its entry point, whatever its role — that is what lets `observability` (a `role: ssot` body) and
   `governance` (one doc) pass without inventing a file. Two `index|broad` docs in one domain is a finding (§2: two hubs are
   two opinions).
2. **A `-review.md` / `-rejected.md` pair cannot create a domain.** A pair whose `domain:` value appears on no doc body is a
   finding — a decision log dispatched from a hub that does not exist is the defect, not the naming.
3. **`storage` is not a domain** → retag [`docs/storage-rejected.md`](docs/storage-rejected.md) +
   [`docs/storage-review.md`](docs/storage-review.md) to `domain: deployment`. Two frontmatter lines, no rename, no row
   migration. Rationale: §8.1's test is a primary owning host/host-class and ZFS spans nas + oldsrv with none; §8.4 already
   names `storage.md` (`domain: deployment` + `cross_cutting: true`) as the canonical cross-cutting umbrella child, so making a
   domain out of it would convert §8.4's own example into a one-doc domain. *Recorded alternative:* if the owner later wants
   storage triage to dispatch from its own hub, retag [`docs/storage.md`](docs/storage.md) → `domain: storage` (keep
   `cross_cutting: true`) and amend §8.1/§8.4's storage lines — **the checker code is identical either way**, because the set is
   derived.
4. **[`docs/orchestration.md`](docs/orchestration.md) → `domain: meta`** + `cross_cutting: true`; its hub is
   [`docs/index.md`](docs/index.md) (`domain: meta`, `role: index`), which already lists the file in its docs tree. Not
   `governance`: that would need a new hub doc for two docs, and `CONVENTIONS.md` already owns repo-process content at root.
   The file has **no frontmatter at all** (line 1 is the `> **Role:**` quote), so this change writes the whole block.
5. **[`docs/spark-llm-profiles.md`](docs/spark-llm-profiles.md) → `domain: hardware`, `role: design-spec`** — the subject is the
   engine tier's serving config and the owning host is `spark`. Not `services` (no `docker_services` catalog), not `harness`
   (harness is the operator seats — [`docs/harness.md`](docs/harness.md) §What this domain is). Also has no frontmatter today.
6. **[`docs/manual/README.md`](docs/manual/README.md) → `role: index`** (was `reference`; its own `tags:` already say `index`).
   This was the **only real hub defect** in the tree: 13 docs under `manual/`, none of them a hub.
7. **§8.1's `role:` vocabulary widens** to admit `log`, `queue`, `evidence`, `incident-log` — the tree already carries them and
   the list omits them, so asserting "role ∈ §8.1 list" would be red at authoring. The checker asserts membership anyway, so a
   typo'd role cannot silently drop a doc out of every other rule.
8. **`*-generated.md` is out of scope** (§8.2 render views carry no frontmatter by design).

**Floor-0 wiring:** the two no-frontmatter docs carry a frontmatter block (rules 4–5), the storage pair is tagged
`domain: deployment` (rule 3), `manual/README.md` is `role: index` (rule 6), and [`CONVENTIONS.md`](CONVENTIONS.md) §8.1 carries the
vocabulary line (rule 7) plus the ≥2-doc hub floor and the pair-cannot-create-a-domain rule — zero renames, zero new docs,
zero new todo rows, so `check_doc_map.py` is untouched. Wire `check_doc_domain.py` + `--self-test` into `validate-all.sh`
**in the same commit as the fix that greens it** — a permanently red suite is a muted suite (`check_registry_prose.py`'s
floor-0 rule).

**Checker contract:** reads only the leading `---` block of each tracked `docs/**/*.md`, never prose (that is what makes it a
floor-0 gate and not a corpus leg); a corpus floor so an empty walk cannot print `OK: 0 domains`; `OK: <n> docs, <m> domains,
each with one claimed home` / `FAIL: <file>: <rule> — <detail>` with rc 1, `CANNOT RUN` rc 2 when `git ls-files` answers
nothing; `--self-test` proves **both halves** of every rule from a fixture under `scripts/testdata/` (excluded from the registry
requirement by `check_script_layout.py` rule 5) — missing `domain`, unknown-domain pair, second hub, missing hub on a ≥2-doc
domain, unknown `role`, and the empty-corpus floor. Do not add "every hub is linked from `docs/index.md`": `check_doc_map.py`
already refuses a doc under `docs/` that the map cannot reach — its map rule is **coverage**, basename-matched, with `manual/*` exempt because `manual/README.md` is their hub — so an orphaned hub cannot exist, and a second checker for the same fact is the §2 second-opinion error. Two of its boundaries matter to whoever writes this one: a **stale basename inside the `## Document Map` code block is NOT its finding** (a bogus name there still prints `OK`; `check_doc_path_refs.py` is what catches it), and **`prompt-*.md` handoffs sit outside both its scans**, so a link written in a brief is guarded by `check_doc_path_refs.py` alone — which is why every path this brief names has to be a real one.

## The `scripts/README.md` prose sweep (landed)

This one is the brief's own file, with no converge and no host slot: [scripts/README.md](scripts/README.md) and
[`scripts/gate/check_registry_prose.py`](scripts/gate/check_registry_prose.py) are the authority for its items, and wiring that
checker into `validate-all.sh` is the sweep's LAST item, not separate work. **Landed:**
`python3 scripts/gate/check_registry_prose.py --show` prints `registry: 120 linked rows, 0 state-date exempt site(s), 0 finding(s)`
and the checker runs there with its `--self-test`. The sequence below is the method, kept because the next registry sweep reuses it.

**The method, for the next registry sweep** (the file is a large fraction of a locally-served lane's rendered window — §Who runs this brief
— so it goes as a sequence of small commits, not one pass):

1. Measure once, with the gate: `python3 scripts/gate/check_registry_prose.py --show`. Count cells with a script, never by eye —
   `check_md_tables.py` is wider-only, so a row that lost its Owning-spec column is invisible to it (the row names the six).
2. Sweep **one registry section per commit** (the file is already one section per folder), gate green after each, exit code read
   from `$?`. Section-sized commits are what make a compaction survivable: the tree behind you is already correct.
3. Never touch a row's **first cell** (`check_script_layout.py` keys registry rows on it) and keep every rewritten row on **one
   physical line** (`check_md_tables.py` refuses a wrapped row, and a wrapped row silently un-checks every row below it).
4. Durable knowledge a cell was carrying goes to the doc in the row's **third column** — which is why the six missing Owning-spec
   columns are repaired before the prose pass, not during it.
5. Fix the two structural defects inside the file first (the verbatim-duplicated paragraph, the unescaped pipe inside a code span):
   they are what the gate's duplicate and pipe rules would otherwise report forever. Path-stale Portability rows: write the
   foldered path or delete the table — never leave a bare filename (`check_doc_path_refs.py`'s bare-path rule cannot see them).
6. Delete any hand-maintained `*Last updated …*` footer and any stale `Layout` bullet, then wire `check_registry_prose.py` +
   `--self-test` into `validate-all.sh` at **floor 0**, in the commit that clears the last finding.

## Acceptance

- `bash scripts/validate-all.sh` green in the worktree, exit code read from `$?` (never from a filtered view of the output).
- `git grep 'scripts/[a-z-]*\.\(sh\|py\|ps1\)'` returns **no** reference to a path that does not exist.
- the seat driver's `--self-test` (wherever the tree leaves it) has all canaries caught, and its `--list` prints the same plane set the
  registry declares.
- **The domain checker:** `python3 scripts/gate/check_doc_domain.py` prints `OK: 88 docs, 10 domains, each with one claimed home` and is
  **wired into `validate-all.sh`**, with `--self-test` catching both halves of every rule. The six floor-0 files named in §The taxonomy call are
  the only things it was told about — if it needs a list to pass, it is hardcoded and wrong.
- **The `scripts/README.md` prose sweep:** `python3 scripts/gate/check_registry_prose.py --show` prints **0 findings** and the checker runs as a gate item; the
  registry's `What it does` column states facts, not the story of how they were found.
- The registry row + this brief report: files moved, the two IaC touchpoints, and any plane that had to be re-converged on a
  seat.
