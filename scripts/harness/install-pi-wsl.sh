#!/usr/bin/env bash
# =====================================================================
# install-pi-wsl.sh — pi.dev coding-agent bootstrap for the WSL Debian runner
#
# Purpose: install pi natively in the Debian WSL distro, then deploy the
# SAME extensions + skills + prompt templates + packages that this instance
# runs on the Windows side, keeping the repo as the single source of truth.
#
# Why (not the /mnt/c Volta copy): pi.dev must run against a *native* ext4
# node + ~/.pi so sessions/worktrees stay on WSL ext4 (git-bootstrap.sh's
# primary-repo move per deployment-manual.md §0.1 (HD-259) instead of
# leaking back onto slow drvfs. The Windows Volta install on the PATH is the
# wrong target for a WSL-native pi.
#
# Usage:
#   bash scripts/harness/install-pi-wsl.sh                 # full install (node + pi + config)
#   bash scripts/harness/install-pi-wsl.sh --pi-only       # pi binary + node, skip config sync
#   bash scripts/harness/install-pi-wsl.sh --config-only   # deploy repo skills/AGENTS/prompts/packages
#   bash scripts/harness/install-pi-wsl.sh --reload        # informational: report pi + config state
#   PATH persistence is OWNED here (HD-1110): the node bin dir and pi's entrypoint dir are written
#   into ~/.bashrc and ~/.profile under this script's marks, and the install legs VERIFY the result
#   by asking a login shell (`bash -lc 'which -a pi'`), not this process. HD-1118 Stage 2 is the
#   follow-through for the rest of the seat family (repo root + pins through scripts/lib/). The
#   hand-written PATH line a seat used to need is superseded by this — do not hand-edit either file.
#   Anything else exits 2 WITHOUT installing: an unrecognised argument used to fall through to the
#   full installer (see the guard below `MODE=`), and this installer cannot be pinned — it fetches
#   `latest`, not `pi_host_npm_version`.
#
# SSOT (deploy direction = repo -> ~/.pi/agent). The root update_pi.cmd that did the
#   Windows half with robocopy is retired (HD-1112): scripts/harness/pi-seat-sync.sh is the path.
#   skills/        -> ~/.pi/agent/skills/       (artifact-ignore: net.json, __pycache__, zero-byte markers)
#   pi-agent/      -> ~/.pi/agent/               (AGENTS.md + prompts/*)
#   packages: fleet rows of the pi_pkg_* inventory -> `pi install npm:...` (discovered, not a list)
#
# Version pins (§7): no version string lives in this file. The package SET is discovered from the
#   `scope: fleet` rows of the pi_pkg_* inventory in IaC/ansible/group_vars/all/versions.yml, and
#   the seat TUI pair (pi_host_tui_npm_*) from the same file, exactly like install-pi-debian.sh
#   reads its pins, so a hand-typed `pi install npm:pi-open-tui` on one seat cannot quietly become
#   the fleet's state (docs/harness-pi-seat-identity.md §5a).
#
# Env overrides: REPO (default: repo root found from this script's path). The package set is NOT
#   overridable here — it is the inventory's, and a private list is what drifted.
#   Run INSIDE WSL Debian
#   (`wsl -d Debian -- bash $REPO/scripts/harness/install-pi-wsl.sh` works too, where $REPO =
#    the repo root self-derived from this script's path — /home/domen/source/homelab).
#
# Requires: curl, bash. Read-only clone/sync needs no GitHub auth.
# Owner: user (pi.dev-in-WSL tooling, HD-259 companion) — record in the owning doc if adopted.
# =====================================================================
set -euo pipefail

# ---- locate repo root (allow override) -----------------------------------
# `:-$0` for the pipe-over-ssh form (`ssh seat 'bash -s' < this-file`), where BASH_SOURCE is unset
# and `set -u` turns the plain form into an "unbound variable" error on every run.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# HD-1118 Stage 1: the repo root is FOUND by scripts/lib/repo-root.sh, never assumed from
# a depth — "one level above me" is what turns a folder move into a green gate that reads
# nothing (an inherited $REPO still wins, so the fixtures keep working).
_hl_d="$SCRIPT_DIR"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"

# ---- pi packages to install (tracked here, mirror of Windows settings.json) --
VERSIONS="$REPO/IaC/ansible/group_vars/all/versions.yml"

# HD-1118 Stage 1: ONE pin() for the whole seat family — lib/pi-seat.sh. The out-parameter form
# is what fixes HD-1115: `X="$(pin k)"` runs in a subshell, where an `exit 1` cannot stop this
# script, so a missing pin used to continue with an empty value.
hl_source_lib "${BASH_SOURCE[0]:-$0}" pi-seat.sh
pin TUI_PKG pi_host_tui_npm_package
pin TUI_V pi_host_tui_npm_version

# HD-1118 Stage 2: the package set is NOT listed in this file. It is DISCOVERED from the pi_pkg_*
# inventory in the version SSOT, so a from-zero WSL bootstrap cannot carry a private list again.
# What these lines were: fleet packages installed with NO version (`pi install npm:pi-subagents`
# takes whatever `latest` means that day), on one of three seat paths, while the settings plane
# owned only two of them. `pi install` is idempotent and the specs now arrive pinned.
pi_fleet_packages() { seat_pkg_rows "$VERSIONS" | awk -F'\t' '$3=="fleet"{print $2}'; }

MODE="${1:-}"

# ⛔ AN UNKNOWN ARGUMENT MEANS FULL INSTALL HERE, so it is refused before anything runs.
# This script has no `--check`: `MODE` is only ever compared with `--pi-only`, `--config-only` and
# `--reload`, so any OTHER first argument falls through to the installer branch, which pipes
# `https://pi.dev/install.sh` into `sh`. Measured the hard way on the WSL seat 2026-10-19: typing the
# shape every sibling script answers to (`install-pi-wsl.sh --check`, the spelling HD-1118's own
# from-zero leg uses for `install-pi-debian.sh --check`) downloaded the managed installer,
# `npm install`ed 119 packages into a staging tree and created `~/.pi/agent/install/{releases,staging}`
# on a box that was only meant to be READ. The pin survived only because the smoke test disagreed
# (`Managed Pi smoke test returned version 1.1.0; expected 1.3.0` — the pi.dev installer takes no
# version, so what it fetches is `latest`, not `pi_host_npm_version`). §7, fail loud: a mode this
# file does not know is a STOP, never a default.
case "$MODE" in
  ''|--pi-only|--config-only|--reload) ;;
  *)
    printf 'error: unknown mode %s — refusing.\n' "$MODE" >&2
    printf '  anything this script does not name INSTALLS (curl -fsSL https://pi.dev/install.sh | sh),\n'
    printf '  so it will not guess. Known: (full) · --pi-only · --config-only · --reload (read-only report).\n' >&2
    printf '  There is NO --check here: the read-only leg is install-pi-debian.sh --check, and on a seat\n'
    printf '  already built the report form is `bash scripts/harness/pi-seat-sync.sh --check`.\n' >&2
    exit 2 ;;
esac

say()  { printf '\n== %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }

require_cmds() {
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || { echo "error: missing '$c' (apt install $c)" >&2; exit 1; }; done
}

# ---- resolve pi across BOTH layouts (see install-pi-debian.sh's header) --------------------
# The official pi.dev installer used below writes pi's OWN managed layout (~/.pi/agent/bin over
# install/releases), which is NOT the npm -g shape the Debian sibling installs; and a seat that
# ran `pi update` can be migrated there with the node-dir symlink deleted. A bare `command -v pi`
# is empty in exactly those cases while pi runs fine (oldsrv, 2026-10-09).
PI_ENTRY_DIR="${PI_ENTRY_DIR:-$HOME/.pi/agent/bin}"
# The node bin dir a pi install needs on PATH. Found, never assumed: pi.dev's installer puts a
# standalone node under ~/.local/share/pi-node, and a hand-written line pointing at ONE version
# directory is what HD-1110 is about — so the `current` symlink is what gets persisted.
PI_NODE_BIN_DIR="${PI_NODE_BIN_DIR:-$HOME/.local/share/pi-node/current/bin}"
pi_bin() {
  local p
  p="$(command -v pi 2>/dev/null || true)"
  [ -n "$p" ] && [ -x "$p" ] && { printf '%s' "$p"; return 0; }
  [ -x "$PI_ENTRY_DIR/pi" ] && { printf '%s' "$PI_ENTRY_DIR/pi"; return 0; }
  return 1
}

# ---- PATH persistence — this installer owns it, it does not describe it --------------------
# HD-1110, with HD-1118 Stage 2 as the follow-through (the seat family resolving repo root and pins
# through lib/repo-root.sh + lib/pi-seat.sh). What this file used to do was PRINT a note asking the
# operator to edit ~/.bashrc. A step an installer only describes is owned by nobody: the box worked
# because one hand-written line happened to put a bin dir first, so whether `pi` resolved was a fact
# about one file on one seat rather than about this script. The lines are written here now, under
# this script's own marks, idempotently, into the files a shell actually reads — and the verify asks
# a LOGIN shell, which is exactly the shell a hand-written ~/.bashrc line does not always reach.
# Measured, which file answers what: `wsl -- bash <cmd>` is non-interactive AND non-login and reads
# neither file; `bash -l` reads ~/.profile; an interactive shell reads ~/.bashrc (which on Debian
# returns early when non-interactive). A systemd USER unit reads neither — that is roles/seat's
# Environment=PATH drop-in, not this file.
# The marks are this installer's OWN, distinct from install-pi-debian.sh's, because both installers
# legitimately run on one box and each must be able to tell whether IT already persisted.
PROFILE_MARK_NODE="# pi-seat wsl node (install-pi-wsl.sh)"
PROFILE_MARK_PI="# pi-seat wsl pi entrypoint (install-pi-wsl.sh)"

persist_path() {
  local f dir mark pair wrote=0
  for pair in "$PROFILE_MARK_NODE|$PI_NODE_BIN_DIR" "$PROFILE_MARK_PI|$PI_ENTRY_DIR"; do
    mark="${pair%%|*}"; dir="${pair##*|}"
    # Only a directory that exists on THIS box is persisted: a PATH line for a layout this seat
    # never had is how a later reader starts trusting a path that leads nowhere.
    [ -d "$dir" ] || { info "skip $dir — no such directory on this box"; continue; }
    for f in "$HOME/.bashrc" "$HOME/.profile"; do
      [ -e "$f" ] || continue
      if grep -qF "$mark" "$f"; then info "PATH block already in $(basename "$f")"; continue; fi
      { printf '\n%s\nexport PATH="%s:$PATH"\n' "$mark" "$dir"; } >> "$f"
      info "persisted $dir into $(basename "$f")"
      wrote=1
    done
  done
  if [ "$wrote" = 1 ]; then hash -r 2>/dev/null || true; fi
  return 0
}

# Ask a LOGIN shell, never this process's own PATH: `hash -r; command -v pi` proves only that the
# installer's shell can see pi — true the moment the installer exports a dir, and silent about the
# shell the operator will actually open. Under WSL the Windows PATH is appended, so a /mnt/c copy is
# always a candidate; what matters is WHO WINS, so that is what is asserted.
verify_login_path() {
  local winner all drvfs
  winner="$(bash -lc 'command -v pi' 2>/dev/null || true)"
  [ -n "$winner" ] || { echo "error: no login shell resolves 'pi' — the persisted PATH block did not take effect" >&2; return 1; }
  all="$(bash -lc 'which -a pi' 2>/dev/null || true)"
  drvfs="$(printf '%s\n' "$all" | grep -c '^/mnt/c' || true)"
  info "login shell resolves pi: $winner"
  info "  candidates: $(printf '%s\n' "$all" | tr '\n' ' ')"
  [ "$drvfs" -gt 0 ] && info "  $drvfs Windows(drvfs) copy(ies) on PATH, not first"
  case "$winner" in
    /mnt/c/*|/mnt/C/*)
      echo "error: a login shell resolves pi to the Windows copy ($winner) — the persisted block must come earlier in PATH" >&2
      return 1 ;;
  esac
  return 0
}

# ---- --reload: informational only -------------------------------------------
if [ "$MODE" = "--reload" ]; then
  say "install-pi (REPO=$REPO)"
  pb="$(pi_bin || true)"
  # What a login shell actually resolves — the only PATH question an operator can ask.
  info "login shell: $(bash -lc 'which -a pi' 2>/dev/null | tr '\n' ' ' || echo 'pi resolves nowhere')"
  if [ -n "$pb" ]; then
    info "pi:        $pb -> $("$pb" --version 2>/dev/null || echo '?')"
    info "pi config: $(ls -d "$HOME/.pi/agent" 2>/dev/null || echo 'ABSENT')"
  else
    info "pi:        NOT installed (run: bash scripts/harness/install-pi-wsl.sh)"
    exit 0
  fi
  info "skills:    $(ls "$HOME/.pi/agent/skills" 2>/dev/null | tr '\n' ' ')"
  info "packages:  $("$pb" list 2>/dev/null | tail -n +1)"
  echo; echo "    then: cd $REPO && bash scripts/gate/guard-session.sh"
  exit 0
fi

require_cmds curl git bash

# ============================ node + pi binary ==============================
if [ "$MODE" != "--config-only" ]; then
  say "installing / updating pi.dev (curl -fsSL https://pi.dev/install.sh | sh)"
  if command -v node >/dev/null 2>&1; then
    info "node: $(command -v node) -> $(node --version)"
  else
    info "no node found — the pi installer will install a standalone Node.js 22.19+ into \$HOME"
  fi
  # Official installer: installs/repairs pi + ensures a new-enough node.
  curl -fsSL https://pi.dev/install.sh | sh
  # PATH is PERSISTED here (HD-1110), not recommended in a note.
  persist_path
  # Refresh PATH for this session (the installer may have installed a standalone node).
  pb="$(pi_bin || true)"
  if [ -z "$pb" ]; then hash -r 2>/dev/null || true; pb="$(pi_bin || true)"; fi
  [ -n "$pb" ] || { echo "error: no pi after install (looked on PATH and in $PI_ENTRY_DIR) — no PATH entry can resolve a binary the installer never wrote" >&2; exit 1; }
  info "pi:  $pb -> $("$pb" --version)"
  verify_login_path || exit 1
else
  pb="$(pi_bin || true)"
  [ -n "$pb" ] || { echo "error: no pi found (neither PATH nor $PI_ENTRY_DIR) — run without --config-only" >&2; exit 1; }
  # --config-only still proves the seat resolves: a synced config for a pi that a login shell
  # cannot find is not a working seat.
  verify_login_path || exit 1
fi
PI_BIN="$pb"

# ============================ repo config sync ===============================
if [ "$MODE" != "--pi-only" ]; then
  [ -d "$REPO/skills" ]          || { echo "error: $REPO/skills not found — run from a homelab clone (git-bootstrap.sh)" >&2; exit 1; }
  [ -f "$REPO/pi-agent/AGENTS.md" ] || { echo "error: $REPO/pi-agent/AGENTS.md not found" >&2; exit 1; }

  say "deploying repo SSOT -> ~/.pi/agent"
  mkdir -p "$HOME/.pi/agent/prompts" "$HOME/.pi/agent/skills"

  # AGENTS.md (global session-start instructions) + /start prompt template.
  cp "$REPO/pi-agent/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"
  if [ -f "$REPO/pi-agent/prompts/start.md" ]; then
    cp "$REPO/pi-agent/prompts/start.md" "$HOME/.pi/agent/prompts/start.md"
  fi
  info "AGENTS.md + prompts synced"

  # Skills: repo is SSOT. Skip runtime artifacts (HD-254 discipline):
  #   net.json (mikrotik), __pycache__/**, zero-byte skill-name markers.
  deployed=0
  for dir in "$REPO"/skills/*/; do
    name="$(basename "$dir")"
    [ -d "$dir" ] || continue
    [ -f "$dir/SKILL.md" ] || { info "skip $name (no SKILL.md)"; continue; }
    rm -rf "${HOME}/.pi/agent/skills/${name}"
    mkdir -p "${HOME}/.pi/agent/skills/${name}"
    # cp -a then drop runtime artifacts so we never ship them to ~/.pi.
    cp -a "$dir"/. "${HOME}/.pi/agent/skills/${name}/"
    find "${HOME}/.pi/agent/skills/${name}" -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true
    find "${HOME}/.pi/agent/skills/${name}" -name "net.json" -type f -delete 2>/dev/null || true
    rm -f "${HOME}/.pi/agent/skills/${name}"/${name} 2>/dev/null || true   # zero-byte skill-name marker
    deployed=$((deployed+1))
  done
  info "$deployed skill(s) synced: $(ls "$HOME/.pi/agent/skills" | tr '\n' ' ')"

  # Packages/extension bundles: the fleet rows of the inventory, pinned (idempotent).
  say "ensuring pi packages/extensions"
  for pkg in $(pi_fleet_packages); do
    case "$pkg" in
      ''|' '*) continue ;;
    esac
    info "pi install $pkg"
    "$PI_BIN" install "$pkg"
  done
  info "installed: $("$PI_BIN" list 2>/dev/null | tr '\n' ' ')"

  # The seat TUI package carries ONE harness-relevant key: the footer's hostname segment,
  # which is what answers "which box am I typing to" (docs/harness-pi-seat-identity.md §5a — the job the
  # retired pi-agent/extensions/host-status.ts used to do). pi-open-tui's own DEFAULT is
  # OFF, so `pi install` alone leaves the seat anonymous: this sets that key and touches
  # nothing else the operator tuned through /open-tui.
  say "seat TUI footer config (pi-tui-config.sh --push)"
  if [ -f "$REPO/scripts/harness/pi-tui-config.sh" ]; then
    bash "$REPO/scripts/harness/pi-tui-config.sh" --push \
      || { echo "error: pi-tui-config.sh --push reported problems" >&2; exit 1; }
  else
    info "no scripts/harness/pi-tui-config.sh in this clone — the footer-hostname leg was NOT run"
  fi

  # The settings plane (HD-1110): the harness keys come from pi-agent/settings-ssot.json and are
  # MERGED, so this runner's workstation keys (externalEditor, lastChangelogVersion, tuiMode) and
  # any seat-local package survive — §5's "the block is the part that must match", enforced.
  say "settings plane (pi-agent/settings-ssot.json -> ~/.pi/agent/settings.json)"
  if [ -f "$REPO/scripts/harness/pi-settings-config.sh" ]; then
    bash "$REPO/scripts/harness/pi-settings-config.sh" --push \
      || { echo "error: pi-settings-config.sh --push reported problems" >&2; exit 1; }
  else
    info "no scripts/harness/pi-settings-config.sh in this clone — the settings plane was NOT run"
  fi

  # The TUI font. Honest scope note: WSL has no display, so THIS leg only places + proves; the
  # glyphs this seat draws come from the font installed on the Windows side
  # (scripts/harness/win/install-nerd-font.ps1, run by pi-seat-sync.sh's win11 seat).
  say "seat TUI font (pinned nerd-fonts release)"
  [ -f "$REPO/scripts/harness/install-nerd-font.sh" ] && bash "$REPO/scripts/harness/install-nerd-font.sh" --push \
    || info "install-nerd-font.sh absent or reported a problem — pi-open-tui falls back to portable Unicode icons"

  # Local hand-written extension files: repo pi-agent/extensions/ is the SSOT, deployed
  # by the sync script — the same discipline the skills loop above uses (HD-254). The
  # inline `cp -a` this replaces copied silently over drift and could not report it;
  # the sync script compares byte-exact, blocks on an encoding violation, does the
  # one thing a cp cannot (PRESERVE a machine-local deployed-only file), and REMOVES
  # the names the repo retired — otherwise a retired extension stays loaded on every
  # seat forever, because --push never deletes a deployed-only file.
  say "repo extensions -> ~/.pi/agent/extensions (sync-extensions.sh --push)"
  if [ -d "$REPO/pi-agent/extensions" ]; then
    bash "$REPO/scripts/harness/sync-extensions.sh" --push \
      || { echo "error: sync-extensions.sh --push reported problems (drift or encoding)" >&2; exit 1; }
  else
    info "no pi-agent/extensions/ in repo — only pi-package extensions installed"
  fi
fi

echo
echo "== Done. pi.dev is bootstrapped in WSL Debian. =="
echo "   Run:      pi"
echo "   Extensions: available in ~/.pi/agent/extensions (repo files are the SSOT set; a"
echo "               machine-local file stays local, and retired names are removed by --push)."
echo "   TUI:      pi-open-tui (pin pi_host_tui_npm_*, installed above) — /open-tui tunes it;"
echo "               its footer hostname IS the seat identity: docs/harness-pi-seat-identity.md §5a"
echo "   Session:  cd $REPO && bash scripts/gate/guard-session.sh  (create a worktree first)"
echo "   Update:   pi update --extensions   +   re-run this script to re-sync repo SSOT"
echo
info "Provider/auth config (models.json, auth.json, settings.json) is NOT auto-synced:"
info "it holds secrets (API keys) + a machine-local lmstudio endpoint. Set it up per-side:"
info "  pi /login    # pick provider + authenticate (OpenRouter, Anthropic, …)"
info "  /model       # select the default model"
info "Settings like theme/thinking live in ~/.pi/agent/settings.json — copy only what's portable."
