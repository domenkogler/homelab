#!/usr/bin/env bash
# =====================================================================
# seed-seat-ssh-config.sh — the ALIAS-CONTRACT PLANE (HD-1123): render ssh/aliases.tmpl for one
# seat class and write the result as ONE marker-delimited block in that seat's ~/.ssh/config.
#
# WHY THIS EXISTS. docs/network-vpn.md §The laptop alias contract is the prose SSOT for the human
# aliases, and until 2026-10-09 the blocks themselves existed only as three hand-kept seat files.
# The measured drift (2026-10-09): the Windows copy carried a DUPLICATE `Host ap-dnevna` and no
# `ap-spare`; the WSL copy still logged `Host pi99` in as the Pi `admin` account HD-443 neutralized;
# the cockpit seat had no self-alias, so `ssh oldsrv` from the box the shell was standing on died
# `domen@oldsrv: Permission denied`. Prose cannot fail, so none of it was ever reported. This script
# is the part of the contract that CAN fail.
#
# THE VERDICTS ARE THE DESIGN. A block can be absent, current, stale (the repo moved) or EDITED BY
# A HAND. The first three are machine states; the fourth is a human decision and this script never
# overwrites it:
#   IN SYNC        the block, its seat class and its digest all match the render           rc 0
#   MISSING/STALE  no block here, or our own block predating ssh/aliases.tmpl              rc 1
#   REFUSAL        hand-edited block / another seat class installed here / an alias of ours
#                  also declared outside the markers (`SHADOW` = the duplicate-Host class) rc 3
#   (rc 2 = usage, or a render that failed its own assertions — nothing is ever written then.)
# --push writes in the first two states and REFUSES in the third. The digest is what makes "stale,
# replace it" distinguishable from "a human edited this, stop": seed-runner-ssh.sh can replace its
# own region because it is one known block; a 30-line alias block cannot be re-written on the theory
# that any difference is staleness. `--force` overrides ONLY the hand-edit verdict — never a class
# mismatch, never a shadow.
#
# IT OWNS ITS MARKERS AND NOTHING ELSE. Everything outside `# >>> alias-contract … <<<` is copied
# through byte for byte, so a seat's `Host ilo4`, `Host SB-Backup`, the 1Password `Include` and
# another script's `Host github.com` block (seed-seat-deploy-key.sh, HD-449) survive untouched;
# --self-test proves it by diffing the outside-marker text before and after a write. Every write
# keeps a dated `~/.ssh/config.bak-<UTC>` beside the file first, and re-reads the file to confirm
# the digest it intended to land actually landed.
#
# NO LIVE LEG IS PROVEN HERE. This writes a CONFIG; it tests no route and never reads or writes a
# key. Whether the identity the block names exists on the seat is
# docs/network-vpn.md §Canonical identity file names + §The Win11 `~/.ssh` retirement list, and that
# ORDER is the safety property (HD-443's place-then-remove): put the canonically-named key in place
# and prove it, THEN push this plane, THEN move the old file name aside.
#
# Usage:
#   bash scripts/seed-seat-ssh-config.sh                    # detect the seat class, report (--check)
#   bash scripts/seed-seat-ssh-config.sh --push             # write the block
#   bash scripts/seed-seat-ssh-config.sh --seat cockpit --check
#   bash scripts/seed-seat-ssh-config.sh --render           # print the block, write nothing
#   bash scripts/seed-seat-ssh-config.sh --self-test        # fixture HOMEs, no network, no $HOME
# Detection: a Windows seat is `laptop-win11`, WSL is `laptop-wsl`; any other host must name its
# class, because "a Debian box" is exactly as likely to be a runner as the cockpit seat, and a guess
# would rewrite the wrong file.
#
# Env (for the self-test's fixtures): SEAT_SSH_CONFIG (the target file), SEAT_ALIASES_TMPL (the
# template). `sha256sum` is required: no digest, no verdict — fail loud rather than guess.
#
# ⚠ Row: scripts/README.md · Plane doc: docs/network-vpn.md §The alias-contract plane.
# HD-1118 Stage 3 relocates this file to `scripts/harness/` — the path moves, the contract does not.
# =====================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
TMPL="${SEAT_ALIASES_TMPL:-$SCRIPT_DIR/../ssh/aliases.tmpl}"
CFG="${SEAT_SSH_CONFIG:-$HOME/.ssh/config}"
HD="HD-1123"
MARK_START="# >>> alias-contract: $HD >>>"
MARK_END="# <<< alias-contract: $HD <<<"
MODE="check"; WANT_CLASS=""; FORCE=0
SCRATCH=""

# The canonical identity file names, identical on every seat (owner ruling 2026-10-09,
# docs/network-vpn.md §Canonical identity file names). The render refuses any other value, so a key
# name can enter this plane only by being listed here and in that table.
CANON_IDENT_FILES="domen_ssh domen_ssh.pub ansible-admin_ssh ansible-admin_ssh.pub"

usage() {
  cat <<'EOF'
usage: seed-seat-ssh-config.sh [--check] | --push | --render | --self-test [--seat CLASS] [--force]
  CLASS = laptop-win11 | laptop-wsl | cockpit     (auto-detected on the two laptop seats)
  --check  report only, write nothing  ·  --push  write the marker block, backing the file up first
  --render print the rendered block    ·  --self-test  fixture HOMEs, offline
exit: 0 in sync · 1 missing or stale · 2 usage / a render that failed its assertions ·
      3 REFUSAL (hand-edit, seat-class mismatch, or a shadowing block)
EOF
}

err() { printf 'seed-seat-ssh-config: %s\n' "$*" >&2; }
# Sets the global; NEVER call it as $(scratch) — a command substitution would set SCRATCH in the
# subshell only and every later "$SCRATCH/..." would resolve to /... (measured: `/next: Permission
# denied` in the write path, which then reported a write that never happened).
scratch() {
  [ -n "$SCRATCH" ] && return 0
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/seatssh.XXXXXX")" || { err "mktemp failed"; exit 2; }
  mkdir -p "$SCRATCH"
}
cleanup() { [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; }
trap cleanup EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE="check" ;;
    --push) MODE="push" ;;
    --render) MODE="render" ;;
    --self-test) MODE="selftest" ;;
    --force) FORCE=1 ;;
    --seat) WANT_CLASS="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
  shift
done
case "$WANT_CLASS" in ""|laptop-win11|laptop-wsl|cockpit) ;; *)
  err "--seat must be laptop-win11 | laptop-wsl | cockpit, got '$WANT_CLASS'"; exit 2 ;;
esac
command -v sha256sum >/dev/null 2>&1 || { err "sha256sum is required — the digest verdict cannot be computed"; exit 2; }
[ -r "$TMPL" ] || { err "template not readable: $TMPL"; exit 2; }

# --- the seat-class table ------------------------------------------------------
# These values ARE the seat deltas; everything else in the template is common. Two axes:
#  * which leg a name reaches — jump vs on-site-direct, and the Mgmt set a host seat does not have;
#  * which FORM an identity takes here — a real key file vs the 1Password `.pub` hint the Windows
#    agent serves (docs/deployment-secrets.md §What actually raises a 1Password prompt: the same
#    `.pub` that Windows OpenSSH authenticates with, Git-Bash's ssh cannot load at all — HD-492).
seat_vars() {
  V_IDENT='~/.ssh/domen_ssh'                  # operator identity: a PRIVATE half on every seat
  V_PI_PAT=''; V_PI_HN='10.10.1.20'; V_PI_USER='domen'; V_PI_ID='~/.ssh/domen_ssh'
  V_NAS_PAT=''; V_NAS_HN='10.10.1.10'
  V_SPARK_PAT=''; V_SPARK_HN='10.10.1.40'
  V_OLDSRV_PAT='oldsrv oldsrv.kogler.si 10.10.1.30'; V_OLDSRV_HN='10.10.1.30'
  case "$1" in
    laptop-win11) V_ADMIN='~/.ssh/ansible-admin_ssh.pub' ;;
    laptop-wsl)   V_ADMIN='~/.ssh/ansible-admin_ssh' ;;
    cockpit)
      V_ADMIN='~/.ssh/ansible-admin_ssh'
      # On-site: no jump anywhere, the FQDN+address spellings ride the alias line, no Mgmt set.
      V_PI_PAT='pi.kogler.si 10.10.1.20'; V_PI_HN='pi.kogler.si'; V_PI_USER='ansible-admin'
      V_PI_ID='~/.ssh/ansible-admin_ssh'
      V_NAS_PAT='nas.kogler.si 10.10.1.10'; V_NAS_HN='nas.kogler.si'
      V_SPARK_PAT='spark.kogler.si 10.10.1.40'; V_SPARK_HN='spark.kogler.si'
      ;;
    *) return 1 ;;
  esac
}

detect_class() {
  case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) printf 'laptop-win11\n'; return 0 ;; esac
  if [ -r /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
    printf 'laptop-wsl\n'; return 0
  fi
  printf '\n'
}

# --- the template engine (three rules; the grammar is written in ssh/aliases.tmpl) ---
render_body() {
  local class="$1" line active=1 open=0 c rest
  seat_vars "$class" || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '#% seat:'*)
        open=0; active=0; rest="${line#\#% seat:}"
        for c in $rest; do [ "$c" = "$class" ] && { active=1; open=1; }; done
        continue ;;
      '#% end')
        open=0; active=1; continue ;;
      '#%'*)
        # The match is EXACT on purpose: a directive that merely BEGINNED with `#% end` would let a
        # typo close a region and land a half-rendered contract on a seat (self-test arm 7e).
        err "ssh/aliases.tmpl: unrecognized directive '$line' — the only directives are '#% seat: <classes>' and '#% end'"; return 1 ;;
    esac
    [ "$active" = 1 ] || continue
    line="${line//@IDENT@/$V_IDENT}"
    line="${line//@ADMIN@/$V_ADMIN}"
    line="${line//@PI_PAT@/$V_PI_PAT}"; line="${line//@PI_HN@/$V_PI_HN}"
    line="${line//@PI_USER@/$V_PI_USER}"; line="${line//@PI_ID@/$V_PI_ID}"
    line="${line//@NAS_PAT@/$V_NAS_PAT}"; line="${line//@NAS_HN@/$V_NAS_HN}"
    line="${line//@SPARK_PAT@/$V_SPARK_PAT}"; line="${line//@SPARK_HN@/$V_SPARK_HN}"
    line="${line//@OLDSRV_PAT@/$V_OLDSRV_PAT}"; line="${line//@OLDSRV_HN@/$V_OLDSRV_HN}"
    line="${line%"${line##*[![:space:]]}"}"      # a var expanding empty must not leave trailing space
    case "$line" in
      # the PLACEHOLDER SHAPE, not merely an at-sign: a typo'd or unknown name must fail the render
      # instead of landing in a seat config as the literal text `@PI_HN@`.
      *'@'[A-Za-z0-9_]*'@'*) err "render left a placeholder unresolved: $line"; return 1 ;;
    esac
    printf '%s\n' "$line"
  done < "$TMPL"
  [ "$open" = 0 ] || { err "ssh/aliases.tmpl: a '#% seat:' region is unterminated at EOF"; return 1; }
  return 0
}

# The assertions. They run on EVERY render — including the one about to be written — because a
# check that only runs in --self-test is a check a template edit can silently disable.
assert_body() {
  local class="$1" f="$2" bad=0 dups v base ok c2 njump
  dups="$(awk '/^Host /{for(i=2;i<=NF;i++) print $i}' "$f" | sort | uniq -d | tr '\n' ' ')"
  if [ -n "$dups" ]; then
    err "FAIL: an alias is declared TWICE in one render: $dups — the duplicate-Host class (first match wins per keyword, so the later block is inert and every future edit lands in the wrong one)"
    bad=1
  fi
  local pj99
  pj99="$(awk '
    /^Host /{ if (n && (hn ~ /10\.10\.99\./ || hl ~ /10\.10\.99\./) && pj) print name
              hl=$0; name=$2; n=1; hn=""; pj=0 }
    /^[[:space:]]*HostName /{ hn=$2 }
    /^[[:space:]]*ProxyJump /{ pj=1 }
    END{ if (n && (hn ~ /10\.10\.99\./ || hl ~ /10\.10\.99\./) && pj) print name }' "$f" | tr '\n' ' ')"
  if [ -n "$pj99" ]; then
    err "FAIL: ProxyJump on a Mgmt-plane (10.10.99.x) alias: $pj99 — the plane is sealed from the VPS tunnel on purpose (HD-398 A); the hop cannot work and it turns a fast failure into a ~90 s banner timeout"
    bad=1
  fi
  while read -r v; do
    case "$v" in
      # the pattern is QUOTED: an unquoted `~` in a case pattern is tilde-expanded by the shell,
      # which would compare the value against this seat's own home and call every render defective.
      "~/.ssh/"*) ;;
      *) err "FAIL: IdentityFile '$v' is not a ~/.ssh/ path — an alias block must survive a different \$HOME on another seat"; bad=1; continue ;;
    esac
    base="${v##*/}"; ok=0
    for c2 in $CANON_IDENT_FILES; do [ "$base" = "$c2" ] && ok=1; done
    [ "$ok" = 1 ] || { err "FAIL: IdentityFile '$v' names no canonical identity — see docs/network-vpn.md §Canonical identity file names"; bad=1; }
  done < <(awk '/^[[:space:]]*IdentityFile /{print $2}' "$f")
  njump="$(grep -c '^  ProxyJump ' "$f" || true)"
  if [ "$class" = cockpit ] && [ "$njump" != 0 ]; then
    err "FAIL: the cockpit class carries $njump ProxyJump line(s) — it sits ON the Home VLAN, so a jump hairpins through the VPS to reach a box the shell is already on"; bad=1
  fi
  if [ "$class" != cockpit ] && [ "$njump" -lt 6 ]; then
    err "FAIL: the $class class carries only $njump ProxyJump lines (expect >= 6: pi/nas/oldsrv/spark + oldsrv-domen + the four typed-address blocks)"; bad=1
  fi
  if [ "$class" = cockpit ]; then
    grep -qE '^Host oldsrv' "$f" || { err "FAIL: the cockpit class has no self-alias — the missing block that made "ssh oldsrv" die on its own box"; bad=1; }
    if grep -qE '^Host (pi99|oldsrv99|nas99|router|switch|ap-)' "$f"; then
      err "FAIL: the cockpit class declares a Mgmt alias — measured absent on that seat and unrouted (HD-487); do not add it from a laptop's config"; bad=1
    fi
  else
    grep -qE '^Host ap-spare$' "$f" || { err "FAIL: the $class class has no ap-spare (missing from the Windows copy, measured 2026-10-09)"; bad=1; }
    grep -qE '^Host 10\.10\.1\.40$' "$f" || { err "FAIL: the $class class has no typed-address block for spark's Home leg"; bad=1; }
    # The comparison value is the ACCOUNT name `domen` — the operator is `dome`, the account is
    # `domen`, and a grep for the wrong one makes every laptop render fail for a reason that has
    # nothing to do with the rule (measured 2026-10-09: this typo alone accounted for 20 of the 28
    # self-test failures, because a refused render leaves no file and every later arm then fails too).
    if ! awk '/^Host pi99$/{p=1;next} /^Host /{p=0} p&&/^[[:space:]]*User /{print $2; exit}' "$f"          | grep -qx domen; then
      err "FAIL: Host pi99 does not log in as the domen account — the Pi's 'admin' account is neutralized (HD-443), so a User admin there is a dead alias that reads like a live one"; bad=1
    fi
  fi
  return "$bad"
}

hash_file() { printf '%s\n' "$(cat "$1")" | sha256sum | cut -c1-12; }

# build_block CLASS BLOCKFILE BODYFILE — the render, its assertions, and the digest line.
build_block() {
  local class="$1" block="$2" body="$3" dig
  render_body "$class" > "$body" || return 1
  printf '%s\n' "$(cat "$body")" > "$body"        # exactly one trailing newline: render ≡ extracted
  assert_body "$class" "$body" || return 1
  dig="$(hash_file "$body")"
  { printf '%s\n' "$MARK_START"
    printf '# alias-contract: seat=%s sha256=%s\n' "$class" "$dig"
    cat "$body"
    printf '%s\n' "$MARK_END"; } > "$block"
}

strip_block() {
  awk -v s="$MARK_START" -v e="$MARK_END" '
    $0 == s { inside=1; next } $0 == e { inside=0; next } !inside { print }' "$1"
}
extract_block() {
  awk -v s="$MARK_START" -v e="$MARK_END" '
    $0 == s { inside=1; next } $0 == e { inside=0; next } inside { print }' "$1"
}
installed_dig() {
  extract_block "$1" | grep -v '^# alias-contract: seat=' > "$2" && hash_file "$2"
}

# The aliases our block owns. A foreign block naming one of them is how `Host ap-dnevna` ended up
# twice: two blocks, first-match-wins per keyword, and the second one is silently inert.
find_shadows() {
  local ours="$1" outside="$2"
  # TOKEN equality, compared with comm. A regex over the Host line looks equivalent and is not: the
  # `Host[[:space:]]+` eats the space that the boundary then had to match, so the FIRST alias on a
  # line — exactly the shadow this guard exists to find — never matched. Measured: arm 5a answered
  # rc 0 on a fixture whose entire point was rc 3, i.e. the guard that prevents the duplicate-Host
  # class was itself silently inert.
  comm -12 \
    <(awk '/^Host /{for(i=2;i<=NF;i++) print $i}' "$ours" | sort -u) \
    <(awk '/^[[:space:]]*Host[[:space:]]/{for(i=2;i<=NF;i++) print $i}' "$outside" | sort -u)
}

write_block() {
  local blockfile="$1" tmp ts
  tmp="$SCRATCH/next"
  umask 077
  mkdir -p "$(dirname "$CFG")"
  if [ -f "$CFG" ]; then
    ts="$(date -u +%Y%m%d-%H%M%S)"
    cp -p "$CFG" "$CFG.bak-$ts" && echo "  backup: $CFG.bak-$ts"
    strip_block "$CFG" > "$tmp"
  else
    : > "$tmp"
  fi
  # every byte outside the markers is copied through, never re-typed (self-test case 3)
  cat "$blockfile" >> "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$CFG"
  echo "  wrote $CFG (mode $(stat -c %a "$CFG" 2>/dev/null || stat -f %Lp "$CFG" 2>/dev/null || echo '?'))"
}

# --- one pass against one seat --------------------------------------------------
run_seat() {
  local class="$1" sc s_block s_body s_out s_inst shadows dig_fresh got_class got_dig inst_dig rc=0
  scratch
  sc="$SCRATCH"
  s_block="$sc/block"; s_body="$sc/body"; s_out="$sc/outside"; s_inst="$sc/installed"
  build_block "$class" "$s_block" "$s_body" || { err "the render failed its own assertions — nothing written"; return 2; }
  dig_fresh="$(sed -n 's/.*sha256=\([0-9a-f]*\).*/\1/p' "$s_block" | head -1)"

  if [ -f "$CFG" ]; then
    strip_block "$CFG" > "$s_out"
    shadows="$(find_shadows "$s_block" "$s_out")"
  else
    : > "$s_out"; shadows=""
  fi

  if [ ! -f "$CFG" ]; then
    printf 'MISSING: %s does not exist — this seat has never been seeded with the alias-contract block\n' "$CFG"
    rc=1
  elif ! grep -qxF "$MARK_START" "$CFG"; then
    printf 'MISSING: %s carries no alias-contract block — the hand-kept aliases are still the only copy\n' "$CFG"
    rc=1
  else
    inst_dig="$(installed_dig "$CFG" "$s_inst")"
    got_class="$(sed -n 's/^# alias-contract: seat=\([^ ]*\).*/\1/p' "$CFG" | head -1)"
    got_dig="$(sed -n 's/.*sha256=\([0-9a-f]*\).*/\1/p' "$CFG" | head -1)"
    if [ -z "$got_class" ] || [ -z "$got_dig" ]; then
      printf 'REFUSAL(hand-edit): the block in %s carries no seat/digest line, so it was not written by this script\n' "$CFG"
      printf '  → diff it against `--render --seat %s`, fold what you learned into ssh/aliases.tmpl, then --force\n' "$class"
      rc=3
    elif [ "$got_class" != "$class" ]; then
      printf 'REFUSAL(class): the block here declares seat=%s, you asked for seat=%s\n' "$got_class" "$class"
      printf '  → one HOME is one seat class. Re-run with: --seat %s\n' "$got_class"
      rc=3
    elif [ "$inst_dig" != "$got_dig" ]; then
      printf 'REFUSAL(hand-edit): the installed block hashes %s but declares %s — a human edited it in place\n' "$inst_dig" "$got_dig"
      printf '  → NOTHING was written. Reconcile the edit with ssh/aliases.tmpl, then re-run with --force (backup kept)\n'
      rc=3
    elif [ "$got_dig" != "$dig_fresh" ]; then
      printf 'STALE: the installed block (%s) predates ssh/aliases.tmpl (%s) — replacing it is the fix\n' "$got_dig" "$dig_fresh"
      rc=1
    else
      printf 'IN SYNC: %s carries the alias-contract block for seat=%s (digest %s)\n' "$CFG" "$class" "$dig_fresh"
      rc=0
    fi
  fi

  # The shadow test applies in every state: a hand-kept duplicate is a defect even beside a current block.
  if [ -n "$shadows" ]; then
    printf 'REFUSAL(shadow): these aliases are ALSO declared outside the markers, so writing would create duplicates:\n'
    printf '  %s\n' "$(printf '%s' "$shadows" | tr '\n' ' ')"
    printf '  → the hand-kept copy wins every keyword it sets first, so a second block is inert AND misleading.\n'
    printf '  → move those blocks out (dated .bak copy first), then re-run. The HD-467 `seat-home-leg` block on the\n'
    printf '     cockpit seat and the laptop contract region ARE this plane, hand-kept: superseded on purpose.\n'
    rc=3
  fi

  case "$MODE" in
    check) return "$rc" ;;
    push)
      if [ "$rc" = 0 ]; then
        echo "already current: $CFG carries the $class block — nothing written"
        return 0
      fi
      if [ "$rc" = 3 ] && [ "$FORCE" != 1 ]; then
        echo "REFUSED: nothing written to $CFG (--force overrides a hand-edit only, never a class mismatch or a shadow)"
        return 3
      fi
      write_block "$s_block"
      # verify the write the only way that means anything: re-read and re-hash
      inst_dig="$(installed_dig "$CFG" "$s_inst")"
      if [ "$inst_dig" = "$dig_fresh" ]; then
        echo "seeded and verified: the $class block is in $CFG (digest $inst_dig)"
      else
        err "the written block hashes $inst_dig, not $dig_fresh — inspect $CFG"
        return 1
      fi
      [ "$rc" = 3 ] && echo "  (--force: the hand-edited block was replaced; the backup holds what the human wrote)"
      echo "  ⚠ this wrote a CONFIG, it proved no route. Before any old key name moves:"
      echo "    docs/network-vpn.md §Canonical identity file names + §The Win11 ~/.ssh retirement list"
      return 0 ;;
  esac
  return "$rc"
}

# --- self-test: fixture HOMEs, both directions of every verdict -----------------
selftest() {
  local root fails=0 pass=0 h c1 r cls
  scratch
  root="$SCRATCH"
  mkhome() { local d="$root/$1"; mkdir -p "$d/.ssh"; printf '%s' "$d"; }
  run() { # run <label> <expected-rc> <home> <args...>
    local label="$1" want="$2" home="$3"; shift 3
    local rc=0
    HOME="$home" bash "$SELF" "$@" >"$root/out" 2>"$root/err" || rc=$?
    if [ "$rc" = "$want" ]; then pass=$((pass+1)); printf 'ok   %s (rc %s)\n' "$label" "$rc"
    else fails=$((fails+1)); printf 'FAIL %s: rc %s, wanted %s\n' "$label" "$rc" "$want"
      sed 's/^/     | /' "$root/out" 2>/dev/null | head -6
      sed 's/^/     ! /' "$root/err" 2>/dev/null | head -6; fi
  }
  probe() { # probe <expected-rc> <home> <tmpl> — a poisoned render, verdict + message checked by the caller
    local want="$1" home="$2" tmpl="$3" rc=0
    SEAT_ALIASES_TMPL="$tmpl" HOME="$home" bash "$SELF" --seat laptop-win11 --push >"$root/out" 2>&1 || rc=$?
    printf '%s' "$rc"
  }
  has() { if grep -qE "$3" "$2"; then pass=$((pass+1)); printf 'ok   %s\n' "$1"
          else fails=$((fails+1)); printf 'FAIL %s: %s lacks /%s/\n' "$1" "$2" "$3"; fi; }
  lacks() { if grep -qE "$3" "$2"; then fails=$((fails+1)); printf 'FAIL %s: %s must NOT contain /%s/\n' "$1" "$2" "$3"
            else pass=$((pass+1)); printf 'ok   %s\n' "$1"; fi; }
  strip_out() { awk -v s="$MARK_START" -v e="$MARK_END" \
    '$0==s{i=1;next} $0==e{i=0;next} !i{print}' "$1"; }

  # 1. CLEAN SEAT — red BEFORE the write, green after, and a re-push that changes no byte.
  h="$(mkhome clean)"
  run "1a clean seat: --check is MISSING (rc 1)" 1 "$h" --seat laptop-wsl --check
  run "1b clean seat: --push writes" 0 "$h" --seat laptop-wsl --push
  run "1c the same seat is now IN SYNC (rc 0)" 0 "$h" --seat laptop-wsl --check
  c1="$root/after-first"; cp -p "$h/.ssh/config" "$c1"
  run "1d a re-push is a no-op (rc 0)" 0 "$h" --seat laptop-wsl --push
  if cmp -s "$c1" "$h/.ssh/config"; then pass=$((pass+1)); echo "ok   1e the re-push changed no byte (idempotent)"
  else fails=$((fails+1)); echo "FAIL 1e the re-push changed the file — the script is not idempotent"; fi
  # A FIRST write has nothing to back up; demanding a `.bak-` of a file that never existed would be
  # noise. The backup rule itself is proved in arms 3f and 4g, where a real file was overwritten.
  if ls "$h/.ssh/" | grep -q 'config\.bak-' || [ ! -f "$h/.ssh/config" ]; then
    fails=$((fails+1)); echo "FAIL 1f a first write either invented a backup or wrote no file"
  else
    mode6="$(stat -c %a "$h/.ssh/config" 2>/dev/null || stat -f %Lp "$h/.ssh/config" 2>/dev/null || echo '?')"
    if [ "$mode6" = 600 ]; then pass=$((pass+1)); echo "ok   1f the new config is mode 600 and no phantom backup was written"
    elif case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) true ;; *) false ;; esac \
         && chmod 600 "$h/.ssh/config" 2>/dev/null; then
      # MSYS derives the reported mode from the ACL and does not honour a mode bit deny-write, so a
      # 644 here is the platform talking, not the script. Say WHICH it is instead of passing silently:
      # the strict read-back only means anything on a POSIX seat (self-test arm 1f, WSL/Debian).
      pass=$((pass+1)); echo "ok   1f chmod 600 succeeded; MSYS reports mode $mode6 from the ACL — the strict read-back runs on a Debian seat"
    else fails=$((fails+1)); echo "FAIL 1f the new config is mode $mode6, not 600, and chmod 600 did not succeed"; fi
  fi

  # 2. MISSING-BLOCK CAUGHT — in a non-empty config, both directions.
  h="$(mkhome missing)"
  printf 'Host something-else\n  HostName anywhere\n' > "$h/.ssh/config"
  run "2a a config with no block is MISSING (rc 1)" 1 "$h" --seat cockpit --check
  run "2b push it" 0 "$h" --seat cockpit --push
  run "2c ... and now the check is green (rc 0)" 0 "$h" --seat cockpit --check

  # 3. FOREIGN CONFIG UNTOUCHED — everything outside the markers must survive byte for byte.
  h="$(mkhome foreign)"
  cat > "$h/.ssh/config" <<'FIX'
Include ~/.ssh/1Password/config
Host ilo4
  HostName 10.10.1.49
  User admin
  IdentityFile ~/.ssh/id_rsa_ilo
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/github_auth
  IdentitiesOnly yes
FIX
  cp -p "$h/.ssh/config" "$root/foreign-before"
  run "3a push over a foreign config" 0 "$h" --seat laptop-win11 --push
  strip_out "$h/.ssh/config" > "$root/foreign-after"
  if [ "$(cat "$root/foreign-before")" = "$(cat "$root/foreign-after")" ]; then
    pass=$((pass+1)); echo "ok   3b nothing outside the markers changed"
  else fails=$((fails+1)); echo "FAIL 3b the script changed text outside its markers"
       diff "$root/foreign-before" "$root/foreign-after" | head -6; fi
  has  "3c the foreign Host ilo4 block is intact" "$h/.ssh/config" '^Host ilo4$'
  has  "3d the 1Password Include is intact" "$h/.ssh/config" '^Include ~/\.ssh/1Password/config$'
  has   "3e the foreign block's own identity line is intact (we never repoint a key we do not own)" "$h/.ssh/config" '^  IdentityFile ~/\.ssh/id_rsa_ilo$'
  if ls "$h/.ssh/" | grep -q 'config\.bak-[0-9]'; then pass=$((pass+1)); echo "ok   3f the replaced config kept a dated .bak-<UTC> copy beside it"
  else fails=$((fails+1)); echo "FAIL 3f a config was overwritten with no dated backup"; fi

  # 4. HAND-EDIT → REFUSAL, plus the proof that the refusal really refused.
  h="$(mkhome handedit)"
  run "4a seed first" 0 "$h" --seat laptop-wsl --push
  grep -v '^  ProxyJump vps$' "$h/.ssh/config" > "$root/he" && mv "$root/he" "$h/.ssh/config"
  cp -p "$h/.ssh/config" "$root/he-before"
  run "4b --check sees the hand-edit (rc 3)" 3 "$h" --seat laptop-wsl --check
  run "4c --push REFUSES it (rc 3)" 3 "$h" --seat laptop-wsl --push
  if cmp -s "$root/he-before" "$h/.ssh/config"; then pass=$((pass+1)); echo "ok   4d the refused file is byte-identical (no silent overwrite)"
  else fails=$((fails+1)); echo "FAIL 4d the refusal still wrote the file"; fi
  nb0="$(ls "$h/.ssh/" | grep -c 'config\.bak-[0-9]')"
  run "4e --force replaces it when a human says so" 0 "$h" --seat laptop-wsl --push --force
  run "4f ... and the seat reads IN SYNC afterwards" 0 "$h" --seat laptop-wsl --check
  nb1="$(ls "$h/.ssh/" | grep -c 'config\.bak-[0-9]')"
  if [ "$nb1" -gt "$nb0" ]; then pass=$((pass+1)); echo "ok   4g the --force write added its own backup ($nb0 → $nb1)"
  else fails=$((fails+1)); echo "FAIL 4g --force replaced a human edit and the backup count stayed $nb1"; fi

  # 5. SHADOW — the duplicate-Host class itself, both directions.
  h="$(mkhome shadow)"
  printf 'Host oldsrv-elsewhere\n  HostName x\nHost nas\n  HostName 10.10.1.10\n  User ansible-admin\n' > "$h/.ssh/config"
  cp -p "$h/.ssh/config" "$root/shadow-before"
  run "5a a hand-kept copy of our alias is a REFUSAL (rc 3)" 3 "$h" --seat cockpit --push
  if cmp -s "$root/shadow-before" "$h/.ssh/config"; then pass=$((pass+1)); echo "ok   5b the shadowing file was left exactly as found"
  else fails=$((fails+1)); echo "FAIL 5b the script wrote beside a shadow it detected"; fi
  printf 'Host oldsrv-elsewhere\n  HostName x\n' > "$h/.ssh/config"
  run "5c with the shadow removed the push succeeds (rc 0)" 0 "$h" --seat cockpit --push

  # 6. PER-SEAT-CLASS correctness, and the class-mismatch guard.
  for cls in laptop-win11 laptop-wsl cockpit; do
    h="$(mkhome "class-$cls")"
    run "6a $cls renders, writes, and reads IN SYNC" 0 "$h" --seat "$cls" --push
  done
  has   "6b win11 serves the admin leg from the 1Password .pub hint" "$root/class-laptop-win11/.ssh/config" 'IdentityFile ~/\.ssh/ansible-admin_ssh\.pub$'
  has   "6c wsl serves it from a real key file" "$root/class-laptop-wsl/.ssh/config" 'IdentityFile ~/\.ssh/ansible-admin_ssh$'
  lacks "6d wsl never points at a .pub its ssh cannot load (HD-492)" "$root/class-laptop-wsl/.ssh/config" 'IdentityFile ~/\.ssh/[a-z0-9-]+\.pub$'
  has   "6e the laptop classes jump the Home legs" "$root/class-laptop-wsl/.ssh/config" '^  ProxyJump vps$'
  lacks "6f the cockpit class jumps nothing (the directive, not the word in a comment)" "$root/class-cockpit/.ssh/config" '^[[:space:]]*ProxyJump'
  has   "6g the cockpit class owns a self-alias as dome" "$root/class-cockpit/.ssh/config" '^Host oldsrv oldsrv\.kogler\.si 10\.10\.1\.30$'
  lacks "6h the cockpit class declares no Mgmt alias" "$root/class-cockpit/.ssh/config" '^Host (pi99|oldsrv99|nas99|router|switch|ap-)'
  lacks "6i no class logs into the Pi as the neutralized admin" "$root/class-laptop-win11/.ssh/config" '^  User admin$'
  has   "6j ap-spare is declared (it was missing on Windows)" "$root/class-laptop-win11/.ssh/config" '^Host ap-spare$'
  h="$(mkhome mismatch)"
  run "6k seed as laptop-wsl" 0 "$h" --seat laptop-wsl --push
  run "6l asking for cockpit on that HOME is a REFUSAL (rc 3)" 3 "$h" --seat cockpit --check

  # 7. THE ASSERTIONS ARE LOAD-BEARING. Each poison must be CAUGHT, and one control must NOT be,
  #    or the assertions prove nothing (CONVENTIONS: a test that cannot fail is not evidence).
  local pt="$root/poison.tmpl"
  sed 's/^Host pi99$/Host pi99\n  ProxyJump vps/' "$TMPL" > "$pt"
  h="$(mkhome poison-jump)"
  [ "$(probe 2 "$h" "$pt")" = 2 ] && grep -q 'ProxyJump on a Mgmt-plane' "$root/out" \
    && { pass=$((pass+1)); echo "ok   7a a ProxyJump put on a Mgmt (10.10.99.x) alias is CAUGHT"; } \
    || { fails=$((fails+1)); echo "FAIL 7a the no-ProxyJump-on-.99 assertion did not fire:"; sed 's/^/     | /' "$root/out" | head -5; }
  sed 's/^Host spark @SPARK_PAT@$/Host spark @SPARK_PAT@\n  ProxyJump nas/' "$TMPL" > "$pt"
  h="$(mkhome poison-control)"
  [ "$(probe 0 "$h" "$pt")" = 0 ] && ! grep -q 'ProxyJump on a Mgmt-plane' "$root/out" \
    && { pass=$((pass+1)); echo "ok   7b control: a jump on a HOME-leg alias does NOT trip the .99 rule (it keys on the address)"; } \
    || { fails=$((fails+1)); echo "FAIL 7b the control fired — the .99 rule is really a 'no ProxyJump anywhere' rule:"; sed 's/^/     | /' "$root/out" | head -5; }
  sed 's#^  IdentityFile @IDENT@$#  IdentityFile ~/.ssh/id_ed25519#' "$TMPL" > "$pt"
  h="$(mkhome poison-name)"
  [ "$(probe 2 "$h" "$pt")" = 2 ] && grep -q 'names no canonical identity' "$root/out" \
    && { pass=$((pass+1)); echo "ok   7c an IdentityFile naming a non-canonical key is CAUGHT"; } \
    || { fails=$((fails+1)); echo "FAIL 7c the identity-name assertion did not fire:"; sed 's/^/     | /' "$root/out" | head -5; }
  sed '$d' "$TMPL" > "$pt"                      # the template's last line is the Mgmt region's `#% end`
  h="$(mkhome poison-region)"
  [ "$(probe 2 "$h" "$pt")" = 2 ] && grep -q 'unterminated' "$root/out" \
    && { pass=$((pass+1)); echo "ok   7d an unterminated region is CAUGHT (a silently half-written contract is the worse failure)"; } \
    || { fails=$((fails+1)); echo "FAIL 7d the region guard did not fire:"; sed 's/^/     | /' "$root/out" | head -5; }
  sed 's/^#% end$/#% endd/' "$TMPL" > "$pt"     # a directive the renderer does not know
  h="$(mkhome poison-directive)"
  [ "$(probe 2 "$h" "$pt")" = 2 ] && grep -q 'unrecognized directive' "$root/out" \
    && { pass=$((pass+1)); echo "ok   7e a typo'd directive is REFUSED, never obeyed as an end"; } \
    || { fails=$((fails+1)); echo "FAIL 7e the unknown-directive guard did not fire:"; sed 's/^/     | /' "$root/out" | head -5; }
  sed 's/^Host ap-dnevna$/Host ap-dnevna\nHost ap-dnevna/' "$TMPL" > "$pt"
  h="$(mkhome poison-dup)"
  [ "$(probe 2 "$h" "$pt")" = 2 ] && grep -q 'declared TWICE' "$root/out" \
    && { pass=$((pass+1)); echo "ok   7f a duplicated Host alias in the template is CAUGHT (the ap-dnevna class)"; } \
    || { fails=$((fails+1)); echo "FAIL 7f the duplicate-alias assertion did not fire:"; sed 's/^/     | /' "$root/out" | head -5; }

  # 8. the three renders differ ONLY where the seat class says they may.
  for cls in laptop-win11 laptop-wsl cockpit; do
    h="$(mkhome "render-$cls")"
    HOME="$h" bash "$SELF" --seat "$cls" --render > "$root/render-$cls.txt" 2>/dev/null
  done
  # ⚠ `diff … | grep -q` is a trap under `set -o pipefail`: grep -q exits at its first match, diff
  # then dies of SIGPIPE, and the PIPELINE status becomes 141 — so a diff that DID find the line
  # reports failure. This single pipeline was arm 8a's whole defect; capture the text, match that.
  local d8; d8="$(diff "$root/render-laptop-win11.txt" "$root/render-laptop-wsl.txt" || true)"
  case "$d8" in
    *'IdentityFile '*)
      pass=$((pass+1)); echo "ok   8a the two laptop renders differ in an IdentityFile (the .pub/private axis is real)" ;;
    *) fails=$((fails+1)); echo "FAIL 8a the two laptop renders are identical — the identity-form axis is not real" ;;
  esac
  local ncockpit nlaptop
  ncockpit="$(grep -c '^Host ' "$root/render-cockpit.txt")"
  nlaptop="$(grep -c '^Host ' "$root/render-laptop-wsl.txt")"
  if [ "$ncockpit" -lt "$nlaptop" ]; then
    pass=$((pass+1)); echo "ok   8b the cockpit render is a strict subset of the laptop one ($ncockpit < $nlaptop blocks — the Mgmt set is the delta)"
  else fails=$((fails+1)); echo "FAIL 8b cockpit $ncockpit vs laptop $nlaptop blocks — the seat-class axis did not shrink anything"; fi

  printf '\nself-test: %s (%d passed, %d failed)\n' \
    "$([ "$fails" -eq 0 ] && echo OK || echo FAILED)" "$pass" "$fails"
  [ "$fails" -eq 0 ]
}

# --- dispatch ------------------------------------------------------------------
case "$MODE" in
  selftest) selftest; exit $? ;;
  render)
    cls="${WANT_CLASS:-$(detect_class)}"
    [ -n "$cls" ] || { err "cannot detect the seat class on this host — pass --seat CLASS"; exit 2; }
    scratch
  sc="$SCRATCH"
    build_block "$cls" "$sc/block" "$sc/body" || exit 2
    cat "$sc/block"
    exit 0 ;;
esac

CLASS="$WANT_CLASS"
if [ -z "$CLASS" ]; then
  CLASS="$(detect_class)"
  if [ -z "$CLASS" ]; then
    err "cannot detect the seat class on a Debian host — it is either the cockpit seat or a runner; pass --seat cockpit"
    exit 2
  fi
fi
echo "seat class: $CLASS  (target: $CFG, mode: $MODE)"
run_seat "$CLASS"
exit $?
