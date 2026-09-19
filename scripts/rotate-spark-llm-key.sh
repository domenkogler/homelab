#!/usr/bin/env bash
# rotate-spark-llm-key.sh — the ATOMIC rotation window for `spark-llm_api` (2026-09-18).
#
# WHY A SCRIPT AND NOT JUST `provision-secrets.py --rotate`: the vault item is not one
# credential, it is FOUR bearers that must agree (see docs/deployment-ai-stack-secrets.md §4a):
#   1. the vLLM engine's `--api-key` argv        (spark,   spark-ai compose)
#   2. the VPS LiteLLM upstream env              (vps,    litellm compose OPENAI_API_KEY)
#   3. the LAN LiteLLM upstream env              (oldsrv, lan-litellm compose OPENAI_API_KEY)
#   4. this laptop harness's spark lane          (~/.pi/agent/models.json → providers.spark.apiKey)
# Rotating the vault and converging "later" leaves a half-applied window in which a re-rendered
# consumer 401s against a still-old engine — and it can be opened by ANOTHER session's converge.
# So: vault write + all three re-renders + the laptop file happen in one run, or not at all.
#
# Cost, stated up front: the engine restarts, and its cold load is ~20-25 min
# (start_period: 1200s — first PLE-table load). Spark inference is DOWN for that window.
#
# Usage:
#   bash scripts/rotate-spark-llm-key.sh              # PLAN ONLY — writes nothing
#   bash scripts/rotate-spark-llm-key.sh --run --yes  # execute the window
#   bash scripts/rotate-spark-llm-key.sh --run --yes --skip-rotate   # VAULT ALREADY ROTATED by
#     hand (2026-09-19 case): re-render the consumers only. Pass the superseded value in the
#     environment as OLD_SPARK_LLM_KEY to keep the "old bearer must 401" proof.
#
# Secrets never touch stdout, argv of other processes, or the transcript: values move through
# shell variables and a 0600 temp file, and every confirmation is a LENGTH or a HASH prefix.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ITEM="spark-llm_api"; VAULT="Homelab-ansible"
WRITE_TOKEN_HOST="vps"; WRITE_TOKEN_PATH="/etc/op/provision-token"
WRITE_TOKEN_ITEM="op-write_api"   # read+write SA, same vault (renamed 2026-09-19 from vps-op-write_api)
MODELS_JSON="$HOME/.pi/agent/models.json"
RUN=0; ASSUME_YES=0; SKIP_ROTATE=0
for a in "$@"; do case "$a" in --run) RUN=1;; --yes) ASSUME_YES=1;; --skip-rotate) SKIP_ROTATE=1;; *) echo "unknown arg: $a" >&2; exit 2;; esac; done

say(){ printf '%s\n' "$*"; }
h(){ printf '%s' "${1:-}" | sha256sum | cut -c1-12; }

# ---- 0. PREFLIGHT -------------------------------------------------------------
say "== preflight =="
BUSY=$(pgrep -af 'ansible-playbook' 2>/dev/null | grep -v "$$" | head -3)
[ -n "$BUSY" ] && { say "ABORT: a converge is already running — this window must be exclusive:"; say "$BUSY"; exit 1; }
say "  no ansible-playbook running ✓"
for w in $(git -C "$REPO" worktree list --porcelain | awk '/^worktree /{print $2}' | tail -n +2); do
  st=$(git -C "$w" status --short 2>/dev/null | wc -l)
  br=$(git -C "$w" branch --show-current 2>/dev/null)
  say "  worktree ${w##*/} [$br] dirty=$st"
done
say "  ⚠ other sessions must be IDLE for this whole window (their converge would half-apply)."
command -v op >/dev/null || { say "ABORT: op CLI not found"; exit 1; }
say "  write-scoped token: item ${WRITE_TOKEN_ITEM} in ${VAULT} (read+write SA, since 2026-09-19), falling back to ${WRITE_TOKEN_HOST}:${WRITE_TOKEN_PATH}. The runner's exported SA token is READ-scoped — 1P answers it with 'Couldn't update the item.'"

say ""
say "== plan =="
say "  1. read the CURRENT value (hash only), for the before/after proof"
say "  2. provision-secrets.py --rotate $ITEM --yes   (writes 1Password = the SSOT; skipped by --skip-rotate)"
say "  3. re-render all three consumers, DETACHED (a timeout-killed converge is worse than none):"
say "       spark   playbooks/spark.yml         -e docker_services_scope=spark-ai   ← restarts the engine"
say "       vps     playbooks/vps.yml           -e docker_services_scope=litellm"
say "       oldsrv  playbooks/home_servers.yml  -e docker_services_scope=lan-litellm --limit oldsrv.kogler.si"
say "  4. wait for /health 200 on spark (expect 20-25 min), then update $MODELS_JSON"
say "  5. VERIFY BOTH DIRECTIONS — new bearer 200, OLD bearer 401. The 401 is the proof;"
say "     a 200 with the old bearer means a re-render did not land and the window is open."
say "  6. remind: history still holds the old value until filter-repo + force-push."
[ "$RUN" = "1" ] || { say ""; say "PLAN ONLY — nothing was written. Re-run with --run --yes inside the window."; exit 0; }
if [ "$ASSUME_YES" != "1" ]; then read -r -p "Execute the window now (engine DOWN ~25 min)? [y/N] " a; [ "${a:-n}" = "y" ] || { say "aborted"; exit 1; }; fi

# ---- 1. before-state ----------------------------------------------------------
# An already-running shell keeps exporting the PREVIOUS token and the environment beats
# ~/.config/op/homelab-sa-token — this exact shadowing aborted a window run on 2026-09-19 with
# a misleading "auth/vault?" line. Re-source the sanctioned file once and retry before blaming
# the rotation.
if ! op vault list </dev/null >/dev/null 2>&1; then
  TOKFILE="$HOME/.config/op/homelab-sa-token"
  if [ -r "$TOKFILE" ]; then
    say "  op auth failed with the inherited env — re-sourcing $TOKFILE and retrying"
    set -a; . "$TOKFILE"; set +a
  fi
fi
OLD=$(op read "op://$VAULT/$ITEM/credential" </dev/null 2>/dev/null)
[ -n "$OLD" ] || { say "ABORT: cannot read the current value. If 1P answers 403, the token in this";
say "  environment is not the current item op_api value — rotate it per docs/1password.md §1 and retry."; exit 1; }
say "  before: len=${#OLD} hash=$(h "$OLD")"

# ---- 2. vault write -----------------------------------------------------------
# The write token is read from the vault itself; the old VPS root-only file is the fallback,
# because that file still carries the token of the DELETED `vps-op-write_api` until its next
# converge — i.e. the fallback is expected to be dead, and saying so beats a silent 403.
SUPERSEDED="${OLD_SPARK_LLM_KEY:-}"
if [ "$SKIP_ROTATE" = "1" ]; then
  NEW="$OLD"
  say "  --skip-rotate: vault already holds the desired value (hash $(h "$NEW")) — re-render only"
  [ -n "$SUPERSEDED" ] || say "  ⚠ OLD_SPARK_LLM_KEY not set in env → cannot prove the superseded bearer is dead."
else
  TOK=$(op read "op://$VAULT/$WRITE_TOKEN_ITEM/credential" </dev/null 2>/dev/null)
  if [ -n "$TOK" ]; then say "  write token from item $WRITE_TOKEN_ITEM (${#TOK} chars, not printed)"
  else
    TOK=$(timeout 60 ssh "$WRITE_TOKEN_HOST" "sudo cat $WRITE_TOKEN_PATH" 2>/dev/null)
    [ -n "$TOK" ] || { say "ABORT: no write-scoped token (item $WRITE_TOKEN_ITEM unreadable AND ${WRITE_TOKEN_HOST} file empty)"; exit 1; }
    say "  write token from ${WRITE_TOKEN_HOST}:${WRITE_TOKEN_PATH} (${#TOK} chars, not printed) — NOTE: that file is the pre-2026-09-19 token and may be revoked"
  fi
  ( export OP_SERVICE_ACCOUNT_TOKEN="$TOK"; cd "$REPO" && python3 scripts/provision-secrets.py --rotate "$ITEM" --yes ) || { say "ABORT: rotate failed"; unset TOK; exit 1; }
  unset TOK
  NEW=$(op read "op://$VAULT/$ITEM/credential" </dev/null 2>/dev/null)
  [ -n "$NEW" ] && [ "$NEW" != "$OLD" ] || { say "ABORT: vault value did not change (op CLI 2.39 may have applied-then-404'd; re-read before retrying!)"; exit 1; }
  SUPERSEDED="$OLD"
  say "  after : len=${#NEW} hash=$(h "$NEW")  ✓ vault rotated"
  say "  ⚠ the superseded value is still LIVE on the engine until the converges land."
fi

# ---- 3. re-render every consumer, detached ------------------------------------
LOGD=$(mktemp -d /tmp/rotate-spark-key.XXXX); : > "$LOGD/manifest"
# Playbook per target — oldsrv is NOT `playbooks/oldsrv.yml`: it lives in `home_servers`,
# so it needs that playbook PLUS an explicit --limit (precedent: services-admin.md §deploy).
# NOTE the deliberate SECOND `local`: in ONE statement bash expands `log="$LOGD/$host-$scope.log"`
# BEFORE host/scope are assigned, so with `set -u` it dies as "host: unbound variable"
# (it did, on the first real run 2026-09-19 — plan mode never reaches this function).
converge(){ local host=$1 pb=$2 scope=$3 limit=${4:-}; local log="$LOGD/$host-$scope.log"
  say "  converge $host via $pb scope=$scope ${limit:+limit=$limit} → $log"
  nohup bash -c "cd '$REPO' && bash scripts/ansible-run.sh $pb --tags docker_services -e docker_services_scope=$scope ${limit}" >"$log" 2>&1 &
  echo "$host $scope $!" >> "$LOGD/manifest"; }
converge spark   playbooks/spark.yml        spark-ai
converge vps     playbooks/vps.yml          litellm
converge oldsrv  playbooks/home_servers.yml lan-litellm "--limit oldsrv.kogler.si"
say "  launched (detached). tail -f $LOGD/*.log"
say "  waiting for the engine to come back (up to 40 min)…"
for i in $(seq 1 80); do
  code=$(timeout 20 ssh spark 'curl -s -o /dev/null -w "%{http_code}" localhost:8000/health' 2>/dev/null)
  [ "$code" = "200" ] && { say "  engine healthy after $((i*30))s"; break; }
  sleep 30
done
[ "${code:-0}" = "200" ] || say "  ⚠ engine not healthy within 40 min — check $LOGD/spark-spark-ai.log before continuing"

# ---- 4. the laptop consumer (outside Ansible) ---------------------------------
if [ -f "$MODELS_JSON" ]; then
  install -m 600 /dev/null "$MODELS_JSON.tmp"
  KEY="$NEW" DST="$MODELS_JSON.tmp" python3 - "$MODELS_JSON" <<'PY'
import json,os,sys
src,dst=sys.argv[1],os.environ["DST"]; key=os.environ["KEY"]
d=json.load(open(src))
def walk(o):
    if isinstance(o,dict):
        for k,v in list(o.items()):
            if k=="apiKey" and isinstance(v,str) and v: o[k]=key
            else: walk(v)
    elif isinstance(o,list):
        for v in o: walk(v)
# ⚠ ONLY the spark lane. An earlier version walked the whole document and overwrote
# EVERY provider's apiKey with the spark key — which would have disabled every other lane
# (VPS edge, Forgejo) in one silent step.
prov=d.get("providers",{}).get("spark")
if not isinstance(prov,dict) or not prov.get("apiKey"):
    raise SystemExit("  ABORT: providers.spark.apiKey not found in models.json — patch it by hand")
prov["apiKey"]=key
open(dst,"w").write(json.dumps(d,indent=2)+"\n")
print("  models.json: providers.spark.apiKey replaced (value not printed)")
PY
  [ -s "$MODELS_JSON.tmp" ] && mv "$MODELS_JSON.tmp" "$MODELS_JSON" || rm -f "$MODELS_JSON.tmp"
else
  say "  ⚠ $MODELS_JSON absent — update the spark lane by hand if this harness uses it"
fi

# ---- 5. verify BOTH directions ------------------------------------------------
say ""; say "== verify =="
verify(){ local host=$1 url=$2 tok=$3 label=$4 code
  code=$(timeout 25 ssh "$host" "curl -s -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer $tok' '$url'" 2>/dev/null)
  say "  $label → $code"; }
verify spark "http://localhost:8000/v1/models" "$NEW"  "engine    NEW (want 200)"
if [ -n "$SUPERSEDED" ]; then
  verify spark "http://localhost:8000/v1/models" "$SUPERSEDED" "engine    SUPERSEDED (want 401 — this is the proof)"
else
  say "  engine    SUPERSEDED → skipped (no OLD_SPARK_LLM_KEY): the window is NOT proven closed"
fi
# The edge does NOT authenticate clients with this secret — clients present
# litellm_master_key; spark-llm_api is only the UPSTREAM credential. So the right edge-side
# check is "does each consumer's env now equal the vault value", not a 401 probe.
envhash(){ timeout 30 ssh "$1" "docker inspect $2 --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep '^OPENAI_API_KEY=' | cut -d= -f2- | tr -d '\\n'" 2>/dev/null | sha256sum | cut -c1-12; }
say "  consumer env hash vs vault NEW ($(h "$NEW")) — a mismatch = that converge did not land:"
say "    litellm      $(envhash vps litellm)"
say "    lan-litellm  $(envhash oldsrv lan-litellm)"
say ""
say "Next, by hand: (a) commit the redaction of any tracked logs that carried the old value;"
say "(b) if the old value was ever pushed, scrub history (git filter-repo --replace-text +"
say "force-push) and rebase every session worktree based on a rewritten commit — and note that"
say "GitHub may still serve the old blob, which is why rotation, not scrubbing, is the fix."
