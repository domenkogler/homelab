#!/usr/bin/env bash
# ============================================================================
# vm-tokens.sh — spark's engine token counters, per day, out of VictoriaMetrics
#
# WHAT IT ANSWERS: "how many tokens did spark produce, per day" and, when given
# --price, "what would that traffic have cost at an external per-token price".
# The counters are the engine's own (`vllm:*`, job="vllm", instance=spark.kogler.si),
# so the numbers are a measurement of every caller at once: **totals are known,
# attribution is not** — there is no client/key/user label anywhere on this path
# (docs/observability.md §LLM token accounting). A per-machine token number is NOT
# what this prints, and no averaging trick in the output column makes it one.
#
# THE SPLIT THAT MAKES A PRICE LEGIBLE, and the proof behind it, measured 2026-10-12:
#   vllm:prompt_tokens_total  ==  vllm:prefix_cache_queries_total  ==  sum(vllm:prompt_tokens_by_source_total)
#   vllm:prompt_tokens_cached_total  ==  vllm:prefix_cache_hits_total   ⊂ prompt_tokens_total
# So `uncached input = prompt − cached` is arithmetic on one quantity, not a guess, and
# the three price lines (input / output / cached-read) never double-count. Cross-checked
# against the request-level histograms (`vllm:request_{prompt,generation}_tokens_sum`)
# to <1 %; the residue is requests still in flight at the window edge.
#
# DAY BUCKETS: `increase(…[1d])` EVALUATED AT LOCAL MIDNIGHT, so a row is that calendar
# day, not a rolling 24 h seen from now. Counter resets (an engine restart inside a day)
# are handled by increase() and are additionally PRICED OUT of silence: the `resets` and
# `series` columns print restarts and the days where no spark engine series exists at all
# (a day with no series prints NO SERIES and is EXCLUDED from every total — a report that
# quietly reads it as zero would understate the period, which is the one way to lie here).
#
# --csv keeps the SAME field count per row as its header, and marks an unmeasured day in a FIELD
# rather than as trailing prose — a thousands separator in that output splits one row into several
# fields, which is what the --csv arm of --self-test holds down.
#
# IT IS A WITNESS, NOT THE INSTRUMENT for anything shorter than a day: the cold scrape
# job samples once a minute, so a sub-minute window is other people's traffic — for a leg
# use vm-window.sh, which refuses that shape.
#
# Usage:
#   ./vm-tokens.sh [--days N] [--end YYYY-MM-DD] [--tz IANA] [--price IN,OUT,CACHED]
#                  [--instance NAME] [--csv] [--dry-run] [--self-test]
#   defaults: --days 7 · --end today · --tz the host's · tokens only, no $ column
#
# Transport — the Victoria endpoint is IaC `victoria_backend_host` (:8428), reachable
# over wg-s2s. A laptop has no route to it, so two forms, and NEITHER is guessed:
#   VM_SSH_HOST=<host>   (default: oldsrv, the Home leg) run the curl there over ssh — the hop
#                        that actually answers from this seat. Away from the house it is
#                        VM_SSH_HOST=oldsrv-vps: a plain node name is the Home leg and times out
#                        off-site (docs/network-vpn.md §The laptop alias contract rule 1)
#   VM_URL=http://host:8428                direct form, for a seat that does have the route
# creds: 1Password `Homelab-ansible/victoria-metrics_api` via `op`, else VM_USERNAME +
# VM_PASSWORD. Written to a 0600 curl config and unlinked; never argv, never printed
# (CONVENTIONS §6 — values never reach stdout, lengths only).
#
# The stdin shape is deliberate, not incidental: creds ride the first two lines of ONE
# pipe into the remote shell and the query list follows on the same stream, and there is
# NO ssh inside the remote loop — a bare `ssh` in that body would eat the loop's own list
# and the run would report a full period after one day (CONVENTIONS §6 stdin trap).
#
# Offline test: `./vm-tokens.sh --self-test` builds a hand-valued fixture for its OWN generated
# bucket epochs and re-runs itself against it (VM_TOKENS_FIXTURE=<file>), so the bucketing, the
# uncached split and both price columns are provable without the box or the vault. The fixture
# hook is the ONLY way this script fabricates data, and it prints a FIXTURE banner when used.
# ============================================================================
set -euo pipefail

# Repo root is FOUND, never assumed from a depth (CONVENTIONS §6 / lib/repo-root.sh) — this script
# reads the Victoria endpoint out of the IaC SSOT, so it needs the root to find group_vars.
_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
. "$_hl_d/lib/repo-root.sh"        # sets REPO; FATAL when no root is found

DAYS=7; END=""; TZQ=""; PRICE=""; INSTANCE="spark.kogler.si"; CSV=0; DRY=0; TEST=0; EMIT=0; STFIX=""
while [ $# -gt 0 ]; do
  case "$1" in
    --days)    DAYS="${2:?--days needs a number}"; shift ;;
    --end)     END="${2:?--end needs YYYY-MM-DD}"; shift ;;
    --tz)      TZQ="${2:?--tz needs an IANA zone}"; shift ;;
    --price)   PRICE="${2:?--price needs input,output,cached (USD per M token)}"; shift ;;
    --instance) INSTANCE="${2:?--instance needs the instance label of the engine}"; shift ;;
    --csv)     CSV=1 ;;
    --dry-run) DRY=1 ;;
    --emit-buckets) EMIT=1 ;;
    --self-test) TEST=1 ;;
    *) echo "unknown arg $1" >&2; exit 1 ;;
  esac
  shift
done
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 needed to parse the query results" >&2; exit 1; }
# A bad --price is refused BEFORE the leg runs: an unparseable price must not cost a VM query.
if [ -n "$PRICE" ]; then
  nf=$(printf '%s' "$PRICE" | awk -F, '{print NF}')
  [ "$nf" = 3 ] || { echo "ERROR: --price wants input,output,cached (USD per M token) — got $PRICE" >&2; exit 1; }
fi
[ -n "$TZQ" ] || TZQ="${TZ:-Europe/Ljubljana}"

# ---- the bucket set: local midnights, one evaluation per day boundary -------------------
mapfile -t BUCKETS < <(python3 - "$DAYS" "$END" "$TZQ" <<'PY'
import sys, datetime, zoneinfo
days, end, tzname = int(sys.argv[1]), sys.argv[2], sys.argv[3]
tz = zoneinfo.ZoneInfo(tzname)
today = (datetime.datetime.strptime(end, "%Y-%m-%d") if end else datetime.datetime.now(tz)).replace(
    hour=0, minute=0, second=0, microsecond=0, tzinfo=tz)
for i in range(days, 0, -1):          # bucket d = day d, evaluated at the midnight that ENDS it
    d = today - datetime.timedelta(days=i)
    print(int((d + datetime.timedelta(days=1)).timestamp()), d.date().isoformat())
PY
)

# --emit-buckets exists so --self-test can pin its fixture to the buckets THIS code generates:
# change the bucketing and the test breaks, instead of both sides drifting together.
if [ "$EMIT" = "1" ]; then printf '%s\n' "${BUCKETS[@]}"; exit 0; fi

SEL="{instance=\"${INSTANCE}\"}"
MGEN="vllm:generation_tokens_total"; MPROMPT="vllm:prompt_tokens_total"; MCACHE="vllm:prompt_tokens_cached_total"
ROWS=""
for line in "${BUCKETS[@]}"; do
  t="${line%% *}"
  for pair in "gen|sum(increase(${MGEN}${SEL}[1d]))" \
              "prompt|sum(increase(${MPROMPT}${SEL}[1d]))" \
              "cached|sum(increase(${MCACHE}${SEL}[1d]))" \
              "req|sum(increase(vllm:request_success_total${SEL}[1d]))" \
              "restarts|max(resets(${MGEN}${SEL}))" \
              "series|count(max_over_time(${MGEN}${SEL}[1d]))"; do
    ROWS+="${t}	${pair%%|*}	${pair#*|}
"
  done
done

if [ "$DRY" = "1" ]; then
  echo "# dry run — ${#BUCKETS[@]} day buckets, instance=${INSTANCE}, tz=${TZQ}"
  echo "# each bucket is the day that ENDS at the shown local midnight; nothing is queried"
  for line in "${BUCKETS[@]}"; do
    t="${line%% *}"; d="${line#* }"
    printf '  %s  (eval_at %s)\n' "$d" "$t"
    printf '%s' "$ROWS" | awk -F'\t' -v t="$t" '$1==t {printf "        %-9s %s\n", $2, $3}'
  done
  exit 0
fi

# ---- the endpoint: resolved from the IaC SSOT, never a literal typed here ----------------
vm_endpoint() {   # echoes http://<victoria_backend_host>:<victoria_metrics_port>
  if [ -n "${VM_URL:-}" ]; then printf '%s' "${VM_URL%/}"; return; fi
  python3 - "$REPO" <<'PY'
import re, sys, pathlib
group = pathlib.Path(sys.argv[1]) / "IaC/ansible/group_vars/all/main.yml"
text = group.read_text(encoding="utf-8") if group.is_file() else ""
def scalar(key):
    m = re.search(r"^" + key + r":\s*(\"?)([^\"#\n]+)\1", text, re.M)
    return m.group(2).strip() if m else ""
def nested(parent, key):        # the `ip:` under a mapping like wg_s2s_vps:
    blk = re.search(r"^" + parent + r":\n((?:[ \t]+.*\n?)+)", text, re.M)
    if not blk:
        return ""
    m = re.search(r"^\s+" + key + r":\s*(\"?)([^\"#\n]+)\1", blk.group(1), re.M)
    return m.group(2).strip() if m else ""
host = scalar("victoria_backend_host")
ref = re.fullmatch(r"{{\s*([\w.]+)\s*}}", host)
if ref:                          # victoria_backend_host IS `wg_s2s_vps.ip` — resolve it here
    parts = ref.group(1).split(".")
    host = nested(parts[0], parts[1]) if len(parts) == 2 else ""
port = scalar("victoria_metrics_port") or ""
if not host or not port:
    sys.exit("ERROR: cannot resolve victoria_backend_host / victoria_metrics_port from "
             f"{group} — point VM_URL at the Victoria endpoint instead")
print(f"http://{host}:{port}")
PY
}

# ---- transport --------------------------------------------------------------------------
ask_all() {   # emits "<name>\t<epoch>\t<json>" per query; no ssh inside a read loop (CONVENTIONS §6)
  if [ -n "${VM_TOKENS_FIXTURE:-}" ]; then
    echo ">>> FIXTURE mode — answering from ${VM_TOKENS_FIXTURE}; the box and the vault are untouched" >&2
    printf '%s' "$ROWS" | python3 -c '
import json, sys
vals = {}
for line in open(sys.argv[1], encoding="utf-8"):
    p = line.rstrip("\n").split("\t")
    if len(p) >= 3 and p[0].isdigit():
        vals[(int(p[0]), p[1])] = p[2]
for line in sys.stdin:
    p = line.rstrip("\n").split("\t")
    if len(p) < 3 or not p[0].isdigit():
        continue
    t, n = int(p[0]), p[1]
    v = vals.get((t, n), "")
    res = [{"metric": {}, "value": [t, v]}] if v != "" else []
    print("\t".join([n, str(t), json.dumps({"status": "success", "data": {"result": res}})]))' "${VM_TOKENS_FIXTURE}"
    return
  fi
  local url host="${VM_SSH_HOST:-}"
  url="$(vm_endpoint)"; printf '>>> endpoint %s\n' "$url" >&2
  local U="${VM_USERNAME:-}" P="${VM_PASSWORD:-}"
  if [ -z "$U" ] || [ -z "$P" ]; then
    command -v op >/dev/null 2>&1 || { echo "ERROR: no op CLI and VM_USERNAME/VM_PASSWORD unset" >&2; exit 1; }
    U=$(op read "op://Homelab-ansible/victoria-metrics_api/username" 2>/dev/null || true)
    P=$(op read "op://Homelab-ansible/victoria-metrics_api/password" 2>/dev/null || true)
  fi
  [ -n "$U" ] && [ -n "$P" ] || { echo "ERROR: victoria-metrics_api credentials unreadable" >&2; exit 1; }
  case "$P" in *\"*) echo "ERROR: credential contains a double quote; cannot embed it safely" >&2; exit 1;; esac
  printf '>>> creds: user=%s chars, secret=%s chars (values not printed)\n' "${#U}" "${#P}" >&2
  if [ -n "$url" ] && [ -z "$host" ] && curl -sf --max-time 5 "${url}/health" >/dev/null 2>&1; then
    echo ">>> transport: direct" >&2
    local C; C=$(mktemp); chmod 600 "$C"
    printf 'user = "%s:%s"\n' "$U" "$P" > "$C"
    printf '%s' "$ROWS" | while IFS=	 read -r t n q; do
      [ -n "$t" ] || continue
      printf '%s\t%s\t' "$n" "$t"
      curl -sS -K "$C" -G --data-urlencode "query=$q" --data-urlencode "time=$t" "${url}/api/v1/query"
      printf '\n'
    done
    rm -f "$C"
  else
    [ -n "$host" ] || host="oldsrv"
    echo ">>> transport: ssh ${host} (this seat has no route to the wg-s2s endpoint)" >&2
    # wire: U, P, url, then (epoch, name, query) as THREE separate lines — no field delimiter to
    # fight with on the far side, and no ssh in the loop body to eat the loop's own list.
    { printf '%s\n%s\n%s\n' "$U" "$P" "$url"; printf '%s' "$ROWS" | tr '\t' '\n'; } | \
      ssh -T -o BatchMode=yes -o ConnectTimeout=8 "$host" \
      'read -r U; read -r P; read -r URL
       C=$(mktemp); chmod 600 "$C"; trap "rm -f \"\$C\"" EXIT
       printf "user = \"%s:%s\"\n" "$U" "$P" > "$C"
       while read -r t && read -r n && read -r q; do
         printf "%s\t%s\t" "$n" "$t"
         curl -sS -K "$C" -G --data-urlencode "query=$q" --data-urlencode "time=$t" "${URL}/api/v1/query"
         printf "\n"
       done'
    local rc=$?
    [ "$rc" = 0 ] || { echo "ERROR: the ssh leg failed (rc $rc) — set VM_SSH_HOST=<host with the route> or VM_URL" >&2; return "$rc"; }
  fi
}

# ---- --self-test: hand-valued fixture over the script's OWN buckets ----------------------
# Every expectation below is written by hand, not produced by the code under test — a test that
# recomputes its own expected value cannot fail. Four buckets, three shapes:
#   · day 1 — a normal day (every metric answers, including the presence probe)
#   · day 2 — the counters answer but the PRESENCE probe does not (an engine that was down at the
#     evaluation instant but served traffic that day). It must still be COUNTED — this arm is the
#     regression that a boundary-instant `count()` probe failed live on 2026-10-04, silently
#     dropping a 6.8 M-token day out of the period total.
#   · days 3+4 — nothing answers at all: that is "spark was not scraped yet", it prints NO SERIES
#     and is LEFT OUT of the averages (a zero-fill prints avg $0.08/day at price A; the correct
#     exclusion prints $0.16).
run_self_test() {
  local self tb fix="" ep="" fails=0 out=""
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  fix=$(mktemp); STFIX="$fix"; trap 'rm -f "${STFIX:-}"' EXIT
  mapfile -t tb < <("$self" --emit-buckets --days 4 --end 2026-10-12 --tz UTC)
  [ "${#tb[@]}" = 4 ] || { echo "FAIL: bucket generator produced ${#tb[@]} buckets, want 4"; return 1; }
  local e1="${tb[0]%% *}" e2="${tb[1]%% *}" e3="${tb[2]%% *}" e4="${tb[3]%% *}"
  { for row in "$e1:100000:1000000:800000:10:0:1" "$e2:200000:2000000:1600000:20:1:"; do
      IFS=: read -r e g p c q r s <<<"$row"
      printf '%s\tgen\t%s\n%s\tprompt\t%s\n%s\tcached\t%s\n%s\treq\t%s\n%s\trestarts\t%s\n' \
        "$e" "$g" "$e" "$p" "$e" "$c" "$e" "$q" "$e" "$r"
      # the trailing `series` row is emitted ONLY when the fixture says it has a value — that
      # empty `s` above is what makes day 2 the probe-blind-but-counted case
      [ -n "$s" ] && printf '%s\tseries\t%s\n' "$e" "$s" || true
    done
    # e3 and e4 get NO rows at all — the shape of "spark was not scraped on that day"
  } > "$fix"

  want()  { if printf '%s\n' "$out" | grep -qF -- "$1"; then printf '  ok:   %s\n' "$2"; else printf '  FAIL: %s (wanted "%s")\n' "$2" "$1"; fails=$((fails+1)); fi; }
  wantnt(){ if printf '%s\n' "$out" | grep -qF -- "$1"; then printf '  FAIL: %s (must NOT contain "%s")\n' "$2" "$1"; fails=$((fails+1)); else printf '  ok:   %s\n' "$2"; fi; }

  echo "self-test: bucket labels + the day that ends at each eval_at"
  out=$(VM_TOKENS_FIXTURE="$fix" "$self" --end 2026-10-12 --days 4 --tz UTC 2>&1) || true
  want "2026-10-08" "day 8 is labelled 2026-10-08"; want "2026-10-11" "day 11 is labelled 2026-10-11"
  want "NO SERIES"  "an unscraped day prints NO SERIES, not zero"
  want "measured days 2 of 4" "the period says 2 of 4 days were measured"
  want "2026-10-09" "a day whose PRESENCE probe was empty but whose counters answered is still listed"

  echo "self-test: the uncached split (input + cached = prompt, never double-counted)"
  wantnt "4,000,000" "cached is not added on top of prompt"
  want "600,000" "uncached input totals 600,000 (3,000,000 prompt - 2,400,000 cached)"

  echo "self-test: price A (0.20 / 0.60 / 0.005 per M)"
  out=$(VM_TOKENS_FIXTURE="$fix" "$self" --end 2026-10-12 --days 4 --tz UTC --price 0.20,0.60,0.005 2>&1) || true
  want "0.10" "200k in + 800k cached + 100k out = \$0.10"; want "0.21" "400k + 1.6M + 200k = \$0.21"
  want "0.31" "the period total is \$0.31"; want "0.16" "avg/day divides by MEASURED days (a zero-fill says 0.08)"
  wantnt "0.08" "the two unmeasured days are not zero-filled into the average"

  echo "self-test: price B (0.10 / 0.35 / 0.0175 per M)"
  out=$(VM_TOKENS_FIXTURE="$fix" "$self" --end 2026-10-12 --days 4 --tz UTC --price 0.10,0.35,0.0175 2>&1) || true
  want "0.07" "200k in + 800k cached + 100k out = \$0.07 at price B"
  want "0.21" "the period total is \$0.21 at price B"; want "0.10" "avg/day = \$0.10 at price B"

  echo "self-test: --csv emits one field per column, always"
  out=$(VM_TOKENS_FIXTURE="$fix" "$self" --end 2026-10-12 --days 4 --tz UTC --price 0.20,0.60,0.005 --csv 2>&1) || true
  bad=$(printf '%s\n' "$out" | awk -F, '/^2[0-9]{3}-|^TOTAL|^avg/ {if (NF != 7) print $0}')
  if [ -z "$bad" ]; then printf '  ok:   every csv row has exactly 7 fields\n'
  else printf '  FAIL: a csv row is not 7 fields (a thousands separator splits it): %s\n' "$bad"; fails=$((fails+1)); fi

  echo "self-test: the endpoint comes from IaC, never from a typed address"
  wantnt "10.255.40.2" "no wg-s2s address hardcoded in the script body"
  ep=$(vm_endpoint 2>&1) || { printf '  FAIL: endpoint resolution died: %s\n' "$ep"; fails=$((fails+1)); }
  if printf '%s' "$ep" | grep -qE '^http://[0-9.]+:[0-9]+$'; then printf '  ok:   resolves to http://<host>:<port>\n'
  else printf '  FAIL: endpoint did not resolve from group_vars: %s\n' "$ep"; fails=$((fails+1)); fi

  echo "self-test: a bad --price is a refusal, not a zero"
  if out=$("$self" --days 1 --tz UTC --price 0.20,0.60 2>&1 || true) && printf '%s' "$out" | grep -q "wants input,output,cached"; then
    printf '  ok:   a 2-field --price refuses\n'
  else printf '  FAIL: a 2-field --price was accepted\n'; fails=$((fails+1)); fi

  [ "$fails" = 0 ] && { echo "SELF-TEST OK"; return 0; }
  echo "SELF-TEST FAILED: $fails assertion(s)"; return 1
}
if [ "$TEST" = "1" ]; then run_self_test; exit $?; fi

OUT=$(mktemp); trap 'rm -f "$OUT"' EXIT
ask_all > "$OUT"
python3 - "$OUT" "$TZQ" "$PRICE" "$CSV" "$DAYS" <<'PY'
import json, sys, collections, datetime, zoneinfo
raw, tzname, price, csv, days = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1", int(sys.argv[5])
tz = zoneinfo.ZoneInfo(tzname)
rows = collections.defaultdict(dict)
for line in open(raw, encoding="utf-8"):
    p = line.rstrip("\n").split("\t")
    if len(p) < 3:
        continue
    n, t, js = p[0], int(p[1]), "\t".join(p[2:])
    try:
        r = json.loads(js)["data"]["result"]
    except Exception:
        r = []
    rows[t][n] = float(r[0]["value"][1]) if r else None

def day(t):  # the bucket is the day that ENDS at t
    return (datetime.datetime.fromtimestamp(t, tz) - datetime.timedelta(days=1)).date()

P = None
if price:
    parts = price.split(",")
    if len(parts) != 3:
        sys.exit("ERROR: --price wants input,output,cached (USD per M token)")
    P = tuple(float(x) / 1e6 for x in parts)

hdr = ["day", "requests", "input tok (uncached)", "cached tok", "output tok", "restarts"] + (["USD"] if P else [])
W = [11, 9, 20, 14, 12, 9] + ([10] if P else [])          # ONE width list, so header and rows align
def fmt(vals):
    return ",".join(str(v) for v in vals) if csv else "  ".join(str(v).rjust(w) for v, w in zip(vals, W))
def num(v, d=0):
    # CSV never carries a thousands separator: 1,234 is TWO fields there, and a consumer reading
    # --csv with any CSV parser gets a shifted row (caught by the --csv self-test arm).
    return f"{v:.{d}f}" if csv else f"{v:,.{d}f}"
if csv:
    print(",".join(hdr))
else:
    print(fmt(hdr))
tot = collections.Counter()
for t in sorted(rows):
    r, d = rows[t], day(t)
    if all(r.get(k) is None for k in ("gen", "prompt", "cached")):
        # Nothing at all answered for this day. It is LEFT OUT, not zero-filled: a period that
        # reads an unscraped day as 0 tokens understates the whole window (the engine came up
        # mid-window, so the earliest days genuinely have no series — Sep 12-14 here).
        # CSV keeps the SAME field count as its header and puts the marker in `requests`, so a
        # machine reader can tell "not scraped" from "zero" without reading prose.
        if csv:
            print(fmt([str(d), "NO SERIES", "", "", "", ""] + ([""] if P else [])))
        else:
            print(fmt([str(d), "-", "NO SERIES", "", "", ""][:len(hdr)]) + "   <- spark had no engine series that day")
        continue
    miss = [k for k in ("gen", "prompt", "cached") if r.get(k) is None]
    if miss:
        print(f"{d}  INCOMPLETE: no data for {','.join(miss)} — excluded from totals", file=sys.stderr)
        continue
    unc = r["prompt"] - r["cached"]
    vals = [str(d), num(r.get('req') or 0), num(unc), num(r['cached']), num(r['gen']), num(r.get('restarts') or 0)]
    if P:
        m = unc * P[0] + r["cached"] * P[2] + r["gen"] * P[1]
        tot["usd"] += m
        vals.append(num(m, 2))
    for k, v in (("unc", unc), ("ca", r["cached"]), ("ge", r["gen"]), ("pr", r["prompt"]), ("q", r.get("req") or 0)):
        tot[k] += v
    tot["n"] += 1
    print(fmt(vals))
if not tot["n"]:
    sys.exit("ERROR: no day in this window carries engine series — nothing measured, refusing to total zero")
n = tot["n"]
print(fmt(["TOTAL", num(tot['q']), num(tot['unc']), num(tot['ca']), num(tot['ge']), ""] + ([num(tot['usd'], 2)] if P else [])))
print(fmt(["avg/day", num(tot['q']/n), num(tot['unc']/n), num(tot['ca']/n), num(tot['ge']/n), ""] + ([num(tot['usd']/n, 2)] if P else [])))
if not csv:
    print(f"\nmeasured days {n} of {days} in the window · cache hit share {tot['ca']/tot['pr']*100:.1f} % of prompt tokens")
    print("tokens are engine-global (every caller at once — no client, key or user label exists on")
    print("this path); the $ column is arithmetic on those counters at the prices given, and it")
    print("prices the cached tier ONLY if the external provider's own prompt cache hits at spark's")
    print("rate — spark's comes from a KV cache that stays resident 24/7, which no meter buys.")
PY
