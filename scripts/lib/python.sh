#!/usr/bin/env bash
# =====================================================================
# lib/python.sh — the ONE Python launcher probe for bash callers
# ---------------------------------------------------------------------
# WHY: the gate probes for an interpreter (validate-all.sh §launcher) because a NAME is not an answer
# on a Windows seat — the Microsoft Store's `python3` alias STUB sits on PATH, `command -v python3`
# finds it, it is not an interpreter, and it exits 49 printing "Python was not found". The bench legs
# never got that lesson and say `python3 script.py` outright, so on the Win11 seat their fixtures die
# with `ERROR: the plan could not be derived` and the Store's own advertisement in place of a verdict
# — while the SAME commit is green on the two Debian seats. One decision, probed twice, is how a fleet
# ends up with a verdict that is true per seat. This file is that one decision.
#
# HOW: `hl_python [module …]` probes candidates in order and leaves the winner in the ARRAY
# `HL_PYTHON`, argv-shaped. The array is the point: the Windows launcher is TWO words (`py -3`), and a
# scalar either re-splits when quoted wrong or execs a program literally named "py -3" when quoted
# right (CONVENTIONS §6, the interpreter-quoting rule). Call it quoted, always:
#
#   hl_source_lib "${BASH_SOURCE[0]}" python.sh
#   hl_python                       # any interpreter that runs
#   hl_python jinja2 yaml           # one that can import these, or a loud stop
#   "${HL_PYTHON[@]}" scripts/bench/spark-llm-probe.py …
#
# `HL_PYTHON=x` in the environment wins unchecked — that is how a wrapper pins the interpreter, and
# how a fixture injects a stub to prove this probe is load-bearing.
#
# SELF-TEST: bash scripts/lib/python.sh --self-test
#   Five arms, each breedable: a Store-stub-shaped candidate must NOT be chosen, a candidate that
#   cannot import the named module must not be chosen either, when nothing works the answer is rc 1
#   with the candidate list printed — never an empty argv that the caller would exec as `""`, a
#   two-word launcher arrives as two argv entries, and the UTF-8 pin is scoped to the seat class that
#   needs it.
# =====================================================================

HL_PYTHON=()
_HL_PYTHON_DONE=0

# hl_python_env [uname-string] — the UTF-8 pin's fleet-wide home, next to the launcher it governs.
# `validate-all.sh` exported PYTHONUTF8 for its own children, so a gate leg answered one question when
# the pool ran it and another when a person ran the same file straight from a Win11 prompt — the tree is
# UTF-8 and git answers in UTF-8, while a Windows-native interpreter decodes a pipe with the ANSI
# codepage unless told otherwise (a non-decodable byte leaves stdout None, and the checker reports
# `'NoneType' object has no attribute 'split'` as if it were a finding about the tree). The launcher and
# the encoding are one decision about the same child process, so they live in one file, and the pin is
# scoped to the seats that need it: on POSIX the interpreter already reads UTF-8 and this changes
# nothing. Python 3.15 makes UTF-8 the default; the pin is what makes the OLDER interpreters on this
# fleet answer the same way.
hl_python_env() {
  case "${1:-$(uname -s 2>/dev/null)}" in
    MINGW*|MSYS*|CYGWIN*) export PYTHONUTF8=1 ;;
  esac
}
hl_python_env

_hl_python_try() {  # _hl_python_try <candidate-string> <modules…> — rc 0 when it really runs
  local _cand="$1"; shift
  local _imp="import sys"
  local _m
  for _m in "$@"; do _imp="import ${_m}"; done
  # shellcheck disable=SC2086
  $_cand -c "$_imp" >/dev/null 2>&1
}

# hl_python [module …] — fill HL_PYTHON with the argv of a working interpreter. rc 1 = none found.
hl_python() {
  if [ "${_HL_PYTHON_DONE}" = 1 ] && [ "${#HL_PYTHON[@]}" -gt 0 ]; then
    return 0                                 # one probe per process; an exec is what is expensive here
  fi
  local _cand
  if [ -n "${HL_PYTHON_OVERRIDE:-}" ]; then  # an explicit pin is trusted, not probed
    # shellcheck disable=SC2206
    HL_PYTHON=(${HL_PYTHON_OVERRIDE})
    _HL_PYTHON_DONE=1
    return 0
  fi
  local _tried=""
  for _cand in "python3" "py -3" "python"; do
    _tried="${_tried} ${_cand}"
    if _hl_python_try "$_cand" "$@"; then
      # shellcheck disable=SC2206
      HL_PYTHON=(${_cand})                   # TWO words for `py -3`, one for the POSIX names
      _HL_PYTHON_DONE=1
      return 0
    fi
  done
  HL_PYTHON=()
  echo "FATAL: no interpreter on PATH runs ${*:+(needs import $*)}" \
       "— tried:${_tried} . A Microsoft Store alias STUB counts as present and is NOT an interpreter;" \
       "install a real Python or run this where ~/ansible-venv exists (HL_PYTHON_OVERRIDE pins one)." >&2
  return 1
}

if [ "${1:-}" = "--self-test" ]; then
  _st=0
  _tmp="$(mktemp -d "${TMPDIR:-/tmp}/hl-python-st-XXXXXX")"
  trap 'rm -rf "$_tmp"' EXIT

  # A stub-shaped interpreter: it is ON PATH, `command -v` finds it, and it answers 49 without
  # importing anything — the Microsoft Store alias, bred rather than described. An interpreter that
  # answers honestly about one module: the other half of the same probe.
  printf '#!/bin/sh
echo "Python was not found; run without arguments to install from the Microsoft Store."
exit 49
' > "$_tmp/python3"
  printf '#!/bin/sh
case "$*" in *canary_module_9137*) exit 1;; esac
exit 0
' > "$_tmp/honest_python3"
  chmod +x "$_tmp/python3" "$_tmp/honest_python3"

  # Arm 1: a PATH that carries ONLY the stub. A name-based probe reports success here and the first
  # validator dies forty seconds later; this probe must refuse. Without this arm the function could
  # pass by never asking anything but "is it on PATH".
  _HL_PYTHON_DONE=0; HL_PYTHON=(); HL_PYTHON_OVERRIDE=""
  if (PATH="$_tmp"; export PATH; hl_python); then
    printf 'SELFTEST FAIL: the Store-stub candidate was accepted
'; _st=$((_st+1))
  elif [ "${#HL_PYTHON[@]}" -ne 0 ]; then
    printf 'SELFTEST FAIL: a refused probe left an argv behind (%s)
' "${HL_PYTHON[*]}"; _st=$((_st+1))
  else
    printf '  ok: a stub that is on PATH but is not an interpreter is refused
'
  fi

  # Arm 2: a real interpreter that cannot import the module the leg needs. The green-at-launch,
  # traceback-at-step-15 shape the gate's own preflight exists to prevent, bred at the lib level.
  mkdir -p "$_tmp/honest"; cp "$_tmp/honest_python3" "$_tmp/honest/python3" 2>/dev/null || true
  _HL_PYTHON_DONE=0; HL_PYTHON=()
  if (PATH="$_tmp/honest"; export PATH; hl_python canary_module_9137); then
    printf 'SELFTEST FAIL: an interpreter that cannot import the named module was accepted
'; _st=$((_st+1))
  else
    printf '  ok: a candidate that cannot import the named module is refused
'
  fi

  # Arm 3: nothing at all. rc 1 AND an empty argv — a caller that ignores rc must not exec "".
  _HL_PYTHON_DONE=0; HL_PYTHON=()
  if (PATH="/nonexistent-hl-python"; export PATH; hl_python); then
    printf 'SELFTEST FAIL: a host with no interpreter reported success
'; _st=$((_st+1))
  elif [ "${#HL_PYTHON[@]}" -ne 0 ]; then
    printf 'SELFTEST FAIL: rc 1 with a non-empty argv behind it
'; _st=$((_st+1))
  else
    printf '  ok: with no usable interpreter the answer is rc 1 and an empty argv
'
  fi

  # Arm 4: the two-word Windows launcher must arrive as TWO argv entries. Bred with an override that
  # spells it: `py -3` is the candidate the Win11 seat falls back to, and one entry would exec a
  # program literally named "py -3" — rc 127, the failure this lib exists to make impossible.
  _HL_PYTHON_DONE=0; HL_PYTHON=(); HL_PYTHON_OVERRIDE="fake -3"
  hl_python
  if [ "${#HL_PYTHON[@]}" -eq 2 ] && [ "${HL_PYTHON[1]}" = "-3" ]; then
    printf '  ok: a two-word launcher arrives as two argv entries
'
  else
    printf 'SELFTEST FAIL: a two-word launcher collapsed into %d argv entry/entries
' "${#HL_PYTHON[@]}"; _st=$((_st+1))
  fi
  HL_PYTHON_OVERRIDE=""

  # Arm 5: the encoding pin is scoped to the seats that need it, and is proved with a uname STRING
  # rather than the host's, because the rule is about the CLASS. A POSIX seat gains nothing (its
  # interpreter already reads UTF-8); a Windows-shaped seat leaves the pin exported for every child,
  # which is the half of the class a gate's own export could never reach — a leg run straight from a
  # prompt is the one that used to answer a different question than the same leg run by the pool.
  if (unset PYTHONUTF8; hl_python_env Linux; [ -z "${PYTHONUTF8:-}" ]); then
    printf '  ok: a POSIX-shaped seat gains no PYTHONUTF8 pin
'
  else
    printf 'SELFTEST FAIL: hl_python_env pinned a POSIX seat
'; _st=$((_st+1))
  fi
  if (unset PYTHONUTF8; hl_python_env "MINGW64_NT-10.0-26300"; [ "${PYTHONUTF8:-}" = 1 ]); then
    printf '  ok: a Windows-shaped seat exports PYTHONUTF8=1 for every child
'
  else
    printf 'SELFTEST FAIL: hl_python_env did not pin a Windows-shaped seat
'; _st=$((_st+1))
  fi

  # Control: on a normal seat the probe finds the interpreter the gate would have found anyway.
  _HL_PYTHON_DONE=0; HL_PYTHON=()
  if hl_python; then
    printf '  ok: control — the probe finds this host interpreter (%s)
' "${HL_PYTHON[*]}"
  else
    printf 'SELFTEST FAIL: the probe found nothing on a host that has an interpreter
'; _st=$((_st+1))
  fi

  if [ "$_st" -eq 0 ]; then echo "self-test: all arms caught, control clean"; else echo "SELFTEST FAILED: $_st arm(s)"; fi
  exit $((_st ? 1 : 0))
fi
