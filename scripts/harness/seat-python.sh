#!/usr/bin/env bash
# =====================================================================
# harness/seat-python.sh — run a repo python script with the interpreter
# THIS box answers (the fix; the rule is docs/harness-pi-seats.md §1).
# ---------------------------------------------------------------------
# WHY: a seat plane command is COMPOSED on the driver and EXECUTED in the
# seat's own shell. Choosing the launcher while composing asks the wrong
# machine: a Windows driver that emits `py -3 …` ships a Windows command
# line into a Debian seat, where it dies at `py: command not found` and
# reads as drift on exactly one plane — with no gate predicting it, because
# the same registry line runs green from either end. So the per-box case
# travels INSIDE the command, and the box that runs it answers.
#
# The case itself is the fact the seat family already carried: on a Windows
# seat `python3` resolves to the Microsoft-Store alias stub and `py -3` is
# the interpreter; on a Debian seat `python3` IS the interpreter and there is
# no `py` at all.
#
# USE: bash scripts/harness/seat-python.sh <script> [args…]     (exec'd, never wrapped)
#      bash scripts/harness/seat-python.sh --self-test          (four arms, stubbed)
#
# NO SCRIPT ARGUMENT IS A REFUSAL, NOT A REPL: the file ends in `exec <interp> "$@"`, and an empty
# "$@" is a bare launcher — an interactive interpreter reading the stdin its caller handed it, which
# never returns and is never reaped. So `$#` 0 exits 2 naming the USE line, and BOTH exec lines carry
# `< /dev/null` so a wrapper can never hand the child the caller's stdin even with arguments present.
# (`bash scripts/lib/vault_read.py --self-test` is how the shape appears without anyone typing the
# wrapper: bash parses that Python as shell, a `"""` line becomes a quoted string that swallows the
# lines after it, and the words inside are word-expanded into a command — CONVENTIONS §6's
# interpreter rule is the entry point to that one.) `timeout` in a caller hides the symptom; the
# refusal is the fix.
#
# SELF-TEST: stubbed `uname` + stubbed interpreters on PATH, so the verdict is
# WHICH launcher got exec'd. Proven by mutation: swap the two branches and both
# arms go red (CONVENTIONS §6 — a test that cannot fail is not evidence). The
# third arm runs the wrapper BARE against those same stubs: no `interp=` line may appear and rc must
# be 2, which is why the shape is caught by a test rather than by an hour of hung legs. The fourth
# pipes a marker into the wrapper and requires a stdin-reading stub to never see it.
# =====================================================================
set -uo pipefail

# A bare call is the hang, so it answers before anything else does — and it never reaches an
# interpreter, which is what the third self-test arm grades.
if [ "$#" -eq 0 ]; then
  printf 'seat-python: no script argument — this wrapper execs an interpreter, so a bare call opens a REPL on the caller stdin and never returns.\n%s\n' \
    "USE: bash scripts/harness/seat-python.sh <script> [args…]" >&2
  exit 2
fi

if [ "${1:-}" = "--self-test" ]; then
  t="$(mktemp -d)"
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  self="$here/$(basename "${BASH_SOURCE[0]}")"
  # Two fake boxes, identical interpreter stubs; only `uname` differs. The stub prints
  # WHICH file got exec'd, so an inverted case cannot pass by running the right script.
  for d in "$t/lin" "$t/win"; do
    mkdir -p "$d"
    printf '%s\n' '#!/bin/sh' 'printf "interp=PY3 args=%s\n" "$*"' >"$d/python3"
    printf '%s\n' '#!/bin/sh' 'printf "interp=PYLAUNCHER args=%s\n" "$*"' >"$d/py"
    chmod +x "$d/python3" "$d/py"
  done
  printf '%s\n' '#!/bin/sh' 'printf "Linux\n"' >"$t/lin/uname"
  printf '%s\n' '#!/bin/sh' 'printf "MINGW64_NT-10.0-19045\n"' >"$t/win/uname"
  chmod +x "$t/lin/uname" "$t/win/uname"

  fails=0
  got="$(PATH="$t/lin:$PATH" bash "$self" a.py --check)"
  case "$got" in
    interp=PY3*--check*) printf 'ok: a Debian box runs python3\n' ;;
    *) printf 'NOT CAUGHT: a Linux-class box got: %s\n' "$got"; fails=$((fails + 1)) ;;
  esac
  got="$(PATH="$t/win:$PATH" bash "$self" a.py --check)"
  case "$got" in
    interp=PYLAUNCHER*--check*) printf 'ok: a Windows box runs py -3\n' ;;
    *) printf 'NOT CAUGHT: a Windows-class box got: %s\n' "$got"; fails=$((fails + 1)) ;;
  esac
  # The bare call, against the SAME stubbed interpreters: with the guard gone this line execs a stub
  # and prints `interp=`, so the arm reddens instead of hanging on a real REPL.
  bare="$(PATH="$t/win:$PATH" bash "$self" 2>&1 </dev/null)"; bare_rc=$?
  case "$bare" in
    *interp=*) printf 'NOT CAUGHT: a bare call execs an interpreter: %s\n' "$bare"
               fails=$((fails + 1)) ;;
    *) if [ "$bare_rc" -eq 2 ] && printf '%s' "$bare" | grep -q 'USE:'; then
         printf 'ok: a bare call is refused at rc 2 and names the USE line\n'
       else
         printf 'NOT CAUGHT: a bare call answered rc %s with: %s\n' "$bare_rc" "$bare"
         fails=$((fails + 1))
       fi ;;
  esac
  # Fourth: the other half of the same trap — a child that INHERITS the caller's stdin. This stub
  # cats its stdin, so the answer is the pipe: `< /dev/null` on the exec lines makes it empty, and
  # take it away and this arm prints the marker. A stub that ignored stdin would pass either way,
  # which is the difference between an arm and a decoration.
  mkdir -p "$t/pipe"
  printf '%s\n' '#!/bin/sh' 'cat' >"$t/pipe/python3"
  printf '%s\n' '#!/bin/sh' 'printf "Linux\n"' >"$t/pipe/uname"
  chmod +x "$t/pipe/python3" "$t/pipe/uname"
  leak="$(printf 'SHOULD-NOT-REACH-CHILD\n' | PATH="$t/pipe:$PATH" bash "$self" a.py 2>&1)"
  case "$leak" in
    *SHOULD-NOT-REACH-CHILD*) printf 'NOT CAUGHT: the child inherited the caller stdin\n'
                              fails=$((fails + 1)) ;;
    *) printf 'ok: the child never inherits the caller stdin\n' ;;
  esac
  rm -rf "$t"
  [ "$fails" -eq 0 ] || printf 'seat-python.sh self-test: %s arm(s) NOT caught\n' "$fails" >&2
  exit "$fails"
fi

case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) exec py -3 "$@" </dev/null ;;
esac
exec python3 "$@" </dev/null
