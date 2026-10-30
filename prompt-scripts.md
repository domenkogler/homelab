# `prompt-scripts.md` — Lane brief · the `scripts/` restructure (HD-1118) and the rows that ride it

> **Role:** dispatch note for **one** lane session: the `scripts/` restructure — reorganise `scripts/` into named folders
> **without changing what any script does** — is **landed**; what this brief dispatches now is its remaining legs and riders.
> The rows are the authority for what is missing: [todo.md](todo.md) **HD-1118 · HD-1125 · HD-1138**
> (row ids as of `c13e30f6` — re-derive with `grep -c "^| HD-<id> " todo.md` before quoting one); the landed half's record is
> the docs themselves plus git, never a pointer. **HD-1125** and **HD-1138** are carried here because every remaining leg of
> each of them edits `scripts/**`; their hosts, slots and traps are in §What is open.
> The foldered tree is written down in [`scripts/README.md`](scripts/README.md) §The tree and held by
> [`scripts/gate/check_script_layout.py`](scripts/gate/check_script_layout.py) — this file carries the contract, the legs and
> the traps, not the tree. Design context: [docs/harness-pi-seats.md](docs/harness-pi-seats.md)
> §1 (the seat planes and the deploy direction) and its §5 (the reference `settings.json` block),
> [CONVENTIONS.md](CONVENTIONS.md) §6 (worktree/gate discipline), [`scripts/README.md`](scripts/README.md) (the registry).
> **Linked from:** [todo.md](todo.md) HD-1118
> **Status:** the tree is foldered and the layout checker is wired; §What is landed is provenance, not work, and the
> unreplayable lane tree is a `rescue/` ref — derive it with `git for-each-ref "refs/*/rescue/*"`, never copy a name. HD-1118
> carries **three live legs**: the two seat legs run FROM the seats (`pi-seat-sync.sh --check` per seat, `install-tmux-conf.sh
> --push` on the win11 seat), plus the from-zero `install-pi-debian.sh --check` leg, **parked** for want of a clean Debian box.
> The verdicts of the landed halves are what their own commands print — quoted in §What is landed, never typed into prose here.
> Read §What is open first.

**Contract:** README §4 (this is a normal lane, not an §4-orchestrator lane): one session, one worktree, one branch, edits to
`todo.md` limited to **the rows this brief carries** — never another lane's row and never a view (O2). No live converges — the
live legs are seat-side, and the parked from-zero check waits on a host this lane does not own. `bash
scripts/validate-all.sh` green **in this worktree** before every commit; close-out = commit, row tail, stop.

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
| the **campaign** items — the gate legs that must compare whole-corpus behaviour (HD-1117's `render_all.py --check` wiring, HD-1137's quick-subset comparison), and any future registry sweep, which is the same working set | the **designated runner station** with an externally-served model — [prompt-laptop-wsl.md](prompt-laptop-wsl.md) §0/§1, and the rule in [todo-table.md](todo-table.md) §C rule 9 |
| the **prep** for those legs — measure the corpus, list the cells that must change, print what `python3 scripts/gate/check_registry_prose.py --show` prints | any seat, spark-served: it is read-only arithmetic and it is what makes the campaign one pass instead of a re-measurement |

Row ownership does not move: this brief keeps the rows (§B0 is the index), the station brief claims **legs, not rows**.

**Why this went as stages, not one move commit:** the reference count is derivable
(`git grep -lE 'scripts/[a-zA-Z0-9_-]+\.(sh|py|ps1)' | wc -l` over the tracked tree) and it was never the hard part — the
part that would have bitten first is that **a script did not know where the repo root is, it assumed a fixed depth.** Root
resolution had to be structural before any file changed directory, or the move turns validators green-while-checking-nothing.

## What is open

Nothing in this brief moves a file: the tree, the harness split, the domain checker and the registry sweep are landed and
§What is landed names the command that holds each. What is live is HD-1118's legs and the two riders whose remaining edits all
land in `scripts/**`.

| Leg | State | Who may run it |
|---|---|---|
| HD-1118 **(a)** + **(c)** — the two seat legs | **open, and they run FROM the seats**: `bash scripts/harness/pi-seat-sync.sh --check` on each seat once it has fast-forwarded, and `bash scripts/harness/install-tmux-conf.sh --push` on the **win11** seat (the provenance marker names `pi-agent/tmux/tmux.conf`, so an installed `~/.tmux.conf` reads `DRIFT` until one push — recognised by `MARKER_LEGACY`, never refused). Each plane converges from its own clone, so each runs in that seat's own session | the win11 and `wsl -d Debian` seats. ⛔ the `oldsrv` seat cannot print `pre-flight OK` from a session branch that is not on `origin/main` — the pre-flight compares the seat's clone with the checkout the driver runs from, so a session branch reads `STALE-CLONE` forever; run its declared planes in place in that clone with the registry's own `check:` arguments |
| HD-1118 **(b)** — `install-pi-debian.sh --check` on a from-zero Debian seat | **PARKED, not open.** It is the only proof that the from-zero path converges the foldered tree, and it needs a clean Debian box: there is no in-lane command and no host in this repo that is a spare Debian box. Do not re-derive it here; the row closes when someone runs it in the seat lane | a clean Debian box, not this lane |
| **HD-1125** — the fleet automation key sits at ssh's DEFAULT path (`~/.ssh/id_ed25519`) on the WSL and cockpit seats, byte-identical to `ansible-admin_ssh`, so HD-1123's retirement rule cannot close | **open, with the `scripts/**` half landed except one file this lane does not own.** The legs that type `vps.kogler.si` name the canonical identity (`ak-shell.sh`, `seed-runner-ssh.sh`'s `KEY`), and `ssh/aliases.tmpl` carries that FQDN on the `Host vps` line — on every class, because an unlisted spelling is the same gap wherever it is typed; the row is the authority for what is left, and it is two things: `scripts/secrets/provision-vault.sh` (the secrets lane's file) and **OQ-17**, which decides where a runner's automation identity lives before `restore-runner-key.sh`'s target can move | the lane for the `scripts/**` hunks; **on each seat** for the rename itself — ⛔ never rename before every caller names an `IdentityFile` and BOTH legs are re-proved with the file aside. No converge; the cockpit seat's copy is the retirement list's step-6 measurement and is not observable from the box running this |
| **HD-1138** — the alias contract now defaults to LAN-direct: a plain `<node>` name takes the Home leg with no jump, `<node>-vps` is the opt-in hop | **landed; one consumer sweep left.** `seed-seat-ssh-config.sh` enforces rule 1 mechanically (a `ProxyJump` may sit only in an all-`-vps` block) plus the five names and a count, and the jump Ansible uses is the inventory's, so no converge is touched. The consumers are the scripts that shell out to bare `ssh <name>`, and each now states its hop at its own seam — `PI_OLDSRV_TARGET=oldsrv-domen-vps` (`pi-seat-sync.sh`), `--host spark-vps` / `STABILITY_HOST` / `VM_SSH_HOST` (`scripts/bench/spark/`), `OLDSRV_SSH` (`rotate-spark-llm-key.sh`), `ssh oldsrv-vps …` in the run-on-the-seat examples of `bootstrap-runner.sh` and `seed-seat-deploy-key.sh`. What is owed is the away measurement itself, which no in-house leg can produce | the lane for the script sweep; the seat premise (the Home-leg binding inside WSL, where the interface carries a NAT address) is a router-slot leg and is **not** this lane's. ⚠ A timeout on those legs **away** is this row, not a dead host — the `-vps` leg answering rc 0 while the plain leg times out is what proves the seat is away |

**Ordering inside this brief:** no file-moving order is left to declare. The live work is HD-1118's two seat legs and its
parked from-zero leg, then HD-1125's callers (which must name an `IdentityFile` **before** any default-path key is renamed) and
HD-1138's bare-`ssh <name>` consumers; the `scripts/**` order in the two rows above is the order. `gate/`'s and `lib/`'s
exception note in the registry header stays the only registry text a domain-set change may touch.

## What is landed, and what holds it

The tree, the harness split, the domain checker and the registry sweep are done; their record is the registry, the owning docs
and git — not this file. Each line is the fact plus the command that keeps it true.

| Landed | What holds it |
|---|---|
| `scripts/` foldered — `lib/ gate/ ansible/ secrets/ git/ harness/ bench/ hardware/ testdata/`, with `validate-all.sh` and `render_all.py` kept at root because they are what a human, cron or the gate invokes by name. Folders are named for the **toolchain the scripts drive**, not the doc domain; `gate/` (owned by CONVENTIONS, cross-cutting) and `lib/` (not runnable) are the two declared non-domain exceptions | [`scripts/README.md`](scripts/README.md) §The tree + `python3 scripts/gate/check_script_layout.py`: exactly one registry row per tracked file and every named path exists, `scripts/<path>` literals across the repo resolve, the **depth ratchet** (no `parent.parent` / `SCRIPT_DIR/..` root derivation outside `lib/`), no second `pin()` and no second tree-sync engine, no `.ps1` or data file at `scripts/` top level, `testdata/**` exempt |
| Repo-root resolution is structural: `lib/repo-root.sh` + `lib/repo_root.py` walk up to the git toplevel (with an upward-scan fallback for a tarball checkout), so no script assumes a depth | the corpus-non-empty assertion in every checker that walks a tree (the `check_md_tables.py` model — assert >N files walked, because a broken root otherwise prints `OK: 0 files` green) plus the root self-test (the resolved root must contain `IaC/ansible/` and `docs/index.md`). ⚠ `lib/pi-seat.sh`'s `pin()` cannot stop its caller from inside `$( )` — the shape is still live in `install-pi-debian.sh` / `pi-settings-config.sh`, so self-test both halves: a missing pin stops the caller, a present pin returns the value |
| The plane registry and the package inventory: `lib/seat-planes.yml` declares the plane set ONCE (read by `pi-seat-sync.sh` and both installers' config stages), and `IaC/ansible/group_vars/all/versions.yml` carries name + version + `scope` (`fleet` or `seat`) for every `pi_pkg_*` row — so `install-pi-wsl.sh` names no package literally and nothing is unversioned and unowned | `bash scripts/harness/pi-seat-sync.sh --self-test` and `--list`. A from-zero `--check` must exercise the **same plane set** its `--push` does, or it reports a seat GREEN with planes never checked. The one `mutable: true` row (`pi_pkg_web_*`, `scope: seat`) is the documented exception — do not "fix" it by pinning it |
| The `harness` docs domain: `harness-pi.md` is now the five `docs/harness-pi-*.md` children plus the hub [`docs/harness.md`](docs/harness.md), and the domain **set** is derived from `domain:` frontmatter over `docs/**/*.md` — so a retag moves the rule, never the code | `python3 scripts/gate/check_doc_domain.py` (+ `--self-test`), wired into `validate-all.sh` at floor 0. The binding taxonomy reading — the ≥2-non-pair-doc hub floor, a `-review`/`-rejected` pair cannot create a domain, `storage` is not a domain, the widened `role:` vocabulary — is [CONVENTIONS.md](CONVENTIONS.md) §8.1, not this brief |
| The `scripts/README.md` prose sweep: the registry's `What it does` column states facts, not the story of how they were found, and carries one section per folder | `python3 scripts/gate/check_registry_prose.py --show` (+ `--self-test`), both `validate-all.sh` items |
| The moved one-liners: `scripts/utils.txt` does not exist in the tree any more — its four lines went to their owning docs ([docs/hardware-spark.md](docs/hardware-spark.md), [docs/hardware-ups.md](docs/hardware-ups.md), [docs/hardware-workstation.md](docs/hardware-workstation.md), [docs/network-vpn.md](docs/network-vpn.md)) — and `ansible-network-hop.sh` is deleted with a retired note in the registry. The foldered paths are also carried by [docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1 + §5 and [docs/deployment-ansible.md](docs/deployment-ansible.md) §Runner placement | `python3 scripts/gate/check_doc_path_refs.py` — the tree proves a citation, so cite the doc, not the story |

**A move, if one is ever owed again — none is owed now:** `git mv` only, **one folder per commit**, ordered by risk. After
each, fix every intra-repo reference (`validate-all.sh`, the driver's plane argv, the installers' `"$REPO/scripts/…"` lines,
docs, IaC comments) and re-run the two cheap witnesses below before committing. ⛔ Never bundle two folders in one commit — a
bad rebase there is the merge-marker class `scripts/gate/check_merge_markers.py` refuses — and never start a tree move in a
session's first commit.

```bash
bash scripts/validate-all.sh > /tmp/v.log 2>&1; echo "exit=$?"; grep -iE 'FAIL|OK: all' /tmp/v.log
git grep -n 'scripts/<moved-file>' -- . ':!reports'   # must print nothing
```

**Standing traps for anyone who touches the foldered tree** (each one is silent or expensive):

- `op_export_script: "{{ role_path }}/../../../../scripts/secrets/op-vault-export.py"` in
  `IaC/ansible/roles/docker_services/defaults/main.yml` — it resolves by **relative depth**: keep
  the depth or change the IaC value **in the same commit** and re-converge `docker_services` once. A wrong depth here is a
  broken bulk 1P pre-pass at the next converge, not a broken doc link.
- `render_all.py` imports its renderers **by module name** (`importlib.import_module("render_network_addresses")`), i.e. it
  depends on them living in its own directory — it carries an explicit name→path map (`lib/repo_root.py` makes it trivial);
  a moved renderer otherwise makes the umbrella silently stop rendering what moved. `render_all --check` is wired into
  `validate-all.sh`, so the failure mode is a red gate at worst, a stale generated doc at best.
- IaC **comments** name scripts (`IaC/router/templates/*.rsc.j2` → `routeros-apply-delta.sh`;
  `roles/docker_services/tasks/main.yml` → `scripts/render_all.py`; `roles/docker_services/tasks/technitium-seed.yml` → `check_dns_seed_drift.py`).
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


**The method, for the next registry sweep** (the file is a large fraction of a locally-served lane's rendered window —
§Who runs this brief — so it goes as a sequence of small commits, never one pass):

1. Measure once, with the gate: `python3 scripts/gate/check_registry_prose.py --show`. Count cells with a script, never by
   eye — `check_md_tables.py` is wider-only, so a row that lost its Owning-spec column is invisible to it.
2. Sweep **one registry section per commit**, gate green after each with the exit code read from `$?`. Section-sized commits
   are what make a compaction survivable: the tree behind you is already correct.
3. ⛔ Never touch a row's **first cell** (`check_script_layout.py` keys registry rows on it) and keep every rewritten row on
   **one physical line** — `check_md_tables.py` refuses a wrapped row, and a wrapped row silently un-checks every row below it.
4. Durable knowledge a cell was carrying goes to the doc in that row's **third column**, which is why a missing Owning-spec
   column is repaired before the prose pass, not during it. Fix the file's own structural defects first (a verbatim-duplicated
   paragraph, an unescaped pipe inside a code span) — they are what the duplicate and pipe rules would report forever.
5. Path-stale Portability rows: write the foldered path or delete the table, never leave a bare filename (the bare-path rule
   cannot see them). Delete any hand-maintained `*Last updated …*` footer or stale `Layout` bullet, and keep
   `check_registry_prose.py` + `--self-test` wired **at floor 0** — a permanently red suite is a muted suite.

⚠ Two checker boundaries, so a green is read for what it is: a stale basename **inside** the `## Document Map` code block is
not `check_doc_map.py`'s finding (its rule is coverage, basename-matched, `manual/*` exempt) — `check_doc_path_refs.py` is
what catches it — and `prompt-*.md` briefs sit outside **both** scans, so a path named in a brief is guarded by
`check_doc_path_refs.py` alone. That is why every path this brief names has to be a real one.


## Acceptance

- `bash scripts/validate-all.sh` green in the worktree, exit code read from `$?` (never from a filtered view of the output).
- `git grep 'scripts/[a-z-]*\.\(sh\|py\|ps1\)'` returns **no** reference to a path that does not exist.
- the seat driver's `--self-test` (wherever the tree leaves it) has all canaries caught, and its `--list` prints the same plane set the
  registry declares.
- **The domain checker:** `python3 scripts/gate/check_doc_domain.py` prints its `OK: <n> docs, <m> domains, each with one
  claimed home` line (re-run it; never quote the numbers) and is **wired into `validate-all.sh`** with `--self-test` catching
  both halves of every rule. The domain set is derived from frontmatter — if the checker needs a list to pass, it is
  hardcoded and wrong.
- **The `scripts/README.md` prose sweep:** `python3 scripts/gate/check_registry_prose.py --show` prints **0 findings** and the
  checker runs as a gate item; the registry's `What it does` column states facts, not the story of how they were found.
- What a lane reports: which leg ran and its read-back, the `pi-seat-sync.sh --check` verdict per seat, and every parked leg
  with its exact blocked action — files moved and planes re-converged only if a leg actually moved or re-converged them.
