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
#   bash scripts/install-pi-wsl.sh                 # full install (node + pi + config)
#   bash scripts/install-pi-wsl.sh --pi-only       # pi binary + node, skip config sync
#   bash scripts/install-pi-wsl.sh --config-only   # deploy repo skills/AGENTS/prompts/packages
#   bash scripts/install-pi-wsl.sh --reload        # informational: report pi + config state
#
# SSOT (deploy direction = repo -> ~/.pi/agent, same as update_pi.cmd):
#   skills/        -> ~/.pi/agent/skills/       (artifact-ignore: net.json, __pycache__, zero-byte markers)
#   pi-agent/      -> ~/.pi/agent/               (AGENTS.md + prompts/*)
#   packages below -> `pi install npm:...`        (tracked in-repo, not a drift copy)
#
# Version pins (§7): no version string lives in this file. The seat TUI pair
#   (pi_host_tui_npm_*) is read from the one pin file
#   IaC/ansible/group_vars/all/versions.yml, exactly like install-pi-debian.sh reads its
#   pins, so a hand-typed `pi install npm:pi-open-tui` on one seat cannot quietly become
#   the fleet's state (docs/pi-harness.md §5a).
#
# Env overrides: REPO (default: $PWD repo root via script path),
#   PI_PACKAGES (space-separated, default below). Run INSIDE WSL Debian
#   (`wsl -d Debian -- bash $REPO/scripts/install-pi-wsl.sh` works too, where $REPO =
#    the repo root self-derived from this script's path — /home/domen/source/homelab).
#
# Requires: curl, bash. Read-only clone/sync needs no GitHub auth.
# Owner: user (pi.dev-in-WSL tooling, HD-259 companion) — record in the owning doc if adopted.
# =====================================================================
set -euo pipefail

# ---- locate repo root (allow override) -----------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# ---- pi packages to install (tracked here, mirror of Windows settings.json) --
VERSIONS="$REPO/IaC/ansible/group_vars/all/versions.yml"
# pin(): read one pin from the SSOT version file. Fail-loud, like install-pi-debian.sh:
# a missing pin aborts here instead of installing whatever npm answers for `latest` (§7).
pin() {
  local v
  v="$(grep -E "^${1}:" "$VERSIONS" 2>/dev/null | head -1 | sed -E 's/^[^:]+:[[:space:]]*"?([^"#]*)"?.*/\1/' | tr -d '[:space:]')"
  [ -n "$v" ] || { echo "error: pin '$1' missing from IaC/ansible/group_vars/all/versions.yml — add it there, do not hardcode it here" >&2; exit 1; }
  printf '%s' "$v"
}
TUI_PKG="$(pin pi_host_tui_npm_package)"
TUI_V="$(pin pi_host_tui_npm_version)"

PI_PACKAGES="${PI_PACKAGES:-
  npm:@ogulcancelik/pi-ssh-tools
  npm:pi-subagents
  npm:@season179/pi-worktree
  npm:pi-deepseek-optimized
  npm:${TUI_PKG}@${TUI_V}
}"

MODE="${1:-}"

say()  { printf '\n== %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }

require_cmds() {
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || { echo "error: missing '$c' (apt install $c)" >&2; exit 1; }; done
}

# ---- --reload: informational only -------------------------------------------
if [ "$MODE" = "--reload" ]; then
  say "install-pi (REPO=$REPO)"
  if command -v pi >/dev/null 2>&1; then
    info "pi:        $(command -v pi) -> $(pi --version 2>/dev/null || echo '?')"
    info "pi config: $(ls -d "$HOME/.pi/agent" 2>/dev/null || echo 'ABSENT')"
  else
    info "pi:        NOT installed (run: bash scripts/install-pi-wsl.sh)"
    exit 0
  fi
  info "skills:    $(ls "$HOME/.pi/agent/skills" 2>/dev/null | tr '\n' ' ')"
  info "packages:  $(pi list 2>/dev/null | tail -n +1)"
  echo; echo "    then: cd $REPO && bash scripts/guard-session.sh"
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
  # Refresh PATH for this session (installer may have appended a standalone node bin).
  if ! command -v pi >/dev/null 2>&1; then
    hash -r 2>/dev/null || true
  fi
  command -v pi >/dev/null 2>&1 || { echo "error: pi not on PATH after install — add the installer-suggested node bin to your shell profile" >&2; exit 1; }
  info "pi:  $(command -v pi) -> $(pi --version)"
else
  require_cmds pi
fi

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

  # Packages/extension bundles: install the tracked set (idempotent; `pi install` is a no-op if present).
  say "ensuring pi packages/extensions"
  for pkg in $PI_PACKAGES; do
    case "$pkg" in
      ''|' '*) continue ;;
    esac
    info "pi install $pkg"
    pi install "$pkg"
  done
  info "installed: $(pi list 2>/dev/null | tr '\n' ' ')"

  # The seat TUI package carries ONE harness-relevant key: the footer's hostname segment,
  # which is what answers "which box am I typing to" (docs/pi-harness.md §5a — the job the
  # retired pi-agent/extensions/host-status.ts used to do). pi-open-tui's own DEFAULT is
  # OFF, so `pi install` alone leaves the seat anonymous: this sets that key and touches
  # nothing else the operator tuned through /open-tui.
  say "seat TUI footer config (pi-tui-config.sh --push)"
  if [ -f "$REPO/scripts/pi-tui-config.sh" ]; then
    bash "$REPO/scripts/pi-tui-config.sh" --push \
      || { echo "error: pi-tui-config.sh --push reported problems" >&2; exit 1; }
  else
    info "no scripts/pi-tui-config.sh in this clone — the footer-hostname leg was NOT run"
  fi

  # The settings plane (HD-1093): the harness keys come from pi-agent/settings-ssot.json and are
  # MERGED, so this runner's workstation keys (externalEditor, lastChangelogVersion, tuiMode) and
  # any seat-local package survive — §5's "the block is the part that must match", enforced.
  say "settings plane (pi-agent/settings-ssot.json -> ~/.pi/agent/settings.json)"
  if [ -f "$REPO/scripts/pi-settings-config.sh" ]; then
    bash "$REPO/scripts/pi-settings-config.sh" --push \
      || { echo "error: pi-settings-config.sh --push reported problems" >&2; exit 1; }
  else
    info "no scripts/pi-settings-config.sh in this clone — the settings plane was NOT run"
  fi

  # The TUI font. Honest scope note: WSL has no display, so THIS leg only places + proves; the
  # glyphs this seat draws come from the font installed on the Windows side
  # (scripts/win/install-nerd-font.ps1, run by pi-seat-sync.sh's win11 seat).
  say "seat TUI font (pinned nerd-fonts release)"
  [ -f "$REPO/scripts/install-nerd-font.sh" ] && bash "$REPO/scripts/install-nerd-font.sh" --push \
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
    bash "$REPO/scripts/sync-extensions.sh" --push \
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
echo "               its footer hostname IS the seat identity: docs/pi-harness.md §5a"
echo "   Session:  cd $REPO && bash scripts/guard-session.sh  (create a worktree first)"
echo "   Update:   pi update --extensions   +   re-run this script to re-sync repo SSOT"
echo
info "Provider/auth config (models.json, auth.json, settings.json) is NOT auto-synced:"
info "it holds secrets (API keys) + a machine-local lmstudio endpoint. Set it up per-side:"
info "  pi /login    # pick provider + authenticate (OpenRouter, Anthropic, …)"
info "  /model       # select the default model"
info "Settings like theme/thinking live in ~/.pi/agent/settings.json — copy only what's portable."
