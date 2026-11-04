#!/usr/bin/env bash
# =====================================================================
# seat-paseo.sh — the `paseo` seat plane: the Paseo daemon's own config, converged on the seats
# where the seat (not a systemd unit) is what configures the daemon (HD-411).
#
# WHY THIS EXISTS
# ---------------
#   ~/.paseo/config.json was seat folklore: the desktop app wrote it, a reimage lost it, and the
#   two facts that decide whether a seat is reachable at all — which address the daemon binds and
#   whether the vendor relay is on — answered differently per box with no check able to say so.
#   Measured before this file existed: both laptop seats were answering with the relay ON while the
#   house posture says off, and the WSL seat was bound to loopback only, so the phone had no way in.
#
# WHAT THIS OWNS                                        (written THROUGH the CLI, which merges)
#   daemon.relay.enabled   false, every seat. The relay is the vendor's path OUT of the tailnet;
#                          the `.ts` router is the path IN.
#   daemon.listen          the seat's own address, from seat_render() below. ONE seat, ONE string —
#                          the schema holds a single listener, which is why the ports live in the
#                          `paseo_ports` map (group_vars/all/main.yml) and not in this file.
#   daemon.auth.password   the bcrypt hash from the vault item `paseo_password` — READ, never
#                          derived here, so a rotation cannot leave a seat answering on its own.
#
# WHAT THIS PLANE DOES NOT WRITE, AND WHY
#   On `oldsrv` the unit carries the bind (PASEO_LISTEN) and the password (its 0600 env file), so
#   writing either here would give one address two authors. What oldsrv owes here is the READ of
#   the two door arms roles/seat sets — daemon.hostnames and daemon.trustedProxies: a router that
#   the daemon answers 403 is a door that reports deployed, and nothing else in the tree can see it.
#   Not win11: that seat's daemon is desktop-managed, its CLI is a `.cmd` behind `cmd //c`, and its
#   bind is the owner's elevated leg (todo HD-411), so the row does not name win11 and this script
#   answers SKIP there instead of running a carrier nobody verified. Not the pairing, not the phone
#   verdict, not ~/.paseo beyond config.json. Not the @getpaseo/cli install — the plane refuses to
#   place a binary no pin in versions.yml names (CONVENTIONS §7), and the package is
#   `@getpaseo/cli`: `npm i -g paseo` is a name-squat.
#
#   ONE ARM HAS NO CLI CARRIER, measured on the 0.15.0 CLI: `daemon config set` refuses any path
#   under `daemon.auth` ("Use daemon set-password to change the daemon password"), and `daemon
#   set-password` reads the PLAINTEXT from a terminal and bcrypts it itself — with a fresh salt, so
#   its output is a different 60-char string for the same value. So the password arm is READ and
#   compared here (shape and length in the verdict, never bytes) and NOTHING here writes it: on a
#   seat with no unit the hash has no carrier this plane may use, which is the open half of HD-411.
#   `daemon.listen` and `daemon.relay.enabled` carry on being written through the CLI, which merges.
#
# VERDICTS
#   OK                every arm this seat owes is what the seat owes
#   MISSING           no CLI on PATH, or no config.json — no daemon has ever run on this seat
#   DRIFT(<arm>)      that arm is not what the seat owes (the line quotes the value it found)
#   DRIFT             more than one arm is off; each is named
#   REFUSAL           config.json is not readable as JSON — the bytes are left exactly as found
#
# Exit: 0 OK / repaired · 1 MISSING, a DRIFT under --strict, a REFUSAL, or a write that did not take
#       · 2 NO VERDICT — the registry cannot be read, the CLI died rather than answered, or THIS BOX
#       IS NOT A SEAT THIS ROW NAMES (the fan-out counts that rc as its own SKIP).
#
# USAGE
#   bash scripts/harness/seat-paseo.sh                  # --check
#   bash scripts/harness/seat-paseo.sh --check --strict # the seat-leg form
#   bash scripts/harness/seat-paseo.sh --push           # write the delta, then re-read it
#   bash scripts/harness/seat-paseo.sh --self-test      # stubs + the value-canary; no daemon, no vault, no seat
#
# NEVER-PRINT, AND HOW IT IS PROVEN
#   Every verdict goes to a fan-out log, so a line that prints a credential VALUE is a leak, not a
#   verdict. `describe_secret` is the guard on the credential arms — shape and length, never bytes
#   (CONVENTIONS §3) — and `--self-test` now proves the guard rather than asserting it: each arm's
#   output is scanned for a bcrypt shape, a bare 32-char token and the fixture's own values, in every
#   mode the arm runs, and a mutated copy of this file (one whose `describe_secret` hands the value
#   back) must redden that scan. This is the arm that was missing when `paseo_password`'s hash
#   reached three run captures through a `--check` drift line: rc and wording were proven, never-print
#   was not.
#
# Env (sandbox hooks for --self-test only): PASEO_BIN, PASEO_HOME_DIR, PI_SEAT, HL_REGISTRY, and
#   vault_read.py's own HL_VAULT_READ_FIXTURE.
#
# Owning rule: docs/services-ai.md §9b-1 (the seat surface) · scripts/lib/seat-planes.yml
# (`plane: paseo`) · docs/deployment-secrets.md (the paseo_password row) · todo.md HD-411.
set -uo pipefail

_hl_self="${BASH_SOURCE[0]}"
case "$_hl_self" in */*) _hl_d="${_hl_self%/*}" ;; *) _hl_d="." ;; esac
_hl_d="$(cd "$_hl_d" && pwd)"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"
# shellcheck source=/dev/null
hl_source_lib "${BASH_SOURCE[0]}" pi-seat.sh    # hl_seat_here + hl_seat_scope_lists: who owes a leg

PLANE_ID="paseo"
PASEO_BIN="${PASEO_BIN:-paseo}"
PASEO_HOME="${PASEO_HOME_DIR:-$HOME/.paseo}"
CONFIG_JSON="$PASEO_HOME/config.json"
VAULT_ITEM="paseo_password"
MODE="check"; STRICT=0
ERRFILE="$(mktemp)"; trap 'rm -f "$ERRFILE"' EXIT

err()  { printf 'seat-paseo: %s\n' "$*" >&2; }
stop() { printf 'FATAL: %s\n' "$*" >&2; exit 2; }
usage() { sed -n '/^# USAGE/,/^# Env/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# --- the per-seat render -----------------------------------------------------------------
# A laptop seat binds every interface, because the desktop app arrives at `localhost` and the phone
# arrives at the laptop's tailnet address — and the tailnet-only boundary then lives in the firewall
# rule (scripts/harness/win/), scoped to 100.64.0.0/10, so the LAN never gets a socket. `oldsrv`
# binds loopback and is reached through the `paseo-oldsrv-ts` router. ⛔ Never bind the tailnet IP
# itself: one listener that cannot bind while Tailscale is down, and the app loses its own daemon.
seat_render() {
  WANT_RELAY="false"
  case "$SEAT" in
    win11) WANT_LISTEN="0.0.0.0:6767"; UNIT=no ;;   # owner's elevated leg; not a seat this row names
    wsl)   WANT_LISTEN="0.0.0.0:6768"; UNIT=no ;;
    oldsrv) WANT_LISTEN="";            UNIT=yes ;;
    *) return 1 ;;
  esac
}

# owed_arms — the arms THIS seat answers to, in the order they are reported.
owed_arms() {
  if [ "$UNIT" = yes ]; then
    printf '%s\n' daemon.relay.enabled daemon.hostnames daemon.trustedProxies
  else
    printf '%s\n' daemon.relay.enabled daemon.listen daemon.auth.password
  fi
}

# --- the read: ONE parse of the file, every arm at once ----------------------------------
# Read from the file, not from `config get` per arm: three calls would answer three times about
# one file, and a file that is not JSON at all must be named as a refusal rather than arrive as
# three parse errors that read like three drifted arms.
read_cfg() {
  python3 - "$CONFIG_JSON" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except json.JSONDecodeError:
    raise SystemExit(4)
except OSError:
    raise SystemExit(2)
def get(path):
    cur = d
    for part in path.split('.'):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur
def enc(v):
    if v is None: return "<unset>"
    if v is True: return "true"
    if v is False: return "false"
    if isinstance(v, (list, dict)): return json.dumps(v, separators=(',', ':'))
    return str(v)
for k in ("daemon.listen", "daemon.relay.enabled", "daemon.auth.password",
          "daemon.hostnames", "daemon.trustedProxies"):
    print("%s\t%s" % (k, enc(get(k))))
PY
}

# describe_secret <value> — how long it is and what shape, never the value itself. The credential
# arms of a seat config are the one place this plane can read a secret and print a verdict, and the
# verdict goes to a fan-out log (CONVENTIONS §3: lengths and shapes, never values).
describe_secret() {
  case "$1" in
    "<unset>") printf '<unset>' ;;
    \$2[aby]\$*) printf 'a bcrypt hash (%s chars)' "${#1}" ;;
    *) printf 'a value of %s chars' "${#1}" ;;
  esac
}

# want_for <arm> — the value the seat owes, in the SAME encoding read_cfg prints.
want_for() {
  case "$1" in
    daemon.listen)         printf '%s' "$WANT_LISTEN" ;;
    daemon.relay.enabled)  printf 'false' ;;
    daemon.auth.password)  vault_bcrypt || return 1 ;;
    daemon.hostnames)      printf '["paseo-oldsrv.ts.kogler.si"]' ;;
    daemon.trustedProxies) printf '["127.0.0.1"]' ;;
  esac
}

# The hash, read from the item. Never hashed here: the plaintext lives in the item beside it for
# the env-file carrier, and a seat that derived its own hash would silently disagree after a
# rotation. A boundary is a FAILURE of this arm, not a green: an unproven password on the seat
# that pairs a phone is exactly what the arm is for.
vault_bcrypt() {
  local out
  out="$(python3 "$REPO/scripts/lib/vault_read.py" --item "$VAULT_ITEM" 2>"$ERRFILE")" || {
    VAULT_NOTE="$(head -1 "$ERRFILE" 2>/dev/null)"; return 1; }
  printf '%s' "$out" | python3 -c '
import json, sys
row = json.load(sys.stdin)["item"]
hashes = [f["value"] for f in row["fields"] if f.get("label") == "bcrypt_hash" and f.get("value")]
if not hashes:
    raise SystemExit("no bcrypt_hash field")
print(hashes[0])' || { VAULT_NOTE="$(tail -1 "$ERRFILE" 2>/dev/null)"; return 1; }
}

# --- the assess: one path for --check and for the read-back after --push -----------------
assess() {
  local arm want got bad=""
  mapfile -t ARMS < <(owed_arms)
  local cfg rc=0
  cfg="$(read_cfg)" || rc=$?
  case "$rc" in
    2) VERDICT="MISSING"; REASON="$CONFIG_JSON cannot be read"; return 0 ;;
    4) VERDICT="REFUSAL"; REASON="$CONFIG_JSON is not JSON — the bytes were left exactly as found"; return 0 ;;
  esac
  for arm in "${ARMS[@]}"; do
    got="$(printf '%s\n' "$cfg" | awk -F'\t' -v k="$arm" '$1==k{print $2}')"
    if ! want="$(want_for "$arm")"; then
      VERDICT="DRIFT(auth)"; REASON="the vault item $VAULT_ITEM could not be read from this seat (${VAULT_NOTE:-no reason given}) — the daemon password is UNPROVEN, not verified"; return 0
    fi
    [ "${got//[[:space:]]/}" = "${want//[[:space:]]/}" ] && continue
    case "$arm" in
      daemon.hostnames|daemon.trustedProxies)
        bad="$bad ${arm}=$got (the router is up and the daemon would answer this Host 403)" ;;
      daemon.auth.password)
        # Lengths, never the value — a bcrypt hash is credential material, and this line reaches a
        # fan-out log the same way a token would (CONVENTIONS §3).
        bad="$bad ${arm}=$(describe_secret "$got") want=$(describe_secret "$want")" ;;
      *) bad="$bad $arm=$got want=$want" ;;
    esac
  done
  [ -n "$bad" ] && { VERDICT="DRIFT"; REASON="${bad# }"; return 0; }
  VERDICT="OK"; REASON=""
}

# --- the scope read, FIRST: a config cannot be owed on a box this row does not name ------
seat_scope() {
  hl_seat_here SEAT
  SCOPE_LIST="$(hl_seat_scope_list "$PLANE_ID")"
  if [ -z "${SEAT:-}" ] || [ "$SEAT" = none ]; then SCOPE="no-seat"; return 0; fi
  hl_seat_scope_lists "$PLANE_ID" "$SEAT"
  case $? in
    0) SCOPE="here" ;;
    1) SCOPE="elsewhere" ;;
    *) stop "the plane registry at $(hl_seat_registry_path) cannot be read — this leg cannot tell whether the box owes a Paseo config, and writing one on that guess is how a seat ends up bound to an address nobody chose" ;;
  esac
}
scope_verdict() {
  case "$SCOPE" in
    elsewhere) printf 'SKIP: %s — the `%s` leg belongs to the seats its registry row names (seats: %s); on win11 the daemon is desktop-managed, its CLI is a .cmd behind cmd //c, and the bind is the owner'"'"'s elevated leg\n' \
        "$SEAT" "$PLANE_ID" "${SCOPE_LIST:-<empty>}" ;;
    no-seat)   printf 'SKIP: no seat — this box is none of the harness seats, so `%s` cannot be scoped here\n' "$PLANE_ID" ;;
  esac
  return 2
}

# prelude — scope, CLI, render, and the one state that is not a verdict about the arms.
# Sets VERDICT/REASON and returns 0 (assess) or 1 (already answered).
prelude() {
  seat_scope
  [ "$SCOPE" = here ] || { scope_verdict; return $?; }
  seat_render || stop "seat $SEAT has no Paseo render — a seat this plane knows nothing about"
  if ! command -v "$PASEO_BIN" >/dev/null 2>&1; then
    printf 'MISSING: no `paseo` CLI on PATH — this seat has no @getpaseo/cli (⛔ never the squatted `paseo` package); nothing was written\n'
    return 1
  fi
  command -v python3 >/dev/null 2>&1 || stop "no python3 here — neither config.json nor the vault answer can be parsed"
  if [ ! -e "$CONFIG_JSON" ]; then
    printf 'MISSING: no %s — no daemon has ever run on this seat\n' "$CONFIG_JSON"
    return 1
  fi
  return 0
}

verdict_out() {
  [ "$VERDICT" != OK ] || return 0
  printf '%s: %s\n' "$VERDICT" "${REASON:-$CONFIG_JSON}"
}

do_check() {
  prelude || return $?
  assess
  [ "$VERDICT" = OK ] && { printf 'OK: seat %s — every Paseo arm it owes is the render (%s)%s\n' \
      "$SEAT" "$(printf '%s ' "${ARMS[@]}")" \
      "$([ "$UNIT" = yes ] && printf ' — the bind and the password are the unit'"'"'s, not this file'"'"'s')"; return 0; }
  verdict_out
  [ "$STRICT" -eq 1 ] && return 1
  case "$VERDICT" in REFUSAL) return 1 ;; *) return 0 ;; esac
}

do_push() {
  prelude || return $?
  local arm want got wrote=0
  mapfile -t ARMS < <(owed_arms)
  # A REFUSAL is settled BEFORE any write: no parse, no write, bytes untouched.
  read_cfg >/dev/null || { assess; verdict_out; return 1; }
  for arm in "${ARMS[@]}"; do
    case "$arm" in
      # The door arms belong to roles/seat. Writing them from a converge host would give one
      # daemon two authors, so the push half reports them and leaves them.
      daemon.hostnames|daemon.trustedProxies) continue ;;
    esac
    if ! want="$(want_for "$arm")"; then
      printf 'DRIFT(auth): the vault item %s could not be read here (%s) — NOTHING was written for that arm\n' \
        "$VAULT_ITEM" "${VAULT_NOTE:-no reason given}"
      continue
    fi
    got="$(read_cfg | awk -F'\t' -v k="$arm" '$1==k{print $2}')"
    [ "${got//[[:space:]]/}" = "${want//[[:space:]]/}" ] && continue
    "$PASEO_BIN" --home "$PASEO_HOME" daemon config set "$arm" "$want" >/dev/null 2>&1 || {
      printf 'DRIFT(%s): the write did not take\n' "$arm"; return 1; }
    case "$arm" in
      daemon.auth.password) printf 'wrote %s = %s from %s\n' "$arm" "$(describe_secret "$want")" "$VAULT_ITEM" ;;
      *) printf 'wrote %s = %s\n' "$arm" "$want" ;;
    esac
    wrote=1
  done
  assess
  [ "$VERDICT" = OK ] && { printf 'OK: re-read config.json — the arms this seat owes are the render%s\n' \
      "$([ "$wrote" = 0 ] && printf ' (nothing needed writing)')"; return 0; }
  printf '%s: after the push — %s\n' "$VERDICT" "$REASON"
  return 1
}

# --- self-test: stubs, so no daemon, no vault, no seat -----------------------------------
self_test() {
  local t fails=0 CFG want
  t="$(mktemp -d)" || { err "mktemp failed"; return 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$t'" RETURN
  mkdir -p "$t/bin" "$t/home/.paseo"
  CFG="$t/home/.paseo/config.json"

  # The stub CLI stands in for `paseo daemon config set` only: it merges one dotted key into the
  # JSON at $ST_CFG and refuses a value that is neither JSON nor a bare string, which is what the
  # real CLI does. The READ half never goes through it — read_cfg parses the file.
  cat > "$t/bin/paseo" <<'EOS'
#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
path = os.environ["ST_CFG"]
d = json.load(open(path)) if os.path.exists(path) else {}
if "set" not in args:
    sys.exit(1)
i = args.index("set")
key, raw = args[i + 1], args[i + 2]
try:
    val = json.loads(raw)
except json.JSONDecodeError:
    val = raw
cur = d
for part in key.split(".")[:-1]:
    cur = cur.setdefault(part, {})
cur[key.split(".")[-1]] = val
json.dump(d, open(path, "w"))
print("saved")
EOS
  chmod +x "$t/bin/paseo"

  # A vault fixture, in vault_read.py's --values shape: the hash is $2b$12$ + 22 + 31 chars.
  printf '%s\n' '{"items":{"i1":{"title":"paseo_password","version":1,"fields":[{"label":"password","value":"plaintext"},{"label":"bcrypt_hash","value":"$2b$12$stubstubstubstubstubstubstubstubstubstubstubstubstubst"}]}}}' > "$t/vault.json"
  printf '%s\n' '{"items":{"i1":{"title":"paseo_password","version":1,"fields":[{"label":"password","value":"plaintext"}]}}}' > "$t/vault-nohash.json"

  run_at() { # run_at <expect-rc> <name> <args...> — every arm drives the REAL CLI path
    local want="$1" name="$2"; shift 2
    local rc=0
    env PI_SEAT="${PI_SEAT:-wsl}" PASEO_BIN="$t/bin/paseo" PASEO_HOME_DIR="$t/home/.paseo" \
        ST_CFG="$CFG" HL_VAULT_READ_FIXTURE="${FIXTURE:-$t/vault.json}" \
        bash "${BASH_SOURCE[0]}" "$@" > "$t/out" 2>&1 || rc=$?
    if [ "$rc" = "$want" ]; then printf 'ok   rc %s  %s\n' "$rc" "$name"
    else printf 'NOT CAUGHT  wanted rc %s, got %s  %s\n%s\n' "$want" "$rc" "$name" "$(sed 's/^/        /' "$t/out")"; fails=$((fails + 1)); fi
  }
  wsl_converged() { printf '%s\n' '{"version":1,"daemon":{"relay":{"enabled":false},"listen":"0.0.0.0:6768","auth":{"password":"$2b$12$stubstubstubstubstubstubstubstubstubstubstubstubstubst"}}}' > "$CFG"; }

  # 1. every arm right → OK, rc 0.
  wsl_converged; PI_SEAT=wsl run_at 0 "converged seat" --check --strict
  grep -q '^OK:' "$t/out" || { printf 'NOT CAUGHT the converged case printed no OK line\n'; fails=$((fails + 1)); }

  # 2. THE DEFECT THIS ROW CLOSES: the relay is ON. A seat that can reach the vendor relay is the
  #    state the house posture refuses, and a check that stayed green over it is a mute gate.
  printf '%s\n' '{"version":1,"daemon":{"relay":{"enabled":true},"listen":"0.0.0.0:6768","auth":{"password":"$2b$12$stubstubstubstubstubstubstubstubstubstubstubstubstubst"}}}' > "$CFG"
  PI_SEAT=wsl run_at 1 "relay on" --check --strict
  grep -q 'daemon.relay.enabled' "$t/out" || { printf 'NOT CAUGHT a relay-on seat was not named\n'; fails=$((fails + 1)); }

  # 3. the bind: loopback on a laptop seat is the state where the phone never arrives.
  printf '%s\n' '{"version":1,"daemon":{"relay":{"enabled":false},"listen":"127.0.0.1:6768","auth":{"password":"$2b$12$stubstubstubstubstubstubstubstubstubstubstubstubstubst"}}}' > "$CFG"
  PI_SEAT=wsl run_at 1 "loopback-only bind on a laptop seat" --check --strict
  grep -q 'daemon.listen' "$t/out" || { printf 'NOT CAUGHT a laptop seat bound to loopback was not named\n'; fails=$((fails + 1)); }

  # 4. --push writes the delta and RE-READS it; the second push writes nothing.
  PI_SEAT=wsl run_at 0 "push repairs" --push
  grep -q '^OK: re-read' "$t/out" || { printf 'NOT CAUGHT the push did not re-read what it wrote\n'; fails=$((fails + 1)); }
  PI_SEAT=wsl run_at 0 "push is idempotent" --push
  grep -q '^wrote ' "$t/out" && { printf 'NOT CAUGHT the second push wrote again\n'; fails=$((fails + 1)); }

  # 5. a config that is not JSON is a REFUSAL, and --push leaves the bytes alone.
  printf '%s\n' 'not json at all' > "$CFG"; cp "$CFG" "$t/junk.before"
  PI_SEAT=wsl run_at 1 "unparseable config" --check --strict
  grep -q '^REFUSAL:' "$t/out" || { printf 'NOT CAUGHT an unreadable config was not a refusal\n'; fails=$((fails + 1)); }
  PI_SEAT=wsl run_at 1 "push refuses" --push
  cmp -s "$CFG" "$t/junk.before" || { printf 'NOT CAUGHT --push overwrote a config it could not read\n'; fails=$((fails + 1)); }

  # 6. no config at all is MISSING, and a push does not invent one for a daemon that never ran.
  rm -f "$CFG"
  PI_SEAT=wsl run_at 1 "no daemon has ever run" --check --strict
  grep -q '^MISSING:' "$t/out" || { printf 'NOT CAUGHT an absent config was not MISSING\n'; fails=$((fails + 1)); }
  PI_SEAT=wsl run_at 1 "push does not create a config" --push
  [ -e "$CFG" ] && { printf 'NOT CAUGHT --push created a config for a daemon that never ran\n'; fails=$((fails + 1)); }

  # 7. the hash is READ, never derived: a foreign hash reddens, and an item with no bcrypt_hash
  #    cannot answer the arm at all — an unproven password is not a verified one.
  printf '%s\n' '{"version":1,"daemon":{"relay":{"enabled":false},"listen":"0.0.0.0:6768","auth":{"password":"$2b$12$someotherhashnottheitem"}}}' > "$CFG"
  PI_SEAT=wsl run_at 1 "a hash that is not the item's" --check --strict
  grep -q 'daemon.auth.password' "$t/out" || { printf 'NOT CAUGHT a seat carrying a foreign hash stayed green\n'; fails=$((fails + 1)); }
  wsl_converged; FIXTURE="$t/vault-nohash.json" PI_SEAT=wsl run_at 1 "the item carries no bcrypt_hash" --check --strict
  grep -q 'UNPROVEN' "$t/out" || { printf 'NOT CAUGHT a vault read that failed answered as a pass\n'; fails=$((fails + 1)); }

  # 8. a seat the row does not name answers SKIP at rc 2, and --push writes NOTHING there.
  wsl_converged
  PI_SEAT=win11 run_at 2 "off-scope seat checks" --check --strict
  grep -q '^SKIP: win11' "$t/out" || { printf 'NOT CAUGHT an off-scope seat did not answer SKIP\n'; fails=$((fails + 1)); }
  rm -f "$CFG"; PI_SEAT=win11 run_at 2 "off-scope seat pushes" --push
  [ -e "$CFG" ] && { printf 'NOT CAUGHT --push wrote off-scope\n'; fails=$((fails + 1)); }

  # 9. oldsrv owes the DOOR arms and NOT the bind — and its push must not touch listen, or the
  #    plane would fight roles/seat for one address.
  printf '%s\n' '{"version":1,"daemon":{"relay":{"enabled":false},"hostnames":["paseo-oldsrv.ts.kogler.si"],"trustedProxies":["127.0.0.1"]}}' > "$CFG"
  PI_SEAT=oldsrv run_at 0 "oldsrv converged (door arms present)" --check --strict
  grep -q "the unit's" "$t/out" || { printf 'NOT CAUGHT oldsrv did not say which carrier owns the bind\n'; fails=$((fails + 1)); }
  printf '%s\n' '{"version":1,"daemon":{"relay":{"enabled":false},"listen":"127.0.0.1:6768","hostnames":["wrong.example"],"trustedProxies":["127.0.0.1"]}}' > "$CFG"
  PI_SEAT=oldsrv run_at 1 "oldsrv with the wrong Host allowlist" --check --strict
  grep -q 'router is up and the daemon would answer this Host 403' "$t/out" \
    || { printf 'NOT CAUGHT a door the daemon 403s was not named as a door\n'; fails=$((fails + 1)); }
  # The push CANNOT repair an arm it does not own, and says so (rc 1) rather than quietly going
  # green: an arm another author owns is reported, never overwritten from a laptop.
  PI_SEAT=oldsrv run_at 1 "oldsrv push leaves the door arms and the bind alone" --push
  grep -q '"listen": *"127.0.0.1:6768"' "$CFG" || { printf 'NOT CAUGHT the oldsrv push rewrote the bind the unit owns\n'; fails=$((fails + 1)); }
  grep -q 'wrong.example' "$CFG" || { printf 'NOT CAUGHT the oldsrv push wrote a door arm roles/seat owns\n'; fails=$((fails + 1)); }

  printf '\nself-test: %s\n' "$([ "$fails" -eq 0 ] && echo "OK — all canaries caught" || echo "$fails canary/canaries NOT caught")"
  return "$fails"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) MODE="check" ;;
    --strict) STRICT=1 ;;
    --push)  MODE="push" ;;
    --self-test) MODE="selftest" ;;
    --help|-h) usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

case "$MODE" in
  check)    do_check ;;
  push)     do_push ;;
  selftest) self_test ;;
esac
