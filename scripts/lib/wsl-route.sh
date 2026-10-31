#!/usr/bin/env bash
# =====================================================================
# lib/wsl-route.sh — the ONE decision: does this leg run on the Debian engine under WSL?
# ---------------------------------------------------------------------
# WHY: the same gate that finishes in ~8 s on the `wsl` seat takes ~11 min on the win11 seat, and the
# difference is not the work — it is the price of a process. A fork+exec on the Windows seat is 16-44 ms
# quiet and 130-185 ms while a second gate is forking with it, against 0.66 ms on the Debian engine of
# the SAME laptop, so a leg that forks ten thousand times costs minutes here and seconds there. The
# answer that keeps ONE item list is to keep ONE gate and run the slow, seat-independent legs on the
# cheap engine: `wsl.exe -d Debian` over the SAME working tree at `/mnt/<drive>/...`, so the verdict is
# still about THIS checkout, uncommitted edits included. A second `validate-all-win11.sh` was weighed
# and rejected for owning a second item list — this file is that same conclusion from the other side:
# one registry, one routing decision, made in one place.
#
# WHAT IS DECIDED HERE:
#   * the seat. `uname` classifies the shell and `wsl.exe`'s presence is the door — not the OS. Inside
#     WSL this shell IS the engine: nesting it pays the fork twice and reads a second HOME.
#   * the path. The engine must see the tree the gate is grading. A Debian CLONE at ~/source/homelab is
#     the `wsl` seat with its own tree, which is not what a win11-seat verdict may be about.
#   * the launcher, PROBED like every other interpreter in this repo. A Windows python.exe reached
#     through WSL interop prints a Windows sys.executable and decodes the tree with the ANSI codepage,
#     so an interop binary is refused rather than trusted, and git must read the checkout without
#     refusing it — a git that will not open the tree turns twelve legs into twelve green walks over an
#     empty corpus.
#
# WHAT MAY CROSS is declared at the registration site by wrapping the leg in `hl_wsl_route`, and the
# rule is a CONJUNCTION: the leg reads only the tree (or a sandbox it builds itself), opens no
# network/ssh/vault connection, touches no seat-local `$HOME`/registry, needs no tool the Debian engine
# lacks, and does not classify the seat it runs on. A leg that asks those questions answers them for
# the WRONG SEAT and prints a verdict, not an error — the class this repo keeps meeting. Speed alone
# never earns a wrap: one trip across the door costs ~0.3 s.
#
# HOW: `hl_wsl_route <argv…>` runs the argv on the engine when the probe said yes and runs it HERE when
# it said no. It never skips and never forks a second copy: a leg that cannot cross is a leg that runs
# at home, and the launch line says which engine answered.
#
#   bash scripts/validate-all.sh              # auto: wrapped legs cross when this seat has the door
#   HL_WSL=off bash scripts/validate-all.sh   # every leg native — the engine-independent proof
#   HL_WSL=on  bash scripts/validate-all.sh   # stop loudly when the engine is unavailable
#
# THE TRAP THIS FILE EXISTS TO AVOID, measured rather than remembered: git-bash rewrites any argument
# that LOOKS like an absolute POSIX path into a Windows path before handing it to a native program —
# `--cd /mnt/d/x` fails with `Wsl/ERROR_PATH_NOT_FOUND`, and `-- /usr/bin/bash` arrives as Git's own
# bash and runs the harness in the wrong HOME. Every spawn here pins the converter on the command line
# only, never as an export: an export would stop the seat's own legs converting the paths they hand to
# `powershell.exe`. Output comes back as clean UTF-8 (the NUL padding belongs to wsl.exe's own
# messages), and the exit code of the far side is the exit code the caller sees.
#
# SELF-TEST: bash scripts/lib/wsl-route.sh --self-test
#   Arms driven through a stub launcher (`HL_WSL_EXE`) and an injected class, so the PARSER is what
#   each one grades rather than the host: the seat classes separate on behaviour; every Windows
#   spelling of a path arrives as `/mnt/<drive>/…` and an untranslatable one is refused; a distro, tree,
#   interpreter or git that cannot answer switches the route OFF with the engine's own words as the
#   reason; `py -3` collapses to the engine's one interpreter with no `-3` left in the guest argv; the
#   far rc is the caller's rc; a refused route runs the argv HERE (a marker file proves it, because
#   "it ran at home" and "nothing ran" look identical in a log); an argv head with nothing to
#   substitute runs at home even while the route is up; and the tool inventory the probe prints once per
#   run states BOTH halves — what the engine answered with and what it answered NOTHING for.
# =====================================================================

: "${HL_WSL:=auto}"                                       # auto | on | off (off = every leg native)
: "${HL_WSL_DISTRO:=Debian}"                              # the distro the Debian engine runs
: "${HL_WSL_EXE:=wsl.exe}"                                # the door; a fixture injects a stub here
: "${HL_WSL_PYTHONS:=}"          # empty = discover the interpreter INSIDE the engine; a list pins it (fixture/expert)
HL_WSL_ON=0
HL_WSL_GIT=0
HL_WSL_WHY="not probed"
HL_WSL_GIT_WHY=""
HL_WSL_MNT=""
HL_WSL_PY=""
HL_WSL_BASH=""
HL_WSL_GUEST=()                                           # per-leg guest prefix: env PATH=…
HL_WSL_TOOLS=""              # what the engine ANSWERED for, in words — printed once per run by the probe
_HL_WSL_TOOL_NAMES_SHIPPED="rsync rg sqlite3 gawk jq git tmux op script ssh curl sudo ansible-playbook node npm npx pi"
HL_WSL_TOOL_NAMES="${HL_WSL_TOOL_NAMES:-$_HL_WSL_TOOL_NAMES_SHIPPED}"
# The names come from the legs this repo actually wraps and from the tool classes the route's PATH pin
# is known to hide (docs/harness-pi-seats.md §1); the probe asks them because a leg's `CANNOT RUN` is
# only readable against a stated inventory, and asking once per run is what keeps it out of the legs.
# A fixture narrows the list the way `HL_WSL_PYTHONS` narrows the interpreter: planted answers need a
# planted question.
_HL_WSL_PROBED=0

# hl_wsl_class [uname] [launcher] [proc-version] — the seat, classified on BEHAVIOUR. Every argument is
# injectable because the rule is about the CLASS, not about the host that happens to be asking (the
# same reason lib/python.sh takes a uname string rather than reading this one's).
hl_wsl_class() {
  local u="${1:-}" exe="${2-$HL_WSL_EXE}" pv="${3:-}"
  [ -n "$u" ] || u="$(uname -s 2>/dev/null || echo unknown)"
  if [ -z "$pv" ] && [ "$u" = Linux ] && [ -r /proc/version ]; then
    pv="$(tr 'A-Z' 'a-z' < /proc/version 2>/dev/null)"
  fi
  case "$u" in
    MINGW*|MSYS*|CYGWIN*)
      if command -v -- "$exe" >/dev/null 2>&1; then printf 'win11'; else printf 'win11-nodoor'; fi ;;
    Linux) case "$pv" in *microsoft*) printf 'wsl' ;; *) printf 'linux' ;; esac ;;
    *) printf 'other' ;;
  esac
}

# hl_wsl_mntpath <path> — the SAME path as the engine spells it; rc 1 when it has no Debian spelling.
# Refusing beats guessing: the alternative is a leg that runs in a directory it cannot see and reports
# the tree it never read as clean.
hl_wsl_mntpath() {
  local p="${1:-}" d rest
  case "$p" in
    /cygdrive/[A-Za-z]/*)
      d="${p:10:1}"; rest="${p:11}" ;;
    /[A-Za-z]/[!/]*)
      d="${p:1:1}"; rest="${p:2}" ;;
    [A-Za-z]:[\\/]*)
      d="${p:0:1}"; rest="${p:2}"; rest="${rest//\\//}"
      case "$rest" in /*) : ;; *) rest="/$rest" ;; esac ;;
    *) return 1 ;;
  esac
  printf '/mnt/%s%s' "$(printf '%s' "$d" | tr 'A-Z' 'a-z')" "$rest"
}

# hl_wsl_exec <guest argv…> — the only line in the repo that spawns the engine from a Windows shell.
# The converter pin sits on this command only (see the header's trap) and rc comes straight through: a
# red leg across the door must redden the gate exactly as a red leg here does.
hl_wsl_exec() {
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' \
    "$HL_WSL_EXE" -d "$HL_WSL_DISTRO" --cd "$HL_WSL_MNT" -- "$@"
}

# hl_wsl_tools — WHAT THE ENGINE HAS, in words, asked under the SAME PATH the legs are launched with.
# WHY THIS EXISTS: a wrapped leg that shells out to `rsync`/`tmux`/`node` and finds nothing prints a
# SKIP or a CANNOT RUN that reads like the leg's own problem. The engine's inventory is a fact about the
# seat, and asking it once here is what stops every leg rediscovering it — and the one question is asked
# in the probe, never in `hl_wsl_route`, so a run pays one spawn and a leg pays none.
# rc 0 with HL_WSL_TOOLS set; rc 1 when the engine answered nothing, which is said rather than shown as
# an empty inventory (an empty list here would read as "the engine has no tools at all").
hl_wsl_tools() {
  local out="" t p answered="" absent="" found=""
  HL_WSL_TOOLS=""
  # ONE spawn, and `which` rather than a shell loop, for two reasons that were measured here rather
  # than assumed: (a) `wsl.exe -- /bin/sh -c '<script>'` arrives on the far side as a JOINED command
  # line, so a `$var` written in that script is expanded by an outer guest shell before the inner one
  # sees it — `for t in a b; do echo "T=$t"; done` comes back as `T=` twice — and (b) no tool is
  # EXECUTED here, which is what keeps the probe out of the side effects the leg contract refuses (an
  # `op` or `ssh` that reached the network would answer about the wrong seat and cost the wrong
  # account). `which` resolves its arguments against the PATH this spawn carries, which is the SAME
  # pinned PATH the legs are launched with, so the inventory describes the environment a leg sees.
  out="$(hl_wsl_exec "${HL_WSL_GUEST[@]}" /usr/bin/which $HL_WSL_TOOL_NAMES 2>/dev/null)" || true
  while IFS= read -r p; do
    case "$p" in /*) found="$found $p" ;; esac     # `no jq in …` went to stderr; only paths are rows
  done <<EOF
$out
EOF
  [ -n "$found" ] || return 1                      # no row at all = the engine answered NOTHING
  for t in $HL_WSL_TOOL_NAMES; do                  # the asking order, so two runs diff by eye
    for p in $found; do
      [ "${p##*/}" = "$t" ] && { answered="$answered $t=$p"; continue 2; }
    done
    absent="$absent $t"
  done
  HL_WSL_TOOLS="$(printf 'answered —%s' "${answered:- none}")"
  [ -n "$absent" ] && HL_WSL_TOOLS="$HL_WSL_TOOLS$(printf ' · ABSENT —%s' "$absent")"
  return 0
}

# hl_wsl_probe <repo> [class] — ask the engine, ONCE, whether it can grade this tree, and build what
# every leg will launch with. rc 0 with HL_WSL_ON=1 only when every half answered; the reason for a NO
# is the engine's own words, because a route that goes quietly off is how a seat starts reading a
# green it did not earn.
hl_wsl_probe() {
  # <repo> [class] [engine-side path] — the two optional arguments exist for the SELF-TEST: a fixture
  # on a Debian host still has to describe what a Windows seat's checkout looks like to the engine, and
  # the alternative is a self-test that can only pass on the one host it was written for.
  local repo="${1:-$PWD}" cls="${2:-}" eng="${3:-}" out="" py="" tried=""
  [ "$_HL_WSL_PROBED" = 1 ] && return 0
  _HL_WSL_PROBED=1
  case "$HL_WSL" in
    off) HL_WSL_ON=0; HL_WSL_WHY="off (HL_WSL=off) — every leg runs native"; return 0 ;;
    on|auto) : ;;
    *) HL_WSL_ON=0; HL_WSL_WHY="HL_WSL=$HL_WSL is not auto|on|off — running native rather than guessing"; return 0 ;;
  esac
  [ -n "$cls" ] || cls="$(hl_wsl_class)"
  case "$cls" in
    wsl)          HL_WSL_ON=0; HL_WSL_WHY="this shell IS the Debian engine — nesting it pays the fork twice"; return 0 ;;
    linux)        HL_WSL_ON=0; HL_WSL_WHY="a Debian seat runs its legs here"; return 0 ;;
    win11-nodoor) HL_WSL_ON=0; HL_WSL_WHY="no $HL_WSL_EXE door on this Windows seat — nothing to delegate to"; return 0 ;;
    other)        HL_WSL_ON=0; HL_WSL_WHY="not a Windows seat ($cls) — legs run here"; return 0 ;;
    win11)        : ;;
    *)            HL_WSL_ON=0; HL_WSL_WHY="unknown seat class ($cls)"; return 0 ;;
  esac
  if [ ! -d "$repo" ]; then
    HL_WSL_ON=0; HL_WSL_WHY="no tree to hand over: $repo is not a directory"
    return 0
  fi
  if [ -n "$eng" ]; then
    HL_WSL_MNT="$eng"
  elif ! HL_WSL_MNT="$(hl_wsl_mntpath "$repo")"; then
    HL_WSL_ON=0; HL_WSL_WHY="$repo has no Debian-side path — only a drive-mapped checkout can cross"; return 0
  fi

  # (1) door + distro + tree + launcher, asked with the SAME `--cd` the legs will use, so an old
  # launcher without the flag, an uninstalled distro, and an unmounted drive are each answered here
  # instead of twelve times later. The bash and python lookups ride along because they must be resolved
  # by the ENGINE'S OWN `$HOME`: the Windows seat's `$HOME` is `C:\Users\…`, and a candidate list built
  # from it finds nothing in the guest and turns the whole route off with a message about a venv (`$HOME`
  # is the one path that is NOT the same on the two sides of this door). `command -v bash` answers for
  # exactly one operand under dash, which is what is wanted.
  if ! out="$(hl_wsl_exec /bin/sh -c 'pwd; uname -s; command -v bash; if [ -x "$HOME/ansible-venv/bin/python3" ]; then echo "$HOME/ansible-venv/bin/python3"; else command -v python3; fi' 2>&1)"; then
    HL_WSL_ON=0; HL_WSL_WHY="the engine could not enter $HL_WSL_MNT: $(printf '%s' "$out" | tr '\n\r' '  ')"
    return 0
  fi
  local pwd_seen="" uname_seen="" bash_seen="" py_seen=""
  { IFS= read -r pwd_seen; IFS= read -r uname_seen; IFS= read -r bash_seen; IFS= read -r py_seen; } <<EOF
$out
EOF
  if [ "$pwd_seen" != "$HL_WSL_MNT" ]; then
    HL_WSL_ON=0; HL_WSL_WHY="$HL_WSL_MNT answers pwd '$pwd_seen' — the engine is not in this tree"; return 0
  fi
  case "$uname_seen" in
    Linux) : ;;
    *) HL_WSL_ON=0; HL_WSL_WHY="$uname_seen inside $HL_WSL_DISTRO — not the Debian engine"; return 0 ;;
  esac
  case "$bash_seen" in
    "" | /*) : ;;
    *) HL_WSL_ON=0; HL_WSL_WHY="bash resolves to '$bash_seen' inside the guest — a Windows binary over interop"; return 0 ;;
  esac
  case "$bash_seen" in /mnt/*) HL_WSL_ON=0; HL_WSL_WHY="bash resolves to $bash_seen inside the guest — a Windows binary over interop"; return 0 ;; esac
  HL_WSL_BASH="${bash_seen:-/usr/bin/bash}"

  # (2) the interpreter, PROBED not named, exactly as lib/python.sh probes the native ones. The
  # candidates are the engine's own venv python (resolved above, in the engine's HOME) and then the
  # system one; a Windows python.exe answered through interop is refused on its own answer, because it
  # decodes this UTF-8 tree with the ANSI codepage.
  local _cands="$HL_WSL_PYTHONS"
  [ -n "$_cands" ] || _cands="$py_seen /usr/bin/python3"
  for py in $_cands; do
    tried="$tried $py"
    if out="$(hl_wsl_exec "$py" -c "import sys,jinja2,yaml;print(sys.executable)" 2>&1)"; then
      case "$out" in
        /mnt/*) HL_WSL_ON=0; HL_WSL_WHY="$py reports sys.executable $out — an interop path, not the engine's interpreter"; return 0 ;;
        /*)     HL_WSL_PY="$out"; break ;;
        *)      HL_WSL_ON=0; HL_WSL_WHY="$py reports sys.executable $out — a Windows path inside the guest (interop bleed)"; return 0 ;;
      esac
    fi
  done
  if [ -z "$HL_WSL_PY" ]; then
    HL_WSL_ON=0; HL_WSL_WHY="no interpreter inside $HL_WSL_DISTRO imports jinja2 + PyYAML (tried:$tried) — bash scripts/ansible/bootstrap-runner.sh"
    return 0
  fi

  # (3) git — probed and REPORTED, never routed on. No wrapped leg may need the checkout's git (see
  # hl_wsl_route), so this half cannot change a verdict; it exists so a run says out loud when the
  # engine cannot open the checkout it is being asked to grade, which is the Windows-worktree case.
  if out="$(hl_wsl_exec /usr/bin/env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
             git rev-parse --show-toplevel 2>&1)"; then
    HL_WSL_GIT=1
  else
    HL_WSL_GIT=0
    HL_WSL_GIT_WHY="$(printf '%s' "$out" | tr '\n\r' '  ')"
  fi

  # The guest PATH: the chosen interpreter's own directory first (a leg that shells out to
  # `ansible-playbook` or `pi` must find THAT distro's, not the seat's), and no `/mnt/c` entry at all,
  # so a tool the engine lacks is absent loudly instead of answered by a Windows binary.
  HL_WSL_GUEST=(/usr/bin/env "PATH=$(dirname "$HL_WSL_PY"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
  HL_WSL_ON=1
  HL_WSL_WHY="wrapped legs run in $HL_WSL_DISTRO at $HL_WSL_MNT (python3=$HL_WSL_PY bash=$HL_WSL_BASH)"
  [ "$HL_WSL_GIT" = 1 ] || HL_WSL_WHY="$HL_WSL_WHY — git=unavailable: a wrapped leg may not read this checkout through git ($HL_WSL_GIT_WHY)"

  # (4) WHAT THE ENGINE HAS, printed once for the whole run, on stderr beside the route line. A leg's
  # `CANNOT RUN`/`SKIP` naming a missing tool is only evidence when the reader can see the inventory it
  # was missing, and the alternative — every leg discovering it — is the per-leg rediscovery this file
  # exists to stop. Only on the way OUT of a probe that raised the route, so a seat with no route prints
  # no inventory about a seat it never asked.
  if hl_wsl_tools; then
    printf 'engine tools (%s at %s): %s\n' "$HL_WSL_DISTRO" "$HL_WSL_MNT" "$HL_WSL_TOOLS" >&2
  else
    printf 'engine tools (%s at %s): the inventory probe answered NOTHING — treat a wrapped leg that needs a tool as unproven, not as absent\n' "$HL_WSL_DISTRO" "$HL_WSL_MNT" >&2
  fi
  return 0
}

# hl_wsl_route <argv…> — the registration-site wrapper: a leg that asked for the engine gets it while
# the probe holds it up, and anything else runs HERE, unchanged. It never skips and never forks a second
# copy: the safe direction is always "run at home", so an argv head this file cannot name a launcher for
# is declined rather than sent to a guessed path.
#
# WHAT A WRAPPED LEG MAY NOT DO — with the measurement behind each clause, because "it is slow here" is
# not on its own a reason:
#   * read THIS checkout through `git`. Two independent reasons. The 9p tax on a Windows volume exceeds
#     the fork win — measured at one tip: `check_hd_mint_space.py` 118 s across against 72 s native,
#     `check_string_twins.py` 71 s against 56 s, `corpus_diff.py --gate` 40 s against 30 s. AND a
#     Windows WORKTREE defeats a Linux git outright: `git worktree add` on that seat writes the `.git`
#     FILE as `gitdir: D:/source/…/.git/worktrees/<name>`, which a Linux git resolves as a RELATIVE
#     path, so every git command dies `fatal: not a git repository: <cwd>/D:/source/…`. Measured, not
#     theorised: it turned one checker into `CANNOT RUN` (rc 2, honest) and another into a FALSE RED, because
#     a self-test whose positive control replays a real commit range cannot tell a missing repo from a
#     broken invariant. The probe prints `git=unavailable` in the route line when it hits this, and the
#     legs that read the checkout stay native either way. (Injecting GIT_DIR/GIT_WORK_TREE would fix the
#     worktree and poison every leg that builds its own fixture repo — the trap scripts/README.md §Notes
#     names — so the checkout is not worked around, it stays home.)
#   * open a network, ssh, vault or 1Password connection: from the engine the source host, the keys and
#     the Rule 0 stamp belong to the Debian seat, not to this seat.
#   * read seat-local `$HOME`, a registry, or a PATH-resolved tool the engine lacks (`rsync`, tmux,
#     `ansible-playbook`, `op`): the answer would describe the other box.
#   * classify the seat it runs on — a leg that asks "which seat am I" answers for the engine.
hl_wsl_route() {
  if [ "$#" = 0 ]; then
    printf 'FATAL: hl_wsl_route: needs the argv of the leg to route\n' >&2
    return 2
  fi
  if [ "$HL_WSL_ON" != 1 ]; then
    "$@"
    return $?
  fi
  local -a rest=("$@")
  local head="${rest[0]}" base=""
  rest=("${rest[@]:1}")
  base="${head##*/}"; base="${base##*\\}"; base="${base%.exe}"
  case "$base" in
    python|python3)
      printf 'route: this leg ran in %s (%s)\n' "$HL_WSL_DISTRO" "$HL_WSL_MNT"
      hl_wsl_exec "${HL_WSL_GUEST[@]}" "$HL_WSL_PY" "${rest[@]}"
      return $? ;;
    py)
      # `py -3` is the win11 launcher's two-word form (CONVENTIONS §6). The flag belongs to the native
      # interpreter: sent on, it arrives in front of the engine's python as an unknown option.
      [ "${rest[0]:-}" = "-3" ] && rest=("${rest[@]:1}")
      printf 'route: this leg ran in %s (%s)\n' "$HL_WSL_DISTRO" "$HL_WSL_MNT"
      hl_wsl_exec "${HL_WSL_GUEST[@]}" "$HL_WSL_PY" "${rest[@]}"
      return $? ;;
    bash|sh)
      printf 'route: this leg ran in %s (%s)\n' "$HL_WSL_DISTRO" "$HL_WSL_MNT"
      hl_wsl_exec "${HL_WSL_GUEST[@]}" "$HL_WSL_BASH" "${rest[@]}"
      return $? ;;
  esac
  printf 'route: declined for %s — no engine-side launcher known for this argv head, ran native\n' "$head" >&2
  "$@"
}

# --------------------------------------------------------------------------- #
# --------------------------------------------------------------------------- #
# SELF-TEST — stub launcher in, verdicts out. Run: bash scripts/lib/wsl-route.sh --self-test
# Every arm drives the REAL argv shape through a stub that emulates the guest, so what is graded is
# this file's parsing and decisions, not the luck of the host it happens to run on.
# --------------------------------------------------------------------------- #
if [ "${1:-}" = "--self-test" ] && [ -z "${BASH_SOURCE[1]:-}" ]; then
  _st=0
  _tmp="$(mktemp -d "${TMPDIR:-/tmp}/hl-wsl-route-st-XXXXXX")"
  trap 'rm -rf "$_tmp"' EXIT

  cat >"$_tmp/wsl-stub" <<'STUB'
#!/usr/bin/env bash
# A stub wsl.exe: it parses the real argv shape (-d DISTRO --cd PATH -- guest argv…) and answers like
# the guest under the knobs each arm sets. Marking a file, not printing, is how the arms prove WHERE a
# leg ran: "it ran at home" and "nothing ran" are the same line in a log.
printf '%s\n' "$@" >"${HL_STUB_ARGV:-/dev/null}" 2>/dev/null || true
d=""; wd=""; mode="${HL_STUB_MODE:-ok}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    -d) d="$2"; shift 2 ;;
    --cd) wd="$2"; shift 2 ;;
    --) shift; break ;;
    *) shift ;;
  esac
done
[ "$d" = "${HL_STUB_DISTRO:-Debian}" ] || { echo "stub: unknown distro $d" >&2; exit 127; }
if [ "$mode" = pathfail ]; then
  printf 'The system cannot find the path specified.\nError code: Wsl/ERROR_PATH_NOT_FOUND\n' >&2
  exit 127
fi
[ "$mode" = rcfail ] && exit 3
if [ "${1:-}" = env ] || [ "${1:-}" = /usr/bin/env ]; then
  shift
  while [ "$#" -gt 0 ]; do case "$1" in *=*) shift ;; *) break ;; esac; done
fi
mark() { printf '%s\n' "$*" >>"${HL_STUB_MARK:-/dev/null}"; }
case "${1:-}" in
  */sh)
    if [ "${3:-}" = 'pwd; uname -s; command -v bash; if [ -x "$HOME/ansible-venv/bin/python3" ]; then echo "$HOME/ansible-venv/bin/python3"; else command -v python3; fi' ]; then
      printf '%s\n%s\n%s\n%s\n' "$wd" "${HL_STUB_UNAME:-Linux}" "${HL_STUB_BASH:-/usr/bin/bash}" "${HL_STUB_PY:-/home/domen/ansible-venv/bin/python3}"
    else
      mark BASH-RAN "$*"
    fi ;;
  */which)
    # The tool-inventory probe (hl_wsl_tools): `which` asked BY NAME, never a shell loop, because a
    # `$var` inside a `-c` script is expanded by the wrong shell across this door (measured). Like the
    # real binary it prints PATHS for the names it found and NOTHING for the rest, so an arm plants the
    # paths and grades the formatter: an unplanted name must come out ABSENT, a planted one as name=path.
    # `%b` because a planted set arrives as one value with \n between the paths.
    printf '%b\n' "${HL_STUB_TOOLS:-/usr/bin/jq}" ;;
  */bash)
    mark BASH-RAN "$*" ;;
  */git|git)
    printf '%s\n' "${HL_STUB_GIT:-/mnt/tree}"
    case "${HL_STUB_GIT:-/mnt/tree}" in
      /*) : ;;
      *) printf '%s\n' "${HL_STUB_GIT:-}" >&2; exit 128 ;;
    esac ;;
  */python3|*/python)
    # sys.executable of the candidate that was invoked — which is the path the probe ASKED ABOUT, so an
    # arm that pins what the engine resolved can tell a resolved path from one built off this shell's
    # $HOME. rc 0 either way: a Windows python answers happily AND decodes the tree with the ANSI
    # codepage, so the refusal has to come from what it prints, not from whether it ran.
    printf '%s\n' "${HL_STUB_PYEXE:-${HL_STUB_PY:-/home/domen/ansible-venv/bin/python3}}"
    case "${HL_STUB_PYEXE:-${HL_STUB_PY:-/ok/python3}}" in
      /*) mark PY-RAN "$*" ;;
    esac ;;
  *) echo "stub: unexpected guest argv $*" >&2; exit 127 ;;
esac
exit "${HL_STUB_RC:-0}"
STUB
  chmod +x "$_tmp/wsl-stub"

  # A checkout the stub can be told about, and a local script whose ONLY job is to prove it ran here.
  mkdir -p "$_tmp/tree/IaC/ansible" "$_tmp/tree/docs"
  printf '%s\n' '#!/usr/bin/env bash' "touch \"\${HL_LOCAL_MARKER:-$_tmp/local-marker}\"" >"$_tmp/plain.sh"
  chmod +x "$_tmp/plain.sh"

  # Every knob is RESET here, then overridden by `name=value` arguments. An assignment that prefixes a
  # function call survives the call in bash, so a knob left set from the previous arm would decide the
  # next one too — which is how a self-test passes for a reason nobody checked.
  _probe() {
    local _a _cls=win11 _exe="$_tmp/wsl-stub" _mnt=/mnt/M/tree _repo="$_tmp/tree"
    HL_STUB_MODE=ok; HL_STUB_PYEXE=''; HL_STUB_BASH=''; HL_STUB_GIT=''; HL_STUB_RC=0; HL_STUB_UNAME=Linux
    HL_STUB_PY=''; HL_PYTHONS_UNSET=1; HL_STUB_TOOLS=''
    HL_WSL=auto; HL_WSL_PYTHONS=''; HL_WSL_TOOLS=''
    HL_WSL_TOOL_NAMES="$_HL_WSL_TOOL_NAMES_SHIPPED"   # a planted question is one arm's, not the run's
    for _a in "$@"; do
      case "$_a" in
        class=*) _cls="${_a#class=}" ;;
        exe=*)   _exe="${_a#exe=}" ;;
        mnt=*)   _mnt="${_a#mnt=}" ;;
        repo=*)  _repo="${_a#repo=}" ;;
        *=*)     export "${_a%%=*}=${_a#*=}" ;;
      esac
    done
    export HL_STUB_MODE HL_STUB_PYEXE HL_STUB_BASH HL_STUB_GIT HL_STUB_RC HL_STUB_UNAME HL_STUB_PY HL_STUB_TOOLS HL_WSL
    HL_WSL_EXE="$_exe"
    _HL_WSL_PROBED=0
    HL_WSL_ON=0; HL_WSL_GIT=0; HL_WSL_WHY=""; HL_WSL_GIT_WHY=""; HL_WSL_PY=""; HL_WSL_BASH=""
    HL_WSL_MNT=""; HL_WSL_GUEST=()
    if [ "$_exe" = "$_tmp/wsl-stub" ]; then
      hl_wsl_probe "$_repo" "$_cls" "$_mnt" >/dev/null 2>&1
    else
      hl_wsl_probe "$_repo" "$_cls" >/dev/null 2>&1
    fi
  }
  # WHERE did it run: cross = the stub marked it and nothing ran here; home = the marker exists.
  _ran=()
  _where() {  # _where <route-fn> <argv…> → cross | home | nowhere
    : >"$_tmp/mark"; rm -f "$_tmp/local-marker"
    HL_STUB_MARK="$_tmp/mark" HL_LOCAL_MARKER="$_tmp/local-marker" "$@" >/dev/null 2>&1
    if [ -s "$_tmp/mark" ] && [ ! -e "$_tmp/local-marker" ]; then printf 'cross'
    elif [ -e "$_tmp/local-marker" ]; then printf 'home'
    else printf 'nowhere'; fi
  }
  local _inv_print="" _inv_off=""
  _ok() { printf '  ok: %s\n' "$1"; }
  _no() { printf 'SELFTEST FAIL: %s\n' "$1"; _st=$((_st + 1)); }

  # Arm 1 — the seat classes separate on BEHAVIOUR. A Windows shell without the door is not a routable
  # seat, and a real Debian box is not "a Windows seat whose door is missing".
  [ "$(hl_wsl_class MINGW64_NT-10.0-26300 "$_tmp/wsl-stub")" = win11 ] \
    && _ok "a Windows shell with the door is the win11 seat" \
    || _no "a Windows seat with wsl.exe was not classed win11"
  [ "$(hl_wsl_class MINGW64_NT-10.0-26300 "$_tmp/no-such-exe")" = win11-nodoor ] \
    && _ok "a Windows shell with no door says so instead of promising a route" \
    || _no "a missing launcher still classed as routable"
  [ "$(hl_wsl_class Linux "$_tmp/wsl-stub" 'linux version 6.6-microsoft-standard')" = wsl ] \
    && _ok "inside WSL the class is the wsl seat — the engine is never nested" \
    || _no "the wsl seat would have nested a second engine"
  [ "$(hl_wsl_class Linux "$_tmp/wsl-stub" 'linux version 6.6.0')" = linux ] \
    && _ok "a real Debian host is a Debian seat, not a Windows seat with a missing door" \
    || _no "a Debian host classed as routable"

  # Arm 2 — the translator. Split on a SPACE, never on `:`: a drive path CONTAINS a colon, and a `%%:*`
  # field split cuts `D:\source\x` in half and then blames the translator for refusing it.
  while IFS=' ' read -r _in _want; do
    [ -n "$_in" ] || continue
    _got="$(hl_wsl_mntpath "$_in" || true)"
    [ "$_got" = "$_want" ] || _no "hl_wsl_mntpath $_in = ${_got:-<refused>} (want $_want)"
  done <<'PAIRS'
/d/source/x /mnt/d/source/x
D:/source/x /mnt/d/source/x
D:\source\x /mnt/d/source/x
C:/Users/x /mnt/c/Users/x
/c/Users/x /mnt/c/Users/x
/cygdrive/d/source/x /mnt/d/source/x
PAIRS
  [ "$_st" = 0 ] && _ok "every Windows spelling of a drive path arrives as /mnt/<drive>/…"
  _ref=0
  hl_wsl_mntpath "/home/domen/source/homelab" >/dev/null || _ref=$((_ref + 1))
  hl_wsl_mntpath "//ts/share/x" >/dev/null || _ref=$((_ref + 1))
  [ "$_ref" -ge 2 ] && _ok "a path with no Debian spelling is refused, never guessed" \
                     || _no "an untranslatable path was translated anyway"

  # Arms 3+ — every refusal, one engine answer each. Each is one silent step away from a green run over
  # a tree the engine never read.
  _probe HL_WSL=off
  { [ "$HL_WSL_ON" = 0 ] && printf '%s' "$HL_WSL_WHY" | grep -qi 'off'; } \
    && _ok "HL_WSL=off keeps every leg native and prints why" \
    || _no "HL_WSL=off did not keep the legs native ($HL_WSL_WHY)"
  _probe class=wsl
  { [ "$HL_WSL_ON" = 0 ] && printf '%s' "$HL_WSL_WHY" | grep -qi 'this shell IS'; } \
    && _ok "the wsl seat runs its own legs (no nested engine, no second HOME)" \
    || _no "the wsl seat would have nested the engine ($HL_WSL_WHY)"
  _probe class=linux
  [ "$HL_WSL_ON" = 0 ] && _ok "a Debian seat runs its own legs" || _no "a Debian seat raised the route"
  _probe class=other
  [ "$HL_WSL_ON" = 0 ] && _ok "any other host runs its legs at home" || _no "an unknown seat offloaded"
  # The engine's `$HOME` is not this shell's. Rebuilding the candidate list from a Windows `$HOME` is
  # the regression this arm exists for: it would find nothing in the guest and switch the whole route
  # off, blaming a missing venv for a path that was never the engine's to begin with.
  HOME='C:\Users\domen' _probe HL_STUB_PY=/opt/venv/bin/python3
  { [ "$HL_WSL_ON" = 1 ] && [ "$HL_WSL_PY" = /opt/venv/bin/python3 ]; } \
    && _ok "the interpreter is resolved by the engine's HOME, not by this shell's" \
    || _no "a Windows \$HOME vetoed the route (py=$HL_WSL_PY on=$HL_WSL_ON: $HL_WSL_WHY)"
  _probe repo=/hl-wsl-route-no-such-tree
  { [ "$HL_WSL_ON" = 0 ] && printf '%s' "$HL_WSL_WHY" | grep -qi 'is not a directory'; } \
    && _ok "a tree that is not there is refused before anything is asked of the engine" \
    || _no "a missing tree raised the route ($HL_WSL_WHY)"
  _probe HL_STUB_MODE=pathfail
  { [ "$HL_WSL_ON" = 0 ] && printf '%s' "$HL_WSL_WHY" | grep -qi 'PATH_NOT_FOUND\|could not enter'; } \
    && _ok "a distro or tree the engine cannot enter switches the route off with its own words" \
    || _no "an unenterable tree still routed ($HL_WSL_WHY)"
  _probe HL_STUB_UNAME=Darwin
  { [ "$HL_WSL_ON" = 0 ] && printf '%s' "$HL_WSL_WHY" | grep -qi 'not the Debian engine'; } \
    && _ok "an engine that answers Darwin is refused — a green from the wrong kernel is no green" \
    || _no "a non-Linux engine raised the route ($HL_WSL_WHY)"
  _probe HL_STUB_PYEXE='C:\Python313\python.exe'
  { [ "$HL_WSL_ON" = 0 ] && printf '%s' "$HL_WSL_WHY" | grep -qi 'interop'; } \
    && _ok "an interop python.exe is refused, not trusted to decode a UTF-8 tree" \
    || _no "an interop interpreter was accepted as the launcher ($HL_WSL_WHY)"
  _probe HL_STUB_BASH='/mnt/c/Program Files/Git/usr/bin/bash'
  { [ "$HL_WSL_ON" = 0 ] && printf '%s' "$HL_WSL_WHY" | grep -qi 'interop'; } \
    && _ok "a bash that resolves under /mnt/c is refused inside the guest" \
    || _no "an interop bash was accepted ($HL_WSL_WHY)"

  # The git split: an unreadable checkout costs the git-reading legs their route and NOTHING else.
  # This is the Windows-worktree case — `.git` names `D:/…`, a Linux git resolves it relatively.
  _probe HL_STUB_GIT='fatal: not a git repository: /mnt/d/x/D:/source/x/.git/worktrees/x'
  { [ "$HL_WSL_ON" = 1 ] && [ "$HL_WSL_GIT" = 0 ]; } \
    && _ok "an unreadable checkout (the Windows-worktree case) is named in the route line" \
    || _no "an unreadable checkout set ON=$HL_WSL_ON GIT=$HL_WSL_GIT ($HL_WSL_GIT_WHY)"
  printf '%s' "$HL_WSL_WHY" | grep -qi 'may not read this checkout through git' \
    && _ok "and the same line says what a wrapped leg may not do" \
    || _no "the git half was probed but never told to the reader"
  [ "$(_where hl_wsl_route bash "$_tmp/plain.sh")" = cross ] \
    && _ok "a leg that needs no git still crosses when the engine cannot open the checkout" \
    || _no "the git refusal took the tree-only legs down with it"

  # Control, then the argv that arrives.
  _probe
  [ "$HL_WSL_ON" = 1 ] && _ok "control — with every half answering, the route is up ($HL_WSL_PY)" \
                       || _no "the healthy stub did not raise the route ($HL_WSL_WHY)"

  # THE TOOL INVENTORY the probe prints once per run, so a wrapped leg's CANNOT RUN names a stated
  # absence instead of a surprise. Graded on planted rows: the ABSENT half and the answered half must
  # both reach the line, and a seat with no route must print nothing at all about an engine it never
  # asked. The question is asked in the PROBE, never in hl_wsl_route, which is what keeps the cost one
  # spawn per run rather than one per leg. `_probe` swallows the probe's own output, so the two arms
  # that read a printed line re-run the probe directly — the memo cleared first, because "it printed
  # nothing" and "it was never asked" are otherwise the same observation.
  _probe HL_WSL_TOOL_NAMES='jq tmux rsync node' HL_STUB_TOOLS='/usr/bin/jq\n/usr/bin/tmux'
  printf '%s' "$HL_WSL_TOOLS" | grep -q 'ABSENT — rsync node' \
    && printf '%s' "$HL_WSL_TOOLS" | grep -q 'answered — jq=/usr/bin/jq tmux=/usr/bin/tmux' \
    && _ok "the inventory states both halves in words: answered jq=/usr/bin/jq tmux=/usr/bin/tmux · ABSENT rsync node" \
    || _no "the inventory line came out as '${HL_WSL_TOOLS:-<empty>}'"
  _HL_WSL_PROBED=0
  _probe HL_WSL_TOOL_NAMES='jq rsync' HL_STUB_TOOLS='/usr/bin/jq'
  _HL_WSL_PROBED=0
  _inv_print="$( { hl_wsl_probe "$_tmp/tree" win11 /mnt/M/tree; } 2>&1 >/dev/null )"
  printf '%s' "$_inv_print" | grep -q '^engine tools' \
    && _ok "and the probe PRINTS it (once, on stderr, beside the route line a run already reads)" \
    || _no "the probe raised the route but printed no engine-tools line: ${_inv_print:-<none>}"
  _probe class=wsl
  _HL_WSL_PROBED=0
  _inv_off="$( { hl_wsl_probe "$_tmp/tree" wsl /mnt/M/tree; } 2>&1 >/dev/null )"
  printf '%s' "$_inv_off" | grep -q '^engine tools' \
    && _no "a seat with no route printed an engine inventory it never asked for: $_inv_off" \
    || _ok "a seat with no route prints no inventory — no question asked, no answer claimed"
  _probe

  : >"$_tmp/mark"
  HL_STUB_MARK="$_tmp/mark" hl_wsl_route py -3 scripts/gate/check_doc_size.py --self-test >/dev/null 2>&1
  if grep -q 'PY-RAN' "$_tmp/mark" && ! grep -q -- ' -3 ' "$_tmp/mark"; then
    _ok "py -3 collapses to the engine interpreter; the native flag never crosses"
  else
    _no "the python leg arrived as: $(tr '\n' '|' <"$_tmp/mark")"
  fi
  _probe
  HL_STUB_MODE=rcfail hl_wsl_route bash scripts/gate/guard-session.sh --self-test >/dev/null 2>&1
  _rc=$?
  [ "$_rc" = 3 ] && _ok "the far exit code is the exit code the caller sees" \
                 || _no "a red leg across the door lost its rc (came back $_rc)"

  # WHERE the argv runs, three ways: route off → home; route up + unknown head → home; route up +
  # a head this file knows → across.
  _probe HL_WSL=off
  [ "$(_where hl_wsl_route bash "$_tmp/plain.sh")" = home ] \
    && _ok "with the route off the argv runs here, unchanged" \
    || _no "a refused route skipped the leg instead of running it"
  _probe
  [ "$(_where hl_wsl_route "$_tmp/plain.sh")" = home ] \
    && _ok "an unknown argv head runs at home even while the route is up" \
    || _no "an unknown head was sent to a guessed engine launcher"
  [ "$(_where hl_wsl_route bash "$_tmp/plain.sh")" = cross ] \
    && _ok "a bash leg crosses to the engine and not to this shell" \
    || _no "a bash leg did not cross as declared"

  # Control on THIS host, with the REAL launcher: the win11 seat must actually reach the engine and
  # every other seat must actually not. Skippable where no distro is installed, and then it says SKIP.
  if [ -n "${HL_WSL_SKIP_LIVE:-}" ]; then
    printf '  SKIP: live probe skipped (HL_WSL_SKIP_LIVE) — the stub arms still ran\n'
  else
    _ctl="$PWD"; [ -d "$_ctl/IaC/ansible" ] || _ctl="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    _HLW="$(hl_wsl_class)"
    # EVERY piece of probe state, cleared with STATEMENTS, and the stub launcher dropped: a prefix list
    # on a function call is the wrong tool here, because a variable this file forgets to name in the
    # list keeps whatever the last stubbed arm left — and an arm that grades a leftover verdict is
    # worse than no arm: on the win11 seat the leftover `HL_WSL_ON=1` is exactly what the control
    # expects, so it passes without asking the door anything, while the SAME arm on the wsl seat fails.
    # That asymmetry is how this defect was found — it went red only on the seat that expected 0.
    HL_WSL=auto; _HL_WSL_PROBED=0; HL_WSL_ON=0; HL_WSL_WHY=""; HL_WSL_EXE=wsl.exe
    HL_WSL_MNT=""; HL_WSL_PY=""; HL_WSL_BASH=""; HL_WSL_GIT=0; HL_WSL_PYTHONS=""; HL_WSL_GUEST=()
    hl_wsl_probe "$_ctl" >/dev/null 2>&1
    case "$_HLW" in
      win11)   [ "$HL_WSL_ON" = 1 ] && _ok "control — this win11 seat reaches the engine ($HL_WSL_PY)" \
                                      || _no "this win11 seat cannot reach the engine — $HL_WSL_WHY" ;;
      wsl)     [ "$HL_WSL_ON" = 0 ] && _ok "control — this seat IS the engine ($HL_WSL_WHY)" \
                                      || _no "the wsl seat turned the route on" ;;
      *)       [ "$HL_WSL_ON" = 0 ] && _ok "control — this seat runs every leg natively ($HL_WSL_WHY)" \
                                      || _no "a non-win11 seat turned the route on" ;;
    esac
  fi

  if [ "$_st" = 0 ]; then printf 'self-test: all arms caught, control clean\n'
  else printf 'SELFTEST FAILED: %s arm(s)\n' "$_st"; fi
  exit $((_st ? 1 : 0))
fi
