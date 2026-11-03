# Handoff note - the `lsp-binaries` lane, state for the next session

> **Role:** the pointer note for the seat language-server lane, for whoever picks it up next. The
> authority for what is owed is [../todo.md](../todo.md) row **HD-1238**; the facts are
> [../docs/harness-pi-seats.md](../docs/harness-pi-seats.md) §1 (the language-server row) and the
> registry row `plane: lsp-binaries` in [../scripts/lib/seat-planes.yml](../scripts/lib/seat-planes.yml);
> the tool is [../scripts/harness/seat-lsp-binaries.sh](../scripts/harness/seat-lsp-binaries.sh).
> **Linked from:** nothing on purpose - the standing handoff is [../prompt.md](../prompt.md) §2 and the row
> is the authority; this note is the lane's pointer sheet, and a lane note with no inbound link is how a
> next session finds it without it becoming a second index.

## What is true now (re-derive, do not trust this list)

| question | command |
|---|---|
| which servers, at which pins | `bash scripts/harness/seat-lsp-binaries.sh --list` |
| what THIS seat owes | `bash scripts/harness/seat-lsp-binaries.sh --check --strict` |
| all seats at once | `bash scripts/harness/pi-seat-sync.sh --check` |
| are the plane's arms still load-bearing | `bash scripts/harness/seat-lsp-binaries.sh --self-test` |

As last read: `wsl` and `oldsrv` `OK: 8 language servers at the pin and visible to a session`;
`win11` answers `MISSING` for five entries with `bash-language-server` and `yaml-language-server` `OK`
and `roslyn-language-server` `DRIFT(invisible)`.

## The one AI-doable item

**The PATH adopt key reads a directory as written.** `hl_path_persist`
([../scripts/lib/pi-seat.sh](../scripts/lib/pi-seat.sh)) adopts an existing export only when the file
spells the directory exactly as the caller does, so a `~/.bashrc` carrying
`export PATH="$HOME/.local/bin:$PATH"` still receives a second marked block from `--push`. The fix:

1. normalise both sides to the RESOLVED directory before comparing (an expansion of `$HOME` and `~/`
   is the whole change; the second export is harmless at runtime and fatal to attribution);
2. plant the `$HOME` spelling in the arms " both the lib's `hl_seatplane_selftest` arm 5 and the plane's
   arm 4 currently prove only the absolute form, which is how a duplicate block passed as converged;
3. mutation-prove it, not just test it: break the adopt test and require one canary to redden.

The blocks that defect wrote on the two Debian seats are removed, with `~/.bashrc.bak-lspblock` beside
each; both seats re-proved `OK` on the operator's line alone, so no repair is owed there.

## What is NOT this lane's work

* win11 installs (Biome, the TS pair, `ruff`, `ty`) and that seat's `%USERPROFILE%\.dotnet\tools`
  PATH entry: the plane refuses to write a Windows image or profile, so these are owner legs " see the
  doc row and HD-1238's win11 tail.
* `~/.pi/agent/mcp.json` and the win11 tool-server autostart: still HD-1238's MCP-side gap, unchanged
  by this lane.

## How the proof was done, so it can be repeated

The mutation driver and its patch table are NOT in the repo " they ran out of tree, in each box's own
`$TEMP`, against a marker-complete fixture tree (lib copies + `harness/` + the two repo-root markers),
so no seat clone was touched. Twelve branch mutations (M1-M14, two anchors stale and one equivalent
until fixed) each reddened at least one canary on both Debian seats; two had reddened NOTHING and those
became arms 10 and 11. Re-run needs only: the plane script, `scripts/lib/{repo-root.sh,pi-seat.sh,
seat-planes.yml}`, and `python3` for the patcher. A mutation that reddens nothing is a blind spot, not
a pass " that is the sentence this note exists to carry forward.
