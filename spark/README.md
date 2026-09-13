# Spark DGX AI Stack

> **Production-ready Ansible deployment** for NVIDIA DGX Spark running Qwen3.8-Flash-Next-AWQ (98/100 accuracy) with vLLM PLE offload and llm-d Router.

## 🎯 What This Deploys

| Component | Version | Purpose |
|-----------|---------|---------|
| **vLLM Engine** | `qwen38-flash-next` (pinned digest) | OpenAI-compatible LLM server with PLE CPU offload |
| **llm-d Router** | `latest` | Request routing, queue management, flow control |
| **Model** | Qwen3.8-Flash-Next-AWQ-W4A16 | 98/100 reasoning accuracy, 135K context |
| **PLE Quantization** | Primitive-AI INT4 tables | 95 GB → 32 GB n-gram tables on XFS |
| **Storage** | XFS on NVMe | Zero-copy mmap for KV cache + quant tables |

## 🏗️ Architecture

```
Client → llm-d Router (:8080) → vLLM Engine (:8000) → GPU + XFS Offload
                              ↘ Prometheus Metrics
```

## 🚀 Quick Start

### Prerequisites
- Ansible control machine (Linux/macOS/WSL2)
- SSH access to DGX Spark (`ubuntu@<IP>` with key auth)
- Python 3.10+ on control machine

### 1. Configure Inventory
```bash
cd ansible
cp inventory.yml.example inventory.yml  # Edit with your Spark IP
nano inventory.yml
```

### 2. (Optional) Encrypt Secrets
```bash
ansible-vault encrypt group_vars/spark_nodes.yml
```

### 3. Deploy Everything
```bash
ansible-playbook -i inventory.yml site.yml
```

### 4. Verify
```bash
curl http://<SPARK_IP>:8000/health   # vLLM
curl http://<SPARK_IP>:8080/ready    # Router
```

## 📁 Repository Structure

```
spark-ai-stack/
├── ansible/
│   ├── inventory.yml              # Target hosts (edit this!)
│   ├── site.yml                   # Main playbook
│   ├── group_vars/
│   │   └── spark_nodes.yml        # ALL configuration lives here
│   └── roles/
│       ├── spark-base/            # System: disk, kernel, docker, systemd
│       ├── spark-ai/              # vLLM: model, overlays, compose, deploy
│       └── llm-router/            # llm-d: deploy, verify
├── spark-compose.proven.yaml      # ⭐ PROVEN BASELINE (B1) — benchmark reference
├── spark-compose.yaml             # Previous config (B0) — kept for A/B comparison
├── BENCHMARK-PLAN.md              # Tuning ladder: change table, gates, results log
├── bench/
│   ├── run-scenario.sh            # One command = metrics + power + CSV row
│   ├── snapshot-metrics.sh        # Prometheus counter snapshot (before/after)
│   └── accuracy-gate.sh           # Fixed 10-prompt sanity set
├── resources/                     # Source recipes (r/LocalLLaMA, primitive-ai card)
├── spark.md                       # Full documentation
└── README.md                      # This file
```

## 🧭 Config provenance: B0 vs B1

| | File | KV cache | Swap | Tool calls | Status |
|---|---|---|---|---|---|
| **B1 (proven)** | `spark-compose.proven.yaml` | bf16 (`auto`) | 4 GB | ✅ enabled | **reference — benchmark everything against this** |
| **B0 (legacy)** | `spark-compose.yaml` | fp8 | 32 GB | ❌ parser set but not enabled | kept only for comparison |

B1 is the verbatim proven recipe (u/WonderRico 98/100 + u/UltrMgns 170K + primitive-ai overlay card, all in `resources/`). B0's deviations (fp8 KV, 32 GB swap on **unified** memory, missing `--enable-auto-tool-choice`) are under review via the benchmark ladder — do not deploy B0 for production.

> ⚠️ On DGX Spark, CPU RAM and VRAM are the same 128 GB pool. `--swap-space`
> budgets consume that pool directly — B0's 32 GB swap effectively stole
> ~28 GB from the KV cache. Any future tuning must respect the unified budget:
> `gpu_memory_utilization` budget + swap + PLE table page cache ≤ 128 GB.

## ⚙️ Configuration

**All tunables are in `ansible/group_vars/spark_nodes.yml`** — never edit templates directly.

Key variables (proven baseline values):
```yaml
vllm:
  image: "vllm/vllm-openai:qwen38-flash-next@sha256:DIGEST"  # Pin this!
  max_num_seqs: 4
  max_model_len: 173400
  max_num_batched_tokens: 16384
  enable_prefix_caching: true
  gpu_memory_utilization: 0.95
  kv_cache_dtype: "auto"      # bf16 — proven; fp8 is ladder step #7 (gated)
  memory_limit: "126G"
  swap_space: 4               # NOT 32 — unified memory! See B0/B1 note above
  speculative_method: "mtp"   # 3 tokens (plain; no disable threshold in baseline)
  enable_auto_tool_choice: true  # required with tool-call-parser

llm_router:
  max_concurrent_sessions: 3

xfs:
  device: "/dev/nvme0n1p2"
  mount_point: "/mnt/spark_nvme"
```

## 🔒 Security Features

- ✅ No privileged containers (`cap_add` minimal: `SYS_PTRACE`, `IPC_LOCK`, `SYS_RESOURCE`)
- ✅ `read_only: true` rootfs + explicit `tmpfs` mounts
- ✅ `no-new-privileges:true` security opt
- ✅ Dedicated Docker bridge network (`spark-net`)
- ✅ Systemd hardening (`ProtectSystem=strict`, `PrivateTmp`, limited `ReadWritePaths`)
- ✅ Log rotation (JSON driver, 50 MB max, 5 files)

## 📊 Observability

| Endpoint | Purpose |
|----------|---------|
| `GET /health` | vLLM liveness (Docker healthcheck) |
| `GET /metrics` | Prometheus metrics (vLLM + Router) |
| `GET /ready` | Router readiness |
| `GET /v1/models` | Model catalog via Router |

Prometheus scrape configs and Grafana dashboard IDs in [`spark.md`](spark.md#-observability).

## 🧪 Benchmark & Tuning Ladder

Full methodology, change table, accuracy gates, and the results log live in
[`BENCHMARK-PLAN.md`](BENCHMARK-PLAN.md). Quick version:

```bash
# on the Spark host — one scenario = before/after metrics + power + CSV row
./bench/run-scenario.sh B1 C3 42          # 8k in / 1k out @ concurrency 3
./bench/accuracy-gate.sh B1               # 10-prompt sanity gate
```

| Script | Purpose |
|---|---|
| `bench/run-scenario.sh` | C1 (32k prefill), C2 (decode), C3 (3 concurrent) → `bench/results.csv` incl. preemption delta, MTP acceptance, Wh/1k tokens |
| `bench/snapshot-metrics.sh` | Raw Prometheus counter snapshot |
| `bench/accuracy-gate.sh` | Fixed prompts saved to `bench/accuracy/<label>/` for diffing |

**Timing:** ~15–25 min of benchmarks per ladder step, ~6–20 min restart between steps → the full 9-step ladder (T1 safe tuning → T3 accuracy-gated experiments) is roughly one working day.

**Rule:** one variable at a time; keep only if the change beats B1 on `bench/results.csv` (and passes the accuracy gate for T3 changes). Sanity targets: decode ≥ 100 tok/s @1 (MTP, code), zero preemptions @3 concurrent, prefix hit ≥ 90% on agent traffic.

## 🔄 Operations

### Update vLLM / Model
```bash
# 1. Update digest in group_vars/spark_nodes.yml
# 2. Re-run only AI role
ansible-playbook -i inventory.yml site.yml --tags spark-ai
```

### Rollback Overlays (if PLE breaks)
```bash
# Pre-backup (do before every update!)
tar -czf /mnt/spark_nvme/overlays-backup-$(date +%F).tar.gz \
  /mnt/spark_nvme/worker_image_quant.py \
  /mnt/spark_nvme/ple_layer_quant.py \
  /mnt/spark_nvme/connector_mrv2.py

# Restore
tar -xzf /mnt/spark_nvme/overlays-backup-2025-01-15.tar.gz -C /
docker compose restart vllm-engine
```

### Backup KV Cache + Tables
```bash
# Add to cron.daily
rsync -a /mnt/spark_nvme/ples_int4/ /backup/spark/ples_int4/
rsync -a /mnt/spark_nvme/kv_cache/ /backup/spark/kv_cache/
```

## 🛠️ Development

### Local Testing (with Molecule)
```bash
cd ansible
pip install molecule molecule-plugins[docker]
molecule test -s ubuntu2204
```

### Lint
```bash
ansible-lint site.yml
yamllint .
```

## 📚 Documentation

- **Benchmark & Tuning**: [`BENCHMARK-PLAN.md`](BENCHMARK-PLAN.md) — proven baseline, change ladder, harness, results log
- **Full Guide**: [`spark.md`](spark.md) — architecture, step-by-step, troubleshooting, changelog
- **Proven Baseline Compose**: [`spark-compose.proven.yaml`](spark-compose.proven.yaml) — B1, the benchmark reference
- **Legacy Compose**: [`spark-compose.yaml`](spark-compose.yaml) — B0, kept for A/B only
- **Source Recipes**: [`resources/`](resources/) — r/LocalLLaMA threads + primitive-ai PLE card the config is built from

## 🤝 Contributing

1. Fork → branch → PR
2. All changes via Ansible (no manual server mutations)
3. Update `group_vars` + templates + `spark.md` together
4. `ansible-lint` and `yamllint` must pass

## 📄 License

MIT — Use freely for your DGX Spark deployments.

---

**Built for NVIDIA DGX Spark (GB10 Grace Blackwell) · Tested on 128 GB Unified Memory · Qwen3.8-Flash-Next-AWQ 98/100**