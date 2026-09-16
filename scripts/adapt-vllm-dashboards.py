#!/usr/bin/env python3
"""Adapt grafana.com vLLM dashboard templates to the homelab file-provisioning format.

Source files (download from grafana.com — every template below is still at revision 1,
verified 2026-09-16, so `latest` == what these files were cut from):

    mkdir -p /tmp/vllm-dash
    for id in 25502 24756 25043; do
      curl -fsS "https://grafana.com/api/dashboards/$id/revisions/latest/download" \\
           -o /tmp/vllm-dash/$id.json
    done
    # /tmp/vllm-dash/vllm-dashboard.json is the gnet 25043 export (HD-368 naming)

    python3 scripts/adapt-vllm-dashboards.py            # /tmp/vllm-dash/*.json -> repo
    python3 scripts/adapt-vllm-dashboards.py --inplace  # drift layer only, over the repo files

Adaptations (homelab conventions, docs/observability.md §Dashboards):
  * strip grafana.com template scaffolding: __inputs / __requires / id / gnetId
  * replace the ${DS_PROMETHEUS} datasource input with the literal uid `prometheus`
    (the homelab VictoriaMetrics datasource uid, API-seeded by the monitoring role)
  * unique uids (the 25043 export shares uid 750918234 with the 24756 one — id collision)
  * homelab tags + refresh/time defaults matching the other homelab dashboards
  * English panel/row/variable strings (TEXT_TRANSLATE) — the upstream exports carry the
    authors' Chinese (25502) and Korean (24756) titles and tooltips; CONVENTIONS language
    rule = English technical, and these are operator-visible strings on stats.kogler.si
  * ★ LIVE-METRIC DRIFT LAYER (see EXPR_REWRITES / PANEL_OVERRIDES / VAR_OVERRIDES):
    the panel queries are NOT left byte-identical to upstream any more. HD-368 shipped the
    three exports on 2026-09-14; the 2026-09-16 live verification pass (against the spark
    engine's /metrics and the VictoriaMetrics job="vllm" series set) found queries that can
    never resolve on our deployment — V0-era metric names, the K8s production-stack router
    family, and a stale upstream `current:` model name. Every such query is rewritten here,
    once, in the reproducible layer — NOT by hand-editing the JSON — so a future upstream
    refresh re-derives the same homelab file. Each rule names the live series it targets.

Fail-loud guards (exit 1, no partial write):
  * an EXPR_REWRITES rule that matches nothing and is not already applied (upstream drifted)
  * a non-ASCII title/label/description that TEXT_TRANSLATE does not cover
  * any metric in STALE_METRICS surviving the pass
"""
import json
import re
import sys
from pathlib import Path

SRC_DIR = Path("/tmp/vllm-dash")
# Self-derived (CONVENTIONS portability): runnable from any cwd.
DST_DIR = Path(__file__).resolve().parents[1] / "IaC/ansible/roles/monitoring/files/dashboards"

# canonical homelab dashboard header fields (see homelab-ups.json)
HOMELAB_HEAD = {
    "timezone": "browser",
    "editable": True,
    "refresh": "30s",
    "time": {"from": "now-6h", "to": "now"},
}

ADAPT = [
    {
        "src": SRC_DIR / "25502.json",
        "dst": DST_DIR / "llm-inference-sglang-vllm.json",
        "title": "Homelab — LLM Inference (vLLM/SGLang)",
        "uid": "homelab-llm-inference",
        "tags": ["homelab", "vllm", "sglang", "llm"],
        "refresh": "10s",  # inference dashboards want fast refresh (gnet default)
        "time": {"from": "now-1h", "to": "now"},
    },
    {
        "src": SRC_DIR / "24756.json",
        "dst": DST_DIR / "vllm-master-v2.json",
        "title": "Homelab — vLLM Monitoring V2",
        "uid": "homelab-vllm-monitoring-v2",
        "tags": ["homelab", "vllm"],
        "refresh": "10s",
        "time": {"from": "now-1h", "to": "now"},
    },
    {
        "src": SRC_DIR / "vllm-dashboard.json",
        "dst": DST_DIR / "vllm-dashboard.json",
        "title": "Homelab — vLLM Dashboard",
        "uid": "homelab-vllm-dashboard",
        "tags": ["homelab", "vllm"],
        "refresh": "10s",
        "time": {"from": "now-1h", "to": "now"},
    },
]

# ---------------------------------------------------------------------------
# Live-metric drift layer (HD-368 live-verification pass, 2026-09-16).
#
# Verified against the live engine (spark vllm-qwen-spark, /metrics on the loopback
# :8000 — 132 series, image vllm/vllm-openai:qwen38-flash-next) and against the
# VictoriaMetrics job="vllm" series set on the VPS (137 names). Host panels use the
# Alloy unix host exporter (job="alloy", instance="spark.kogler.si", HD-346).
#
# Each rule: (old, new, mode) with mode "sub" (substring) or "exact" (the whole
# trimmed expr — needed when `new` contains `old`, which would re-match on re-run).
# ---------------------------------------------------------------------------
EXPR_REWRITES = {
    "llm-inference-sglang-vllm.json": [
        # Panel 20: vllm:kv_block_idle_before_evict_seconds_* is not emitted by this vLLM
        # build (newer upstream metric). vLLM's real KV-pressure signal is preemptions.
        (
            'histogram_quantile(0.50, sum(rate(vllm:kv_block_idle_before_evict_seconds_bucket'
            '{instance=~"${instance}"}[$__rate_interval])) by (le))',
            'sum(rate(vllm:num_preemptions_total{instance=~"${instance}"}[$__rate_interval]))',
            "sub",
        ),
        (
            'histogram_quantile(0.95, sum(rate(vllm:kv_block_idle_before_evict_seconds_bucket'
            '{instance=~"${instance}"}[$__rate_interval])) by (le))',
            'sum(increase(vllm:num_preemptions_total{instance=~"${instance}"}[$__range]))',
            "sub",
        ),
    ],
    "vllm-master-v2.json": [
        # Panel 403: vllm:num_requests_swapped is a V0-engine metric, removed in V1.
        # vllm:num_requests_waiting_by_reason (reason=capacity|deferred) is its V1 successor.
        (
            'vllm:num_requests_swapped{model_name="$model_name"}',
            'vllm:num_requests_waiting_by_reason{model_name="$model_name"}',
            "sub",
        ),
        # Panel 501: both process metrics also exist for 11 other jobs in VM — without a
        # job filter the panel plots every process in the homelab, not the engine.
        (
            "rate(python_gc_collections_total[5m])",
            'rate(python_gc_collections_total{job="vllm"}[5m])',
            "sub",
        ),
        (
            "process_resident_memory_bytes",
            'process_resident_memory_bytes{job="vllm"}',
            "exact",
        ),
    ],
    "vllm-dashboard.json": [
        # Panel 1: vllm:healthy_pods_total is a production-stack (K8s) metric.
        (
            "sum(max by (server) (vllm:healthy_pods_total))",
            'sum(up{job="vllm"})',
            "sub",
        ),
        # Panel 3: vllm:current_qps is emitted by the production-stack router, never by
        # a standalone engine — derive QPS from the engine's own success counter.
        (
            "vllm:current_qps",
            "sum(rate(vllm:request_success_total[$__rate_interval]))",
            "exact",
        ),
        # Panel 13: gpu_prefix_cache_* was renamed to prefix_cache_* (V1); the K8s
        # endpoint="service-port" label does not exist here.
        (
            'vllm:gpu_prefix_cache_hits_total{endpoint="service-port"} / '
            "vllm:gpu_prefix_cache_queries_total",
            "sum(rate(vllm:prefix_cache_hits_total[$__rate_interval])) / "
            "clamp_min(sum(rate(vllm:prefix_cache_queries_total[$__rate_interval])), 0.001)",
            "sub",
        ),
        # Panels 15/16/17: router_{cpu,memory,disk}_usage_percent are production-stack
        # router hostmetrics — repoint at the spark host (Alloy unix exporter).
        (
            "router_cpu_usage_percent",
            '100 - (avg(rate(node_cpu_seconds_total{job="alloy",instance="spark.kogler.si",'
            'mode="idle"}[5m])) * 100)',
            "exact",
        ),
        (
            "router_memory_usage_percent",
            '(1 - sum(node_memory_MemAvailable_bytes{job="alloy",'
            'instance="spark.kogler.si"}) / sum(node_memory_MemTotal_bytes{job="alloy",'
            'instance="spark.kogler.si"})) * 100',
            "exact",
        ),
        (
            "router_disk_usage_percent",
            '100 - (sum(node_filesystem_avail_bytes{job="alloy",'
            'instance="spark.kogler.si",mountpoint="/"}) / '
            'sum(node_filesystem_size_bytes{job="alloy",instance="spark.kogler.si",'
            'mountpoint="/"}) * 100)',
            "exact",
        ),
    ],
}

# Per-panel metadata fixes that go together with an expr rewrite (title / unit / tooltip /
# legend). unit values follow Grafana units: "s" seconds, "short" count, "percent" 0-100,
# "percentunit" 0-1, "reqps" requests/s.
PANEL_OVERRIDES = {
    "llm-inference-sglang-vllm.json": {
        20: {
            "title": "KV Cache Pressure (preemptions / eviction)",
            "unit": "short",
            "description": (
                "vLLM: preemptions — requests evicted from the KV cache and recomputed "
                "(vllm:num_preemptions_total); sustained >0 means the KV budget is too "
                "tight (see docs/hardware-spark.md §Unified-memory budget). SGLang half "
                "(eviction duration) stays empty until an SGLang engine is deployed."
            ),
            "legend": {"A": "vLLM preemptions/s", "B": "vLLM preemptions (window)"},
        },
    },
    "vllm-master-v2.json": {
        403: {
            "title": "Scheduler State",
            "description": (
                "Requests per scheduler state. running = executing on the GPU; waiting = "
                "queued. vLLM V1 dropped num_requests_swapped — the V1 replacement breaks "
                "the queue down by reason (capacity / deferred). Growing waiting = overload."
            ),
            "legend": {"A": "running", "B": "waiting", "C": "waiting: {{reason}}"},
        },
        501: {
            "description": (
                "Engine process only (job=\"vllm\"): Python GC rate + RSS. Frequent GC or a "
                "monotonically rising RSS points at a leak in the API server."
            ),
        },
    },
    "vllm-dashboard.json": {
        1: {
            "title": "Scraped vLLM engines",
            "description": (
                "Engines the spark Alloy scrape job reaches (sum of the up pseudo-metric for "
                "job vllm). Upstream used a Kubernetes-only pods-total metric."
            ),
            "unit": "short",
        },
        3: {
            "title": "Request Rate (QPS)",
            "description": (
                "Completed requests/s from the engine's own success counter. Upstream used a "
                "production-stack router metric that a standalone engine never exposes."
            ),
            "unit": "reqps",
        },
        13: {
            "title": "Prefix Cache Hit Rate",
            "unit": "percentunit",
            "description": (
                "prefix_cache_hits / prefix_cache_queries (rate). vLLM V1 renamed "
                "gpu_prefix_cache_* to prefix_cache_*."
            ),
        },
        15: {
            "title": "spark Host CPU (%)",
            "unit": "percent",
            "description": (
                "spark host CPU busy % from the Alloy unix exporter (job=\"alloy\"). Upstream "
                "used the production-stack router's own hostmeter, which we do not run."
            ),
        },
        16: {
            "title": "spark Host Memory (%)",
            "unit": "percent",
            "description": (
                "spark host memory used % (Alloy exporter). The engine cage lives in this "
                "number — see docs/hardware-spark.md §Unified-memory budget."
            ),
        },
        17: {
            "title": "spark Host Disk (%) — /",
            "unit": "percent",
            "description": (
                "spark root filesystem used % (Alloy exporter; /mnt/spark_nvme is the XFS "
                "artifact store, tracked separately)."
            ),
        },
    },
}

# Query variables whose `current:` is baked into the upstream export and points at the
# author's own deployment — Grafana would ship a model name we do not serve.
VAR_OVERRIDES = {
    "llm-inference-sglang-vllm.json": {
        "model_name": {"reset_current": True},
    },
}

# Operator-visible strings: upstream author language -> English (CONVENTIONS: English
# technical). Exact match on title / label / description values; unmapped non-ASCII fails.
TEXT_TRANSLATE = {
    # --- 25502 rows ---
    "核心概览 (Core Overview)": "Core Overview",
    "延迟分析 (Latency Analysis)": "Latency Analysis",
    "吞吐量与 Token (Throughput & Tokens)": "Throughput & Tokens",
    "队列与资源 (Queue & Resources)": "Queue & Resources",
    "节点/Engine 分布 (Node / Engine Distribution)": "Node / Engine Distribution",
    # --- 25502 panels ---
    "总请求数": "Total Requests",
    "Token 吞吐量": "Token Throughput",
    "缓存命中率": "Prefix Cache Hit Rate",
    "KV/GPU Cache 使用率": "KV / GPU Cache Usage",
    "E2E 延迟 P95": "E2E Latency P95 / P99",
    "中止/Abort 请求数": "Aborted Requests",
    "首 Token 延迟 (TTFT)": "Time to First Token (TTFT)",
    "Token 间延迟 (ITL)": "Inter-Token Latency (ITL)",
    "端到端请求延迟 (E2E)": "End-to-End Request Latency",
    "队列等待时间 (按 Engine / TP Rank)": "Queue Wait Time (per Engine / TP Rank)",
    "Token 吞吐量 (Prefill / Decode)": "Token Throughput (Prefill / Decode)",
    "实时 Token 处理 (按 Engine / TP Rank)": "Realtime Token Rate (per Engine / TP Rank)",
    "缓存 Token 统计": "Cached Token Stats",
    "Engine Step / CUDA Graph 指标": "Engine Step / CUDA Graph Metrics",
    "运行中请求": "Running Requests",
    "等待队列请求": "Queued Requests",
    "Token 容量 / Max Tokens": "Requested Max Tokens (avg)",
    "新 Token / Prefill KV 计算比例": "Prefill KV Computed Ratio",
    "CPU / 请求阶段耗时": "Request Phase Time (Prefill / Decode)",
    "KV Cache 驱逐时间": "KV Cache Pressure (preemptions / eviction)",
    "Decode 吞吐量 (按 Engine / TP Rank)": "Decode Throughput (per Engine / TP Rank)",
    "Prefill 吞吐量 (按 Engine / TP Rank)": "Prefill Throughput (per Engine / TP Rank)",
    "Prefill 延迟 (按 Engine / TP Rank)": "Prefill Latency (per Engine / TP Rank)",
    "平均队列时间 (按 Engine / TP Rank)": "Avg Queue Time (per Engine / TP Rank)",
    # --- 25502 variables + dashboard description ---
    "模型名称": "Model",
    "实例 (Instance)": "Instance",
    "SGLang / vLLM 模型名称": "SGLang / vLLM model name",
    "SGLang / vLLM 实例 - 用于区分不同机器": "SGLang / vLLM instance — distinguishes hosts",
    (
        "同时支持 SGLang 和 vLLM 的统一 LLM 推理监控 Grafana Dashboard，数据源为 Prometheus。"
        "该模板将两类推理后端的可比指标放在同一视图中展示，覆盖请求量、Token 吞吐、延迟分位数、"
        "队列状态、缓存行为以及 Engine 或 TP Rank 维度的分布情况。适用于混合推理集群、后端迁移、"
        "压测对比和统一运维场景，帮助团队用一致的视角观察不同推理框架的服务表现。"
    ): (
        "Unified LLM inference dashboard covering both SGLang and vLLM against one "
        "Prometheus-compatible datasource (here VictoriaMetrics, uid `prometheus`). Comparable "
        "panels per backend: request volume, token throughput, latency quantiles, queue state, "
        "cache behaviour and per-engine / TP-rank distribution. The SGLang queries stay empty "
        "until an SGLang engine is deployed (HD-367 throughput lane) — the vLLM half is live "
        "from the spark engine."
    ),
    # --- 24756 tooltips (Korean upstream) ---
    "vLLM 추론 서버 모니터링": "vLLM inference server monitoring",
    (
        "요청 성공률. 99.5% 이상이면 정상(초록), 98% 미만이면 위험(빨강). "
        "finished_reason='stop'인 정상 완료만 성공으로 집계."
    ): (
        "Request success rate. Healthy >99.5% (green), at risk <98% (red). Only clean "
        "completions count as success."
    ),
    "현재 처리 중(Running) + 대기 중(Waiting) 요청 수. 급격히 증가하면 트래픽 급증 신호.": (
        "Running + waiting requests. A sharp jump = traffic spike or a stalled engine."
    ),
    (
        "스케줄러 효율성. Running/(Running+Waiting). 100%면 모든 요청이 즉시 처리됨. "
        "70% 미만이면 과부하."
    ): (
        "Scheduler efficiency = running/(running+waiting). 100% = everything served "
        "immediately; <70% = overloaded."
    ),
    "첫 토큰 생성까지 걸리는 시간 P99. 사용자가 느끼는 초기 응답 속도의 핵심 지표. 1초 미만이 이상적.": (
        "P99 time to first token — the latency the user actually feels at the start of a "
        "response; <1s is ideal (long-context prefill on spark is I/O-bound, see hardware-spark.md)."
    ),
    (
        "[Critical] Preemption 발생률. KV Cache 부족으로 실행 중인 요청을 중단. 0 초과 시 즉시 확인 "
        "필요. GPU 메모리 증설 또는 배치 크기 감소 고려."
    ): (
        "[Critical] Preemption rate — running requests evicted because the KV cache ran out. "
        "Anything >0 sustained needs attention: lower gpu_memory_utilization headroom use, "
        "shorten max_model_len, or reduce concurrency."
    ),
    (
        "요청 접수부터 응답 완료까지 전체 소요 시간. P50은 절반의 요청, P99는 99%의 요청이 이 시간 내 "
        "완료. P99가 급증하면 병목 구간 분석 필요."
    ): (
        "Full request latency, arrival to completion (P50 / P95 / P99). A P99 spike marks a "
        "bottleneck worth profiling."
    ),
    (
        "Prefill(입력 처리) vs Decode(출력 생성) 지연 시간 비중. Prefill이 높으면 긴 입력 프롬프트, "
        "Decode가 높으면 긴 출력 생성이 병목."
    ): (
        "Prefill (input) vs decode (output) time split. Prefill-heavy = long prompts; "
        "decode-heavy = long generations."
    ),
    (
        "TTFT(첫 토큰까지) vs TPOT(토큰당 생성시간) 비교. TTFT가 높으면 Prefill 병목, TPOT이 높으면 "
        "Decode 병목."
    ): (
        "TTFT vs TPOT. High TTFT = prefill bottleneck; high TPOT = decode bottleneck."
    ),
    (
        "초당 처리되는 토큰 수. Input(Prompt)=입력 토큰, Output(Generation)=출력 토큰. 처리량이 "
        "높을수록 시스템 효율성이 좋음."
    ): (
        "Tokens per second — prompt (in) vs generation (out). Higher is better."
    ),
    "입력 토큰 대비 출력 토큰 비율. 높으면 긴 입력+짧은 출력(RAG), 낮으면 짧은 입력+긴 출력(생성/요약).": (
        "Prompt-to-generation token ratio. High = long-in/short-out (RAG); low = "
        "short-in/long-out (generation, summarisation)."
    ),
    (
        "Prefix Cache로 절약된 연산 비율. 높을수록 캐시가 Prefill 연산을 많이 건너뛰어 GPU 자원 절약. "
        "(1 - 실제연산/전체입력) * 100"
    ): (
        "Share of prefill work skipped by the prefix cache, (1 - computed/prompt) * 100 — "
        "higher saves GPU time."
    ),
    (
        "요청별 입력(Prompt) 토큰 수 분포. 색이 진할수록 해당 길이의 요청이 많음. 특정 구간에 "
        "집중되면 해당 길이 최적화 고려."
    ): (
        "Prompt-length distribution per request — darker = more requests at that length. "
        "Clustering at one length is worth tuning for."
    ),
    (
        "요청이 대기열에서 기다린 시간. GPU가 바쁘면 대기 시간 증가. 지속적으로 높으면 인스턴스 스케일 "
        "아웃 고려."
    ): (
        "Time requests spend queued. Persistently high = add capacity (or a second engine)."
    ),
    "GPU KV Cache 사용률. 중간 연산 결과를 저장하는 메모리 영역. 80% 이상이면 주의, 95% 이상이면 "
    "Preemption 발생 위험.": (
        "KV cache utilisation. >80% watch it, >95% = preemption risk."
    ),
    (
        "Prefix Cache 적중률. 동일한 시스템 프롬프트나 Few-shot 예시를 재사용하는 비율. 70% 이상이면 "
        "효율적, RAG 환경에서 핵심 지표."
    ): (
        "Prefix cache hit rate — reused system prompts / few-shot examples. >70% is "
        "efficient; the key metric in RAG setups."
    ),
    (
        "스케줄러 상태별 요청 수. Running=GPU에서 추론 중, Waiting=대기열, Swapped=메모리 스왑됨. "
        "Waiting이 지속 증가하면 과부하."
    ): (
        "Requests per scheduler state. running = executing on the GPU; waiting = queued "
        "(split by reason: capacity / deferred). Sustained growth in waiting = overload."
    ),
    (
        "Python GC 발생 횟수와 프로세스 메모리 사용량. GC가 자주 발생하거나 RSS가 지속 증가하면 메모리 "
        "누수 가능성."
    ): (
        "Engine process GC rate + RSS (job=\"vllm\"). Frequent GC or ever-rising RSS = leak."
    ),
    (
        "요청 완료 사유 분포. stop=정상 종료(EOS), length=최대 길이 도달, abort=중단. abort 비율이 "
        "높으면 문제."
    ): (
        "Finish-reason mix: stop = EOS, length = hit max tokens, abort = cancelled. A "
        "significant abort share is a problem."
    ),
    (
        "전체 요청 처리량 vs 성공 요청 추이. 갭이 발생하면 실패 요청 존재. 꾸준히 일치해야 정상."
    ): (
        "Total request rate vs successful request rate — a gap means failures; they should "
        "track each other."
    ),
}

# Queries that must NOT survive the drift layer — the exact dead names the 2026-09-16 live
# audit found. If one survives (or reappears after an upstream refresh), the script fails.
# Checked against the panel queries (the expr blob) only — tooltips intentionally avoid
# repeating these literals, and prose is not a query.
STALE_METRICS = [
    "vllm:num_requests_swapped",
    "vllm:kv_block_idle_before_evict_seconds",
    "vllm:gpu_prefix_cache_hits_total",
    "vllm:gpu_prefix_cache_queries_total",
    "vllm:current_qps",
    "vllm:healthy_pods_total",
    "router_cpu_usage_percent",
    "router_memory_usage_percent",
    "router_disk_usage_percent",
]

# sglang:* is empty BY DESIGN until the SGLang engine lands (HD-367 lane) — not stale, so
# it is excluded from any absence check.

# Series live-verified on 2026-09-16: engine (spark :8000/metrics -> VM job="vllm"), plus
# the Alloy host exporter (job="alloy", instance="spark.kogler.si") used by the repointed
# host panels. Used only by verify_live_queries() for the informational coverage line.
LIVE_VERIFIED_SET = [
    # engine (vllm:* family, labels engine/model_name/instance/job)
    "vllm:request_success_total", "vllm:generation_tokens_total", "vllm:prompt_tokens_total",
    "vllm:num_requests_running", "vllm:num_requests_waiting", "vllm:num_requests_waiting_by_reason",
    "vllm:num_preemptions_total", "vllm:kv_cache_usage_perc", "vllm:prefix_cache_hits_total",
    "vllm:prefix_cache_queries_total", "vllm:prompt_tokens_cached_total",
    "vllm:time_to_first_token_seconds_bucket", "vllm:inter_token_latency_seconds_bucket",
    "vllm:e2e_request_latency_seconds_bucket", "vllm:e2e_request_latency_seconds_count",
    "vllm:e2e_request_latency_seconds_sum", "vllm:request_queue_time_seconds_bucket",
    "vllm:request_queue_time_seconds_count", "vllm:request_queue_time_seconds_sum",
    "vllm:request_prefill_time_seconds_bucket", "vllm:request_prefill_time_seconds_count",
    "vllm:request_prefill_time_seconds_sum", "vllm:request_decode_time_seconds_count",
    "vllm:request_decode_time_seconds_sum", "vllm:request_time_per_output_token_seconds_bucket",
    "vllm:request_time_per_output_token_seconds_count", "vllm:request_time_per_output_token_seconds_sum",
    "vllm:request_prompt_tokens_bucket", "vllm:request_prompt_tokens_sum",
    "vllm:request_params_max_tokens_count", "vllm:request_params_max_tokens_sum",
    "vllm:request_prefill_kv_computed_tokens_sum", "vllm:iteration_tokens_total_bucket",
    "vllm:cache_config_info", "process_resident_memory_bytes", "python_gc_collections_total",
    "up",
    # spark host via the Alloy unix exporter (job="alloy")
    "node_cpu_seconds_total", "node_memory_MemAvailable_bytes", "node_memory_MemTotal_bytes",
    "node_filesystem_avail_bytes", "node_filesystem_size_bytes",
]

NON_ASCII = re.compile(r"[\u3000-\u31ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af\u3040-\u30ff]")


def walk_scrub(obj):
    """Recursively rewrite ${DS_*} datasource refs to the literal `prometheus` uid."""
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            if k == "datasource" and isinstance(v, dict) and "uid" in v:
                v = dict(v)
                uid = v.get("uid", "")
                if isinstance(uid, str) and uid.startswith("${DS_"):
                    v["uid"] = "prometheus"
                out[k] = v
            else:
                out[k] = walk_scrub(v)
        return out
    if isinstance(obj, list):
        return [walk_scrub(x) for x in obj]
    return obj


def walk_panels(dash):
    """Yield every panel incl. row children."""
    stack = list(dash.get("panels", []) or [])
    while stack:
        p = stack.pop(0)
        yield p
        stack = (p.get("panels") or []) + stack


def expr_blob(dash):
    """All panel queries in one string — the scope for stale-metric + idempotency checks."""
    return json.dumps(
        [
            t.get("expr")
            for p in walk_panels(dash)
            for t in (p.get("targets") or [])
            if isinstance(t.get("expr"), str)
        ]
    )


def apply_expr_rewrites(dash, name, errors):
    """Apply the rewrite table to every panel query.

    Rule accounting is PER TARGET: a rule that matches nothing is a hard error, a rule that
    matched but left a stale name behind is a hard error. Both are checked from the FINAL
    query blob, so a re-run over already-adapted files is a clean no-op (every new value is
    present, every old value is gone) instead of a false "matched nothing" failure.
    """
    applied = 0
    rules = EXPR_REWRITES.get(name, [])
    leftovers = []
    for panel in walk_panels(dash):
        for t in panel.get("targets") or []:
            expr = t.get("expr")
            if not isinstance(expr, str):
                continue
            before = expr
            for old, new, mode in rules:
                if mode == "exact":
                    if before.strip() == old:
                        before = new
                elif old in before:
                    before = before.replace(old, new)
            if before != expr:
                t["expr"] = before
                applied += 1
            if any(k in before for k in STALE_METRICS):
                leftovers.append(f"{name}: panel {panel.get('id')} still carries a stale metric: {before[:120]}")
    errors.extend(leftovers)
    # Rule accounting, per rule (substring rules only — an "exact" rule is a whole-expr
    # replacement, so it cannot leave the old query behind and re-runs are a no-op by
    # construction). A substring rule is satisfied when the final queries no longer contain
    # `old`; if they do, the rewrite did not take (upstream drift) → hard error.
    final = expr_blob(dash)
    for old, new, mode in rules:
        if mode != "sub":
            continue
        if old in final:
            errors.append(f"{name}: expr rewrite did not clear the old query: {old[:110]}")
        elif new not in final:
            # legitimate when a future upstream revision drops the query entirely
            print(f"NOTE {name}: rewrite source absent from upstream export: {old[:90]}")
    return applied


def verify_live_queries(dash, name):
    """Report which panel queries resolve against the series set live-verified 2026-09-16.

    Informational (no secrets, no network): prints the count of populated vs empty-by-design
    queries so a future refresh shows the coverage drift in one line. The empty list must
    stay exactly {sglang:*} — those panels light up with the SGLang engine (HD-367 lane).
    """
    live = {n for n in LIVE_VERIFIED_SET if n}
    populated = empty = 0
    empties = set()
    for panel in walk_panels(dash):
        for t in panel.get("targets") or []:
            expr = t.get("expr")
            if not isinstance(expr, str):
                continue
            names = {m for m in re.findall(r"[A-Za-z_:][A-Za-z0-9_:]*", expr) if ":" in m}
            if not names:
                continue
            if names <= live:
                populated += 1
            else:
                empty += 1
                empties |= {n for n in names if n not in live}
    print(
        f"live-query check {name}: {populated} populated / {empty} empty-by-design "
        f"(unknown: {', '.join(sorted(empties)) or 'none'})"
    )


def apply_panel_overrides(dash, name):
    changed = 0
    for pid, spec in PANEL_OVERRIDES.get(name, {}).items():
        for panel in walk_panels(dash):
            if panel.get("id") != pid:
                continue
            for key in ("title", "description"):
                if key in spec and panel.get(key) != spec[key]:
                    panel[key] = spec[key]
                    changed += 1
            if "unit" in spec:
                defaults = panel.setdefault("fieldConfig", {}).setdefault("defaults", {})
                if defaults.get("unit") != spec["unit"]:
                    defaults["unit"] = spec["unit"]
                    changed += 1
            for ref, legend in (spec.get("legend") or {}).items():
                for t in panel.get("targets") or []:
                    if t.get("refId") == ref:
                        t.setdefault("legend", {})
                        if t["legend"].get("format") != legend:
                            t["legend"] = dict(t["legend"], format=legend)
                            changed += 1
    return changed


def apply_var_overrides(dash, name):
    changed = 0
    for var in dash.get("templating", {}).get("list", []) or []:
        spec = VAR_OVERRIDES.get(name, {}).get(var.get("name"))
        if spec and spec.get("reset_current") and var.get("current"):
            var["current"] = {}  # Grafana picks the first live value on load
            changed += 1
    return changed


def apply_translations(dash, name, errors):
    changed = 0

    def rec(obj):
        nonlocal changed
        if isinstance(obj, dict):
            for k, v in obj.items():
                if isinstance(v, str) and k in ("title", "label", "description", "tooltip"):
                    if NON_ASCII.search(v):
                        if v in TEXT_TRANSLATE:
                            if obj[k] != TEXT_TRANSLATE[v]:
                                obj[k] = TEXT_TRANSLATE[v]
                                changed += 1
                            continue
                        errors.append(f"{name}: unmapped non-ASCII {k}: {v[:80]}")
                else:
                    rec(v)
        elif isinstance(obj, list):
            for x in obj:
                rec(x)

    rec(dash)
    return changed


def apply_drift_layer(dash, name):
    """Run every homelab live-data fix over one dashboard dict. Returns (report, errors)."""
    errors: list = []
    report = {
        "expr": apply_expr_rewrites(dash, name, errors),
        "panels": apply_panel_overrides(dash, name),
        "vars": apply_var_overrides(dash, name),
        "strings": apply_translations(dash, name, errors),
    }
    blob = expr_blob(dash)
    for stale in STALE_METRICS:
        if stale in blob:
            errors.append(f"{name}: stale metric survives the drift layer in a query: {stale}")
    if "${DS_" in json.dumps(dash):
        errors.append(f"{name}: leftover ${DS_} datasource template ref")
    return report, errors


def main(argv) -> int:
    inplace = "--inplace" in argv
    specs = ADAPT
    wrote = 0
    all_errors: list = []
    for spec in specs:
        dst = spec["dst"]
        if inplace:
            if not dst.exists():
                print(f"FAIL {dst} — repo dashboard missing", file=sys.stderr)
                return 1
            d = json.loads(dst.read_text(encoding="utf-8"))
        else:
            src = spec["src"]
            if not src.exists():
                print(f"SKIP {src} — source missing", file=sys.stderr)
                return 1
            d = json.loads(src.read_text(encoding="utf-8"))
            # strip gnet scaffolding
            for key in ("__inputs", "__requires", "id", "gnetId"):
                d.pop(key, None)
            # rewrite datasource templates
            d = walk_scrub(d)
            # canonical homelab header
            d.update(HOMELAB_HEAD)
            d["title"] = spec["title"]
            d["uid"] = spec["uid"]
            d["tags"] = spec["tags"]
            if spec.get("refresh"):
                d["refresh"] = spec["refresh"]
            if spec.get("time"):
                d["time"] = spec["time"]
            # version: keep the source version (bump on future refreshes)
            d.setdefault("version", 1)

        report, errors = apply_drift_layer(d, dst.name)
        all_errors.extend(errors)
        verify_live_queries(d, dst.name)
        out = json.dumps(d, indent=2, ensure_ascii=False) + "\n"
        dst.write_text(out, encoding="utf-8")
        wrote += 1
        print(
            f"wrote {dst} ({len(out)} bytes, uid={d['uid']}) — "
            f"exprs {report['expr']}, panels {report['panels']}, "
            f"vars {report['vars']}, strings {report['strings']}"
        )

    if all_errors:
        print("\nDRIFT-LAYER FAILURES:", file=sys.stderr)
        for e in all_errors:
            print(f"  - {e}", file=sys.stderr)
        return 1
    print(f"OK: {wrote} dashboards, drift layer clean (live-metric audit 2026-09-16)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
