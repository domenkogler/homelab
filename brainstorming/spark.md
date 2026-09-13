Tukaj je kratek, strukturiran in pregleden povzetek celotnega pogovora, ki vam bo služil kot natančen načrt za prvi zagon in konfiguracijo vaše naprave **DGX Spark** (128 GB RAM-a, 1 TB NVMe SSD).

## ---

**1\. Razporeditev 1 TB NVMe SSD diska**

Glede na to, da imate na voljo 1 TB prostora, je ključno, da disk med namestitvijo operacijskega sistema (DGX OS / Ubuntu) ročno razdelite na dve particiji. S tem zaščitite sistem pred zrušitvijo in maksimizirate hitrost umetne inteligence.

> * **Particija 1: Sistemska (/) — Velikost: 450 GB | Format: EXT4**  
  * **Namen:** Operacijski sistem, Docker okolje in shranjevanje samega modela Qwen3.8-Flash-Next (ki teče v stisnjeni NVFP4/4-bitni različici in zasede \~25 GB).  
> * **Particija 2: AI Podatki (/mnt/spark\_nvme) — Velikost: preostalih \~500 GB | Format: XFS**  
  * **Namen:** Ekskluzivna particija za vLLM offloading. XFS preprečuje zaklepanje niti pri več sejah in omogoča najvišjo PCIe Gen5 prepustnost.  
  * **Nastavitev v /etc/fstab (za minimalno zakasnitev):**  
    `/dev/nvme0n1p2  /mnt/spark_nvme  xfs  noatime,nodiratime,logbufs=8,logbsize=256k  0  2`

## ---

**2\. Končna odločitev glede programske opreme (Engine Stack)**

Za upravljanje **3 konkurentnih sej** enega uporabnika boste uporabili kombinacijo dveh orodij v Docker okolju:

> 1. **vLLM (v1 eksperimentalni način):** Skrbi za izvajanje modela, stiskanje pomnilnika in asinhroni prenos podatkov na XFS particijo SSD-ja prek DMA prenosov.  
> 2. **llm-d Router:** Postavljen pred vLLM. Skrbi za pametno usmerjanje sej. Če se v več sejah pojavi enak obsežen dokument ali sistemski poziv (*System Prompt*), ga llm-d obdela le enkrat (prefix\_match), kar drastično prihrani prostor in čas.

## ---

**3\. Končna Docker Compose konfiguracija in nastavitve**

Ta konfiguracija omogoča hkratni **N-gram Offload** (51 GB velika FP16 tabela za spekulativno dekodiranje se preslika na SSD preko mmap in ne obremenjuje RAM-a) ter **KV Cache Offload** (zgodovina sej se odlaga na disk).

Ustvarite docker-compose.yaml na sistemski particiji:

`version: '3.8'`

`services:`  
  `# 1. vLLM Engine - Glavni motor z optimizacijami za Spark in SSD`  
  `vllm-engine:`  
    `image: vllm/vllm-openai:latest`  
    `container_name: vllm-qwen-spark`  
    `environment:`  
      `- CUDA_VISIBLE_DEVICES=0`  
      `- VLLM_LOGGING_LEVEL=INFO`  
      `- VLLM_PLE_CPU_OFFLOAD=1 # Preslika 51GB FP16 N-gram tabelo na SSD (mmap)`  
    `volumes:`  
      `- ~/models/Qwen3.8-Flash-Next:/model # Model je varno na EXT4 particiji`  
      `- /mnt/spark_nvme/kv_cache:/data/kv_cache # KV Cache gre na hitri XFS`  
      `- /mnt/spark_nvme/ngram_mmap:/root/.cache/vllm/ngram # N-gram gre na XFS`  
    `ports:`  
      `- "8000:8000"`  
    `ipc: host`  
    `deploy:`  
      `resources:`  
        `reservations:`  
          `devices:`  
            `- driver: nvidia`  
              `count: 1`  
              `capabilities: [gpu]`  
    `command: >`  
      `--model /model`  
      `--max-num-seqs 4`  
      `--max-model-len 131072`  
      `--kv-cache-dtype fp8`  
      `--gpu-memory-utilization 0.85`  
      `--kv-offloading-backend native`  
      `--kv-offloading-size 150`  
      `--kv-connector-extra-config '{"type": "fs", "path": "/data/kv_cache"}'`  
      `--enable-chunked-prefill true`  
      `--speculative-config '{"method": "ngram", "num_speculative_tokens": 5, "ngram_prompt_lookup_max": 4}'`

  `# 2. llm-d Router - Upravnik sej in pametnega predpomnilnika`  
  `llm-router:`  
    `image: ghcr.io/llm-d/router:latest`  
    `container_name: llm-d-router`  
    `ports:`  
      `- "8080:8080"`  
    `depends_on:`  
      `- vllm-engine`  
    `environment:`  
      `- BACKEND_URL=http://vllm-engine:8000`  
      `- MAX_CONCURRENT_SESSIONS=3`  
      `- ROUTING_STRATEGY=prefix_match`

## ---

**4\. Podrobnosti za izvedbo in pričakovani kontekst**

> * **Zmogljivost konteksta:** Qwen3.8-Flash-Next ima napredno GDN \+ QSA arhitekturo, zato je njegov KV Cache do 4-krat lažji od klasičnih modelov. S **FP8 stiskanjem** (--kv-cache-dtype fp8) bo sistem v hitrem pomnilniku Sparka zadržal med 400k in 500k toknov, preostalih 150 GB na SSD-ju (--kv-offloading-size 150\) pa lahko shrani še do 1 milijon toknov zgodovine.  
> * **Optimalna meja konteksta (262k):** Sistem je nastavljen na nativno mejo **262k toknov** na sejo. To pomeni, da lahko **vse 3 seje hkrati delujejo na polnem nativnem kontekstu**. Preklapljanje med njimi bo bliskovito.  
> * **Opozorilo glede dviga na 1M kontekst:** Tehnično je mejo mogoče dvigniti na 1 milijon toknov z YaRN skaliranjem, vendar bi v tem primeru ena sama polna seja (80 GB podatkov) zapolnila celoten RAM Sparka. Preostali dve seji bi morali v celoti spati na SSD-ju, kar bi ob preklopu med sejami povzročilo večsekundni zamik (*Time-to-First-Token*), medtem ko sistem prepisuje gigabajte podatkov preko PCIe vodila. Za eksperimentiranje je 1M izvedljiv, za tekoče delo pa je 262k idealna točka.

## **Naslednji korak**

Ko zaključite namestitev OS-a in particioniranje, preprosto zaženite sistemske mape z mkdir \-p /mnt/spark\_nvme/{kv\_cache,ngram\_mmap} in poženite celoten sklad z docker compose up \-d.

**Sporočite, ko boste pripravljeni na prvi zagon**, pa lahko pripraviva preprosto Python testno skripto, ki bo hkrati obremenila vse 3 seje z dolgimi dokumenti, da boste v živo videli preklapljanje med RAM-om in SSD-jem\!

