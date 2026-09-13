# NVIDIA DGX Spark — AI Stack Deployment Guide

> **Celoten, avtomatiziran vodnik** za pretvorbo novega DGX Spark sistema v produkcijsko-pripravljen AI stroj z **Qwen3.8-Flash-Next-AWQ (98/100)** in **llm-d Router**, upravljan z **Ansible** od samega začetka.

---

## 🧠 Povzetek strategije

| Ciljna metrika | Vrednost |
|----------------|----------|
| Model natančnost (logični sklep) | **98/100** (AWQ W4A16) |
| Maksimalni kontekst | **173,400 tokenov** |
| KV Cache offload | **XFS na NVMe** (mmap, zero-copy) |
| N-gram tabelo kompresija | **95 GB → 32 GB (INT4)** |
| Upravljanje seij | **llm-d Router** (FIFO + flow control) |
| Spekulativno kodiranje | **MTP, 3 tokeni** (~87% acceptance koda/JSON) |
| Avtomatizacija | **Ansible (idempotentno, ponovljivo)** |

---

## 🏗️ Arhitektura

```
┌─────────────────────────────────────────────────────────────────┐
│                      DGX Spark (128 GB Unified)                 │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐    ┌──────────────────┐                  │
│  │  llm-d Router    │───▶│  vLLM Engine     │                  │
│  │  :8080 (Gateway) │    │  :8000 (OpenAI)  │                  │
│  └──────────────────┘    └────────┬─────────┘                  │
│                                   │                            │
│                    ┌──────────────┼──────────────┐             │
│                    ▼              ▼              ▼             │
│             ┌──────────┐   ┌────────────┐  ┌──────────┐       │
│             │Model AWQ │   │PLE Overlays│  │INT4 Tables│       │
│             │(EXT4)    │   │(XFS, ro)   │  │(XFS, ro) │       │
│             └──────────┘   └────────────┘  └──────────┘       │
│                                   ▲                            │
│                    ┌──────────────┼──────────────┐             │
│                    ▼              ▼              ▼             │
│             ┌────────────────────────────────────────┐         │
│             │      KV Cache (XFS, rw, mmap)          │         │
│             └────────────────────────────────────────┘         │
└─────────────────────────────────────────────────────────────────┘
```

**Disk layout:**
- **EXT4** (`/dev/nvme0n1p1` ~450 GB): OS, Docker, modeli (`~/models`), projekt (`~/qwen-spark-stack`)
- **XFS** (`/dev/nvme0n1p2` ostatak): `/mnt/spark_nvme/{kv_cache, ples_int4, overlays}`

---

## 🚀 Hitri zagon (Ansible)

### Predpogoji
- Ansible control machine z dostopom do Spark preko SSH
- SSH ključi že nastavljeni (`~/.ssh/id_ed25519`)
- Python 3.10+ na control machine

```bash
# 1. Kloniraj repozitorij
git clone <your-repo> spark-ai-stack
cd spark-ai-stack/ansible

# 2. Uredi inventory.yml (nastavi IP, uporabnik, napravo)
nano inventory.yml

# 3. (Opcijsko) Šifriraj občutljive vrednosti
ansible-vault encrypt group_vars/spark_nodes.yml

# 4. Zaženi celoten deployment
ansible-playbook -i inventory.yml site.yml

# 5. Preveri status
curl http://<SPARK_IP>:8000/health   # vLLM
curl http://<SPARK_IP>:8080/ready    # Router
```

**Čas trajanja:** ~15–25 min (odvisno od hitrosti prenosa modela ~75 GB + tabel ~32 GB).

---

## 📋 Podrobni koraki (Ansible rologija)

### 1. `spark-base` — Osnovna konfiguracija sistema
| Task | Opis |
|------|------|
| Paketi | `parted`, `xfsprogs`, `docker.io`, `docker-compose-v2`, `python3-docker`, `curl`, `jq`, `htop`, `nvme-cli` |
| Docker | Omogoči, zagnaj, dodaj uporabnika v `docker` skupino |
| Disk | Ustvari XFS particijo na preostanku NVMe, formatiraj (`agcount=16`), mount v `/etc/fstab` z `noatime,nodiratime,logbufs=8,logbsize=256k,nobarrier` |
| Direktoriji | `/mnt/spark_nvme/{kv_cache,ples_int4}` z `0777` |
| Kernel | `ptrace_scope=0`, `vm.max_map_count=262144`, `fs.file-max=1000000`, `net.core.somaxconn=65535` (trajno v `/etc/sysctl.d/99-spark-ai.conf`) |
| Systemd | Ustvari `spark-ai.service` za avtomatski zagon Docker Compose stacka |
| HF CLI | Namesti `huggingface_hub[cli]` s `hf_transfer` |

### 2. `spark-ai` — vLLM Engine deployment
| Task | Opis |
|------|------|
| Model | Prenesi `wtdcode/Qwen3.8-Flash-Next-AWQ-W4A16` → `~/models/Qwen3.8-Flash-Next-AWQ` |
| PLE Overlays | Prenesi `worker_image_quant.py`, `ple_layer_quant.py`, `connector_mrv2.py` → `/mnt/spark_nvme/` |
| INT4 Tabele | Prenesi `ples_int4/*` → `/mnt/spark_nvme/ples_int4/` |
| Compose | Rendiraj `docker-compose.yaml.j2` → `~/qwen-spark-stack/docker-compose.yaml` |
| Images | `docker compose pull` (pinned digest!) |
| Start | `docker compose up -d vllm-engine` |
| Health | Počakaj na `/health` (max 180 s) |

### 3. `llm-router` — llm-d Router deployment
| Task | Opis |
|------|------|
| Start | `docker compose up -d llm-router` (odvisno od `vllm-engine:healthy`) |
| Health | Počakaj na `/ready` |
| Verify | Preveri `GET /v1/models` preko routerja |

---

## ⚙️ Konfiguracija (group_vars/spark_nodes.yml)

Vse ključne nastavitve so v enem mestu — **nikoli ne urejaj templatov neposredno**.

```yaml
# Primer spremenljivk (glej datoteko za polno verzijo)

vllm:
  image: "vllm/vllm-openai:qwen38-flash-next@sha256:DIGEST"  # OBVEZNO pinaj digest!
  max_num_seqs: 4
  max_model_len: 173400
  enable_chunked_prefill: true
  max_num_batched_tokens: 16384
  enable_prefix_caching: true
  gpu_memory_utilization: 0.95
  kv_cache_dtype: "fp8"
  memory_limit: "126G"
  swap_space: 32
  shm_size: "32g"
  speculative_method: "mtp"
  speculative_tokens: 3
  enforce_eager: false

llm_router:
  max_concurrent_sessions: 3
  routing_strategy: "fifo"

xfs:
  device: "/dev/nvme0n1p2"
  mount_point: "/mnt/spark_nvme"
  mkfs_options: "-f -d agcount=16"

kernel_params:
  kernel.yama.ptrace_scope: 0
  vm.max_map_count: 262144
  fs.file-max: 1000000
```

### Ključne spremenljivke za prilagajanje

| Spremenljivka | Kdaj spremeniti |
|---------------|-----------------|
| `spark_nvme_device` | Drugačen NVMe disk (npr. `/dev/nvme1n1`) |
| `vllm.max_model_len` | Krajši/daljši kontekst (pazi na VRAM) |
| `vllm.gpu_memory_utilization` | Če pride do OOM (znižaj na 0.82) |
| `llm_router.max_concurrent_seessions` | Več hkratih seij (pazi na VRAM) |
| `vllm.image` | Nov vLLM release — **vedno posodobi digest!** |

---

## 🔒 Varnost in Hardening

| Ukrep | Implementacija |
|-------|----------------|
| No privileged containers | `cap_add: [SYS_PTRACE, IPC_LOCK, SYS_RESOURCE]`, `security_opt: [no-new-privileges:true]` |
| Read-only rootfs | `read_only: true`, `tmpfs` za `/tmp`, `/var/run`, `/data/kv_cache` |
| Minimal capabilities | Samo nujni CAPs, brez `CAP_SYS_ADMIN`, `CAP_DAC_OVERRIDE` |
| Network isolation | Lasten `bridge` network `spark-net` |
| Log rotation | JSON driver, `max-size: 50m`, `max-file: 5` |
| Systemd hardening | `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `ReadWritePaths` omejeno |

---

## 📊 Observability

### Health Endpoints
| Storitev | Endpoint | Upravitelj |
|----------|----------|------------|
| vLLM Engine | `GET /health` | Docker healthcheck + systemd |
| vLLM Metrics | `GET /metrics` | Prometheus scrape |
| llm-d Router | `GET /ready` | Docker healthcheck |
| Router Metrics | `GET /metrics` | Prometheus scrape |

### Prometheus Scrape Config (primer)
```yaml
scrape_configs:
  - job_name: 'vllm-engine'
    static_configs:
      - targets: ['spark-dgx:8000']
  - job_name: 'llm-router'
    static_configs:
      - targets: ['spark-dgx:8080']
```

### Grafana Dashboards
- **vLLM**: `vllm-official` (import ID: 18659)
- **llm-d**: custom dashboard za queue depth, latency percentili, routing decisions

---

## 🧪 Testiranje in Benchmark

### Ročni test (po deploymentu)
```bash
# Preveri model
curl -X POST http://<SPARK_IP>:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen3-8-flash-next", "prompt": "Hello, world!", "max_tokens": 50}'

# Preveri dolg kontekst (100k+)
curl -X POST http://<SPARK_IP>:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen3-8-flash-next", "prompt": "'"$(head -c 100000 /dev/zero | tr '\0' 'a ')"'", "max_tokens": 100}'
```

### Ansible Benchmark (vključen v `site.yml`)
```yaml
benchmark:
  enabled: true
  tool: "hey"
  requests: 100
  concurrency: 10
  prompt: "Explain quantum computing in simple terms."
  max_tokens: 512
```

**Ciljne metrike (DGX Spark, Qwen3.8-Flash-Next):**
| Metrika | Cilj |
|---------|------|
| TTFT (p50) | < 200 ms |
| TTFT (p99) | < 800 ms |
| Decode throughput | > 100 tok/s |
| Concurrent sessions | 3 brez degradation |

---

## 🔄 Operacije

### Posodobitev modela / vLLM
```bash
# 1. Posodobi digest v group_vars/spark_nodes.yml
vllm:
  image: "vllm/vllm-openai:qwen38-flash-next@sha256:NEW_DIGEST"

# 2. Poženi le spark-ai rolo
ansible-playbook -i inventory.yml site.yml --limit spark_nodes --tags spark-ai
# Ali ročno:
cd ~/qwen-spark-stack && docker compose pull vllm-engine && docker compose up -d vllm-engine
```

### Rollback (če nov vLLM zlomi PLE overlays)
```bash
# 1. Varnostna kopija overlayev (naredi pred vsakim update-om!)
tar -czf /mnt/spark_nvme/overlays-backup-$(date +%F).tar.gz \
  /mnt/spark_nvme/worker_image_quant.py \
  /mnt/spark_nvme/ple_layer_quant.py \
  /mnt/spark_nvme/connector_mrv2.py

# 2. Ob napaki: vrni datoteke in restart
tar -xzf /mnt/spark_nvme/overlays-backup-2025-01-15.tar.gz -C /
docker compose restart vllm-engine
```

### Backup KV Cache in tabel
```bash
# Dnevni cron (dodaj v /etc/cron.daily/spark-ai-backup)
#!/bin/bash
rsync -a /mnt/spark_nvme/ples_int4/ /backup/spark/ples_int4/
rsync -a /mnt/spark_nvme/kv_cache/ /backup/spark/kv_cache/
```

### Logs
```bash
# Docker logs (JSON, rotirani)
docker logs -f vllm-qwen-spark --tail 100
docker logs -f llm-d-router --tail 100

# Systemd journal
journalctl -u spark-ai -f

# Sistemski logi
dmesg -T | grep -i nvme
```

---

## 🛠️ Razvoj in Debug

### Vstop v vLLM kontejner
```bash
docker exec -it vllm-qwen-spark bash
# Notri: python -c "import vllm; print(vllm.__version__)"
```

### Preveri PLE offload status
```bash
curl -s http://localhost:8000/metrics | grep ple
# Išči: ple_offload_ready, ple_cpu_offload_bytes, ple_gpu_offload_bytes
```

### NCCL Debug
```bash
docker exec vllm-qwen-spark env | grep NCCL
# Nastavi v compose: NCCL_DEBUG=INFO za verbosen output
```

### XFS Performanca
```bash
# Preveri mount options
findmnt -T /mnt/spark_nvme -o OPTIONS

# Benchmark disk
fio --name=randread --ioengine=libaio --iodepth=32 \
    --rw=randread --bs=4k --direct=1 --size=10G \
    --numjobs=4 --runtime=60 --group_reporting \
    --filename=/mnt/spark_nvme/test.fio
```

---

## ❗ Pogosti problemi in rešitve

| Simptom | Uzrok | Rešitev |
|---------|-------|---------|
| `pidfd_getfd failed` | Manjka `SYS_PTRACE` | Preveri `cap_add` v compose |
| OOM killer ubi vLLM | `gpu_memory_utilization` previsoko | Znižaj na 0.82, preveri `memory_limit` |
| Router vrača 503 | vLLM ni `healthy` | Preveri `docker logs vllm-qwen-spark`, počakaj na `/health` |
| XFS mount fails | Napaka v `/etc/fstab` | `mount -a` prikaže napako, popravi opcije |
| Model download stuck | Brez `hf_transfer` | `pip install -U "huggingface_hub[cli]"` + `HF_HUB_ENABLE_HF_TRANSFER=1` |
| `permission denied` na XFS | Napačni lastnik/pravice | `chown -R ubuntu:ubuntu /mnt/spark_nvme` |

---

## 📚 Viri in reference

- [vLLM PLE Offload Documentation](https://docs.vllm.ai/en/latest/features/ple_offload.html)
- [Primitive-AI Qwen3.8-Flash-Next-PLE-quant](https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant)
- [llm-d Router GitHub](https://github.com/llm-d/llm-d)
- [XFS Optimization for NVMe](https://xfs.wiki.kernel.org/index.php/Performance_tuning)
- [NCCL Tuning Guide](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/usage/troubleshooting.html)
- [Reddit: Qwen3.8-Flash-Next 98/100](https://www.reddit.com/r/LocalLLaMA/comments/1w7c4ej/)
- [Reddit: 170K Context on 96 GB](https://www.reddit.com/r/LocalLLaMA/comments/1w2b2j0/)

---

## 📝 Changelog

| Verzija | Datum | Spremembe |
|---------|-------|-----------|
| 2.1 | 2025-01 | Recept tuning po r/LocalLLaMA (1w2b2j0, 1w7c4ej): MTP spekulacija (3 tok), prefix caching, 16k chunked prefill, 173400 kontekst, gpu-mem-util 0.95, swap-space 32, brez enforce-eager, healthcheck start_period 1200 s, persistirani compile cache-i na XFS |
| 2.0 | 2025-01 | Ansible avtomatizacija, hardening, healthchecks, systemd, logging, benchmark |
| 1.0 | 2025-01 | Prva verzija: ročni setup, compose, XFS, PLE |

---

> **Napomena:** Ta dokumentacija je del Git repozitorija. Vse spremembe potekajo skozi PR review. Ansible playbooki so **edini** način deploymenta — ročni ukazi so samo za debug.