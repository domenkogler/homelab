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
# Binary is judged by a NUL byte found WITHOUT a fork: `IFS= read -r -d ''` returns SUCCESS at the first NUL
# and FAILURE at EOF when there is none — that is the whole question, and it used to be answered by
# comparing `wc -c < f` with `tr -d '\0' < f | wc -c` because a bash variable cannot hold a NUL.
bad_encoding() {
  local p="$1" line first=1 chunk
  [ -f "$p" ] || return 1
  [ -s "$p" ] || return 1
  while IFS= read -r -d '' chunk; do
    return 1   # NUL byte -> binary, no judgement
  done < "$p"
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
  # sync-skills.sh, the sibling, runs the SAME body and is proven by its own canaries too (it got a
  # --self-test on 2026-10-12, which is the thing that made this body portable to it at all). The NUL probe
  # above is the one part of the guard that is NOT proven by a CRLF/BOM canary, so this fixture carries a
  # binary arm with a NUL AND a CRLF pair in the same file: abstention that nobody can break is a rule
  # nobody has (CONVENTIONS §6).
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
# ONE WALK PER SIDE, CACHED IN THE CALLER'S SHELL. These were called from five places per run (compare
# twice, the encoding sweep, push, pull) through `< <(list_*_files)` — and a process substitution runs in a
# SUBSHELL, so the memo it set was discarded with it and every caller paid `cd+find+sed+sort` all over
# again. The builders fill the global in the caller's shell and the loops read it from a here-string;
# `sed 's#^\./##'` is gone with the `cd` and the prefix comes off by parameter expansion. Sorting absolute
# paths instead of relative ones cannot reorder anything: every entry of one side shares the same
# absolute prefix, so the compared bytes are the same bytes `sort` saw before.
_src_list=""; _src_list_set=0
_deploy_list=""; _deploy_list_set=0
build_src_list() {
  [ "$_src_list_set" = 1 ] && return 0
  _src_list_set=1
  local f t=""
  if [ -d "$SRC" ]; then
    while IFS= read -r f; do
      f="${f#"$SRC/"}"
      is_artifact "$f" && continue
      t+="$f"$'\t'"$SRC/$f"$'\n'
    done < <(find "$SRC" -type f | sort)
  fi
  _src_list="${t%$'\n'}"
  return 0
}

build_deploy_list() {
  [ "$_deploy_list_set" = 1 ] && return 0
  _deploy_list_set=1
  local f t=""
  if [ -d "$DEPLOY" ]; then
    while IFS= read -r f; do
      f="${f#"$DEPLOY/"}"
      is_artifact "$f" && continue
      t+="$f"$'\t'"$DEPLOY/$f"$'\n'
    done < <(find "$DEPLOY" -type f | sort)
  fi
  _deploy_list="${t%$'\n'}"
  return 0
}

# --- encoding guard over repo-side files --------------------------------------
# The count lands in ENCODING_N, an out-parameter (HD-1115's shape): `v="$(encoding_violations)"` at the
# call sites was a fork per call, on a host that charges ~80 ms for one and does not parallelise them.
ENCODING_N=0
encoding_violations() {
  local rel abs
  ENCODING_N=0
  build_src_list
  if [ -n "$_src_list" ]; then
    while IFS=$'\t' read -r rel abs; do
      if bad_encoding "$abs"; then
        err "ENCODING violation: $rel  (UTF-8 BOM or CRLF — must be LF, no BOM)"
        ENCODING_N=$((ENCODING_N + 1))
      fi
    done <<<"$_src_list"
  fi
  return 0
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
  build_src_list
  if [ -n "$_src_list" ]; then
    while IFS=$'\t' read -r rel abs; do
      if [ ! -f "$DEPLOY/$rel" ]; then
        info "MISSING on deploy:  $rel"
        drift=1
      elif ! cmp -s "$abs" "$DEPLOY/$rel" 2>/dev/null; then   # cmp = the byte-truthful compare, keep the exec
        info "DIFFERS:            $rel   (repo != deployed)"
        drift=1
      fi
    done <<<"$_src_list"
  fi

  build_deploy_list
  if [ -n "$_deploy_list" ]; then
    while IFS=$'\t' read -r rel abs; do
      if [ ! -e "$SRC/$rel" ]; then
        # a retired name is NOT a machine-local extra — it is drift, reported once below
        case " ${RETIRED[*]} " in *" $rel "*) continue ;; esac
        info "LOCAL (deploy-only, not drift): $rel"
        extras=$((extras+1))
      fi
    done <<<"$_deploy_list"
  fi

  [ "$extras" -gt 0 ] && info "$extras deployed-only file(s) left alone (machine-local by design; a name the repo retired is NOT in that class)"
  retired check; [ "$RETIRED_N" -gt 0 ] && drift=1
  return $drift
}

# --- push: repo -> deploy (canonical direction) ---------------------------------
do_push() {
  [ -d "$SRC" ] || { err "repo extensions dir not found ($SRC)"; return 1; }
  local v
  encoding_violations; v=$ENCODING_N
  if [ "$v" -gt 0 ]; then
    err "encoding violation(s) ($v) block --push — fix to LF/no-BOM, then retry"
    return 1
  fi
  mkdir -p "$DEPLOY"
  local rel abs n=0 dsub
  build_src_list
  if [ -n "$_src_list" ]; then
    while IFS=$'\t' read -r rel abs; do
      dsub="${rel%/*}"; [ "$dsub" = "$rel" ] && dsub="."          # == dirname, without the fork
      mkdir -p "$DEPLOY/$dsub"
      cp -a "$abs" "$DEPLOY/$rel" || { err "push failed: $rel"; return 1; }
      n=$((n+1))
    done <<<"$_src_list"
  fi
  retired push || return 1
  info "pushed $n file(s) -> $DEPLOY (deployed-only files preserved, retired names removed)"
  # What the seat holds NOW, after the push — so this walks the tree again instead of reusing the memo, and
  # it walks it with 2 execs (`find | sort`) instead of 4 (`cd | find | sed | sort | tr`): the `sed` and the
  # `tr` are parameter expansion and a string append now. Artifacts stay in this listing, as they were.
  local _held="" _f
  while IFS= read -r _f; do _held+="${_f#"$DEPLOY/"} "; done < <(find "$DEPLOY" -type f 2>/dev/null | sort)
  info "deployed now holds: $_held"
  return 0
}

# --- pull: deployed -> repo working tree, TRACKED files only --------------------
# Never imports a deployed-only file: on the laptop that would commit
# remote-bash.ts — Windows sshpass.exe + C:\ paths — into the portable SSOT, and
# every later --push would ship it to the Debian seats.
do_pull() {
  [ -d "$DEPLOY" ] || { err "no deployed extensions at $DEPLOY — nothing to pull"; return 1; }
  local rel abs n=0 skipped=0
  build_deploy_list
  if [ -n "$_deploy_list" ]; then
    while IFS=$'\t' read -r rel abs; do
      if [ ! -e "$SRC/$rel" ]; then
        skipped=$((skipped+1))
        continue
      fi
      cmp -s "$abs" "$SRC/$rel" && continue                        # cmp = byte truth, keep the exec
      cp -f "$abs" "$SRC/$rel" || { err "pull failed: $rel"; return 1; }
      n=$((n+1))
    done <<<"$_deploy_list"
  fi
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
      bash "$SCRIPT_DIR/${BASH_SOURCE[0]##*/}" "$@" >/dev/null 2>&1
  }

  # The SAME sandbox driven in-process, for the arms whose value is a RULE verdict rather than the
  # process-level exit code. It points every global a launched CLI would have derived from REPO /
  # PI_EXT_DIR at the sandbox and drops the memoised file lists — the lists are built in the CALLER's
  # shell now, so a missing reset would have an arm quote the previous tree's verdict (proved, not
  # assumed: deleting that reset line reddens `differs` and `bom-push`, see the mutation record).
  # Nothing here can reach a real seat: REPO/SRC/DEPLOY are set to paths under $tmp before the first arm.
  at_sandbox() {  # $1 = sandbox root, $2 = check | check-strict | push | pull -> rc
    local root="$1" mode="$2"
    REPO="$root"; SRC="$root/pi-agent/extensions"; DEPLOY="$root/agent/extensions"
    _src_list=""; _src_list_set=0; _deploy_list=""; _deploy_list_set=0
    STRICT=0
    case "$mode" in
      check)        run_check   >/dev/null 2>&1 ;;
      check-strict) STRICT=1; run_check >/dev/null 2>&1 ;;
      push)         do_push     >/dev/null 2>&1 ;;
      pull)         do_pull     >/dev/null 2>&1 ;;
      *)            err "at_sandbox: unknown mode '$mode'"; return 2 ;;
    esac
  }
  # Fail-safe while no sandbox is selected: name paths inside $tmp, never the seat this ran from.
  REPO="$tmp/no-repo"; SRC="$tmp/no-repo/pi-agent/extensions"; DEPLOY="$tmp/no-deploy"

  # 1. rest state: repo file identical + one deployed-only extra -> GREEN.
  #    This is the extras rule; if it ever reads as drift the gate fails on the
  #    laptop seat forever and someone mutes it. LAUNCHED: --check --strict's rc-0 contract.
  a="$tmp/rest"; mk_tree "$a"
  if run_at "$a" --check --strict; then info "extras-at-rest     GREEN (as designed)"; else err "canary: deployed-only extra was treated as drift"; fails=$((fails+1)); fi

  # 2. deployed side loses the repo file -> MUST fail. LAUNCHED: the rc-1-on-drift contract.
  rm -f "$a/agent/extensions/seat-status.ts"
  if run_at "$a" --check --strict; then err "canary passed: MISSING file stayed green"; fails=$((fails+1)); else info "missing-canary     caught"; fi

  # 3. deployed side differs -> MUST fail. In-process from here on: every in-process arm calls the same
  #    run_check()/do_push()/do_pull() the dispatch calls, so it asserts the shipped rules, not a copy.
  mk_tree "$tmp/diff"
  printf 'export default function () { /* drifted */ }\n' > "$tmp/diff/agent/extensions/seat-status.ts"
  if at_sandbox "$tmp/diff" check-strict; then err "canary passed: DIFFERING file stayed green"; fails=$((fails+1)); else info "drift-canary       caught"; fi

  # 4. repo-side CRLF -> blocks --push AND fails --check --strict. LAUNCHED: these two ARE the encoding rc
  #    contracts (push refuses; --check --strict exits 1), so they stay real process creations.
  #    The bad bytes go on BOTH sides, exactly as in sync-skills.sh's arm 6, for the reason that harness
  #    recorded on 2026-10-12: with the CRLF only on the repo side the tree is ALSO drifting, so the gate
  #    line passes on the DRIFT rule and the encoding rule is never what made it red. Measured here, not
  #    assumed: with the bad bytes on one side, neutering `[ "$STRICT" -eq 1 ] && rc=1` left this whole
  #    fixture GREEN; with them on both, that mutation reddens `crlf-gate` and `bom-gate`.
  mk_tree "$tmp/enc"
  printf 'export default function () {}\r\n' > "$tmp/enc/pi-agent/extensions/seat-status.ts"
  printf 'export default function () {}\r\n' > "$tmp/enc/agent/extensions/seat-status.ts"
  if run_at "$tmp/enc" --push; then err "canary passed: --push deployed a CRLF file"; fails=$((fails+1)); else info "crlf-canary        caught (push blocked)"; fi
  if run_at "$tmp/enc" --check --strict; then err "canary passed: CRLF stayed green"; fails=$((fails+1)); else info "crlf-gate          caught"; fi

  # 4b. repo-side BOM -> blocks --push AND fails --check --strict. Same rule as CRLF, and it had NO
  #     canary at all until 2026-10-10: the check was rewritten to read the file in-process instead of
  #     through `head|od`, and "a test that cannot fail is not evidence" (CONVENTIONS §6) means that
  #     rewrite needed its own proof, not the CRLF canary's. In-process: the rc shape behind it is the
  #     pair of launches above.
  mk_tree "$tmp/bom"
  printf '\xef\xbb\xbfexport default function () {}\n' > "$tmp/bom/pi-agent/extensions/seat-status.ts"
  printf '\xef\xbb\xbfexport default function () {}\n' > "$tmp/bom/agent/extensions/seat-status.ts"   # both sides, see arm 4
  if at_sandbox "$tmp/bom" push; then err "canary passed: --push deployed a BOM file"; fails=$((fails+1)); else info "bom-canary         caught (push blocked)"; fi
  if at_sandbox "$tmp/bom" check-strict; then err "canary passed: a BOM stayed green"; fails=$((fails+1)); else info "bom-gate           caught"; fi

  # 4c. A NUL byte means BINARY -> the guard abstains. The bad bytes sit on BOTH sides so the tree is not
  #     also DRIFTING, and the CRLF pair next to the NUL is the teeth: a binary file that would pass the
  #     text rules anyway cannot tell an abstention from a blind probe, and the abstention is what keeps a
  #     font/logo asset from failing the gate on a seat where someone would then mute the whole guard.
  #     Before 2026-10-12 this fixture had no binary arm at all, so the fork-free NUL probe could not have
  #     been landed here honestly.
  mk_tree "$tmp/bin"
  printf 'PNG-ish\x00\x01\x02\r\ndata\r\n' > "$tmp/bin/pi-agent/extensions/asset.bin"
  cp "$tmp/bin/pi-agent/extensions/asset.bin" "$tmp/bin/agent/extensions/asset.bin"
  if at_sandbox "$tmp/bin" check-strict; then info "binary             GREEN (abstains, no false alarm)"; else err "canary: a binary file was flagged as an encoding violation"; fails=$((fails+1)); fi

  # 5. --push converges a clean repo and is idempotent (push twice == green). The first --push is LAUNCHED
  #    (it is --push's rc-0 contract and the one place a real process writes real bytes); the follow-ups
  #    are the same verdict, read in-process.
  mk_tree "$tmp/push"; rm -f "$tmp/push/agent/extensions/seat-status.ts"
  run_at "$tmp/push" --push || { err "--push failed on a clean tree"; fails=$((fails+1)); }
  at_sandbox "$tmp/push" check-strict || { err "canary: still drifting after --push"; fails=$((fails+1)); }
  if at_sandbox "$tmp/push" push && at_sandbox "$tmp/push" check-strict; then
    info "push-idempotent    GREEN"
  else
    err "canary: --push not idempotent"; fails=$((fails+1))
  fi
  # push must not delete the deployed extra
  [ -f "$tmp/push/agent/extensions/windows-only.ts" ] \
    && info "extra-preserved    GREEN" || { err "canary: --push deleted a deployed-only file"; fails=$((fails+1)); }

  # 6. absent deploy dir -> MUST be reported (validate-all guards the SKIP). LAUNCHED: this is the
  #    environment-boundary contract — a missing target is rc!=0 for the caller to guard, never a silent
  #    green (CONVENTIONS §6: a boundary prints SKIP, not a verdict).
  mk_tree "$tmp/nodir"; rm -rf "$tmp/nodir/agent/extensions"
  if run_at "$tmp/nodir" --check --strict; then err "canary passed: absent deploy target read as clean"; fails=$((fails+1)); else info "no-target-canary   caught"; fi

  # 7. THE RETIREMENT RULE, both halves. A name the repo deleted would otherwise stay loaded on
  #    every seat forever, because --push never deletes a deployed-only file — and the rule must
  #    NOT swallow the LOCAL rule above, so the same tree keeps its non-retired extra.
  #    The check half is LAUNCHED (the rc-1 contract a retired name still loaded must set); the removal is
  #    asserted against the same do_push() the CLI calls.
  mk_tree "$tmp/retired"
  printf 'export default function () {}\n' > "$tmp/retired/agent/extensions/${RETIRED[0]}"
  if run_at "$tmp/retired" --check --strict; then err "canary passed: a RETIRED deployed file stayed green"; fails=$((fails+1)); else info "retired-canary     caught"; fi
  at_sandbox "$tmp/retired" push || true
  if [ ! -e "$tmp/retired/agent/extensions/${RETIRED[0]}" ]; then info "retired-removed    GREEN (--push took it out)"; else err "canary: --push left a retired extension deployed"; fails=$((fails+1)); fi
  if [ -f "$tmp/retired/agent/extensions/windows-only.ts" ]; then info "retired-vs-local   GREEN (a non-retired extra survived)"; else err "canary: --push deleted a machine-local extra while retiring"; fails=$((fails+1)); fi
  at_sandbox "$tmp/retired" check-strict && info "post-retire        GREEN" || { err "canary: still drifting after the retirement push"; fails=$((fails+1)); }

  printf '\nself-test: %s\n' "$([ "$fails" -eq 0 ] && echo "OK — all canaries caught" || echo "$fails canary/canaries NOT caught")"
  return "$fails"
}

# --- the ONE decision body for --check ------------------------------------------
# Shared by the CLI dispatch and --self-test, so an in-process arm can never assert against logic the
# shipped CLI does not run. That is what buys the launches down (this host charges ~80 ms per process
# creation and does not parallelise them) without buying a cheaper second implementation of the rules.
run_check() {
  local rc v
  [ -d "$SRC" ] || { err "no pi-agent/extensions/ at $SRC — run from a homelab clone"; return 1; }
  if [ ! -d "$DEPLOY" ]; then
    info "deploy target missing: $DEPLOY (nothing deployed yet)"
    info "hint: 'sync-extensions.sh --push', or re-run install-pi-debian.sh / install-pi-wsl.sh"
    return 1
  fi
  info "comparing repo pi-agent/extensions/  <->  deployed ($DEPLOY)"
  compare
  rc=$?
  encoding_violations; v=$ENCODING_N
  if [ "$v" -gt 0 ]; then
    err "$v encoding violation(s) in pi-agent/extensions/"
    [ "$STRICT" -eq 1 ] && rc=1
  fi
  if [ "$STRICT" -eq 1 ] && [ "$rc" -eq 0 ]; then
    info "OK: repo extensions == deployed (no drift; deployed-only extras are not drift)"
  elif [ "$rc" -ne 0 ]; then
    info "drift detected — --push to deploy, or --pull to capture a seat-side edit"
  fi
  return "$rc"
}

# ================================ dispatch ======================================
if [ "$MODE" = "selftest" ]; then
  self_test; exit $?
fi

case "$MODE" in
  check) run_check ; exit $? ;;
  push)  do_push ; exit $? ;;
  pull)  do_pull ; exit $? ;;
esac
