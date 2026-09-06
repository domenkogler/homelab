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
#   - .env.op                (mikrotik op:// credential file — giteignored local runtime state)
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
    .env.op) return 0 ;;   # mikrotik op:// credential file — local runtime state (giteignored)
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
  if [ "$(head -c3 "$p" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "efbbbf" ]; then
    return 0   # UTF-8 BOM
  fi
  LC_ALL=C grep -q $'\r' "$p" 2>/dev/null && return 0   # CRLF
  return 1
}

# --- repo file list: "NAME \t REL \t ABS" (non-artifact, real files) ----------
list_repo_files() {
  local sk name f rel
  for sk in "$REPO"/skills/*/; do
    name="$(basename "$sk")"
    [ "$sk" = "$REPO/skills/*/" ] && continue
    [ -f "$sk/SKILL.md" ] || continue
    while IFS= read -r f; do
      rel="${f#"$sk"}"
      is_artifact "$name" "$rel" "$REPO/skills/$name/$rel" && continue
      printf '%s\t%s\t%s\n' "$name" "$rel" "$REPO/skills/$name/$rel"
    done < <(cd "$sk" && find . -type f | sed 's#^\./##' | sort)
  done
}

# --- deploy file list: same TAB format (includes artifacts for prune) --------
list_deploy_files() {
  local name f rel
  [ -d "$DEPLOY" ] || return 0
  for sk in "$DEPLOY"/*/; do
    name="$(basename "$sk")"
    [ "$sk" = "$DEPLOY/*/" ] && continue
    while IFS= read -r f; do
      rel="${f#"$sk"}"
      printf '%s\t%s\t%s\n' "$name" "$rel" "$DEPLOY/$name/$rel"
    done < <(cd "$sk" && find . -type f | sed 's#^\./##' | sort)
  done
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
    name="$(basename "$sk")"
    [ "$sk" = "$REPO/skills/*/" ] && continue
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
    [ "$n" = "*" ] && continue
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

# ================================ dispatch ======================================
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