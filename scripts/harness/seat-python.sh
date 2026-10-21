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
#      bash scripts/harness/seat-python.sh --self-test          (both halves, stubbed)
#
# SELF-TEST: stubbed `uname` + stubbed interpreters on PATH, so the verdict is
# WHICH launcher got exec'd. Proven by mutation: swap the two branches and both
# arms go red (CONVENTIONS §6 — a test that cannot fail is not evidence).
# =====================================================================
set -uo pipefail

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
  rm -rf "$t"
  [ "$fails" -eq 0 ] || printf 'seat-python.sh self-test: %s arm(s) NOT caught\n' "$fails" >&2
  exit "$fails"
fi

case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) exec py -3 "$@" ;;
esac
exec python3 "$@"
