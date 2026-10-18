---
title: pi.dev Harness — The seat terminal (tmux mouse + OSC 52 clipboard)
role: detail
domain: harness
status: active
tags: [ai, pi, agent-harness, harness, spark, llm, terminal]
---

# pi.dev Harness — The seat terminal harness

> **Role:** Detail doc — the harness-**independent** terminal layer: tmux mouse + OSC 52 clipboard, the load-probe method, the measured fixture table, apply-and-verify, and the three ways this plane's own scripts can lie.
> **Linked from:** [`index.md`](index.md) (Document Map + dispatcher) ·
> [`harness.md`](harness.md) (the `harness` domain hub — placement map).

---
## 5b. The seat's terminal harness — tmux mouse + OSC 52 clipboard

pi runs inside tmux on the Debian seats — **one in active use**, oldsrv — and two things a
session touches every minute are **terminal-level, not pi-level**: the mouse and the clipboard. Repo
SSOT [`../pi-agent/tmux/tmux.conf`](../pi-agent/tmux/tmux.conf) → `~/.tmux.conf`, installed and *proved*
by [`../scripts/harness/install-tmux-conf.sh`](../scripts/harness/install-tmux-conf.sh), drift-gated by
[`../scripts/README.md`](../scripts/README.md) → validate-all item 29.

| Action | Result on the seat |
|---|---|
| click pane / click status / drag border | focus pane / switch window / resize pane |
| drag text, double- or triple-click | selection → tmux buffer **and** the outer clipboard |
| wheel in a shell pane | history scroll (`history-limit 100000`, 5 lines/notch) |
| wheel over a TUI that grabs the mouse (pi, vim, htop) | passed through raw — tmux never intercepts it |
| `prefix m` | toggle mouse off/on without editing the file — the escape hatch when capture gets in the way |
| SHIFT held while dragging | the outer terminal's own selection, bypassing tmux |

The `managed-by:` line names the **SSOT file**, never the installer's path: a marker that embeds a
script path is a second copy of that path, and HD-1118 moved the script, which is the failure the
marker exists to avoid. The installer therefore also recognizes the path-markers it wrote before
that move (`MARKER_LEGACY` in the script) as its own — what it never accepts is a file it did not
write, which stays a REFUSAL and not an overwrite.

### Why the installer loads the file instead of comparing it

`cmp` proves the right bytes are on disk. It cannot prove tmux obeyed them, and the failure mode is
silent: **a config that errors mid-load leaves the options at their DEFAULTS and the caller still gets
exit 0 with empty stderr** (tmux reports a config failure as a client *message*; a detached
`new-session` has no client to print it to). Measured on tmux 3.5a, six fixtures, each loaded with
`tmux -L <sock> -f <conf> new-session -d` and read back with `tmux show -g …`:

| fixture appended to a working config | reads back | verdict |
|---|---|---|
| *(nothing — the SSOT as-is)* | `mouse on`, `history-limit 100000`, `mode-keys vi` | EFFECTIVE |
| block opened at end of a line, closed on its own line | same | EFFECTIVE |
| backslash-continued command | same | EFFECTIVE |
| one bad command (`select-pane -t = extra extra extra`) | `mouse off`, `2000`, `emacs` | **INERT** |
| unknown command | same defaults | **INERT** |
| nested wrapped `if-shell { } { }` | same defaults | **INERT** |
| unterminated quote at the end | `mouse on`, `mode-keys emacs` | **PARTIAL** |

Two conclusions, both load-bearing: **which part** of a file survives an error is not predictable from
the parser (last row — a later option applied while an earlier one did not), and a static "looks like a
bad block" rule cannot be written honestly, because the first two wrapped shapes load fine while the
nested one does not. So the gate starts a throwaway server on a private socket and **reads the options
back** — and its own canaries mutate the fixture, not the checker (CONVENTIONS §6: a test that cannot
fail is not evidence). The probe must not key on a raw failure *count*: two failed assertions read as `2`,
which is also the SKIP code, so a count-shaped verdict can print green over inert canaries.

### The clipboard leg — OSC 52, measured

oldsrv is headless: no `xclip`, no `xsel`, no `wl-clipboard`, and the clipboard lives on the machine
you typed into. The only path is an **OSC 52 escape sequence written to the outer terminal through
SSH**, which tmux emits only when the client terminal is credited with the capability — either by
tmux's built-in terminal-NAME table (`xterm*`/`vte`: credited; `screen`, `tmux`, `vt220`, `linux`: not)
or by an `Ms` terminfo capability. **No terminfo entry on this box carries `Ms`** — `infocmp -1 <term>`
shows none for `xterm-256color`, `screen-256color`, `tmux-256color`, `vt100`, `vt220` or `linux` — so the
SSOT's `terminal-overrides ',*:Ms=\E]52;%p1%s;%p2%s\7'` is what earns the sequence on a
non-`xterm`-classified seat:

| probe client `TERM` | `Ms` override present | OSC 52 sequences on the wire |
|---|---|---|
| `xterm-256color` | yes | 1 |
| `screen-256color` | yes | **1** |
| `screen-256color` | no | **0** ← the canary |
| `vt100` | no | 0 |

Three facts that are easy to get wrong, each measured here rather than assumed:

- **A `set-buffer` emits nothing.** Only a **selection** (`copy-mode` → `begin-selection` →
  `copy-selection-and-cancel`, i.e. what a mouse drag or `y` does) produces the sequence. A probe built
  on `set-buffer` reports a working clipboard no user can reach.
- **`#{client_termfeatures}` is a belief about the terminal's NAME, not a capability read.** Its
  `clipboard` flag tracks the wire in the rows above but is not a read of the capability: a probe
  client with `TERM=tmux-256color` reports no `clipboard` while tmux emits OSC 52 for it. The gate reads
  the **bytes** (attach a `script(1)` pty client, capture, grep for `\033]52;`); the flag is printed as
  information only.
- **`set-clipboard on`, not the default `external`**: `external` lets tmux's own commands and key
  bindings set the outer clipboard but ignores one written by a program running *inside* tmux, and a
  coding agent is exactly such a program.

### Apply and verify

```bash
bash scripts/harness/install-tmux-conf.sh --check          # SSOT vs ~/.tmux.conf + load probe (report-only)
bash scripts/harness/install-tmux-conf.sh --push           # install; a foreign ~/.tmux.conf is a REFUSAL (+ --force, backup kept)
bash scripts/harness/install-tmux-conf.sh --reload         # install + source into the RUNNING server + read it back
bash scripts/harness/install-tmux-conf.sh --verify         # load probe + OSC 52 emission on the wire + live server
```

`--check` exits 0 on drift unless `--strict` (the `sync-skills.sh`/`sync-extensions.sh` contract: the
gate owns the decision to fail), but an **ineffective** config fails in every mode — that is a defect,
not a seat state. `--self-test` runs seven canaries (rest green, missing, drift, foreign-refusal +
backup, **two inert-config arms that are byte-identical by construction**, the `Ms` removal, and
`set-clipboard off`) and is wired into `validate-all.sh` item 29.

End-to-end by hand, the way a person notices it: select text with the mouse in a tmux pane, then paste
it on the machine you are sitting at. If nothing arrives, the seat's config is fine and the **outer
terminal is refusing OSC 52** — `xterm` needs the `allowWindowOps: true` resource; VTE ≥ 0.60, kitty,
wezterm, foot and alacritty accept by default. Nothing inside tmux can fix that leg, which is why it is
an ⏳ owner-gated tail and not a bug in the script.

**Seat state (WSL Debian laptop; live-verified marker):** tmux 3.5a is installed on this seat and the config is
*effective*, not just in place — `install-tmux-conf.sh --check --strict` prints `load probe OK — the SSOT parses AND
applies` and `OK: seat tmux config == repo SSOT and effective` (the load-probe line is a **verdict**, not a SKIP),
and `--verify` run FROM INSIDE the session reports the sandbox load probe OK, the running server's `mouse on` /
`extended-keys on` / `set-clipboard on`, and one OSC 52 emission left on the wire. The **binary** is a host change
with no in-repo path: `roles/seat`'s `seat_packages` covers only hosts in `IaC/ansible/inventory.ini` and this
laptop is not one of them, so a rebuilt WSL seat comes back without tmux and must replay `sudo apt-get install -y tmux
&& bash scripts/harness/install-tmux-conf.sh --reload` ([../deployment-manual.md](../deployment-manual.md) §0.3.6).

**Not wired yet (debian only):** `install-pi-debian.sh` runs the tmux plane through `scripts/lib/seat-planes.yml`;
[`../scripts/harness/install-pi-wsl.sh`](../scripts/harness/install-pi-wsl.sh) still does not call this installer, so a freshly
bootstrapped **WSL** seat gets no `~/.tmux.conf` until `install-tmux-conf.sh --push` runs once (and, as above, the tmux
binary must be installed by hand).

### The three ways this plane's own scripts can lie

All three are the CONVENTIONS §6 class — a verdict printed at an environment boundary. The rescue path that
surfaced two of them is [orchestration.md](orchestration.md) §4 step 5: a lane branch can already be an
ancestor of `main`, so `git branch -d` succeeds and uncommitted work dies with the directory — only
`git status --porcelain` inside the lane sees it.

1. **The installer collapsed a three-state rc into one note.** `install-tmux-conf.sh --push` ends in the load
   probe, so **0 = installed AND effective, 1 = a real defect** (refusal / CRLF / inert file), **2 = installed
   but UNPROVEN** (no tmux binary here). `… --push || info "…reported a problem"` printed rc 1 as a note, so a
   genuinely broken seat harness configured GREEN. `install-pi-debian.sh` `case`s all three.
2. **`check()` aborted at the first drift and printed nothing.** Under `set -euo pipefail` a bare
   `X --check 2>&1 | tail -2` is a failing pipeline, so `set -e` killed the script at that line: the settings,
   font, tmux and tui legs and the `check: GREEN|DRIFT` summary never ran — the first skill drift made the
   whole seat gate go silent. Proved both ways: `set -euo pipefail; false 2>&1 | tail -2; echo REACHED` prints
   **nothing**; with `|| bad=1` it prints `REACHED` and `bad=1`. Three sites carry the pattern — the
   `sync-skills`, `sync-extensions` and `install-nerd-font` checks in `install-pi-debian.sh` — and every one
   of them needs the `|| bad=1` guard.
3. **`--check` must not say "and effective" while printing SKIP.** With no tmux the load probe returns 2, the
   byte-compare passes, and the verdict line can print `OK: … == repo SSOT and effective` two lines after an
   honest SKIP. The two arms are: tmux present → `load probe OK … and effective`; a
   tmux-less seat → `SKIP: … IN PLACE; effectiveness UNPROVEN — a SKIP, not a pass`. Same rc, honest words:
   **in place ≠ effective**.
