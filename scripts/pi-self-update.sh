#!/usr/bin/env bash
# =====================================================================
# pi-self-update.sh — the pi BUILD each seat runs is a pinned artifact, and this
#                     script is what keeps the running binary equal to the pin.  (HD-1115)
#
# WHY THIS IS A PLANE AND NOT A SENTENCE
# --------------------------------------
# Until 2026-10-08 the Windows half of "update pi" was a line of prose in
# readme-humans.md, and before that it was the root `update_pi.cmd` running an unpinned
# `volta install @earendil-works/pi-coding-agent` (HD-1112 deleted it). What that left
# behind is the reason this file exists: the Win11 seat was RUNNING pi 1.1.0 while
# `pi_host_npm_version` said 1.0.3, and not one of the other planes could see it — every
# other plane compares files, and the binary was the one harness artifact with no gate.
# A pi release changes what the harness IS (1.1.0 added the host-provided-package check
# that produced HD-1111's start-up panel), so "which build" is exactly as much a seat
# invariant as "which extensions".
#
# Two opposite shapes, and the second is the one that hides:
#   BEHIND — the pin moved, the seat did not. Ordinary drift, converges by installing.
#   AHEAD  — the seat moved past its pin (an unpinned `@latest`, a hand-run `pi update
#            self`, a Volta auto-update). Every file plane stays GREEN while the seat runs
#            a build the repo has never reviewed. This is the class this session found, so
#            AHEAD is DRIFT here, not a warning.
#
# MECHANISM BY PLATFORM (never a third one)
#   Windows (this seat's pi is Volta-managed)  -> volta install <pkg>@<pin>
#   Debian / WSL (pinned standalone node)      -> npm -g <pkg>@<pin> at $PI_NODE_PREFIX
# A host where neither exists is a FAILURE, never a shrug: silently skipping "update the
# thing you run" is how a fleet accumulates six different pis.
#
# THREE LAYOUTS, ONE PROBE (measured on oldsrv 2026-10-09, why the SKIP arm was lying)
#   on PATH      whatever the operator types — a Volta shim on Windows, an npm -g symlink on
#                the pinned Node tarball on Debian/WSL.
#   managed      ~/.pi/agent/bin/pi, pi's OWN launcher over ~/.pi/agent/install/releases/<ver>/.
#                pi 1.1.0's `pi update` migrates a global npm install HERE and removes the
#                node-dir symlink. This probe did not look there, so the seat that ran pi 1.1.0
#                perfectly reported `SKIP — no pi binary answers on this host` with rc 0: the
#                binary plane went blind exactly when a seat moved, the CONVENTIONS §6 class
#                ("a gate that cannot see the file cannot fail either").
#   pinned prefix $PI_NODE_PREFIX/bin/pi — what npm -g writes.
# The layout of the ANSWERING binary picks the installer, so a managed seat is never "converged"
# with an npm -g install that would leave two layouts and a version that depends on PATH order.
#
# MODES
#   --check (default)  OK · BEHIND · AHEAD · NO-PI(SKIP) · NO-INSTALLER. Drift is
#                      report-only unless --strict (same rc contract as the other planes).
#   --check --strict   also exit 1 on drift. Gate use (validate-all.sh).
#   --push             install the pinned build, then RE-PROBE and assert equality —
#                      the install is believed only when the binary says so. An
#                      already-correct seat runs NOTHING (no network, no churn).
#   --self-test        sandboxed canaries on stubbed installers; includes the two arms
#                      people get wrong: "equal means no installer call at all" and
#                      "no installer is a failure, not a pass".
#
# Exit codes: 0 OK / converged · 1 drift(strict), a failed install, no installer, or a
#             missing pin · 2 SKIP — no pi binary answers on this host, so nothing was read.
#
# Env (sandbox hooks only): REPO, PI_SELF_PI (probe binary), PI_SELF_VERSION_FILE (print
# the installed version from a file instead of running pi — the self-test's hook),
# PI_SELF_INSTALLER (volta|npm|managed|stub), PI_SELF_INSTALL_LOG,
# PI_NODE_PREFIX (default $HOME/.local/share/pi-node, the prefix install-pi-debian.sh creates),
# PI_ENTRY_DIR (default $HOME/.pi/agent/bin, pi's own launcher dir — the managed layout).
# Portability: bash + the platform installer; `$HOME`/self-derived paths only.
#
# Owning rule: docs/pi-harness.md §1 (the pin table) · §5 (what the harness is).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
VERSIONS="$REPO/IaC/ansible/group_vars/all/versions.yml"
PI_NODE_PREFIX="${PI_NODE_PREFIX:-$HOME/.local/share/pi-node}"
PI_ENTRY_DIR="${PI_ENTRY_DIR:-$HOME/.pi/agent/bin}"   # pi's own launcher dir (managed layout)

MODE="check"; STRICT=0

err()  { printf 'pi-self-update: %s\n' "$*" >&2; }
info() { printf '  %s\n' "$*"; }

pin() {
  local v
  v="$(grep -E "^${1}:" "$VERSIONS" 2>/dev/null | head -1 | sed -E 's/^[^:]+:[[:space:]]*"?([^"#]*)"?.*/\1/' | tr -d '[:space:]')"
  [ -n "$v" ] || { err "pin '$1' missing from IaC/ansible/group_vars/all/versions.yml — add it there, do not hardcode it here"; exit 1; }
  printf '%s' "$v"
}

usage() {
  cat <<'EOF'
usage: pi-self-update.sh [--check [--strict]] | --push | --self-test

  --check          (default) compare the pi build on this host against pi_host_npm_version
  --check --strict exit 1 on drift too (gate use)
  --push           install the pinned build with the platform's own mechanism, then prove it
  --self-test      sandboxed canaries; nothing is installed anywhere
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)     MODE="check" ;;
    --strict)    STRICT=1 ;;
    --push)      MODE="push" ;;
    --self-test) MODE="selftest" ;;
    --help|-h)   usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

# --- probe: what pi does this host actually run? ------------------------------
# Order matters: a file override (self-test) beats an explicit binary, which beats PATH, which
# beats pi's OWN managed launcher, which beats the pinned prefix. PATH first on purpose - PATH is
# what the operator typed into, and a seat whose PATH pi is NOT the pinned prefix is precisely the
# drift HD-1112 left behind (the Windows Volta shim shadowing the pinned install). The managed
# launcher was missing from this candidate list until 2026-10-09: see THREE LAYOUTS in the header.
pi_candidate() {
  local c
  [ -n "${PI_SELF_PI:-}" ] && { printf '%s' "$PI_SELF_PI"; return 0; }
  # PI_SELF_PROBE_ONLY=1 (the self-test) keeps PATH and both installed dirs OUT of the probe:
  # without it a canary on a host that really runs pi would find that pi and report OK, so the
  # SKIP arm could never be proven on the one machine people run the test on.
  [ -n "${PI_SELF_PROBE_ONLY:-}" ] && return 1
  c="$(command -v pi 2>/dev/null || true)"
  [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  [ -x "$PI_ENTRY_DIR/pi" ] && { printf '%s' "$PI_ENTRY_DIR/pi"; return 0; }
  [ -x "$PI_NODE_PREFIX/bin/pi" ] && { printf '%s' "$PI_NODE_PREFIX/bin/pi"; return 0; }
  return 1
}

installed_version() {
  if [ -n "${PI_SELF_VERSION_FILE:-}" ]; then
    [ -f "$PI_SELF_VERSION_FILE" ] && tr -d '[:space:]"' < "$PI_SELF_VERSION_FILE" && return 0
    return 1
  fi
  # The candidate ORDER lives in pi_candidate(), so installer_kind() asks the same question.
  local b cand
  cand="$(pi_candidate || true)"
  for b in "${cand:-}"; do
    [ -n "$b" ] && [ -x "$b" ] || continue
    local out
    out="$("$b" --version 2>/dev/null | tr -d '[:space:]"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" || true
    [ -n "$out" ] && { printf '%s' "$out"; return 0; }
  done
  return 1
}

installer_kind() {
  [ -n "${PI_SELF_INSTALLER:-}" ] && { printf '%s' "$PI_SELF_INSTALLER"; return 0; }
  # The layout of the ANSWERING binary picks the installer, so a managed seat is never "converged"
  # by an npm -g install that would leave two layouts and a version decided by PATH order.
  local b; b="$(pi_candidate || true)"
  case "$b" in
    "$PI_ENTRY_DIR"/*|*/.pi/agent/bin/pi|*/install/releases/*) printf 'managed'; return 0 ;;
  esac
  case "$(uname -s 2>/dev/null || echo unknown)" in
    MING*|MSYS*|CYGWIN*) command -v volta >/dev/null 2>&1 && { printf 'volta'; return 0; } ;;
  esac
  command -v volta >/dev/null 2>&1 && { printf 'volta'; return 0; }
  PATH="$PI_NODE_PREFIX/bin:$PATH" command -v npm >/dev/null 2>&1 && { printf 'npm'; return 0; }
  printf 'none'; return 1
}

install_pinned() {  # $1 = pkg, $2 = version
  local kind="$3" pkg="$1" v="$2"
  case "$kind" in
    volta) volta install "$pkg@$v" ;;
    npm)   PATH="$PI_NODE_PREFIX/bin:$PATH" npm install -g "$pkg@$v" ;;
    managed)
           err "this pi is pi's OWN managed install (~/.pi/agent/bin + install/releases): 'pi update self' owns that layout and installs the LATEST release, not a version it is handed (the pi.dev installer takes no version either)."
           err "two legal moves, in order: (1) run 'pi update self' on the seat, then move pi_host_npm_version AND pi_dev_npm_version to what it reports (an owner ruling, CONVENTIONS §7); (2) move the seat back onto the pinned layout with 'bash scripts/install-pi-debian.sh --pi-only'."
           err "refusing to npm install -g over a managed install: it leaves TWO layouts and makes 'which pi' a PATH-order question."
           return 1 ;;
    stub)  printf '%s\n' "$pkg@$v" >> "${PI_SELF_INSTALL_LOG:?self-test must set PI_SELF_INSTALL_LOG}";
           [ -n "${PI_SELF_VERSION_FILE:-}" ] && printf '%s\n' "$v" > "$PI_SELF_VERSION_FILE"
           printf 'stub installed %s@%s\n' "$pkg" "$v" ;;
    *)     err "no installer on this host (looked for volta, then npm at $PI_NODE_PREFIX) — refusing to pretend the pi build was updated"; return 1 ;;
  esac
}

do_check() {
  local want got kind
  # `|| exit 1` is load-bearing: pin() runs inside $( ), so its `exit 1` leaves the SCRIPT
  # running with an empty value — the silent-default failure CONVENTIONS §4 forbids, and a
  # self-test canary now holds the behaviour down (arm 5).
  want="$(pin pi_host_npm_version)" || exit 1; PKG="$(pin pi_host_npm_package)" || exit 1
  if ! got="$(installed_version)"; then
    info "pi build:        SKIP — no pi binary answers on this host (looked on PATH, $PI_ENTRY_DIR and $PI_NODE_PREFIX/bin)"
    return 2
  fi
  kind="$(installer_kind)" || kind="none"
  if [ "$got" = "$want" ]; then
    info "pi build:        OK — $got == pi_host_npm_version ($kind would install it)"
    return 0
  fi
  if [ "$(printf '%s\n%s\n' "$got" "$want" | sort -V | head -1)" = "$want" ]; then
    info "pi build:        AHEAD — installed $got, pinned $want: this seat runs a build the repo has not reviewed (an unpinned @latest or a hand-run pi update self)"
  else
    info "pi build:        BEHIND — installed $got, pinned $want"
  fi
  [ "$STRICT" -eq 1 ] && return 1
  return 0
}

do_push() {
  local want got kind
  want="$(pin pi_host_npm_version)" || exit 1; PKG="$(pin pi_host_npm_package)" || exit 1
  if ! got="$(installed_version)"; then
    err "no pi binary answers on this host — refusing to install a build onto a box whose current pi cannot be read (install pi first, then re-run)"
    return 1
  fi
  if [ "$got" = "$want" ]; then
    info "pi build:        already $got, nothing run (no network, no churn)"
    return 0
  fi
  kind="$(installer_kind)" || true
  info "pi build:        installing $PKG@$want (was $got) via $kind"
  install_pinned "$PKG" "$want" "$kind" || { err "the installer failed — the seat still runs $got"; return 1; }
  got="$(installed_version)" || { err "installed, but pi no longer answers on this host"; return 1; }
  [ "$got" = "$want" ] || { err "ran the installer and the binary still says $got, not $want — a PATH/shim problem, NOT a version problem (check what 'command -v pi' resolves to)"; return 1; }
  info "pi build:        converged to $got and PROVEN by re-probing the binary"
  return 0
}

do_selftest() {
  local tmp fails=0 log
  tmp="$(mktemp -d)" || { err "mktemp failed"; return 1; }
  trap 'rm -rf "$tmp"' RETURN
  local vf="$tmp/version" ; log="$tmp/installed.log"
  : > "$log"
  export PI_SELF_VERSION_FILE="$vf" PI_SELF_INSTALLER=stub PI_SELF_INSTALL_LOG="$log" PI_SELF_PROBE_ONLY=1

  local c
  for c in bash grep sed sort mktemp rm; do command -v "$c" >/dev/null 2>&1 || { err "self-test needs $c"; return 1; }; done
  local me; me="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

  # 1. equal -> OK, and --push must run NOTHING (the arm that turns a sync into a reinstall storm).
  printf '9.9.9\n' > "$vf"
  # pin the fleet to the same value by rewriting the sandbox versions file the script reads
  mkdir -p "$tmp/repo/IaC/ansible/group_vars/all"
  sed -E 's/^pi_host_npm_version:.*/pi_host_npm_version: "9.9.9"/' "$VERSIONS" > "$tmp/repo/IaC/ansible/group_vars/all/versions.yml"
  REPO="$tmp/repo" bash "$me" --check --strict >/dev/null 2>&1 && info "equal            GREEN" || { err "canary: an in-sync build was not OK"; fails=$((fails+1)); }
  REPO="$tmp/repo" bash "$me" --push >/dev/null 2>&1
  if [ ! -s "$log" ]; then info "push-idempotent  GREEN (no installer call)"
  else err "canary passed: a correct seat reinstalled pi"; fails=$((fails+1)); fi

  # 2. behind -> drift is caught, and push converges to the pin.
  printf '1.0.3\n' > "$vf"
  REPO="$tmp/repo" bash "$me" --check --strict >/dev/null 2>&1 && { err "canary: a behind build stayed green"; fails=$((fails+1)); } \
    || info "behind-canary      caught"
  REPO="$tmp/repo" bash "$me" --push >/dev/null 2>&1
  if [ "$(tr -d '[:space:]' < "$vf")" = "9.9.9" ] && grep -q '@9.9.9' "$log"; then info "behind-push      GREEN (converged to the pin)"
  else err "canary passed: a behind build did not converge"; fails=$((fails+1)); fi

  # 3. AHEAD -> this is the class every file plane misses (HD-1112's unpinned @latest).
  printf '9.9.10\n' > "$vf"
  out="$(REPO="$tmp/repo" bash "$me" --check 2>&1)"; rc=$?
  if printf '%s' "$out" | grep -q AHEAD && ! printf '%s' "$out" | grep -q BEHIND; then info "ahead-canary       caught (a seat ahead of its pin is drift)"
  else err "canary passed: a seat ahead of its pin read as in sync"; fails=$((fails+1)); fi
  REPO="$tmp/repo" bash "$me" --check >/dev/null 2>&1 || { err "canary: a DRIFT must be report-only without --strict"; fails=$((fails+1)); }
  REPO="$tmp/repo" bash "$me" --push >/dev/null 2>&1
  [ "$(tr -d '[:space:]' < "$vf")" = "9.9.9" ] && info "ahead-push         GREEN (the pin wins, the seat is not the SSOT)" \
    || { err "canary passed: an ahead build was left ahead"; fails=$((fails+1)); }

  # 4. no installer -> failure, never a silent pass.
  printf '1.0.0\n' > "$vf"
  PI_SELF_INSTALLER=none REPO="$tmp/repo" bash "$me" --push >/dev/null 2>&1 \
    && { err "canary: a host with no installer reported success"; fails=$((fails+1)); } \
    || info "no-installer       caught (refusing to pretend is the point)"

  # 5. a missing pin -> hard error, never an inline default (CONVENTIONS §4).
  sed -E '/^pi_host_npm_version:/d' "$VERSIONS" > "$tmp/repo/IaC/ansible/group_vars/all/versions.yml"
  printf '1.0.0\n' > "$vf"
  REPO="$tmp/repo" bash "$me" --check >/dev/null 2>&1 && { err "canary: a missing pin silently defaulted"; fails=$((fails+1)); } \
    || info "missing-pin        caught (fail-loud)"

  # 6. no binary at all -> SKIP rc 2, printed and never counted as in sync.
  sed -E 's/^pi_host_npm_version:.*/pi_host_npm_version: "9.9.9"/' "$VERSIONS" > "$tmp/repo/IaC/ansible/group_vars/all/versions.yml"
  # pipefail is set at the top of this file, and this child legitimately exits 2 (SKIP) — a
  # bare `cmd | grep -q` would therefore take the || branch and the canary would report a bug
  # that does not exist. Capture first, then grep the capture.
  local skipout
  skipout="$(env -u PI_SELF_VERSION_FILE PI_SELF_PI="$tmp/nope" bash "$me" --check 2>/dev/null || true)"
  printf '%s' "$skipout" | grep -q SKIP \
    && info "skip-honest        GREEN (a SKIP is printed, not passed)" \
    || { err "canary: no-binary did not report SKIP"; fails=$((fails+1)); }

  # 7. the MANAGED layout must be SEEN (2026-10-09 oldsrv: pi ran perfectly under ~/.pi/agent/bin
  #    and this plane answered `SKIP — no pi binary answers` with rc 0 — a green it had not
  #    earned), and --push there must REFUSE rather than npm -g a second layout under it.
  mkdir -p "$tmp/managed" "$tmp/sandbox-node"
  printf '#!/bin/sh\necho 9.9.9\n' > "$tmp/managed/pi"; chmod +x "$tmp/managed/pi"
  local sysbin bashbin mout
  sysbin="$(dirname "$(command -v grep)")"; bashbin="$(command -v bash)"
  # Never let a canary reach a real installer: PI_NODE_PREFIX points at an empty sandbox and the
  # repo copy names a package that does not exist, so even a broken kind-detection cannot npm
  # install anything real from a self-test.
  sed -E 's/^pi_host_npm_version:.*/pi_host_npm_version: "9.9.9"/; s/^pi_host_npm_package:.*/pi_host_npm_package: "pi-self-update-canary"/' \
    "$VERSIONS" > "$tmp/repo/IaC/ansible/group_vars/all/versions.yml"
  # PATH neutered to the system dirs so a pi that really lives on the test host (a Volta shim, a
  # pinned prefix) cannot answer for the canary and make it pass for the wrong reason.
  mout="$(env -u PI_SELF_VERSION_FILE -u PI_SELF_PI -u PI_SELF_INSTALLER -u PI_SELF_PROBE_ONLY \
         PATH="$sysbin:/bin" PI_ENTRY_DIR="$tmp/managed" PI_NODE_PREFIX="$tmp/sandbox-node" \
         REPO="$tmp/repo" "$bashbin" "$me" --check --strict 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$mout" | grep -q OK; then
    info "managed-probe      GREEN (a ~/.pi/agent/bin pi is seen, not SKIPped)"
  else err "canary passed: a managed-install seat read as no-pi (rc $rc) $mout"; fails=$((fails+1)); fi
  # and --push there must REFUSE rather than npm -g a second layout under it — which only becomes
  # visible when that seat is OFF its pin (an in-sync seat runs NOTHING, arm 1's rule).
  printf '#!/bin/sh\necho 9.9.10\n' > "$tmp/managed/pi"
  mout="$(env -u PI_SELF_VERSION_FILE -u PI_SELF_PI -u PI_SELF_INSTALLER -u PI_SELF_PROBE_ONLY \
         PATH="$sysbin:/bin" PI_ENTRY_DIR="$tmp/managed" PI_NODE_PREFIX="$tmp/sandbox-node" \
         REPO="$tmp/repo" "$bashbin" "$me" --push 2>&1)"; rc=$?
  # rc alone cannot tell the managed refusal from "no installer found" — the same trap CONVENTIONS
  # §6 names (a test whose verdict is the same either way proves nothing). Assert the REASON.
  if [ "$rc" -ne 0 ] && printf '%s' "$mout" | grep -q "pi update self"; then
    info "managed-push       caught (refuses to npm -g over pi's own layout, and says why)"
  else err "canary passed: --push installed a second layout over a managed install"; fails=$((fails+1)); fi

  printf '\nself-test: %s\n' "$([ "$fails" -eq 0 ] && echo 'OK — all canaries caught' || echo "$fails canary/canaries NOT caught")"
  return "$fails"
}

case "$MODE" in
  check)    do_check ;;
  push)     do_push ;;
  selftest) do_selftest ;;
esac
exit $?
