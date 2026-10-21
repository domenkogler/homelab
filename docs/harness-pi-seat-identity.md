---
title: pi.dev Harness — Seat identity (which box the footer names)
role: detail
domain: harness
status: active
tags: [ai, pi, agent-harness, harness, spark, llm, seat-identity]
---

# pi.dev Harness — Seat identity

> **Role:** Detail doc — which box the pi TUI footer names: the three seats, the `footerSegments.hostname` mechanism, the retired `host-status.ts`, and the Nerd Font the icons come from.
> **Linked from:** [`index.md`](index.md) (Document Map + dispatcher) ·
> [`harness.md`](harness.md) (the `harness` domain hub — placement map).

---
## 5a. Seat identity — which box the footer names

Three seats exist and all three run this harness: **Win11**, **the WSL Debian seat**, and **the oldsrv cockpit**. The WSL
Debian seat is the **designated runner station** for externally-served sessions — the one box that is off-box for every
converge target, is not the engine host, and owns no converge slot. It stays in `pi-seat-sync.sh`'s `SEATS` on purpose:
a fan-out must still name it, and it reports drift where drift is real rather than certifying another seat — from **inside**
WSL the driver names only the `wsl` and `oldsrv` seats, so the Win11 seat's planes can only be proven from that seat. That is also why the "two seats on ONE machine" case below is occasional rather than daily.
**Pi has no setting for footer
content** — `settings.md` §Terminal and display carries `theme`/`tuiMode`/`terminal.*` and nothing else,
and the default footer shows folder / model / context / cost. So "which machine am I typing to" is only
answerable from an extension, and this section is the only place that fact is written down.

- **The mechanism:** the pi package `pi-open-tui` (pin
  `pi_host_tui_npm_*`) draws the whole footer, and its `footerSegments.hostname` segment prints
  `os.hostname()` in short form. The hand-written `pi-agent/extensions/host-status.ts` is **retired**
  with it — a `ctx.ui.setStatus` line under a package-drawn footer is two sources of truth for one
  line, and the package owns the line. Retirement is a MECHANISM, not a deletion:
  `sync-extensions.sh --push` never deletes a deployed-only file, so without the script's
  `RETIRED` list a deleted extension stays loaded on every seat forever, invisible to a gate that
  compares only repo-side files. Also on that list: `remote-bash.ts`
  (Windows `sshpass.exe` + drive-letter paths, never in the repo by design).
- **The trap that makes this a script and not a note:** pi-open-tui's `DEFAULT_CONFIG` ships
  `footerSegments.hostname: false`. A seat that only ran `pi install npm:pi-open-tui` therefore has
  an **anonymous footer** — precisely the regression retiring the extension would have caused, and
  it lands where nobody looks (the SSH legs, where the prompt is gone). So
  [`../scripts/harness/pi-tui-config.sh`](../scripts/harness/pi-tui-config.sh) asserts that ONE key: it creates the
  minimal override file when absent, preserves every other key the operator tuned through
  `/open-tui`, and REFUSES to rewrite an unparseable file. Both installers call it; `validate-all.sh`
  gates it (self-test + `--check --strict`).
- **Deploy direction:** repo `pi-agent/` + `skills/` is SSOT → `bash scripts/harness/pi-seat-sync.sh --push`
  runs every plane on every seat,
  and per plane `sync-skills.sh` / [`sync-extensions.sh`](../scripts/harness/sync-extensions.sh) (item 27).
  A **deployed-only** extension is still deliberately NOT drift — it is reported `LOCAL`, never
  deleted, never imported; only a name on the `RETIRED` list is removed. The self-test asserts both
  halves, so the retirement rule cannot quietly swallow the `LOCAL` rule.
- **Keyboard, not just mouse:** inside tmux pi 1.1.0 runs `tmux show -gv extended-keys` at start-up and warns unless the answer is `on`/`always`, then warns AGAIN when `extended-keys-format` is `xterm`, because pi speaks CSI-u. On tmux 3.5a the defaults are `extended-keys=off` AND `extended-keys-format=xterm` — tmux still defaults the FORMAT to xterm, so setting only the first option swaps one warning for the other. Both lines live in `pi-agent/tmux/tmux.conf`; `install-tmux-conf.sh --reload` sources the RUNNING server, because a server that was already up keeps its old values whatever the file says — and on tmux < 3.3 neither option exists, where pi stays silent too, so an option-absent answer is reported and never failed.
- **The font is part of this, not a nicety:** pi-open-tui's icons are Nerd Font private-use glyphs,
  and its `icons.mode: auto` chooses them from the TERMINAL ENVIRONMENT, never from the installed
  font file. The release is pinned (`nerd_fonts_version`) and installed by
  [`../scripts/harness/install-nerd-font.sh`](../scripts/harness/install-nerd-font.sh) on the Debian seats and by
  [`../scripts/harness/win/install-nerd-font.ps1`](../scripts/harness/win/install-nerd-font.ps1) per-user on the
  Windows one — and **the Windows leg is the one that draws** (on this workstation that leg is already satisfied **machine-wide**: JetBrainsMono is installed globally and `install-nerd-font.ps1 -Check` reports `OK (machine-wide)` rather than nagging for a duplicate per-user install — an operator who already did the thing is DONE, not drift), because on WSL and on every SSH leg
  the terminal runs on the machine you type from. Having the font installed is not the same as the
  terminal selecting it: that stays a `fontFace` choice in the terminal profile, and `unicode` mode
  is the documented fallback when a box has no patched font.
- **Under `pipefail`, never `producer | grep -q`** — the early exit is a bug in the probe, never news about
  the producer. `grep -q` exits at the FIRST match while `fc-list` is still writing, so `fc-list` dies of
  SIGPIPE (rc **141**) and `set -o pipefail` promotes the dead producer to a failed pipeline even though grep
  found the family and returned 0 — a red font plane on a seat whose font is placed, hashed AND registered.
  It bites well under the 64 KiB pipe, because `fc-list` emits in chunks across its cache scan. The fix is to
  capture the listing and search the captured text: the producer is finished before grep starts, so there is
  no race. A self-test whose fake producer prints one line cannot see this — the same "a test that cannot
  fail is not evidence" trap as [`harness-pi-terminal.md`](harness-pi-terminal.md) §5b's `-eq 1` (CONVENTIONS.md §6) — so self-test arm 8 breeds it (family first,
  ~160 KB of filler after it, counting chunks so a GREEN can tell "drained" from "this host's buffer
  absorbed it").
  **Seat state:** the fixed driver run from the cockpit gives 8/8 green including `pi-self` (the answering
  `pi` equals the `pi_host_npm_version` pin), and `validate-all.sh` exits 0 there. The retired `host-status.ts` is gone from
  every seat — the Win11 copy is removed by that seat's own `--push` — so the retirement mechanism has
  reached every seat and `validate-all.sh`'s RETIRED arm has nothing left to fail on.
- **Running the driver ON the oldsrv box (seat == host):** `win11` is "this shell" only on the
  Windows workstation and `wsl` needs `wsl.exe`, so both read `NOT-HERE` here; `oldsrv` is the seat
  THIS box is, so its leg is local — the driver takes `cd "$REPO" && eval` whenever the host's own
  hostname is `oldsrv`, and `--list` prints that leg per seat on the host you are standing on. An ssh
  leg from a box to its own alias cannot work in principle: there is no self-alias in the box's ssh
  config (the `oldsrv-domen` alias is written for the laptop-class seats) and a host carries no host
  key for itself, which is why `PI_OLDSRV_TARGET=localhost` fails host-key verification rather than
  looping back. Everywhere else — the laptop, the runner, the VPS — the ssh leg stays first, away form
  (`oldsrv-domen-vps`) included. A `--seat` naming a seat this host does not have is a usage refusal,
  never a run of nothing that prints `IN SYNC`.
  From the seat, run that seat's own plane list locally — the same commands `planes_for_seat oldsrv`
  prints, in the same order, from the same clone (pre-flight still applies: the clone must be at
  `origin/main`). One seat-side failure is NOT the repo's fault:
  the `models` plane resolves credentials at render time, so a `TLS handshake timeout` from `op` is a
  transient 1Password/network fault — retry it, and never reach for `--keep-legacy-credentials`, which
  would paper over a provider the spec expects to be managed.
- **The laptop seat is the only leg nothing on the oldsrv box can reach:** one
  `bash scripts/harness/sync-extensions.sh --push` there, then `/reload`, and the footer reads **`@ DomenP14s`**.
  The same kind of run takes `bash scripts/validate-all.sh` **non-interactively** to `OK: all validators
  passed` with the `launcher: ~/ansible-venv activated` line.
- **Bonus invariant, not decoration:** the token the footer prints is the one `host_norm()`
  (`../scripts/harness/render-pi-config.py`) uses for a provider's `hosts:` scope — `DomenP14s` normalises to the
  spec row `domenp14s`. A case/SEPARATOR mismatch there silently
  drops a provider from the picker in both directions; the footer makes that invariant visible, so the
  wrong machine shows up before it becomes a missing provider.
- **What it does NOT distinguish is two seats on ONE machine** — Win11 and WSL Debian report the same
  Windows-derived hostname. It answers "which box" (the cockpit-vs-laptop question over SSH, where the
  prompt is gone), not "which seat". The WSL marker is available (`/proc/version` carries `microsoft`, which
  `laptop-llm.py` already reads) and deliberately NOT used here: a second host-identity signal invented in
  a footer would drift from the one `host_norm()` owns.
