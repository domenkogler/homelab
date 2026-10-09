#!/usr/bin/env bash
# install-tmux-conf.sh — install AND prove the seat's tmux seat config
# (repo SSOT `pi-agent/tmux/tmux.conf` → `~/.tmux.conf`). HD-1085.
#
# WHY THIS IS NOT JUST A `cmp` OF THE TWO FILES
# --------------------------------------------
# Byte equality proves the file is in place. It does NOT prove the file WORKS, and
# the gap is not theoretical — it cost this session an hour of "the file is on disk
# and mouse is still off" with every command returning 0. Six fixtures on tmux 3.5a,
# each loaded with `tmux -L <sock> -f <conf> new-session -d` (method + table in
# docs/pi-harness.md §5b):
#
#   block opened at end of a line ......... EFFECTIVE   ← ordinary wrapped shapes
#   backslash-continued command ........... EFFECTIVE     load fine
#   one bad command mid-file .............. INERT       ← mouse OFF, history-limit
#   unknown command mid-file .............. INERT         2000, mode-keys emacs:
#   nested wrapped if-shell { } { } ....... INERT         the DEFAULTS, as if the
#                                                         file were not there
#   unterminated quote at the end ......... PARTIAL     mouse ON, mode-keys emacs
#
# In every INERT case the caller got **exit 0 with empty stderr** — tmux reports a
# config failure as a client *message*, and a detached `new-session` has no client
# to print it to. So an error anywhere in the file can leave part or all of it
# unapplied, WHICH part is not predictable from the parser, and the exit code never
# tells you. Hence: this script LOADS the config into a throwaway server on a
# private socket and reads the options back. CONVENTIONS §6 — a test that cannot
# fail is not evidence, and a `cmp` of two identical files cannot fail.
#
# The second silent failure is the clipboard. tmux sends an OSC 52 sequence for a
# buffer update only when the terminal it drives is credited with the capability —
# either by tmux's built-in terminal-NAME table (xterm*/vte: yes; screen, tmux,
# vt220, linux: no) or by an `Ms` terminfo capability. NO terminfo entry on this box
# carries Ms (`infocmp -1 <term> | grep Ms=` finds nothing anywhere), so on a seat
# whose outer TERM is not xterm-classified the clipboard is dead and stays silent.
# Measured pair (same fixture, tmux 3.5a): TERM=screen-256color emits 1 sequence
# WITH the SSOT's `terminal-overrides ',*:Ms=…'` line and 0 without it.
#
# MODES
#   --check (default)   report MISSING / SAME / DRIFTED vs the SSOT. A missing
#                       target exits 1 (nothing installed); a DRIFTED target is
#                       report-only unless --strict — the same exit-code contract as
#                       sync-skills.sh / sync-extensions.sh: the gate owns the
#                       decision to fail, a human run does not look like a failure.
#                       An INERT config fails even WITHOUT --strict: that is a
#                       defect, not a seat state.
#   --check --strict    exit 1 on drift, on an encoding violation, or on a config
#                       that is in place but NOT EFFECTIVE. Gate use (validate-all.sh).
#   --push              install SSOT -> ~/.tmux.conf (0600, timestamped backup).
#                       A target file this script cannot name (no managed-by marker)
#                       is a REFUSAL unless --force; it is never silently overwritten.
#   --reload            --push if needed, then `source-file` the LIVE server and
#                       verify it. Run this from inside the tmux session.
#   --verify            prove effectiveness. Two arms:
#                       sandbox probe  — loads the SSOT into a throwaway server on a
#                                        private socket (touches nothing live) and
#                                        reads the options back;
#                       live probe     — reads the RUNNING server's options +
#                                        `client_termfeatures` (needs an attached
#                                        client, i.e. run it from inside tmux).
#   --self-test         sandboxed canaries in a temp dir; asserts BOTH halves,
#                       including the one that matters: a byte-identical SSOT/target
#                       pair whose config is inert must still go RED.
#
# Env (sandbox hooks only — there is no other reason for them):
#   REPO          repo root, self-derived from this script's own path
#   TMUX_CONF_SRC SSOT path            (default $REPO/pi-agent/tmux/tmux.conf)
#   TMUX_CONF     target path          (default $HOME/.tmux.conf)
#   TMUX_SOCKET   probe socket name    (default homelab-tmux-probe-$$)
#
# Portability: bash, `$HOME`/self-derived paths only, no Windows idiom. Where tmux
# is absent (native Windows runner) the load/live arms SKIP with a printed reason —
# a SKIP is printed, never counted as a pass.
#
# Owning rule: docs/pi-harness.md §5b · CONVENTIONS §6 (repo = SSOT).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
SRC="${TMUX_CONF_SRC:-$REPO/pi-agent/tmux/tmux.conf}"
DEST="${TMUX_CONF:-$HOME/.tmux.conf}"
MARKER='managed-by: scripts/install-tmux-conf.sh'
PROBE_SOCK="${TMUX_SOCKET:-homelab-tmux-probe-$$}"

MODE="check"; STRICT=0; FORCE=0

err()  { printf 'install-tmux-conf: %s\n' "$*" >&2; }
info() { printf '  %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
usage: install-tmux-conf.sh [--check [--strict]] | --push [--force] | --reload | --verify | --self-test

  --check          (default) report SSOT pi-agent/tmux/tmux.conf vs ~/.tmux.conf
  --check --strict also exit 1 on drift OR on a config that is in place but ineffective
  --push           install SSOT -> ~/.tmux.conf (backup kept; a foreign file is a
                   REFUSAL unless --force)
  --force          with --push: allow replacing a file this script did not write
  --reload         push if needed + `source-file` the live server + verify it
  --verify         prove effectiveness (sandbox load probe + live server probe)
  --self-test     sandboxed canaries, incl. the inert-config canary that a diff
                   CANNOT catch
  --probe-emit    run ONLY the OSC 52 emission arm (the self-test's hook)
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)     MODE="check" ;;
    --strict)    STRICT=1 ;;
    --push)      MODE="push" ;;
    --force)     FORCE=1 ;;
    --reload)    MODE="reload" ;;
    --verify)    MODE="verify" ;;
    --self-test) MODE="selftest" ;;
    --probe-emit) MODE="probeemit" ;;
    --help|-h)   usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

[ -f "$SRC" ] || { err "no SSOT at $SRC — run from a homelab clone"; exit 1; }

# --- SSOT shape guards ------------------------------------------------------
# Text must be UTF-8, no BOM, LF (CRLF breaks tmux parsing of a quoted value and
# is a real cross-seat hazard; same guard as sync-skills.sh / sync-extensions.sh).
encoding_violation() {
  local p="$1" total strip
  [ -s "$p" ] || return 1
  total="$(wc -c < "$p")"
  strip="$(tr -d '\0' < "$p" | wc -c)"
  [ "$total" != "$strip" ] && return 1
  [ "$(head -c3 "$p" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "efbbbf" ] && return 0
  # -U/--binary is load-bearing on a Windows seat: Git-Bash's MSYS layer opens files in TEXT mode,
  # so a plain grep never sees the CR of a CRLF pair and this guard was silently blind there
  # (measured 2026-10-07; `-U` is a no-op on Debian, where no conversion exists to disable).
  LC_ALL=C grep -qU $'\r' "$p" 2>/dev/null && return 0
  return 1
}

# There is deliberately NO static "this looks like a bad block" rule. One was
# written first and then measured away: a block opened at end-of-line and closed on
# its own line loads FINE (fixture A) and so does a backslash continuation
# (fixture B), while the nested wrapped form does not (fixture F). No textual rule
# separates them without a parser, and a rule with false positives gets muted — the
# HD-417 lesson. The load probe below is the authority.

# --- load probe: does the file actually TAKE EFFECT? ------------------------
# Starts a throwaway server on a private socket with -f <conf> and reads the
# options back. On a mid-file error tmux leaves the DEFAULTS in place — every one of
# these reads back as its default, and that is the only reliable signal: the caller
# got exit 0 and empty stderr either way (a config failure is a client *message*, and
# a detached new-session has no client to print it to).
probe_load() {
  local conf="$1" sock="$2-l$RANDOM" fails=0 got
  have tmux || { info "SKIP: no tmux on PATH — load probe needs it"; return 2; }
  tmux -L "$sock" -f "$conf" new-session -d -s probe 'sleep 15' >/dev/null 2>&1 \
    || { err "load probe: could not start a throwaway tmux server"; return 1; }
  # shellcheck disable=SC2064
  trap "tmux -L '$sock' kill-server >/dev/null 2>&1 || true" RETURN

  got="$(tmux -L "$sock" show -g mouse 2>/dev/null | awk '{print $2}')"
  [ "$got" = "on" ] || { err "load probe: mouse is '$got' (SSOT says on) — the file did NOT take effect"; fails=$((fails+1)); }
  got="$(tmux -L "$sock" show -g history-limit 2>/dev/null | awk '{print $2}')"
  [ "${got:-0}" -ge 10000 ] 2>/dev/null \
    || { err "load probe: history-limit is '${got:-?}' (default 2000) — mid-file abort discarded the load"; fails=$((fails+1)); }
  got="$(tmux -L "$sock" show -g focus-events 2>/dev/null | awk '{print $2}')"
  [ "$got" = "on" ] || { err "load probe: focus-events is '$got'"; fails=$((fails+1)); }
  got="$(tmux -L "$sock" show -gw mode-keys 2>/dev/null | awk '{print $2}')"
  [ "$got" = "vi" ] || { err "load probe: mode-keys is '$got' (SSOT says vi)"; fails=$((fails+1)); }
  got="$(tmux -L "$sock" show -g terminal-overrides 2>/dev/null)"
  case "$got" in *Ms=*) ;; *) err "load probe: no Ms in terminal-overrides — OSC 52 stays silently disabled"; fails=$((fails+1));; esac
  got="$(tmux -L "$sock" show -s set-clipboard 2>/dev/null | awk '{print $2}')"
  case "$got" in on|external) ;; *) err "load probe: set-clipboard is '$got'"; fails=$((fails+1));; esac

  if [ "$fails" -eq 0 ]; then info "load probe       OK — the SSOT parses AND applies (mouse/history/focus/mode-keys/Ms/clipboard)"; fi
  # rc contract: 0 = effective, 1 = NOT effective, 2 = SKIP (no tmux). Callers must
  # not test `-eq 1` on a raw failure COUNT (two failed assertions would read as 2,
  # and 2 is also the SKIP code — that collision made the inert canaries pass).
  [ "$fails" -gt 0 ] && return 1
  return 0
}

# Does a copy-mode selection ACTUALLY leave this seat as an OSC 52 sequence on the
# wire? This is the only arm that proves the clipboard leg, and it is deliberately
# built to be able to fail: the probe client attaches with TERM=screen-256color, a
# terminal whose terminfo carries no Ms AND which tmux's built-in terminal-name
# table does not credit with a clipboard — so the sequence can appear ONLY because of
# the SSOT's `terminal-overrides` line. Measured pair on tmux 3.5a, same fixture:
#
#   TERM=screen-256color, SSOT as-is ............ 1 OSC 52 sequence
#   TERM=screen-256color, Ms override removed ... 0            <- canary 7
#
# Why not just read `client_termfeatures`? Its `clipboard` flag comes from that same
# name table (xterm*/vte yes, screen/tmux/vt220 no), so on this box it agreed with
# the wire in all three cases — but it is a belief about the terminal NAME, not about
# the capability, and it went false under this script's own feet: a probe client with
# TERM=tmux-256color reports no clipboard even though tmux emits OSC 52 for it. Read
# the bytes, not the guess.
probe_emit() {
  local conf="$1" sock="$2-e$RANDOM" cap rc=0
  have tmux   || { info "SKIP: no tmux — OSC 52 emission arm not run"; return 2; }
  have script || { info "SKIP: no script(1) (util-linux) — no pty, emission arm not run"; return 2; }
  cap="$(mktemp 2>/dev/null)" || { err "emit probe: mktemp failed"; return 1; }
  tmux -L "$sock" -f "$conf" new-session -d -s emit 'sleep 20' >/dev/null 2>&1 \
    || { err "emit probe: could not start a throwaway server"; rm -f "$cap"; return 1; }
  # shellcheck disable=SC2064
  trap "tmux -L '$sock' kill-server >/dev/null 2>&1 || true; rm -f '$cap'" RETURN
  # script(1) supplies the pty a tmux client requires; $TMUX must be unset or tmux
  # refuses to attach from inside another session ("sessions should be nested").
  setsid script -qec "env -u TMUX TERM=screen-256color tmux -L $sock attach -t emit" /dev/null > "$cap" 2>&1 &
  local i=0
  while [ "$i" -lt 20 ]; do
    tmux -L "$sock" list-clients -F '#{client_name}' 2>/dev/null | grep -q . && break
    i=$((i+1)); sleep 0.1
  done
  tmux -L "$sock" list-clients >/dev/null 2>&1 || { info "SKIP: probe client never attached — emission arm inconclusive"; return 2; }
  tmux -L "$sock" send-keys -t emit "printf 'aaa\\nbbb\\n'" Enter; sleep 0.4
  # A selection is required: `set-buffer` alone emits NOTHING (measured), so a probe
  # built on set-buffer would report a working clipboard that no user can reach.
  tmux -L "$sock" copy-mode -t emit 2>/dev/null
  tmux -L "$sock" send-keys -t emit -X begin-selection 2>/dev/null
  tmux -L "$sock" send-keys -t emit -X copy-selection-and-cancel 2>/dev/null
  sleep 0.8
  if grep -aq $'\033]52;' "$cap"; then
    info "OSC 52 arm       OK — a copy-mode selection left an OSC 52 sequence on the wire"
  else
    err "OSC 52 arm: NO OSC 52 sequence was emitted — the clipboard leg is dead on this configuration (check the terminal-overrides Ms entry)"
    rc=1
  fi
  return "$rc"
}

# --- live probe: the RUNNING server, read from inside the session -----------
probe_live() {
  have tmux || { info "SKIP: no tmux — live probe not run"; return 2; }
  tmux list-sessions >/dev/null 2>&1 || { info "SKIP: no running tmux server — live probe not run"; return 2; }
  local fails=0 got
  got="$(tmux show -g mouse 2>/dev/null | awk '{print $2}')"
  [ "$got" = "on" ] || { err "live: mouse is '$got' in the RUNNING session (a session option — 'source-file' sets the global; check 'tmux show -g mouse')"; fails=$((fails+1)); }
  got="$(tmux show -s set-clipboard 2>/dev/null | awk '{print $2}')"
  case "$got" in on|external) ;; *) err "live: set-clipboard is '$got'"; fails=$((fails+1));; esac
  got="$(tmux show -g terminal-overrides 2>/dev/null)"
  case "$got" in *Ms=*) ;; *) err "live: no Ms in terminal-overrides on the running server"; fails=$((fails+1));; esac
  # pi's own start-up check (HD-1112): it reads these two options back via `tmux show -gv`
  # whenever $TMUX is set, so THIS is the arm that says whether the warning the operator
  # sees is config or a stale server. An empty answer means tmux < 3.3 (no such option) —
  # reported, not failed, because pi stays silent there too and there is nothing to set.
  got="$(tmux show -gv extended-keys 2>/dev/null)"
  case "$got" in
    "")      info "live: this tmux has no extended-keys option (< 3.3) — pi will not warn about it either" ;;
    on|always) ;;
    *)       err "live: extended-keys is '$got' — pi warns 'Modified Enter keys may not work'; run --reload (the server keeps the OLD value until sourced)"; fails=$((fails+1)) ;;
  esac
  got="$(tmux show -gv extended-keys-format 2>/dev/null)"
  case "$got" in
    "")      ;;
    xterm)   err "live: extended-keys-format is xterm — pi wants csi-u and warns about it"; fails=$((fails+1)) ;;
  esac
  # Informational, deliberately NOT an assertion: this flag is tmux's belief about
  # the terminal NAME, not a capability read. --verify's OSC 52 arm is the proof.
  got="$(tmux display -p '#{client_termfeatures}' 2>/dev/null)"
  if [ -z "$got" ]; then
    info "live: no attached client visible — run this FROM INSIDE the tmux session to see its terminal"
  else
    info "live: client_termfeatures=$got  (name-table belief, not a capability read — see --verify's OSC 52 arm)"
  fi
  [ "$fails" -eq 0 ] && info "live probe         OK — the running server matches the SSOT intent"
  return "$fails"
}

# --- install ----------------------------------------------------------------
do_push() {
  local stamp
  encoding_violation "$SRC" && { err "refusing to deploy: CRLF/BOM in the SSOT $SRC"; return 1; }
  if [ -f "$DEST" ]; then
    if cmp -s "$SRC" "$DEST"; then info "in place and identical: $DEST"; return 0; fi
    stamp="$(date +%Y%m%d-%H%M%S)"
    if grep -qF "$MARKER" "$DEST" 2>/dev/null; then
      cp -p "$DEST" "$DEST.pre-tmux-$stamp" && info "backup kept: $DEST.pre-tmux-$stamp"
    elif [ "$FORCE" -eq 1 ]; then
      cp -p "$DEST" "$DEST.foreign-$stamp" && info "backup of the FOREIGN file kept: $DEST.foreign-$stamp"
    else
      err "REFUSAL: $DEST exists and was not written by this script (no '$MARKER' line)."
      # Name WHAT stands there. "An operator's own config" and "my own install from another layout"
      # are different decisions and rc 1 cannot tell them apart — measured on oldsrv 2026-10-09, where
      # the standing file's only difference from the SSOT was a header naming scripts/harness/… (a
      # lane mid-HD-1118-Stage-3), and the refusal said only "foreign", so the session had to diff it
      # by hand to find there was nothing to decide.
      found="$(grep -m1 'managed-by:' "$DEST" 2>/dev/null || true)"
      if [ -n "$found" ]; then
        err "  its own marker line: $found"
        err "  — a marker that differs from this script's own is an install made by another version"
        err "    or layout of this script, not an operator's file."
      else
        err "  it carries no managed-by: line at all — an operator's own config, or another tool's."
      fi
      changed="$(diff "$SRC" "$DEST" 2>/dev/null | grep -c '^[<>]')"
      real="$(diff "$SRC" "$DEST" 2>/dev/null | grep '^[<>]' | grep -cvE '^[<>][[:space:]]*(#|$)')"
      err "  content differs in ${changed:-?} line(s), ${real:-?} of them not comments."
      err "Diff it first, then re-run with --force to replace it (the foreign file is kept as .foreign-<stamp>)."
      return 1
    fi
  fi
  mkdir -p "$(dirname "$DEST")" 2>/dev/null || true
  install -m 600 "$SRC" "$DEST" 2>/dev/null || { cp "$SRC" "$DEST" && chmod 600 "$DEST"; } \
    || { err "could not write $DEST"; return 1; }
  info "installed $SRC -> $DEST (0600)"
  probe_load "$SRC" "$PROBE_SOCK"
}

do_check() {
  local rc=0 lp state
  info "SSOT   $SRC"
  info "target $DEST"
  if [ ! -f "$DEST" ]; then
    err "MISSING: no $DEST — run 'install-tmux-conf.sh --push'"
    rc=1; state="missing"
  elif cmp -s "$SRC" "$DEST"; then
    info "SAME: byte-identical to the SSOT"; state="identical"
  else
    err "DRIFT: $DEST differs from the repo SSOT — --push to deploy, or edit the SSOT (repo is the source of truth)"
    diff -u "$SRC" "$DEST" 2>/dev/null | head -20 | sed 's/^/    /' >&2
    state="drifted"; [ "$STRICT" -eq 1 ] && rc=1
  fi
  encoding_violation "$SRC" && { err "encoding violation in the SSOT (CRLF/BOM)"; rc=1; }
  grep -qF "$MARKER" "$SRC" || { err "SSOT lost its '$MARKER' line — installed files become unnameable"; rc=1; }
  # Always load-probe, in every mode: the byte-compare above cannot see an INERT
  # file, and ineffectiveness is a defect rather than a seat state, so it fails
  # without --strict too (and prints SKIP where tmux is absent, never a silent pass).
  probe_load "$SRC" "$PROBE_SOCK"; lp=$?
  case "$lp" in
    1) rc=1 ;;
    2) info "load probe SKIP — no tmux here, so effectiveness is UNPROVEN (not a pass)" ;;
  esac
  if [ "$rc" -eq 0 ] && [ "$state" = identical ]; then
    info "OK: seat tmux config == repo SSOT and effective"
  elif [ "$rc" -eq 0 ]; then
    info "reported, not failed: $state (add --strict for the gate form; effectiveness is always enforced)"
  fi
  return "$rc"
}

do_reload() {
  do_push || return 1
  if have tmux && tmux list-sessions >/dev/null 2>&1; then
    tmux source-file "$DEST" || { err "tmux source-file failed"; return 1; }
    info "sourced into the running server"
    probe_live || return 1
  else
    info "no running tmux server here — nothing to source (start one, then --verify)"
  fi
}

# --- self-test --------------------------------------------------------------
# Everything runs in a temp HOME against a sandbox SSOT; nothing here touches
# $HOME/.tmux.conf or a real server. Canary 5 is the point of this file.
self_test() {
  local tmp fails=0
  tmp="$(mktemp -d 2>/dev/null)" || { err "mktemp failed"; return 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  mk_sandbox() {  # $1 = root; SSOT + installed target, identical, EFFECTIVE
    mkdir -p "$1/repo/pi-agent/tmux"
    cp "$REPO/pi-agent/tmux/tmux.conf" "$1/repo/pi-agent/tmux/tmux.conf"
    cp "$1/repo/pi-agent/tmux/tmux.conf" "$1/tmux.conf"
  }
  run_at() { local root="$1"; shift
    REPO="$root/repo" TMUX_CONF="$root/tmux.conf" TMUX_SOCKET="hl-selftest-$$" \
      bash "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" "$@" >/dev/null 2>&1; }

  # 1. rest state -> GREEN.
  mk_sandbox "$tmp/rest"
  run_at "$tmp/rest" --check --strict && info "rest-state        GREEN" \
    || { err "canary: the SSOT itself does not pass its own gate"; fails=$((fails+1)); }

  # 2. missing target -> MUST fail.
  rm -f "$tmp/rest/tmux.conf"
  run_at "$tmp/rest" --check --strict && { err "canary passed: MISSING target stayed green"; fails=$((fails+1)); } \
    || info "missing-canary    caught"

  # 3. drifted target (a seat-side hand edit) -> MUST fail.
  mk_sandbox "$tmp/drift"; printf 'set -g mouse off\n' >> "$tmp/drift/tmux.conf"
  run_at "$tmp/drift" --check --strict && { err "canary passed: DRIFTED target stayed green"; fails=$((fails+1)); } \
    || info "drift-canary      caught"

  # 4a. --push onto a FOREIGN file -> REFUSAL.
  mk_sandbox "$tmp/foreign"; printf '# hand-made by an operator\nset -g mouse off\n' > "$tmp/foreign/tmux.conf"
  run_at "$tmp/foreign" --push && { err "canary passed: --push clobbered a foreign file"; fails=$((fails+1)); } \
    || info "foreign-refusal   caught"

  # 4a2. the file carries a DIFFERENT managed-by: line — an install by another layout of this very
  #      script (the oldsrv state of 2026-10-09). Still a REFUSAL, but the message must NAME the
  #      marker it found and say how far apart the two files are; rc 1 alone cannot make that call.
  mk_sandbox "$tmp/marker"
  sed '1s|.*|# managed-by: pi-agent/tmux/tmux.conf (installed by scripts/harness/install-tmux-conf.sh)|' \
      "$REPO/pi-agent/tmux/tmux.conf" > "$tmp/marker/tmux.conf"
  mout="$(REPO="$tmp/marker/repo" TMUX_CONF="$tmp/marker/tmux.conf" TMUX_SOCKET="hl-selftest-$$" \
          bash "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" --push 2>&1)" && mrc=0 || mrc=$?
  if [ "$mrc" -ne 0 ] && printf '%s' "$mout" | grep -q REFUSAL \
     && printf '%s' "$mout" | grep -q 'its own marker line: ' \
     && grep -q 'scripts/harness/install-tmux-conf.sh' "$tmp/marker/tmux.conf"; then
    info "marker-provenance GREEN (refusal names the marker found; nothing overwritten)"
  else err "canary: the refusal did not name the foreign marker, or it overwrote the file"; fails=$((fails+1)); fi
  # 4b. --force replaces it and keeps a backup.
  #     The replacement itself is provable everywhere, so assert it with `cmp` instead of trusting
  #     the exit code alone: `--push` ENDS in the load probe, which returns 2 (SKIP, see `have tmux`
  #     above) on a host with no tmux — counted here as a failure, this self-test reported
  #     "canary: --push --force failed" on the Win11 seat (measured 2026-10-07) while the install had
  #     in fact succeeded. A host boundary read as a broken invariant is how a gate gets muted.
  rc=0; run_at "$tmp/foreign" --push --force || rc=$?
  cmp -s "$REPO/pi-agent/tmux/tmux.conf" "$tmp/foreign/tmux.conf" \
    && info "foreign-force     replaced (SSOT == target, byte-exact)" \
    || { err "canary: --push --force did NOT replace the foreign file"; fails=$((fails+1)); }
  [ "$rc" -eq 0 ] && info "foreign-probe     GREEN" \
    || { have tmux && { err "canary: --push --force failed (rc $rc)"; fails=$((fails+1)); }; \
         info "foreign-probe     SKIP (no tmux) — install ran, the load probe cannot"; }
  ls "$tmp/foreign"/tmux.conf.foreign-* >/dev/null 2>&1 \
    && info "foreign-backup    kept" || { err "canary: --force kept no backup"; fails=$((fails+1)); }

  # 5. THE INERT-CONFIG CANARIES — the point of this file. In both arms the SSOT and
  #    the installed target are BYTE-IDENTICAL (a `diff` says SAME, an install says
  #    done), while tmux leaves every option at its DEFAULT. Both shapes were
  #    measured on tmux 3.5a; the same SSOT without the appended line is GREEN
  #    (canary 1), so the red can only come from that line. See docs/pi-harness.md §5b.
  inert_case() {  # $1 = label, $2 = sandbox root holding ./conf as the fixture
    mkdir -p "$2/repo/pi-agent/tmux"; cp "$2/conf" "$2/repo/pi-agent/tmux/tmux.conf"
    cp "$2/conf" "$2/tmux.conf"
    cmp -s "$2/conf" "$2/tmux.conf" \
      || { err "canary '$1': fixture not byte-identical — it would prove nothing"; fails=$((fails+1)); return; }
    if have tmux; then
      run_at "$2" --check --strict \
        && { err "canary passed: '$1' identical-but-INERT config stayed green"; fails=$((fails+1)); } \
        || info "inert-$1  caught (a cmp/diff would have said SAME)"
    else
      info "inert-$1  SKIP (no tmux) — the load probe needs a tmux binary"
    fi
  }

  # 5a. one bad command mid-file (measured: mouse off, history-limit 2000).
  mkdir -p "$tmp/badcmd"
  { cat "$REPO/pi-agent/tmux/tmux.conf"; printf 'select-pane -t = extra extra extra\n'; } > "$tmp/badcmd/conf"
  inert_case "badcmd" "$tmp/badcmd"

  # 5b. the nested wrapped if-shell — the shape that broke the LIVE seat while the
  #     file on disk was correct (measured INERT; a plain wrapped block and a plain
  #     backslash continuation are both EFFECTIVE, which is why no static rule here).
  mkdir -p "$tmp/wrapped"
  {
    cat "$REPO/pi-agent/tmux/tmux.conf"
    cat <<'EOS'
bind -T root WheelUpPane \
  if-shell -F "#{||:#{pane_in_mode},#{mouse_any_flag}}" { send-keys -M } { \
    if-shell -F "#{alternate_on}" { send-keys -X page-up } \
      { select-pane -t = \; copy-mode -e \; send-keys -M } }
EOS
  } > "$tmp/wrapped/conf"
  inert_case "wrapped" "$tmp/wrapped"

  # 6b. THE Ms CANARY. Same fixture, the terminal-overrides line removed: the OSC 52
  #     arm must go RED. Without this arm the emission probe could be passing because
  #     it emits for the wrong reason (its TERM is chosen so that ONLY the override
  #     can earn the sequence — measured 1 vs 0, see docs/pi-harness.md §5b).
  sed "s/^set -g terminal-overrides.*$/# Ms override removed (canary)/" \
    "$REPO/pi-agent/tmux/tmux.conf" > "$tmp/noms.conf"
  grep -q '^# Ms override removed' "$tmp/noms.conf" \
    && ! grep -q 'Ms=' "$tmp/noms.conf" \
    || { err "canary fixture did not remove the Ms override — it would prove nothing"; fails=$((fails+1)); }
  if have tmux && have script; then
    REPO_TMP="$tmp/noms.conf"
    TMUX_CONF_SRC="$tmp/noms.conf" TMUX_SOCKET="hl-selftest-noms-$$" \
      bash "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" --probe-emit >/dev/null 2>&1 \
      && { err "canary passed: OSC 52 emitted with NO Ms override — the arm proves nothing"; fails=$((fails+1)); } \
      || info "noms-canary     caught (no OSC 52 without the override)"
  else
    info "noms-canary     SKIP (no tmux/script) — emission arm unproven on this host"
  fi

  # 6c. clipboard-intent canary: set-clipboard off must fail WITHOUT needing a pty.
  sed 's/^set -s  set-clipboard on/set -s set-clipboard off/; s/^set -s set-clipboard on/set -s set-clipboard off/' \
    "$REPO/pi-agent/tmux/tmux.conf" > "$tmp/noclip.conf"
  grep -q '^set -s set-clipboard off$' "$tmp/noclip.conf" \
    || { err "canary fixture did not flip set-clipboard — it would prove nothing"; fails=$((fails+1)); }
  mkdir -p "$tmp/noclip/repo/pi-agent/tmux"; cp "$tmp/noclip.conf" "$tmp/noclip/repo/pi-agent/tmux/tmux.conf"
  cp "$tmp/noclip.conf" "$tmp/noclip/tmux.conf"
  if have tmux; then
    run_at "$tmp/noclip" --check --strict && { err "canary passed: set-clipboard off stayed green"; fails=$((fails+1)); } \
      || info "noclip-canary     caught"
  else
    info "noclip-canary     SKIP (no tmux)"
  fi

  printf '\nself-test: %s\n' "$([ "$fails" -eq 0 ] && echo "OK — all canaries caught" || echo "$fails canary/canaries NOT caught")"
  return "$fails"
}

# ================================ dispatch ======================================
case "$MODE" in
  selftest) self_test; exit $? ;;
  probeemit) probe_emit "$SRC" "$PROBE_SOCK"; exit $? ;;
  check)    do_check; exit $? ;;
  push)     do_push; exit $? ;;
  reload)   do_reload; exit $? ;;
  verify)
    rc=0 skipped=0
    # rc 2 means SKIP. A skipped arm is never a pass, so it is counted and printed;
    # rc 1 is a real failure.
    for arm in "probe_load $SRC $PROBE_SOCK" "probe_emit $SRC $PROBE_SOCK" "probe_live"; do
      # shellcheck disable=SC2086
      $arm; r=$?
      [ "$r" -eq 1 ] && rc=1
      [ "$r" -eq 2 ] && skipped=$((skipped+1))
    done
    [ "$skipped" -gt 0 ] && info "NOTE: $skipped arm(s) SKIPPED above — effectiveness is partially UNPROVEN, not proven"
    [ "$rc" -eq 0 ] && info "verify OK — the config parses, applies, and a selection really leaves an OSC 52 sequence on the wire"
    exit "$rc" ;;
esac
