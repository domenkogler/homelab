#!/usr/bin/env bash
# rotate-spark-llm-key.sh — the ATOMIC rotation window for `spark-llm_api` (2026-09-18).
#
#   WHY A SCRIPT AND NOT JUST `provision-secrets.py --rotate`: the vault item is not one
# credential, it is THREE DEPLOYED CONSUMERS plus a fourth copy outside Ansible (see
# docs/deployment-ai-stack-secrets.md §4a — read the 2026-09-19 correction there before
# re-stating this as "four bearers"):
#   1. the vLLM engine's `--api-key` argv        (spark,   spark-ai compose)  — THE authority
#   2. the VPS LiteLLM upstream env              (vps,    litellm compose OPENAI_API_KEY)
#   3. the LAN LiteLLM upstream env              (oldsrv, lan-litellm compose OPENAI_API_KEY)
#   4. this laptop harness's spark lane          (~/.pi/agent/models.json → providers.spark.apiKey)
#      ⚠ `llm.ts.kogler.si` is NOT LiteLLM: traefik-tailnet proxies that host straight to
#      spark's own edge and the request is authenticated by the ENGINE's `--api-key` (see
#      routes.yml.j2:365). So #4 is a SECOND COPY OF #1, not a LiteLLM client key — which is
#      why models.json can use it while `litellm_api` (the master key) gets 401 there.
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
say "       spark   playbooks/spark.yml   (FULL converge) ← recreates the engine container"
say "       vps     playbooks/vps.yml     (FULL converge)"
say "       oldsrv  playbooks/home_servers.yml --limit oldsrv.kogler.si"
say "     ⚠ DO NOT use -e docker_services_scope=<svc> here. Measured 2026-09-19: a scoped run"
say "       reported ok=11 changed=0 skipped=17 — the deploy loop skipped the very service named,"
say "       so the new key never reached the compose/argv while the playbook still exited 0."
say "       A green scoped converge is NOT evidence the credential landed; only the argv hash is."
say "  4. wait for the engine to RE-RENDER (argv hash == vault) and then for /health — a health-only"
say "     wait returns instantly, because the engine answers 200 the whole time BEFORE it is recreated."
say "  5. update $MODELS_JSON (a second copy of the ENGINE key — llm.ts is not LiteLLM)."
say "  6. VERIFY BOTH DIRECTIONS — new bearer 200 at engine AND llm.ts, SUPERSEDED bearer 401."
say "     The 401 is the proof; a 200 means the re-render did not land and the window is open."
say "  7. report the per-consumer env hashes vs the vault (empty = host unreachable, not half-applied)."
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
  nohup bash -c "cd '$REPO' && bash scripts/ansible-run.sh $pb ${limit}" >"$log" 2>&1 &
  echo "$host $scope $!" >> "$LOGD/manifest"; }
converge spark   playbooks/spark.yml        spark-ai
converge vps     playbooks/vps.yml          litellm
converge oldsrv  playbooks/home_servers.yml lan-litellm "--limit oldsrv.kogler.si"
say "  launched (detached). tail -f $LOGD/*.log"
# ⚠ Do NOT gate on /health alone. Measured 2026-09-19: the engine answers 200 for the WHOLE
# window before its container is recreated, so a health-only wait returns instantly and the
# verification below then runs against the OLD key — it printed "NEW → 401 / superseded → 200",
# i.e. an exactly inverted and completely false proof. Gate on the argv hash instead: the
# rotation has landed when the engine's own --api-key equals the vault value.
say "  waiting for the engine to RE-RENDER (argv hash == vault), then for /health…"
say "  (converge + cold load can exceed an hour: the full converge re-checks the PLE artifacts first)"
TARGET=$(h "$NEW")
for i in $(seq 1 140); do
  CUR=$(timeout 25 ssh spark 'K=$(docker inspect vllm-qwen-spark --format "{{join .Config.Cmd \" \"}}" | tr " " "\n" | grep -A1 -- "--api-key" | tail -1); printf %s "$K" | sha256sum | cut -c1-12' 2>/dev/null)
  [ "${CUR:-none}" = "$TARGET" ] && { say "  engine argv matches the vault after $((i*30))s"; break; }
  sleep 30
done
[ "${CUR:-none}" = "$TARGET" ] || say "  ⚠ engine argv still ${CUR:-?} after 70 min — the spark re-render did NOT land; do not trust any check below"
for i in $(seq 1 60); do
  code=$(timeout 20 ssh spark 'curl -s -o /dev/null -w "%{http_code}" localhost:8000/health' 2>/dev/null)
  [ "$code" = "200" ] && { say "  engine healthy after $((i*30))s more"; break; }
  sleep 30
done
[ "${code:-0}" = "200" ] || say "  ⚠ engine not healthy — check $LOGD/spark-spark-ai.log before continuing"

# ---- 4. the laptop consumer (outside Ansible) ---------------------------------
# The laptop copy is a second copy of the ENGINE key (llm.ts → spark's edge → engine --api-key),
# so it is only safe to write once the engine itself has re-rendered — hence step 3 above gates
# on the argv hash, not on /health. Writing it early silently breaks this harness's spark lane.
if [ -f "$MODELS_JSON" ] && [ "${CUR:-none}" = "$TARGET" ]; then
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
  say "  ⚠ skipping $MODELS_JSON — the engine has not re-rendered yet; writing it now would point"
  say "    this harness at a key the engine rejects. Re-run once the spark converge lands."
fi

# ---- 5. verify BOTH directions ------------------------------------------------
say ""; say "== verify =="
verify(){ local host=$1 url=$2 tok=$3 label=$4 code
  code=$(timeout 25 ssh "$host" "curl -s -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer $tok' '$url'" 2>/dev/null)
  say "  $label → $code"; }
# Measured 2026-09-19: the edge does NOT authenticate clients with this secret — clients present
# a LiteLLM scoped key (`litellm_*`), and `litellm_api` (the master key) gets 401 at the edge too.
# So "the edge returns 401 with the old bearer" was never a valid test. What IS checkable is that
# each consumer's rendered env equals the vault value; and llm.ts.kogler.si is checked separately
# below because that host bypasses LiteLLM and authenticates with THIS bearer.
envhash(){ timeout 30 ssh "$1" "docker inspect $2 --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep '^OPENAI_API_KEY=' | cut -d= -f2- | tr -d '\\n'" 2>/dev/null | sha256sum | cut -c1-12; }
say "  consumer env hash vs vault NEW ($(h "$NEW")) — a mismatch = that converge did not land:"
say "    litellm      $(envhash vps litellm)"
say "    lan-litellm  $(envhash oldsrv lan-litellm)   (empty hash = host unreachable, NOT a rotation failure)"
verify spark "http://localhost:8000/v1/models" "$NEW" "engine     NEW (want 200)"
if [ -n "$SUPERSEDED" ]; then
  verify spark "http://localhost:8000/v1/models" "$SUPERSEDED" "engine     SUPERSEDED (want 401 — this is the proof)"
else
  say "  engine     SUPERSEDED → skipped (no OLD_SPARK_LLM_KEY): the window is NOT proven closed"
fi
# llm.ts.kogler.si / llm.kogler.si route straight to spark's own edge (traefik-tailnet
# routes.yml.j2:365: "auth is the ENGINE's --api-key, not a middleware"), so this bearer IS the
# client credential there — unlike the LiteLLM edge, which rejects it.
verify spark "https://llm.ts.kogler.si/v1/models" "$NEW" "llm.ts     NEW (want 200)"
if [ -n "$SUPERSEDED" ]; then
  verify spark "https://llm.ts.kogler.si/v1/models" "$SUPERSEDED" "llm.ts     SUPERSEDED (want 401)"
fi
say ""
say "Next: (a) re-render oldsrv's lan-litellm when that host is reachable (it was UNREACHABLE in"
say "this run — an empty env hash there is a down host, not a half-applied secret); (b) history"
say "scrub is now OPTIONAL — once the superseded bearer 401s it is inert (docs §4a records the"
say "condition that re-opens it: rolling any consumer back to the old value)."
