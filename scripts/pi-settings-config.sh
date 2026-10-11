#!/usr/bin/env bash
# =====================================================================
# pi-settings-config.sh — the settings plane of the pi seats: merge the repo-owned
#   keys into ~/.pi/agent/settings.json on the seat that runs it (HD-1110).
#
# WHAT THIS SYNCS, AND WHAT IT MUST NOT
# -------------------------------------
# Three seats run this harness (Win11, WSL Debian, the oldsrv cockpit) and until
# 2026-10-08 the only way their `settings.json` agreed was a session remembering to edit
# each one — docs/pi-harness.md §5 WAS the SSOT (a doc block, hand-copied). Owner ruling
# 2026-10-08: the harness keys become a repo file and a script, so a new seat starts
# correct. Fleet driver: scripts/pi-seat-sync.sh.
#
# The keys are §5's block + `theme` (§5's table: all three seats read `dark`, and absence
# is not neutral — it selects pi's `system` theme, which paints from the terminal's own
# palette). `packages` is COMPOSED here rather than typed: the version of every entry is
# the pin in group_vars/all/versions.yml (§7), so a seat can only end up on a different
# pi-open-tui than the fleet if the pin moved.
#
# Keys NOT owned, deliberately: `externalEditor`, `lastChangelogVersion`, `tuiMode` and
# the rest of the workstation state (pi writes lastChangelogVersion itself). §5's sentence
# "the block above is the part that must match" is still the rule — this script enforces it
# instead of restating it. A seat-local `packages` entry the repo does not name is KEPT and
# printed (`seat-local …, kept`): the cockpit's pi-web belongs to roles/seat, and deleting a
# seat's package from a sync would be data loss dressed up as hygiene.
#
# MODES
#   --check (default)  OK / DRIFT (names the keys) / MISSING / INVALID. MISSING and INVALID
#                      exit 1; a DRIFT is report-only unless --strict — the same contract as
#                      sync-extensions.sh / pi-tui-config.sh.
#   --check --strict   exit 1 on a drift too (gate use; validate-all.sh item 31).
#   --push             write the owned keys + the composed packages, keep every other key,
#                      keep a timestamped backup. An UNPARSEABLE file is a REFUSAL.
#   --self-test        sandboxed canaries; asserts both halves of every rule above.
#   --with-package S   add one package source to the owned set for THIS seat (repeatable) —
#                      seat placement (e.g. the cockpit's pi-web), not a fleet key.
#
# Exit codes: 0 OK / repaired · 1 drift(strict), missing, invalid, refusal ·
#             2 SKIP — no usable node, so nothing was read (a SKIP is never a pass).
#
# Env (sandbox hooks only): REPO, PI_SETTINGS (default $HOME/.pi/agent/settings.json),
# PI_NODE (which node — the oldsrv seat runs this over `ssh seat '…'`, a NON-interactive
# non-login shell that reads no profile, so PATH may not carry node: HD-446).
#
# Owning rule: docs/pi-harness.md §5 · CONVENTIONS §6 (repo = SSOT) · §7 (pins).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
SSOT="$REPO/pi-agent/settings-ssot.json"
CONF="${PI_SETTINGS:-$HOME/.pi/agent/settings.json}"
VERSIONS="$REPO/IaC/ansible/group_vars/all/versions.yml"

MODE="check"; STRICT=0
EXTRA_PKGS=()

err()  { printf 'pi-settings-config: %s\n' "$*" >&2; }
info() { printf '  %s\n' "$*"; }

usage() {
  cat <<'EOF'
usage: pi-settings-config.sh [--check [--strict] | --push] [--with-package SRC] [--self-test]

  --check            (default) compare ~/.pi/agent/settings.json against pi-agent/settings-ssot.json
  --check --strict   exit 1 on a drift too (gate use)
  --push             merge the repo-owned keys in; keep every other key; backup kept
  --with-package SRC add a package source for this seat (repeatable; the version of a
                     FLEET package comes from the versions.yml pin, not from here)
  --self-test        sandboxed canaries (temp files; never touches ~/.pi)
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)        MODE="check" ;;
    --strict)       STRICT=1 ;;
    --push)         MODE="push" ;;
    --self-test)    MODE="selftest" ;;
    --with-package) shift; [ $# -gt 0 ] || { err "--with-package needs a source"; exit 2; }; EXTRA_PKGS+=("$1") ;;
    --help|-h)      usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

[ -f "$SSOT" ] || { err "no settings SSOT at $SSOT — run from a homelab clone"; exit 1; }

# pin(): one pin from the SSOT version file; a missing pin aborts (§7, no inline default).
# FORK-FREE, and the four processes this used to spawn per call are what the pi-harness legs paid
# for. The old body was `grep|head|sed|tr` — FOUR EXECs — and pi-settings-config composes PKG_BASE
# from eight of them AT START-UP: 32 process spawns before it reads a single seat, ~1.3 s of pure
# process creation per invocation on the Win11 git-bash seat (one such pipeline measured 180 ms there,
# 0.66 ms per spawn on WSL Debian of the same laptop). Interleaved A/B, same tree, quiet host: that
# script's `--check` 1.51 s -> 0.40 s and its self-test 24.1 s -> 6.9 s. One read of the file plus an
# associative cache answers every pin at builtin speed, with the SAME parse the sed did: value after
# the first colon, optional opening quote, stop at the first `"` or `#` (whichever comes first),
# whitespace removed — verified against the old pipeline over all 118 keys in versions.yml, and the
# fail-loud path (missing key, mapping-valued key) proven to still abort.
# `pin_of` is the zero-fork form: it sets $PIN instead of being command-substituted.
declare -A PIN_CACHE=()
PIN_LOADED=0
# _pin_load parses versions.yml ONCE per process into the cache. Why a loop and not a search:
# `${BIG#*"$pat"}` (prefix removal with a LEADING WILDCARD) is not a substring search in bash — it
# retries the match at every prefix length, and each retry is itself a scan, so on this 49 KB file it
# measured 1.3 s per lookup for a key near the end of the file and 0.2 s near the top (position-
# proportional = quadratic). A one-pass `IFS=: read` over the same file is a few milliseconds, and it
# splits at the FIRST colon with no wildcard: column-0 `key:` rows only, comments and indented (nested)
# rows skipped — exactly what `grep -E "^key:"` saw.
pin_of() {
  local k="$1" v
  [ "$PIN_LOADED" = 1 ] || { _pin_load; PIN_LOADED=1; }
  v="${PIN_CACHE[$k]-}"
  [ -n "$v" ] || { err "pin '$k' missing from IaC/ansible/group_vars/all/versions.yml — add it there, do not hardcode it here"; exit 1; }
  PIN="$v"
}
_pin_load() {
  local k rest a b line src
  # NOTE the two-step read: `<<< "$(<file 2>/dev/null)"` yields NOTHING — the `$(<…)` special form
  # does not accept an extra redirection, it just becomes an empty command. Read it plainly first.
  src=""
  [ -r "$VERSIONS" ] && src="$(<"$VERSIONS")"
  while IFS=: read -r k rest; do
    case "$k" in ''|\#*|' '|"$'\t'"*|*[!A-Za-z0-9_]*) continue ;; esac
    line="${rest#"${rest%%[![:space:]]*}"}"        # ltrim
    line="${line#\"}"                              # optional opening quote
    a="$line"; b="$line"
    case "$a" in *\"*) a="${a%%\"*}" ;; esac
    case "$b" in *#*)  b="${b%%#*}" ;; esac
    [ "${#b}" -lt "${#a}" ] && a="$b"              # keep whichever truncation is SHORTER
    PIN_CACHE[$k]="${a//[[:space:]]/}"             # also strips a CR from a CRLF checkout, as tr did
  done <<< "$src$'\n'"                            # trailing sentinel: never drop an unterminated last row
}
pin() { pin_of "$1"; printf '%s' "$PIN"; }

# The packages the harness owns: NAME here, VERSION from the pin (§7). pi-web-access is the
# web-tool leg every seat should have, pi-open-tui the TUI/footer leg (docs/pi-harness.md §5a),
# and the last pair is the agent-work set — the subagent extension the lane workflow runs on and
# the DeepSeek tuning. Those two were `seat-local, kept` until 2026-10-09: named in exactly one
# executable line (`install-pi-wsl.sh`, unversioned) they were never converged and never pinned
# (HD-1118 Stage 2).
PKG_BASE=()
# pin_of, not `$(pin …)`: a command substitution FORKS, and this block used to fork eight times (and
# exec thirty-two) before the script had read anything. See pin_of above.
pin_of pi_web_access_version;          PKG_BASE+=("npm:pi-web-access@$PIN")
pin_of pi_host_tui_npm_package;   _t="$PIN"; pin_of pi_host_tui_npm_version;   PKG_BASE+=("npm:$_t@$PIN")
pin_of pi_host_subagents_npm_package; _s="$PIN"; pin_of pi_host_subagents_npm_version; PKG_BASE+=("npm:$_s@$PIN")
pin_of pi_host_deepseek_npm_package;  _d="$PIN"; pin_of pi_host_deepseek_npm_version;  PKG_BASE+=("npm:$_d@$PIN")
unset _t _s _d

# node: pi's own shebang is `#!/usr/bin/env node`, so a seat always HAS node — but a
# non-interactive non-login shell on the Debian seat reads no profile, so PATH may not
# carry it (HD-446). Look for the pinned seat prefix BEFORE PATH.
NODE="${PI_NODE:-}"
if [ -z "$NODE" ]; then
  for c in "$HOME/.local/share/pi-node/current/bin/node" "$(command -v node 2>/dev/null || true)" "$(command -v node.exe 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] && { NODE="$c"; break; }
  done
fi
require_node() {
  if [ -z "$NODE" ] || ! "$NODE" -e 'process.exit(0)' >/dev/null 2>&1; then
    info "SKIP: no usable node (looked for '${NODE:-none}') — $CONF was NOT read; a SKIP is not a pass"
    return 2
  fi
  return 0
}

# --- the compare / the write (ONE node program, two actions) ------------------
# Two lines on stdout:
#   STATE<TAB>detail      ok | drift | changed | missing | invalid   (detail = key names)
#   SEATLOCAL<TAB>names   packages the seat carries that the repo does not name (kept)
# A report NAMES the drifted keys instead of dumping someone's editor settings into a
# terminal. One invocation, one effect.
run_node() {
  local action="$1"
  "$NODE" -e '
    const fs = require("fs");
    const [ssotPath, confPath, action, ...pkgs] = process.argv.slice(1);
    const ssot = JSON.parse(fs.readFileSync(ssotPath, "utf8"));
    const owned = Object.keys(ssot).filter((k) => !k.startsWith("_"));
    const isObj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
    const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);

    // Package identity = the npm package NAME, so a seat entry `npm:pi-open-tui@0.3.9` and
    // the owned entry `npm:pi-open-tui@0.3.11` are the SAME package (the pin wins), while an
    // entry naming a package the repo does not carry is seat-local and is KEPT.
    const nameOf = (p) => {
      const src = typeof p === "string" ? p : (p && p.source) || "";
      const m = /^((?:@[^/]+\/)?[^@/]+)/.exec(src.replace(/^(?:npm:|git:|https?:\/\/)/, ""));
      return m ? m[1] : src;
    };
    const ownedNames = new Set(pkgs.map(nameOf));
    const seatLocal = (have) => have.filter((p) => !ownedNames.has(nameOf(p)));
    const names = (list) => list.map((p) => (typeof p === "string" ? p : p.source)).join(",");
    const report = (state, detail, have) => {
      console.log(state + "\t" + (detail || ""));
      console.log("SEATLOCAL\t" + names(seatLocal(have)));
    };

    if (!fs.existsSync(confPath)) { report("missing", "", []); process.exit(0); }
    let cur;
    try { cur = JSON.parse(fs.readFileSync(confPath, "utf8")); }
    catch { report("invalid", "", []); process.exit(0); }
    if (!isObj(cur)) { report("invalid", "", []); process.exit(0); }
    const have = Array.isArray(cur.packages) ? cur.packages : [];

    const bad = owned.filter((k) => !eq(cur[k], ssot[k]));
    // A package is only OK when the seat carries the OWNED source byte-for-byte: a seat on
    // an older version of the same package is drift, and the pin wins (docs/pi-harness.md §1).
    const badPkgs = pkgs.filter((src) => !have.some((h) => nameOf(h) === nameOf(src) && eq(h, src)));
    const detail = [...bad, ...(badPkgs.length ? ["packages"] : [])].join(",");

    if (action === "check") { report(detail ? "drift" : "ok", detail, have); process.exit(0); }

    const out = { ...cur };
    for (const k of owned) out[k] = ssot[k];
    out.packages = [...pkgs, ...seatLocal(have)];      // owned first, seat-local preserved after
    if (eq(cur, out)) { report("ok", "", have); process.exit(0); }
    fs.writeFileSync(confPath, JSON.stringify(out, null, 2) + "\n", "utf8");
    report("changed", detail, have);
  ' "$SSOT" "$CONF" "$action" "${PKG_BASE[@]}" ${EXTRA_PKGS[@]+"${EXTRA_PKGS[@]}"}
}

# A missing file is written from the SSOT + the composed packages, nothing else.
write_from_scratch() {
  "$NODE" -e '
    const fs = require("fs");
    const [ssotPath, confPath, ...pkgs] = process.argv.slice(1);
    const ssot = JSON.parse(fs.readFileSync(ssotPath, "utf8"));
    const out = {};
    for (const k of Object.keys(ssot)) if (!k.startsWith("_")) out[k] = ssot[k];
    out.packages = pkgs;
    fs.writeFileSync(confPath, JSON.stringify(out, null, 2) + "\n", "utf8");
  ' "$SSOT" "$CONF" "${PKG_BASE[@]}" ${EXTRA_PKGS[@]+"${EXTRA_PKGS[@]}"}
}

# run_node -> STATE / DETAIL / SEATLOCAL
# Split in the SHELL: three `printf '%s\n' "$out" | sed -n …` pipelines were SIX EXECs per invoke,
# and do_push invokes twice (the post-write re-check is the proof, not a formality).
invoke() {
  local out l1 l2
  out="$(run_node "$1")"
  l1="${out%%$'\n'*}"; l2="${out#*"$'\n'"}"; l2="${l2%%$'\n'*}"
  STATE="${l1%%$'\t'*}"
  DETAIL="${l1#*$'\t'}"; [ "$DETAIL" = "$l1" ] && DETAIL=""
  SEATLOCAL="${l2#SEATLOCAL$'\t'}"; [ "$SEATLOCAL" = "$l2" ] && SEATLOCAL=""
}

do_check() {
  require_node || return $?
  invoke check
  case "$STATE" in
    ok)
      info "OK: $CONF carries every repo-owned key of pi-agent/settings-ssot.json"
      [ -n "$SEATLOCAL" ] && info "seat-local package(s), kept by design: $SEATLOCAL"
      return 0 ;;
    drift)
      err "DRIFT: these keys differ from pi-agent/settings-ssot.json: $DETAIL"
      [ -n "$SEATLOCAL" ] && info "seat-local package(s), kept by design: $SEATLOCAL"
      [ "$STRICT" -eq 1 ] && return 1
      info "reported, not failed (add --strict for the gate form; --push converges)"; return 0 ;;
    missing) err "MISSING: no $CONF — the seat has no harness settings (run --push, or an install-pi-*.sh)" >&2; return 1 ;;
    *)       err "INVALID: $CONF is not parseable JSON — fix it by hand; this script will not rewrite a file it cannot read"; return 1 ;;
  esac
}

do_push() {
  require_node || return $?
  local stamp
  invoke push
  case "$STATE" in
    ok)
      info "in place: every repo-owned key matches ($CONF)"
      [ -n "$SEATLOCAL" ] && info "seat-local package(s), kept: $SEATLOCAL"
      return 0 ;;
    invalid) err "REFUSAL: $CONF does not parse — refusing to overwrite it"; return 1 ;;
    missing) mkdir -p "$(dirname "$CONF")" 2>/dev/null || true
             write_from_scratch || { err "could not write $CONF"; return 1; }
             info "created $CONF from pi-agent/settings-ssot.json"; return 0 ;;
  esac
  # a write happened: keep the pre-change file nameable
  stamp="$(date +%Y%m%d-%H%M%S)"
  cp -p "$CONF" "$CONF.pre-pi-settings-$stamp" 2>/dev/null || true
  invoke check
  [ "$STATE" = ok ] || { err "wrote $CONF but the keys still read '$STATE' ($DETAIL)"; return 1; }
  info "merged the repo-owned keys into $CONF (backup: $(basename "$CONF").pre-pi-settings-$stamp)"
  [ -n "$SEATLOCAL" ] && info "seat-local package(s), kept: $SEATLOCAL"
  return 0
}

# --- self-test ---------------------------------------------------------------
self_test() {
  local tmp fails=0 SEAT_EXTRA self jv
  tmp="$(mktemp -d 2>/dev/null)" || { err "mktemp failed"; return 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  self="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"     # ONE fork for the leg, not one per canary
  run_at() { local f="$1"; shift
    PI_SETTINGS="$f" bash "$self" "$@" >/dev/null 2>&1; }
  # json_val FILE KEY  (flat key only — the self-test never needs a nested path)
  json_val() { "$NODE" -e 'const c=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(JSON.stringify(c[process.argv[2]]))' "$1" "$2"; }
  poke()     { "$NODE" -e 'const fs=require("fs");const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));eval(process.argv[3]);fs.writeFileSync(process.argv[1],JSON.stringify(c,null,2)+"\n")' "$1" "" "$2"; }
  # has <text> <token> — substring test with no PIPELINE: `json_val … | grep -q` paid the node run AND
  # two forks to answer a question `case` answers for free.
  has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

  require_node || { err "self-test needs node — it cannot prove anything without it"; return 1; }
  SEAT_EXTRA="npm:@ygncode/pi-web"

  # A compliant seat file: every SSOT key + workstation keys + a seat-local package. The owned
  # package list comes from PKG_BASE itself and is NEVER restated here — a fixture that names the
  # packages by hand turns red the day the owned set grows, and a red self-test whose real meaning
  # is "the set changed" teaches nobody to update the fixture.
  mk_seat() {
    "$NODE" -e '
      const fs = require("fs");
      const [ssotPath, seatExtra, outPath, ...owned] = process.argv.slice(1);
      const s = JSON.parse(fs.readFileSync(ssotPath, "utf8"));
      s.lastChangelogVersion = "1.1.0";
      s.externalEditor = "notepad.exe -multiInst";
      s.packages = [...owned, seatExtra];
      fs.writeFileSync(outPath, JSON.stringify(s, null, 2) + "\n", "utf8");
    ' "$SSOT" "$SEAT_EXTRA" "$1" "${PKG_BASE[@]}"
  }
  mk_seat "$tmp/rest.json"

  # 1. rest -> GREEN, and --push is a byte-exact no-op (no churn on every seat run).
  if run_at "$tmp/rest.json" --check --strict; then info "rest-state       GREEN"; else err "canary: a compliant seat file failed its own check"; fails=$((fails+1)); fi
  cp "$tmp/rest.json" "$tmp/rest.before"; run_at "$tmp/rest.json" --push
  if cmp -s "$tmp/rest.before" "$tmp/rest.json"; then info "push-idempotent  GREEN (byte-exact no-op)"; else err "canary: --push rewrote a compliant file"; fails=$((fails+1)); fi

  # 2. a harness key off — the exact failure this exists for (one seat thinking at `medium`,
  #    the HD-484/493 finding) -> strict RED, and --push fixes ONLY that key.
  poke "$tmp/rest.json" 'c.defaultThinkingLevel="medium"'
  if run_at "$tmp/rest.json" --check --strict; then err "canary passed: a drifted harness key stayed green"; fails=$((fails+1)); else info "key-drift        caught"; fi
  if run_at "$tmp/rest.json" --check; then info "report-only      GREEN (drift does not fail a human run)"; else err "canary: --check without --strict failed a report-only state"; fails=$((fails+1)); fi
  run_at "$tmp/rest.json" --push
  if [ "$(json_val "$tmp/rest.json" defaultThinkingLevel)" = '"high"' ]; then info "key-repair       GREEN"; else err "canary: --push did not repair defaultThinkingLevel"; fails=$((fails+1)); fi
  if [ "$(json_val "$tmp/rest.json" externalEditor)" = '"notepad.exe -multiInst"' ]; then info "workstation-keys GREEN (externalEditor untouched)"; else err "canary: --push clobbered a workstation key"; fails=$((fails+1)); fi

  # 3. the seat carries the same package at an older version -> RED (the pin wins), --push repins.
  pin_of pi_host_tui_npm_package;          local tp="$PIN"
  pin_of pi_host_tui_npm_version;          local tv="$PIN"
  pin_of pi_host_subagents_npm_package;    local sp="$PIN"
  pin_of pi_host_subagents_npm_version;    local sv="$PIN"
  poke "$tmp/rest.json" 'c.packages=c.packages.map(p=>String(p).startsWith("npm:pi-open-tui")?"npm:pi-open-tui@0.0.1":p)'
  if run_at "$tmp/rest.json" --check --strict; then err "canary passed: a stale package pin stayed green"; fails=$((fails+1)); else info "package-pin      caught"; fi
  run_at "$tmp/rest.json" --push
  jv="$(json_val "$tmp/rest.json" packages)"
  if has "$jv" "pi-open-tui@$tv"; then info "package-repin    GREEN"; else err "canary: --push did not repin the package"; fails=$((fails+1)); fi

  # 4. a seat-local package (the cockpit pi-web) survives every write.
  if has "$jv" "@ygncode/pi-web"; then info "seat-local-kept  GREEN (cockpit pi-web survived)"; else err "canary: --push deleted a seat-local package"; fails=$((fails+1)); fi

  # 4b. an OWNED package the seat does not carry at all — the class the owned set grew to close
  #     (pi-subagents / pi-deepseek-optimized were seat-local until 2026-10-09, so whichever seat
  #     ran `pi install` last was the only seat that had them, and no version was recorded
  #     anywhere) -> strict RED, and --push brings it back AT THE PIN without touching pi-web.
  poke "$tmp/rest.json" 'c.packages=c.packages.filter(p=>!String(p).startsWith("npm:'"$sp"'@"))'
  if run_at "$tmp/rest.json" --check --strict; then err "canary passed: a missing owned package stayed green"; fails=$((fails+1)); else info "pkg-absent       caught"; fi
  run_at "$tmp/rest.json" --push
  jv="$(json_val "$tmp/rest.json" packages)"
  if has "$jv" "$sp@$sv"; then info "pkg-restored     GREEN (owned package back at its pin)"; else err "canary: --push did not restore the missing owned package"; fails=$((fails+1)); fi
  if has "$jv" "@ygncode/pi-web"; then info "seat-local-again GREEN"; else err "canary: restoring an owned package deleted the seat-local one"; fails=$((fails+1)); fi

  # 5. missing file -> strict RED; --push creates it WITH the pinned packages.
  if run_at "$tmp/none.json" --check --strict; then err "canary passed: MISSING settings stayed green"; fails=$((fails+1)); else info "missing-canary   caught"; fi
  if ! run_at "$tmp/none.json" --push; then err "canary: --push created no file"; fails=$((fails+1)); fi
  jv="$(json_val "$tmp/none.json" packages)"
  if has "$jv" "pi-open-tui@$tv"; then info "missing-create   GREEN (created with the pinned packages)"; else err "canary: the created file carries no pinned packages"; fails=$((fails+1)); fi

  # 6. unparseable -> RED, and a REFUSAL that leaves the bytes alone.
  printf '{ "defaultModel": , }\n' > "$tmp/bad.json"; cp "$tmp/bad.json" "$tmp/bad.before"
  if run_at "$tmp/bad.json" --check --strict; then err "canary passed: unparseable settings stayed green"; fails=$((fails+1)); else info "invalid-canary   caught"; fi
  if run_at "$tmp/bad.json" --push; then err "canary passed: --push overwrote an unparseable file"; fails=$((fails+1)); else info "refusal-canary   caught"; fi
  if cmp -s "$tmp/bad.before" "$tmp/bad.json"; then info "file-untouched   GREEN"; else err "canary: a REFUSAL still modified the file"; fails=$((fails+1)); fi

  # 7. no usable node -> rc 2 SKIP, never a pass.
  rc=0
  PI_NODE="$tmp/there-is-no-such-node" PI_SETTINGS="$tmp/rest.json" \
    bash "$self" --check --strict >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ]; then info "skip-arm         GREEN (rc 2 = SKIP, not a pass)"; else err "canary: the no-node path returned $rc — a SKIP must be 2"; fails=$((fails+1)); fi

  printf '\nself-test: %s\n' "$([ "$fails" -eq 0 ] && echo "OK — all canaries caught" || echo "$fails canary/canaries NOT caught")"
  return "$fails"
}

# ================================ dispatch ======================================
case "$MODE" in
  selftest) self_test; exit $? ;;
  check)    do_check; exit $? ;;
  push)     do_push; exit $? ;;
esac
