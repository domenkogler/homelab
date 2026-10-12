#!/usr/bin/env bash
# sync-skills.sh — keep `skills/` ↔ `~/.pi/agent/skills/` drift-free (repo = SSOT).
#
# Only the repo's `skills/` tree is the source of truth for skill content.
#   --push  repo -> ~/.pi/agent/skills   (canonical deploy direction)
#   --pull  ~/.pi/agent/skills -> repo working tree  (self-learn capture —
#           copies into the working tree ONLY, never auto-commits and never
#           deletes the repo side; the change then lands via the normal
#           worktree+commit flow, per CONVENTIONS §6)
#   --check (default)  report drift repo <-> deployed; exit 0 (report only).
#   --check --strict   exit non-zero when real drift OR an encoding violation
#                      is found — wired into validate-all.sh as a gate.
#
# Artifact ignore-list (never compared, never deployed — runtime/local state,
# not content, so it must never look like drift):
#   - net.json               (mikrotik runtime host map)
#   - .env.op                (op:// reference file — tracked in the repo, but never deployed:
#                            the scripts read it from the repo path, so a deployed copy is noise)
#   - __pycache__/**          (python bytecode)
#   - zero-byte skill-name markers  (e.g. skills/mikrotik/mikrotik)
# Mirrors the artifact-prune in scripts/install-pi-wsl.sh.
#
# Byte-compare is exact (`cmp -s`), so a CRLF or UTF-8-BOM difference reads as a
# content change. Encoding guard additionally NAMES the offender, because the
# SSOT rule (platform-env / CONVENTIONS) is UTF-8, no BOM, LF line endings: a
# repo-side skill file with CRLF endings or a UTF-8 BOM fails --check --strict
# and blocks --push, so a bad-encoding file is never deployed to ~/.pi.
#
# --self-test exists because of a hole found on 2026-10-12: this script had NO self-test at all, so
# when its sibling sync-extensions.sh got a fork-free encoding guard, the same rewrite here could not
# be proven — and the proven way to check a byte for CRLF on a Windows seat is NOT a command
# substitution, which eats the CR exactly like plain `grep` without `-U` (CONVENTIONS §6). Breeds each
# rule in a temp HOME and refuses a canary that passes.
#
# Env: REPO (default: repo root self-derived from this script's path).
# Deploy target: $HOME/.pi/agent/skills (the pi agent skills dir).
#
# Owning rule: CONVENTIONS §6 (worktree + findability) · registered as HD-254.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
DEPLOY="$HOME/.pi/agent/skills"

MODE="check"
STRICT=0

err()  { printf 'sync-skills: %s\n' "$*" >&2; }
info() { printf '  %s\n' "$*"; }

usage() {
  cat <<'EOF'
usage: sync-skills.sh [--check [--strict] | --push | --pull]

  --check            (default) drift report: repo skills/ vs ~/.pi/agent/skills
  --check --strict   also exit 1 when drift or an encoding violation is found
                     (gate use — wire into validate-all.sh)
  --push             deploy repo -> ~/.pi/agent/skills (canonical direction);
                     refuses when a repo-side encoding violation is found
  --pull             capture ~/.pi -> repo working tree (copy-only, no commit)
  --self-test        breed drift / untracked / CRLF / BOM / binary in a temp HOME and refuse a canary
                     that passes (never reads or writes the real ~/.pi)

Artifact ignore-list: net.json, __pycache__, zero-byte skill-name markers.
Encoding guard: repo skill text must be UTF-8 no-BOM + LF; CRLF/BOM fails.
EOF
}

# --- argument parsing ---------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)  MODE="check" ;;
    --strict) STRICT=1 ;;
    --push)   MODE="push" ;;
    --pull)   MODE="pull" ;;
    --self-test) MODE="selftest" ;;
    --help|-h) usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

# --- artifact predicate -------------------------------------------------------
# $1 skill name, $2 relpath, $3 abs path -> 0 if on the ignore-list. Works for
# both the repo list and the deploy list (uses the given abs path for the
# zero-byte marker test).
is_artifact() {
  local name="$1" rel="$2" abs="$3"
  case "$rel" in
    net.json) return 0 ;;
    .env.op) return 0 ;;   # op:// reference file — tracked, read from the repo path, never deployed
    __pycache__|__pycache__/*|*/__pycache__/*) return 0 ;;
  esac
  # zero-byte skill-name marker: empty file whose basename == skill name.
  if [ "$(basename "$rel")" = "$name" ] && [ -e "$abs" ] && [ ! -s "$abs" ]; then
    return 0
  fi
  # basename == skill name AND empty is the marker regardless of path depth.
  return 1
}

# $1 = path -> 0 if it has UTF-8 BOM and/or CRLF (text, non-empty); else 1.
# Binary is judged by a NUL byte (portable: bash args can't hold NUL, so use
# tr byte-count subtraction instead of grep).
bad_encoding() {
  local p="$1"
  [ -f "$p" ] || return 1
  [ -s "$p" ] || return 1
  local total strip
  total="$(wc -c < "$p")"
  strip="$(tr -d '\0' < "$p" | wc -c)"
  if [ "$total" != "$strip" ]; then
    return 1   # contains a NUL byte -> binary, skip encoding judgement
  fi
  # -U/--binary is load-bearing on a Windows seat: Git-Bash's MSYS layer opens files in TEXT mode, so
  # a plain grep never sees the CR of a CRLF pair and this guard was silently blind there (measured
  # 2026-10-07; `-U` is a no-op on Debian, where no conversion exists to disable).
  #
  # THE HALF THAT RULE WAS MISSING, found 2026-10-12: a COMMAND SUBSTITUTION translates the same way.
  # `s=$(<"$p")` with `case "$s" in *$'\r'*)` finds NO CR in a CRLF file on a Git-Bash seat (write
  # `printf 'a\r\n' > t` and compare the substitution with `od`), while `IFS= read -r` does NOT
  # translate. So the BOM and CRLF answers below come from bash's own read of the file, line by line,
  # zero forks — the same body as the sibling sync-extensions.sh — and it is only allowed to live here
  # because --self-test's crlf/bom/binary canaries prove it on whatever host runs it. Until this script
  # had a self-test that rewrite could not be verified here at all, which is why it waited.
  local line first=1
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$first" = 1 ]; then
      first=0
      case "$line" in $'\xef\xbb\xbf'*) return 0 ;; esac      # UTF-8 BOM
    fi
    case "$line" in *$'\r'*) return 0 ;; esac                  # CRLF — `read` keeps the CR, see above
  done < "$p"
  return 1
}

# --- repo file list: "NAME \t REL \t ABS" (non-artifact, real files) ----------
# CACHED: compare() and encoding_violations() each call this, and a cold call is a `find | sed | sort`
# PER SKILL. The tree cannot change mid-run, so one walk per side is the honest cost (the sibling
# sync-extensions.sh got the same treatment for the same reason).
_repo_list=""; _repo_list_set=0
list_repo_files() {
  if [ "$_repo_list_set" != 1 ]; then
    local sk name f rel t=""
    _repo_list_set=1
    for sk in "$REPO"/skills/*/; do
      [ -d "$sk" ] || continue                       # the unmatched glob stays a literal: skip it
      name="$(basename "$sk")"
      [ -f "$sk/SKILL.md" ] || continue
      while IFS= read -r f; do
        rel="${f#"$sk"}"
        is_artifact "$name" "$rel" "$REPO/skills/$name/$rel" && continue
        t+="$name"$'\t'"$rel"$'\t'"$REPO/skills/$name/$rel"$'\n'
      done < <(cd "$sk" && find . -type f | sed 's#^\./##' | sort)
    done
    _repo_list="${t%$'\n'}"
  fi
  [ -n "$_repo_list" ] && printf '%s\n' "$_repo_list"
  return 0
}

# --- deploy file list: same TAB format (includes artifacts for prune) --------
_deploy_list=""; _deploy_list_set=0
list_deploy_files() {
  if [ "$_deploy_list_set" != 1 ]; then
    local sk name f rel t=""
    _deploy_list_set=1
    if [ -d "$DEPLOY" ]; then
      for sk in "$DEPLOY"/*/; do
        [ -d "$sk" ] || continue
        name="$(basename "$sk")"
        while IFS= read -r f; do
          rel="${f#"$sk"}"
          t+="$name"$'\t'"$rel"$'\t'"$DEPLOY/$name/$rel"$'\n'
        done < <(cd "$sk" && find . -type f | sed 's#^\./##' | sort)
      done
    fi
    _deploy_list="${t%$'\n'}"
  fi
  [ -n "$_deploy_list" ] && printf '%s\n' "$_deploy_list"
  return 0
}

# --- encoding guard over repo-side skill files ---------------------------------
# info() line per offender; echoes the count.
encoding_violations() {
  local name rel abs count=0
  while IFS=$'\t' read -r name rel abs; do
    if bad_encoding "$abs"; then
      err "ENCODING violation: $name/$rel  (UTF-8 BOM or CRLF — must be LF, no BOM)"
      count=$((count+1))
    fi
  done < <(list_repo_files)
  printf '%s' "$count"
}

# --- drift compare --------------------------------------------------------------
# Reports repo-side files missing/differing on the deploy side, and deploy-only
# files with no repo source. Returns 1 if any drift, else 0.
compare() {
  local name rel abs dname drel dabs
  local drift=0

  while IFS=$'\t' read -r name rel abs; do
    local dep_path="$DEPLOY/$name/$rel"
    if [ ! -f "$dep_path" ]; then
      info "MISSING on deploy:  $name/$rel"
      drift=1
    elif ! cmp -s "$abs" "$dep_path" 2>/dev/null; then
      info "DIFFERS:            $name/$rel   (repo != deployed)"
      drift=1
    fi
  done < <(list_repo_files)

  while IFS=$'\t' read -r dname drel dabs; do
    is_artifact "$dname" "$drel" "$dabs" && continue
    if [ ! -e "$REPO/skills/$dname/$drel" ]; then
      info "UNTRACKED (deploy-only): $dname/$drel"
      drift=1
    fi
  done < <(list_deploy_files)

  return $drift
}

# --- push: repo -> deploy (canonical direction) ----------------------------------
do_push() {
  [ -d "$REPO/skills" ] || { err "repo skills/ not found ($REPO/skills)"; return 1; }
  local v
  v="$(encoding_violations)"
  if [ "$v" -gt 0 ]; then
    err "encoding violation(s) ($v) block --push — fix to LF/no-BOM, then retry"
    return 1
  fi
  local sk name
  local deployed=0
  for sk in "$REPO"/skills/*/; do
    [ -d "$sk" ] || continue
    name="$(basename "$sk")"
    [ -f "$sk/SKILL.md" ] || continue
    rm -rf "$DEPLOY/$name"
    mkdir -p "$DEPLOY/$name"
    cp -a "$sk/." "$DEPLOY/$name/"
    find "$DEPLOY/$name" -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true
    find "$DEPLOY/$name" -name "net.json" -type f -delete 2>/dev/null || true
    find "$DEPLOY/$name" -name ".env.op" -type f -delete 2>/dev/null || true
    rm -f "$DEPLOY/$name/$name" 2>/dev/null || true
    deployed=$((deployed+1))
  done
  info "pushed $deployed skill(s) -> $DEPLOY"
  info "deployed: $(ls "$DEPLOY" 2>/dev/null | tr '\n' ' ')"
  return 0
}

# --- pull: deploy -> repo working tree (copy-only; no commit, no delete) ---------
do_pull() {
  [ -d "$DEPLOY" ] || { err "no deployed skills at $DEPLOY — nothing to pull"; return 1; }
  local name dname drel dabs pulled=0
  for name in "$DEPLOY"/*; do
    [ -d "$name" ] || continue
    local n; n="$(basename "$name")"
    [ -e "$name" ] || continue
    mkdir -p "$REPO/skills/$n"
    while IFS=$'\t' read -r dname drel dabs; do
      is_artifact "$n" "$drel" "$dabs" && continue
      [ "$(basename "$drel")" = "$n" ] && [ ! -s "$dabs" ] && continue  # never restore a zero-byte marker
      mkdir -p "$REPO/skills/$n/$(dirname "$drel")"
      cp -f "$dabs" "$REPO/skills/$n/$drel" || { err "pull failed: $n/$drel"; return 1; }
      pulled=$((pulled+1))
    done < <(list_deploy_files_under "$n")
  done
  info "pulled $pulled file(s) from $DEPLOY -> repo skills/ (working tree only)"
  info "commit the change per CONVENTIONS §6 (worktree + validate + branch)"
  return 0
}

list_deploy_files_under() {
  local want="$1" dname drel dabs
  while IFS=$'\t' read -r dname drel dabs; do
    [ "$dname" = "$want" ] || continue
    printf '%s\t%s\t%s\n' "$dname" "$drel" "$dabs"
  done < <(list_deploy_files)
}

# --- self-test ------------------------------------------------------------------
# Breeds each invariant in a temp HOME and refuses a canary that passes. Nothing here touches the real
# ~/.pi: the deploy path is derived from $HOME, so HOME is the sandbox lever — there is no PI_SKILLS_DIR
# override like the sibling's PI_EXT_DIR, which is worth knowing before someone tries to redirect a run
# by env var and finds the real seat got written to.
self_test() {
  local tmp fails=0
  tmp="$(mktemp -d 2>/dev/null)" || { err "mktemp failed"; return 1; }
  local self="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  pass() { printf '  %-19s %s\n' "$1" "$2"; }
  fail() { printf '  %-19s %s\n' "$1" "$2"; fails=$((fails + 1)); }

  mk_tree() {  # $1 = sandbox root: repo skills/ (the SSOT) + the deployed copy under .pi/
    local r="$1"
    mkdir -p "$r/repo/skills/demo/references" "$r/.pi/agent/skills/demo/references"
    printf '# demo skill\n' > "$r/repo/skills/demo/SKILL.md"
    printf 'notes\n'        > "$r/repo/skills/demo/references/notes.md"
    printf '# demo skill\n' > "$r/.pi/agent/skills/demo/SKILL.md"
    printf 'notes\n'        > "$r/.pi/agent/skills/demo/references/notes.md"
  }
  run_at() {  # $1 = sandbox root, rest = args -> run THIS script against that sandbox only
    local root="$1"; shift
    REPO="$root/repo" HOME="$root" bash "$self" "$@" >/dev/null 2>&1
  }

  # 1. At rest: repo == deployed => GREEN. Without this half every "caught" below could be the script
  #    simply failing to run, which is not the same invariant.
  mk_tree "$tmp/rest"
  if run_at "$tmp/rest" --check --strict; then pass "rest-green" "OK (as designed)"; else fail "rest-green" "BROKEN: a clean tree reads as drift"; fi

  # 2. Deployed side loses a repo file => MUST fail.
  rm -f "$tmp/rest/.pi/agent/skills/demo/references/notes.md"
  if run_at "$tmp/rest" --check --strict; then fail "missing" "canary passed: a MISSING deploy file stayed green"; else pass "missing" "caught"; fi

  # 3. Deployed side differs => MUST fail. (Re-built first; case 2 left the tree edited.)
  mk_tree "$tmp/diff"
  printf 'seat-side edit\n' > "$tmp/diff/.pi/agent/skills/demo/references/notes.md"
  if run_at "$tmp/diff" --check --strict; then fail "differs" "canary passed: a DIFFERING deploy file stayed green"; else pass "differs" "caught"; fi

  # 4. A deployed-only file IS drift here (the deliberate difference from sync-extensions.sh, where an
  #    extra is machine-local by design): if this ever reads as clean, untracked seat content silently
  #    stops being a contract.
  mk_tree "$tmp/extra"
  printf 'stray\n' > "$tmp/extra/.pi/agent/skills/demo/stray.md"
  if run_at "$tmp/extra" --check --strict; then fail "untracked" "canary passed: a deploy-only file stayed green"; else pass "untracked" "caught"; fi

  # 5. The ARTIFACT RULE, both directions: runtime state the repo carries but never deploys must NOT
  #    read as drift — and it must not become a hole wide enough to hide case 2/3/4 either.
  mk_tree "$tmp/art"
  printf '{"hosts":[]}\n' > "$tmp/art/repo/skills/demo/net.json"
  printf '' > "$tmp/art/repo/skills/demo/.env.op"
  : > "$tmp/art/repo/skills/demo/demo"                       # zero-byte skill-name marker
  mkdir -p "$tmp/art/repo/skills/demo/__pycache__" && printf 'x' > "$tmp/art/repo/skills/demo/__pycache__/c.pyc"
  if run_at "$tmp/art" --check --strict; then pass "artifacts" "OK (ignored, not drift)"; else fail "artifacts" "BROKEN: runtime state reads as drift"; fi
  rm -f "$tmp/art/.pi/agent/skills/demo/SKILL.md"
  if run_at "$tmp/art" --check --strict; then fail "artifacts" "canary passed: the ignore-list swallowed a REAL missing file"; else pass "artifacts" "still catches real drift"; fi

  # 6. Repo-side CRLF => blocks --push AND fails --check --strict, and must not deploy anything.
  #    The bad bytes go on BOTH sides on purpose: if only the repo side is CRLF, the tree is also
  #    DRIFTING, and the assertion would pass on the drift rule instead of the encoding rule. That is
  #    not a hypothetical — the first version of these two cases put them on one side, and a deliberately
  #    BLIND encoding guard (byte checks through `$( )`, see bad_encoding above) still printed "caught"
  #    for all four encoding lines. Isolated, they now fail when the guard goes blind.
  mk_tree "$tmp/crlf"
  printf '# demo skill\r\n' > "$tmp/crlf/repo/skills/demo/SKILL.md"
  printf '# demo skill\r\n' > "$tmp/crlf/.pi/agent/skills/demo/SKILL.md"
  if run_at "$tmp/crlf" --push; then fail "crlf-push" "canary passed: --push accepted a CRLF file"
  elif cmp -s "$tmp/crlf/repo/skills/demo/SKILL.md" "$tmp/crlf/.pi/agent/skills/demo/SKILL.md"; then pass "crlf-push" "blocked, deployed untouched"
  else fail "crlf-push" "blocked but WROTE the bad file"; fi
  if run_at "$tmp/crlf" --check --strict; then fail "crlf-gate" "canary passed: CRLF green with no drift to blame"; else pass "crlf-gate" "caught (encoding, not drift)"; fi

  # 7. Repo-side UTF-8 BOM => the same two rules, also with no drift in play. No canary for this half
  #    existed anywhere until 2026-10-12 (CONVENTIONS §6: a test that cannot fail is not evidence).
  mk_tree "$tmp/bom"
  printf '\xef\xbb\xbf# demo skill\n' > "$tmp/bom/repo/skills/demo/SKILL.md"
  printf '\xef\xbb\xbf# demo skill\n' > "$tmp/bom/.pi/agent/skills/demo/SKILL.md"
  if run_at "$tmp/bom" --push; then fail "bom-push" "canary passed: --push accepted a BOM file"
  elif cmp -s "$tmp/bom/repo/skills/demo/SKILL.md" "$tmp/bom/.pi/agent/skills/demo/SKILL.md"; then pass "bom-push" "blocked, deployed untouched"
  else fail "bom-push" "blocked but WROTE the bad file"; fi
  if run_at "$tmp/bom" --check --strict; then fail "bom-gate" "canary passed: a BOM green with no drift to blame"; else pass "bom-gate" "caught (encoding, not drift)"; fi

  # 8. A NUL byte means BINARY => the guard abstains, so a binary asset must stay GREEN (a guard that
  #    flags binaries gets muted inside a week, and then it guards nothing).
  mk_tree "$tmp/bin"
  printf 'PNG-ish\x00\x01\x02data\n' > "$tmp/bin/repo/skills/demo/references/asset.bin"
  cp "$tmp/bin/repo/skills/demo/references/asset.bin" "$tmp/bin/.pi/agent/skills/demo/references/asset.bin"
  if run_at "$tmp/bin" --check --strict; then pass "binary" "OK (abstains, no false alarm)"; else fail "binary" "BROKEN: a binary file flagged as an encoding violation"; fi

  # 9. --push converges, is idempotent, and never deploys the artifact set.
  mk_tree "$tmp/push"; rm -f "$tmp/push/.pi/agent/skills/demo/references/notes.md"
  printf '{"hosts":[]}\n' > "$tmp/push/repo/skills/demo/net.json"
  if ! run_at "$tmp/push" --push; then fail "push" "--push failed on a clean tree"
  elif ! run_at "$tmp/push" --check --strict; then fail "push" "still drifting after --push"
  elif [ -e "$tmp/push/.pi/agent/skills/demo/net.json" ]; then fail "push" "deployed an artifact (net.json)"
  else pass "push" "converged + idempotent, artifacts not deployed"; fi

  # 10. --pull captures a seat-side edit into the repo WORKING TREE (and does not commit, and does not
  #     restore a zero-byte marker). Byte-compare via cmp, NOT `[ "$(cat f)" = ... ]` — on a Git-Bash
  #     seat the command substitution eats CR, so the naive form can report a byte-differing file as a
  #     match (that lie is documented in bad_encoding above and in CONVENTIONS §6).
  mk_tree "$tmp/pull"
  printf 'captured on the seat\n' > "$tmp/pull/.pi/agent/skills/demo/references/notes.md"
  if ! run_at "$tmp/pull" --pull; then fail "pull" "--pull failed"
  elif ! cmp -s "$tmp/pull/repo/skills/demo/references/notes.md" "$tmp/pull/.pi/agent/skills/demo/references/notes.md"; then fail "pull" "ran but captured the wrong bytes"
  elif ! run_at "$tmp/pull" --check --strict; then fail "pull" "green contract broke after capturing"
  else pass "pull" "captured into the working tree"; fi

  printf '\nself-test: %s\n' "$([ "$fails" -eq 0 ] && echo "OK — all canaries caught" || echo "$fails canary/canaries NOT caught")"
  return "$fails"
}

# ================================ dispatch ======================================
if [ "$MODE" = "selftest" ]; then
  self_test; exit $?
fi

rc=0
case "$MODE" in
  check)
    [ -d "$REPO/skills" ] || { err "no skills/ at $REPO — run from a homelab clone"; exit 1; }
    if [ ! -d "$DEPLOY" ]; then
      info "deploy target missing: $DEPLOY (nothing deployed yet)"
      info "hint: run 'sync-skills.sh --push' to populate, or re-run install-pi-wsl.sh"
      rc=1
    else
      info "comparing repo skills/  <->  deployed ($DEPLOY)"
      compare
      rc=$?
    fi
    v="$(encoding_violations)"
    if [ "$v" -gt 0 ]; then
      err "$v encoding violation(s) in repo skills/"
      [ "$STRICT" -eq 1 ] && rc=1
    fi
    if [ "$STRICT" -eq 1 ] && [ "$rc" -eq 0 ]; then
      info "OK: repo skills == deployed (no drift, no encoding violations)"
    fi
    [ "$rc" -ne 0 ] && info "drift detected — run --push to deploy or --pull to capture"
    exit "$rc"
    ;;
  push) do_push ; rc=$? ;;
  pull) do_pull ; rc=$? ;;
esac
exit "$rc"