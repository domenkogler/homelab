# Handoff note - the `lsp-binaries` lane, state for the next session

> **Role:** the pointer note for the seat language-server lane, for whoever picks it up next. The
> authority for what is owed is [../todo.md](../todo.md) row **HD-1238**; the facts are
> [../docs/harness-pi-seats.md](../docs/harness-pi-seats.md) §1 (the language-server row) and the
> registry row `plane: lsp-binaries` in [../scripts/lib/seat-planes.yml](../scripts/lib/seat-planes.yml);
> the tool is [../scripts/harness/seat-lsp-binaries.sh](../scripts/harness/seat-lsp-binaries.sh).
> **Linked from:** nothing on purpose - the standing handoff is [../prompt.md](../prompt.md) §2 and the row
> is the authority; this note is the lane's pointer sheet, and a lane note with no inbound link is how a
> next session finds it without it becoming a second index.

## Environment (this lane ran on the win11 seat)

Windows 11, **Git-Bash (MSYS/MINGW64)**, `py -3` (plain `python`/`python3` is the Store alias on this
seat), LF + UTF-8 no-BOM, out-of-tree work under `%TEMP%` (`$TEMP`, not `/tmp`). The Debian engine is
reached with `wsl.exe -d Debian` and **needs `MSYS_NO_PATHCONV=1`** from Git-Bash, or MSYS rewrites
`/usr/bin/bash` into `C:/Program Files/Git/usr/bin/bash` and the call dies before it starts.

## Where the lane stands, in one commit

Branch `homelab-wt-20261103-0811` in worktree `../homelab-wt-20261103-0811`, one commit `47b66cb9` on
top of `main` at `055e1f09`. **Not merged, not pushed** — the mutation proof and the doc surface below
are unfinished, so the merge station has nothing to take yet. Re-derive with:

```bash
git -C ../homelab-wt-20261103-0811 log --oneline -2
git -C ../homelab-wt-20261103-0811 status --short          # clean: the work is committed
bash scripts/lib/pi-seat.sh --self-test                    # green, includes the new arm 5
bash scripts/harness/seat-lsp-binaries.sh --self-test      # green, includes arms 14, 14b, 15
```

**What that commit changes.** `hl_path_persist` ([../scripts/lib/pi-seat.sh](../scripts/lib/pi-seat.sh))
now keys on the RESOLVED directory: `hl_path_dir_norm` collapses `$HOME`, `${HOME}`, `~/` and a
trailing slash, and `hl_path_exports` reads a PATH line as the list it is — quoted text only, split on
`:`, each entry normalised — so an operator's `export PATH="$HOME/.local/bin:$PATH"` is adopted
byte-for-byte instead of receiving a second marked block. And the plane's visibility read asks the
`.cmd` spelling **on win11 only**, because MSYS `command -v` honours `.exe` but not `.cmd` and the seat's
.NET global tool is `roslyn-language-server.cmd`.

One trap the fix found, since it reads as working code: **a tilde in a REMOVE pattern is
tilde-expanded**, so `${v#~/}` strips nothing and `$HOME/~` comes back. Substring (`${v:2}`), not
pattern. Arm 5's tilde case is the canary that says so.

## What is still owed HERE, in order

1. **Mutation-prove the two new branches, on the Debian engine** (how, and why not on win11, three
   sections down). The driver and its 14-mutation table were written and run only from win11, where one
   full pass did not finish in 26 min; the table's correctness is therefore **unproven** — an earlier
   pass that looked fully green was false, because the driver rewrote its own fixture as CRLF and every
   run after the first died on `$'\r': command not found`. That half is fixed (byte round-trip); the
   pass itself still has to happen, and `python` must be `python3` on the engine.
2. **The doc/row surface, none of which is written yet** — `docs/harness-pi-seats.md` §1's language-server
   row still says the adopt key reads the directory *as written* and still blames `%USERPROFILE%\.dotnet\tools`
   for the `DRIFT(invisible)`, which is false on this seat (that dir is on the interactive PATH three
   times; what failed was the `.cmd` spelling). Both sentences become state. Then `scripts/README.md`,
   the `todo.md` HD-1238 tail, `todo-table.md` §B0, and `prompt.md` §2 by diff (the "one AI-doable debt is
   the PATH adopt key" clause leaves the file, no ✅ note stays behind).
3. **Merge, then re-prove the seats** — `bash scripts/harness/pi-seat-sync.sh --check` on each seat once
   it has fast-forwarded, and `bash scripts/harness/seat-lsp-binaries.sh --check --strict` on win11, which
   reads `OK: 8 language servers at the pin and visible to a session` only from the fixed plane.

## The mutation proof, so it can be finished

Twelve branch mutations proved the old arms out of tree in `$TEMP`, against a marker-complete fixture
tree, never a seat clone; a mutation that reddens nothing is a blind spot, not a pass. The current
driver itself is kept at `.scratch/lsp-mutation-proof/mutate.py` in the primary checkout — that path is
gitignored scratch and the only durable copy is the table below, so a machine that loses it owes a
rewrite, not a rescue. The table has 14 entries: 11 in `hl_path_dir_norm` / `hl_path_exports` / `hl_path_persist` (revert to the
literal grep; kill each of the three expansions; the `${v#~/}` pattern trap; drop the trailing-slash
strip; always-adopt; never-adopt; read the PATH line as one entry; drop the no-final-newline read;
leave the quoted text in; leave a `"` inside an entry) and 3 in the plane (remove the `.cmd` fallback;
make it universal; swallow the adopt report). The fixture needs the **whole `scripts/` tree** plus
`IaC/ansible/group_vars/all/versions.yml` and both repo-root markers (`IaC/ansible` and `docs/index.md`) —
the lib's registry arms resolve plane *owners* by a globstar walk, so a thin fixture reads as a broken
registry and the baseline goes red before any mutation. The baseline MUST print green for both suites
before a single mutation counts.

⚠ **A win11-linked worktree is invisible to the engine's git.** Its `.git` file carries
`gitdir: D:/source/domenkogler/homelab/.git/worktrees/…`, which a Linux `git` reads as a relative path,
so anything the gate does through `git` dies with `not a git repository` on the mount — measured, and
it is why `guard-session.sh` walked away saying `not inside a git work tree` while exiting `0`. Grade a
lane on the engine through [../scripts/harness/gate-snapshot.sh](../scripts/harness/gate-snapshot.sh)
`--run`, which moves the commit into ext4 with git rather than reading the mount.

## Run the slow legs on the Debian engine, not on win11

`scripts/validate-all.sh` takes ~11 min on the win11 seat against ~8 s on the `wsl` seat, and the
difference is not the work: **one `fork`+`exec` is 16-44 ms quiet on Git-Bash (560-995 ms while a second
pool forks with you) and 0.66 ms on the Debian engine of the same laptop.** A mutation driver that
spawns ~20 bash processes per mutation therefore costs seconds on the engine and tens of minutes across
the door — which is where this session lost the afternoon. The gate prints its own `ms/exec` line every
run, and the routing is a repo decision with three rows in
[../scripts/README.md](../scripts/README.md), not a personal trick:

| fact | where it lives |
|---|---|
| WHICH engine runs a leg: seat class from `uname`; the door probed four ways (`--cd` reaches the tree, `uname` says Linux, `bash` resolves outside `/mnt/c`, a candidate python imports jinja2+PyYAML); `hl_wsl_mntpath` translates a `D:` path to `/mnt/d/…`. Automatic **only** on win11 — inside WSL the engine is never nested, and a real Debian host runs its legs native | `scripts/lib/wsl-route.sh` (its README row and its `--self-test`) |
| every engine spawn pins `MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'` **as a command prefix** — exporting them globally breaks the legs that need Git-Bash to convert their own arguments; without them `-- /usr/bin/bash` arrives as *Git-Bash inside the guest* | the same row (why the incantations below begin with the prefix) |
| WHAT MAY CROSS is a conjunction declared at the registration line by wrapping the leg in `hl_wsl_route`: tree-or-own-sandbox only, **never through `git`**, no network/ssh/vault trip, no seat `$HOME`, no tool the engine lacks, and it must not classify its own seat. A leg that cannot cross runs at home — a wrap never turns a check into a SKIP | same row; graded by `scripts/gate/check-leg-contract.sh` against `scripts/gate/leg_contract_boundaries.txt` |
| the `git` ban's reason, hit for real here: in a **Windows-linked worktree** a Linux `git` reads the `gitdir:` line as a RELATIVE path and dies. README names the two checkers that became `CANNOT RUN` and a false red; here it made `guard-session.sh` print `not inside a git work tree` and exit `0` | same row, with the 9p tax measured (118 s across / 72 s native on one leg) |
| a leg CLAIMS its tools with `hl_wsl_needs <tool>…` against the run's one-shot `engine tools:` inventory, so a missing tool stops it as `CANNOT RUN` (rc 2) instead of reading as a pass | same row |
| the FACE axis: `face tree` runs in a commit-stamped snapshot, `face seat` native, `face joined` native because a snapshot proves neither side. `scripts/lib/pi-seat.sh --self-test` is **`face seat`**, so it is never wrapped. `--face tree\|seat\|both\|auto` and `--wsl auto\|on\|off` are two switches on ONE item list | README's `validate-all.sh` row, HD-1202, [../docs/harness-pi-seats.md](../docs/harness-pi-seats.md) §1 |
| the tree half of the registry, moved into the engine's own ext4 **with git only**, one round trip, commit-stamped, `--carry` for a dirty tree — how a lane gets graded from win11 | `scripts/harness/gate-snapshot.sh --run` |
| did a wrapped leg judge the SAME thing on both sides of the door | `scripts/bench/win/gate-parity.sh` |

```bash
# a lane's tree face on the engine, commit-stamped — the route a win11 worktree MUST use, because its
# gitdir is a Windows path the guest cannot open
bash scripts/harness/gate-snapshot.sh --run          # from the lane worktree; --carry if dirty

# a self-built sandbox: the fixture goes in the ENGINE's /tmp (ext4), never on the 9P mount
MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Debian -u domen -- bash -c \
  'python3 /tmp/lsp_mut/mutate.py /mnt/d/source/domenkogler/homelab-wt-<date>-<HHMM>'
```

A snapshot run grades half the registry and says so, naming the items it left for the seat face; half a
registry is not a green. And `~/source/homelab` inside the guest is the `wsl` SEAT with its own tree — a
win11-seat verdict is never about it.

## What the win11 seat now carries (owner acts, all re-derivable)

The plane refuses to write a Windows image or profile, so these were done by hand on this box:
`@biomejs/biome@2.6.4`, `typescript-language-server@6.0.3`, `typescript@6.0.3` through `npm i -g`
(`npm prefix -g` is `…\Volta\tools\image\node\26.5.0`, the root the plane reads), and `ruff 0.17.3` +
`ty 0.0.95` unzipped from the `*-x86_64-pc-windows-msvc.zip` release assets into `~/.local/bin`, each
sha256-checked against the published `.sha256`. Every entry answers an `initialize` handshake —
biome 3 caps, typescript-language-server 23, ruff 10, ty 25, bash 11, yaml 16, roslyn 26 — and the
roslyn handshake only works through a **shell** spawn, which is the evidence behind the `.cmd` change.

## Two facts the row still gets wrong

* **The win11 MCP autostart is not owed** — `~/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup/AmazingMCP.vbs`
  is the per-user Startup carrier (`schtasks /Create /SC ONLOGON` answers `Access is denied` unelevated),
  it pins `--urls http://localhost:7777`, and `GET /` answers `400` on both loopbacks. The row's
  "win11 carrier still owed" clause is about a decision already executed on the seat.
* **`%USERPROFILE%\.dotnet\tools` is on that PATH** (three times, in an interactive shell too); the
  `DRIFT(invisible)` was the `.cmd` spelling, now handled in code. Do not write the PATH story back.

## What is NOT this lane's work

* `~/.pi/agent/mcp.json` — still no plane reads it; `scripts/lib/seat-planes.yml` names an owner for
  every other harness artifact and nothing touches an MCP server list.
* The Debian seats' `--push` legs. Both seats re-proved `OK` on the operator's own line with
  `~/.bashrc.bak-lspblock` beside each, so nothing is owed there beyond the post-merge `--check`.
