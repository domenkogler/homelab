#!/usr/bin/env python3
"""Merge the three HD-368 vLLM dashboards into ONE `homelab-llm-dashboard` (HD-377).

WHY A GENERATOR AND NOT A HAND-EDITED FILE (CONVENTIONS §SSOT + the HD-368 precedent):
the three inputs are themselves *derived* — `adapt-vllm-dashboards.py` re-derives them
byte-for-byte from the grafana.com exports 25502 / 24756 / 25043. The merged dashboard
consumes their PANELS, so it is derived too. Hand-editing the merge would make the next
upstream refresh (or the next live-metric fix) a manual re-merge of 53 hand-touched
panels. Order is therefore always: upstream → adapt-vllm-dashboards.py → THIS script.

    python3 scripts/build-llm-dashboard.py            # write the merged dashboard
    python3 scripts/build-llm-dashboard.py --check    # CI form: fail if drift, no write

WHAT MERGING ACTUALLY MEANS HERE (it is not concatenation):
  * de-duplicated coverage — the three exports overlap heavily (3× TTFT, 3× KV, 2× E2E
    latency, 2× prefix-cache, 3× running/queued). See DROPPED for every cut + the reason.
  * new panels none of them have and the owner asked for: engine **readiness** (vLLM /
    SGLang /health) and spark **CPU / RAM / GPU**.
  * **cross-engine `by (job)` join** — the merged view spans vLLM *and* SGLang *and*
    (later) the RX 7600, so every vLLM-only expr gains an `sglang:*` sibling and every
    aggregate gets `by (job, instance)`. Without that a second engine silently lies
    (sum() across engines is not a metric). EXPR_REWRITES below carries each join.
  * DRY: a panel whose query already spans both engines (25502's gnet family) is carried
    VERBATIM — no rewrite, no re-translation of the Chinese legend format it carries.

GPU NOTE — read before "fixing" the empty GPU panels (docs/observability.md §LLM
Dashboard): the GB10 in spark has **no independent VRAM counter** (live 2026-09-16:
`nvidia-smi -q -d MEMORY` → Total/Used/Free `N/A`; `dmon -s um` → fb/bar1 `-`; no
`dcgm`/`dcgmi` package on the host). DCGM is the correct source (SM activity, power,
temp — none of which any other exporter produces) and its panels are authored empty-on-
purpose, NOT faked from host CPU/RAM, which would be a different quantity. See GPU_ROW.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DASH_DIR = ROOT / "IaC/ansible/roles/monitoring/files/dashboards"
DST = DASH_DIR / "homelab-llm.json"

SRC_INFERENCE = DASH_DIR / "llm-inference-sglang-vllm.json"   # gnet 25502
SRC_V2 = DASH_DIR / "vllm-master-v2.json"                      # gnet 24756
SRC_STACK = DASH_DIR / "vllm-dashboard.json"                   # gnet 25043

# canonical homelab header (see adapt-vllm-dashboards.py HOMELAB_HEAD)
HEAD = {
    "timezone": "browser",
    "editable": True,
    "refresh": "10s",                 # inference wants fast refresh (gnet default)
    "time": {"from": "now-1h", "to": "now"},
    "schemaVersion": 41,
    "version": 1,
    "tags": ["homelab", "llm", "vllm", "sglang", "gpu"],
    "title": "Homelab — LLM",
    "uid": "homelab-llm",
    "links": [],
    "annotations": {"list": [{
        "builtIn": 1,
        "datasource": {"type": "grafana", "uid": "-- Grafana --"},
        "enable": True, "hide": True,
        "iconColor": "rgba(0,211,255,1)",
        "name": "Annotations & Alerts", "type": "annotation",
    }]},
    "graphTooltip": 1,
    "preload": False,
    "fiscalYearStartMonth": 0,
}

SPARK = 'job="alloy", instance="spark.kogler.si"'
# The engine half of the readiness pair: VM's `up` for the scrape job that reads the
# engine's :8000/metrics on the spark loopback publish (HD-368 data path).
VLLM_UP = 'up{job="vllm", instance=~"$instance"}'

# ---------------------------------------------------------------------------
# Layout: which source panel goes into which merged row.
#   "inf:<id>" / "v2:<id>" / "stack:<id>"  → verbatim carry (only gridPos changes)
#   a key of NEW_PANELS                    → authored here (no upstream equivalent)
# Order in the list == order on the dashboard. w is the panel width (24-row grid).
# ---------------------------------------------------------------------------
LAYOUT: list[tuple[str, str, list[tuple[str, int]]]] = [
    ("row_health", "Health & Readiness", [
        ("new:vllm_ready", 5), ("new:sglang_ready", 5), ("new:engine_probe", 5),
        ("new:engines_scraped", 4), ("new:model_served", 5),
        ("new:health_note", 24),
    ]),
    ("row_spark", "spark node — CPU / RAM / GPU (GB10 unified memory)", [
        ("new:spark_cpu", 8), ("new:spark_ram_pct", 8), ("new:spark_ram", 8),
        ("new:spark_load", 8), ("new:engine_rss", 8), ("new:spark_disk", 8),
        ("new:spark_disk_io", 8), ("new:spark_disk_iops", 8), ("new:spark_disk_sat", 8),
        ("new:spark_gpu", 12), ("new:gpu_activity", 12),
        ("new:spark_gpu_note", 24),
    ]),
    ("row_sched", "Scheduling & Concurrency", [
        ("new:requests", 8), ("new:kv_cache", 8), ("v2:101", 8),
        ("v2:403", 8), ("new:preemptions", 8), ("inf:17", 8),
        ("inf:18", 8), ("inf:24", 16),
    ]),
    ("row_latency", "Latency", [
        ("inf:7", 12), ("inf:9", 12), ("inf:8", 12), ("inf:10", 12),
    ]),
    ("row_throughput", "Throughput & Workload", [
        ("inf:11", 12), ("inf:12", 12), ("new:request_rate", 8),
        ("inf:19", 8), ("new:request_rate_note", 8),
    ]),
    ("row_cache", "Cache", [
        ("new:prefix_cache", 8), ("inf:13", 8), ("new:e2e_avg", 8),
    ]),
    ("row_reliability", "Reliability", [
        ("v2:502", 8), ("v2:503", 8), ("v2:501", 8),
    ]),
    ("row_request", "Request shape (single-engine deep dive)", [
        ("v2:304", 12), ("v2:202", 12),
    ]),
    ("row_engine_detail", "Per-engine / TP-rank detail", [
        ("inf:21", 12), ("inf:22", 12), ("inf:23", 12), ("inf:14", 12),
    ]),
    ("row_forward", "Forward look — RX 7600 (oldsrv) + SGLang", [
        ("new:forward_note", 24),
    ]),
]

# ---------------------------------------------------------------------------
# Everything NOT carried: the cut list, with the reason for each cut.
# An "LLM dashboard" that is the union of three dashboards is not one dashboard;
# these are dropped because the merged view keeps an equal-or-better panel.
# ---------------------------------------------------------------------------
DROPPED = {
    # --- vllm-dashboard (gnet 25043): fully superseded, 0 panels carried ---
    "stack:1": "→ row Health 'Engines scraped' (same up{job=vllm}, now spans SGLang too)",
    "stack:19": "→ row Cache 'Average E2E latency' (identical avg sum/count, scoped to $instance)",
    "stack:2": "→ row Latency 'E2E Request Latency' (histogram_quantile p50/95/99 is readable; a raw bucket bargauge is not)",
    "stack:3": "→ row Throughput 'Request rate' (same rate(request_success_total), instance-scoped)",
    "stack:20": "→ row Latency 'Inter-Token Latency (ITL)' (quantiles, not avg-of-sums)",
    "stack:4": "→ row Latency 'Time to First Token' (quantiles)",
    "stack:10": "→ row Scheduling 'Requests: running / queued' (both engines in one panel)",
    "stack:11": "→ same stat panel",
    "stack:12": "→ row Scheduling 'KV cache usage' (both engines)",
    "stack:13": "→ row Cache 'Prefix cache hit rate' (same ratio, instance-scoped)",
    "stack:14": "→ duplicate of stack:12 within its own dashboard",
    "stack:15": "→ row spark 'spark CPU' (same node_cpu_seconds_total query, clearer title/unit)",    "stack:16": "→ row spark 'spark RAM' (adds absolute GiB + the MemAvailable floor the OOM class needs)",
    "stack:17": "→ row spark 'spark disk' (adds the /mnt/spark_nvme XFS mount — weights/KV live there, HD-359)",
    # --- vllm-master-v2 (gnet 24756) cuts ---
    "v2:102": "→ 'Requests: running / queued' (gauge + timeseries say the same thing; the timeseries is the one with history)",
    "v2:103": "rejected on merit: running/(running+waiting) is an unlabeled composite of two uncorrelated gauges — not a rate, not a ratio with a definition. 'Preemption rate' (v2:105) carries the real signal.",
    "v2:104": "→ row Latency TTFT p99 (same histogram_quantile, with p50/p95 alongside)",
    "v2:105": "→ row Scheduling 'Preemptions' (carried in the 'preemptions' new panel: per-second rate + window total)",
    "v2:201": "→ row Latency 'E2E Request Latency'",
    "v2:203": "→ row Latency TTFT + ITL panels (same two histograms, each readable on its own axis — overlaying p99 TTFT with p99 TPOT forces a shared unit on two 100×-different scales)",
    "v2:301": "→ row Throughput 'Token throughput' (carried as 'token_rate')",
    "v2:302": "rejected on merit: prompt/generation ratio is dominated by chat-template noise and duplicates the two rates already plotted side by side.",
    "v2:303": "rejected on merit: 1 - prefill_kv_computed/prompt_tokens is the same quantity as the prefix-cache hit ratio (carried) via a second, more fragile formula.",
    "v2:305": "→ row Latency 'Queue Wait Time' (inf:10, quantiles per engine)",
    "v2:401": "→ row Scheduling 'KV cache usage' (both engines, not vLLM-only)",
    "v2:402": "→ row Cache 'Prefix cache hit rate' (both engines)",
    # --- llm-inference (gnet 25502) cuts ---
    "inf:15": "→ merged 'Requests: running / queued' (already joins vLLM + SGLang; kept once)",
    "inf:16": "→ same stat panel",
    "inf:20": "carried as the 'preemptions' panel — the HD-368 rewrite of this panel already IS the preemption rate; the SGLang eviction half stays empty until SGLang lands",
}

# ---------------------------------------------------------------------------
# Cross-engine join rewrites. mode "sub" (substring) / "exact" (whole trimmed
# expr — needed when new contains old, which would re-match on re-run).
# Every rule names the live series it targets; verified 2026-09-16 against the
# spark engine /metrics (137 job="vllm" series in VM).
# ---------------------------------------------------------------------------
EXPR_REWRITES = {
    # The SGLang siblings here mirror the 25502 author's own metric naming (that
    # export is the SGLang+vLLM pair), so they are the best available guess for the
    # SGLang lane: empty until the engine lands, correct by construction when it does.
    "v2:101": [
        # Carried stat, but the source expr sums ACROSS instances and across every
        # engine — in a merged multi-engine view that is not a metric. Scope it to the
        # picker (still vLLM-only: SGLang has no finished_reason label, so the numerator
        # has no SGLang sibling).
        ('(sum(rate(vllm:request_success_total{finished_reason=~"stop|length", '
         'model_name="$model_name"}[5m])) / clamp_min(sum(rate(vllm:request_success_total'
         '{model_name="$model_name"}[5m])), 0.001)) * 100',
         '(sum(rate(vllm:request_success_total{finished_reason=~"stop|length", '
         'model_name=~"$model_name", instance=~"$instance"}[$__rate_interval])) / '
         'clamp_min(sum(rate(vllm:request_success_total{model_name=~"$model_name", '
         'instance=~"$instance"}[$__rate_interval])), 0.001)) * 100', "exact"),
    ],
    "v2:403": [
        ('vllm:num_requests_running{model_name="$model_name"}',
         'vllm:num_requests_running{model_name=~"$model_name", instance=~"$instance"}',
         "exact"),
        ('vllm:num_requests_waiting{model_name="$model_name"}',
         'vllm:num_requests_waiting{model_name=~"$model_name", instance=~"$instance"}',
         "exact"),
        ('vllm:num_requests_waiting_by_reason{model_name="$model_name"}',
         'vllm:num_requests_waiting_by_reason{model_name=~"$model_name", instance=~"$instance"}',
         "exact"),
    ],
    "v2:502": [
        ('sum by(finished_reason) (increase(vllm:request_success_total{model_name="$model_name"}[$__range]))',
         'sum by (finished_reason, job) (increase({__name__=~"vllm:request_success_total|sglang:finish_reason_count", '
         'instance=~"$instance"}[$__range]))', "exact"),
    ],
    "v2:503": [
        ('sum(rate(vllm:e2e_request_latency_seconds_count{model_name="$model_name"}[5m]))',
         'sum by (job) (rate({__name__=~"vllm:e2e_request_latency_seconds_count|sglang:e2e_request_latency_seconds_count", '
         'instance=~"$instance"}[$__rate_interval]))', "exact"),
        ('sum(rate(vllm:request_success_total{model_name="$model_name"}[5m]))',
         'sum by (job) (rate({__name__=~"vllm:request_success_total|sglang:num_run_reqs_total", '
         'instance=~"$instance"}[$__rate_interval]))', "exact"),
    ],
    "v2:501": [
        # job=~ so the SGLang engine's process lands in the same panel (HD-368 scoped
        # this to job="vllm" precisely because 12 other jobs emit these — never global).
        ('rate(python_gc_collections_total{job="vllm"}[5m])',
         'rate(python_gc_collections_total{job=~"vllm|sglang", instance=~"$instance"}[$__rate_interval])', "exact"),
        ('process_resident_memory_bytes{job="vllm"}',
         'process_resident_memory_bytes{job=~"vllm|sglang", instance=~"$instance"}', "exact"),
    ],
    "v2:304": [
        # vLLM has no SGLang-side sibling with the same semantics here (vLLM's
        # request_prompt_tokens HISTOGRAM has no SGLang equivalent; SGLang exports a
        # summary), so this heatmap stays vLLM-only rather than summing two different
        # quantities. See the "Why the token panels are not re-joined" note.
        ('sum by(le) (increase(vllm:request_prompt_tokens_bucket{model_name="$model_name"}[$__rate_interval]))',
         'sum by (le) (increase(vllm:request_prompt_tokens_bucket{model_name=~"$model_name", '
         'instance=~"$instance"}[$__rate_interval]))', "exact"),
    ],
    "v2:202": [
        ('rate(vllm:request_prefill_time_seconds_sum{model_name="$model_name"}[5m]) / '
         'clamp_min(rate(vllm:request_prefill_time_seconds_count{model_name="$model_name"}[5m]), 0.001)',
         'sum by (job) (rate({__name__=~"vllm:request_prefill_time_seconds_sum|sglang:per_stage_req_latency_seconds_sum", '
         'instance=~"$instance"}[$__rate_interval])) / clamp_min(sum by (job) (rate({__name__=~'
         '"vllm:request_prefill_time_seconds_count|sglang:per_stage_req_latency_seconds_count", '
         'instance=~"$instance"}[$__rate_interval])), 0.001)', "exact"),
        ('rate(vllm:request_decode_time_seconds_sum{model_name="$model_name"}[5m]) / '
         'clamp_min(rate(vllm:request_decode_time_seconds_count{model_name="$model_name"}[5m]), 0.001)',
         'sum by (job) (rate({__name__=~"vllm:request_decode_time_seconds_sum|sglang:per_stage_req_latency_seconds_sum", '
         'stage="decode", instance=~"$instance"}[$__rate_interval])) / clamp_min(sum by (job) (rate({__name__=~'
         '"vllm:request_decode_time_seconds_count|sglang:per_stage_req_latency_seconds_count", '
         'stage="decode", instance=~"$instance"}[$__rate_interval])), 0.001)', "exact"),
    ],
}

# Legend formats applied per panel after rewrites (keyed by target refId).
LEGEND = {
    "v2:101": {"A": "{{ job }}"},
    "v2:403": {"A": "vLLM running", "B": "vLLM waiting", "C": "vLLM waiting by reason"},
    "v2:502": {"A": "{{ finished_reason }} · {{ job }}"},
    "v2:503": {"A": "completed req/s · {{ job }}", "B": "success req/s · {{ job }}"},
    "v2:501": {"A": "GC/s · {{ job }} {{ instance }}", "B": "RSS · {{ job }} {{ instance }}"},
    "v2:304": {"A": "{{ le }}"},
    "v2:202": {"A": "prefill s · {{ job }}", "B": "decode s · {{ job }}"},
}

# Panels whose expr already joins both engines in the upstream export → carried
# byte-identical (no rewrite = no silent drift on an upstream refresh).
VERBATIM_PREFIXES = ("inf:",)

# ---------------------------------------------------------------------------
# $instance propagation. The $instance variable exists so the SECOND engine (SGLang
# on spark, then the RX 7600 on oldsrv) becomes selectable — but gnet 25502's exports
# only carry it on its own panels, and gnet 24756's carry none at all. Meanwhile every
# panel I author filters on it. Result without this pass: select anything other than
# the default and most of the board silently empties — the exact failure class HD-368
# recorded for the stale `current:` model pin. So each bare matcher is extended here,
# and guard_instance() fails the build if a panel still lacks the filter.
# ---------------------------------------------------------------------------
def add_instance(expr: str) -> str:
    """Extend an existing label matcher with instance=~"$instance" (idempotent).

    Targets the two matcher shapes the exports actually use; anything else is left
    alone and caught by guard_instance() rather than guessed at."""
    if 'instance=' in expr:
        return expr
    if '{__name__=~' in expr:
        # ... "<last alternation>", model_name=~"$model_name"}  /  }}  forms
        for probe in ('", model_name=~"$model_name"}', '"}', '|sglang:token_usage"}',
                      '|sglang:num_running_reqs"}', '|sglang:num_queue_reqs"}'):
            if expr.rstrip().endswith(probe):
                inner = probe[2:-2] if probe.endswith('"}') and not probe.startswith('", ') else None
                if probe.startswith('", '):
                    return expr.rstrip()[:-len(probe)] + '", instance=~"$instance"}'
                # closing brace form: insert before it
                return expr.rstrip()[:-1] + ', instance=~"$instance"}'
        return expr
    # single-metric selector: name{labels}
    m = re.match(r'^(?P<head>[A-Za-z_:][A-Za-z0-9_:]*\{)(?P<rest>[^}]*)\}', expr.strip())
    if m and m.group("rest"):
        return expr.replace('}', ', instance=~"$instance"}', 1) if expr.rstrip().endswith('}') \
            else expr
    return expr

# ---------------------------------------------------------------------------
# Authored panels: readiness, spark node, and the de-duplicated aggregates that
# replace several near-identical upstream panels with one cross-engine panel.
#   spec: type, title, description, unit, max?, targets[{expr, legend}],
#         thresholds?[{color,value?}], panel_extra? (deep-merged)
# ---------------------------------------------------------------------------
NEW_PANELS = {
    # ---- Health & Readiness ------------------------------------------------
    "vllm_ready": {
        "type": "stat",
        "title": "vLLM engine — ready",
        "description": (
            "up{job=\"vllm\"} = the spark Alloy reaches the engine's /metrics on the "
            "loopback :8000 publish (HD-368 data path). 1 = engine answering. "
            "This is the scrape-leg signal; pair it with the /health probe below: "
            "metrics can serve while /health is not 200, and /health can be green "
            "while the scrape leg is dead (a config gap, not an outage)."
        ),
        "unit": "short", "min": 0, "max": 1,
        "targets": [{"expr": VLLM_UP, "legend": "{{ instance }}"}],
        "thresholds": [{"color": "red", "value": None}, {"color": "green", "value": 1}],
    },
    "sglang_ready": {
        "type": "stat",
        "title": "SGLang engine — ready",
        "description": (
            "up{job=\"sglang\"} — EMPTY until the SGLang lane runs (HD-367 S2/S3). Wiring "
            "when it lands = one prometheus.scrape \"sglang\" block in alloy.river.j2 on "
            "the same loopback pattern as the vllm job. "
            "NOTE ON EVERY SGLang QUERY IN THIS DASHBOARD: the `sglang:*` siblings are "
            "written from SGLang's documented metric names (and the gnet 25502 author's "
            "pairing of them), NOT from a live SGLang scrape — we have never run one. "
            "Expect to correct names here exactly as HD-368 corrected the vLLM half "
            "against the live engine; the fix is in this script, not in the JSON."
        ),
        "unit": "short", "min": 0, "max": 1,
        "targets": [{"expr": 'up{job="sglang", instance=~"$instance"}', "legend": "{{ instance }}"}],
        "thresholds": [{"color": "red", "value": None}, {"color": "green", "value": 1}],
    },
    "engine_probe": {
        "type": "stat",
        "title": "Engine /health probe",
        "description": (
            "blackbox http_2xx against the engine's own /health — the readiness signal "
            "INDEPENDENT of the metrics path. ⏳ EMPTY until the probe is wired "
            "(HD-377): the target is spark loopback, so it must run through a blackbox "
            "exporter reachable from spark's Alloy — the VPS blackbox cannot reach "
            "127.0.0.1:8000 on spark. Authored empty rather than faked from up{job=vllm}, "
            "which would make the panel a duplicate of the first one and hide real "
            "readiness failures. Spec: docs/observability.md §LLM Dashboard."
        ),
        "unit": "short", "min": 0, "max": 1,
        "targets": [{
            "expr": 'max(probe_success{job="blackbox_llm", instance=~"$instance"})',
            "legend": "http_2xx",
        }],
        "thresholds": [{"color": "red", "value": None}, {"color": "green", "value": 1}],
    },
    "engines_scraped": {
        "type": "stat",
        "title": "Engines scraped",
        "description": (
            "count of inference-engine scrape targets across vLLM + SGLang. Replaces the "
            "K8s-only vllm:healthy_pods_total the production-stack export shipped. "
            "1 today (spark vLLM); rises with SGLang on spark or an RX 7600 engine on "
            "oldsrv. 0 = the metrics pipeline itself is down."
        ),
        "unit": "short",
        "targets": [{"expr": "count(up{job=~\"vllm|sglang\"})", "legend": "engines"}],
        "thresholds": [{"color": "red", "value": None}, {"color": "green", "value": 1}],
    },
    "model_served": {
        "type": "stat",
        "title": "Model served",
        "description": (
            "The model_name label live on the engine right now — a sanity check that the "
            "dashboards $model_name variable and the engine agree. Guards the HD-368 "
            "'stale upstream current:' class of bug: a pinned model_name makes every "
            "panel behind the variable silently render No data."
        ),
        "unit": "string",
        "targets": [{
            "expr": 'count by (model_name) ({__name__=~"vllm:num_requests_running|sglang:num_running_reqs"})',
            "legend": "{{ model_name }}",
            "instant": True,
        }],
        "panel_extra": {"options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "/model_name/", "values": True},
                                    "textMode": "name", "colorMode": "value"}},
    },
    "health_note": {
        "type": "text",
        "title": "Readiness semantics",
        "content": (
            "**Three different failures, three different panels.** "
            "`/health probe` red + `vLLM ready` green = engine up, HTTP layer broken. "
            "`vLLM ready` red + container running = **scrape/config** leg (Alloy, the "
            "loopback publish `spark_metrics_publish`), not an inference outage. "
            "Both red = engine down. The engine restarts and re-reads 60 GB of weights "
            "on its own; the OOM history is in `docs/spark-incidents.md`, the KV/memory "
            "governance in `docs/hardware-spark.md` §Unified-memory budget."
        ),
    },

    # ---- spark node (the explicit ask) -------------------------------------
    "spark_cpu": {
        "type": "timeseries",
        "title": "spark CPU — % busy",
        "description": (
            "Host CPU from the Alloy unix host exporter (node_cpu_seconds_total, "
            "job=\"alloy\", instance=spark). Matters on a GB10: the PLE CPU offload + "
            "tokenizer/detokenizer threads run here and compete with the engine, so CPU "
            "saturation surfaces as TTFT before it surfaces anywhere in the vllm: family. "
            "Cross-check on Host Overview (`homelab-host-overview`) for the other hosts."
        ),
        "unit": "percent", "min": 0, "max": 100,
        "targets": [{
            "expr": f'(1 - avg(rate(node_cpu_seconds_total{{{SPARK}, mode="idle"}}[$__rate_interval]))) * 100',
            "legend": "CPU %",
        }],
    },
    "spark_ram_pct": {
        "type": "stat",
        "title": "spark RAM — % of unified pool",
        "description": (
            "GB10 unified memory: 121.6 GiB serves GPU **and** host — there is no VRAM "
            "number to read, so this percentage IS the GPU-memory number. Thresholds track "
            "the HD-375 alert reserve: MemAvailable < 24 GiB warns, < 16 GiB is critical "
            "(≈ used 80 % / 87 % of the pool). Live 2026-09-16: 92 % used, 9.5 GiB "
            "available with the engine loaded — already inside the warn band."
        ),
        "unit": "percent", "min": 0, "max": 100,
        "targets": [{
            "expr": f'(1 - node_memory_MemAvailable_bytes{{{SPARK}}} / '
                    f'node_memory_MemTotal_bytes{{{SPARK}}}) * 100',
            "legend": "used %",
        }],
        "thresholds": [{"color": "green", "value": None}, {"color": "yellow", "value": 75},
                       {"color": "orange", "value": 87}, {"color": "red", "value": 92}],
    },
    "spark_ram": {
        "type": "timeseries",
        "title": "spark RAM — used / available (absolute)",
        "description": (
            "Absolute GiB — the series that actually predicts an OOM is **MemAvailable**, "
            "not utilisation %. Every global OOM in spark-incidents.md came from "
            "replace-by-percentage GPU-reserve arithmetic against this pool (HD-374 now "
            "sizes the KV pool explicitly with --kv-cache-memory-bytes). Watch the FLOOR: "
            "the ~21.9 GiB host reserve is the line the engine must not cross."
        ),
        "unit": "bytes", "min": 0,
        "targets": [
            {"expr": f"node_memory_MemTotal_bytes{{{SPARK}}}", "legend": "total"},
            {"expr": f"node_memory_MemTotal_bytes{{{SPARK}}} - node_memory_MemAvailable_bytes{{{SPARK}}}",
             "legend": "used"},
            {"expr": f"node_memory_MemAvailable_bytes{{{SPARK}}}", "legend": "available (the OOM floor)"},
        ],
    },
    "spark_load": {
        "type": "timeseries",
        "title": "spark load — 1m / 5m",
        "description": "Load average. Sustained load above the core count with a live engine = CPU contention with the PLE offload threads (visible as TTFT inflation).",
        "unit": "short", "min": 0,
        "targets": [
            {"expr": f"node_load1{{{SPARK}}}", "legend": "load 1m"},
            {"expr": f"node_load5{{{SPARK}}}", "legend": "load 5m"},
        ],
    },
    "engine_rss": {
        "type": "timeseries",
        "title": "Engine process RSS — vs 105 GiB cage",
        "description": (
            "Resident set of the inference process itself (job=~vllm|sglang): the weights "
            "mirror + PLE CPU offload + runtime. This is the quantity the HD-374 memory "
            "cage (limit 105 GiB) bounds — crossing it kills the CONTAINER instead of the "
            "host, which is the whole point of the cage. On GB10 this memory is also "
            "CUDA-visible, so it is part of what a discrete GPU would call VRAM."
        ),
        "unit": "bytes", "min": 0,
        "targets": [
            {"expr": 'max by (job, instance) (process_resident_memory_bytes{job=~"vllm|sglang", instance=~"$instance"})',
             "legend": "RSS · {{ job }} {{ instance }}"},
            {"expr": "105 * 1024^3", "legend": "memory cage (105 GiB, HD-374)", "instant": True},
        ],
    },
    "spark_disk": {
        "type": "timeseries",
        "title": "spark disk used — / and /mnt/spark_nvme",
        "description": (
            "Root (EXT4) and the XFS data partition that holds the model weights, the KV "
            "cache and the torch compile caches (HD-359: weights must never land on EXT4). "
            "A full XFS partition fails the next model load, not this one — which is why "
            "it is on the LLM dashboard and not only on Host Overview."
        ),
        "unit": "percent", "min": 0, "max": 100,
        "targets": [{
            "expr": f'(1 - node_filesystem_avail_bytes{{{SPARK}, mountpoint=~"/|/mnt/spark_nvme"}} / '
                    f'node_filesystem_size_bytes{{{SPARK}, mountpoint=~"/|/mnt/spark_nvme"}}) * 100',
            "legend": "{{ mountpoint }}",
        }],
    },
    # --- disk WORK, not disk capacity -------------------------------------------------
    # The owner asked for "DISK io/throughput", and it matters here for one concrete
    # reason: every model load streams tens of GB through the XFS mount on nvme0n1, so
    # a slow-looking load is either the device saturating or the engine not asking for
    # data — these two panels separate them. Verified live in VM 2026-09-16:
    # node_disk_* exists for instance="spark.kogler.si", device="nvme0n1" (the Alloy
    # unix exporter already enables `diskstats`) — no exporter or scrape change needed.
    # One device serves both / (EXT4) and /mnt/spark_nvme (XFS), so the split by
    # mountpoint is NOT available at the block layer; capacity stays per-mount above.
    "spark_disk_io": {
        "type": "timeseries",
        "title": "spark disk I/O — read / write throughput",
        "description": (
            "Bytes/s on the single NVMe device (nvme0n1) that carries BOTH the EXT4 root "
            "and the XFS weights/KV mount — the block layer cannot separate the two, so "
            "attribute a large sustained read to the model load and anything steady-and-"
            "small to the OS. Read spikes at the moment a load starts, with the engine's "
            "`num_requests_running` still at 0, = streaming weights, not inference I/O."
        ),
        "unit": "Bps", "min": 0,
        "targets": [
            {"expr": f'rate(node_disk_read_bytes_total{{{SPARK}}}[5m])',
             "legend": "read · {{ device }}"},
            {"expr": f'rate(node_disk_written_bytes_total{{{SPARK}}}[5m])',
             "legend": "write · {{ device }}"},
        ],
    },
    "spark_disk_iops": {
        "type": "timeseries",
        "title": "spark disk IOPS — completions/s",
        "description": (
            "Completed read/write operations per second on nvme0n1. Read it against the "
            "throughput panel: high bytes at LOW iops = sequential streaming (a healthy "
            "weight load); low bytes at HIGH iops = small random I/O. Per-operation wait "
            "time is deliberately NOT plotted here — the builder gives every target the "
            "panel's unit, and seconds-per-op on an ops/s axis is exactly the kind of "
            "mislabeled series this board refuses; it is on Host Overview (\"Disk avg "
            "wait\") with the correct unit."
        ),
        "unit": "ops", "min": 0,
        "targets": [
            {"expr": f'rate(node_disk_reads_completed_total{{{SPARK}}}[5m])',
             "legend": "reads/s · {{ device }}"},
            {"expr": f'rate(node_disk_writes_completed_total{{{SPARK}}}[5m])',
             "legend": "writes/s · {{ device }}"},
        ],
    },
    "spark_disk_sat": {
        "type": "timeseries",
        "title": "spark disk saturation — device busy %",
        "description": (
            "The saturation half of the USE method: fraction of time nvme0n1 had at least "
            "one request in flight. Pinned near 1.0 while throughput is below what the "
            "device can do = queue depth/segment limits or a contended mount, not a slow "
            "disk. Same counter as Host Overview's 'Busiest disk' stat, over time."
        ),
        "unit": "percentunit", "min": 0, "max": 1,
        "targets": [
            {"expr": f'rate(node_disk_io_time_seconds_total{{{SPARK}}}[5m])',
             "legend": "busy · {{ device }}"},
        ],
    },
    "spark_gpu": {
        "type": "timeseries",
        "title": "spark GPU — DCGM (⚠ impossible on GB10, pending deletion)",
        "description": (
            "SM / tensor-pipe / device-memory activity ratios. **EMPTY PERMANENTLY ⏳ — "
            "these three series can never appear on a GB10, and this panel is pending "
            "deletion, not wiring.** "
            "Measured 2026-09-16 with the `nvidia/dcgm-exporter` image already on spark: "
            "the exporter starts, then logs `Not collecting DCP metrics: This request is "
            "serviced by a module of DCGM that is not currently loaded`, and forcing the "
            "DCP counter file gives `Skipping line 21..25 (GR_ENGINE_ACTIVE / "
            "PIPE_TENSOR_ACTIVE / DRAM_ACTIVE / PCIE_TX_BYTES / PCIE_RX_BYTES): metric "
            "not enabled`. NVIDIA has stated DCGM profiling will not be supported on "
            "Spark (not a datacenter device). What DCGM DOES give here — and what is "
            "worth wiring instead — is `DCGM_FI_DEV_GPU_UTIL` (measured 88-90 % under "
            "load), `GPU_TEMP` (50-58 C), `POWER_USAGE` (12-39 W), "
            "`TOTAL_ENERGY_CONSUMPTION`, `SM_CLOCK` (2509 MHz) and `XID_ERRORS`; none of "
            "those is on any other exporter, and they are NOT faked from host CPU%/RAM, "
            "which is a different quantity. Runbook + the full emit/refuse table: "
            "docs/observability.md §LLM Dashboard (GPU) and §Host sensors and disk I/O."
        ),
        "unit": "percentunit", "min": 0, "max": 1,
        "targets": [
            {"expr": 'DCGM_FI_PROF_SM_ACTIVE{job="dcgm", instance=~"$instance"}', "legend": "SM active · {{ instance }}"},
            {"expr": 'DCGM_FI_PROF_PIPE_TENSOR_ACTIVE{job="dcgm", instance=~"$instance"}', "legend": "tensor pipe · {{ instance }}"},
            {"expr": 'DCGM_FI_PROF_DRAM_ACTIVE{job="dcgm", instance=~"$instance"}', "legend": "DRAM active · {{ instance }}"},
        ],
    },
    "gpu_activity": {
        "type": "timeseries",
        "title": "GPU work — engine-reported (live today)",
        "description": (
            "What the engine says the GPU is doing, available WITHOUT DCGM: vLLM's own "
            "per-GPU FLOP/byte estimates (vllm:estimated_flops_per_gpu_total, "
            "estimated_read/write_bytes_per_gpu_total) plus the KV-pool occupancy that is "
            "the closest live proxy for 'GPU busy with real work'. Use this for shape now; "
            "the DCGM panel for truth once wired."
        ),
        "unit": "short",
        "targets": [
            {"expr": 'sum by (job, instance) (rate(vllm:estimated_flops_per_gpu_total{instance=~"$instance"}[$__rate_interval]))',
             "legend": "est FLOP/s · {{ instance }}"},
            {"expr": 'sum by (job, instance) (rate(vllm:estimated_read_bytes_per_gpu_total{instance=~"$instance"}[$__rate_interval]))',
             "legend": "est read B/s · {{ instance }}"},
            {"expr": 'max by (instance) (vllm:kv_cache_usage_perc{instance=~"$instance"})',
             "legend": "KV pool % · {{ instance }}"},
        ],
    },
    "spark_gpu_note": {
        "type": "text",
        "title": "GB10 GPU telemetry — what is and is not available",
        "content": (
            "**GB10 has no independent VRAM counter, by design.** NVIDIA's own answer to "
            "`nvidia-smi` reporting memory as \"Not Supported\": the DGX Spark is a "
            "unified-memory device and nvidia-smi reports memory utilisation only when "
            "there is dedicated VRAM — for memory usage use `free`/`top` or the DGX "
            "Dashboard. Measured here: `nvidia-smi -q -d MEMORY` → FB/BAR1 N/A, "
            "`dmon -s um` → fb/bar1 `-`, and the dcgm-exporter emits **no** `FB_*` series. "
            "So 'GPU usage' is assembled from three honest signals: unified-pool RAM (the "
            "allocation lives there), engine RSS (the process's share of it) and "
            "engine-reported work. **Nothing is faked:** the alternative would be a GPU "
            "panel plotting CPU. "
            "⚠ The DGX Dashboard's 'GPU Memory' tile is *system* RAM under a GPU label "
            "(`memory_total_in_kib` = 127532360 KiB = the whole 121.6 GiB pool; its "
            "`gpu_memory_in_use_in_mb` is a hard 0) — do not copy that semantic here. "
            "Temperatures are split on purpose: host silicon (NVMe composite, acpitz SoC "
            "zones, WiFi PHY) is on **Host Overview** from the Alloy `hwmon` collector; "
            "the GPU die temperature is DCGM's `DCGM_FI_DEV_GPU_TEMP` (there is no nvidia "
            "hwmon chip, and the acpitz zones run 5-15 C above it — they are NOT the GPU)."
        ),
    },

    # ---- merged cross-engine aggregates (replace multiple near-duplicates) --
    "requests": {
        "type": "timeseries",
        "title": "Requests — running / queued (both engines)",
        "description": (
            "Running vs queued per engine, vLLM and SGLang in one panel "
            "(merges gnet 25502's two stat panels + gnet 24756's Active Requests gauge + "
            "gnet 25043's running/pending pair). Queued sustained > 0 with running flat "
            "= the scheduler is the bottleneck, not the GPU."
        ),
        "unit": "short", "min": 0,
        "targets": [
            {"expr": 'sum by (job, instance) ({__name__=~"vllm:num_requests_running|sglang:num_running_reqs", instance=~"$instance"})',
             "legend": "running · {{ job }} {{ instance }}"},
            {"expr": 'sum by (job, instance) ({__name__=~"vllm:num_requests_waiting|sglang:num_queue_reqs", instance=~"$instance"})',
             "legend": "queued · {{ job }} {{ instance }}"},
        ],
    },
    "kv_cache": {
        "type": "timeseries",
        "title": "KV cache usage — % of pool (both engines)",
        "description": (
            "Fraction of the KV pool in use. Sits under the HD-374 explicit budget "
            "(--kv-cache-memory-bytes = 8.8e9 ≈ 283k tokens @262k ctx). Pinning near 1.0 "
            "is what precedes a preemption storm — read it together with the Preemptions "
            "panel. Collapses gnet 24756 'GPU KV Cache Usage' + gnet 25043 'GPU KV Usage "
            "Percentage' + gnet 25043 'GPU Cache Usage' (three panels, one quantity). "
            "SGLang's same-quantity name is token_usage (its KV+pool utilisation gauge)."
        ),
        "unit": "percentunit", "min": 0, "max": 1,
        "targets": [{
            "expr": 'max by (job, instance) ({__name__=~"vllm:kv_cache_usage_perc|sglang:token_usage", instance=~"$instance"})',            "legend": "{{ job }} {{ instance }}",
        }],
    },
    "preemptions": {
        "type": "timeseries",
        "title": "Preemptions — rate + window total (vLLM)",
        "description": (
            "vllm:num_preemptions_total: requests evicted from KV and recomputed. "
            "Sustained > 0 means the KV budget is too tight for the concurrent window "
            "(HD-374 governance; the gnet 25502 panel this replaces was HD-368-rewritten "
            "from a metric this build does not emit). 0 is the target — the 2026-09-15 "
            "C3 incident is what a non-zero line looks like. "
            "vLLM-only: SGLang signals the same event through its eviction counters "
            "(eviction_duration_seconds / evicted_tokens_total), already plotted by the "
            "carried gnet 25502 KV-pressure panel — not summed into this one."
        ),
        "unit": "short", "min": 0,
        "targets": [
            {"expr": 'sum by (job, instance) (rate({__name__=~"vllm:num_preemptions_total", instance=~"$instance"}[$__rate_interval]))',
             "legend": "preemptions/s · {{ instance }}"},
            {"expr": 'sum by (job, instance) (increase({__name__=~"vllm:num_preemptions_total", instance=~"$instance"}[$__range]))',
             "legend": "window total · {{ instance }}"},
        ],
    },
    "request_rate": {
        "type": "stat",
        "title": "Request rate (QPS)",
        "description": (
            "Completed requests/s — derived from the engine's own success counter. The "
            "gnet 25043 export asked for vllm:current_qps, which only exists on the K8s "
            "production-stack router we do not run (HD-368 finding); this is the honest "
            "equivalent, now instance-scoped."
        ),
        "unit": "reqps", "min": 0,
        "targets": [{
            "expr": 'sum by (job) (rate({__name__=~"vllm:request_success_total|sglang:num_run_reqs_total", instance=~"$instance"}[$__rate_interval]))',
            "legend": "{{ job }}",
        }],
    },
    "request_rate_note": {
        "type": "text",
        "title": "Why the token panels are not re-joined",
        "content": (
            "The two panels above (gnet 25502) **already** cover both engines: each keeps a "
            "`vllm:*` target and the `sglang:realtime_tokens_total` sibling side by side. "
            "Re-writing them into one `{__name__=~...}` regex would only be possible by "
            "assuming vLLM's `prompt_tokens_total` and SGLang's `realtime_tokens_total` are "
            "the same quantity measured the same way — they are not (the SGLang counter "
            "carries a `mode` dimension), and a sum across them would print a number that "
            "means neither. **Cross-engine joins in this dashboard are applied only where "
            "the two engines expose the same metric name** (the waiting_by_reason / "
            "prefix_cache_* / num_preemptions_total family), which is why the joins are "
            "visible in the Scheduling and Cache rows and absent here."
        ),
    },
    "prefix_cache": {
        "type": "timeseries",
        "title": "Prefix cache hit rate (both engines)",
        "description": (
            "hits / queries for the automatic prefix cache. The single most valuable "
            "cache number on a chat/agent box: every hit is prefill you did not pay. "
            "Live ≈ 0.97 on spark (HD-368). Collapses gnet 24756's gauge + gnet 25043's "
            "rate panel into one. "
            "⚠ NOT live-verified for SGLang, and the denominator is the weaker half: "
            "SGLang exposes cached_tokens_total{cache_source} but no prefix-cache QUERIES "
            "counter, so the SGLang leg divides by total prompt tokens — an upper bound "
            "on the true hit rate. Confirm against a real scrape (same drill as HD-368)."
        ),
        "unit": "percentunit", "min": 0, "max": 1,
        "targets": [{
            "expr": 'sum by (job) (rate({__name__=~"vllm:prefix_cache_hits_total|sglang:cached_tokens_total", '
                    'cache_source="device", instance=~"$instance"}[$__rate_interval])) / '
                    'clamp_min(sum by (job) (rate({__name__=~"vllm:prefix_cache_queries_total|sglang:prompt_tokens_total", '
                    'instance=~"$instance"}[$__rate_interval])), 1)',
            "legend": "hit rate · {{ job }}",
        }],
    },
    "e2e_avg": {
        "type": "stat",
        "title": "Average E2E latency",
        "description": (
            "Mean end-to-end request latency (sum/count). Kept as the one headline "
            "latency number; the p50/p95/p99 truth is the E2E timeseries in the Latency "
            "row. Replaces gnet 25043's unscoped avg() across every engine."
        ),
        "unit": "s", "min": 0,
        "targets": [{
            "expr": 'sum by (job) ({__name__=~"vllm:e2e_request_latency_seconds_sum", instance=~"$instance"}) / '
                    'clamp_min(sum by (job) ({__name__=~"vllm:e2e_request_latency_seconds_count", instance=~"$instance"}), 0.001)',            "legend": "{{ job }}",
        }],
    },
    "forward_note": {
        "type": "text",
        "title": "Forward look — RX 7600 + SGLang",
        "content": (
            "**The rows above are engine-agnostic on purpose.** Every joined query groups "
            "`by (job, instance)` and filters on `$instance`/`$model_name`, so adding a "
            "target adds a series, not a dashboard. "
            "**RX 7600 (oldsrv, decision #24 pinned-services tier — Whisper STT + bge-m3 "
            "embed + bge-reranker):** needs an ROCm exporter (`rocm-smi`/amd_smi → "
            "Prometheus textfile) + an oldsrv Alloy scrape job, then its GPU columns land "
            "in the node row here — that card DOES expose VRAM, unlike the GB10. "
            "**SGLang:** needs `prometheus.scrape \"sglang\"` only; its `sglang:*` sibling "
            "is already written into every joined query, so the SGLang half of this "
            "dashboard fills from the same file. "
            "**The three HD-368 dashboards stay provisioned** until the owner retires them."
        ),
    },
}

# Panels that need a title suffix / legend note when carried verbatim.
DESCRIPTION_NOTES = {
    "inf:14": "Carried from gnet 25502: vLLM per-engine step/token histogram + the SGLang CUDA-graph counter.",
    "inf:13": "Cached-token stats — vLLM cached prompt tokens vs the prefix-cache miss delta, plus the SGLang radix-cache pair.",
}

# Operator-visible strings must be English (CONVENTIONS: English technical). The three
# upstream exports carried Chinese (25502) and Korean (24756); this guard is what keeps
# them out of the merge. Two whitelists:
#   ASCII_OK   — typographic punctuation we author (dashes, arrows, ≈)
#   REPO_GLYPH — repo-conventional STATUS markers already used across docs/dashboards
#                (⏳ deploy-gated/pending, ✅ done, ⚠ warning, § doc-section pointer)
# Anything else non-ASCII is treated as untranslated upstream text or a look-alike glyph.
ASCII_OK = set("—–…“”‘’·•→←↑↓°±×÷≈≥≤≠   ” “ ’ ‘ ‑­")
REPO_GLYPH = set("⏳✅⚠❌§◆■□→")
NON_ASCII = re.compile(r"[^\x00-\x7f]")


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def panels_by_id(dash: dict) -> dict:
    out = {}
    for p in dash.get("panels", []):
        if p.get("type") != "row":
            out[p.get("id")] = p
    return out


def sources() -> dict:
    return {
        "inf": panels_by_id(load(SRC_INFERENCE)),
        "v2": panels_by_id(load(SRC_V2)),
        "stack": panels_by_id(load(SRC_STACK)),
    }


def ref_panel(key: str, srcs: dict) -> dict:
    """Return a deep copy of the referenced panel spec (source or authored)."""
    kind, _, ident = key.partition(":")
    if kind == "new":
        if ident not in NEW_PANELS:
            raise KeyError(f"LAYOUT references unknown authored panel {key!r}")
        return build_new(NEW_PANELS[ident])
    src = srcs.get(kind)
    if src is None:
        raise KeyError(f"LAYOUT references unknown source {key!r}")
    pid = int(ident)
    if pid not in src:
        raise KeyError(f"LAYOUT references missing panel {key!r} (not in that export)")
    panel = json.loads(json.dumps(src[pid]))  # deep copy
    if key in EXPR_REWRITES:
        panel = apply_rewrites(panel, key)
    # Propagate the merged-view instance filter into every carried query, EXCEPT the
    # gnet 25502 panels that already bind it via ${instance} (double-brace Grafana
    # syntax) — those are rewritten upstream and must stay byte-identical.
    for t in panel.get("targets") or []:
        expr = t.get("expr") or ""
        if "${instance}" in expr or "${model_name}" in expr:
            continue
        if "$instance" in expr:
            continue
        t["expr"] = add_instance(expr)
    if key in LEGEND:
        for t in panel.get("targets") or []:
            fmt = LEGEND[key].get(t.get("refId") or "A")
            if fmt:
                t["legendFormat"] = fmt
    if key in DESCRIPTION_NOTES:
        panel["description"] = (panel.get("description") or "").strip()
        panel["description"] = (panel["description"] + " — " if panel["description"] else "") \
            + DESCRIPTION_NOTES[key]
    # Grafana-level hygiene for the merged view
    panel.pop("id", None)
    panel.pop("gridPos", None)
    return panel


def apply_rewrites(panel: dict, key: str) -> dict:
    for t in panel.get("targets") or []:
        expr = (t.get("expr") or "").strip()
        for old, new, mode in EXPR_REWRITES[key]:
            if mode == "exact" and expr == old:
                expr = new
                break
            if mode == "sub" and old in expr:
                expr = expr.replace(old, new)
        t["expr"] = expr
    return panel


def build_new(spec: dict) -> dict:
    ptype = spec["type"]
    defaults: dict = {
        "unit": spec.get("unit", "short"),
        "color": {"mode": "palette-classic"},
        "custom": {
            "axisCenteredZero": False, "axisPlacement": "auto", "drawStyle": "line",
            "fillOpacity": 8, "gradientVisibility": False, "hideFrom": {"legend": False, "tooltip": False, "viz": False},
            "lineInterpolation": "linear", "lineWidth": 1, "pointSize": 5,
            "showPoints": "never", "spanNulls": False,
            "stacking": {"group": {"A": "none"}, "mode": "none"},
            "thresholdsStyle": {"mode": "off"}, "axisBorderShow": False,
        },
        "mappings": [],
        "thresholds": {
            "mode": "absolute",
            "steps": steps(spec.get("thresholds")) if spec.get("thresholds") else
                     [{"color": "green", "value": None}],
        },
    }
    if spec.get("min") is not None:
        defaults["min"] = spec["min"]
    if spec.get("max") is not None:
        defaults["max"] = spec["max"]

    panel: dict = {
        "type": ptype,
        "title": spec["title"],
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "fieldConfig": {"defaults": defaults, "overrides": []},
        "options": {},
        "targets": [],
        "description": spec.get("description", ""),
    }
    if ptype == "text":
        panel.pop("fieldConfig")
        panel["options"] = {"mode": "markdown", "content": spec["content"]}
        panel["targets"] = []
        panel["mode"] = "markdown"
        return panel

    for i, t in enumerate(spec.get("targets") or []):
        target = {
            "refId": chr(ord("A") + i),
            "expr": t["expr"],
            "legendFormat": t.get("legend", ""),
            "datasource": {"type": "prometheus", "uid": "prometheus"},
        }
        if t.get("instant"):
            target["instant"] = True
            target["range"] = False
        panel["targets"].append(target)

    if ptype == "stat":
        panel["options"] = {
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
            "orientation": "auto", "textMode": "auto", "justifyMode": "auto",
            "colorMode": "value", "graphMode": "area", "showPercentChange": False,
            "percentChangeColorMode": "standard", "wideLayout": True,
        }
        defaults["custom"] = {}
    elif ptype == "gauge":
        panel["options"] = {
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
            "orientation": "auto", "showThresholdLabels": False,
            "showThresholdMarkers": True, "minVizHeight": 75, "minVizWidth": 75,
            "sizing": "auto",
        }
        defaults["custom"] = {}
    else:  # timeseries
        panel["options"] = {
            "legend": {"calcs": ["mean", "max"], "displayMode": "list", "placement": "bottom", "showLegend": True},
            "tooltip": {"hideZeros": False, "mode": "multi", "sort": "desc"},
        }
    if "thresholds" in spec and ptype in ("stat", "gauge"):
        defaults["custom"] = {} if defaults.get("custom") in ({}, None) else defaults["custom"]
    panel.update(spec.get("panel_extra") or {})
    return panel


def steps(thresholds):
    return [{"color": t["color"], "value": t.get("value")} for t in thresholds]


def build() -> dict:
    srcs = sources()
    panels: list = []
    y = 0
    rid = 1
    for _row_id, row_title, items in LAYOUT:
        # FLAT row form: a `type: "row"` panel followed by sibling panels that follow it
        # in the list — the form every other dashboard in this folder uses
        # (homelab-ups.json, the three HD-368 exports). The alternative (panels nested
        # INSIDE the row object + collapsed:true) hides the whole row until the operator
        # clicks it, and a collapsed row with an empty nested list renders nothing at all.
        panels.append({
            "type": "row",
            "id": rid,
            "title": row_title,
            "collapsed": False,
            "gridPos": {"h": 1, "w": 24, "x": 0, "y": y},
            "panels": [],
        })
        rid += 1
        y += 1
        x = 0
        row_h = 0
        for key, w in items:
            panel = ref_panel(key, srcs)
            h = panel_height(panel)
            if x + w > 24:            # wrap to a fresh line when the row is full
                y += row_h
                x, row_h = 0, 0
            panel["id"] = rid
            rid += 1
            panel["gridPos"] = {"h": h, "w": w, "x": x, "y": y}
            panels.append(panel)
            x += w
            row_h = max(row_h, h)
        y += row_h

    dash = dict(HEAD)
    dash["templating"] = {"list": template_vars()}
    dash["panels"] = panels
    return dash


def panel_height(panel: dict) -> int:
    """Uniform heights per kind so a wrapped line never leaves a ragged gap."""
    ptype = panel["type"]
    if ptype == "text":
        return 3
    if ptype == "stat":
        return 5
    return 8


def template_vars() -> list:
    # Instance + model vars enumerate BOTH engine families so a second engine (or the
    # RX 7600 later) becomes selectable the moment it is scraped — the same join trick
    # the queries use, applied to the pickers. gnet 25502's own pair is the pattern.
    inst_q = ('label_values({__name__=~"vllm:num_requests_running|sglang:num_running_reqs"}, instance)')
    model_q = ('label_values({__name__=~"vllm:num_requests_running|sglang:num_running_reqs"}, model_name)')
    return [
        {
            "name": "instance", "label": "Instance", "type": "query",
            "datasource": {"type": "prometheus", "uid": "prometheus"},
            "query": inst_q, "definition": inst_q, "refresh": 1,
            "regex": "", "sort": 0, "multi": True, "includeAll": True, "allValue": ".*",
            "current": {"selectedAllValue": True, "text": ["All"], "value": ["$__all"]},
            "hide": 0, "options": [], "skipUrlSync": False,
            "description": "Engine instances (vLLM/SGLang). Add a scrape job → it appears here.",
        },
        {
            "name": "model_name", "label": "Model", "type": "query",
            "datasource": {"type": "prometheus", "uid": "prometheus"},
            "query": model_q, "definition": model_q, "refresh": 1,
            "regex": "", "sort": 0, "multi": True, "includeAll": True, "allValue": ".*",
            "current": {"selectedAllValue": True, "text": ["All"], "value": ["$__all"]},
            "hide": 0, "options": [], "skipUrlSync": False,
            "description": "Served model. NEVER pin `current:` to a literal — HD-368 found a stale upstream pin that made every panel behind it empty.",
        },
    ]


# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------
def guard_references(dash: dict) -> list:
    errors = []
    wanted = set()
    for _row, _title, items in LAYOUT:
        for key, _w in items:
            wanted.add(key)
    for _row, _title, items in LAYOUT:
        for key, _w in items:
            kind, _, ident = key.partition(":")
            if kind != "new" and not ident.isdigit():
                errors.append(f"LAYOUT key {key!r}: panel id must be numeric")
    # every LAYOUT panel must resolve — proven by construction in ref_panel(), this
    # catches the case where a source export changed shape
    try:
        srcs = sources()
        for key in sorted(wanted):
            ref_panel(key, srcs)
    except KeyError as exc:
        errors.append(str(exc))
    return errors


def guard_no_dead_query(dash: dict) -> list:
    """A carried panel must keep a non-empty expr; authored panels must not reference
    a metric we proved absent WITHOUT saying so in the description."""
    errors = []
    for p in dash["panels"]:
        if p.get("type") in ("row", "text"):
            continue
        targets = p.get("targets") or []
        if not targets:
            errors.append(f"panel {p.get('title')!r} has no targets")
        for t in targets:
            if not (t.get("expr") or "").strip():
                errors.append(f"panel {p.get('title')!r} target {t.get('refId')} empty expr")
            expr = t["expr"]
            if "$model_name" in expr and "model_name=" not in expr:
                errors.append(f"panel {p.get('title')!r}: $model_name used outside a label matcher")
    return errors


def guard_english(dash: dict) -> list:
    errors = []

    def offenders(text: str) -> list:
        return [c for c in text if not c.isascii() and c not in ASCII_OK and c not in REPO_GLYPH]

    def walk(node, path):
        if isinstance(node, dict):
            for k, v in node.items():
                if k in ("title", "label", "description", "legendFormat", "content") \
                        and isinstance(v, str):
                    bad = offenders(v)
                    if bad:
                        shown = "".join(sorted(set(bad)))[:12]
                        errors.append(
                            f"non-English/unexpected glyph {shown!r} at {path}.{k}: {v[:90]!r}")
                walk(v, f"{path}.{k}")
        elif isinstance(node, list):
            for i, v in enumerate(node):
                walk(v, f"{path}[{i}]")

    walk(dash, "")
    return errors


def guard_stale(dash: dict) -> list:
    """HD-368's dead-metric list must not creep back into a QUERY through a merge.

    Scoped to target exprs, NOT the whole file: the panel descriptions deliberately NAME
    several of these ("vllm:current_qps only exists on the K8s router we do not run") so
    the next operator knows why the query looks the way it does. Scanning prose would
    fail the build for documenting the fix."""
    stale = [
        "vllm:num_requests_swapped", "vllm:kv_block_idle_before_evict_seconds",
        "vllm:gpu_prefix_cache_hits_total", "vllm:gpu_prefix_cache_queries_total",
        "vllm:current_qps", "vllm:healthy_pods_total", "router_cpu_usage_percent",
        "router_memory_usage_percent", "router_disk_usage_percent",
    ]
    errors = []
    for p in dash["panels"]:
        for t in p.get("targets") or []:
            expr = t.get("expr") or ""
            for m in stale:
                if m in expr:
                    errors.append(f"stale metric in query, panel {p.get('title')!r}: {m}")
    return errors


def guard_instance(dash: dict) -> list:
    """Every engine/metric query in the merged view must honour $instance.

    Without this, a multi-engine future silently lies: a `sum()` across two engines is
    not a metric, and selecting one instance in the picker would still plot the other.
    Exempt: the node/host panels (pinned to the spark instance by design — the row is
    titled 'spark node') and the engine-count stat (a dashboard-level count on purpose)."""
    errors = []
    node_titles = {"spark CPU — % busy", "spark RAM — % of unified pool",
                   "spark RAM — used / available (absolute)", "spark load — 1m / 5m",
                   "spark disk used — / and /mnt/spark_nvme",
                   "spark disk I/O — read / write throughput",
                   "spark disk IOPS — completions/s",
                   "spark disk saturation — device busy %",
                   "Engines scraped", "Model served"}
    # A constant reference line carries no metric selector, so it cannot scope to
    # $instance — exempt with a reason rather than by omission.
    constant_lines = {"memory cage (105 GiB, HD-374)"}
    for p in dash["panels"]:
        if p.get("type") in ("row", "text") or p.get("title") in node_titles:
            continue
        for t in p.get("targets") or []:
            expr = t.get("expr") or ""
            if t.get("legendFormat") in constant_lines:
                continue
            if not re.search(r"vllm:|sglang:|\bup\{|probe_success|process_|python_gc", expr):
                continue
            # Both documented Grafana interpolation forms are valid: `$instance` and
            # `${instance}`. Strip the braced form first — a naive '$instance' substring
            # test reads `${instance}` as a MISS (the '}' terminates the name) and 52
            # perfectly good gnet 25502 panels would report as unscoped.
            probe = expr.replace("${instance}", "<scoped>")
            if "$instance" not in probe and "<scoped>" not in probe:
                errors.append(
                    f"panel {p.get('title')!r} query ignores $instance — it will merge "
                    f"every engine once a second one exists: {expr[:110]}")
    return errors


def guard_layout_consistency(dash: dict) -> list:
    """The script's self-documented claims must actually hold.

    A merge tool whose DROPPED list drifts from the layout is worse than no list: the
    next operator auditing "why is panel X gone" gets a confident wrong answer. Cheap
    to check, so it is a build failure rather than a comment."""
    errors = []
    carried = {k for _r, _t, items in LAYOUT for k, _w in items}
    ids = set()
    srcs = sources()
    for kind, pan in srcs.items():
        ids |= {f"{kind}:{pid}" for pid in pan}

    # 1. nothing is both carried and declared dropped
    both = sorted(carried & set(DROPPED))
    if both:
        errors.append(f"panels both carried AND listed in DROPPED: {both}")

    # 2. every DROPPED entry must name a panel that really exists in that export
    for key in sorted(DROPPED):
        if key not in ids:
            errors.append(f"DROPPED lists a panel that does not exist: {key}")

    # 3. coverage: every source panel is either carried or explained
    unaccounted = sorted(ids - carried - set(DROPPED), key=lambda k: (k.split(":")[0], int(k.split(":")[1])))
    if unaccounted:
        errors.append(f"source panels neither carried nor documented as dropped "
                      f"({len(unaccounted)}): {unaccounted[:14]}")

    # 4. ids unique across the whole merged file
    seen, dupes = set(), set()
    for p in dash["panels"]:
        pid = p.get("id")
        if pid in seen:
            dupes.add(pid)
        seen.add(pid)
    if dupes:
        errors.append(f"duplicate panel ids: {sorted(dupes)}")
    return errors


def dump(dash: dict) -> str:
    return json.dumps(dash, indent=2, ensure_ascii=False, sort_keys=True) + "\n"


def guard_empty_by_design(dash: dict) -> list:
    """A panel with NO live-vLLM target must explain its empty state in-panel.

    The HD-368 close-out was entirely about dashboards that silently rendered empty, so
    the merge refuses to ship a new one. Granularity matters here and is chosen to match
    what the operator actually sees:
      * Grafana renders a whole panel, so a panel that carries at least one target on a
        live `vllm:` series is NOT empty — its sglang sibling returning no data is normal
        and needs no apology (an earlier per-target version of this guard failed 8 healthy
        panels for exactly that reason).
      * a panel whose targets are all `sglang:` / DCGM / unscraped has to say so.

    'Live' is the set verified against VM on 2026-09-16 — see LIVE_VLLM_METRICS. A vllm:
    metric outside that set is treated as unproven, so a future upstream metric cannot
    sneak in as a silently-empty panel.
    """
    errors = []
    for p in dash["panels"]:
        if p.get("type") in ("row", "text"):
            continue
        targets = p.get("targets") or []
        if not targets:
            continue
        exprs = [t.get("expr") or "" for t in targets]
        if any(_has_live_series(e) for e in exprs):
            continue
        desc = p.get("description") or ""
        if isinstance(p.get("options"), dict):
            desc += " " + (p["options"].get("content") or "")
        if any(m in desc for m in ("⏳", "EMPTY", "until", "not yet", "No data", "by design")):
            continue
        errors.append(
            f"panel {p.get('title')!r} has no target on a live-vLLM series and does not "
            f"explain why it is empty: {exprs[0][:100]}")
    return errors


# Metric selectors confirmed present in VictoriaMetrics for the spark deployment on
# 2026-09-16 (VM /api/v1/series + /api/v1/query via the VPS loopback). Anything outside
# this allowlist is treated as UNPROVEN, so a new metric cannot sneak in as a panel that
# silently renders No data. Re-derive after an engine/Alloy change — the commands are in
# docs/observability.md §LLM Dashboard.
LIVE_VLLM_METRICS = (
    "vllm:cache_config_info", "vllm:e2e_request_latency_seconds", "vllm:generation_tokens_total",
    "vllm:inter_token_latency_seconds", "vllm:iteration_tokens_total", "vllm:kv_cache_usage_perc",
    "vllm:num_preemptions_total", "vllm:num_requests_running", "vllm:num_requests_waiting",
    "vllm:num_requests_waiting_by_reason", "vllm:prefix_cache_hits_total",
    "vllm:prefix_cache_queries_total", "vllm:prompt_tokens_cached_total", "vllm:prompt_tokens_total",
    "vllm:request_decode_time_seconds", "vllm:request_params_max_tokens",
    "vllm:request_prefill_kv_computed_tokens_sum", "vllm:request_prefill_time_seconds",
    "vllm:request_prompt_tokens", "vllm:request_queue_time_seconds",
    "vllm:request_success_total", "vllm:estimated_flops_per_gpu_total",
    "vllm:estimated_read_bytes_per_gpu_total", "vllm:estimated_write_bytes_per_gpu_total",
    "vllm:time_to_first_token_seconds", "vllm:request_time_per_output_token_seconds",
)

# Engine-process + host metrics: live for the engine (job=vllm) and for spark's Alloy
# unix exporter (job=alloy, instance=spark.kogler.si) respectively — both verified.
LIVE_PROCESS_METRICS = ("process_resident_memory_bytes", "python_gc_collections_total")
LIVE_NODE_METRICS = ("node_cpu_seconds_total", "node_load1", "node_load5",
                     "node_memory_MemTotal_bytes", "node_memory_MemAvailable_bytes",
                     "node_filesystem_avail_bytes", "node_filesystem_size_bytes",
                     # diskstats: each name confirmed present for instance="spark.kogler.si"
                     # (device=nvme0n1) in VM on 2026-09-16
                     "node_disk_read_bytes_total", "node_disk_written_bytes_total",
                     "node_disk_reads_completed_total", "node_disk_writes_completed_total",
                     "node_disk_io_time_seconds_total")


def _has_live_series(expr: str) -> bool:
    """True if the query touches at least one selector proven live in VM.

    `up` counts only when the query actually selects a scrape-target's up — with a label
    matcher, which is what pins it to a real job. A bare `up` would let any query borrow
    liveness from the word (a first version of this guard accidentally credited
    `count by (model_name) (...)` with being "live" because 'up' appears inside
    'num_requests_running'), which defeats the whole point of the allowlist."""
    if re.search(r"\bup\s*\{", expr):
        return True
    if any(m in expr for m in LIVE_PROCESS_METRICS + LIVE_NODE_METRICS):
        return True
    for name in re.findall(r"vllm:[A-Za-z0-9_:]+", expr):
        base = name.rstrip("_")
        if any(name == m or name.startswith(m + "_") or base == m for m in LIVE_VLLM_METRICS):
            return True
    return False


def main(argv=None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true",
                    help="verify the file on disk matches this script (no write)")
    ap.add_argument("--report", action="store_true", help="print the merge map and exit")
    args = ap.parse_args(argv)

    if args.report:
        print(f"merged dashboard: {DST.name} ({len(LAYOUT)} rows)")
        for row_id, title, items in LAYOUT:
            print(f"\n{title}")
            for key, w in items:
                print(f"  - {key:<16} w={w}")
        print(f"\ncarried verbatim: {sum(1 for _r, _t, i in LAYOUT for k, _ in i if not k.startswith('new:'))}")
        print(f"authored here:    {sum(1 for _r, _t, i in LAYOUT for k, _ in i if k.startswith('new:'))}")
        print("\ncut from the three source dashboards (with reason):")
        for k in sorted(DROPPED):
            print(f"  {k:<12} {DROPPED[k]}")
        return 0

    dash = build()
    errors = (guard_references(dash) + guard_no_dead_query(dash) + guard_instance(dash)
              + guard_layout_consistency(dash) + guard_empty_by_design(dash)
              + guard_english(dash) + guard_stale(dash))
    if errors:
        for e in errors:
            print(f"FAIL {e}", file=sys.stderr)
        return 1

    text = dump(dash)
    if args.check:
        if not DST.exists() or DST.read_text(encoding="utf-8") != text:
            print(f"FAIL {DST.name} is stale — re-run scripts/build-llm-dashboard.py",
                  file=sys.stderr)
            return 1
        print(f"OK {DST.name} current")
        return 0
    DST.write_text(text, encoding="utf-8")
    n = sum(1 for p in dash["panels"] if p["type"] != "row")
    print(f"wrote {DST} — {len(LAYOUT)} rows, {n} panels")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
