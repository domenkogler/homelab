#!/usr/bin/env bash
# =====================================================================
# seat-lsp-binaries.sh — the `lsp-binaries` seat plane: the language servers pi-lsp spawns.
#
# WHAT THIS OWNS
# --------------
#   The SET of language-server binaries a Debian seat must carry, at the versions pinned in
#   `IaC/ansible/group_vars/all/versions.yml` (`lsp_bin_*`), and the one PATH fact that decides
#   whether a session can see them. The pi-lsp PACKAGE is not here — that is the `settings` plane's
#   `pi_pkg_lsp` row — and neither is the unit that holds up an MCP tool server (`mcp-server`).
#
#     installed version   read from the installer's own record (see HOW A VERSION IS READ), and
#                         compared with the pin — `OK` is equality with the pin, never "it runs"
#     visible to a        resolved through an INTERACTIVE shell, because that is the shell a pi
#     session             session inherits; a login shell proves nothing about it
#     PATH persistence    the ~/.local/bin export, written under this script's mark
#
# WHY THIS EXISTED AS AN ACT AND NOT A SCRIPT
# -------------------------------------------
#   pi-lsp spawns one server per call, chosen by its built-in catalog, and when the command is not
#   on PATH it says `server skipped` and NOTHING ELSE CHANGES about the seat. Nine hand-run install
#   commands therefore produced a fleet where `lsp_diagnostics` returned a real diagnostic on one
#   box and a shrug on another, with no check able to tell the two apart. Two of the three ways that
#   happened are worth naming, because both were measured here:
#
#   * `npm i -g typescript-language-server typescript` followed `latest` for the peer and landed
#     `typescript@7`, the native port, which ships no `lib/tsserver.js`. The server STARTS, then
#     fails `initialize` with "Could not find a valid TypeScript installation" — which reads as a
#     broken route rather than as a wrong version. Hence `typescript` is a pinned entry of its own
#     (via `npm-lib`), and its probe looks at the package directory.
#   * `~/.profile` puts `~/.local/bin` on PATH behind an `if [ -d ]` guard, and `~/.profile` is read
#     by a LOGIN shell only. A session from a plain prompt is interactive-but-not-login, reads
#     `~/.bashrc`, and never sees that directory — while the PATH it does get carries the WINDOWS
#     `~/.local/bin` across `/mnt/c`. That is how a seat with every server installed answered that
#     none were on PATH, and why the visibility read asks an interactive shell.
#
# HOW A VERSION IS READ (no `--version`, wherever a record exists)
# ----------------------------------------------------------------
#   npm/npm-lib   ~/.local/lib/node_modules/<name>/package.json          — a file read, no exec
#   dotnet        `dotnet tool list -g`                                  — one exec for the plane,
#                 (the apphost is NOT run: it needs DOTNET_ROOT on a seat whose runtime is a
#                  ~/.dotnet prefix, and a probe that gets that wrong reports a working seat as
#                  broken, which happened once already)
#   astral        <cmd> --version                                        — these two accept it
#   A probe that DIES is rc 2, never a missing binary: CONVENTIONS §6.
#
#   WHERE THE RECORD ROOT IS (a seat fact, not a constant): a Debian seat keeps its npm globals in the
#   `npm --prefix ~/.local` layout; win11 keeps them in a Volta image whose NODE VERSION MOVES under
#   the seat, so the root there is derived from the node an interactive shell resolves (a pinned image
#   version turns every Volta upgrade into a MISSING for every entry).
#   HOW `dotnet` IS FOUND: a name this process already resolves needs no asking; a name it does not is
#   looked up through the SAME interactive shell the visibility read uses. On the cockpit seat the only
#   dotnet is a ~/.local/bin wrapper that a non-interactive shell never sees, and a probe that execs a
#   name it cannot find answers NO-PROBE forever. That is a read that was measured, not imagined.
#
# WHAT THIS PLANE DOES NOT WRITE
#   On win11 it writes NOTHING. The set there lives inside a Volta image and inside a .NET global-tool
#   store, and a plane that installs into another tool's image owns a mess nobody can attribute. So that
#   seat answers verdicts from those records, and a `--push` there prints NO-INSTALLER and changes no
#   byte. It is NOT a SKIP: a short win11 set stays a red leg that names which entries are short.
#
# VERDICTS   (per entry, and the run reports the worst one it saw)
#   OK                  installed at the pin and resolvable by a session
#   MISSING             no record of it at all
#   DRIFT(version)      installed, not at the pin
#   DRIFT(invisible)    installed but NO interactive shell resolves it — on a Debian seat the ~/.bashrc
#                       export is absent; on win11 it also means the bare name AND its `.cmd` spelling
#                       both fail to resolve (a .NET tool's `.cmd` is asked, because MSYS `command -v`
#                       skips `.cmd` and would otherwise call a working server invisible)
#   DRIFT(shadowed)     an interactive shell resolves it to a /mnt/c copy: the Windows binary wins,
#                       and on that seat it answers nothing at all
#   DRIFT(broken-lib)   installed but unusable in the specific way the TS route fails — no
#                       lib/tsserver.js in the typescript package (the `typescript@7` shape)
#   NO-INSTALLER        this seat has no installer for the entry's `via` — printed, never swallowed
#
# Exit: 0 OK / repaired · 1 any non-OK verdict under `--check --strict`, a push that did not take, or
#       a MISSING PIN — `pin()` owns that one and exits 1 with its own §7 FATAL, which is the lib's
#       fact and not this script's to reinterpret ·
#       2 NO VERDICT — a pin names an unknown `via`, a version probe died, or THIS BOX IS NOT A SEAT
#       THE ROW NAMES (the fan-out counts that rc as its own SKIP, neither a pass nor a failure).
#
# USAGE
#   bash scripts/harness/seat-lsp-binaries.sh                   # --check
#   bash scripts/harness/seat-lsp-binaries.sh --check --strict  # the seat-leg form
#   bash scripts/harness/seat-lsp-binaries.sh --push            # install what is short, re-prove
#   bash scripts/harness/seat-lsp-binaries.sh --list            # the set as the pins declare it
#   bash scripts/harness/seat-lsp-binaries.sh --self-test       # stubs: no npm, no dotnet, no net
#
# Env (sandbox hooks for --self-test only): LSP_ROOT, LSP_NPM, LSP_DOTNET, HL_SHELL_PROBE, PI_SEAT,
#   VERSIONS.
#
# Owning rule: docs/harness-pi-seats.md §1 (the language-server row) · scripts/lib/seat-planes.yml
# (`plane: lsp-binaries`) · the `lsp_bin_*` rows of the version SSOT.
set -uo pipefail

_hl_self="${BASH_SOURCE[0]}"
case "$_hl_self" in */*) _hl_d="${_hl_self%/*}" ;; *) _hl_d="." ;; esac
_hl_d="$(cd "$_hl_d" && pwd)"
# The repo root is FOUND by scripts/lib/repo-root.sh, never assumed from a depth; an inherited $REPO
# still wins, which is exactly the lever --self-test uses to point at a fixture SSOT.
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"
# shellcheck source=/dev/null
hl_source_lib "${BASH_SOURCE[0]}" pi-seat.sh    # pin(), hl_seat_plane_scope, hl_path_persist, hl_path_resolved

PLANE_ID="lsp-binaries"
VERSIONS="${VERSIONS:-$REPO/IaC/ansible/group_vars/all/versions.yml}"
LSP_ROOT="${LSP_ROOT:-$HOME/.local}"
LOCAL_BIN="$LSP_ROOT/bin"
NPM="${LSP_NPM:-npm}"
DOTNET="${LSP_DOTNET:-dotnet}"
PATH_MARK="# pi-seat lsp binaries (seat-lsp-binaries.sh)"
MODE="check"; STRICT=0; KEYS=(); NAME=(); CMD=(); VER=(); VIA=()
DOTNET_LIST=""
NM="$LSP_ROOT/lib/node_modules"   # the record root; set_roots moves it on a win11 seat

err()  { printf 'seat-lsp-binaries: %s\n' "$*" >&2; }
stop() { printf 'FATAL: %s\n' "$*" >&2; exit 2; }
usage() { sed -n '/^# USAGE/,/^# Env/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# --- the set, DISCOVERED from the pins so that adding a row is the only act that adds a server ----
read_set() {
  local k
  [ -r "$VERSIONS" ] || stop "no version SSOT at $VERSIONS (§7)"
  for k in $(sed -nE 's/^lsp_bin_([a-z0-9_]+)_cmd:.*/\1/p' "$VERSIONS" | sort); do
    local n="" c="" v="" w=""
    # Four reads, no fallbacks: `pin()` owns the §7 verdict and EXITS with its own FATAL when a key is
    # missing, so there is nothing for this script to add — and an `|| stop` after a pin is a line that
    # can never run, which is worse than no line at all.
    pin n "lsp_bin_${k}_name"
    pin c "lsp_bin_${k}_cmd"
    pin v "lsp_bin_${k}_version"
    pin w "lsp_bin_${k}_via"
    case "$w" in npm|npm-lib|astral|dotnet) ;; *) stop "lsp_bin_${k}_via: unknown installer '$w' — a reader that guesses an installer is worse than one that stops" ;; esac
    KEYS+=("$k"); NAME+=("$n"); CMD+=("$c"); VER+=("$v"); VIA+=("$w")
  done
  [ "${#KEYS[@]}" -gt 0 ] || stop "no lsp_bin_* rows in $VERSIONS — an empty set is not a set that is satisfied"
}

# --- where the records live, which is a SEAT fact and not a constant -----------------------------
# set_roots resolves the npm record root for the seat this box is. A Debian seat keeps the layout the
# installer writes; win11 gets it from the node an interactive shell resolves, so a Volta upgrade moves
# the root with the seat instead of leaving the plane behind.
set_roots() {
  local _n=""
  NM="$LSP_ROOT/lib/node_modules"
  [ "${SEAT:-}" = win11 ] || return 0
  _n="$(hl_path_resolved node)" || _n=""
  [ -n "$_n" ] || stop "win11: no node resolves for an interactive shell, so the image holding this seat's npm globals cannot be located - a plane that guesses that path calls every server MISSING"
  NM="${_n%/*}/node_modules"
  [ -d "$NM" ] || stop "win11: node resolves to $_n with no node_modules beside it - that is not a global npm layout this plane can read"
}

# --- one probe per `via`, and a dead probe is never read as absent --------------------------------
ver_read() { # ver_read <i> — prints "<version>|<detail>", rc 0 read · 1 absent · 2 probe died
  local i="$1" pkg="${NAME[$i]}" cmd="${CMD[$i]}" via="${VIA[$i]}" f out="" rc=0 dt=""
  case "$via" in
    npm|npm-lib)
      f="$NM/$pkg/package.json"
      [ -r "$f" ] || return 1
      # Not anchored and not layout-dependent: a probe that depends on how npm happened to wrap the
      # file is a probe that reports "absent" for an installed server.
      out="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$f" | head -1)"
      [ -n "$out" ] || return 2
      if [ "$via" = npm-lib ] && [ ! -f "$NM/$pkg/lib/tsserver.js" ]; then
        printf '%s|no lib/tsserver.js' "$out"; return 0
      fi
      printf '%s|' "$out"; return 0 ;;
    dotnet)
      # A name this process resolves needs no asking; a name it does not is looked up the way a session
      # would look it up. Executing a name that is not there is what turns one seat's wrapper into a
      # permanent NO-PROBE, and that happened on the cockpit seat.
      if command -v "$DOTNET" >/dev/null 2>&1; then dt="$DOTNET"
      else dt="$(hl_path_resolved "${DOTNET##*/}")" || dt=""; fi
      [ -n "$dt" ] || dt="$DOTNET"
      if [ -z "$DOTNET_LIST" ]; then
        DOTNET_LIST="$("$dt" tool list -g 2>/dev/null)" || return 2
      fi
      out="$(printf '%s\n' "$DOTNET_LIST" | awk -v p="$pkg" '$1 == p { print $2; exit }')"
      [ -n "$out" ] || return 1
      printf '%s|' "$out"; return 0 ;;
    astral)
      # The astral installer lands a STANDALONE binary in ~/.local/bin, so that file is what is
      # asked; resolving through this process's PATH would ask a different question than the seat's.
      # A .exe is the same answer on a Windows seat, where that is the only spelling that exists.
      f="$LOCAL_BIN/$cmd"
      [ -x "$f" ] || f="$LOCAL_BIN/$cmd.exe"
      [ -x "$f" ] || return 1
      out="$("$f" --version 2>&1)" || rc=$?
      [ "$rc" = 0 ] || return 2
      # grep -oE and not a sed group: `.*([0-9]+\.[0-9]+).*` is greedy and reads "ruff 0.17.3" as "7.3",
      # which would report every astral server as off-pin.
      out="$(printf '%s' "$out" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
      [ -n "$out" ] || return 2
      printf '%s|' "$out"; return 0 ;;
  esac
  return 2
}

# --- the assess: one path for --check and for the read-back after --push --------------------------
assess() {
  local i got ver detail res worst="" why=""
  RES=(); WORST=()
  for i in "${!KEYS[@]}"; do
    got=""; detail=""; RES+=("")
    got="$(ver_read "$i")"; local rc=$?
    case "$rc" in
      1) RES[$i]="MISSING"; continue ;;
      2) RES[$i]="NO-PROBE"; continue ;;
    esac
    detail="${got#*|}"; got="${got%%|*}"
    if [ -n "$detail" ]; then RES[$i]="DRIFT(broken-lib)"; continue; fi
    if [ "$got" != "${VER[$i]}" ]; then RES[$i]="DRIFT(version) ${got}"; continue; fi
    if [ "${VIA[$i]}" = npm-lib ]; then RES[$i]="OK"; continue; fi   # a library, not a command
    res="$(hl_path_resolved "${CMD[$i]}")"; rc=$?
    # A win11 `.NET global tool` is a `.cmd`, and MSYS `command -v` tries `.exe` but NOT `.cmd`: the bare
    # name has no answer there even though the tool is installed and answers `initialize` when spawned
    # the way a session spawns it (through a shell, which does honour PATHEXT). Measured on the win11
    # seat, where the plane called a working C# server invisible. Ask the extension the way that seat's
    # own shell would before calling an installed server invisible — and only there: on a Debian seat a
    # bare name that does not resolve IS the invisible seat, and a `.cmd` guess would hide it.
    if [ $rc -ne 0 ] || [ -z "$res" ]; then
      [ "${SEAT:-}" = win11 ] || { RES[$i]="DRIFT(invisible)"; continue; }
      res="$(hl_path_resolved "${CMD[$i]}.cmd")" || res=""
      [ -n "$res" ] || { RES[$i]="DRIFT(invisible)"; continue; }
    fi
    case "$res" in /mnt/c/*|/mnt/C/*) RES[$i]="DRIFT(shadowed) $res"; continue ;; esac
    RES[$i]="OK"
  done
  for i in "${!KEYS[@]}"; do
    [ "${RES[$i]}" = OK ] || worst="${RES[$i]}"
  done
  VERDICT="${worst:-OK}"
  if printf '%s\n' "${RES[@]}" | grep -q '^NO-PROBE$'; then VERDICT="NO-PROBE"; fi
}

say_read() {
  local i
  printf 'read: seat=%s root=%s bin=%s on PATH for an interactive shell: %s\n' \
    "${SEAT:-?}" "$LSP_ROOT" "$LOCAL_BIN" \
    "$([ -n "$(hl_path_resolved "${CMD[0]}")" ] && echo yes || echo unknown)"
  for i in "${!KEYS[@]}"; do
    printf '  %-26s want %-16s via %-8s %s\n' "${CMD[$i]}" "${VER[$i]}" "${VIA[$i]}" "${RES[$i]}"
  done
}

do_check() {
  hl_seat_plane_scope "$PLANE_ID"; local rc=$?
  case "$rc:$SCOPE" in
    2:*) stop "the plane registry at $(hl_seat_registry_path) cannot be read — the leg cannot tell whether this box owes language servers, and an install run on that guess writes into a HOME nobody audited" ;;
    1:*) hl_seat_skip_line "$PLANE_ID" "no language-server set"; return 2 ;;
  esac
  set_roots
  assess
  say_read
  if [ "$VERDICT" = NO-PROBE ]; then stop "a version probe died rather than answered — an unread version is not evidence of a missing server"; fi
  if [ "$VERDICT" = OK ]; then printf 'OK: %s language servers at the pin and visible to a session\n' "${#KEYS[@]}"; return 0; fi
  printf '%s: the seat does not match the %s pins\n' "$VERDICT" "$PLANE_ID"
  [ "$STRICT" -eq 1 ] && return 1
  return 0
}

install_one() { # install_one <i> — the installer for one `via`; rc 0 when the command ran
  local i="$1" pkg="${NAME[$i]}" v="${VER[$i]}" via="${VIA[$i]}"
  if [ "${SEAT:-}" = win11 ]; then
    printf '  NO-INSTALLER win11 for %s - this plane reads the Volta image and the .NET tool store, it does not write either\n' "$pkg"
    return 1
  fi
  case "$via" in
    npm|npm-lib) command -v "$NPM" >/dev/null 2>&1 || { printf '  NO-INSTALLER npm for %s\n' "$pkg"; return 1; }
      "$NPM" --prefix "$LSP_ROOT" install -g "$pkg@$v" >/dev/null 2>&1 ;;
    astral)
      # LSP_ASTRAL_FETCH replaces the network fetch wholesale — the self-test must never reach the
      # network, and a test that downloads a tool is not a test of this script.
      if [ -n "${LSP_ASTRAL_FETCH:-}" ]; then
        LSP_PKG="$pkg" sh -c "$LSP_ASTRAL_FETCH" 2>/dev/null | LOCAL_BIN="$LOCAL_BIN" sh -s -- "--version$v" >/dev/null 2>&1
        return $?
      fi
      command -v curl >/dev/null 2>&1 || { printf '  NO-INSTALLER curl for %s\n' "$pkg"; return 1; }
      LSP_PKG="$pkg" curl -LsSf "https://astral.sh/$pkg/install.sh" 2>/dev/null | LOCAL_BIN="$LOCAL_BIN" sh -s -- "--version$v" >/dev/null 2>&1 ;;
    dotnet)  command -v "$DOTNET" >/dev/null 2>&1 || { printf '  NO-INSTALLER dotnet for %s\n' "$pkg"; return 1; }
      DOTNET_LIST="" "$DOTNET" tool install -g "$pkg" --version "$v" --prerelease >/dev/null 2>&1 ;;
  esac
}

do_push() {
  hl_seat_plane_scope "$PLANE_ID"; local rc=$?
  case "$rc:$SCOPE" in
    2:*) stop "the plane registry at $(hl_seat_registry_path) cannot be read — nothing was written" ;;
    1:*) hl_seat_skip_line "$PLANE_ID" "no language-server set"; return 2 ;;
  esac
  # The PATH block FIRST: installing into a directory a session cannot see produces a seat that is
  # correct and still answers "server skipped". On win11 there is no such block to write: that seat's
  # PATH comes from the Windows profile and the Volta bin dir, so exporting ~/.local/bin there would
  # put a directory holding nothing relevant in front of the entries that are.
  if [ "${SEAT:-}" = win11 ]; then
    printf 'path: win11 resolves its servers through the Windows PATH, so no ~/.local/bin export is written here\n'
  else
    hl_path_persist "$PATH_MARK" "$LOCAL_BIN" || stop "cannot write the PATH block into the seat's startup files"
    [ "${HL_PATH_WROTE:-0}" = 1 ] && printf 'path: persisted %s under this plane'"'"'s mark\n' "$LOCAL_BIN"
    [ "${HL_PATH_WROTE:-0}" = 0 ] && [ "${HL_PATH_ADOPTED:-0}" = 1 ] && \
      printf 'path: adopted the export of %s that was already there - no block written\n' "$LOCAL_BIN"
  fi
  set_roots
  assess
  local i n=0
  for i in "${!KEYS[@]}"; do
    [ "${RES[$i]}" = OK ] && continue
    printf 'install: %s (%s) — was %s\n' "${NAME[$i]}" "${VER[$i]}" "${RES[$i]}"
    install_one "$i" || n=$((n+1))
  done
  assess; say_read
  if [ "$VERDICT" = OK ]; then printf 'OK: re-proved after the push — %s servers at the pin and visible\n' "${#KEYS[@]}"; return 0; fi
  printf '%s: after the push\n' "$VERDICT"
  [ "$n" -gt 0 ] && printf '  (%s installer(s) reported failure — the verdict above is the seat, not the installer)\n' "$n"
  return 1
}

do_list() {
  local i
  read_set
  printf 'lsp-binaries: %s entries, from %s\n' "${#KEYS[@]}" "$VERSIONS"
  for i in "${!KEYS[@]}"; do printf '  %-26s %s  (package %s, via %s)\n' "${CMD[$i]}" "${VER[$i]}" "${NAME[$i]}" "${VIA[$i]}"; done
}

# --- self-test: stubbed installers, stubbed shell, fixture pins -----------------------------------
self_test() {
  local t fails=0 i
  t="$(mktemp -d)" || { err "mktemp failed"; return 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$t'" RETURN
  mkdir -p "$t/root/bin" "$t/repo/IaC/ansible/group_vars/all" "$t/bin"
  cat > "$t/repo/IaC/ansible/group_vars/all/versions.yml" <<'EOS'
lsp_bin_bash_name: "bash-language-server"
lsp_bin_bash_cmd: "bash-language-server"
lsp_bin_bash_version: "5.8.1"
lsp_bin_bash_via: "npm"
lsp_bin_ruff_name: "ruff"
lsp_bin_ruff_cmd: "ruff"
lsp_bin_ruff_version: "0.17.3"
lsp_bin_ruff_via: "astral"
lsp_bin_roslyn_name: "roslyn-language-server"
lsp_bin_roslyn_cmd: "roslyn-language-server"
lsp_bin_roslyn_version: "5.13.0-1.26514.10"
lsp_bin_roslyn_via: "dotnet"
lsp_bin_tsserver_name: "typescript"
lsp_bin_tsserver_cmd: "tsserver"
lsp_bin_tsserver_version: "6.0.3"
lsp_bin_tsserver_via: "npm-lib"
EOS
  # npm/dotnet shims that install what they are told, into the fixture tree, and RECORD every call.
  cat > "$t/bin/npm" <<'EOS'
#!/bin/sh
# argv is `npm --prefix DIR install -g NAME@VERSION`, so the package is the argument that carries @.
echo "npm $*" >> "$ST_LOG"
spec=""
for a in "$@"; do case "$a" in *@*) spec="$a" ;; esac; done
pkg="${spec%@*}"; ver="${spec##*@}"
d="$PREFIX/lib/node_modules/$pkg"; mkdir -p "$d"
printf '{\n  "name": "%s",\n  "version": "%s"\n}\n' "$pkg" "$ver" > "$d/package.json"
exit 0
EOS
  cat > "$t/bin/dotnet" <<'EOS'
#!/bin/sh
if [ "$1" = "tool" ] && [ "$2" = "list" ]; then cat "$ST_TOOLS" 2>/dev/null; exit 0; fi
echo "dotnet $*" >> "$ST_LOG"
pkg=""; ver=""
while [ $# -gt 0 ]; do
  case "$1" in
    --version) ver="$2"; shift ;;
    tool|install|-g|--prerelease) ;;
    *) [ -z "$pkg" ] && pkg="$1" ;;
  esac
  shift
done
printf '%s %s %s
' "$pkg" "$ver" "$pkg" >> "$ST_TOOLS"
exit 0
EOS
  # The astral installer lands a STANDALONE binary in ~/.local/bin, so the stub goes
  # there and not onto PATH: the probe asks that file, the same question the seat answers.
  cat > "$t/root/bin/ruff" <<'EOS'
#!/bin/sh
printf 'ruff %s
' "$ST_RUFF_VER"
exit 0
EOS
  chmod +x "$t/bin/npm" "$t/bin/dotnet" "$t/root/bin/ruff"
  cat > "$t/bin/fetch" <<'EOS'
#!/bin/sh
# Stands in for `curl -LsSf https://astral.sh/<pkg>/install.sh`: it prints an installer that installs
# the version it is handed into $LOCAL_BIN/$LSP_PKG. The self-test must never reach the network.
echo "fetch $*" >> "$ST_LOG"
cat <<'OUT'
#!/bin/sh
v="${1#--version}"
d="$LOCAL_BIN/$LSP_PKG"
{
  echo '#!/bin/sh'
  printf "printf 'v %s\\\\n' '%s'\n" "$v"
} > "$d"
chmod +x "$d"
OUT
EOS
  chmod +x "$t/bin/fetch"
  # the interactive-shell probe: resolves commands from a file the arms edit, so "invisible" and
  # "shadowed" are states an arm can plant without owning a shell.
  cat > "$t/bin/probe" <<'EOS'
#!/bin/sh
# An interactive shell's resolution. An explicit answer wins (that is how an arm plants "shadowed");
# otherwise the answer follows the seat's startup file, so a PATH block that has not been written
# really does produce "nothing resolves here" — the state this whole plane exists to catch.
if [ -f "$ST_RESOLVE" ] && grep -q "^$1=" "$ST_RESOLVE" 2>/dev/null; then
  grep -m1 "^$1=" "$ST_RESOLVE" | cut -d= -f2-
  exit 0
fi
if [ -f "$HOME/.bashrc" ] && grep -q 'lsp binaries\|HOME/\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  printf '%s/bin/%s\n' "$LSP_ROOT" "$1"
  exit 0
fi
exit 1
EOS
  chmod +x "$t/bin/probe"
  : > "$t/log"; : > "$t/tools"; : > "$t/resolve"
  mkdir -p "$t/root/lib/node_modules/bash-language-server"
  printf '{
  "version": "5.8.1"
}
' > "$t/root/lib/node_modules/bash-language-server/package.json"
  mkdir -p "$t/root/lib/node_modules/typescript/lib"
  printf '{
  "version": "6.0.3"
}
' > "$t/root/lib/node_modules/typescript/package.json"
  : > "$t/root/lib/node_modules/typescript/lib/tsserver.js"
  printf 'roslyn-language-server 5.13.0-1.26514.10 roslyn-language-server\n' > "$t/tools"
  ST_RUFF_VER=0.17.3; export ST_RUFF_VER
  PATH_OK="/home/d/.local/bin"
  printf 'bash-language-server=%s/bash-language-server\nruff=%s/ruff\nroslyn-language-server=%s/roslyn-language-server\n' "$PATH_OK" "$PATH_OK" "$PATH_OK" > "$t/resolve"

  run() { # run <expect-rc> <args...> — the REAL CLI, under the fixture environment
    local want="$1"; shift
    PI_SEAT="${PS:-wsl}" VERSIONS="$t/repo/IaC/ansible/group_vars/all/versions.yml" \
    LSP_ROOT="${LSPROOT:-$t/root}" LSP_NPM="$t/bin/npm" LSP_DOTNET="${LSPDOT:-$t/bin/dotnet}" HL_SHELL_PROBE="$t/bin/probe" \
    LSP_ASTRAL_FETCH="$t/bin/fetch" \
    ST_LOG="$t/log" ST_TOOLS="$t/tools" ST_RESOLVE="$t/resolve" PREFIX="$t/root" \
    PATH="$t/bin:$PATH" HOME="$t/home" bash "${BASH_SOURCE[0]}" "$@" > "$t/out" 2>&1
    local got=$?
    if [ "$got" = "$want" ]; then printf 'ok   rc %s  %s\n' "$got" "$*"
    else printf 'NOT CAUGHT  wanted rc %s, got %s  [%s]\n' "$want" "$got" "$(sed -e 's/^/      /' "$t/out" | tr '\n' '|')"; fails=$((fails+1)); fi
  }
  export HOME="$t/home"; mkdir -p "$HOME"; printf '# existing\n' > "$HOME/.bashrc"

  # 1. every entry at the pin and resolvable → OK, rc 0.
  run 0 --check --strict
  grep -q '^OK:' "$t/out" || { printf 'NOT CAUGHT the satisfied case printed no OK line\n'; fails=$((fails+1)); }

  # 2. an installed version off its pin reddens, and --push installs it and RE-PROVES it.
  printf '{
  "version": "9.9.9"
}
' > "$t/root/lib/node_modules/bash-language-server/package.json"
  run 1 --check --strict
  grep -q 'DRIFT(version) 9.9.9' "$t/out" || { printf 'NOT CAUGHT a wrong version stayed green\n'; fails=$((fails+1)); }
  run 0 --push
  grep -q "bash-language-server@5.8.1" "$t/log" || { printf 'NOT CAUGHT --push never ran the npm installer\n'; fails=$((fails+1)); }

  # 3. absent (no package.json at all) is MISSING, not a silent pass.
  rm -rf "$t/root/lib/node_modules/bash-language-server"
  run 1 --check --strict
  grep -q 'MISSING' "$t/out" || { printf 'NOT CAUGHT an absent server was not MISSING\n'; fails=$((fails+1)); }
  run 0 --push
  # 4. installed and pinned but INVISIBLE: the ~/.local/bin export is missing from the shell a
  #    session reads. This is the seat that answers "no server on PATH" while carrying all of them.
  #    The PATH line is removed here, not just the resolve answers: an earlier arm's --push put it
  #    there, and a fixture that still carries it is testing a different seat than the one described.
  : > "$t/resolve"; printf '# existing\n' > "$HOME/.bashrc"
  mkdir -p "$t/root/lib/node_modules/bash-language-server"
  printf '{
  "version": "5.8.1"
}
' > "$t/root/lib/node_modules/bash-language-server/package.json"
  run 1 --check --strict
  grep -q 'DRIFT(invisible)' "$t/out" || { printf 'NOT CAUGHT an invisible server stayed green\n'; fails=$((fails+1)); }
  run 0 --push
  grep -q 'lsp binaries (seat-lsp-binaries.sh)' "$HOME/.bashrc" \
    || { printf 'NOT CAUGHT --push did not persist the PATH block\n'; fails=$((fails+1)); }

  # 5. shadowed by the Windows copy across /mnt/c: the seat resolves, but to something that answers
  #    nothing. PATH order is the fact, so it has to be the verdict.
  printf 'bash-language-server=/mnt/c/Users/d/.local/bin/bash-language-server\nruff=%s/ruff\nroslyn-language-server=%s/roslyn-language-server\n' "$PATH_OK" "$PATH_OK" > "$t/resolve"
  run 1 --check --strict
  grep -q 'DRIFT(shadowed)' "$t/out" || { printf 'NOT CAUGHT a /mnt/c shadow went unnoticed\n'; fails=$((fails+1)); }

  # 6. the typescript@7 shape: installed, pinned-looking, and unusable because lib/tsserver.js is
  #    not there. `initialize` fails on a server that is otherwise 'ready'.
  printf '{
  "version": "6.0.3"
}
' > "$t/root/lib/node_modules/typescript/package.json"
  rm -f "$t/root/lib/node_modules/typescript/lib/tsserver.js"
  run 1 --check --strict
  grep -q 'DRIFT(broken-lib)' "$t/out" || { printf 'NOT CAUGHT a typescript package without tsserver.js stayed green\n'; fails=$((fails+1)); }
  : > "$t/root/lib/node_modules/typescript/lib/tsserver.js"
  printf 'bash-language-server=%s/bash-language-server\nruff=%s/ruff\nroslyn-language-server=%s/roslyn-language-server\n' "$PATH_OK" "$PATH_OK" "$PATH_OK" > "$t/resolve"

  # 7. a dotnet entry installed at another version reddens from `tool list`, without running the
  #    apphost (which needs DOTNET_ROOT on a seat whose runtime is a home prefix).
  printf 'roslyn-language-server 1.2.3 roslyn-language-server\n' > "$t/tools"
  run 1 --check --strict
  grep -q 'DRIFT(version) 1.2.3' "$t/out" || { printf 'NOT CAUGHT a dotnet tool off-pin stayed green\n'; fails=$((fails+1)); }
  printf 'roslyn-language-server 5.13.0-1.26514.10 roslyn-language-server\n' > "$t/tools"

  # 8. an absent pin and an unknown `via` both stop the run — the pin half with the LIB's rc 1 FATAL
  #    (pin() exits, it does not return: a script that reinterpreted that into its own rc would hide
  #    §7 behind a nicer number), the `via` half with rc 2, because a script that guesses an installer
  #    installs something nobody pinned.
  # 8a. an absent pin: pin() EXITS 1 with its own §7 FATAL, and that rc belongs to the lib, not here.
  sed -E 's/^lsp_bin_ruff_version:.*/# removed/' "$t/repo/IaC/ansible/group_vars/all/versions.yml" > "$t/v2.yml"
  VERSIONS="$t/v2.yml" LSP_ROOT="$t/root" LSP_NPM="$t/bin/npm" LSP_DOTNET="$t/bin/dotnet" PI_SEAT=wsl \
    HL_SHELL_PROBE="$t/bin/probe" ST_RESOLVE="$t/resolve" bash "${BASH_SOURCE[0]}" --check --strict > "$t/out" 2>&1
  _rc=$?
  { [ "$_rc" = 1 ] || [ "$_rc" = 2 ]; } && grep -q 'missing from' "$t/out" \
    || { printf 'NOT CAUGHT a missing pin did not stop the run (rc %s)\n' "$_rc"; fails=$((fails+1)); }
  sed -E 's/^lsp_bin_ruff_via:.*/lsp_bin_ruff_via: "carrier-pigeon"/' "$t/repo/IaC/ansible/group_vars/all/versions.yml" > "$t/v3.yml"
  VERSIONS="$t/v3.yml" LSP_ROOT="$t/root" PI_SEAT=wsl bash "${BASH_SOURCE[0]}" --check --strict > "$t/out" 2>&1
  [ $? -eq 2 ] && grep -qi 'unknown installer' "$t/out" || { printf 'NOT CAUGHT an unknown via was accepted\n'; fails=$((fails+1)); }

  # 9. a box the row does not name answers SKIP at rc 2 and installs NOTHING. (win11 is NOT this arm
  #    any more: the row names it now, and arm 13 is what proves what it answers there.)
  rm -f "$t/log"; PS=aboxnobodycallsaseat run 2 --push
  [ -s "$t/log" ] && { printf 'NOT CAUGHT --push installed packages off-scope\n'; fails=$((fails+1)); }
  grep -q '^SKIP: aboxnobodycallsaseat' "$t/out" || { printf 'NOT CAUGHT an off-scope box did not answer SKIP\n'; fails=$((fails+1)); }

  # 10. a version probe that DIES is rc 2 with a FATAL, never MISSING. The seat this catches is a
  #     half-finished npm install: `package.json` exists and carries no `version`, so a reader that
  #     calls an unread version "absent" would `--push` a reinstall at a seat whose server is already
  #     on disk, and `--check` would answer green at a seat that has nothing installed. A branch nobody
  #     plants is a branch nobody tests, so the state is planted here rather than trusted.
  mkdir -p "$t/root/lib/node_modules/bash-language-server"
  printf '{\n  "name": "bash-language-server"\n}\n' > "$t/root/lib/node_modules/bash-language-server/package.json"
  run 2 --check --strict
  grep -qi 'probe died' "$t/out" \
    || { printf 'NOT CAUGHT a dead version probe did not stop the run\n'; fails=$((fails+1)); }
  grep -q 'NO-PROBE' "$t/out" \
    || { printf 'NOT CAUGHT a dead version probe was read as MISSING\n'; fails=$((fails+1)); }
  printf '{\n  "version": "5.8.1"\n}\n' > "$t/root/lib/node_modules/bash-language-server/package.json"

  # 11. the dotnet read is an EXACT row match in `tool list -g`, and it never runs the apphost.
  #     One fixture proves both halves: a tool whose name CONTAINS this one's sorts ahead of it, so a
  #     substring read returns 9.9.9 for a tool that is at the pin; and the apphost planted here is
  #     the probe that reports a working seat as broken on a box whose .NET runtime lives in a
  #     ~/.dotnet prefix (the `DOTNET_ROOT` trap), so the plane must read the record and exec nothing.
  printf 'roslyn-language-server-classic 9.9.9 roslyn-language-server-classic\nroslyn-language-server 5.13.0-1.26514.10 roslyn-language-server\n' > "$t/tools"
  : > "$t/trap"; ST_TRAP="$t/trap"; export ST_TRAP
  printf '#!/bin/sh\necho ran-apphost >> "$ST_TRAP"\nprintf "roslyn-language-server 0.0.0\\n"\n' > "$t/root/bin/roslyn-language-server"
  chmod +x "$t/root/bin/roslyn-language-server"
  run 0 --check --strict
  if grep -q 'ran-apphost' "$t/trap"; then
    printf 'NOT CAUGHT the plane ran the dotnet apphost to read a version\n'; fails=$((fails+1))
  fi
  printf 'roslyn-language-server 5.13.0-1.26514.10 roslyn-language-server\n' > "$t/tools"
  rm -f "$t/root/bin/roslyn-language-server"

  # 12. the dotnet read uses the SAME interactive shell as the visibility read when the plain name is
  #     not resolvable. On the cockpit seat the only dotnet is a ~/.local/bin wrapper that a
  #     non-interactive shell never sees, so a plane that execs the bare name reads NO-PROBE forever on
  #     a box whose tool is at the pin. LSPDOT points the plane at a name nothing resolves directly.
  printf '#!/bin/sh\nif [ "$1" = tool ] && [ "$2" = list ]; then printf "roslyn-language-server 1.2.3 roslyn-language-server\\n"; exit 0; fi\nexit 0\n' > "$t/bin/dotnet-i"
  chmod +x "$t/bin/dotnet-i"
  { printf 'dotnet-absent=%s/bin/dotnet-i\n' "$t"; cat "$t/resolve"; } > "$t/resolve2" && mv "$t/resolve2" "$t/resolve"
  LSPDOT=dotnet-absent run 1 --check --strict
  grep -q 'DRIFT(version) 1.2.3' "$t/out" \
    || { printf 'NOT CAUGHT a dotnet carrier reachable only through an interactive shell was never read\n'; fails=$((fails+1)); }
  printf 'bash-language-server=%s/bash-language-server\nruff=%s/ruff\nroslyn-language-server=%s/roslyn-language-server\n' "$PATH_OK" "$PATH_OK" "$PATH_OK" > "$t/resolve"

  # 13. win11 is IN SCOPE: the row names it, so the answer there is a verdict and not a SKIP. The set is
  #     read from the node image that seat's node actually resolves (a Volta layout: the shims and
  #     node_modules sit beside node.exe), and a push there WRITES NOTHING while still naming what is
  #     short. Both halves matter: a SKIP would hide a short seat, and a push that installed into the
  #     image would make this plane the owner of somebody else's tree.
  mkdir -p "$t/volta/node/1.2.3/node_modules/bash-language-server" "$t/volta/node/1.2.3/node_modules/yaml-language-server"
  : > "$t/volta/node/1.2.3/node"
  printf '{\n  "version": "5.8.1"\n}\n' > "$t/volta/node/1.2.3/node_modules/bash-language-server/package.json"
  printf '{\n  "version": "2.0.0"\n}\n' > "$t/volta/node/1.2.3/node_modules/yaml-language-server/package.json"
  printf 'node=%s/volta/node/1.2.3/node\nbash-language-server=%s/volta/node/1.2.3/bash-language-server\nyaml-language-server=%s/volta/node/1.2.3/yaml-language-server\nruff=%s/ruff\nroslyn-language-server=%s/win-tools/roslyn-language-server.cmd\n' "$t" "$t" "$t" "$PATH_OK" "$t" > "$t/resolve"
  rm -f "$t/log"
  PS=win11 run 1 --check --strict
  grep -q '^SKIP' "$t/out" && { printf 'NOT CAUGHT win11 answered SKIP after the row took it in\n'; fails=$((fails+1)); }
  grep -q 'MISSING' "$t/out" || { printf 'NOT CAUGHT the Volta image was not read (a short win11 set answered OK)\n'; fails=$((fails+1)); }
  grep -q 'bash-language-server.*OK' "$t/out" || { printf 'NOT CAUGHT a server present in the Volta image was not OK\n'; fails=$((fails+1)); }
  printf '# existing\n' > "$HOME/.bashrc"
  PS=win11 run 1 --push
  [ -s "$t/log" ] && { printf 'NOT CAUGHT a win11 push wrote into the seat image\n'; fails=$((fails+1)); }
  grep -q 'lsp binaries (seat-lsp-binaries.sh)' "$HOME/.bashrc" \
    && { printf 'NOT CAUGHT a win11 push wrote a ~/.local/bin export that seat does not use\n'; fails=$((fails+1)); }
  grep -q 'NO-INSTALLER win11' "$t/out" || { printf 'NOT CAUGHT a win11 push did not say it writes nothing\n'; fails=$((fails+1)); }

  # 14. the win11 `.cmd` half of that seat's read: a .NET global tool there is `roslyn-language-server.cmd`,
  #     and MSYS `command -v` will not resolve the BARE name to it — so the answers file carries only the
  #     `.cmd` spelling, exactly as the seat does. A plane that asks the bare name alone reports a tool
  #     that is installed, at pin, and answers `initialize` as DRIFT(invisible).
  printf 'node=%s/volta/node/1.2.3/node\nbash-language-server=%s/volta/node/1.2.3/bash-language-server\nyaml-language-server=%s/volta/node/1.2.3/yaml-language-server\nruff=%s/ruff\nroslyn-language-server.cmd=%s/win-tools/roslyn-language-server.cmd\n' "$t" "$t" "$t" "$PATH_OK" "$t" > "$t/resolve"
  PS=win11 run 1 --check --strict
  grep -q 'roslyn-language-server .*invisible' "$t/out" \
    && { printf 'NOT CAUGHT a win11 .cmd-only carrier was called invisible\n'; fails=$((fails+1)); }
  grep -q 'roslyn-language-server.*OK' "$t/out" \
    || { printf 'NOT CAUGHT the .cmd spelling was never asked (roslyn answered neither OK nor invisible)\n'; fails=$((fails+1)); }

  #     14b. and the fallback is win11's, not universal. On a Debian seat a bare name that does not
  #          resolve IS the invisible seat (arm 4), so a `.cmd` answer sitting in the same file must NOT
  #          rescue it there — a fallback that ignores the seat would hide the seat this verdict exists
  #          to catch, and only this half can tell the two readings apart.
  PS=wsl run 1 --check --strict
  grep -q 'roslyn-language-server .*invisible' "$t/out" \
    || { printf 'NOT CAUGHT a .cmd answer rescued a Debian seat whose bare name does not resolve\n'; fails=$((fails+1)); }
  printf 'bash-language-server=%s/bash-language-server\nruff=%s/ruff\nroslyn-language-server=%s/roslyn-language-server\n' "$PATH_OK" "$PATH_OK" "$PATH_OK" > "$t/resolve"

  # 15. the PATH ADOPT key on this plane's own push: a ~/.bashrc whose operator line spells the directory
  #     "$HOME/.local/bin" exports the SAME directory the plane passes in absolute form, so --push adopts
  #     it and writes NO block. Arm 4 proves the absolute spelling; absolute alone is how a duplicate
  #     block passed as converged on both Debian seats.
  PS=wsl; mkdir -p "$t/home/.local/bin"
  printf '# existing\nexport PATH="$HOME/.local/bin:$PATH"\n' > "$HOME/.bashrc"
  LSPROOT="$t/home/.local" run 1 --push
  grep -q 'path: adopted the export' "$t/out" \
    || { printf 'NOT CAUGHT --push did not report adopting a $HOME-spelled export\n'; fails=$((fails+1)); }
  [ "$(grep -c 'lsp binaries (seat-lsp-binaries.sh)' "$HOME/.bashrc")" = 0 ] \
    || { printf 'NOT CAUGHT a $HOME-spelled export still received a second marked block\n'; fails=$((fails+1)); }
  [ "$(wc -l < "$HOME/.bashrc")" = 2 ] \
    || { printf 'NOT CAUGHT the adopt case grew the startup file (%s lines)\n' "$(wc -l < "$HOME/.bashrc")"; fails=$((fails+1)); }
  printf '# existing\n' > "$HOME/.bashrc"

  printf '\nself-test: %s\n' "$([ "$fails" -eq 0 ] && echo "OK — all canaries caught" || echo "$fails canary/canaries NOT caught")"
  return "$fails"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) MODE="check" ;;
    --strict) STRICT=1 ;;
    --push)  MODE="push" ;;
    --list)  MODE="list" ;;
    --self-test) MODE="selftest" ;;
    --help|-h) usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

case "$MODE" in
  check) read_set; do_check ;;
  push)  read_set; do_push ;;
  list)  do_list ;;
  selftest) self_test ;;
esac
