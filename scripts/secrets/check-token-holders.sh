#!/usr/bin/env bash
# =====================================================================
# scripts/secrets/check-token-holders.sh — enumerate every holder of a 1Password service-account value
# across the plane, INCLUDING the class no other command in this repo can see: the environment of a
# running process. Digests only; a value never leaves the host it was read on.
#
# WHY THIS EXISTS: `reseat-vault-token.sh --check` proves FILES, and its own header says so — it reaches
# neither `/etc/op/provision-token` nor any already-running shell's exported environment. But
# `scripts/lib/vault-env.sh` resolves the credential **env → file → door**, so a process EXEC'd before a
# re-seat keeps answering with the superseded generation and 403s at its next vault leg while every file
# on the plane reads CURRENT. A process is a holder too, and the only proof of that class used to be a
# human walking `/proc` by hand during a rotation (docs/1password.md §Where a token is installed, the
# running-process row).
#
# WHAT IT NEVER DOES: print a value, a value's length, or a captured environment line. Each host hashes
# its own holders and ships ONLY `sha256[:12]`, so a transcript of this run holds twelve hex characters
# per holder and nothing else (CONVENTIONS §6, docs/1password.md §Output hygiene). No `env`, no `set`,
# no `echo $OP_SERVICE_ACCOUNT_TOKEN`, no `set -x` — and the sweep's own children run with the variable
# REMOVED, so a probe can never list itself as a holder.
#
#   bash scripts/secrets/check-token-holders.sh                     # sweep the alias plane
#   bash scripts/secrets/check-token-holders.sh --host vps          # one target
#   bash scripts/secrets/check-token-holders.sh --item op-write_api # the OTHER item's holders
#   bash scripts/secrets/check-token-holders.sh --self-test         # sandboxed, ZERO vault contact
#
# TARGETS are the SSH ALIAS PLANE, exactly like the re-seat: `wsl` plus `$PI_OLDSRV_TARGET`, `vps`,
# `oldsrv`. Override with `HOLDERS_TARGETS="…"` or `--host`. AWAY FROM THE LAN the plain home aliases
# time out and print UNREACHABLE — use the jump plane:
# `HOLDERS_TARGETS="wsl oldsrv-domen-vps vps oldsrv-vps" bash scripts/secrets/check-token-holders.sh`.
#
# WHAT IT CANNOT PROVE, stated once: `/proc/<pid>/environ` is the EXEC-time environment, so this sweep
# proves a holder SUPERSEDED and never proves one CURRENT — a shell that sourced the file after it
# started still shows the value it was born with. A process whose environ this account cannot read is
# named as `sudo needed`, never counted clean, and an unreachable target is never a green row.
# Root-side hand-planted FILES are a different class: `reseat-vault-token.sh --check` plus the
# `/root/.config/op/` read that docs/1password.md §Where a token is installed names.
#
# COST: ONE vault read per run — the item's current value, read here and digested here, compared against
# digests computed on the far side. Everything else is `/proc` over ssh.
# =====================================================================
set -euo pipefail

_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"   # sets REPO (an inherited $REPO still wins)
SELF="${BASH_SOURCE[0]}"
ITEM="op_api"
MODE="check"
HOSTS=""
: "${PI_WSL_DISTRO:=Debian}"
: "${PI_OLDSRV_TARGET:=oldsrv-domen}"
: "${HOLDERS_TARGETS:=wsl $PI_OLDSRV_TARGET vps oldsrv}"
: "${HL_PROC_ROOT:=/proc}"
: "${HL_SUDO:=auto}"          # auto = probe `sudo -n true`; the self-test pins no/yes so an arm never
                              # depends on whether THIS box is passwordless
VAR="OP_SERVICE_ACCOUNT_TOKEN"

say() { printf '%s\n' "$*"; }
die() { printf '%s\n' "$*" >&2; exit 1; }
d12() { tr -d '\r\n' | sha256sum | cut -c1-12; }
this_is_wsl_engine() { grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; }

# ---- credential: asked as a subprocess, never sourced (the re-seat's lesson) -------------------------
hl_vault_ask() {
  local lib
  [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] && return 0
  lib="$(cd "$(dirname "$SELF")/.." && pwd)/lib/vault-env.sh"
  [ -f "$lib" ] || lib="$REPO/scripts/lib/vault-env.sh"
  [ -f "$lib" ] || return 1
  OP_SERVICE_ACCOUNT_TOKEN="$(bash "$lib" --emit 2>/dev/null || true)"
  [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]
}

# The current value, read ONCE through the repo's ONE batched reader. Shape-checked: a read that fails AS
# A SUCCESS is how an empty value reaches a verdict (docs/1password.md §Proving which service account…).
read_item() {
  local json
  if [ -n "${HOLDERS_STUB:-}" ]; then printf '%s' "${STUB_ITEM_VALUE:-ops_stubvalue}"; return 0; fi
  json=$(python3 "$REPO/scripts/lib/vault_read.py" --item "$ITEM" 2>/dev/null | sed -n '/^{/,$p' || true)
  [ -n "$json" ] || return 1
  printf '%s' "$json" | python3 -c 'import json,sys
try:
    j = json.load(sys.stdin)
except Exception:
    sys.exit(1)
item = j.get("item", j)
for f in item.get("fields", []):
    v = f.get("value")
    vals = [v] if isinstance(v, str) else ([x.get("value") for x in v if isinstance(x, dict)] if isinstance(v, list) else [])
    for s in vals:
        if isinstance(s, str) and s.startswith("ops_"):
            print(s.strip()); sys.exit(0)' 2>/dev/null || true
}

# ---- transport: the re-seat's semantics, value never on the wire -------------------------------------
# `wsl` runs HERE only when this box IS the engine; from another Debian seat it is UNREACHABLE by
# definition, never a silent substitution of the box driving the sweep.
# The payload travels as base64 for the ssh leg so no quoting level can mangle it, and every leg runs it
# under `env -u` so no child of the sweep is ever a holder of its own making.
tx() { # tx <target> <cmd>   (the cmd is the payload text)
  local t="$1" p="$2" b
  if [ -n "${HOLDERS_STUB:-}" ]; then
    [ -d "$HOLDERS_STUB/$t" ] || return 255
    local stub_root="$HOLDERS_STUB/$t/proc"      # a shell variable, NOT a same-line assignment: the
    env -u "$VAR" HL_PROC_ROOT="$stub_root" HL_SKIP_TREE="${HL_SKIP_TREE:-$$}" bash -c "$p"   # rhs sees no prefix
    return $?
  fi
  if [ "$t" = "wsl" ]; then
    if this_is_wsl_engine; then env -u "$VAR" HL_SKIP_TREE="$$" bash -c "$p"; return $?; fi
    if command -v wsl.exe >/dev/null 2>&1; then
      MSYS_NO_PATHCONV=1 wsl.exe -d "$PI_WSL_DISTRO" -- bash -c "$p"; return $?
    fi
    return 99
  fi
  b=$(printf '%s' "$p" | base64 -w0)
  # `-n`: for the duration of an ssh, stdin is whatever the parent was reading (CONVENTIONS §6).
  ssh -n -o BatchMode=yes -o ConnectTimeout=10 "$t" "printf %s $b | base64 -d | env -u $VAR bash -s"
}

# ---- the payload: walks the proc root and ships digests plus counts, never values --------------------
payload() {
  cat <<EOS
root="\${HL_PROC_ROOT:-/proc}"
[ -d "\$root" ] || { echo 'NOPROC refuse'; exit 0; }
sudo="\${HL_SUDO:-auto}"
[ "\$sudo" = auto ] && { if sudo -n true 2>/dev/null; then sudo=yes; else sudo=no; fi; }
tot=0; unread=0; sn=0; skipl=0
skip="\${HL_SKIP_TREE:-}"
for p in \$root/[0-9]*; do
  [ -d "\$p" ] || continue
  [ -e "\$p/environ" ] || continue
  # the sweep's own invocation chain: on the local leg the driver and everything it forks inherit the
  # seat's environment, so reporting them would be the probe listing itself as a holder
  if [ -n "\$skip" ] && [ "\$skip" != 0 ]; then
    q=\${p##*/}; hit=no; i=0
    [ "\$q" = "\$skip" ] && hit=yes
    while [ "\$hit" != yes ] && [ "\$i" -lt 24 ]; do
      pq=\$(awk '{ s=\$0; sub(/^[^)]*\) /, "", s); split(s, a, " "); print a[2] }' "\$root/\$q/stat" 2>/dev/null)
      case "\$pq" in ''|*[!0-9]*) break ;; esac
      [ "\$pq" = "\$skip" ] && { hit=yes; break; }
      [ "\$pq" -le 1 ] && break
      q=\$pq; i=\$((i+1))
    done
    [ "\$hit" = yes ] && { skipl=\$((skipl+1)); continue; }
  fi
  tot=\$((tot+1))
  v=\$( { [ -r "\$p/environ" ] && cat -- "\$p/environ"; } 2>/dev/null | tr '\0' '\n' | sed -n 's/^$VAR=//p' | head -1 )
  if [ -z "\$v" ] && [ ! -r "\$p/environ" ]; then
    if [ "\$sudo" = yes ]; then
      v=\$(sudo -n cat -- "\$p/environ" 2>/dev/null | tr '\0' '\n' | sed -n 's/^$VAR=//p' | head -1)
      [ -n "\$v" ] || unread=\$((unread+1))
    else
      # a kernel thread has no environment at all (it is a child of kthreadd, pid 2); anything else this
      # uid cannot read is a BLIND SPOT. /proc reports size 0 for every file, so size is not the test.
      ppid=\$(awk '{ s=\$0; sub(/^[^)]*\) /, "", s); split(s, a, " "); print a[2] }' "\$p/stat" 2>/dev/null)
      if [ "\$ppid" = 2 ]; then unread=\$((unread+1)); else sn=\$((sn+1)); fi
      continue
    fi
  fi
  [ -n "\$v" ] || continue
  pid=\${p##*/}
  comm=\$(tr -d '\n' < "\$p/comm" 2>/dev/null || echo '?')
  uid=\$(stat -c %u "\$p" 2>/dev/null || echo '?')
  up=\$(cut -d' ' -f1 "\$root/uptime" 2>/dev/null | cut -d. -f1)
  # starttime is field 22, but comm can hold spaces — so drop everything through the closing paren first
  st=\$(awk '{ s=\$0; sub(/^[^)]*\) /, "", s); split(s, a, " "); print a[20] }' "\$p/stat" 2>/dev/null)
  hz=\$(getconf CLK_TCK 2>/dev/null || echo 100)
  age='?'
  case "\$up\$st\$hz" in ''|*[!0-9]*) : ;; *) age=\$(( up - st / hz )); esac
  printf 'H %s %s %s %s %s\n' "\$pid" "\$uid" "\$comm" "\$age" "\$(printf %s "\$v" | sha256sum | cut -c1-12)"
done
printf 'C %s %s %s %s %s\n' "\$tot" "\$unread" "\$sudo" "\$sn" "\$skipl"
exit 0
EOS
}

human() { # seconds → 45d3h / 9h53m / 12m / 9s ; anything non-numeric stays literal
  case "$1" in ''|*[!0-9]*) printf '%s' "$1"; return 0 ;; esac
  local s=$1 d h m
  d=$((s/86400)); h=$((s%86400/3600)); m=$((s%3600/60))
  if [ "$d" -gt 0 ]; then printf '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh%02dm' "$h" "$m"
  elif [ "$m" -gt 0 ]; then printf '%dm' "$m"
  else printf '%ds' "$s"; fi
}

# The restart a superseded holder owes, keyed on the shape it shows. The rule lives in the doc; this
# names the COST, because the two shapes that turn up are the two an agent must not pay alone.
hint() {
  case "$1" in
    # The CLI has NO daemon-stop verb: `op daemon stop` parses as `op daemon <arg>`, prints the daemon
    # help and exits 0 — a rotation that "stopped" a daemon stopped nothing. Measured on op 2.39 and 2.40.
    op) printf "kill pid %s as uid %s — there is no op daemon-stop verb, so a stop that exits 0 stopped nothing; the next op call respawns it from the environment of whoever calls it" "$2" "$3" ;;
    node|Code|code|Electron|vscode*) printf 'IDE/agent server: restarting it closes EVERY terminal in it' ;;
    pi|tmux|screen|bash|sh|zsh) printf 'restart the session from a shell that sources the file' ;;
    *) printf 'restart this process from a shell that sources the file' ;;
  esac
}

# ---- one target -------------------------------------------------------------------------------------------------
target_check() { # 0 nothing superseded · 1 a superseded holder (or an unmeasurable host) · 2 unreachable
  local t="$1" out r n=0 cur=0 dead=0 k pid uid comm age dg verdict
  if tx "$t" 'true' >/dev/null 2>&1; then r=0; else r=$?; fi
  [ "$r" = 99 ] && r=1
  if [ "$r" != 0 ]; then say "  $t  UNREACHABLE  — no sweep ran there, so NOTHING about it is known"; return 2; fi
  out=$(tx "$t" "$(payload)" 2>&1 | grep -v 'ops_' || true)
  if printf '%s\n' "$out" | grep -q 'NOPROC refuse'; then
    say "  $t  NO-PROC  — \$HL_PROC_ROOT is not a directory there: the sweep measured NOTHING, which is not a clean verdict"
    return 1
  fi
  while IFS=' ' read -r k pid uid comm age dg; do
    [ "$k" = "H" ] || continue
    n=$((n+1))
    if [ "$dg" = "$WANT" ]; then verdict="CURRENT"; cur=$((cur+1))
    else verdict="SUPERSEDED"; dead=$((dead+1)); fi
    printf '    pid %-8s uid %-6s %-14s %6s  %s  %s\n' "$pid" "$uid" "$comm" "$(human "$age")" "$dg" "$verdict"
    [ "$verdict" = SUPERSEDED ] && printf '        → %s\n' "$(hint "$comm" "$pid" "$uid")"
  done <<<"$(printf '%s\n' "$out" | grep '^H ' || true)"
  local tot k2 unread sudo sn skipped
  read -r k2 tot unread sudo sn skipped <<<"$(printf '%s\n' "$out" | awk '/^C /{print; exit}')"
  say "  $t  holders $n · CURRENT $cur · SUPERSEDED $dead · pids swept ${tot:-?} · unreadable ${unread:-0} (sudo: ${sudo:-?}) · sudo-needed ${sn:-0} · self ${skipped:-0}"
  [ "${sn:-0}" != 0 ] && say "       sudo needed for $sn pid(s): those environments were NOT read, so this host is PARTLY UNSEEN, not clean (docs/1password.md §Where a token is installed)"
  [ "$dead" -eq 0 ] && return 0
  return 1
}

# ---- self-test: a fixture /proc, a stubbed vault, ZERO network ----------------------------------------------------
HL_ST_DIR=""
hl_selftest_dir() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/hl-holders-selftest.XXXXXX" 2>/dev/null || true)"
  case "$d" in
    */hl-holders-selftest.??????) HL_ST_DIR="$d"; trap 'hl_selftest_clean' EXIT ;;
    *) die "self-test refuses to run without a provably private temp dir (mktemp gave: '$d')" ;;
  esac
}
hl_selftest_clean() {
  [ -n "${HL_ST_DIR:-}" ] || return 0
  case "$HL_ST_DIR" in
    */hl-holders-selftest.??????) rm -rf -- "$HL_ST_DIR" ;;
    *) printf 'SELFTEST: refusing to remove a temp dir that is not ours: %s\n' "$HL_ST_DIR" >&2 ;;
  esac
}

# mkpid <proc-root> <pid> <comm> <value|-> <age-seconds> [<environ-mode>] [<ppid>]
# A fixture process is a directory holding environ, comm and a stat line whose field 22 is the start time
# in clock ticks and whose stripped index 2 is the ppid — the same four things the real /proc offers, and
# the only things the sweep reads. ppid 2 marks it a kernel thread (no environment, even for root).
mkpid() {
  local root=$1 pid=$2 comm=$3 val=$4 age=$5 mode=${6:-600} ppid=${7:-1} up hz st i line
  up=$(awk '{print int($1)}' "$root/uptime"); hz=$(getconf CLK_TCK 2>/dev/null || echo 100)
  st=$(( (up - age) * hz ))
  mkdir -p "$root/$pid"
  printf '%s\n' "$comm" > "$root/$pid/comm"
  # index 20 of the list AFTER the closing paren is field 22, and comm may hold spaces — so the fixture
  # writes exactly 17 filler fields between the ppid and the start time, the way the real /proc/stat reads.
  line="($comm) S $ppid"
  for i in $(seq 3 19); do line="$line x$i"; done
  printf '%s %s 0 0 0\n' "$line" "$st" > "$root/$pid/stat"
  if [ "$val" = "-" ]; then : > "$root/$pid/environ"
  else printf 'PATH=/usr/bin\0%s=%s\0HOME=/home/u\0' "$VAR" "$val" > "$root/$pid/environ"; fi
  chmod "$mode" "$root/$pid/environ" 2>/dev/null || true
}

self_test() {
  local fails=0 out rc T
  say "SELFTEST: check-token-holders.sh — a holder is found, classified by digest, and never printed"
  hl_selftest_dir; T="$HL_ST_DIR"
  mkdir -p "$T/vps/proc" "$T/clean/proc" "$T/tree/proc"
  # uptime must EXCEED every planted age, or a negative start time would read as non-numeric
  printf '400000.00 12345\n' > "$T/vps/proc/uptime"
  printf '400000.00 12345\n' > "$T/clean/proc/uptime"
  mkpid "$T/vps/proc" 100  op   ops_oldvalue  162000        # an op daemon, up 45 h, superseded
  mkpid "$T/vps/proc" 101  pi   ops_stubvalue    1200       # this session, CURRENT
  mkpid "$T/vps/proc" 102  node ops_oldvalue2   86400       # an IDE server, superseded
  mkpid "$T/vps/proc" 103  bash -                120        # a process that holds nothing
  mkpid "$T/vps/proc" 104  op   ops_rootvalue     300 000   # unreadable to this uid → a BLIND SPOT
  mkpid "$T/vps/proc" 105  kwork -                 300 000 2 # a kernel thread: no environment at all
  # Arms 1–3 — the two verdicts, the counts, and the two restart costs an agent must not pay alone.
  out=$(HOLDERS_STUB="$T" HL_SUDO=no STUB_ITEM_VALUE="ops_stubvalue" HOLDERS_TARGETS=vps bash "$SELF" 2>&1 || true)
  printf '%s' "$out" | grep -qE 'pid 101 +uid .*CURRENT' \
    || { echo "SELFTEST FAIL [current]: a holder at the vault's value was not CURRENT (got: $(printf '%s' "$out" | tr '\n' '|' | cut -c1-200))"; fails=$((fails+1)); }
  printf '%s' "$out" | grep -qE 'pid 10[02] +uid .*SUPERSEDED' \
    || { echo "SELFTEST FAIL [superseded]: a holder at a dead value was not SUPERSEDED"; fails=$((fails+1)); }
  printf '%s' "$out" | grep -q 'holders 3 · CURRENT 1 · SUPERSEDED 2' \
    || { echo "SELFTEST FAIL [count]: the summary miscounted (got: $(printf '%s' "$out" | grep 'holders [0-9]' | head -1))"; fails=$((fails+1)); }
  printf '%s' "$out" | grep -q 'kill pid 100 as uid' \
    || { echo "SELFTEST FAIL [hint]: a superseded op daemon did not say how it closes"; fails=$((fails+1)); }
  printf '%s' "$out" | grep -q 'op daemon stop' \
    && { echo "SELFTEST FAIL [hint]: the advice named a CLI verb that does not exist"; fails=$((fails+1)); }
  printf '%s' "$out" | grep -q 'EVERY terminal' \
    || { echo "SELFTEST FAIL [hint]: an IDE-server holder did not name the terminal cost"; fails=$((fails+1)); }
  printf '%s' "$out" | grep -q '1d21h' \
    || { echo "SELFTEST FAIL [age]: a 45-hour holder did not age-format"; fails=$((fails+1)); }
  # Arm — the leak canary: value-blind even with four fixture values in reach.
  printf '%s' "$out" | grep -q 'ops' \
    && { echo "SELFTEST FAIL [value-blind]: a fixture value reached the output"; fails=$((fails+1)); }
  # Arm — an unreadable environ is named as UNSEEN, never as clean.
  printf '%s' "$out" | grep -q 'sudo needed for 1 pid' \
    || { echo "SELFTEST FAIL [sudo]: an unreadable process was reported as clean"; fails=$((fails+1)); }
  # Arm — a kernel thread is NOT a blind spot: /proc reports size 0 for every file, so the only honest
  # test is descent from kthreadd (pid 2). Without this arm a whole host of threads reads as 0 unseen.
  printf '%s' "$out" | grep -q 'unreadable 1 (sudo: no) · sudo-needed 1' \
    || { echo "SELFTEST FAIL [kthread]: a kernel thread and a blind spot were not told apart (got: $(printf '%s' "$out" | grep 'holders [0-9]' | head -1))"; fails=$((fails+1)); }
  # Arm — with sudo, that same pid is READ and counted, and `sudo needed` drops to 0.
  if sudo -n true 2>/dev/null; then
    out=$(HOLDERS_STUB="$T" HL_SUDO=yes STUB_ITEM_VALUE="ops_stubvalue" HOLDERS_TARGETS=vps bash "$SELF" 2>&1 || true)
    printf '%s' "$out" | grep -q 'holders 4 · CURRENT 1 · SUPERSEDED 3' \
      || { echo "SELFTEST FAIL [sudo-covered]: sudo did not close the blind spot (got: $(printf '%s' "$out" | grep 'holders [0-9]' | head -1))"; fails=$((fails+1)); }
    printf '%s' "$out" | grep -q 'sudo-needed 0' \
      || { echo "SELFTEST FAIL [sudo-covered]: sudo-covered pids still counted as sudo-needed"; fails=$((fails+1)); }
  else
    say "  note: no passwordless sudo on this box, so the sudo-covered arm SKIPs (the sudo-needed arm above still ran)"
  fi
  # Arm — the sweep's own chain: a holder that descends from the named pid is the PROBE, not a holder.
  mkdir -p "$T/tree/proc"; printf '400000.00 12345\n' > "$T/tree/proc/uptime"
  mkpid "$T/tree/proc" 777 bash ops_stubvalue  60   # the driver
  mkpid "$T/tree/proc" 106 bash ops_stubvalue  10 600 777   # its child — the same value, one hop down
  out=$(HOLDERS_STUB="$T" HL_SUDO=no HL_SKIP_TREE=777 STUB_ITEM_VALUE="ops_stubvalue" HOLDERS_TARGETS=tree bash "$SELF" 2>&1 || true)
  printf '%s' "$out" | grep -q 'holders 0 · CURRENT 0 · SUPERSEDED 0' \
    || { echo "SELFTEST FAIL [skip]: the sweep reported its own process tree as holders (got: $(printf '%s' "$out" | grep 'holders [0-9]' | head -1))"; fails=$((fails+1)); }
  printf '%s' "$out" | grep -q 'self 2' \
    || { echo "SELFTEST FAIL [skip]: the skipped processes were not counted as self"; fails=$((fails+1)); }
  out=$(HOLDERS_STUB="$T" HL_SUDO=no HL_SKIP_TREE=999 STUB_ITEM_VALUE="ops_stubvalue" HOLDERS_TARGETS=tree bash "$SELF" 2>&1 || true)
  printf '%s' "$out" | grep -q 'holders 2 · CURRENT 2 · SUPERSEDED 0' \
    || { echo "SELFTEST FAIL [skip]: an unrelated skip root hid real holders (got: $(printf '%s' "$out" | grep 'holders [0-9]' | head -1))"; fails=$((fails+1)); }
  # Arm — a host with no holders: a clean 0 and a clean exit.
  mkpid "$T/clean/proc" 200 sshd - 90
  rc=0
  HOLDERS_STUB="$T" HL_SUDO=no STUB_ITEM_VALUE="ops_stubvalue" HOLDERS_TARGETS=clean bash "$SELF" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 0 ] || { echo "SELFTEST FAIL [clean]: a no-holder host did not exit 0 (rc=$rc)"; fails=$((fails+1)); }
  out=$(HOLDERS_STUB="$T" HL_SUDO=no STUB_ITEM_VALUE="ops_stubvalue" HOLDERS_TARGETS=clean bash "$SELF" 2>&1 || true)
  printf '%s' "$out" | grep -q 'holders 0 · CURRENT 0 · SUPERSEDED 0' \
    || { echo "SELFTEST FAIL [clean]: a no-holder host did not count 0 (got: $(printf '%s' "$out" | grep 'holders [0-9]' | head -1))"; fails=$((fails+1)); }
  # Arm — a proc root that is not a directory REFUSES; it must never read as `0 holders`.
  rm -rf "$T/clean/proc"
  out=$(HOLDERS_STUB="$T" HL_SUDO=no STUB_ITEM_VALUE="ops_stubvalue" HOLDERS_TARGETS=clean bash "$SELF" 2>&1 || true)
  printf '%s' "$out" | grep -q 'NO-PROC' \
    || { echo "SELFTEST FAIL [noprocp]: a sweep that walked nothing printed a verdict anyway"; fails=$((fails+1)); }
  # Arm — an absent target is named absent, never substituted with the box driving the sweep.
  out=$(HOLDERS_STUB="$T" HL_SUDO=no STUB_ITEM_VALUE="ops_stubvalue" HOLDERS_TARGETS=nosuchhost bash "$SELF" 2>&1 || true)
  printf '%s' "$out" | grep -q 'UNREACHABLE' \
    || { echo "SELFTEST FAIL [unreachable]: an absent target was not named as absent"; fails=$((fails+1)); }
  # Arm — what the parent compares against is a digest, never the value.
  printf '%s' "$out" | grep -q "sha256\[:12\]=$(printf %s 'ops_stubvalue' | d12)" \
    || { echo "SELFTEST FAIL [digest]: the run did not print the vault digest it compared against"; fails=$((fails+1)); }
  if [ "$fails" -eq 0 ]; then
    say "SELFTEST OK: CURRENT/SUPERSEDED by digest, unseen pids named as unseen, an empty proc root refuses, an absent target is never a green row, and no value crosses the wire (sandboxed, zero vault contact)"
  else
    say "SELFTEST FAILED: $fails arm(s)"; exit 1
  fi
}

# ---- driver ------------------------------------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --self-test) MODE="selftest"; shift ;;
    --host) HOSTS="$2"; shift 2 ;;
    --item) ITEM="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^# =\{10,\}/p' "$SELF"; exit 0 ;;
    *) die "unknown option: $1 (--help)" ;;
  esac
done
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) die "run this on the Debian engine: the sweep reads /proc, and a Windows seat reaches it through the same door as reseat-vault-token.sh (docs/1password.md §Rotating the control-node token)" ;;
esac
[ "$MODE" = selftest ] && { self_test; exit 0; }

hl_vault_ask || die "no vault credential for this seat (see scripts/lib/vault-env.sh) — the verdict compares against the item's CURRENT value, so it needs one working credential: this seat's env, its file, or the WSL door"
VALUE="$(read_item || true)"
case "$VALUE" in ops_*) : ;; *) VALUE="" ;; esac
[ -n "$VALUE" ] || die "could not read a service-account token from '$ITEM' via lib/vault_read.py — nothing was compared"
WANT="$(printf %s "$VALUE" | d12)"; VALUE=""
say "check-token-holders · item $ITEM · vault sha256[:12]=$WANT · targets: ${HOSTS:-$HOLDERS_TARGETS} · 1 vault read"
fails=0
for t in ${HOSTS:-$HOLDERS_TARGETS}; do target_check "$t" || fails=$((fails+1)); done
say "EXEC-time environments only: SUPERSEDED is proof, CURRENT is not (a shell that sourced the file later still shows what it was born with)"
say "digests only — a value is never printed here (docs/1password.md §Proving which service account an install holds)"
if [ "$fails" -eq 0 ]; then
  say "RESULT no superseded holder found — and any UNREACHABLE/NO-PROC/sudo-needed line above is NOT a clean verdict"
  exit 0
fi
say "RESULT $fails target(s) hold a superseded value or could not be fully swept — the owner restarts what is listed, from a shell that sources the file"
exit 1
