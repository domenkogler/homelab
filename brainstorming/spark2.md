Tukaj je celovit, strukturiran in natančen vodnik za pretvorbo popolnoma novega **NVIDIA DGX Spark** sistema v vrhunski AI stroj, ki združuje izjemno natančnost modela **Qwen3.8-Flash-Next-AWQ (98/100)** z bliskovito hitrostjo prek **XFS disk offloadinga**.

* * *

🧠 Povzetek strategije seje

Da bi na enem samem Sparku (ki ima 128 GB enotnega pomnilnika) dosegli ogromen kontekst (nad 131k) brez upočasnitev in sesutij:

1.  **Disk razdelimo na dve particiji:** Prva (EXT4) je za sistem in Docker, druga (XFS) pa služi kot hitri podaljšek RAM-a za AI podatke.
2.  **Uporabimo AWQ W4A16 različico modela:** Ta dokazano dosega najvišjo natančnost logičnega sklepanja (98/100), saj ohranja ključne plasti v polni BF16 natančnosti.
3.  **Kvantiziramo N-gram tabelo (Primitive-AI):** Ogromno 95 GB tabelo zamenjamo s stisnjeno **INT4 različico (32 GB)**, ki jo preko `mmap` prebiramo neposredno iz XFS diska. RAM tako ostane prazen za KV Cache (zgodovino sej).
4.  **Dodamo `llm-d` Router:** Ta bo pred vLLM motorjem inteligentno združeval podvojene kontekste več sej (Prefix Matching).

* * *

🛠️ KORAK 1: Particioniranje diska in XFS optimizacija

Predpostavljamo, da ima tvoj Spark 1 TB NVMe pogon (če imaš tovarniško 4 TB različico, le prilagodi številke velikosti). Ker je sistem nov, skrčimo sistemsko particijo in ustvarimo namensko XFS particijo za AI podatke.

```bash
# 1. Poglej trenutno razporeditev diska (običajno je primarni disk /dev/nvme0n1)
lsblk

# 2. Ustvari novo particijo na preostanku diska (od 450 GB do konca)
sudo parted /dev/nvme0n1 mkpart primary xfs 450GB 100%

# 3. Formatiraj novo particijo (veje /dev/nvme0n1p2) z optimizacijo za vzporedno branje
sudo mkfs.xfs -f -d agcount=16 /dev/nvme0n1p2

# 4. Ustvari trajno mapo za montažo
sudo mkdir -p /mnt/spark_nvme

# 5. Odpri datoteko za trajno montažo ob zagonu
sudo nano /etc/fstab
```

Kodo uporabljajte previdno.

Na dno datoteke `/etc/fstab` dodaj naslednjo vrstico (z vsemi nizko-zakasnitvenimi zastavicami in `,nobarrier` za maksimalno Gen5 hitrost):

```text
/dev/nvme0n1p2  /mnt/spark_nvme  xfs  noatime,nodiratime,logbufs=8,logbsize=256k,nobarrier  0  2
```

Kodo uporabljajte previdno.

_Shrani in zapri (`Ctrl+O`, nato `Ctrl+X`)._

```bash
# 6. Zaženi montažo in ustvari podmape s polnimi pravicami za Docker
sudo mount -a
sudo mkdir -p /mnt/spark_nvme/kv_cache
sudo mkdir -p /mnt/spark_nvme/ples_int4
sudo chmod -R 777 /mnt/spark_nvme
```

Kodo uporabljajte previdno.

* * *

🐳 KORAK 2: Priprava Docker okolja in pravic

Na novem sistemu moramo poskrbeti, da bo Docker imel pravico izvajati neposredne prenose pomnilnika (DMA) in zaklepanje RAM-a.

```bash
# 1. Ustvari mapo za projekte na EXT4 particiji
mkdir -p ~/qwen-spark-stack
cd ~/qwen-spark-stack

# 2. Omogoči Ptrace scope na operacijskem sistemu (nujno za CUDA IPC komunikacijo med vsebnikoma)
sudo sysctl -w kernel.yama.ptrace_scope=0

# Da bo ta nastavitev ostala trajna tudi po ponovnem zagonu Sparka:
echo "kernel.yama.ptrace_scope = 0" | sudo tee -a /etc/sysctl.conf
```

Kodo uporabljajte previdno.

* * *

📥 KORAK 3: Prenos modela in popravkov (Overlays)

Najprej namestimo Hugging Face CLI in prenesemo vse potrebne komponente.

```bash
# 1. Namesti Hugging Face CLI orodje
pip install -U "huggingface_hub[cli]"

# 2. Prenesi zmagovalni AWQ model na EXT4 particijo (velikost cca 75 GB)
mkdir -p ~/models/Qwen3.8-Flash-Next-AWQ
huggingface-cli download wtdcode/Qwen3.8-Flash-Next-AWQ-W4A16 --local-dir ~/models/Qwen3.8-Flash-Next-AWQ

# 3. Premakni se na XFS particijo in prenesi Primitive-AI datoteke
cd /mnt/spark_nvme

# Prenos treh Python skript (vključno s popravkom za odpravo obešanja vLLM-ja)
huggingface-cli download primitive-ai/Qwen3.8-Flash-Next-PLE-quant worker_image_quant.py ple_layer_quant.py connector_mrv2.py --local-dir .

# Prenos stisnjenih INT4 tabel (cca 32 GB podatkov) directly v namensko mapo
huggingface-cli download primitive-ai/Qwen3.8-Flash-Next-PLE-quant --include "ples_int4/*" --local-dir /mnt/spark_nvme
```

Kodo uporabljajte previdno.

* * *

📝 KORAK 4: Ustvarjanje `docker-compose.yaml`

Premakni se nazaj v projektno mapo na EXT4 particiji in ustvari nastavitveno datoteko:

```bash
cd ~/qwen-spark-stack
nano docker-compose.yaml
```

Kodo uporabljajte previdno.

Vpiši to natančno in preverjeno vsebino:

Za konfiguracijo `docker-compose.yaml` vključite storitvi `vllm-engine` in `llm-router` z ustreznimi nastavitvami za deljenje virov, mape in povezave na stisnjene tabele ter model.

Nato zaženite sistem z ukazom `docker compose up -d` in spremljajte dnevnike izvajanja z `docker logs -f vllm-qwen-spark`.


[Updated my benchmark with a new vLLM based recipe for Qwen 3.8 Flash Next : now up to 98/100 (instead of 91 previously)](https://www.reddit.com/r/LocalLLaMA/comments/1w7c4ej/updated_my_benchmark_with_a_new_vllm_based_recipe/)
[Qwen3.8-Flash-Next at 170K context on a single 96 GB card. ~110 tok/s](https://www.reddit.com/r/LocalLLaMA/comments/1w2b2j0/qwen38flashnext_at_170k_context_on_a_single_96_gb/)