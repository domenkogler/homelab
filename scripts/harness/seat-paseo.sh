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
#                          derived here, so a rotation cannot leave a seat answering on its own. The
#                          ONE arm merged into the file instead of written through the CLI, because no
#                          `paseo` command will carry it (THE CARRIER, below).
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
# THE CARRIER, AND WHICH HALF MAY ASK FOR IT
#   The fan-out leg is `ssh -n host "cd dir && cmd"` (pi-seat-sync.sh `seat_ssh_exec`), which reads no
#   startup file. On `oldsrv` the CLI lives in the dir the rendered `paseo.service` drop-in puts on
#   PATH (`~/.local/share/pi-node/current/bin`), which only the seat's own shell carries — so a bare
#   `command -v` on that leg answers "no CLI" about a seat whose every owed arm is already the render.
#   That is the over-report lib/pi-seat.sh records for the login/interactive split, arriving through a
#   different door: the verdict named the seat (`this seat has no @getpaseo/cli`) while what it had
#   actually read was one transport's PATH. So the halves are gated apart. The READ half is gated by
#   `config.json` alone — python parses the file and no arm needs the binary — and only the WRITE half,
#   the half that execs the CLI to merge a value, refuses for its absence. Asking in both halves bought
#   `MISSING` on a green seat; refusing only in the write half still refuses a seat that cannot write.
#
#   ONE ARM HAS NO CLI CARRIER, measured on the 0.15.0 CLI. `daemon config set` refuses any path under
#   `daemon.auth` — `Error: Use daemon set-password to change the daemon password.`, rc 1, the file
#   untouched — and `daemon set-password` reads its PLAINTEXT from a TERMINAL (`needs a terminal to read
#   the password` over a pipe) and bcrypts what it reads with a FRESH SALT, so it answers a different
#   60-char string for the same value and can never produce the stored hash this arm compares against.
#   `daemon.auth.password` is therefore MERGED into config.json by `merge_auth_hash`: the same file the
#   CLI writes for every other arm, at the mode the CLI writes it (0600), every other key carried
#   through the same parse, and a rename behind it so a file that cannot be written is left alone. That
#   is a merge into the CLI's OWN file, not a second source of truth: the value still lives in the
#   vault item and is never derived here. A vault read that fails leaves the arm UNWRITTEN and the bytes
#   exactly as found — the `DRIFT(auth)` refusal that keeps an unproven password unproven rather than
#   half-written. `daemon.listen` and `daemon.relay.enabled` are carried by the CLI alone, which merges
#   for them; a push that cannot exec the CLI therefore lands this one arm (merging a file needs no
#   binary) and then names the arms it could NOT carry, instead of reporting a run that converged the
#   seat.
#
# VERDICTS
#   OK                every arm this seat owes is what the seat owes
#   MISSING           no config.json — no daemon has ever run on this seat; in the WRITE half only,
#                     also no `paseo` CLI this shell can exec, and then that line names the arms it
#                     could not carry. The READ half never asks for the binary: it parses config.json
#                     itself (see THE CARRIER, BELOW).
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
#   The merge that carries the auth arm keeps the same rule: the hash arrives on the python child's
#   STDIN — never in argv, which `ps` shows to the whole machine — that child prints nothing when it
#   succeeds, and the `wrote` line for the arm goes through `describe_secret` as its drift line does. A
#   merge that fails names the file and never the value.
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

# merge_auth_hash <hash> — the carrier for the ONE arm the CLI refuses to write, the arm's value
# merged into $CONFIG_JSON. WHY the CLI is not the carrier here, both halves measured on 0.15.0:
# `daemon config set daemon.auth.password …` answers `Error: Use daemon set-password to change the
# daemon password.` at rc 1 and leaves the file untouched, and `daemon set-password` reads a PLAINTEXT
# from a terminal (a pipe answers `needs a terminal to read the password`) and bcrypts it with a FRESH
# SALT — so it cannot be pointed at the stored hash, which is what `assess` compares this arm against.
# This is NOT a second source of truth: it writes the same config.json the CLI writes for every other
# arm, at the 0600 the CLI writes it at, and the value it writes is READ from the vault item, never
# derived here. Everything outside the one dotted path is carried through the same parse, and the write
# lands as a rename of a sibling temp file, so a file that cannot be written is left exactly as found.
# The hash arrives on STDIN, never in argv, and nothing here prints it: a refusal names the file and the
# shape of the problem, never the value (CONVENTIONS §3).
merge_auth_hash() {
  printf '%s' "$1" | python3 -c '
import json, os, sys, tempfile
path, arm = sys.argv[1], sys.argv[2]
want = sys.stdin.read().strip()
if not want:
    sys.stderr.write("seat-paseo: no value on stdin to merge\n"); raise SystemExit(1)
try:
    with open(path) as fh:
        doc = json.load(fh)
except json.JSONDecodeError:
    sys.stderr.write("seat-paseo: %s is not JSON — nothing was merged\n" % path); raise SystemExit(1)
except OSError as exc:
    sys.stderr.write("seat-paseo: %s could not be read (%s)\n" % (path, exc.strerror or type(exc).__name__)); raise SystemExit(1)
if not isinstance(doc, dict):
    sys.stderr.write("seat-paseo: %s is not a JSON object — nothing was merged\n" % path); raise SystemExit(1)
parts = arm.split(".")
cur = doc
for i, part in enumerate(parts[:-1]):
    nxt = cur.get(part)
    if nxt is None:
        nxt = cur[part] = {}
    elif not isinstance(nxt, dict):
        # A scalar sitting where the arm needs an object is a shape to refuse, not to overwrite: the
        # merge carries the arm in, it does not decide what another author meant.
        sys.stderr.write("seat-paseo: %s holds a non-object at %s — nothing was merged\n"
                         % (path, ".".join(parts[:i + 1]))); raise SystemExit(1)
    cur = nxt
cur[parts[-1]] = want
fd, tmp = tempfile.mkstemp(prefix=".config.json.", dir=os.path.dirname(path) or ".")
try:
    os.fchmod(fd, 0o600)                      # the secret is never world-readable, not even in the temp
    with os.fdopen(fd, "w") as fh:
        json.dump(doc, fh, indent=2)           # the shape the CLI itself writes: 2-space indent, file order
        fh.write("\n")
    os.replace(tmp, path)                      # atomic: a failed write cannot leave a half config
    os.chmod(path, 0o600)
except OSError as exc:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    sys.stderr.write("seat-paseo: %s could not be written (%s)\n" % (path, exc.strerror or type(exc).__name__)); raise SystemExit(1)
' "$CONFIG_JSON" "daemon.auth.password"
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

# prelude — scope, render, and the states that are not verdicts about the arms: no config (no daemon has
# ever run) for both halves, and no CLI for the WRITE half only (THE CARRIER above). Nothing here
# asks a login or interactive shell: widening the probe would replace one over-report with another,
# and the half that writes must know whether IT can exec the carrier it is standing on. The CLI answer
# is recorded in CLI_OK rather than answered here, because ONE arm has no CLI carrier at all and must
# still be landed on a seat whose CLI this transport cannot resolve.
# Sets VERDICT/REASON/CLI_OK and returns 0 (assess) or 1 (already answered).
prelude() {
  CLI_OK=1
  seat_scope
  [ "$SCOPE" = here ] || { scope_verdict; return $?; }
  seat_render || stop "seat $SEAT has no Paseo render — a seat this plane knows nothing about"
  command -v python3 >/dev/null 2>&1 || stop "no python3 here — neither config.json nor the vault answer can be parsed"
  if [ ! -e "$CONFIG_JSON" ]; then
    printf 'MISSING: no %s — no daemon has ever run on this seat\n' "$CONFIG_JSON"
    return 1
  fi
  # The CLI is the WRITE carrier and nothing else. The sentence claims only what this half can prove —
  # that THIS shell cannot exec it — and never that the seat has no such package, which is the
  # over-report the read half must not carry.
  [ "$MODE" = push ] || return 0
  command -v "$PASEO_BIN" >/dev/null 2>&1 || CLI_OK=0
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
  local arm want got wrote=0 cli_refused=""
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
    if [ "$arm" = daemon.auth.password ]; then
      # No CLI carrier for this arm — see `merge_auth_hash`. It lands (or refuses) whatever this
      # transport can exec the CLI from, which is the point of carrying it through the file.
      merge_auth_hash "$want" || { printf 'DRIFT(%s): the write did not take\n' "$arm"; return 1; }
      printf 'wrote %s = %s from %s\n' "$arm" "$(describe_secret "$want")" "$VAULT_ITEM"
      wrote=1
      continue
    fi
    if [ "$CLI_OK" = 0 ]; then
      cli_refused="$cli_refused $arm"      # named below; the merge above is not a way to write these
      continue
    fi
    "$PASEO_BIN" --home "$PASEO_HOME" daemon config set "$arm" "$want" >/dev/null 2>&1 || {
      printf 'DRIFT(%s): the write did not take\n' "$arm"; return 1; }
    printf 'wrote %s = %s\n' "$arm" "$want"
    wrote=1
  done
  # The refusal this half owes a CLI it cannot exec, and it is still a refusal at rc 1 whether or not
  # the merge above had anything to write: an arm the CLI carries is an arm this run did not converge.
  if [ "$CLI_OK" = 0 ]; then
    printf 'MISSING: no `paseo` CLI this shell can exec — %s (those arms ride @getpaseo/cli on this transport'"'"'s PATH alone, ⛔ never the squatted `paseo` package)%s\n' \
      "$([ -n "$cli_refused" ] && printf 'not written: %s' "${cli_refused# }" || printf 'nothing the CLI carries needed writing')" \
      "$([ "$UNIT" = no ] && printf '; `daemon.auth.password` needs no CLI and is carried by the merge above')"
    return 1
  fi
  assess
  [ "$VERDICT" = OK ] && { printf 'OK: re-read config.json — the arms this seat owes are the render%s\n' \
      "$([ "$wrote" = 0 ] && printf ' (nothing needed writing)')"; return 0; }
  printf '%s: after the push — %s\n' "$VERDICT" "$REASON"
  return 1
}

# --- self-test: stubs, so no daemon, no vault, no seat -----------------------------------
self_test() {
  local t fails=0 CFG want CLI m ino
  t="$(mktemp -d)" || { err "mktemp failed"; return 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$t'" RETURN
  mkdir -p "$t/bin" "$t/home/.paseo"
  CFG="$t/home/.paseo/config.json"
  # CLI — the $PASEO_BIN every arm gets by default: the stub below. Arm 12 points it at a path that
  # does not exist, which is how a seat whose CLI sits in a dir this transport's PATH cannot see is
  # bred without touching the host PATH (an absolute $PASEO_BIN is taken at its own word).
  CLI="$t/bin/paseo"

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

  # The fixture's secrets, named ONCE and shaped like the real item's: `password` 32, `bcrypt_hash`
  # 60 (docs/deployment-secrets.md, paseo_password). They are the bytes the value-canary below
  # refuses to see in output, so a fixture that spelled them some other way could disarm that scan
  # without touching it.
  local STUB_HASH STUB_PLAIN STUB_FOREIGN
  STUB_HASH='$2b$12$'"$(printf 'a%.0s' {1..53})"
  STUB_PLAIN="$(printf 'b%.0s' {1..32})"
  STUB_FOREIGN='$2a$10$'"$(printf 'c%.0s' {1..53})"   # a hash that is NOT the item's (arm 7)

  # A vault fixture, in vault_read.py's --values shape.
  printf '{"items":{"i1":{"title":"paseo_password","version":1,"fields":[{"label":"password","value":"%s"},{"label":"bcrypt_hash","value":"%s"}]}}}\n' \
    "$STUB_PLAIN" "$STUB_HASH" > "$t/vault.json"
  printf '{"items":{"i1":{"title":"paseo_password","version":1,"fields":[{"label":"password","value":"%s"}]}}\n' \
    "$STUB_PLAIN" > "$t/vault-nohash.json"

  # --- the value-canary ------------------------------------------------------------------
  # Every rc assertion below proves WORDING and rc; none of them proves NEVER-PRINT. That gap is how
  # paseo_password's bcrypt hash reached three run captures: a `--check` drift line printed the arm's
  # value, every arm stayed green, and the self-test reported "all canaries caught". So each arm's
  # output is scanned too, in whatever mode that arm runs, for three shapes — a bcrypt hash, a bare
  # 32-char token (the minted shape of every value in this vault), and the fixture's own bytes.
  # Shapes are stated, not derived from the fixtures: editing a fixture value must not blind the scan.
  local SCAN_BCRYPT='\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}'
  local SCAN_TOKEN='(^|[^A-Za-z0-9])[A-Za-z0-9]{32}([^A-Za-z0-9]|$)'

  secret_scan() { # secret_scan <file> — the secret SHAPES in a run's output, never the bytes: this
    # report lands in a run capture too, so it names shapes and no value (§3).
    local found=""
    grep -qE -- "$SCAN_BCRYPT" "$1" 2>/dev/null && found="$found a-bcrypt-hash"
    grep -qE -- "$SCAN_TOKEN" "$1" 2>/dev/null && found="$found a-32-char-token"
    grep -qF -e "$STUB_HASH" -e "$STUB_PLAIN" "$1" 2>/dev/null && found="$found the-stubbed-vault-value"
    printf '%s' "${found# }"
  }

  redact() { # redact — the shape of every secret-shaped string, for a diagnostic that dumps output.
    sed -E 's%\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}%[a bcrypt hash]%g; s%(^|[^A-Za-z0-9])[A-Za-z0-9]{32}([^A-Za-z0-9]|$)%[a 32-char token]%g'
  }

  run_cli() { # run_cli <script> <args...> — one real invocation of a seat-paseo script in the fixture
    # seat; the output lands in "$t/out" and the exit status is the return value. A copy of this file
    # lives in a marker-complete tree whose scripts/lib IS this one, so it reads the same registry.
    local script="$1"; shift
    env -u REPO PI_SEAT="${PI_SEAT:-wsl}" PASEO_BIN="$CLI" PASEO_HOME_DIR="$t/home/.paseo" \
        ST_CFG="$CFG" HL_VAULT_READ_FIXTURE="${FIXTURE:-$t/vault.json}" \
        bash "$script" "$@" > "$t/out" 2>&1
  }

  run_at() { # run_at <expect-rc> <name> <args...> — every arm drives the REAL script; $CLI says which
    # carrier that shell can resolve (arm 12 breeds the seat whose carrier it cannot)
    local want="$1" name="$2"; shift 2
    local rc=0 leak note=' (no secret-shaped output)'
    run_cli "${BASH_SOURCE[0]}" "$@" || rc=$?
    leak="$(secret_scan "$t/out")"
    if [ -n "$leak" ]; then
      printf 'NOT CAUGHT  %s — the output carries %s; the bytes are never echoed here\n' "$name" "$leak"
      fails=$((fails + 1)); note=''
    fi
    if [ "$rc" = "$want" ]; then printf 'ok   rc %s  %s%s\n' "$rc" "$name" "$note"
    else printf 'NOT CAUGHT  wanted rc %s, got %s  %s\n%s\n' "$want" "$rc" "$name" "$(redact < "$t/out" | sed 's/^/        /')"; fails=$((fails + 1)); fi
  }

  # seat_cfg <relay> <listen> <password> — the one spelling of a seat's config.json in this fixture.
  seat_cfg() { printf '{"version":1,"daemon":{"relay":{"enabled":%s},"listen":"%s","auth":{"password":"%s"}}}\n' \
      "$1" "$2" "$3" > "$CFG"; }
  wsl_converged() { seat_cfg false "0.0.0.0:6768" "$STUB_HASH"; }

  # 1. every arm right → OK, rc 0.
  wsl_converged; PI_SEAT=wsl run_at 0 "converged seat" --check --strict
  grep -q '^OK:' "$t/out" || { printf 'NOT CAUGHT the converged case printed no OK line\n'; fails=$((fails + 1)); }
  grep -q '^OK:' "$t/out" || { printf 'NOT CAUGHT the converged case printed no OK line\n'; fails=$((fails + 1)); }

  # 2. THE DEFECT THIS ROW CLOSES: the relay is ON. A seat that can reach the vendor relay is the
  #    state the house posture refuses, and a check that stayed green over it is a mute gate.
  seat_cfg true "0.0.0.0:6768" "$STUB_HASH"
  PI_SEAT=wsl run_at 1 "relay on" --check --strict
  grep -q 'daemon.relay.enabled' "$t/out" || { printf 'NOT CAUGHT a relay-on seat was not named\n'; fails=$((fails + 1)); }

  # 3. the bind: loopback on a laptop seat is the state where the phone never arrives.
  seat_cfg false "127.0.0.1:6768" "$STUB_HASH"
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
  seat_cfg false "0.0.0.0:6768" "$STUB_FOREIGN"
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

  # 10. THE CANARY FOR THE CANARY: the scan must fire on every shape it claims to catch, and stay
  #     silent on the redacted wording a clean run prints. An unproven scan is the same mute gate in
  #     a better costume, so both halves are asserted here (CONVENTIONS §6).
  local plant hits
  for plant in "$STUB_HASH" "token=$STUB_PLAIN" "want=$STUB_FOREIGN"; do
    printf 'DRIFT: daemon.auth.password=%s\n' "$plant" > "$t/plant"
    hits="$(secret_scan "$t/plant")"
    if [ -n "$hits" ]; then printf 'ok   the leak scan catches %s\n' "$hits"
    else printf 'NOT CAUGHT  the leak scan ignored a planted value\n'; fails=$((fails + 1)); fi
  done
  printf 'DRIFT: daemon.listen=127.0.0.1:6768 want=0.0.0.0:6768 daemon.auth.password=a bcrypt hash (60 chars) want=a bcrypt hash (60 chars)\n' > "$t/clean"
  hits="$(secret_scan "$t/clean")"
  [ -z "$hits" ] || { printf 'NOT CAUGHT the leak scan fired on the redacted wording: %s\n' "$hits"; fails=$((fails + 1)); }
  printf 'ok   the leak scan stays silent on the redacted wording it is supposed to accept\n'
  # And the diagnostic that dumps a failing arm's output must not report a leak by committing one:
  # this self-test's own stdout lands in a run capture, the same class the leak was found in.
  printf 'DRIFT: daemon.auth.password=%s want=%s\n' "$STUB_HASH" "$STUB_PLAIN" > "$t/dump"
  local shown; shown="$(redact < "$t/dump")"
  hits="$(printf '%s\n' "$shown" | secret_scan /dev/stdin)"
  if [ -n "$hits" ]; then
    printf 'NOT CAUGHT  the rc-mismatch diagnostic still carried %s\n' "$hits"; fails=$((fails + 1))
  elif ! printf '%s' "$shown" | grep -q '\[a bcrypt hash\].*\[a 32-char token\]'; then
    printf 'NOT CAUGHT  the redactor changed nothing (it runs, but it matches nothing)\n'; fails=$((fails + 1))
  else printf 'ok   the rc-mismatch diagnostic is redacted before it is printed\n'; fi

  # 11. PROOF OF BITE. This copy's `describe_secret` prints what it is handed — the exact edit that
  #     put the bcrypt hash in three run captures, and one every rc assertion here stayed green
  #     over. The scan must redden it in EVERY mode, the push's `wrote` line and every drift line
  #     included. If these arms go green, the canary is decoration.
  local mut="$t/mut" lib_dir
  # A marker-complete tree of its own, whose scripts/lib IS this one: the mutant resolves its repo
  # root, its plane registry and its vault reader normally, so only the script under test is mutated.
  lib_dir="$(dirname "$(hl_seat_registry_path)")"
  mkdir -p "$mut/IaC/ansible" "$mut/docs" "$mut/scripts/harness"
  : > "$mut/docs/index.md"
  ln -s "$lib_dir" "$mut/scripts/lib"   # a symlink, not a copy: nothing under $mut may shadow the real lib
  python3 - "${BASH_SOURCE[0]}" "$mut/scripts/harness/seat-paseo.sh" <<'PY' || { printf 'NOT CAUGHT the mutant could not be built — the bite is unproven\n'; fails=$((fails + 1)); }
import sys
src = open(sys.argv[1]).read()
anchor = 'describe_secret() {\n  case "$1" in'
if src.count(anchor) != 1:
    raise SystemExit('the mutation anchor is gone: the canary has no witness')
open(sys.argv[2], 'w').write(src.replace(
    anchor,
    'describe_secret() {\n  printf "%s" "$1"   # MUTANT: hands back the value, which is the leak under test\n  return\n  case "$1" in'))
PY
  bite() { # bite <mode name> <args...> — the mutant must leak, and the scan must say so
    local name="$1"; shift
    local hits rc=0
    seat_cfg false "0.0.0.0:6768" "$STUB_FOREIGN"
    run_cli "$mut/scripts/harness/seat-paseo.sh" "$@" || rc=$?
    hits="$(secret_scan "$t/out")"
    if [ -n "$hits" ] && grep -qE '^(DRIFT|OK)' "$t/out"; then
      printf 'ok   the mutated copy leaks in %s and the scan catches it (%s)\n' "$name" "$hits"
    elif ! grep -qE '^(DRIFT|OK)' "$t/out"; then
      printf 'NOT CAUGHT  the mutant never reached the wording under test in %s (rc %s)\n' "$name" "$rc"
      fails=$((fails + 1))
    else printf 'NOT CAUGHT  the mutated copy printed nothing the scan recognises in %s (rc %s)\n' "$name" "$rc"; fails=$((fails + 1)); fi
  }
  bite '--check --strict' --check --strict
  bite '--check' --check
  bite '--push' --push

  # 12. THE DEFECT THIS HUNK CLOSES, bred BOTH ways. The READ answers from config.json and the
  #     fan-out's leg (`ssh host "cd dir && cmd"`) reads no startup file, so a seat whose CLI lives in
  #     a dir only its own shell carries used to answer `MISSING: … this seat has no @getpaseo/cli`
  #     while every arm it owed was already the render. A short PATH is a fact about ONE TRANSPORT, so
  #     it must not reach the read half at all — and the refusal that stays must stay a refusal: a
  #     config that is absent, or a write with no carrier, is still MISSING. Drop the gate and the
  #     push arms here go green; drop the config gate and the last arm goes green.
  local NO_CLI="$t/no-cli-on-this-path/paseo"   # an absolute path that is not there: no PATH search,
  #                                              so the arm cannot pass or fail by accident of the host
  wsl_converged
  CLI="$NO_CLI" PI_SEAT=wsl run_at 0 "config complete, CLI invisible to this transport" --check --strict
  grep -q '^MISSING:' "$t/out" && { printf 'NOT CAUGHT a short-PATH seat was still told it has no Paseo\n'; fails=$((fails + 1)); }
  grep -q '^OK:' "$t/out" || { printf 'NOT CAUGHT the short-PATH read did not answer from config.json\n'; fails=$((fails + 1)); }
  # The same seat with one arm off still reddens as a DRIFT that NAMES the arm: the CLI gate was not
  # what was holding the line on the relay.
  seat_cfg true "0.0.0.0:6768" "$STUB_HASH"
  CLI="$NO_CLI" PI_SEAT=wsl run_at 1 "short-PATH seat with the relay on" --check --strict
  grep -q '^DRIFT' "$t/out" || { printf 'NOT CAUGHT a short-PATH seat with a drifted arm stayed quiet\n'; fails=$((fails + 1)); }
  grep -q 'daemon.relay.enabled' "$t/out" || { printf 'NOT CAUGHT the short-PATH drift line did not name the arm\n'; fails=$((fails + 1)); }
  # oldsrv's own shape — the door arms, no bind, no password — under the same short PATH: the leg that
  # reproduced the defect must read OK, because that is the verdict the transport was wrong about.
  printf '%s\n' '{"version":1,"daemon":{"relay":{"enabled":false},"hostnames":["paseo-oldsrv.ts.kogler.si"],"trustedProxies":["127.0.0.1"]}}' > "$CFG"
  CLI="$NO_CLI" PI_SEAT=oldsrv run_at 0 "oldsrv door arms, CLI invisible to this transport" --check --strict
  grep -q '^MISSING:' "$t/out" && { printf 'NOT CAUGHT the oldsrv read still gated on the CLI\n'; fails=$((fails + 1)); }
  # AND THE REFUSAL, both halves of it. A write with no carrier refuses and writes NOTHING.
  wsl_converged
  CLI="$NO_CLI" PI_SEAT=wsl run_at 1 "push refuses with no CLI carrier" --push
  grep -q '^MISSING:' "$t/out" || { printf 'NOT CAUGHT a push with no CLI wrote anyway\n'; fails=$((fails + 1)); }
  grep -q '^wrote ' "$t/out" && { printf 'NOT CAUGHT the push wrote without a carrier\n'; fails=$((fails + 1)); }
  # Neither a CLI nor a config: no daemon has ever run, and that is MISSING in both halves.
  rm -f "$CFG"
  CLI="$NO_CLI" PI_SEAT=wsl run_at 1 "no CLI and no config, check" --check --strict
  grep -q '^MISSING: no ' "$t/out" || { printf 'NOT CAUGHT a seat with neither CLI nor config was not MISSING\n'; fails=$((fails + 1)); }
  CLI="$NO_CLI" PI_SEAT=wsl run_at 1 "no CLI and no config, push" --push
  [ -e "$CFG" ] && { printf 'NOT CAUGHT --push created a config on a seat with no carrier\n'; fails=$((fails + 1)); }
  CLI="$t/bin/paseo"   # restore the default carrier for anything that runs after this arm

  # 13. THE CARRIER `daemon.auth.password` now has, bred in BOTH directions. The CLI cannot carry this
  #     arm: `daemon config set` refuses any `daemon.auth.*` path and `daemon set-password` reads a
  #     PLAINTEXT from a terminal and salts it fresh, so the push merges the vault's stored hash into
  #     the same config.json the CLI writes. Four states are bred, because each is a way the merge could
  #     go green while being wrong: (a) a seat owed the arm and its config lacks it — the item's hash
  #     lands, the file still re-reads, and every key the merge does not own survives; (b) a seat whose
  #     hash already matches is NOT rewritten; (c) a vault that cannot be read leaves the arm unwritten
  #     and the bytes identical; (d) a file that cannot be parsed is still a REFUSAL, never a file to
  #     merge over.
  # cfg_same_except_auth <after> <before> — every key/value outside `daemon.auth` survived the merge,
  # compared as parsed JSON so the re-serialisation the merge does cannot fail the check.
  cfg_same_except_auth() {
    python3 - "$1" "$2" <<'PY'
import json, sys
def strip(path):
    with open(path) as fh:
        doc = json.load(fh)
    daemon = doc.get("daemon")
    if isinstance(daemon, dict):
        daemon.pop("auth", None)
    return doc
sys.exit(0 if strip(sys.argv[1]) == strip(sys.argv[2]) else 1)
PY
  }
  # cfg_auth_is_the_item — the arm in the file is the fixture item's hash, compared inside python so the
  # bytes never cross this script's stdout (§3).
  cfg_auth_is_the_item() {
    python3 - "$CFG" "$t/vault.json" <<'PY'
import json, sys
with open(sys.argv[1]) as fh:
    got = json.load(fh).get("daemon", {}).get("auth", {}).get("password")
with open(sys.argv[2]) as fh:
    want = [f["value"] for f in json.load(fh)["items"]["i1"]["fields"] if f.get("label") == "bcrypt_hash"][0]
sys.exit(0 if got == want else 1)
PY
  }
  cfg_ino() { python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_ino)' "$1"; }
  # mode_of / msys_here — the mode as the platform reports it. MSYS derives it from the ACL, so a strict
  # 0600 read-back only means anything on a POSIX seat: the same carve-out and the same wording
  # seed-seat-ssh-config.sh's arm 1f states, said rather than passed silently.
  mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1" 2>/dev/null || echo '?'; }
  msys_here() { case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; *) return 1 ;; esac; }

  # (a) the arm is owed and absent: the hash lands, the keys survive, the file re-reads at 0600.
  printf '%s\n' '{"version":1,"daemon":{"relay":{"enabled":false},"listen":"0.0.0.0:6768","cors":{"allowedOrigins":["https://app.paseo.sh"]}},"app":{"baseUrl":"https://app.paseo.sh"}}' > "$CFG"
  chmod 600 "$CFG"; cp "$CFG" "$t/auth.before"
  PI_SEAT=wsl run_at 0 "push merges the vault hash into a config that lacks the arm" --push
  grep -q '^wrote daemon.auth.password = a bcrypt hash (60 chars) from paseo_password' "$t/out" \
    || { printf 'NOT CAUGHT the auth merge did not report the arm it wrote\n'; fails=$((fails + 1)); }
  grep -q '^OK: re-read' "$t/out" \
    || { printf 'NOT CAUGHT the push did not re-read the arm it merged\n'; fails=$((fails + 1)); }
  cfg_auth_is_the_item || { printf 'NOT CAUGHT the arm in config.json is not the vault item hash\n'; fails=$((fails + 1)); }
  cfg_same_except_auth "$CFG" "$t/auth.before" \
    || { printf 'NOT CAUGHT the merge changed a key outside daemon.auth\n'; fails=$((fails + 1)); }
  m="$(mode_of "$CFG")"
  if [ "$m" = 600 ]; then printf 'ok   the merge lands its config at 0600\n'
  elif msys_here; then printf 'ok   MSYS reports mode %s from the ACL — the 0600 read-back runs on a Debian seat\n' "$m"
  else printf 'NOT CAUGHT the merge left the config mode %s, not 600\n' "$m"; fails=$((fails + 1)); fi

  # (b) the hash already matches: nothing is rewritten. The INODE is the witness — a re-write renames a
  # new file over the old one, and a converge that rewrote a secret it agrees with would burn the vault
  # read and the file for nothing, every leg, forever.
  ino="$(cfg_ino "$CFG")"
  PI_SEAT=wsl run_at 0 "a matching hash is not rewritten" --push
  grep -q '^wrote ' "$t/out" && { printf 'NOT CAUGHT the push rewrote an auth arm that already matched\n'; fails=$((fails + 1)); }
  [ "$ino" = "$(cfg_ino "$CFG")" ] \
    || { printf 'NOT CAUGHT a converged seat had its config.json rewritten anyway\n'; fails=$((fails + 1)); }
  m="$(mode_of "$CFG")"
  if [ "$m" = 600 ]; then printf 'ok   a converged seat keeps its config at 0600\n'
  elif msys_here; then printf 'ok   MSYS reports mode %s from the ACL — the 0600 read-back runs on a Debian seat\n' "$m"
  else printf 'NOT CAUGHT a no-op push left the config mode %s, not 600\n' "$m"; fails=$((fails + 1)); fi

  # (c) the vault cannot answer: the arm stays unwritten and the file byte-identical, and the run still
  # reddens — an unproven password never reads as a written one.
  cp "$CFG" "$t/vault-fail.before"
  FIXTURE="$t/vault-nohash.json" PI_SEAT=wsl run_at 1 "a vault that cannot answer leaves the arm unwritten" --push
  grep -q '^DRIFT(auth):' "$t/out" \
    || { printf 'NOT CAUGHT a failed vault read reached the merge\n'; fails=$((fails + 1)); }
  cmp -s "$CFG" "$t/vault-fail.before" \
    || { printf 'NOT CAUGHT --push wrote the config when the vault could not be read\n'; fails=$((fails + 1)); }

  # (d) an unparseable file is a REFUSAL, not a file to merge over: the arm being absent and the file
  # being unreadable are two different facts and only the first is this merge's business.
  printf '%s\n' '{"version":1,"daemon":' > "$CFG"; cp "$CFG" "$t/broken.before"
  PI_SEAT=wsl run_at 1 "push refuses to merge over an unparseable config" --push
  grep -q '^REFUSAL:' "$t/out" \
    || { printf 'NOT CAUGHT an unparseable config was merged over instead of refused\n'; fails=$((fails + 1)); }
  cmp -s "$CFG" "$t/broken.before" \
    || { printf 'NOT CAUGHT --push rewrote a config it could not parse\n'; fails=$((fails + 1)); }
  # And a shape the merge cannot walk — a scalar where `daemon.auth` must be an object — is refused the
  # same way rather than overwritten with the shape the merge would have liked.
  printf '%s\n' '{"version":1,"daemon":{"relay":{"enabled":false},"listen":"0.0.0.0:6768","auth":"not-an-object"}}' > "$CFG"
  cp "$CFG" "$t/scalar.before"
  PI_SEAT=wsl run_at 1 "push refuses to merge over a scalar daemon.auth" --push
  cmp -s "$CFG" "$t/scalar.before" \
    || { printf 'NOT CAUGHT the merge overwrote a daemon.auth it could not walk\n'; fails=$((fails + 1)); }

  # 14. THE MERGE IS NOT A BACK DOOR FOR THE CLI ARMS. Arm 12 proved the READ half does not need the
  #     binary; this proves the WRITE half lands ONLY the arm that genuinely needs no binary. A seat
  #     whose relay and bind are both wrong and whose CLI is invisible must still get the auth arm (the
  #     CLI could not write it anyway) and must still be REFUSED the two arms the CLI carries, unwritten
  #     and at rc 1. Delete the gate and the CLI arms get written here without a carrier.
  printf '%s\n' '{"version":1,"daemon":{"relay":{"enabled":true},"listen":"127.0.0.1:6768"}}' > "$CFG"
  CLI="$NO_CLI" PI_SEAT=wsl run_at 1 "no CLI: the auth arm lands by the merge, the CLI arms stay refused" --push
  grep -q '^wrote daemon.auth.password' "$t/out" \
    || { printf 'NOT CAUGHT the auth arm was withheld for want of a CLI that cannot carry it\n'; fails=$((fails + 1)); }
  grep -q '^MISSING:' "$t/out" \
    || { printf 'NOT CAUGHT a push with no CLI carried no refusal\n'; fails=$((fails + 1)); }
  grep -q '^wrote daemon.listen\|^wrote daemon.relay.enabled' "$t/out" \
    && { printf 'NOT CAUGHT the push wrote a CLI arm with no CLI\n'; fails=$((fails + 1)); }
  grep -q '"enabled": true' "$CFG" \
    || { printf 'NOT CAUGHT the merge overwrote the relay arm the CLI owns\n'; fails=$((fails + 1)); }
  grep -q '"listen": "127.0.0.1:6768"' "$CFG" \
    || { printf 'NOT CAUGHT the merge overwrote the bind the CLI owns\n'; fails=$((fails + 1)); }
  cfg_auth_is_the_item || { printf 'NOT CAUGHT the auth arm did not reach config.json\n'; fails=$((fails + 1)); }
  CLI="$t/bin/paseo"

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
