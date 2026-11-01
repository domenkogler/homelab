#!/usr/bin/env bash
# =====================================================================
# gate/check-leg-contract.sh — the WSL door's LEG CONTRACT, checked on this tree.
# ---------------------------------------------------------------------
# WHY THIS EXISTS. `lib/wsl-route.sh` decides which engine runs a leg, and its header states the
# conjunction a crossing leg must satisfy — one half of which is that the leg needs no tool the Debian
# engine lacks. A conjunction nobody can read per leg is prose: a wrapped leg that shells out to an
# engine-side tool that is not there simply JUDGES LESS and comes back rc 0, because `hl_wsl_route`
# passes the far exit code straight through. Two things close that hole — the leg's own claim
# (`hl_wsl_needs <tool>…`) and the run's inventory (`engine tools: answered — … · ABSENT — …`) — and
# this file is what keeps the two of them honest. A claim that cannot be answered, a claim nobody acts
# on, or the same question asked in two places each restore the rc-0-lies shape the rule exists to stop.
#
# THE RULE, in one line: a leg that crosses says which engine tools it needs, the name it says is a
# name the probe ASKS about, the leg ACTS on the answer, and nothing outside the lib asks the question
# again.
#
# WHAT IS CHECKED — one finding prefix per rule, with the shape each catches:
#   DECLARATION  a call of `hl_wsl_needs` must NAME its tools (not `$var`: a name that arrives from the
#                environment is one no inventory answers for and no checker can grade), must name a tool
#                the probe ASKS about (`HL_WSL_TOOL_NAMES` in the lib — an unasked name can only ever
#                read as absent, so the leg would refuse on a question nobody asked), and must be GUARDED
#                on its own line (`|| exit`, `|| return`, `if ! …`). An unguarded claim is precisely the
#                rc-0-lies shape, and it is invisible to every other gate.
#                A MENTION is not a CALL: the name has to sit in command position, so a comment, an error
#                string, a redirection (`>/dev/null`, `2>&1`) and a backslash line-continuation are read
#                as the prose and the punctuation they are, and a claim split across lines is ONE claim.
#                A checker that accuses the shape of a comment is a checker that gets muted.
#   INVENTORY    the engine-tool answer is named in ONE file — `lib/wsl-route.sh`. A leg that reads the
#                inventory variable or calls the inventory function for itself is a second spelling of
#                one question, which turns "the run asked once" back into "every leg guessed".
#   REGISTRATION a leg wrapped in `hl_wsl_route` declares its tools at that line too: the registration is
#                where a reader learns which engine answered a leg, so it says what the engine must have.
#   RUNTIME      no leg declares `node` / `npm` / `npx` / `pi`. Those names sit behind the route's
#                deliberate PATH pin, whose widening is declined in `docs/harness-rejected.md`; naming
#                one is a leg assuming the engine's runtime, which is the assumption the pin exists to
#                make impossible.
#
# A leg that needs no engine tool writes `hl_wsl_needs none`, so "needs nothing" is a STATEMENT rather
# than an absence a checker cannot tell from "nobody thought about it". A tree where no leg declares
# anything prints a NOTE instead of a clean-looking zero: on such a tree the rule is unexercised by the
# tree, and the arms are what still prove it bites.
#
# Usage:
#   bash scripts/gate/check-leg-contract.sh              # this tree
#   bash scripts/gate/check-leg-contract.sh --root DIR   # a planted tree (the canaries, and an audit)
#   bash scripts/gate/check-leg-contract.sh --self-test  # each rule breeds its finding
#   bash scripts/gate/check-leg-contract.sh --arms       # planted legs through a door: the verdicts
#
# Exit: 0 clean · 1 finding(s) · 2 could not run (no lib, no registrations, an empty corpus). No stdin
# is read, and nothing outside a temp directory is written.
#
# WHAT IS NOT HERE: the engine's ANSWER about a tool is the probe's (`hl_wsl_tools`, asked once per run,
# never from a checker's loop); the parity of a leg across the door is `bench/win/gate-parity.sh`'s; and
# WHICH legs cross are validate-all.sh's registration lines. This file reads those decisions and never
# re-makes them — the same reason the repo keeps no second item list.
#
# Cost: the walk reads `*.sh` / `*.py` under scripts/ and forks ONCE (the file list), the rest with
# builtins, on the seat whose whole measurement is the price of a fork. A `.ps1` file is out of scope by
# fact rather than by choice: `hl_wsl_route` names an engine-side launcher for a python|python3|py|bash|
# sh head only, so a PowerShell leg has nothing to declare.
#
# SELF-TEST: bash scripts/gate/check-leg-contract.sh --self-test
#   Each rule breeds its finding alone in a planted tree, and the same tree with nothing planted stays
#   green — so no canary reddens for a reason outside its own rule. Four arms are SILENCE arms: a comment,
#   an error string, a redirection and a line continuation naming the declaration must answer rc 0.
#   `--arms` runs the contract through a door instead of through a grep; it refuses until the declaring
#   fixture leg lands under `testdata/`, and says so rather than printing verdicts it did not take.
# =====================================================================
set -uo pipefail
set -f        # the words below come out of file text; a `*` in a leg must not become a file list

_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"        # sets REPO; FATAL when no root is found
ROOT="$REPO"

# The inventory's two names, COMPOSED, so this file does not name what it forbids: a checker whose own
# canary pattern matches itself has to exempt itself, and an exemption is where a rule stops existing —
# the same reason check_script_layout.py composes its fixture paths.
INV_VAR='HL_WSL''_TOOLS'
INV_FN='hl_wsl''_tools'
NEEDS='hl_wsl_needs'
PINNED_RUNTIMES="node npm npx pi"    # behind the route's PATH pin; widening that pin is declined

find_n=0
_asked=""
_note="nothing read"

# _read_all <var> <file> — a whole file in ONE builtin read. `read` is byte-truthful (`$( )` is the shape
# that loses a CR on a Windows seat — CONVENTIONS §6), and a checker that execs a grep per file would pay
# 345 forks on the seat where a fork is the measurement.
_read_all() {
  local _v=""
  IFS= read -r -d '' _v <"$2" 2>/dev/null || :
  printf -v "$1" '%s' "${_v//$'\r'/}"
}

# corpus_files — the tracked files under scripts/, one fork. Outside a git tree (a planted canary tree)
# the walk falls back to find: a canary that silently read ZERO files is a canary that proved nothing.
corpus_files() {
  local _list=""
  if [ -e "$ROOT/.git" ]; then
    _list="$(cd "$ROOT" && git ls-files -- scripts 2>/dev/null)" || _list=""
  fi
  [ -n "$_list" ] || _list="$(cd "$ROOT" && find scripts -type f 2>/dev/null)" || _list=""
  printf '%s\n' "$_list"
}

# asked_names — the tool names the probe ASKS, read out of the lib that asks them. Retyping the list
# here would make this checker a second inventory, which is the thing the INVENTORY rule is about.
asked_names() {
  local _c="" _ln=""
  [ -f "$ROOT/scripts/lib/wsl-route.sh" ] || return 1
  _read_all _c "$ROOT/scripts/lib/wsl-route.sh"
  while IFS= read -r _ln; do
    case "$_ln" in
      _HL_WSL_TOOL_NAMES_SHIPPED=*) _ln="${_ln#*\"}"; _asked="${_ln%%\"*}"; return 0 ;;
    esac
  done <<<"$_c"
  return 1
}

# is_declaration <line> — a CALL of the declaration function, in COMMAND POSITION. Three shapes are not
# calls: the function's own definition, an error string that merely spells the name (`hl_wsl_needs:`),
# and prose inside a quoted argument. Position is what separates them without a parser: what precedes the
# name must be empty or end where a command may start — a separator, a paren, a `!`, an `if`.
is_declaration() {
  case "$1" in *"$NEEDS"*) : ;; *) return 1 ;; esac
  case "$1" in *"$NEEDS()"*) return 1 ;; esac
  local _pre="${1%%"$NEEDS"*}" _rest="${1#*"$NEEDS"}"
  case "$_rest" in ' '*) : ;; '') : ;; *) return 1 ;; esac     # a word, not `hl_wsl_needs:`
  _pre="${_pre%"${_pre##*[![:space:]]}"}"                      # rtrim
  case "$_pre" in
    '' | *';' | *'&' | *'|' | *'(' | *'!' | *'{' | *'if' | *'then' | *'do') return 0 ;;
    *) return 1 ;;                                            # `… _no "`, `printf '…`: a mention
  esac
}

# is_continuation <line> — does the line end in a backslash? Inside a declaration that means the
# ARGUMENT LIST continues, and a call site split across lines is one call site: grading the first
# fragment alone reports `hl_wsl_needs` with no names — a finding about a line break, not about the
# contract. A file that ends mid-continuation is not parseable bash, and the `bash -n` sweep is what
# grades that, so an open fragment is never carried into the next file.
is_continuation() { case "$1" in *\\) return 0 ;; *) return 1 ;; esac; }

# decl_names <line> — the names one declaration claims. Cut at the operators so
# `hl_wsl_needs rsync || exit $?` yields `rsync` and not the exit leg, and REDIRECTIONS are dropped —
# `2>&1` and `>/dev/null` say where the output goes, not what the leg needs. A trailing backslash is
# stripped as well: `hl_wsl_needs rsync \` claims a tool, and `\` is punctuation.
decl_names() {
  local _r="${1#*"$NEEDS"}" _t="" _out=""
  _r="${_r%%||*}"; _r="${_r%%;*}"; _r="${_r%%\)*}"; _r="${_r%%&&*}"
  local -a _w=()
  read -r -a _w <<<"$_r"
  for _t in "${_w[@]-}"; do
    _t="${_t%\\}"
    case "$_t" in '' | '&' | *'>'* | *'<'*) continue ;; esac
    _out="$_out $_t"
  done
  printf '%s' "${_out# }"
}

# has_name <line> <name> — is <name> a WORD of this line? A registration reason is PROSE, and prose
# ends its clauses with punctuation: `(its engine needs rsync)` names the tool exactly as `needs rsync`
# does. A substring test would answer for `rsync-max-delete` too, so the line is cut into words first
# and each word is reduced to its name characters.
has_name() {
  local _w
  for _w in $1; do
    _w="${_w//[![:alnum:]_.+-]/}"
    [ "$_w" = "$2" ] && return 0
  done
  return 1
}

fail() { printf 'FAIL: %s\n' "$*"; find_n=$((find_n + 1)); }

# --------------------------------------------------------------------------- #
# THE CHECK                                                                   #
# --------------------------------------------------------------------------- #
check_tree() {
  local _files="" _f="" _c="" _ln="" _names="" _t=""
  local _pre="" _rest="" _leg="" _line="" _arg="" _dn="" _va="" _acc="" _df=0
  local _cont=0
  local decl_files=0 decl_n=0 wrapped=0 resolved=0

  if [ ! -f "$ROOT/scripts/lib/wsl-route.sh" ]; then
    printf 'CANNOT RUN: no scripts/lib/wsl-route.sh under %s — the lib this contract is written in\n' "$ROOT"
    return 2
  fi
  if ! asked_names; then
    printf 'CANNOT RUN: scripts/lib/wsl-route.sh under %s names no tool set — an inventory that cannot be read cannot grade a claim\n' "$ROOT"
    return 2
  fi
  if [ ! -f "$ROOT/scripts/validate-all.sh" ]; then
    printf 'CANNOT RUN: no scripts/validate-all.sh under %s — no registration line to weigh\n' "$ROOT"
    return 2
  fi
  _files="$(corpus_files)"
  [ -n "${_files//[[:space:]]/}" ] \
    || { printf 'CANNOT RUN: the walk found no files under %s/scripts — a walk that reads nothing is not a pass\n' "$ROOT"; return 2; }

  # DECLARATION + INVENTORY — one pass over the corpus.
  while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    case "$_f" in *.sh | *.py) : ;; *) continue ;; esac
    [ -f "$ROOT/$_f" ] || continue
    _read_all _c "$ROOT/$_f"

    if [ "$_f" != "scripts/lib/wsl-route.sh" ]; then
      case "$_c" in
        *"$INV_VAR"* | *"$INV_FN"*)
          fail "INVENTORY: $_f names the engine-tool question ($INV_VAR / $INV_FN) outside the lib — one question, asked once, in lib/wsl-route.sh" ;;
      esac
    fi

    # The lib DEFINES and self-tests the claim; it is not a leg, so its own arms are not declarations
    # of a leg's needs (the INVENTORY rule above is what reads this file).
    if [ "$_f" != "scripts/lib/wsl-route.sh" ]; then
    case "$_c" in *"$NEEDS"*) : ;; *) continue ;; esac
    _df=$decl_n _acc="" _cont=0
    while IFS= read -r _ln; do
      # A call site split by a trailing backslash is ONE call site, so its continuations are joined
      # before the line is graded. Only a fragment that is ALREADY a call site starts a join: folding
      # the next line into a comment or a printf would trade a false finding for a missed one.
      if [ "$_cont" = 1 ]; then
        _cont=0 _acc="$_acc ${_ln%\\}"
        if is_continuation "$_ln"; then _cont=1; continue; fi
        _ln="$_acc" _acc=""
      elif is_continuation "$_ln" && is_declaration "$_ln"; then
        _acc="${_ln%\\}" _cont=1
        continue
      fi
      is_declaration "$_ln" || continue
      decl_n=$((decl_n + 1))
      _names="$(decl_names "$_ln")"
      if [ -z "$_names" ]; then
        fail "DECLARATION: $_f: \`$NEEDS\` with no names declares nothing — write \`$NEEDS none\` to claim no engine-tool need"
        continue
      fi
      for _t in $_names; do
        case "$_t" in
          '$'*)
            fail "DECLARATION: $_f: \`$NEEDS $_t\` names a tool through a variable — a claim must NAME the tool, or no inventory answers it and no checker grades it"
            continue ;;
          none) : ;;
        esac
        case " $_asked " in
          *" $_t "*) : ;;
          *) fail "DECLARATION: $_f: \`$NEEDS $_t\` names a tool the probe never asks about, so the inventory can only read as absent — add the name to HL_WSL_TOOL_NAMES in lib/wsl-route.sh with the leg that needs it" ;;
        esac
        case " $PINNED_RUNTIMES " in
          *" $_t "*) fail "RUNTIME: $_f: \`$NEEDS $_t\` assumes a runtime the route's PATH pin hides on purpose (docs/harness-rejected.md) — a leg that needs PATH-resolved $_t is the evidence the refusal asked for, not a reason to widen the pin" ;;
        esac
      done
      case " $_names " in
        *" none "*)
          case " ${_names//none/} " in
            *[![:space:]]*) fail "DECLARATION: $_f: \`none\` claimed beside names ($_names) is both claims at once — name the tools, or claim none" ;;
          esac
          ;;
        *)
          case "$_ln" in
            *'||'*) : ;;
            *'if ! '"$NEEDS"* | *'if '"$NEEDS"*) : ;;
            *) fail "DECLARATION: $_f: the rc of \`$NEEDS\` is discarded ($_ln) — a claim that cannot stop the leg is the rc-0-lies shape this rule exists to catch" ;;
          esac
          ;;
      esac
    done <<<"$_c"
    # A file that only MENTIONS the declaration (prose, an error string, a self-test message) declared
    # nothing, and the denominator must not count it as a declaring file.
    [ "$decl_n" = "$_df" ] || decl_files=$((decl_files + 1))
    fi
  done <<<"$_files"

  # REGISTRATION — a wrapped leg that declares, declares at its line too. Only `item…` lines are
  # registrations: the runner's own `= hl_wsl_route` test and a commented-out wiring are not wraps.
  _read_all _va "$ROOT/scripts/validate-all.sh"
  while IFS= read -r _line; do
    case "$_line" in item*) : ;; *) continue ;; esac
    case "$_line" in *hl_wsl_route*) : ;; *) continue ;; esac
    wrapped=$((wrapped + 1))
    _leg=""
    for _arg in $_line; do
      case "$_arg" in scripts/*.sh | scripts/*.py) _leg="$_arg"; break ;; esac
    done
      [ -n "$_leg" ] || continue
    resolved=$((resolved + 1))
    [ -f "$ROOT/$_leg" ] || { fail "REGISTRATION: $_leg is wrapped in validate-all.sh and does not exist"; continue; }
    _dn=""
    _read_all _c "$ROOT/$_leg"
    while IFS= read -r _ln; do
      is_declaration "$_ln" || continue
      for _t in $(decl_names "$_ln"); do
        case "$_t" in none) : ;; *) _dn="$_dn $_t" ;; esac
      done
    done <<<"$_c"
    for _t in $_dn; do
      has_name "$_line" "$_t" \
        || fail "REGISTRATION: $_leg declares \`$_t\` but its hl_wsl_route line does not name it — the line is where a reader learns what the engine has to have"
    done
  done <<<"$_va"

  # The honest denominator, printed whether or not anything was found: a rule that read nothing must
  # never look like a pass.
  _note="declarations $decl_n in $decl_files file(s) · wrapped legs $resolved/$wrapped registration(s) named a leg path · tools the probe asks: $(printf '%s\n' "$_asked" | wc -w)"
  if [ "$decl_n" = 0 ]; then
    printf 'NOTE: no leg on this tree declares its engine tools yet — the tree exercises nothing, so the\n'
    printf '      arms are the proof here. A wrapped leg that shells out to a tool is what adds a declaration.\n'
  fi
  [ "$resolved" = "$wrapped" ] \
    || printf 'NOTE: %s wrapped registration(s) name no `scripts/…` leg path on the line, so REGISTRATION\n      could not weigh them — a leg wrapped inside a shell function is that shape.\n' \
         "$((wrapped - resolved))"
  return 0
}

report() { # report <check-rc>
  local _rc="$1"
  if [ "$_rc" = 2 ]; then return 2; fi
  if [ "$find_n" = 0 ]; then
    printf 'OK: the leg contract holds — %s\n' "$_note"
    return 0
  fi
  printf '\n%s finding(s): the leg contract is not what lib/wsl-route.sh promises.\n' "$find_n"
  printf '      Re-derive the inventory: bash scripts/lib/wsl-route.sh --self-test (its last arm is the live probe)\n'
  return 1
}

# --------------------------------------------------------------------------- #
# SELF-TEST — every rule breeds its finding, and the legal shape stays green.          #
# --------------------------------------------------------------------------- #
_st_n=0
_st_f=0
_st_ok() { printf '  ok: %s\n' "$*"; _st_n=$((_st_n + 1)); }
_st_no() { printf 'SELFTEST FAIL: %s\n' "$*"; _st_f=$((_st_f + 1)); }

# _st_tree <dir> — the legal shape: the real lib, one named+guarded+asked declaration, and a
# registration that names the tool. Every canary below mutates ONE thing out of it.
_st_tree() {
  local d="$1"
  mkdir -p "$d/scripts/lib" "$d/scripts/harness" || return 1
  cp "$REPO/scripts/lib/wsl-route.sh" "$d/scripts/lib/wsl-route.sh" || return 1
  cat >"$d/scripts/harness/leg.sh" <<'LEG'
#!/usr/bin/env bash
# A planted leg in the contract's legal shape: a named, guarded declaration of a tool the probe asks.
hl_wsl_needs rsync || exit $?
printf 'ok  the leg ran\n'
LEG
  cat >"$d/scripts/validate-all.sh" <<'REG'
#!/usr/bin/env bash
item_q "leg.sh --self-test (the planted leg; its engine needs rsync)" hl_wsl_route bash scripts/harness/leg.sh --self-test
REG
  return 0
}

_st_run() { # _st_run <tree> -> the checker's rc on that tree
  local _rc=0
  bash "${BASH_SOURCE[0]}" --root "$1" >/dev/null 2>&1 || _rc=$?
  return $_rc
}

# _st_breed <name> <want-rc> <file> <one line appended> <why> — mutate ONE thing out of the legal tree.
# The locals are split on purpose: `local x="$1" d="$x"` expands `$x` BEFORE the assignment lands, so on
# a `set -u` seat the second name is an unbound variable and the whole self-test dies on line one.
_st_breed() {
  local name="$1" want="$2" file="$3" body="$4" why="$5" _rc=0
  local _d="$_st_tmp/$name"
  if ! _st_tree "$_d"; then _st_no "$name: the tree could not be built"; return 0; fi
  printf '%s\n' "$body" >>"$_d/$file"
  _st_run "$_d"; _rc=$?
  if [ "$_rc" = "$want" ]; then
    _st_ok "$name → rc $_rc ($why)"
  else
    _st_no "$name answered rc $_rc, want $want ($why)"
  fi
}

# _st_multiline <name> <want-rc> <file> <heredoc body> <why> — the same, for a canary whose shape IS
# multiple lines (a call site continued with backslashes cannot be passed as one argument).
_st_multiline() {
  local name="$1" want="$2" file="$3" why="$4" _rc=0
  local _d="$_st_tmp/$name"
  if ! _st_tree "$_d"; then _st_no "$name: the tree could not be built"; return 0; fi
  cat >>"$_d/$file"
  _st_run "$_d"; _rc=$?
  if [ "$_rc" = "$want" ]; then
    _st_ok "$name → rc $_rc ($why)"
  else
    _st_no "$name answered rc $_rc, want $want ($why)"
  fi
}

self_test() {
  local _rc=0
  _st_tmp="$(mktemp -d "${TMPDIR:-/tmp}/leg-contract-st-XXXXXX")" || return 1
  trap "rm -rf '$_st_tmp'" EXIT

  # The control first: if the legal shape is not green, every canary below could redden for a reason
  # that has nothing to do with its own rule.
  if _st_tree "$_st_tmp/control" && _st_run "$_st_tmp/control"; then
    _st_ok "control: a named, guarded, asked, registered declaration is green"
  else
    _st_no "the control tree was NOT green — the canaries below would redden for the wrong reason"
  fi

  _st_breed unasked 1 scripts/harness/leg.sh 'hl_wsl_needs nosuchtool || exit 2' \
    "an unasked name can only ever read as absent; the probe has to be told to ask"
  _st_breed unguarded 1 scripts/harness/leg.sh 'hl_wsl_needs jq' \
    "a discarded rc: the claim cannot stop the leg, which is the rc-0-lies shape"
  _st_breed noname 1 scripts/harness/leg.sh 'hl_wsl_needs || exit 2' \
    "a declaration that names nothing declares nothing"
  _st_breed varname 1 scripts/harness/leg.sh 'hl_wsl_needs "$HL_LEG_TOOL" || exit 2' \
    "a name from the environment is a name no inventory answers for"
  _st_breed twoclaims 1 scripts/harness/leg.sh 'hl_wsl_needs none rsync || exit 2' \
    "claiming none and a name at once claims nothing"
  _st_breed secondspelling 1 scripts/harness/leg.sh 'if [ -n "${'"$INV_VAR"':-}" ]; then :; fi' \
    "the engine-tool question asked twice is the per-leg rediscovery the lib exists to stop"
  _st_breed pinnedruntime 1 scripts/harness/leg.sh 'hl_wsl_needs node || exit 2' \
    "naming a pinned runtime assumes the engine's node, which the declined pin refuses"
  _st_breed noregname 1 scripts/validate-all.sh \
    'item_q "a second wrap of the same leg, tool unnamed" hl_wsl_route bash scripts/harness/leg.sh --check' \
    "a wrap whose line hides the tool sends the reader to the engine blind"
  _st_breed missingleg 1 scripts/validate-all.sh \
    'item_q "a wrap of a leg that is not there" hl_wsl_route bash scripts/harness/gone.sh --self-test' \
    "a wrapped leg has to exist"

  # The silence half: each shape below MENTIONS the declaration without CALLING it, and must answer rc 0
  # in a tree that already holds one legal declaration. A parser that reads prose, redirections or line
  # breaks as call sites reddens a leg for the shape of its comments — the false-positive class that
  # makes a checker get muted, so it is fenced here rather than in an audit note.
  _st_breed prosecomment 0 scripts/harness/leg.sh '# the rule: hl_wsl_needs rsync || exit 2 stops the leg' \
    "a comment about the rule is prose, not a call site"
  _st_breed prosestring 0 scripts/harness/leg.sh \
    "printf 'usage: call hl_wsl_needs with the tools this leg shells out to\n' >&2" \
    "an error string that spells the name is prose, not a call site"
  _st_breed redirection 0 scripts/harness/leg.sh 'hl_wsl_needs rsync >/dev/null 2>&1 || exit $?' \
    "a redirection says where the output goes, not what the leg needs"
  _st_multiline continuation 0 scripts/harness/leg.sh \
    "a declaration split by backslashes is one call site, not three" <<'CONT'
hl_wsl_needs \
  rsync \
  || exit $?
CONT

  # The refusal half: a tree this checker cannot weigh answers rc 2, never a green.
  mkdir -p "$_st_tmp/empty/scripts" || _st_no "the empty tree could not be built"
  _st_run "$_st_tmp/empty"; _rc=$?
  [ "$_rc" = 2 ] && _st_ok "a tree with nothing to weigh refuses (rc 2) rather than printing OK" \
                 || _st_no "an unreadable tree answered rc $_rc, want 2"
  _st_run "$_st_tmp/no-such-tree" >/dev/null 2>&1; _rc=$?
  [ "$_rc" = 2 ] && _st_ok "and a root that is not a directory refuses too" \
                 || _st_no "a missing root answered rc $_rc, want 2"

  printf '\n%s arm(s): %s passed, %s failed\n' "$((_st_n + _st_f))" "$_st_n" "$_st_f"
  [ "$_st_f" = 0 ] || return 1
  return 0
}

# --------------------------------------------------------------------------- #
# Main                                                                        #
# --------------------------------------------------------------------------- #
case "${1:-}" in
  --root)
    [ -n "${2:-}" ] || { printf 'CANNOT RUN: --root needs a directory\n' >&2; exit 2; }
    [ -d "$2" ] || { printf 'CANNOT RUN: --root %s is not a directory\n' "$2" >&2; exit 2; }
    ROOT="$(cd "$2" && pwd)"
    check_tree; report $?; exit $? ;;
  --self-test)
    printf '== leg contract: each rule breeds its finding ==\n'
    if self_test; then
      printf 'self-test: every rule caught its canary, the legal shape stayed green\n'
      exit 0
    fi
    printf 'SELFTEST FAILED\n'
    exit 1 ;;
  --arms)
    printf 'CANNOT RUN: the door arms land with the planted legs in scripts/testdata/leg-contract/\n' >&2
    exit 2 ;;
  "")
    check_tree; report $?; exit $? ;;
  -h | --help)
    sed -n '1,52p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  *)
    printf 'usage: bash scripts/gate/check-leg-contract.sh [--root DIR | --self-test | --arms]\n' >&2
    exit 2 ;;
esac
