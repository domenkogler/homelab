#!/usr/bin/env bash
# =====================================================================
# install-pi-debian.sh — pi.dev bootstrap for a bare-Debian HOST pi seat (HD-446)
#
# Purpose: bring a clean Debian 13 box (or a fresh user account on one — the
#   oldsrv cockpit seat `domen` is the reference target) to the SAME pi harness
#   this repo's other seat runs: pinned Node, the pinned pi coding-agent, the
#   rendered model contract/auth, the repo skills + extensions, the seat's terminal
#   harness (`~/.tmux.conf`: mouse + OSC 52 clipboard, HD-1085), the seat TUI
#   package, and (optionally) the web cockpit. Rebuildable instead of remembered:
#   the seat must survive a rebuild without a session having to remember what was
#   hand-installed. The tmux leg is the SAME gap HD-446 closed for extensions — a
#   package DECISION (`seat_packages: [tmux]`, roles/seat) whose CONFIG was never
#   deployed, so a rebuilt seat had tmux and no seat config.
#
# SIBLING, NOT FORK (the row's own trap): [`install-pi-wsl.sh`](install-pi-wsl.sh)
#   is the WSL shape — `/mnt/c`, drive letters, a Windows-side mirror. Nothing
#   here reads /mnt or a Windows path. What the two DO share is the deploy
#   direction (repo -> ~/.pi/agent) and the package list.
#
# WHY NOT `apt install nodejs` (measured on oldsrv, the reason this row exists):
#   pi declares `engines.node >= 22.19.0`; Debian 13's apt candidate is Node
#   20.19.2 — an apt-based install produces a harness that cannot start. The
#   pinned official tarball under ~/.local/share/pi-node/ is the shape BOTH the
#   laptop and the oldsrv seat actually use, so this script installs that shape.
#
# TWO PI LAYOUTS (measured on oldsrv 2026-10-09 — the reason TWO PATH blocks are persisted):
#   npm -g   -> <pi-node prefix>/bin/pi, the symlink npm creates next to the pinned node binary.
#              What install_pi() installs, and what the oldsrv seat had until 2026-10-09.
#   managed  -> ~/.pi/agent/bin/pi, a launcher over ~/.pi/agent/install/releases/<ver>/ (layout
#              `releases-v1`). pi 1.1.0's `pi update` MIGRATES a global install to this layout and
#              removes the node-dir symlink (its own CHANGELOG: "`pi update` on global npm
#              installations now recommends migrating to the managed installation").
# Both are working pi installs; only ONE is on PATH when a seat exports just the node bin dir,
# which is how a seat that ran `pi update` inside a session woke up with `pi: command not found`
# while pi itself was healthy. So: PATH carries BOTH dirs, every probe here goes through pi_bin()
# (never a bare `command -v pi`), and scripts/pi-self-update.sh names the managed layout instead
# of reporting SKIP for it.
#
# Usage (run AS the seat user, on the seat):
#   bash scripts/install-pi-debian.sh              # full: node + pi + config + skills
#   bash scripts/install-pi-debian.sh --pi-only    # pinned node + pi, no config sync
#   bash scripts/install-pi-debian.sh --path-only  # only the two PATH blocks — the repair for a
#                                                  # seat whose pi moved to the managed layout
#   bash scripts/install-pi-debian.sh --config-only# skills/AGENTS/prompts + model contract
#   bash scripts/install-pi-debian.sh --cockpit    # + the pi-web cockpit package
#   bash scripts/install-pi-debian.sh --tui        # + the seat TUI package only (pi-open-tui)
#   bash scripts/install-pi-debian.sh --check      # report only, write nothing (exit 1 on drift)
#
# Pins: read from the SSOT `IaC/ansible/group_vars/all/versions.yml` (§7 — one
#   file per pin). A missing pin ABORTS; there is no inline default (§7 fail-loud).
# Env overrides: REPO, PI_SEAT_ROOT (default $HOME/.local/share/pi-node).
#
# Requires: curl, xz, tar, git. `--config-only`/full also needs 1Password access
#   on the machine running it (render-pi-config.py resolves credentials at render
#   time); without it, render on a machine that has access and use --out + scp.
# Owner: the pi.dev seat lane (`prompt-seat-cockpit-grants.md`). Record in docs/pi-harness.md §1.
# =====================================================================
set -euo pipefail

# `:-$0` because the pipe-over-ssh form (`ssh seat 'bash -s' < this-file`) leaves BASH_SOURCE
# unset, and `set -u` made every such run print "BASH_SOURCE[0]: unbound variable".
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="${REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PI_SEAT_ROOT="${PI_SEAT_ROOT:-$HOME/.local/share/pi-node}"
VERSIONS="$REPO/IaC/ansible/group_vars/all/versions.yml"
NODE_BIN_DIR="$PI_SEAT_ROOT/current/bin"
PI_ENTRY_DIR="${PI_ENTRY_DIR:-$HOME/.pi/agent/bin}"   # pi's own launcher dir (managed layout)
PROFILE_MARK="# pi-seat node (install-pi-debian.sh)"
PROFILE_MARK_PI="# pi-seat pi entrypoint (install-pi-debian.sh)"

say()  { printf '\n== %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
err()  { printf '    ERROR: %s\n' "$*" >&2; }

require_cmds() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || { err "missing '$c' — apt install $c"; exit 1; }
  done
}

# ---- pins from the SSOT (fail-loud: no default, §7) -----------------------
pin() {
  local v
  v="$(grep -E "^${1}:" "$VERSIONS" 2>/dev/null | head -1 | sed -E 's/^[^:]+:[[:space:]]*"?([^"#]*)"?.*/\1/' | tr -d '[:space:]')"
  [ -n "$v" ] || { err "pin '$1' missing from IaC/ansible/group_vars/all/versions.yml — add it there, do not hardcode it here"; exit 1; }
  printf '%s' "$v"
}
NODE_V="$(pin pi_host_node_version)"
PI_PKG="$(pin pi_host_npm_package)"
PI_V="$(pin pi_host_npm_version)"
WEB_PKG="$(pin pi_host_web_npm_package)"
WEB_V="$(pin pi_host_web_npm_version)"
TUI_PKG="$(pin pi_host_tui_npm_package)"
TUI_V="$(pin pi_host_tui_npm_version)"

MODE="${1:-full}"

# ---- node: pinned official tarball, never apt ----------------------------
node_pinned_ok() {
  [ -x "$NODE_BIN_DIR/node" ] && "$NODE_BIN_DIR/node" -v 2>/dev/null | grep -qx "v${NODE_V}"
}
install_node() {
  if node_pinned_ok; then info "node ${NODE_V} already pinned at $PI_SEAT_ROOT/current"; return 0; fi
  if command -v node >/dev/null 2>&1; then
    info "PATH node is $(command -v node) -> $(node -v) (apt node 20.x cannot run pi: engines >= 22.19.0)"
  fi
  require_cmds curl tar xz
  local tarball="node-v${NODE_V}-linux-x64.tar.xz" url="https://nodejs.org/dist/v${NODE_V}/${tarball}"
  say "fetching pinned node ${NODE_V}"
  mkdir -p "$PI_SEAT_ROOT"
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' RETURN
  curl -fsSL --retry 3 -o "$TMP/$tarball" "$url"
  curl -fsSL --retry 3 -o "$TMP/SHASUMS256.txt" "https://nodejs.org/dist/v${NODE_V}/SHASUMS256.txt"
  ( cd "$TMP" && grep " ${tarball}\$" SHASUMS256.txt | sha256sum -c - ) \
    || { err "checksum mismatch for $tarball — refusing to install"; exit 1; }
  rm -rf "$PI_SEAT_ROOT/v${NODE_V}"
  mkdir -p "$PI_SEAT_ROOT/v${NODE_V}"
  tar -xJf "$TMP/$tarball" -C "$PI_SEAT_ROOT/v${NODE_V}" --strip-components=1
  ln -sfn "$PI_SEAT_ROOT/v${NODE_V}" "$PI_SEAT_ROOT/current"
  info "node ${NODE_V} installed, current -> v${NODE_V}"
}
export PATH="$NODE_BIN_DIR:$PATH"

# ---- PATH persistence (idempotent; a systemd USER unit never reads this) --
persist_path() {
  # BOTH files, and know which shell reads which (measured on the seat 2026-10-05):
  #   interactive non-login  (`ssh seat` then type pi)  -> ~/.bashrc
  #   login shell            (`bash -l`, some consoles)  -> ~/.profile
  #   NON-interactive non-login (`ssh seat 'pi …'`)      -> NEITHER. Debian's .bashrc
  #     returns early for non-interactive shells, so a one-shot remote pi call must use
  #     the absolute path (or `bash -lic`). This is the same split a systemd USER unit
  #     has — that one is solved by roles/seat's Environment=PATH drop-in, not here.
  local f
  for f in "$HOME/.bashrc" "$HOME/.profile"; do
    [ -e "$f" ] || continue
    grep -qF "$PROFILE_MARK" "$f" && { info "PATH block already in $(basename "$f")"; continue; }
    { printf '\n%s\nexport PATH="%s:$PATH"\n' "$PROFILE_MARK" "$NODE_BIN_DIR"; } >> "$f"
    info "appended the node bin dir to $(basename "$f")"
  done
  # The pi ENTRYPOINT dir, under its OWN mark. A seat whose node block predates 2026-10-09 has
  # the node mark (so the loop above skips it) yet lost 'pi' when 'pi update' migrated it to the
  # managed layout — this second block is that repair, and a separate mark is what lets it append
  # one line instead of rewriting a block a previous run already owns.
  for f in "$HOME/.bashrc" "$HOME/.profile"; do
    [ -e "$f" ] || continue
    grep -qF "$PROFILE_MARK_PI" "$f" && { info "pi entrypoint block already in $(basename "$f")"; continue; }
    { printf '\n%s\nexport PATH="%s:$PATH"\n' "$PROFILE_MARK_PI" "$PI_ENTRY_DIR"; } >> "$f"
    info "appended the pi entrypoint dir to $(basename "$f")"
  done
  info "NOTE: neither file is read by a systemd user unit — that needs roles/seat's Environment=PATH drop-in"
}

# ---- resolve the pi binary across BOTH layouts ----------------------------
# PATH first (it is what the operator typed into), then the managed launcher. Anything asking
# "does pi exist here?" must call this and NOT a bare `command -v pi`: on a migrated seat the
# latter is empty while pi runs perfectly at ~/.pi/agent/bin/pi (the 2026-10-09 oldsrv class).
pi_bin() {
  local p
  p="$(command -v pi 2>/dev/null || true)"
  [ -n "$p" ] && [ -x "$p" ] && { printf '%s' "$p"; return 0; }
  [ -x "$PI_ENTRY_DIR/pi" ] && { printf '%s' "$PI_ENTRY_DIR/pi"; return 0; }
  return 1
}

# ---- pi + packages -------------------------------------------------------
install_pi() {
  say "installing ${PI_PKG}@${PI_V} into the pinned prefix"
  npm_config_prefix="$PI_SEAT_ROOT/current" npm install -g --no-fund --no-audit "${PI_PKG}@${PI_V}" >/dev/null \
    || { err "npm install -g ${PI_PKG}@${PI_V} failed"; exit 1; }
  local pb; pb="$(pi_bin || true)"
  [ -n "$pb" ] || { err "no pi binary answers after install (looked on PATH and in $PI_ENTRY_DIR)"; exit 1; }
  info "pi $("$pb" --version 2>&1 | head -1) [$pb]"
}
install_tui() {
  # The seat's TUI skin (docs/pi-harness.md §5a): pi-open-tui owns the footer, and the
  # footer's hostname segment is what answers "which box am I typing to" — the job the
  # retired pi-agent/extensions/host-status.ts used to do. Fleet-wide, not seat-local:
  # the version is the pi_host_tui_npm_version pin, never a bare `pi install npm:…`.
  local pb; pb="$(pi_bin || true)"
  [ -n "$pb" ] || { info "no pi binary found — skipping the ${TUI_PKG} package (run --pi-only first)"; return 0; }
  say "installing the seat TUI package ${TUI_PKG}@${TUI_V}"
  "$pb" install "npm:${TUI_PKG}@${TUI_V}" 2>&1 | tail -2 || { err "pi install npm:${TUI_PKG}@${TUI_V} failed"; return 1; }
  bash "$REPO/scripts/pi-tui-config.sh" --push || return 1
}
check_tui() {
  local pb; pb="$(pi_bin || true)"
  [ -n "$pb" ] || { err "pi: no binary found (neither PATH nor $PI_ENTRY_DIR) — cannot read the TUI package"; return 1; }
  if "$pb" list 2>/dev/null | grep -q "$TUI_PKG"; then
    info "tui package: ${TUI_PKG} installed (pin ${TUI_V})"
    "$pb" list 2>/dev/null | grep "$TUI_PKG" | sed 's/^/      /'
  else
    err "tui package: ${TUI_PKG} NOT installed — pi install npm:${TUI_PKG}@${TUI_V}"; return 1
  fi
  bash "$REPO/scripts/pi-tui-config.sh" --check --strict || return 1
}
install_cockpit() {
  say "installing the web cockpit package"
  # TRAP: the pi-web binary exits 1 unless ~/.pi/agent/sessions already exists.
  mkdir -p "$HOME/.pi/agent/sessions"
  pi install "npm:${WEB_PKG}@${WEB_V}" 2>&1 | tail -2 || { err "pi install ${WEB_PKG} failed"; exit 1; }
  info "cockpit package ${WEB_PKG}@${WEB_V} (live tag now resolves ${WEB_V}; the seat has self-updated inside @beta before — see HD-484)"
  check_cockpit_unit
}
check_cockpit_unit() {
  # pi's shebang is `#!/usr/bin/env node` and a systemd USER unit gets no login
  # PATH, so the unit needs the node bin dir handed to it. The DROP-IN IS OWNED BY
  # IaC/ansible/roles/cockpit — never hand-write it here (that is the HD-445 class).
  command -v systemctl >/dev/null 2>&1 || return 0
  systemctl --user cat pi-web.service >/dev/null 2>&1 || { info "no pi-web user unit yet (roles/cockpit renders it)"; return 0; }
  local unit_path d found="" dirs
  unit_path="$(systemctl --user cat pi-web.service 2>/dev/null | sed -n 's/^Environment=PATH=//p' | tail -1)"
  if [ -n "$unit_path" ]; then
    # "It carries an Environment=PATH=" is not the property that matters; the property is that
    # one of those directories holds an executable pi. Reading the PATH instead of grepping for
    # the key works on either layout and is blind to neither (CONVENTIONS §6: prove the probe).
    IFS=':' read -r -a dirs <<< "$unit_path"
    for d in "${dirs[@]}"; do
      [ -x "$d/pi" ] && { found="$d/pi"; break; }
    done
  fi
  if [ -n "$found" ]; then
    info "pi-web unit PATH finds pi: $found"
  elif [ -n "$unit_path" ]; then
    err "pi-web unit PATH lists no directory holding an executable pi (PATH=$unit_path)"
    err "remediation: converge roles/seat (renders pi-on-path.conf carrying BOTH pi dirs), do not hand-write the drop-in"
    return 1
  else
    err "pi-web unit has NO Environment=PATH= — every chat send will die with: exec: \"pi\": executable file not found in \$PATH"
    err "remediation: converge roles/seat (renders pi-on-path.conf), do not hand-write the drop-in"
    return 1
  fi
}

# ---- config: rendered model contract + repo skills ------------------------
install_config() {
  say "model contract + auth (RENDERED — never a copied laptop file, HD-388)"
  mkdir -p "$HOME/.pi/agent/sessions" "$HOME/.pi/agent/skills" "$HOME/.pi/agent/prompts"
  if python3 "$REPO/scripts/render-pi-config.py" --vendor all; then
    info "models.json + auth.json rendered"
  else
    err "render failed — this host needs 1Password access. Render elsewhere and ship it:"
    err "  python3 scripts/render-pi-config.py --vendor all --out /tmp/models.json && scp /tmp/models.json <seat>:.pi/agent/models.json"
    return 1
  fi
  say "repo skills -> ~/.pi/agent/skills (repo is SSOT, HD-254)"
  bash "$REPO/scripts/sync-skills.sh" --push || err "sync-skills.sh --push reported problems"
  say "repo extensions -> ~/.pi/agent/extensions (repo is SSOT; deployed-only files preserved, retired names removed)"
  bash "$REPO/scripts/sync-extensions.sh" --push || err "sync-extensions.sh --push reported problems"
  say "the seat TUI package (pi-open-tui, pinned) + its footer key"
  install_tui
  say "AGENTS.md + prompt templates"
  [ -f "$REPO/pi-agent/AGENTS.md" ] && install -m 0644 "$REPO/pi-agent/AGENTS.md" "$HOME/.pi/agent/AGENTS.md" && info "AGENTS.md deployed"
  [ -d "$REPO/pi-agent/prompts" ] && { mkdir -p "$HOME/.pi/agent/prompts"; install -m 0644 "$REPO"/pi-agent/prompts/*.md "$HOME/.pi/agent/prompts/" 2>/dev/null || true; }
  info "the harness keys of settings.json are NOT written here by hand: pi-settings-config.sh merges them from pi-agent/settings-ssot.json (§1, §5)"
  say "settings plane (pi-agent/settings-ssot.json -> ~/.pi/agent/settings.json, machine-local keys preserved)"
  bash "$REPO/scripts/pi-settings-config.sh" --push || err "pi-settings-config.sh --push reported problems"
  say "the seat's terminal harness (repo pi-agent/tmux/tmux.conf -> ~/.tmux.conf, HD-1085)"
  # This was HD-1085's known gap — the installer never called the tmux installer, so a freshly
  # bootstrapped seat had no mouse and no OSC 52 clipboard. --push REFUSES a foreign ~/.tmux.conf
  # rather than clobbering it, so a hand-configured seat is a loud stop, not a silent overwrite.
  # rc-aware on purpose: --push ENDS in the load probe, so its exit code carries three states —
  # 0 = installed AND effective, 1 = a real defect (refusal / CRLF / inert file), 2 = installed but
  # UNPROVEN because no tmux binary is here. Collapsing those into one `|| info` made rc 1 (a real
  # defect) print as a note, and counting 2 as either a pass or a failure would be a lie —
  # CONVENTIONS §6: an environment boundary prints SKIP, never a verdict (docs/pi-harness.md §5b).
  local tmrc=0
  bash "$REPO/scripts/install-tmux-conf.sh" --push || tmrc=$?
  case "$tmrc" in
    0) info "~/.tmux.conf installed and the load probe read the options back — effective" ;;
    2) info "SKIP: installed, but tmux is not on PATH here, so effectiveness is UNPROVEN (not a pass). roles/seat owns the package; then: bash scripts/install-tmux-conf.sh --verify" ;;
    *) err "tmux seat harness is NOT in place/effective (rc $tmrc) — a tmux config that errors mid-load still exits 0, so trust this, never the reload: bash scripts/install-tmux-conf.sh --check" ;;
  esac
  say "seat TUI font (the pinned nerd-fonts release the footer icons come from)"
  # Honest scope: on a headless seat this PLACES the font (and proves the placement); the leg
  # that buys visible glyphs is the terminal you draw pi with — on the Windows side, where the
  # sibling is scripts/win/install-nerd-font.ps1 (docs/pi-harness.md §5a).
  bash "$REPO/scripts/install-nerd-font.sh" --push || info "install-nerd-font.sh reported a problem (the seat still works; icons.mode falls back to portable Unicode)"
}

# ---- check mode ----------------------------------------------------------
check() {
  local bad=0
  say "check (write nothing)"
  node_pinned_ok && info "node: pinned ${NODE_V} OK" || { err "node: pinned ${NODE_V} NOT at $NODE_BIN_DIR"; bad=1; }
  local pb; pb="$(pi_bin || true)"
  if [ -z "$pb" ]; then
    err "pi: no binary found (neither PATH nor $PI_ENTRY_DIR)"; bad=1
  else
    local pv; pv="$("$pb" --version 2>&1 | head -1 | tr -d '[:space:]')"
    [ "$pv" = "$PI_V" ] && info "pi: ${pv} == pin [$pb]" || { err "pi: ${pv} != pin ${PI_V} [$pb]"; bad=1; }
    # The exact 2026-10-09 oldsrv state: pi present, PATH unaware. Name the repair.
    if [ "$pb" = "$PI_ENTRY_DIR/pi" ] && ! command -v pi >/dev/null 2>&1; then
      err "pi: found at $PI_ENTRY_DIR/pi but that dir is NOT on PATH — typing 'pi' fails. Repair: bash $0 --path-only"; bad=1
    fi
  fi
  python3 "$REPO/scripts/render-pi-config.py" --vendor all --check >/dev/null 2>&1 \
    && info "models.json + auth.json match the spec" || { err "model contract drift (or not rendered)"; bad=1; }
  # `|| bad=1` is NOT decoration: this script runs under `set -euo pipefail`, so a bare
  # `X --check | tail -2` ABORTS the whole check on the first drift (measured: `false 2>&1 | tail -2`
  # under those options exits 1 and never reaches the next line). Until 2026-10-09 the first skill
  # drift therefore ended check() before the settings/font/tmux legs and before the GREEN-or-DRIFT
  # summary — a seat reported nothing at all, which reads like a quiet box rather than a broken gate.
  bash "$REPO/scripts/sync-skills.sh" --check 2>&1 | tail -2 || bad=1
  bash "$REPO/scripts/sync-extensions.sh" --check 2>&1 | tail -2 || bad=1
  bash "$REPO/scripts/pi-settings-config.sh" --check --strict || bad=1
  bash "$REPO/scripts/install-nerd-font.sh" --check 2>&1 | tail -2 || bad=1
  # The tmux seat harness. --strict so a seat-side hand edit counts as drift (repo is the SSOT),
  # guarded at the host boundary: a box with neither the tmux binary nor a ~/.tmux.conf is not a
  # tmux seat, and printing that as DRIFT would mute the gate (validate-all item 29 guards the same way).
  if [ -f "$HOME/.tmux.conf" ] || command -v tmux >/dev/null 2>&1; then
    bash "$REPO/scripts/install-tmux-conf.sh" --check --strict || bad=1
  else
    info "tmux: SKIP — no tmux binary and no ~/.tmux.conf here (roles/seat's seat_packages owns it); a SKIP is not a pass"
  fi
  [ -d "$HOME/.pi/agent/sessions" ] && info "sessions dir present" || { err "~/.pi/agent/sessions missing (pi-web exits 1 without it)"; bad=1; }
  check_cockpit_unit || bad=1
  check_tui || bad=1
  say "check: $([ $bad -eq 0 ] && echo GREEN || echo 'DRIFT — see ERROR lines')"
  return $bad
}

case "$MODE" in
  --check)      check ;;
  --pi-only)    require_cmds curl tar xz git; install_node; persist_path; install_pi ;;
  --path-only)  persist_path ;;
  --config-only) install_config ;;
  --cockpit)    require_cmds curl tar xz git; install_node; persist_path; install_pi; install_config; install_cockpit ;;
  --tui)        require_cmds curl tar xz git; install_node; persist_path; install_pi; install_tui ;;
  full|"")      require_cmds curl tar xz git; install_node; persist_path; install_pi; install_config ;;
  *)            err "unknown option: $MODE"; echo "  use: (none) | --pi-only | --path-only | --config-only | --cockpit | --tui | --check" >&2; exit 2 ;;
esac
say "done"
