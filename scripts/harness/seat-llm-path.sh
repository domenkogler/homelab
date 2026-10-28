#!/usr/bin/env bash
# =====================================================================
# seat-llm-path.sh — the `llm-path` seat plane: which PATH the WSL seat's model lane takes.
#
# WHAT THIS OWNS
# --------------
#   One marker-delimited block in the seat's hosts file that answers the inference name with
#   spark's Home IPv4, and the decision whether that block should exist at all:
#
#     a TCP connect to <spark Home IPv4>:<https port> completes  ->  the pin is in force  (path=lan)
#     it does not                                                ->  no pin, resolution decides (path=edge)
#
#   So the seat uses the LAN answer when the LAN answer WORKS, and the ordinary resolver stack when
#   it does not. Nothing here changes an answer plane: the zone rows, the netmap and the policy are
#   untouched, every other name answers exactly as it did before, and away-from-home behaviour is
#   unchanged. A hosts entry is a SEAT act scoped to one name on one box — that is why this is a seat
#   plane and not a DNS change (docs/network-dns.md §Host-side resolver).
#
# WHY ONE PIN AND NOT A ZONE-WIDE SWITCH
# -------------------------------------
#   Sending all of `*.kogler.si` to the home resolver from a seat was measured and rejected: the LAN
#   tier answers some names with an edge that returns 404 for them where the netmap answer returns
#   200. So the plane pins ONE name, and only while that address answers TCP on the https port.
#
# WHAT IT DOES NOT OWN
# --------------------
#   Not the resolver. The seat's per-link route claim, its resolved drop-in and the 2-minute
#   re-assert timer stay exactly as they are and are NOT touched here — this script writes one hosts
#   block and nothing else, and it installs no unit of its own. Not the answer plane (zone rows,
#   netmap, policy), not the engine, not the certificate.
#
# THE TWO VALUES, READ FROM THE SSOT (CONVENTIONS §2 — no literals in this file)
# -----------------------------------------------------------------------------
#   fqdn  the `name:` of the `zone_kogler_si` row whose label is `llm`. That row must ALSO carry
#         `lan_only: true` (the Home-addressed contract) and an `ip:` naming `spark_home_ip`, so the
#         pin can never answer with an address no plane answers.
#   ip    that host's `network_static_hosts` row with `vlan: 10`.
#   An unreadable, absent, ambiguous or contract-violating row is a STOP (exit 2) and the hosts file
#   is left byte-identical. A guessed value substituted for a row is how a seat ends up pointed at an
#   address that does not exist, silently. The label `llm` and the port 443 are this plane's SUBJECT
#   and an architectural constant — they are not values the SSOT is asked about.
#
# VERDICTS   (`OK` is BYTE equality with what `--push` would write, so "in sync" and "a push changes
#            nothing" are one fact, never two claims that can disagree)
#   OK               the file is what this path calls for
#   MISSING          path=lan and no answer line for the name is in force
#   DRIFT            the answer in force is not the one this path calls for: a wrong or duplicate
#                    address, an EXTRA pin while path=edge, or marker cruft with no answer line
#   DRIFT(shadow)    an entry OUTSIDE the markers, sitting EARLIER in the file, already names the
#                    name — the files backend takes the first match, so writing ours would land a pin
#                    that is inert while the plane reports a pin in place. `--push` REFUSES this one;
#                    a matching entry AFTER our block is printed as a NOTE and changes no verdict.
#
# Exit: 0 OK / repaired · 1 MISSING, or DRIFT under `--strict`, or a `--push` that could not run
#       (the hosts file is root-owned: the push half is a root act on the seat) ·
#       2 NO VERDICT — the SSOT rows cannot be read, the target file cannot be read, or the probe
#       died rather than answered (a dead probe is not evidence of an unreachable path).
#
# Usage:
#   bash scripts/harness/seat-llm-path.sh                     # --check, report only
#   bash scripts/harness/seat-llm-path.sh --check --strict    # the seat-leg form
#   sudo bash scripts/harness/seat-llm-path.sh --push         # write or remove the block
#   bash scripts/harness/seat-llm-path.sh --self-test         # fixtures; no network, nothing under /etc
#
# Env hooks — every one points the script at a FIXTURE; none of them changes a verdict rule:
#   REPO                     a fixture repo whose IaC/ansible/group_vars/all/main.yml is the SSOT
#   SEAT_LLM_HOSTS           the hosts file to read and write (default /etc/hosts)
#   SEAT_LLM_PROBE           an executable called as `PROBE <ip> <port>`, rc 0 = reachable
#   SEAT_LLM_PORT            the probed port (default 443)
#   SEAT_LLM_LABEL           the zone label whose row carries the name (default llm)
#   SEAT_LLM_PROBE_TIMEOUT   seconds the connect probe waits (default 3)
#
# ⚠ Row: scripts/README.md §scripts/harness/ · Registry: scripts/lib/seat-planes.yml ·
#   Rule: docs/network-dns.md §Host-side resolver and docs/harness-pi-seats.md §1.
# =====================================================================
set -uo pipefail

# The repo root is FOUND by scripts/lib/repo-root.sh, never assumed from a depth. An inherited $REPO
# still wins, which is precisely the lever --self-test uses to point at a fixture SSOT.
_hl_self="${BASH_SOURCE[0]}"
case "$_hl_self" in */*) _hl_d="${_hl_self%/*}" ;; *) _hl_d="." ;; esac
_hl_d="$(cd "$_hl_d" && pwd)"
SCRIPT_DIR="$_hl_d"
SELF="$SCRIPT_DIR/$(basename "$_hl_self")"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"

SSOT="$REPO/IaC/ansible/group_vars/all/main.yml"
TARGET="${SEAT_LLM_HOSTS:-/etc/hosts}"
PORT="${SEAT_LLM_PORT:-443}"
LABEL="${SEAT_LLM_LABEL:-llm}"
PROBE_TIMEOUT="${SEAT_LLM_PROBE_TIMEOUT:-3}"
MARK_START='# >>> seat-llm-path >>>'
MARK_END='# <<< seat-llm-path <<<'

MODE="check"; STRICT=0; SCRATCH=""; BLOCK_FILE=""; WANT_FILE=""; SHADOW_LINE=""
FQDN=""; HOME_IP=""; PATH_VERDICT=""; PROBE_RC=""; STATE=""; REASON=""

err()  { printf 'seat-llm-path: %s\n' "$*" >&2; }
note() { printf '  %s\n' "$*"; }
# A STOP, never a report. exit 2 means "no verdict was computed", so nothing downstream may read the
# run as a state. It must run in the CALLER's shell: inside `$( )` an `exit` stops only the subshell
# (the rule lib/pi-seat.sh carries), which is why every read below returns through a variable and
# never through a command substitution.
stop() { printf 'FATAL: %s\n' "$*" >&2; exit 2; }
usage() {
  cat <<'EOF'
usage: seat-llm-path.sh [--check [--strict]] | --push | --self-test

  --check          (default) read the SSOT rows, probe the path, report the hosts-file state
  --check --strict exit 1 on DRIFT too (the seat-leg form; MISSING exits 1 either way)
  --push           write the block while the LAN path answers, remove it when it stops answering
                   (root-owned file: on a seat this is
                    sudo bash scripts/harness/seat-llm-path.sh --push)
  --self-test      fixture repo + fixture hosts file + stub probe; no network, nothing under /etc
EOF
}

scratch() {
  [ -n "$SCRATCH" ] && return 0
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/seat-llm-path.XXXXXX")" || { err "mktemp failed"; exit 2; }
  BLOCK_FILE="$SCRATCH/block"
}
cleanup() { [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; }
trap cleanup EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --check)     MODE="check" ;;
    --strict)    STRICT=1 ;;
    --push)      MODE="push" ;;
    --self-test) MODE="selftest" ;;
    -h|--help)   usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
  shift
done

# --- the SSOT reads ---------------------------------------------------------------
# Both readers take the same shape: find the named top-level key's block, count the rows matching the
# selector, STOP on anything but exactly one. "First of two" is how a renamed row keeps answering
# while the real one is silently ignored.
read_zone_fqdn() {
  [ -r "$SSOT" ] || stop "cannot read the zone/address SSOT at $SSOT — the pin has no source"
  local row rc ipexpr
  row="$(awk -v lbl="$LABEL" '
    $0 ~ "^zone_kogler_si[[:space:]]*:" { inz = 1; next }
    inz && $0 ~ /^[^[:space:]#]/ { inz = 0 }
    inz {
      line = $0; sub(/[[:space:]]*#.*$/, "", line)
      if (line ~ ("^[[:space:]]*-[[:space:]]*\\{[[:space:]]*name:[[:space:]]*" lbl "\\.[^,]*[[:space:]]*,")) { hits++; row = line }
    }
    END { if (hits != 1) exit 3; print row }' "$SSOT")"
  rc=$?
  if [ "$rc" = 3 ]; then
    stop "the zone rows matching the label \"$LABEL.\" are not exactly one row in $SSOT — a pin needs one name, and an ambiguous list is not an answer"
  fi
  [ "$rc" = 0 ] || stop "cannot read $SSOT (the row reader died, rc $rc)"
  # The CR of a CRLF checkout survives a pipe into awk and sits at the end of the captured line
  # (CONVENTIONS §6, the MSYS text-mode trap): strip it before any comparison touches the value.
  row="${row%$'\r'}"
  [[ $row =~ lan_only:[[:space:]]*true ]] \
    || stop "the zone row for \"$LABEL.\" carries no lan_only: true — that flag is the contract that makes a Home address the honest answer for this name, and a seat must not invent one"
  # `tailnet_ip:` ENDS in `ip:`, so neutralise it: "the row's ip:" must mean the row's ip:.
  ipexpr="${row//tailnet_ip:/tailnet_ADDR:}"
  ipexpr="${ipexpr#*ip:}"; ipexpr="${ipexpr%%,*}"
  case "$ipexpr" in
    *spark_home_ip*) : ;;
    *) stop "the zone row for \"$LABEL.\" answers from [$ipexpr] rather than from spark_home_ip — the pin would carry an address no plane answers, which is the black hole the answer-must-be-routable rule refuses" ;;
  esac
  if [[ $row =~ name:[[:space:]]*([^,[:space:]]+) ]]; then FQDN="${BASH_REMATCH[1]}"; else stop "the matched zone row carries no name field"; fi
  [[ $FQDN =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]] \
    || stop "the zone row's name [$FQDN] is not an FQDN — a hosts key that is not one matches nothing, silently"
  return 0
}

read_spark_home_ip() {
  [ -r "$SSOT" ] || stop "cannot read the address SSOT at $SSOT"
  local row rc candidate oct
  row="$(awk '
    $0 ~ "^network_static_hosts[[:space:]]*:" { inz = 1; next }
    inz && $0 ~ /^[^[:space:]#]/ { inz = 0 }
    inz && $0 ~ /(^|[^_[:alnum:]])name:[[:space:]]*spark[[:space:]]*,/ \
        && $0 ~ /(^|[^_[:alnum:]])vlan:[[:space:]]*10[[:space:]]*[,}]/ { hits++; row = $0 }
    END { if (hits != 1) exit 3; print row }' "$SSOT")"
  rc=$?
  if [ "$rc" = 3 ]; then
    stop "the spark vlan-10 row is not exactly one row in $SSOT — that address IS the pin, so an ambiguous address table is a STOP and never a first-of-two"
  fi
  [ "$rc" = 0 ] || stop "cannot read $SSOT (the row reader died, rc $rc)"
  candidate="${row%$'\r'}"
  candidate="${candidate#*ip:}"; candidate="${candidate%%,*}"
  candidate="${candidate//\"/}"; candidate="${candidate//[[:space:]]/}"
  [[ $candidate =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] \
    || stop "the spark vlan-10 row carries [$candidate] as its ip, which is not an IPv4 address"
  for oct in 1 2 3 4; do
    (( BASH_REMATCH[oct] <= 255 )) || stop "the spark vlan-10 row carries an out-of-range octet: [$candidate]"
  done
  [ "$candidate" = "0.0.0.0" ] && stop "the spark vlan-10 row carries the UNSPECIFIED address as its Home address"
  HOME_IP="$candidate"
  return 0
}

# --- the probe -------------------------------------------------------------------
# rc 0 = the path answers · rc 1/124 = refused or timed out, so it does not · ANY OTHER rc = the probe
# itself failed. That last case is NOT a verdict about the path: answering `path=edge` to a broken
# probe would delete a working pin because a tool went missing.
run_probe() {
  if [ -n "${SEAT_LLM_PROBE:-}" ]; then
    [ -x "$SEAT_LLM_PROBE" ] || stop "SEAT_LLM_PROBE [$SEAT_LLM_PROBE] is not an executable — the plane cannot ask whether the path answers"
    "$SEAT_LLM_PROBE" "$HOME_IP" "$PORT" >/dev/null 2>&1
  elif command -v timeout >/dev/null 2>&1; then
    timeout "$PROBE_TIMEOUT" bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$HOME_IP" "$PORT" >/dev/null 2>&1
  else
    bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$HOME_IP" "$PORT" >/dev/null 2>&1
  fi
  PROBE_RC=$?
  case "$PROBE_RC" in
    0)     PATH_VERDICT="lan" ;;
    1|124) PATH_VERDICT="edge" ;;
    *)     stop "the reachability probe died with rc $PROBE_RC instead of answering — a dead probe is not an unreachable path, and no pin is removed on an answer that was never given" ;;
  esac
  return 0
}

# --- the block -------------------------------------------------------------------
# The block is a RENDER. Everything outside the markers is copied through byte for byte, so a line an
# operator wants kept lives outside them; `compose` is the only writer and `--check` OK means
# compose(current) == current.
render_block() {
  { printf '%s\n' "$MARK_START"
    printf '# seat-llm-path: owned by scripts/harness/seat-llm-path.sh — keep your own lines outside these markers.\n'
    printf '# The LAN path to the inference host answers, so it answers %s here; docs/network-dns.md §Host-side resolver.\n' "$FQDN"
    printf '%s %s\n' "$HOME_IP" "$FQDN"
    printf '%s\n' "$MARK_END"; } > "$BLOCK_FILE"
}

# compose <file> <out> — the file with our block replaced by $BLOCK_FILE (an empty block file removes
# it), appended at the end when the file carries no block yet. Awk's `print` always terminates a line, so
# a source file whose last line has no newline gains one; do_push PRINTS that, because it is the one byte
# outside the markers a write can touch.
compose() {
  awk -v s="$MARK_START" -v e="$MARK_END" -v blk="$BLOCK_FILE" '
    function emit() { if (blk != "") { while ((getline l < blk) > 0) print l; close(blk) } }
    BEGIN { seen = 0 }
    !inside && $0 == s { inside = 1; seen = 1; emit(); next }
    inside { if ($0 == e) inside = 0; next }
    !inside { print }
    END { if (!seen) emit() }' "$1" > "$2"
}

# answer_lines <file> — the lines that actually answer: inside our block, neither a comment nor blank.
answer_lines() {
  awk -v s="$MARK_START" -v e="$MARK_END" '
    !inside && $0 == s { inside = 1; next }
    inside && $0 == e { inside = 0; next }
    inside && $0 !~ /^[[:space:]]*$/ && $0 !~ /^[[:space:]]*#/ { print }' "$1"
}

# shadow <file> — `early:` an entry outside our markers that answers the name BEFORE we do, `late:`
# one that sits after it, nothing otherwise. Only `early:` matters: the files backend takes the FIRST
# match, so a pin written behind it is inert while the plane reports a pin in place. When the file
# carries no block yet our lines land at the end, so every match is an early one.
shadow() {
  awk -v s="$MARK_START" -v e="$MARK_END" -v fq="$FQDN" '
    !inside && $0 == s { inside = 1; if (!blockpos) blockpos = NR; next }
    inside && $0 == e { inside = 0; next }
    inside { next }
    { t = $0; sub(/#.*/, "", t); n = split(t, f, /[ \t]+/)
      for (i = 1; i <= n; i++) if (f[i] == fq) { m++; nr[m] = NR; txt[m] = $0; break } }
    END {
      for (i = 1; i <= m; i++)
        if (blockpos == 0 || nr[i] < blockpos) { printf "early:%s: %s\n", nr[i], txt[i]; exit }
      if (m > 0) printf "late:%s: %s\n", nr[1], txt[1]
    }' "$1"
}

# assess — sets STATE (OK | MISSING | DRIFT) and REASON. OK is BYTE equality with what --push writes.
assess() {
  local want have same
  [ -r "$TARGET" ] || stop "cannot read $TARGET — a verdict about a hosts file nobody can read is not a verdict"
  if [ "$PATH_VERDICT" = "lan" ]; then render_block; else : > "$BLOCK_FILE"; fi
  WANT_FILE="$SCRATCH/want"
  compose "$TARGET" "$WANT_FILE"
  cmp -s "$TARGET" "$WANT_FILE"; same=$?
  want="$(answer_lines "$WANT_FILE")"; have="$(answer_lines "$TARGET")"
  SHADOW_LINE="$(shadow "$TARGET")"
  REASON=""
  case "$SHADOW_LINE" in
    early:*) STATE="DRIFT"; REASON="shadow"
             note "shadowed by an entry outside the markers: ${SHADOW_LINE#early:}"
             return 0 ;;
    late:*)  note "NOTE: an entry outside the markers also names $FQDN (${SHADOW_LINE#late:}) — ours is first, so it answers; the other line is a lie waiting for a reorder" ;;
  esac
  if [ "$same" = 0 ]; then STATE="OK"; REASON="in sync"; return 0; fi
  if [ -n "$want" ] && [ -z "$have" ]; then
    STATE="MISSING"; REASON="no answer line in force for $FQDN while path=lan"
  else
    STATE="DRIFT"; REASON="the answer in force is not the one this path calls for"
  fi
  return 0
}

read_inputs() {
  read_zone_fqdn
  read_spark_home_ip
  run_probe
  assess
}

say_verdict() {
  printf 'read: fqdn=%s ip=%s port=%s path=%s probe-rc=%s file=%s\n' \
    "$FQDN" "$HOME_IP" "$PORT" "$PATH_VERDICT" "$PROBE_RC" "$TARGET"
  printf '%s' "$STATE"
  [ -n "$REASON" ] && printf ': %s' "$REASON"
  printf '\n'
}

do_check() {
  say_verdict
  case "$STATE" in
    MISSING) return 1 ;;
    DRIFT)   [ "$STRICT" = 1 ] && return 1; return 0 ;;
    *)       return 0 ;;
  esac
}

do_push() {
  say_verdict
  if [ "$STATE" = "OK" ]; then echo "already in sync: $TARGET needs no change — nothing written"; return 0; fi
  if [ "$REASON" = "shadow" ]; then
    printf 'REFUSAL(shadow): writing would place our answer BEHIND an entry that already names %s, and the files backend takes the first match — the pin would be inert while reported in place.\n' "$FQDN"
    printf '  → move that entry elsewhere in the file (keep a dated .bak), then re-run: sudo bash scripts/harness/seat-llm-path.sh --push\n'
    return 1
  fi
  if [ ! -w "$TARGET" ]; then
    printf 'REFUSAL(not-writable): %s is not writable by this user — the hosts file is root-owned, so the push half is a root act on the seat.\n' "$TARGET"
    printf '  → sudo bash scripts/harness/seat-llm-path.sh --push\n'
    return 1
  fi
  local tmp ts mode
  tmp="$SCRATCH/next"
  compose "$TARGET" "$tmp"
  # The one byte outside the markers a write can touch: an unterminated last line. Say it, do not do it.
  if [ -s "$TARGET" ] && [ -n "$(tail -c1 "$TARGET" 2>/dev/null)" ]; then
    note "the file's last line carried no newline; the write terminates it (an unterminated hosts line is the malformed case, not a shape to preserve)"
  fi
  if cmp -s "$TARGET" "$tmp"; then
    echo "already in sync: $TARGET needs no change — nothing written"
    return 0
  fi
  if [ -e "$TARGET" ]; then
    ts="$(date -u +%Y%m%d-%H%M%S)"
    cp -p "$TARGET" "$TARGET.bak-$ts" && note "backup: $TARGET.bak-$ts"
    mode="$(stat -c %a "$TARGET" 2>/dev/null || stat -f %Lp "$TARGET" 2>/dev/null || echo 644)"
  else
    mode=644
  fi
  chmod "$mode" "$tmp" 2>/dev/null || note "could not set mode $mode on the new copy"
  # Replace the CONTENTS, never the inode: a hosts file moved out from under a running resolver is a
  # window with no name resolution at all, and a hard link elsewhere would keep the old bytes alive.
  if ! cat "$tmp" > "$TARGET"; then
    printf 'FAILED: %s could not be written — no verdict claimed (the backup above holds the previous bytes)\n' "$TARGET"
    return 1
  fi
  assess
  say_verdict
  if [ "$STATE" != "OK" ]; then
    printf 'FAILED: %s was written but does not read back in sync\n' "$TARGET"
    return 1
  fi
  if [ "$PATH_VERDICT" = "lan" ]; then echo "repaired: the pin is in place (path=lan)"
  else echo "repaired: the pin is removed (path=edge)"; fi
  return 0
}

# --- self-test -------------------------------------------------------------------
# A fixture REPO with its own group_vars, a fixture hosts file that carries foreign bytes, and a
# probe that is a SCRIPT — so every verdict here is an answer the harness chose, never one the script
# inferred. Both halves of every rule (CONVENTIONS §6): every STOP needs the unpoisoned control that
# reads green, every state needs its opposite state, and no arm is allowed to pass on a file the run
# was supposed to leave alone. Fixture values are TEST-NET addresses and a `.test` name, so nothing in
# here can be mistaken for a fleet value.
selftest() {
  local fails=0 pass=0 root hosts ssot_f ip_fix fq_fix n
  scratch; root="$SCRATCH"
  ip_fix="192.0.2.44"; fq_fix="llm.example.test"
  mkdir -p "$root/repo/IaC/ansible/group_vars/all"
  ssot_f="$root/repo/IaC/ansible/group_vars/all/main.yml"

  write_ssot() {
    cat <<FIX >"$ssot_f"
# fixture SSOT — the real file's SHAPE, no fleet value in it
zone_kogler_si:
  - { name: spark.example.test,   internal: true, ip: "{{ spark_home_ip }}", lan_only: true, tailnet: node, tailnet_ip: "100.64.0.9", ts_router: true }
  - { name: $fq_fix, internal: true, ip: "{{ spark_home_ip }}", lan_only: true, tailnet: edge, ts_router: true }
  - { name: other.example.test,   internal: true, ip: "{{ oldsrv_home_ip }}", lan_only: true, tailnet: none, ts_router: false }
network_static_hosts:
  - { name: router,  vlan: 10, ip: "192.0.2.1",   role: "fixture gateway" }
  - { name: spark,   vlan: 99, ip: "192.0.2.140", role: "fixture mgmt row" }
  - { name: spark,   vlan: 10, ip: "$ip_fix", role: "fixture Home row" }
FIX
  }
  write_ssot

  # mk_hosts <name> — foreign content in both directions: the lines a WSL boot writes, and another
  # tool's block. Byte-preservation is only proven against bytes this script does not own.
  mk_hosts() {
    hosts="$root/$1.hosts"
    printf '127.0.0.1\tlocalhost\n::1\tlocalhost\n\n# Generated by WSL\n10.10.1.81\thostname\n\n# another tool\n198.51.100.9\telsewhere.example\n' > "$hosts"
  }
  mk_hosts clean
  # The probes are SCRIPTS: the harness chooses the answer, and the ok/edge pair records WHAT it was
  # asked, so an arm can prove the script asked the SSOT address rather than a typed one.
  for p in ok edge; do
    printf '#!/bin/sh\nprintf "%%s %%s\\n" "$1" "$2" >> "${PROBE_LOG:-%s}"\nexit %s\n' \
      "$root/probe.$p.log" "$([ "$p" = ok ] && echo 0 || echo 1)" > "$root/probe-$p"
  done
  printf '#!/bin/sh\nexit 127\n' > "$root/probe-die"
  chmod +x "$root/probe-ok" "$root/probe-edge" "$root/probe-die"

  run() {   # run <label> <want-rc> <hosts> <probe> <args…>
    local label="$1" want="$2" hf="$3" pb="$4"; shift 4
    local rc=0
    REPO="$root/repo" SEAT_LLM_HOSTS="$hf" SEAT_LLM_PROBE="$pb" \
      bash "$SELF" "$@" >"$root/out" 2>&1 || rc=$?
    if [ "$rc" = "$want" ]; then pass=$((pass + 1)); printf 'ok   %s (rc %s)\n' "$label" "$rc"
    else fails=$((fails + 1)); printf 'FAIL %s: rc %s, want %s\n' "$label" "$rc" "$want"
      sed 's/^/     | /' "$root/out" | head -6; fi
  }
  says() { if grep -qE "$2" "$root/out"; then pass=$((pass + 1)); printf 'ok   %s\n' "$1"
           else fails=$((fails + 1)); printf 'FAIL %s: output lacks /%s/\n' "$1" "$2"; sed 's/^/     | /' "$root/out" | head -4; fi }
  file_has() { if grep -qxF "$3" "$2"; then pass=$((pass + 1)); printf 'ok   %s\n' "$1"
           else fails=$((fails + 1)); printf 'FAIL %s: %s lacks the line [%s]\n' "$1" "$2" "$3"; fi }
  unchanged() { if cmp -s "$2" "$3"; then pass=$((pass + 1)); printf 'ok   %s\n' "$1"
           else fails=$((fails + 1)); printf 'FAIL %s: %s changed when it must not have\n' "$1" "$3"; diff "$2" "$3" | head -6; fi }
  skip_arm() { pass="$pass"; printf 'SKIP %s (%s)\n' "$1" "$2"; }
  # poison <label> <sed-expr> — break ONE thing in the SSOT, require a STOP, require no byte written.
  poison() {
    local label="$1" expr="$2"
    write_ssot
    sed -e "$expr" "$ssot_f" > "$ssot_f.next" && mv "$ssot_f.next" "$ssot_f"
    cp -p "$hosts" "$root/keep"
    run "$label" 2 "$hosts" "$root/probe-ok" --check
    says "$label — it says FATAL rather than a verdict" 'FATAL'
    unchanged "$label — the hosts file is byte-identical" "$root/keep" "$hosts"
    write_ssot
  }
  outside() { awk -v s="$MARK_START" -v e="$MARK_END" '!i && $0==s{i=1;next} i&&$0==e{i=0;next} !i{print}' "$1"; }

  # 1. THE PROBE DECIDES, and it is asked the question the SSOT implies.
  run "1a  path=lan, no pin yet -> MISSING" 1 "$hosts" "$root/probe-ok" --check
  says  "1b  the verdict line names what it read (both SSOT values, the port, the path)" "fqdn=$fq_fix ip=$ip_fix port=443 path=lan"
  run "1c  path=edge, no pin -> OK: the pin is simply not desired" 0 "$hosts" "$root/probe-edge" --check --strict
  says  "1d  and that green says path=edge, so it cannot be mistaken for a pin being in place" "path=edge"
  if [ "$(tail -1 "$root/probe.ok.log")" = "$ip_fix 443" ]; then
    pass=$((pass + 1)); echo "ok   1e the probe was asked the SSOT address on port 443, not a typed one"
  else fails=$((fails + 1)); printf 'FAIL 1e the probe was asked [%s] (want "%s 443")\n' "$(tail -1 "$root/probe.ok.log")" "$ip_fix"; fi

  # 2. THE WRITE, its idempotence, and the canary: a pin the probe cannot reach is never OK.
  run "2a  --push writes the pin" 0 "$hosts" "$root/probe-ok" --push
  run "2b  --check --strict is OK afterwards" 0 "$hosts" "$root/probe-ok" --check --strict
  file_has "2c  the block carries the answer line the SSOT implies" "$hosts" "$ip_fix $fq_fix"
  cp -p "$hosts" "$root/after-2a"
  run "2d  a second --push changes nothing" 0 "$hosts" "$root/probe-ok" --push
  unchanged "2e  re-asserting twice lands the same bytes (WSL regenerates the file; the assert must be idempotent)" "$root/after-2a" "$hosts"
  n="$(grep -cxF "$MARK_START" "$hosts")"
  if [ "$n" = 1 ]; then pass=$((pass + 1)); echo "ok   2f  exactly one marker pair after two pushes"
  else fails=$((fails + 1)); echo "FAIL 2f  $n marker pairs after two pushes"; fi
  run "2g  CANARY: the pin is in place and the probe cannot reach it -> NOT OK under --strict" 1 "$hosts" "$root/probe-edge" --check --strict
  says  "2h  and it is reported as DRIFT, not as an error" "^DRIFT"
  run "2i  report-only mode stays green (the fan-out is the strict leg)" 0 "$hosts" "$root/probe-edge" --check
  run "2j  --push removes the pin when the path stops answering" 0 "$hosts" "$root/probe-edge" --push
  if grep -qxF "$MARK_START" "$hosts" || grep -qE "^$ip_fix $fq_fix\$" "$hosts"; then
    fails=$((fails + 1)); echo "FAIL 2k  the pin survived a path=edge push"
  else pass=$((pass + 1)); echo "ok   2k  the pin is gone once the path stops answering"; fi
  run "2l  and the check reads OK again" 0 "$hosts" "$root/probe-edge" --check --strict

  # 3. DRIFT by a wrong answer, both halves, and the repair.
  run "3a  re-pin, so arm 3 starts from a pin and not from a missing one" 0 "$hosts" "$root/probe-ok" --push
  sed -e "s|^$ip_fix $fq_fix\$|198.51.100.7 $fq_fix|" "$hosts" > "$hosts.w" && mv "$hosts.w" "$hosts"
  run "3b  a wrong address inside the block is DRIFT under --strict" 1 "$hosts" "$root/probe-ok" --check --strict
  says  "3c  and it reads as DRIFT, not as MISSING — the state word is the finding" "^DRIFT"
  run "3d  report-only stays green" 0 "$hosts" "$root/probe-ok" --check
  run "3e  --push repairs it" 0 "$hosts" "$root/probe-ok" --push
  run "3f  and it reads OK afterwards" 0 "$hosts" "$root/probe-ok" --check --strict

  # 4. FOREIGN BYTES SURVIVE BOTH WRITE DIRECTIONS, and a replaced file keeps a backup.
  mk_hosts foreign
  cp -p "$hosts" "$root/foreign-before"
  run "4a  push over a foreign hosts file" 0 "$hosts" "$root/probe-ok" --push
  outside "$hosts" > "$root/foreign-mid"
  if [ "$(cat "$root/foreign-before")" = "$(cat "$root/foreign-mid")" ]; then
    pass=$((pass + 1)); echo "ok   4b  writing kept every byte outside the markers"
  else fails=$((fails + 1)); echo "FAIL 4b the write changed text outside its markers"; diff "$root/foreign-before" "$root/foreign-mid" | head -6; fi
  run "4c  push it away again" 0 "$hosts" "$root/probe-edge" --push
  outside "$hosts" > "$root/foreign-after"
  if [ "$(cat "$root/foreign-before")" = "$(cat "$root/foreign-after")" ]; then
    pass=$((pass + 1)); echo "ok   4d  removing the block gives the file back byte for byte"
  else fails=$((fails + 1)); echo "FAIL 4d the removal left text behind"; diff "$root/foreign-before" "$root/foreign-after" | head -6; fi
  if ls "$root" | grep -q 'foreign\.hosts\.bak-[0-9]'; then
    pass=$((pass + 1)); echo "ok   4e  the replacing pushes kept a dated .bak- beside the file"
  else fails=$((fails + 1)); echo "FAIL 4e a file was replaced with no backup"; fi
  # An unterminated last line is the ONE byte outside the markers a write touches — so it is printed.
  printf '127.0.0.1\tlocalhost\n198.51.100.9\telsewhere.example' > "$root/nonl"
  run "4f  pushing a file whose last line has no newline" 0 "$root/nonl" "$root/probe-ok" --push
  says  "4g  and the write says it terminated that line" "carried no newline"
  if [ -z "$(tail -c1 "$root/nonl")" ] && grep -qxF "$ip_fix $fq_fix" "$root/nonl"; then
    pass=$((pass + 1)); echo "ok   4h  the file now ends in a newline and carries the pin"
  else fails=$((fails + 1)); echo "FAIL 4h the unterminated-last-line write did not land cleanly"; fi

  # 5. SHADOW — the inert-pin class, both halves.
  mk_hosts shadow
  printf '198.51.100.200\t%s\n' "$fq_fix" >> "$hosts"
  cp -p "$hosts" "$root/shadow-before"
  run "5a  an earlier entry that also names the name is DRIFT(shadow)" 1 "$hosts" "$root/probe-ok" --check --strict
  says  "5b  and it is named as a shadow, not as ordinary drift" "^DRIFT: shadow"
  run "5c  --push REFUSES to write behind it" 1 "$hosts" "$root/probe-ok" --push
  unchanged "5d  the refusal left the shadow exactly as found" "$root/shadow-before" "$hosts"
  grep -v "^198\.51\.100\.200	" "$hosts" > "$hosts.w" && mv "$hosts.w" "$hosts"
  run "5e  with the shadow gone the push works" 0 "$hosts" "$root/probe-ok" --push
  run "5f  and the check reads OK" 0 "$hosts" "$root/probe-ok" --check --strict
  mk_hosts shadow-late
  run "5g  seed our block first" 0 "$hosts" "$root/probe-ok" --push
  printf '198.51.100.201\t%s\n' "$fq_fix" >> "$hosts"
  run "5h  control: a foreign entry AFTER our block does not change the verdict — the first match is ours" 0 "$hosts" "$root/probe-ok" --check --strict
  says  "5i  and the late duplicate is still printed, as a NOTE rather than a verdict" "NOTE: an entry outside the markers"

  # 6. A DEAD PROBE IS NOT A VERDICT — the guard that protects every pin this file can write.
  mk_hosts probe
  cp -p "$hosts" "$root/probe-before"
  run "6a  a probe that dies stops instead of answering path=edge" 2 "$hosts" "$root/probe-die" --check
  says  "6b  and it names the dead probe rather than a path" "reachability probe died"
  unchanged "6c  nothing was decided from a probe that could not answer" "$root/probe-before" "$hosts"
  run "6d  control: the same file with a working probe yields a verdict (MISSING, here)" 1 "$hosts" "$root/probe-ok" --check

  # 7. THE SSOT READS — each STOP with its byte-identical proof; the controls are arms 1-6, which all
  #    read the unpoisoned fixture.
  mk_hosts ssot
  poison "7a  the zone row for the label is gone"          "/$fq_fix/d"
  poison "7b  the row lost its lan_only: true contract"    "s/lan_only: true/lan_only: false/"
  poison "7c  the row answers from another address"        "s|ip: \"{{ spark_home_ip }}\"|ip: \"{{ oldsrv_home_ip }}\"|"
  poison "7d  two rows answer for the label"               "s/other\.example\.test/$fq_fix/"
  poison "7e  the spark vlan-10 row is gone"               "/\"$ip_fix\"/d"
  poison "7f  its ip is not an address"                    "s|\"$ip_fix\"|\"\"|"
  poison "7f2 an out-of-range octet"                       "s|\"$ip_fix\"|\"192.0.2.999\"|"
  poison "7g  only a wrong-vlan row for the host survives" "s/vlan: 10, ip: \"$ip_fix\"/vlan: 99, ip: \"$ip_fix\"/"
  poison "7h  the zone name is not an FQDN"                "s|$fq_fix|llm..example|"
  poison "7i  the row sits outside the zone list"          "/$fq_fix/d; \$a  - { name: $fq_fix, internal: true, ip: \"{{ spark_home_ip }}\", lan_only: true, tailnet: edge, ts_router: true }"
  mv "$ssot_f" "$ssot_f.gone"
  cp -p "$hosts" "$root/keep"
  run "7j  no SSOT at all" 2 "$hosts" "$root/probe-ok" --check
  unchanged "7j  the hosts file is byte-identical" "$root/keep" "$hosts"
  mv "$ssot_f.gone" "$ssot_f"
  run "7k  control: the unpoisoned SSOT answers again" 1 "$hosts" "$root/probe-ok" --check

  # 8. MARKER CRUFT — in sync means BYTES, so an empty block while path=edge is a defect, not a green.
  mk_hosts cruft
  printf '%s\n%s\n' "$MARK_START" "$MARK_END" >> "$hosts"
  run "8a  an empty block while path=edge is DRIFT, not OK" 1 "$hosts" "$root/probe-edge" --check --strict
  run "8b  --push removes the cruft" 0 "$hosts" "$root/probe-edge" --push
  outside "$hosts" > "$root/cruft-after"; cp -p "$root/foreign-before" "$root/cruft-want"
  unchanged "8c  and the file is the foreign file again" "$root/cruft-want" "$root/cruft-after"
  run "8d  control: no block at all while path=edge is OK" 0 "$hosts" "$root/probe-edge" --check --strict

  # 9. THE TARGET FILE ITSELF. Both are mode-dependent: as root, no chmod binds, so the arm prints
  #    SKIP rather than a pass (CONVENTIONS §6 — an environment boundary is never a green).
  if [ "$(id -u)" = 0 ]; then
    skip_arm "9a  an unreadable hosts file is a STOP, not a verdict" "running as root, file modes do not bind"
    skip_arm "9b  an unwritable hosts file REFUSES, it does not pretend" "running as root, file modes do not bind"
  else
    mk_hosts unreadable
    chmod 000 "$hosts"
    run "9a  an unreadable hosts file is a STOP, not a verdict" 2 "$hosts" "$root/probe-ok" --check
    chmod 644 "$hosts"
    run "9c  control: readable again, it answers" 1 "$hosts" "$root/probe-ok" --check
    mk_hosts unwritable
    chmod 444 "$hosts"
    cp -p "$hosts" "$root/unw-before"
    run "9b  an unwritable hosts file REFUSES, it does not pretend" 1 "$hosts" "$root/probe-ok" --push
    says  "9d  and the refusal names the root act that is needed" "REFUSAL\(not-writable\)"
    unchanged "9e  the refusal wrote nothing" "$root/unw-before" "$hosts"
    chmod 644 "$hosts"
    run "9f  control: writable again, the push lands" 0 "$hosts" "$root/probe-ok" --push
  fi

  printf '\nself-test: %s (%d passed, %d failed)\n' \
    "$([ "$fails" -eq 0 ] && echo OK || echo FAILED)" "$pass" "$fails"
  [ "$fails" -eq 0 ]
}

# --- dispatch --------------------------------------------------------------------
case "$MODE" in
  selftest) selftest; exit $? ;;
esac
scratch
read_inputs
if [ "$MODE" = "push" ]; then do_push; else do_check; fi
exit $?
