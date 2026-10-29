#!/usr/bin/env bash
# =====================================================================
# seat-dns-route.sh — the `dns-route` seat plane: the WSL seat's resolver ROUTE arm, repo-owned.
#
# WHY THIS EXISTS
# ---------------
#   The seat leaks. A `*.kogler.si` name that only the split-horizon answers is queried against the
#   PUBLIC tree by the uplink behind the default route, and the zone's Cloudflare SOA minimum (1800 s)
#   caches that `NXDOMAIN` against the NAME — so the `A` lookup fails for the same half hour as the
#   `AAAA`, and the `AAAA` leg is the one that reaches the public tree. The fix was measured and landed:
#   a route-only claim for `~ts.kogler.si` + `~kogler.si` held on the PER-LINK plane, re-asserted every
#   2 minutes, because per-link state does not survive a `systemd-resolved` restart or a link
#   reconfigure. What was never landed is the OWNER. The four artifacts that do this lived on one box, in
#   three unversioned files and one hand-placed script, so a reimaged seat came back leaking with nothing
#   in the tree to say so. This file is that owner.
#
#   It implements the three rules docs/network-dns.md §Host-side resolver states, one per mechanism:
#     · the claim is held PER-LINK, because `resolved.conf.d` merges the `DNS=`/`Domains=` of EVERY
#       drop-in onto EVERY global server — a drop-in cannot assign different domains to different
#       servers. Only per-link state pairs a server with its domains, and `resolvectl domain` REPLACES
#       the list, so both domains go in ONE call.
#     · per-link state does not survive a resolved restart or a link reconfigure, hence the oneshot plus
#       timer, `Type=oneshot` WITHOUT `RemainAfterExit`: with it the unit stays `active (exited)` and
#       every later start, timer fires included, is a no-op that REPORTS SUCCESS.
#     · `resolvectl` exits 0 when resolved refuses the call, so the re-assert reads itself back: the
#       write's exit code says the call ran, the read-back is the verdict.
#
# WHAT THIS OWNS / WHAT IT DOES NOT
# ---------------------------------
#   Three FILES, byte for byte, and one ACT:
#     homelab-dns.conf               the uplink drop-in, in resolved.conf.d
#     homelab-dns-route.service      the oneshot whose ExecStart runs THIS script's `--push`
#     homelab-dns-route.timer        the cadence, WantedBy=timers.target — the only unit that gets enabled
#     the per-link claim             an ACT, not a file: `resolvectl dns <link> 100.100.100.100` plus
#                                    `resolvectl domain <link> "~ts.kogler.si" "~kogler.si"`, read back and
#                                    compared, by `--push`
#   The unit NAMES are the live ones: both units are enabled on the seat today, and renaming a live unit
#   to make a repo path match is how an arm gets orphaned. What moves is where its ExecStart points:
#   `/bin/bash <repo>/scripts/harness/seat-dns-route.sh --push`, the repo root FOUND from this script's
#   own location. The copy under `/usr/local/sbin` is not kept — see DRIFT(legacy) — because an unowned
#   copy is a second source that no converge reaches and no drift check can see (CONVENTIONS §2), which
#   is the standing complaint about this very family.
#   Not the answer plane: no zone row, no netmap record, no `hosts` line, and the zone-wide "ask the home
#   resolver while at home" switch stays REJECTED for everything but the one inference name the `llm-path`
#   plane pins — `litellm` is the counter-example, answered by the LAN tier at an edge that returns 404
#   where the netmap answer serves 200. Not the engine, not the certificate, not `/etc/resolv.conf`, and
#   not `systemd-resolved` itself: this arm NEVER restarts the resolver, because bouncing it takes every
#   link's state with it, which is the very state this arm exists to hold.
#
# THE CONSTANTS THIS FILE HOLDS — and the values it does NOT
# ----------------------------------------------------------
#   100.100.100.100    the MagicDNS loop address — THIS family's constant, not a derived one: it is what
#                      the per-link arm asks, and the netmap's own loopback resolver does not move.
#   ~ts.kogler.si      the route-only claim. `~ts.kogler.si` may be MagicDNS-only; `~kogler.si` keeps
#   ~kogler.si         BOTH arms, because MagicDNS `SERVFAIL`s every name outside the netmap.
#   ~.  ~kogler.si     the GLOBAL claim in the drop-in: default-route everything, and keep the plain zone
#                      routed so an internal name gets the MagicDNS answer as well as the uplink's.
#   cadence            OnBootSec=10s OnUnitActiveSec=120s — the cadence the seat already runs. Note the
#                      direction of the citation: `seat-llm-path-timer.sh` cites THIS shape; that pair is
#                      the sibling, not the parent.
#   the uplink address DERIVED at run time from `ip route`. The WSL NAT gateway IS the Windows host
#   the link name  resolver and it MOVES between boots — the doc's own rule is "read it, never type it".
#                      A typed gateway is one address with two owners, and the owner that changes is the
#                      one that is not the file. So a boot that hands the guest a new gateway makes the
#                      drop-in DRIFT, and `--install` re-renders it; that is a verdict, not a bug.
#   An ambiguous read is a STOP, never a pick: no default route, or several with different gateways,
#   answers nothing (exit 2). Choosing the first line of a guessing order is a seat pointed at a gateway
#   it is not using, which is worse than no answer.
#   No fleet value sits in any of the three files beyond those constants — nothing here reads an
#   inventory host var, because the address this arm needs is this box's own routing table, not the
#   fleet's. The one thing it must not become is a second copy of a host address in a unit file.
#
# WHY OK IS BYTE EQUALITY
# -----------------------
#   `--check` renders the bytes `--install` writes, with the same derived gateway, and compares — so "in
#   sync" and "an install changes nothing" are ONE fact, never two claims that can disagree. Two
#   consequences worth saying out loud: every file this arm writes carries a `# managed-by:` line naming
#   the PLANE, not a path — a path-naming marker goes stale the day the script changes folder and then
#   accuses every file it wrote of being someone else's (the lesson install-tmux-conf.sh carries after
#   its own move) — so the live artifacts read DRIFT until the first `--install` adds that line; and the
#   live service ExecStart names `/usr/local/sbin`, so that one reads DRIFT for the same reason.
#   `--render` prints the target, `--install` lands it, `--check` measures the gap. One fidelity note is
#   worth keeping with the shape: the drop-in render is the seat's live `homelab-dns.conf` byte for byte
#   once the derived gateway is the one this boot has, apart from the marker line — so `--install` on the
#   seat changes one line of that file and nothing else, which is the point of rendering rather than
#   inventing a tidy version of what is already working.
#
# VERDICTS
#   OK               all three files are the render AND systemd says the timer is enabled
#   MISSING          a file this arm owns is not there — a reimaged box, or a hand cleanup
#   DRIFT            a file this arm wrote is not the render — a moved cadence, an ExecStart aimed outside
#                    the repo, a hand-added RemainAfterExit, a re-addressed gateway. ALSO the verdict for a
#                    timer systemd has never enabled: a written-but-never-enabled timer is an arm that
#                    never fires, and no file is out of place to blame
#   DRIFT(foreign)   bytes under one of these paths that this arm can prove NOTHING about — no marker, not
#                    the render, not the record of what this family hand-placed. Someone else's file under
#                    this arm's name. `--install` REFUSES and writes NOTHING: half an installed arm is a
#                    state no later verdict can describe, and an act that guesses is an act on a stranger.
#   DRIFT(drop-in)   a `<unit>.d/` drop-in that sets `RemainAfterExit` — the trap, arriving through a side
#                    door a green file compare cannot see. Any OTHER drop-in content prints as a NOTE and
#                    changes no verdict: that is an operator override, outside what this arm owns.
#   DRIFT(legacy)    PROVABLY this family's own unowned copy, in either of its two forms:
#                      · `/usr/local/sbin/homelab-dns-route.sh` — its sha256 equals the digest of the
#                        superseded script, or it carries this arm's marker. `--install` RETIRES it, moved
#                        aside under a dated name and inert because nothing names it: the act is the repo
#                        path now, and a second copy of an act is a second source.
#                      · one of the three files, still carrying the bytes this arm REPLACES — no marker
#                        because it predates the marker, equal byte for byte to the legacy render below.
#                        `--install` TAKES IT OVER: dated `.bak-` beside it, then the render. This is the
#                        migration, and it is the reason the arm can land on the seat it was written for.
#                    Both forms are PROVED by equality with something this family shipped. One edited byte
#                    defeats either proof and the file is DRIFT(foreign) instead — the rule is a fingerprint,
#                    never "it has no marker, so it must be ours".
#   DRIFT(per-link)  `--push` only, and only the READ-BACK can say it: resolved answers that link with a
#                    different server or domain set than the claim asked for. The write's rc 0 is not a
#                    verdict — this is (docs/network-dns.md §Host-side resolver).
#
# NOTE, never a verdict: a non-`.conf` file in `resolved.conf.d/` (this seat has two dated leftovers) is
#   INERT, because systemd-resolved reads only `*.conf`. Naming them and leaving the verdict alone is the
#   same discipline as the drop-in NOTE above: an exclusion wider than the finding is blindness with a
#   label on it, and a NOTE that reddens a seat over bytes nothing reads is a finding nobody can clear.
#
# Exit: 0 OK / repaired · 1 MISSING, or DRIFT under `--strict`, or a `--push` whose read-back disagrees
#       with the claim — the "exits 0 yet resolved refuses" class — or an `--install` that refused, or one
#       whose enable leg could not run ·
#       2 NO VERDICT — a directory cannot be read, the default route cannot be derived or is ambiguous,
#       the script the ExecStart names is not in the repo, the timer's enable state cannot be read at all,
#       a superseded copy whose provenance cannot be PROVED, or a sandbox hook that is wrong. A guess is
#       not a verdict.
#
# Usage:
#   bash scripts/harness/seat-dns-route.sh                     # --check, report only
#   bash scripts/harness/seat-dns-route.sh --check --strict    # the failing form of a check (seat-leg)
#   bash scripts/harness/seat-dns-route.sh --render [name]     # print what it renders; writes nothing
#   sudo bash scripts/harness/seat-dns-route.sh --install      # the FILES + the enable (root act)
#     `--install` runs FROM THE PRIMARY CLONE: from a linked worktree it refuses, because the ExecStart it
#     writes would name a lane directory that `git worktree remove` deletes. `--check` and `--render` are
#     read-only and run from anywhere.
#   sudo bash scripts/harness/seat-dns-route.sh --push         # the ACT: claim, read back, flush, log
#   bash scripts/harness/seat-dns-route.sh --self-test         # fixtures; no /etc, no systemd, no network
#
# Env hooks — every one points the script at a FIXTURE; none of them changes a verdict rule:
#   REPO                       a fixture repo whose scripts/harness/seat-dns-route.sh is the ExecStart target
#   SEAT_DNS_ROUTE_UNIT_DIR    the unit directory (default /etc/systemd/system)
#   SEAT_DNS_ROUTE_DROPIN_DIR  the resolved drop-in directory (default /etc/systemd/resolved.conf.d)
#   SEAT_DNS_ROUTE_LEGACY      the superseded copy's path (default /usr/local/sbin/homelab-dns-route.sh)
#   SEAT_DNS_ROUTE_IP          the `ip` used to derive link + uplink (default: PATH's)
#   SEAT_DNS_ROUTE_SYSTEMCTL   the `systemctl` used by the enable leg and the enabled-state read
#   SEAT_DNS_ROUTE_RESOLVEDCTL the `resolvectl` the act runs — a STUB holding the link state in a file, so
#                              "accepted with rc 0, obeyed nowhere" is an ARM and not a hope
#   SEAT_DNS_ROUTE_LOGGER      the `logger` the journal line goes to
#   SEAT_DNS_ROUTE_ST          set by a fixture run only: it arms the guard that STOPS an arm that forgot
#                              a stub, so no self-test can drive a real systemd or a real resolver
#
# ⚠ Nothing here is wired into validate-all.sh, and that is deliberate: on the other seats and on every
#   fleet host these artifacts are legitimately absent — the cockpit seat runs `systemd-resolved`
#   INACTIVE and has no `resolvectl` at all — so a gate item would report MISSING everywhere forever, the
#   mute-a-gate class. `--check` on the seat is the read, `--install` on the seat as root is the files.
#   Registry: scripts/lib/seat-planes.yml owns the PLANE (the record `plane: dns-route`, owner this file,
#   `seats: wsl`, `installer: none`) and the fan-out's push leg runs `--push`.
#   Rules: docs/network-dns.md §Host-side resolver · docs/harness-pi-seats.md §1 · CONVENTIONS §2, §6
# =====================================================================
set -uo pipefail

# The repo root is FOUND by scripts/lib/repo-root.sh, never assumed from a depth. An inherited $REPO
# still wins, which is the lever --self-test uses to point the ExecStart at a fixture repo.
_hl_self="${BASH_SOURCE[0]}"
case "$_hl_self" in */*) _hl_d="${_hl_self%/*}" ;; *) _hl_d="." ;; esac
_hl_d="$(cd "$_hl_d" && pwd)"
SCRIPT_DIR="$_hl_d"
SELF="$SCRIPT_DIR/$(basename "$_hl_self")"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"

# The ExecStart names THIS script by its repo path — that is the only way the arm is repo-owned rather
# than one box's state. Both segments are read from this file's own location, so a folder move cannot
# leave a unit pointing at a path the tree no longer has. The folder is a VARIABLE and the name is a
# variable: to `git grep scripts/[a-z-]*\.\w+` — which IS HD-1118's acceptance test — a literal
# `scripts/<name>.sh` is indistinguishable from a reference, and this file would be citing itself.
SUBDIR="$(basename "$SCRIPT_DIR")"
PLANE_SCRIPT="$REPO/scripts/$SUBDIR/$(basename "$SELF")"

SVC="homelab-dns-route.service"
TMR="homelab-dns-route.timer"
DROPIN_FILE="homelab-dns.conf"
UNIT_DIR="${SEAT_DNS_ROUTE_UNIT_DIR:-/etc/systemd/system}"
DROPIN_DIR="${SEAT_DNS_ROUTE_DROPIN_DIR:-/etc/systemd/resolved.conf.d}"
LEGACY="${SEAT_DNS_ROUTE_LEGACY:-/usr/local/sbin/homelab-dns-route.sh}"
IP_BIN="${SEAT_DNS_ROUTE_IP:-ip}"
SYSTEMCTL="${SEAT_DNS_ROUTE_SYSTEMCTL:-systemctl}"
RESOLVEDCTL="${SEAT_DNS_ROUTE_RESOLVEDCTL:-resolvectl}"
LOGGER_BIN="${SEAT_DNS_ROUTE_LOGGER:-logger}"

MAGICDNS="100.100.100.100"                 # the MagicDNS loop: what the per-link arm is asked to use
GLOBAL_DOMAINS='~. ~kogler.si'             # the drop-in's route-only claim (the plain zone keeps both arms)
# ONE `resolvectl domain` call, because the command REPLACES the link's domain list: two calls would
# leave only the last one in force and read green on the way there (docs/network-dns.md §Host-side
# resolver). The order here is the order the seat runs today.
ROUTE_DOMAINS=( '~ts.kogler.si' '~kogler.si' )
ON_BOOT_SEC="10s"
ON_ACTIVE_SEC="120s"
# WHO WROTE THIS FILE. The identity is the PLANE, not a path — a path-naming marker goes stale the day the
# script changes folder, and every file it wrote would start reading as foreign.
MARKER='# managed-by: homelab dns-route seat plane (scripts/harness/seat-dns-route.sh)'
# The FINGERPRINT of the superseded `/usr/local/sbin` script — a digest, never a value, and not a secret.
# It is how `--install` can say "this is the copy this family left behind, remove it" instead of "this is
# someone else's file at my path, write NOTHING". A hand-placed copy with edited bytes matches neither this
# digest nor the marker and is DRIFT(foreign): provenance is PROVED or the arm stops, because an uninstall
# that guesses is an act on someone else's file.
LEGACY_DIGEST="1971d4c77c4e750fb1af8eced4a65969d32e743e8876b8cb5a526eb8fdc63415"

MODE="check"; STRICT=0; SCRATCH=""; RENDER_ONLY=""
STATE=""; REASON=""; RANK=0; GW=""; LINK=""
# WITH_TRIGGER=1 is the whole verdict: the files AND the timer's enable state. `--install` sets it to 0 for
# its own post-write pass only — it has not enabled anything YET, so a not-yet-enabled timer would be
# accused of drift by the run that is about to enable it — and the enable leg then reads that half back and
# fails the install if it is wrong. Deferred, never dropped.
WITH_TRIGGER=1
A_NAMES=(); A_STATES=()

err()  { printf 'seat-dns-route: %s\n' "$*" >&2; }
note() { printf '  %s\n' "$*"; }
# A STOP, never a report: exit 2 means "no verdict was computed", so nothing downstream may read the run as
# a state. It must run in the CALLER's shell — inside `$( )` an `exit` stops only the subshell (the rule
# lib/pi-seat.sh carries), which is why every read here returns through a variable or a file and never
# through a command substitution.
stop() { printf 'FATAL: %s\n' "$*" >&2; exit 2; }
usage() {
  cat <<'EOF'
usage: seat-dns-route.sh [--check [--strict]] | --render [name] | --install | --push | --self-test

  --check          (default) report the three files, the timer's enabled state and the superseded copy
  --check --strict exit 1 on DRIFT too (MISSING exits 1 either way)
  --render [name]  print what this script renders — nothing written, nothing enabled. The names are
                   homelab-dns-route.service, homelab-dns-route.timer and homelab-dns.conf.
  --install        root act: write the three files, daemon-reload, `enable --now` the timer, TAKE OVER
                   this family's unowned copies (the bytes this arm replaces, kept as a dated .bak-) and
                   retire the superseded /usr/local/sbin copy (moved aside under a dated name) — but only
                   when that copy is provably this family's. Anything else at one of these paths is a
                   REFUSAL that writes NOTHING. Unprivileged: prints the exact sudo command and changes
                   nothing. From the PRIMARY clone only: a linked worktree refuses.
  --push           the ACT: derive link + uplink from `ip route`, claim the MagicDNS loop and BOTH route
                   domains on that link, READ THE CLAIM BACK (resolvectl exits 0 even when resolved
                   refuses, so the read-back is the verdict and the write's rc is a NOTE), flush the
                   caches, and log the exchange to the journal. This is what the timer's ExecStart runs.
                   Root: per-link state is not writable by a plain user.
  --self-test      fixture dirs + ip/systemctl/resolvectl/logger stubs; no /etc, no systemd, no network
EOF
}

scratch() {
  [ -n "$SCRATCH" ] && return 0
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/seat-dns-route.XXXXXX")" || { err "mktemp failed"; exit 2; }
}
cleanup() { [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; }
trap cleanup EXIT

# The self-test's belt: a fixture run must never be able to drive a real systemd or a real resolver. The
# stub hooks are the mechanism; this is what makes FORGETTING one a STOP rather than an act on the host
# running the test — and for this arm an act means rewriting a live seat's resolver state.
st_guard() {
  [ -n "${SEAT_DNS_ROUTE_ST:-}" ] || return 0
  # Four explicit tests, not a loop over names through `eval`: this is the one piece of the self-test that
  # has to be obvious at a glance, because a guard that quietly passes is a fixture that rewrites the seat.
  if [ -z "${SEAT_DNS_ROUTE_SYSTEMCTL:-}" ]; then
    stop "self-test arm with no SEAT_DNS_ROUTE_SYSTEMCTL stub — refusing to drive a real systemctl for a fixture"
  fi
  if [ -z "${SEAT_DNS_ROUTE_RESOLVEDCTL:-}" ]; then
    stop "self-test arm with no SEAT_DNS_ROUTE_RESOLVEDCTL stub — refusing to rewrite a live resolver for a fixture"
  fi
  if [ -z "${SEAT_DNS_ROUTE_IP:-}" ]; then
    stop "self-test arm with no SEAT_DNS_ROUTE_IP stub — a fixture must not read the host's routing table"
  fi
  if [ -z "${SEAT_DNS_ROUTE_LOGGER:-}" ]; then
    stop "self-test arm with no SEAT_DNS_ROUTE_LOGGER stub — a fixture must not write the host's journal"
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --check)     MODE="check" ;;
    --strict)    STRICT=1 ;;
    --install)   MODE="install" ;;
    --push)      MODE="push" ;;
    --render)    MODE="render" ;;
    --self-test) MODE="selftest" ;;
    -h|--help)   usage; exit 0 ;;
    *)
      if [ "$MODE" = "render" ] \
         && { [ "$1" = "$SVC" ] || [ "$1" = "$TMR" ] || [ "$1" = "$DROPIN_FILE" ]; }; then
        RENDER_ONLY="$1"
      else
        usage; exit 2
      fi ;;
  esac
  shift
done

# --- the derivations ---------------------------------------------------------------
# Two values come from the BOX and from nowhere else. `ip route` is ASKED, not assumed: the WSL NAT
# gateway is the Windows host resolver and it MOVES between boots, so typing it would give one address two
# owners and hand the changing half to the file nobody edits. Out-parameters, never a substitution: a STOP
# inside `$( )` stops only the subshell, and a silent empty answer here is a drop-in naming no gateway.
derive_route() {
  command -v "$IP_BIN" >/dev/null 2>&1 \
    || stop "no ip route reader at [$IP_BIN] — the link and the uplink are DERIVED, so with no reader there is no verdict"
  local out rc line gw dev first_gw="" first_dev="" n=0
  out="$("$IP_BIN" route 2>&1)"; rc=$?
  if [ "$rc" != 0 ]; then
    stop "ip route answered rc $rc: ${out%%$'\r'} — a routing table that cannot be read answers nothing about the uplink"
  fi
  GW=""; LINK=""
  while IFS= read -r line; do
    case "$line" in default\ via\ *) : ;; *) continue ;; esac
    gw="${line#default via }"; gw="${gw%% *}"
    dev=""
    case "$line" in *" dev "*) dev="${line##* dev }"; dev="${dev%% *}" ;; esac
    [ -n "$gw" ] || stop "a default route with no gateway in it [$line] — which address the uplink lives at is not derivable from this read"
    [ -n "$dev" ] || stop "a default route with no interface in it [$line] — which link carries the claim is not derivable from this read"
    n=$((n + 1))
    if [ "$n" = 1 ]; then first_gw="$gw"; first_dev="$dev"; continue; fi
    # An ambiguous read is not a verdict: with two defaults the choice is the first line of a GUESSING
    # ORDER, and a seat pointed at a gateway it is not using fails in a way no probe predicts.
    if [ "$gw" != "$first_gw" ] || [ "$dev" != "$first_dev" ]; then
      stop "two default routes that disagree (via $first_gw dev $first_dev, and via $gw dev $dev) — the uplink is not decidable from this read, so nothing is derived and nothing is claimed"
    fi
  done <<<"$out"
  [ "$n" -ge 1 ] || return 1
  GW="$first_gw"; LINK="$first_dev"
  return 0
}

# digest_of <var> <path> — sets <var> to the file's sha256, or rc 1 when provenance CANNOT be proved (no
# tool, unreadable file). Out-parameter for the same reason as derive_route: a substitution would swallow
# the STOP, and a digest that silently answers nothing here would read as "not ours" and delete a file
# this arm never looked at.
digest_of() {
  local __out="${1:?digest_of: needs an output variable}" _f="${2:?digest_of: needs a file}" _d="" _rc
  if command -v sha256sum >/dev/null 2>&1; then
    _d="$(sha256sum -- "$_f" 2>&1)"; _rc=$?
  elif command -v shasum >/dev/null 2>&1; then
    _d="$(shasum -a 256 -- "$_f" 2>&1)"; _rc=$?
  else
    printf 'digest: no sha256 tool answers, so the provenance of %s cannot be proved\n' "$_f" >&2
    return 1
  fi
  if [ "$_rc" != 0 ]; then
    printf 'digest: %s could not be hashed: %s\n' "$_f" "${_d%%$'\r'}" >&2
    return 1
  fi
  _d="${_d%% *}"; _d="${_d//[[:space:]]/}"
  printf -v "$__out" '%s' "$_d"
  return 0
}

# --- the render --------------------------------------------------------------------
# The render is the ONLY writer of these bytes, so there is no second copy of any of the three files in
# the tree to drift from. `--check` compares against it, `--install` writes it, and everything a unit
# needs is composed from the repo root this script was found in — which is what makes the same bytes
# correct on a reimaged box at a different path.
render_dropin() {
  { printf '%s\n' "$MARKER"
    printf '# Uplink (the Windows host resolver): default route for public names, and a\n'
    printf '# route-only claim on the plain zone so internal names keep the MagicDNS answer too.\n'
    printf '# The .ts namespace is NOT claimed here - it is routed to the MagicDNS loop per-link\n'
    printf '# (see systemd-resolved per-link state), because a public answer for a .ts name is an\n'
    printf '# NXDOMAIN that gets cached against the whole name for the zone SOA minimum (1800 s).\n'
    printf '[Resolve]\n'
    printf 'DNS=%s\n' "$GW"
    printf 'Domains=%s\n' "$GLOBAL_DOMAINS"
    printf 'DNSOverTLS=no\n'
    printf 'DNSStubListener=yes\n'; } >"$1"
}
render_service() {
  { printf '%s\n' "$MARKER"
    printf '# Re-asserts the homelab WSL seat'"'"'s per-link route for kogler.si + ts.kogler.si. This unit is\n'
    printf '# RENDERED by scripts/harness/seat-dns-route.sh - edit it there, not here. Its --install\n'
    printf '# rewrites only what this arm owns and REFUSES bytes it did not write.\n'
    printf '[Unit]\n'
    printf 'Description=Homelab WSL seat: route kogler.si + ts.kogler.si through the MagicDNS loop\n'
    printf 'Documentation=file:/etc/systemd/resolved.conf.d/%s\n' "$DROPIN_FILE"
    printf 'Wants=systemd-resolved.service\n'
    printf 'After=systemd-resolved.service\n'
    printf '\n[Service]\n'
    printf '# Type=oneshot WITHOUT RemainAfterExit, on purpose: with RemainAfterExit=yes the unit stays\n'
    printf '# active (exited) and every later start - including every timer fire - is a NO-OP that\n'
    printf '# reports success. The re-assert is the whole point, so the unit must go inactive when done.\n'
    printf 'Type=oneshot\n'
    printf '# The REPO path, never a copy under /usr/local/sbin: an unowned copy is what no converge\n'
    printf '# reaches and no drift check sees, which is the standing complaint about this family. The\n'
    printf '# link and the gateway are read from ip route at every fire, so this unit names neither.\n'
    printf 'ExecStart=/bin/bash %s --push\n' "$PLANE_SCRIPT"
    printf '\n[Install]\n'
    printf 'WantedBy=multi-user.target\n'; } >"$1"
}
render_timer() {
  { printf '%s\n' "$MARKER"
    printf '# The cadence of the homelab WSL seat'"'"'s resolver route arm. Edit it in that script.\n'
    printf '[Unit]\n'
    printf 'Description=Re-assert the Homelab DNS route (WSL restart, suspend/resume)\n'
    printf '\n[Timer]\n'
    printf 'OnBootSec=%s\n' "$ON_BOOT_SEC"
    printf 'OnUnitActiveSec=%s\n' "$ON_ACTIVE_SEC"
    printf '\n[Install]\n'
    printf 'WantedBy=timers.target\n'; } >"$1"
}
render() {   # render <name> <out>
  case "$1" in
    "$SVC")         render_service "$2" ;;
    "$TMR")         render_timer   "$2" ;;
    "$DROPIN_FILE") render_dropin  "$2" ;;
    *)              stop "render: [$1] is not a file this script owns ($SVC, $TMR, $DROPIN_FILE)" ;;
  esac
}
# Rendered to FILES, never straight to a stdout redirect: `> /dev/stdout` opens the caller's target AGAIN
# and truncates it, so the second and third renders would erase the first — a trio that renders as one
# file, and every comparison against it would read bytes nobody wrote.
render_all_to() {   # render_all_to <dir>
  render "$DROPIN_FILE" "$1/$DROPIN_FILE"
  render "$SVC"         "$1/$SVC"
  render "$TMR"         "$1/$TMR"
}
render_wants() {
  local _n
  for _n in "$DROPIN_FILE" "$SVC" "$TMR"; do render "$_n" "$SCRATCH/$_n.want"; done
}

# --- the legacy render -------------------------------------------------------------
# THE STATE THIS ARM REPLACES: the trio exactly as one box carries it today, hand-placed before this file
# existed to write it. This is a RECORD of a state, not a second source of truth — `render` above stays the
# ONLY writer, and `--install` never lands these bytes, it REPLACES them and keeps a dated `.bak-`. It
# exists because `classify_file` must answer one question before it may call a marker-less file FOREIGN:
# is this this family's own unowned copy, or someone else's file sitting at this path? Proven, not assumed,
# exactly the way the superseded `/usr/local/sbin` script is proven by its digest — equality with the bytes
# this family actually shipped. Without it the arm could not take over the one seat it was written for,
# because every artifact there predates the marker and would read as somebody else's.
#
# The values are HARD here, including ones that also live in a constant, deliberately: a historical record
# that tracked today's constants would stop matching the historical file the day a constant moved, and the
# migration would silently degrade into DRIFT(foreign) — an accusation, and a refusal. Only the gateway is
# DERIVED, because the live drop-in always named THIS boot's uplink: on a box whose gateway moved, this
# family's file still differs from the render by the address alone, and deriving it keeps that file
# provable instead of foreign.
legacy_dropin() {   # legacy_dropin <out>
  { printf '# Uplink (the Windows host resolver): default route for public names, and a\n'
    printf '# route-only claim on the plain zone so internal names keep the MagicDNS answer too.\n'
    printf '# The .ts namespace is NOT claimed here - it is routed to the MagicDNS loop per-link\n'
    printf '# (see systemd-resolved per-link state), because a public answer for a .ts name is an\n'
    printf '# NXDOMAIN that gets cached against the whole name for the zone SOA minimum (1800 s).\n'
    printf '[Resolve]\n'
    printf 'DNS=%s\n' "$GW"
    printf 'Domains=~. ~kogler.si\n'
    printf 'DNSOverTLS=no\n'
    printf 'DNSStubListener=yes\n'; } >"$1"
}
legacy_service() {  # legacy_service <out> — the one substantive difference: the act lived in /usr/local/sbin
  { printf '[Unit]\n'
    printf 'Description=Homelab WSL seat: route kogler.si + ts.kogler.si through the MagicDNS loop\n'
    printf 'Documentation=file:/etc/systemd/resolved.conf.d/homelab-dns.conf\n'
    printf 'Wants=systemd-resolved.service\n'
    printf 'After=systemd-resolved.service\n'
    printf '\n[Service]\n'
    printf '# Type=oneshot WITHOUT RemainAfterExit, on purpose: with RemainAfterExit=yes the unit stays\n'
    printf '# active (exited) and every later start - including every timer fire - is a NO-OP that\n'
    printf '# reports success. The re-assert is the whole point, so the unit must go inactive when done.\n'
    printf 'Type=oneshot\n'
    printf 'ExecStart=/usr/local/sbin/homelab-dns-route.sh\n'
    printf '\n[Install]\n'
    printf 'WantedBy=multi-user.target\n'; } >"$1"
}
legacy_timer() {    # legacy_timer <out>
  { printf '[Unit]\n'
    printf 'Description=Re-assert the Homelab DNS route (WSL restart, suspend/resume)\n'
    printf '\n[Timer]\n'
    printf 'OnBootSec=10s\n'
    printf 'OnUnitActiveSec=120s\n'
    printf '\n[Install]\n'
    printf 'WantedBy=timers.target\n'; } >"$1"
}
legacy_render() {   # legacy_render <name> <out>
  case "$1" in
    "$SVC")         legacy_service "$2" ;;
    "$TMR")         legacy_timer   "$2" ;;
    "$DROPIN_FILE") legacy_dropin  "$2" ;;
    *)              stop "legacy_render: [$1] is not a file this family hand-placed ($SVC, $TMR, $DROPIN_FILE)" ;;
  esac
}
legacy_render_wants() {
  local _n
  for _n in "$DROPIN_FILE" "$SVC" "$TMR"; do legacy_render "$_n" "$SCRATCH/$_n.legacy"; done
}
# path_of <var> <name> — where the artifact lives. Out-parameter, for the STOP rule above.
path_of() {
  local __out="${1:?path_of: needs an output variable}" _n="${2:?path_of: needs an artifact name}" _p
  case "$_n" in
    "$SVC") _p="$UNIT_DIR/$SVC" ;;
    "$TMR") _p="$UNIT_DIR/$TMR" ;;
    "$DROPIN_FILE") _p="$DROPIN_DIR/$DROPIN_FILE" ;;
    *) stop "path_of: [$_n] is not a file this script owns" ;;
  esac
  printf -v "$__out" '%s' "$_p"
}

# --- the verdict -------------------------------------------------------------------
# assess fills the per-artifact states and the overall STATE. Every finding is PRINTED; the overall word
# is the STRONGEST one, because the report has to name the finding that explains a broken arm best, and an
# exit code cannot tell "absent" from "wrong" — nor either of those from "present but never enabled".
rank_state() {   # rank_state <state> — keeps the strongest finding of the sweep
  local r
  case "$1" in
    OK)               r=0 ;;
    'DRIFT(legacy)')  r=1 ;;
    DRIFT)            r=2 ;;
    'DRIFT(drop-in)') r=3 ;;
    'DRIFT(foreign)') r=4 ;;
    MISSING)          r=5 ;;
    *)                stop "rank_state: unknown state [$1]" ;;
  esac
  [ "$r" -le "$RANK" ] && return 0
  RANK="$r"; STATE="$1"
}

# classify_file <installed> <want> <label> <legacy> — the four ways a path can answer. The ORDER is the
# rule, and the fourth branch is the one that has to be last:
#   equal to the render                → OK
#   carries the marker, bytes moved    → DRIFT            (this script wrote it, someone edited it)
#   equal to the legacy render         → DRIFT(legacy)    (this family hand-placed it, before the owner)
#   anything else                      → DRIFT(foreign)   (not ours: --install writes NOTHING)
# Proven, never inferred from silence: "no marker" is not evidence of foreignness, it is the state every
# file on the seat was in before this file existed, and an arm that accused those bytes could never land on
# the one box it was written for. Equality with the legacy render is the proof, the same kind of proof the
# superseded sbin digest is — and one edited byte defeats it, so the door stays shut for a stranger.
classify_file() {
  A_NAMES+=("$3")
  if [ ! -e "$1" ]; then
    A_STATES+=("MISSING"); note "$3: MISSING — not installed ($1 is not there)"; rank_state MISSING
    return 0
  fi
  [ -r "$1" ] || stop "cannot read $1 — a verdict about a file nobody can read is not a verdict"
  if cmp -s "$1" "$2"; then
    A_STATES+=("OK"); return 0
  fi
  if grep -qF "$MARKER" "$1"; then
    A_STATES+=("DRIFT")
    note "$3: DRIFT — not what this script renders (left: the render, right: the file):"
    diff "$2" "$1" | sed -e 's/^/      /' -e '13q'
    rank_state DRIFT
    return 0
  fi
  if cmp -s "$1" "$4"; then
    A_STATES+=("DRIFT(legacy)")
    note "$3: DRIFT(legacy) — this family's unowned copy: the bytes this arm replaces, written by hand"
    note "  before this script existed to write them. --install takes it over (dated .bak beside it);"
    note "  the difference is only ownership and the ExecStart path (left: the render, right: the file):"
    diff "$2" "$1" | sed -e 's/^/      /' -e '13q'
    rank_state 'DRIFT(legacy)'
    return 0
  fi
  A_STATES+=("DRIFT(foreign)")
  note "$3: DRIFT(foreign) — a file at this path that carries no '$MARKER' line and is not the copy this"
  note "  family hand-placed either: neither the render nor the record of what this arm replaces"
  rank_state 'DRIFT(foreign)'
  return 0
}

# classify_legacy — the superseded copy. Provenance is PROVED two ways and never guessed: the digest of
# the script this family shipped, or this arm's own marker on a copy somebody re-typed by hand. Anything
# else at that path is someone else's file, and the only safe act on it is NOTHING.
classify_legacy() {
  A_NAMES+=("superseded sbin copy")
  if [ ! -e "$LEGACY" ]; then A_STATES+=("OK"); return 0; fi
  [ -r "$LEGACY" ] || stop "cannot read $LEGACY — provenance cannot be proved for a copy this arm cannot read, and a guess here is an uninstall"
  local d
  if digest_of d "$LEGACY"; then
    if [ "$d" = "$LEGACY_DIGEST" ]; then
      A_STATES+=("DRIFT(legacy)")
      note "superseded sbin copy: DRIFT(legacy) — digest ${d:0:12}… is the script this arm superseded, and the"
      note "  act now lives at $PLANE_SCRIPT --push; a second copy of an act is a second source"
      rank_state 'DRIFT(legacy)'; return 0
    fi
  else
    stop "cannot prove the provenance of $LEGACY — neither hashed nor matched, and an uninstall that guesses is an act on someone else's file"
  fi
  if grep -qF "$MARKER" "$LEGACY"; then
    A_STATES+=("DRIFT(legacy)")
    note "superseded sbin copy: DRIFT(legacy) — it carries this arm's marker, so this family wrote it; the act now lives in the repo"
    rank_state 'DRIFT(legacy)'; return 0
  fi
  A_STATES+=("DRIFT(foreign)")
  note "superseded sbin copy: DRIFT(foreign) — a file at the superseded path that is neither its digest nor this arm's marker"
  rank_state 'DRIFT(foreign)'
  return 0
}

# legacy_is_ours — the install-time form of the same rule, rc-only: 0 ours (or nothing there), 1 foreign,
# 2 provenance undecidable. No verdict, no note: this one answers the act, not the reader.
legacy_is_ours() {
  [ -e "$LEGACY" ] || return 0
  [ -r "$LEGACY" ] || return 2
  local d
  if digest_of d "$LEGACY"; then
    [ "$d" = "$LEGACY_DIGEST" ] && return 0
  else
    return 2
  fi
  grep -qF "$MARKER" "$LEGACY" && return 0
  return 1
}

# timer_enabled <var> — the enable state, read from systemd rather than inferred from a symlink in a
# directory this arm does not own. `is-enabled` exits non-zero for `disabled`, so the WORD is the answer
# and the rc is not; that is why the rc is dropped and the word is what the verdict reads.
timer_enabled() {
  local __out="$1" _o _rc
  _o="$("$SYSTEMCTL" is-enabled "$TMR" 2>&1)"; _rc=$?
  _o="${_o%%$'\r'}"; _o="${_o//[[:space:]]/}"
  printf -v "$__out" '%s' "$_o"
  return "$_rc"
}

require_inputs() {
  [ -d "$UNIT_DIR" ]   || stop "no unit directory at $UNIT_DIR — nothing can be read, so no verdict is owed"
  [ -d "$DROPIN_DIR" ] || stop "no resolved drop-in directory at $DROPIN_DIR — the uplink file cannot be read, so no verdict is owed"
  [ -r "$PLANE_SCRIPT" ] || stop "the script the ExecStart names is not readable at $PLANE_SCRIPT — a unit that fires into a missing file is silence behind an enabled timer, so nothing here may read as in sync"
}

assess() {
  st_guard
  require_inputs
  command -v "$SYSTEMCTL" >/dev/null 2>&1 \
    || stop "no systemctl answers at [$SYSTEMCTL] — whether the timer is ENABLED cannot be read, and a green that never read the arm's trigger is the mute-gate class"
  derive_route || stop "no single default route to derive a link and an uplink from — the drop-in's DNS= is that gateway, so with nothing to derive there is no render to compare and no verdict to print"
  render_wants
  legacy_render_wants
  local n inst _f inert enabled
  STATE="OK"; REASON=""; RANK=0; A_NAMES=(); A_STATES=()
  for n in "$DROPIN_FILE" "$SVC" "$TMR"; do
    path_of inst "$n"
    classify_file "$inst" "$SCRATCH/$n.want" "$n" "$SCRATCH/$n.legacy"
  done
  # A drop-in merges OVER the unit, so the RemainAfterExit trap can come back with no change to the unit
  # file at all. Content that does not touch that key is an operator override: printed, and no verdict —
  # an exclusion wider than the trap is just blindness with a NOTE attached.
  for n in "$SVC" "$TMR"; do
    [ -d "$UNIT_DIR/$n.d" ] || continue
    if [ -n "$(grep -rlE '^[[:space:]]*RemainAfterExit' "$UNIT_DIR/$n.d" 2>/dev/null)" ]; then
      A_NAMES+=("$n.d"); A_STATES+=("DRIFT(drop-in)")
      note "$n.d: DRIFT(drop-in) — a drop-in sets RemainAfterExit, which makes every timer fire a no-op that reports success"
      rank_state 'DRIFT(drop-in)'
    else
      note "NOTE: $n has drop-ins in $UNIT_DIR/$n.d that this arm does not own — they merge over the unit, so read them before believing a fire"
    fi
  done
  # Inert by the loader's own rule: systemd-resolved reads only `*.conf` from this directory, so the two
  # dated leftovers this seat carries are history, not state. Named, and the verdict is left alone.
  inert=""
  for _f in "$DROPIN_DIR"/*; do
    [ -f "$_f" ] || continue
    case "$_f" in *".conf") continue ;; esac
    inert="$inert ${_f##*/}"
  done
  if [ -n "$inert" ]; then
    note "NOTE: $DROPIN_DIR carries non-.conf leftover(s):$inert — inert: systemd-resolved reads only *.conf, so they change no verdict"
  fi
  # The trigger, read from systemd. A pair that is written and never enabled is an arm that never fires,
  # and no file is out of place to blame for it — so this half belongs in the verdict, not in a NOTE. The
  # one pass that skips it is --install's post-write look, which has not enabled anything yet: the enable
  # leg reads the same state back one step later and fails the install on a non-`enabled` answer.
  if [ "$WITH_TRIGGER" = 1 ]; then
    timer_enabled enabled
    if [ "$enabled" = enabled ]; then
      A_NAMES+=("timer enabled"); A_STATES+=("OK")
    else
      A_NAMES+=("timer enabled"); A_STATES+=("DRIFT")
      note "timer enabled: DRIFT — systemctl is-enabled $TMR answers [$enabled], so the pair is written but nothing will ever fire it"
      rank_state DRIFT
    fi
  else
    note "trigger: not read in this pass — the enable leg below runs enable --now and reads is-enabled back, and a non-enabled answer fails that install"
  fi
  classify_legacy
  if [ "$STATE" = "OK" ]; then
    REASON="in sync"
  else
    local i why=""
    for i in "${!A_NAMES[@]}"; do
      [ "${A_STATES[i]}" = "$STATE" ] || continue
      why="$why${why:+, }${A_NAMES[i]}"
    done
    REASON="in this state: $why"
  fi
  return 0
}

say_verdict() {
  printf 'read: units=%s drop-in=%s link=%s uplink=%s\n' "$UNIT_DIR" "$DROPIN_DIR" "${LINK:-?}" "${GW:-?}"
  # The address is an ARGUMENT here, never part of the format string: the gateway is the one value this arm
  # takes from the box, and a `%` inside a printf FORMAT is a conversion — which would misreport the read
  # rather than fail it, the worst kind of wrong output.
  printf 'exec: %s\n' "/bin/bash $PLANE_SCRIPT --push"
  printf '%s' "$STATE"
  [ -n "$REASON" ] && printf ': %s' "$REASON"
  printf '\n'
}

do_check() {
  say_verdict
  note "the per-link CLAIM is an act, not a file: this read did not prove it. What proves it is the read-back --push prints, and that is also what the timer runs."
  case "$STATE" in
    MISSING) return 1 ;;
    DRIFT|'DRIFT(foreign)'|'DRIFT(drop-in)'|'DRIFT(legacy)')
             [ "$STRICT" = 1 ] && return 1; return 0 ;;
    *)       return 0 ;;
  esac
}

# readback_norm <raw> — the answer of `resolvectl dns|domain <link>` in ONE comparable spelling. Measured
# on the seat, systemd 257 answers `Link 2 (eth0): 100.100.100.100` and answers a link with nothing claimed
# as the bare `Link 2 (eth0):` — a colon and no value. An older release prints the bare value with no
# prefix at all, so the prefix is stripped WHEN PRESENT rather than assumed, and the remainder becomes a
# sorted token list because the order resolved prints a list in is not part of the claim. Without this the
# comparison would run against `Link2(eth0):100.100.100.100` and call a correct seat drifted on every fire
# — a parser that only understands the tidy form of a tool is a parser that fails on the real one.
readback_norm() {
  printf '%s' "${1-}" | tr -d '\r' \
    | sed -e 's/^[Ll]ink[[:space:]][0-9][0-9]*[[:space:]]*([^)]*)[[:space:]]*:[[:space:]]*//' \
    | tr ' \t' '\n\n' | sed -e '/^$/d' | LC_ALL=C sort | tr '\n' ' ' | sed -e 's/ $//'
}

# --- the act -----------------------------------------------------------------------
# push — the only place the per-link claim is made, and the only place it is PROVEN. `resolvectl` exits 0
# even when resolved refuses the call, so the READ-BACK is the verdict and the write's exit code is a
# NOTE. Everything the run decided goes to the journal under its own tag, because a timer fire has no
# terminal: without the journal line, a fire that accomplished nothing and a fire that fixed the leak look
# identical from the outside.
do_push() {
  st_guard
  # The tool first, the derivation second: with nothing to act WITH, deriving a link and naming it in a STOP
  # would describe a fact about the box that no act can ever use.
  command -v "$RESOLVEDCTL" >/dev/null 2>&1 \
    || stop "no resolvectl at [$RESOLVEDCTL] — the act has nothing to act with, so it prints no verdict"
  derive_route || stop "no single default route to derive a link and an uplink from — which link carries the claim is not guessable, so nothing was claimed"
  local dns_rc dom_rc rb_rc got dns_got="" dom_got="" claim_ok=1 uplink_state="" out rc
  # The domain set the read-back must match, in the same spelling readback_norm produces (sorted: the order
  # resolved prints a list in is not part of the claim).
  local want
  want="$(readback_norm "${ROUTE_DOMAINS[*]}")"
  { printf 'push: link=%s gateway=%s (both derived from ip route at run time)\n' "$LINK" "$GW"
    out="$("$RESOLVEDCTL" dns "$LINK" "$MAGICDNS" 2>&1)"; dns_rc=$?
    printf -- '-- dns -- rc=%s %s\n' "$dns_rc" "${out%%$'\r'}"
    out="$("$RESOLVEDCTL" domain "$LINK" "${ROUTE_DOMAINS[@]}" 2>&1)"; dom_rc=$?
    printf -- '-- domain -- rc=%s %s\n' "$dom_rc" "${out%%$'\r'}"
    # The read-back IS the verdict. rc 0 says the call was accepted; only resolved answers what is in
    # force, and it is entitled to refuse without saying so in its exit code.
    got="$("$RESOLVEDCTL" dns "$LINK" 2>&1)"; rb_rc=$?
    if [ "$rb_rc" != 0 ]; then
      printf 'READBACK: resolvectl dns %s answered rc %s — resolved was not ASKABLE, so the claim is NOT proven\n' "$LINK" "$rb_rc"
      claim_ok=0
    else
      dns_got="$(readback_norm "$got")"
      printf -- '-- readback dns -- [%s]\n' "$dns_got"
      if [ "$dns_got" != "$MAGICDNS" ]; then
        printf 'DRIFT(per-link): resolvectl dns %s answers [%s], want [%s] — rc said yes, resolved says otherwise\n' \
          "$LINK" "${dns_got:-nothing}" "$MAGICDNS"
        claim_ok=0
      fi
    fi
    got="$("$RESOLVEDCTL" domain "$LINK" 2>&1)"; rb_rc=$?
    if [ "$rb_rc" != 0 ]; then
      printf 'READBACK: resolvectl domain %s answered rc %s — resolved was not ASKABLE, so the claim is NOT proven\n' "$LINK" "$rb_rc"
      claim_ok=0
    else
      dom_got="$(readback_norm "$got")"
      printf -- '-- readback domain -- [%s]\n' "$dom_got"
      if [ "$dom_got" != "$want" ]; then
        printf 'DRIFT(per-link): resolvectl domain %s answers [%s], want [%s] — the claim REPLACES the list, so both domains belong in one call\n' \
          "$LINK" "${dom_got:-nothing}" "$want"
        claim_ok=0
      fi
    fi
    # rc 0 means ACCEPTED, not OBEYED. It is also the only evidence an operator gets when the refusal is
    # for privileges, so the sudo line prints when both halves say so: the write failed AND the claim did
    # not land. A failed write whose claim is nevertheless in force is not a failure — it is a fire that
    # had nothing to change, and printing sudo there would teach a reader to ignore the line.
    if { [ "$dns_rc" != 0 ] || [ "$dom_rc" != 0 ]; } && [ "$claim_ok" != 1 ]; then
      printf 'REFUSAL(per-link): the write rc was dns=%s domain=%s and the claim did not land — per-link state is not writable by a plain user.\n' "$dns_rc" "$dom_rc"
      printf '  → sudo bash %s --push\n' "$SELF"
    fi
    # The two halves of this family land together, so every timer fire reports the whole state. Naming
    # --install here is a step owned by THIS arm, not one handed to a person to remember.
    if [ -f "$DROPIN_DIR/$DROPIN_FILE" ]; then
      uplink_state="$(sed -n 's/^DNS=\(.*\)$/\1/p' "$DROPIN_DIR/$DROPIN_FILE" 2>/dev/null | head -1)"
      uplink_state="${uplink_state//[[:space:]]/}"
      if [ "$uplink_state" != "$GW" ]; then
        printf 'NOTE: the uplink half is stale: %s carries DNS=[%s] and this boot'"'"'s gateway is [%s]. Fix: sudo bash %s --install\n' \
          "$DROPIN_DIR/$DROPIN_FILE" "${uplink_state:-none}" "$GW" "$SELF"
      fi
    else
      printf 'NOTE: the uplink half is absent: %s is not there, so global names take whatever the link was handed. Fix: sudo bash %s --install\n' \
        "$DROPIN_DIR/$DROPIN_FILE" "$SELF"
    fi
    # A cached NXDOMAIN outlives the route fix, so the flush is part of the act and not a nicety.
    "$RESOLVEDCTL" flush-caches >/dev/null 2>&1 \
      || printf 'NOTE: resolvectl flush-caches did not run — a cached NXDOMAIN outlives the route fix, so flush by hand before testing\n'
    if [ "$claim_ok" = 1 ]; then
      printf 'OK: the claim is in force on %s — %s + %s\n' "$LINK" "$MAGICDNS" "$want"
      rc=0
    else
      printf 'NOT-IN-SYNC: the claim this run asked for is NOT what resolved says is in force on %s\n' "$LINK"
      rc=1
    fi
    printf 'rc=%s\n' "$rc"
  } >"$SCRATCH/push.log" 2>&1
  # Out to the terminal AND into the journal: the same bytes, so the witness a timer fire leaves is the
  # witness the operator read. `logger` reads stdin and takes one journal entry per line.
  cat "$SCRATCH/push.log"
  if command -v "$LOGGER_BIN" >/dev/null 2>&1; then
    "$LOGGER_BIN" -t homelab-dns-route <"$SCRATCH/push.log" 2>/dev/null \
      || note "NOTE: logger did not take the journal line — the exchange printed above is then the only copy of it"
  else
    note "NOTE: no logger at [$LOGGER_BIN] — the exchange is on stdout only, so a timer fire leaves no witness"
  fi
  return "$rc"
}

# enable_leg — the half that makes the files an ARM and not three files. A unit systemd has never reloaded
# is not known to it, and a timer that is never enabled never fires, so an install that stops at the write
# is the "NOTE asking the operator for a step owned by nobody" shape this repo has been taught about. It
# prints its OWN read-back, because exit code 0 says the call ran, not that anything is scheduled.
enable_leg() {
  local out rc enabled active
  out="$("$SYSTEMCTL" daemon-reload 2>&1)"; rc=$?
  if [ "$rc" != 0 ]; then
    printf 'FAILED(reload): systemctl daemon-reload rc %s: %s\n' "$rc" "${out%%$'\r'}"
    return 1
  fi
  out="$("$SYSTEMCTL" enable --now "$TMR" 2>&1)"; rc=$?
  if [ "$rc" != 0 ]; then
    printf 'FAILED(enable): systemctl enable --now %s rc %s: %s\n' "$TMR" "$rc" "${out%%$'\r'}"
    return 1
  fi
  timer_enabled enabled
  active="$("$SYSTEMCTL" is-active "$TMR" 2>&1)"; active="${active%%$'\r'}"; active="${active//[[:space:]]/}"
  printf 'read-back: is-enabled=%s is-active=%s\n' "$enabled" "$active"
  # rc 0 from `enable --now` says the call ran. THIS is the verdict on the arm: an enable that systemd
  # accepted and did not act on is the same silence as no enable at all, and the files are already in
  # place by the time this line runs, so nothing else in the run would notice.
  if [ "$enabled" != enabled ]; then
    printf 'NOT-ARMED: systemctl accepted `enable --now %s` and is-enabled still answers [%s] — the files are in place, nothing will fire them.\n' "$TMR" "$enabled"
    printf '  → check for a masked or static unit: systemctl status %s\n' "$TMR"
    return 1
  fi
  return 0
}

# write_file <name> — render → temp BESIDE the target → rename in. Nothing but an `mv` is atomic to a
# reader, and `daemon-reload` and resolved both READ these files: a half-written unit is a parse failure,
# not a warning. Returns 0 wrote-or-nothing-to-do, 1 failed; sets WROTE=1 when bytes actually changed.
WROTE=0
write_file() {
  local n="$1" inst want tmp ts
  path_of inst "$n"; want="$SCRATCH/$n.want"
  cmp -s "$inst" "$want" 2>/dev/null && return 0
  if [ -e "$inst" ]; then
    ts="$(date -u +%Y%m%d-%H%M%S)"
    cp -p "$inst" "$inst.bak-$ts" && note "backup: $inst.bak-$ts"
  fi
  tmp="$(mktemp "${inst}.homelab.XXXXXX")" || { err "cannot create a temp file beside $inst"; return 1; }
  if ! cat "$want" >"$tmp" || ! chmod 644 "$tmp" || ! mv -f "$tmp" "$inst"; then
    rm -f "$tmp"
    printf 'FAILED: %s could not be written\n' "$inst"
    return 1
  fi
  WROTE=1
  return 0
}

do_install() {
  local n inst want rc d dirs="" wrote_ts
  st_guard
  # A LINKED WORKTREE IS NOT A HOME FOR THIS ARM. The ExecStart names $REPO by ABSOLUTE path, and a lane
  # worktree is `git worktree remove`-d the day its lane closes — the timer would then fire every 120 s
  # into a directory that is gone, which is the same silence as no timer at all. `.git` being a FILE (not
  # a directory) is how a linked worktree says so. --render and --check stay read-only and still run from
  # anywhere, and a pair installed from a worktree reads as DRIFT on the next --check from the primary
  # tree, so the mistake is visible rather than durable.
  if [ -f "$REPO/.git" ]; then
    printf 'REFUSAL(worktree): %s is a LINKED worktree — the path its ExecStart names is deleted when that lane closes.\n' "$REPO"
    printf '  → install from the PRIMARY checkout: cd <primary clone> && sudo bash scripts/harness/seat-dns-route.sh --install\n'
    return 1
  fi
  # The trigger is checked BEFORE anything is written: three files with no timer behind them are half an
  # installed arm, which is the one state this arm has promised never to leave. (In --check the same
  # missing systemctl is exit 2 — a read that could not read its trigger owes no verdict; here the run is
  # an act, and an act that cannot be completed says INCOMPLETE and touches nothing.)
  if ! command -v "$SYSTEMCTL" >/dev/null 2>&1; then
    printf 'INCOMPLETE(systemctl): no systemctl at [%s], so nothing here can be reloaded or enabled and NOTHING WOULD FIRE. Nothing was written.\n' "$SYSTEMCTL"
    printf '  → on a systemd host: sudo systemctl daemon-reload && sudo systemctl enable --now %s\n' "$TMR"
    return 1
  fi
  require_inputs
  derive_route || stop "no single default route to derive the uplink from — the drop-in's DNS= is that address, so an install with nothing to derive would write a file naming a guessed gateway"
  render_wants
  legacy_render_wants
  # Provenance BEFORE anything is written, the superseded copy included: writing the files this arm does own
  # and then refusing the rest would leave half an installed arm, which is worse than no arm at all. Three
  # answers are allowed to reach the write — the render (nothing to do), this script's own bytes with a
  # marker (a repair), and this family's hand-placed legacy form (a TAKEOVER, the migration this file exists
  # to land, and `write_file` keeps a dated `.bak-` beside it exactly as it does for a repair). Anything else
  # is a stranger at this path and the whole run stops with nothing written.
  for n in "$DROPIN_FILE" "$SVC" "$TMR"; do
    path_of inst "$n"; want="$SCRATCH/$n.want"
    [ -e "$inst" ] || continue
    cmp -s "$inst" "$want" && continue
    grep -qF "$MARKER" "$inst" && continue
    if cmp -s "$inst" "$SCRATCH/$n.legacy"; then
      printf 'takeover: %s — this family'"'"'s unowned copy, the bytes this arm replaces. A dated .bak is kept\n'
      printf '  beside it, then the render lands; nothing else about the arm changes.\n'
      continue
    fi
    printf 'REFUSAL(foreign): %s carries no marker this script writes and is not the copy this family hand-placed.\n' "$inst"
    printf '  → it is someone else'"'"'s file under this arm'"'"'s name. Nothing at all was written: rename or remove\n'
    printf '    it (keep a dated .bak), then re-run: sudo bash %s --install\n' "$SELF"
    return 1
  done
  legacy_is_ours; rc=$?
  case "$rc" in
    0) : ;;
    1) printf 'REFUSAL(foreign): %s is not this family'"'"'s superseded copy — neither its digest nor this arm'"'"'s marker.\n' "$LEGACY"
       printf '  → nothing at all was written. Read it, rename it (keep a dated .bak), then re-run: sudo bash %s --install\n' "$SELF"
       return 1 ;;
    2) printf 'REFUSAL(unknown-provenance): %s exists and cannot be hashed, so this arm cannot prove the copy is its own to remove.\n' "$LEGACY"
       printf '  → nothing at all was written. A removal that guesses is an uninstall of a file nobody looked at: sudo bash %s --install\n' "$SELF"
       return 1 ;;
    *) stop "legacy_is_ours answered [$rc] — a provenance probe that does not answer ours/foreign/unknown is not a probe" ;;
  esac
  # Unprivileged: name the command, change nothing. Checked once per DIRECTORY the arm writes into, plus
  # the directory the superseded copy has to be removed from — an install that half-lands because the
  # third directory was not writable is the same half arm under a different name.
  for n in "$DROPIN_FILE" "$SVC" "$TMR"; do
    path_of inst "$n"
    d="${inst%/*}"
    case " $dirs " in *" $d "*) : ;; *) dirs="$dirs $d" ;; esac
  done
  if [ -e "$LEGACY" ]; then
    d="${LEGACY%/*}"
    case " $dirs " in *" $d "*) : ;; *) dirs="$dirs $d" ;; esac
  fi
  for d in $dirs; do
    if [ ! -w "$d" ]; then
      printf 'REFUSAL(not-writable): %s is not writable by this user — unit files, a resolved drop-in and an enable are root acts.\n' "$d"
      printf '  → sudo bash %s --install\n' "$SELF"
      return 1
    fi
  done
  WROTE=0
  for n in "$DROPIN_FILE" "$SVC" "$TMR"; do
    write_file "$n" || return 1
  done
  if [ -e "$LEGACY" ] && legacy_is_ours; then
    wrote_ts="$(date -u +%Y%m%d-%H%M%S)"
    # Moved aside under a dated name rather than unlinked: this is the one file this arm DELETES a path
    # for, and the repo rule for a replaced file is a dated copy beside it. It is inert for the same
    # reason the resolved.conf.d leftovers are — nothing references that name — and the legacy probe
    # reads the exact path only, so the .bak never re-triggers a verdict.
    if mv -f "$LEGACY" "$LEGACY.bak-$wrote_ts"; then
      printf 'retired: %s — provably this family'"'"'s superseded copy, moved aside to %s.bak-%s (inert: nothing names that path). The act is the repo path now.\n' \
        "$LEGACY" "$LEGACY" "$wrote_ts"
      WROTE=1
    else
      printf 'FAILED: %s could not be moved aside, so nothing was enabled\n' "$LEGACY"
      return 1
    fi
  fi
  if [ "$WROTE" = 0 ]; then
    echo "already in sync: every file this arm owns is the render — nothing written"
  else
    echo "repaired: the files this arm owns are now the render"
  fi
  WITH_TRIGGER=0
  assess
  WITH_TRIGGER=1
  say_verdict
  if [ "$STATE" != "OK" ]; then
    # Nothing was written and the finding stands, or something was written and did not land. The first case
    # is a drop-in that sets the trap: a file under <unit>.d/ is not this arm's to rewrite, so it says so
    # and stops BEFORE enabling rather than enabling an arm the verdict just called neutered.
    if [ "$WROTE" = 0 ]; then
      printf 'NOT-FIXED: nothing was written and the finding above stands — a drop-in under <unit>.d/ belongs to whoever wrote it, so edit or remove it and re-run.\n'
    else
      printf 'FAILED: the files were written but do not read back in sync\n'
    fi
    return 1
  fi
  enable_leg
  rc=$?
  [ "$rc" = 0 ] && note "the per-link claim is the act itself, run by the timer's ExecStart: sudo bash $SELF --push"
  return "$rc"
}

do_render() {
  local n
  scratch
  derive_route || stop "no single default route to derive the uplink from — the drop-in's DNS= is that address, so this render cannot be printed honestly"
  if [ -n "$RENDER_ONLY" ]; then
    render "$RENDER_ONLY" "$SCRATCH/$RENDER_ONLY" && cat "$SCRATCH/$RENDER_ONLY"
    return $?
  fi
  render_all_to "$SCRATCH" || return $?
  for n in "$SVC" "$TMR" "$DROPIN_FILE"; do
    printf '# ===== %s =====\n' "$n"
    cat "$SCRATCH/$n"
  done
}

# --- self-test ---------------------------------------------------------------------
# Fixture DIRECTORIES for the three files, fixture PATHS for the superseded copy and for every system
# binary this arm touches, and a resolvectl stub that keeps the per-link state in a FILE. The stub is the
# point: `resolvectl` exits 0 when resolved refuses, so proving that this script believes the read-back
# and not the exit code needs a resolver that LIES with rc 0. Both halves of every rule (CONVENTIONS §6):
# every STOP with the unpoisoned control that reads green again, every state with its opposite state, and
# no arm allowed to pass on a file the run was supposed to leave alone.
selftest() {
  local fails=0 pass=0 root dir ddir legf state want_render rc0
  local -a envpre
  scratch; root="$SCRATCH"; dir="$root/units"; ddir="$root/resolved"; legf="$root/sbin/homelab-dns-route.sh"
  state="$root/state"
  mkdir -p "$root/repo/scripts/harness" "$root/sbin" "$root/stubs" "$dir" "$ddir" "$state"
  # The ExecStart target. It is NOT what the arms run — they run the real SELF from the real tree — it is
  # what the render must NAME, and arm 13 reddens when it is not there.
  printf '#!/usr/bin/env bash\n# fixture stand-in for this script, at the repo path the ExecStart names\n' \
    >"$root/repo/scripts/harness/$(basename "$SELF")"
  chmod 755 "$root/sbin"      # so a NON-root self-test can make it unwritable, and undo that

  # `ip`: prints the routing table the arm under test is told to believe. Every route arm rewrites it.
  set_route() { printf '%s\n' "$1" >"$root/ip-route"; }
  # The route this fixture's seat is assumed to have: the WSL NAT gateway the live drop-in names today.
  base_route() { set_route 'default via 172.17.0.1 dev eth0 proto kernel
172.17.0.0/20 dev eth0 proto kernel scope link src 172.17.7.3'; }
  base_route
  { printf '#!/bin/sh\n'
    printf 'cat "%s/ip-route" 2>/dev/null\n' "$root"
    printf 'exit 0\n'; } >"$root/stubs/ip"
  # `systemctl`: records every argv, and answers is-enabled/is-active from a state file — so "the timer got
  # enabled" is an ARM (provable on a machine with no systemd), an arm can UN-enable it, and `enable` moves
  # the state the way the real symlink would.
  { printf '#!/bin/sh\n'
    printf 'printf "%%s\\n" "$*" >> "%s/systemctl.log"\n' "$root"
    printf 'case "$1" in\n'
    printf '  enable)     : >"%s/state/enabled"; exit 0 ;;\n' "$root"
    printf '  is-enabled) if [ -e "%s/state/enabled" ]; then echo enabled; else echo disabled; fi; exit 0 ;;\n' "$root"
    printf '  is-active)  if [ -e "%s/state/enabled" ]; then echo active;  else echo inactive; fi; exit 0 ;;\n' "$root"
    printf 'esac\nexit 0\n'; } >"$root/stubs/systemctl"
  # `resolvectl`: the per-link state lives in files, so a write is remembered by the read-back — which is
  # the whole point. The `state/refuse` file models the defect this arm exists for: the call is ACCEPTED,
  # rc 0, nothing printed, and resolved obeys NONE of it. Green exit code, no state, and only the
  # read-back knows. Argv is `dns <link> [value…]`: no value is the read, a value is the claim. The READ
  # prints the way the seat's systemd 257 prints — `Link 2 (eth0): <values>`, and the bare `Link 2 (eth0):`
  # when nothing is claimed — because a stub that printed only the tidy value would let a parser that
  # cannot read the real answer pass here and fail on the seat.
  { printf '#!/bin/sh\n'
    printf 'printf "%%s\\n" "$*" >> "%s/resolvectl.log"\n' "$root"
    printf 'if [ -e "%s/state/refuse" ]; then exit 0; fi\n' "$root"
    printf 'cmd="$1"; shift\n'
    printf 'case "$cmd" in dns|domain) : ;; *) exit 0 ;; esac\n'
    printf 'link="$1"; shift\n'
    printf 'if [ "$#" -eq 0 ]; then\n'
    printf '  printf "Link 2 (%%s):" "$link"\n'
    printf '  [ -f "%s/state/rb-$cmd" ] && printf " %%s" "$(cat "%s/state/rb-$cmd")"\n' "$root" "$root"
    printf '  printf "\\n"; exit 0\nfi\n'
    printf 'printf "%%s" "$*" >"%s/state/rb-$cmd"; exit 0\n' "$root"; } >"$root/stubs/resolvectl"
  # `logger`: the journal line a timer fire leaves behind, captured so "it logged the verdict" is an arm
  # rather than a hope — `logger -t <tag>` takes the entry on stdin, so the stub keeps argv and body.
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/logger.argv"\ncat >>"%s/journal.log"\n' "$root" "$root" \
    >"$root/stubs/logger"
  chmod +x "$root/stubs"/*

  # The hook set EVERY arm runs with: the real script from this tree, every system path pointed at a
  # fixture. Composed in ONE place so no arm can forget one — and the ST guard is the belt behind it.
  set_envpre() {
    envpre=( REPO="$root/repo" SEAT_DNS_ROUTE_ST=1
             SEAT_DNS_ROUTE_UNIT_DIR="$dir" SEAT_DNS_ROUTE_DROPIN_DIR="$ddir"
             SEAT_DNS_ROUTE_LEGACY="$legf"
             SEAT_DNS_ROUTE_IP="$root/stubs/ip"
             SEAT_DNS_ROUTE_SYSTEMCTL="$root/stubs/systemctl"
             SEAT_DNS_ROUTE_RESOLVEDCTL="$root/stubs/resolvectl"
             SEAT_DNS_ROUTE_LOGGER="$root/stubs/logger" )
  }
  report() {   # report <label> <want> <got>
    if [ "$3" = "$2" ]; then pass=$((pass + 1)); printf 'ok   %s (rc %s)\n' "$1" "$3"
    else fails=$((fails + 1)); printf 'FAIL %s: rc %s, want %s\n' "$1" "$3" "$2"
      sed 's/^/     | /' "$root/out" | head -10; fi
  }
  run() {   # run <label> <want-rc> <args…>
    local label="$1" want="$2"; shift 2
    local rc=0; set_envpre
    env "${envpre[@]}" bash "$SELF" "$@" >"$root/out" 2>&1 || rc=$?
    report "$label" "$want" "$rc"
  }
  # The same run with ONE hook pointed at a path that does not resolve — the dead-leg arms. A later env
  # assignment wins, which is exactly what makes this the way to kill one leg.
  run_hook() {   # run_hook <label> <want-rc> <HOOK> <path> <args…>
    local label="$1" want="$2" hook="$3" val="$4"; shift 4
    local rc=0; set_envpre
    env "${envpre[@]}" "$hook=$val" bash "$SELF" "$@" >"$root/out" 2>&1 || rc=$?
    report "$label" "$want" "$rc"
  }
  # The same run with ONE hook MISSING ENTIRELY — the guard arms. Without these, every arm above would be
  # trusting the next one not to drive this host's real systemd, resolver, routing table or journal.
  run_nohook() {   # run_nohook <label> <want-rc> <HOOK-to-omit> <args…>
    local label="$1" want="$2" omit="$3"; shift 3
    local rc=0 x; set_envpre
    local -a keep=()
    for x in "${envpre[@]}"; do
      if [ "${x%%=*}" != "$omit" ]; then keep+=("$x"); fi
    done
    env "${keep[@]}" bash "$SELF" "$@" >"$root/out" 2>&1 || rc=$?
    if [ "$rc" = "$want" ] && grep -q "no $omit" "$root/out"; then
      pass=$((pass + 1)); printf 'ok   %s (rc %s)\n' "$label" "$rc"
    else fails=$((fails + 1)); printf 'FAIL %s: rc %s, want %s (guard line %s)\n' "$label" "$rc" "$want" "$omit"
      sed 's/^/     | /' "$root/out" | head -6; fi
  }
  says()  { if grep -qE "$2" "$root/out"; then pass=$((pass + 1)); printf 'ok   %s\n' "$1"
            else fails=$((fails + 1)); printf 'FAIL %s: output lacks /%s/\n' "$1" "$2"; sed 's/^/     | /' "$root/out" | head -8; fi; }
  lacks() { if grep -qE "$2" "$root/out"; then fails=$((fails + 1)); printf 'FAIL %s: output carries /%s/\n' "$1" "$2"; sed 's/^/     | /' "$root/out" | head -8
            else pass=$((pass + 1)); printf 'ok   %s\n' "$1"; fi; }
  unchanged() { if cmp -s "$1" "$2"; then pass=$((pass + 1)); printf 'ok   %s\n' "$3"
                else fails=$((fails + 1)); printf 'FAIL %s: %s changed when it must not have\n' "$3" "${2##*/}"; diff "$1" "$2" | head -6 | sed 's/^/     | /'; fi; }
  has_line()  { if grep -qE "$3" "$2"; then pass=$((pass + 1)); printf 'ok   %s\n' "$1"
                else fails=$((fails + 1)); printf 'FAIL %s: %s lacks /%s/\n' "$1" "${2##*/}" "$3"; grep -nE '^(ExecStart|Type|On|WantedBy|DNS|Domains)' "$2" | sed 's/^/     | /' | head -6; fi; }
  lacks_line(){ if grep -qE "$3" "$2"; then fails=$((fails + 1)); printf 'FAIL %s: %s carries /%s/\n' "$1" "${2##*/}" "$3"
                else pass=$((pass + 1)); printf 'ok   %s\n' "$1"; fi; }
  skip_arm() { printf 'SKIP %s (%s)\n' "$1" "$2"; }
  edit_in()  { sed -e "$2" "$1" >"$1.next" && mv "$1.next" "$1"; }     # in place, with no stray .bak
  syslog() { cp -f "$root/systemctl.log" "$root/seen.log" 2>/dev/null || : >"$root/seen.log"; }
  rclog()  { cp -f "$root/resolvectl.log" "$root/seen.log" 2>/dev/null || : >"$root/seen.log"; }
  log_has() { if [ -f "$root/seen.log" ] && grep -qxF "$2" "$root/seen.log"; then pass=$((pass + 1)); printf 'ok   %s\n' "$1"
              else fails=$((fails + 1)); printf 'FAIL %s: nothing was recorded as [%s]\n' "$1" "$2"; [ -s "$root/seen.log" ] && sed 's/^/     | /' "$root/seen.log"; fi; }
  # A READ of systemctl (is-enabled) is expected in every run; what an arm must prove absent is the ACT.
  no_act() { if [ -s "$root/seen.log" ] && grep -qE '^(enable|daemon-reload|disable)' "$root/seen.log"; then
               fails=$((fails + 1)); printf 'FAIL %s: systemd was ACTED on:\n' "$1"; sed 's/^/     | /' "$root/seen.log"
             else pass=$((pass + 1)); printf 'ok   %s\n' "$1"; fi; }
  # The whole fixture tree, hashed: the only proof of "nothing changed" that cannot be talked into passing.
  tree_hash() { find "$dir" "$ddir" "$root/sbin" -type f 2>/dev/null | LC_ALL=C sort |
                  while IFS= read -r f; do sha256sum "$f"; done | sha256sum | cut -d' ' -f1; }
  clean_fixture() {
    rm -rf "$dir" "$ddir"; mkdir -p "$dir" "$ddir"
    rm -f "$legf" "$legf".bak-* "$state"/rb-* "$state/enabled" "$state/refuse"
    rm -rf "$root/pre"; mkdir -p "$root/pre"
    base_route
  }
  # seed_legacy — the trio EXACTLY as one box carries it today: this family's own hand-placed bytes, with no
  # marker anywhere because they predate the marker. Seeded through legacy_render, whose values are hard
  # (a record of a state, not a configuration), with the gateway derived from the fixture route the way the
  # real drop-in always derived it. The timer is left ENABLED, as it is on the seat: an un-enabled timer
  # would add its own DRIFT and bury the finding this group is about.
  seed_legacy() {
    local _ip="$IP_BIN"
    IP_BIN="$root/stubs/ip"
    derive_route || stop "the fixture route is not derivable, so the state this arm replaces cannot be seeded"
    IP_BIN="$_ip"
    legacy_render "$DROPIN_FILE" "$ddir/$DROPIN_FILE"
    legacy_render "$SVC"         "$dir/$SVC"
    legacy_render "$TMR"         "$dir/$TMR"
    : >"$state/enabled"
  }
  # The bytes the superseded script had, byte for byte. Arm 7 hands these to the fixture to prove the
  # digest in this file identifies THAT file and no other.
  legacy_bytes() {
    cat >"$legf" <<'LEGACY_BYTES'
#!/bin/sh
# Applies the per-link DNS route. Logs the verdict of each call to the journal:
# resolvectl exits 0 even when resolved refuses, so the output is the only witness.
{
  echo "id: $(id -u) $(id -un)"
  echo "-- dns --"; resolvectl dns eth0 100.100.100.100; echo "rc=$?"
  echo "-- domain --"; resolvectl domain eth0 "~ts.kogler.si" "~kogler.si"; echo "rc=$?"
  echo "-- readback --"; resolvectl dns eth0; resolvectl domain eth0
  resolvectl flush-caches >/dev/null 2>&1
} 2>&1 | logger -t homelab-dns-route
LEGACY_BYTES
    chmod 755 "$legf"
  }

  # 1. MISSING, and the act that ends it — the state a reimaged box is in. Both halves: absent is not OK,
  #    and after the install the very same command is.
  clean_fixture
  run "1a  no files installed is MISSING" 1 --check
  says  "1b  and the verdict names all three artifacts" 'MISSING: in this state: homelab-dns\.conf, homelab-dns-route\.service, homelab-dns-route\.timer'
  run "1c  MISSING fails without --strict too (no arm at all is not a seat state)" 1 --check --strict
  rm -f "$root/systemctl.log"
  run "1d  --install writes the three files and enables the timer" 0 --install
  if [ -f "$dir/$SVC" ] && [ -f "$dir/$TMR" ] && [ -f "$ddir/$DROPIN_FILE" ]; then
    pass=$((pass + 1)); echo "ok   1e  all three artifacts are in place after --install"
  else fails=$((fails + 1)); echo "FAIL 1e  an artifact is absent after --install"; ls -a "$dir" "$ddir" | sed 's/^/     | /'; fi
  syslog
  log_has "1f  the install reloaded systemd (a unit systemd has never read cannot fire)" 'daemon-reload'
  log_has "1g  and enabled --now the TIMER (a written unit that is never enabled is an arm that never fires)" "enable --now $TMR"
  says  "1h  and printed its own read-back, because rc 0 says the call ran, not that anything is scheduled" 'read-back: is-enabled=enabled is-active=active'
  run "1i  control: the same command now reads OK" 0 --check --strict

  # 2. BYTE EQUALITY AND IDEMPOTENCE — `OK` claims equality with what `--install` writes, so the claim is
  #    compared and not asserted, and "installing twice changes nothing" is proved by hashing the tree.
  want_render="$root/render"
  run_hook "2z  --render runs with the fixture route" 0 SEAT_DNS_ROUTE_IP "$root/stubs/ip" --render
  set_envpre; env "${envpre[@]}" bash "$SELF" --render >"$want_render" 2>&1
  has_line "2a  the installed .service is the render --render prints" "$dir/$SVC" '^Description=Homelab WSL seat: route kogler\.si \+ ts\.kogler\.si through the MagicDNS loop$'
  has_line "2b  the installed drop-in is the render too" "$ddir/$DROPIN_FILE" '^DNS=172\.17\.0\.1$'
  has_line "2c  and so is the timer cadence" "$dir/$TMR" '^OnUnitActiveSec=120s$'
  local h_before h_after
  h_before="$(tree_hash)"
  run "2d  --install a second time answers rc 0" 0 --install
  says  "2e  and says it changed nothing" 'already in sync'
  h_after="$(tree_hash)"
  if [ "$h_before" = "$h_after" ]; then pass=$((pass + 1)); echo "ok   2f  the whole fixture tree hashes IDENTICAL across a second install (an arm that rewrote its own files every run would never read OK)"
  else fails=$((fails + 1)); echo "FAIL 2f  the tree changed on an install that said it did not"; fi
  run "2g  and it still reads OK" 0 --check --strict

  # 3. DRIFT BY A MOVED VALUE — a cadence and a gateway, the two values most likely to be tuned in the
  #    wrong file. Report-only, strict-failing, repairable, with a dated .bak- beside what was replaced.
  edit_in "$dir/$TMR" 's/^OnUnitActiveSec=120s$/OnUnitActiveSec=180s/'
  run "3a  a hand-moved cadence is report-only in plain --check" 0 --check
  says  "3b  and it is reported as DRIFT, naming the file" '^  homelab-dns-route\.timer: DRIFT'
  run "3c  the same file is a FAILURE under --strict" 1 --check --strict
  run "3d  --install repairs it" 0 --install
  has_line "3e  and the timer is the render again" "$dir/$TMR" '^OnUnitActiveSec=120s$'
  if ls "$dir" | grep -q "^$TMR\.bak-[0-9]"; then pass=$((pass + 1)); echo "ok   3f  the replaced unit kept a dated .bak- beside it"
  else fails=$((fails + 1)); echo "FAIL 3f  a unit file was replaced with no backup"; ls -a "$dir" | sed 's/^/     | /'; fi
  run "3g  control: OK after the repair" 0 --check --strict
  edit_in "$ddir/$DROPIN_FILE" 's/^DNS=172\.17\.0\.1$/DNS=10.0.0.1/'
  run "3h  a hand-edited uplink address in the drop-in is DRIFT under --strict" 1 --check --strict
  says  "3i  and it names the drop-in, not the units" '^  homelab-dns\.conf: DRIFT'
  run "3j  --install re-renders the drop-in" 0 --install
  has_line "3k  and the uplink address is back to the derived one" "$ddir/$DROPIN_FILE" '^DNS=172\.17\.0\.1$'

  # 4. THE GATEWAY IS DERIVED, NEVER TYPED. A boot that hands the guest a new address makes the drop-in
  #    drift, and both the file verdict and the timer's own log say so. This is the arm that proves no
  #    constant in this file is standing in for a host fact.
  set_route 'default via 192.168.99.1 dev eth0 proto kernel'
  run "4a  a moved gateway makes the drop-in DRIFT (the file names an address the box no longer uses)" 1 --check --strict
  says  "4b  and the verdict names the drop-in as the file that moved" '^  homelab-dns\.conf: DRIFT'
  run "4c  --install re-renders it with the NEW gateway" 0 --install
  has_line "4d  and the address written is the one ip route named" "$ddir/$DROPIN_FILE" '^DNS=192\.168\.99\.1$'
  run "4e  control: the derived value and the file agree again" 0 --check --strict
  run "4f  and --push claims on the link ip route names, not a hardcoded eth0" 0 --push
  rclog
  log_has "4g  --push points the link the route names at the MagicDNS loop" 'dns eth0 100.100.100.100'
  log_has "4h  and BOTH route domains travel in ONE call, because the claim replaces the link list" 'domain eth0 ~ts.kogler.si ~kogler.si'
  set_route 'default via 172.17.0.1 dev eth0 proto kernel'
  run "4i  a gateway that moved under an installed arm: --push still lands the claim, and says which half is stale" 0 --push
  says  "4j  the NOTE names the uplink half and the fix that owns it" 'NOTE: the uplink half is stale.*--install'
  run "4k  --install lands the stale half too" 0 --install
  run "4l  and --push has nothing left to complain about" 0 --push
  lacks "4m  a clean run prints no stale NOTE" 'uplink half'

  # 5. THE TRAP: Type=oneshot, and RemainAfterExit nowhere near it. A comment MAY name the key (that is
  #    what the rendered comment is for); a line that SETS it is the defect, so the rule is the key form.
  has_line   "5a  the rendered service is Type=oneshot" "$want_render" '^Type=oneshot$'
  lacks_line "5b  and renders no RemainAfterExit setting (with it the unit stays active(exited) and every timer fire is a no-op that reports success)" "$want_render" '^[[:space:]]*RemainAfterExit'
  has_line   "5c  the timer carries the boot-time fire" "$want_render" '^OnBootSec=10s$'
  has_line   "5d  and the 120 s re-assert interval — the cadence the seat already runs, and the one seat-llm-path-timer.sh cites" "$want_render" '^OnUnitActiveSec=120s$'
  has_line   "5e  and the timer is wanted by timers.target" "$want_render" '^WantedBy=timers.target$'
  has_line   "5f  the service is wanted by multi-user.target, as the live unit is" "$want_render" '^WantedBy=multi-user.target$'
  has_line   "5g  the uplink drop-in routes the plain zone and leaves the .ts namespace to the link" "$want_render" '^Domains=~\. ~kogler\.si$'
  has_line   "5h  and turns neither DNSOverTLS nor the stub listener off" "$want_render" '^DNSStubListener=yes$'
  printf '%s\n' '' '[Service]' 'RemainAfterExit=yes' >>"$dir/$SVC"
  run "5i  a hand-added RemainAfterExit is DRIFT under --strict" 1 --check --strict
  says  "5j  and the finding names the file that moved it" '^  homelab-dns-route\.service: DRIFT'
  run "5k  --install retires it" 0 --install
  lacks_line "5l  the trap does not survive the repair" "$dir/$SVC" '^[[:space:]]*RemainAfterExit'
  mkdir -p "$dir/$SVC.d"
  printf '[Service]\nNice=10\n' >"$dir/$SVC.d/operator.conf"
  run "5m  a drop-in that does not touch the trap stays outside the verdict" 0 --check --strict
  says  "5n  and it is printed as a NOTE, because a drop-in merges over the unit" 'NOTE: .*drop-ins'
  printf '[Service]\nRemainAfterExit=yes\n' >"$dir/$SVC.d/trap.conf"
  run "5o  a drop-in that SETS RemainAfterExit is the verdict: the trap through the side door" 1 --check --strict
  says  "5p  and it is named as the drop-in rather than as file drift" 'DRIFT\(drop-in\)'
  rm -f "$root/systemctl.log"
  run "5q  --install will not enable an arm it just called neutered" 1 --install
  says  "5r  and it says the finding is not its own to fix" 'NOT-FIXED'
  syslog
  no_act "5s  a refused install acts on systemd not at all (reading is-enabled is not an act)"
  rm -rf "$dir/$SVC.d"
  run "5t  control: with the drop-in gone the arm reads OK again" 0 --check --strict

  # 6/7. A FOREIGN FILE, at every path this arm owns. Refused, with the bytes proven untouched and NOTHING
  #      written — because half an installed arm is a state no later verdict can describe.
  foreign_probe() {   # foreign_probe <label-prefix> <path>
    local num="$1" path="$2"
    clean_fixture
    printf '[Unit]\nDescription=someone else under this arm name\n\n[Service]\nType=simple\nExecStart=/bin/true\n' >"$path"
    cp -p "$path" "$root/foreign-before"
    run "${num}a  a file this script did not write is DRIFT(foreign)" 1 --check --strict
    says  "${num}b  and the verdict names it foreign rather than drift" 'DRIFT\(foreign\)'
    rm -f "$root/systemctl.log"
    run "${num}c  --install REFUSES it" 1 --install
    says  "${num}d  and the refusal says what it is" 'REFUSAL\(foreign\)'
    unchanged "$root/foreign-before" "$path" "${num}e  the refusal left the foreign file byte-identical"
    syslog
    no_act "${num}f  and a refused install acts on systemd not at all"
  }
  foreign_probe 6 "$dir/$SVC"
  foreign_probe 7 "$dir/$TMR"
  foreign_probe 8 "$ddir/$DROPIN_FILE"
  clean_fixture
  run "9a  control: with the foreign file gone the arm installs" 0 --install
  run "9b  and it reads OK" 0 --check --strict

  # 10. THE SUPERSEDED `/usr/local/sbin` COPY — three states, and the one that must never be guessed.
  legacy_bytes
  run "10a  the superseded copy at the old path is DRIFT(legacy)" 1 --check --strict
  says  "10b  and it is named as the legacy arm, not as a foreign file" 'DRIFT\(legacy\)'
  says  "10c  and the finding says where the act lives now" 'second source'
  run "10d  --install retires it, because its digest proves this family wrote it" 0 --install
  if [ ! -e "$legf" ]; then pass=$((pass + 1)); echo "ok   10e  the superseded copy is gone from the path it occupied"
  else fails=$((fails + 1)); echo "FAIL 10e  --install left the superseded copy in place"; fi
  if ls "$root/sbin" | grep -q 'homelab-dns-route\.sh\.bak-[0-9]'; then pass=$((pass + 1)); echo "ok   10f  and it was moved aside under a dated name, not deleted"
  else fails=$((fails + 1)); echo "FAIL 10f  the superseded copy vanished with no copy of itself"; ls -a "$root/sbin" | sed 's/^/     | /'; fi
  run "10g  control: with the copy gone the arm reads OK" 0 --check --strict
  rm -f "$root/sbin"/*.bak-*
  printf '%s\n' "$MARKER" '# a hand-retyped copy of the same act' >"$legf"
  run "10h  a copy carrying this arm MARKER is ours too, even with different bytes" 1 --check --strict
  says  "10i  and it reads as the legacy arm" 'DRIFT\(legacy\)'
  run "10j  --install retires it on that proof as well" 0 --install
  if [ ! -e "$legf" ]; then pass=$((pass + 1)); echo "ok   10k  removed"
  else fails=$((fails + 1)); echo "FAIL 10k  the marker-carrying copy survived --install"; fi
  rm -f "$root/sbin"/*.bak-*
  printf '%s\n' '#!/bin/sh' '# a different script that happens to live at the superseded path' >"$legf"
  cp -p "$legf" "$root/leg-before"
  run "10l  a DIFFERENT file at that path is DRIFT(foreign), not a leftover to clean up" 1 --check --strict
  says  "10m  and it is named foreign" 'DRIFT\(foreign\)'
  rm -f "$root/systemctl.log"
  run "10n  --install REFUSES it" 1 --install
  says  "10o  and says nothing at all was written" 'nothing at all was written'
  unchanged "$root/leg-before" "$legf" "10p  the foreign copy is byte-identical: an uninstall that guesses is an act on someone else's file"
  if [ -f "$dir/$SVC" ] && [ -f "$ddir/$DROPIN_FILE" ]; then pass=$((pass + 1)); echo "ok   10q  and the files this arm owns were NOT half-installed around the refusal"
  else fails=$((fails + 1)); echo "FAIL 10q  the install wrote files before refusing"; fi
  syslog
  no_act "10r  and a refused install acts on systemd not at all"
  rm -f "$legf"
  run "10s  control: with the foreign copy gone the arm installs" 0 --install
  run "10t  and reads OK" 0 --check --strict
  if [ "$(id -u)" != 0 ]; then
    legacy_bytes; chmod 000 "$legf"
    run "10u  a superseded copy that cannot be hashed is a STOP, not a verdict" 2 --check
    says  "10v  and it says FATAL rather than guessing provenance" '^FATAL'
    chmod 644 "$legf"
    run "10w  control: readable again, the verdict comes back (and it is the legacy one, not a guess)" 1 --check --strict
    says  "10x  naming it DRIFT(legacy)" 'DRIFT\(legacy\)'
    rm -f "$legf"
    run "10y  control: with it gone, OK" 0 --check --strict
  else
    skip_arm "10u  an unhashable superseded copy is a STOP" "running as root, file modes do not bind"
    skip_arm "10v  and the control that answers again" "running as root, file modes do not bind"
  fi

  # 11. THE READ-BACK IS THE VERDICT — the canary this whole arm exists for. resolvectl exits 0 when
  #     resolved refuses, so a run that trusts the exit code reports a working arm on a box still leaking.
  #     The stub here LIES with rc 0 and says so only in the read-back.
  : >"$state/refuse"
  run "11a  a resolver that accepts with rc 0 and obeys NOTHING must NOT read OK" 1 --push
  says  "11b  the read-back is what says so, not the exit code" 'DRIFT\(per-link\)'
  says  "11c  and the run ends NOT-IN-SYNC" 'NOT-IN-SYNC'
  lacks "11d  and nothing in the output claims the claim is in force" 'OK: the claim is in force'
  rm -f "$state/refuse"
  run "11e  control: the very same push reads OK once resolved obeys" 0 --push
  says  "11f  with the write rc AND the read-back printed side by side" 'readback dns -- \[100\.100\.100\.100\]'
  if [ -f "$root/journal.log" ] && grep -qF 'push: link=eth0' "$root/journal.log"; then
    pass=$((pass + 1)); echo "ok   11g  and the exchange reached the journal — a timer fire with no witness is a fire nobody can audit"
  else fails=$((fails + 1)); echo "FAIL 11g  nothing reached the journal stub"; fi
  rclog
  log_has "11h  the claim names the LOOP address on the derived link" 'dns eth0 100.100.100.100'
  log_has "11i  and caches are flushed, because a cached NXDOMAIN outlives the route fix" 'flush-caches'

  # 12. THE TRIGGER: three correct files and a timer nobody enabled is an arm that never fires. No file is
  #     out of place to blame, so the enable state belongs in the verdict rather than in a NOTE.
  rm -f "$state/enabled"
  run "12a  a written-but-never-enabled timer is DRIFT under --strict" 1 --check --strict
  says  "12b  and the finding names the trigger, not a file" 'timer enabled: DRIFT'
  run "12c  --install re-arms it" 0 --install
  syslog
  log_has "12d  by enabling the timer again" "enable --now $TMR"
  run "12e  control: enabled again, it reads OK" 0 --check --strict

  # 13. A dead systemctl: in --check that is NO VERDICT (a read that never read the trigger owes no
  #     answer); in --install it is INCOMPLETE and NOTHING is written, because three files with no timer
  #     behind them are half an installed arm. The difference is the mode, not the fact.
  run_hook "13a  --check with no systemctl to ask is a STOP, never a green" 2 \
           SEAT_DNS_ROUTE_SYSTEMCTL "$root/no-systemctl-here" --check --strict
  says  "13b  and it says FATAL rather than inferring the enable state from a symlink" '^FATAL'
  clean_fixture
  run_hook "13c  --install with no systemctl says INCOMPLETE" 1 \
           SEAT_DNS_ROUTE_SYSTEMCTL "$root/no-systemctl-here" --install
  says  "13d  and says plainly that nothing will fire" 'INCOMPLETE\(systemctl\)'
  if [ -z "$(ls -A "$dir")" ] && [ -z "$(ls -A "$ddir")" ]; then pass=$((pass + 1)); echo "ok   13e  and it wrote NOTHING — three files with no timer are half an arm"
  else fails=$((fails + 1)); echo "FAIL 13e  the incomplete install wrote files anyway"; ls -a "$dir" "$ddir" | sed 's/^/     | /'; fi
  run "13f  control: with the stub back the install lands" 0 --install
  run "13g  and reads OK" 0 --check --strict

  # 14. The environment boundaries. Each prints a NAMED state rather than a verdict, and the mode-dependent
  #     ones print SKIP where the mode does not bind.
  if [ "$(id -u)" != 0 ]; then
    chmod 555 "$dir"
    run "14a  an unwritable unit dir REFUSES, it does not pretend" 1 --install
    says  "14b  and the refusal prints the exact sudo command" 'sudo bash .*/scripts/harness/seat-dns-route\.sh --install'
    chmod 755 "$dir"
    run "14c  control: writable again, the install lands" 0 --install
    chmod 000 "$dir/$SVC"
    run "14d  an unreadable unit file is a STOP, not a verdict" 2 --check
    says  "14e  and it says FATAL rather than guessing a state" '^FATAL'
    chmod 644 "$dir/$SVC"
    run "14f  control: readable again, it answers" 0 --check --strict
  else
    skip_arm "14a  an unwritable unit dir REFUSES" "running as root, file modes do not bind"
    skip_arm "14d  an unreadable unit file is a STOP" "running as root, file modes do not bind"
  fi
  mv "$dir" "$dir.saved"
  run "14g  a missing unit directory is a STOP, never MISSING (a dir nobody can read answers nothing)" 2 --check
  says  "14h  and it says FATAL" '^FATAL'
  mv "$dir.saved" "$dir"
  run "14i  control: the directory back, the verdict is back" 0 --check --strict
  printf '%s\n' '# a drop-in from another family, still read by resolved' '[Resolve]' 'DNS=1.1.1.1' >"$ddir/other.conf"
  run "14j  another family's .conf in the same directory is not this arm's business" 0 --check --strict
  lacks "14k  and it is not reported as a leftover, because it is not inert" 'non-\.conf'
  printf '%s\n' '# inert: systemd-resolved reads only *.conf' '[Resolve]' 'DNS=9.9.9.9' >"$ddir/homelab-dns.conf.bak-20261020-1315"
  printf '%s\n' '# inert: the day this arm was disabled by hand' '[Resolve]' 'DNS=8.8.8.8' >"$ddir/homelab-dns.conf.orig-disabled"
  run "14l  the seat's dated .bak/.orig leftovers are a NOTE, never a verdict" 0 --check --strict
  says  "14m  and the NOTE names them and says they are inert" 'non-\.conf leftover.*inert'
  rm -f "$ddir/other.conf" "$ddir"/*.bak-* "$ddir"/*.orig-disabled
  run "14n  control: with the directory tidied the same check still reads OK" 0 --check --strict
  run_hook "14o  with no logger, a push still works but says its own witness is missing" 0 SEAT_DNS_ROUTE_LOGGER "$root/no-logger" --push
  says  "14p  and names the witness it could not write" 'no logger at'

  # 15. THE ROUTE READ, both edges. A seat with no default route has no uplink to name; a seat with two
  #     disagreeing ones has no decidable one. Neither gets a guess.
  run_hook "15a  with no ip to ask, --check is a STOP" 2 SEAT_DNS_ROUTE_IP "$root/no-ip" --check --strict
  says  "15b  and it names the derivation as the thing it could not do" '^FATAL'
  run_hook "15c  and --install stops too, before writing a drop-in that would name a guessed gateway" 2 SEAT_DNS_ROUTE_IP "$root/no-ip" --install
  says  "15d  and it says so rather than writing" '^FATAL'
  set_route '172.17.0.0/20 dev eth0 proto kernel scope link src 172.17.7.3'
  run "15e  no default route is NO VERDICT, not a drop-in naming no gateway" 2 --check
  says  "15f  and it says so rather than typing something" '^FATAL'
  run "15g  --push refuses to claim on a link it could not derive" 2 --push
  says  "15h  and claims nothing" '^FATAL'
  set_route 'default via 10.0.0.1 dev wlan0 metric 100
default via 10.0.0.9 dev eth0 metric 200'
  run "15i  two default routes that disagree are NO VERDICT: the first line of a guessing order is a guess" 2 --check
  says  "15j  and the STOP says the uplink was not decidable" 'not decidable'
  run "15k  and --install writes nothing on an undecidable uplink" 2 --install
  set_route 'default via 172.17.0.1 dev eth0 proto kernel
default via 172.17.0.1 dev eth0 proto kernel'
  run "15l  two IDENTICAL defaults are one fact, not a disagreement" 0 --check --strict
  set_route 'default via 172.17.0.1 dev eth0 proto kernel'
  run "15m  control: one default route, and the verdict is back" 0 --check --strict
  run "15n  and a gateway that moved is repaired by the same act, not by a reboot" 0 --install
  has_line "15o  the derived address is what the drop-in carries" "$ddir/$DROPIN_FILE" '^DNS=172\.17\.0\.1$'

  # 16. The STOPs that are about the REPO rather than the box: an ExecStart that names a script the tree
  #     does not have is a timer that fires into nothing, so nothing here may read in sync.
  mv "$root/repo/scripts/harness/$(basename "$SELF")" "$root/plane.moved"
  h_before="$(tree_hash)"
  run "16a  an ExecStart naming a script the repo does not have is a STOP" 2 --check
  says  "16b  and it says so rather than reporting three files in sync" '^FATAL'
  run "16c  and --install stops too, before writing anything" 2 --install
  h_after="$(tree_hash)"
  if [ "$h_before" = "$h_after" ]; then pass=$((pass + 1)); echo "ok   16d  and the STOP changed nothing in the tree (a stopped run leaves no trace)"
  else fails=$((fails + 1)); echo "FAIL 16d  the STOP changed the tree"; fi
  mv "$root/plane.moved" "$root/repo/scripts/harness/$(basename "$SELF")"
  run "16e  control: the unpoisoned repo installs again" 0 --install
  run "16f  and reads OK" 0 --check --strict

  # 17. THE SELF-TEST'S OWN BELT: a fixture arm that FORGOT a stub must stop rather than drive this host's
  #     real systemd, resolver, routing table or journal. Every arm above is trusting this to be true.
  run_nohook "17a  an arm with no systemctl stub stops before it touches anything" 2 SEAT_DNS_ROUTE_SYSTEMCTL --install
  run_nohook "17b  an arm with no resolvectl stub stops before it rewrites a live resolver" 2 SEAT_DNS_ROUTE_RESOLVEDCTL --push
  run_nohook "17c  an arm with no ip stub stops instead of reading the host's routing table" 2 SEAT_DNS_ROUTE_IP --check
  run_nohook "17d  an arm with no logger stub stops instead of writing the host's journal" 2 SEAT_DNS_ROUTE_LOGGER --push

  # 18. THE WORKTREE: a LINKED worktree is not a home for an arm whose ExecStart names $REPO by absolute
  #     path — `git worktree remove` deletes the lane's directory, and a timer firing into nothing is the
  #     silence this arm exists to prevent. --check and --render stay read-only and still run from anywhere.
  mkdir -p "$root/wt/scripts/harness"
  : >"$root/wt/.git"                       # a linked worktree says so with a .git FILE, not a directory
  cp "$root/repo/scripts/harness/$(basename "$SELF")" "$root/wt/scripts/harness/$(basename "$SELF")"
  rc0=0
  env "${envpre[@]}" REPO="$root/wt" bash "$SELF" --install >"$root/out" 2>&1 || rc0=$?
  if [ "$rc0" = 1 ] && grep -q 'REFUSAL(worktree)' "$root/out"; then pass=$((pass + 1)); echo "ok   18a  installing from a linked worktree is REFUSED"
  else fails=$((fails + 1)); printf 'FAIL 18a the worktree install answered rc %s, want 1 with a refusal\n' "$rc0"; sed 's/^/     | /' "$root/out" | head -6; fi
  rc0=0
  env "${envpre[@]}" REPO="$root/wt" bash "$SELF" --check --strict >"$root/out" 2>&1 || rc0=$?
  # The read still runs from a worktree — it writes nothing, so it needs no home. And it reads the pair as
  # DRIFT, which is the point: an arm installed from a path that gets deleted is VISIBLE, not durable.
  if [ "$rc0" = 1 ] && grep -q '^  homelab-dns-route\.service: DRIFT' "$root/out"; then
    pass=$((pass + 1)); echo "ok   18b  --check still runs from a worktree, and the ExecStart it names reads as DRIFT there"
  else fails=$((fails + 1)); printf 'FAIL 18b --check from a worktree answered rc %s\n' "$rc0"; sed 's/^/     | /' "$root/out" | head -6; fi

  # 19. THE REPO CARRIER — the arm that makes this more than one box's state. Asked of THIS checkout, with
  #     no fixture repo in the way: what a reimaged box gets is what this tree carries.
  local rc_tree=0
  env SEAT_DNS_ROUTE_IP="$root/stubs/ip" bash "$SELF" --render >"$root/render-this-checkout" 2>&1 || rc_tree=$?
  if [ "$rc_tree" = 0 ]; then pass=$((pass + 1)); echo "ok   19a  this checkout renders the trio with no fixture repo in the way"
  else fails=$((fails + 1)); printf 'FAIL 19a --render on this checkout rc %s\n' "$rc_tree"; sed 's/^/     | /' "$root/render-this-checkout" | head -6; fi
  has_line "19b  and the ExecStart it carries names the script that lives in this checkout" \
    "$root/render-this-checkout" "^ExecStart=/bin/bash $REPO/scripts/$SUBDIR/$(basename "$SELF") --push\$"
  has_line "19c  the service is wanted by multi-user.target, so enabling it has something to enable" \
    "$root/render-this-checkout" '^WantedBy=multi-user.target$'
  has_line "19d  both units and the drop-in carry the marker that makes them nameable as ours" \
    "$root/render-this-checkout" '^# managed-by: homelab dns-route seat plane'
  lacks_line "19e  this checkout renders no copy of the act outside the repo" \
    "$root/render-this-checkout" '^[E]xecStart=.*usr/local/sbin'
  if [ -r "$PLANE_SCRIPT" ]; then pass=$((pass + 1)); echo "ok   19f  and the script the ExecStart names is tracked here, so a reimaged box gets the arm with the clone"
  else fails=$((fails + 1)); echo "FAIL 19f  the ExecStart names $PLANE_SCRIPT, which is not in this tree"; fi

  # 20. THE MIGRATION — the case this file exists to land. A seat whose three artifacts this family
  #     hand-placed BEFORE the repo owner existed carries no marker anywhere, so "no marker" must not be the
  #     test for "not ours". Seeded from legacy_render, which is byte-identical to what the seat carries
  #     today, and run as a canary: the state, the act, the proof, the control — and then the one-byte
  #     variant, the arm that proves the new rule is still a fingerprint and not "anything unmarked is ours".
  clean_fixture
  seed_legacy
  cp -p "$ddir/$DROPIN_FILE" "$dir/$SVC" "$dir/$TMR" "$root/pre/"
  run   "20a  this family's unowned trio is DRIFT under --strict, as it must be" 1 --check --strict
  says  "20b  and it is DRIFT(legacy), naming the artifacts as this family's unowned copies" 'DRIFT\(legacy\) — this family.s unowned copy'
  says  "20c  the verdict itself is the legacy one, not an accusation of a stranger" '^DRIFT\(legacy\): in this state'
  lacks "20d  and NOTHING here reads as someone else's file — the case the whole rule exists for" 'DRIFT\(foreign\)'
  says  "20e  the NOTE says --install takes it over rather than asking for a cleanup first" 'takes it over'
  run   "20f  --install takes the whole trio over" 0 --install
  says  "20g  and it says so, once per artifact, before it writes" '^takeover: '
  n_bak=$(find "$dir" "$ddir" -name '*.bak-*' -type f 2>/dev/null | wc -l)
  if [ "$n_bak" = 3 ]; then pass=$((pass + 1)); echo "ok   20h  a dated .bak- was kept beside each of the three"
  else fails=$((fails + 1)); printf 'FAIL 20h  %s .bak- files, want 3\n' "$n_bak"; find "$dir" "$ddir" -name '*.bak-*' | sed 's/^/     | /'; fi
  n_same=0
  for f in "$ddir/$DROPIN_FILE.bak-"* "$dir/$SVC.bak-"* "$dir/$TMR.bak-"*; do
    base="$(basename "$f")"; base="${base%.bak-*}"
    case "$base" in "$DROPIN_FILE") src="$root/pre/$DROPIN_FILE" ;; "$SVC") src="$root/pre/$SVC" ;; *) src="$root/pre/$TMR" ;; esac
    cmp -s "$f" "$src" && n_same=$((n_same + 1))
  done
  if [ "$n_same" = 3 ]; then pass=$((pass + 1)); echo "ok   20i  and every .bak- is byte-identical to the bytes that were there, so the takeover is reversible"
  else fails=$((fails + 1)); printf 'FAIL 20i  only %s of 3 backups match the pre-install bytes\n' "$n_same"; fi
  run   "20j  the taken-over trio is the render now (rc 0 --check --strict)" 0 --check --strict
  lacks "20k  and the migration left no legacy verdict behind" 'DRIFT\(legacy\) — this family'
  h_pre="$(tree_hash)"
  run   "20l  a second --install on the migrated tree is a no-op" 0 --install
  h_post="$(tree_hash)"
  if [ "$h_pre" = "$h_post" ]; then pass=$((pass + 1)); echo "ok   20m  and the whole tree hashes IDENTICAL across it — a takeover, not a rewrite loop"
  else fails=$((fails + 1)); echo "FAIL 20m  the second install changed the tree"; fi
  lacks_line "20n  the taken-over ExecStart no longer points at /usr/local/sbin" "$dir/$SVC" '^[E]xecStart=.*/usr/local/sbin/'

  clean_fixture
  seed_legacy
  edit_in "$dir/$TMR" 's/^OnBootSec=10s$/OnBootSec=11s/'      # ONE byte off the legacy form, no marker
  cp -p "$dir/$TMR" "$root/pre/tmr.hand"
  run    "20o  one byte off the legacy form is NOT this family's copy: DRIFT(foreign)" 1 --check --strict
  says   "20p  the hand-edited file is named foreign" 'homelab-dns-route\.timer: DRIFT\(foreign\)'
  says   "20q  and the verdict names ONLY the timer: its two siblings stay this family's own copies" \
         '^DRIFT\(foreign\): in this state: homelab-dns-route\.timer$'
  says   "20qa  the rule is a fingerprint, not 'anything without a marker is ours'" 'family hand-placed either'
  rm -f "$root/systemctl.log"
  run    "20r  --install REFUSES the hand-edited variant" 1 --install
  says   "20s  and says nothing at all was written" 'Nothing at all was written'
  unchanged "$root/pre/tmr.hand" "$dir/$TMR" "20t  the hand-edited file is byte-identical: an act that guesses is an act on a stranger"
  run    "20ta  the two artifacts it did own were NOT half-taken-over around the refusal" 1 --check --strict
  says   "20tb  they still read, untouched, as this family's unowned copies" 'homelab-dns\.conf: DRIFT\(legacy\)'
  syslog
  no_act "20u  and a refused takeover acts on systemd not at all"
  edit_in "$dir/$TMR" 's/^OnBootSec=11s$/OnBootSec=10s/'
  run    "20v  control: put the legacy bytes back and the takeover lands" 0 --install
  run    "20w  and the migrated seat reads OK" 0 --check --strict

  # The fingerprint's documented limit, kept as a canary rather than a surprise. The legacy drop-in carries
  # the gateway of the boot it was hand-placed on, and the comparison DERIVES the current one — so a seat
  # whose uplink moved since then no longer matches byte for byte. It reads foreign and `--install` refuses:
  # the conservative side, because a re-derived address is a fact about the box that a provenance proof must
  # not borrow. Clear it by hand (a dated .bak of the file, then re-run) or by landing the render on a box
  # that still has the address the copy was written with.
  clean_fixture
  seed_legacy
  set_route 'default via 10.0.0.1 dev wlan0 proto kernel'
  run    "20z  the limit: a trio whose uplink moved since the hand-place is foreign, not taken over" 1 --check --strict
  says   "20za  and it is the drop-in, the one file that names an address, that reads foreign" 'homelab-dns\.conf: DRIFT\(foreign\)'
  rm -f "$root/systemctl.log"
  h_off="$(tree_hash)"
  run    "20zb  --install refuses it rather than rewriting an address on an unproven claim" 1 --install
  says   "20zc  and the run says REFUSAL, not a silent rewrite" 'REFUSAL\(foreign\)'
  unchanged_by_hash() { if [ "$1" = "$(tree_hash)" ]; then pass=$((pass + 1)); echo "ok   $2"
                        else fails=$((fails + 1)); echo "FAIL $2  the refused run changed the tree"; fi; }
  unchanged_by_hash "$h_off" "20zd  and the refused run changed nothing on the seat"
  syslog
  no_act "20ze  and it acted on systemd not at all"
  base_route
  run    "20zf  control: the route back, and the same trio is this family's again" 0 --install
  run   "20zb  control: the route back, and the same trio is this family's again" 0 --install

  printf '\nself-test: %s (%d passed, %d failed)\n' \
    "$([ "$fails" -eq 0 ] && echo OK || echo FAILED)" "$pass" "$fails"
  [ "$fails" -eq 0 ]
}

# --- dispatch ----------------------------------------------------------------------
case "$MODE" in
  selftest) selftest; exit $? ;;
  render)   do_render; exit $? ;;
esac
scratch
case "$MODE" in
  push)    do_push ;;
  install) do_install ;;
  *)       assess; do_check ;;
esac
exit $?
