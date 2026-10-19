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
#   bash scripts/harness/install-pi-wsl.sh --self-test     # the pi leg against fixture pins, in a
#                                                          # temp HOME; installs nothing on this box
#   PATH persistence is OWNED here (HD-1110): the node bin dir and pi's entrypoint dir are written
#   into ~/.bashrc and ~/.profile under this script's marks, and the install legs VERIFY the result
#   by asking a login shell (`bash -lc 'which -a pi'`), not this process. HD-1118 Stage 2 is the
#   follow-through for the rest of the seat family (repo root + pins through scripts/lib/). The
#   hand-written PATH line a seat used to need is superseded by this — do not hand-edit either file.
#   Anything else exits 2 WITHOUT installing: an unrecognised argument used to fall through to the
#   full installer (see the guard below `MODE=`). The pi leg is PINNED (HD-1161): it runs the
#   Debian sibling's pinned leg and then asserts the answering `pi` against `pi_host_npm_version`,
#   so nothing here can install a build the repo has not read.
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
# The pi binary's own pin, read HERE so the leg can ASSERT its result. Before HD-1161 this file read
# the TUI pair and not this one, because it never compared the install against anything — the
# upstream bootstrap it called takes no version, so there was no expectation to read.
pin PI_PKG pi_host_npm_package
pin PI_V  pi_host_npm_version

# HD-1118 Stage 2: the package set is NOT listed in this file. It is DISCOVERED from the pi_pkg_*
# inventory in the version SSOT, so a from-zero WSL bootstrap cannot carry a private list again.
# What these lines were: fleet packages installed with NO version (`pi install npm:pi-subagents`
# takes whatever `latest` means that day), on one of three seat paths, while the settings plane
# owned only two of them. `pi install` is idempotent and the specs now arrive pinned.
pi_fleet_packages() { seat_pkg_rows "$VERSIONS" | awk -F'\t' '$3=="fleet"{print $2}'; }

MODE="${1:-}"

# ---- --self-test: the pi leg, proven in a sandbox -------------------------------------------
# This file had NO self-test for its install leg, so the leg HD-1161 is about could not fail. The
# arms drive THIS script with HOME and REPO pointed at a fixture in a temp dir — `env -i`, so no
# host PATH can smuggle in the pi this box really has — where:
#   * the fixture inventory carries the pin the arm names, and
#   * the Debian delegate this script calls is stubbed to install a `pi` answering a chosen version
#     and to RECORD that it ran,
# which is the only way to ask "what happens when the install answers something other than the
# pin?" and "does it npm-install underneath a managed seat?" without doing either to a real box.
# The delegate's own pinned leg is proven by install-pi-debian.sh, whose --check this arm set does
# not replace.
if [ "${MODE:-}" = "--self-test" ]; then
  _st_fail=0
  _st_t="$(mktemp -d)"; trap 'rm -rf "$_st_t"' EXIT
  # _st_arm <name> <pin> <answer> <pre: none|managed> <expect: ok|fail|refuse|skip>
  _st_arm() {
    local _n="$1" pinv="$2" ansv="$3" pre="$4" expect="$5" out rc
    local _d="$_st_t/$_n"   # separate statement: one `local` line cannot read a name it is assigning
    mkdir -p "$_d/repo/IaC/ansible/group_vars/all" "$_d/repo/scripts/harness" "$_d/repo/scripts/lib" \
             "$_d/repo/docs" "$_d/home/bin" "$_d/home/.pi/agent/bin"
    : >"$_d/repo/docs/index.md"
    # persist_path only writes into files that already exist, and verify_login_path asks a LOGIN
    # shell — so the fixture home needs the two files a real Debian home ships with.
    : >"$_d/home/.profile"; : >"$_d/home/.bashrc"
    cp "$REPO/scripts/lib/"*.sh "$_d/repo/scripts/lib/" 2>/dev/null || true
    # The script under test runs FROM the fixture, so the fixture's copy is this file byte for byte;
    # only the stubbed delegate and the fixture inventory differ from the real tree.
    cp "$REPO/scripts/harness/install-pi-wsl.sh" "$_d/repo/scripts/harness/install-pi-wsl.sh"
    printf 'pi_host_npm_package: @x/pi\npi_host_npm_version: %s\npi_host_tui_npm_package: pi-open-tui\npi_host_tui_npm_version: 0.1.0\n' \
      "$pinv" >"$_d/repo/IaC/ansible/group_vars/all/versions.yml"
    # The delegate, stubbed. Recording that it ran is what makes "refused, so nothing was installed"
    # an observable fact rather than an absence of evidence.
    cat >"$_d/repo/scripts/harness/install-pi-debian.sh" <<STUB
#!/usr/bin/env bash
printf called >> "$_d/delegate-called"
mkdir -p "\$PI_SEAT_ROOT/current/bin"
{ echo '#!/bin/sh'; echo "echo $ansv"; } > "\$PI_SEAT_ROOT/current/bin/pi"
chmod +x "\$PI_SEAT_ROOT/current/bin/pi"
exit 0
STUB
    chmod +x "$_d/repo/scripts/harness/install-pi-debian.sh"
    if [ "$pre" = managed ]; then
      # pi's OWN layout: the launcher dir, answering $ansv. This is the state §1 says not to
      # npm-install underneath.
      printf '#!/bin/sh\necho %s\n' "$ansv" >"$_d/home/.pi/agent/bin/pi"
      chmod +x "$_d/home/.pi/agent/bin/pi"
      # A managed seat got that launcher onto PATH from a previous install, so the fixture carries
      # the same persisted block — otherwise the login-shell leg tests the fixture, not the script.
      printf '\nexport PATH="%s:$PATH"\n' "$_d/home/.pi/agent/bin" >>"$_d/home/.profile"
      printf '\nexport PATH="%s:$PATH"\n' "$_d/home/.pi/agent/bin" >>"$_d/home/.bashrc"
    fi
    out="$(env -i HOME="$_d/home" TERM=dumb \
            PATH="$_d/home/.local/share/pi-node/current/bin:$_d/home/bin:$_d/home/.pi/agent/bin:/usr/bin:/bin" \
            REPO="$_d/repo" PI_ENTRY_DIR="$_d/home/.pi/agent/bin" PI_SEAT_ROOT="$_d/home/.local/share/pi-node" \
            bash "$_d/repo/scripts/harness/install-pi-wsl.sh" --pi-only 2>&1)" && rc=0 || rc=$?   # `|| rc=$?`: under
            # set -e a failing assignment would abort the arm before its expectation could be checked
    local called=0; [ -f "$_d/delegate-called" ] && called=1
    # Every expectation is an if/then, never a bare `test && printf`: under `set -e` a false
    # AND-list would abort the whole arm run at the first arm that passes.
    if [ "$expect" = ok ]; then
      if [ "$rc" = 0 ] && [ "$called" = 1 ]; then
        printf 'ok: %s — an on-pin answer is accepted (rc 0, delegate ran)\n' "$_n"
      else
        printf 'NOT CAUGHT: %s rc %s delegate %s\n%s\n' "$_n" "$rc" "$called" "$out"; _st_fail=$((_st_fail+1))
      fi
    elif [ "$expect" = fail ]; then
      if [ "$rc" != 0 ]; then
        printf 'ok: %s — an off-pin answer reddens the leg\n' "$_n"
      else
        printf 'NOT CAUGHT: %s accepted an off-pin pi\n%s\n' "$_n" "$out"; _st_fail=$((_st_fail+1))
      fi
    elif [ "$expect" = refuse ]; then
      if [ "$rc" != 0 ] && printf '%s' "$out" | grep -q managed && [ "$called" = 0 ]; then
        printf 'ok: %s — a managed seat off its pin is a STOP, and nothing was installed\n' "$_n"
      else
        printf 'NOT CAUGHT: %s did not refuse a managed seat (rc %s, delegate %s)\n%s\n' "$_n" "$rc" "$called" "$out"
        _st_fail=$((_st_fail+1))
      fi
    else  # skip
      if [ "$rc" = 0 ] && [ "$called" = 0 ]; then
        printf 'ok: %s — a managed seat AT its pin is left alone, no second layout\n' "$_n"
      else
        printf 'NOT CAUGHT: %s touched a managed seat already at the pin (rc %s, delegate %s)\n%s\n' "$_n" "$rc" "$called" "$out"
        _st_fail=$((_st_fail+1))
      fi
    fi
  }
  _st_arm on-pin          7.7.7 7.7.7 none     ok
  _st_arm off-pin         7.7.7 7.7.8 none     fail
  # The pair that proves the expectation is READ, not typed: a fixture pin of 8.8.8 must be obeyed
  # in one direction and disbelieved in the other. A hardcoded version anywhere in this file makes
  # one of these two arms impossible to pass. The numbers are deliberately not real pi releases —
  # a real one in this file would be indistinguishable from the pin it is supposed to be read from.
  _st_arm pin-is-read-yes 8.8.8 8.8.8 none     ok
  _st_arm pin-is-read-no  8.8.8 9.9.9 none     fail
  _st_arm managed-off-pin 7.7.7 7.7.8 managed  refuse
  _st_arm managed-on-pin  7.7.7 7.7.7 managed  skip
  if [ "$_st_fail" = 0 ]; then printf 'install-pi-wsl self-test: all arms ok\n'; exit 0; fi
  printf 'install-pi-wsl self-test: %s arm(s) NOT caught\n' "$_st_fail" >&2; exit 1
fi

# ⛔ AN UNKNOWN ARGUMENT MEANS FULL INSTALL HERE, so it is refused before anything runs.
# This script has no `--check`: `MODE` is only ever compared with `--pi-only`, `--config-only`,
# `--reload` and `--self-test`, so any OTHER first argument used to fall through to the installer
# branch, which piped `https://pi.dev/install.sh` into `sh`. Measured the hard way on the WSL seat
# 2026-10-19: typing the shape every sibling script answers to (`install-pi-wsl.sh --check`, the
# spelling HD-1118's own from-zero leg uses for `install-pi-debian.sh --check`) downloaded the
# managed installer, `npm install`ed 119 packages into a staging tree and created
# `~/.pi/agent/install/{releases,staging}` on a box that was only meant to be READ. The pin survived
# only because that installer takes no version — it fetches `latest`, and its own smoke test is what
# disagreed. §7, fail loud: a mode this file does not know is a STOP, never a default.
case "$MODE" in
  ''|--pi-only|--config-only|--reload|--self-test) ;;
  *)
    printf 'error: unknown mode %s — refusing.\n' "$MODE" >&2
    printf '  anything this script does not name INSTALLS (it runs the pinned pi leg), so it will not\n'
    printf '  guess. Known: (full) · --pi-only · --config-only · --reload (read-only report) ·\n' >&2
    printf '  --self-test (the pi leg against a fixture pin, in a temp HOME — installs nothing).\n' >&2
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
# HD-1161: this leg was `curl -fsSL https://pi.dev/install.sh | sh` — no version argument, no
# version env, and the smoke test inside that script compares what it installed against ITS OWN
# `latest` — measured on the WSL seat, its own smoke test reported the version it installed and the
# newer version it expected, and the fleet pin was on the installed side of that disagreement.
# Upstream takes no version, so the only honest expectation
# is this repo's pin, read here through pin() and asserted on the binary that answers afterwards.
# The leg is DELEGATED to the pinned Debian sibling rather than re-implemented: two installers
# carrying the same node-tarball-and-prefix logic is how the fleet grew a pinned and an unpinned
# path to one binary in the first place.
PI_SEAT_ROOT="${PI_SEAT_ROOT:-$HOME/.local/share/pi-node}"
pi_answers() { local b; b="$(pi_bin || true)"; [ -n "$b" ] && "$b" --version 2>/dev/null \
  | tr -d '[:space:]"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1; }
pi_is_managed() { case "$1" in "$PI_ENTRY_DIR"/*|*/.pi/agent/bin/pi|*/install/releases/*) return 0 ;; esac; return 1; }

if [ "$MODE" != "--config-only" ]; then
  pb="$(pi_bin || true)"
  install_leg=1
  if [ -n "$pb" ] && pi_is_managed "$pb"; then
    # docs/harness-pi-seats.md §1: an `npm install -g` underneath a managed seat leaves TWO
    # layouts and makes `which pi` a PATH-order question, so this is an owner action, not a lane's.
    if [ "$(pi_answers)" = "$PI_V" ]; then
      info "the answering pi is pi's OWN managed install ($pb) and already answers the pin $PI_V —"
      info "leaving that layout alone: 'pi update self' owns it, and installing under it would add a second layout"
      install_leg=0
    else
      printf 'error: the answering pi is pi%s  s OWN managed install (%s) and answers %s, not the pin %s.\n' \
        "'" "$pb" "$(pi_answers || echo '?')" "$PI_V" >&2
      printf '  "pi update self" owns that layout and installs the LATEST release, not a version it is handed,\n' >&2
      printf '  so this script will not npm-install underneath it (docs/harness-pi-seats.md §1). Two legal moves:\n' >&2
      printf '    1. run "pi update self" here, then move pi_host_npm_version AND pi_dev_npm_version to what it\n       reports (an owner ruling, CONVENTIONS §7);\n' >&2
      printf '    2. move the seat back onto the pinned layout with "bash scripts/harness/install-pi-debian.sh --pi-only",\n       which removes the managed launcher rather than burying it.\n' >&2
      exit 1
    fi
  fi

  if [ "$install_leg" = 1 ]; then
    say "installing ${PI_PKG}@${PI_V} via the pinned Debian leg"
    [ -f "$REPO/scripts/harness/install-pi-debian.sh" ] \
      || { echo "error: no scripts/harness/install-pi-debian.sh in this clone — the pinned leg has no owner here" >&2; exit 1; }
    # --pi-only = pinned node tarball + `npm_config_prefix=$PI_SEAT_ROOT/current npm install -g
    # ${PI_PKG}@${PI_V}`, which is the shape pi-self-update.sh can converge. The upstream bootstrap
    # is gone from this file, so nothing here can fetch a version the repo has not read.
    bash "$REPO/scripts/harness/install-pi-debian.sh" --pi-only || { echo "error: the pinned install leg reported a problem" >&2; exit 1; }
    persist_path
    pb="$(pi_bin || true)"
    if [ -z "$pb" ]; then hash -r 2>/dev/null || true; pb="$(pi_bin || true)"; fi
    [ -n "$pb" ] || { echo "error: no pi after install (looked on PATH and in $PI_ENTRY_DIR) — no PATH entry can resolve a binary the installer never wrote" >&2; exit 1; }
    got="$(pi_answers || true)"
    # The assertion, not the delegate's exit code: a delegate that installs something else and exits
    # 0 is exactly the failure this row is about.
    [ "$got" = "$PI_V" ] \
      || { printf 'error: the pi that answers is %s, pin pi_host_npm_version says %s — refusing to call that installed\n' "${got:-nothing}" "$PI_V" >&2
           printf '  (%s). An off-pin answer is the HD-1161 defect, not a finished install.\n' "$pb" >&2; exit 1; }
    info "pi:  $pb -> $got == pi_host_npm_version"
    verify_login_path || exit 1
  else
    verify_login_path || exit 1
  fi
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
