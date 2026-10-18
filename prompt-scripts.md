# `prompt-scripts.md` — Lane brief · the `scripts/` restructure (HD-1118; the docs-domain split rides nothing, it is HD-1119)

> **Role:** dispatch note for **one** lane session: reorganise `scripts/` into named folders **without changing what any
> script does**. The rows are the authority for what is missing: [todo.md](todo.md) HD-1118 (+ HD-1119 for the docs half).
> The structure itself was brainstormed with the owner on 2026-10-09 and is **agreed as the target, not as a doc** — this
> file is the only place the agreed tree + the stage order are written down. Design context: [docs/harness-pi-engines.md](docs/harness-pi-engines.md)
> §1 (the seat planes, split into [`docs/harness-pi-seats.md`](docs/harness-pi-seats.md) §5), [CONVENTIONS.md](CONVENTIONS.md) §6 (worktree/gate discipline), [`scripts/README.md`](scripts/README.md) (the registry).
> **Linked from:** [todo.md](todo.md) HD-1118
> **Status 2026-10-12:** HD-1118 **landed**, re-derived at the tip — Stages 1–4 below are the tree's provenance,
> not work; the unreplayable 2026-10-09 lane tree is pinned as `rescue/hd1118-20261011`. This brief now carries
> **HD-1119** (the `harness` docs domain) and the row's live legs. **Status 2026-10-18:** re-derived at the tip — the tree is
> foldered and `gate/check_script_layout.py` is wired, Stage 2's package-inventory tail is landed, HD-1118's two seat legs are
> closed and its third is **parked** (needs a clean Debian box). **HD-1141 landed**: [`scripts/gate/check_registry_prose.py`](scripts/gate/check_registry_prose.py)
> prints `registry: 120 linked rows, 0 state-date exempt site(s), 0 finding(s)` and runs in `validate-all.sh` with its
> `--self-test`. **HD-1119(a) landed**: the split was of `harness-pi.md` — not of [`docs/harness-pi-engines.md`](docs/harness-pi-engines.md),
> which is one of the five children it produced alongside [`docs/harness-pi-models.md`](docs/harness-pi-models.md), [`docs/harness-pi-seats.md`](docs/harness-pi-seats.md),
> [`docs/harness-pi-seat-identity.md`](docs/harness-pi-seat-identity.md), [`docs/harness-pi-terminal.md`](docs/harness-pi-terminal.md) — with its
> reference sweep and hub-map repair. **HD-1119(b) landed**: [`scripts/gate/check_doc_domain.py`](scripts/gate/check_doc_domain.py) exists, runs in
> `validate-all.sh` (run + `--self-test`) and prints `OK: 88 docs, 10 domains, each with one claimed home`.
> Read §What is open at this commit first; everything above it in this file is provenance.

**Contract:** README §4 (this is a normal lane, not an §4-orchestrator lane): one session, one worktree, one branch, edits to
`todo.md` limited to **this row**. No live converges except the one named in Stage 3. `bash scripts/validate-all.sh` green
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
| the **campaign** items — the landed `scripts/README.md` prose sweep (HD-1141) and the landed `docs/harness-pi-*.md` split with its reference sweep (HD-1119), and the gate legs that must compare whole-corpus behaviour (HD-1117's `render_all.py --check` wiring, HD-1137's quick-subset comparison) | the **designated runner station** with an externally-served model — [prompt-laptop-wsl.md](prompt-laptop-wsl.md) §0/§1, and the rule in [todo-table.md](todo-table.md) §C rule 9 |
| the **prep** for the campaign legs still live — measure the corpus, list the cells that must change, print the live count `check_registry_prose.py --show` prints (0 findings since HD-1141 landed, so the six rows that lacked the third column are repaired, not owed) | any seat, spark-served: it is read-only arithmetic and it is what makes the campaign one pass instead of a re-measurement |

Row ownership does not move: this brief keeps the rows (§B0 is the index), the station brief claims **legs, not rows**.

**Why stages, not one move commit:** ~1,500 literal `scripts/<name>` references across 173 tracked files, and — the part that
would have bitten first — **the scripts do not know where the repo root is, they assume a fixed depth.** Fix that before any
file changes directory, or the move turns validators green-while-checking-nothing (Stage 1 is the whole reason Stage 3 is safe).

## What is open at this commit (re-derived 2026-10-18)

Nothing in this brief moves a file any more. Stages 1-4 are provenance, **and Stage 2's tail landed too**: `IaC/ansible/group_vars/all/versions.yml` carries the `pi_pkg_*` inventory with `scope: fleet | seat` and a registry-verified version on every name, and `install-pi-wsl.sh` installs the fleet set by discovery rather than a bare literal list — so no package is unversioned and unowned.

| Leg | State | Who may run it |
|---|---|---|
| HD-1118 **(b)** — `install-pi-debian.sh --check` on a from-zero Debian seat | **PARKED, not open.** It is the only proof that the from-zero path converges the foldered tree, and it needs a clean Debian box: there is no in-lane command and no host in this repo that is a spare Debian box. Do not re-derive it here; the row closes when someone runs it in the seat lane | a clean Debian box, not this lane |
| HD-1119 **(a)** — split `harness-pi.md` by subject | **landed.** Five children now carry the content — [`docs/harness-pi-engines.md`](docs/harness-pi-engines.md), [`docs/harness-pi-models.md`](docs/harness-pi-models.md), [`docs/harness-pi-seats.md`](docs/harness-pi-seats.md), [`docs/harness-pi-seat-identity.md`](docs/harness-pi-seat-identity.md), [`docs/harness-pi-terminal.md`](docs/harness-pi-terminal.md) — with the whole-tree reference sweep and the hub-map repair in the same wave | nobody — the row's remaining ⏳ is in [todo.md](todo.md) HD-1119 |
| HD-1119 **(b)** — [`scripts/gate/check_doc_domain.py`](scripts/gate/check_doc_domain.py) | **landed and wired.** The run and its `--self-test` are `validate-all.sh` items; the verdict is `OK: 88 docs, 10 domains, each with one claimed home`. The domain set stays derived from `docs/**/*.md` frontmatter, so a retag moves the rule and not the code — the six floor-0 files in §The taxonomy call are what it was told about | nobody — retags are frontmatter edits, not a lane |
| HD-1141 — `scripts/README.md` prose sweep, then wire `check_registry_prose.py` | **landed.** `python3 scripts/gate/check_registry_prose.py --show` prints `registry: 120 linked rows, 0 state-date exempt site(s), 0 finding(s)` and the checker + `--self-test` run as gate items. The row is a record until the owner confirms the delete | nobody — [todo.md](todo.md) HD-1141 states the pending delete |

**Ordering inside this brief** (it was undeclared when two rows here edited the same file): that ordering is spent — **HD-1141** landed first and **HD-1119(a)**'s sweep landed on the registry text that survived it, exactly in that order. The only live work this brief carries now is **HD-1118's seat legs, run FROM the seats** (`pi-seat-sync.sh --check`, `install-tmux-conf.sh --push` on the win11 seat) and its **parked** from-zero leg; nothing in this brief has a file-moving order dependency left, and `gate/`'s and `lib/`'s exception note in the registry header stays the only registry text a domain-set change may touch.

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
| `ansible/` | `ansible-run.sh`, `ansible_query.py`, `guarded-converge.sh`, `restart-watchdog.sh`, `ak-shell.sh`, `probe-net-manager.sh`, `bootstrap-runner.sh`, `restore-runner-key.sh`, `seed-runner-ssh.sh`, `seed-seat-deploy-key.sh`, `render_network_addresses.py`, `render_rack_connections.py`, `zone_kogler_si_render.py`, `capture_zone_kogler_si_golden.py`, `knx-hass-gen.py`, `adapt-vllm-dashboards.py`, `build-llm-dashboard.py`, `routeros-apply-delta.sh`, `image-pin-probe.py` · **delete** `ansible-network-hop.sh` (headed OBSOLETE 2026-09-08; history is git) |
| `secrets/` | `provision-secrets.py`, `provision-vault.sh`, `op-vault-export.py`, `gen-htpasswd.py`, `get-bootstrap-keys.sh`, `rotate-spark-llm-key.sh`, `gen-custom-script.sh`, `gen-media-post-install.sh` |
| `git/` | `git-bootstrap.sh`, `git-bootstrap-win11.sh`, `data/gitconfig-nightly` (today's `scripts/git/` holds only that data file, with its two installers elsewhere — the folder becomes what a reader assumes it is) |
| `harness/` | `pi-seat-sync.sh`, `pi-self-update.sh`, `pi-settings-config.sh`, `pi-tui-config.sh`, `sync-skills.sh`, `sync-extensions.sh`, `install-nerd-font.sh`, `install-tmux-conf.sh`, `install-pi-debian.sh`, `install-pi-wsl.sh`, `render-pi-config.py`, `win/install-nerd-font.ps1`, `pi/models-spec.yml` (was `pi-config/`) |
| `bench/` | `spark-llm-probe.py`, `spark-fp8-image-probe.py`, `spark-llm-render-matrix.py`, `laptop-llm.py`, `laptop/profiles.yml` (was `laptop-llm/`), `laptop/win/lmstudio-llm.ps1`, **`scripts/bench/spark/*.sh` moved in** → `bench/spark/` (owner ruling 2026-10-09: one instrument, one home; `spark/reports/` keeps the artifacts) |
| `hardware/` | `collect-disk-facts.sh`, `collect-smart-live.sh`, `collect-smart.ps1`, `wsl-nat-resolv.ps1` |

Folder-name rule the owner set: **name the folder after the toolchain the scripts actually drive** (`ansible`, not the doc
domain `deployment`), following `docs/index.md`'s vocabulary where a domain and a toolchain agree, and declaring the two
non-domain folders as exceptions in the registry header: `gate/` (its owning doc is CONVENTIONS.md — cross-cutting, like
CONVENTIONS itself) and `lib/` (not runnable).

## Stage 1 — structure-neutral, zero moves (the safety property; ~5–7 files + the sweep)

Nothing in this stage depends on the tree decision, and Stage 3 is unsafe without it.

1. **`lib/repo-root.sh` + `lib/repo_root.py`** — resolve the repo root by walking up to the git toplevel
   (`git rev-parse --show-toplevel`, with an upward-scan fallback for a tarball checkout — the same case that made
   `pi-seat-sync.sh --self-test` read every seat as STALE-CLONE once). Then convert **every fixed-depth assumption**:
   22 bash files with `REPO="$(cd "$SCRIPT_DIR/.." && pwd)"`, 29 python files with `ROOT = Path(__file__).resolve().parent.parent`,
   `win/lmstudio-llm.ps1:52` `$PSScriptRoot\..\..`, and the two same-dir imports
   (`check_dns_seed_drift.py:50`, `check_zone_kogler_si_parity.py:31` — `sys.path.insert(0, parent)` then
   `import zone_kogler_si_render`). **Prove the conversion before moving anything:** add a self-test arm that asserts the
   resolved root contains `IaC/ansible/` and `docs/index.md` — a wrong root is otherwise silent.
2. **Corpus-non-empty assertions** in every checker that walks a tree (the `check_md_tables.py` model: assert >N files
   walked), so a broken root can never print `OK: 0 files`. This is what turns Stage 3 from a gamble into a mechanical sweep.
3. **`lib/pi-seat.sh`**: one `pin()` replacing the 5 byte-identical copies (`install-pi-debian.sh:60`, `pi-self-update.sh:64`,
   `install-nerd-font.sh:61`, `pi-settings-config.sh:89`, `install-pi-wsl.sh:51`), **carrying the `$()`-subshell fix** — the pin helper
   recorded that `pin()`'s `exit 1` inside `$( )` cannot stop the caller and that the shape is still live in
   `install-pi-debian.sh` / `pi-settings-config.sh`. Self-test both halves: a missing pin stops the caller; a present pin
   returns the value.
4. **Registry hygiene, no moves:** add the missing [`scripts/README.md`](scripts/README.md) row for `pi-self-update.sh` (the
   `pi-self` plane landed (with the pin helper) with **no registry row** — the dispatcher missed a whole plane), and delete the two
   duplicate rows in the cross-platform table (`check_iac_backend_strings.py`, `testdata/check-vault-items/run.sh` —
   `check_md_tables.py`'s duplicate-identity half only fires on link-headed rows, so plain-text keys are invisible to it).
5. **`scripts/utils.txt` → delete after folding its four one-liners into their owning docs** (spark vllm health-wait →
   [docs/hardware-spark.md](docs/hardware-spark.md); `upsc powerwalker@localhost` → [docs/hardware-ups.md](docs/hardware-ups.md);
   the `powercfg` standby-disable → [docs/hardware-workstation.md](docs/hardware-workstation.md); `tailscale up --login-server` →
   [docs/network-vpn.md](docs/network-vpn.md)). A scratch pad is the only place those commands are currently written down.
6. **Delete `ansible-network-hop.sh`** and reduce its `scripts/README.md` row to a one-line retired note.

Commit: one commit, `validate-all` green. **Do not start Stage 3 in the same session's first commit.**

## Stage 2 — one plane registry + packages from pins (still no moves)

1. **`lib/seat-planes.yml`** — the plane set declared ONCE, read by `pi-seat-sync.sh` (`planes_for_seat()` today),
   `install-pi-debian.sh`'s config stage and `install-pi-wsl.sh`'s config stage. Per entry: plane, harness (`pi | all`),
   owner script + check/push argv, applicable seats. Fixes two live defects by construction: `install-pi-debian.sh`'s
   `check()` pipes `sync-skills` / `sync-extensions` / `install-nerd-font` through `tail -2` **without `--strict` and without
   setting `bad=1`**, and never runs `install-tmux-conf.sh --check` — so a from-zero seat can be reported GREEN with three
   planes never checked, while its `--push` does run them. Give the registry a `harness:` axis now (the spec already renders a
   second harness — `vendors: continue:` in the models spec), so the next harness is a row and not a restructure.
2. **Packages from the pins**: move the package inventory into `group_vars/all/versions.yml` (name + version + scope:
   `fleet | seat`), composed by `pi-settings-config.sh`. Delete the unversioned literal list in `install-pi-wsl.sh:60-66`.
   This is the change that makes `npm:pi-subagents` fleet-wide: before 2026-10-09 it was named in **one** executable line
   (`install-pi-wsl.sh:62`, no version → whatever npm answers) and reached the other seats only because a session hand-ran
   `pi install` there; the settings plane classified it as seat-local and kept it, so nothing converges or pins it. Same
   treatment for `@season179/pi-worktree`, `@ogulcancelik/pi-ssh-tools`, `pi-deepseek-optimized`.
   ✅ **2026-10-09 (part, seat lane):** `pi-subagents` + `pi-deepseek-optimized` now have pins
   (`pi_host_subagents_npm_*` / `pi_host_deepseek_npm_*`) and belong to the settings plane's owned set, and
   `install-pi-wsl.sh` versions those two from the pins instead of naming them bare. ✅ **Closed at the tip:** the inventory in
   `IaC/ansible/group_vars/all/versions.yml` carries **name + version + scope for all seven `pi_pkg_*` rows** (the version is
   either literal or a `version_pin:` reference to an existing pin), `pi-settings-config.sh` composes the settings `packages`
   array from the `scope: fleet` rows by **discovery**, and the installer names no package literally. The one `mutable: true` row
   (`pi_pkg_web_*`, `scope: seat`) is the documented exception — the cockpit self-updates inside a dist-tag — do not "fix" it by
   pinning it.
3. Converge the seats with `bash scripts/harness/pi-seat-sync.sh --push` — **after** the paths move, not before (Stage 3 relocates
   the driver into its own folder; the command is otherwise unchanged) — because the driver's command strings are literal and
   the pre-flight compares each seat's
   `git rev-parse HEAD` with this checkout, so a seat on an old commit is `STALE-CLONE` by design, not a bug.

## Stage 3 — the moves (one commit per folder, ordered by risk, `git mv` only)

Order: `harness/` (self-contained, 12) → `git/` (3) → `hardware/` (4) → `secrets/` (8) → `bench/` (5 + `scripts/bench/spark/*`) →
`ansible/` (19, biggest sweep) → `gate/` (27, mechanical, safe only because Stage 1 fixed the roots) → `lib/` already there.

Per folder, in this order: `git mv`; fix intra-repo path references (`validate-all.sh`, the driver's plane argv, the
installers' `"$REPO/scripts/…"` lines, docs, IaC comments); re-run the two cheap witnesses before committing:

```bash
bash scripts/validate-all.sh > /tmp/v.log 2>&1; echo "exit=$?"; grep -iE 'FAIL|OK: all' /tmp/v.log
git grep -n 'scripts/<moved-file>' -- . ':!reports'   # must print nothing
```

⛔ Never bundle two folders in one commit — a bad rebase here is exactly how the merge-marker class happened, the
one `scripts/gate/check_merge_markers.py` now refuses.

**Named traps for this stage (each one is silent or expensive, all are measured):**

- `IaC/ansible/roles/docker_services/defaults/main.yml:17` —
  `op_export_script: "{{ role_path }}/../../../../scripts/secrets/op-vault-export.py"`. It resolves by **relative depth**: either keep
  the depth or change the IaC value **in the same commit** and re-converge `docker_services` once. A wrong depth here is a
  broken bulk 1P pre-pass at the next converge, not a broken doc link.
- `render_all.py:103,144` imports its renderers **by module name** (`importlib.import_module("render_network_addresses")`),
  i.e. it depends on them living in its own directory. Give it an explicit name→path map (Stage 1's `repo_root` makes it
  trivial) — otherwise the umbrella silently stops rendering what moved. `render_all --check` is wired into
  `validate-all.sh`, so the failure mode is a red gate at worst, a stale generated doc at best.
- IaC **comments** name scripts (`IaC/router/templates/*.rsc.j2` → `routeros-apply-delta.sh`;
  `roles/docker_services/tasks/main.yml:642` → `render_all.py`; `technitium-seed.yml:210` → `check_dns_seed_drift.py`).
  `check_doc_path_refs.py` catches dangling ones — treat a green there as necessary, not sufficient, for comments that are
  only prose-quoted.
- The seat driver (`pi-seat-sync.sh`) and both installers carry **literal command strings**; after the move, run
  `bash scripts/harness/pi-seat-sync.sh --self-test` (stubbed seats) **and** `--list` — at whichever path Stage 3 leaves it at —
  and confirm every plane still reports a
  verdict rather than `FAILED` with `No such file`.
- `install-pi-wsl.sh` / `install-pi-debian.sh` are invoked by the runbook with paths in `deployment-manual.md` Phase 0/4c —
  sweep that file too (`check_runbook_purity.py` keeps it honest but does not check path existence beyond the ref checker).
- `scripts/bench/spark/*.sh` reference `results-v2.csv`, `raw/`, `accuracy/` **relative to their own location**; moving them into
  `bench/spark/` while the artifacts stay in `spark/reports/` means auditing every one of their path derivations first —
  that is why they move last inside Stage 3's bench commit, with a read of `run-scenario.sh` before it.

## Stage 4 — the checker that makes the tree stay (end of lane)

`gate/check_script_layout.py`, wired into `validate-all.sh`, asserting:

1. every tracked file under `scripts/` has exactly one row in `scripts/README.md` (this is what `pi-self-update.sh` needed),
   and every row names an existing path;
2. `scripts/<path>` literals across the repo resolve (overlaps `check_doc_path_refs.py` deliberately — one of them is
   fail-closed on links, this one on commands);
3. **the depth ratchet**: no `parent.parent` / `SCRIPT_DIR/..` root derivation survives outside `lib/` — this is what keeps
   the Stage-1 fix from regrowing one file at a time;
4. no second `pin()` / second tree-sync engine outside `lib/` (a ratchet with floor 1 — the width-rule lesson
   `scripts/gate/check_md_tables.py` carries: one finding at rest, not 41);
5. no `.ps1` and no data file at `scripts/` top level; `testdata/**` excluded from the registry requirement.

Then restructure `scripts/README.md` into one section per folder (the file's own §"Validation gate" / "Renderers" /
"Utilities" sections become folder sections), and update [docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1 + [docs/harness-pi-seats.md](docs/harness-pi-seats.md) §5 +
[docs/deployment-ansible.md](docs/deployment-ansible.md) §Runner placement for the new paths.

## HD-1119 — the `harness` docs domain (both legs landed; the `docs/`-wide move stays out of scope)

The `harness` domain exists now and both legs are landed, so what is left is what the row's ⏳ names.
**(a)** Landed: `harness-pi.md` was split by subject into the five `docs/harness-pi-*.md` children, as its own change with its
own reference sweep — a `docs/<file>.md` split has call sites across the whole tree, which is why it was never folded into a
stage commit here. **(b)** Landed: [`scripts/gate/check_doc_domain.py`](scripts/gate/check_doc_domain.py) is written, wired into
`validate-all.sh` with its `--self-test`, and green at floor 0. **The taxonomy call was made** (owner accepted these defaults
2026-10-18) and the rules below are what it was built from — they stay the binding reading of the domain set for whoever
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
   Measured, this is the **only real hub defect** in the tree: 13 docs under `manual/`, none of them a hub.
7. **§8.1's `role:` vocabulary widens** to admit `log`, `queue`, `evidence`, `incident-log` — the tree already carries them and
   the list omits them, so asserting "role ∈ §8.1 list" would be red at authoring. The checker asserts membership anyway, so a
   typo'd role cannot silently drop a doc out of every other rule.
8. **`*-generated.md` is out of scope** (§8.2 render views carry no frontmatter by design).

**Floor-0 diff for the wiring commit** (measured at the tip — six files, zero renames, zero new docs, zero new todo rows, so
`check_doc_map.py` is untouched): the two no-frontmatter docs get a block (rules 4-5), the storage pair gets `domain: deployment`
(rule 3), `manual/README.md` gets `role: index` (rule 6), and [`CONVENTIONS.md`](CONVENTIONS.md) §8.1 gets the vocabulary line
(rule 7) plus the ≥2-doc hub floor and the pair-cannot-create-a-domain rule. Wire `check_doc_domain.py` + `--self-test` into
`validate-all.sh` **in that same commit** — a permanently red suite is a muted suite (the HD-1141 rule).

**Checker contract:** reads only the leading `---` block of each tracked `docs/**/*.md`, never prose (that is what makes it a
floor-0 gate and not a corpus leg); a corpus floor so an empty walk cannot print `OK: 0 domains`; `OK: <n> docs, <m> domains,
each with one claimed home` / `FAIL: <file>: <rule> — <detail>` with rc 1, `CANNOT RUN` rc 2 when `git ls-files` answers
nothing; `--self-test` proves **both halves** of every rule from a fixture under `scripts/testdata/` (excluded from the registry
requirement by `check_script_layout.py` rule 5) — missing `domain`, unknown-domain pair, second hub, missing hub on a ≥2-doc
domain, unknown `role`, and the empty-corpus floor. Do not add "every hub is linked from `docs/index.md`": `check_doc_map.py`
already refuses a doc under `docs/` that the map cannot reach — its map rule is **coverage**, basename-matched, with `manual/*` exempt because `manual/README.md` is their hub — so an orphaned hub cannot exist, and a second checker for the same fact is the §2 second-opinion error. Two of its boundaries matter to whoever writes this one: a **stale basename inside the `## Document Map` code block is NOT its finding** (measured at the tip: a bogus name there still prints `OK`; `check_doc_path_refs.py` is what catches it), and **`prompt-*.md` handoffs sit outside both its scans**, so a link written in a brief is guarded by `check_doc_path_refs.py` alone — which is why every path this brief names has to be a real one.

## HD-1141 — the `scripts/README.md` prose sweep (landed; the row is a record)

This one is the brief's own file, with no converge and no host slot: [todo.md](todo.md) HD-1141 is the authority for its items,
and wiring `scripts/gate/check_registry_prose.py` into `validate-all.sh` is that row's LAST item, not separate work. **Landed:**
`python3 scripts/gate/check_registry_prose.py --show` prints `registry: 120 linked rows, 0 state-date exempt site(s), 0 finding(s)`
and the checker runs there with its `--self-test`. The sequence below is the method, kept because the next registry sweep reuses it.

**How it was survived in one lane** (the file is a large fraction of a locally-served lane's rendered window — §Who runs this brief
— so it went as a sequence of small commits, not one pass):

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
6. Delete the hand-maintained `*Last updated …*` footer and the stale `Layout` bullet, then wire `check_registry_prose.py` +
   `--self-test` into `validate-all.sh` at **floor 0**, in the commit that clears the last finding.

## Acceptance

- `bash scripts/validate-all.sh` green in the worktree, exit code read from `$?` (never from a filtered view of the output).
- `git grep 'scripts/[a-z-]*\.\(sh\|py\|ps1\)'` returns **no** reference to a path that does not exist.
- the seat driver's `--self-test` (wherever Stage 3 puts it) has all canaries caught, and its `--list` prints the same plane set the
  registry declares.
- **HD-1119(b):** `python3 scripts/gate/check_doc_domain.py` prints `OK: 88 docs, 10 domains, each with one claimed home` and is
  **wired into `validate-all.sh` in the same commit that made it green**, with `--self-test` catching both halves of every rule. The six floor-0 files named in §The taxonomy call are
  the only things it was told about — if it needs a list to pass, it is hardcoded and wrong.
- **HD-1141:** `python3 scripts/gate/check_registry_prose.py --show` prints **0 findings** and the checker runs as a gate item; the
  registry's `What it does` column states facts, not the story of how they were found.
- The registry row + this brief report: files moved, the two IaC touchpoints, and any plane that had to be re-converged on a
  seat.
