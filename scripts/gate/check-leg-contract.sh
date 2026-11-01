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
# name the probe ASKS about, the leg ACTS on the answer, nothing outside the lib asks the question again,
# and the leg does not ask WHICH SEAT IT IS ON or open something only the far side can open.
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
#                make impossible. The crossed-side pointer is `pi-tui-config --self-test`'s `pinned-node`
#                arm, which SKIPs when the route's pin carries no node dir: the engine HAS a node and the
#                leg may not assume it.
#   VERDICT      a leg that declares a real tool may not be registered straight onto an `item…` line. Its
#                rc 2 IS the boundary — an engine that lists the name ABSENT stops it before it judges — and
#                a line that reads the leg's rc as the run's verdict turns a true sentence into a FAILED
#                gate. The block form maps it (`blk_rsync_max_delete`), and that is also the shape the
#                REGISTRATION rule then weighs.
#   SEAT         a wrapped leg that CLASSIFIES the seat it runs on, at column 0: crossed, it answers about
#                the engine's OS, its `/proc`, its registry — and prints a verdict instead of an error. This
#                is the conjunction's first clause (`lib/wsl-route.sh`), and the ban list that names it has
#                had no enforcer until this line. Detectors: `hl_wsl_class`, `hl_wsl_probe`,
#                `this_is_wsl_engine`, `/proc/version`, `uname -s|-r|-m`, `WSL_DISTRO_NAME`, `hostnamectl`.
#   TRIP         a wrapped leg that opens a vault, ssh or network trip at column 0, where every registered
#                mode reaches it — so it opens it on BOTH sides of the door. Detectors: `ssh`, `curl`,
#                `wget`, `op`, `ansible-playbook`, and sourcing `lib/vault-env.sh` / `lib/vault_read.py`.
#                Column 0 is the test because it is the one thing grep can settle: an INDENTED site sits in
#                a function body or an `if` branch, and whether the registered argv reaches it is a parity
#                question. Those sites are printed as NOT JUDGED with the command that answers it.
#   BOUNDARY     the exceptions, in `scripts/gate/leg_contract_boundaries.txt` — one leg, one class, one
#                argument each. A line whose leg is no longer wrapped, or no longer trips the class it
#                names, REDDENS: an exception that cannot be invalidated is a mute button.
#   FACE         the `face tree|seat|joined` word at a registration line, DERIVED rather than read. The
#                word claims where the leg's SUBJECT lives (the axis is stated once, in `lib/wsl-route.sh`),
#                and a word nobody can re-derive is a label that rots the moment the leg reads something
#                new. The facts are the conjunction's own, read off the registration line, the block it
#                calls and the leg file: a seat classifier, a vault/ssh/network trip or a seat-`$HOME`
#                read makes the subject SEAT state; a checkout read (`$REPO`, `repo_root`, `git` at
#                command position) makes it TREE state; both make it JOINED; neither makes it TREE. One
#                narrowing is allowed — a `--self-test` leg that builds its OWN sandbox planted that
#                `$HOME` and that socket, so those facts do not count, while a CLASSifier still does
#                because it asks the question of the engine wherever it runs. A WRAPPED registration is
#                `tree` by definition: the runner crosses it, and the conjunction it passed to be crossed
#                says its subject is the tree or a sandbox it builds — so `face seat` on a wrapped line is
#                a placement lie, and the seat facts under that wrap are already named by SEAT/TRIP.
#                A registration with NO face word is UNDECIDED, and `--profile quick` refuses the run.
#
# A leg that needs no engine tool writes `hl_wsl_needs none`, so "needs nothing" is a STATEMENT rather
# than an absence a checker cannot tell from "nobody thought about it". A tree that wraps legs while
# NOTHING declares answers rc 2 rather than OK: a contract the tree never exercised is not a pass, and
# the subject to add is one wrapped leg that names what it shells out to
# (`scripts/testdata/leg-contract/run.sh`). A tree with no declarations AND no wraps — a checkout where
# the door is not wired at all — prints the NOTE instead, because there is nothing here to weigh.
#
# Usage:
#   bash scripts/gate/check-leg-contract.sh              # this tree
#   bash scripts/gate/check-leg-contract.sh --root DIR   # a planted tree (the canaries, and an audit)
#   bash scripts/gate/check-leg-contract.sh --self-test  # each rule breeds its finding
#   bash scripts/gate/check-leg-contract.sh --arms       # the declaring leg, driven by planted answers
#   bash scripts/gate/check-leg-contract.sh --faces      # the derivation table, one row per registration
#
# Exit: 0 clean · 1 finding(s) · 2 could not run (no lib, no registrations, an empty corpus). No stdin
# is read, and nothing outside a temp directory is written.
#
# WHAT IS NOT HERE: the engine's ANSWER about a tool is the probe's — ONE `which` spawn per run, asked
# from the probe and never from a checker's loop (the function is not named here because naming it in a
# scanned file is what this rule hunts, and a checker exempt from its own rule is a checker with no rule);
# the parity of a leg across the door is `bench/win/gate-parity.sh`'s; and WHICH legs cross are
# validate-all.sh's registration lines. This file reads those decisions and never re-makes them — the
# same reason the repo keeps no second item list.
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
#   Six more arms grade the FACE derivation, one per way a word on a registration line can stop matching
#   the leg: a `tree` leg that reads `$HOME/.pi`, a `tree` leg that opens a socket, a registration with no
#   face word at all, a `seat` leg whose facts say seat (green, plus the NOTE that it could have been a
#   tree), a `joined`-capable leg that only reads seat state, and a WRAPPED leg declared `seat` — which is
#   a finding rather than a note, because the runner crosses the line it is lying about.
#   `--arms` runs the contract through the ANSWERS instead of through a grep: the declaring leg in the
#   tree is driven by four planted inventories and answers rc 0 having run, rc 2 naming a tool the
#   inventory lists as ABSENT and quoting that inventory, unchanged and silent with no answer in hand, and
#   rc 2 as UNPROVEN for an engine that answered nothing. The door itself is `lib/wsl-route.sh --self-test`
#   and the native-versus-crossed pair is `bench/win/gate-parity.sh`'s; no engine is spawned here.
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
# The two detectors that read the conjunction off the wrapped legs. They name CALLS: the SEAT list is how a
# leg asks which seat it is on, the TRIP list is how a leg opens something only the seat it stands on can
# open. A name inside prose or inside a quoted string is not a call — see at_cmd.
SEAT_WORDS=(hl_wsl_class hl_wsl_probe this_is_wsl_engine '/proc/version' 'uname -s' 'uname -r' 'uname -m'
            WSL_DISTRO_NAME hostnamectl)
TRIP_WORDS=('ssh ' 'curl ' 'wget ' 'op ' 'ansible-playbook ' 'vault-env.sh' 'vault_read.py')
BOUNDARIES="scripts/gate/leg_contract_boundaries.txt"   # accepted wrong-seat boundaries, one per line

find_n=0
_asked=""
_note="nothing read"
SHOW_FACES=0                       # --faces: face_walk prints one row per registration, not just the counts
_face_note="faces not weighed"
declare -A _face_cache=()          # leg path -> its five fact lists, for the width of one check_tree run

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

# has <text> <needle> — the substring test as a named condition, so the door arms read as sentences.
has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

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
# THE CONJUNCTION, read off the wrapped legs.                                        #
# --------------------------------------------------------------------------- #
# WHY THIS IS HERE AT ALL: the rule that a leg may not cross if it classifies the seat it runs on, or
# opens a vault/ssh/network trip, is stated in `lib/wsl-route.sh`'s header and in the brief's ban list —
# and nothing in the tree enforced either. The conjunction's first clause is decidable from the text
# because a seat classifier answers for the WRONG SEAT in every mode, and a top-level vault/ssh trip runs
# in every mode. A site inside a function body is a different question — whether the REGISTERED argv
# reaches it is a parity question, not a grep question — so those sites are counted and printed as
# NOT JUDGED with the instrument that does decide them, `bench/win/gate-parity.sh`, rather than guessed at
# in either direction. `pi-tui-config --self-test`'s `pinned-node` arm is the sibling case on the tool
# side: crossed, the engine's node sits behind the PATH pin whose widening docs/harness-rejected.md
# declines, so the arm SKIPs and the leg still exits 0. No arm here widens that PATH or names a runtime.
#
# Both detectors read COMMAND position, not the word: prose about ssh and a printed suggestion of an `op`
# command are not a trip, and neither is an interpreter call that merely contains the letters.
at_cmd() { # at_cmd <line> <word> — does <word> sit where a COMMAND may start?
  local _pre="${1%%"$2"*}"
  [ "$_pre" != "$1" ] || return 1                          # the word is not in the line at all
  _pre="${_pre%"${_pre##*[![:space:]]}"}"                  # rtrim
  case "$_pre" in
    '' | *';' | *'&' | *'|' | *'(' | *'!' | *'`' | *'{' | *then | *do | *if) return 0 ;;
    *) return 1 ;;
  esac
}

# tail_comment <line> — the line with a balanced trailing ` # …` comment cut off, into _tc. The balance
# test is the whole care: `"#ff0000"` and `s/x#y//` are text, `foo  # note` is a comment, and cutting the first would
# hide a trip that really runs.
# It ASSIGNS to _tc rather than printing: this runs once per line of every wrapped leg, and a command
# substitution there is ~6,000 forks on the seat whose whole measurement IS the price of a fork — the
# shape that made this checker time out rather than answer.
tail_comment() {
  local _cut="${1%%[[:space:]]#*}" _q=""
  _tc="$1"
  [ "$_cut" != "$1" ] || return 0
  _q="${_cut//[!\']}"
  [ $(( ${#_q} % 2 )) = 0 ] || return 0
  _q="${_cut//[!\"]}"
  [ $(( ${#_q} % 2 )) = 0 ] || return 0
  _tc="$_cut"
}

# wrap_scan <file> — the seat/trip sites of one wrapped leg, split by whether every registered mode
# reaches them. Sets _ws_seat / _ws_trip (the unconditional sites, as `file:line`) and _ws_nv (the
# conditional ones). Unconditional is read OFF THE COLUMN, not off a control-flow guess: this tree writes
# its top-level statements at column 0, so a site at column 0 runs in every mode, and a site that is
# INDENTED sits in a function body or an `if` branch — reachable or not depending on the argv, which is a
# parity question and not a grep question. A brace depth was tried first and is wrong twice over: an `if`
# at top level opens no brace, and a heredoc full of braces is prose.
wrap_scan() {
  local _f="$1" _ln="" _t="" _w="" _n=0 _hd="" _h=""
  _ws_seat="" _ws_trip="" _ws_nv=0
  while IFS= read -r _ln; do
    _n=$((_n + 1))
    _ln="${_ln%$'\r'}"
    _t="${_ln#"${_ln%%[![:space:]]*}"}"                    # ltrim — the terminator test below reads it
    # A heredoc body is text the leg writes, not calls the leg makes, so it is skipped whole.
    if [ -n "$_hd" ]; then
      case "$_t" in "$_hd") _hd="" ;; esac
      continue
    fi
    case "$_t" in
      *'<<'*)                                             # a heredoc starts here; the tag is the next word
        _h="${_t##*<<}"; _h="${_h#-}"
        _h="${_h#"${_h%%[A-Za-z_]*}"}"                    # drop what precedes the tag: blanks, dash, quote
        _hd="${_h%%[!A-Za-z0-9_]*}"
        ;;
    esac
    case "$_t" in '' | '#'*) continue ;; esac
    tail_comment "$_t"; _t="$_tc"
    [ "${#_ln}" != "${#_t}" ] && _site=1 || _site=0       # indented → conditional site
    for _w in "${SEAT_WORDS[@]}"; do
      case "$_t" in *"$_w"*) : ;; *) continue ;; esac
      at_cmd "$_t" "$_w" || continue
      if [ "$_site" = 0 ]; then _ws_seat="$_ws_seat $_f:$_n"; else _ws_nv=$((_ws_nv + 1)); fi
    done
    for _w in "${TRIP_WORDS[@]}"; do
      case "$_t" in *"$_w"*) : ;; *) continue ;; esac
      at_cmd "$_t" "$_w" || continue
      if [ "$_site" = 0 ]; then _ws_trip="$_ws_trip $_f:$_n"; else _ws_nv=$((_ws_nv + 1)); fi
    done
  done <<<"$_c"
  return 0
}

# blk_wrap_line <fn> — the hl_wsl_route line inside a registration block: a declaring leg's registration
# MUST take this form (VERDICT), so a wrap hidden in a block is a wrap and has to be weighed.
blk_wrap_line() {
  local _fn="$1" _l="" _in=0
  while IFS= read -r _l; do
    if [ "$_in" = 0 ]; then
      case "$_l" in "$_fn"*'() '*) _in=1 ;; esac
      continue
    fi
    case "$_l" in '}'*) return 1 ;; esac
    case "$_l" in *hl_wsl_route*) printf '%s' "$_l"; return 0 ;; esac
  done <<<"$_va"
  return 1
}

# --------------------------------------------------------------------------- ## THE FACE, DERIVED                                                           #
# --------------------------------------------------------------------------- #
# WHY THIS IS DERIVED AND NOT READ: `face tree|seat|joined` at a registration line claims where a leg's
# SUBJECT lives, and a claim nobody can re-derive is a label — it rots the moment the leg starts reading
# something new. So the same facts the conjunction is written in are read a second time, off the SUBJECT
# instead of the launcher: a seat classifier, a vault/ssh/network trip or a seat-`$HOME` read makes the
# subject SEAT state; a checkout read (`$REPO`, `repo_root`, `require_corpus`, `__file__`, or `git` at
# command position) makes it TREE state; both make it JOINED; neither makes it TREE. The word lists are
# the conjunction's own (SEAT_WORDS / TRIP_WORDS above) — a leg cannot be a trip to one rule and prose to
# the other — and the reading is the same: COMMAND position via at_cmd, array literals are DATA, heredoc
# bodies and python docstrings are text the leg writes rather than calls it makes.
#
# Two asymmetries are the whole design, and both are deliberate:
#   * a `--self-test` registration whose leg BUILDS ITS OWN SANDBOX (mktemp/tempfile/mkdtemp) has planted
#     that `$HOME` and opened that socket, so the seat trip/home facts drop out — a fixture is not seat
#     state. A CLASSIFIER survives the narrowing: a leg that asks which seat it is on asks it of the
#     engine wherever it runs.
#   * a WRAPPED registration is `tree` BY DEFINITION: the runner crosses it, and the conjunction it passed
#     to be crossed says its subject is the tree or a sandbox it builds. `face seat` on such a line is
#     therefore a placement lie rather than a conservative word — and the seat facts under that wrap are
#     already named by SEAT / TRIP / NOT JUDGED above, so they are not weighed twice.
# The mismatch that costs nothing is a NOTE: a NATIVE line that claims MORE seat than the facts show is
# only refusing a free grading (the direction A7 names — "a leg marked seat that could have crossed only
# costs a note").

# The markers the derivation reads, beside the conjunction's own two lists at the top of this file — one
# spelling per class, so a leg cannot be a trip to one rule and prose to the other.
CK_WORDS=('$REPO' '${REPO}' '${REPO_ROOT')             # this checkout, by the variables that name it
CK_PY_WORDS=(require_corpus _hl_root repo_root __file__)      # …and the python ways of finding that root
GIT_WORD='git '                                        # …or reached through git: needs a command test
HOME_SH=('$HOME' '~/')                                 # seat state, in the two spellings a shell reaches it
HOME_PY=('Path.home(' 'expanduser(' 'from vault_read import ')   # …and the ones a python leg reaches it with
SAND_WORDS=(mktemp tempfile mkdtemp)                   # a sandbox the leg builds for itself
SEAT_MARKS=("${SEAT_WORDS[@]}" "${TRIP_WORDS[@]}" "${HOME_SH[@]}" "${HOME_PY[@]}")
ALL_MARKS=("${SEAT_MARKS[@]}" "${CK_WORDS[@]}" "${CK_PY_WORDS[@]}" "$GIT_WORD" "${SAND_WORDS[@]}")

# face_fact <cls|trip|home|ck|sand> - record ONE fact: the count always moves, and the example list stops
# at three sites. Uncapped, a leg whose every line mentions `repo_root` grows its own fact string on every
# hit and the derivation spends five minutes copying a string: the quadratic cost this file exists to avoid,
# wearing a different coat. Three sites is also all a finding can quote.
face_fact() {
  local _nv="_fc_$1_n" _xv="_fc_$1_x"
  printf -v "$_nv" '%s' "$(( ${!_nv} + 1 ))"
  [ "${!_nv}" -le 3 ] && printf -v "$_xv" '%s %s:%s' "${!_xv}" "$_fc_tag" "$_fc_line"
  return 0
}

# face_scan <text> <kind: sh|py|blk> <tag> — the face facts of one body of text, as `tag:line` entries in
# _fc_cls / _fc_trip / _fc_home (the three SEAT facts), _fc_ck (the TREE fact) and _fc_sand (a sandbox the
# leg builds). `py` reads python spellings and skips the shell-only ones, because a shell word inside a
# python argv is not a shell; `blk` is a registration line or the block it calls, which is shell text.
# Assigns rather than prints, for the reason `tail_comment` does — this runs once per line of every leg,
# and a fork per line is the cost this checker exists to avoid.
face_scan() {
  local _txt="$1" _kind="$2" _tag="$3" _ln="" _t="" _w="" _n=0 _hd="" _h="" _pre="" _doc=0 _par=0 _arr=0 _q="" _qn=0 _hit=""
  _fc_cls_n=0 _fc_trip_n=0 _fc_home_n=0 _fc_ck_n=0 _fc_sand_n=0
  _fc_cls_x="" _fc_trip_x="" _fc_home_x="" _fc_ck_x="" _fc_sand_x=""
  _fc_tag="$_tag"
  local _udeep="$HL_FACE_UNCOND"
  while IFS= read -r _ln; do
    _n=$((_n + 1)); _fc_line=$_n
    # UNCONDITIONAL-ONLY mode: a fact reached from an enclosing branch belongs to that branch, which
    # is exactly what SEAT / TRIP call a conditional site and hand to gate-parity. Used to grade a
    # CROSSED registration, where "the subject reads seat state" must mean the same thing the
    # conjunction says it means — what runs at gate shape, not what might run on some seat.
    if [ -n "$_udeep" ] && [ "${#_ln}" != "${#_t}" ]; then continue; fi
    _t="${_ln#"${_ln%%[![:space:]]*}"}"                        # ltrim — the region tests below read it
    if [ -n "$_hd" ]; then case "$_t" in "$_hd") _hd="" ;; esac; continue; fi     # a heredoc body is DATA
    if [ "$_par" = 1 ]; then case "$_t" in *')'*) _par=0 ;; esac; continue; fi    # an array literal's tail
    if [ "$_kind" = py ] && [ "$_doc" = 1 ]; then                                  # a docstring is prose
      _q="${_t//\"\"\"/}"; _qn=$(( (${#_t} - ${#_q}) / 3 ))
      [ $((_qn % 2)) = 0 ] || _doc=0
      continue
    fi
    # The fast path: a line carrying no marker holds no fact and opens no data region. This is a loop over
    # ALL_MARKS, not one long `case` alternation, and it is the measured shape — on the Windows seat, where
    # the price of a builtin is the whole measurement, the alternation cost ~5 min a run and the loop ~12 s.
    _hit=""
    for _w in "${ALL_MARKS[@]}"; do
      case "$_ln" in *"$_w"*) _hit=1; break ;; esac
    done
    if [ -z "$_hit" ]; then                                    # no marker on the line, so no fact is on
      case "$_ln" in                                           # it — unless a data region OPENS here
        *'<<'*) : ;;                                           # a heredoc body follows this line
        *='('*) : ;;                                           # an array literal's tail follows it
        *'"'*) [ "$_kind" = py ] || continue ;;                # a python docstring may open here
        *) continue ;;
      esac
    fi
    case "$_t" in '' | '#'*) continue ;; esac
    tail_comment "$_t"; _t="$_tc"
    if [ "$_kind" = py ]; then                                 # does a docstring open on this line?
      _q="${_t//\"\"\"/}"; _qn=$(( (${#_t} - ${#_q}) / 3 ))
      [ $((_qn % 2)) = 0 ] || _doc=1
    fi
    case "$_t" in
      *'<<'*)                                                  # the heredoc tag is the next word
        _h="${_t##*<<}"; _h="${_h#-}"; _h="${_h#"${_h%%[A-Za-z_]*}"}"; _hd="${_h%%[!A-Za-z0-9_]*}" ;;
    esac
    _arr=0
    case "$_t" in
      *[A-Za-z_]='('*) _arr=1; case "$_t" in *')'*) : ;; *) _par=1 ;; esac ;;
    esac
    case "$_t" in *'_hl_d/lib/repo-root.sh'*) continue ;; esac  # the root is FOUND, not read
    for _w in "${SEAT_WORDS[@]}"; do
      case "$_t" in *"$_w"*) : ;; *) continue ;; esac
      [ "$_arr" = 1 ] && continue                              # a detector table is DATA, not a call
      at_cmd "$_t" "$_w" || continue                           # a question asked of the kernel, not of the tree
      face_fact cls
    done
    for _w in "${TRIP_WORDS[@]}"; do
      case "$_t" in *"$_w"*) : ;; *) continue ;; esac
      [ "$_arr" = 1 ] && continue
      at_cmd "$_t" "$_w" || continue
      par_quote "$_t" "$_w" || continue
      # In a python leg a shell verb is a string, not a trip — except the names this repo actually runs.
      if [ "$_kind" = py ]; then
        case "$_w" in 'ansible-playbook ' | *vault-env.sh | *vault_read.py) : ;; *) continue ;; esac
      fi
      face_fact trip
    done
    if [ "$_kind" = py ]; then
      case "$_t" in
        *'from vault_read import'*) face_fact trip ;;
        *'Path.home('* | *'expanduser('*) face_fact home ;;
      esac
      for _w in "${CK_PY_WORDS[@]}";
      do case "$_t" in *"$_w"*) face_fact ck ;; esac
      done
    fi
    case "$_t" in
      *"$GIT_WORD"*)
        if at_cmd "$_t" "$GIT_WORD" && par_quote "$_t" "$GIT_WORD"; then face_fact ck; fi ;;
    esac
    for _w in "${CK_WORDS[@]}"; do
      case "$_t" in *"$_w"*) face_fact ck ;; esac
    done
    if [ "$_kind" != py ]; then
      for _w in "${HOME_SH[@]}"; do
        case "$_t" in *"$_w"*) : ;; *) continue ;; esac
        # A path inside the quote that stops its expansion is a STRING: `$HOME` survives double quotes and
        # `~/` survives single ones, so each spelling is only a path when its own quote is balanced.
        _pre="${_t%%"$_w"*}"
        case "$_w" in
          '$HOME') _q="${_pre//[!\']}" ;;
          *) _q="${_pre//[!\"]}" ;;
        esac
        [ $(( ${#_q} % 2 )) = 0 ] || continue
        face_fact home
      done
    fi
    for _w in "${SAND_WORDS[@]}"; do
      case "$_t" in *"$_w"*) face_fact sand; break ;; esac
    done
  done <<<"$_txt"
  return 0
}

# par_quote <line> <word> — is <word> outside every quote open where it sits? An ODD number of a quote
# character before the word puts the word inside it, and a command inside a quote is a string: a printed
# suggestion of an `op …` command and a printf of `ssh …` are prose, not trips. (The two shell HOME
# spellings test their own quote above, because which quote stops an expansion depends on what expands.)
par_quote() {
  local _pre="${1%%"$2"*}" _q=""
  _q="${_pre//[!\']}"; [ $(( ${#_q} % 2 )) = 0 ] || return 1
  _q="${_pre//[!\"]}"; [ $(( ${#_q} % 2 )) = 0 ] || return 1
  return 0
}

# blk_body <fn> — the body of a registration block, so a fact that lives IN the block rather than on the
# line is read by the derivation too. `blk_wrap_line` reads the same shape for the wrap half.
blk_body() {
  local _fn="$1" _t="" _end="$_nl}"*        # the pattern: the first line that OPENS with a closing brace
  _blk_out=""
  case "$_va" in *"$_nl$_fn() "*) : ;; *) return 1 ;; esac
  _t="${_va#*"$_nl$_fn() "}"
  _blk_out="${_t%%$_end}"
  return 0
}

# leg_facts <path> — the face facts of one leg FILE, CACHED: a leg is registered more than once (a run and
# its --self-test are separate registrations, and 145 registrations name 82 files), so re-reading a file per
# registration is the per-leg rediscovery the probe's one-question-per-run rule exists to avoid. A file whose
# text carries no marker at all is answered without the line walk.
leg_facts() {
  local _p="$1" _k="" _w=""
  if [ -n "${_face_cache[$_p $_udeep]+x}" ]; then
    IFS='|' read -r _fc_cls_n _fc_trip_n _fc_home_n _fc_ck_n _fc_sand_n \
                  _fc_cls_x _fc_trip_x _fc_home_x _fc_ck_x _fc_sand_x <<<"${_face_cache[$_p $_udeep]}"
    return 0
  fi
  _fc_cls_n=0 _fc_trip_n=0 _fc_home_n=0 _fc_ck_n=0 _fc_sand_n=0
  _fc_cls_x="" _fc_trip_x="" _fc_home_x="" _fc_ck_x="" _fc_sand_x=""
  [ -f "$ROOT/$_p" ] || return 1
  _read_all _c "$ROOT/$_p"
  for _w in "${ALL_MARKS[@]}"; do
    case "$_c" in *"$_w"*) : ;; *) continue ;; esac
    case "$_p" in *.py) _k=py ;; *) _k=sh ;; esac
    face_scan "$_c" "$_k" "${_p##*/}"
    break
  done
  _face_cache["$_p $_udeep"]="$_fc_cls_n|$_fc_trip_n|$_fc_home_n|$_fc_ck_n|$_fc_sand_n|\
$_fc_cls_x|$_fc_trip_x|$_fc_home_x|$_fc_ck_x|$_fc_sand_x"
  return 0
}

# face_args <text> — the ARGV of a registration line or block body: the leg it names (`_fa_leg`), the block
# it calls (`_fa_fn`) and the flags it passes (`_fa_flags`). Words inside a double-quoted string are the
# registration's PROSE — an `item_x` reason is a paragraph about a leg and may name `~/ansible-venv`, `git`
# or a block function without any of that being something the leg runs.
face_args() {
  local _txt="$1" _l="" _w="" _q="" _inq=0
  while IFS= read -r _l; do
    for _w in $_l; do          # split, never glob (`set -f`); an expansion keeps its words' quotes
      _q="${_w//[!\"]}"
      [ $(( ${#_q} % 2 )) = 0 ] || _inq=$(( 1 - _inq ))      # the label opens and closes inside these words
      [ "$_inq" = 1 ] && continue                             # inside the label: prose, never argv
      # `item_q` / `item_blk_x` are the registration call itself, and a word carrying `$` is built at run
      # time — both exist as functions in validate-all.sh, and resolving one as the block would read that
      # function's own body as the leg.
      case "$_w" in item* | *'$'*) continue ;; esac
      case "$_w" in
        --*) _fa_flags="$_fa_flags $_w" ;;
        scripts/*/*.sh | scripts/*/*.py) [ -z "$_fa_leg" ] && _fa_leg="$_w" ;;
        *)
          if [ -z "$_fa_fn" ]; then
            case " $_fn_defs " in *" $_w "*) _fa_fn="$_w" ;; esac
          fi ;;
      esac
    done
  done <<<"$_txt"
  return 0
}

# fn_index — the names validate-all.sh DEFINES, read ONCE into the space-delimited set `_fn_defs`. The
# alternative is a 178 KB substring match per word, a thousand times over, to answer a question the file
# answers once.
fn_index() {
  local _l="" _w=""
  _fn_defs=""
  while IFS= read -r _l; do
    case "$_l" in *'() '*) : ;; *) continue ;; esac
    _w="${_l%%'() '*}"
    case "$_w" in '' | *[![:alnum:]_]*) continue ;; esac
    _fn_defs="$_fn_defs $_w"
  done <<<"$_va"
  return 0
}

# face_walk — THE DERIVATION, over every registration line: the `face` word it declares, weighed against the
# face its facts show. Prints the line the denominator carries and the list of the legs that are not `tree`;
# with SHOW_FACES it also prints one row per registration, so the derivation is auditable and not asserted.
face_walk() {
  local _nl=$'\n' _line="" _decl="" _d="" _n=0 _leg="" _fn="" _body="" _der="" _why="" _ent=""
  local _has_seat="" _has_tree="" _st="" _wrapped="" _l1="" _l2="" _blk_out="" _udeep=""
  local _cls_n=0 _trip_n=0 _home_n=0 _ck_n=0 _sand_n=0 _cls_x="" _trip_x="" _home_x="" _ck_x="" _sand_x=""
  local _n_tree=0 _n_seat=0 _n_joined=0 _n_und=0 _n_bad=0 _n_tot=0 _n_note=0

  _face_seat="" _face_joined=""
  fn_index
  while IFS= read -r _line; do
    _n=$((_n + 1))
    _decl=""
    case "$_line" in
      'face '*) _d="${_line#face }"; _decl="${_d%%[ ;]*}"; _line="${_line#*; }" ;;
    esac
    case "$_line" in item*) : ;; *) continue ;; esac
    case "${_line%%[[:space:]]*}" in *'('*) continue ;; esac     # `item_q() { …` defines; it registers nothing
    _n_tot=$((_n_tot + 1))

    # The three places a leg's subject is written down: the line, the block it calls, the leg file.
    _cls_n=0 _trip_n=0 _home_n=0 _ck_n=0 _sand_n=0
    _cls_x="" _trip_x="" _home_x="" _ck_x="" _sand_x=""
    _fa_leg="" _fa_fn="" _fa_flags=""
    face_args "$_line"
    _leg="$_fa_leg" _fn="$_fa_fn" _body=""
    face_scan "$_line" blk "line$_n"
    _cls_n=$_fc_cls_n _trip_n=$_fc_trip_n _home_n=$_fc_home_n _ck_n=$_fc_ck_n _sand_n=$_fc_sand_n
    _cls_x="$_fc_cls_x" _trip_x="$_fc_trip_x" _home_x="$_fc_home_x" _ck_x="$_fc_ck_x" _sand_x="$_fc_sand_x"
    if [ -z "$_leg" ] && [ -n "$_fn" ]; then
      _blk_out=""
      blk_body "$_fn" || _blk_out=""
      _body="$_blk_out"
      _fa_leg="" _fa_fn="$_fa_fn"
      face_args "$_body"
      [ -n "$_fa_leg" ] && _leg="$_fa_leg"
      face_scan "$_body" blk "line$_n"
      _cls_n=$((_cls_n + _fc_cls_n)); _trip_n=$((_trip_n + _fc_trip_n)); _home_n=$((_home_n + _fc_home_n))
      _ck_n=$((_ck_n + _fc_ck_n)); _sand_n=$((_sand_n + _fc_sand_n))
      _cls_x="$_cls_x $_fc_cls_x" _trip_x="$_trip_x $_fc_trip_x" _home_x="$_home_x $_fc_home_x"
      _ck_x="$_ck_x $_fc_ck_x" _sand_x="$_sand_x $_fc_sand_x"
    fi
    # A CROSSED registration is graded on the leg's UNCONDITIONAL facts, minus what the boundary ledger
    # accepts for that leg: that is exactly the claim `hl_wsl_route` makes when it returns rc, word for word
    # the conjunction in lib/wsl-route.sh. A conditional site is not a fact about the crossing — gate-parity
    # judges those, and the NOT JUDGED line below names them.
    _udeep=""
    if [ -n "$_wrapped" ]; then
      _udeep=1
      case "$_acc $_acc_leg " in *" $_leg:seat "*) _cls_n=0 _cls_x=""; _home_n=0 _home_x="" ;; esac
      case "$_acc $_acc_leg " in *" $_leg:trip "*) _trip_n=0 _trip_x="" ;; esac
    fi
    HL_FACE_UNCOND="$_udeep"
    if [ -n "$_leg" ] && leg_facts "$_leg"; then
      _cls_n=$((_cls_n + _fc_cls_n)); _trip_n=$((_trip_n + _fc_trip_n)); _home_n=$((_home_n + _fc_home_n))
      _ck_n=$((_ck_n + _fc_ck_n)); _sand_n=$((_sand_n + _fc_sand_n))
      _cls_x="$_cls_x $_fc_cls_x" _trip_x="$_trip_x $_fc_trip_x" _home_x="$_home_x $_fc_home_x"
      _ck_x="$_ck_x $_fc_ck_x" _sand_x="$_sand_x $_fc_sand_x"
    fi

    # The narrowing: a `--self-test` registration whose leg builds its OWN sandbox planted the `$HOME` it
    # reads and the socket it opens — a fixture is not seat state. A classifier is not planted with them:
    # it asks which seat it is on wherever it runs, and a crossed answer is an answer about the engine.
    case "$_line$_body" in *hl_wsl_route*) _wrapped=1 ;; *) _wrapped="" ;; esac
    _st=""
    case "$_fa_flags" in *--self-test*) _st=1 ;; esac
    if [ "$_st" = 1 ] && [ "$_sand_n" != 0 ]; then _trip_n=0 _trip_x=""; _home_n=0 _home_x=""; fi

    _has_seat="" _has_tree=""
    [ "$_cls_n" = 0 ]  || _has_seat=1
    [ "$_trip_n" = 0 ] || _has_seat=1
    [ "$_home_n" = 0 ] || _has_seat=1
    [ "$_ck_n" = 0 ]   || _has_tree=1
    if   [ -z "$_has_seat" ]; then _der=tree        # nothing but this checkout, which is what tree MEANS
    elif [ -n "$_has_tree" ]; then _der=joined      # both, so grading one of them in a snapshot proves neither
    else _der=seat
    fi

    case "$_der" in
      tree) _n_tree=$((_n_tree + 1)) ;;
      seat) _n_seat=$((_n_seat + 1)); _face_seat="$_face_seat $_n:${_leg:-$_fn}" ;;
      joined) _n_joined=$((_n_joined + 1)); _face_joined="$_face_joined $_n:${_leg:-$_fn}" ;;
    esac
    [ "$SHOW_FACES" = 1 ] && printf '  %-6s %5d  %-40s cls %s trip %s seat %s ck %s\n' \
      "$_der" "$_n" "${_leg:-${_fn:-a command line}}" "$_cls_n" "$_trip_n" "$_home_n" "$_ck_n"

    if [ -z "$_decl" ]; then
      _n_und=$((_n_und + 1))
      fail "FACE: validate-all.sh:$_n carries no face word — \`face tree|seat|joined;\` belongs before the item call, and \`--profile quick\` refuses the run while one is undecided. The axis is stated in lib/wsl-route.sh."
      continue
    fi
    [ "$_decl" = "$_der" ] && continue

    _why=""
    [ "$_cls_n" = 0 ]  || _why="$_why classifier×$_cls_n${_cls_x:+ ($_cls_x)}"
    [ "$_trip_n" = 0 ] || _why="$_why trip×$_trip_n${_trip_x:+ ($_trip_x)}"
    [ "$_home_n" = 0 ] || _why="$_why seat-state×$_home_n${_home_x:+ ($_home_x)}"
    [ "$_ck_n" = 0 ]   || _why="$_why checkout×$_ck_n${_ck_x:+ ($_ck_x)}"
    [ "$_sand_n" = 0 ] || _why="$_why sandbox×$_sand_n"

    # The one mismatch that costs nothing: a NATIVE line claiming MORE seat than its facts show. It refuses a
    # free grading rather than trading in a wrong one — A7's direction, and the reason it is a NOTE. On a
    # WRAPPED line the same word is a finding, because there the runner crosses it.
    if [ -z "$_wrapped" ] && [ "$_decl" = seat ] && [ "$_der" = tree ]; then
      _n_note=$((_n_note + 1))
      printf 'NOTE: face — validate-all.sh:%s declares `face seat'"'"' while the derivation says `tree'"'"' (%s): no seat fact answers, so the tree face could grade this leg and is not being offered it.\n' \
        "$_n" "${_leg:-$_fn}"
      continue
    fi
    _n_bad=$((_n_bad + 1))
    if [ -n "$_wrapped" ]; then
      fail "FACE: validate-all.sh:$_n declares \`face $_decl' on a line the runner CROSSES, where its facts say \`$_der' ($_why). A crossed leg whose SUBJECT reads seat state is graded in neither face: the snapshot cannot see the seat and the crossing answers the questions about the engine. UNWRAP it (the conjunction in lib/wsl-route.sh already forbids the trip or classifier — SEAT / TRIP name any unconditional one), or, where the facts are tree-and-sandbox only, write \`face tree'."
    else
      fail "FACE: validate-all.sh:$_n declares \`face $_decl' and the derivation says \`$_der' ($_why). The face is derived from what the leg reads — the classifier, the trip, the seat-\$HOME path, the checkout read — so the word on the line is a claim being graded and not a label that can rot. Change the word, or change what the leg reads."
    fi
  done <<<"$_va"

  _face_note="faces $_n_tot registration(s): $_n_tree tree · $_n_joined joined · $_n_seat seat, undecided $_n_und"
  printf 'FACE: %s registration(s) derived — %s tree · %s joined · %s seat · %s undecided · %s contradicted · %s note\n' \
    "$_n_tot" "$_n_tree" "$_n_joined" "$_n_seat" "$_n_und" "$_n_bad" "$_n_note"
  _l1="${_face_seat# }"; [ -n "$_l1" ] || _l1="none"
  _l2="${_face_joined# }"; [ -n "$_l2" ] || _l2="none"
  printf '      seat:   %s\n      joined: %s\n' "$_l1" "$_l2"
  return 0
}

# --------------------------------------------------------------------------- #
# THE CHECK                                                                   #
# --------------------------------------------------------------------------- #
check_tree() {
  local _files="" _f="" _c="" _ln="" _names="" _t=""
  local _pre="" _rest="" _leg="" _line="" _arg="" _dn="" _va="" _acc="" _df=0 _s="" _i=""
  local _wline="" _fn="" _bp="" _bc="" _br="" _av="" _site=0 _known=0 _live=0 _nv_leg=0 _nv_site=0
  local _cont=0
  local decl_files=0 decl_n=0 wrapped=0 resolved=0
  local nl=$'\n'        # a function definition is found at a LINE start, which is what `case` needs

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

  # REGISTRATION + CONJUNCTION — one pass over the registration lines. A wrap is a wrap whether
  # `hl_wsl_route` sits on the item line or inside the block the line calls, and a declaring leg has to use
  # the second form, so both forms are resolved rather than only the one that is easy to grep.
  _read_all _va "$ROOT/scripts/validate-all.sh"
  _b_leg=(); _b_seat=(); _b_trip=(); _b_nv=(); _b_argv=()
  while IFS= read -r _line; do
    # A registration may state its FACE before the item call (`face seat; item_x "…" …`). That word is a
    # decision AT the registration line, not a second registry, so the reader strips it and weighs the
    # registration underneath; `face` is what the face half below grades.
    case "$_line" in 'face '*) _line="${_line#*; }" ;; esac
    case "$_line" in item*) : ;; *) continue ;; esac
    _wline="$_line" _fn=""
    case "$_line" in
      *hl_wsl_route*) : ;;
      *)  for _arg in $_line; do
            case "$_arg" in item* | *[\"$]*) continue ;; esac
            case "$_va" in *"$nl$_arg() "*) _fn="$_arg"; break ;; esac
          done
          [ -n "$_fn" ] || continue          # a registration that runs a command, not a block
          _wline="$(blk_wrap_line "$_fn")" || continue ;;
    esac
    wrapped=$((wrapped + 1))
    _leg=""
    for _arg in $_wline; do
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
      has_name "$_line $_wline" "$_t" \
        || fail "REGISTRATION: $_leg declares \`$_t\` but its registration does not name it — the line is where a reader learns what the engine has to have"
    done

    # VERDICT — a leg that declares a real tool answers rc 2 the moment an engine lists that name ABSENT,
    # and an item line that reads the leg's rc as its verdict turns that boundary into a FAILED run. The
    # block is what maps it: same leg, same answer, said in the words the run already prints.
    if [ "$_line" = "$_wline" ] && [ -n "${_dn// /}" ]; then
      fail "VERDICT: $_leg declares ($_dn) and its registration reads the leg's rc as the verdict — register a declaring leg through a block that maps rc 2 to a NOTE (the shape of blk_rsync_max_delete), or keep the leg native"
    fi

    # The conjunction, on this leg.
    wrap_scan "$_leg"
    _b_leg+=("$_leg"); _b_seat+=("$_ws_seat"); _b_trip+=("$_ws_trip"); _b_nv+=("$_ws_nv")
    _av="${_wline#*hl_wsl_route }"          # the argv ONLY: the labels are prose, not part of the command
    _b_argv+=("$_av")
  done <<<"$_va"

  # THE BOUNDARY LEDGER — this repo's exception idiom: one accepted wrong-seat boundary per line, each
  # printed as a named NOTE, each REDEEMED by the tree. A leg no longer wrapped, or one that no longer
  # trips the class its line names, reddens: that is what keeps an exception file from aging into a mute
  # button, and why the file holds one line per leg rather than one line per class of leg.
  _acc=""
  if [ -f "$ROOT/$BOUNDARIES" ]; then
    while IFS=$'\t' read -r _bp _bc _br; do
      case "$_bp" in '' | '#'*) continue ;; esac
      _known=0 _live=0
      case "$_bc" in
        seat | trip) : ;;
        *) fail "BOUNDARY: $BOUNDARIES names class \`$_bc\` for $_bp — the classes are seat and trip" ;;
      esac
      [ "${#_br}" -ge 40 ] \
        || fail "BOUNDARY: $BOUNDARIES gives $_bp a reason under 40 characters — the reason IS the argument, and a short one is a mute button"
      for _i in "${!_b_leg[@]}"; do
        [ "${_b_leg[$_i]}" = "$_bp" ] || continue
        _known=1
        case "$_bc" in
          seat) case "${_b_seat[$_i]}" in *:*) _live=1 ;; esac ;;
          trip) case "${_b_trip[$_i]}" in *:*) _live=1 ;; esac ;;
        esac
      done
      [ "$_known" = 1 ] \
        || { fail "BOUNDARY: $BOUNDARIES accepts $_bp, which no registration wraps any more — delete the line in the change that unwraps the leg"; continue; }
      [ "$_live" = 1 ] \
        || { fail "BOUNDARY: $BOUNDARIES accepts a $_bc boundary at $_bp that the leg no longer trips — the line is dead, delete it"; continue; }
      _acc="$_acc $_bp:$_bc"
      printf 'NOTE: boundary accepted — %s (%s): %s\n' "$_bp" "$_bc" "$_br"
    done <"$ROOT/$BOUNDARIES"
  else
    printf 'NOTE: no boundary ledger at %s — every wrapped leg that classifies its seat or opens a vault,\n' "$BOUNDARIES"
    printf '      ssh or network trip at top level is a finding, and a real accepted boundary has no home.\n'
  fi
  for _i in "${!_b_leg[@]}"; do
    for _s in ${_b_seat[$_i]}; do
      case "$_acc" in
        *"${_b_leg[$_i]}:seat"*) : ;;
        *) fail "SEAT: $_s — a leg registered through hl_wsl_route classifies the seat it runs on, so crossed it answers about the ENGINE and not about the seat the verdict is for (the conjunction in lib/wsl-route.sh). Unwrap it, or book it in $BOUNDARIES with its reason." ;;
      esac
    done
    for _s in ${_b_trip[$_i]}; do
      case "$_acc" in
        *"${_b_leg[$_i]}:trip"*) : ;;
        *) fail "TRIP: $_s — a leg registered through hl_wsl_route opens a vault/ssh/network trip at top level, where every registered mode reaches it, so it opens it on BOTH sides of the door. Unwrap it, or book it in $BOUNDARIES with its reason." ;;
      esac
    done
  done

  # THE FACE — every registration line's word, weighed against the derivation. Its own findings print as it
  # walks; the counts land in the denominator below.
  face_walk

  # NOT JUDGED, in the open: the sites a function body may or may not hide from the registered argv.
  # Guessing either way would be wrong in one direction, so the blind spot is named with the command that
  # closes it, beside what WAS judged.
  _nv_leg=0 _nv_site=0
  for _i in "${!_b_leg[@]}"; do
    [ "${_b_nv[$_i]}" != 0 ] || continue
    _nv_leg=$((_nv_leg + 1))
    _nv_site=$((_nv_site + ${_b_nv[$_i]}))
    printf 'NOT JUDGED: %s — %s conditional seat/trip site(s); whether the registered argv reaches them is a parity question, re-derive with: bash scripts/bench/win/gate-parity.sh -- %s\n' \
      "${_b_leg[$_i]}" "${_b_nv[$_i]}" "${_b_argv[$_i]}"
  done
  [ "$_nv_leg" = 0 ] \
    || printf 'NOT JUDGED: %s site(s) across %s wrapped leg(s). Judged here: every top-level seat/vault/ssh/network site and every declaration. Not judged: one live crossing per leg — a parity instrument, not a grep.\n' "$_nv_site" "$_nv_leg"

  # The honest denominator, printed whether or not anything was found: a rule that read nothing must
  # never look like a pass.
  _note="declarations $decl_n in $decl_files file(s) · wrapped legs $resolved/$wrapped registration(s) named a leg path · tools the probe asks: $(printf '%s\n' "$_asked" | wc -w) · $_face_note"
  if [ "$decl_n" = 0 ]; then
    if [ "$wrapped" != 0 ]; then
      printf 'CANNOT RUN: %s registration(s) cross the door and nothing in this tree declares its\n' "$wrapped"
      printf '      engine tools — the half of the contract the tree is supposed to carry was never\n'
      printf '      exercised, and a green here would be a green about planted strings. The shape to copy\n'
      printf '      is scripts/testdata/leg-contract/run.sh: one wrapped leg that names what it needs.\n'
      return 2
    fi
    printf 'NOTE: no leg on this tree declares its engine tools, and no leg is wrapped either — the rule\n'
    printf '      has no subject here, so the arms are the proof. A wrapped leg that shells out to a tool\n'
    printf '      is what adds a declaration.\n'
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
# THE DOOR ARMS — the in-tree declaring leg, driven by planted answers.                #
# --------------------------------------------------------------------------- #
# WHY NO ENGINE IS SPAWNED HERE: `hl_wsl_needs` grades a name against the answer the probe put on the
# guest env, so planting THAT is what grades the leg's use of it — which is the whole subject of these
# arms. The door is proved by `lib/wsl-route.sh --self-test` through its own stub launcher, and a leg's
# native-versus-crossed PAIR belongs to `bench/win/gate-parity.sh`; a checker that paid a crossing per
# arm would buy a slower checker, not a truer one. The inventory's name arrives COMPOSED ($INV_VAR) for
# the reason the canaries compose it: this file may not contain the string its own INVENTORY rule hunts.
# `pi-tui-config --self-test`'s `pinned-node` arm is the crossed-side pointer for why no arm here names a
# runtime: the engine's node sits behind the PATH pin whose widening docs/harness-rejected.md declines.
door_arms() {
  local _leg="$ROOT/scripts/testdata/leg-contract/run.sh" _out="" _rc=0 _bad=0
  [ -f "$_leg" ] \
    || { printf 'CANNOT RUN: no declaring leg at %s — the door arms need a leg that declares something\n' "$_leg"; return 2; }
  printf '== leg contract: the declaring leg, driven by planted answers ==\n'

  # 1 · answered. The leg runs, and says it ran: an answer that stops a leg it should let through is the
  #     refusal that gets a working wrap unwrapped for the wrong reason.
  _out="$( export "$INV_VAR=answered — rsync=/usr/bin/rsync"; bash "$_leg" --declare-only 2>&1 )"; _rc=$?
  if [ "$_rc" = 0 ] && has "$_out" 'ran past its declaration' && ! has "$_out" 'CANNOT RUN'; then
    printf '  ok: answered tool → rc 0 and the leg ran\n'
  else
    printf 'FAIL: DOOR: an answered tool stopped the leg (rc %s)\n      | %s\n' "$_rc" "$_out"
    _bad=$((_bad + 1))
  fi

  # 2 · ABSENT. rc 2, and the words must name BOTH the tool and the inventory the refusal was read
  #     against — a CANNOT RUN that quotes nothing is a boundary nobody can check.
  _out="$( export "$INV_VAR=answered — bash=/usr/bin/bash · ABSENT — rsync"; bash "$_leg" --declare-only 2>&1 )"; _rc=$?
  if [ "$_rc" = 2 ] && has "$_out" 'CANNOT RUN' && has "$_out" 'rsync' && has "$_out" 'ABSENT — rsync' \
     && ! has "$_out" 'ran past its declaration'; then
    printf '  ok: ABSENT tool → rc 2 naming the tool and quoting the inventory\n'
  else
    printf 'FAIL: DOOR: an ABSENT tool did not refuse the way the contract says (rc %s)\n      | %s\n' "$_rc" "$_out"
    _bad=$((_bad + 1))
  fi

  # 3 · no inventory in hand — the shape `HL_WSL=off`, a Debian seat and a declined argv head all look
  #     like from in here. rc unchanged, the leg ran, and NOTHING was said: a leg that refuses on its own
  #     seat is one answering a question its own probe answers better.
  _out="$( unset -v "$INV_VAR"; bash "$_leg" --declare-only 2>&1 )"; _rc=$?
  if [ "$_rc" = 0 ] && has "$_out" 'ran past its declaration' && ! has "$_out" 'CANNOT RUN'; then
    printf '  ok: no inventory in hand → ran at home, rc unchanged, silent\n'
  else
    printf 'FAIL: DOOR: a leg with no inventory was talked out of running (rc %s)\n      | %s\n' "$_rc" "$_out"
    _bad=$((_bad + 1))
  fi

  # 4 · the probe answered NOTHING. Still rc 2, but as UNPROVEN: "nobody answered" and "it is not there"
  #     are different sentences, and collapsing them would let an engine outage read as a missing tool.
  _out="$( export "$INV_VAR=unknown"; bash "$_leg" --declare-only 2>&1 )"; _rc=$?
  if [ "$_rc" = 2 ] && has "$_out" 'unproven' && ! has "$_out" 'does not answer for it'; then
    printf '  ok: the probe answered nothing → rc 2 as unproven, not as absent\n'
  else
    printf 'FAIL: DOOR: an unanswered inventory was not called a boundary (rc %s)\n      | %s\n' "$_rc" "$_out"
    _bad=$((_bad + 1))
  fi

  [ "$_bad" = 0 ] || { printf '\n%s door finding(s)\n' "$_bad"; return 1; }
  return 0
}
# --------------------------------------------------------------------------- #
# SELF-TEST — every rule breeds its finding, and the legal shape stays green.          #
# --------------------------------------------------------------------------- #
_st_n=0
_st_f=0
_st_out=""
_st_ok() { printf '  ok: %s\n' "$*"; _st_n=$((_st_n + 1)); }
_st_no() { printf 'SELFTEST FAIL: %s\n' "$*"; _st_f=$((_st_f + 1)); }

# _st_tree <dir> — the legal shape: the real lib, one named+guarded+asked declaration, and a
# registration that names the tool. Every canary below mutates ONE thing out of it.
_st_tree() {
  # The planted paths are REAL paths of this repo, in a tree that does not carry them all: a literal
  # `scripts/<path>` in a tracked script is a COMMAND that check_script_layout.py resolves, and the
  # finding a canary breeds is about the PLANTED tree, which is where the path has to be missing.
  local d="$1"
  mkdir -p "$d/scripts/lib" "$d/scripts/testdata/leg-contract" "$d/scripts/gate" || return 1
  cp "$REPO/scripts/lib/wsl-route.sh" "$d/scripts/lib/wsl-route.sh" || return 1
  # The declaration name is COMPOSED here, for the reason the inventory names are composed: heredoc text
  # is file text, and a literal planted leg in this checker's own body is read back by the corpus walk as
  # a declaration IN THE TREE — a denominator the checker inflates about itself.
  cat >"$d/scripts/testdata/leg-contract/run.sh" <<LEG
#!/usr/bin/env bash
# A planted leg in the contract's legal shape: a named, guarded declaration of a tool the probe asks.
${NEEDS} rsync || exit \$?
printf 'ok  the leg ran\n'
LEG
  # A declaring leg is registered through a BLOCK, because its rc 2 is a boundary and an item line would
  # read it as a verdict (VERDICT below) — so the legal shape has to be the shape the rule asks for.
  cat >"$d/scripts/validate-all.sh" <<'REG'
#!/usr/bin/env bash
blk_st_leg() {
  local rc_s=0
  hl_wsl_route bash scripts/testdata/leg-contract/run.sh --self-test || rc_s=$?
  case "$rc_s" in 0) return 0 ;; 2) return 0 ;; *) return "$rc_s" ;; esac
}
item_q "run.sh --self-test (the planted leg; its engine needs rsync)" blk_st_leg
REG
  # The ledger exists with no lines: an accepted boundary is a thing the tree has to decide, not a shape
  # the canaries get by the file being absent.
  printf '# planted ledger: no boundary accepted here\n' >"$d/scripts/gate/leg_contract_boundaries.txt"
  return 0
}

_st_run() { # _st_run <tree> -> the checker's rc on that tree, its text in _st_out
  local _rc=0
  _st_out="$(bash "${BASH_SOURCE[0]}" --root "$1" 2>&1)" || _rc=$?
  return $_rc
}

# _st_breed <name> <want-rc> <file> <one line appended> <why> — mutate ONE thing out of the legal tree.
# The locals are split on purpose: `local x="$1" d="$x"` expands `$x` BEFORE the assignment lands, so on
# a `set -u` seat the second name is an unbound variable and the whole self-test dies on line one.
_st_breed() {
  local name="$1" want="$2" file="$3" body="$4" why="$5" _rc=0
  local _needle="${6:-}" _d="$_st_tmp/$name"
  if ! _st_tree "$_d"; then _st_no "$name: the tree could not be built"; return 0; fi
  printf '%s\n' "$body" >>"$_d/$file"
  _st_run "$_d"; _rc=$?
  if [ "$_rc" != "$want" ]; then
    _st_no "$name answered rc $_rc, want $want ($why)"
    return 0
  fi
  # The rc alone cannot say WHICH rule reddened: a canary that reddens for a reason outside its own rule
  # would pass here and lie, so the finding's own prefix is asserted when one was given.
  if [ -n "$_needle" ] && ! has "$_st_out" "$_needle"; then
    _st_no "$name answered rc $_rc but bred no \`$_needle\` ($why)"
    return 0
  fi
  _st_ok "$name → rc $_rc ($why)"
}

# _st_multiline <name> <want-rc> <file> <heredoc body> <why> — the same, for a canary whose shape IS
# multiple lines (a call site continued with backslashes cannot be passed as one argument).
# _st_two <name> <want-rc> <file a> <line a> <file b> <line b> <why> [needle] — the same, for a canary
# whose shape is TWO files: an accepted boundary is a leg AND a ledger line, and mutating one of them
# alone would breed a different finding than the one the arm names.
_st_two() {
  local name="$1" want="$2" fa="$3" ba="$4" fb="$5" bb="$6" why="$7" _rc=0
  local _needle="${8:-}" _d="$_st_tmp/$name"
  if ! _st_tree "$_d"; then _st_no "$name: the tree could not be built"; return 0; fi
  printf '%s\n' "$ba" >>"$_d/$fa"
  printf '%s\n' "$bb" >>"$_d/$fb"
  _st_run "$_d"; _rc=$?
  if [ "$_rc" != "$want" ]; then
    _st_no "$name answered rc $_rc, want $want ($why)"
    return 0
  fi
  if [ -n "$_needle" ] && ! has "$_st_out" "$_needle"; then
    _st_no "$name answered rc $_rc but bred no \`$_needle\` ($why)"
    return 0
  fi
  _st_ok "$name → rc $_rc ($why)"
}

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

  _st_breed unasked 1 scripts/testdata/leg-contract/run.sh 'hl_wsl_needs nosuchtool || exit 2' \
    "an unasked name can only ever read as absent; the probe has to be told to ask" 'DECLARATION:'
  _st_breed unguarded 1 scripts/testdata/leg-contract/run.sh 'hl_wsl_needs jq' \
    "a discarded rc: the claim cannot stop the leg, which is the rc-0-lies shape" 'DECLARATION:'
  _st_breed noname 1 scripts/testdata/leg-contract/run.sh 'hl_wsl_needs || exit 2' \
    "a declaration that names nothing declares nothing" 'DECLARATION:'
  _st_breed varname 1 scripts/testdata/leg-contract/run.sh 'hl_wsl_needs "$HL_LEG_TOOL" || exit 2' \
    "a name from the environment is a name no inventory answers for" 'DECLARATION:'
  _st_breed twoclaims 1 scripts/testdata/leg-contract/run.sh 'hl_wsl_needs none rsync || exit 2' \
    "claiming none and a name at once claims nothing" 'DECLARATION:'
  _st_breed secondspelling 1 scripts/testdata/leg-contract/run.sh 'if [ -n "${'"$INV_VAR"':-}" ]; then :; fi' \
    "the engine-tool question asked twice is the per-leg rediscovery the lib exists to stop" 'INVENTORY:'
  _st_breed pinnedruntime 1 scripts/testdata/leg-contract/run.sh 'hl_wsl_needs node || exit 2' \
    "naming a pinned runtime assumes the engine's node, which the declined pin refuses" 'RUNTIME:'
  _st_breed noregname 1 scripts/validate-all.sh \
    'item_q "a second wrap of the same leg, tool unnamed" hl_wsl_route bash scripts/testdata/leg-contract/run.sh --check' \
    "a wrap whose line hides the tool sends the reader to the engine blind" 'REGISTRATION:'
  # The path is a real script of this repo that the planted tree does not carry — see _st_tree.
  _st_breed missingleg 1 scripts/validate-all.sh \
    'item_q "a wrap of a leg that is not there" hl_wsl_route bash scripts/harness/pi-self-update.sh --self-test' \
    "a wrapped leg has to exist" 'does not exist'

  # The conjunction, seen from the tree: a wrapped leg that classifies its seat, opens a vault/ssh/network
  # trip where every mode reaches it, or reports a declaring leg's rc as the run's verdict.
  _st_breed seatwrap 1 scripts/testdata/leg-contract/run.sh 'hl_wsl_class >/dev/null 2>&1 || true' \
    "a leg that asks which seat it is on answers for the wrong seat once it crosses" 'SEAT:'
  _st_breed tripwrap 1 scripts/testdata/leg-contract/run.sh 'ssh -o BatchMode=yes somewhere uptime || true' \
    "a trip at column 0 runs on both sides of the door, which is what the conjunction forbids" 'TRIP:'
  _st_breed verdict 1 scripts/validate-all.sh \
    'item_q "a declaring leg wrapped straight onto the item line (needs rsync)" hl_wsl_route bash scripts/testdata/leg-contract/run.sh' \
    "a declaring leg's rc 2 is a boundary, not a failed run — it belongs in a block or stays native" 'VERDICT:'

  # The silence half: each shape below MENTIONS the declaration without CALLING it, and must answer rc 0
  # in a tree that already holds one legal declaration. A parser that reads prose, redirections or line
  # breaks as call sites reddens a leg for the shape of its comments — the false-positive class that
  # makes a checker get muted, so it is fenced here rather than in an audit note.
  _st_breed prosecomment 0 scripts/testdata/leg-contract/run.sh '# the rule: hl_wsl_needs rsync || exit 2 stops the leg' \
    "a comment about the rule is prose, not a call site"
  _st_breed prosestring 0 scripts/testdata/leg-contract/run.sh \
    "printf 'usage: call hl_wsl_needs with the tools this leg shells out to\n' >&2" \
    "an error string that spells the name is prose, not a call site"
  _st_breed redirection 0 scripts/testdata/leg-contract/run.sh 'hl_wsl_needs rsync >/dev/null 2>&1 || exit $?' \
    "a redirection says where the output goes, not what the leg needs"
  _st_multiline continuation 0 scripts/testdata/leg-contract/run.sh \
    "a declaration split by backslashes is one call site, not three" <<CONT
${NEEDS} \\
  rsync \\
  || exit \$?
CONT

  # The door half, in the tree: the declaring leg driven by four planted answers. Its verdicts print
  # themselves, so a failure here names the arm — and the leg it drives is the same file the real-tree
  # check reads, which is what keeps a canary and the tree from holding two opinions.
  printf '== the door arms ==\n'
  if door_arms; then
    _st_ok "the in-tree declaring leg answered the door all four ways"
  else
    _st_no "a door arm lost its verdict — bash scripts/gate/check-leg-contract.sh --arms prints which one"
  fi

  # The ledger, both alive and dead. An exception that cannot be invalidated is a mute button, so the
  # file is graded in both directions: what it accepts must still be a boundary, and a boundary that
  # stopped being one reddens the file that accepted it.
  # The ledger, in both directions. An exception nobody can invalidate is a mute button, so the file is
  # graded against the tree: what it accepts has to still BE a boundary (a leg that is still wrapped and
  # still trips the class named), and a line whose leg moved on reddens the file that trusted it.
  _st_two boundary_live 0 scripts/testdata/leg-contract/run.sh 'hl_wsl_class >/dev/null 2>&1 || true' \
    scripts/gate/leg_contract_boundaries.txt $'scripts/testdata/leg-contract/run.sh\tseat\tthe planted leg classifies its seat, and the reason is long enough to be an argument' \
    "an accepted boundary prints a NOTE and leaves the tree green" 'NOTE: boundary accepted'
  _st_breed boundary_dead 1 scripts/gate/leg_contract_boundaries.txt \
    $'scripts/harness/sync-extensions.sh\ttrip\ta leg that no registration wraps any more, with a reason long enough to be an argument' \
    "a dead exception line reddens: the register cannot rot into a mute button" 'BOUNDARY:'
  _st_two boundary_wrong 1 scripts/testdata/leg-contract/run.sh 'ssh -o BatchMode=yes somewhere uptime || true' \
    scripts/gate/leg_contract_boundaries.txt $'scripts/testdata/leg-contract/run.sh\tseat\tthe leg opens a trip, while this line excuses the seat class it never claimed' \
    "an exception excuses the class it names and never the other one" 'BOUNDARY:'
  _st_two boundary_short 1 scripts/testdata/leg-contract/run.sh 'hl_wsl_class >/dev/null 2>&1 || true' \
    scripts/gate/leg_contract_boundaries.txt $'scripts/testdata/leg-contract/run.sh\tseat\tbecause yes' \
    "a reason under 40 characters is an amnesty, not an argument" 'BOUNDARY:'

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
    door_arms; exit $? ;;
  --faces)
    SHOW_FACES=1
    check_tree; report $?; exit $? ;;
  "")
    check_tree; report $?; exit $? ;;
  -h | --help)
    # The header IS the usage: printed to the first non-comment line, so it cannot drift from the file's
    # length the way a fixed `sed -n 1,52p` does.
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"
    exit 0 ;;
  *)
    printf 'usage: bash scripts/gate/check-leg-contract.sh [--root DIR | --self-test | --arms]\n' >&2
    exit 2 ;;
esac
