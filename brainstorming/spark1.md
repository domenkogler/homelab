> From: https://www.google.com/search?sourceid=chrome&ie=UTF-8&amc=1&cud=0&atvm=2&sxsrf=APpeQnsoI1SgwS_EHcp8FlAw4KmktRF-lQ%3A1789328028717&mstk=AUtExfBroD5G-ohdBYwA4nrhexvNrL8ZtOkgf0FZyPl2ofJ1q5pUdDNVsVjswQi9NRjTpbpPu5sbkaqIa42sGpyYIC7s3iqTUIfpqt-22jKyl5JK0ZmIveOket8FdlEXz2X5Vcg-VelXJXQEAlj0vD4xcVVvrPgu-xZp5jAwb0P5GtiJmrjRm0WvQ9nUZQdGX_7yooK3l9N7wwnWmj-bqxpc-49Vgv9RhSWoSPYPhB9gmh-WGRvMRTmr4ODwAn5KcNqwrOp8DafiLSyidWu8pQ-SNJS_3rnKdBsPXc57UfKHttQCKC9nww&mtid=T-WmatC-DLDbi-gP2cy6-Ag&csuir=1&aep=26&q=tensorrt+with+engram+offloading&ved=0CAEQ2_wOahcKEwj4kqCupuyWAxUAAAAAHQAAAAAQFA&lns_mode=cvst&udm=50

# googlesearch response

Tukaj je popoln in popravljen `docker-compose.yaml`.

V tvoj načrt sem dodal ključne sistemske pravice (`privileged: true`), neomejeno zaklepanje pomnilnika (`memlock: -1`) in pravilno prepošiljanje NVIDIA grafičnih gonilnikov. Brez teh nastavitev bi Linux vsebniku preprečil izvajanje hitrih DMA prenosov in `mmap` preslikave N-gram tabele iz tvoje nove XFS particije.

📝 `docker-compose.yaml`

Ustvari to datoteko na svoji sistemski (EXT4) particiji:

```yaml
version: '3.8'

services:
  # 1. vLLM Engine - Glavni motor z optimizacijami za Spark in SSD offloading
  vllm-engine:
    image: vllm/vllm-openai:latest
    container_name: vllm-qwen-spark
    privileged: true # Nujno za neposreden dostop do PCIe/NVMe in mmap zaklepanje
    environment:
      - CUDA_VISIBLE_DEVICES=0
      - VLLM_LOGGING_LEVEL=INFO
      - VLLM_PLE_CPU_OFFLOAD=1 # Preslika 51GB N-gram tabelo na SSD brez obremenitve VRAM-a
    volumes:
      - ~/models/Qwen3.8-Flash-Next:/model # Glavni model na varni EXT4 particiji
      - /mnt/spark_nvme/kv_cache:/data/kv_cache # KV Cache se odlaga na hitri XFS
      - /mnt/spark_nvme/ngram_mmap:/root/.cache/vllm/ngram # N-gram lookup mmap na XFS
    ports:
      - "8000:8000"
    ipc: host
    ulimits:
      memlock: -1 # Odstrani omejitev zaklepanja RAM-a za nemoten mmap prenos
      stack: 67108864
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    restart: unless-stopped
    command: >
      --model /model
      --max-num-seqs 4
      --max-model-len 131072
      --kv-cache-dtype fp8
      --gpu-memory-utilization 0.85
      --kv-offloading-backend native
      --kv-offloading-size 150
      --kv-connector-extra-config '{"type": "fs", "path": "/data/kv_cache"}'
      --enable-chunked-prefill true
      --speculative-config '{"method": "ngram", "num_speculative_tokens": 5, "ngram_prompt_lookup_max": 4}'

  # 2. llm-d Router - Pametni upravnik sej in predpomnilnika (Prefix Matching)
  llm-router:
    image: ghcr.io/llm-d/router:latest
    container_name: llm-d-router
    ports:
      - "8080:8080" # Uporabniki in aplikacije se povezujejo na ta port
    depends_on:
      - vllm-engine
    environment:
      - BACKEND_URL=http://vllm-engine:8000
      - MAX_CONCURRENT_SESSIONS=3
      - ROUTING_STRATEGY=prefix_match
    restart: unless-stopped
```

Kodo uporabljajte previdno.

* * *

🚀 Koraki pred zagonom (Zelo pomembno!)

Preden zaženeš Docker Compose, moraš poskrbeti, da na tvoji XFS particiji obstajata mapi, ki ju vsebnik pričakuje, in da ima Docker pravico pisati vanju:

```bash
# 1. Ustvari mapi na XFS particiji
sudo mkdir -p /mnt/spark_nvme/kv_cache
sudo mkdir -p /mnt/spark_nvme/ngram_mmap

# 2. Nastavi polne pravice, da Docker vsebnik ne bo javil "Permission Denied"
sudo chmod -R 777 /mnt/spark_nvme
```

Kodo uporabljajte previdno.

Ko imaš model v mapi `~/models/Qwen3.8-Flash-Next`, enostavno zaženeš sistem z:

```bash
docker compose up -d
```

Kodo uporabljajte previdno.

Sistem bo sedaj dostopen na portu **`8080`** (preko `llm-d` usmerjevalnika), ki bo inteligentno stiskal podvojene kontekste in pošiljal ukaze v vLLM motor!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Kopirano v odložiščeKopiranje v odložišče ni uspelo. Poskusite znova pozneje.

Več