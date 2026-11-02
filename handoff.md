# HANDOFF — LSP/MCP seat work, session 2026-11-02 (unfinished)

**Status: WIP committed on branch `lane/lsp-binaries-plane`, worktree `../homelab-wt-2026-11-02-2102`.**
Not merged, not pushed, gate NOT run. `main` is clean at `af267465` and everything on `main` is green
and pushed. Resume in that worktree.

---

## 1. What already landed on `main` (green, pushed, converged)

| Commit | What |
|---|---|
| `6a273933` | doc: the shell kind that hides the seat's LSP binaries; `mcp.json` gets a row in `docs/harness-pi-seats.md` §1 |
| `c94af10a` | **plane `mcp-server`** — `scripts/harness/seat-mcp-server.sh`, registry row (`seats: wsl oldsrv`, `installer: none`), README row |
| `af267465` | `seats:` is read as a LIST (owner-side scope reader bug) + a push waits for the server it started |

Gates on those: tree face `OK: all validators passed` (126 items). Seat face ran green earlier in the
session (`674s`). Both Debian clones and this checkout were fast-forwarded to `af267465`.

## 2. Live seat state (changed by hand this session — verify before assuming)

* `AmazingMCP` systemd **user** unit on `wsl` + `oldsrv`: enabled, active, `127.0.0.1:7777` → 400.
  Hand-written copies were moved aside and then deleted; the plane owns the file name.
* `~/.bashrc` on both Debian seats carries `export PATH="$HOME/.local/bin:$PATH"` (added by hand,
  no marks — the WIP plane writes a **marked** block, see §4.3).
* Both Debian seats now have `typescript-language-server 6.0.3` + `typescript 6.0.3` in
  `~/.local/lib/node_modules`, proven with a real LSP round trip:
  `initialize` → 23 capability groups, `documentSymbol` → 58 symbols on `pi-agent/extensions/vault-mask.ts`.
  **Why it matters:** `npm i -g typescript-language-server typescript` resolved `latest` →
  `typescript@7.0.2`, the native port, which has **no `lib/tsserver.js`**; the server starts and then
  fails `initialize` with *"Could not find a valid TypeScript installation"*. Pin `typescript@6`.
* C# story corrected: `roslyn-language-server` **is** on PATH and `ready` on both seats by pi-lsp's own
  `commandExists` semantics (`adapters.ts:110-111` names `roslyn-language-server --stdio --autoLoadProjects`).
  The seat reports claiming "no C# LSP" were wrong; the repo has **0 `.cs` files**, so the route is
  simply never selected there.
* Loopback trap on the WSL seat: the server listens on `127.0.0.1` **and** `[::1]`, but the `::1` leg
  answers NOTHING. `curl http://localhost:7777/` fails where `127.0.0.1` returns 400. Any `mcp.json`
  entry there must name `127.0.0.1`.

## 3. WIP in this worktree (uncommitted → now committed as WIP on the lane branch)

### 3.1 `IaC/ansible/group_vars/all/versions.yml` — DONE
New `lsp_bin_*` block: 4 fields per entry (`_name` package, `_cmd` what pi-lsp spawns, `_version`,
`_via` = `npm | npm-lib | astral | dotnet`). 8 entries; observed identical on both seats:
bash-language-server 5.8.1, yaml-language-server 2.0.0, @biomejs/biome 2.6.4 (cmd `biome`),
typescript-language-server 6.0.3, typescript 6.0.3 (`via: npm-lib`, cmd `tsserver`), ruff 0.17.3,
ty 0.0.95, roslyn-language-server 5.13.0-1.26514.10.

### 3.2 `scripts/lib/pi-seat.sh` — DONE, self-test green
Added `hl_seat_plane_scope`, `hl_seat_skip_line`, `hl_path_persist`, `hl_path_resolved` +
`hl_seatplane_selftest` (6 arms, mutation-proven for the scope half). `_HL_SEAT_DIR` is resolved once
at source time instead of a subshell per scope read.
**Measured fact worth keeping:** `hl_planes_selftest` costs **~2 min on the win11 tree box** — that is
pre-existing (old lib measured 2m52s vs mine 2m6s), not a regression. My earlier "17.6 s baseline" was
bogus: the copy I timed was reading a missing registry and short-circuiting.

### 3.3 `scripts/harness/seat-lsp-binaries.sh` — new owner, `--self-test` = 17/17 green
Verdicts: `OK · MISSING · DRIFT(version) · DRIFT(invisible) · DRIFT(shadowed) · DRIFT(broken-lib) ·
NO-INSTALLER`. Set is **discovered** from the pins (adding a row adds a server). Versions are read from
installer records (`package.json`, `dotnet tool list -g`) — **not** by running apphosts
(`roslyn-language-server --version` doesn't even exist). Visibility is read through an **interactive**
shell (`script -qec "bash -ic …"`), because `~/.profile` is login-only.

### 3.4 `scripts/lib/seat-planes.yml` — row appended (`seats: wsl oldsrv`, `installer: debian cockpit wsl`)

## 4. REMAINING — do these in order

1. **Mutation-prove the plane's arms** (CONVENTIONS §6 — I proved the lib's, not the script's). Break
   one branch at a time: the `DRIFT(invisible)` branch, the `/mnt/c` shadow case, the `tsserver.js`
   existence test, the greedy-version read. Each must redden exactly one arm.
2. **`scripts/README.md` registry row** for `seat-lsp-binaries.sh` (required by `check_script_layout.py`).
   Put it next to the `seat-mcp-server.sh` row (~line 227) and **re-add the row's own line, do not
   replace the neighbour** — I clobbered the `gate-snapshot.sh` row once that way and had to splice it back.
   No `HD-…` ids and no dates in registry prose (`check_registry_prose.py`).
3. **Docs**: `docs/harness-pi-seats.md` §1 — the language-server row must say the set + the PATH block
   are now owned by the `lsp-binaries` plane (they were "seat state, no owner"), and keep the five traps.
4. **`todo.md` HD-1238** — shrink the language-server ⏳ tail to "owned by the `lsp-binaries` plane on
   the Debian seats; win11 carriers (Volta npm tree, `%USERPROFILE%` dotnet tools) are still unowned,
   and the row's `seats:` list names win11 out". Update `todo-table.md` §B9 ⏳ cell to match.
5. **Decide win11** (open design question, not a bug): either a `lsp-binaries` row with
   `seats: win11` and a probe that reads Volta's tree + `%USERPROFILE%\.dotnet\tools`, or an explicit
   ruling that win11 stays an act. Today's answer is SKIP; the doc must say which it is.
6. Gate: `bash scripts/harness/gate-snapshot.sh --run` (must be committed first — the snapshot REFUSEs
   a dirty tree), then `bash scripts/validate-all.sh --face seat` before finishing.
7. Merge `lane/lsp-binaries-plane` → `main`, push, ff both seat clones, then **converge for real**:
   `bash scripts/harness/pi-seat-sync.sh --check` (expect the new leg on wsl/oldsrv) and `--push`.
   Expect on first run: `DRIFT(invisible)` → push writes the marked PATH block next to my unmarked
   hand-written line. **Check whether the plane should adopt or duplicate that line** (current logic:
   `hl_path_persist` keys on its own mark, so it will ADD a second block — decide adopt-vs-note).
8. `git worktree remove ../homelab-wt-2026-11-02-2102` + `git branch -d lane/lsp-binaries-plane` after merge.

## 5. Traps learned the hard way (do not re-derive)

* **git-bash → `wsl.exe -d Debian -- bash -c '…$HOME…'`**: `$HOME` expands on the Windows side. Pipe a
  script on **stdin** (`wsl.exe -d Debian -- bash -ls < file`, `ssh host 'bash -ls' < file`) instead.
* **`bash -lc` proves nothing about a session's PATH** (login reads `~/.profile`); `bash -ic` without a
  tty prints job-control noise. Use `script -qec "bash -ic '…'" /dev/null | tr -d '\r'`.
* **Backquotes inside a double-quoted string are command substitution** —
  `REASON="… (`$ENABLED`)"` executed systemctl's output.
* **`pin()` EXITS (rc 1)** on a missing key; an `|| stop` after a pin is unreachable code.
* **`sed 's/.*([0-9]+\.[0-9]+).*//'` is greedy**: read versions with `grep -oE | head -1`.
* **`npm --prefix DIR install -g NAME@VER`** — the package is the arg containing `@`, not `$3`.
* **astral installs land in `~/.local/bin`** (standalone binaries); no uv/pipx on these seats.
* **Windows python can't see `/tmp`** — stage fixtures under `$USERPROFILE`. `PYTHONIOENCODING=utf-8`
  for non-cp1252 output.
* Self-test must never touch the network: `LSP_ASTRAL_FETCH` replaces the astral fetch wholesale.
* Never add a `pi-lsp.json` casually: a custom server map **replaces** the built-in catalog.

## 6. Facts about this fleet, for the doc row

Tracked files by extension: `.yml` 182 + `.yaml` 26, `.py` 139, `.sh` 89, `.js` 4, `.ts` 2
(`pi-agent/extensions/vault-mask.ts`, `pi-agent/proposed/vault-mask.selftest.ts`), `.cs` 0,
`.rs`/`.go`/`.c`/`.java`/`.lua`/`.zig`/`.fs` 0 — which is why rust-analyzer/gopls/clangd/jdtls are
correctly MISSING and are not pinned.
