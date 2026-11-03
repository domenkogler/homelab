#!/usr/bin/env bash
# rotate-engine-bearers.sh — PROPOSE the two coupled engine bearers; never write.
#
#   WHY THIS EXISTS. `spark-llm_api` and `litellm-engine_api` both sit in
#   `NOT_AUTO_ROTATABLE` in scripts/secrets/provision-secrets.py, so `--rotate <item>` refuses
#   them BY DESIGN: the engine's accepted-key list lives in vLLM's argv, so a vault-only write
#   leaves the running engine authenticating the OLD value while every re-rendered consumer
#   holds the new one. The documented shape for that class is §5b of prompt-update.md: generate
#   the value where nothing reads it, land it, converge, prove both directions.
#
#   WHAT THIS DOES NOT DO: it does not read, print, store or transmit a value. It prints exactly
#   one line per item — the title and the fact that a value is proposed — and writes the value to
#   a 0600 file whose path it prints, so the operator's one `op item edit` can read it without the
#   value ever reaching argv or a transcript. `--apply` writes the vault field from that file and
#   `shred -u`s it.
#
#   The engine renders TWO accepted keys (templates/docker_services/spark-ai/docker-compose.yml.j2
#   :312-314, `--api-key` is `nargs='+'`): position 1 must stay `spark-llm_api` because the
#   oom-watchdog parses that position, position 2 is `litellm-engine_api`. Both therefore move in
#   one window, or neither: rotating one leaves the other live.
#
# Usage:
#   bash scripts/secrets/rotate-engine-bearers.sh              # propose; print two files + hashes
#   bash scripts/secrets/rotate-engine-bearers.sh --apply      # write both vault fields, shred files
set -uo pipefail
_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
. "$_hl_d/lib/repo-root.sh"
VAULT="Homelab-ansible"
ITEMS="spark-llm_api litellm-engine_api"
OUTDIR="${TMPDIR:-/tmp}/hl-engine-keys-$$"
APPLY=0
DIRNEXT=0
for a in "$@"; do
  if [ "$DIRNEXT" = 1 ]; then OUTDIR="$a"; DIRNEXT=0; continue; fi
  case "$a" in
    --apply) APPLY=1 ;;
    --dir)   DIRNEXT=1 ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

say(){ printf '%s\n' "$*"; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v op >/dev/null || fail "op CLI not found"
mkdir -p "$OUTDIR" && chmod 700 "$OUTDIR"

if [ "$APPLY" = "0" ]; then
  say "== proposing two NEW values (nothing written to the vault) =="
  for it in $ITEMS; do
    f="$OUTDIR/$it"
    ( umask 077; python3 -c 'import secrets,string,sys
al=string.ascii_letters+string.digits+"-_"
sys.stdout.write("".join(secrets.choice(al) for _ in range(32)))' > "$f" ) || fail "could not mint a value for $it"
    chmod 600 "$f"
    say "  $(printf '%-20s' "$it") proposed  sha256[:12]=$(sha256sum "$f" | cut -c1-12)  file=$f"
  done
  say ""
  say "The vault still holds the OLD values. Nothing has moved yet."
  say "Apply with:  bash scripts/secrets/rotate-engine-bearers.sh --apply --dir $OUTDIR"
  say "⚠ Values live only in $OUTDIR (0700 dir, 0600 files). Never cat them."
  exit 0
fi

say "== applying: writing both vault fields from the proposed files =="
for it in $ITEMS; do
  f="$OUTDIR/$it"
  [ -s "$f" ] || fail "no proposed value for $it at $f — run without --apply first"
  # The write goes through a pipe, never argv: `op item edit <id> 'credential=<value>'` would put
  # the secret in a process table every user on this box can read.
  id="$(op item get "$it" --vault "$VAULT" --format json </dev/null 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' 2>/dev/null)"
  [ -n "$id" ] || fail "$it: could not resolve an item id in $VAULT"
  # Round-trip: get the item, set `value` on the field whose id already exists, edit via pipe.
  op item get "$id" --format json </dev/null 2>/dev/null \
    | python3 -c '
import json,sys
item=json.load(sys.stdin); want=open(sys.argv[1]).read().rstrip("\n")
hit=[f for f in item.get("fields",[]) if f.get("id")=="credential"]
if not hit: sys.exit("no field with id=credential — refusing a fields-only template")
hit[0]["value"]=want
json.dump(item,sys.stdout)
' "$f" \
    | op item edit "$id" >/dev/null 2>&1
  rc=$?
  # Re-read and verify by hash — an op rc alone is not evidence (op 2.39 spurious HTTP errors).
  got="$(op read "op://$VAULT/$it/credential" </dev/null 2>/dev/null | sha256sum | cut -c1-12)"
  wanth="$(sha256sum "$f" | cut -c1-12)"
  if [ "$got" = "$wanth" ]; then
    say "  $(printf '%-20s' "$it") written  sha256[:12]=$got  (rc=$rc, re-read matches)"
    shred -u "$f" 2>/dev/null || rm -f "$f"
  else
    fail "$it: re-read does NOT match the proposal (rc=$rc) — the value is UNPROVEN; the file is kept at $f and the vault may hold either value. Converge nothing."
  fi
done
rmdir "$OUTDIR" 2>/dev/null || true
say ""
say "Both fields written and re-read. The RUNNING engine still authenticates the OLD values."
say "Next: converge spark so the engine boots with the new accepted-key list, then prove both directions."
