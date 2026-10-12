#!/usr/bin/env bash
# sync-extensions.sh — keep `pi-agent/extensions/` ↔ `~/.pi/agent/extensions/`
# drift-free (repo = SSOT). Sibling of scripts/harness/sync-skills.sh (HD-254); same
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
# deployed-only extension is a NORMAL state here, not drift — a seat-side file the repo does
# not carry (a machine-local experiment, a per-seat tool that cannot be made portable) is
# reported as LOCAL and does NOT set the exit code. sync-skills.sh counts an untracked
# deployed file as drift; doing that here would fail the gate permanently on the seat that
# carries one and teach the next reader to mute the gate (the HD-417 failure mode). So
# --self-test asserts BOTH halves — a missing repo-side file fails, a deployed-only extra
# stays green — and a third rule cannot quietly become the second: the names the repo
# RETIRED (below) are the one exception, and their canary proves they are removed.
#
# RETIRED EXTENSIONS
# ------------------
# `--push` never deletes a deployed-only file, which is correct for machine-local files and
# WRONG for something the repo used to ship and stopped shipping: it would keep loading on
# every seat forever, invisible to a gate that only compares repo-side files. So retirement
# is explicit, in ONE place, and enforced by both --push (removes) and --check --strict
# (fails while one is still deployed). Retired: `host-status.ts` (the footer hostname is
# pi-open-tui's own segment now — docs/pi-harness.md §5a) and `remote-bash.ts` (Windows
# sshpass.exe + drive-letter paths, never in the repo by design, dropped 2026-10-08).
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
# HD-1118 Stage 1: the repo root is FOUND by scripts/lib/repo-root.sh, never assumed
# from a depth — "one level above me" is what turns a folder move into green-while-nothing.
_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"   # sets REPO (an inherited $REPO still wins)
SRC="$REPO/pi-agent/extensions"
DEPLOY="${PI_EXT_DIR:-$HOME/.pi/agent/extensions}"

MODE="check"
STRICT=0

# Names the repo used to ship and no longer does. --push removes them from the deploy
# target; --check --strict fails while one is still loaded. NEVER extend this list to
# something the repo merely stopped tracking — a machine-local file is a LOCAL extra, not
# retired (that distinction is canary 1 vs canary 7 in --self-test).
RETIRED=(
  "host-status.ts"   # superseded by the pi-open-tui footer hostname segment (§5a)
  "remote-bash.ts"   # Windows-only (sshpass.exe, C:\ paths); never in the repo, dropped 2026-10-08
)

err()  { printf 'sync-extensions: %s\n' "$*" >&2; }
info() { printf '  %s\n' "$*"; }

usage() {
  cat <<'EOF'
usage: sync-extensions.sh [--check [--strict] | --push | --pull] [--self-test]

  --check            (default) drift report: repo pi-agent/extensions/ vs deployed
  --check --strict   also exit 1 on drift, an encoding violation, or a RETIRED extension
                     the seat still has deployed
  --push             deploy repo -> ~/.pi/agent/extensions; deployed-only files are
                     PRESERVED (never deleted) and the RETIRED names are removed
  --pull             copy tracked-by-repo deployed files into the repo working
                     tree (no commit, no delete, no import of extras)
  --self-test        sandboxed canaries in a temp dir; asserts a missing repo
                     file FAILS the check, a deployed-only extra stays GREEN, and a
                     retired deployed file is caught AND removed

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
  local p="$1" line first=1
  [ -f "$p" ] || return 1
  [ -s "$p" ] || return 1
  local total strip
  total="$(wc -c < "$p")"
  strip="$(tr -d '\0' < "$p" | wc -c)"
  [ "$total" != "$strip" ] && return 1   # NUL byte -> binary, no judgement
  # SEVEN EXECs per file used to sit here (wc, tr|wc, head|od|tr, grep) — over ~30 extension files the
  # encoding sweep alone was ~200 processes, which on a Windows seat is most of this leg (measured
  # 2026-10-10: 14 s solo; a spawn there is 16-44 ms against 0.66 ms on WSL Debian).
  #
  # ⚠ WHY `read` AND NOT `$(<"$p")`, measured on the Win11 git-bash seat the day it was rewritten: a
  # COMMAND SUBSTITUTION applies the SAME text-mode translation that made `grep` need `-U` (CONVENTIONS
  # §6). `printf 'a\r\n' > t`, then `s=$(<t)` tested for a CR reports NO CR; `IFS= read -r line < t`
  # keeps it (`od` shows the byte either way). The first version of this rewrite used `$(<"$p")` and
  # BOTH CRLF canaries printed "canary passed" — the guard was blind on Windows again, three years
  # after that same trap was written down. `read` is the builtin that does not translate here.
  #
  # sync-skills.sh, the sibling, STILL has the old `grep -U` body: it has no --self-test at all, so the
  # rewrite there would have had nothing to prove itself with, and its leg is 3 s, not a hot spot. See
  # the HD row in todo.md for giving that script a self-test; until then this body is proven here and
  # only here.
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$first" = 1 ]; then
      first=0
      case "$line" in $'\xef\xbb\xbf'*) return 0 ;; esac      # UTF-8 BOM
    fi
    case "$line" in *$'\r'*) return 0 ;; esac                  # CRLF — `read` keeps the CR, see above
  done < "$p"
  return 1
}

# --- file lists: "REL\tABS", repo side and deploy side ------------------------
# CACHED. These are called from five places per run (compare twice, the encoding sweep, push, pull)
# and every cold call was `find | sed | sort` — three EXECs plus the caller's process substitution —
# for a tree that cannot change mid-run. One walk per side is the honest cost.
_src_list=""; _src_list_set=0
_deploy_list=""; _deploy_list_set=0
list_src_files() {
  if [ "$_src_list_set" != 1 ]; then
    local f t=""
    _src_list_set=1
    if [ -d "$SRC" ]; then
      while IFS= read -r f; do
        is_artifact "$f" && continue
        t+="$f"$'\t'"$SRC/$f"$'\n'
      done < <(cd "$SRC" && find . -type f | sed 's#^\./##' | sort)
    fi
    _src_list="${t%$'\n'}"
  fi
  [ -n "$_src_list" ] && printf '%s\n' "$_src_list"
  return 0
}

list_deploy_files() {
  if [ "$_deploy_list_set" != 1 ]; then
    local f t=""
    _deploy_list_set=1
    if [ -d "$DEPLOY" ]; then
      while IFS= read -r f; do
        is_artifact "$f" && continue
        t+="$f"$'\t'"$DEPLOY/$f"$'\n'
      done < <(cd "$DEPLOY" && find . -type f | sed 's#^\./##' | sort)
    fi
    _deploy_list="${t%$'\n'}"
  fi
  [ -n "$_deploy_list" ] && printf '%s\n' "$_deploy_list"
  return 0
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

# --- retired names -------------------------------------------------------------
# Sets RETIRED_N to the number of retired names found deployed; prints what it did.
RETIRED_N=0
retired() {
  local action="${1:-check}" name
  RETIRED_N=0
  for name in "${RETIRED[@]}"; do
    [ -e "$DEPLOY/$name" ] || continue
    if [ "$action" = push ]; then
      rm -f "$DEPLOY/$name" || { err "could not remove the retired $DEPLOY/$name"; return 1; }
      info "RETIRED removed:      $name"
    else
      err "RETIRED still deployed: $name — the repo no longer ships it, --push removes it"
    fi
    RETIRED_N=$((RETIRED_N+1))
  done
  return 0
}

# --- drift compare -------------------------------------------------------------
# Repo-side missing/differing = DRIFT (exit 1). Deployed-only = LOCAL (exit 0).
# A RETIRED name still deployed = DRIFT (exit 1) — that is the retirement channel.
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
      # a retired name is NOT a machine-local extra — it is drift, reported once below
      case " ${RETIRED[*]} " in *" $rel "*) continue ;; esac
      info "LOCAL (deploy-only, not drift): $rel"
      extras=$((extras+1))
    fi
  done < <(list_deploy_files)

  [ "$extras" -gt 0 ] && info "$extras deployed-only file(s) left alone (machine-local by design; a name the repo retired is NOT in that class)"
  retired check; [ "$RETIRED_N" -gt 0 ] && drift=1
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
  retired push || return 1
  info "pushed $n file(s) -> $DEPLOY (deployed-only files preserved, retired names removed)"
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
    printf 'export default function () {}\n' > "$1/pi-agent/extensions/seat-status.ts"
    printf '{\n  "intervalSec": 10\n}\n' > "$1/pi-agent/extensions/autotalk/settings.json"
    printf 'export default function () {}\n' > "$1/agent/extensions/seat-status.ts"
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
  rm -f "$a/agent/extensions/seat-status.ts"
  if run_at "$a" --check --strict; then err "canary passed: MISSING file stayed green"; fails=$((fails+1)); else info "missing-canary     caught"; fi

  # 3. deployed side differs -> MUST fail.
  mk_tree "$tmp/diff"
  printf 'export default function () { /* drifted */ }\n' > "$tmp/diff/agent/extensions/seat-status.ts"
  if run_at "$tmp/diff" --check --strict; then err "canary passed: DIFFERING file stayed green"; fails=$((fails+1)); else info "drift-canary       caught"; fi

  # 4. repo-side CRLF -> blocks --push AND fails --check --strict.
  mk_tree "$tmp/enc"
  printf 'export default function () {}\r\n' > "$tmp/enc/pi-agent/extensions/seat-status.ts"
  if run_at "$tmp/enc" --push; then err "canary passed: --push deployed a CRLF file"; fails=$((fails+1)); else info "crlf-canary        caught (push blocked)"; fi
  if run_at "$tmp/enc" --check --strict; then err "canary passed: CRLF stayed green"; fails=$((fails+1)); else info "crlf-gate          caught"; fi

  # 4b. repo-side BOM -> blocks --push AND fails --check --strict. Same rule as CRLF, and it had NO
  #     canary at all until 2026-10-10: the check was rewritten to read the file in-process instead of
  #     through `head|od`, and "a test that cannot fail is not evidence" (CONVENTIONS §6) means that
  #     rewrite needed its own proof, not the CRLF canary's.
  mk_tree "$tmp/bom"
  printf '\xef\xbb\xbfexport default function () {}\n' > "$tmp/bom/pi-agent/extensions/seat-status.ts"
  if run_at "$tmp/bom" --push; then err "canary passed: --push deployed a BOM file"; fails=$((fails+1)); else info "bom-canary         caught (push blocked)"; fi
  if run_at "$tmp/bom" --check --strict; then err "canary passed: a BOM stayed green"; fails=$((fails+1)); else info "bom-gate           caught"; fi

  # 5. --push converges a clean repo and is idempotent (push twice == green).
  mk_tree "$tmp/push"; rm -f "$tmp/push/agent/extensions/seat-status.ts"
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

  # 7. THE RETIREMENT RULE, both halves. A name the repo deleted would otherwise stay loaded on
  #    every seat forever, because --push never deletes a deployed-only file — and the rule must
  #    NOT swallow the LOCAL rule above, so the same tree keeps its non-retired extra.
  mk_tree "$tmp/retired"
  printf 'export default function () {}\n' > "$tmp/retired/agent/extensions/${RETIRED[0]}"
  if run_at "$tmp/retired" --check --strict; then err "canary passed: a RETIRED deployed file stayed green"; fails=$((fails+1)); else info "retired-canary     caught"; fi
  run_at "$tmp/retired" --push || true
  if [ ! -e "$tmp/retired/agent/extensions/${RETIRED[0]}" ]; then info "retired-removed    GREEN (--push took it out)"; else err "canary: --push left a retired extension deployed"; fails=$((fails+1)); fi
  if [ -f "$tmp/retired/agent/extensions/windows-only.ts" ]; then info "retired-vs-local   GREEN (a non-retired extra survived)"; else err "canary: --push deleted a machine-local extra while retiring"; fails=$((fails+1)); fi
  run_at "$tmp/retired" --check --strict && info "post-retire        GREEN" || { err "canary: still drifting after the retirement push"; fails=$((fails+1)); }

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
