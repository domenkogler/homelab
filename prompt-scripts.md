# `prompt-scripts.md` — Lane brief · the `scripts/` restructure (HD-1118; the docs-domain split rides nothing, it is HD-1119)

> **Role:** dispatch note for **one** lane session: reorganise `scripts/` into named folders **without changing what any
> script does**. The rows are the authority for what is missing: [todo.md](todo.md) HD-1118 (+ HD-1119 for the docs half).
> The structure itself was brainstormed with the owner on 2026-10-09 and is **agreed as the target, not as a doc** — this
> file is the only place the agreed tree + the stage order are written down. Design context: [docs/pi-harness.md](docs/pi-harness.md)
> §1/§5 (the seat planes), [CONVENTIONS.md](CONVENTIONS.md) §6 (worktree/gate discipline), [`scripts/README.md`](scripts/README.md) (the registry).
> **Linked from:** [todo.md](todo.md) HD-1118

**Contract:** README §4 (this is a normal lane, not an §4-orchestrator lane): one session, one worktree, one branch, edits to
`todo.md` limited to **this row**. No live converges except the one named in Stage 3. `bash scripts/validate-all.sh` green
**in this worktree** before every commit; close-out = commit, row tail, stop.

**Why stages, not one move commit:** ~1,500 literal `scripts/<name>` references across 173 tracked files, and — the part that
would have bitten first — **the scripts do not know where the repo root is, they assume a fixed depth.** Fix that before any
file changes directory, or the move turns validators green-while-checking-nothing (Stage 1 is the whole reason Stage 3 is safe).

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
├── bench/       (5 + spark data)  serving-leg instruments, incl. spark/bench moved in
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
| `bench/` | `spark-llm-probe.py`, `spark-fp8-image-probe.py`, `spark-llm-render-matrix.py`, `laptop-llm.py`, `laptop/profiles.yml` (was `laptop-llm/`), `laptop/win/lmstudio-llm.ps1`, **`spark/bench/*.sh` moved in** → `bench/spark/` (owner ruling 2026-10-09: one instrument, one home; `spark/reports/` keeps the artifacts) |
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
   `install-nerd-font.sh:61`, `pi-settings-config.sh:89`, `install-pi-wsl.sh:51`), **carrying the `$()`-subshell fix** — HD-1115
   recorded that `pin()`'s `exit 1` inside `$( )` cannot stop the caller and that the shape is still live in
   `install-pi-debian.sh` / `pi-settings-config.sh`. Self-test both halves: a missing pin stops the caller; a present pin
   returns the value.
4. **Registry hygiene, no moves:** add the missing [`scripts/README.md`](scripts/README.md) row for `pi-self-update.sh` (the
   `pi-self` plane landed in HD-1115 with **no registry row** — the dispatcher missed a whole plane), and delete the two
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
   This is the change that makes `npm:pi-subagents` fleet-wide: today it is named in **one** executable line
   (`install-pi-wsl.sh:62`, no version → whatever npm answers) and reaches the other seats only because a session hand-ran
   `pi install` there; the settings plane classifies it as seat-local and keeps it, so nothing converges or pins it. Same
   treatment for `@season179/pi-worktree`, `@ogulcancelik/pi-ssh-tools`, `pi-deepseek-optimized`.
3. Converge the seats with `bash scripts/pi-seat-sync.sh --push` — **after** the paths move, not before (Stage 3 relocates
   the driver into its own folder; the command is otherwise unchanged) — because the driver's command strings are literal and
   the pre-flight compares each seat's
   `git rev-parse HEAD` with this checkout, so a seat on an old commit is `STALE-CLONE` by design, not a bug.

## Stage 3 — the moves (one commit per folder, ordered by risk, `git mv` only)

Order: `harness/` (self-contained, 12) → `git/` (3) → `hardware/` (4) → `secrets/` (8) → `bench/` (5 + `spark/bench/*`) →
`ansible/` (19, biggest sweep) → `gate/` (27, mechanical, safe only because Stage 1 fixed the roots) → `lib/` already there.

Per folder, in this order: `git mv`; fix intra-repo path references (`validate-all.sh`, the driver's plane argv, the
installers' `"$REPO/scripts/…"` lines, docs, IaC comments); re-run the two cheap witnesses before committing:

```bash
bash scripts/validate-all.sh > /tmp/v.log 2>&1; echo "exit=$?"; grep -iE 'FAIL|OK: all' /tmp/v.log
git grep -n 'scripts/<moved-file>' -- . ':!reports'   # must print nothing
```

⛔ Never bundle two folders in one commit — a bad rebase here is exactly how the merge-marker class happened, the
one `scripts/check_merge_markers.py` now refuses.

**Named traps for this stage (each one is silent or expensive, all are measured):**

- `IaC/ansible/roles/docker_services/defaults/main.yml:17` —
  `op_export_script: "{{ role_path }}/../../../../scripts/op-vault-export.py"`. It resolves by **relative depth**: either keep
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
  `bash scripts/pi-seat-sync.sh --self-test` (stubbed seats) **and** `--list` — at whichever path Stage 3 leaves it at —
  and confirm every plane still reports a
  verdict rather than `FAILED` with `No such file`.
- `install-pi-wsl.sh` / `install-pi-debian.sh` are invoked by the runbook with paths in `deployment-manual.md` Phase 0/4c —
  sweep that file too (`check_runbook_purity.py` keeps it honest but does not check path existence beyond the ref checker).
- `spark/bench/*.sh` reference `results-v2.csv`, `raw/`, `accuracy/` **relative to their own location**; moving them into
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
   `scripts/check_md_tables.py` carries: one finding at rest, not 41);
5. no `.ps1` and no data file at `scripts/` top level; `testdata/**` excluded from the registry requirement.

Then restructure `scripts/README.md` into one section per folder (the file's own §"Validation gate" / "Renderers" /
"Utilities" sections become folder sections), and update [docs/pi-harness.md](docs/pi-harness.md) §1/§5 +
[docs/deployment-ansible.md](docs/deployment-ansible.md) §Runner placement for the new paths.

## Out of scope for this lane (do not start it here)

**HD-1119 — the `docs/` reorganisation + the missing `harness` domain.** It is the *same* naming decision one level up
(`pi-harness.md` declares `domain: services`; `spark-llm-profiles.md` and `orchestration.md` declare no domain at all;
harness decisions currently sit in `services-ai-rejected.md` / `services-rejected.md`, which a `harness` prior-art sweep
cannot find), and it must not be folded in: `docs/<file>.md` is referenced ~2,289 times across 73 files, so the docs half has
its own cost curve and its own owner gate. If the domain set changes while this lane runs, only `gate/`'s and `lib/`'s
exception note is affected — which is why the note is prose in the registry header and not hardcoded in the checker.

## Acceptance

- `bash scripts/validate-all.sh` green in the worktree, exit code read from `$?` (never from a filtered view of the output).
- `git grep 'scripts/[a-z-]*\.\(sh\|py\|ps1\)'` returns **no** reference to a path that does not exist.
- the seat driver's `--self-test` (wherever Stage 3 puts it) has all canaries caught, and its `--list` prints the same plane set the
  registry declares.
- The registry row + this brief report: files moved, the two IaC touchpoints, and any plane that had to be re-converged on a
  seat.
