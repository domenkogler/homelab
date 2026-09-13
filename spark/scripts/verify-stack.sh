#!/bin/bash
# verify-stack.sh - Comprehensive health verification for Spark DGX AI Stack
# Run via cron or systemd timer for ongoing monitoring

set -euo pipefail

VLLM_URL="${VLLM_URL:-http://localhost:8000}"
ROUTER_URL="${ROUTER_URL:-http://localhost:8080}"
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"  # Slack/Discord/PagerDuty webhook
METRICS_PUSHGATEWAY="${METRICS_PUSHGATEWAY:-}"  # Prometheus Pushgateway URL

# Thresholds
MAX_TTFT_P50_MS=200
MAX_TTFT_P99_MS=800
MIN_DECODE_TOK_S=50
MAX_GPU_MEM_PCT=95
MAX_DISK_PCT=90

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
alert() {
    local msg="$1"
    log "ALERT: $msg"
    if [[ -n "$ALERT_WEBHOOK" ]]; then
        curl -sf -X POST -H "Content-Type: application/json" \
            -d "{\"text\":\"🚨 Spark AI Alert: $msg\"}" "$ALERT_WEBHOOK" >/dev/null 2>&1 || true
    fi
}

push_metric() {
    local name="$1"
    local value="$2"
    local labels="${3:-}"
    if [[ -n "$METRICS_PUSHGATEWAY" ]]; then
        cat <<EOF | curl -sf --data-binary @- "$METRICS_PUSHGATEWAY/metrics/job/spark-ai/instance/$(hostname)" >/dev/null 2>&1 || true
# TYPE $name gauge
$name{$labels} $value
EOF
    fi
}

check_vllm_health() {
    log "Checking vLLM health..."
    local resp
    resp=$(curl -sf --max-time 10 "$VLLM_URL/health" 2>/dev/null) || { alert "vLLM health endpoint unreachable"; return 1; }
    log "vLLM health: OK"
    push_metric "spark_ai_vllm_healthy" 1
    return 0
}

check_router_health() {
    log "Checking router health..."
    local resp
    resp=$(curl -sf --max-time 10 "$ROUTER_URL/ready" 2>/dev/null) || { alert "Router ready endpoint unreachable"; return 1; }
    log "Router health: OK"
    push_metric "spark_ai_router_healthy" 1
    return 0
}

check_model_accessible() {
    log "Checking model accessibility via router..."
    local resp
    resp=$(curl -sf --max-time 10 "$ROUTER_URL/v1/models" 2>/dev/null) || { alert "Router /v1/models unreachable"; return 1; }
    if ! echo "$resp" | grep -q "qwen3-8-flash-next"; then
        alert "Model qwen3-8-flash-next not found in router"
        return 1
    fi
    log "Model accessible: OK"
    push_metric "spark_ai_model_accessible" 1
    return 0
}

check_gpu_memory() {
    log "Checking GPU memory..."
    local mem_used_pct
    mem_used_pct=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits | awk -F, '{printf "%.0f", $1/$2*100}')
    log "GPU memory used: ${mem_used_pct}%"
    push_metric "spark_ai_gpu_memory_used_pct" "$mem_used_pct"
    if [[ $mem_used_pct -gt $MAX_GPU_MEM_PCT ]]; then
        alert "GPU memory usage critical: ${mem_used_pct}% (threshold: ${MAX_GPU_MEM_PCT}%)"
        return 1
    fi
    return 0
}

check_disk_space() {
    log "Checking disk space..."
    local xfs_pct models_pct project_pct
    xfs_pct=$(df /mnt/spark_nvme | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
    models_pct=$(df /home/ubuntu/models | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
    project_pct=$(df /home/ubuntu/qwen-spark-stack | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
    log "Disk usage - XFS: ${xfs_pct}%, Models: ${models_pct}%, Project: ${project_pct}%"
    push_metric "spark_ai_disk_xfs_used_pct" "$xfs_pct"
    push_metric "spark_ai_disk_models_used_pct" "$models_pct"
    push_metric "spark_ai_disk_project_used_pct" "$project_pct"
    for pct in "$xfs_pct" "$models_pct" "$project_pct"; do
        if [[ $pct -gt $MAX_DISK_PCT ]]; then
            alert "Disk usage critical: ${pct}% (threshold: ${MAX_DISK_PCT}%)"
            return 1
        fi
    done
    return 0
}

check_docker_containers() {
    log "Checking Docker containers..."
    local vllm_status router_status
    vllm_status=$(docker inspect -f '{{.State.Status}}' vllm-qwen-spark 2>/dev/null || echo "missing")
    router_status=$(docker inspect -f '{{.State.Status}}' llm-d-router 2>/dev/null || echo "missing")
    log "Container status - vLLM: $vllm_status, Router: $router_status"
    push_metric "spark_ai_vllm_container_running" "$( [[ $vllm_status == running ]] && echo 1 || echo 0 )"
    push_metric "spark_ai_router_container_running" "$( [[ $router_status == running ]] && echo 1 || echo 0 )"
    if [[ $vllm_status != "running" || $router_status != "running" ]]; then
        alert "Container not running - vLLM: $vllm_status, Router: $router_status"
        return 1
    fi
    return 0
}

run_inference_test() {
    log "Running inference test..."
    local start end ttft_ms
    start=$(date +%s%3N)
    local resp
    resp=$(curl -sf --max-time 30 -X POST "$ROUTER_URL/v1/completions" \
        -H "Content-Type: application/json" \
        -d '{"model": "qwen3-8-flash-next", "prompt": "Test", "max_tokens": 10}' 2>/dev/null) || { alert "Inference request failed"; return 1; }
    end=$(date +%s%3N)
    ttft_ms=$((end - start))
    log "Inference test: TTFT = ${ttft_ms}ms"
    push_metric "spark_ai_ttft_ms" "$ttft_ms"
    if [[ $ttft_ms -gt $MAX_TTFT_P99_MS ]]; then
        alert "High TTFT: ${ttft_ms}ms (threshold: ${MAX_TTFT_P99_MS}ms)"
        return 1
    fi
    return 0
}

check_ple_offload() {
    log "Checking PLE offload status..."
    local metrics
    metrics=$(curl -sf --max-time 10 "$VLLM_URL/metrics" 2>/dev/null | grep -E "ple_(offload_ready|cpu_offload_bytes|gpu_offload_bytes)" || true)
    if echo "$metrics" | grep -q "ple_offload_ready 1"; then
        log "PLE offload: READY"
        push_metric "spark_ai_ple_offload_ready" 1
    else
        warn "PLE offload not ready yet"
        push_metric "spark_ai_ple_offload_ready" 0
    fi
    # Extract offload bytes if available
    local cpu_bytes gpu_bytes
    cpu_bytes=$(echo "$metrics" | grep "ple_cpu_offload_bytes" | awk '{print $2}' || echo 0)
    gpu_bytes=$(echo "$metrics" | grep "ple_gpu_offload_bytes" | awk '{print $2}' || echo 0)
    log "PLE offload - CPU: ${cpu_bytes} bytes, GPU: ${gpu_bytes} bytes"
    push_metric "spark_ai_ple_cpu_offload_bytes" "$cpu_bytes"
    push_metric "spark_ai_ple_gpu_offload_bytes" "$gpu_bytes"
    return 0
}

check_systemd_service() {
    log "Checking systemd service..."
    local status
    status=$(systemctl is-active spark-ai 2>/dev/null || echo "inactive")
    log "Systemd service: $status"
    push_metric "spark_ai_systemd_active" "$( [[ $status == active ]] && echo 1 || echo 0 )"
    if [[ $status != "active" ]]; then
        alert "Systemd service not active: $status"
        return 1
    fi
    return 0
}

main() {
    log "=== Spark DGX AI Stack Health Check ==="
    local failed=0
    
    check_vllm_health || failed=1
    check_router_health || failed=1
    check_model_accessible || failed=1
    check_gpu_memory || failed=1
    check_disk_space || failed=1
    check_docker_containers || failed=1
    check_systemd_service || failed=1
    check_ple_offload || true  # Non-critical
    run_inference_test || failed=1
    
    if [[ $failed -eq 0 ]]; then
        log "=== ALL CHECKS PASSED ==="
        push_metric "spark_ai_overall_healthy" 1
        exit 0
    else
        log "=== SOME CHECKS FAILED ==="
        push_metric "spark_ai_overall_healthy" 0
        exit 1
    fi
}

main "$@"