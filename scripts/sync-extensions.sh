#!/usr/bin/env bash
# sync-extensions.sh — keep `pi-agent/extensions/` ↔ `~/.pi/agent/extensions/`
# drift-free (repo = SSOT). Sibling of scripts/sync-skills.sh (HD-254); same
# three modes, same byte-exact compare, same encoding guard — and ONE deliberate
# difference, because extensions are not skills:
#
#   --check (default)  report drift repo -> deployed; exit 0 (report only).
#   --check --strict   exit non-zero when a repo-side file is missing/differs on
#                      the deployed side, or a repo-side encoding violation
#                      exists. Wired into validate-all.sh as the extension gate.
#   --push             deploy repo -> ~/.pi/agent/extensions (canonical).
#                      NEVER deletes a deployed file the repo does not have.
#   --pull             capture deployed -> repo WORKING TREE for files the repo
#                      already tracks. Copy-only: never commits, never deletes,
#                      never imports a deployed-only file (see below).
#
# THE DIFFERENCE, and the reason it is not just a copy of sync-skills.sh: a
# deployed-only extension is a NORMAL state here, not drift. `remote-bash.ts`
# lives on the Win11 host only — it hardcodes Windows sshpass.exe and C:\ paths
# and is intentionally out of the repo (scripts/README.md, install-pi-wsl.sh).
# sync-skills.sh counts an untracked deployed file as drift; doing that here
# would fail the gate permanently on the laptop seat and teach the next reader to
# mute the gate (the HD-417 failure mode). So: deployed-only files are reported
# as LOCAL and do NOT set the exit code. --self-test asserts BOTH halves — a
# missing repo-side file fails, a deployed-only extra stays green — so this rule
# cannot silently become the old one.
#
# Artifacts never compared or deployed: __pycache__/**, .DS_Store, *.bak, *.log.
#
# Env: REPO (default: repo root, self-derived from this script's path) and
# PI_EXT_DIR (default: $HOME/.pi/agent/extensions — override is what the
# self-test uses to point at a sandbox; there is no other reason for it).
#
# Owning rule: CONVENTIONS §6 (repo = SSOT, worktree discipline) · HD-254 family.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
SRC="$REPO/pi-agent/extensions"
DEPLOY="${PI_EXT_DIR:-$HOME/.pi/agent/extensions}"

MODE="check"
STRICT=0

err()  { printf 'sync-extensions: %s\n' "$*" >&2; }
info() { printf '  %s\n' "$*"; }

usage() {
  cat <<'EOF'
usage: sync-extensions.sh [--check [--strict] | --push | --pull] [--self-test]

  --check            (default) drift report: repo pi-agent/extensions/ vs deployed
  --check --strict   also exit 1 on drift or an encoding violation (gate use)
  --push             deploy repo -> ~/.pi/agent/extensions; deployed-only files
                     are PRESERVED, never deleted
  --pull             copy tracked-by-repo deployed files into the repo working
                     tree (no commit, no delete, no import of extras)
  --self-test        sandboxed canaries in a temp dir; asserts a missing repo
                     file FAILS the check and a deployed-only extra stays GREEN

Artifacts ignored: __pycache__, .DS_Store, *.bak, *.log.
Encoding guard: text must be UTF-8 no-BOM + LF; CRLF or BOM blocks --push.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)     MODE="check" ;;
    --strict)    STRICT=1 ;;
    --push)      MODE="push" ;;
    --pull)      MODE="pull" ;;
    --self-test) MODE="selftest" ;;
    --help|-h)   usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

# --- artifact predicate -------------------------------------------------------
is_artifact() {
  case "$1" in
    __pycache__|__pycache__/*|*/__pycache__/*) return 0 ;;
    .DS_Store|*/.DS_Store) return 0 ;;
    *.bak|*.log) return 0 ;;
  esac
  return 1
}

# $1 = path -> 0 if UTF-8 BOM and/or CRLF present in a non-empty text file.
# Binary is judged by a NUL byte (bash args cannot hold NUL, so count bytes
# before/after tr instead of grepping for it).
bad_encoding() {
  local p="$1"
  [ -f "$p" ] || return 1
  [ -s "$p" ] || return 1
  local total strip
  total="$(wc -c < "$p")"
  strip="$(tr -d '\0' < "$p" | wc -c)"
  [ "$total" != "$strip" ] && return 1   # NUL byte -> binary, no judgement
  [ "$(head -c3 "$p" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "efbbbf" ] && return 0
  LC_ALL=C grep -q $'\r' "$p" 2>/dev/null && return 0
  return 1
}

# --- file lists: "REL\tABS", repo side and deploy side ------------------------
list_src_files() {
  local f
  [ -d "$SRC" ] || return 0
  while IFS= read -r f; do
    is_artifact "$f" && continue
    printf '%s\t%s\n' "$f" "$SRC/$f"
  done < <(cd "$SRC" && find . -type f | sed 's#^\./##' | sort)
}

list_deploy_files() {
  local f
  [ -d "$DEPLOY" ] || return 0
  while IFS= read -r f; do
    is_artifact "$f" && continue
    printf '%s\t%s\n' "$f" "$DEPLOY/$f"
  done < <(cd "$DEPLOY" && find . -type f | sed 's#^\./##' | sort)
}

# --- encoding guard over repo-side files --------------------------------------
encoding_violations() {
  local rel abs count=0
  while IFS=$'\t' read -r rel abs; do
    if bad_encoding "$abs"; then
      err "ENCODING violation: $rel  (UTF-8 BOM or CRLF — must be LF, no BOM)"
      count=$((count+1))
    fi
  done < <(list_src_files)
  printf '%s' "$count"
}

# --- drift compare -------------------------------------------------------------
# Repo-side missing/differing = DRIFT (exit 1). Deployed-only = LOCAL (exit 0).
compare() {
  local rel abs drift=0 extras=0
  while IFS=$'\t' read -r rel abs; do
    if [ ! -f "$DEPLOY/$rel" ]; then
      info "MISSING on deploy:  $rel"
      drift=1
    elif ! cmp -s "$abs" "$DEPLOY/$rel" 2>/dev/null; then
      info "DIFFERS:            $rel   (repo != deployed)"
      drift=1
    fi
  done < <(list_src_files)

  while IFS=$'\t' read -r rel abs; do
    if [ ! -e "$SRC/$rel" ]; then
      info "LOCAL (deploy-only, not drift): $rel"
      extras=$((extras+1))
    fi
  done < <(list_deploy_files)

  [ "$extras" -gt 0 ] && info "$extras deployed-only file(s) left alone (machine-local by design, e.g. remote-bash.ts)"
  return $drift
}

# --- push: repo -> deploy (canonical direction) ---------------------------------
do_push() {
  [ -d "$SRC" ] || { err "repo extensions dir not found ($SRC)"; return 1; }
  local v
  v="$(encoding_violations)"
  if [ "$v" -gt 0 ]; then
    err "encoding violation(s) ($v) block --push — fix to LF/no-BOM, then retry"
    return 1
  fi
  mkdir -p "$DEPLOY"
  local rel abs n=0
  while IFS=$'\t' read -r rel abs; do
    mkdir -p "$DEPLOY/$(dirname "$rel")"
    cp -a "$abs" "$DEPLOY/$rel" || { err "push failed: $rel"; return 1; }
    n=$((n+1))
  done < <(list_src_files)
  info "pushed $n file(s) -> $DEPLOY (deployed-only files preserved)"
  info "deployed now holds: $(cd "$DEPLOY" && find . -type f | sed 's#^\./##' | sort | tr '\n' ' ')"
  return 0
}

# --- pull: deployed -> repo working tree, TRACKED files only --------------------
# Never imports a deployed-only file: on the laptop that would commit
# remote-bash.ts — Windows sshpass.exe + C:\ paths — into the portable SSOT, and
# every later --push would ship it to the Debian seats.
do_pull() {
  [ -d "$DEPLOY" ] || { err "no deployed extensions at $DEPLOY — nothing to pull"; return 1; }
  local rel abs n=0 skipped=0
  while IFS=$'\t' read -r rel abs; do
    if [ ! -e "$SRC/$rel" ]; then
      skipped=$((skipped+1))
      continue
    fi
    cmp -s "$abs" "$SRC/$rel" && continue
    cp -f "$abs" "$SRC/$rel" || { err "pull failed: $rel"; return 1; }
    n=$((n+1))
  done < <(list_deploy_files)
  info "pulled $n changed file(s) $DEPLOY -> $SRC (working tree only)"
  [ "$skipped" -gt 0 ] && info "$skipped deployed-only file(s) NOT imported (not in the repo by design)"
  info "commit per CONVENTIONS §6 (worktree + validate + branch); never commit straight off main"
  return 0
}

# --- self-test ------------------------------------------------------------------
# Breeds each invariant and refuses a canary that passes. Everything runs in a
# temp HOME; nothing here reads or writes $HOME/.pi.
self_test() {
  local tmp fails=0
  tmp="$(mktemp -d 2>/dev/null)" || { err "mktemp failed"; return 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  mk_tree() {  # $1 = sandbox root holding pi-agent/extensions (repo) + agent/extensions (deploy)
    mkdir -p "$1/pi-agent/extensions/autotalk" "$1/agent/extensions/autotalk"
    printf 'export default function () {}\n' > "$1/pi-agent/extensions/host-status.ts"
    printf '{\n  "intervalSec": 10\n}\n' > "$1/pi-agent/extensions/autotalk/settings.json"
    printf 'export default function () {}\n' > "$1/agent/extensions/host-status.ts"
    printf '{\n  "intervalSec": 10\n}\n' > "$1/agent/extensions/autotalk/settings.json"
    printf 'export default function () {}\n' > "$1/agent/extensions/windows-only.ts"  # deployed-only extra
  }
  run_at() {  # $1 = sandbox root, rest = args -> run THIS script against that sandbox
    local root="$1"; shift
    REPO="$root" PI_EXT_DIR="$root/agent/extensions" \
      bash "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" "$@" >/dev/null 2>&1
  }

  # 1. rest state: repo file identical + one deployed-only extra -> GREEN.
  #    This is the extras rule; if it ever reads as drift the gate fails on the
  #    laptop seat forever and someone mutes it.
  a="$tmp/rest"; mk_tree "$a"
  if run_at "$a" --check --strict; then info "extras-at-rest     GREEN (as designed)"; else err "canary: deployed-only extra was treated as drift"; fails=$((fails+1)); fi

  # 2. deployed side loses the repo file -> MUST fail.
  rm -f "$a/agent/extensions/host-status.ts"
  if run_at "$a" --check --strict; then err "canary passed: MISSING file stayed green"; fails=$((fails+1)); else info "missing-canary     caught"; fi

  # 3. deployed side differs -> MUST fail.
  mk_tree "$tmp/diff"
  printf 'export default function () { /* drifted */ }\n' > "$tmp/diff/agent/extensions/host-status.ts"
  if run_at "$tmp/diff" --check --strict; then err "canary passed: DIFFERING file stayed green"; fails=$((fails+1)); else info "drift-canary       caught"; fi

  # 4. repo-side CRLF -> blocks --push AND fails --check --strict.
  mk_tree "$tmp/enc"
  printf 'export default function () {}\r\n' > "$tmp/enc/pi-agent/extensions/host-status.ts"
  if run_at "$tmp/enc" --push; then err "canary passed: --push deployed a CRLF file"; fails=$((fails+1)); else info "crlf-canary        caught (push blocked)"; fi
  if run_at "$tmp/enc" --check --strict; then err "canary passed: CRLF stayed green"; fails=$((fails+1)); else info "crlf-gate          caught"; fi

  # 5. --push converges a clean repo and is idempotent (push twice == green).
  mk_tree "$tmp/push"; rm -f "$tmp/push/agent/extensions/host-status.ts"
  run_at "$tmp/push" --push || { err "--push failed on a clean tree"; fails=$((fails+1)); }
  run_at "$tmp/push" --check --strict || { err "canary: still drifting after --push"; fails=$((fails+1)); }
  run_at "$tmp/push" --push >/dev/null 2>&1 && run_at "$tmp/push" --check --strict \
    && info "push-idempotent    GREEN" || { err "canary: --push not idempotent"; fails=$((fails+1)); }
  # push must not delete the deployed extra
  [ -f "$tmp/push/agent/extensions/windows-only.ts" ] \
    && info "extra-preserved    GREEN" || { err "canary: --push deleted a deployed-only file"; fails=$((fails+1)); }

  # 6. absent deploy dir -> MUST be reported (validate-all guards the SKIP).
  mk_tree "$tmp/nodir"; rm -rf "$tmp/nodir/agent/extensions"
  if run_at "$tmp/nodir" --check --strict; then err "canary passed: absent deploy target read as clean"; fails=$((fails+1)); else info "no-target-canary   caught"; fi

  printf '\nself-test: %s\n' "$([ "$fails" -eq 0 ] && echo "OK — all canaries caught" || echo "$fails canary/canaries NOT caught")"
  return "$fails"
}

# ================================ dispatch ======================================
if [ "$MODE" = "selftest" ]; then
  self_test; exit $?
fi

case "$MODE" in
  check)
    [ -d "$SRC" ] || { err "no pi-agent/extensions/ at $SRC — run from a homelab clone"; exit 1; }
    if [ ! -d "$DEPLOY" ]; then
      info "deploy target missing: $DEPLOY (nothing deployed yet)"
      info "hint: 'sync-extensions.sh --push', or re-run install-pi-debian.sh / install-pi-wsl.sh"
      exit 1
    fi
    info "comparing repo pi-agent/extensions/  <->  deployed ($DEPLOY)"
    compare
    rc=$?
    v="$(encoding_violations)"
    if [ "$v" -gt 0 ]; then
      err "$v encoding violation(s) in pi-agent/extensions/"
      [ "$STRICT" -eq 1 ] && rc=1
    fi
    if [ "$STRICT" -eq 1 ] && [ "$rc" -eq 0 ]; then
      info "OK: repo extensions == deployed (no drift; deployed-only extras are not drift)"
    elif [ "$rc" -ne 0 ]; then
      info "drift detected — --push to deploy, or --pull to capture a seat-side edit"
    fi
    exit "$rc"
    ;;
  push) do_push ; exit $? ;;
  pull) do_pull ; exit $? ;;
esac
