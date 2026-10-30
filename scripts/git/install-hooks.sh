#!/usr/bin/env bash
# =====================================================================
# install-hooks.sh — install, and PROVE, the clone's own pre-push leak gate (HD-1202, HD-1219)
# ---------------------------------------------------------------------
# WHY A HOOK, AND WHY A HOOK ALONE WAS NEVER GOING TO BE ENOUGH
# ------------------------------------------------------------
# Every push leg in this repo runs through a human decision. The leak eye is wired into
# `validate-all.sh`, so a session that runs the gate is covered — and a session that pushes
# without running it is not, which is exactly how HD-1170 happened: a bearer was published in
# a tracked capture of a PUBLIC repo and sat there for 13 days while the gate that would have
# named it existed and was green on every run that mattered. A hook stands between the commit
# and the remote, so a leaked secret stops AT the push rather than in the next review, and —
# the property no other convergence point in this fleet has — it travels with the CHECKOUT. A
# worktree created after this ran, a clone made on a new machine, a seat that runs no converge:
# all of them carry the gate, because the gate lives inside `.git/`.
#
# WHAT THE HOOK ACTUALLY RUNS, AND WHY IT IS NOT THE FULL EYE
# -----------------------------------------------------------
# `check_secret_leak.py --tree-only --no-history`: the repo-tree-current leg only. The other two
# are not cheap — the history leg sends vault values to `git log -S` across the whole blob
# history, and the run-capture leg walks hundreds of transcript files — and a hook that takes
# minutes on every push gets bypassed within a week, which is a worse outcome than no hook at
# all. So the hook buys the leg it can afford and SAYS what it did not look at: the checker
# prints `NOT SCANNED git-history` and `NOT SCANNED run-capture`, and its clean verdict is
# `PARTIAL`, not `OK`. ⛔ A push is NOT a gate, and the sentence is in the hook's own output
# because the next reader must not conclude from a green push that the fleet is clean — the
# ledgered debt stays outstanding and only rotation closes it.
#
# THE BUG THIS SCRIPT EXISTS TO NOT HAVE: `$(dirname "$(git rev-parse --git-dir)")/hooks`
# ---------------------------------------------------------------------------------------
# Every existing consumer of that idiom in this repo wants the CHECKOUT root, and gets it. In a
# LINKED WORKTREE `--git-dir` answers `.git/worktrees/<name>` — whose parent is not the root, and
# whose `hooks/` subdirectory does not exist — and the script that builds a path from it installs
# its hook into a directory git never reads. The install then REPORTS SUCCESS, `--check` compares
# the file it wrote against itself and reports SAME, and the gate is absent from every push on
# that seat forever. Git reads hooks from the COMMON dir, resolved: `git rev-parse
# --git-path hooks` (equivalently `--git-common-dir`/hooks), which is why the hook installed by
# this script covers every worktree of the clone with ONE install, and why `--self-test` builds a
# real linked worktree and asserts the hook is where THAT worktree looks.
#
# MODES — the same contract as every other seat-plane owner
#   --check (default)   SAME / DRIFTED / MISSING against what this script would write. Report
#                       only; exits 0. MISSING means this clone has no gate, which is a finding
#                       for the driver, not for a human terminal run.
#   --check --strict    exit 1 on MISSING or DRIFTED — the form `pi-seat-sync.sh` fans out and the
#                       form that makes "the seat has no hook" a reported state instead of an
#                       assumption.
#   --push              write the hook. A pre-push hook this script cannot claim (no
#                       `managed-by:` marker) is a REFUSAL, never an overwrite: a seat with its
#                       own hook is a seat with a reason, and the merge is a human's call.
#   --self-test         sandboxed arms in a temp dir: a canary in the tree must BLOCK a real push,
#                       a clean tree must allow one, a seat with no reachable vault must SKIP with
#                       a printed reason rather than pass silently, and the hook must be found by
#                       a SECOND worktree of the same clone — the arm the naive path fails.
#
# Exit codes follow the checker's own vocabulary: 0 ok/SAME, 1 MISSING or DRIFTED under --strict,
# 2 a boundary (not a git repo, no python) — a SKIP that is printed, never counted as a pass.
#
# Env: REPO (self-derived, an inherited value wins) and HL_LEAK_PY (the interpreter the INSTALLED
# hook will use; default `python3`) — the override exists for the self-test, which is the only
# reason any of these scripts have env knobs at all.
#
# Owning rule: docs/deployment-secrets.md §Output hygiene · docs/1password.md §Output hygiene ·
# CONVENTIONS §6 (a check that cannot fail is not evidence).
# =====================================================================
set -uo pipefail

_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"

MARKER="managed-by: scripts/git/install-hooks.sh"
HOOK_NAME="pre-push"
MODE="check"
STRICT=0
FORCE=0

say() { printf 'install-hooks: %s\n' "$*"; }
note() { printf '  %s\n' "$*"; }

usage() {
  cat <<'EOF'
usage: install-hooks.sh [--check [--strict]] | --push [--force] | --self-test

  --check          (default) SAME / DRIFTED / MISSING for the clone's pre-push hook
  --check --strict  exit 1 on MISSING or DRIFTED (the seat-plane form)
  --push           write the hook into the COMMON hooks dir (one install, every worktree);
                   a foreign pre-push hook is refused unless --force
  --self-test      canary / clean / no-vault / second-worktree arms in a temp dir
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)     MODE="check" ;;
    --strict)    STRICT=1 ;;
    --push)      MODE="push" ;;
    --force)     FORCE=1 ;;
    --self-test) MODE="selftest" ;;
    --help|-h)   usage; exit 0 ;;
    *) say "unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

# --- the hook body, in ONE place: what --check compares against is what --push writes ----------
# Quoted heredoc on purpose: every `$` in here must survive into the installed file, where it is
# the pushing shell's variable, not this installer's.
hook_body() {
  cat <<'HOOK'
#!/usr/bin/env bash
# pre-push — the leak eye's affordable leg, run between this commit and the remote.
# Do not edit in place: edit scripts/git/install-hooks.sh and re-run it with --push.
# managed-by: scripts/git/install-hooks.sh (HD-1219)
#
# Tree-only by design; it prints what it did NOT scan. A green here is not a clean fleet.
set -uo pipefail
root="$(git rev-parse --show-toplevel 2>/dev/null)" || root="$(pwd)"
cd "$root" || { echo "pre-push: cannot reach the worktree root — push NOT judged"; exit 2; }
[ -f "scripts/gate/check_secret_leak.py" ] || {
  echo "pre-push: scripts/gate/check_secret_leak.py is not in this checkout — push NOT judged"; exit 2; }

PY="${HL_LEAK_PY:-python3}"
# stdout is captured, not streamed, because the verdict must be READ before the push is decided: the
# checker's rc 1 means "finding" ONLY when it printed the finding line. rc 1 with no finding line is a
# crash (a missing lib, a bad interpreter, a half-checked-out tool), and refusing a push for a crash
# accuses the tree of a leak the tool never actually looked for — the accusation would be wrong, and
# a wrongly-red hook is a hook that gets `--no-verify`'d into decoration.
# shellcheck disable=SC2086
out="$("$PY" scripts/gate/check_secret_leak.py --tree-only --no-history 2>&1)"; rc=$?
printf '%s\n' "$out"
if [ "$rc" = 1 ] && ! printf '%s' "$out" | grep -q '^FAIL: '; then
  echo "pre-push: NOT JUDGED — the leak eye exited $rc without producing a verdict, so this push was"
  echo "          not checked by anything. The output above is the reason. Fix the tool, then push;"
  echo "          a crash is not a leak and must not be reported as one."
  exit 0
fi
case "$rc" in
  0)
    echo "pre-push: repo tree carries no current vault value OUTSIDE the ledger — the two legs this"
    echo "          hook never ran (git-history, run-capture) are named above, and a ledgered debt is"
    echo "          still open until the VALUE rotates. Pushing."
    exit 0 ;;
  2)
    echo "pre-push: SKIP — the vault or \`op\` is not reachable from this seat, so the tree was NOT"
    echo "          judged. The push proceeds because a hook that blocks every push on a seat with no"
    echo "          token is a hook that gets removed; run \`bash scripts/validate-all.sh --only secret\`"
    echo "          where a vault IS reachable. A SKIP is not a pass."
    exit 0 ;;
  1)
    echo "pre-push: REFUSED — a value that is LIVE in the vault right now is present in this tree."
    echo "          Find it:  python3 scripts/gate/check_secret_leak.py --strict"
    echo "          The close is a ROTATION, never a scrub of the commit or an edit to this hook"
    echo "          (docs/1password.md §Output hygiene). \`git push --no-verify\` is how you skip it;"
    echo "          it is also how HD-1170 happened."
    exit 1 ;;
  *) echo "pre-push: NOT JUDGED — the leak eye exited $rc, which is not a verdict it defines"; exit 0 ;;
esac
HOOK
}

# --- paths: the COMMON dir, never `dirname --git-dir` -------------------------------------------
hooks_dir() {  # echo the dir git actually reads hooks from, absolute; rc 1 outside a repo
  # `--git-path hooks`, not `dirname --git-dir`: git-path resolves the COMMON dir for a linked
  # worktree AND honours `core.hooksPath`, and the answer is therefore the directory git will
  # actually read. --path-format is newer than every git on this fleet, so the absolute-ness is
  # checked rather than assumed: a relative answer is relative to the -C directory.
  local d
  d="$(git -C "$REPO" rev-parse --git-path hooks 2>/dev/null)" || return 1
  [ -n "$d" ] || return 1
  case "$d" in /*) ;; *) d="$REPO/$d" ;; esac
  printf '%s' "${d%/}"
}

want() {  # the file content --push would write
  hook_body
}

case "$MODE" in
  check|push)
    HD="$(hooks_dir)" || { say "boundary: $REPO is not a git repository — nothing to check or install"; exit 2; }
    TARGET="$HD/$HOOK_NAME"

    tmp="$(mktemp)"
    want >"$tmp"
    if [ ! -e "$TARGET" ]; then
      state="MISSING"
    elif cmp -s "$tmp" "$TARGET"; then
      state="SAME"
    elif grep -qF "$MARKER" "$TARGET" 2>/dev/null; then
      state="DRIFTED"
    else
      state="FOREIGN"
    fi

    if [ "$MODE" = push ]; then
      if [ "$state" = FOREIGN ] && [ "$FORCE" != 1 ]; then
        say "REFUSED: $TARGET is a pre-push hook this script did not write (no managed-by marker)."
        say "         A seat with its own hook has a reason; merge it by hand, or --force to replace."
        rm -f "$tmp"; exit 1
      fi
      mkdir -p "$HD"
      if [ -f "$TARGET" ] && [ "$state" != SAME ]; then
        cp -p "$TARGET" "$TARGET.bak-$(date -u +%Y%m%dT%H%M%SZ)"
        note "backed up the previous hook beside it (.bak-<utc>)"
      fi
      want >"$TARGET".new && chmod 0755 "$TARGET".new && mv -f "$TARGET".new "$TARGET"
      say "installed $TARGET ($state) — one install, every worktree of this clone"
      say "hooks dir: $HD (common dir: $(git -C "$REPO" rev-parse --git-common-dir 2>/dev/null))"
      rm -f "$tmp"; exit 0
    fi

    note "$TARGET: $state"
    rm -f "$tmp"
    case "$state" in
      SAME) exit 0 ;;
      MISSING)
        say "this clone has NO pre-push leak gate — a push from it is unchecked by this route"
        [ "$STRICT" = 1 ] && exit 1
        exit 0 ;;
      *)
        say "$state — the hook here is not the hook the repo would write"
        [ "$STRICT" = 1 ] && exit 1
        exit 0 ;;
    esac
    ;;
esac

# --------------------------------------------------------------------------- self-test
fails=0
check() {  # check <name> <cond-rc> [detail]
  local name="$1" ok="$2" detail="${3:-}"
  if [ "$ok" = 0 ]; then printf '  ok   %s\n' "$name"
  else printf '  FAIL %s%s\n' "$name" "${detail:+ — $detail}"; fails=$((fails + 1)); fi
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
command -v git >/dev/null 2>&1 || { say "self-test: no git on this seat — cannot run any arm"; exit 2; }
PYC="${HL_LEAK_PY:-python3}"
"$PYC" -c 'import sys' >/dev/null 2>&1 || { say "self-test: no python ('$PYC') — arms would be vacuous"; exit 2; }

T="$(mktemp -d)"
# shellcheck disable=SC2064
trap 'rm -rf "$T"' EXIT

# A self-test that installs hooks must prove it installed them ONLY in its fixtures. This exact bug
# happened: one fixture invocation left $REPO inherited, the fixture's checker resolved the REAL
# checkout, and the run installed a live hook into the merge station. So the checkout's own hook is
# hashed before and after, and any change is a finding.
_home_hook="$(git -C "$REPO" rev-parse --git-path hooks 2>/dev/null)/pre-push"
case "$_home_hook" in /*) ;; *) _home_hook="$REPO/$_home_hook" ;; esac
before_hook="$([ -f "$_home_hook" ] && cksum <"$_home_hook" || echo ABSENT)"

# A fixture repo whose ONLY content is a real checkout of the tooling the hook calls, so the hook
# runs the REAL checker against a minted vault fixture — never a live vault, never a real value.
mk_repo() {  # mk_repo <dir> — a git repo with scripts/gate + scripts/lib from THIS repo
  local d="$1"
  mkdir -p "$d/scripts/gate" "$d/scripts/lib" "$d/scripts/git" "$d/IaC/ansible" "$d/docs"
  : >"$d/docs/index.md"
  git init -q "$d"
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  # The SAME tree shape, or the fixture proves nothing: the checker imports `repo_root`,
  # `vault_env` and `vault_read` off `scripts/lib/`, and a fixture that omits them dies with
  # ModuleNotFoundError — which is rc 1, which a naiver hook than this one would have reported as a
  # leak. That exact accident is why the rc-1-without-a-verdict arm below exists.
  cp "$REPO/scripts/gate/check_secret_leak.py" "$d/scripts/gate/"
  cp "$REPO"/scripts/lib/*.py "$_hl_d"/lib/*.sh "$d/scripts/lib/"
  cp "$SELF" "$d/scripts/git/"
  # the ledger: empty, so ANY current value found in the tree is a finding, not carried debt
  : >"$d/empty-ledger.txt"
  printf 'a\n' >"$d/README.md"
  git -C "$d" add -A >/dev/null && git -C "$d" commit -qm init >/dev/null
}

VAULT="$T/vault.json"
CANARY="canary-$(head -c 24 /dev/urandom | base64 | tr -d '\n/+=')"
SHORTV="short-$(head -c 6 /dev/urandom | base64 | tr -d '\n/+=')"
cat >"$VAULT" <<JSON
{"items": {"aaaaaaaaaaaaaaaaaaaaaaaaaa": {"title": "item_secret", "version": 3, "fields": [
  {"id": "password", "label": "password", "value": "$CANARY", "type": "Concealed", "section": ""}]},
 "bbbbbbbbbbbbbbbbbbbbbbbbbb": {"title": "item_short", "version": 3, "fields": [
  {"id": "credential", "label": "credential", "value": "$SHORTV", "type": "Concealed", "section": ""}]}}}
JSON
export HL_VAULT_READ_FIXTURE="$VAULT" HL_LEAK_LEDGER="$T/ledger.txt" HL_LEAK_HISTORY_CACHE="$T/hist"
: >"$T/ledger.txt"

REMOTE="$T/remote.git"; git init -q --bare "$REMOTE"

# (1) install, then a REAL push of a tree carrying a live value must be BLOCKED
mk_repo "$T/leaky"; git -C "$T/leaky" remote add origin "$REMOTE"
( cd "$T/leaky" && REPO="$PWD" bash scripts/git/install-hooks.sh --push >/dev/null ) || true
printf 'token = "%s"\n' "$CANARY" >"$T/leaky/config.yml"
git -C "$T/leaky" add -A >/dev/null && git -C "$T/leaky" commit -qm "adds a live value" >/dev/null
out="$( cd "$T/leaky" && REPO="$PWD" git push origin HEAD:refs/heads/leaky 2>&1 )"; rc=$?
check "a canary value in the tree BLOCKS a real push" \
      "$([ "$rc" != 0 ] && printf '%s' "$out" | grep -q REFUSED && printf 0 || printf 1)" \
      "rc=$rc out=$(printf '%s' "$out" | tr '\n' '|' | tail -c 200)"
check "the refusal names the close that works: a rotation, not a scrub" \
      "$(printf '%s' "$out" | grep -qi 'ROTATION' && printf 0 || printf 1)"
check "the blocked push reached no remote (the canary never left the machine)" \
      "$(git -C "$REMOTE" rev-list --all --count 2>/dev/null | grep -q '^0$' && printf 0 || printf 1)"

# (2) a clean tree: the push must PASS, and still say what it did NOT look at
mk_repo "$T/clean"; git -C "$T/clean" remote add origin "$REMOTE"
( cd "$T/clean" && REPO="$PWD" bash scripts/git/install-hooks.sh --push >/dev/null )
out="$( cd "$T/clean" && REPO="$PWD" git push origin HEAD:refs/heads/clean 2>&1 )"; rc=$?
check "a clean tree allows the push" "$([ "$rc" = 0 ] && printf 0 || printf 1)" \
      "rc=$rc $(printf '%s' "$out" | tr '\n' '|' | tail -c 200)"
check "the clean push still prints the two legs it did NOT scan" \
      "$(printf '%s' "$out" | grep -q 'NOT SCANNED git-history' && printf '%s' "$out" | grep -q 'NOT SCANNED run-capture' && printf 0 || printf 1)" \
      "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-200)"
check "and calls its own verdict PARTIAL, never a clean fleet" \
      "$(printf '%s' "$out" | grep -q 'PARTIAL' && printf 0 || printf 1)"

# (3) no reachable vault: SKIP with a printed reason, and the push still goes (rc 0)
# The same both-ways-to-be-unreachable env the checker's own arm (6) builds: no `op` on PATH, no
# seat file (HOME), no door (HL_WSL), no token. The hook's contract is the MAPPING: rc 2 → allow +
# print, because a hook that blocks every push on a tokenless seat is a hook that gets deleted.
mk_repo "$T/novault"; git -C "$T/novault" remote add origin "$REMOTE"
( cd "$T/novault" && REPO="$PWD" bash scripts/git/install-hooks.sh --push >/dev/null )
mkdir -p "$T/noop-bin" "$T/noop-home"
for _b in git bash grep cmp sed uname mv chmod date; do ln -sf "$(command -v "$_b")" "$T/noop-bin/$_b"; done
ln -sf "$(command -v "$(basename "$PYC")")" "$T/noop-bin/$(basename "$PYC")"
out="$( cd "$T/novault" && env -u HL_VAULT_READ_FIXTURE -u OP_SERVICE_ACCOUNT_TOKEN -u REPO \
        HL_VAULT_READ_ROUTE=sdk HL_VAULT_READ_PY_CANDIDATES=vault-unreachable-stub HL_WSL=off \
        HL_LEAK_PY="$T/noop-bin/$(basename "$PYC")" PATH="$T/noop-bin" HOME="$T/noop-home" \
        REPO="$PWD" bash "$(git rev-parse --git-path hooks)/pre-push" 2>&1 )"; rc=$?
check "an unreachable vault does not block the push" "$([ "$rc" = 0 ] && printf 0 || printf 1)" \
      "rc=$rc $(printf '%s' "$out" | tr '\n' '|' | cut -c1-240)"
check "but it prints the SKIP rather than passing silently" \
      "$(printf '%s' "$out" | grep -qiE 'SKIP' && printf 0 || printf 1)" \
      "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-240)"

# (3b) a checker that CRASHES is not a leak: rc 1 with no verdict line must print NOT JUDGED and let
# the push through, because accusing a clean tree of a leak is how a hook loses its authority.
mk_repo "$T/broken"; git -C "$T/broken" remote add origin "$REMOTE"
( cd "$T/broken" && REPO="$PWD" bash scripts/git/install-hooks.sh --push >/dev/null )
rm -f "$T/broken/scripts/lib/repo_root.py"
out="$( cd "$T/broken" && REPO="$PWD" git push origin HEAD:refs/heads/broken 2>&1 )"; rc=$?
check "a crashed leak eye lets the push through, and says NOT JUDGED" \
      "$([ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'NOT JUDGED' && printf 0 || printf 1)" \
      "rc=$rc $(printf '%s' "$out" | tr '\n' '|' | tail -c 200)"
check "and never calls a crash a leak" \
      "$(printf '%s' "$out" | grep -q 'REFUSED' && printf 1 || printf 0)"

# (4) THE WORKTREE ARM — the defect this script exists to not have
mk_repo "$T/main-wt"; git -C "$T/main-wt" worktree add -q "$T/link-wt" -b wt 2>/dev/null
( cd "$T/link-wt" && REPO="$PWD" bash scripts/git/install-hooks.sh --push >/dev/null )   # install FROM the worktree
naive="$( cd "$T/link-wt" && printf '%s/hooks/%s' "$(git rev-parse --git-dir)" pre-push )"
deployed="$( cd "$T/link-wt" && d="$(git rev-parse --git-path hooks)"; case "$d" in /*) ;; *) d="$PWD/$d";; esac; printf '%s/pre-push' "$d" )"
check "the naive dirname(--git-dir) path is NOT where the hook went" \
      "$( [ "$naive" != "$deployed" ] && [ ! -e "$naive" ] && printf 0 || printf 1)" "naive=$naive deployed=$deployed"
check "a SECOND worktree of the same clone reads the installed hook" \
      "$(grep -q 'managed-by: scripts/git/install-hooks.sh' "$deployed" && printf 0 || printf 1)"
out="$( cd "$T/link-wt" && REPO="$PWD" bash scripts/git/install-hooks.sh --check 2>&1 )"
check "--check run from the OTHER worktree reports SAME, not MISSING" \
      "$(printf '%s' "$out" | grep -q 'SAME' && printf 0 || printf 1)" "$out"
# and the arm that makes --check load-bearing: delete the hook, --check --strict must go red
rm -f "$deployed"
( cd "$T/link-wt" && REPO="$PWD" bash scripts/git/install-hooks.sh --check --strict >/dev/null 2>&1 ); rc=$?
check "a clone with NO hook is MISSING under --strict, not silently green" "$([ "$rc" != 0 ] && printf 0 || printf 1)"
# drift: an edited hook must not read as SAME
( cd "$T/link-wt" && REPO="$PWD" bash scripts/git/install-hooks.sh --push >/dev/null )
printf '# tampered\n' >>"$deployed"
out="$( cd "$T/link-wt" && REPO="$PWD" bash scripts/git/install-hooks.sh --check --strict 2>&1 )"; rc=$?
check "an EDITED managed hook is DRIFTED under --strict" "$([ "$rc" != 0 ] && printf '%s' "$out" | grep -q DRIFTED && printf 0 || printf 1)"
# a foreign hook is refused, never overwritten
printf '#!/usr/bin/env bash\n# someone else\n' >"$deployed"; chmod +x "$deployed"
printf 'kept\n' >"$T/marker-inside-foreign"
out="$( cd "$T/link-wt" && REPO="$PWD" bash scripts/git/install-hooks.sh --push 2>&1 )"; rc=$?
check "a FOREIGN pre-push hook is refused, not overwritten" \
      "$([ "$rc" != 0 ] && printf '%s' "$out" | grep -qi refused && grep -q 'someone else' "$deployed" && printf 0 || printf 1)"

after_hook="$([ -f "$_home_hook" ] && cksum <"$_home_hook" || echo ABSENT)"
check "the self-test installed nothing into the checkout it was run from" \
      "$([ "$before_hook" = "$after_hook" ] && printf 0 || printf 1)" "before=$before_hook after=$after_hook"

printf 'install-hooks.sh --self-test: %s failing arm(s)\n' "$fails"
exit "$fails"
