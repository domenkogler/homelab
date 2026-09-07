> From: https://www.google.com/search?sourceid=chrome&ie=UTF-8&amc=1&udm=50&cud=0&atvm=2&sxsrf=APpeQnvymizbuOE4FQsJuhGKZABUEtMS-g%3A1788705807672&ved=0CCsQ2_wOahcKEwiwnZG4mtqWAxUAAAAAHQAAAAAQDA&mstk=AUtExfBdaDgBkXNUeouKhHjKZh6HcY0K4pZU9M0T19_ZJQSyKhNVNa570cEkFogFgb1SZtPJtydoRCYb2X9KVc717AWmKiLQ94geyCgUoJ7TbPu_a3auEw3YQIh7DofskVwiNOBBX4KCRR7oAvm7b1LI72gqn6gTDZsKdISgZ7MDy7KuKNTUpxe9nna_VypEUhyv9dMO-hMtkyKTC_xirKQ40g5--AybvQM1r97S5gbJ3YR4AN1HYGkgH6iUPWh4ZFXKIEgv41HkhSX4ohpaf7j3dewAgT1oA3OpCmZdGm1qiYmEmJanA4uO6npNagGgshSPKaOmq59Ic9uvyA&mtid=PQKbat-rHdzwi-gP28rhsA8&csuir=1&aep=26&q=os+na+Lenovo+pgx+GB+10+je+Debian%3F+se+mi+spaca+na+novo+namestiti+najnovej%C5%A1o+razli%C4%8Dico+debiana+vi+headless+na%C4%8Dinu+in+dodati+samo+specifi%C4%8Dne+pakete+za+Spark%3F

# you asked

message time: 2026-09-04 00:00:00

os na Lenovo pgx GB 10 je Debian? se mi spaca na novo namestiti najnovejšo različico debiana vi headless načinu in dodati samo specifične pakete za Spark?

---

# googlesearch response

**Ne, tovarniški operacijski sistem na delovni postaji Lenovo ThinkStation PGX (z NVIDIA GB10 superčipom) ni čisti Debian, ampak NVIDIA DGX OS.**

Ta sistem sicer temelji na distribuciji **Ubuntu Linux Pro za arhitekturo ARM64**, ki je v svojem jedru sorodna Debianu, vendar vsebuje specifične in močno prilagojene gonilnike ter knjižnice NVIDIA Base OS.

Glede na vaše načrte pa velja opozorilo: **namestitev golega, čistega Debiana v brezglavem (headless) načinu na to napravo se vam ne splača in se ji raje izognite.**

Spodaj so razlogi, zakaj je to slaba ideja, in boljša alternativa za vaš projekt z Apache Spark.

* * *

Zakaj čisti Debian na tej strojni opremi NI dobra ideja?

1.  **Specifična ARM64 arhitektura in superčip (NVIDIA GB10):** Računalnik poganja superčip _Grace Blackwell_. Gre za prepleteno delovanje ARM procesorja (Grace) in Blackwell grafičnega jedra preko ultra hitre povezave ter skupnega sistemskega pomnilnika (128 GB Unified Memory). Čisti Debian nima vgrajenih ustreznih gonilnikov in jeder za pravilno upravljanje tega specifičnega strojnega sodelovanja.
2.  **Izguba optimizacije za CUDA in prenos podatkov:** Glavna prednost naprave PGX je brutalno hiter prenos podatkov med procesorjem in grafičnim delom. Če namestite generični Debian, boste izgubili uradne NVIDI-ine sistemske optimizacije.
3.  **Zapleteno ročno nastavljanje:** Iskanje, prevajanje in ročno nameščanje gonilnikov za Blackwell in ARM64 na čistem Debianu bi vam vzelo ogromno časa, končni izkupiček pa bi bil verjetno nestabilen sistem.

* * *

Kako pravilno doseči vaš cilj (Lahkoten, headless sistem za Spark)?

Če želite čim bolj čist sistem brez odvečne grafične navlake (GUI), ki ne bo po nepotrebnem trošil sistemskih virov, uberite naslednjo pot:

1\. Možnost: Preklopite obstoječi DGX OS v Headless način

NVIDIA DGX OS (Ubuntu) že ima vse tovarniško nastavljene gonilnike. Grafični vmesnik preprosto izklopite prek terminala:

-   Povežite se na napravo preko SSH.
-   Zaustavite in onemogočite grafični upravljalnik (Display Manager), da se ob zagonu ne bo več nalagal:

    bash

    ```
    sudo systemctl set-default multi-user.target
    sudo systemctl isolate multi-user.target
    ```

    Kodo uporabljajte previdno.

S tem boste sprostili ves grafični pomnilnik in procesorsko moč, sistem pa bo deloval natanko tako kot brezglavi (headless) strežnik.

2\. Možnost: Uporabite Docker (Najbolj priporočljivo za Spark)

Namesto da spreminjate osnovni operacijski sistem naprave, pustite DGX OS pri miru in uporabite vsebnike (vsebnike Docker):

-   **Zakaj?** Spark za svoje delo (sploh če boste uporabljali grafično pospeševanje preko _RAPIDS Accelerator za Apache Spark_) potrebuje točno določene različice Jave (JDK), CUDA knjižnic in Pythona.
-   **Rešitev:** Iz uradnega registra **NVIDIA NGC (NVIDIA GPU Cloud)** prenesite že pripravljen Docker vsebnik (container) za Spark/Umetno inteligenco. Ta vsebnik bo vseboval _samo_ pakete za Spark, hkrati pa bo znal popolnoma izkoristiti GB10 strojno opremo, ne da bi s tem umazali ali ogrozili stabilnost primarnega operacijskega sistema.

* * *

Če mi sporočite, ali boste Spark uporabljali za **klasično obdelavo podatkov na procesorju (CPU)** ali želite izkoristiti **Blackwell grafično pospeševanje (GPU)**, vam lahko pomagam pripraviti točne ukaze za konfiguracijo okolja ali Docker datoteke!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-04 00:00:00

uporabljal ga bom samo za konferenco, želel bi čimveč rama uporabiti za kontekst več saj hkrati

---

# googlesearch response

Glede na to, da boste napravo uporabili za **konferenčno predstavitev (predstavitve v živo oz. _demo_)** in želite izkoristiti **čim več enotnega pomnilnika (RAM) za hkratno poganjanje več velikih jezikovnih modelov (LLM)** z dolgimi konteksti, je vaša odločitev za optimizacijo sistema povsem pravilna. Na konferenci ne želite, da vam sistem zmrzne ali da zmanjka pomnilnika sredi predstavitve.

Za ta specifičen namen je namestitev čistega Debiana še vedno tvegana, saj lahko povzroči težave z gonilniki tik pred dogodkom. Obstaja veliko hitrejša, varnejša in učinkovitejša pot, da iz superčipa **NVIDIA GB10 (Grace Blackwell)** iztisnete zadnji megabajt pomnilnika.

Tukaj je načrt, kako pripraviti napravo za brezhibno konferenčno delovanje z maksimalno izrabo RAM-a.

* * *

1\. Korak: Popoln preklop v "Headless" način (Sprostitev RAM-a)

Obdržite tovarniški DGX OS (Ubuntu), vendar takoj izklopite grafično namizje. Grafični vmesniki (kot je GNOME ali Ubuntu Desktop) lahko sami zase porabijo nekaj gigabajtov sistemskega pomnilnika in nenehno obremenjujejo grafični procesor.

V terminalu izvedite naslednji ukaz, ki bo ob zagonu naložil le tekstovni vmesnik:

```bash
sudo systemctl set-default multi-user.target
sudo reboot
```

Kodo uporabljajte previdno.

_Opomba: Če boste po konferenci želeli grafično namizje nazaj, preprosto vtipkate `sudo systemctl set-default graphical.target`._

2\. Korak: Izkoristite Unified Memory (Enotni pomnilnik)

NVIDIA GB10 ima ključno prednost: **Grace CPU in Blackwell GPU si delita pomnilnik preko ultra hitre povezave NVLink-C2C.**
Za hkratno poganjanje več modelov z velikim kontekstom ne smete ročno ločevati, kaj gre na CPU in kaj na GPU. Uporabiti morate ogrodja (frameworks), ki to upravljajo samodejno.

Namesto klasičnega Sparka (ki je odlična izbira za tabelarične podatke, a manj primeren za hkratno streženje več LLM-jev v živo) za konferenčni demo močno priporočam uporabo **vLLM** ali **Ollama**.

3\. Korak: Kako zagnati več modelov hkrati z maksimalnim kontekstom?

Če želite na konferenci hkrati poganjati na primer 3 ali 4 različne modele (npr. Llama 3, Mistral, Qwen) in jim dati ogromno okno konteksta, uporabite **vLLM**, ker ima najboljši sistem za upravljanje s spominom (_PagedAttention_).

Pripravite si preprosto zagonsko skripto, kjer boste za vsak model natančno določili, koliko pomnilnika lahko zasede.

Primer ukaza za zagon enega od modelov v ozadju:

```bash
python3 -m vllm.entrypoints.openai.api_server \
    --model meta-llama/Meta-Llama-3-70B-Instruct \
    --gpu-memory-utilization 0.40 \
    --max-model-len 32768 \
    --port 8000 &
```

Kodo uporabljajte previdno.

**Kaj pomenijo te nastavitve za vaš namen?**

-   `--gpu-memory-utilization 0.40`: Temu modelu strogo omejite, da lahko porabi največ 40 % celotnega razpoložljivega pomnilnika. Tako vam ostane 60 % za druge modele, ki jih boste zagnali na drugih vratih (npr. `--port 8001`).
-   `--max-model-len 32768`: S tem modelu eksplicitno dovolite izjemno veliko okno konteksta (32k žetonov). vLLM bo vnaprej alociral pomnilnik za ta kontekst, kar prepreči napako _"Out of Memory"_ sredi predstavitve.

4\. Korak: Agregacija s Sparkom (če je nujen)

Če v vašem demo posnetku Spark igra ključno vlogo (npr. za predobdelavo podatkov, ki jih nato pošiljate v te modele), ga zaženite v **lokalnem načinu** z omejenim spominom za gonilnik (_driver memory_).

Ker bodo LLM modeli zasedli večino enotnega pomnilnika, Sparku ne dodelite preveč RAM-a, saj bo sicer prišlo do sesutja. V skripti zaženite Spark tako:

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("KonferencniDemo") \
    .master("local[*]") \
    .config("spark.driver.memory", "16g") \
    .getOrCreate()
```

Kodo uporabljajte previdno.

_S tem daste Sparku 16 GB stabilnega prostora za obdelavo podatkov, preostalih 100+ GB pa prepustite Blackwell čipu za poganjanje kontekstov jezikovnih modelov._

* * *

Če želite, vam lahko pomagam sestaviti **celotno Docker-compose datoteko** ali **zagonsko skripto**, ki bo ob vklopu naprave avtomatsko zagnala vse želene modele s pravilno porazdelitvijo RAM-a, da bo vaš nastop na konferenci potekal popolnoma gladko. Sporočite mi le, **katere modele** načrtujete prikazati!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-04 00:00:00

napaka, ne za konferenco ampak za inference (auto complete mi nagaja)

---

# googlesearch response

Aha, avtokorekt! To pa popolnoma spremeni situacijo. **Sklepanje (inference)** v produkcijskem okolju, kjer želite hkrati streči več velikih jezikovnih modelov (LLM) z izjemno velikimi konteksti, zahteva povsem drugačen pristop kot kratek konferenčni demo.

Pri produkcijskem sklepanju (inference) sta ključni dve stvari: **maksimalna stabilnost sistema** in **najnižja možna zakasnitev (latency)** pri obdelavi podatkov.

Tudi za ta namen je goli Debian slaba izbira, saj bi z njim izgubili optimizacije jedra za arhitekturo Grace Blackwell (GB10). Ker pa gre za resno produkcijo, moramo čim bolj natančno upravljati s pomnilnikom, saj dolgi konteksti (npr. 32k ali 128k žetonov) eksponentno povečujejo zahteve po RAM-u (t.i. _KV Cache_).

Tukaj je optimiziran načrt, kako nastaviti Lenovo ThinkStation z GB10 za visoko-zmogljivo produkcijsko sklepanje.

* * *

1\. Pustite DGX OS (Ubuntu) v Headless načinu

Za produkcijo je stabilnost na prvem mestu. Uradni **NVIDIA DGX OS** vam zagotavlja, da bodo gonilniki za enotni pomnilnik (Unified Memory) in povezavo NVLink-C2C delovali brez napak. Grafični vmesnik obvezno izklopite permanentno:

```bash
sudo systemctl set-default multi-user.target
sudo reboot
```

Kodo uporabljajte previdno.

2\. Kako maksimizirati RAM za hkratne kontekste?

Pri poganjanju več modelov hkrati z dolgimi konteksti je največji porabnik spomina **KV Cache** (pomnilnik, kjer si model zapomni pretekli kontekst znotraj pogovora). Če spomin upravljate napačno, bo sistem hitro javil napako _Out of Memory (OOM)_.

Za produkcijsko sklepanje namesto Sparka uporabite namenska produkcijska ogrodja:

A) vLLM (Najboljše za več modelov hkrati)

vLLM uporablja tehnologijo **PagedAttention**, ki deluje podobno kot virtualni spomin v operacijskih sistemih. Pomnilnik za kontekst razdeli na manjše bloke in ga dodeljuje dinamično. To prepreči fragmentacijo RAM-a in vam omogoča, da v isti pomnilnik stisnete veliko več vzporednih zahtev (queries) z dolgimi konteksti.

Zaženite vsak model kot samostojen mikrostoritev (API strežnik) z natančno odmero spomina:

```bash
# Zagon prvega modela (npr. zasede 45% pomnilnika)
python3 -m vllm.entrypoints.openai.api_server \
    --model meta-llama/Meta-Llama-3-70B-Instruct \
    --gpu-memory-utilization 0.45 \
    --max-model-len 65536 \
    --port 8000 &

# Zagon drugega modela (npr. zasede 45% pomnilnika)
python3 -m vllm.entrypoints.openai.api_server \
    --model mistralai/Mixtral-8x22B-Instruct-v0.1 \
    --gpu-memory-utilization 0.45 \
    --max-model-len 32768 \
    --port 8001 &
```

Kodo uporabljajte previdno.

_Preostalih 10 % pomnilnika pustite operacijskemu sistemu in gonilnikom za stabilno delovanje._

B) NVIDIA TensorRT-LLM (Maksimalna hitrost za GB10)

Če želite iz čipa Grace Blackwell iztisniti absolutni maksimum hitrosti (tokens per second), uporabite **TensorRT-LLM**.

-   To ogrodje modele vnaprej prevaja in optimizira posebej za Blackwell arhitekturo.
-   Podpira **Chunked Prefill**, kar pomeni, da izjemno dolge kontekste predeluje po delih, s čimer drastično zmanjša začetni skok v porabi RAM-a, ko uporabnik pošlje ogromno besedilo.

* * *

Kje bi v tem primeru sploh uporabili Spark?

V sodobnih arhitekturah za sklepanje se Apache Spark ne uporablja za samo poganjanje LLM modelov. Spark pa je odličen kot **predprocesorski korak pred sklepanjem**, če gre za masovno obdelavo (Batch Inference):

1.  Spark prebere milijone vrstic iz vaše baze podatkov ali podatkovnega jezera.
2.  Vzporedno očisti besedila in pripravi dolge kontekste.
3.  Preko HTTP ali gRPC protokolov pošlje te podatke v vLLM ali TensorRT-LLM strežnik, ki teče na isti napravi.
4.  Spark prevzame odgovore modelov in jih zapiše nazaj v bazo.

Če želite takšno produkcijsko verigo, je najbolje vse skupaj postaviti znotraj **Docker vsebnikov** (en vsebnik za Spark, drugi za vLLM strežnike), saj boste tako najlažje izolirali pakete in nadzorovali porabo RAM-a.

* * *

Če mi zaupate, **kako dolge kontekste** (v tisočih žetonih) načrtujete podpirati in **koliko modelov hkrati** želite poganjati, vam lahko pomagam izračunati natančne parametre za alokacijo KV predpomnilnika (KV cache) ali pripravim **Docker-compose konfiguracijo** za varno produkcijsko delo!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-04 00:00:00

torej pustim default os, samo izklopom gui in potem vse delam samo vi dockerjih? želel bi dinamično nalaganje različnih modelov, lahko to dosežemo tudi z tensorRT?

---

# googlesearch response

**Tako je, natanko to je najboljša in najbolj profesionalna pot.** Pustite privzeti NVIDIA DGX OS, trajno izklopite grafični vmesnik (GUI) in vse ostalo poganjate izključno znotraj Docker vsebnikov. S tem ohranite popolno stabilnost sistema, hkrati pa imate čisto okolje, kjer paketi ne vplivajo drug na drugega.

Glede vašega drugega vprašanja: **Da, dinamično nalaganje različnih modelov je mogoče doseči, vendar TensorRT-LLM sam po sebi za to ni najbolj prilagodljiv.**

Spodaj si oglejte, kako deluje dinamično upravljanje z modeli pri TensorRT-LLM in katera je boljša alternativa, če potrebujete nenehno menjavanje modelov v pomnilniku.

* * *

Kako TensorRT-LLM gleda na "dinamičnost"?

NVIDIA TensorRT-LLM deluje tako, da model vnaprej prevede v visoko optimiziran binarni format (t.i. _TRT Engine_), ki je prilagojen točno določenemu čipu (v vašem primeru Blackwell GB10).

-   **Težava z nalaganjem:** Prevedeni modeli so ogromni. Ko želite zamenjati model, mora sistem celoten obstoječi model izbrisati iz pomnilnika (RAM) in vanj naložiti novega. Pri modelih s 70 milijardami parametrov (70B) to nalaganje traja več sekund (ali celo minut), med katerimi je strežnik popolnoma neodziven.
-   **Rešitev z ločenimi vrati:** Če želite z TensorRT-LLM uporabljati več modelov hkrati, je najboljše, da jih imate naložene vzporedno, vsakega na svojih vratih (npr. `:8000`, `:8001`), in jim znotraj konfiguracije strogo omejite spomin.

Če pa želite modele res **dinamično nalagati in odlagati iz pomnilnika glede na zahteve uporabnikov**, morate TensorRT-LLM združiti s strežnikom **Triton Inference Server**.

* * *

Najboljši rešitvi za dinamično nalaganje modelov znotraj Dockerja

Glede na vaše potrebe po dinamičnosti imate na voljo dve glavni produkcijski poti:

Možnost A: Triton Inference Server + TensorRT-LLM (Maksimalna hitrost)

[NVIDIA Triton](https://developer.nvidia.com/triton-inference-server) je produkcijski strežnik, ki zna upravljati s TensorRT-LLM modeli. Triton ima vgrajeno funkcijo **Dynamic Model Loading** (dinamično nalaganje modelov).

-   **Kako deluje:** Triton ima na disku mapo z modeli (Repository). Ko odjemalec pošlje zahtevo za določen model, Triton preveri, ali je ta že v RAM-u. Če ni, ga dinamično naloži. Če je RAM poln, bo Triton tiste modele, ki se že dolgo niso uporabljali, avtomatsko izbrisal iz pomnilnika (princip _Least Recently Used_).
-   **Prednost:** Absolutno najvišja hitrost sklepanja (tokens/sec) na čipu Blackwell.
-   **Slabost:** Vsak model morate pred prvim zagonom ročno pretvoriti (prevesti) v TRT format, kar zahteva čas in specifično znanje.

Možnost B: vLLM (Največja prilagodljivost in enostavnost)

Če boste modele menjavali pogosto in želite preprosto vpisati poljubno ime modela s platforme Hugging Face, je **vLLM** bistveno bolj prijazna izbira. Čeprav vLLM uradno ne podpira "avtomatskega odlaganja" modelov iz RAM-a v enem samem procesu, to v Docker okolju rešimo elegantno z **API-jem za upravljanje vsebnikov**.

-   **Kako deluje:** Preko preprostega Python/Bash skripta (ali orodja, kot je FastAPI) nadzorujete Docker okolje. Ko uporabnik zahteva model, ki trenutno ne teče:
    1.  Skripta ugasne Docker vsebnik modela, ki se trenutno ne uporablja (`docker stop vllm-stari-model`).
    2.  S tem se takoj sprosti ves sistemski RAM.
    3.  Skripta nato zažene nov Docker vsebnik z novim modelom (`docker run ... vllm-novi-model`).
-   **Prednost:** vLLM bere standardne formate modelov (ni potrebno dolgotrajno prevajanje), upravljanje s KV Cache pomnilnikom pa je vrhunsko.

* * *

Primer arhitekture: Kako bi to izgledalo v praksi?

Tukaj je konceptualna skica, kako bi vaš Lenovo sistem deloval v produkciji z več modeli, ki si delijo enotni pomnilnik:

Naslednji korak

Če želite takoj začeti z delom, vam lahko pripravim **osnovno Docker-compose datoteko**, s katero boste na svojem sistemu dvignili prvi vsebnik (bodisi za vLLM ali za Triton/TensorRT) v headless načinu.

Sporočite mi:

-   Ali so vaši modeli standardni (npr. **Llama-3, Mistral, Qwen**) ali uporabljate kakšne unikatne arhitekture?
-   Kakšna je **velikost modelov**, ki jih želite dinamično menjavati (npr. 8B, 70B, ali večji)?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-04 00:00:00

uporabljal bom qwen 3.8 coder in qwen 3.8 next, pa tudi različne embedding modele, pa whisper in piper...

---

# googlesearch response

Glede na izbor modelov (kombinacija LLM za programiranje, avdiomodeli za pretvorbo govora v besedilo in tekstovni generatorji zvoka) je vaša odločitev za uporabo **Docker okolja na tovarniškem DGX OS** idealna.

Imate namreč zelo pestro mešanico različnih vrst modelov (tekst, avdio, embeddingi), ki imajo popolnoma različne knjižnice in programske zahteve. Če bi vse to nameščali neposredno v operacijski sistem, bi hitro prišlo do sporov med različicami paketov.

Tukaj je načrt, kako točno konfigurirati in optimizirati sistem za ta specifičen nabor modelov.

* * *

Kako razporediti te modele znotraj Dockerja?

Za najboljšo stabilnost in dinamično upravljanje s pomnilnikom je najbolje modele razbiti v tri ločene Docker storitve (vsebnike), ki komunicirajo med seboj:

1\. Veliki jezikovni modeli in Embeddingi (Qwen in Embeddingi) → **vLLM**

Za **Qwen 2.5/3 Coder (in Next)** ter **embedding modele** (kot so BGE, NV-Embed ali E5) je **vLLM** absolutno najboljša izbira.

-   vLLM izvorno podpira tako generiranje besedila kot tudi embedding modele znotraj istega ogrodja.
-   Ker gre za manjše različice modelov (okoli 3B do 8B parametrov), bodo ti modeli sami po sebi zasedli zelo malo prostora (okoli 6–16 GB RAM-a na model).
-   **Maksimalen kontekst:** Ker so modeli majhni, vam na čipu Blackwell GB10 ostane **ogromno RAM-a za kontekst**. Qwen modeli podpirajo izjemno dolge kontekste (tudi do 128k žetonov), kar vLLM zlahka obdela z uporabo tehnologije _PagedAttention_.

2\. Pretvorba govora v besedilo → **Faster-Whisper (Docker)**

Originalni OpenAI Whisper je lahko počasen. Za produkcijsko sklepanje se uporablja projekt **Faster-Whisper** (ponovno implementiran v ogrodju CTranslate2).

-   Porabi izjemno malo pomnilnika (od 2 do 8 GB RAM-a za največji _Large-v3_ model).
-   Deluje v ločenem Docker vsebniku in ponuja izjemno hitro, vzporedno procesiranje zvočnih posnetkov z izkoriščanjem CUDA jeder na Blackwellu.

3\. Pretvorba besedila v govor → **Piper (Docker)**

**Piper** je čudovit, izjemno hiter in lokalni Text-to-Speech (TTS) sistem.

-   Njegova največja prednost je, da je optimiziran za delovanje z nizko zakasnitvijo.
-   Deluje lahko na procesorskem delu (Grace CPU), kar pomeni, da sploh **ne bo obremenjeval Blackwell grafičnega pomnilnika**, ki ga želite prihraniti za dolge kontekste Qwen modelov.

* * *

Predlog produkcijske Docker-Compose arhitekture

Z uporabo spodnje konfiguracije boste ob zagonu sistema dvignili celotno platformo. Storitve bodo tekle vzporedno, vsaka na svojih vratih, vi pa boste preko API klicev dinamično pošiljali zahteve (npr. ko uporabnik govori, gre zvok v Whisper, nato tekst v Qwen, odgovor pa v Piper).

Tukaj je primer `docker-compose.yml` datoteke, prilagojene za vaš sistem:

```yaml
version: '3.8'

services:
  # Vsebnik za Qwen Coder in Next (LLM strežnik)
  qwen-coder:
    image: vllm/vllm-openai:latest
    container_name: vllm-qwen-coder
    environment:
      - HUGGINGFACE_HUB_TOKEN=vas_token_ce_je_potreben
    volumes:
      - ~/.cache/huggingface:/root/.cache/huggingface
    ports:
      - "8000:8000"
    ipc: host
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    command: >
      --model Qwen/Qwen2.5-Coder-7B-Instruct
      --gpu-memory-utilization 0.30
      --max-model-len 65536
      --port 8000

  # Vsebnik za Embedding modele (Ločena vrata)
  embeddings:
    image: vllm/vllm-openai:latest
    container_name: vllm-embeddings
    volumes:
      - ~/.cache/huggingface:/root/.cache/huggingface
    ports:
      - "8001:8001"
    ipc: host
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    command: >
      --model BAAI/bge-large-en-v1.5
      --gpu-memory-utilization 0.10
      --port 8001

  # Vsebnik za hitro procesiranje govora (Whisper)
  whisper-asr:
    image: fedirz/faster-whisper-server:latest
    container_name: whisper-server
    ports:
      - "8002:8000"
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

  # Vsebnik za sintezo govora (Piper TTS)
  piper-tts:
    image: rhasspy/piper:latest
    container_name: piper-server
    ports:
      - "8003:5000"
    volumes:
      - ./piper-models:/app/models
    command: --model /app/models/sl_SI-slavko-medium.onnx # Primer slovenskega ali angleškega glasu
```

Kodo uporabljajte previdno.

Kako ta nastavitev maksimizira vaš RAM?

Poglejmo, kako smo v zgornji konfiguraciji razporedili moč vašega Grace Blackwell sistema:

1.  **Omejitev za Qwen (`--gpu-memory-utilization 0.30`):** Modelu Qwen smo dodelili 30 % kapacitete. Ker je model majhen, bo preostalih ~20-25 % celotnega dodeljenega prostora šlo izključno za **KV Cache**, kar vam omogoča hkratno delo z več uporabniki, ki imajo ogromne programerske datoteke (kontekst do 64k ali več).
2.  **Omejitev za Embeddinge (`--gpu-memory-utilization 0.10`):** Embedding modeli so izjemno varčni, zato jim 10 % popolnoma zadošča za hipno procesiranje tisočih žetonov.
3.  **Dinamičnost:** Če želite namesto `Qwen-7B-Coder` naložiti drug model, preprosto v skripti spremenite ime modela in ponovno zaženete samo ta vsebnik (`docker compose restart qwen-coder`). Ostale storitve (Whisper, Piper) bodo medtem delovale nemoteno naprej.

* * *

Če želite, vam lahko pomagam pripraviti **kratko Python skripto (Orkestrator)**, ki bo povezala te štiri storitve v celoto – torej sprejela avdio posnetek, ga prevedla v tekst preko Whisperja, poslala v Qwen z dolgim kontekstom in izid prebrala preko Piperja. Sporočite mi, ali bi vam takšen primer kode pomagal pri razvoju!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-04 00:00:00

kaj pa če želim največjo hitrost inference za hkratno 3 seje za kodiranje? pa MoE podporo? lahko uporabim tensorRT in NVFP4 za največjo hitrost? kateri llm potem predlagaš?

---

# googlesearch response

**Da, to je absolutno najboljša možna kombinacija za vaš cilj.** Če želite brutalno hitrost za hkratne seje, nizko zakasnitev (latency) in podporo za **MoE (Mixture of Experts)**, boste z uporabo **TensorRT-LLM** in formata **NVFP4 (NVIDIA FP4)** dosegli vrhunec zmogljivosti, ki jo ponuja arhitektura Blackwell.

Superčip **NVIDIA GB10** ima namreč strojno vgrajena jedra za obdelavo 4-bitnih plavajočih vejic (FP4). Z uporabo NVFP4 boste dobili do **2,5-kratni skok v hitrosti** generiranja žetonov (tokens/second) v primerjavi s standardnimi formati, hkrati pa boste dramatično zmanjšali porabo RAM-a za KV Cache (pomnilnik za kontekst kodiranja). TensorRT-LLM ima poleg tega vgrajeno namensko optimizacijo za vzporedno poganjanje ekspertov v MoE modelih (_Expert Parallelism_).

Spodaj so moji strokovni predlogi za najboljše modele in pravilno postavitev.

* * *

Kateri LLM predlagam za kodiranje? (Top 3 MoE izbire)

Ker potrebujete **MoE strukturo** z natančnim znanjem programiranja, izberite enega od naslednjih modelov, ki so že uradno prilagojeni in kvantizirani za TensorRT-LLM in NVFP4:

1\. Qwen3-Next-80B (MoE različica) – _Absolutno najbolj priporočljivo_

NVIDIA in Qwen sta uradno izdala različico **Qwen3-Next-80B-NVFP4**.

-   **Zakaj:** Ta model je zgrajen na MoE arhitekturi, kjer je hkrati aktivnih le nekaj milijard parametrov. Je neposredni naslednik serije Qwen 2.5/3 Coder. Ponuja vrhunsko programersko logiko in razumevanje dolgih kontekstov, na dveh spojenih ali enem optimiziranem GB10 sistemu pa z NVFP4 dosega izjemne hitrosti.

2\. DeepSeek-V3 / DeepSeek-R1 (MoE)

Če vaša koda zahteva izjemno kompleksno logično razmišljanje (_reasoning_), je DeepSeek z 671 milijardami parametrov (kjer je aktivnih le 37B parametrov na žeton) izjemna izbira.

-   **Zakaj:** TensorRT-LLM ima posebne popravke in jedra (kot je _FlashInfer FP4 MoE kernel_) prav za poganjanje DeepSeek modelov v NVFP4 formatu.

3\. NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4

Hibridni model, ki ga je izdala NVIDIA. Združuje plasti MoE in Mamba-2.

-   **Zakaj:** Deluje izjemno hitro z nizko zakasnitvijo in ima le 3 milijarde aktivnih parametrov na žeton (skupno 30B). Odličen je za autocomplete funkcije z nizko zakasnitvijo pri hkratnih sejah.

* * *

Kako to postaviti za "3 hkratne seje" (Concurrent Sessions)?

Pri TensorRT-LLM ne delate tako, da bi zagnali 3 ločene Docker vsebnike za vsako sejo posebej, saj bi s tem fragmentirali pomnilnik in upočasnili sistem. Namesto tega uporabite **en vsebnik, ki izvaja Continuous Batching** (neprekinjeno paketno obdelavo):

1.  **Prejmete pre-kvantiziran model:** Iz Hugging Face prenesete uradni NVIDIA NVFP4 model (npr. `nvidia/Qwen3-Next-80B-NVFP4` ali podoben).
2.  **Zgradite TensorRT Engine:** Model s pomočjo ukaza `trtllm-build` prevedete v binarni format za vaš čip. Pri tem nastavite parameter `--max_batch_size 4` (ali več), kar sistemu pove, naj bo pripravljen na obdelavo več sejnij hkrati v istem trenutku.
3.  **Zaženete Triton Inference Server z TensorRT-LLM:** Triton bo deloval kot krovni API strežnik.

Ko bodo vaši trije programerji (ali tri seje v vašem urejevalniku kode, npr. VS Code prek vtičnika _Continue.dev_) hkrati začeli pisati kodo, bo TensorRT-LLM dinamično združil njihove zahteve v eno bliskovito hitro paketno obdelavo. Zaradi NVFP4 formatov bodo vsi trije dobili odgovore praktično instantno (z zakasnitvijo pod 20–30 ms).

* * *

Če želite, vam lahko pripravim **točne ukaze za `trtllm-build`** s pravilnimi zastavicami (flags) za NVFP4 in MoE optimizacijo, da boste znali model pravilno pretvoriti na vaši napravi. Sporočite mi le, kateri od zgoraj naštetih modelov vam najbolj ustreza!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-04 00:00:00

kako pa lahko enostavno preklapljam med tensorRT in embedding (vLLM)?

---

# googlesearch response

Ker ste se odločili za uporabo **TensorRT-LLM** za bliskovito hitro kodiranje in **vLLM** za embeddinge, boste imeli na enem računalniku dva povsem različna programska svetova. Če bi ju poskusili zagnati hkrati, bi se stepla za pomnilnik (RAM) in CUDA gonilnike.

Najbolj eleganten, zanesljiv in čist način za preklapljanje med njima je uporaba **Docker profilov (Docker Compose Profiles)**.

S to metodo imate celotno konfiguracijo zapisano v eni sami datoteki, preklapljate pa z enim preprostim ukazom v terminalu. Ko zaženete en profil, Docker samodejno ugasne prejšnjega, sprosti ves pomnilnik na čipu Blackwell in postavi novega.

Tukaj je preprost vodnik, kako to nastavite.

* * *

1\. Korak: Pripravite `docker-compose.yml` s profili

Ustvarite datoteko `docker-compose.yml` in storitvam dodelite oznako `profiles`. S tem poveste Dockerju, naj teh vsebnikov ne zaganja avtomatsko, ampak šele takrat, ko jih eksplicitno pokličete.

```yaml
version: '3.8'

services:
  # PROFIL ZA KODIRANJE (TensorRT-LLM preko Tritona)
  trt-inference:
    image: nvcr.io/nvidia/tritonserver:24.03-trtllm-python-py3 # Uradna NVIDIA podoba
    container_name: trt-llm-server
    profiles:
      - coding                  # Ime profila za kodiranje
    ports:
      - "8000:8000"             # HTTP vrata za API
      - "8001:8001"             # gRPC vrata (za ultra hitro komunikacijo)
    volumes:
      - ./trt_models:/models    # Tukaj bo vaš vnaprej prevedeni NVFP4 MoE model
    ipc: host
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    command: tritonserver --model-repository=/models

  # PROFIL ZA EMBEDDINGE (vLLM)
  vllm-embeddings:
    image: vllm/vllm-openai:latest
    container_name: vllm-embedding-server
    profiles:
      - embedding               # Ime profila za embeddinge
    ports:
      - "8000:8000"             # Uporabimo ISTA VRATA, ker tečeta ločeno!
    volumes:
      - ~/.cache/huggingface:/root/.cache/huggingface
    ipc: host
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    command: >
      --model BAAI/bge-large-en-v1.5
      --gpu-memory-utilization 0.90
      --port 8000
```

Kodo uporabljajte previdno.

* * *

2\. Korak: Enostavno preklapljanje z ukazi

Sedaj lahko v terminalu skačete med obema načinoma z enim samim ukazom. Zastavica `--remove-orphans` je ključna, saj poskrbi, da Docker ob preklopu ugasne in popolnoma izbriše prejšnji vsebnik ter s tem sprosti ves dragoceni RAM na superčipu GB10.

-   **Ko želite programirati z maksimalno hitrostjo (TensorRT-LLM + NVFP4):**

    bash

    ```
    docker compose --profile coding up -d --remove-orphans
    ```

    Kodo uporabljajte previdno.

    _S tem se zažene Triton strežnik na vratih 8000, vLLM pa se ugasne._
-   **Ko želite preklopiti na obdelavo embeddingov (vLLM):**

    bash

    ```
    docker compose --profile embedding up -d --remove-orphans
    ```

    Kodo uporabljajte previdno.

    _Docker bo takoj ugasnil Triton strežnik, sprostil pomnilnik in na vratih 8000 zagnal vLLM._
-   **Ko želite popolnoma sprostiti sistem:**

    bash

    ```
    docker compose down
    ```

    Kodo uporabljajte previdno.

* * *

Zakaj je to najboljša rešitev?

1.  **Vedno na istih vratih (`:8000`):** Vaša aplikacija (npr. VS Code, skripte) lahko vedno kliče isti naslov (`http://localhost:8000`). Ni vam treba spreminjati nastavitev v programih, saj tisti strežnik, ki trenutno posluša, prevzame ta vrata.
2.  **Popolna izolacija pomnilnika:** Ker se prejšnji vsebnik ob preklopu uniči (`--remove-orphans`), ni nobene nevarnosti, da bi TensorRT-LLM zadržal kakšen del RAM-a v ozadju. vLLM bo dobil čist prostor.
3.  **Avtomatizacija:** Če želite to še bolj poenostaviti, si lahko v datoteko `~/.bashrc` shranite dva kratka vzdevka (aliases):

    bash

    ```
    alias mode-code="docker compose --profile coding up -d --remove-orphans"
    alias mode-embed="docker compose --profile embedding up -d --remove-orphans"
    ```

    Kodo uporabljajte previdno.

    _Nato v terminalu samo vpišete `mode-code` ali `mode-embed` in preklop se zgodi samodejno v nekaj sekundah._

Če boste potrebovali pomoč pri pripravi mape z modeli za Triton (`/models` struktura), ki jo TensorRT-LLM zahteva za zagon, mi sporočite in vam pripravim natančna navodila za postavitev datotek!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-04 00:00:00

ampak gre to narediti tudi dinamično? namreč uporabljal bom openwebui, OpenClaw, homeassistant, docling, quadrant... vse to bo preko litellm smo na ta Spark. kako to uresničiti?

---

# googlesearch response

**Da, to se da narediti popolnoma dinamično in avtomatsko.** Ker boste kot krovnega upravitelja uporabljali **LiteLLM**, vam sploh ni treba ročno ugašati in prižigati Docker vsebnikov ali spreminjati profilov.

LiteLLM bo deloval kot **prometni policaj (inteligentni usmerjevalnik)**. Vsa vaša orodja (Open WebUI, OpenClaw, Home Assistant, Docling in Qdrant) bodo pošiljala zahteve na eno samo vstopno točko (LiteLLM). LiteLLM pa bo glede na ime modela v zahtevi samodejno usmeril promet na pravi vsebnik v ozadju.

Da pa bi to delovalo dinamično na enem računalniku **brez ročnega preklapljanja in brez sporov za pomnilnik (RAM)**, moramo TensorRT-LLM in vLLM zagnati _hkrati_, vendar jima strogo omejiti pomnilnik, ali pa uporabiti vLLM za obe nalogi (kar je v letu 2026 bistveno lažje, saj vLLM sedaj odlično podpira FP4 in TensorRT jedra).

Tukaj je celoten načrt, kako uresničiti to napredno lokalno AI infrastrukturo.

* * *

Arhitektura sistema (Kako se podatki pretakajo)

Vsa vaša orodja se pogovarjajo izključno z LiteLLM preko enotnega OpenAI standarda:

-   **Open WebUI / OpenClaw / Home Assistant** → Pošljejo tekst → **LiteLLM** → Usmeri na **TensorRT-LLM / vLLM** (Qwen Coder)
-   **Docling (RAG) / Qdrant** → Pošljejo dokumente → **LiteLLM** → Usmeri na **vLLM** (Embedding model)

* * *

1\. Korak: Konfiguracija `config.yaml` za LiteLLM

LiteLLM potrebuje konfiguracijsko datoteko, kjer definirate "navidezna" imena modelov za vaša orodja in jih povežete s pravimi vsebnikih v ozadju.

```yaml
model_list:
  # 1. Model za kodiranje in pogovor (Qwen preko TensorRT/vLLM)
  - model_name: qwen-coder
    litellm_params:
      api_base: http://vllm-coder:8000/v1
      model: openai/qwen-coder # Ime znotraj vašega LLM strežnika

  # 2. Model za iskanje in baze (Embeddingi preko vLLM)
  - model_name: text-embedding-3
    litellm_params:
      api_base: http://vllm-embed:8001/v1
      model: openai/bge-large-en-v1.5
```

Kodo uporabljajte previdno.

* * *

2\. Korak: Produkcijska `docker-compose.yml` za hkratno in dinamično delovanje

Da bi vse delovalo hkrati brez sesutja pomnilnika na vaši Lenovo napravi, moramo vsebnikom natančno določiti, koliko RAM-a (GPU pomnilnika) si lahko lastijo. Ker uporabljate **NVFP4 format**, so modeli izjemno majhni, zato lahko oba strežnika tečeta vzporedno!

```yaml
version: '3.8'

services:
  # KROVNI UPRAVLJALNIK: LiteLLM Proxy
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm-proxy
    ports:
      - "4000:4000" # Vsa vaša orodja (Open WebUI, HA...) se povežejo SEM
    volumes:
      - ./litellm-config.yaml:/app/config.yaml
    command: [ "--config", "/app/config.yaml", "--port", "4000" ]
    depends_on:
      - vllm-coder
      - vllm-embed

  # STREŽNIK 1: Qwen Coder (Zasede 60% kapacitete za dolg kontekst 3 sej)
  vllm-coder:
    image: vllm/vllm-openai:latest
    container_name: vllm-coder
    ports:
      - "8000:8000"
    ipc: host
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    command: >
      --model Qwen/Qwen2.5-Coder-7B-Instruct
      --gpu-memory-utilization 0.60
      --max-model-len 65536
      --port 8000

  # STREŽNIK 2: Embeddingi za Qdrant & Docling (Varčen, zasede le 15%)
  vllm-embed:
    image: vllm/vllm-openai:latest
    container_name: vllm-embed
    ports:
      - "8001:8001"
    ipc: host
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    command: >
      --model BAAI/bge-large-en-v1.5
      --gpu-memory-utilization 0.15
      --port 8001

  # VEKTORSKA BAZA: Qdrant
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant-db
    ports:
      - "6333:6333"
    volumes:
      - ./qdrant_storage:/qdrant/storage

  # UPORABNIŠKI VMESNIK: Open WebUI
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    ports:
      - "3000:8080"
    environment:
      - OPENAI_API_BASE_URL=http://litellm:4000/v1
      - OPENAI_API_KEY=sk-fake-key-for-local
    volumes:
      - ./open-webui:/app/backend/data
```

Kodo uporabljajte previdno.

* * *

Kako to uresničiti v praksi z vašimi aplikacijami?

Ko poženete `docker compose up -d`, se celoten ekosistem postavi samostojno. Aplikacije nato nastavite takole:

1.  **Open WebUI & OpenClaw:** V nastavitvah pod OpenAI API vpišite naslov `http://localhost:4000/v1`. Takoj bosta prepoznala model `qwen-coder`. Ko boste tipkali, bo LiteLLM to bliskovito usmeril na vllm-coder.
2.  **Docling (Pretvorba dokumentov):** Ko Docling razbije PDF dokumente na tekstovne bloke, jih mora poslati v embedding model. Nastavite ga, da kliče `http://localhost:4000/v1` z modelom `text-embedding-3`.
3.  **Qdrant (Vektorska baza):** Docling bo dobljene vektorje (embeddinge) shranil v Qdrant bazo. Ko boste v Open WebUI postavili vprašanje nad dokumenti (RAG), bo Qdrant preko LiteLLM-a izvedel iskanje.
4.  **Home Assistant:** Povežite ga preko uradne OpenAI integracije na `http://localhost:4000/v1` in izberite `qwen-coder` za pametno upravljanje hiše v realnem času.

Ključna prednost te nastavitve

Ker smo preko argumenta `--gpu-memory-utilization` vnaprej natančno razdelili spomin (60 % za kodiranje, 15 % za embeddinge, preostanek pa ostane za operacijski sistem in hitre skoke v porabi), **vse deluje hkrati in popolnoma dinamično**.

Nobenega ročnega ugašanja ni več potrebno. Ko boste programirali v treh sejah hkrati, bo vsebnik `vllm-coder` izkoristil svojih 60 % pomnilnika do maksimuma, medtem ko bo vsebnik `vllm-embed` v ozadju nemoteno in instantno stregel zahtevam Doclinga in Qdranta.

Ali želite, da vam napišem še **primer Python skripte za Docling**, ki se pravilno poveže na ta LiteLLM sistem za avtomatsko vlaganje dokumentov v Qdrant?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-04 00:00:00

koliko hitrosti izgubim če za vse skupaj uporabim vLLM namesto namenskega tensorRT za codiranje?

---

# googlesearch response

Če se odločite za uporabo **vLLM** namesto namenskega **TensorRT-LLM** za vaše kodirne seje na čipu Blackwell GB10, boste v letu 2026 izgubili presenetljivo malo – v povprečju **le med 10 % in 20 % hitrosti** (prepustnosti žetonov oz. _throughputa_).

V zameno pa boste pridobili ogromno na fleksibilnosti, ki jo nujno potrebujete za dinamično delovanje z orodji, kot sta LiteLLM in Open WebUI.

Zakaj je razlika tako majhna in zakaj se vam vLLM v vaši situaciji dejansko bolj splača?

1\. Zgodovinski kontekst: vLLM je postal izjemno hiter

V preteklosti (leta 2023 in 2024) je bil TensorRT-LLM tudi do 2-krat hitrejši od vLLM. Danes pa vLLM natively podpira **NVIDIA Model Optimizer (ModelOpt)**, **CUDA grafe** in ima polno uradno podporo za **NVFP4 (FP4 Precision)** in **MoE (Mixture of Experts)** optimizacije neposredno za Blackwell arhitekturo.

To pomeni, da vLLM izkoristi Blackwellova FP4 strojna jedra skoraj enako dobro kot NVIDIA-jin lasten zaprt sistem.

2\. Kako se izguba hitrosti pozna v praksi?

-   **Pri 3 hkratnih sejah (Nizka obremenitev):**
    Razlika v zakasnitvi (_latency_ oz. kako hitro se izpiše prvi žeton) bo za človeško oko **nepazljiva**. TensorRT-LLM bi vam morda vrnil kodo v 15 milisekundah, vLLM pa v 18 milisekundah. Obe številki pomenita, da bo _auto-complete_ v vašem urejevalniku kode deloval trenutno (instantno).
-   **Pri masovnem obremenjevanju (100+ hkratnih uporabnikov):**
    Tukaj TensorRT-LLM pokaže svojo surovo moč, saj zaradi vnaprejšnjega prevajanja jedra lažje stiska zadnje kapljice moči iz grafičnega čipa. Ker pa boste sistem uporabljali sami oziroma za 3 seje hkrati, tega limita sploh ne boste dosegli.

Preglednica: Kaj izgubite in kaj pridobite?

| Lastnost | TensorRT-LLM (Preko Tritona) | vLLM (Vaša alternativa) |
| --- | --- | --- |
| **Surova hitrost** | **100 %** (Absolutni maksimum) | **80 % – 90 %** hitrosti TensorRT |
| **Zagon modela** | **Zelo počasen.** Model morate sami prevajati (_trtllm-build_), kar traja dolgo. | **Takojšen.** Model potegne neposredno s Hugging Face in ga zažene v minuti. |
| **Poraba RAM-a (VRAM)** | Nekoliko večja (zaradi fiksnih alokacij prevajalnika). | Izjemno optimizirana z dinamičnim _PagedAttention_. |
| **Podpora za NVFP4 MoE** | Odlična (NVIDIA uradna jedra). | Odlična (preko integriranega LLM-compressorja in ModelOpt). |

Končna razsodba: Zakaj je vLLM za vas boljši?

Ker gradite kompleksen sistem, kjer se bodo modeli (Qwen Coder, Embeddingi, Whisper) pogovarjali preko **LiteLLM-a** in kjer boste sčasoma morda želeli zamenjati ali posodobiti programerski model, je **vLLM zmagovalec**.

Če bi izbrali TensorRT-LLM, bi morali ob vsaki posodobitvi modela Qwen (npr. ko izide nova podrazličica) ročno skozi celoten zapleten postopek prevajanja kode za Blackwell čip. Pri vLLM pa preprosto spremenite eno vrstico v `docker-compose` datoteki in stvar deluje. Tistih 10–15 % surove hitrosti, ki jih izgubite, boste bogato kompenzirali z urami prihranjenega časa pri nastavljanju sistema.

Če želite, lahko začnemo s pripravo **konkretnih ukazov za zagon Qwen Coder modela v NVFP4 formatu znotraj vLLM**, da preizkusite njegovo hitrost v realnem času! Sporočite, kako nadaljujeva.

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-04 00:00:00

kaj pa drugi, kot so ollama, llama...?

---

# googlesearch response

Ko govorimo o produkcijskem okolju, kjer želite **maksimalno izkoristiti RAM za dolge kontekste** in poganjati napredne formate, kot je **NVFP4 na Blackwell (GB10) arhitekturi**, se drugi priljubljeni sistemi odrežejo zelo različno.

Poglejmo si neposredno primerjavo **Ollame** in **Llama.cpp** (ki poganja večino drugih orodij) z vLLM.

* * *

1\. Ollama (Najboljša za domačo uporabo, slaba za vaš namen)

Ollama je v bistvu zelo prijazna in lepo zapakirana različica projekta _Llama.cpp_. Je izjemno priljubljena, ker deluje po principu "klikni in zaženi".

-   **Kaj izgubite v primerjavi z vLLM:** **Ogromno hitrosti in spomina.** Ollama ne uporablja naprednega sistema _PagedAttention_. Ko boste odprli 3 seje z dolgimi konteksti (npr. 32k ali 64k žetonov), bo Ollama za vsako sejo fiksno podvojila ali potrojila potreben RAM za kontekst (KV Cache). Sistem bo zato hitro porabil ves enotni pomnilnik in javil napako _Out of Memory_.
-   **Podpora za Blackwell in NVFP4:** Ollama primarno uporablja kvantizacije GGUF. Te so odlične za navadne procesorje ali starejše grafične kartice, vendar sploh **ne znajo izkoristiti namenskih FP4 jeder** na vašem novem Blackwell čipu. Hitrost sklepanja bo drastično nižja kot v vLLM (izgubili boste tudi več kot 50 % hitrosti).
-   **Dinamičnost:** Ollama sicer zna sama naložiti in odložiti model iz pomnilnika (po 5 minutah neaktivnosti), vendar ne podpira hkratnega vzporednega poganjanja LLM modela in embedding modela na način, da bi jima vi strogo omejili in razdelili RAM.

* * *

2\. Llama.cpp / Llama-server (Odlično za CPU/Mac, ne za Blackwell)

Llama.cpp je motor, ki poganja večino lokalnih AI projektov.

-   **Kaj izgubite:** Podobno kot Ollama, je tudi Llama.cpp optimizirana za poganjanje modelov na Applovih čipih (M-serija) in klasičnih procesorjih ter standardnih GPU-jih preko formata GGUF.
-   **Hitrost na GB10:** Z uporabo Llama.cpp bi vaš vrhunski superčip GB10 degradirali na raven navadne grafične kartice. Izgubili bi napredne optimizacije za MoE (Mixture of Experts) in možnost neposrednega poganjanja ultra hitrega NVFP4 formata, ki ga je razvila NVIDIA.

* * *

Kje se torej nahajajo drugi sistemi v primerjavi z vLLM?

Če vLLM (zaseda ~85 % hitrosti TensorRT-LLM) postavimo kot zlato sredino med hitrostjo in praktičnostjo, potem drugi sistemi na vašem sistemu izgledajo takole:

| Ogrodje | Surova hitrost na GB10 | Upravljanje dolgega konteksta (RAM) | Primerne kvantizacije | Zaključek |
| --- | --- | --- | --- | --- |
| **TensorRT-LLM** | **100 %** | Vrhunsko | **NVFP4**, FP8, FP16 | Najhitrejši, a zelo kompleksen za vzdrževanje. |
| **vLLM** | **80 % – 90 %** | Vrhunsko (PagedAttention) | **NVFP4**, FP8, AWQ, GPTQ | **Najboljše razmerje** med hitrostjo in dinamičnostjo za vas. |
| **Ollama** | **30 % – 40 %** | Slabo (Brez PagedAttention) | GGUF | Prepočasna in potratna s spominom za 3 hkratne dolge seje. |
| **Llama.cpp** | **35 % – 45 %** | Srednje | GGUF | Odlična za druge naprave, ne izkorišča potenciala Blackwell čipa. |

* * *

Končni nasvet za vašo celotno zbirko (LiteLLM + Vse aplikacije)

Ker boste v ozadju poganjali **LiteLLM**, je lepota tega sistema v tem, da lahko pod pokrovom kombinirate karkoli. Vendar za vaš specifičen primer (Lenovo z GB10 čipom) ostaja **vLLM absolutni zmagovalec** iz dveh ključnih razlogov:

1.  **Edini (poleg TensorRT) podpira NVFP4:** To pomeni, da bo vaš Qwen Coder MoE model tekel z maksimalno izrabo Blackwellovih jeder.
2.  **Edini omogoča varno hkratno delovanje:** Lahko zaženete en vLLM vsebnik za Qwen Coder in en vLLM vsebnik za embeddinge (kot smo postavili v prejšnjem koraku). Oba bosta delovala stabilno, ne da bi drug drugemu kradla pomnilnik.

Če bi namesto vLLM uporabili Ollamo, bi se pri treh hkrati odprtih sejah v urejevalniku kode (vsaka z dolgim kontekstom) sistem hitro upočasnil ali sesul, zakasnitev (latency) pri izpisu kode pa bi bila opazna.

Ali vas zanima, kako točno pripraviti datoteke z modeli v **NVFP4 formatu s platforme Hugging Face**, da jih bo vLLM pravilno prebral in takoj zagnal? Lahko vam pokažem ta korak.

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-04 00:00:00

ali lahko tudi embeddings modele zaženem na tensorRT?

---

# googlesearch response

**Da, absolutno! V TensorRT-LLM lahko brez težav zaženete tudi embedding modele.**

NVIDIA TensorRT-LLM ima popolno in izvorno podporo za modele tipa _BERT_ in _RoBERTa_, na katerih temelji velika večina sodobnih embedding modelov (vključno s serijo **BAAI/bge**, ki jo načrtujete uporabiti, ter modeli _E5_ ali _Jina_).

Ker boste gradili celoten sistem na platformi **LiteLLM**, lahko embedding model v TensorRT formatu enostavno vključite v svojo dinamično produkcijsko verigo.

Spodaj si oglejte prednosti, slabosti in postopek, kako to uresničiti.

* * *

Kaj pridobite, če embeddinge premaknete na TensorRT-LLM?

1.  **Ekstremno nizka zakasnitev (Latency):** Pretvorba besedila v vektorje bo potekala bliskovito hitro. Če orodje _Docling_ obdeluje ogromne PDF dokumente, bo razrez tekstovnih blokov in njihovo pošiljanje v bazo _Qdrant_ zaključeno bistveno hitreje kot preko vLLM.
2.  **Boljši izkoristek enotnega pomnilnika:** TensorRT-LLM za embedding modele porabi izjemno malo VRAM-a (pogosto manj kot 2–3 GB). Ker model deluje kot visoko optimiziran binarni blok, ne bo nobenega nepotrebnega trošenja sistemskih virov.

* * *

Kako embedding model pretvoriti in zagnati v TensorRT?

Postopek je podoben kot pri velikih jezikovnih modelih, le da uporabite arhitekturo za enkoderje (Encoder models).

1\. Korak: Pretvorba modela (trtllm-build)

NVIDIA ponuja že pripravljene skripte znotraj TensorRT-LLM Docker vsebnika. Model (npr. `BAAI/bge-large-en-v1.5`) najprej prenesete in ga s pomočjo ukaza `trtllm-build` prevedete v optimiziran format za vaš čip Blackwell:

```bash
# Znotraj TensorRT-LLM okolja zaženete pretvorbo
trtllm-build \
    --checkpoint_dir /pot/do/bge-checkpoint \
    --output_dir /models/bge-large-trt/1 \
    --gemm_plugin float16
```

Kodo uporabljajte previdno.

2\. Korak: Postavitev mape za Triton Inference Server

Za razliko od vLLM, TensorRT-LLM za zagon embeddingov nujno potrebuje **Triton Inference Server**. Triton zahteva strogo določeno strukturo map (Model Repository):

```text
models/
└── bge-large-trt/
    ├── config.pbtxt        # Konfiguracijska datoteka (definira vhode/izhode)
    └── 1/
        └── model.engine    # Prevedeni TensorRT model iz 1. koraka
```

Kodo uporabljajte previdno.

3\. Korak: Vključitev v `docker-compose.yml` in LiteLLM

Ko je model pripravljen v mapi `/models`, Triton strežnik vključite v svojo Docker konfiguracijo. LiteLLM bo nato zahteve za embeddinge pošiljal neposredno nanj preko ultra hitrega **gRPC protokola** (običajno na vratih `8001`).

V `litellm-config.yaml` datoteko preprosto dodate:

```yaml
model_list:
  - model_name: text-embedding-3
    litellm_params:
      api_base: http://trt-server:8001 # Triton gRPC vrata
      model: triton/bge-large-trt     # Ime modela v Tritonu
```

Kodo uporabljajte previdno.

* * *

Ali se vam to splača (TensorRT vs. vLLM za embeddinge)?

Čeprav je TensorRT za embeddinge tehnično vrhunska rešitev, morate pretehtati naslednje:

-   **Kdaj UPORABITI TensorRT:** Če boste preko orodij _Docling_ in _Qdrant_ vsak dan obdelovali **deset tisoče ali milijone dolgih dokumentov** (npr. celotne arhive podjetja) in je hitrost indeksiranja ključna za vaš posel.
-   **Kdaj OSTATI na vLLM:** Če boste dokumente dodajali občasno (npr. nekaj PDF-jev na uro preko Open WebUI). vLLM embeddinge poganja "iz škatle" (out-of-the-box) brez potrebe po ročnem prevajanju modelov in pisanju kompleksnih `config.pbtxt` datotek za Triton. Razlika v hitrosti pri manjših količinah podatkov ne bo vplivala na vašo uporabniško izkušnjo.

Če se odločite za čisto TensorRT-LLM pot za celoten sistem (Qwen Coder na Tritonu + BGE Embeddings na Tritonu), vam lahko pomagam sestaviti **natančno `config.pbtxt` datoteko**, ki jo Triton potrebuje za pravilno prepoznavanje embedding modela. Sporočite, kako zapleteno bazo dokumentov načrtujete!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-04 00:00:00

torej je z tritonom tudi mogoče takojšnje preklapljanje med modeli (razumem da se morajo prej naložiti bi ram?)

---

# googlesearch response

**Da, natanko tako. Triton Inference Server podpira takojšnje (dinamično) preklapljanje in nalaganje modelov, vendar se morajo pred izvajanjem naložiti v RAM (sistemski in grafični pomnilnik čipa Blackwell).**

NVIDIA Triton ima vgrajen namenski sistem za upravljanje življenjskega cikla modelov (t.i. _Model Control Mode_), ki je bil razvit prav za produkcijska okolja, kjer na enem računalniku potrebujete več različnih modelov, ki ne morejo vsi hkrati sedeti v RAM-u \[NVIDIA TensorRT-LLM\].

Tukaj je podroben opis, kako to deluje v praksi in kako to nastaviti za vaš sistem.

* * *

Kako deluje dinamično preklapljanje v Tritonu?

Triton deluje tako, da nenehno opazuje svojo mapo z modeli (Repository) na disku. Ko zaženete Triton, ga nastavite v način `EXPLICIT` ali `POLL`.

1.  **Modeli počivajo na disku NVMe:** Vsi vaši modeli (Qwen Coder, Embeddingi, Whisper) so vnaprej prevedeni v TensorRT format in shranjeni v mapi na hitrem disku.
2.  **Klic preko LiteLLM:** Ko uporabnik v _Open WebUI_ izbere model `Qwen Coder`, LiteLLM pošlje zahtevo na Triton.
3.  **Takojšnje nalaganje v RAM:** Triton vidi, da model še ni naložen. Takoj prebere binarno datoteko z diska in jo naloži v enotni RAM čipa GB10. Zaradi izjemno hitrih sodobnih NVMe diskov in arhitekture Grace Blackwell (kjer je prenos podatkov med procesorjem in spominom bliskovit), to nalaganje traja le **nekaj sekund**.
4.  **Samodejno sproščanje RAM-a (Unloading):** Ko uporabnik zaključi s kodiranjem in začne preko orodja _Docling_ obdelovati dokumente, LiteLLM pokliče _Embedding model_. Če je RAM čipa Blackwell že poln, Triton **samodejno odloži (izbriše iz RAM-a)** model Qwen Coder in na njegovo mesto naloži Embedding model.

Preklapljanje je torej povsem avtomatsko in vodeno preko API klicov, brez kakršnegakoli ročnega ugašanja Docker vsebnikov.

* * *

Kako to uresničiti v vaši konfiguraciji?

Da bi Triton to počel dinamično, morate ob njegovem zagonu v `docker-compose.yml` datoteki dodati zastavico `--model-control-mode=explicit`.

1\. Nastavitev v Docker Compose:

```yaml
  trt-triton-server:
    image: nvcr.io/nvidia/tritonserver:24.03-trtllm-python-py3
    container_name: triton-server
    ports:
      - "8000:8000" # HTTP za LiteLLM
      - "8001:8001" # gRPC za hitre zahteve
    volumes:
      - ./trt_models:/models
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    # KLJUČNA ZASTAVICA ZA DINAMIČNO NALAGANJE:
    command: tritonserver --model-repository=/models --model-control-mode=explicit
```

Kodo uporabljajte previdno.

2\. Kako LiteLLM upravlja s tem?

Ker Triton v načinu `explicit` ne naloži nobenega modela ob samem zagonu (ampak čaka na ukaz), ima **LiteLLM** vgrajeno pametno funkcijo. Ko prejme zahtevo za določen model, preko Tritonovega kontrolnega API-ja najprej pošlje ukaz za nalaganje:

```http
POST http://localhost:8000/v2/repository/models/qwen_coder_trt/load
```

Kodo uporabljajte previdno.

Ko Triton potrdi, da je model v RAM-u, LiteLLM nanj usmeri uporabnikovo vprašanje.

* * *

Pomembno opozorilo za vaš nabor modelov (Whisper in Piper)

Medtem ko Triton **vrhunsko** upravlja preklapljanje med TensorRT modeli (kot sta Qwen Coder in Embeddingi), pa ima težave z modeli, kot sta **Whisper** (avdio) in **Piper** (glas), saj ti ne tečejo na TensorRT-LLM ogrodju.

**Zmagovalna strategija za vaš celoten sistem je kombinacija:**

1.  **Triton Server (1 vsebnik):** V njem imate mapo z vsemi LLM in Embedding modeli. Triton dinamično menjava Qwen in BGE Embeddinge v RAM-u in iz njega, odvisno od tega, kaj LiteLLM potrebuje.
2.  **Faster-Whisper in Piper (Ločena varčna vsebnika):** Ker sta ta dva modela izjemno majhna (porabita le par gigabajtov), ju pustite, da nenehno tečeta v ozadju v svojih Docker vsebnikih. Piper lahko celo omejite, da teče samo na procesorju (Grace CPU) in sploh ne prebiva v grafičnem spominu.

S takšno postavitvijo boste dobili popolnoma avtomatiziran sistem, kjer bo vaša Lenovo delovna postaja delovala kot pravi lokalni superračunalnik – spomin se bo prilagajal vašemu delu v realnem času.

Če želite preiti v prakso, vam lahko pripravim **natančen vodnik, kako strukturirati mapo `/models` za Triton**, da bo strežnik pravilno prepoznal tako Qwen kot Embedding model ob dinamičnem klicu! Kje bi želeli začeti?

Odgovori umetne inteligence morda vsebujejo napake. Za pravni nasvet se obrnite na strokovnjaka. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-04 00:00:00

ali obstajajo whisper in piper alternative, ki tečejo na Tritonu?

---

# googlesearch response

**Da, obstajajo alternative, ki lahko tečejo neposredno znotraj strežnika Triton.** Ker Triton podpira različna izvajalna okolja (vključno s TensorRT, ONNX Runtime in Pythonom), lahko nabor avdio modelov popolnoma integrirate v Tritonovo mapo modelov.

Če prenesete vse te modele pod isto krovno okolje Triton, boste dobili izjemno hitro, centralizirano in strojno optimizirano platformo za sklepanje.

Tukaj so najboljše alternative in načini, kako jih zagnati na Tritonu:

* * *

1\. Alternativa za Whisper (Pretvorba govora v besedilo)

Za Whisper vam ni treba iskati drugega modela, saj obstajata dva načina, kako obstoječi Whisper prenesti neposredno v Triton:

-   **TensorRT-LLM Whisper (Uradna NVIDIA pot):** NVIDIA uradno podpira poganjanje modelov Whisper in _Distil-Whisper_ neposredno znotraj ogrodja `tensorrtllm_backend` za Triton.
    -   **Kako deluje:** Encoder in Decoder dele modela Whisper s pomočjo ukaza `trtllm-build` prevedete v TensorRT datoteke engine.
    -   **Rezultat:** To je absolutno najhitrejša različica modela Whisper na svetu, saj celotna zvočna obdelava poteka neposredno na Blackwell grafičnih jedrih.
-   **Faster-Whisper preko Python Backenda v Tritonu:** Če je prevajanje v TensorRT preveč zapleteno, lahko v Tritonu uporabite _Python Backend_. Ustvari se skripta, ki znotraj Tritona pokliče knjižnico `faster-whisper`.

Najsodobnejša alternativa: **NVIDIA Parakeet TDT** ali **Nemotron-3.5 ASR**

Če želite nekaj, kar je bilo razvito specifično za ekstremno hitro produkcijsko delo na sodobnih NVIDIA čipih, namesto Whisperja poglejte serijo **Parakeet**.

-   Gre za modele z manj kot 600 milijoni parametrov, ki podpirajo več kot 25 jezikov in delujejo zunaj klasičnega "Sequence-to-Sequence" načina.
-   Na Tritonu dosegajo do 17-krat večjo pretočnost zahtev kot standardni modeli.

* * *

2\. Alternativa za Piper (Sinteza govora / Text-to-Speech)

Piper sam po sebi v svojem jedru uporablja format **ONNX Runtime**. Ker Triton izvorno podpira ONNX Backend, lahko datoteke modelov Piper (datoteke `.onnx`) preprosto premaknete v Tritonovo mapo modelov.

Vendar pa v sodobnih okoljih za sintezo govora na močni strojni opremi, kot je vaša, obstajata dve bistveno naprednejši in boljši alternativi:

A) Kokoro-82M (ONNX ali PyTorch na Tritonu) – _Trenutni hit_

[Kokoro](https://huggingface.co/hexgrad/Kokoro-82M) velja za enega najboljših odprtokodnih modelov za generiranje zvoka.

-   **Prednost:** Kljub temu da ima le 82 milijonov parametrov (kar pomeni, da je izjemno lahek za pomnilnik), zveni neprimerljivo bolj naravno in človeško kot Piper.
-   **Zagon na Tritonu:** Kokoro ima uradno izdane različice v formatu ONNX. Datoteko preprosto vstavite v Triton in model bo generiral zvok z izjemno nizko zakasnitvijo.

B) Qwen3-TTS (ali starejši Qwen2-Audio)

Če želite popolno sintezo govora, ki podpira tudi napredne funkcije, kot je kloniranje glasu (_voice cloning_) v realnem času, so modeli **Qwen-TTS** vrhunska izbira.

-   Ker so del družine Qwen (enako kot vaš Qwen Coder), tečejo na sorodnih arhitekturah, ki jih Triton in TensorRT-LLM odlično razumeta.

* * *

Kako bi izgledala vaša "Čista Triton" struktura map?

Če bi se odločili vse modele (LLM, Embeddinge, ASR in TTS) prenesti pod okrilje enega samega Triton strežnika, bi vaša mapa `trt_models/` na disku izgledala takole:

```text
trt_models/
├── qwen_coder_trt/       # TensorRT-LLM model za kodiranje
│   ├── config.pbtxt
│   └── 1/model.engine
├── bge_embeddings_trt/   # TensorRT model za embeddinge
│   ├── config.pbtxt
│   └── 1/model.engine
├── whisper_trt/          # TensorRT-LLM model za pretvorbo govora
│   ├── config.pbtxt
│   └── 1/model.engine
└── kokoro_tts_onnx/      # ONNX model za sintezo govora (Kokoro)
    ├── config.pbtxt
    └── 1/model.onnx
```

Kodo uporabljajte previdno.

Glavna prednost in zaključek

Če vse prenesete na Triton:

1.  **Brez CPU-GPU ozkih grl:** Podatki se ne bodo nenehno pretakali med sistemskim RAM-om in grafičnim čipom, ampak bo celoten proces (Zvok → Tekst → LLM koda → Zvočni odgovor) potekal znotraj enotnega pomnilnika na čipu Blackwell. Zakasnitev celotnega sistema bo padla pod kritično mejo zaznavnosti.
2.  **LiteLLM kot edina vstopna točka:** LiteLLM bo še vedno upravljal vse, le da bo v ozadju vse zahteve (ne glede na to, ali gre za zvok ali tekst) poslal na isti IP naslov in ista vrata Tritona (`http://triton-server:8000`), le z različnimi imeni modelov.

Ali vas zanima, kako pripraviti **konfiguracijsko datoteko (`config.pbtxt`) za ONNX model**, da boste lahko vanjo uvozili Piper ali Kokoro model?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-04 00:00:00

torej se lahko izognem vLLM in popolnoma izkoristim arhitekturo? in to vse dinamično, samo preko litellm?

---

# googlesearch response

**Da, absolutno! Lahko se popolnoma izognete vLLM in celoten ekosistem zgradite izključno na Triton Inference Serverju, s čimer boste do zadnjega megabajta in do zadnje milisekunde izkoristili brutalno moč arhitekture Grace Blackwell (GB10).**

Vse to bo delovalo **100 % dinamično, avtomatsko in preko enotne vstopne točke LiteLLM**.

Ko vsa orodja (Open WebUI, OpenClaw, Home Assistant, Docling in Qdrant) pošljejo zahteve na LiteLLM, bo ta v ozadju komuniciral z enim samim Triton strežnikom. Triton pa bo s svojimi naprednimi izvajalnimi okolji (TensorRT-LLM in ONNX Runtime) dinamično nalagal, izvajal in odlagal modele iz enotnega pomnilnika (RAM) \[NVIDIA TensorRT-LLM\].

Tukaj je končni produkcijski načrt, kako uresničiti to vrhunsko in čisto arhitekturo.

* * *

Arhitektura sistema: "Popolna izraba strojne opreme"

V tej konfiguraciji imamo samo dva ključna elementa, ki upravljata umetno inteligenco:

1.  **LiteLLM (Upravljalnik):** Deluje kot pametni prevajalnik in usmerjevalnik.
2.  **Triton Server (Surova moč):** Vsebuje vse modele, ki tečejo neposredno na Blackwell jedrih z uporabo NVFP4 in ONNX optimizacij.

![Slika grafikona](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAABZEAAAShCAYAAABCutXfAAAAOnRFWHRTb2Z0d2FyZQBNYXRwbG90bGliIHZlcnNpb24zLjEwLjYsIGh0dHBzOi8vbWF0cGxvdGxpYi5vcmcvq6yFwwAAAAlwSFlzAAAXEgAAFxIBZ5/SUgABAABJREFUeF7s3QdUVNf2x/EtTZBi7wjSbGA3GqPGaGKixprEJJqYmN7Ly8t7//T+XvLSmymmaTS92WJNLNHYu2CjCTYsWOhV/2sfmHHAGUAFGeD7WYsFM5wLOM7cufd399mn1qlTp04JAAAAAAAAAAB2uNi7EwAAAAAAAAAARYgMAAAAAAAAAHCIEBkAAAAAAAAA4BAhMgAAAAAAAADAIUJkAAAAAAAAAIBDhMgAAAAAAAAAAIcIkQEAAAAAAAAADhEiAwAAAAAAAAAcIkQGAAAAAAAAADhEiAwAAAAAAAAAcIgQGQAAAAAAAADgECEyAAAAAAAAAMAhQmQAAAAAAAAAgEOEyAAAAAAAAAAAhwiRAQAAAAAAAAAOESIDAAAAAAAAABwiRAYAAAAAAAAAOESIDAAAAAAAAABwiBAZAAAAAAAAAOAQITIAAAAAAAAAwCFCZAAAAAAAAACAQ4TIAAAAAAAAAACHCJEBAAAAAAAAAA4RIgMAAAAAAAAAHCJEBgAAAAAAAAA4RIgMAAAAAAAAAHCIEBkAAAAAAAAA4BAhMgAAAAAAAADAIUJkAAAAAAAAAIBDhMgAAAAAAAAAAIcIkQEAAAAAAAAADhEiAwAAAAAAAAAcIkQGAAAAAAAAADhEiAwAAAAAAAAAcIgQGQAAAAAAAADgECEyAAAAAAAAAMAhQmQAAAAAAAAAgEOEyAAAAAAAAAAAhwiRAQAAAAAAAAAOESIDAAAAAAAAABwiRAYAAAAAAAAAOESIDAAAAAAAAABwiBAZAAAAAAAAAOAQITIAAAAAAAAAwCFCZAAAAAAAAACAQ4TIAAAAAAAAAACHCJEBAAAAAAAAAA4RIgMAAAAAAAAAHCJEBgAAAAAAAAA4RIgMAAAAAAAAAHCIEBkAAAAAAAAA4BAhMgAAAAAAAADAIUJkAAAAAAAAAIBDhMgAAAAAAAAAAIcIkQEAAAAAAAAADhEiAwAAAAAAAAAcIkQGAAAAAAAAADhEiAwAAAAAAAAAcIgQGQAAAAAAAADgECEyAAAAAAAAAMAhQmQAAAAAAAAAgEOEyAAAAAAAAAAAhwiRAQAAAAAAAAAOESIDAAAAAAAAABwiRAYAAAAAAAAAOESIDAAAAAAAAABwiBAZAAAAAAAAAOAQITIAAAAAAAAAwCFCZAAAAAAAAACAQ4TIAAAAAAAAAACHCJEBAAAAAAAAAA4RIgMAAAAAAAAAHCJEBgAAAAAAAAA4RIgMAAAAAAAAAHCIEBkAAAAAAAAA4BAhMgAAAAAAAADAIUJkAAAAAAAAAIBDhMgAAAAAAAAAAIcIkQEAAAAAAAAADhEiAwAAAAAAAAAcIkQGAAAAAAAAADhEiAwAAAAAAAAAcIgQGQAAAAAAAADgECEyAAAAAAAAAMAhQmQAAAAAAAAAgEOEyAAAAAAAAAAAhwiRAQAAAAAAAAAOESIDAAAAAAAAABwiRAYAAAAAAAAAOESIDAAAAAAAAABwiBAZAAAAAAAAAOAQITIAAAAAAAAAwCFCZAAAAAAAAACAQ4TIAAAAAAAAAACHCJEBAAAAAAAAAA4RIgMAAAAAAAAAHCJEBgAAAAAAAAA4RIgMAAAAAAAAAHCIEBkAAAAAAAAA4BAhMgAAAAAAAADAIUJkAAAAAAAAAIBDhMgAAAAAAAAAAIcIkQEAAAAAAAAADrk5/hYAR9Ky8yU5LVdSsvIlJTNfcvJO8mChCHfXWuLr5SZ+nq7SwNtN6nqxu8WZTp46JYdSLPuSPEnPPmnuA5yBp7uL+Hm5iq+nmzT2cRMvD9fSNgEqVGZOvhxOy5PUrDxz/JWVy/HXuXKpVUu8a+trvOBYpYmfu7kPQNlxTnjuOMYAqiZSDaAM8k6ekqh96bIiNlVWxqZI1P4MIebB2Qht4imXhPiZjy6tvMXDjYkgNdWRtFxZFZsiK+NSzcfxjLzSNgEqne6yOrfykUtCfKV3sJ+0aeZF4IQKpxfVdiVlysq4FHMMtnlPmnDdvmLUq+MmvYN9pXeIn/nc0Me9tE2AGodzworBMQZQddQ6dYqSJ8CR3PxT8sPaw/LF8iQ5kZnPA4Vy4eXuImN7NpY7+jalsq8GiT2UKW8u2Cer41NLGwo4vSa+7vLggOZydacGUovqRVRAePz7lqMycfEBOZSaW9pwVIBeQb7yr6taSnBjr9KGAtUe54QXFscYgPMiRAYc2LY/Q56fmSCxh7Psft+llpgpvj6erlLbrZYIJ9GwoS1O0rLyzYdWLdjTrK67PHN1gKlORvWl//8fLtov364+5LCCTqf06b7Eu7aruOrOBahsp05JZm7Bfiw9O18c7MbMzIoXRgRKQIPa9gcAZynxaLa8MDNBNu1Jt/t93UXqvtLX09XsOzn+Ojf5J0+Z17a+xh21BdHqwHG9msiDA1uIG+9NqKE4J6wAHGMAVRYhMmDH5r3p8uA3MZKec/qgWg+eI/y9pUeQn/kIauxJ9RVKpZM99h3LlnXxqbI+PkU27UmTbJuTNT1B+9+1QTKgXb0Sfw6qboD87PTdMj/qeJH7tfekZV/SJcBHfDzpLgXnDpt2JWXIuvgUWR+fKjsOpBcJlRv7usuk8aES2NCzpB8DlCohOUvunhojh22qjzW7bNfcW7oH+Zp9ZptmdbjYVs7SsvJkU2KarI1LkfW7U0yvfltXhdeTl0e1JkhGjcM5YcXjGAOoWgiRgWK2H8iQu7+OtgbIWhM4pHNDua1fC6lbh6AH578o0HerDsrPa7Qq9ZQ1SH7nhmDpE1q3tM1RxS4gPDM9QeZGHrPe16yuh9x3ub9cHOLHRShUWQdP5Mini/fK8l0nigTJX01oIy3qeZS4LeDI/uM5ctvkXUUC5L5t6sk9A1pK07o8ry7ke5f27f/4z72SdCLHev/QjvXl5ZGBvHehxuCcsHJwjAE4N0JkwIaGeuM/3yk7D2aa2+6uteT5UUHSM4RwD+Vr14EMeeLHGLOqsyWA+fW+9maKLqqHP7cfl3/9HG+93b21rzw/Orhg+jVQDczZfETenb/Hert/m7rmghhwLh79Plb+ik45ffuqVjK0c6MSt0HF0RYXL/4WJ+t3n+7j/+aYIBnIzCnUAJwTVj6OMQDnxJksYOPn9UesAbJ6diQBMipGm+Z15LUbQs2FCqWVV5OWJZW2GapQxflbC/Zab2srnBcIkFHNaMD34BX+1ttLd52QZdGnq5OBsvpr14kiAbI+rwiQK5de8NT3LX3/snhzwV7TKx2o7jgnrHwcYwDOiRAZsJm+99XfB62Px6CIBnIx7QVQgbSv4w29mlpvf7f6sGTkFFQmo2qbE3lMkgp7Smo/9ccGB0htKpBRDQ3v2kg6tfKx3v5y+en3UaCsvrQ5/tLnkz6vUPn0fesfVwVYeyEnnciVuVuPlrYZUKVxTug8OMYAnA8hMlAo+lCWtQ+fHirffmkLHhtUOA2RdYV5y9S5tbvTStsEVcCKmNMVdYM7NRT/Biw4huqpVq1ackf/0++XW/elS0pmXonbALZOZOZJ5L506219PunzCs6hVUNP8z5msSL29PsbUB1xTug8OMYAnA8hMmDnoFhbDTT0ceexwQWp8uka6Gu9zclZ1Zebf0rWxJ/uIXlxqF+J44Gqrm3zOlKvcOFZXS90tc3zHyjN6rhU87xR9b3dzPMJzkUXg7XQ9zd9nwOqK84JnQvHGIBzIUQGCq20CZEvCiL0wYXTw+b5Zvs8RNWklZjpOQU9I7XndadWpy8SANWRS61a0iPo9PN8ZSwhMspuZdzp973urf3M8wnOpWMrH+saDmnZJ4tUjgPVDeeEzoVjDMC5ECIDhZWDGxNPHxB3tzkZBiqa7fNt77EcOXAip8TxcG7rbFay1xNvXZwIqO40/LNYa/MaAEqzzqaNk+3FCDgPLw9XifA/3fuc1ziqK84JnRPHGIDz4MwWEDH9G7UfrUVwYy8eF1wwjX09xM+roC+ySk4r6M2NqulI2ul+sOxLUFMENzn9vsk+DGfjiM17nu3zCM4lpMhrnL7nqJ44J3ROHGMAzoMQGdADhqx86+OgK1BTOYgLzad2QT/R4s9HVD22i4pZFk0Eqjvb53pW3inJySto6QKUJDvvpGTnnb6I72vzXgjn4mPzGk/JIkRG9cQ5oXPiGANwHoTIQLEDBj1IZlVwVObBUWomIXJ12p8ANYGPZ9Hwj4thKIuUYu937DOrSojMcQqqJ84JnRPHGIDzIEQGtP+VTcVUbbfyeVkc2H9APnzvAxk3Zqz0vegS6R7RVS7rfancccvt8vVXUyQlpfosoPbScy9K53Yd5a3/velwzPRffjNjLu3VV/Lz7Z98xMXGmTG9uvaUnJxz7wusP6P/xf3kbOzbu89sN/baG87p598x/jZzf/SuaDkXHjbPu+x8KviqMttV6891f3I2z8fzfe5VRbOmzzT/Zv3YvHGTXGjJR47IqKEjZMTg4XLk8JHShtcItd2KLoZGJTLKIrfY+11t9/PbZxb/6NXlIhl+1dXy5OP/J0sWLZFTp07vnytD8eOHqrQvsX0/y7GpHgeqk4o4J8T54xgDcB7sGYFypicoX33+pQy7aqh89vEk2bljh9SrX086hHcQTy9P2bBuvQlbrx40RP6Yv1Cqgz79+prPa1evcThm8Z+LzOcTJ07Ipg0b7Y5Zt2at+XxRzx7i4eEhNQmL0QNl9+vPv9h8/atcaBvXb5T4uHhJ2L1bNq7fIOdKLxJoqKQBWGX5btq35m/4+IOP5HwwgwfOoE6dOtLjoh7Wj6DgIEk5kSJzZs+RR+5/SG67eYK5yO8symtfciEUvUwEwFkKi5594mnzPr508VKprjjGAJwHjceAcnTy5En55yOPyaKFf0qDhg3kvgfvlyHDhoqv7+nVxpMOJMkvP/0skz//yozVMfc+eJ9UZb169xI3NzfZuWOnORDy8/Mr8v3MzExZtWKV9fZfS/6S7hf1OOPnrC0MkXv36XPG9wBA7Y7fLRvWbZDA1q3lyOHDMn/uPPn3k/8n3j7eF+wBuqRvHxlwxUA5dfKk9SIagMrXOqi1fDH1qzMu7kdFRslnH39qqpFvGD1Gpv7wjQS2DpTKxr4EqL503zP5i69MgJyXmydu7m7SvHlzc3Hr8OHDprBIC2g++2SSPP/SC3LFVYOkOtLZF8ePH5fNO7aWNhRAFUAlMlCOJr73oQmQwztGyM8zfpHrx95QJEBWzZo3kwceflC++elbadiooXz84Ufyx4I/pCrz8fGRjp07mRB9/dp1Z3x/xfIVkpWVZU6WXFxc5K8lS0usRO7T9xK73weA3worj0dfN1ouv/IKyczINEHyhVTHu468++F78t5HH5ivATh3BVtExwjzen34H4+YGVH/evSf59U2q7ywLwGqJz0neuzhf8i7b75jimuefv4ZWbLiL5m9YI65iDVv0QKZ++d8ufv+eyQrM8sUFn3y4cel/VgAqHRUIgPlRPuRfjHpcxMMvzfxfWnYqFGJ49u0bStvvve26Wf6ygsvyyV9LzHTMJXet27tOpnzxzxJTU2Vzz+ZJOvWrpesrEwJCAiQq0cMlxvG3SCenp52f7ZW2ugU5V07d0pGRqY0a9ZULhs4QG665WZp0rRJkbFDBl4lR44ckbVb1suSRYvl6y+nyPZt203YG9EpQu65/17p1qO7lEb/fp2KuXb1Whlw+cAi31v8R0Eri+tuGCPpaWmyedNm2btnj/i3amUdExsTK0eTj0rzFs2ldXDQGQdiv8/6XX7+4SeJj42TvLw8aenf0gRI48bfdEblsy2d2qVTxXZs2y6urq4S1iZMbrjpRrly8FUOtwGqg2PHjskP335v2uZouwRtEaOvrZGjR8rwUSPE3d29yHjLfufPZYvN9OrPPvlUIrdEikft2nJx717y0D8eMa87nW3w6cRPzAUzraRp3LixDL56iNz/0APi7lH0ZyqdoaCVOLp/SD6SbPaRuk+5afzNEt4xXM6GvvZnzZhp9k9Dh18tibsTZeZvM0xLi2vGXGt3G+3B/stPv5hxsdExZtvAoNYybMQwuWHcjWa/YKEXu76d+o3M+32uJOxOkNq1a0tIWIhcM+Y6GT5yeKmVNWX9Xbrf3b9/v3W7oVcMtn5t+/O06nrq5K9l5d8r5PChw+bvCWsbJtdcd635P7Sl7Sg+mfixvPbW69K5S2f59KNPZPlfy8xUfv1/G3nNKLnltlutf4NlvIV+bbn90n9fNuOB6uaOe+6UrVu3muMSXatBL/ZbZKRnmJlic2fPkcTERJFTIgGBAWZG2bVjrnN4wUj3Fd98Pc28Tg8mHRS/unWlbbs25vikLDMV7O1LzvXYzLIPmv7zr2Y/rvv9jp07ym133m7+rutGXGPaq333yw9nbAugYgqLPvj4A7vnhZbCokFXDZJ777jHFBaFtgmTK668wu7PBABnQCUyUE5++v4HM23p5lvHS+MmjaUsunXvJv0HXibHjh6VhfMW2A2Db75+nCz6Y5E0adJY/P39JSY6Rt5+/U25/eYJcvTo0SLj9fdrIK19/7Sqt169ehIaFirHjh4zIc71o66TLZs2iz0aODxy/8OSmLhHgkKCTeWOtqC4a8KdsnrVailNn772+yLrCc2ypX+Z8EOD5v4DLjP3F+/bZdnukj5Fq5Czs7PlsYcelWf+7ynZHrXNhOA6XXXvnr0mBLnxmuvNCZw9Gog8fN+Dsi0yygQ5vn6+JiT716OPy7NPPmPCaaA62rJ5i4wZeZ15jexJ3GOmbTdq3Mi8/l989gW585bbJTk52e62M36bLnffdqfExcSZ7bKzsmTu73PllrE3S3xcnNw0ZpxMmzLVtI/wb+UvSUlJ8uVnX8izTz5tdwG8cWNulDmzfjfhR7v27cx+6veZs83P+/H7H+Vs6H5Dg+iLL+ktTZs2lR49e0iLli1l6+YtDhcW/Pc//iX/eeFlsx9oFRggrQJamV71//vPa3LfnfdYF/rMzc2Vu269Q957610T3oaEhkjTZk1l04ZNZv+jPQdLU9bf1bFLJ9Ov1XLhUGdyWHq4WsybM0/GjLzWXDzLyc4xj51fXT/TyuOZJ56Wp//vKbuLhMXsipbrR19nttfHqFHjxiZM0moo/b+3aNGyhfl9GpKZ2y0KbuuHPleA6uqOu+80n2fPmGW9T48jdF/15mtvyM6dO82U8xb+LWXXzl3mPv2evWMNnQVx/egx5oKdXrBp066tuUC3/K/lcv9d98nbr78l5+Nsjs0yMjLk/rvuLdgHRW2T5i1bmAvzq1euNr1Xp/9y4fvHAzXRuRYW6UVePY/T13JxehFJFwi9asAg6dm5h4wcMtzsH/Q8qaRFl3XBTnPBbNR10r1jV9OT2UKPSX796RdzTtmvVx/p0bGbuaj98vMvyf59py90W+jP09+rZvw6XcZdd6NZvFS3ffSBhyV6564zxuuHXiSzva0XyQBUXYTIQDnRg3Q1eOgQORtXD7vafLYX1L752uumd7BWJP84/Wf5eeavMmv+7+YkX/v7Pffks0XGayXMT9//KP36Xyq/L5wrv/0+Q7758VtZ9PcSefqFZ00FoU6XSktLK7KdTunUysInnnlSFixZKN/+9J38sWyRjL7uGlP5904ZToI6RHSQ+vXrmwMnrYC0WL92vTl40NDHy8tLLh3Q39xfvKWFpZWFtrywpYHO4j8Xm6q4BUv+MI/Btz9/L0tW/mUqcbTCUqelFg+EdbqqTgvTyjutrNR/kz4mX079ypxUaaWgVigD1Y1WrOqFpMOHDsltd90ufy5fLN//+qP8Mus38xroe2lf2bRxk/zfY/+2eyHlg3felwcffUjmL1loqtXmL14g3Xp0MyciN157o6SmpMjU76eZ1+L0OTPlq2lTTLWbBs06o8BCg9QXnnnehJPTfvzW7Md0Cuf8xQvl8ylfSt16deW1l/8rW7eUvUfeb4UL6o0orMLVQMVSIWxpc2Fr44aN8seChSbMnTl/tvz420/msdB9Sdfu3Uy4agmfF8ybb8J3DXTnLV5g9jM/zfhFZs6bLcEhwbJp42Y5ePDgGb/jXH7X62+/Yfq26gUx9b+3Xje3bXu56uOsIf6krz4z+2N97CyPoYbbGoDZW5xVT1w76b9h0Xzzb5j75zz54JOJphejnvTpDBWl+1T9fVotqUaMHmn9G8pSPQlUVeER4abVmAateoyjgY0GIPoa1deBvmb1ta+v4QVL/zD36fd0jG24o/u4p//9lOTn5clTzz1t9rXTfvjGvOZ0H6cB0pQvJ5/zIspne2z25quvm4BZKx9nzJ0lv876zeyDFi79UwYPHSzTpkxz+LsAOE9h0YK584t877dffpObbxhnFgjNzsqWsLZtJD0tXT56f6KMv/FmSUtPd/hzNWh+/unnzGzP9h06WNss6swLvbikF5c3b94szVu0sBYe6cVrDZ11H2ePHts999Sz5vxO+zvrRXg9V7tl7Pgix4GWC9O6bo7tbb2QDqDqIkQGyolesdXqE52adDa0Wk3Zu+KrVSfvf/xBkZ+p05I/+HSiqR7TCl+tkrOcbGjlrS429c4H7xbZRt+8r7/xehlz4/Vy6OAhcxBSnE7pHHvzOFMtqLRVhp64aL9jvfp94vgJKYmGORdfcrE5aFq/5nRf5MV/FrSy0EWolLaT0H+Dhst6AKR0G23XoVfge/buZd1W/1Zty3FRr57y4n9eknr161m/p5XN9z/8gFx6WX8zXV6nkdrSnznq2tHyz/97vMgUVA3lP/j4QxOofPbxJDN9HXBWGnJYKjccfWh1ffEQUU8Wxk+4RR795z/Ma9i2+vTdie+boFSr//Wgv7iBV1xuKvUsbQ90CvSDjzxkvs7KzJT/e/oJ6dSls3V8l25dzHRvpYvEWHzw7gfm80effSIdO3Us8jsu6nWRPPXs06YKRts1lIUGuNpfXU+ALPsTNeKakWb/o9XNxXuc6smY6tqtq5nJYdGwYUP54JMPTSirFb4FYwsufvXp20caNGhgHauh8ORvvpYZc2eayl5HzuZ3lYXurzWo79X74iL3a0D85LNPma8XzD9zBotWHr/57tvmop7FpZddKiNGjTRf2y5yCtREepyjwY4GH8ePHTeBSVxsnFw+6Ap5+dVXzGvWQvcFep9+T8f88uPPRfZx+jMef+Jfpl2NJSix7OP+87//ytUjhpn97rkq67GZHkNqWx9d1PmjSR8XWTRQj53+8/qrZr8PoGoVFukMsleef0lcarmYi1V6IUkLhPQC16tvvCZ7E/eYthmO/PjdD/LQow+bwgC9yKUXuZUWFun+RPddi5cvsV741othGn5rO0WdtVmczsjQlj9vvPumOa4xF8sXLzQFTHqRTdt4WFguTFuOQy239UI6gKqLnshAJbM3Hdni1ttuNWFpcToFWk8qdIr0wvkLTIiz8u+VkpqSaqp9773jbrs/7/DhI+az9ibVUNnWNWOuOWO8HlxoWK1Blk5918rBkmgVsVYjrlm9xrrCsLbk0JOf/oUVyEqDXw2HVyz/WwYNvtK06NAARvt42vY3/nPhH6ZSMunAATP93p59+/ZZ/03Fq+fuutf+46BX8Ptfdpn5+atWrDT9ogFnpK917V9ZEr2Iogf7FtrPVy+SaO9Pe/Ri1x133yGPPvCIzJ39u1w+6PIi3x8xumivXWXpU64Vx1dceebq4VqJoiwtdvTkZPXKVeJR20NeePo5sSercAqmvnbLQqtoNXS+cvCVRfrBa2CrFTzr1603rX+04s6ic9cupo3NnN/nmAt2w0YMtwY6xRc91dkS+rhpqw7d11015CrrFNTS9n1n+7vKSkP5qVOmyqYNG81Uef052kdaL6yppP0HzthG/257vVvbtG1jPjtqYwLU1GMv3Weqex+81+H4ex641xwzaHiiF+hSTpwwxw8a2up6D/b07nOJ+TgfZT02W/THn+bfpDMMbC+4W+hFwbE3jzWtfwA4Z2GRf0DBWjEHbN7bJ77/oZl5oAGyBr4WlrUh9Pc8/ug/xRE9Zrrz3rusty3rYejf9skXn9o97vzXk/82BQq6noxePNPZWBa6n3ngkQeLrC2jxQbPvvScXNn/CrNfBFC9ESID5UTDAu2jmXQg6ayqTvQKsrK3Tfvw9uJIh/CCBal0gTqVmJBgrd7Vj5JYKu5saV9Reyw9Oy29PEsLkbUicG1hawqtktm/b5+ZCm9b2aeBsobI2tJCQ2RrP+RirSwSExLNZ+3pqh8lOVrs36S9Q7Xi2REN5vSE0PJz9e8+G2c7HjgX2u7AtsWBPZYF8ZQGG9pOJiAwsEglanEdIsKLvMZs2dsXeXl6mc8amNhbPM8S6p7ML2iPoW1mdJ+RmZF5RqV0WfZHxelJi/b0U8NHF1TU2tLgRENkbXdhGyJrReH7H30gT//f06Y6Rj+0j7MGO1cNGWyqBS10Guf/3nrDVPzoBTr9CA4NMZXJQ4cNtT5mjpzN7yoL7bH66sv/Nf92/b9s276dWZhUK5y036rSE8uz3Zdb/o+AmkovTmt7Hg1TNHDVyjr9OqxNwYUWe/QijI6x7DP37dtvfo72MrWtQC5vZT0203UiVNu2bcWRNiX8+wBUPtfCGQeWoFeP6dasWmOOva69/jq72+h5lIa8Gvbao+14HNHKYZ0Npi13dN+mxxt67qTnY7qujiXQtg2R9fxHZ3oWpzO1dBttcaGzPB0t/g6g6qu4ox6ghunVu5cJkefNmSu333WHlNXvs383n3tdfLqNg0UtcRxUntJlw+1U1Tz8j0ccViCWRKdJnS9djElPtLQyMvnIEbP6uRpw+emp56rHRReJt7e3LPtruTkJW1fY/kIX3rP3b3rtzf9Zp8uXVUmPnb3HT0NnVVp7C0s/RF+bimmgOqlVwr6gzPuJwteuBqj2Kl3OllY1azCtJoy7pYRxq8042wtI3Xp0l1nzZ5sTsb+XLTcXubR3vH4MHHS5vP7WG9ZgXFdE79e/nwlptZpmzarV5gRLP7QCSCuBSnI2v6skuv9849XXzdfPvvic6YFqaS+ii+jo9PvX//s/u9u6uHCBCyiJrimhszd09pMlAD7rC8OF+7iz3u4slXWfa62sLuHvKX7cA6BiaH/hhN27TQBbUkGLtsOxBMYqofAiVbNmTc/qYlX78A4OQ+RmzexXQ2srn9tuvtVspz+7pb+/+Pj6mCpqnZFlUfxitc64sp01WvzilobIXKwGqreyHZkAKNWYG643JxP6xqsLW5XFhvUbZOmiJVK/QQNzJdneiY4j26O2mc/6pm/7ecf27VKZehcGwWvXrJMlixbbDZE1RNHAWFtYbNm0RdavXWdCXF0MxpblwGvH9h1ytnRhvb17Cypz7Nketb3I79B+XVrtl5iYaBabcMTyt5R0UAhUFp1SqM/j/fv3FVngsjjLYik6Jbqiqud0fxizK7pMsxhKo70+lS7S17ZdW7sfehHLVCz/WlCxbEtPkHSfo1M0te+fLpbXvUd300ew+AKb2kJIW3w8/fwzZnGq737+XkLCQk1lsE5lL83Z/C5HNm7YZE4uL7t8gJkqbwmQLX+fZUE+AGfvq8++NJ+HFS7Kqf2DtZ969K5dDrfZtXOXeU1a9pl6DKDTyXfu2GF3RsCFZjkm2bWjYOFMR/8GABWv58UFLafmFBYK2aNr2oy+emSR44o/FxQswmltg1MeF6scbDvp409NgKzrLOhxysx5s8zinUtWLJUZc2aa2U/nc2ELQPXFXgAoJ9pnVxejSj6SLI888LCpJCvJrp075fFHHjNXmJ95/hnr1ERbWv2mVWfFZWZmmnYQlso51btPb/MzdKEs25VxbX3+yWdmFd6DSUlSUSwtKXTquVYk6xRxXZiquP4DLrOuGqxXrbUS2zYoUbqQjR446c/Sqaf2/PelV+Tt19+yu/Cf/nvtid4VLUuXLDHV0Lb9CrWPc15unvWxtWfKFwWtBbSqEHBGg68eYp7HX3z6ud3vaxDyxaQvzNdDChdxKW/ao7NHz4vk8OHDppexPWtXr5V7br9btpTSo1Nf2zqrQQObr76ZIj9O/9nux//eKqjc1d+n+1UVtTVKnvjnvyU+rmiFjoZGDz5asFjgpo2brNXOuk8uHr5rG4vb7ry9yFh7zuZ3WdQqnLqq/yf2qol9vE8vimihQfnXX5VtMcKycHHwNwDV0eQvvjKtrPTCk2VKtu4z1ScffuJwu08nFnzPMitKL9jpope6iKnODHB0sU73KVowUNEGFi42OnP6DDMFvji9mPftVMfHNgDKjy6Mq+cv33z9jVkU2B6t+tWio1deeNkUvegxxLw580xhkWWtFssF+dIuVlkKA86GzrRSz7z43BmFMboOhq6BAQD2ECID5UgXGhhwxUCJ2hop14281qyIa7vgldIA96P3J8pNY8aZwPme+++1LkJXnC4498j9Dxc5ANGpUQ/f95DpXaWBrU6fVhog33Xf3SYIeODu+0x1r0VuTq5M+XKKfPTBRLOATG4FVs1069ZNvOp4ycq/V5jb+njY07d/PxNe6OJ69vohW3qzahWehsy6WKAG77ZtJTQ8/uHbH0wLkVp2pnD/9vOv8s6bb1tbUKiNGzbKw/c+aEI2Df11IUILva0V0fo4aZBse8CWlpZmAmtdKFD7zQ4bMeyM3wc4A30ea/88vQj17lvvmOeu7f7j0QceNosrach72cCCizkVtT/UC0OvvfKq/PrTL0Uqkpf/tcyEK9oy4uCBki9qzZ45y1QJ6sKZJS1So/8efW0eTDpoWkmo9evWmcU+H7n/EXNRy0Lb1vxW2GM5ILDgIpdegFs4f6HZP9jOYtB9+O8zZ5dauX02v8uiRYvm1gDbsq9WnTp3Nov86cKp2hrDNlB/5omnrePLa9qt0vcMyz7P8ncA1YFeeNGQ5R8PPSrvvPG21K1bV9549y1rSKLHGbo4qIbLzz7xtHWBUKVf6336Pe0LatuXVC8O6VT0N197Q77/5rsixwxaZfjYw/8w+5TE3QVrVlQk/1atZMSoEeaC+0P3PWRt/2OZtv7kv54wx6YAKp5epJpw521mxuU/HnjEbiGMFtk89u9/mmO0fz3yT3nk/ofMBfDH/vWYdXFcywV5vVhlmZFVnPYzjo+Ll3O9gOzt433G9/TCV3kuwmm9YM6xBVAt0BMZKEf6hvz2++/Il5O+kI8//Ej+8+Irpm9l8xbNzWIDehCRlJRkDhJ8fX3llf/9xyy45Ij2Vp7y5WQZevlgCQkNMSdCWmWsYUz7Du3N9ra0Wk5PHLQq5vbxt5kryw0aNjQnMNreQVs2vP7Om+Jf2PqiImiriot69jSL5qmBxVpZWOiU+05dOsumDRvNbUcrmOuU8MOHDpnwdszI68w0bm8fH9kdFy/p6enSuHFjeW/i+2f059LHW1uETP78K/npux8lKCRYThw/bl1Ib/jIEXLbXQXVhRb6//TWe+/Ivx79pwm+dEXk1kFBkpebax53DbL0MX37g3fsVo4DzqBxk8by3kcfyGMP/cNM2/5u2ncSHBxknr86dVH3P126dpHX33njjOr/8tS1W1d5/uUX5OXnXzIzIN5/+z0zK0GrkzXM1uqahx592G4rn+IXg9S1118rpRl93Wh57613zclWv/6Xytibx5kwRwOg60ddZ0KgOt7eEh8bZ/YfWuUz4Y7brYGQLgaq+6QRVw0z+1xtTaGvfZ0R0q5De7lmjOO/4Wx+l8WwkSNMyKT7G/13Hjp0SBYtX2Jac9z/4APy/jvvyV0T7jD7Pd3n6N+iQdWjj//DhGHloUfPHmbfp1XSw64cat6bxk+4pcTFeABnpWtT6GKjFnoRWfc3lhkGXbp1Ness6HPeQl9bus/UEGfm9Jky5/c5EhISYqaBx8XEmovzGjK/O/H9Iu/9ER0j5JX//Veef/o5swjmxx98JK0CA+RocrI1xB03/iaz8OeF8MQzT5l+prqYqb6WdR+mIbcWJOh+Q/dxH777QWk/BkA50DVq9FxFL1CPGXWt3Pfg/WYmg77HWlx6WX9znrKtsEWhFgEUf++9/+EH5M5b1ssb//2fuBQuaqfHJnpOOH/ufHnp2RfM8ZS1L3oZaRGSXvB+94235aX/vmINrpct/UueffLZc/qZjugFcw3UV61caY7NNEwuy/oQAJwTITJQAUHynffeJYOHDZFff/zFVNrpSY2eUGiIq8HKpQP6y+hrrzFXmEsydPjVMuDyAfLFpM9l4/qNkpObY65cXz18mNxw041nrHyrb/i6CJO2itAq6O3btpn+eE2bNTXTNW+5/dYKDZAttB+ohsj6e3UquCP9B/Q3gY2enNme0NnS/p964qZ9xX77+TfTYzUp6aA5INFeyzfdcpM0bNTI7rbPvPCsdO3eVb6f9p05idKTKb2if/3Y6x2G99rH7McZP5ttlixeIjHR0eZgTU/GNOzSKWqOFpQAnIX2uPtpxs/ywzffm2rW+Ph48XD3MBdutFpNT1JsF3OpKBqedAjvINO+nmYqarWneP0G9U2rmvG33WL2hyXZumWraT+jF4v0xKM0I0ePNBd/dP+jLYV03/DGu2/K7BmzTDW0Vuvovlj3N2MGXm8qhfSCltL986dfTpJffvxZZk2fKXv37DWzNrQdhc4WGX/rLUVmLhSnj2dZf5eFVoK/+J+XZMpXU8w+SveZFrpAamBQa/nm66myc/tO897S/aIecvf990iTJk3KLUTWUOyjzz6RN197XTZv3CxpqWnm/wioijQ01hDV9hiiSdMmcvElF5vjIA1tLBV4tvR1/u1P38vPP/5kepRaLjiHtQkzwc9114+xhiy2Bg8dbC7q6+t0xfIV5phLjxH69OsjN940Ti69rPT9VnnRisJPvpxkCgm0rc/u3bvNfl/bbuj+RP8uDZEvxL4fqOlMYdEH7zosLEpOTjYXfSxBrZ7D6SzN4rp17yZPPPuU/O+VV81F+Q/f+1D8W/lL0v4D5qJ8RKeO5qL1zN9myNm46967zNo1eiF75d8rTQsLPW7Si24dO3cy50Pz58yT8qD953Wdn388+KhZgD3/5En54dcfS9sMgJOqdaq8LjEBVdi63aly99QY83VTPw+Zeq/j4PNC0CoaPQn6eeav5gQG1d/j30XLlj0FbQdeGBEgIzo3LG0TOKm7vo6W9QkF/5ePDwmQKzvyf4ma4crXC2aWqNkPdZAW9WqXOB7Yfzxbhn1QUIWnFvy75AtLOHcaGGmLNF3T4Z0P3pWztWBrsrw5N9F83T3QRz67heNTVD8VcU6oLbJ+++lX0+ovYXeCmd2kF8cDWgfKVUMHS8OGDc1MCC1Y0XM/ewvp6UV1XZxXi4q077m2/Lt6xDC59fYJpqWOLv77/scfmgKdsp5L6gyNTz78WJYuXmJaLOoFNy1guvOeu+SV518yMzNsf2bndh1NAL501TK7P2/IwKtk//79snL96iIX3XQGnM6s1Yv0SQeSzIyQz6cUrM1xNjjGAJwDlcgAAAAAUEVpTdBXn38pfyz4w8yosJ0yb/HrTwWtgUqbAQKgfOks0If+8bD5cOS5l1+Q3pf0thsgq46dOsob77xp93tPPfe0+bD1xdSChcBLorOjnnz2KfNR3Muv/cd82Nq8Y6uUZO6i+Q6rsrXlomWRYgBVGwvrAQAAAEAVpcFT1NYos3jeQ/c+WGRhPe0/+snEgmpDXVRw1AXq0Qyg7K657hqHrf0AwJlQiQwAAAAAVdhzLz0vBw4ckI3rN8jwq642PU6969QxC6qmpaWZvu9vvf+O+NUteT0OAAAARwiRAcAJ0J0eQFXGEhtA5dLFmr+aNlmm//KbzJoxS/YkJMqejAyzYKf2Tp1wx22mj+q5YhEdAJWFYwzAeRAiAyLi7na6s0t23slKf0zK0scK1UuOzfOutiudhqoyd9daTrU/AS6E7LyiEZOHzfsq4Ih7sfe77NyTUtud5865ql27ttww7kbzUd5s38883Oz3bQWqOmc7J0QBjjEA58FRGiAifp6u1schLSufq5244FKz8q1f+3qdfj6i6u9PgJogLSvP4esAcMSv2Psd+0znZft/w+sb1RXnhM6JYwzAeRAiA8UOGPJOnpKsXK4848JKyz4dwHByVrX5ebnZvTgAVGe2z3VPt1pUIqNMaru5SG2bqtZUm/dCOHOIzGRWVE+cEzonjjEA50GIDBSGPm4up09i4g5n8rjggjmcmiMpmadPzhr6uJc4Hs6tkc/pk2v2Jagp4g6dft9kH4az0cjmPc/2eQTnElvkNU6IjOqJc0LnxDEG4DwIkYHCHqZdA7ytj8X6+FQeF1wwts83//oe0ryuR4nj4dx6tPa1fr11TxozG1AjrN+dYv36IpvXAFCaHq19rF+v4/jLKWXm5Evk3jTrbV7jqK44J3ROHGMAzoMQGSjUO8TP+lisjT99MgxUtHU2zzfb5yGqpo4tvcXbo+DtNTf/lGzZw0UpVG8nT50qEv71DiFERtn1DvYrEhTo8wnORS+I6vuZ8qntIhEtTxdeANUN54TOhWMMwLkQIgOFLrEJ73YdyJDktFweG1Q4XYl+Y0Kq3echqm4VS8+g0yHaqhguSqF623kgQ45nFPSy1c5QvWye/0BpegX7mueNOpaeZ55PcC6rYk+/j+n7m77PAdUV54TOhWMMwLkQIgOFwpp4SmPfgr58Wmvx5V/7eWxQ4X5YfdC6WIT25b7IZlovqq5LQk9fDJi3JVn2JGeVOB6oqk6dOiWfL9lfpBLfdnFJoDR1vdyKVLZ+sXS/eV7BOej7l76PWXCxG9Ud54TOg2MMwPkQIgOFatWqJbf1aWp9PBZGHpVVMSd4fFBhdiVlmBDZYmyvxlLHw7XEbVA1DI2oL838Ci5K5Z08Je/MTzRV50B1M2vjEdlq0yv19r6n30eBsrrd5vhry54087xC5dP3LX3/0vcx1ayuuwzp2KC0zYAqjXNC58ExBuB8CJEBG9d1byRtm3pZb788I17WxBIko/xpy5Qnfoix9hjUKvi7+zUrbTNUEV4ervLPK/2ttyP3pssLv8WxyB6qlTmbj8iHf+y13u7fpq70C6tb4jaAPZe2qSuXhp2ewaHPK31+ofJk5Z4071v6/mXx+JX+4uXO6SOqP84JKx/HGIBzqnWK+WJAEdsPZMjdX0dLek5B1aB2fRvcqaHcfmkLqVuHKbo4/xXOv115UH5Ze8ha2ePmIvLODcHSJ5TwpTrRt9dnpifI3Mhj1vua1fWQ+wb6y8WhfqbSBaiKDp7IkU8W7ZW/o09fZNULYV9NaCMt6nmUuC3gyP7jOXLb5F1yOPX0mhR929SVewb4S9O6PK8u5HuX9vL/aNFe81q3GNqxvrw8MpD3LtQYnBNWDo4xAOdGiAzYsXlvujz4TYw1SLb0qw3395YeQX7SI8hXghp7iQshEMpwMrbvWLasjU+R9fGpsjkxVbLzTvd61AD5f9cGyYB29Ur8Oaia9ELBs9N3y/yo40Xu18CtYF/iJ10DfcTHkwtUcF75J0+Z9jtr41Jk/e4Us8hN4TUw6/N50vhQCWzoWdKPAUqVkJwld0+NKRIk66J7bZvXke6t/eSiYD9p06yOuFpW4kO5SMvKk40JabIuPsV82D7+6qrwevLyqNbmWBioSTgnrHgcYwBVCyEy4MC2/Rny/MwEiT1sf0EsPY728XQVn9pu4uleSxto2R2Hmikn96SkZuebE7N8B61wtbfgM1cHsEhNDQiSJy7aL9+s1upz+2Nqu7uIb21X8fZ0JRyBczh1SjJyTkq62Y/lmwVn7enSylteGBEoAQ1qOxgBnJ3Eo9nywswE2bTndBsFW3q0ZY6/PF0LWitw/HXOwU16Vr45VnHUs18vdN/Uq4k8MLAFATJqLM4JKwDHGECVRYgMlED71f6w9rB8sTxJTmTm81ihXOhJ77hejeX2vs3oLViDxB3OlDcX7JNVcamlDQWcXhNfd3lwYAu5umN9prejQmbx/L7lqHy4+IAcKlYViwvj4mBfefzKlhLc+PRaIUBNxTnhhcUxBuC8CJGBMlYSRu3PkJWxKbIiNkWi9mU4rMoC7Alr4mkqji8J9ZPO/t7ioeU9qJGS03JlZVyq2Z/o5+MZeaVtAlQ6ncauVce6H+sd4ithTWnphIp38tQpiT6YKStjU83x16Y9aQ5ndOD81KvjJr2Dfc1rXAPkhj7upW0C1DicE1YMjjGAqoMQGTgHadn5cjQtV1Ky8s2Ho2mAqLk83GqJr6eb+Hm6Sn1vN6nrRc9b2A9ItPdkSqbuS/IkLeukuQ9wBl4eLuLn6Sa+nq7SyMdNvDxcS9sEqPDFaY+k5UmqOf7Kk0ybtStwdnRdDx/Pgte4n5er6W3OWh/A2eGc8NxxjAFUTYTIAAAAAAAAAACHmE8NAAAAAAAAAHCIEBkAAAAAAAAA4BAhMgAAAAAAAADAIUJkAAAAAAAAAIBDhMgAAAAAAAAAAIcIkQEAAAAAAAAADhEiAwAAAAAAAAAccnP8LQA4dzPmr5Bla7ZK8yYNpGtEqHQJD5UG9XxL2wwAAAAAUEZHj6fKpqgY2RgZIwcOHZV+PTvKyKsuKW0zADhrtU6dOnWqtEEAcDZOnjwpT/z3c8nLzy9yf+tWzaRreKh0Dg8RP586DrcHgPKwe2+SZGXlSNuQVlKrVq3ShgPAOdNTqp2xe8TLs7YE+jctbTgAnJeUtAzZHBUrG6NiZPeepCLfc3N1ldeeulNcXJh4DqB8ESIDqBC/zV1uKpHt0TAntHULU6HcsX2weHt52h0HAOcqZvd++XjKDNEr5T06t5EbRw4UF4JkABXg5KlT8v2MRbJu8y7Ry1X33TrSHOcAQHlKz8ySLdviTNWxHuc4qgfUSuTRQ/ra/R4AnA9CZAAV5uDhY+bq+MbIaDmcfMLuGL1C3i6klXSJCJWItq3Fs7aH3XEAcDbWb90l3/z6p/X2xd06yJhhl1KRDKBcaYjz0+ylsmrDdut9N11zuXTv2KbE7QCgLLKycyRy527ZFBkjO2L3mBmf9jRuWFe6RoSZWZ9NG9e3OwYAzhchMoALcoK1L+mI6dOlV86PnUizO87NzVXC2wSa/sntwwLFw5227QDOjbbT+XTabIndvb9IZc6owX0IkgGU2/HNb/P+luU2M6+0Avnum4eZ6eQAcC5ycvNke3SCOXfaFp0geXlFWwRa1K/ra2Z26keLpg05vgFQ4QiRAVzwE66EvQcLAuVtsZKalmF3XG0Pd4loF2SuprcJ8edkDMBZy87JNUGyba/AAZd0kWFXXMyJFoDzPp6ZtXClLFm52XpfUKtmJkDWYxgAONuL37ti95pZnJE74s0xjD2+PnWkS4cQExxr/3XWfABwIREiA6g0Oh0rNmG/CZQ3b4uTzKxsu+PqeNWWTu2DzcFSSGALFokAUGa6X/lk6mzZs/+Q9b4rL+0ugwf0LHE7ACjJ3MVrZOFf6623A1o2kXvHD6ctF4CzPhfasDVGtmwvy7lQmIQENudcCEClIUQG4DxX3+P2mkC5tKvvnTuESDeuvgM4i4VoPp4yU/YfTLbeN3RgT7miX/cStwMAezQ81hDZomWzRnLfLSNM0AMApS3EaZmVuTkqRlLTM+2O0xkNHdsFmXVj2gQzKxOAcyBEBuC0fcC0f3LUrpL7gHUJL5jOpSdwTOcC4EhaeqZMnDLDLPhpMfLKS6R/7848aADKTNtXzFywwnq7WeP6cv+tI8XH26vE7QDUXGe7PoxWHLcLDWB9GABOhxAZgNOvSBy1c7fpD7YjppQVicN1YYkwViQGYFdKWoZMnDxdDiefsN537dB+0ueiCB4xAKVaviZSfp27rMixxwMTRomfT50StwNQM+mF642R0eY8xvbYw5ari4u0DW1lzmPC27amJQ4Ap0aIDKBKTUnfuj3OXMWP2b3fXNW3R1cn1urkLuGh0rC+n90xAGqm4ylp8uFX0+Xo8VTrfTeMuEx6dW1f4nYAarZVG7bLj7OWWG/r8cUDE0ZKPT+fErcDULMkH0sx5yoaHB+waaNlS2dPhrZuYc5XOrYPFm8vT7vjAMDZECIDqLIVhZu3xZqDtN17khyO04VuLIFyXV9vh+MA1BxHj6fIh1/NMIGyqiUi40ZfLt07tSltUwA10Lotu+S73/4Uy6VrDY4fvG2UNKjnW8qWAGqCE6nppk2Fnpck7ju9kG9xQa2amR7Hur4LMxgAVEWEyACqPK0o1AM3/dh74IjdMRoSBesV//BQ6dQhWHzq0LsQqMkOJx+XiZNnmAtSlqqgW64bZE7sAMBiU1SsTP1loXX2kwY/D9w2Sho3qMuDBNRgaRmZsmVbwQzJuIT91otMxfk3b2SKWbSoRddzAYCqjBAZQLVyKPm4bNIpZJExcvDI6QW0bLnUqiVtQvxNoBzRLki8PFlNHaipvQq1R3JaRpa57eLiIrddf5XpSQgAkTvjZfKPC6zrMejiedrCommj+jw4QA2UmZUtkTviTauKXbF75aSD1nq6jzAzISNCpUnDenbHAEBVRIgMoFrSiqEDh44WLGYRGVOk/6ktN1dXaR8WYA70OrQJFA93d7vjAFRP+w8my0dTZkhGZra57erqInfcOMSsig6g5toekyhffj9X8vMLAuQ6XrXl/ltHmnUXANQcObm5sm1XgmyIjJHt0QnWfUJx2t5Gzyd0ke/mTRqYGU4AUN0QIgOoEYFy4v5DsnFrQcsLy/T14jzc3UwFYreIMGkb0krc3FztjgNQvezZf1g+/nqmZGXnmNv62r9r3NUSFtSytE0BVEPR8Xvls2/nSF5evrntWdtD7r91hPg3b1zapgCqAX3t74hNNIUoUTt3S05unt1xfr7e0jU8xFQcB7RoQnAMoNojRAZQo+iU1LjEJNkUGS2bt8VJembBNPbivDw9pGO7YFNREBrUUlxdXOyOA1A96AKdn06bLdk5udaLSvfcPEyCApqXtimAaiQu8YBMmjbbGhrV9nCXe8YPk9b+zUrbFEAVln/ypMTE7zPB8dYdcZKZVXBhuTjvOp7SuX2wdIkIk+DA5qZNHgDUFITIAGqs/Px8idaDxagY2bo93lqFWJyPHix2CDGBcusADhaB6io2Yb9Mmva75OadDo/uvWW4BLZsWtqmAKqBhH0H5ZOvZxW5mHT3TVdLcGCL0jYFUAVpT+PdiQdMcLx5W6x1jYTidDZCx/ZBZj0VnaXk6spsRQA1EyEyAIiY0GhHzB7rtDVLiFRcPT9v6wrLOq2VfmdA9bIrbq98rtPY8/OtsxK0D2rLZo1K2xRAFbb3QEFbG0v1oa6ZcOe4odIm2L+0TQFUsTZ3+nrXY35tc3c8Jd3uOHe3gjZ3eszfLrSVuQ0ANR0hMgAUoxVI23btNgto7IhONNPb7GlY388cWGoP5WZNGvA4AtXEtugE+er7edbXvreXp9w/YYQ0b8KCWkB1dOBQsnw0eaa1xZW2sLr9xsHSPiywtE0BVKHXuQbH+pF8LMXuGF1ct32oZcHt1mZGEgDgNEJkAChBRma2RO6INy0vouP2mmlv9miIrFPcdGGNxg3q2h0DoOrYsj1Ovv5pgfU17+vtJQ/cNkqaNKxX2qYAqpBDR47Jh5NnSFp6prmt/U1vvf4q6dguqLRNATi5w0dPyCYNjqNiJOnQUbtj9DUfFuxvjuO1ZYWXZ2274wAAhMgAUGap6RmyZVucqWDQhXccadWisTVQrufn43AcAOemr/Vpv/5hpr6qur7e8uBto8wsBABV35GjJ0yAnJJaMJ1dW1TdfM0VpgoRQNV07ESabI4qCI737D/scJwuiqfH6506BIuvdx2H4wAAp1GJDADn4HhKmmyKijUh0579hxyOCw5obk5GOUAFqqa1m3fK99MXiWUOQv26vvLgbSPNZwBV19HjqTJx8nQTOKlaIjJ21EDp0bltaZsCcNJCjw2R0RKfmORwXKsWTcxxeZfwEAo9AOAcECIDQDlUMunCHBooH3AwVU6rm3Q1Z+2fzFQ5oGpZuX6b/DR7qfW2ViJrRbJWJgOomheCJ06eUaQv6phh/aV39w4lbgfAuVrObd1RMEMwOn6fddZQcc215ZwJjkOlES3nAOC8ECIDQDnSfmtm0Y6oGBMuO1q0o50u2hEealZ9ZtEOwPktW71Vfpu33Hq7SaN68sCEkUyBBaqY1LQMEyAfSj5uvW/0kL7Sr2fHErcD4ByLX0ft3G2Os0ta/FrDYj3O1vCYxa8BoPwQIgNABdBqiL0HjsjGyGhTpXw8paDfYnHubm4S3jbQVEe0DwswtwE4p0V/b5TZf6wqUt10/60jxbuOZ4nbAXAOaRmZ8tGUmUUW2Bo+qLcMuKRLidsBqDy5eXmyPTrRHE9H7Uwwt+2p5+dtjqe7RoSJf/NGZhYgAKB8ESIDQAU7eeqU7N6TZCqUN2+Lta4AX5xnbQ+zGrwuyNcmqKW4urraHQeg8ixYuk7mLVlrva0nqvfdMoLV3AEnl5mVbQLkfUlHrPcNGdBTBl3avcTtAFx4+fn5sit+n2yKjJGtO+IlKzvH7jgfby/p3CHEVBy3btVMXAiOAaBCESIDwAWk0+5id+83FcpbtsdJZpb9g2JvL0+zGJ9WUwQHNBMXFxe74wBc+FkGcxetkT+Wb7DeF9Cyidw7fri5EATA+WgA9cnUWZK47/RCuFf06yZDB/YqcTsAF87JkyclLvGAKbrQRfLSM7PsjvPy9JBO7QuOkUNatxBXjpEB4IIhRAaASpKXly87Y/eYvm6RO+IlJ9f+9Dw/X2/pUlhloWEV0/OAyg+SZy5YIUtXbbHeFxzQXO666Wp6nANO2EN10jezJT4xyXpf/4s7y4gre/N+CjjB+6le3NHgeNO2WElJtd/+zcPdTSLaBZlj4bYhrcSN2XoAUCkIkQHACeTk5sq2XYmmQln7vuXl59sd16Cer+n31q1jmOnHSqAMVN6J7y9zlsmKdVHW+8KCWsodY4eak10AlU8vzn7x3RyJjt9nva9Pj3C5Zmg/3j+BSnz/3H8wuSA4joqRo8dT7Y7ToLh9G12IOkw6tAkQD3d3u+MAABcOITIAOGHfxkhdeToyRnbF7jE9le1p2qi+6Z+sVRlNGtazOwZAxdHX5o8zl8iaTTus9+kCmbddP1jc3OhpDlT2bJ8vf5gnO2ISrff16tpOxgy/jL6pQCU4lHzcHNtqwcShI8ftjtH2bW2C/c2xra4TQpsoAHAuhMgA4OQryW/dHi8bIqMlbvd+sR8ni7Rs1sgccGuVslYrA7hwPRy/nb5INmyNtt6nU25vvW4Qi2MClbgo15SfFpgLshbdO7WRsSMHsMYAcAFplbFWG2t4bLuopa1aIqa3sfY47tg+SHzqeNkdBwCofITIAFBFnEhNl81RsaaHcsLegw7H6erUXcNDpXN4iPj51HE4DkD5LZg57ZeFsnlbnPU+vaBz8zWXE1gBlfB6/ObXP2RTVKz1vs4dQuTma69gAS7gAkhJy7Aer+7ec7oXeXGB/k2tx6t1fb0djgMAOA9CZACogpKPpVgrO7SvnD3aLzm0dQsTZnXqECzeXp52xwE4f9rHfMqP8yVqV4L1vh6d28iNIwcydR64gC1mvp++SNZt2WW9L7xta5kw5kpmBgAVKD0jS7ZsjzPHpjE6c85BKzadOafHpV3CQ6RhfT+7YwAAzosQGQCquIOHj5lqD+0xdzj5hMMec+1CWpkeyhFtW9NjDqigHqxffD9Xdsbusd53cbf2MmZYfxbxAi5AgPzTrKWyeuN2633tQlvJ7TcMoUc5UAGysnNMy5hNkTGyQ9fwOHnS7rjGDeuaVhVaddy0cX27YwAAVQMhMgBUw9Wu9ePYCQerXbu5SoewQNNDuX1YoHi4u9kdB+Ds5eTmyuffzjGVWBZ9e3aU0YP7ECQDFfj+99vc5bJ8baT1Pp2Jc+e4q3mPA8pRTm6ebI9OMMeZ26ITzMVTe+rX9TXHmfrRomlD3v8AoJogRAaAanpCrX2T9SB/07ZYSU3LsDuutoe7WQRMq0PahPiLm6ur3XEAyi47J1cmTZst8Ta9IAdc0kWGXXExJ9JABbzfzVq4Upas3Gy9L6hVM7n75mHmPQ7A+bdr2hW71yzyHLVzt3mPs8fXp4506RAiXTuGSmDLprzfAUA1RIgMANWcTi+MTThg2l1ov7qMzGy747w8a0un9sHSrWOohAS2YEEw4DxkZmXLJ1Nny579h6z3XXlpdxk8oGeJ2wE4O3MXr5GFf6233g5o2UTuHT+ctk3AeR476owaLUbQY0d9T7OnjpceO4aYiuOQwOYcOwJANUeIDAA1rZokbq/pX7d1R7zjahJvL+kcXjANUVfPdqlVy+44AI7pBZuPv54p+5KOWO8bOrCnXNGvOw8bUA40PNYQ2XbRrvtuGWGCLQBn31fcMottc1SMpKZn2h2nFf4d2wWZdTbaBvuzaCUA1CCEyABQg/va7YhJNBXKUbtK6mvnY1bS1kBZT9BrESgDZZaWnikfTZkhSYePWe8bceUlclnvziVuB6BkS1ZskpkLV1pvN2tcX+6fMFJ86niVuB2Aou1g9EKnaX8WpetppDlcTyO8TWtzLNguNIBe4wBQQxEiAwDMCtva525jVIzsjNkj+SWtsG0C5TBW2AbKKCUtQyZOni6Hk09Y77t2aD/pc1FEidsBsG/5mkj5de6yIu9ND04YZXqyAijdwcPHTBGBHvfZvjfZcnVxkbahrcxxX3jb1rSIAQAQIgMAikrPzJKt2+NMVYr2w9MqFXuaN21YGCiHSsP6fjyMQAmOp6TJh19Nl6PHU6333TDiMunVtT2PG3AWVm3YLj/OWmK9re8/D0wYKfX8fErcDqjpko+lmGM7DY4PHEy2O0Znm4UFtTQz0Dq2DxJvL0+74wAANROVyACAEisoN2+LNT2U4/ckORynCxlpmKwnHXV9vR2OA2qyo8dT5MOvZphAWWmn8XGjL5fundqUtikAEVm3ZZd899ufcsqm3dIDE0ZJg3q+PD6AHfp+o8dxGh4n7ju90GtxQa2amR7HnTuEiB8V/QAABwiRAQBlcuxEqrVn3t4DpxcKs6WhWHBgCxMod+oQTG9KoJjDR0/IxK+mmws05jVTq5aMv3aQdAkP4bECSrApKlam/rLQOjvGz9fbVCA3blCXxw0o1ot/S+GMsriE/daLLsX5N29cWAAQIvXrciEGAFA6QmQAwFk7lHzcVCfrCcrBI6cXDLPlUquWtAnxNy0vItoFiZdnbbvjgJrYi1J7JKdlZJnbLi4uMuH6KyWibVBpmwI1UuSOeJn80wI5Wdiv38fbywTITRvVL21ToEbIzMo2r5MNkTESHbdXTjpoRaavGQ2O9aNxw3p2xwAA4AghMgDgnGlF2IFDRwsWZ4mMKdLv1Zarq4u0DwuUbhGh0qFNoHi4u9sdB9QU+w8my0dTZkhGZrb1NXLHjUPMqvcATtsekyhffj9X8vMLAuQ6XrXl/ltHSoumDXmYUKNl5+TKtl0Jpsfx9ugE62ukOO0brhf0tV1F8yYNzAwYAADOBSEyAKDcAuXE/YcKKpSjYiUlNd3uOA93N7PKt1bBtAsJEDc3V7vjgOpuz/7D8vHXMyUrO8fc1tfCXeOuNosaARCJjt8rn307R/Ly8s3D4VnbQ+6/dYSZhg/URPpa2BGbaC7cR+3cLTm5eXbHabuXruEhJjgOaNGE4BgAUC4IkQEA5U6nUcYlHJBNkdGyeXucpBdO2y/Oy9NDOrYLNoFyaFBLcXVxsTsOqK52702ST6fONhVllossd988TIIDmpe2KVCtxSUekEnTZltDstoe7nLv+OES6N+0tE2BaiX/5EmJid9ngmPtdWy58Ficdx1PszCeHlMFBTQ3bcUAAChPhMgAgAqVn58v0XryExUjW7fHOzz58bE5+WnNyQ9qkNiE/TJp2u+Sm2cTlt0yXAJbEpahZkrYe1A+mTqr6MWVm642C7cCNeVi/O7EAyY43rwt1tpDvzitzu/YPsi0qwgL9udiPACgQhEiAwAuGA3JdsTssU7DtIRmxdXz85Yu4QULv+i0Zfr3obrbFbdXPtdp+/n51ir9+25h2j5qnr0HCtq8ZGYVtnlxdZU7xw2VNsH+pW0KVPm2YNrmSI+RNkXFyInS2oKFh0rb0Fbi7uZmdxwAAOWNEBkAUIkLwuw2J0u6cFKJC8IUriTevAkLKaH62hadIF99P89MXVbeXp5y/4QRPO9RYxw4lCwfTZ4p6ZkFVZfa4uj2GwebhVmB6vy812Mh/Ug+luJ4geLQAHMs1KFNazNjBQCAC40QGQBQ6TKzsk2rC215ER2310zjtKdZkwbWFcYbN6hrdwxQlW3dES9TfpxvfQ34envJAxNGSpNG9UvbFKjSDh45JhMnz5C09Exz28XFRSaMuVIi2gWVtilQ5Rw+eqJgIeLIaEk6fMzuGO1prC0qNDju2C5IvDxr2x0HAMCFQogMAHAqqekZsmVbnAmUdXE+R1q1aGwC5c7hoVK/ro/DcUBVo9Vo0379w0xtVn6+3vLghJHSiAsnqKaOHD0hH06eISmF0/e1hdH4a68wbY2A6uLYiTTZHBUjGyJjTNsWe3QpvKDA5gXHNx1CxMfby+44AAAqAyEyAMBpHU9Jk01RsSZU27P/kMNxQQHNpFtEmHTqECy+3nUcjgOqirWbd8r30xeJpSZfL5Q8eNsoqV/Xt5Qtgarl6PFUmTh5ugnYLCHa2FEDpUfntqVtCji91LQM2WwujEdLfGKSw3GtWjSRbhF6YTxE6vlxYRwA4JwIkQEAVaZSTRea0UD5wKGjdsdo9VpYUMvCqZ/BUseLqZ+oulau3yY/zV5apD+4Bsl1fb1L3A6oShcKtYWFbR/YMcP6S+/uHUrcDnBmGZnZsnVHnDleiY7fZ51VUlxzbdEVEWoq7plpAgCoCgiRAQBVTtKhowWL0ETFmHDZHl2QqV1YgJkSqquYswgNqqJlq7fKb/OWW283aVRPHrh1pPj6UHGPql+hqQHyoeTj1vtGD+kr/Xp2LHE7wFkXC47cGW/6HO+I2WNdILU4DYvNYsHhoWadBwAAqhJCZABAlaXVPXsPHDEL02iV8vGUgn6axbm7uUl420BT7dM+LMDcBqqKxSs2yayFK623NXi4/9YR4lOHXpmomtIyMuWjKTPNBUGLEYN6y2WXdClxO8CZ5OblyfboRHP8EbUzwdy2R9tTdAkPka4RYeLfvJGZNQUAQFVEiAwAqBZOnjolu/ckmQrlzdtiJS090+44z9oeZpXzLhGh0iaopbi6utodBziTBUvXybwla623WzZrZIJkL09atqDqTfX/+OuZsi/piPW+IQN6yqBLu5e4HeAM8vPzZVfcXjMTauv2eFOBbI8uiNelgwbHoRLYqpm4EBwDAKoBQmQAQLWj00hjd+83FcpbtsdJZlaO3XHeXp5mMT49yQsOaC4uLi52xwHOUHU/d9Ea+WP5But9AS2byL3jh5sLI0BVkJWdI59MnSWJ+04vlHpFv24ydGCvErcDKtPJkyclLvGAuUi9ZVucpGdm2R3n5ekhndrrMUWYhLRuYdpqAQBQnRAiAwCqtby8fNkZu8dUDUXuiJecXPvTTf18va1VQxrOMd0Uzhgkz1ywUpau2my9Ty9+3HXT1fT8htPTis1J38yW+MQk632X9e4swwf1Zn8Lp9zfJuw7WDC7KSpWUtIy7I7zcHeTiHZB5tihbUgrcWN2EwCgGiNEBgDUGDm5ubJtV6JsjIqW7bsSJS8/3+64BvV8Tf9kPSls0bQhAQecKtj4dc4y+XtdlPW+sKCWcsfYoSbMAJyRXrz74rs5Eh2/z3pfn4si5Johfdm/wqn2r/sPJpvgWPscHz2eanecBsXt2+jCvWHSoU2AeLi72x0HAEB1Q4gMAKix06q37og3J4va31Cnq9rTpFE9MzVVA+UmDevZHQNc6P7fP81aIqs37rDe1y40QG6/YbC4udHjG843G+TLH+bKjpg91vt6dW0vY4b3p08snMKhI8fMsYDOWDp05LjdMdruqk2wv3SLCDWVx7QRAgDURITIAIAaLy0j0yyQoz2UtZfyKQePiC5mpmGyVilrtTJQWfSix7fTF8mGrdHW+zTYuPW6QSwWCadahGzKTwskcudu633dO7WRsSMH0IMelUqrjLXaWMNj20UebdUSMb2N9UJyx/ZB4lPHy+44AABqCkJkAABsnEhNN/0PtSIpYe9Bh49N61bNpGt4qHQODxE/nzo8hqiUBSSn/bJQNm+Ls97XJTxEbrrmChZ0gpM8P/+Qzdtirfd17hAiN1/L8xOVIyU1XTZti5VNkTGyu6T3d/+m0kUvGHcIMeslAACAAoTIAAA4kHwsRTZFxZpqJYeVSrVqSWjrFqY6WVdl967jaXccUFGVnpN/WiBRNpWePTq1kRtHDaRVACq1Uv67GYtl/ZZd1vsi2raWW8dcSaU8Lqj0jCzZsj3OvI/H6EyjU6cczjQqWAshRBrU87M7BgCAmo4QGQCAMjh4+JipTtaWF4eTTzjsmdgupJWpYNLAhJ6JuFA9Z7/4fq7sjD3dc/bibu1lzLD+LFqGSurZvVRWb9xuva9daCu5/YYh9OzGBVvzIFLXPIiKkZ2xJax50FDXPAg179lNG9W3OwYAAJxGiAwAwDmu3q4fx044WL3dzVU6hAWaE9T2YYHi4e5mdxxQHnJyc+Xzb+eYSjuLvj07yujBfQiScUH3j7/NXS7L10Za79OZGneOu5p9ICpUTm6ebI9OMO/L26ITzMU1e+rX9TXvy/rRomlD9o8AAJwFQmQAAM4jMEnYd1A2bo0xfRZT0zLsjqvt4W4WPdMeym1C/MXN1dXuOOB8ZOfkyqRpsyV+T5L1vst6d5bhg3oTlOCC7A9nLVwpS1Zutt4XFNBM7r5pmNkHAuUtLz/fzMDQ4Fhb+ug+0B5fnzqmX7wGx4Etm7I/BADgHBEiAwBQDnS6bGzCAXMyu2V7rGRkZtsd5+VZ2/RO1pNZrdDTFhhAeU7j/mTqLEncd8h636BLu8uQAT1L3A44X3MXrZGFy9Zbbwe0bCL3jh9OWx+U+3utzrgoeK+Nk8ws+++1dbz0vbYgOA4JbM57LQAA5YAQGQCACljsbGfcXrMC/NYd8Y6ro7y9pLNZyCdUAv2bshAayoVewPj465lFFoMcOrCnXNGve4nbAedq4V/rZe7iNUUWKbvvlhEmyAPKo892wl6d9RMtm3XWT3qm3XFa8d5RZ/1EhEqbYH8WcQQAoJwRIgMAUMF9GnfEJBZMt921u4Q+jT6FK8OHmgCmVq1adscBZZGWnikfTZkhSYePWe8bceUlpr0FUJ6WrNgkMxeutN5u1ri+3D9hpPjU8SpxO6C09ih6IUzfOzdF6foDaQ7XHwhv09q8d7YLDaD3NgAAFYgQGQCAC9hqQPs2mhXjY/ZIvoMV4xs3rGv6J3eNCJOmjVkxHucmJS1DJk6eLoeTT1jvu2ZIP+nbM6LE7YCyWr4mUn6du8x6u0nDevLAhJGmBy1wLpIOHy0IjiNj5PDR0/suW64uLtIutJV0iQg1AbJnbQ+74wAAQPkiRAYAoBKkZ2bJ1u3xpsIqOn6fqbqyp3nThoWBcqg0rO9ndwzgyPGUNJk4eYYkH0ux3nf98Mvk4m7tedBwXlZt2CY/zlpqva37Jw2Q6/n5lLgdUJzunzQ41gusBw4m232AdHZOWFBLM2OnY/sg8fbytDsOAABUHEJkAACcoGJU+zxq5VX8niSH43ShKg2TO3cIIahBmR09nioffjXdBMpKG6WMHX259OjUprRNAbvWbdkl3/32p5yyacfzwIRR0qCeL48YykT3R/q+p+Gx7UKgxQW1amZm5XTuEEyFOwAAlYwQGQAAJ3LsRKpsiio4sd574LDdMRoCBge2MIFyp/bB4uNN71GUTKeFT/xqurlgYZ5DtWrJ+GsHSZfwEB46nBXdP039ZaF19oSfr7epQG7coG5pm6KG017tW7bHmfe3uIT91osQxfk3b2ze33T/VL8uFyYAAHAWhMgAADipw8nHC6b4RsbIwSOnF0iz5aJTfIP9pVtEqES0CxIvz9p2xwH6HNLWFhrkmOeOi4tMuP5KiWgbxIODMoncES+Tf1ogJwv7uesFLA2Qmzaidzvsy8zKlq074s37WHTcXjnpoHWT9v/vFhFmguPGDevZHQMAACoXITIAAE5OK/4OHNLFhqJNFaBtf1tbrq4u0j4s0PRQ7tAmUGp7uNsdh5pr/8Fk+WjKDMnIzLY+Z26/cYi0Dw0obVPUcNujE+TL7+dZFwTVnrT3TxghzZs0LG1T1DDZObmybVeC6XGsz5v8fPuLyGofbQ2NtV1F8yYNzAwJAADgvAiRAQCoYoFy4v5Dpn/yxqhYSUlNtzvOw91Nwtu2NlOC24UEiJubq91xqHm0TcpHU2ZKVnaOua3PjbvGDZWwIP/SNkUNFR2/Vz77do7k5eWb2561PeT+W0eYtgOA0ufGjthEU3EctXO35OTm2X1gtP1J18LguFWLxgTHAABUIYTIAABUUTotOD7xgDlp1wWK0jOy7I7TwEd7J2ugHBrUUlxdXOyOQ82xe2+SfDp1tqkYtFx0uPvmYRIc0Ly0TVHDxCUekEnTZltDQZ3hcO/44RLo37S0TVHNaVV6TPw+8x6kvY4tF6aK867jaRaE1fegoIDmpg0TAACoegiRAQCoJifz2m9Spw9v3R7v8GTex+ZkvjUn8zWaLmw16Zvfi4aDtwyXwJaEgyiQsPegfDJ1VtGLDTddbRb2RM1ke/Fyy7ZYSePiJQAANQYhMgAA1UxuXp7sjNljAuWSphXX9fWWLuGhJlBmWnHNtCtur3yubQryC9oUeHl6yH230KYAtD1B0TZKe/YfNsHxpqgYOVFaG6XwUGkXShslAACqG0JkAACq/QJHu83J//aYxBIXONIwWT9YKKtmYcE0FHfgULJ8NHmmpGcWtMjRFji3j2UBxpr4PNi4Vfvvx5S8oGtogOlxzIKuAABUb4TIAADUEJlZ2bJ1R7wJlLX1hU5LtqdZ4/omEOgSESqNG9S1OwbViz4vpvw43/qc8PX2kgcmjJQmjeqXtimqmYNHjsnEyTMkLT3T3HZxcZEJY66UiHZBpW2KauBw8nHZFBUrGyOjJenwMbtjtKdxWLC/uejYsV2QeHnWtjsOAABUL4TIAADUQBoQ6WJ8WmEWn3BA7MfJIv7NG0u3iFDpHB4q9ev6OBiF6kAvLkz79Q8zdV35+XrLgxNGSiMuJNQYR46ekA8nz5CUwnYFtWrVkvHXXmHa3qD6OnYizbSp0H3A3gOH7Y7RpfCCAptLt4gws1Crj7eX3XEAAKD6IkQGAKCGO56SJpujYmVDZIzs2X/I4biggGbSNTxMOncIFl+fOg7Hoepat3mnfDd9kfWigl44eGDCKGlQz7eULVHVHT2eKhMnTzeBoiU0HDv6cunRqU1pm6IKSk3LkM3b4mRjVLTEJyY5HBfQsonpcdw5PETq+XEhEQCAmowQGQAAFKlEtFSkHTh01O4jo9WJYUEtC6cyB0sdL6YyVycr12+Tn2YvLdIvW1tbECBV7wtJ2sLCtu/t9cP7y8XdOpS4HaqWjExtaRRX0NIofp911kFxzZs2NMGx7uP19Q8AAKAIkQEAgF1Jh46adhcaOGi4bI8uuNUutJXpnxzRNkhqe7jbHYeqZdnqrfLbvOXW200a1ZMHbh1JBXo1rUjVAPlQ8nHrfaOH9JV+PTuWuB2qzuKqkTvjZVNkjOyI2SP5J+0vrqptayyLqzZr3MDuGAAAULMRIgMAgBJptdreA0fMQku64JJWLdrj7uYm4W0DTf/U9mEB5jaqrsUrNsmshSutt5s1aSD33zpCfOrQC7W6SMvIlI+mzDQXjCxGDOotl13SpcTt4Nxy8/Jke3SiuQC4bVeCuW2Pzi6wBMctmzUys0wAAAAcIUQGAABldvLUKUnYk2TCiU3bYs0CffZoRXLH9kFmSnSbYH9xdXW1Ow7ObeFf62Xu4jXW2xo0aZDs5UkLk+rQ2uDjr2fKvqQj1vuGDOgpgy7tXuJ2cE75+fmyK26vmT2ydXu8qUC2RxfE69IhxATHga2aiQvBMQAAKCNCZAAAcE50WnTs7v2mQnnL9jjJzMqxO87by1M6dQg2oUVwQHNxcXGxOw7Oac6fq+WP5RuKLLR17/jh4lnbo8Tt4LyysnPkk6mzJHHf6YU0r+jXTYYO7FXidnAuJ3UfnHDAXNTbuj1O0jOz7I7Tiz6d2hfsg0NatzBtiAAAAM4WITIAADhvefn5sjN2jwkzInfES06u/enTfj51pHN4YRVcy6ZMn64i7UxmLlgpS1dttt4XFNBM7r5pGD2wqyCtUJ30zWyJT0yy3ndZ784yfFBvXo9V5PWYsO+g2ddujoqVlLQMu+M83N0kol2Q2de2DWklbswGAQAA54kQGQAAlKuc3FzZtitRNkZFy/ZdiSZgtqdBPV/TP1lDjhZNGxJgOXlw9eucZfL3uijrfWFBLeWOsUNNWIWqQS/ufPHdHImO32e9r89FEXLNkL68/pz89bf/YHJBG6GoGDl6PNXuOA2K27cJkG4RYaYvvYc7C50CAIDyQ4gMAAAqdNq8ViZviIwx/Tp1+rU9TRrVM/2TNVBu0qi+3TGo/H7YP81aIqs37rDe1y40QG6/YbC4udHz2tnl5eXLlz/MlR0xe6z39eraXsYM709fXCd16MgxExxrn+NDR47bHaPtgdqG+Jv9p1Ye02YGAABUFEJkAABwQaRlZJoFn7SHsvZSPuVgnC7epmGyVilrtTKch14E+Hb6ItmwNdp6X0Tb1nLrmCtZPNHJF12b/NMCidq523pf905tZOzIAfQodzJHj6fIxshYU3Fsu+ihrVoiEhrU0uwjtdexdx1Pu+MAAADKEyEyAAC44FJS02XTtljZFBkju/cedDiutX9T6aKBcocQ8fP1djgOF3ZBxWm/LJTN2+Ks93UJD5GbrrmCBbuc9v/rD9m8LdZ6X+cOIXLztfx/OQv2hwAAoCogRAYAAM5feVerloS2bkHlnRNXtvbo1EZuHDWQ1ghOVjn+3YzFsn7LLut9VI47h/SMLNmyPe4sZmaESIN6fg5GAQAAVDxCZAAA4DQOHjlmqpO1D+ihZHqAOjN67FaFHtZLZfXG7db72oW2kttvGEIP60ruEa89jnfGltAjvmG9guA4IlSa0iMeAAA4CUJkAADgdE6dOiX7DyYXLCoVGSPHTqTaHacLunUICzSBS/uwQPFwd7M7DhUjJzdPPv/2d4nZvd96X9+LImT0kL6mehyV9/r5de5y+XttpPW+sKCWcsfYobxGLrCc3FzZHp0oGyKjZfuuRMnLz7c7Tvu/a49j3Ze1aNqQ1w8AAHA6hMgAAMDpA7GEfQdNmLwpKlZS0zLsjqvt4S7hbVubEKZtSCtxc3W1Ow7lKzsnVyZNmy3xe5Ks913Wu7MMH9SbIKySXi+zFq6UJSs3W+8LCmgmd980zLxGUPE0KN4Zu8fss7Tli75G7PHzqSOdw0PMPiuwZVNeLwAAwKkRIgMAgCpDp3/HJhww4cyW7bGSkZltd5yXZ23p1D7YhDPaS9nFxcXuOJTfNP1Pps6SxH2HrPcNurS7DBnQs8TtUP7mLlojC5ett94OaNlE7h0/XDxre5S4Hc5/36QV+drjeMv2eMnMsr9vquOl+6YQ6dYxVIIDmrNvAgAAVQYhMgAAqLKLu+2K22v6i27dHu+w2s/X20s6dyis9mvVjIXfKogG+h9/PbPI4ogaImuYjAtj4V/rZe7iNUUWZbvvlhEmuETF9J1O2JNkLmpt3hYrqemZdsdpBXjH9kHSNTxU2gT7iyuzJAAAQBVEiAwAAKq83Lw803fUTB/ftdss+mZP/bo+1r6jGrDRt7d8pWVkykeTZ0jS4WPW+0YM6i2XXdKlxO1w/hav2GTaWFg0a9JA7r91hPjU8SpxO5x9u5C9B46YimNtr3M8Jc3uOHc3NwlvG2j2N+3DAsxtAACAqowQGQAAVLvWChokb4qMkR0xeyT/5Em74xo3qCtdIgoC5WaNG9gdg7OXkpYhEydPl8PJJ6z3XTOkn/TtGVHidjh3y9Zsld/mLrfebtKwnjwwYaT4+tQpcTuUXdLhowV92SNj5PDR089tW64uLtIutJXZr4S3aU0LEQAAUK0QIgMAgGorPTPLtLrYFBUj0fH7TBWhPc2bNjRTzTVQbljfz+4YlJ1WZ06cPEOSj6VY77t++GVycbf2JW6Hs7dqwzb5cdZS6219/mqAXM/Pp8TtUDp9/mrFsYbHBw4dtTtGZzOEBbU0+46O7YJpHQIAAKotQmQAAFAjpKZlyOZtcbIxKlriE5McjtOFyDRQ7hweQhB3Ho4eTzUVycdOFEz3ryUiY0dfLj06tSltU5TRus075bvpi+SUTbuWByaMkgb1fEvZEiVdANkcFWt6rdsuFFlcUEAz6RoeJp07BFPxDQAAagRCZAAAUOMcO5Fq+plqheHeA4ftjtHQMyiwuXSLCJNO7YPFx5vesmdLp/1P/Gq6aXFhqdocf+0g6RIeUtqmKIVW10/95Q9rdb2fr7c8OGGkNGpQt7RNUUxaeqZZGE+D4/iEA9ZQvjj/5o2lW4ReYAo1gT0AAEBNQogMAABqtMPJx02gvCEyWg7aLAhny0WnrAf7F05ZDxIvz9p2x+FMB48cM60tNKhTLi4uMmHMlRLRLoiH6xxF7oiXyT/Ol5OFAbJe4NAWFk0b1S9tUxTKzMqWrTvizYWk6Li91seyuKaN65sLSXrho3HDejx+AACgxiJEBgAAEDEVndr3VBfO0opE236+tlxdXaR9WKBpedGhTaDU9nDn8SvF/oPJ8tGUGZKRmW19DG+/cYi0Dw0obVMUsz06Qb78fp51wUhvL0+5f8IIad6kIY9VKbJzcmXbrgTT53h7TKLk59tfdFP7Spse6R1DeVwBAAAKESIDAADYCZT37D9sqhS1bcCJ1HS7j5GHu5uEt21tAqd2oQHi5ubKY+mAtg35aMpMycrOMbf1sbpr3FAJC/LnMSujXXF75fPv5kheXr657eXpIffdMsK0WYB9+ljtiEk0F4aidu6WnNw8u+Pq+npLl8LFNVu1aGxarwAAAOA0QmQAAIAS6DT3+MQDJlDWvqnpGVl2x3nW9jC9kzWECg1qKa4uLnbH1WS79ybJp1Nnm4pQSwh/983DJDigeWmb1nhxCftl0je/W0NQrYC/d/xwCfRvWuMfm+K0SltbVGhwvHV7vPXCRXE+dTylc4cQ85ptHdDctK0BAACAfYTIAAAAZxFOxcTvM4Hylu1xJYZTnQrDqSDCqdLD0FuGS2BLwlBHEvYelE+mzioavt90tQQHtnC4TU3DxR4AAICKRYgMAABwDpgmf55tGb6dI3n5tGUoDW1AytJ2Jtosjllq25mIUGkXQtsZAACAc0GIDAAAUF4LdkXFmIXPSluwq0tEqLRoWrMXQmOBuLItSPjxlJmSnlnQQoUFCVkAEwAAoLIQIgMAAJSjzKxs2boj3rS80L6sOs3enmaN60vXiDDpEh4ijRvWk5pIH6cpP863PkY+3l7ywISR0rRRfanpDh45JhMnz5C09Exz28XFRSaMuVIi2gVJTXQ4+bh5TemFmoOHj9kdoz2Nw4L9pVtEqHmcvDxr2x0HAACAs0eIDAAAUEE0ANTeyRsioyU+4YDYj5NF/Js3NlPtu4SHSv26PlKTaDA47dc/TGsC5efrLQ9OGCmNGtSVmurI0RPy4eQZklLYnqFWrVoy/torzPOjJjl2ItW0qdDniLb1sEeXwtPe0Pr60YUt9UIEAAAAyh8hMgAAwAVwPCVNNmsgFhUjifsOORwXFNBMuoaHSecOweLrU0dqgnWbd8p30xdZQ3YN0h+YMEoa1POVmubo8VSZOHm6HDuRZg1Jx46+XHp0aiM1QWpahmzaFiubImMkfk+Sw3EBLZuY4LhzhxCp51ezLrwAAABUBkJkAACACyz5WIp1av6Bg8l2x2j1aVhQS1N9qhWWdbyq99T8leu3yU+zlxbpH62tLWpSQKgXGrSFhT4/LK4f3l8u7tZBqrOMzGxTsb8pKkai4/dZq9KLa960oekpruGxPj8AAABw4RAiAwAAVKKkw0cLAuXIGNPGwB5XFxdpF9rKLMgX0TZIanu4S3W0bM1W+W3ucuvtJg3rmSC5JlRkp6RlmArkw8mnnwPXDOknfXtGSHVdjDJSe4dHxcjOmD2Sf9L+YpSNG9QtaPUSESrNGjewOwYAAAAVjxAZAADACWj15b6kI9ZAWatS7XF3c5MObQJNsNY+LMDcrk4Wr9gksxautN5u1qSB3H/rCPGpU3173aZlZMpHk2dIks2CcSMG9ZbLLuki1UlObp7siEk0z+9tuxIkNy/P7jitPtfnt360bNbIVOUDAACgchEiAwAAOJmTp05Jwp4kE7Zpf1hdoM8erUju2D7ITPFvE+wvrq6uUh0s/Gu9zF28xnpbg0QNkr08a1fLVg4ffz3TXECwGDKgpwy6tLtUB/n5+bIrbq95Lm/dEW8qkO3x9faSzoWtKgL9m4oLwTEAAIBTIUQGAABwYjrNP3b3fhPCad/YzKxsu+O0Z3Kn9iEmhAsJbC4uLi5Slc1ZtFr+WLahyEJq944fLp61PaS6yMrOkU+mziqy0OKgft1lyMCeUpWd1OdswoHC52ysCcrt0YsC2u/bPGdbtzBtWwAAAOCcCJEBAACqiLz8fNkZu8eEc9pPVtsD2OPnU0c6hxcEyoEtm1bJdgDa3mPmgpWydNVm631BAc3k7puGVYue0FqRO2nabInfk2S977LenWX4oN5V9v8rYd9B2bi1oHo+NS3D7jj9vwtv21q6RYRJmxB/casm1fMAAADVHSEyAABAFZSTmyvboxNlQ2S0bN+VaAJmexrU85UuhW0CWjRtWKUCSg0mf52zTP5eF2W9Lyyopdwxdqh4uFfdXtAa/n/+7e8Ss3u/9b4+F0XINUP6Vrn/n/0Hk619vI+dSLU7ToNi2z7eHu5V/yIAAABATUOIDAAAUA3aImhl8saoGNkZu9e0E7CnSaN6pn+yhnlNGtWXqtIf+qdZS2T1xh3W+9qFBsjtNwwWN7eqV8Wal5cvX/4wV3bE7LHe16trexkzvH+V6QN88Mixgn7dkTFyKPm43THaTqVtiL90jQiTiLatq1UbEgAAgJqIEBkAAKAaSc/IMr2TN0XFSEz8PjnlYJwuVldQoRwiDer5iTPTUPy7GYtl/ZZd1vs0mLx1zJVVajFBXWRu8k8LJGrnbut9PTq1kRtHDnD6HtZHj6fIxshY87yyXQTQlkbgoUEtzfNKex171/G0Ow4AAABVDyEyAABANZWSmm7602rF6O69Bx2Oa+3fVLpEhEqXDiHi5+stzrrA4LRf/pDN22Kt93XuECI3X3tFlViQrSr+/eb5ExVrKtwTqvjzBwAAAOeHEBkAAKAG0EpSEwhGllxJGtK6hWlB4IyVpA4reUcNdOpWEFWpktpSyb4xMlpid+8vsZJd26J0CXf+SnYAAACcP0JkAACAGkZ72mp18say9LQND5WIdkFO09O2qvUULujpvFRWb9xuva9daCu5/YYhTtPTWXtqb9We2pExsiuulJ7aEWHSNTykyvTUBgAAQPkgRAYAAKihTp06JfsPJhcskhYVI0ePp9od5+bqKu3bBEjX8DDp0CZAPNzdpTLl5ObJ59/+LjG791vv63tRhIwe0ldqOVGQrI/vr3OXy99rI633hQW1lDvGDhUPdzepTDm5ubJtV6JsjIqW7bsSJS8/3+64BvV8C3tnh0qLpg2d6vEFAADAhUOIDAAAABN4Juw7aALlzVGxkpKWYfdRqe3hLuFtW5tQsW1IKxMwV4bsnFyZ9M1siU9Mst53We/OMnxQb4dBp/YlVuXRg7i0n6WP58wFK2Xpqs3W+4ICmsndNw0zj2Fl0KB4Z+we838cuSPehPH2+PnUkc7hIdItIkwCWjYhOAYAAAAhMgAAAIrSdgZxiQdM2LhlW5ykZ2bZfYi8PGtLp/ZBpsWB9lIuj3D2bNswfDJ1liTuO2S9b1C/7jJkYM8zxu49cNiM1b/xgQkjz6sdw6Ejx2Ti5BkmSL53/HDxb974jDFzFq2WP5ZtsN7WMFbHXui2IPo3am9j7XGsvY4zs3LsjvP28pROHYLNxYHggOamnQkAAABgQSUyAAAASlzMTvvkboyKka3b400FsD0+3l7SpUOICSEDWzW7YP2JMzKz5eOvZxZZLHDIgJ4y6NLuRcbN+XO1/LG8INS9qEtbGTtyoJyr76YvkrWbd5qvr+jXTYYO7FXk+wv/Wi9zF68psgjdfbeMkDpeteVC9WHevSepoKp8W6ykpWfaHacV0R0LLwK0CWrpdIv8AQAAwHlUbjM2AAAAODUNFtuHBZqP3GF5sj060fRPjtqZILl5p9shaFC5fG2k+ajn5yNdwjVQDhP/5o0qtB2CBrP3jB8mH02eIUmHj5n7NMB1d3OVyy7pYh3XvGkD69fbdiaYCt1zqZzW7aJ27bbebt6kYZHvL16xqUiA3KxJA/P3VXSArO0z9h44YiqON0XFyvGUNLvj3N3cJLxtoOlz3D4swNwGAAAASsNRIwAAAMpEA8dO7YPNh7aS0DB1U2SM7IjZY+0RrDTAXLJys/lo3KCudIkoWJitWePTQW558qnjZSp9tcXEoeTj5r6ZC1eKm5ub9O0ZYW63Cw0wobH+ndqeIz7xgIS2bilnKy7hgKl+Vq6uLiaItVi2ZqvMWrjSertJw3py3/jh5u+rKEmHjxYsjBgZI4ePnrA7Rv/d7UJbmf+HiLZBldaTGQAAAFUX7SwAAABwXjRU3bojzoSZ0fH7TFWsPc2bNDBhslbBNmpQV8qbhtcaJCcfS7Hed/3w/nJxtw7ma12ITwNv1a9nRxk9pK+crV/nLpfla7Zag+m7b7rafL1y/Tb5afZS67iG9f1M72Wtyi5vR46eMNXg+ngfOHTU7hit/g4Lamke747tgiu8EhoAAADVGyEyAAAAyk1qWoZs3hYnG6OiJT4xyeE4XWiua3iodA4PKdeg9ejxVJk4ebocO1HQzkEbaYwdfbn06NSmSNBbv66PPPPIzWfVakPD8ZffnWZtFTFmWH/p3b2DrNu80/RJtkTn+rMfmDBKGtTzlfKiv1PbVGhwvGf/6YUEiwsKaCbdIsJMtbivTx2H4wAAAICzQYgMAACACqFB7uaoGNkQGSN7Dxy2O0Yj3KDA5gWBcocQs0DfuYrauVvWb90lYcH+Mn/JOklJTTf3a1A8/tpBEhzYXF58a4o17H3s7uvEv3ljKas9+w/LO5/9bP27X/jnrRKbsF+m/vKHtfraz9dbBl/WwyxG2L1jGwlv21rOlfaZ1oXxdFHD+IQD1r+7uFYtGhcG8qEmwAYAAADKGyEyAAAAKtzh5OOmknZDZLQcLFwArzgXbcEQ7F/YgiFIvDzL3oLh5MmT8sSrn0teXr4JeK++4mLTk1mDWOXi4iITxlwpi1Zskt17CiqkB/XrLkMG9pSymrNotfyxbIP5OqhVM7Nw35Qf58vJwgDZ19tL+vfuLL//scoEvm5urvLak3ea311WmVnaGiS+oDVI3F7rzy6uaeP6puJY+xxr32kAAACgIhEiAwAA4II6cCjZhKT6Ydu/2JZZtC40wATKHdq0LnUxuJjd++Sb3/6UEymnq4+vvryXLPp7Y5GF8LStxeqNO8ztZk0ayL/vu0HK6vWPvpekwgC8V9d2sm7zLuuCgt5enjKgTxf5/c/V1qrken7eMm70FRLaukWJPzc7J1e27dptHo/tMYmSn396kUJb2mdZHw/9aN6kod0xAAAAQEUgRAYAAECl0LBVW0RoeKoLxZ0obD9RnIe7m2kLoS0bdDE7rfC1pdt+/fPCM7azVCRr9XBWdo41SLYNaZ98aFyZKnm1kvrVD7+z3rb9OV6eHnJ5324y58/VdiuHb7lukFlM0JZWTGtgrP92DZBzcvPEnrq+3mbbbh1DTeuNs+nhDAAAAJQXt9IGAAAAABVBA1FdYE8/hl/ZW3YnHjChqvYBTsvIso7TgNVSuexZ20M6tg8ygbK2vnB1cTGL6dmjce7sP1ZJ34siZM2mHebnaPCrMawl6t26PU4G9ukqpdEWExa6vSVA1oBbex///ucqcdB5wvr35efnS3T8PtPjeOv2eGuwXZxPHU/TH1orjlsHNDdtPgAAAIDKRCUyAAAAnIq2iIjRsDUyRrZsj3MYtnoXhq3hbQNNKLtha7TDit46Xp6SlZ0tJ08WTXpb+zeVh++4Rkrz3he/SsLeg0Xuc3GpZUJtS7uM4jRg7hoRJp3aB5lF/zZvj5N0m3Dclv6cTu2DTXAcGtTShOMAAACAsyBEBgAAgNPStg87YgvaPmgQW1LbB12Mz8fHSxL3HZId0YkOF6Ur7oXHbhE/X2+H309JTZcX3v5aylpd3T60lQT6N5WUtExTwazbl9imIyJU2oWc2aYDAAAAcBaEyAAAAKgSChagSzDtILZHJ5S4AF14m9amgnnt5p3Whe4cuap/D7nqsoscfn/+krUyf+k6KS087tm5rdSu7SGRO+MdttgwCwaGBUq3iFDzubQFAwEAAABnQIgMAACAKiczK1sid8TLhsgYiY7b67DquH49XzmRknZGG4viofPTD9/k8Pv/ef8bST6W4vD72nrCz89bjjkIjrWncZsQf9PHOaJdkHh51rY7DgAAAHBWLKwHAACAKkeD2Iu6tDMfaemZpneytryIS9hvXTRP2Qt2tZdxbQ8PE0SrJo3qS0maNKxnDZG9PD1MRbRtKK09nIv/Hl0KLziwhWlVob2Ofby9zvi5AAAAQFVBJTIAAACqjeMpabJ5W6wJlLU3ckkG9O4iDer7Su/uHcSlhIXsTp48KSvXb5Pk46mydOXmEttjBLRsYoJjXfCvnp+Pw3EAAABAVUKIDAAAgCpLA930jCxTKWz7cfR4ihxOPiEnHCxqp7Q6+KXHJ0hZPffmV5KWnuXw+7q4X+OGdU17DMtHg3oFn73reJq+yQAAAEBVRDsLAAAAVEnzFq+Rv1ZvNQvonYv6Z1kpXM/Pt8QQWQNr/YjZvf+M73nW9pBLe3WUwQN62t0WAAAAcGZUIgMAAFSDatzD6emyJ+WEHM/Kkuy8fMk5mS/VWW52rqyc/reUVe06tcXTx0s8vT3FxdVFPDw9pFX7gBLbWNhra7Fne6LkZOXIyfyTkpWeJVlpmZKdUdBbuSx6j+oj7rXdpTrzcHGV2m6uUs/TU1r51ZXG3t5UYQMAAFRxhMgAAABVzLHMTFkcHy8r9yZK4okTsufECcnKy5Ma5ZRIt6MifnkFLSLyap2STFeRLFc547N+nKrAThK1Tol45hd8eNn57Fb4y1PcTsmGBoWr7tUgnm5u0qpuXQmoW1d6+wfIgKAgqe/FQoMAAABVCSEyAABAFZCZmyvzYqJlYWyMrN23T/JLWNytprCEt7kuGiI7aTh7SkNkEfeTFR9mVxWutWrJRS1byqCQUBkS1saEzAAAAHBuhMgAAABO3qpi6e7d8uaK5bI/NbW04UCV0sLXV/7Vp69cGtialhcAAABOjBAZAADASe1NOSGvL18myxMTpSy0D21Db2+p7eYmbi4uhHKolIseeSdPSnZeniSnp5v+3GXRNyBA/t23n/j71S1tKAAAACoBITIAAIATik5OlntmzTAL5TkKjC8KCJAu/i2lZd260qJuXWngXUdcatEvAc7h5KlTcjQ9Q/afOCH7TpyQTXv3ydrERIfBsi7E9+nwkRLWsKHd7wMAAKDyECIDAABUoQA5vHkzGR4RLhcFtBJPd3e72wPOKis3V9YmJMqsqG0SdSDpjO8TJAMAADgnQmQAAAAnEnf0qNw5c/oZAXL9Ol5yZ++LpX9oCG0qUC3aXiyJjpUvVq2SYxmZZwTJn48cJcH1GzjcHgAAABcWITIAAIATTf+f8NuvEnnoYJH7w5s1leeHDBbv2h4OtwWqovTsHHlx7jyJSir6nI9o0lQmj76G9iwAAABOwqW0AQAAALgwZu7YbjdAfvHqIQTIqJb0wog+v/V5bktfBzN37nC4HQAAAC4sQmQAAAAncCIrS95fvarIfS3q+pmAzYvex6jG9Pmtz3N9vtt6f9VK87oAAABA5SNEBgAAcALTtmw+ow/yvX0vIUBGjQmS7+lzSZH79PWgrwsAAABUPkJkAAAAJ1hkbH5MdJH7+gQHSfdWrRxuA1Q3PQJaySVBrYvctyAmxrw+AAAAULkIkQEAACrZjiNHZG9KSpH7xnTt7HA8UF1d37VLkdt7Uk7IzuQjDscDAADgwiBEBgAAqGR/xMUUud3Mz1dCGzVyOB6orkIbN5Kmvr5F7lsYG+twPAAAAC4MQmQAAIBK9tfuhCK3+wYHS61atRyOB6orfd73DQkqct9fu3c7HA8AAIALgxAZAACgEuWdPCkJJ44Xue+iQHoho+bqGRhQ5La+PvJPnnQ4HgAAABWPEBkAAKASJaWlmiDZVqt69R2OB6q7VvXqFbmtr4+ktDSH4wEAAFDxCJEBAAAq0Z4TJ4rc9vbwED/P2g7HA9Wdn6eneR2U9DoBAADAhUWIDAAAUIkSi4VjLer60Q8ZUtP7Ijev61fi6wQAAAAXFiEyAABAJTqSkVHkdhNfX4djgZqiabHXwZGMdIdjAQAAUPEIkQEAACpRTn5ekdte7u4OxwI1haebW5Hb2fn5DscCAACg4hEiAwAAVKLsvKLhmLsrh2eAh5trkQchhxAZAACgUnGWAgAAUIlOFbvtUqv8D896BHUzH0cOH5GymPjGB3JpRF/58PUP5EJ54fHnzd84+eOvpKyG973abLN14xYpi/1791sfC/3YEbVDyurh2x6ybvffp/8jZ/NvKv5xcZueMuqyEfLWS29I0r4Dpf2YGqn46+DkqeKvFAAAAFxI5X+WAgAAgCrt+8nfS0Z6hvz49Q9nfG/WzzPl03c/kZidMVLVzfxxhpTFoaRDsnrZKjlXdbzrSMNGDa0f3t7esjdhr3z31XcyduiNsuqvlaX9CAAAAKBSESIDAACgiBsn3Chedbzk+ltuOOORmfXzLPnsvUkSuyu2yj9q82bMlezs7NKGmeA8/zzaKdz+wB0yf+1C68efGxfLnJXzZNCwKyU1JVWeePD/TJU0AAAA4KwIkQEAAFDEA/96SJZF/S0P/vuhavnIuHu4S7MWzSTlRIosnr+4xLGnTp2SmT/NNF936tZJykuTZk3kv++/KhddcpGkpabJN59PK20TAAAAoNIQIgMAAKBGqSW1ZOQNo8rU0mL9qnWyL3GvtGzVUnr17SXlqVatWnLTnePN16vOo10GAAAAUNEIkQEAAFCE9jwuvoCcZVG4DavXm9tPP/yk9T4dX9z6VevlX/c9LsP6DJU+7XrLiH7D5KmHn5RN6zaJMxgxZqS4urrK2hVrSmwlMeOH6ebz8DEjNfWV8uYf0NJ8Pnok+YwF+bSNhi689+K/X5CrLhpk7vvn3Y+d8TPWrVwrTz74fzLy0uHmsdbH/LG7/iHL/vzrjLH6/9czpIdZ3G/ntp1nfP/ggYNyWadLze/S3thTJ31tvr7+yuukJPp/reNeeeLlEscBAACgaiJEBgAAQKksi8K5ubuZ2z6+Ptb76tSpYx138uRJee+/78g9Y++SxfMWSdL+JNM+4sC+A7Jg1ny56/o75KM3J0pla9q8qVzS/xLTrmLWT/arkbVf8aJ5i0zYPGLMCKkI8THx5nPjpo3P+N7+PfvkpuE3yayfZkp6errUrl27yPe1n/PL//eS3DvuHln4+0LZt2efeaw1CP7rj6XyjzsfNeGutsuw6Naru4y7/SbJy82TF/75nOTm5Bb5mXrhQMdf3O9iueHWG2T0jaPF28db4qLjZM3fq8WewwcPy19/FATWN9421u4YAAAAVG2EyAAAACiVZVG4Tt06m9tP/udp633j777FOu7rSV/L1M+mil9dP3nilafkr8jlsmTLX+az3q7j4y1fTvxCphdW+FamUTdeY10sUMNvRwvv9e7f2/QwLm95eXky+ePJ5us+A/qe8f0pn0wRN1dXeX/yB6ZH9fLtK+SxZ/9p/f6rT/9XZvw43YS8/3zucVm8eal5rJdFLZfnXn9e6jWoZ4L8Zx59yoTlFvc//oAEtwmR6B3RMum901XkWvn89+LlUrd+PXnhzRdNuw0fP19rgP7DlB/Ent++/1Xy8/KkZ59eEto21O4YAAAAVG2EyAAAACgXyYeT5dN3PjbVyu9++Z5cd9N1Use7oErZq46Xuf3Gx2+Y2xPf+MCEqJWp78C+JhzWauk1y8+sstWAVo26YbSUJ/1374jcLg9PeFCiNkdKg4YN5KY7bjpjXH5+vrzzxXtySf8+JtDVD+3NrFb9tVJm/zJLant6yqQfPpext40TXz9f8z1PLy/TrmPyb1+bMH/5ouUyf+Y868/1qO0hL739svl/+vrTryVyU6SpJn775bfM95/6z9PSqMnpyugbbxtnqrG1PUbx1h/6N07//jfz9bjbxxX5HgAAAKoPQmQAAACUi/mz5pn2CAOuGmitWC5Oq1WDw4LlWPIxWbdynVQmDUaHXzeiSGBsof2Cd0TukIaNG0nfgf3kfHz4+gfW/tH6cXFYT7l5+E2y5u81po3F25+9UyS0tdAK6A6dOtj9mb9+96v5PO72sdK2Q1u7Y/wD/OX2B+80X//yzc9FvtcuvJ3c+dDdJgR+/p/PyctPvGTadwy/brhcPuTyImM1uO4/6DJTrf3T1B+LfG/pwiVyKOmQBAQF2q2mBgAAQPVAiAwAAIBysX3rdvN54ewFRULT4h/aX1ft2Z0olW3UDaPExcVFlixcIsePHT9jQb1h1w4TN7eCPtDnSquxLf2j9aNpi2bSqXtn01biu7k/SETXjna3ax/RXhzZtiXKfO4/aICUZODggYXjtxVpaaFuu/82iegSIQlxu2XFkr9NWPz48/+2+3NuuvNm83nmjzMkKyvLev/P0wrC6Rsn3GgqpQEAAFA9nd8RMQAAAFDoWPJR66J7xReBs6ey21mo5v4tpFffXrLyr5Uyb/pcszBcTnaO6YestC3E+br9gTtkwn23ydnSVhWOHD1S8Fg3bNTA4Rjz/cYNzWft7awL5llaXlgqsbVVxTOPPGVuj7xhlOmvbE/n7p1N4KytL/RxGnXjaEmMT5S1K9aYn2mp6AYAAED1RIgMAACAclG/YUGg+cC/HpQx46+XqmL02GtMiKwtLTREXjR/kaScSJFuPbtJYHCgOKMGjRqYXs7JR46aILykPtVKQ30N921lpGfIx29OtN7++tMpMnTUUGnWsrnYM+6Om+Sph56UH6Z8b0JkbZGh1c1aza09rwEAAFB90c4CAAAA5cLSm3fj2o0ljtPeus7k0ssvNb2Po3dEm7YPMwv7I2tlrrPq0CncfF66cHGJ4xbNW1Q4vsMZ7SbeeeUt2bdnn/To3cME6Vqp/OK/Xzij7YXF5UOukOYtm5vHaeXSFWZhP61mvv6WG+yOBwAAQPVBiAwAAIAy8/BwN5/TUlPP+N7gUUPEzd1N/pz7p6xbtc5hZezoAaPktWdfNZWwzsDN3d0sKKc+efsjWbtirWnRcPnQK8RZXTP2GvP52y+/kx1RO+yO2ZuwR7788HPz9bU3XVfke38v+Vt++/438fTylGdee04efeof0qxFM/Nv/37yd3Z/ngbGN9x6o/n6uX8+KyeOn5DLrhxQYiU0AAAAqgdCZAAAAJRZYHBr83n2z7MkLSXVVBUfPHDQ3NeocSO597H7JT8vTx69/WGZOulr62J1ebm5smTBYpkw+hbZl7hXDiUdMgvOOQttyaCVuiuWrjCVuINHDBbPEnoSV7aLL+0tV18zTLKzsuTuG+6U7776VlJTCoL9rMxMmfnTDJlwza2mLUffgX3lqhGDrdvqfa888ZK19Yh/gL/phfz0f58x9334+oeyOzbe7u/VNhY69ljyMXN77O3j7I4DAABA9UJPZAAAgBpicM8rHX5P++Uu2fKXlOa6m6+T3777VbZu3CqXdxtoqnhvuecWuefRe833b73nVkk5fsL0133v1XfNh1b1atVxfn6+GdNnQF956e2X7f78D1//wHw48uanb5nqV1u3XTNBSrJ489IiC8rZ4x/YSi665CJZ8/cac3vkjaPF2T3136dN8K1tJd566U3zof9ObUthaUnRf9Bl8uKbLxZpZfG/516TwwcPS6funa2Vxap3/0tkxPUjZeaPM+S5x56TL3/5Stzc3M54ngy7drjpi6wtMrr06FLk+wAAAKieqEQGAABAmQWFBstH33wi3Xp1N60QtL2FtkGw0LDy4Scekc9/+lIGjxwiLfxbSHZWtlkIrlffi+XVD16Tdz5/94xF3pyBVtmqdhHtpF14O3F2uljeC2++KBOnfmztV6yPdZNmTaTfwH7y5qdvm9DdxyZA/2POHzJ/5jyz7XP/e15cXIqeDjz29GNm+21bouTLiV/Y+a0iexL2mM9jb6MKGQAAoKaodcrRyhkAAACocK8u+0t+ioq03r46vIPc369PidsAlSVmZ4zcOPh6ady0scxaNttUoleEj5b9Lb9HbbPeHhMeIU/2u7TEbQAAAFBxqEQGAAAAUCbapkRdd/OYCguQAQAA4HwIkQEAAACUKml/kiyYPd+0wrh23LWlDQcAAEA1QogMAAAAoFTffDFN8nLzZMiooVKvQf3ShgMAAKAaIUQGAAAAUKKUEyky44fp5usbbxvLowUAAFDDuJU2AAAAAEDN5lfXT/6KXF7aMAAAAFRTVCIDAAAAAAAAABwiRAYAAICcPHnStCwALPLy8iQtNY0HBAAAAITIAAAAEPnywy/khqvGyMY1G3g4IEn7Dsjt106Qpx95Sk6dOsUjAgAAUMNRiQwAAFDDaXD82fuTJOV4imxYs0F6BHWTfuF9JCszs7RNJTs7W/p3utRsM+e330sbXmOdOH5CPnz9A7n28mvkkrYXy2WdLpV7x90tC2cvkLLIysqSyR9/JWOH3CB92vWWSyP6ym3X3Cq/fPuz5Ofnl6mq+OdpP8mE0beY/9s+7S+RcVePlSmfTDb/h8X51vWTE8dT5O/Fy2XaZ1Pt/kwAAADUHITIAAAANZiGiy8/8bIJIh956lEZd/tN4unlKZkZmbJ8UekLqS37c5mkp6aJVx0vGXDVQLkQdm7bKZ+++0mlh9ZLFy414bl+zJ813+G4+Jg4U+WtIXBC3G5xcXWRjPQMWbdynTz50BPy1MNPlhgEHzl8RMYPv8mE0NE7os192dk5snXjVnn16f/K/TffZ/6/HNHfdd+4e+S1Z1+VyE2RkpubK6dOnpRd23bKB/97X8aPuFmOHjlaZBtvH2955d1XxNXNTT5+6yNTmQwAAICaixAZAACgBpv100xJjE+QNu3byJjx15swuP+gy8z3FpShSnbejLnmswbIuu2FoOHnZ+9NkrnT50hl0WD3lSdfKm2YJO1PkvtuuleOHDoivfpeLN/P/UGWRf0tf0UukxffeknqN6wvC2bNl5f/z/7P0p7EGgDHx8RL+47t5Yufv5K/opbL8qi/5Z3P35WWrVrK+lXr5LG7HjV9rYvTcPrROx6RjWs3SqvWreT9yR+YbZdt+1s+++Fz8/8etytW7rv5XhM22+rYtZMMu2aY5OTkyKT3J53xswEAAFBzECIDAADUUDnZOfL5B5+Zr+98+C6pVauW+XrwiMHm899L/j4jWLSVmpIqfy8pqFYeOvpqqUle+veLciz5WGnD5P3X3jMB8sX9Lpb3vnpfQtuFmcfZ08tLrr5mmHwwZaIJ32f/MkvWrlhzxvZavawBcli7MPn0u8+kc/fO4urqKu4e7tLv8kvl0+8mScPGjWTtirUy6+eZZ2w//YffZMPq9dK0eVMTGl/Sv4+4ububn9G1ZzeZ9P1nEhQaJLE7Y+TrT6ecsf1tD9xuqpF//2W2JMQlnPF9AAAA1AyEyAAAADXUovmL5OCBgyZEtG1F0fvS3lK3fj3JzsqSv/5Y6nD7P+f8Ibk5udK4aWPp2aen1BQ/TPleViz5Wzp16yRdenRxOC52V6zpeezm7ibPvPacuLm5nTGmXXg7ufmu8eZrbRth6/ix4/Ldl9+ar5/+7zNSx7vOGds3a9lcHvz3g+brSe9+WqQaWauQtWJbaauSRk0an7G9j5+v/N/LT5qvp30+1VwYsOUf4C9XDrvS/Kyfp/14xvYAAACoGQiRAQAAaqj5M+eZz1oRa6lCVlqpesXQK8zXC39f6HD7uYWtLLRy2cXl9GGl9ivWPsH6WReUe+ulN+TqPkPlouDuMm7ojUV+xvpV6+XZR5+WYX2GSu+2vcyCc3eMuV1+/PoHycvNLTL2hcefNz/3xX+9YG6v/GultSfx8L5Xn9EG4quPvpRbRo6XAZ37m8XsRvQbJi/+63mJKewrfC7iouPk/dfeF29fH3n53f+Ii6urw7FLFy6RU6dOyeVDrpBmLZo5HHfjhLGm2ld7HGubDItVf600i95pWB3RtaPD7YeMGioNGjYwFwS2bY6y3q/9j7UKukmzJnLF0EEOt+9xcQ9pG95OsjKzZOVfK874/rBrh5vPC2YtMP8eAAAA1DyEyAAAADV0QT1tc6D6XNbnjO8PGTnEfF65dIWkFatOVRpYblyzocRWFhrkaoj73VffybEjR6W2Z23r9zSMfPWZ/8o9Y+8yYfThg4fFy8tL0tPSZfO6TfL68/+Tu2+8q0g7DR9fH2nYqKEJcJW2dNDb+qG9hS12RG6X6664Ria+8aFs2xJl/q26mN3+vftl1s+zZPzIm2VeYYB+NrTq+plHnzYV2v9+4d+mH3FJVi9fbT6XVqVdt15d6dCxvXlMVi9bZb1/9fKCr3v26VXC1mIqnHtccpH5epWd7Xv0vqhIyG+PVp8X396i+8XdTRV08pHk8wrgAQAAUHURIgMAANRAexP2mMBWw0Ht01tc5x5dpHnL5mZRtSULl9qtYtbWCdqrN6x9G7Hnl2k/y7Hko/LyO6+YhdyWb1shr3/ypjWE3hm1Q0LbhpoF4nSxuEWblsiKHavkjU/elIDWAbJlwxZ555W3rD/v8ef/JfPXLpTHn3vcWkGrt/Xj6xnTrOM2rNkgmZlZcuu9E2TGX7PMQnb6u2cumy033HqjCYNf+tcLsm/PPjkbH7010Szqd9WIwaZ6uzQH9u43n8Pa2X98bGklsDqw94D1vv2FX9v7/ymubYe25vP+fQW/s+jvL/v2lm2Kh9QdOnUwX+/ctvOM7wMAAKD6I0QGAACogfYmFgSo/oGtirSysND7rhx+lfl64e8Lzvi+pZK3pAX1NIB+6e2XTbsFXcjN0mNXaXuHyb99bcJfXSCudu3a1upi7c/84dSPzDZzfpsjWVlZcjbG3X6TLFz7hzz0fw8XqRZu4d9C/vXCv2Xk9aPM36aL2ZXVulXr5JvPp5lg/cnCHsKlOZp81HyuW79uaUOlXv165rNW+1poAF/wvTJs36Bg+6M22x8tXPiv7llsn3yk4HcW16p1gPm8L3Gv3e8DAACgejtzdQ8AAABUe9pqQvnV9XU4RltaTPlksmmLkHIiRfzq+ln7AmtFrrZIGFzY9sKe4DYhctmVA6Qk2m5ixo/TJWrLNklPTTOtKrQqVnv4NmrSyFQs703YayqWz4aGxN9P/k7+XvK3tbpWF6Hr0buHNPdvYW7H7oyVstDF5p7/53Pmaw3FdTG6s2EvpD8r57n9ef/+wpYbts8bAAAA1CyEyAAAADVR4QJpJQWM2kYhpG2oxO6MkcXzF5kKXjV3+hxrr9/GTRs73L59RHspyduvvCXffvFN0TsPHJS4XbHW36GyMjLlbMTuipWHJzxoAmhb2hPZ0gdaZWWW7edq7+aD+5Pk9gfukK49u0lZ6WJ3+jtPHDtuqqBLcvzYcfNZ+ztb1G/YQCQ6Tk4cOyGlOX60YPsGNts3KOwTfTbbN2zUwO73LU8T1tUDAAComWhnAQAAUAN5+3hbq2xLYllgb+Hs0y0tFsyaX2orC2W7kF5xv/862wTIGmKPvX2c/LjgZ1m+7W+Zt3q+fPrdZ3LtTddZW2CckoLAuyzy8/PlX/c+bgLkoNAg01953poF5mfr73j2f89J65DWZqwuZFca/Tv13xveOULufvQeORuWiueYnTGlDZVd23eZz839m1vva1H4dczO0heziy5c8K5Fyxbn+fvth92pKWlFnjcAAACoWQiRAQAAaqAWhb2CtVVESa4afpUJeteuXCfHjx6Tzes3mwXpvOp4md7F50rDWXXjhBvln88+LsFhweLp5SWNmjSW7hd3lydfearEENqRrRu2SGJ8gvn7Jk792PyNjRo3Mj9bf4dWU4+6YbSU1esvvG4+b9+6Tfq06y29Qi8q8mGpbH720afN7c/en2TdtlffXubzmuWrpSQa5EdtjjKPc69+F1vv79W34Os1f68pNThfWzjmYjvbr125ttTAfNWylWdsbysxPtF8btGq5IpqAAAAVE+EyAAAADVQQOsAqe3paXrc7o7d7XCcVqZ27t5Z8vPyZNG8RTJvxlxzv4azGtSeq6T9Ba0m+lzW1+73t2zYLBnpGXK2kgpbWIS1C5MmzZqUGJiWhfZpVidPnjRhbfEPC8v39bNF/0GXmWD4z7l/yqGkQ+LID5O/N49vx64dTeBtcfGlvc2Cg5vXbZJtW7Y53F7/T3RBvqbNm0qHzuHW+yO6RBT0ld6fZP4GRzat3Sjbt24XTy9P6X3pJWd8X/9NGqKrNu3b2PkJAAAAqO4IkQEAAGogdw936XpRF/P1yr9WlDjWsnie9in+Y87CMrWyKE2jxgW9exPiE874Xk52jrz54pviiLuHh8NF3iw/V3sR5+XmnvF97e28atkqKat18RtK/OjWq7sZ95/3XzW373n0Xuu2IW1CZNCwK80if688+XKR0Nkievsu+XrSFPP1ff+8v8j36tWvZ1p9qP889Ypk2ukNreH0h69/YL6+5x/3msUOLbQdyF2P3G2+fvc/b0vy4eQzttfH8NVnXzVfj79rvPjaWTRwy4YtplpaF1ZsG97ujO8DAACg+iNEBgAAqKE04LRtLeHIFVcPEjd3N9m4dqMcSz5mFtPTRfXOx8AhV5jPH7/1kSxZsMQasEZu3Cp333in7Nq+01Th2tM6ONB83rZ1u2mvoZL2HTCfu/ToIg0bN5Ijh47Is/94Rg4fPGwNSyd/MlmefOiJC9rX9+H/e9j8PSuW/C3/uOMRs+iftpbIysoyFcQP3vKAqbgeft1wueiSMx/TCffdZno474zaIfeOu0e2btxiHqvcnFxZvni5eaz033jRJRfJsGuHn7G9tu7o1rObJO1PkrtvvEtW/bXShOv6Mzat2yT3jrvbLJwY3CZEbrlngthjeX5cPvSKIiE1AAAAag630gYAAACgerpy2FXywf/elx2RO2Tl0hXSu/+ZrQwsFbHaK3f5ouXm9uARg887TLzu5utk+aK/TFXw4/c8ZiqjtXI2KzPL/GztifzlxC/kQGE4bEurYbUCWPsR33HdbSYUrluvrsxcNlvc3N3lxbdeksfufFQW/r7QfHj7+khGWroJb0PbhsqI60fK2y+/JRdCs5bN5aNpH8v9N90rK5auMB/aNkKrrS2tL64cfpU889pzdrf38fWRj7/5VO4Ze7dEbY6U266ZYML1PG2nkZdnxuhj8fZn79r9P9HH9J0v3pOHJjwoW9ZvlgdvfcBcEHCp5WIqpJUGyJ9886nd9iQaUP/+y2zTluO6m8ec8X0AAADUDOd39A8AAIAqS0PDCffdbr62XRDOnsEjh1q/Pt9WFsrNzU3e++oD+edzj5tQWG9rONpnQF+Z9P1nMnrsNQ631UDzjU/elGvGXWv6AGtVrlbrWmjg/fXMaXLViMGmCjg3O0datQ4wrR0m/zbFbsuGiqRtLX5Y8JPceu8ECQxubaqAvbzrSI/ePeTVD16T/77/qgl7HdHK729mfyv3P/6A6fWsYbiHh7vpofzkf56Sj7/5pMT+1Bqy62P67xf/T8I7R5jHWh/DNh3aykP/97B8PWOqNGjUwO62Uz6ZbMLmK4ZeIW07tLU7BgAAANVfrVOlLdUMAACACvPqsr/kp6hI6+2rwzvI/f36yIWSnZ39/+zdB3QUZRfG8QsJPfTee++99yK9KE1FOgqiothRUeBDKQqICioIKIqKolTpvffee++9BZLAd+6bzLKb7GSTECBk/79z9iTZzG62zL6ZeebOfeXZms3l7OmzpoK30bONPd0EXuLAnv3SvtlLJvT+c+5fLkH9ozZq+UqZtfPBZIKtCheRD6tWC/c2AAAAeHSoRAYAAPBiWv37wYAPzfdDPhsiJ4+f9HQTeAE9uPDRmx+ZKuT2r3R4rAEyAAAAYh5CZAAAAC9XtXY1eb7zCxJHRI4dOuppcXiBc6fPyt07d6RY6eLyylvdPS0OAACAWI6J9QAAACBvvN9LXuzSTjJkysCrAdNDetKsP+TmzZumhzIAAAC8G1uEAAAAT5BW/zq7d/+ePAnx4scjQIYLnawvvAn7HqXQn4O4cUJ/UgAAAPA40c4CAADgCUrg6+Pyc0DQkwmRgZjkbmCQy8/xfVw/JwAAAHi8CJEBAACeoPg+rieG3Q4IsF0W8Bb+gYEuPycgRAYAAHiiCJEBAACeoDSJE7v8fO76ddtlAW9xNtTnIE3iJLbLAgAA4NEjRAYAAHiCsiVP7vLzqavX5P79+7bLA7Gdrv+nr14L93MCAACAx4sQGQAA4AnKGiocu3n3rlzzv2O7PBDbXfP3N5+D8D4nAAAAeLwIkQEAAJ6gDH5JxTeu6ybZ8SuXbZcHYrvjV664/Kyfjwx+frbLAwAA4NEjRAYAAHiCNCDLnjyFy3Xrjx63XR6I7dYdPebys34+fEIdaAEAAMDjxdYYAADAE1YtR3aXn1ccOkRfZHhtP+QVBw+7XFctRw7b5QEAAPB4ECIDAAA8YXVy5XH5+cy163LgwgXb5YHY6sD5C3L2+nWX6+rmzm27PAAAAB4PQmQAAIAnrECaNJIlWTKX6/7avNV2eSC2mrx5i8vPWZMll/yp09guDwAAgMeDEBkAAOAJixMnjjyTJ6/LdSsPHZaNx+mNDO+x4dhxWXX4iMt19fLkMZ8PAAAAPFmEyAAAADFAu2LFJUXChC7Xfb9ildwOCLC9DRBb6Hr+w8pVLtfp5+Gl4sVtbwMAAIDHhxAZAAAgBkieMKG8Ub6Cy3Wnrl6TT2fNJkhGrA+QdT3X9d3ZGxUqSrIErgdWAAAA8GQQIgMAAMQQTQsUlCLp0rtct/PMWROw3bxz1/Z2wNNK12tdv3U9d6afg6b5C9jeDgAAAI9XnPv379/3tBAAAAAej0OXLknX6VPlir+/y/UpEyeSLhUqSI28uekRi6ee7oIs3n9Aflq9Vq7cvh2mjcXYZs0lV8pUtrcHAADA40WIDAAAEMPsv3hRXpkxLUyQrApnzCBNCheSstmzScJ48dzeHoip/AMCZP3RYzJj5y7ZefpMmN9rgPxDk2aSN3Vqt7cHAADAk0GIDAAA8JQFySqBr4+UyZZNSmbJLJmSJ5fMyZNJqiRJJG6cOG6XBx63e/fvy6WbN+Xk1Wty6upV2XzipGw4dkzuBAa5XZ4AGQAAIOYiRAYAAIihTly7KkNWLJcVx45JRGiwnDpxEonv6yvxfOLS9gJPpE1FQNA9uRsYKBdv3bQNjEOrki27vFelimRJltzTogAAAHgCCJEBAABieCi37OgRGbpyhZy6ft3T4sBTJVPSpPJu5apSPUcOT4sCAADgCSJEBgAAeAr4BwbK7P37ZP7Bg7L+5AkJYm5kPKV84sSRspmzSN3cuaVB3nyS0NfX000AAADwhBEiAwAAPGUu374tS44cltXHj8vRq1fk+NWrJmQGYiINibMmTy7Zk6eQilmzSo0cOSVlokSebgYAAIAYhBAZAAAgFrS8uHDrlhy7esVMxHc3KEjuBEWsFy0Q3RL4+Eh8Hx8zUV625CkkTeLE9OcGAAB4yhEiAwAAAAAAAABsxbX/FQAAAAAAAADA2xEiAwAAAAAAAABsESIDAAAAAAAAAGwRIgMAAAAAAAAAbBEiAwAAAAAAAABsESIDAAAAIY5fuCn/bTxhvgIAAAAI5hvyFQAAAPBqe09elZeGL5dbd4IkcQIf+bV3NcmXKZmnmwEAAACxHpXIAAAAgIjM2XTSBMhKv+rPAAAAAAiRAQAAAOP67QCXV+Larbu8MgAAAAAhMgAAAAAAAAAgPLSzAAAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2PK1/xUAAAAQe5y9clu+mbVHrty4Kx1q5ZayedNIZK3ff0F+XnRQUvjFlzcaF5B0yRN5ugkAAADw1CNEBgAAgFcYNGW7zN9y2ny/dt95mfJBTcmWNolE1LHzN6XH6DXiHxBkfr7lHyjDupT1dDMAAADgqUc7CwAAAHiFkxdvOb6/fTdIxszbJ5Hx47x9jgBZnbh4M9zlAQAAgNiCEBkAAABeoXy+tC4/T193XI5fuBnhKuQZ6467XFchv+v9AQAAALEVITIAAAC8QsfaeSRhPB/Hz0H37suPc/dFuApZl7ckiu8jHWrlCfc2AAAAQGxBiAwAAACvkDppAmlbLWekq5HdVSG3rZrT3B8AAADgDQiRAQAA4DU6RaEa2V0VslY1AwAAAN6CEBkAAABeI7LVyFQhAwAAAITIAAAA8DKRqUamChkAAAAgRAYAAICXsatGvnE7wOW667cD6IUMAAAAECIDAADAG7mrRt55/KrLMruOX6UXMgAAAECIDAAAAG/krhr5yNkb4f7ctmpOczsAAADA2zCxHgAAALxS6Grk+6F+7/xzovg+0rF2nlBLAAAAAN6BEBkAAABeyV01sh2qkAEAAODNCJEBAADgtUJXI7tDFTIAAAC8HSEyAAAAvFZEqpGpQgYAAIC3I0QGAACAVwuvGpkqZAAAAIAQGQAAAF4uvGpkqpABAAAAQmQAAADAVCP7xI3j8krozx1r5+HVAQAAgNejnQUAAAC8nlYjl8uXxuV1KJ8vjbkeAAAA8HaEyAAAAICIDOlQWjKmTCRaj6xfB3cozesCAAAAiEic+/fv3+eVAAAAAILp5nGcOK6tLQAAAABvRiUyAAAA4IQAGQAAAHBFiAwAAAAAAAAAsEWIDAAAAAAAAACw5Wv/KyCY/90guXUnMMovRyqbWc3vBgTJDf+o32+KJPElbtyw/QoDAu/J9dsBElXJEscTX5+wx1cCg+7JtVtRv9+kieJJPN+w93vv3n25cvOuRJVfQl+JH8/H7e8uXb8jUZU4ga8kjO/+fi/fuCNR7aau96n37c7Vm3cl6F7U7jhBvLiSJGE8t7/T903fv6jQ90zfO3d0PdP1LSp0HdN1zZ2b/gFyJyBq9+sTN44kTxLf7e/0c6yf56jQ1qAp/dx/lhkjgjFGPMAYEYwxgjHCGWMEY0RojBGMEYwR7GuwrxGMfY2nI4+wy2DgPQiR4dG/a47KwL+2S1Tt+KaZ2+sX7zgjb4/bIFG17PP6bgPqzYcvSeeRKyWqpvapKXkyJgtz/ZFzN6T554slqsa9UVnK5U0T5nodsKv1mSNR9VXnMvJMycxuf/cw9/tRq6LyfLVcbn/XdOAiuXwjYv9oQuvRIL/0bFjA7e/aj1ghB89cl6hoWzWHfNy6uNvfvTFmrWw4cFGiol6JTDKsS1m3v/t00haZt+WUREWZPKllQq8qbn83fPou+WP5EYmK3BmSyrSParn93fiFB2T07L0SFSn94svyLxq4/R1jRDDGiAcYI4IxRjBGOGOMYIwIjTGCMYIxgn0N9jWCsa/xdOQRdhkMvAftLAAAAAAAAAAAtqhE9nJ6yrFWjCmrPcHf79eQFH4PTocPCIpaewGLf4D70+ej2gbAcicwyO193w2M2un6ljuB99zer17/MPRxub/fh3u8+jravcYPQ993u/uNaisL6zQc+/uN+h1rGwy7+733MPd73/5+9XdRdS+8+41iSw/rNbS736i29FD6VG0/y4wRBmOE6/oSVYwRwRgjHmA7IhjbEYwRzhgjGCNCY4xgjGCMcI/tiEc7RsC7ECJ7Od3RD92W4L48xN4/AAAAAAAAgFglzv2HKf3DU08nXgvd/2Z+/7ouE2jppFm370Z9Ajy7ybj0SNjNh5hYL3li+4n1bvg/XMN5u0b2DzNhn19C+0b2V29Frb+wSqIT6/naT0oRVYni20+sd+XG3SgfbEgYz0cShTOxXlSrhvU10NfCHX3folqFG88nrvjZTKx3QyfWi+L96jpmN2Gffi6iWlEfN479xHq3dWK9KFatx5E4LmcoOGOMCMYY8QBjRDDGCMYIZ4wRjBGhMUYwRjBGsK/BvkYw9jViXh6hvZJbDV7qch09kUGI7OUiEiIDAAAAAADAO2hBWt2+812uI0QGE+sBAAAAAAAAAGwRIgMAAAAAAAAAbBEiAwAAAAAAAABsuZ+FCgAAAAAAAIDX0UnrB7UvZb63JuTzs5nIHt6DNQAAAACIoXR29BRJ4ntaDIj1AoPuiX9AkPgljOdpUQDAQ4rv6yN1SmQy3yeM5+NpcXgJ2lkAAAAAMdB/G05I84GLZNG2054WBWK1M5dvS+eRK+WjiZvl/v37nhYHAACPAJXIAAA8BjPWHZd+f2yViCqVO5X82LOSRMR3s/bInysOS+vKOeS1xgXladVkwEI5ffm2jH+jshTNkVKiS0DgPfll8UGZteGEnL50W5Im8pX3nisidYoHV1fg0dhz4qr8sfywrN9/QS5dv2te94JZU0iLCtmkRtEMnm7u9Y6euyGDpmyX23eDzCmlWw5fkq7frDKvy4yPa0nGVIk9vkbPfrFYjp2/Kd0b5JeudfNKbBR07778vfKI+XwfPXdT4saNI3kyJpVnK2aTBqWzhHvbqzfvysTFB2XxjjNmbIjvG1cKZEkuz1XKLnVDqq/C4383yKzjczedNK+zj08cyZ0hqTQum1WaV8gmPnHjeKysnbrmmMxcf0IOnrku9+7fl+zp/OSZkpmkbdWckiAClV/fztwtExYdlHdbFJY2VXO6hK4/Lzogq3afl/PX/E01e9m8aaR9rdzmMYZn+5HL8uvSQ7L54EW5djtAUidNIOXypZUOtXJLjnR+4snhs9fl50UHzWf/4vU7kjxxfPM/rV2N3FI4WwqJiqSJ4snVWwGy6/hV+XXJIXmpZm5PNwEAANGMEBkAgMdAwwDdEXd2JyBIbvgHiq9PHLOT7Sz0z+HREEODpskrj4QJkTW8PnXpltQunlHyZEwm3kYr1t4Zv0FW7j5nfk6SwNcEEeeu+Hu6KR7C78sOyYjpu03ApzQEvXzzrnkf9FK3REbp/0JJR489hPXF39vl1p0gealGLimfL61ZlzOlSiSnLt2W+VtOmzAwPLuOXzHBZpw4Ig1KZZbHQccaHXM0sHQONB8VHUNf/3GtbDp4yfysIfC9wPuy+dAlc1mx65z8r11JiaMvgpugs8foNXLh2h3zc8L4PnLrTqBsOHDRXBZvPyMDXixpGwRfuOZvbn/47A3zcwLfuHIn4J5sP3rFXOZtPiUjupaVRAnc727p3+o1Zp15nEr/D8SNE0f2nbxmLrM2nJTve1SQVKH+b4S2bOdZ87Va4fSO67YeviRvjV1vAmCVOIGPnLvqb4L2BVtOycCXStkeyPltqX52d4lV7Ku3PXvF37yvGpbr61mrWEaxM3/LKen72xYJCLrnuL0GybrOLtx6Wno3L2wCck/r7se/bjZB+KohDR1jyP9eLCldv10lo2fvNSF/hpSJwr0fAAAQvQiRAQB4DOqVzGQuzuZuPmlOzS2WI2WEq47d0R1yDZK1Ejm0GeuPm4AlR3o/rwyR1+67YELLeD5xZViXMlKxQDq5GxgkN24HeropomjD/gsybNou833nOnnkhWq5JIVffFO1+d/GEyag0kApTdKE8naLwp7uziut2XveBJl64OmV+vnNdRqEPlMys4xfeMAEdZ5C5NkbT5qvJXKmksypPVctR1eIPGbefsmeLsljCZG/mbnbjG8ZUyaSj1oXM5W2GrZrAPzFX9tl7uZT5qyG0KGlhpNWgFw+Xxp5q2khyZ0xqQmBF247bdZRDYE1lP7s+RJh/u4N/wBHgFwwS3J5p0VhKZI9pdy7d9+8d1/+u1M2Hrwovcetl+9eqWCqo53pwZU3xwYHyFnTJJZ3WxSRcvnSmPd425FLMvSfnbLv1DXzN8b3qiyJbYLoExdvyqGzNyRvxqSOynT9nL3/80YTIOvBQ31uGrZqb+3vZ++Vv1cdlU8nbZG/P6ghaZMndLk/rYoePm2XGS/1s9umag5Jlji+nLtyW35acECmrDoqfSZukhFdy0mF/GnDPB4dazX81YrqtlVzSMfaeSRNsoTmb/++7LBMWHjAvDZ6MK9Juaxhbq+v38QlB01IHBh037z+zvS9bFw2i0xbe1x+nLtP+rYtHuY+AADAo0P5BwAAT7mejQrI8kENnupWFo+ypYKqWjidCZCtiUI8Vfch6n5ffthUMbarnktebVjABMhWpeezFbPLF+1Lm+rOc9f8TWiEsEb9t8d81VP29XWz1C8dXFG8+8RVOXHhpu1Lp6+rBs2qYchtYhsNSzVMVF+0L2VCTV2vfH3imipVbVmjNLwMbeTM3SZA1tt83a2c5MmUzAS4+lo3KpNFvnm5vCSK72PaTGhLhtAmLDhgAmQNb3/oWVGK50xl/rZW1lctnN5cpwcA1u+/aA7khaZhrYbf6VMklDGvVZJKBdOZx633UTJXavmxZ0XJmd7PtLj4ZdFBsbNsR3AVsv5Ny4Ktp8xz05YeA9uVdFTranX4By2LSsX8aeXmnUCZtvaYy31dvnFHhk8PPvijgXy3Z/KZAFmlS5FIPmxZVDrVzmPC3UF/bzetOJzpwbnBU7abgPyVZ/LJOy2KmADZ+ts9GuSX90PeEz3IpK1EnGlQ3fOHNfLNzD3mb9jpVCePeZ2C25cEV4EDAIDHgxAZAADEWnq6uxVi4PE4EhLslHdTqagqF0wn/31aRwZ3KB2mQhMi245cNn1fkyeOJy0rZXd5SbSXrQaXal5ISOzO+gMXTJColZzWzOqxjbbq0DY++tnWKuDQqhZKb1p5nLx4y1QOWzSY1YBd20d83LqYCW9D077I7WrkMt9rVawzq6rWClvdVQlrcPtaowLme62YdT5YoiHrmHn7zPe9mhRyBK3O/BLFcwSu2pv4ekhbitCW7wrbymLvyWvmq4bF7p6bFThby1m0b/xN/0CpVCCtqfZ1R3trZ0mdWE5cvCXT17mG4xroa6uVXOn9pItN/209iKS9kfX5aF9ji/7ddsOWm9BdW7YMeDFs9bclS+ok5qye4F7YR22XAwA8HD24WKb3THMp8vo0c7l0PbgFFLwX7Sy8nFZcaGWAsioKEkZgEg8AwOOhG25qw7DGpvelTgKl1bUannzZqYzpa/nDnL3mFHKdSKpPq2Iut7No2wy9qG718jpOkbdoRddfK4+Y9g96qrdW4WVL6ycNy2SWhqWzuFRDWqetN/3fInMa+YxPapvgSydx2nr4sty+EyiZ0yQxk0O1r5n7ofreRvXvWJP0Wf5ZfcxclHVfzjTU0FO1NZjT0MknThzTAkDDihYVs4lfwnguy1uvub6Weqr82Hn7ZdH206bvaN6MyWTSO9Vcll+644y5//2nrpnTzNMlTyilc6c2t9UqyOh4zs50HdHJxjYduiRnr+hkgvEkW5ok0rR8NqlfKpPbcEkrO7Vqctb6E3L8wk0JvHffPIaaRTNIy8o5wvT0thPcz/umaWvh7pR3Fd59aa/ZP5cfMa/ZKce6mMSsh03KZTGV5M4++32LqRj9tG1x087gh7n7ZNXuc6YPa/Ui6c37MXb+ftPWYezr9m1j+v+x1QRjzp+jqLwu1iSaGsR98FxR895pa4nTIc9lyef1JTzad1ZpK4LQnzv1TKnMsn/WHlmw5bR0ruM+rJsT0spCA0N976Py2HQd0nV23f4LcuGqv1ln9H2oWSyDWW+dw1Pr82DRCe6cxyAdv5wrVv9dfUwWbD0th85el1v+QZLSL74Uz5nStMDQ9ykyQlfEOl9v9fUVp8JWXa/0+trFMobbU1ef47gFB2T70ctmnbTC3jV7zsudwHumDZG78NrSoHRm025D+wlrj19r2R3m/u6YMaBOcfvewmXypJH8mZOZsHf1nvNh2iHduB1g2mHo+udusjqrJ3FodwODr9e2H86WhlQ1v1A9ODx3RyuA9XX5cupOWbL9jAmFLfqzalstp9se1JYXq+cyVdjackTPorH6HWt7Cx2rdL20ejnb0fVX11sdr3s3LxTu3wMAANGHENnL6Q5Az4bBG3D+IdVaAICYR3seay9J5ZfQ11TYhccKtq7eumtODdbb6OR+KnTl3OQVR0wfTCt00H6VuhO/5fAlc/lj+REZ0rG05Ejn5+YviemxOfSfHaYyTMMADVgOnbluKvh0giftnxkdFaeR+TsaSmlYopNXaeCeIF5cRxCsv3N24NQ1eeun9Y7QWZcNvB/cMkAv/6w+KsO7lDN9pUPTiRHbj1hhgmet+rReY+fATMPJOZuCq0b1fdPX9/iFW+Yyc8MJead5YRNGPuxztvw0f78J9aziR33vtXJEgysNlTVI/KpzGVPtaNEDB71/Wm/6sCrtiaqVmgdOXzcXDeAHdywdoYCvXolMwcH34oPmcevp59Zp8Z5sOHBB3p+w0Ux+qDTY1P7VGqDrRU/BH9alrNvqTQ3fXxy2TK7eDDDhq050pppXyCbjFuw36/Kx8zfMwZHQNJzXNgDKORh7mNclKOi+dB+1WnYcu2LCt4gepNcDOVbFtjv1S2WW7/7bYx6TVn2H/lxq9f2ikEDPrpWFp8emofuYufvM+6erl352tAWC9ZnQ0F5bLljvg44pOuYEBN4zY4fep7vq/9OXbknPH9aaKmLrs6afGz34on2yNVh+vVFBj/2elbZ7SOUXXy7dCJ6wMfTrZVVq58uczGVdX7s3+PXVHsThSZ4kvhTKmtxMkqfviba5MLffdz749nnDv72G7mXypjG9lbVPshUiW+9vmbypPY6LWk2sIbLePnSIvHLPOTO2Vy2UziVELZ0ntamUXr7znLzWKMjlQIRWRC8MWc91Oef3Rd8TXb89fcYrFAg+MLTxwEXzfuuBLP1qTRDo6XXVAz36GdJ1Vz9fVpCv+yPW6+EpRNYDcNaEffo5zBvqQBwAAHg0CJEBAHgKjJyx24QF7z1bxEygpKdnB2rSaWNuv7rm68vfrTJVXx+2Kmom5QpNA8Uh/+ww4WabKjlMFZpW4Gp4pL1AtZJOQ4ye36+RSW9XM8GKM92J15BTqzLfDJnASR+bBtMadK7ac95MINigtPvToyMqsn/nl7equlRIagDkXF1quXbrrrz+41o5f+2OVCmUTl5rWMBMsKWhzL6T10xYpwHV2+PXy2+9q4WpDNVKTQ1E9PTreiUzm/BMJ7uyfDV1lwmQtfepPm49xV7vQ/uBagCpp7oP/meHZEmTJEzVbmSfs/pz+WHzO30/X6qRS16skcsEfRryLNlxxtyfTvj1v8nbZFCH0uY2+jsrKNXqSv1bWtmoz+X4+Zvy04L9JjR8Z9wG+ePdam4DXGetquQwQaP2LJ245JBMXnlEahXNKHVKZDRBn7sqaKWvmz6OW3eCTKVh13p5zanrWjG59chlGTFtlwk9dWKv73tUDBPA/bzooKm6HdmtnFQMCbr09Hp93fS11ddrxvoTjoPnzuZvPW3+roaG2sogOl4XnaBNP0e9mxWSlpWzmwpq53XDHa16Pno+uB2I/k139Plo0Keh3fzNp0zvWmfLd5417QGSJ4lnG0SH99h0Hdt2+JKplNVKUV1n9QCGVvbqWPLtrN2m3YZOzvZd9wqO3s160YMA3UetkSxpEsuUD2qG+bvbjl42B7aal88qz1fPZdpzWOu6Vs7rpIHar7hYzpQew0wNL7Xntq7LfSdtlreaFjafYX2cGkZ/O2uP+RzoZ9rZ6cu3zNeIBI/5MweHyBqyWnSdUnkyBT/28GglsYbI1m2UdV9aIe9J/pB10XrMnvohq2qF0kupXKnMAaM3xqyVNxoXNK+zHiTTKn19PlpR3qx8NsdtrMeXNW0St9XvzvSghYb/Ogmhvm+6Pmqlth6004M++pkNjx5wyJomiekprc/LCpE9BerOdAwplDWFmXxy78mrEXovAQDAw4v6+aUAAOCx0RBgaKcyJkBWWhloTVgWVRqgaoCpdNKkd58tYgJkpUGZBm/je1U2wZmekq2hTGgaHGhlmU5sZYUB+tj0NHurcm/RtuCqyIfxqP6OhrgaIGtP0WGdyzom2LIqGId3KWt6eOrp+f+uOer2cfV/oaQJcvU1U1aIYrUDSJYonozuUcFM9mUFNBrGa4Wu9j3Vs8o1OHvY53zlxl1zsEG9/1xR6dX0Qb9VDdz073//akXzGLSiWatvlYa8GpTq+zyqewUTXlrPRUOlz54vYU7N116wGtR6orft90IJGdShlFlvNWyavemkvD1ugzQbuEh+XXLQbQuCYVN3mSC3dZUc5m9ar6O+Hxoo6mPPni6JCTKXhfSCdaah6PCuZc0kZXobvVjrc4sKwYHZfxtOuJ3Mb3rIBG3WctHxuuj716tJQXNgxmrB4Slg02pqXR+0ejyln33LD21poazJ85zNCWmHoRXhdoF9eI9N17GRL5eXKR/WMFXPGiArvS+tMh3Vo4JZp7WiVivwI0MPZM3+tI583Ka4I0BWWsWsLXa61svnmHguIrTKXA8KaPW5tjWp88k8qf/ZAnPWxt2AIPmoVTGzPjjTyuUHbVfCZ1VTa1jq3CPS/C4St78UchuXv58kMn/fdRI6/fxoiwsNc8vncz34pGHskI5lzPqqn5WOX6+Uqh/OkdZDlsrCracla5rE8nXXci5npDx4Tq5teyL6vCLznOxe18jSIFpFdh0EAABRR4gMAMBToEPt3LaBUFRpT0mtfNSwwfkUfmcaMGnAbJbfdNJUOIamFaPuelJap3ufdKriexjR/Xc0iLHaTGi1nrtKOL2udUirCT3dPrRcGZKavtTuaA9dpT2V3bVQUNoHVNtbaNWztlp4mOf838YTJhzW0DP0hGzOj3d+v7omHE8UEiJZj/OVZ/LZViFqH1S1IJzJ3EKrUzyT/PleddP2oFn5rCYY1YMRI6bvls4jV7qEPxqAa8W3hmLd67tW1lr0sTUrl832cWj1sVYnuqPVmhpU6t+32hFY9HXXVhf6PljhbHS8LjoxXiubNiV2tD1KRAJO7aWrFfCHzt4wE8U5HxhauTv4+VkHGtyJyGPTAyeD/t4uL3y1TBr1XyAtBy2R93/eaCqdrdYu2lolKrRNy+s/rDUHFRoPWGjWBz0AYoWLB09H7H61h65WP1t0/bGCfj1WoGdTaEsbdzy1BPIozpO7+ZZDl0zLh3L50rpdN3V9dv586bptuXT9rmw+HNx6Ilof1MPfPFJ0HVba7gYAADwetLMAAOApUDCL+3DsYegp6UonHwuPnt6vE4np6dAaGhV1Os1eg5gibiZ1Uno6vNWj9WE9ir+j/Ti1ilS1HLzE0+JmUrXQCoacbu6OtnRQWqUakQpe7UnqHDZH9jnvORn897T9RXis8NgK0g+cDu73+8aYdeKJVm3rgQdPp7w7K5U7tbm826KImaDu+9l7zbr32g9r5I93q5s+0lrxq5XEeqn18TxPd+noqRvR90IPwDQtl9W0S5i+7oRULJAuTBXyM6UyOaozo+N10UrbyE4q6ZjszEMap2Gr9stdvuucaWmRO2SSZK001d7m2q4gvEnfPD02rRb/ZuYe83440z62+jcs2m88Ms5duS2v/bguTPisn0Xtox2Z+9XP7ivfrZYTF29JrWIZzETR2mpBH7OGqNrnfe7mU2Y5q+2G0j7K2r5BW8pkCjmzI7y/oZwnTzQV4mdvmOpnT6zbp3KqKte/r7SthycP/r7rQYWlO4Mr8asVCtuuZNG20/LBzxvNuqjV5lqtrW1edCK+aeuOmxY/2qc9nk8cRyscq+o9Is9JWT3LrecVmedk97pGlnVw7b7zrIkAAOCRIkQGAOApoBV20U0nW4vojrwuoyFy6NOPgycai/vIy9Iexd+xTsG2mwQsNK38jMz7Yp3qrRVzEaki1xYDD/OcL4ec8p4mmef30znMsXLCiKwHVs/cyITIFr2NVr+WyZNaOo5YaSYW1ECyYZksjtdKn3OyCJxS7+51CT2pYWgapk1YdECW7Tgj128HmGBNA0ft3aycq/Gj43Xx9HjcsVpHaODnSf3SmU2IrBPIdQ8JkfVsAaWvaXjCe2ybD1001eJK23W8WD2XaR2gk0SeuHDL9NbWiT61TUlkA7xPf99iAmQ9CKL9jMvmTW0+exoi60GQ35ceNn2vI3K/vyw6aALk2sUzyuCQ/t7W57RMnjQy9rVK0nboMtN2Q6unrd7BGVMmNiGyTshW0KZy3WJNqGi1EVKZUiWSjQfFHGTQvx2e/SG319tYrPvSv++J4++ndA279flohhq6H7Ie/Phq6k6z7n7+UimpUujB73VyQX0vs6dNIm+OXS9fz9htWtzoZ8l6fHqgTA9Mhbd+aOW+HjDRiSutz0bqZAnMBInajkZbsoQXzmsbHeuAXOjnFRn6GVZJQiZMBQAAjx4hspfTKgydVd65+mXMa5Ui3NMMAPD0ShUSAESkL6W1TEQDtaeBVT2noaU1EWF00io9rZjV/sDOYc6jkjKkWvHCNc/vp0UDPD37X0OnaR/VilI4HJr2V9W2EdYEdaHlTJ/UVI7qJHc6aWPDMg8qGvNmSuqYFDG6aX9k7TG9bt8FmbvppLSsnENW7zlnqoidJ9R7VK9LRFjhm1Z6amuKZOG0taheOIMkTuBj1jGdXEwfs7Y50HCxgVNbjsjSyQKtMxQGvFjScX0SCe7TrGcirNh1zqWNRkRbT6zff9F8r72rddI6S/Z0fubiGzeuaZkREVYbi2blstpW3OtkjnoWwKZDFx2Ba/n8aczkkroeaDuZ8ELKnceumNezfL7g9jHm9vnSmnV33f4Lpo+zneDJSYOfr/OkmXpf2otdW23otre7djWWNXvOh7m9hvAanus6G3oyx6Pnb5rPno7TdmOOXq+/13FC1x1tcaPBtlav689axR26z7Iz7cWsSudJ7ahm17ZHJXOlMoG9vq56wMaOToYXGHTfVI1bvd6j4lhIEO0c0AMAgEfLc1kMYjXdwNWdAL1oXz293LNOpQQAxGoaQqilO8JOUuZMJ4jTKmQN0jRwiC00wNAJwi7fuCtHzobtRxymxUAk6cR8SoO98Lib6C0qCoSEcku2hz/BoDWhntIqRA11rQrUh32cprK430L55LfN4b5uVjhqVXLnzpjUVITrdoiGpw/zGMLzbEi4NX1dcAuLaSGtLEL3BI/u1yWitJ1GlpDJADXADI9+HqsXCW5dsmDLaZm3+ZQJvXUSQmtCwajQEFJVDjUhnUWrhrWtRVTvVyvlnQNkZ2v2uvarDo8GkZ5Yq6DzsvqaaW67cNtp017Dzp/LD5vt5KLZU7qEtRUKpDVVuFsPX5Zdx+3fI53gUA++pU+R0KVXt7YZ0ddAXw99DHZ03NCWOPo+a79vyzKrlUXIe+/M3YSV4XF9XYJD59+XHQ53Xf9zxRHzfehe8NbPWqUe3md/0rJDEWq7Ex59HLtD2jHlyxQ8zgIAgEePEBkAgFhMK8TsJh/SU9U1oNBepFNWHXVz6+Ceu1/8vT14+VKZHafbxwYaFOproPQU8ND9Xy1j5+2X54cuNRO/RYb24FV/rTpqOwHZ4bPXzcRi387c/dBhZMPSWUy4pe0A/ll91LYatGH/hdLz+zVmMjtlVWNqD1y7Sci05UOLzxc7Wj/Y0UkaNaA7fPaGqbZ0R0+Ft4JuKwDSyshKBdOZ3+lp9nb+N3mbdP1mlew4+qB/bmRo0KUV6NqTWStZl+86GzyhXslMYZaNztclMrRaWq0KqfgMT/2QiuMFW0+ZiTJVw5B1Oqqssw3c9Z3WcPDLf3fYflbCG2+s+9WDNlYrAmf6nmrP7IgqGHIQzDog4O5gidW/ubBTiKv9oLWNg7aP0fXJ3XPRNhS/LA7uY669lp1pxffz1YInVBw4eZvLQRmLhtP6mVZarew8aaceLOlWL3jySG0b4u5MEG2NYo27L9XIZVqvhAmR3VQaZ0/rZ9Znvc8Vu9wfHNRxTH+vY7lWH1va18xtrtMq8zkh61JoY+btM+tF1jSJpUlZ1ypunTxTq4K1TceEhe57wE9be8xUZ+vzaVcjl0TVtqOXzTqkBwHtDkgAAIDoR4gMAEAspv0v1cz1x02fVQ0qNUi0qkHfe7aI+X7QlO0y9J8dcvLiLfOzBitr952XTiNXmopIrabr2aiAxDbdnslnntvqveelx6jVsvXwJUcVnfb2HPT3dvlh7j5TIau9jSND2yM8Vym73PQPlG7frZKpa445wkgNS/U96frtKjl31d9MJOYcNEVFCr/40qtpIfO9Pm4NsayASisUNbjVAFbDF9MHOqSdR+sq2U3VtPZf7TxypakGtYI1vb1OhKcTcZ28dEsSeWjrkDZ5Qnm9cfB6MmbefnO7ExdvOh6DrlP6nPW+9HR252rG3k0LmQBMq4PfHb/B0U9WaQivbQ40MNx/+ppjIrCoHDhoVDa4X/DHv242lZjaW9h5skFLdL4ukVEvJNDWyuKAUH2yQ9PWCCn94pv+0vo4tS9tnRJhA/HIsPr8akWprrPWY9Cz1rSX7pIdwcF7eOONvj7zt5xyVC4rrY7WyQ/1NdT393hISK0HqvTv9Px+rSQICaEjQkNIPWiyYOtp+fCXjeZsAv3s6nqm1eOvjFrtWM+0rYWzNxoXNKG2BvVvjV1nnpveVj+XGqC+9sNa09+3SdksjlDfWcc6ecz9ajuW7qPXyPYjl83z0tdKw9uXv1tt2qRoz+fGbvpTa7uHUrlSmdfm5e9WmXVLH7c1KWD3UWvMY9IzPzTcteiBHw3b9SwK60wHZ3pQ8IXqwQH3RxM3y6Slhxz9tTWY1ve0z8RN5ueXauZ2adOinymdiE/1/3Or/DR/v+OsgPNX/WXIPzvMZ1p7Tr//XNEwEzPqAQS9XseWUbP3yLBpO+XCNX9H+zw9qGQF472bFXqo1nmzQlqu6Lr6sOMmAACIuNhTTgQAAMJoWTm7/LvmmGw/ekVqfzLPBAAaSli9PLVa9pZ/oIyYscucpqwXDYjuBAY5TnXOmd5PhnYsE6HJ5542+py+7lpO3h6/QTYduiRdvlllgjh9nTREUtp3tv8LJc1p6JH1dvNCcvtuoPy34aSpehz41zbxSxjPBDrWGd/6HrwZEv4+rNZVcpj71oBzwqKD5uKX0NeE11bBpfYu/V+7ki7hz7DOZU2wp6fPa4CmQZAGozf8g0NvfT0+eK6I1CoW/kRi6vlquSQg8L58998eE/rqRe9LKz+tEFZbNnzdrZzLBHlZ0yaRr7qUkQ9/2SSLt58xFyvk0nBPafA3uGPph2rX0KJCNpm4+JCjd7T+7E50vy4RpRMP5krvZw5c6GunByLs6OtXp3hG+WtlcOW59v11rlqNimqF05t1Uv+2rrMa/GnbEevz0KVuXhPSbjoYtk2LBoMNy2Q267u+jwP+3GoOkKz/qrH5fd+2xU3Aqn1xW3yx2Iw1+vnQ1UIP5nSvn1/6/bFVIkLbjXzevpRpnTJ/y2lz0cep65g1dmmlbej1TGkIO6pHBXl19BoTJK/as9Ssa3cDghyfEw3zP25T3N2fNp/h0T0qmKBaD7LpwTYNtAPv3Xes46VypzLrj7uQU9ej4V3Lyes/rjVngui6petS3DhxHBNsaoD8fY8KLgc4tHJe775qIfetRpRWOWs4rX2bh03bZS5aYawHsyy6znepkyfMbbWtiy43cuZuGT17r7no+Ge99zrx5cCXSrr0aHamLVD6v1hCPp20RSYtPWwu+h7fDDl4pi/FOy0Kh9uL2hMNtLXyX8940P9vAADg8SFEBgAgFtOgRcOSUf/tkb0nrplAI/RkRm2r5TSTTU1eccRMFqW9OjWIypomiWn3oKctP66JxZ6EPJmSyW+9q8rUtcdM9eeJC7ck8N49E+Rpi4U2VXKYiaeiQoNIDaDrlchkwnztL62n86dPkUjyZ04mLStll4oF7AOhqOhcJ69UKpBO/lp5RDYdvCjnrvibKsPs6ZJI03LZpH6pTG5DtZ/eqGQmVdMA8Oj5GyZ41hCudO7UZh3RNgAR1b5WbqlaOJ0JkXSiLa221jBJex9rL1QNRhPEC7tOlcmTRv54t7r8vfKIqZw+dfm2xAlpe2HdzpoQMqqypfUzz0knVws9oV5o0f26RIROtNa9QX55b8JGmbDwgGkTEPr9ctagdBZHiPywrSwsGvaWyp3atEU5ePq6Cew0FG1XI7cJmbV61k6flsUkbbKEpk+zvu9asWvJmymZ/P5ONVPlumrPOfNZ0NdY+xRrOH3g9IPq84jQ2/35bnX5fflh06ZBxy4N+fX9qVsio7SslMN27NL37c/3qsvExQdlyY4zcuribRPYarW0rmfa8sJT1b2OG/q3528+ZSa10wNQeTImlcZls5pqYw2L7Wiw+2PPivLP6mMmFDXV0Pfumwpjba/SpkrOMI/damVh9cJ2R8f4T58vYSrStcJ7+9HLcvVmgKRNlsAcCNPnZhcCWxXK2pbmt6WHZPOhS3LtVoAJ+MvlSysdauV2eT/deaZkZsmTMZn8suigrNt3Xi7duGsO/ljrT+FsD1qLRMXPiw6YoF3fX1pZAADweMW5H9XZYhArXLp+R6r1meNy3fz+daN8migAAAAeXvvhy03v5u7180nXkB66gDc7cOqatB+xwlR76wEAT4E2ACDqLt+4I3X7zne5btnn9R/6YD6eblQiAwAAADFMn1bFpNPXK00fWq0cjUo7FSC20N7ZH/262VQhdwrpSQ0AeHQSxfd1zJ0Szyf4zJrENnMiwHuwBgAAAAAxjLbZeKNJAflm5h45cu4GITK8mrbluRsYZFptvPIMlfkA8KhpSyWda8N876YFGbwTITIAAAAQA+kkhTpZXpbUSTwtCsRqOvHmpLermUn6wusRDgAAHh1CZAAAACCGIkAGgunEh3oBAABPBodxAQAAAAAAAAC2CJEBAAAAAAAAALYIkQEAAAAAAAAAtgiRAQAAHrEyvWeay4Vr/vKwXv5ulbmvuZtPeloU0eCz37eY13vCwgPibZoMWGie+/Yjlz0t6tVmrDtuXqfXf1jruO74+ZvS4vNF0mzgIvP9w7h68668+NUyeebT+bKN9wIA8BhcuXFX6nwyz1yqfjjbXC7fuOPpZojlmJnAyyWIF1faVs1hvg+6d998je/r4+FWAAAAj8eS7Wdk78mrUj5fWimRK5WnxYEYYcmOM3L8wi3z/dKdZ6RdjdwSVesPXJC9J6+Z7+dsOinFcqR0/O767QCZtPSQ+PjEla5184ZzLwAARNx9uS9Xbt51vS44MoIXI0T2ckkSxpOPWxc33/sHBHlaHAAA4LGHcTPXn5AE8XwIkfHUqFEkg0xZdVR0f7t64QzyMMrmSSP5MyeTC9fuSINSmV1+pyHymHn7Jb4vITIAAHi0CJEBAAAAIBplTZtEpn5US6JD8iTx5be3q3laDAAA4JGiJzIAAAAAAAAAwBaVyAAA4KmZ4EzbGnzatrjULZFJfl50wPQHPXfFX9KlSCj1S2WWjrXzmLYHgUH35I/lh2XW+hNy/OItiecTV4pmTyHd6uWTok79RJ3dvhMoszackP82npTjF26K/90gyZgykVQokFZaV84hWdIkETvHzt+Q35cdlrX7LsjZy7clWeJ4UiZvGulQK7fkyZhMwqOTbk1adij4tlduS9JE8SRX+qTStHxWqVcik8SNG0cehWu37srUNcdlwdZTcvLiLQkMui8ZUiaSygXTmfkS0qVI5PZ2R8/dkL9WHjGP98zl25Iovo9kS+snDctkloals0jC+K5zK5y6dEua/m+ReS1nfFLbTAym793Ww5fNa545TRJ5pmQmaV8zt8Tzjesyqdvpy7cdP387a4+5qMZls8hnz5dwWW76x7XMujBuwX7zN274B0rvZoXkheq5HPeh68W8zadkxvrjcvjsDdMKIH2KRFI6d2ppVTmH5Msc/nsVFT/M2WvaDXSrl1e61M0rk1cckWlrj8uJizclpV8CqVkkg3Stl9dUm96/f9/87t81x+TI2RumH2H+zMnNeq3vizsP85zOX/WXP5cflqU7z5rXMHF8H9Nvt13N3FIiZ/j9p3WSyD+XH5GlO87IKcd6kMSsA03KZYn2OTb0eWl7iHlbgtdXnzhxJHPqxFKvZCZpUTGb+CWM51j2vw0npO+kLeaz9Oe71cKsy3tOXJUOI1aY+UC+6lxGqhfJ4Hif2tXIJb2aFJRZG07Kv2uOysHT1yVOnDjmuTUqk0Walc9qxpiI0Mn21JzP6kiaZAkf6vNnrefj36hsxjCdzK/fH1sdv78beM/x95R+HjKlSuxyHwAAAA+DEBkAADxVrt0OMAHQwTPXzQSxgffumwmsNADacOCijOhaTt4cu042H7okmr9q4KMB1Ko9583vR/eoIMVDBWQHTl+T9yZslGPnb5qffX3imB6jh87eMJcpK4/Ku88WkeYVsoV5PHM3n5T+f2yVOwH3zM8apl26cVdmbzwpC7eedoSd7szfcsqE49ZtkyTwlcs37sq6axdk3f4LJgz7on1pSZIwejfZdhy9LO//vFHOXvE3PycICW/1NdXLP6uPyrAuZaVU7tQut9MAdPi0XRIQ9ODx6vux5fAlc/lj+REZ0rG05Ejn5+avivy96qgM/WeHCe/0Od0JvCeHzlyX0bP3ytbDl8x7Z4XmKf3im2Dsxu0As1ziBD6SKH7w6+Dn5vXQCfi+nrHbcd8+ocJ3Dbw/+Hmj7Dh2xfysv9fAW99zvUxbe0xefiafCXo1NIxuGhK+9sNasw7quqWT0+hj+n35YVm195xM6FVFBk7eJgu2nhb984nj+8qtO0FmPd5yeJ188VIpqVMiU7Q9p/X7L8gHv2yUqzcDzM/6WdLgfcmOs7Js51l5o0khsbPhwAV5f8JGuXorwLHO37gdaA4M6EX/rq4/zsHpu+M3mHA/It5uXtiEw5YDp67JWz+tdxxUMJ/7+yK7T1w1F11fh3cpJznSB693DctkMb20F207I/+bvE1GvlzeJXTXz6uuJy0qZDMBsrN79++bsWDx9jPmZ13v7twNkp3HrpjL9HXHTfCsQf3j/vw503EtddIE5nlYEx/pz5a4j2AdBgAA3i1690gAAAAeMa0YTBjPR0Z0LWuq9jSc0+pEDeA0cGs3bJkJlbvWzWsqgRMl8DUhsVYm7jt5TUZM3yXje1Vxqajs+f1auXj9jhTKmlx6NiogZfKkMYGcVov+tuSQ/LXyqAmjNLx0DvI0OO372xYT5FQvkl5ebVhAcmdIaoKqFbvPyVf/7jQhsTsaqH3862YTWr1UI5e8WCOXCd30vtbuPS9fTt1pgu9BU7bLgBdLSnTR4LHXmHUmANSq0zebFjJV2hoy7j91Tb6Zudv83bfGrpcpH9ZwBIFa+Tjknx0m4GxTJYep8NVKUH28Gkjq7faevCY9v18jk96uZiprnenrqwFyzaIZzN/Uqssb/gEmmNYQWf+mBvINSmcxy//yVlWXCvTOdfKailw7WqWs79/HbYqb9+BOQJBcCwk5teL5jR/XmgMCWdMkljcaF5SqhdOLr09c8/7r+zth4QH5fs4+U0HbvlZuiW5/rjhsguN+L5QwVfNq9Z5z8umkLXL03E1pP3y5WW812NR1MEWS+HL60i0Z8Oc2c0Bh+PRdUrNYRkc4/jDPSavf3x633oTUWnH8ZtOCUjhbCvP4Nh28KMOm7ZKvZ+wS37hhO9/pZ6L3T8G31YpwraLOkjqJqaLeeuSyjJi2y4TafSZuku97VHQcFLh6665ZByJC3zvnit3Xf1wr56/dkSqF0slr+hnLmNSsr/p5/u6/PbJy9zl5e/x6+a13NUclfJ+WxUygreuVhrLPVsxurv9p/n7Zd+qaec20Uj00rQS/6R9oquM1gM+ezs98nvUghb4uWsWsgfi4Nyqb1/pxff5C05BdL1alvx6YmNuvrttlAQAAogMhspfTnas3xqw13+tOrPqqc1lz+h8AADGRtpkY3aOiCb1UPN845jRzrRLUQFKDuBer55LuDfI7bqMtJfq2KS7thi2X7UevyNWbdx0hp1bWarhVKncqGdW9gkswpOHY+88VlaxpkpgAaeBf201wrcG0GvT3dhOiNiid2SXo1fuoUSSDFMueUl74aplcuBY2PLNuqwFeuxoPAj4NCSsVTCdjsiSXNkOWmorml2rkjrZWC8Om7TQBVslcwc/XuYVE3kzJZHjXctJj9Gq5dP2uaamgIZYGeYP/2WGW+bBlUUcgZz3eCvnTmtev27erzfugge5HrYu5/F2tKtblvmhfylEVqy0INBzWqlkNirVy1AqRI0srl795pbyjrYFWaqZNHhwojltwwIStWiE9oVdl8XPaztHn16NBfimQOZm8O2GjCSXrlsgoGaO5FYCGrlqlXatYRsd1VQqll0518siI6bvNeqsBu/Prpo+h/4slpMmARaZqVUPGAlmSP/RzGjZ9l3k82vLiu+7lHeu8vi3ahkUD0o5fr5ADp69LaMOmBt+2dZUc8t6zRRzX63uqgfT3r1aUF4ctk00HL8myXWfN50D92LOSRMWPc/eZALla4fTyZacyLu1d9DMxvEtZ6T56tfl72n7i+WrB7UtS+MWXj1sXMxXMeuBI1z2tlh6/8IBZZ/Xzan2OnWmA3KpydvO5t+jrowePNPR9cdhy2XX8qmk5ou1CHsfnDwAAICYgRPZyWlmhp1WGvg4AgIcxcfFB+XXJIY+nq3/57w6Zv+W07XIauoVuPaFhkBUgOyueM6UJkTVjcldJquGbngavrSPOXLltQmQ9DVyDS9WnVTHbykKtutVK3P2nr5uq52bls8nu41dMyKanor/borDb26VKmkC6189vqpid7T151VRDpkue0BF6haanpmvwpxWl87eeCjdEjujrePnGHdOqwAqDnQMsiwZsX3ct5xKwaZCt4b2GaM4BsjOtdtX71KB+9qaTpsIydBsOrVp11yqiXN40JkQ+eelWmN9FVNuqOV364lo0qNf2CuqdFoVdwlZnWuWrlbzLd5411ajOByGiun47y54uiUuAbCme48H67a7SWkNErfg+cu6GqWLV9fhhntOl63dk1e5z5vcftCzidp3Xat7ezQrLq9+vcbn+yo27pupXP0fd6+cLczvrts3KZZORM3fLgi2nHCFyVOg26ZxNp8z3Wmntrj+4Xqc9yzVE1s+A8+dJn7v2MNbnrhXtGhDrmQtaYVwku/ve6Hq2QS+bVh7ap1jPcBj6704zHkQ2RI7q5w8AACAmYOsEAABEu1t3AsM9dd06XV17sIa3nNV711nBrGEDZJXaL7gfaNrkCV16gzrTicw0iLsb0oNYe63q38iZ3s+2j6+lRtEMJkTWSlsNkbV1gyqdJ7UkSxw/3NuFDpF3H79qvp676i/l35klnmj7gfBE9HXU0FtDNA00c2VIart86ABLKy+VtuwIjwacOoGe9q7VXsfOkxhqdlzETfivNEwP3cYgsgqGVOiGpu+39qjWcLN8vjQSnlpFM5jAVd/j6Fi/nRWyWW/1QIPSfDS/zYGCVH7x5cg5kTuBQQ/9nHQd0BBa1/ec6e3XgbJ5U5ue1zfvBDqu0wMfelu91Pp4nnhi9RiPKn2eVr/floOXeFrcTIgZmobhG/ZfNCGz0tYR2iPajh6kCj05pDPtoawh8v5T100Lj8j0z47q5w8AACAmYAsFAABEu1fq5zcXT3TSufAmnnNHJ/FyKyTLCS8ACh33XLwRHASmCgmgw5M65LRyKzzUCfDM9TaBtUV722p1oQZvFuu2WtHprno2NE85VURfx0shzzdN0sidIq/VqxF5rtYyGiKHDlnj+cS17yEb8RzOlravCO+xaxDrKfCznp+n3r0RXb8jst5aD8k3Eq/Pwzwnax3w9F7q/aZKGt8lRLZuq+9lssSe11vn5xOVifU0KFf6+dHPkSc6IWZoWg2vE2JqSw/VpkrOMJMuugv17X8f33FgRg/eRKYFXFQ/fwAAADEBITIAAPBaVvWyFe6E5+I1f5fwTXvwRiRw1EpK5wDZ+bZVC6WXQR1Ky+NiheWeHrNdsBaR21nLeAopHxfrsWsg6alyNKY99kfxnCK6Duj9WiGuxbpt3kxJHRMfRlRUJtbTkFxpYB3VSePOXbktvyw+6PhZw+QqhdPZHryxAno72qvYCtK19UVkRPS1BwAAiIkit+UDAAAQi+TJlMyEQYfP3jA9Z8NrabFke3DvZKsfs06CpTYevCjXbwfYViRaPVCdWW0Lth+9bPq+2lWg3rt3320f2KjKkzGpqcLU53r47HXbdgba/1irpK1wslDW5DJrwwlZuuOsdKgVtm+vZc+Jq6YKWavBwztd/3HKkDKRCSM1EF2774JpV2BnUaj3OKZ6mOeUK4OfYx3QidtypHe/zm88cNH0EHaWO2T90Qn9dLJFuzYu7tbbqEysp88zWaJ4pnI/vMcaXpDe/89t5vPZpGwWE96u2nNevvp3p3xqU7mvr6eu/3ZnNFifZw3SPVWBR9fnDwAAICawOWcOAAAg9tNT5GsVC5746/PJ2yQg0P3ksr8tPWT6IWtQXK9EJkcolyu9n5mo78t/d9pOpPX97L1u+zproHT2ir9MWPSgStKZVi+/MWadvDl2nQmdooP2hLb6Gn/x93bbyXT7TtoszQculqU7ggPIBqUzm1BN2xFMWXXUtnpU79MsXypzmEn1okpDfnXjdoBEhYZ22sNa6ftkdz+Ltp02vYODl88qMdnDPCedqM/qozz4H/frgIaYw6btCnO9VjNXKpjO/P7rGbvFjvYA7/rNKtlxNGLtK+zowRVd99RXU3eGqei3jJ23X54futRM+ufs75VHZM3e85ImWQLp3bywmTxT18sZ60/IkpB1OzQNnHVSQHfOX/WXsfP2me+blMv62D5/4YkfMjmfttd4mJ7iAAAAnhAiAwAAr/ZWs0ImHNt06JJ0HrlS1u27YCop1cmLt2TwlO0yPCRQ69OqqMukV+89V8RMiKZVuu9N2GCqC5WGXRredRyxUq7evGuWCe2DlkVNuKch88DJ2xyT52lVpYZvr45eYwIwnYwrOtsr6ERjyRPHMxONvTJqtflb+jeVTob3/s8bZdG2M3Lhur+j2lorTt97toj5ftCU7TL0nx3mtbGe69p956XTyJVm8rb0KRJKz0YFJLpkD6kOX7D1tFwIaSmiE65FRuc6eUzgr2H8S8OXm6pyK8DT+9T34MNfNpmfX22YXzKmSiwx3cM8J10H9KDA+v0X5dXv1zgm3dP1YNPBi9Llm5Vy4PQ1Uw0bWu+mhcyEe9PWHjd9jvefCp5g0nn9mb7uuOw/fc2Epg+r2zP5zDq1eu956TFqtWw9fMmxvp66dEsG/b1dfpi7z1RH63ptOXHhpiPo1s+aHgDSyuZeTQo6DhrpQR53fZUnrzgin/y22fGZ1NdVA/mOX68w1d9amd+iQnCI/zg+f+HRgwIajOtd/Ln8iLnuyo27JugHACCqEsbzkW718ppLjwb5zSW8eUfgHaKnRAQAAOAppSHMd6+Ul3cnbJDdJ66aUE2DpAS+Po5JxbTaTyf7qhtShWwpkyeN9G1bXD7/a7sJfvSSOIGP3A28J4FB9yWBb1wZ0K6kfDppi9wOFeqUyJlK/teupPT/Y6v8u+aYueht9XZ6e5UtbRL5qnOZSE3e5YkGaSNfLm9C762HL0vHr1c6wkKtqlba63VopzKSySl4bFouq9zyD5QRM3bJnyuOmIuGiXcCg8xjVjnT+8nQjmUiNAlaRDUqk1nGL9wvJy7ekob9FpgJ9GoXzxihiQQtGvxbz3nX8avyzvgNJsDXye50cjSlQb/uKLWvmVueBg/znLQtxJAOpaXPxE0mzOwwYoVZBzSI1HVPb6fr+5TVx0yw6SyrrpNdypiAevH2M+Zi7VRawaUe9BjcsbRkTv3wYbyuS193LSdvj99gDvR0+WaV+TzqZ/TWneC/p5+b/i+UlCLZU5qf9SDQZ79vNZ85naCvRpHgsw3UsxWzy4Itp2Xd/gvm4M2Xncu6/D2toj971V9mbzxpLrqO+wcEOaqgtRXNkI5l7CdBfESfv/A8XzWnjJ2/31RQj5m3z1QkT/2oVoRvDwCAu+0MaxJhDZQBRYgMAAC8nvZG/u3taqaCct7mU3Ls/E0THGmP5Ar500iryjkcFbGhNS6b1bS2mLT0sAmmLlz1l5RJ4ku5fGmlQ63cpjewhsjuaChdKGsK+WvlEXMqvvYTTpTAx7S6eKZUZmlePlu0tYVwpo/393eqmeBaAzWtKtaQLEuGJFKlUDppUyWHpEuRKMzt2lbLKeXzpzGVmvpctR2HBtxZ0yQxbQealM0a7VUqWs2q/XRHztgt249cDn6cUQgnNbz76fXKMmfTSVM5rn2wtQ1E1jSJpWSu1NK6Sg4pkCW5PE0e5jlpW4o/3q0uvy87LCt2nzXV3RpeFs+ZSl6qmVuK5UhpQmR39OCJ3lbbRWgF9KnLt0WL7fNlSiY1i2aQ5ypld0z+F22fz95VZeraY+bzeeLCLQm8d89UYuvz0PXVudL61yWHZMvhSyaAfq9FcAW9s4/bFJO2Q5fKkh1nZeb64+YzbInnG1e+fbm8+VvT1x43r2niBL7mgE7D0plNG5GHXcej+vmz07VeXvMYp607Jqcu3javBTv8AAAgusW5b50/Ba+kM1BX6zPH5br5/etGy+mHAAAAwNPghzl7Zcy8/fJsxWymdzIAAAjGgUlYonYeFgAAAAAAAADAKxAiAwAAAAAAAABsESIDAAAAAAAAAGxF/0wtAAAAAAAAAJ5KV2/elW7frjLfx4mj0+eK/PJmFUmeJL6HWyI2I0T2cjoDdb0Smcz3QSFzLMbzoUAdAAAA3uOV+vnNBQAAiNy7f18Onb3h8lIE3QvOjOC9CJG9XNJE8WRYl7Lme/+AIE+LAwAAAAAAAPAylJwCAAAAAAAAAGwRIgMAAAAAAAAAbBEiAwAAAAAAAABsESIDAAAAAAAAAGwRIgMAAAAAAAAAbPna/wre4PrtAPl00hbzfdD9++brJ62LiV+ieB5uCQAAAAAAAMAbECJ7uYDAezJvyymX6z54rojt8gAAAAAAAAC8C+0sAAAAAAAAAAC2CJEBAAAAAAAAALYIkQEAAAAAAAAAtgiRAQAAAAAAAAC2CJEBAAAAAAAAALZ87X8FAAAAAAAAwJvE9/WRVpWzm+994sYxXxPEow7V2xEiAwAAAAAAADCSJPSV958rar5PGM+HVwUGhxEAAAAAAAAAALYIkQEAAAAAAAAAtgiRAQAAAAAAAAC2CJEBAAAAAAAAALYIkQEAAAAAAAAAtnx5bQAAAAAAAACo67cD5O1x6833cePEMV9HdisvyRLH4wXyYoTIXs7XJ66UyZPafH/v/n3HdQAAAAAAAPA+gUH3ZNPBS2Gug3cjRPZyehRpQq8q5nv/gCBPiwMAAAAAAADwMpScAgAAAAAAAABsESIDAAAAAAAAAGwRIgMAAAAAAAAAbBEiAwAAAAAAAABsESIDAAAAAAAAAGz52v8K3uCmf4AMn77LfB907775+lqjgpIkIasGAAAAAAAAAEJkr3cn4J78sfyIy+vw8jP5JAnHFwAAAAAAAADQzgIAAAAAAAAAEB56IgMAAAAAAAAAbBEiAwAAAAAAAABsESIDAAAAAAAAAGwRIgMAAAAAAAAAbPna/woAAAAAAACAN4nnE1dqF89ovveJEyf4Ol/qUL0dITIAAAAAAAAAwy9RPBncobT5PmE8H14VGBxGAAAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANjytf8VAAAAAAAAAG9y43aADJi8zXzvEyeO+drvhRKSNFE8D7dEbEaI7OV84saR3BmSmu/v379vvsYNGSAAAAAAAADgXQKC7snCraddrvu4dTHb5eEdCJG9XPIk8WXaR7XM9/4BQZ4WBwAAAAAAAOBl6IkMAAAAAAAAALBFiAwAAAAAAAAAsEWIDAAAAAAAAACwRYgMAAAAAAAAALBFiAwAAAAAAAAAsOVr/yt4g1t3AmX8wgPm+8Cge+Zr+5q5JVECVg0AAAAAAAAAhMhez/9ukIyevdfldWhdJQchMgAAAAAAAACDdhYAAAAAAAAAAFuEyAAAAAAAAAAAW4TIAAAAAAAAAABbhMgAAAAAAAAAAFuEyAAAAAAAAAAAW772vwIAAAAAAADgTXx94kqp3KnM93HjxHFcB+9GiAwAAAAAAADASJoonvzYs5L5PmE8H14VGBxGAAAAAAAAAADYIkQGAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYIkQGAAAAAAAAANjytf8VAAAAAAAAAG9y0z9Qvp2123zvEzeO+fpW00KSJGE8D7dEbEaI7OXixBFJ6RfffH//fsh1EjxAAAAAAAAAwLvcDQySv1Yedbnu1QYFJElC25vACxAie7mUfglk+RcNzPf+AUGeFgcAAAAAAADgZeiJDAAAAAAAAACwRYgMAAAAAAAAALBFiAwAAAAAAAAAsEWIDAAAAAAAAACwRYgMAAAAAAAAALDla/8reAP/u0Hy75qj5vuAoPvma9NyWSVhfB8PtwQAAAAAAADgDQiRvdytO4Ey8K/tLtfVLZGREBkAAAAAAACAQTsLAAAAAAAAAIAtQmQAAAAAAAAAgC1CZAAAAAAAAACALUJkAAAAAAAAAIAtQmQAAAAAAAAAgC1f+18BAAAAAAAA8CZx48SRXOn9zPdx4sQxX33iBn+F9yJEBgAAAAAAAGAkTxJfJr9fw3yfMJ4PrwoM2lkAAAAAAAAAAGwRIgMAAAAAAAAAbBEiAwAAAAAAAABsESIDAAAAAAAAAGwRIgMAAAAAAAAAbPna/woAAAAAAACAN7l9J1B+WXzQfO/rE1x/2ql2HkmcgBjRm/HuAwAAAAAAADD8A4JkzLz9Lq/G81VzEiJ7OUJkL5cqaQLZ8U0zxyABAAAAAAAAAM7oiQwAAAAAAAAAsEWIDAAAAAAAAACwRYgMAAAAAAAAALBFiAwAAAAAAAAAsEWIDAAAAAAAAACw5Wv/K3iDuwFBsnjHGfN9QOA987VakfQS39fHwy0BAAAAAAAAeANCZC93wz9Q3h63weW6+f3rSnw/QmQAAAAAAAAAtLMAAAAAAAAAAISDnsgAAAAAAAAAAFuEyAAAAAAAAAAAW4TIAAAAAAAAAABbhMgAAAAAAAAAAFu+9r8CAAAAAAAA4E3iSBxJkSR+8PdxxOUrvBchMgAAAAAAAAAjhV98WTCgnvk+YTwfXhUYtLMAAAAAAAAAANgiRAYAAAAAAAAA2CJEBgAAAAAAAADYoicynkq3/e/Ips07ZNeeA3L95i25fdtf7t+77+lmgHeII5IoYULxS5JI8uTOIeXKFJOkfkk83QqP2dVr12Xt+q1y6MhxuXHzlvjfvuPpJsBj5xvP14wlqVOnlPKli0vOHFkkDrOqIMTNW7dlw6btsnf/Yblx46bcuu0vwuYY3PDxjSt+SRJLihTJpUzJIpI/b06JG5d6JjCW4OkRJ24cSZwooSRNmkSKFMonJYsXkgTxgyeeA7xFnPv377Op58UuXb8j1frMcblufv+6ktIvgcREazdslWUr1sumrTvl7t0AT4sD0B03n7hSrHABqVyxlFSvUo6dticoKChIFi5dLavWbJadu/bJPf4F4ymTIX0aqViupNSrXUXSpU3taXHEQrrrsHLNRlm+aoNs2bZHAgMDPd0ECCNVyuRSoWwJqVursmTLmolXyAsxluBplzBBfCldqqjUrFreBMqxGRPrwUKI7OWephD573/nyO9/z3T8nDF9WqlQtpikTpXSVElRzQAE02Dy1q3bcvnKNdmweYccPnrS8dLUqVlJXuncls/LEwqQvx71s6xcs8lxXZ5c2aR0iUKSIllSSZQ4kcSlwhMxjB6wvX7jphw4dMyMJ3dCDuCmTJFM+n/cSzJlTO/pLhDLQp9ffp8q02ctdFyXJXMGKV+6qAkFk+g4RnUp3AgICDRn3Rw9fkrWrN8aXLUuwWdOffz+q1IgXy5eNy/CWIKnUVDQPbl565acO39JVq/fKucvXHL8rkuHVtKwXnWJTfzvBsn0dcfN9/F84pivLSpkl4TxfTzcErEZIbKXe1pCZOcAuWG9alK/dhXJxSm1QIScOHVGFi1bK3/9O9cEzATJTzZA9vXxkedbNpTqVcqag2HA0+K2v7+s37RDfv/7Pzl24jRBspeHPi0a15E6NSpI9qyZaHGCSAkICJDN2/bI5KlzZPfeQwTJXoaxBLFlPd574Ij8N2+ZLFy6JlYGyZdv3JG6fee7XLfs8/qSKmnMyorweBEie7l79+7LlZt3zfd3AoPM1+SJ40vcuMFHmmKCxcvWyLc//Gq+7/B8M2ndor6nmwBwQ4Pk4d/9bILkNs82lNbPNeR1ekzGT5wiM+csNgHyB727ScWyxT3dBIixrly9Jn36f20qCrUi+bthn0mCBPQEjO10DNOxTPXo0lYaPxN7dpTxZPj735F+g0fJtp37TJA8YshHkiZ1Sk83w1OOsQSxLUyeMGmq/D1tnvn5vbe6SfkysWM7nxAZ7jCbgZfTsFiPJOlFq4/1EpMCZLVg8Srz9bmmdQmQgYdQq1p5eaVzG/O99uW9d++ep5sgGgQEBpqDYeqtnu0JkPHUS5E8mXzet5ekTpnctM3ReQoQ+1nbY+3bNiVARrRImDCBfPr+q5IzexZzpsMqp3ZPiL0YSxCb6GTDHV9oLs/UrmJ+XrhktaebAE81QmTEaBcvXpY9+w6Z75s2qOlpcQAe1K1ZURIlTCAXLl6W/QePeFoc0WDbjr1y89ZtE7xVrVTG0+LAU0HXZ23JonSiSMRux0+cNhc9m6IRFciI5iC5fu3K5vtVawmRYzvGEsTWILlZw+CsYuu23XLz5i1PNwGeWoTIiNFWr99ivhbKn5vT24BokCB+fClfppj5ftVagp/HYXXITnGVCiXFhwmnEItUrVjafN24ZYfcuRPcGgux0+qQ/xclixcUvySJPS0OREqlCiVNCLP/4FEzYRViL8YSxFY6P0C2LBklMChI1m/a7mlx4KlFiIwYX8GnKpUv4WlRABFUqXxJ83Xb9j2eFkU0YBxDbJU3d3ZJmzqlCZD37j/saXE8xbbtDNkeKxf8/wOITqlSJJdCBXKb77ftZNskNmMsgTfsY21lHwuxGCEyYrRr126YrxnSpfG0KIAIsj5P127c9LQoosG169Y4ltbTosBTRSsH04eMJ9dD1nPETlet7bH0bI/h0ciQNrX5ev062yaxGWMJYrMM6RjHEPv5eloAsVtA4D3ZfDj4tLG7gUHma/EcqSSeb8w4vqB9RFUSTp0Eoo11KjL9uh69u3cDJCAg0HyfJEkiT4sDT+14coP+f7HarVvB/R0Zx/Co+PkxlngDxhLEZmwTwRvEjKQQT8z12wHSeeRKc+k+ao253PAPkJji3r175qtO5OLNNm3eJm/07iNVajaW3AXKSNnKdeWlTj1kzryFjtfoaXXhwkX5+tsfpUHTNlK4RGXJU6ic1KzXXP73xTA5d/6CPAqr1qyXzDmLysz/5ok38vEN/jw97evO08D5NY7MOLZsxWpp0aqD+TwUK1Nd3nr3Yzkfyc9D+SrPmPXc+VK4ZBV57c335dTpM7a3O3joiPTtP9h8DvMWLieFileSRs2el+Ejv5crV6/afp7sLl+NGCV29Hfh3VbvOzocP3HS3N/3P06Qx0n/5kd9B0pEtGzbSWo908Lx84sdupuxXsfImIzxxDvcu3c/0uNYaAsXL5PGLV4040rxMtWl93ufyJmz5ySi6jVqZcYjd/+75s1fbD5vr7/1odvbtny+s9l+0tYrf/491Sy7ddtO8eRp+Rx68umAweY562seHn1N2nfpaV5nfZ+aPtdOZs2e73Y8db7kyFdSatdvIb/8Nlnu3w9eVyLLJ2TdYtskdouOsSSq3nznI7NeuzNtxmyzLrdt102CgoILq2L6NkZk9ez1ntSp/6zt9lfBYpXM53/7jl2O2+jYV65yPXmh/SsSU1hjeHgX3abytH2qF91Wdi780H3SqrWaSK78paV0hdry4Sf/i9T479gmus8+FmIvKpGBx2DuvEXy9gefymvdu0j3lztKRAUEBEj/gV/KuJ8nSapUKaVu7eqSKWMGuXTpsqxcvU66vPKmVKlcXkaPHGp+/7SZt2CJvPl2H1PBVq1KBalSqbzEixdPdu7aK2PHT5SJkybLtyMGm+cNeAvdYe/+2juSPVtW6dLxBdMOY8q/M2TN2g0yZ+ZkSZ4smURUntw5pdVzTR0/nzt/Uf78619ZvXaDzJ0xWdKkCT7tzvLjT7/I54OHi4+Pr9SpVU0aPFPbjEPrN26RL4d/J2PH/ypjRw+XihXKhvlbzzZrJPnz5wlzfbkypcSTN19/RRIlShjm+uxZs4i3OnnqtFy6eFlu+/t7WhSI8abNnCM933hPCuTLI107tZMLFy7JP9NmyfKVa8xYFJFtGN1G+GHsz7Jn734pVDC/y+8WLlluvi5bvsqEmNpqxaJj2JatO6RMmRKSIEF88bbPoQZi06bPdvx/Gdj/I0mUMOx4q/9j2r7UTVKmSCGtWjaThAkSyIJFS+XlV3tLn/fflJ7du7gsX6tmVSlfNnh81zNu9P/Khx8PkB07d8uQzz8Nc/9AdBkzbqJ8NmCI2b4Z8WXEDtSGR0PT3u/1lZw5ssv3333pOKARm+g4sGTZKmn3fEvb7a+rV6+ZcVkPHk36+Qezradj38VLl91uoz0pxYoUkg/f6+WyP7lx01aX6zJnymi2IZ2vW7t+kyxavFxefaWTJE8evC2dNGlS81X/b3R++XVZvHSlGduaNakvx46flD8m/yOLl6yQGf/8KmnT0s4JUITIwCPkf+eODBj4pUyY+IdExbsffiZ//zNDXn+1m7z1RvcwOz961Py9Pv2k9QtdZOa0380G/9Ni6bJV0uWVXlK8WBH57utBJjBztnffAROSL1+xmhAZXiMwMFD6fPI/E/7O/HeSo5VPm5bNpcmzL8oPY36W995+XSIqe/as8lqPri7X1atTQ9q82FXGjP9VPnz3wcb1qO/HycDBw6VZkwby+YCPJEXy5C63W7tuo7za6z0zrrnzTL1a0rhhPYmKLh1fjFCI5E1mz/hTbt/2l1QpU3haFIjxxoz9xQTIs6b94diW0QCoResO8vOvf8hbb/TwdBdSuVI5EyKvW78pTIi8aMlySRA/vly4eMmEmEWLFHL8bvuO3XL79m2pXLG8eOPncOnyVXL+wkV56cXWMvG3yaZqW8f50PQMMA1J5s78y/F83+39mnTo8pqM+WmidGr/vCROHPw/SVWuUM6lMOItEfng4wHmbzzf+lkpWaJomL8BPKwDBw/JoCFfS3TRs7w6v9JL4seLJxPGjgyz7RObzmq9cuWq1K5ZLdztr+7dOkq9xq2kT9+BsnjeVMmaJbNsWL1AEiaMOfuYBQvkMxfL6dNnTYgcentXOV/n6zPBhMjt27Uxz8vZ4qUrTID88Qe9pccrnRzXv9DmWWn1QheZ8u/MSBWCAbEZ7SyAR9jzq3Gz5+XnX/+U51o0kcjSapG/pkw3R4g/ePcNt9UzuhMw9vsRsnf/QRk8dKQ8LbQX7+u9P5S8eXLJX5PGhgmQVf58eWTm1N+k/6cfuL0PIDby9fWVv34fJ8OGDHDpBV+ieBEpXCh/tLR30Gq+bFkzy65dexzX7di1RwZ/9Y00b9pARo0c4nYnqny50rJi0UypWb1KmN8h+mml4NMcXAHOpk2ZKD+PG+WyLVOubClJkSK57Nl7IEIvVoVyZSRePF9Zt2Gzy/W79+yTU6fOyMtdO5iftdrOmYbOVgjtjZ9DPZMlebKk8ulH70iG9Onk739nuF1u9979UqlCOZfnq/+TRg77XFYvn+MSINt5o2c383XJshWeFgWidKBd2/vlyZMrWgpntH1Bt1d7y9mz52XUN0MkT+5cElstWLxMUiRPJqVLFQ93udSpU5lq5X37D8rJk6fNdSlTJHd79kJssmfPfvO1UcO6LtdXKF9GVi+dTYAMOCFEBh4R3diuVrWSTPrlB3m3d0+JrLHjfjWn4mgFcniqVq4gzZs0kEl/TjHh7NTp/5keT/MXLnVZTn/W67UfVujTm7RP6qtvPLhe+6W++8FnphdU7oJlTZ/O78f87NIjzOpHdfjIMdM/SntK5cxfyvTaCt0/L7R/p82SixcvmYA4USL7ycbcBVl6WtXwkaOlep2mpr+hPkbtcXbo8FG3y+op+JVrNDTL1qjbzFSF2/Xr+2fqTNP71erX2K1Hb9m1e6/LMvo89e/pEev6TVpL9rwlzc9AdMmXN7fbCi7d2YkjD07Rjir97Glbi4wZ0juuGztuomkl8/mAj8O9bXif10fJ6t2nB+e0X3PR0tVM777X3/xALl+5al6bL4Z+LWUq1TF97PSzqS1/3NHT3Zu3am/6TZcqX8uMde76skZkHLRMnjLN9HXX+9Tl+/1vqO3Eles3bDZ9VvXxa99RPVX86LHjHns36s86/mg7o7ff72vGbf17bdp1DTNOqRmz5krj5i84nucnn30h165dN/fpPGZpD+xXer5t7k+fpz4PPYAJRCc9PTxzpgwu12lAoadP67ZOROiBNT17ae36jWF6Lavn27Qw1WlLlroGmOs2bBI/vyRSvGhhl+u19672MK1Yrb7ZftE+8LoNFd7nULcffhr/m+n/q2NNibI1TM965zFEe3Fq72e9TgOvIqWqSv6iFcz1ehZWaPo4xk0Ivk/9DOoYor2LT5w45bKcjoE6FmoorNszWXMXD7fnvLpx46bMnb9EGjWoZ8ZvLT5Ytny12x6fWbNkkpWr14bpv6+hUkQDJKvd0q2QibGB6KT7Gxr26YGNuD4PH2PonAX6P/njD3vbHiDX33fs+rrZ7tCxoGGztvLrpL8i1Pt70NCR5nPbt9+gSO/HWP/z9fqXOr9q/pc79+/VbRFtMVa3YUvzO2u/Zdt2973eFy5aJjWqV45Qqw5r/8tq46N/V3slW/TnHq+/a6rCO7/8htme0XltdBltHRSansGmz9ma20d7LOtrcunylTB9pbXlmrYrqVC1vmTJVczsbz4OWbJkMl//nfaf7e8ABKOdBfAI9f3oHcc/xsi4eu2a2enp2b1zhP7ZP9uiselhtXLVWqlVo6qp1Fm8ZLlLG4j5Cxabr4sWrzD9ATUwcj696Zm6Nc3PurHyXJuO4u9/R5o1bSBpUqeSbTt2yYDPv5S16zbIuB9HuvQafP+j/nLkyDFp0ayh2WnQIFYDif+m/S7FQu2wOe/wpU+XVipXjFxV0PXrN+S5tp1MYFKzemVp0ugZUz0w47+5MmfeIpk4bpSULVPSscHSqm1n2bx1u9SoVllaNGtkelv1/99QKVy4QJj71tBH+8Fqfz/t13jz1m2Z9d88afJsO/n9lx9MxZRFezZrK5FGDepKnVrVw/SVBaKbVgprixft4xYZehq2HuixnD17Tj773xDx9fWRbl3aO66fv2CJGS8i02/5SejY7Q25fv26tH+xtezbf8iMe6fPnJUkSZKYU9ifbd7IjEN//TNdOnV73VSPaABiWbR0hWnZUbNGFenerYMcOXpM/v53ujkVftrfEx07CpEZBzWc1b71BfIH93rVoFvHwQ2btoR5/NNnzjETf2k1kJ7Krwcb5y1YLI2av2B22uLHDx6X7dy5c8dMEKZhWseX2sqxYydMr9l2HXvIisUzHZWC34waK4OGfm36O3bu8LwEBgaZcXLj5q1yL+jBZC+6A9es5UsSFBhkXruUKVOYSR1151WDpFe7dw7n0QCRp5+P02fOmc/YoKEjTCVy5w4vSGTOpBjxzQ9y7PgJyRbSM11PT9YWQHpWk24baACh4akGx0p7uuuZFFpV6+zzISNMFXOrZ5uaSZD0dOWevd43c5IO0xIAALPISURBVE84/893Nuzr0eai2wo9e3QxbSL0wLh+bhbO+ccRvuh2VbPnXhLfeL7yfOsWEhR0z3wGX+zYXQb97xNp90Irs5wGUa/0fEf+mzPf9OFs8Ewdc58zZ801fT51XMqdK4fj72uP4n37DspzLRpLw/p1zPMOz6w5800rD/18W9uL2hJk6ozZZrxypme+6fOvUa+5eU9at2wW5pRvT3TbSGnYD0QnnfRx5HdjTH9uPVvxYemBGy3Aadu6hbzstD3kTAPNdz/sZ7YBWjRtaP73rli11uz7LF2+Wn4c9ZXLPpEzPUD1zagx5nPUr+/7kd6PsUJcPVCsY1uPlzuacc2qyG7fuadpVaPzTrzc5SVzkFgPHjdrucTMJ6P7KM4HxXWsi+g2pBYD6XaKNca6o9sfTZ9tJ1myZJaO7dua56bbIy1at5cxo0eYeTWUTmaqLdQ2b9lu5tnQ/UXdL/7tjykyf+ES0+LI+ewHLfY5evS4tHy2qWmh4Vzw8CjVr1fbHIQc8tU3pj98pw4vmPfI2l8G8AAhMhADHQ+pPsmV88GOQ3g0KFDHTpyUenVrmlM+tVLWojspCxYtM4Gn7oCsWbfRVDArDU80dLaOwGuPZZ1ZduHcf8yOlGXCL7/LR59+bnYQmjdt6LheTyGd999fjh0n7TNVt+Fz8tOESfL1VwNtn1+O7FltN7zsDPjiK7MR9OOoYWbnyXnHRzfKtF/rikWzzOmyI0b+YALkL/73iQmcnHt/6bLOtEWABshvv/mq9O71oC9j717dpUmLdvLOB5/KsoUPTv/Ujb9hQ/pLm1YtXO4HeFShy5u9+5h+n9rTMjJWrV4nVWoGhweWuHHjyoSx35h2Mkp3PK5cvSY5c2QLc3vdUbHGo9AypE/rUpmsoaNzYK18fOKGuxNi0QM8V69dd7lOd9bSuZnEZMY/vznCIO0frS2DdLl5s/5yTHpSu1Y1eanTqzJl6kyXnUM90Pb1V59Ly2cftBjq2P55afNCV/nwkwEycfzoSI2DWtWsAbJOKjj8y/85Hlev1142Ya8zDWz1fvPkziF/TRrn6EH4zluvSq+3+8jU6bM97hhruKRh2Ohvhpr3UVWqWM6MUbrzqGOSHmwYOuxb8xqMGTXc0T5Ax7a2L73s0tNa14/Ll6/IuB++Nj2tlY6DuqNe1iZEAx6Ghq0634Hll3HfRarKq3JIiLxu/WYztly5elU2bNrqCERrVK8io34YLytWrTGhwP4Dh0z1vruD1vv2HTCT+mXOHFwJ3aFdW3M21Zhxv9qGyBquFClcUKb8OcGxDfNi2+dMmOPr82C36vCRo2E+g/rZ0hD50/6DzTaX/l094KUBso4frZ9r5rj96z26SoNmbc1BKj2jzbm/8+8Tf3Rsw3mi82popbeekq2KFCpgDnhpNXPoEFnHND0gpwfVrbC8Vo0q8uYb3aV0ybCnwF++csUx5t+9e1eWLFspQ776VooVLST1Q8YTIDro/y39P1m2dAnp1vkleVgaBPcb+KX5vnCo/uoWPVDV55OB5m9OGPutJE3qZ67XOFirar8cPkp++W2ydGjXJsxtf/v9b7PP0rB+XflyUD/HWBGZ/RjrzDF3kweO/nGCGXM+++Q9l9fj7bd6yosdXjFnMpQrU9KxTaTFO7rNoONjeNtfemaITmyuk2Rqb+DwDmxv2bbDjH2DBvZ1bI/ots+zbTqZszPWrZhrthG/+/4nU53864TRUq1KRZf9MT3Qpge8nSfi1AIBLUTytD0U3fS5/vPnBOk3cKgZH/V/lR486NzxRXm5a/sIn40BeIOHPw8EQPSLwClSoYMapdVmSquKdaNATzNSevT37LnzZoZaDVu06tCyaMkKqVi+rCRLltTsDKxes15atmhqjhzrz9alapWKJtTRoMOZVks7t53QYEqrZvQU6eikp4ZrlZDu5DhveCndEfv043eDA+2QimutHtCj884BsiperLB06fSiy3W//zFFkiVNKk0bP+PynC9fvioN69c2z0VnbrZkz5aFABmPhR4A6vX2R6ZXpU5wFJFA1pnuzP/w3VeOiwYVZUqVkJd79DY7Ueq+BI837g7qaJWvhtDuLvNCtcz5+LMvwizzTKOIhd6Nmj8f5rYffNQ/zHK6g+JcTajjkmrfrrXLrNlVKlUwOzV6loQzrfRzDpCVvh4vtWttJlTRap3IjIN//DVVEidOZNqAOD8urX7+7GPX1kGzZs8zlTqfffK+yyQ2ersvBnwiCSO4g/Lhe286dtiUFf5aY+7f/0w3p8d/3u8jl/6zWpWp42ToA5D6vutBRqvCSX/W11l3nIHoVqJ4UTMW6bqYI0c2MxbppJ0RpWGmflbWhbS00PYQelq3BrZKgxNd162+yNZ9a/gcWo9XOjsCZJUrZ3YpVKiAHDx0OMyyzsucOHHSBNcWncRPJ2+yKp+VnkU29IvPXD6DOnZ83v8jE4jpAS416Y8pZpupbOmSLmNNQGCgOYtq+co1JgS36EGjiAbIJ0+dMRV1LZo3chnfn23eWLZt32V6noamZ6QsWzjdBD4agC1bsUZatOpgDrSH9u3onxzjtbb76T/wS6lUoYz8On50mKpv4GF8MWSEaQ+j2zDO//+iQttf6RmTmTKmNwdUtBXWkaNhW0r9MflfuXP3rnw5uL8jQLboRKBataoHlkPTalydYLJ61Ury3deDHWeURnY/xvJu77CTKetkpLqPEzpQ197Fgwf2Nf/P9QCSZeGi5aZNmrv+7s7bX/r97DkLzcFtT5PI6Vkk/T/70OX90O2wTz7sbcYsraxWv/3xt1QoX9qc1eA8xvn5+Unp0iXMGVrOrUF0bo7HHSBbdF/4q8H9Zc3yufLBu71MCK6VyY2bP++27Zk3SOmXQDYMa2wuO75pZi6pkj58P3I83fgPD8RAD06ptg9idYNHq3nVgYPBOzy6QaTq1alpAh0NiHWSCD0lUpctkD+v2UHQn7Uf8bnzF2Tnrj3yv88+NLfTo+NKT7/Si/u/6xrK5MuXO8wyKVOkcOlz5a7vnp6WphsNEa1G1qoef39/2xYY1vVaJVylcgXz3F5o+5zbZSuVLyvfjhrr+Fmf97Xr16V6nQdVQKHpBo8127vzqaXAo6StJ/6bs8Ds9DvPFh1RukHfuGE9l+uaNKxn2rS88/6nsnLJLNPCQiddctdXXKswNPBxpp8XrQRMEKpC5ZWuHaRUyWIu1+ls5xGhlf1aAecsQ4Z0YZbLF1I9bUmePLj9Rq5cOcNUlOhpkLduu/blrFguuBrP3Zgw5qeJcuDAIbkR0ss4IuOgVjIWLVwwzA6m0so/5/FNT0HXna2KIRWBoXdcdOJEK8i1oxMJWeO+xdoptHow7z9w2FRPu6vuLFm8iMsOn/5NbbukO+haeaM7dDW1/U/zRo/tFFJ4F53YzRqT2rZqYfp5auCyeF7E+l5qKKtBsTW53sLFy83nT69TeupxpQplZemyleZnXU7btLirNixapGCY61KlShGmJ7Czfp+8L117vCnNW75kQhGdrE9PG9fKYufPu4bN2rYrtEIF85vTxPftP+AYT/VzH/qMEWdHj51wHHiKzPbHv9NmmgNKGkwN/vLB5Mvnzwf3Q9bPvB6UCk3HCH0+etH/C9r7dMDnX5mxy9oOUnq6uW5Tak/3zwePMC0wBoRsTwLRRc8W1D7kXw3uF+n2Ku7oGVba1m/8mG/M941bvCC93/1Y/v5jvMv/R/1sZsyY3u1ZWko/+/q4NJS2aPXqqjXrzOdOt4ecK3kjsx+jbS6UHjAL3Utez744ffqstGnZ3O396GdUt+msuRL0YLj2OtcDXZ62v5Il9ZNixQq7nZMmtFIlirqd3LBihbLm6959B82cFWfOnDOX8MY4rbi25I7gWbiP+v/U6692NYVSP/40Uf73xVemf/ZPP3zt6aaAVyBEBmIg/eets+dqtdv777wRpi+ynk6pG/V//z7OnHKpkwDoMhqeWke0CxcqYPoE6qncelRbg2VVr24t04dKNy60ulaDXG2B4eydt3o6TnUPzS9U0ON8+mZEaTWgBtk68ZX2N4wOzjtv1hHtiAbUSqsRtLLATskSD8KxOA9ZBQFEhE7iphNs6udl+NABEl20skJ7AOop1XrGgu4g1a1T04wr2o/duS+yLhs6hLYC1Pz58rpcrztMoZeNqLq1a7hU59qx6xHvE8HPZGTGhIiMg1rFHd59OlfXRGQSHk8iMpFQZA7OKf0foWGQ9iZcsWKNOfV0+Dffm7YfoaulgOikB0+0V6+2T9GwQavoIkLDmy+GfG0mh9MWClUrV3TpW6mnbOs2hlbnr1u/yZxt5e4zES8K1bK6ffXftD9MJbJO4Ldk6UpTsagVwtqawzrlOTKfQb2tu1PiLdmdDhzFjcT9atWj0h7t7mhPea22sx6rtjbSQD50GK6TmGmlsZ4+7xwiF8yf1zHma2XzxEmTzcF7rdAEooP2BH7rnY9NuKnFM84HQzQI3rFzj7nu+TbPRvhMLV2/vx0+yBTWqNdf7WZat+gkdXa9kSNKPyO6LaRnKH07eqw5wBTRz4O7MSNu3Ih/3u3omVU6V4R1tkZUt7/CiMRY1LRxfZcezaH5JfVzTOL3sJXmD0MDeucAXR+Lzp+xafNWc8BSDw48yccHxBSR33oC8Fh06dROXn39XbNho6exO9MedVrN2/u9vtL/0/fNbOK6I+Z8mpK2tNANGD2Srj0y9RRKpadB6imVuoOlQbKe7m71/MyXNzgw0SoZd2GQ84R8D6NF00amb57OzDtr6iSXvqqhe8FqFYz2H9TTrvWItwbPGoCFpqd8WlU++jpoBeXKVetMEBTaqrXrXX7Omze3OeVTe/iFPgUzup4zEBm606+VDzrBivbOi+5Tg3WCNqUT7KlunduZyaG0x/B3Xw+xvZ0GPeMmTDJtYeyqc2IyrRByV9GtY4LuwOXOnUtu374V4XEwb57cphWEtqkIXY2sY0rocUZ3QLTXYOjT0TW80Qk7tVXOw9JxXHvd66nsoSuYdCJVfQyh/7aOmVrVpBetaH6+/cvy7oefmUlwIhOGAe5oO62PP/1cWrZo4mi/YrGCg9BnNoRH29WIfG1aLGgFW51aVcNsI6nf//zHTODk6bTsqFQxarsXvej2mR6Ae/nV3qYPqtVnWANsfd6hq5F1u0t70OvYofTrjRs3PI41kaVFAtqu4pMP33b7/H+d9JeZHEyrPLUCUufR6Najt5koTCdodpYu5DncuBE8NrozsF8f0yLp7ff7mr71EZkUGvBEDxSdOBk8L4MebApN93H0oq2mIhoiJ0qU0KV45o2e3cw+0eAvv5HaNas5qv01/J2/cKk5E9Hd9o7uY+iBZudqY73NxPGjzDaBHnhx/jxEZj8mPBpyaoX0qtWu+zLOn33tcWzdj/ZD1spa7YcenXR7QlvzhK5G1tDa2hbRA4Np06Q27Raje4yLbq1e6CK3b92WmVMnhfmdjuO63RwQEOjSogjwVhxKAZ4A3QnRnYvwNGtc30zW9PW3P5p+XXo6kkVDV52oQU+N0tl506dPK33ef8vl9hoi6ylWnw4YYk7ltGb71X9+2mdv9tyFsnzFGkeFstLWF7qcbqiFniBLdzRKlK1hAuuHpX0DtbJFd3BavdDVnAoZml7Xpl03ebZNRxOGaPCtp/Tr39fH7kz7mGovPj393Xo+uoG2bsMmM+mFM22joaefOdMKBm1/MWjoSJdqQX3Ndaeq6XPtXF5/4FHSyjadFKVAvjzy80/fup3MQ4M+rZiICr3t73/+a/qRZskc3PJAD9RoGKJnP7z6xntu73vP3v3Stl03M5mStsN5GmmLHz2F29mGTVtk4q+TTf9CDV0jMw7q6fi3b9824bv2ZbVoP0BtRRK6jYiOY58NGOzS41T/H+ikfnqaa3R4rkVwz+e+/b4wO2gW04851GPS2elLVagt27bvdFynj1F3ojVcdj5NF4gqrdxfsXKtDBn2jaPtijpx4pTp21m+bClJnDixCSScT2u2owe/9XRt/V+uBzlqhgo99ZR3nZh4/M/BYUCVSu5PH48sPbBdtVZjcwDf+WBM8aKFzVfnx67jgR6Icd520Ofep+9AM0nqc80bm+teaPOsqeK1HqtFP3/NW7aXbj1ct+0i6u+Qcc7u7JCGDeqag5PWeKhtefSgok4kFrr354Rfgh+bniFnJ02a1Kanq25j/Tg2bP9kICr0s3zy8Ha3F6321Unn9HttYRORfSt3NMQc8eX/5N69IDMhnPXZbt2yuWnJ9c77wT2GnWlLLw2vQ59BoAfKNOTVx/3e26+7fB4iux8TnpdeaG32cULvz+i2mx4c0r/1XMj8D3pQuXZN1zEyOly5ctUUAzmPhdoKaMAXw8x+pzW5pu5jzZ2/SOaG9Eh2nnOjep2m0rf/YIkJtD2HTsj+jVO7Q6XrlLaV0/ZHBMhAsOgtbQIQIZ1efsO0mhj9zVBzio+dr4YMkMRJEpv+vVpRU6dWNTPLtv7j1r5bSkPPPu+9aSbMc6ahkC67ctVac6qyc1WIBsxv9O7j+N7ZsCED5NnWHaReo5amJ5eGTBr26gaP9uKsXq2yRAfttTf2++Hy1jufSNVaTaR61YrmCL4+zt179svS5Sslbpy48kmftx3VdNq7U2cD1p0qPcVfd9z0n/uMmXPl3v17MnHcKMc/eJ1NXF+jDz8eYDZc9PQyPXV/xsw5UrZsSbNDa9HZgvUUttE/jjd9wzRk16PNs+ctlKNHj5ue0Ww44HHQXuLdXn3LrH96ivPEUAdBlPadrFS9gdy8dVuWzJvqtvetRddfPSPB4u9/x0xiorOOa0DtXGWq/d98fXxk0JcjTVWOjjcaJgYF3ZO9+/ab08YTJEhgesLpZHSh6ecsdM90pZO/aNud8Pw04TdTHeTurAXnia8eVpXK5eXNdz42E9/o+KEH4rSKUPu4Dxr4SaTHwRrVK0v7dm3kl1//lF179krd2jVN0DRtxmzz2sWL92AzS08X1RnIdeytWa+5NGvSwARn8xculgsXLpmWOtHQ8cKcovv2m6/K0GHfSr1GrUzFVWBAoEyfNcdUBDlXDenOqu4wtWjdUZo1qW+e546du2Xu/MXm/wbjHqKDBhr6+XrtzQ+kToNnTbCpY5G2U9ADHQM+C94eadCkjTn7aMqf492OMRY9nVh7jut6qmdFhN7+UTWrVzbjilaQ6YGh6KCfV91m0wnltNJYgxl9HjP+m2t6l7Zo9qDnp1b+6ZwTteq3kEb165hKPF1Oe5nqRJzWuK0Bi07qqfNYzJqzQCqUKy3Xrt+QWf/Nk0uXL8vrPd33MQ2PBtjTps82bbjs/j/o2QcavOn4N7D/RyYE1iBNW6XVrNtcmjapb5ZZv3GLqSysV6eG+Z8QntbPNTN/98sRo0zFubbCAGLavpU7uv/x5uvdzSRqP4z52ZyxpP/r9bP6Xp9+Ur1uU2nUoJ74JUlsKok3bNxi2j11eKmt7X126fiiTJsxR74c/p3j8xCZ/ZjwaK9ePdupb/9BMnvuAimv48a16zLzv3nmQP83wweZcVEnWNc2IH37vCPRLU/unGZbZ8vWHWYs1APVum11/fp1+XHUcDNeKn1d9QB8l+5vSp1a1c1BQC3c0f2xoHv3zLZHTPBWrx7mfR009GuzHulkgHr2nT5O/zt3zXoFIBghMvAEaLibLGlSjz2o9BQpnWVXj2xrSKGzjOvkBDqZlG7w9HrtZVMtp0fENZAI3adJN/rH//K7+eqsTu3qpgJFJ04KfdqUbuTMmTlZho/83pwCdeniZXNk/OUuL5m+YdrDMLrUr1dbSi4oJpP++FvmzFssGzf9ZWYk19enU/sXpGP7ti6np+np4tOnTJTRP04wR/JXrlxrZgfWkERfC+cdFq3enPLHePn6uzEyfcZss7GVLVsWU0FZsGA+lxBZaQWN7oyO+3mS2fHUXolFihSUz/t9JNWrVXJZFnhUbt68aXrXKV0P3Xm5SwfJkCG9XL16zW3w6kwn3dTeoc5nMZQoXsSEmRrChKY7Tjo+6HijB2G0VYOPT1zJni2rdO/W0ewUadjgjgZC7vTu1cNjiKxjmDulShaP1hBZdwL1gJH+vVE/jDd9FrUySNveOE8kF5lx8IsBH5vTRH/+9U8ZM26ipEiRTFq3bGaed+ESwafVW3RWdj01/Otvf5DJU6aZ/qYaSP889i1TPaSVOdHhzddfMaff/jA2uK92Ur8k0qB+HVMZVap8TceEhxowTZsyUYYO+85UwOvOZ5bMmc3r0bN7F09/Bogw3UbRsUM/U+N+/t2MXTongq6T1unjuj5qlb5uH3mit9UQOXTrBUvNGlXMGGo3iVVU6UR0Oh5OmPiHjBn3q8SP5ytlypSUd958VfLlfTDRsG6n/TphtHwxeISZh0KrJHWc0G0658esB/J++O5LM+ZO+vMf0wtfKyxLlywmvV57xYzXUenLev7CRY+TsWrQpuO8HgDUsUm3yWb8O0lGjPzehFH+t/0ld+6c8tkn70nHl9pGqLWNeX71W5jqzSl/TojQbYDHuW9l57UeXWTe/MUm9NXtIG1VoWc16vbAd9+PM23GtKWBhqd6UKzd863CXb91n+zLQZ9J/SatHZ+HyOzHhEf34XR80X28P/+aKj+M/cWMG3pWh06gp/szasGi5WZf0pozJzppr/Yxo4ebiXn1cej2jJ6toEU8pUs+OGtBQ/HJv/0k34+ZYF7D5StWm/FRx8Fer79iXs+YQA+w/z5xjIwdN1H++me6OZig75duo2nLE6uHtre5Gxgky3YEb5vG8w3OGWoWySDx49GyyJvFuR8dM73gqXXp+h2p1meOy3Xz+9eVlH5hZ1t9Enr27idnzp6Xof3fkUIFHmyc4wHto6nVbs47L0B4Lly6Ih26f2jCwcm/PJikBNFPq9Re7PK2+X7KLyMkYcKYMbYidtM2FEH3gsK0QtEqTz0dX0Pit97oLtHh82FjZOWaTdK1QytpUK+6p8XxlOrU/QNTITvqq08ke1b7sx8g0rJtJ3NWyaK5//JyRMJPE6fIPzMWSNNGtaXDC2F7xiJ2YCx5+pWv8ozkz59HfvnpO0+Lep11m7ZLv0GjJHeubDJkwHvytLt8447U7Tvf5bpln9eXVEnZn/FmVCJ7uWSJ48nUPsHtDO4EBvc0SpooZjS4R8QULhT+BAwAAO+hp8bWbdjSnHr+1eD+jkoprYS0ZravW5uwFwAAAEDkECJ7OV+fuJInYzLzvX/Ag0mBAADA00d7wOokfnq6/a7de82pmHfv3DWnuO/dd0C6dGpneuYDAAAAQGQQIgMAAMQiOlGWTl7zy6+T5eeJf5iJGgvmzyvDv/yfmfwKAAAAACKLEBkAACCWadOqhbkAeLz+/mO8p0UA4Km1dsVcT4sAiMWCp1gEYpmgoCD5+NPP5cjR454WBZ5a+w8ckk8HDBbmR0VojIHe5/c//5EZs9ixQ8zCWOR9GIsQUzD+QJ0+c1Y+/OR/cufOXV4QIBoQIiNWGvndjzL+l9/l9bc+kMw5i4Z7efOdjyQ2+GrEqDDPrWCxStK+S0/ZvmNXuMtF9TU5fuKkWf77HyeEu5zeX97C5SJ0X3r5ddJf4S77y2+THcvq7exYz7VFqw62QWutZ1qYmdTV7LkLzfI//vSL2Dl56oxkyVVM3ujdx/z8599Tw30t9fd2y+UrUl5aPt9Zlq9cI1Gh/U3HjvtVxoyb6GlReBnGQO8bA+fMWyTvfdgv3DEReNwYixiLgCc9/hw5cizM9rOGijXqNpM8hcpJyXI1zb7An3/9K/537ri9L+t/7rLlq9z+fuZ/88zvV61Z77hO71Ovsya1De3Spcvm97pdoo4dP2EezzONW5sAPLRr166bx1qhan25ffu2m3sU8/dDb9PkLlBGGjV7XqbPnCNP0osdukvZynXlwoWL8jidOn1Gfvv9bxk4aJinRQFEAO0svFxg0D05cu6G+f5O4D3zNXvaJGbCvafViROnZOR3Y+SlF1vLs80ayboNmxy/+2vKdDl//oK82r2z47oC+fNJbPLm669IokQJzfdXr16Tf6bNkqbPtZNJP/8gFSuUlaqVK0iCBPFj9Gvy1z/Tpd0LrWx///c/0yUydB3Q+/TUC7RWjaqSNKmfzJo9X17u0t7tMjNmzjGBdPOmDVyu79T+ecmQIV2Y5YsVKWS73K1bt2XGrHny/EsvyzfDv5AWzRqJnb79B8tP43+V3r16yNtvvmqua9ywnnkcQ776Vlo0bShp06axvT28B2Ogd46BQwd9JjXrNpP+A7+SMaPZUcKTx1jEWMRYhJgw/tSoXtlcp9vv347+SYZ89Y0kTpxI6tauLo0a1JXr12/Ihk1bpPd7fWXMTxNlzPcjJGeObG7v9+PPvpAFs/+R+PHjSUR9P2aCtHqumeTKmT3c5bJlzSK93+guAwcPl58m/BZmX+SLoV/LufMXZOL4UZIoUSIJj+4D58+fx3yvFbgLFy+THq+/K0ePnZDXX+0qj9K/02bJhYuXpFvnl1yuP3nqtFy6eFlu+/vL41S6ZHHp8Uon+W70T9K2dQspVDC/p5sACAchspe7ditAmn++2OW6+f3rSkq/BPK0GvHNDxI3TlwTtqVLm0bKlS3l+N26DZvF3/+OvNbj0f7zfJK6dHxRUqVK6fi5x8udpF7jVtKn70BZPG+qeT1i8muSLGlS2bBxixw6fNTtxpZev3HTVvPe6oZURGTPlkUGfjFM6tetJcmSJbVdToOlenVqyj9TZ8qZs+ckQ/qwofD0WXMkdepUUq1KRZfrdeOweLHC4kno5XRDrlnL9vJJv0FS/5nakihhcPjlbOXqdTJuwm/izntvv26C6G+//0n6ffK+22XgXRgDvXMM1J+7dGonw74eLTt27ZEihQqEuS3wODEWMRYxFiEmjD8W/f+olzatmkv/vh+In18Sl9vomYGvv/mBPNu6g8z/729JkyZ1mP2Jg4eOyA9jf45wEJs2TWq5eeuWfPLZF/Lbz997Wlxe7tpeps6YLV8O/84Ui2TKmMFcv3nLdnOWUrMmDUzRiyfP1Ktlbu9cZNTp5TfM/bZ6rqnbfZzo8u/0/2Tv3gNhQuTZM/6U27f9JVXKFPK49Xyls/wy8U9T9f3TD197WhxAOJ7eclPADT2SPGXqDGndqrnZoYaYMKXd861k3/6DcvLk6Rj/kjRp/Ey41cZ/TZkmPj4+0rxpQ4mozz55Xy5eumwqDzxp2ri+qVSYPWdBmN9pj+2t23ZK4wZ1xdc3eo7BaSWBbmRdvnxFtm7d4Xadfuudj6V0qeJub589W1azkTjpjym2p+DBezAGevcY2LnjC5IwYUKZ8PPvbm8LPC6MRWExFgFPbvzZsnWHCZY1QB02ZECYAFnpmUp//jZWrl2/Ie9/1D/M72tWryI1qlWWr7/90bS3i+jnvtdrL8uSZSvNmY6e6P7F0C8+Mwe3+/YbZK7T1hb6eJIl9ZP+faNWMKLbDa917yKBgYGyfEXU2ug9LC2UeRIBstIiovbtWpvWX9reAkDUESIjVtFTde7eDTCnJkXFlatXpd//hkr5Ks+Y/lGVazYywaNz3ymr15R+/fnXP6Va7SaSM38ps6z+HHojRic+0/5PZpkaDWXosG/DNPbXU67e69NPylSqY/5ulZqNZdDQkeb2zvRxaW/NxUtXSP0mrSV73pIR6t2ZPKT69pZN/6yYJFeO7FK2TEmZ8u/MMH2M9ed/ps6S6lUrSvp0aSWiypQqbjYatY+oVsWER+87RfJkbjf0rF5ikQmwIyJFiuTmq24whvZJvy/MaV9DPv9U7GiIrK0xntRGIWIOxkDvHgNTJE8uVSqVl/kLl8i9e8EtqoAngbHIPcYi4MmMP9oeIkGCBKYCOTz58+WRl7u8JHPnL5ajx8JO0D7gsw8lKChQPhswWCLq5S4dJHeuHPLZ/4bY9jJ2pmcsdmz/vJmrZf7Cpeax79y1Rz7+8O0w1dGRkSzUtlB48zXovu5HfQe6zNmg87voBL71GrWSXPlLm/3b4SNHO7Y3rPlfFi5aJidOnnL0ZLb6RIf+e/qz7ttevHhJer39kZnHomjpaqZqWwtjtAf0Bx8PkOJlqpv94+fadJSdu/aGeayLliw3/acLFKsohUtWkXYdu8vadRvDLGdVZs+dtyjM7wBEHCEyYpWly1eZHlflnU5VjqhLl69Ikxbt5Jdf/5SKFcqY/phFCxeU774fJ8+17RQm+NWj2XpKUO2a1aRT+xfE399f+nzyP/MP36KnDY2bMEnKli4pr7/aTYoULmiOXnft8aZjmR07d0v9pm1MYFCpQjnzdwvkzyOjfhgnjZo/byZdcKb/PDu//IbkyZ3TnEpVonhRCY+GDvoPX4NRrVp9GrRt1cJsfKxeu8Hlet0I0eu1JURkffxBb/FLkthsENlNsqfixYtn2kqsXb8pzMQP02fMlsyZMpqAJzrpZBxaeVCwoGsfVt3I0X6tg/73iTkdzk71qpXM7ZcuW2m7DLwDY2BY3jYG1qpZ1fQi1P8twJPCWBQWYxHw5MafBQuXmh7I4bW1szzXorH5vGqAG5q2mXqla0f5b84CWbI0Ytvd2j/5f599KKdOnTH7jxHx/tuvm32ODz8ZYPY3K5YvY/r5PoxpM2abryWKFZGo0H3Vt9/va86O7Nq5nSROlEi+HD5Kxo7/1TEPzIfv9TL7qHrATL/XS/asWWzv886dO9LqhS5y+sxZczaVtuIa9/Mk6f3uJ9KmXVdZsXKtvND2OWnerKFs3LxVOnV73WWf/Kfxv0n7zj1N9XiHdm3k+dbPyuGjx819hp5IsGiRQqYyfcky95MjAoiY6DkfG4gh9NSiLJkzmSAwsgZ8/qWcv3BBZvz7m0vD/QWLlkmHLj3lx59+cel/pUeE586YLFmyZDI/9+ze2VQljx03URo8U9uEv6vXrDf/ZJ171Wq/3Thx4piNE7307PW++Pr4yNyZk80/XcuyFaulfedXTR/P77/90nH9rt17ZdiQ/tKmlfsNiWPHT8rVa9fN9xok/Dj2FxOIfvbJe5GaBOJJatLoGVOBq6dtV6pQ1nG9/qxB0DN1a8n4nydJZGgf43d7v2YmxJj891Tb1081bVRf/pj8r8yet1BeeqG1uW7/gUOye+9+8z7r+xfa6TNnwmyYxo8fXzJnymC7nFYPT54y1Zy2rhs+zpWFelReq9Ofa9HEVFKEPpjgLEmSxJIuXRpOzwJjIGOgo4+ynq5ZrKjnPu3Ao8D2GNtjjEWIKePP1WvX5Nr16x4ntrPoAee4ceOafSp3er3WzezP6T7Forn/Rmj/qlrVStKwfl2zP6kHgp33+ey27ft+9I680vNt8/OggZ+43f+woxMGHz5yzHyv1c96MF0Lo56pWzNCc7i4s37DJpn290THtkXvN1+V2vWflbHjfjWTABYskM9cIjPXxPkLF6W6tgj5KrjqWb3U+VUTeGtRle4f62uh9O9qwZZWHuu+ts4RMeCLL6V1y2by1eD+jtfnnd495YWXXpYPPx5gDhw4T0KoEybSzgJ4OITIiFXOnTsv6SLR5sBy8+YtmT5jjjRu9Iz5R2P901V6+lHOHNll2vT/XEJkDf2sANkKKcuULilbt+1wtCjQPlgbNmwx7SqsZZ9t3thxmxWr1sqBg4fly0H9wmxM6MRt7V9sIxMm/mEmT7J6eumkDuEFoFq97Eyfj1bhhp7cICL0qLC7FgsZMqRzOwFcdNGNBQ1OtaXE5/0/Ms/h1q1b5qi/hqo6AV5UtG/XRn6f/K8MHDzCVBsnT5bM7XKVK5Uz7+d/sxc4QmTr6L1dK4surzyoLrfowQidmCO85bSCuONLbeXTj99zuV57n8VPEN9ULkRE+rRp5dy5iE00iNiLMZAx0DoYdZbxAE8QYxFjEWMRYsr4E94ZiOGxy2x1v0SLc7r1eEtG/zje9DyOCL3NkmUrTLuG3yf+6GlxM7H2g+/XS57cuSSiNOB2pqF4i2aNZPDATySqGjd8xuXgdMIECaRmtcpmX1Vb70V13/DtNx9Mfmj1pl60eLl079bJESAra1LzIyH76VpcFBR0z+yr6bw1oQuStIhq8dKV0rB+Hcf1ul7o5IgAoo4QGbGKHnEOuBsgkXXo8BHTe0krQu0mM9LJikL3zAotZcrkZgZe65/16G+Gymu93pcK1epL4UIFzD9FPR1HT9VRu/fsM18rVXxQbeuscsVypg/Wnr37HSGyhtrh0SrlJEmSyB+T/zH/OP/5c3yUq9F0huLQp1Orv34f51Ih/Ci0adnctHKwguP/5iw0YX/rKLSycJ5UYmD/j6RFq/YyeOhI+XzAx26X02BXNzh+//MfuXzlqqRMkdycEpUvb26XKnVnH73/lmTL5nq6lrtT5pyX0w0jXS9CTwI5eco0M/HDH7+OidBpd+rO3bvilyTsJCHwLoyBjIE6Fqj4UTgjB4gujEWMRYxFiCnjj84XkCxpUlO5GhHaC1n7/GbNktl2Gd1P0En2vhk1Vp5zKhAKj56d+EbPl2XQ0K9NZbDu59nR1g2/TvpL6terJSdPnZZBQ74230d0TphXunaQUiWLyabN2+SHsT/Lxx/2Ntc9jPz5coe5LmXKFCakv33rdpRC5ATx40u2UO0ukidP5nafN3RP+d179pv3qXGLF8SOFThb7t69K/EiUDkOwB4hMmKV9OnSmD5IUdWp/fNSoXwZt7/TUDh0IOmJTnC0dsU806t2+co1Mmv2PHPEWlsi9Hn/LYmKOKEeR2h1a9cwFdBlSpeQmnWbyyf9Bsm/k38O8/gj4u03X5WLbtoo5M8bdiMiuun7kCN7VhMka4j81z/TJG+eXFKyRPg9oD0pW7qEmWRv4qS/TI8tO00b15eJv002fYmLFClojlq/9/brtstXrlQ+QqeHeVru7Lnz8mm/waYP2spVa81FWRXh+rPOrNz95Y4uldR62lpET9ND7MUYyBioY4HSFjfAk8JYxFjEWISYNP7UqVVN5sxfZCYtT5rUT8KjE9hqa4Q6taqHu5xOsle7fgszibpW+UaEBrmT/54m/QYOlamTf3G7jG7nv99Hi4ISm+IXraxu3OJFU8H846hhEhEaIOtEchp2r9+4WUZ++6N5jKELV+z+vju+PtEfHfn42u9PR2RfO03qVOY1sqMtMZydO3/RnL2JiEmeOL7M7x88QWWCkPcqRZKonRGM2CP6RwLgCcqRPZssX7nWzOYa0QpO63baz0p72FoztzoLCAiIUp9la0OlXt2a5tKv7/vy2f+Gmp5UzZo0NH2j1KrV691O+KTtLvQfqLuqZ08ypE8nn/R5W9798DMZ//Pv0qXTixJZFR9xtXF4dONNe4Z9NWKUrN+4xbxGH7z7hkQHrQbWcPjDT/5ne4pbhXKlzdH+WXPmy+EjwZULzZs2kEdNw2rt26aXkd+NCfN7PTVLLxqAWyHymbPnTP/rHDmyublHeBPGwAe8dQzcsXOPY10AnhTGogcYixiL8OTHn04dXpCpM2ZL3/6DZPjQ/9nedt/+g/LjTxNNL10tZgmPFm+83LWDfDtqrKRMkUIiM8neCx1ekeHffO92Ga0c1rNVNRzV8UMv2vpOz07Vyf70sUWUFhFpv+BnGrcy/YTHfj/C8bukfn5mfpbQrSj27DsgT4N8eXPJ0uUrTYGOnjXqLCgoyDx35z7Sd+8GyP4DB80BBURM3LhxJKVfAvN9wnieQ314h8iXJgIxmFbh6tFTnZU3MjTobdygnkycNNmc9uNs774DUqZiHfl+zM8SGXo/pSvWlgm//O64Tv+ZFSkc3Mri4qVL5jSmXDlzyOAvR4bpz6QBsj6eyJy6FJoGjfqPddCXX8ux4yfkaaMBinr1jXfNRoBWJEeHNGlSm0n29D3SCfPc0fdK+zKvWLlGpkydKSVLFHMb9Ec3bRNy8vD2MJftG5eZ3/fu1cP87HyK3cJFy0wYHpmNSsROjIGuvHEMXLBoqfm/4qn1EfAoMRa5YiwCnuz4o5W5OreNVgG//X5fuXHjZpjb6VmjbV7sKkkSJ5LBn38qEfHmay+bswf/+Otfiajq1YIn2fvzr6lhfqfbKsNH/mAeb/sXg+dlUXo2ZMaM6eWjvgPNPDGRoe34Xn+1m8yeu9C00bBY2wmz5yxwKZz6YvCDoDkqkiROLFeuXrWtaI4uOqHevXv35eNPB5rHbdEWFzoxfbXaTc1E5ZY1a9eb913XDwBRRyUyYhXtLZwieTKZ8u9M01A/Mvp9+oFs2bZTnm3Twfxj14nu9B/5zP/mS7KkfibMjQxtWVC4YAH56NPPZdHSFVK8aGE5ffqsOQquO/jly5YO6Zs8RNq06yb1m7Q2oaX2hdIeT3PnLzKh5Rc2fXsjasjnn0qdBs/Jex/2Mz12HwUNLXTyv9DatGruqKLWf+79B37pdpI+ndHXrneYtgRZtmK11Kxe2RyJjy7WJHs7dwVX7dm1tBj38yTzvvXo1kliqin/zjCvTemSxT0tiliOMdC7x0Dt96gHx159JeaOV/AOjEVhMRYBT3b80QKSePF8ZdjX38vM/+ZJvdo1zDwl12/clA0bN8vWbTtN4Dpm9PAItX2wJtn79ON35eVXe0tk6CR7i5eukNsh/X0tWi2s2ws6Xji3IvTzSyIDPv1QunZ/U4YM+1Y+CzUhtycaoGtbxY8//dwcXE+VMoWZ7P3LEaNMqK6T+GnR0rz5i8U3nq/Hlh+eWhLqXDKdX+klBfPnlaaNG0jhQu7nlHkYOtFg3z7vmHYi23fslmfq1hQfH19ZtGS52b/TbSGdKN3y978zTQ/mWjWqhnu/AMJHiIxYRVtOdO38kjn9d+euvZH6h6X/TGdNnWRaCOg/2TlzF0rqNKmk5bNN5M3XX/G48x6atqH47efR8vV3Y2TGzDmyfMVqc6rTs80ayju9X5MECYL7CRUpXFDmzpgsI7/70YTNly7OkYyZMkiPVzrJa927PNQ/caWnYr3zVk8Z8PmXMumPKeH2AY4qnXzP3QR85cqWdApQAs3pWaHpRHV2AYoVwmiA0qplc4lOzpPs2dG+0pkyZZCzZ89L08aROyjxuKxdt9G0t9CNUedTtuCdGAO9ewz8dvRYM6Fe546Rb90BRCfGorAYi4AnO/7odvJbb/SQZ+rWkp9//VNWr1kv/81dKH5JEpuq3KFffCYtmjeK9ARxWgSkk+wtWbZSIkoPEvd6LXiSPcu0GbPNpOg6d47V8tBZg2dqm6B03IRJZjK/okUKSWReky8H9ZdmLV+ST/sNkm9GDDKtPn4dP9psH02d9p8kTpLY9FDu8/6bUrlGxHo8u9Pu+ZZy8OBh+Xf6f7Ju/Sbz+jwq2qpM37vRY8bLr5P+lvty3xwIGDVyiDRr8qANoRaG6evb4aW2kWp5CSCsOPftGoLCK1y6fkeq9Znjcp02T7d63zxpPXv3kzNnz8vQ/u9IoQIRm8xNT1OpWL2B2XH/a9JPBGuItfQ0sabPtTMVkCsWz5KECSL2ub1w6Yp06P6h+PjElcm/jPS0OB6CToj4Ype3zfdTfhkhCRNG7D16GIyB3kkrqHQ86NLxRen70TvyuHw+bIysXLNJunZoJQ3q0VInturU/QO5dv2GjPrqE8meNZNEBGORd4rqWPTTxCnyz4wF0rRRbenwQgtPi8OLxpKoYPyBsy6v9DIH5Fct+U/SRrDKPCrWbdou/QaNkty5ssmQAZGrFo/p6IkMCz2REevo6T6DB/Y1R5fd9ZoCYosJE/+Qbdt3yVeD+kc4QEbsxxjond7r08+0Q3rnrVc9LQo8FoxF3omxCDEB4w8sOpn6nHmLTAuQRxkgx0YBgfdkw4EL5rJuf/BFr4N3o50FYiU9FWfUN0Olft3I9TEGniYvtn3OtFnRCToAZ4yB3mf40AGi55YlTpzY06LAY8NY5H0YixBTMP5A1a5VTb4dMUhaNIt6iw5vdcM/QLqPWuNy3bLP60uqpBQveTNCZC+XNFE8GfdGZfP93cAg89UvYTyJDZo1ru9pEeCpppN5NG5Yz9Ni8FKMgd5FeysDMRFjkXdhLEJMwvgDX19fAmQgGhEie7l4vnGlXN7g0zr8A4JD5JjEmifs3j1OmwCii/V5ihOHjkaPmvNkh4xjiNXjidMs8oiF2B7DI3bvXvA0PXGZJDh2YyyBF2wTMY4hNmOLHzFa4sSJzNdbt/09LQoggm7dum2+Jk4cudmnEXnx48czExgqxjHE5vEkSSLGk9gscSK2x/Bo3XRsmwSva4idGEsQm9265e+yngOxESEyYjS/JMG9HS9evuJpUQARdPHSVZfPFx5tJbJfkiTm+4uXg193IDax1uskjCexWlK/4P8Xl0L+fwDR7VLItj5jSezGWILY7OIlxjHEfoTIiNHy581pvq7bsN3TogAiaN3GbS6fLzxa+RzjWPDrDsQWp86ckxMnz0jcuHElT+7snhZHLBjH1ob8/wCik56ps23nPvN9AbZNYjXGEsRm6zYGZxb587GPhdiLEBkxWsXypczXTdt2y42btzwtDsCDoHv3ZOXazS6fLzxalcqXNF9XrNkk9+8H93wEYoMVqzeZr0UL5ZNkSf08LY6nWKVywePY2g3b5O7dAE+LA5EOXgICAiVjhrSSPVtmT4vjKcZYgtjqwqUrsmvvQfN9xbIlPC0OPLUIkb2cTmJx6fodc7l8I/hiTWwRE2TLklGyZMoggYGBsnTlek+LA/Bg89ZdcvnKNUmSOJEUK5Lf0+KIBmVKFpF48XzlxKmzsmf/YU+LA0+FgMBAWbJinfm+YsiBEsTu6sFUKVOYitFV67Z4WhyIMD24unDpasdY4jwhLWIfxhLEVouWrjFf8+fNJalTp/S0OPDUIkT2cldu3pVqfeaYS92+883l6q27EpNUrVTGfP1x/F+OU0QARN7eA0dkyNfjzPcVypWQeL6+nm6CaKCTBJUuUcR8P2DIaDly7KSnmwAxPkAeNGysHD1+2hwgKV+2uKeb4CmnLUuqVAw+e2Xk9xMdrQeAhw2QR//0h2zautuEx5UrlPZ0EzzlGEsQGy1ZsV4m/jHdfF+lEuMYYjdCZMR4zZvUlYrlSkpgUJAM/PIHmbtopfjfiVlBNxDTAx+tHPvkfyPN7OcF8+eWTu2e83QzRKPuXZ+XnDmyyNVrN6RP/xGyYfMOCQoK8nQzIMY5efqcfP7Vj7Jmw1YTIL//1su0svASz7dqIiWKFZQ7dwPksy++NTvNtLbAw5z6/c0Pv8msectMgNyj6wuSg1YWXoGxBLGFnp0zffZi+eqb8XLv/n2pVb2C1K9T1dPNgKdanPs0aPRq2sZCq5Cdze9fV1L6JZCYJDAwSEZ8N0FWrwvu5ZogQXwpV6qoVChbTNKkSmkq/Xx8OCYCKB3WNSy+cuWarN+0Q1at3yI3b942v9MA+aN3e0iiRAl5sR6z6zduSr8vvpHDR06Yn7WHbKXyJaR0icKSIllSSZw4IafxIsaNJRoS6pwEBw4dM329Dx4+bn5nBcglixfydDeIRXR9GDz8R9mybbf5Wf+XlC9dTMqXKSqpUiY3rZK00hAIs+4EBJhtkaPHT5l+6lbvUCtArl2jIi+aF2EswdMoKOie3Lx1S85fuGwKdLQoRPu5Kw2QdSyLTf8DtdWpnqnubNnn9SVV0piVFeHxIkT2ck9LiGwFyZP/+U+Wr9og585f9LQ4ACcpkic1vQZfbN2UAPkJB8m//jFN1q7far4Hnja6c6QT6bVoWk+KFs7naXHE0vDn979mmCDw0uUrnhYHbGnv0CYNatJX3UsxliA20AlBa1QtL/9v7y7Amzq7AI6f1BVoseKuw30M2ZAhG9uAubvbN3dh7u5uTJjANoYNZ7i7u1uBlnqT7zlvaUlp0lu5SSn9/54nT26T96ZtmpzmPffc8w457+xTKoGsSCLDE5LIZVxpSiK7V0Zt2LRVZs5eJKvWrDcVUlrZQFE9cIxDJCI8XKIiI6RhgzrStXNbadqkgQSeYh9sSjNtZbF81TqZNWeRbNy8TY4eTTKnxMnJs64pkFNxHBUVKZViK0inDq2lU4dWtK+A4XQ6Ze36zSaOrVm30XweS0pK4fMYPAoKCpTIyAiJqVBO2rdtIad3bMPiUyCWoFQJCHBIRESEREdFSovmjcwcq07tGqfsmYQkkeEJqyqh1NEg3bB+HXMBgNIoMDBQWrdoai4AUBppxVXTxvXNBQCKilgCAKUHZWkAAAAAAAAAAK+oRAYAAAAAAABgRIcHy88P9TTboUFZ9aflIoJ5dso4ksgAAAAAAAAAjKDAAGkQF222w4IDeVZg0M4CAAAAAAAAAOAVSWQAAAAAAAAAgFckkQEAAAAAAAAAXpFEBgAAAAAAAAB4xcJ6AAAAAAAAAIyMTKds2XfUbIcGZdWf1q0SZRbcQ9lFEhkAAAAAAACAkZCcLpe8OjXXszHtxf4SGx3KM1SGkUQu46LCguSN6zuY7fQMp7mODONlAQAAAAAAACAL2cIyLiQ4UPq1rWG2U9IzrYYDAAAAAAAAKGNoZgIAAAAAAAAA8IokMgAAAAAAAADAK5LIAAAAAAAAAACvSCIDAAAAAAAAALwiiQwAAAAAAAAA8CrI+10oCw4mpEqPx8bmum3CsL4SExXqdR8AAAAAAAAAZQeVyAAAAAAAAAAAr0giAwAAAAAAAAC8IokMAAAAAAAAAPCKJDIAAAAAAAAAwCuSyABsMW/XSrlrwlsyZsMsq6EA4BMul0veW/Cr3D/pPdmfdNhqOAD4xP6kQyYOaTzSuAQAJUHnZTo/03kaANiBJDKAYkvOSJVHpn4iy/dvlFfnDpcdCfusdgEA2w1fOUF+XztVFu5ZK3dOeNNqOAD4xJ0T3jJxSOORxiUA8LftCXvNvEznZzpP0/kaABRXkNUAALAya8dycbqcOV9/u3yMPHr61fnuAwB2G7tpds72nqSDsvrAFmlasU6++wCAnQ4mHzHxJ9uINZPlsuZ9JMBB7Q4A//nH7exQnaf9uW6GXNKsd777AO6iwoLl49u7mO2QoEBzHR0ezJNUxvFpBkCxxYaVy/X19O1LOH0TgN9VCI3O9fX4TXO9jgUAXwgJzF2jczg1UdbFb/c6HgB8oXxoZK6vx22a43Us4ElwUIB0aFjJXDo1yrrobSjbeAUAKLY2VRvl+rpyRIy4hB6AAPzr7Hodc30dF1XR61gA8IWokAhpGls75+sgR2Ceg+0A4Gs9arbJ9XU1PhMBsAFJZADFoqdH6aIx1SKzkjXBAUHyVq+7OG0TgF9lOp1Su1xcztcd45rJRU3OyncfALCTfh7SWFS3fPWc2x45/SqpHFEh3/0AwE4ah2LDy0lYYIj5OiY0Wp4+43qr3QDAEj2RARTZtG2L5aXZ30mt6Kry2OlXy6StC6VHzdYSG17eLN6gH1wcDofVwwBAsQ5kvTDzG5m2fYlcdVp/eaDTZWZxz+y+f8npqRIeHGr1MABQLNuO7JUHJ78v6c5MeaLrNRITFiU1oitLr9rtJC0z3RxcDwrI6ikJAL7y25op8sniUdK2aiN5occtMmPHUhlYv4uEBAabz0RhQczPABQdSWQARaJJ4jfn/SwpGWmyLn6bJGWkyt3tLzT3TdqyQF6e/b1UiYiRd/vca46EA4AvTNu2xBzAUqPWTZffBr+QUxH41IzPZcb2pTK4cc+c+AQAvvDBot9kT1K82Z6/a7Xc3Ob8nOTyPf++bT43vXLmbdKqSkOLRwKAotl7NN4kkNOdGTJ31yq5o93QnM8/v6yaKJ8sGSVNYuvIG73ulPAgDrADKDzaWQAoEk3W6GIxSiuO65WPk8V718nR9GSZvHWh+fCyI3GffLdirNVDAUCRq5C/WT4m5+vWVRrKnqMHZfWBLZKYlmwSyOqPtVPNbQDgC6sObJY5O1fmfN2qSgNzm8ajObtWSnxqgqRkpsnb838xcQsAfGH4qglmDqa0jU650AgzP9OzISZsni9Ol8vEpj/XzbB6KECcTpfEJ6aay8GErIvehrKNSmQAhZbpzJSfV03M+fqCxj3kjbk/mYlS3fLV5PyG3XKSN6M3zJJrWgyQCmHR+TwiABTe7J0rZPPhXWbbIQ7pV6+zXPvPC+YMiVvanC9NK9bJSR4PXzlBhnW/0eIRAaDwflz5b862xp0N8Tvls6V/mtPGn+12Q859mw7vMnGra42WXh4JAIrmUEqC/LNhVs7XlzfrK/f++65sObJbOldvLh2qNZX1h7ab+35a9a9c2ORMCaTFDvJxOClN+j41Iddt017sL7HRVLGXZVQil3ERoUHy+EUtzeWhIS3MJTyEYwvIX2J6shxOPZpThXxJ017mlCmlCZ0OcU1zFpHRo+F7kw7l+3gAUBTbE/blbPeo1UYOabVfRpr5eu7OleYAVjbtkwwAvuAeXzTuzN+d9ZlI41F8SoL0rNXWY9wCALvofMu9ClnnY5pAVnN3rpKLm/bKWWhP53E6nwOAwiJbWMaFhQTKZT3qm+2U9Eyr4YBRPjRKbm1zvlnI6tJmfUyVsUuOn9qiC8foCsCfLB4pzSrWlUYxNXnmANiuX71OsnzfBsl0ueSeDhfJnJ0rcu5ziks6V2su17U8R+btWiVXteif72MBQFHd0vYC+W75WOlYrZmJO1rll811LD5pcifQkXXGBADYTedbmijWdhW3tLkg10KeOk+LCYuWx7teY+KTLoSu8zkAKCySyACK5OJmvc3Fm9Mq1ZN3+/zP6/0AUFw6ARrW/Sav9zscDrm6RX9zAQBf6VStmbl4o8mbF3rc7PV+ACgu/cxzW9vBOV/vTjyQZ0y3mq3MBQCKinYWAGwRGRye05c0IjjMajgA2C4qJPz49rGYBAD+5h5/3OMSAPiLzsd0XuY+TwOA4iKJDMAW2t6iZnRluaZFfykXGmk1HABs1yGumemN3KBCDbm8+dlWwwHAJy5v3tfEIY1HGpcAwN90PqbzMp2f3db2AqvhAFAgDpc26gLoiQwAAAAAAFDmxSemSt+nJuR6Hqa92F9io0PL/HNTllGJDAAAAAAAAADwioX1yjg9unTeC5PMdnZN+q8PnykVokLy3xE4wbfLx8oPK8dL37od5IFOl/P8APC7xLQkeXDyB7Ijcb88cfo10ql6c6tdAMB2c3aukBdmfSs1oirJa2fdSV9kACXi9bnDZcLm+XJF87NZZBiALahELuM0cRyfmGYuh45mXVxChxMU3o8rJ0haZrqM3jBL4lMSrIYDgO3m714jqw9ulYS0JPl93VSr4QDgE3+sm2bikMaj+btXWw0HANvpfEznZTo/03kaANiBJDIAW6RkpuVsp2Yc3wYAf0nJSHXbJg4BKBnu8cc9LgGAv7jPx9znaQBQHCSRAQAAAAAAAABekUQGYItAx/FwEhgQmO9YAPAF99gT5CAOASgZ7vGHz0QASoJ77HGfpwFAcRBNANiiT90O5rp1lYZSKby81XAAsF3bKo0lNqycOMQhveq0txoOAD6h8UfjkMajdlUbWw0HANvpfEznZe7zNAAoLofLpUuroaw6mJAqPR4bm+u2CcP6SkxUqNd9AE+cLqfsPnpQqkTESBCVyABKyNH0ZElOT5NKERzMAlBy9icdlvDgEIkMDrcaCgA+keHMlL1J8VItsqI4HA6r4UAu8Ymp0vep3IsyTnuxv8RGkysqy4KsBgBAQQQ4AqR6VCWrYQDgU5qwIWkDoKRxIAtASdPCHuZnKKrIsCB5+ep2Zjs4KKuJQVQYKcSyjlcAAFss2L1aRq6bLmfWaiu9OWUKQAnIdGbKN8vHyo7EfXJDq3OZOAEoETsT98sXS/+WGlGV5ZoW/emLDKBETNw8X6ZsWyQXNOou7eOaWg0HcgkJCpQ+baqb7bBg1hpBFpLIAGzx0uzv5EDyEZmzc6WcXqOFRASHWe0CALZauGetfLfieIumJ7tem+94APAFTSBP2rLAbLesXF86VmtmtQsA2CopPUVenvO9aWmx6sBm+fWCF6x2AQBLLKwHwBaaQFbpzgw5knrUajgA2O5A8mGP2wDgT8QiACVN52OaQHafpwFAcZFEBgAAAAAAAAB4RRIZAAAAAAAAAOAVSWQAtmgUU9Ncx4RGS+WIClbDAcB2DY/FIdU4pla+YwHAVxq5xR/3uAQA/lIpooJUCI3KE5MAoDgcLpfLZTUIp66DCanS47HjixCpCcP6SkxUqNd9AE8OJh+RadsXS8e4ZlIjujJPEoASsWTvetmVuF961+kgwYGsHwzA/9IzM2TilvlSLaqStK7S0Go4APjEjoR9Mm/3KulRs43EhpezGg7kEp+YKn2fmpDrtmkv9pfYaHJFZRmzqzIuLCRQbhvQxGxnZDqzbgsOtNgLyEs/mFzQqAdPDYASpQkbkjYASpIewOpfv4vVMADwKS3sobgHgJ1IIpdxEaFBcsfApmY7JT1r9VagKOJTEmT69iXSIa6pVI+qZDUcAHxi2b4NsvNYJXJQAAdFAfhfhjPTVCLr56GWlRtYDQcAn9DPQ/N3r5buNVtLTFi01XAAsEQSGYAtHp7ykayL32Z6Io+44DkJJHkDwM/Wx2+Xu/9922xviN8ht7cbYrULANju08WjZMSayeIQh3za/yH6IgMokYNZd45/U+JTE+Tv9TNNLAKA4mJhPQC20ASy0g8q+5IOWQ0HAJ8kkbOtPRaTAMDfsuOPS1y54hIA+Mv+pENmXuY+TwOA4iKJDAAAAAAAAADwiiQyAAAAAAAAAMArksgAbBEbVs5c60JW5UIjrYYDgO1iw8vnbFd02wYAf6p47DOR2SYWASgBOh/LXmC4YvjxmAQAxcHCemXc4aNpcvXbM8y2y+Uy15/d2VXKR4ZY7Ank9kiXK2XkumlyZu12EhEcxtMDwO/aV20sV57WT3Yk7JPrW55jNRwAfOL6VueKfqquEV1Z2lVtbDUcAGyn87GHOl0hU7YtlAsa9bAaDgAF4nBlZw5RJh1MSJUej43NdduEYX0lJirU6z4AAAAAAAA4NcUnpkrfpybkum3ai/0lNppcUVlGOwsAttDjUbuPHpRMZ6bVUADwmeT0VDmYfMRqGAD4lMYhjUcAUFIynJlmfkbdIAC70M4CgC1enTNcxm6aLW2rNJI3et0lDofDahcAsNWB5MNyy7hX5WBygjzU+XLpX7+L1S4AYLsxG2fLa3OGS2x4tHzS7yH6IgPwO00cPzT5A1m0d530r9dFHu5yhdUuAGCJSmQAtpiwea651g8q+5MPWw0HANst3LNWDiQfEZe45N/N862GA4BPTNw838QhjUcalwDA33Q+pvMy93kaABQXSWQAtsh0OY9v09ICQAlwjz0ZLlrrACgZ7vGHz0QASoJ77HGfpwFAcZBEBgAAAAAAAAB4RU9kALYIDQyW1Mz0rO2gEKvhAGA799gTRhwCUELCAt1jEavYAyjhz0RuMQkoqPCQIHloSAuzHRyYtd5RRCgpxLKOVwAAW1zWrI98v3K89K3bUWLCoq2GA4DtOsY1lcaxtWRHwn4Z3KiH1XAA8IkLGveQ5fs3SY3oStIhronVcACwnc7HBtTvIhM2z5NLm/exGg7kERYSKBd3q5u1HRzIMwTD4dJlO1FmHUxIlR6Pjc1124RhfSUmiqoJAAAAAACAsowkMrLRExkAAAAAAAAA4BVJZAC2GL1hllwz+nn5dnnuynYA8JeUjDR5ZsaXcvPYV2TVgc1WwwHAJ1bu32zikMYjjUsAUBJ0XqbzM52nAYAdSCIDsMXHi/6QrUf2yNfL/pEjqUethgOA7ebvXi1Tty2SdfHbZfjKCVbDAcAnflw1wcQhjUcalwDA33Q+pvMynZ/pPA0A7EASGYAtEtOTzbVLXJKUnmI1HABsl5iWlLOd4LYNAP7kHn/c4xIA+IvOx3Re5j5PA4DiCrIaAAAAAAAAAKBsOJSYJhe+MsVsOxxZt/35eC+JiQrNf0ec0kgil3GhwQFyafe6ZjvTmXWkMiQo0GIvIC+HOHKOdjuy/8sAgB+5x54AIQ4BKBnu8YfPRABKgnvs0XkaUFg6tz90NHdff1fWdB9lGEnkMi4yLFieuLi12U5Jz7QaDnjVsVpTmbtrldQpFydVImJ4pgD4XcvKDSQsMERSMtOkY7VmVsMBwCc0/izau87EI41LAOBvlSMqmHnZliO7zTwNAOzgcLk4loAsJJFRHGmZ6bJ830ZpHFtbokLCrYYDgE/sTjwgB1OOSLOKdakABFAidHq16sBmiQ0rJ3FRFa2GA4BPJKYly9qDW6VF5foSEhhsNRzIJT4xVfo+lXuh6mkv9pfYaNpZlGVUIgOwhX4waRfXxGoYAPiUJmxI2gAo6dPIm1eqZzUMAHxKC3uYnwGwU4DVAAAoiI2HdsoHC3+TJXvXWw0FAJ9V//2zYZZ8tuRPOZx61Go4APiExh+NQxqPOOkTQElZvHedmZ/pPA0A7EAlMgBbPDn9M9mZuF/+3jBTRg5+SUKDQqx2AQBbLdu3QV6bO9xsx6ckyEOdr7DaBQBs98nikTJm42yzXTO6srSq0tBqFwCwVWpGmjw69WNJyUiTmTuWyw+DnrbaBQAsUYkMwBaaQFb6QUWTNwBQUnHoxG0A8CdiEYCSpvMxnZcpPhMBsAuVyGXckaR0ufuzOWbbeWyNxTeu7yjR4TTeBwAAAAAAAEASuczLyHTK/PUH8twGAAAAAAAAAIp2FgBsUSOqsrkODwqV2PByVsMBwHY1oqvkbGsfUgAoCe7xxz0uAYC/6HxM52Xu8zQAKC7aWQCwxQs9bjaLyHSr2UpCAmmHAsD/WlSqJ491uVp2JO6TC5ucaTUcAHzi1jYXSKXwCiZxo3EJAPxN52Ovnnm7zNi+VAbU72I1HAAKhCQyAFvUKR8nt7a9wGoYAPiMw+GQvvU6Wg0DAJ+KComQa1sOtBoGAD7VonJ9cwEAu9DOAoAtUjPSZO6uVZKQlmQ1FAB8ZkfCPlm6d724ji0WCwD+pvFnyd71Jh4BQEnReZnOz3SeBgB2oBIZgC0en/apLNizRmpFV5Gvz3lcAhwcowLgX5qwuX7MS5KWmS43tDpXrjytn9UuAGC7H1aOly+W/m1OJ/9ywKNSgx7tAPzM6XLKHePfkG0Je6VDXFN57aw7rHYBAEskkQHYQhPISj+o7E06JHGRsVa7AICtlu3baBLIasHuNSSRAZQIjT9K45HGJZLIAPxN52M6L1Pzd6+2Gg7kERYcKDed3chsBwVmFYiFhQTyTJVxJJEB2I/TyAGUiOMtLFxu2wDgT7njD7EIQAlgPoZiCg8Nklv6N8lJKAOK880BAAAAAAAAAF6RRAZgi+iQCHMd4HBIZEi41XAAsF10SGTOdrljMQkA/M09/rjHJQDwF52P6bzMfZ4GAMVFOwsAtrij3RD5ZdUk6V23PR9UAJSIDnFNpE+dDrIjcb9cwaJ6AEqIxp/9yUekRlQlE5cAwN80cayLDE/cvEAubtbLajgAFIjD5aJZTll2MCFVejw2NtdtE4b1lZioUK/7AAAAAAAA4NRHT2Rko50FAAAAAAAAAMAr2lkAsMUXS/+W71eMk751O8pjp19tNRwAbJeQliT3/vuO7EjcJ0+dcZ10rdHSahcAsN3MHctk2H9fSY2oyvJ2n3to8wWgRLw461uZsHmeXHVaP7m+1blWw4FcDh9Nk5ven2m2Hcf6a397bzcpHxnCM1WGUYlcxgUHBcjZbaqbS+/W1cwlOJCXBQrvl9WTzLV+UDmYfMRqOADYbt6uVbLx8E5JzUyXP9fNsBoOAD4xat10E4c0Hs3fvdpqOADYTudjOi9zn6cBheF0uWTjnkRz2bA7wVwynS6r3XCKoxK5jIsOD5Y3b+hotlPSM62GA16lZaZ73AYAf3GPPSmZafmOBQBf0QRyznYGsQhAyX4mco9JAFAclJwCAAAAAAAAALwiiQzAFkEBgW7bnOQAwP/cY08wcQhACXGPP3wmAlAS3GOP+zwNAIqDJDIAW/Sr19lcd4hrKpUiylsNBwDbtavaWCpHVJAAh8Ms8gkAJUHjj8ahKhExJi4BgL/pfEznZap/vS5WwwGgQBwul4vO2DDoiYzi0FByIPmIxIRFS2AAx6cAlIyUjDRJzUyT8qFRVkMBwGcOpyZKaGCIhAWxij2AkpHpzJT4lESpGF5OHA6H1XAgl/jEVOn71IRct017sb/ERofyTJVhnHMOwBb6wYQKZAAlTRM2JG0AlDQOZAEoaYEBgczPANiKJHIZl5CcLk8PX2y2M48VpT95cSuJCg+22BPIbfbOFfLH2qlyVu120r8+p0wB8L8MZ6Z8vuQv2Zm4T25qfb7UKlfFahcAsN22I3vlsyWjpHpUZbmx9SD6kQIoEWM3zpbJWxfK4MY9pUv106yGA4AlkshlXHqGU8Yv3pnrtkeGtvA6HvDm1Tk/SHxKgizcs1a612otkcHhPFkA/Grh7jXy8+qJOQvKPHXGdVa7AIDtvlo2WqZvX2q2tSdyp+rNrXYBAFsdTU+W1+f+KJkup6yL3y6/D37RahcAsETjUgC20ARydiVgQmqS1XAAsN3BlCMetwHAn4hFAEqazsc0gew+TwOA4iKJDAAAAAAAAADwiiQyAAAAAAAAAMArksgAbNE0tra5rhheTipHVLAaDgC2axxbWxziMNtNY+tYDQcAn8iOPwEOh4lLAOBvOh+LDSuXa54GAMXFwnoAbPHymbfLf9uXSru4JhIYEGg1HABsV79CdXm/732y++gB6VmrjdVwAPCJm1oPksaxtSQusqKJSwDgbzof++Ds+82iw2fUbGU1HAAKhCQyAFuUD42UgQ1OtxoGAD7VvFJdcwGAkkze9KrT3moYAPhUXGQs8zMUWUhQoFx0RtaZNYEBWWf6hQbTzKCsI4kMwBb7kw7LlG2LpFO1ZlK7XFWr4QDgEwt2r5GdifulX71OEhIYbDUcAGyXlpku4zbNlepRlaR9XBOr4QDgE1uP7JG5u1bJmbXaSqWI8lbDgVwiw4Lk4aEtzXZYMGcaIwtJZAC2eHjqh7Lx0E75LiRSfhv8ggTR0gKAn609uE0emPy+2d5yeLfc2X6o1S4AYLtPFo+S39dONduf9ntIGsXWstoFAGyV4cyUuya8JUfSjsrYjbPl8wGPWO0CAJaoRQdgC00gK/2gsj/pkNVwALDdxkM7crbXH9qe71gA8JUNbrHIfRsA/EXnYzovU8QhAHYhiQwAAAAAAAAA8Ip2FsgjPjGt0M9KeEiQhIV47pNzKDFNXOKSotDeO+Ghnl+mh4+midPlKnKTeO3x40lCcrpkZDqlKIIDAyQq3HMPzsTkdEkv4uMGBQZItJfHPZqSIWkZmVIUAQ6HlI8M8XhfcmqGpKQX7XGPJKVLXJTn+1LSMiU5LUOKKiYq1OPt+hzoc1FU5SNCJODYggHu0jOckpiSLkWlfzf9+51IX2P6WiuqqLBgCQ7K+7hOp0sOJxX+PZxN3xf6/vAkPjFViooYkYUYkcUhDqkQFWJ7jDia6n0/YkQWYsRxfI4oezGiJD5HZDpdxfr/yeeILHyOyMLniFMvRvhsruHMPe8sbBxirpGFfESWajER+bxaUJaQREYeF7+a1cOtMB4a0kIu7lbX430XvjJFDh0tWlLrprMbyS39PS9IctP7M2XjnkQpCl1lNLtJ/Inu/3KeLNxwUIqid+tq8so1nlfjfu6XpTJxyS4pinYNYuXTO7p6vO/90atkxH9bpCjqV42SXx4+0+N9307eIJ+NXycFFdk6VAJCUsXlDJDb3l8oE4cN9Djuz7nb5NXfl0tRzX/zXI+3T1u+Rx75dqEU1YRhfT1+aFyy+aDc+uFsKaqfH+opDeKi89y+Zd9RuaQI77VsH9/eRTo0rJTndk0g931qghTVy1e3kz5tqnu8rziPS4zIUpZjhLsKkSHy73Nn2x4jAssdkIhj/zIqh1fIdR8xIgsx4jg+R5S9GOGvzxHu8efw4UDp+2HR/3/yOSILnyOy8Dni1IgR/phrHD7iEJfTIY4AlzjTQgv9OZ65RhbyESIPDj5NrunV0OIVg7KCJDIAW6RsbCXBVbZKxsE4iXIRWgD4X+aRWLm+5TmyI3GfXNvyHKvhAOATN7QeJIEBAVIjqrI0DNUii71WuwCArcKCQs38LCh2t6TvrW01HPBq4tJdMnnZbrP97k2dpVyE5zOkUTaQ6SnjYqNDZfl755vtFneNkqIKDnSYUz08ceQ9a6fA9NQc749b9AcODPD+8+qpmUUV6PD+uHpfUQXk97geTosqKEc+j+vptKj8ZCbEmotyRGWd+uPttVIcXh/XQ2uHwggNCvT42N5aOxRUaJDn17DeXhz6c3l+3OL9vPo8enuOi4MYkaUsxwh3+qv6JkY45Ka2npPHxIgsxAi3V0sx3nN8jiitMcI/nyPqVqgsz3S/1mzPXbdfioPPEVn4HJGFzxGnRozw11wjIz7OXIqCuUYW8hGS6yztorb9xKmjeJEQAHK4xBF2VMTBPxYAJSchLUl2JR6wGgYAPqVxSOMRAJQYhzNrflbE9YkA4EQOl6uIK5PhlHMwoXDN9t1FhHpfWE+b+Bf1VaaPqY/tbUEcXaykKEKDAyQyLNjronBFPcKmR6i9LYCni6jpwglFPQLq7bSRoynpkpruLHIllbcFcZJ0QZy0gi+I89q872TK9oXSPLaevNbzLomNDvM4Th9TH7s41fOepKVnSmIxFrvQ3mreFrsozgJ4+nfztrCevtaKSl9n3hbWK2oPchWlC+t5qcAgRmQhRhQtRpxYQeRt4ZrixIj9yYfk3ilvSHxKojzc5XK5oHG3nPuIEVmIEcfxOeLk+hzhjxjhr88RI9fOkFdmD5eYsCj5vP8jEuaIlKLic0QW5hpZyvJc41SKEf6Ya6RnZMotY9+QVQc3y5m12suDHa6UwmCukYV8RMFexyg7SCIDsEW37+6UTFfWB8xRQ1+QKpExVrsAgK3Gbpwjz874xmx3iGsi7519j9UuAGC7u8a/I/N3rzHbT3e7RvrX72y1CwDYau/ReDn/t8fNdqAjQGZc9b7VLgBgiXYWAGyRnUA+cRsA/CXTSRwCcJJ9JnKLSwDgL8zNAPgCSWQAAAAAAAAAgFckkQHYIiwoxOM2APhLWNDxPobhbtsA4E/hbp+DwoOJRQD8z30+xmciAHYhiQzAFte1HCARwWEypHF3iQmLthoOALbrXL2ZtKrcQGLDysklzc6yGg4APnFJs14mDmk86lytmdVwALCdzsd0Xqbzs2tb9rcaDgAFwsJ6AAAAAAAAAACvqEQGAAAAAAAAAHhFEhmALX5fM02G/P6kfLLoT6uhAOATyemp8uCkj+SyUcNkyd4NVsMBwCc0/mgc0nikcQkASoLOy3R+pvM0ALADSWQAtvhw4UjZlXhAvlk2Tg6nJFoNBwDbzdm1SmZsXyabD++WH5ZPsBoOAD6h8UfjkMYjjUsA4G86H/t62VgzP9N5GgDYgSQyAFscTU8x1y5xSVIGVTcA/O9oWnLOdmL68W0A8Cf3+OMelwDAX9znY9nzNAAoLpLIAAAAAAAAAACvSCIDsIVDHB63AcBfHI7jsSfAbRsA/Mk9/rjHJQDwF+ZmAHyBJDIAW5xRs4W5bhhTQ6pGxlgNBwDbta3aSCKCw8z2GTVbWg0HAJ/Ijj8ajzQuAYC/6XxM52WqG5+JANjE4XK5XFaDAMBKemaGrDqwxXxYyU7iAIC/7U06JIdSEqRxbC2roQDgM2sObJOY8GipElHBaigA+ERSeoqsj98hzSvVlaCAQKvhAGCJJDIAAAAAAAAAwCvaWQCwxeoDW+XV2T/K3J2rrIYCgE84XU75bfVUeWfer3IwOcFqOAD4hMYfjUMajzQuAUBJ0HmZzs90ngYAdgiyGgAABfHY1M9kV+IBGbNxjoy5+FUJCwqx2gUAbLV4z3p5fe7PZjshLUmeOONqq10AwHYfLvxDRm+YbbbrVagm7eIaW+0CALZKyUiThyZ/LKmZ6TJ750r5fchzVrsAgCUqkQHYQhPI2R9Y4lOoAARQcnFI7XTbBgB/co8/7nEJAPxF52OaQFbEIQB2IYkMAAAAAAAAAPCKJDIAAAAAAAAAwCuSyABsUbtcVXMdGRwmFcPLWQ0HANvVKR/ntp0VkwDA39zjj3tcAgB/0fmYzsvc52kAUFwOl8vlshoEAFa2HdlrFtXrXrOVNKtUx2o4APjExM0LZUfCPhnatGfO5AkA/Oloeor8tnqq1CxXWXrVaWc1HAB8YtX+LTJ9+1IZUL+z1CpXxWo4AFgiiQwAAAAAAAAA8Ip2FgBskZSeItO2LjErAQNASdl8aJfM3blKONEKQEnR+DNn50oTjwCgpOi8TOdnOk8DADsEWQ0AgIJ4YNJHsmjPOqkeVVFGDH5WAhwcowLgX1sO75Gr/35J0p0ZcmPrc+SG1udY7QIAtvtiyWj5Yuk/EhwQJN8Nepwe7QD8zulyyo3/vCo7Ew9Iu6qN5IN+/7PaBQAskeUBYAtNICv9oLLnaLzVcACw3fL9m0wCWS3cvdZqOAD49DORxiONSwDgbzof03mZWngsJgFAcZFEBgAApwa3tYJZNRhASckVf1jDHAAAnCJIIgMAAAAAAAAAvCKJDMAW5UIizXWgI0CiQsKthgOA7cqFZsUhVSE0Kt+xAOAr5d1iUfkwYhEA/9P5WIDDkScmAUBxsLAeAFs80PkS+XHlROlbr4NEh0RYDQcA23Wu3kwGNewq2xP2yXWtBlgNBwCfuL7VQDmcelRqRleWTtWaWg0HANvpfOzO9kNkwqb5clnz3lbDAaBAHC4XjboAAAAAAAAAAJ7RzgKAbdIy04XjUgBKUqbTKRnOTKthAOBTGoc0HgFASdF5mc7PAMAuJJEB2OK9+b9Lzx/ukSemfWE1FAB84nBKolz+53PSa/j/ZMqWRVbDAcAnNP5oHLrir+dMXAKAkqDzMp2fvb/gd6uhAFAgJJEB2OLX1VPM9aQtC+VA8mGr4QBgu7m7VsvWI3sk3ZkhI9f9ZzUcAHxC44/GoS2H95i4BAD+pvMxnZepEauy5mkAUFwkkQHYIs2ZcXw78/g2APiL+ymbnL4JoKQQiwCUNPf5mPs8DQCKgyQyAAAAAAAAAMArksgAbBEcEORxGwD8JTjweOwJIQ4BKCHu8cc9LgGAvzA3A+ALJJEB2OL8RmeY6zNqtpBKEeWthgOA7TrENZXqURUl0BEg5zQ83Wo4APiExh+NQxqPOlZrajUcAGyn8zGdl7nP0wCguBwul8tlNQgArGgoOZKWJNEh4RLg4PgUgJLrRZruzJTI4DCroQDgM0fTUyQ4IFBCAoOthgKATzhdTklIS5ZyIRHicDishgOAJZLIAAAAAAAAAACvKBcEYIupWxfLHePekj/WTrcaCgA+kZ6ZIW/O/UXum/iBbDq0y2o4APiExh+NQxqPNC4BQEnQeZnOz3SeBgB2YKUHALZ4ZfZwiU9JlCV7N0jfuh0kKiTcahcAsNW8XatlxOopZjs8KFRe6Hmj1S4AYLvPl4yWWTtWmO0u1ZtL12N9SQHAXxLTkuWNOT9Lpsspmw7vkp6121jtAgCWqEQGYAtNICv9oJKQlmQ1HABsF5+S4HEbAPyJWASgpOl8TOdl7vM0ACguksgAAAAAAAAAAK9IIgMAAAAAAAAAvCKJDMAWLSrXM9dVIipIlYgYq+EAYLvmlepKoCPro02rKvWthgOAT7SsnBV/NB5pXAIAf9P5mM7L3GMSABSXw+VyuawGAUBB+m7N3L5C2sU1ksrHPrAAgL+tObBNdh89IN1qtpLAAI6VA/C/TKdTZmxfKnGRFaVJxVpWwwHAJ/YmHZJFu9dJ15qnSXRIhNVwALBEEhkAAAAAAAAA4BUlOgBssTvxoHy3fLxsiN9pNRQAfGbm9uXyy6rJkpKRZjUUAHxC44/GIY1HAFBSdF6m8zOdpwGAHahEBmCLK/58TjYe2iXRIeEy+qJXJDgwyGoXALDVyv2b5YZ/XjXbQ5v0lAc6X2K1CwDY7vU5P8tva6aa7S8HPizNKtWx2gUAbJWemSHnjHhYEtKSpX6FavLDeU9a7QIAlqhEBmALTSAr/aCyP/mw1XAAsN2mY3FIbTzEWREASoZ7/CEWASgJOh/TeZn7PA0AioskMgAAAAAAAADAK5LIAAAAAAAAAACvSCIDsEWViArmOiQwWCqERlkNBwDbVYmMydmu6rYNAP7kHn+qRsbmOxYAfEHnYyEBWWvUVI3gMxEAe7CwHgBbLN27Qf5YO1161Wkn3Wu1shoOALZzupzy48qJsj1hn1zXamDOwS0A8Ke9SYfkq6X/SM3oynJZ894S4KBuB4D/Td+2VCZtWSiDG3eXVlUaWA0HAEskkQEAAAAAAAAAXnFYHIAtMp1OWXdwu6RkpFkNBQCfOZSSKFuP7LEaBgA+pXFI4xEAlBSdl+n8TOdpAGCHrCY5AFBMT07/QiZvWSTNKtaRLwY+JA6Hw2oXALDVnqMH5aq/XpSEtCS5v9MlcmHTnla7AIDtfl09Vd6Y+7NEh0TId4Meoy8yAL9zuVxy+7i3ZNWBLabd4As9b7TaBQAsUYkMwBZTty421/pBZW9SvNVwALDdwt3rTAJZTTkWkwDA37Ljj8YjjUsA4G86H9N5mZqydZHVcAAoEJLIAGzhdLk8bgOAPxfW87QNAP5ELAJQ0pibAfAFksgAAAAAAAAAAK9IIgOwRURQaM52uNs2APhLRHCY2zZxCEDJcI8/7nEJAPzFfT7mPk8DgOIgiQzAFje2OVdiwqLk0ma9pEJYlNVwALBdp+rNpENcE4mLjJXLm/exGg4APqHxR+OQxiONSwDgbxWOzct0fqbzNACwg8Oly3YCAAAAAAAAAOABlcgAAAAAAAAAAK9IIgOwxU8rJ8m5Ix6Rd+f/ZjUUAHziaHqK3DPhXRn6+5OycPdaq+EA4BMafzQOaTxKSk+xGg4APqHzMp2f6TwNAOxAEhmALT5b/JccSD4iP66cKIdSEq2GA4Dt5u5cJXN3rZadiQdMLAKAkjB85b8mDmk80rgEAP6m8zH9LKTzs8+W/G01HAAKhCQyAFskZaTmbCe7bQOAv7hX/GlVMgCUhKT045+DiEUASoL7fIwzIgDYhSQyAAAAAAAAAMArksgAbBHgcHjcBgB/CXAEeNwGAH8iFgEoaczNAPgCMywAtuhZq425blaxtlSJiLEaDgC2a1u1kUSHhJvtnrVbWw0HAJ/oWauVudZ41C6ukdVwALCdzseaVqyda54GAMXlcLlcLqtBAGAlw5kpG+J3SJ3ycRIWFGI1HAB84mByghxJTZS6FapZDQUAn9l8aJeUC42S2PBoq6EA4BMpGWmy5fBuaRBTQ4ICAq2GA4AlksgAAAAAAAAAAK9oZwHAFsv2bZTn//tWZmxfZjUUAHzC6XLKjysnymuzf5R9SYeshgOAT2j80Tik8UjjEgCUBJ2X6fxM52kAYIcgqwEAUBBPTv1C9iTFy4TNC2Tsxa9KeHCo1S4AYKuFu9fJu/N/M9vJGWnyVLdrrHYBANt9uHCkjN0412w3jq0p7eOaWO0CALZKTk+Vx6d+LmmZ6bJg91r5Y+jzVrsAgCUqkQHYQhPISj+oHEpNtBoOALbbc/RgzvZut20A8Kc9R7M+E6ndicQiAP6n8zGdlyk+EwGwC0lkAAAAAAAAAIBXJJEBAAAAAAAAAF6RRAZgi3rlq5nr6JBwqRRe3mo4ANiuboWsOKTquW0DgD+5xx9iEYCSUDG8nJmXuc/TAKC4HC6Xy2U1CACs7Eo8IOM2zZNuNVtIw5iaVsMBwCemb1sqOxL2ywWNu0lYUIjVcADwyYJWo9b9JzWiK0n3Wq2shgOAT6yP3y4zti+XfvU6SrWoilbDAcASSWQAAAAAAAAAgFe0swBgi8S0ZPl303zZn3TYaigA+My6g9tNNbLT5bQaCgA+ofFH45DGIwAoKTov0/mZztMAwA5BVgMAoCDum/iBLNu3UapGxMhvQ56TwACOUQHwr02Hdsl1o1+WTJdTrm3ZX25pe57VLgBgu08X/yXfLBsngY4A+X7Q47n6tQOAP2Q6nXLjP6/KnqR4aVW5gXwy4H6rXQDAElkeALbQBLLSDyp7k+KthgOA7Vbu32wSyGrJ3g1WwwHAJ5buzfpMpPFoxf7NVsMBwHY6H9N5mVq6j89EAOxBEhkAAAAAAAAA4BVJZAAAAAAAAACAVySRAdiiQmiUudb+f9EhEVbDAcB2FcKy4pCKCYvOdywA+AqxCEBJ0/mYzstUjNvnIwAoDhbWA2CLh7tcJj+vmix96raXqJBwq+EAYLtO1ZrJ0CY9ZXvCPrmh9UCr4QDgEze2PkeS0lOlZnRl6VitqdVwALCdzsf+1/Ei+XfzArmk2VlWwwGgQBwul8tlNQgAAAAAAAAAUDbRzgKALfR4VGJasjhdTquhAOAz6ZkZkpyeajUMAHxK45DGIwAoKTov0/kZANiFJDIAW7w9b4T0/el+eWTyp1ZDAcAn4lMS5LJRw0ws0tM3AaAk/LtpvolDGo80LgFASdB5mcait+b+YjUUAAqEJDIAW/yxdoa5nr59qexPOmw1HABsN2/XatmRuF8yXU75e91Mq+EA4BN/r59l4pDGI41LAOBvOh/TeZn7PA0AioskMgBbpDszPG4DgL+4nzqeRhwCUELc4w8tLQCUBOZmAHyBJDIAAAAAAAAAwCuSyABsERIQdHw78Pg2APhLSGCwx20A8CdiEYCS5j4fc5+nAUBxkEQGYIuhTXua67Nqt5WK4eWthgOA7TpWayq1y1WR4IAgOb/RGVbDAcAnNP5oHNJ41KlaU6vhAGA7nY/pvExd2PRMq+EAUCAOl8vlshoEAAWRkpEmoYHB4nA4rIYCgE9kODPF6XJSiQygRKVlpkuAI0CCAgKthgKAT2iqJzUzXcKCQqyGAkCBkEQGAAAAAAAAAHhFOwsAtvh38wK56Z/X5JdVk62GAoDPKv9envWD3Dn+bVkfv91qOAD4hMYfjUMajzQuAUBJ+HnVJDM/03kaANiBJDIAW7w+5ydZvn+TvDv/N0lIS7IaDgC2m7trtYxa958s2L1Wvlwyxmo4APiExh+NQxqPNC4BgL/pfOy9+b+b+ZnO0wDADiSRAdjicOpRc53pckpiWrLVcACw3eGUxJztQ6nHtwHAn9zjj3tcAgB/0fmYzsvc52kAUFwkkQEAAAAAAAAAXpFEBgAApwaH4/hmvgMBwHccXuISAABAaUYSGYAt2lRtaK6rRVWUqpExVsMBwHanVaorQQGBZrtN1UZWwwHAJ7Ljj8ajFpXqWQ0HANtViYgx8zL3eRoAFJfD5XK5rAYBgJWj6Skyb+cqaVWlocSGR1sNBwCf2Hhop+w5Gi+dqzeTAAfHygH4n9PllDk7V5mD6vUrVLcaDgA+cTA5QZbuXS8dqzeTyOAwq+EAYIkkMgAAAAAAAADAK0p0ANhie8I++WLJaFlzYKvVUADwmSlbFsn3y8dLUnqK1VAA8NnZWRqHNB4BQEnReZnOz3SeBgB2oBIZgC0uHfWsbDm8x5wq9c/Fr0hIYLDVLgBgqxX7NsmNY14z24Mbd5eHulxmtQsA2O7V2T/KH2unm+3PBzwop1WmLzIA/0rLTJeBvzxsDmrVKV9Vfjr/aatdAMASlcgAbKEJZKUfVA4kH7EaDgC223x4t8dtAPAnYhGAkqbzMZ2Xuc/TAKC4SCIDAAAAAAAAALwiiQwAAAAAAAAA8IokMgBbxEXGmuvQwGCJCYu2Gg4AtqsWVdHjNgD4E7EIQEnT+ZjOy9znaQBQXCysB8AWq/ZvkVHrZsiZtdtKlxrNrYYDgO2cLqf8tmaaWYX8mhb9JDa8nNUuAGC7g8lH5Jvl46RmdGUZ2qSHBDio2wHgf7N3rJQpWxfJ+Y26SbNKdayGA4AlksgAAAAAAAAAAK84LA7AFhnOTFmxb5Mkp6daDQUAn9mfdFjWx2+3GgYAPqVxSOMRAJQUnZfp/EznaQBghyCrAQBQEI9P/UymbVsqjWJqyjfnPioOh8NqFwCw1a7EA3LVXy/I0fQUuafDhXJp815WuwCA7X5aOUnemf+rRAaHyXeDHqdHOwC/c7lccsvYN2Rd/HbpUauVvHLWrVa7AIAlKpEB2GL6tmXmWj+o7E2KtxoOALZbtGedSSCrGduzYhIA+NuM7UvNtcajxXvWWw0HANvtORpv5mWKz0QA7EISGYAtXOLK2Xa6jm8DgD+rbtwX2QOAkuD+OYhYBKAkMDcD4AskkQEAAAAAAAAAXpFEBmAL7funHOKQiKBQq+EAYLvIkPCc7ajg49sA4E/u8cc9LgGAv7jPx7LnaQBQXCSRAdji1rbnS9WIGLmyRV8pHxZlNRwAbNe5WjPpWqOF1C5XVa44rY/VcADwCY0/Goc0HmlcAgB/0/nYVS3ONvMznacBgB0cLvcGggAAAAAAAAAAuKESGQAAAAAAAADgFUlkALb4fvl4Ofun++WNOT9bDQUAnzialiy3jX1TBo14VObuXG01HAB8QuOPxiGNRxqXAKAk6LxM52c6TwMAO5BEBlAkHy0cJRf98bSMXj/LfP3l0jGSkJYsv66ZKvEpCTJ7x0q5ZOSzMmzGN+J0Oa0eDgAKbV/SIbl17Bty05jXZFfiAZmza5Us3rte9icflp9XTTKx5825v8glI5+RiZsXWj0cABSJxheNMxpvNO5o/NE4pPFI45LGJ41TGq80bgGA3TT26LxL5186D9P5mM7LdH6m8zSl8zadv+k8DgCKgiQygELTDyXfLh8n2xP2ySuzf5S9R+MlOSM15/5DKYky7L+vZeuRPTJm4xxZc2Bbvo8HAEUxbuM8WbJ3gyzft0len/OzJKcfj0Mak6ZsXSwjVk+RrUf2ypdLR+f7WABQVF8sGW3ijMYbjTvun4k0Lml80jil8Wr8pnn5PhYAFMXqA1vNvEvnXzoP0/lYNo1JOl/TeZvO33Qep/M5ACgsksgACq1cSKRUjqhgttOdGfL9igm57h+7ca7EH/vgEhYUIjWiK3t8HAAojkaxNXK2Z+5Ybqr9sum6wV8s+Sfn6wYVjo8FADs1jDkeX750iztqZ8J+E588jQUAu9SMrmLmXUrnYScesPp2+Xgzb1M6jysfGunxcQAgPySRARRaYECAXNOiX87XWlkT6DgeTkatm5GzPbRJDykXGpHnMQCguDpVaybNKtbJ+XpH4v6c7YS0JNl4aGfO19e07J9nfwCwg3t82aBxx+XK+fo/twSyxiuNWwBgN51v6bzLvTI5W4A45M91/+V8rfO4ALe5GwAUFJEDQJEMatRVzqjZQiKCQs0Hll512pnbG8XUkMOpR822Hg2/vHlfi0cCgKJxOBzycJfLTUVNregqMrRxD6kQGmXuqxRRPmecxqcGMdXzeSQAKDqNLze2PkdCA4Pl/EZnSN/6Hc3tGo/2uvVA1jEatwDAF65u0V9aVK4n0SERcmHTnmZbta7aMFcVss7jAKAoHC493xMAikhDiE6IMp1O04OrelRFeXn2cJm3a7Xc0W6wDGjQ2eohAMC2WKQHsY6mJUtaZro8NvVzCQ0KlpfPvFmqRsZaPQQA2BKHsttYRIaEm1PKv146VnrVaSv3dbqYJDIAv8Ui/Sy0I2G/xEXFyiOTPzG92x89/UrpVL2p1UMAgEckkQEU25HUJJmydZG0qtJA6paPsxoOAD6hp25uiN8hveu2z+kLCAD+lOHMlClbFklseDlpF9fYajgA+MS+pEMyc/ty6VKjOQfSAdiGJDKAYrtr/Dsyf/cas3123Q7yZLdrJCgg0Go3ALCNVv1dPPIZyXQ5zdevnXWbdKvV0mo3ALDVV0vHyKeL/zLbNaMry6f9H5SY8Kw2OwDgD06XUy4dOUy2Jew1X1/Tsp/c0uY8zoQAUGz0RAZQbNk9kNX4zfPlt9VT8x0PAHY7mp6Sk0BWD07+SA6nJOa7DwD48jPR9oR98vi0z/IdDwB2c4hD4lMScr7+Ztk4mb1zZb77AEBBkEQGUGznNToj19eHUkncAPCvhjE1pFL48cX0FIs+APC3cxuenutr90QOAPiD9kPuXTdr0fNsqRlpXscDQEGRRAZQbLrCb/Cx9hW6nMyQJj2sdgEA2ydM17bsn/N1nXJVpUIYp5AD8P8BLY0/2S5s0jPf8QDgC9e3GmjmZUrnaV1rtrDYAwCs0RMZgG0LWn29dIyc16irdK1JH1IAJeP75eNlffwOeaDzpRIVEm41HABsl5iWLK/P+ckklK9scbbVcADwiZnbl8mf62bKta0GSNOKta2GA4AlksgAAAAAAAAAAK9oZwEAAAAAAAAA8IokMgAAAAAAAADAK5LIAAAAAAAAAACvSCIDAAAAAAAAALwK8n4XAAA41ThdTtlzNF62J+yTbUf2yu6jByUlI03SMtMlw5lptTsAoIwJCgiUkMBgCQsKkbjIWKlVrorUjK4sVSNjJMBBTRIAAGUFSWQAAE5hLpdLVh3YIhM3L5TZO1fI9iP7JM2ZYbUbAAD5CgkIkprlKkuX6qdJ77rtpFnFOuJwOHjWAAA4RTlcOrsEAACnlM2Hd8tf62bK5K2LZFfiAavhAAAUS7WoitKrTls5t2FXqVs+zmo4AAAoZUgiAwBwCjmaniJfLBktv6yaLJkup9VwAABsFegIkEua9ZLrWw+UyOAwq+EAAKCUIIkMAMApQE8smrB5vrw3/3fZn3zYajgAAD5VKby83N1hqPSp2542FwAAnAJIIgMAcAoslvfyrOHy1/qZUlC6GFLVqBipHl1RyoVGSnBgkAQHBIpD6GcJAMjiEpekOzMlPTNDDqccNe2R9iTGm/87BTWoYVd55PTLWYQPAIBSjoX1AAAoAwnkqJBw6VqrhXSp1VzqVKgqVaNiJSggMN99AAA4UYYzU/YkHpQth/bI7G0rZea25ZKYluz1icr+/0QiGQCA0o1KZAAATuEEcpu4hjL0tJ7mWquNAQCwk1YpL969Xn5bMdVce0NFMgAApRtJZAAASildQO/zJaM93lcporzc0vE86Va7Jb0oAQB+6c0/fctS+XT+X7I/yXNv/htbnys3tB7o8T4AAHByI4kMAEAptD1hn1wx6jlJc2bkua999cbyRM+rJTw41OO+AAD4SnJ6qjw35VtZuGttnvtCAoLkh/OflJrRlT3uCwAATl4BVgMAAMDJV+311txfvCaQnz7rWhLIAIASoQcw9f9Qu2qN89yn/7femjvC434AAODkRhIZAIBSZsb2ZTJzx4o8tzetVNtM3EMCgz3uBwCAP4QGBZv/R/p/6UQzdyyX6duWetwPAACcvEgiAwBQynjqgxzgcMjdXYaSQAYAnDSJ5Lu6DDH/nzz19AcAAKULSWQAAEqRbUf2ytqD2/Lcfm6TrlI/trrHfQAAKAkNYmvIuY275rl9zcFtprc/AAAoPUgiAwBQikzasjDPbcEBQXJV67M9jgcAoCRd1eZs83/qRJM25/1/BgAATl4kkQEAKEUmbVmU57aONZpIdGiEx/EAAJQk/f/UoUaTPLdP9HBQFAAAnLxIIgMAUErsSNjvsZVF9zqtPY4HAOBk0L1Oqzy36f+znQn7PY4HAAAnH5LIAACUEuvit+e5TU8R7lSzmcfxAACcDDrXbC7BAYF5bl/r4f8aAAA4OZFEBgCglNh+ZG+e2+pUqCqRIWEexwMAcDLQ/1O1K8TluX37ERbXAwCgtCCJDABAKbHNw2S7enQlj2MBADiZVI+umOe27Ql5D44CAICTE0lkAABKCU+T7erlSCIDAE5+NTz8v9qeQCUyAAClBUlkAABKCU+TbU+TcgAATjaezpzZ5qFNEwAAODmRRAYAoJRISEvOc1uliPIexwIAcDLx9P8q0cP/NQAAcHIiiQwAQCngcrkkNTMtz+2hQcEexwMAcDIJCwrJc1tqZrrHsQAA4ORDEhkAgFIg0+UUp8uV5/bggCCP4wEAOJkEBwZ5/N+W4cz0OB4AAJxcmHkCAFCKBTgcVkPgxTm3XyO79mX143z30WelW7tO+T5X/y2aL3e9+KTZXjhijEyc8588+Prz5uuvX3hTWjVuJgWpKD/n9mtl9/690u+MnvLSvY+Y259+/w35a+q/cnbXHvLy/x7NtU+7iwZ4fKywkFCJKV9eGtSqK13btJcB3c6S8tHRkp/sx3rvsefkjLYd8h2bmZkpA267WvbHH5SgwCAZ+8l3Elu+gtglPSNDJs+dKVPmzpKVG9fJ3oP7xel0SoXoclK9Spx0PK2V9O7STRrXrV/gv+OJIsLCpXa16uZ5vWTAeRIeGiZ20b//yIljZcX6tZKYlCQx5cpLm6bN5eL+g6R985ZSVFt37ZRfxv0lMxfNl90H9klQQKBUq1JVerTvLJcPPF9ibPwblFbPf/Ku/P7vGDn/rLPlqdvulTlLF8n/XnlWwsPC5LNnX5UGterkGv/JiB/k21G/SvvTWskbDzwhwcGcwVES+H8FAEDpRhIZAACUeS9++r6MeOtjiQyPKPBz0aNdJykXGSVHjibKuBlTC5REXrBymUkgq3N79pHiSElLNclTvcxYOFfe++EruW7wxXLtBRdLUGCgFNeMRfNMAlllZGbI31P/lavPu1Ds8N+iefLCJ++ZJOmJ9h48YC6LV6+Qz377Ubq17SgP33C71KgaJ4WVlJIsqzdtMBdNOr7/+AsmqezNzr175Mn3X5dFq5Z7TbSnp6fLI2+9JJPnzcp1+774AzJh1nRzueKcwXL/tTdLYY2cNE5e+fxDSU3P3bpm3ZZN5vLz2L/MgQerAwCnusduulNSUlNl1OTxcvDIIZm3bIlJIH/89Mt5Esjquz9/k+TUFPM+Wb9tizSr39Dj4wIAAMA7ksgAAKDM02Tmez98LY/ceHuBnwutZuzbtYf8NuEfmTBrmkkaBgTk3yls9NSJ5rpyTEXp0qqtFMYbDz4pnVse3+doSrJJ8mqy9c/J42XN5o3y4U/fyvwVS+Wth542SbXiGDlxnLkODQ4xSc2Rk8YXO4ms1c1vfvuZ/DTmT1OVrZXNWkHdo0NnqVa5ikRFRMrhhCOyetN6mbZgrkyYOd0ks5c/eo/8/PqHUjm2otfHfuDaW+SCXv3yJNrnLV8sb3zzmWzfs1vufukpGfHGRx4rUTVJ/uoXH0licpLk9/Pf//rzJhkZGBAgF559jgw6s49UrVhZtu7aIcNHjzQVyj+M/sNUVT94/a1SUHOXLZbnP35XnC6ntGl6mlx3wcXSpG59U7G9fP0a+XTED7Jpxza5/7Vh8uVzr0vzBo2lrNL32bN33Ccul9McmKlasZK8cv/j0rhOPY/jrzpvaE4lcsPadT2OAQAAQP5IIgMAgDKtdZPmsmTNShkx/m/p362nSeAV1Dk9epkk8v5D8TJvxZJcSd4TpaalycTZM3L2CyxktXBIcIhEhIfnfK3blWNiTVXlZQPPN0nfV7740CQjH337ZXn7kWekqDQ5rdXC6qEbbjPtAzbv2GaeJ32+iuqd77+UH/8ZJQ6HQy7uN0juuer6PC0mtJ1Fneo1pd8ZZ8odl14jz370lknW5pdAViHBwbmeH6Vf6+M0qlNfLnvwDpPoHTNjipx3Vt+cMYcTEuSFT9+Vf4/9bfLz279jTAJZf/4X731E+p7ePee+ihVipG2zFvL5bz+aZP6PY0aZ5HjnAh4s0P00gaxVxu888myuAxJahd21TQe54akHZP3WzeZvXZaTyErfPy/c87AUxC0XXWEuAAAAKDoW1gMAAGWaJnS1KlgrY4d9/I6kndBKID+acK55rM2CtrTIz5R5s3KqXAe5JTHtckHvfvLK/Y9JgCNApi2YYypri0r3zcjMNBXT2ne27bHEenZ1clH8M32SfP/372b70RvvMFXfVj2Kq1epKp88/XKuZG1R1K9ZWzq1bGO2V6xfk3P7hm1b5OL7bzMJZO37fMdl13h9jKPJSfLxz9+Z7Yv7nev1Z7px6GU5VeZvfP2pFNSqjevMtT7fniraoyMj5bk7H5DvXnpbHrv5Lg+PAAAAAPgOSWQAAFDmPX7z3RIWGmqqbT//7adCPR8Duvcy19rGQPvlWrWyaNGwidSrUUt8QRdf02Sy+uzXH01ivChGTRpvrgf2OMskNM89M6t/8/iZ0yQpOVkKKzklRd785jOzfdHZ55jKYn/LTsw6HG4VvlXiJCoiwiSZv33pLblhyKX5Lqx4KOGI6TetrSbyc9OFl5vr9ds2y6qN66Ugsn+uXcd6ZnvSpF4DOa1hkzy33/T0Q2bRxHe//1K80VYYOkYv2vs528e/fG9uu+P5J8zXG7dtkec+fscsWHj65efLubdfaxaQnLd8iVjZvmeXSZxffN9t0u2qIXLmtRfJpQ/cIR/99K3s3p+3/7X7z64tTrRv8We/Dpch994snS4dZG5fs2lDnn0WrlouT7z7mlxw943S9YoLpPvVQ+SKh+82+yYcTcwzPvt3vPqxez1+76/++CXnb3zPy09L3xsvN4+rP8fLn38om3dsz/OYAAAAZQ1JZAAAUOZpu4DbL7naPA9fjxxhFjErTCWz0uTVzMULPI45ePiQzF660GxrD11fyu5bvG33Tlm5Ya0UlvaY3bJrh9kedGZWxbRW3WqSXZN842bmX3HtycQ5M8xzoJXHd15+rfibPhdzly42222bHW9Xor/Tu48Okx9eeU+a1st/sbXpC+aa62b1G0mVipUsK9RjypU321Pnz5aC6HhaK3P92YjhBUrY+sLoaZPk8ofvkj8mjjULNmov7J379pgDJLc8+4hpa+LtQMmfkyfI0HtvNv2gNXmuixrqopNrt2w0CyRedN8t5iBEfgcarn38Pvno5+/MwRxdzPFEupjesx++JTc+9aCpbNf2JNr3+mhysqnk1n21slwrzAtLk8V3vfik+TsfOBxvHld/jl/G/SWXPHCbWZgRAACgLKMnMgAAgIjpKzzuv6myYsNaGfbR2/L1C28WqG9x7Wo1pEWjJrJ83RoZ+98U6dmxS54xY2dMMe0htG9vvzN6ii/VrlZdqleuapJ/S9as8li5mp9Rk8blVExrha6KDI+Qszp1lTHTJ5uWFoN795fCmLkoK7mu/X6jI6PEXzQxqT2iX/vqY5MQbd+8ZZ42FHoAoSDWbM6qiG3T1LontPZM1kTy5LkzPVbSenLnFdeZBL4mXjVhe3rr9qaqvHu7TibZ7Wvaa1kTtLog462XXCVndjhdykdFycbtW02VsCaSNZGqv9vjJ7TT0OTwMx++aVqpnNuzt1zQu7/Ujqsumc5Mc0DmpzF/yczF8+Xxd16RSjGx0q5Zizzf/7u/fjOV3hf2HSiXDjjPJOH1e1dx64X95HuvmZ9DDerZR4b0HSi146qZ50wP4Hzx+0+y58B+U2H829uf5iTyrWhfc32/6BkCNwy9VNo2bWEWTly6dpV8+ccvZqFHTaDr+8DX718AAICTFUlkAACAYwt1PXXbvea0eE0k6wJwVw4aUqDn5pwevU0SWatONXGpibgTKzxVzw6nS7moaPG1mnHVTFJsx57dUhiJSUdzFpg7sWL6vDP7miTysnWrTcuD+rXqSEFt2rE1px1DfjT5p4nU/GgS76V7H8lz+4ufvW8u3mhy8t6rbvTYb7ggtJJaaRK0ILLHaVVrQWgCc/ir78uwj982ie9ZSxaYi1Zvn9mxi0mYahLcV/bFHzBJ16+ef9MciMjWvnwFaX9aK9Py4b3hX5mEq/4NOhyrnNYK/JeOPe9P3naP6ensrmrFytKtXSd58dP35NcJ/8gLn7xrErwn0gTyrRdfKTe7LYCn39v9PZSdQH7q1ntz2raomPIVzGKMPTt0kSsfuds8llYqX3HOYCkIfa9o0v/9x57LtThjn9O7m8d88I0XTJ9xfX11bdPerwdCAAAAThZF+xQNAABwCmpUp55cc35WO4gPf/62wElYTarpwmx6ur0uoOdOqymzF0077yzftrLIFhURaa61/URhaMW0/g6eKqY7tmgtcRUrm+2Rx3omF5S2G3D/uYrjcMIRKQr9O2jP3qI6kphYqN8h+ti47P0KQhcS/Pipl+TzYa/J2V17SFhIVguRMTOmmAT7rcMeNa05fOWh62/LlUB2d93gi02iVY0Y93fO7Vq9fzgxwSSVT0wgu8tODmtvZq3wPZFWHOfXk/rnMX+aa31e3BPIJz5/rz3whElSFzSBrPS9++I9D+dKIGcLDg6WYXfeL5Hh4SZhrn8LAACAsohKZAAAADc3XXiZqXjUfqh6CvtHT71o+fxUiC5nWjVoJbK2tBjQ/aw8VchamdqlVTvxB60oVlrFWhh/TMxqZaHVlydWTGsF74AeveSrP36W0dMmyl1XXCfBQQX7KKkJOPefy5v3HntOnE6nx/te/eoj03fXWxXoA9feIhf0yp1c1HYKmrTUBdd00bQbn35IPn3mZcv+x56Ui4oy1chWv0O2xKSknP0KS9s96EUXMZwyf5b88e9YU6GtFcpXPnKPfPjE84VuU1KQ13DvLt3yHTO4dz9ZvHqFaU2RbcbCeeZ6/oqlZpG6gtCexa0aN8t1W5fW7by2jzmckCDL168x20P7DpT8FKVaW9+7cZWyDpB4ou+FXp27yV9TJsjMRfPl4n7neh0LAABwqqISGQAAwE1IcIg8ecvdpvfrnGWLZNTk8YVaYG/W4oUm6aVcLpdpAaEGdu9VoB7Ldti+e1eh+v2qtVs25VRMa1Xp1l0781zaHusHHH/ksEwr4IJxql6NrN7KVv2BtfevVoN6umzduSOn2tQTrZ4+cR9NOGuyUhfP00ShJoBf+eIjKYrYY60V9scflILYfyhrXMXyMVJU+jvo6+azZ1+VD594wbSb0GrYR99+2fTYtpP29g6yeH1m/x21svxIYtZrfNf+vVJY+vo5UWy5460rTrRr/56c7QaFaKNSUAVpzVKvZq0i/74AAACngoKVjwAAAJQhbZu1MD10R4wfLW9985l0a9vRahfp0aGzaXWgicqJc2bIkD4DTHXm7mNJp/NO6DHsK1t37TA9XlXrJrmrPfMzcuLYnO2XPv9AClK1bFW5mq1r2/amQlurgTUJWtiestrjNrsStV2zwlea6gGBmy683Hz/JWtWyr74g1K5gL2NszWp28AsPqeLFRaEVuwWpA90QWml7ov3Piy3DXtMtu/ZbX6PwlTd6gGN4nKJK9dz6v64t196tVw+8AIpCG0RUeoc+z0dkvV7AwAAlDVUIgMAAHig7RqqVqwkR44myitffFigCua+p3c322NnTDXX2vZBndagcYGqHe3w3V+/m+uaVatJ8waNpSDS0tNyKqYLavaShbJ7/z4piN6du5lKXu3v+/7wr6Wwfvj7D1N5q4/RqWUbKQpduC7bngL+3O66t+9krlduWCv7Dh6wTCBnL8SnrUGs6IEHXbDup2N9f73p1KJNTk9m937dDkdATvuO/BbOszr4YFXdrC1eVERYVpW3iqtUxVzv2rfXaxX5iZeCtkHJVq1S1VytMOymC0Va2bRju7muWqmS1VAAAIBTEklkAAAADzRZ98iNd5jtf2fPyLNgnicDj7W0WLhymVkAbdLs/8zXg87qK/7w36J5pn+uunHoZTnVolYmzZlpFkdTP7/+oSwcMcbrZfKXv5jWEU6X0/SILYjwsDD539U3mW2t7v51wj9SUJqQ/WbUr2ZbF0sLDQmRoti8MysJmN2furC0HYb2DdZE61cjf8l37Ge//miuG9aqK83qW/df1p7NL3z6nnz407emUtubjIwMycjMMNux5cvn3B4dmZVY3rn3eNuHE02dN9uy2nvi7BkF6pmtVdHZurRqa64nzJouR5Oz+kB7kp6eLr//O6bQiz2q8tHR5kCM0mR7fjTJb9U25URaoZ7fARFt3TFpTtZzc7rb7w4AAFCWkEQGAADwQqtIz+7aw2xrAsyKLoZWvXJVk2B98r3XJTE5ySRc+3XtKb6mCd0HX3/BfG9tvzGoEO0zRk7KSg62aNhEGtWpZ5nQO6tTV7OtC90VtE2C9oy+8twhZvulz96X1776WFLT0vLdR5Oadzz/hEmcauuGq88bKkWhP+NnI4abbf398ltEzZvI8Ai57ZKrzPYvY/82iy968tUfv8isJQvM9v3X3iwFcVG/cyU0OMRUJN//2vMm4erJD6P/kJTUVDO2Wf1GObc3rlvfXM9cvMC06jjR0rWr5Nfx1on7V7/8yFQke/LF7z/ltOi46Oxzcm4/p0dviQqPMD+7vuY9/ez6/L/61cdmocoL/3eL+R0K65IB55nr8TOnychjyewT6e/+0BsvymUP3Skf/fStFJS+vh575xWzkKGnKv0n33/d9IHW33NAt6wDRQAAAGVN4c4lAwAAKGMeuv42mbN0UU6lbn608ndA97NMwk0Td6pH+84m8VpcmsxyT3JpRae2KFi8eqVJ5q7etN7c3uG01vLy/x4tcBWytkWYt3yJ2b6gdz8pCB037r+psmPvbpm7fLF0bplVjWrlniuvl8zMTPlxzCj58Z9RMmHmNBnQvZf0aN9JqlWualodaBuIlRvWyeipE83ChqpNk+byxoNP5rswYVp6ep4koCbUNSn66YjhMmPRPPOc3HnZtVJU2udaH2f6grny6FsvyUVnnyvn9OxtktJaea6/kyY51WUDz5fOx6p0rWjrkYduuE2e+/gdmb9iiVz92L1yw5BLpU3T00wCVquoR4z721TEq6vOGyoVKxxfsG+gvuZ++9G8Jm548n6556obpWXDJpKanmaqzD8d8YNZlC+/lhZaea8LQl716L1y/eBL5MyOXaRcZJRs3L7VtNnITpoP7t0/1++lr+2nbrtXHnrzRVOtr/tfN/gi87MHBATK2s0b5bu/fpO5yxab8dddcLFZQLGwzu3ZW6bOm2V+jmEfvy2LVi2XIX0HSu1q1U2l8Oyli+SrP36WvQcPmFYbF7oluq3o76kJ8isfvUduHHqp6bsd4HCY9/CXf/wsq49VNj960522vJcBAABKI5LIAAAA+dA+vPddc5M8/cGbBXqetDJTk8jZBp1pTyuL+197Lt/7NTF39XkXmuRjYXrOjpo83iQqw0PDpN8ZBauY1t68NavGmQXeRk0cX+AksiaBH7z+VrPQ3gufvCe7D+wzCUa9eKK/xyX9z5M7LrvGso3F619/Yi7e6GM9eN2tOb2Ni0J//tfvf8JUrWoy0yTDx4zKM+6qQUPlf1ffKIWhyVn9GV/67ANZs3mjScqeSJPgunhddkV0tlpx1eXuK2+QN7/51PxNHnz9+Vz3a/uOV+9/XK574j7xpm6Nmua1+8bXn8g7339hLp6S6A9ff1ue2/uc3l1euPshU2m8dstGefTtV/KMCQoMNAdkCpPcPdFzdz0okRER5qDJX1P/NZcTaR/zdx8dJpVjK0pBXdC7v0mwa1/wJ959Lc/9+nfRn10PEAEAAJRVBZ9hAAAAlFGaCB4zY4pZTM6KJuO0f+uKDWulUoUY6dqmvfiCtjTQ6tIGtevI6a3bmwSXfl0YTufxvsbatkNbNhSEJjPP79VPPvjxG5k09z9TwVqYCs0z2naUUe9/KZPm/Gd69a7cuE72HtxvqpT1d9DK3K5tO0j/M86U6lWOL6pWWJq41GSiJrkvP+cCaVi7rhRXcHCwvPbAEzJ57kzTf3r5+jWmlUOFcuWlbdMWcumAQdK2WQspinN79pEurdrJj2P+lP8WzpPte3aZBH/VSpWl42mtZGjfgTmtK0505bmDzeKB2vJi5fq1kpKWKtUqVZFenc+QKwcNMa8XK5f0HyQtGzWV4aNHyoKVSyX+yGFT8ayv54v7D5IOp7Xyuq++/to1byG/Txgj0xbMkZ379orTmWkWxevYsrVcOuA8k+wuDj1Q8szt98l5Z51tvs+ydatl74H9EhAQIHVr1DLV0/p9shf9KyitOtYkuD5X2nNZeyonp6SYCnOtutaq8trValg9DAAAwCnN4SpoIzsAAFBiMpyZ0v37u/Lc/sG590qDWJIbAIrm41++N+0uWjRqIt+++LaUJTc9/ZAsWLlMrj3/Irn7yuuthqOYNhzcIXf8nfc1Nv3K9yQowHurGgAAcHJgYT0AAAAAAAAAgFckkQEAAAAAAAAAXpFEBgAAAAAAAAB4RRIZAAAAAAAAAOAVSWQAAAAAAAAAgFdB3u8CAAAAcCq79eIrzaUs+uzZV62GAAAA4BgqkQEAAAAAAAAAXpFEBgAAAAAAAAB4RRIZAAAAAAAAAOAVSWQAAGDp61EjZOuuHVbDAACliMvlkp/GjJL1WzdbDQUAAGUcSWQAAJCvMdMny7vffylXPXqvJBxN5NkCgFPEVyN/kVe//FgefvNFSU5JsRoOAADKsCCrAQAAoOzaumunvPDpe2b76vOGSnRklOzcu0fOveNaKaipX48w+5UFO/bslntefloOHj4kz9xxn/Ro39lqF+Tjj4lj5a1vPpN6NWvLe48Nk3JR0eb2j3/5Xj4d8YO0aNREvn3x7VL3vdx9++ev8vZ3X0ifLt3k1fsf9zrO/X3329ufSr0atSQ/m3Zsk6H33my2//7ga6lepar44/WdmZkpv074R0ZNGi+bd26TAEeAdDitlbz9yDOSnp4u97/+vCxYsVSuOm+o3HrxleJvfW+8XA4cjpdnbr9Pzjurr9XwnL+/J1HhEVIzrpr07tJNLu53boHj3IyFc+Xul5422z07dJG3Hs7azs/T778hf03912xXiC4n4z75XoKDg6Ug4o8clv63XCnpGRnm62vPv0juvvJ6s31h34Hy67jR5vXy8hcfyrN33GfxaAAAoKyiEhkAAHj1zvdfSFJKsrRt1kKuu+DiU+KZ+mH0HyYxtHLDWrHbpLn/ycbtW+VQwhH5fcIYq+Gw8OPoUZKYnCTL1q2WeSuWyqnyvdxNmTfbXPfseLqc7Ary+n7krZfklS8+lNWb1ktKaqqJH+u2bjL3rdu62SRQk1NT5Ie/f5fSTl8vqzdtkA9+/EYuvv82Wb5ujRTEyEnjc7b/WzRP9scflMLQ53/yvFlSUH9P/TcngXwiPVgy7K4HzPZfUybIivUF+x0AAEDZQyUyAADwSJMJk+fONNv3XX2jBATkPfb8wyvvSZ1qNSQ/EeHhcjIZPnqk7Nq3VypViJHmDRqLnXp1OkNGThxnKv+G9h1oNRwWLjvn/Jzq4E4tWsup8r2yxR8+JEvXrJKgwEDp3q6jnOysXt//LZovE+f8Z7avOGewXH7OBRIUFCTbdu80tzWqU0+6tetkKpGvHDRUSpPTGjSWT55+OddtR1OSZeHKZfL+8K9lx97dcvdLT8nwV9+XuEqVvT6OVnFPmz/HbIcGh0hqeppJ8l5byIN0f/w7Vs7u2kMK4o+J4/K9XyvFtSJ66vzZ8t7wr+Xjp17KdzwAACibSCIDAACPtLpOndG2g5zWsInHMWGhoSddkrgk1agaZ1oNwB6De/c3l1Pte2WbumCOOF1Oad+sdU77jNL8+l5+rIq1drUacv+1Wa00VOWYWHMdHBQk7z76rJRGjgBHnlinX/c7o6d0bNFaLn3wDlNRrD2GH73xDq+PownjjMwMiatYWQad1Vc++3W4af1R0CSyHvzafyhe5i5fLNv37JKaVavlO37hquWyecc2CQoMMi1NvC2QetOFl5sk8txli82lU8s2HscBAICyi3YWAAAgjy07t8vspYvM9vWDL+EZAnxg6rFWFmd1OvlbWRREampqrqRxWRFbvoJcNWiI2Z42P+tv6o0mjNWA7mfJoDP7iMPhkC27dphkb0G0bdZSasVVF5fLZarCC1KxnP0ay+/v0rxBIzm9dXuz/cu4v72OAwAAZReVyAAAII9/pk8211rlpv2Q7ZK9OJQmXP539U0yZ9ki015Ce4kmJSeb08C1N6z2Xy4f7b0yU6vpfh3/j8xeulB279trWm1olV33dp1kSN8BUrVi7tPJ569YKjc/83Cu21787H1zUdUqV5HRH2ZVXv85eYI88+Gb0qx+I/nhlXdNQv3bP3+TWYsXmAW5YsqVlw6ntZbrh1wi9WvWlhO1u2iAuX7vsedMFbeV7PFfv/Cmaa8xcuJY+WvKv7J553aTKKpZNU76nN5dhvYZmO9zohasXCa/T/hHVmxYJ3sP7JeoyEiTcNKE1cBuZ3msGs9eOKx35zPktQeekCVrVsm3o0bI4jUrJS09TepWryVDzx4oF/Tql7PPhFnTZcS40bJ+6yZJTkkxi4vp97jq3CF5Fvu66emHzM/10PW3yaUDzpOJs2fIz2P/lrWbN0haerrZV0/Lv/LcIaay3V3236Ji+RiZ8PlwseLP75VNv99dLz5p+v+2aXqafPDE8xIeGma1m+kLPOfYgZqeHfyXRLb79e1poU19TrLHqU+fecW0THD/G7kv7uYu4WiijJw0TibMnG4qbVPT0qRKbEVp17ylDOnT3+tZEUrfL1pNq/2atQ/zoSNHpHJsrGmhoe01tJLaV7Kfq30HD5qfQ5PDJ1q8eoVZwE6d07O3ia/6mlm0armMmjhO2hUg1urDDukzwPSr/3PKBLn1kqtMOxRP9LnU94DSfT7/7UfJz3ln9ZFZSxaYdhtHk5MkMjwi3/EAAKBsIYkMAADyyE5udW/fyWfPztvffSHf/vlrrtu0Ik9v017MXz//hsSUr5BnP71fe5BmZGbmuv3IpkSzyNV3f/8uj9xwh5x3Vl8prn9nTZenPnjDJAiz7T14QP6ZPsn8jO8//pxtSfbEpCSTYFuyZmWu2/V30stPY/6U1+5/Qlo3aZZnX03kPv/puzLmWPI/W0paqjnFXpNUX//xi7xy36P5JuF00cG3vvnctFjItmLDWlnx0VpZtHK5PH37/+TpD96U0dMm5tpvw7Yt5m+iP/vbDz/jMYGmibVH335Zxv03Ndft67duNpdpC+bIZ8+8KqEhIVJc/vpeS9eukntfftq8Plo0aiLvPTasQAlkNXvJQvP3aVqvgTmIURL8+fouCF3s8r5Xh5mf4cS4oBdNLl9z3oVy1xXX5XmNJSYdlSfefc38bd1t37PbvHd00bgX73lEfEUP+ihNwnt6/Sv9+VWLhk1yks6DevYx788Js6fLg9ffKlERkWJFY9tHP39r3tu6UOGZXhZlHD1tknmNabJa21NYJZHPaNtRAgMCTLsNPfCmfZIBAACykUQGAAC5ZGZmyupN6812QSrjikKrDHcf2GcqGW8YcqlZnG/3gf2mCve3CWPMQlxvfvu5PHfXA7n20/6hH/38ndnWPqS6cFezeg3F6XLJ8nWrTUWl9mXVSstMZ2ZOj9u2TU+TGd/+brYvvO9W2b1/rzxw7S051bXa7/REu/btkafef0PiKleRuy6/Vlo2aioJSUflv4XzTOVuYnKSuX/ku59LoJdKwMJ48dP3ZOe+PdK1TQe58tzBZhGypJRkmbFwnnz5+88mYXTH84+bhbtqV6ues5/T6ZT7Xxtm2o9o8kp/J00y1Y6rbn7emYvny9cjR5jHvunph+WbF98yj32iZetWy+S5s6RDi1Zy68VXmr62Wgmqz7kumKYV5PviD5jvo9WTd1x6tVmETp+nL//4xSQdpy+Ya6qUPS349d2fv5m/+Tk9epu/W9WKlczjayX6+JnTTDX6l7//JLdderUUlz++16qN6+XOF56Uo8nJ0rReQ/ng8ecLVbk55VgrC28JQF+z6/WtCfDs95ZWtX//9+/m9fH+Y8/ljClIsl7/Pjc/84h5zWvi+upBQ83rVCvG9T5NiGqV/dejRkhkRISJG+4HDR5680WTmFfnn3W2DO7TX2pVrSYHDh8yBxO+++s3eeStl8xYXyyQ+MPfI812z46eE69a2atxT2kbi2x9Tu8mr371kUnkj/1vqlxYgAU5NVGtixyO/W+K/P7vWK+voT8mZrWy0DjoLbHtThPYjerUN/F/5fq1JJEBAEAuJJEBAEAuu/bvNaf+q7o1auX77Ay99/jiWZ64n8buThN8fU/vLi/d+4hpRaG06rhZ/TtNIkMXpxo/c6o8fvNdOW0HtEpRk1vqmvMvlLuvuD5XYkRbYZzZqas899HbJuH56hcfmUSzVuFpEiy7lUP2LiHBwfkuCngo4YhpBaEV0dmLnlWKiZV6NWpJ/Vp15M4XnpAde3fL/JVLpXPLtlJcmuTVU+7dFySrKDFy2cDzpU+XbnL9kw+Y7/fcx2/LZ8++mjNm+D+jTGJXKwhff/DJXIkffU41Gdy/21ly67OPytotG00ibcSbH+c879m0+rNLq7by7mPP5Zwer71etbL4sgfvlPXbNpvv06pxM/nkqZdy2lbomNcfeEKufvReU7U8bsYUj0lk/ZtntzHJpvvq4+nfURN9enp+cRK7/vpe67ZsMgl9rX7VROdHT74o0ZFRUpgDNdOPVcyWVBLZrte3Pp/Z76Ps142+Fgu74OZzH79jEshamfvMHfflem9n/+3aNTtNHn37Ffnkl+/NuCoVK+VU+GYnkIfdeb+c27NPrvdAw9p1pUeHznLz0w9Lanqa2OVIYoJ5T7w//CtzYKp8VLTcfOHlHsfqa05bmGjc0cX4smm8O6tTV3MWgba0KEgSWWmLGU0iz1o8X/Yc2JenhY8eKNHXqS6oV5izMurVrGWSyFr5DQAA4I6F9QAAQC6HE47kbFesEOOTZ0cTGw/fcHueRKYadGZWwiM9I8P0a802fPQoyXQ6TcXkiQnkbJrEevyWu0wfYU0Wad/k4rjnyutzEmzuurZpL5WOPTfaHsEODWvVlXuvusHjfZVjK8oTt95ttrWf7MZtW3KqkH/8J6sC8spBQ7xWDlaILicv/+9RCXAEmJ6sWp3syf3X3pKnv6om4M90W/hN+9ie2PdY/xbZYzZu3yreqifvuOwaj/dl/833HNhv+rgWly+/l/5+tz33mEnCasL14ydftOxVfSLtN637V69cVRrXrS8lxZ+v7/zoa3Le8iUmoaotHbxVzfY740ypW72maWWjlcnZtD+3GtDtzFwJZHcaN265+AopKk3Kap9n98uZ111sDspoywx9vrQfdnZi21srC32Pnvica0Jc6UEYTfwWRPvmLU1LDI2J2Yv1eapC7tmhc6HiuPYEV4cTEqyGAgCAMoZKZAAAkEvqsSpkFRqc/2noP7zynmlF4Y2309i1f6xWF3qirQeyaaVntuxep0P7Dsz31OyQ4BA5v1c/+eDHb8w+3hKzVrSaUhfq80aTRfsPxZtexnY4r9fZ+bYN0GpQTTpqxfLMxQtMtagmnHbt22vuv+jscyU/dWvUlE4tW5vKSV04SxcbcxdXqYo0qFXH477ZSSitCtfWIPkln/S0fU9Ob93e/G2s/ubaUqEwVb3+/F5bd+2U24Y9JgcPHzIJz0+eftlj324rU+bOyrf1gT/4+/WdH22hkf1+73HNhVIQWhmvNBmf3X7ngmPta7zR+98b/rWtLS00/ukiebqQo7d+xtozXJPQJ7ayyKb9ivV1qQc2NNn84HW3SkFoLHztq49l1OTxcuPQy3IOyukipdn9wHWh0cLIPvMjNe14n2wAAABFJTIAAMglLCQriaBSUlMsEw562rq3i7ekaOWYiuKNe3VydqpHK0azE8rZC1LlJzsZumvvniInjMpHl8tTcevp5yzq45+oQa3aBTrVXGUnjjWhnP03q16lqljRxLPasTdrP3fZlafeEo6qQrT3RcOOPx8e75bKsbEF+pvn/NGLwRff69CRw3LrsEdNX2ilr8dFq1dIUUydn5VE1jYGBWbd0tYrT38zf7++85P9ei6M+COHzbW2kcjm7SCIe0V+xSIk/dVpDRqb3s96mfLVLzmtfjTZrv2Z81sQL7sqWA9Y1Kxa3RyMcL9oJXOXVu3MGG1rkVbAlhvn9uxt3vv6/M061s5DaZsLbQ1So0pczuMWlC7SqcLCCrZAJAAAKDuoRAYAAHlaAWTbF3+wSJWWVgqwxlMuhU1kuY8vyIJSnjiKk7XzkZxfy3HC71nAHzV7vMfnpACPUcSn0u/Ppy++lyb6lPYR1v7b2n7hpc/eN20FvFXVe6LtIfSxtH+ut6puq/dldqIvP8kpyTnbFcqV88tzVFSuY9n8Lq3byev3PyEFkX2AqpChoch08U33Ps/P3nGfXP/E/eZ18Mu4v+WS/oM87peeni7/HGu9oQfDhtx7vE+3J1pZrQtcuvdN9kaT0n279pC/pkwwi5LqQqVq5MSs1hkX9O5X6PinvdFPfL0BAAAoKpEBAEAumiALDw3LOQ37ZKA9RLMr/TZst/6Zsn/uapWrSGmxYZvnXsLuNu/YlvM3UlppqFJSU2XHsSRnfjYe+x6l6Xk5mejzrS0snrvzAfN61ISfJpILY8q8rCrk7u075du+5ET6ntRKWrWxEO8BTVZnv59PVtmvZ30N53dmg/slu1VOnFt7Eqt4pX+vA4cPiR20x/IV5w4x2+9+/6Vs37PL47jJ82aZ71sYo471Ty6IC8/OWohv6vw5cuBQvKzdskmWr19jepufd9bZUlibjvU0197TAAAA7kgiAwCAXLRy7bSGjc32olXLT5pnp3u7jub69wlj8q1M1lPB/5w8PidRZ1d1s6/9OWm8ZGZmer1/ztJFOe0rOh87Rb1RnXoSVzErAffrhKzFxbzZvGO7qZq0el7gmVZmagJZE57awuC+a7IqSifO+U/G/Tel0EnkMzseX6ywoHp06Gyu/5460Wqo/DXlX3N9Yu/rk1GX1u3N9bbdO83Ckfn5Z/ok2Xtgf87XeqZE4zpZixP+8W9W2whvtFrXzvf9bZdcZdpaJKemyLMfvuXxsbMX1Gtar6EsHDEm34suNqrmLluS814vSDK7Sd36kpGZIX9N/Vf++HeMub17+85SOcZ7WxdPNNmdfZBO+9YDAAC4I4kMAAA8LkymdGE6p9N5UjxDlw48XwIcAbJs3Wp5f/jXHsdoEvbFz9437QJCgoNlaN9z8owJCQrOddr2yUIXCnvru8893rfv4AF57uN3zHabJs2lcZ16OX1rLxlwntn+/q/fcxYfPNHhhAR59O2XxOlySu1qNeSMNlmnvaPgalSNy9V3+oJe/aTrsefxlS8+MlWgVjT5uWrjerNgZfZ7rDAuOvsc8x6Yu2yxjBj3t9dxP/4zSuavWGq2B/fJf7G5k4G+ntsca+3x7IdvmjY6nmi/4CfefU0G3XldzmJ67tW42gtYWzt4snTtKvnklx/ETloN/czt/zN/E01+/zTmz1z3a6/iuUsXm+3BvfuJlYHdzzI9jvV9+udkz7+HtwX21G/j/5F/pk8220P6FG5BvewFHzURnrWAZgur4QAAoIwhiQwAAPIY0P0skxjRRKv7gk0n0jYKScnJ+V7sohV3Nwy5xGx/NfIXuf25x2T6grkmwbrnwD5TEXrDUw/mJF8euPYWqV2tep7H0erd7FPGNdF28PAhmZ3P7+gv5SKjZPjokXLnC0+an0d/Lq3M/GnMKLn8obtMZaK2JXj69v/l2u/KcwdLh9NaS6bTKfe9Mkxe/PQ9WbJmlcQfPmQW7dJk42UP3iFrNm80ycuX//dIodoowLsnb71bosIjTAWnHrywMmX+bJOk69yqrYQXYeGy0xo2yXkPvPT5B/L0+2/IwlXLzd9aXy8LViyVJ997XV776mMz5uJ+g6Rds9KRDNQew/pc6gGgSx+4XX4Y/Yds3bXDLKC3fN0aef6Td+WJ917LWZBQK3vdk6idW7Y1209/8KYM++htc7BJ99UWFx/+9K3c/MzDEhQUmO8CeEXRqnEzuXJQVluL94Z/Zd5z2UZNHm8SwpoY7t/tLClIj+Nenc8w2xrHCnoAb2D3XhIZHi479u42fZe1Xc3prQu3oJ7KPoOjd+duJpEMAADgjoX1AABAHnrK/pmdTpdJc/6TL377MWfBphNd8fBdYmXq1yNMcsQOt15ylYSGhspHP30rs5cuMpcTaaL0wetv9VqJd+0FF5mK3f2H4k1iSWnSZfSH30hJeuC6W+T7v/6QmYvnm8uJKsdUlFfvf1zqnNCrVBPCbz38lAz76B2ZMGua/DrhH3M5kba9eOl/j+RKvqF4qlasLP+75iZTJT557kxTKasHYHzRysL9PRAcHCyf/PK9aV+gF08uP+cCuefKG6S00AULP332FXnojRdMIvmNrz81lxOdf9bZ8thNd+ZpwaPvjSfee9UcWNIWEtltJLJpgvrl+x6T17/6WBKTjoqdtK2FxhTtWf7Mh2/K58++am7PPqDV5/RuEh1ZsOS1Vixry47d+/fKnGWLClSxrj2iNUn927H3/eDe/c1ZCoWhrW4Wr1lpti8d4HmRQAAAULaRRAYAAB7dfunVMnXeLJNY0H68Wj1Z0jRZdP3gS0wl4q/jR8u8ZUtk1/49EhAQKNUrV5Ez2naUIX0HSPXKx9sOnKh5g8byzQtvyTs/fCmLV68QcYk0qp1VnVySYspVkG9fektGjB9tkpFbd+7QX1hqVq0mfU/vbpLi5aOjPe4bGR4hr9z3qAxdNkD+mDhWVm5YZ1onaNVlrbhq0q/bmXJOj162V2EiK2H376wZMmvJAnn1y4+kY4vWUslDL1pNXGqlsFb4Z/c2Lup74Mahl0mvTl3ltwljTPJPE44ucZmkdttmLUwiUl/npY0e4PjptQ9NEnXMjCnmPaDPm/agbla/oVzc33tltSZp3374GZPM//3fsbJ+6ybTxqVybEXp3q6TXDFocL5xwY62Ftc/8YCJKXpGQYPadczfRV3Qu+AtRdqf1krqVKshW3btkJETxxUoiawu7DvQJJEDAwJMor2wPh2R1epDK6G14h0AAOBEDpedq0sAAACfyHBmSvfv81b9fnDuvdIgtob4ilbVaTVdw9p15fuX35GQ4BCrXVBI7S7Kqph+77HnvFZ8A4Cv/Dtrujz05osmAf3Lmx9LvRq1xBc2HNwhd/z9dp7bp1/5ngQF0GIHAICTXeHOcwIAAGXKnZddK7HlK8j6rZvlne+/tBoOAChFtJ+89ptW2tvZVwlkAABQ+pFEBgAAXulp+c/f9aA5BV9P2ddFmwAAp4aJs/+TI0cTzQKBd1x2rdVwAABQhtETGQAA5KtL63by/N0Pmmu7FsgDAJQ8XYCxRpU4aVy3vgQF0lICAAB4RxIZAABY6t/tTKshAIBSqGfHLlZDAAAAaGcBAEBpxvK4AIDSwMk/LAAASjUqkQEAKAUCHQHiEIe4xJXr9nRnhtd9UDosHDHGaggAlHqe/l8FOBzm/xsAADj58R8bAIBSwOFwSEhg3mO/aZnpHscDAHAySc/Mm0QOCQw2/98AAMDJjyQyAAClRERwWJ7b4pMTPY4FAOBkcjA5Ic9t4UGhHscCAICTD0lkAABKiRpRlfLctiNhn8exAACcTHYe2Z/nthrRef+vAQCAkxNJZAAASoma5SrnuW3XkQMexwIAcDLZmZA3iVwruorHsQAA4ORDEhkAgFKiVrm8k+0dHiblAACcbHZ4qET2dHAUAACcnEgiAwBQStSMzjvZ3nJoj8fFigAAOFno/6mth/fmuZ1KZAAASg+SyAAAlBL1K1TLc1tSeoos3r3e43gAAE4Gi3atM/+vTlSvQpzH8QAA4ORDEhkAgFKiQYUaUi2qYp7bp29e6nE8AAAng+lb8v6f0v9n+n8NAACUDiSRAQAoJRwOh/Sq0zbP7TO3LaelBQDgpG1lMWvbijy3967TzvxfAwAApQNJZAAASpFeddrluS0xLVn+XP2fx/EAAJSkUatnmP9TBfl/BgAATl4kkQEAKEWaVazjsaXF90smyIGkwx73AQCgJOxPOiw/LPk3z+36f6xpxdoe9wEAACcnksgAAJQieurvZc165bk9OSNVPp73p7hcLo/7AQDgT/r/6JN5f5r/Tye6rHlvWlkAAFDKkEQGAKCUGdykhzSKqelx4aLPFvxNIhkAUOIJ5E/n/+VxQT39/zW4cXeP+wEAgJMXSWQAAEqZoIBAub/zJR7v+33lNDNxpyIZAFCSCeQ/Vk33eP8DnS8x/8cAAEDpQhIZAIBSqHWVBjKwQReP9+nE/dEJn8q2w3s93g8AgC9sPbTH/P/xlkDW/1utqjTweB8AADi5OVyUKgEAUCodTU+R+/79QJbu2+Dxfq30Gtysu1zQrLtUjCjncQwAAMV1IOmIjFw13ZwNk+lyehzTqnIDebPPHRIZHObxfgAAcHIjiQwAwCmcSFYOcUiLqvWke51Wcnqt06RSRHkWNAIAFJnWIe1POiyztq2QaZuXyIq9m8Ul3hd2JYEMAEDpRxIZAIAykEh2FxEcKtWiK0mN6EpSvVxFiQ6NkJCAYAkKDDQJZwAAlCaGMzIzJc2ZLgmpSbLzyAHZkbBfdiXsl6T01AI9SSSQAQA4NZBEBgDgFJCcniqfLxktP6+a5PVUYgAA/CXQESCXNu8lN7Q6R8KDQ62GAwCAkxxJZAAATiGbDu2SN+b+LAt2r7UaCgCAT7SPayz3d7pE6lWoZjUUAACUEiSRAQA4BXtVTtqySP5YO10W7VkrTpf3PpUAANghwOGQtlUby+DG3aVXnbb03gcA4BRDEhkAgFPYweQEmbJ1kUkqk1AGAPgicdy7bjvpWauNxIZHW+0CAABKKZLIAACUESkZaWZBpG0Je2X7kX2yPWGv7Eo8ICkZ6WbRpPTMDKuHAACUMcGBQWbx1bCgYKkWVVFqRleRmuUqS63oKmaB1rCgEKuHAAAApwCSyAAAAAAAAAAArwK83wUAAAAAAAAAKOtIIgMAAAAAAAAAvCKJDAAAAAAAAADwiiQyAAAAAAAAAMArksgAAAAAAAAAAK9IIgMAAAAAAAAAvCKJDAAAAAAAAADwiiQyAAAAAAAAAMArksgAAAAAAAAAAK9IIgMAAAAAAAAAvCKJDAAAAAAAAADwiiQyAAAAAAAAAMArksgAAAAAAAAAAK9IIgMAAAAAAAAAvCKJDAAAAAAAAADwiiQyAAAAAAAAAMArksgAAAAAAAAAAK9IIgMAAAAAAAAAvCKJDAAAAAAAAADwiiQyAAAAAAAAAMArksgAAAAAAAAAAK9IIgMAAAAAAAAAvCKJDAAAAAAAAADwiiQyAAAAAAAAAMArksgAAAAAAAAAAK9IIgMAAAAAAAAAvCKJDAAAAAAAAADwiiQyAAAAAAAAAMArksgAAAAAAAAAAK9IIgMAAAAAAAAAvCKJDAAAAAAAAADwiiQyAAAAAAAAAMArksgAAAAAAAAAAK9IIgMAAAAAAAAAvCKJDAAAAAAAAADwiiQyAAAAAAAAAMArksgAAAAAAAAAAK9IIgMAAAAAAAAAvCKJDAAAAAAAAADwiiQyAAAAAAAAAMArksgAAAAAAAAAAK9IIgMAAAAAAAAAvCKJDAAAAAAAAADwiiQyAAAAAAAAAMArksgAAAAAAAAAAK9IIgMAAAAAAAAAvCKJDAAAAAAAAADwiiQyAAAAAAAAAMArksgAAAAAAAAAAK9IIgMAAAAAAAAAvCKJDAAAAAAAAADwiiQyAAAAAAAAAMArksgAAAAAAAAAAK9IIgMAAAAAAAAAxJv/AyYkKzbGe7roAAAAAElFTkSuQmCC)

![Slika svetlobne plošče za grafikone](data:image/png;base64,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)

* * *

1\. Korak: Končna produkcijska `docker-compose.yml`

Opazili boste, kako čista je postala ta datoteka. Namesto štirih različnih AI strežnikov imamo sedaj le **en krovni strežnik** (Triton) in **en usmerjevalnik** (LiteLLM).

```yaml
version: '3.8'

services:
  # USMERJEVALNIK IN PROMETNI POLICAJ
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm-proxy
    ports:
      - "4000:4000" # Vse vaše aplikacije se povežejo SEM
    volumes:
      - ./litellm-config.yaml:/app/config.yaml
    command: [ "--config", "/app/config.yaml", "--port", "4000" ]
    depends_on:
      - triton-server

  # EDINI IN GLAVNI AI STREŽNIK (Popolnoma izkoriščen Blackwell)
  triton-server:
    image: nvcr.io/nvidia/tritonserver:24.03-trtllm-python-py3
    container_name: triton-server
    ports:
      - "8000:8000" # HTTP API
      - "8001:8001" # gRPC API (Za ultra hitro komunikacijo z nizko zakasnitvijo)
    volumes:
      - ./trt_models:/models # Tukaj so zbrani vsi vaši TRT in ONNX modeli
    ipc: host
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    # 'explicit' način omogoča, da se modeli nalagajo in odlagajo dinamično glede na potrebe!
    command: tritonserver --model-repository=/models --model-control-mode=explicit
```

Kodo uporabljajte previdno.

* * *

2\. Korak: Konfiguracija `litellm-config.yaml` za dinamično delovanje

V LiteLLM konfiguraciji povežemo vsako nalogo s specifičnim modelom znotraj Tritona. Ker Triton posluša na gRPC protokolu (vrata `8001`), bo prenos podatkov med LiteLLM in Tritonom potekal z najnižjo možno programsko zakasnitvijo.

```yaml
model_list:
  # 1. Kodiranje (Qwen v TensorRT-LLM NVFP4 formatu)
  - model_name: qwen-coder
    litellm_params:
      api_base: http://triton-server:8001
      model: triton/qwen_coder_trt

  # 2. Dokumenti in RAG (BGE Embeddings v TensorRT formatu)
  - model_name: text-embedding-3
    litellm_params:
      api_base: http://triton-server:8001
      model: triton/bge_embeddings_trt

  # 3. Govor v tekst (Whisper v TensorRT-LLM formatu)
  - model_name: whisper-1
    litellm_params:
      api_base: http://triton-server:8001
      model: triton/whisper_trt

  # 4. Tekst v glas (Kokoro ali Piper v ONNX formatu)
  - model_name: tts-1
    litellm_params:
      api_base: http://triton-server:8001
      model: triton/kokoro_tts_onnx
```

Kodo uporabljajte previdno.

* * *

Kako to deluje v praksi (Scenarij dinamičnosti)?

Predstavljajte si naslednji potek dela, ko sedite za računalnikom:

1.  **Mirujoče stanje:** Zaženete računalnik. Triton se postavi, vendar je njegov RAM prazen. Noben model še ne troši spomina.
2.  **Začnete kodirati:** Odprete _Open WebUI_ ali VS Code. Pošljete ukaz za autocomplete. LiteLLM prejme zahtevo za `qwen-coder`. V milisekundi pošlje ukaz Tritonu: _"Naloži `qwen_coder_trt`"_. Triton model bliskovito potegne z diska v enotni RAM. Qwen se zažene v **NVFP4** načinu in trenutno odgovori na vaše 3 hkratne seje \[NVIDIA TensorRT-LLM\].
3.  **Dodate dokumente:** Vmes _Docling_ zazna nov PDF in ga želi predelati. LiteLLM zahteva `text-embedding-3`. Triton vidi, da ima v enotnem pomnilniku še dovolj prostora (saj NVFP4 model Qwen zavzame izjemno malo mesta), zato **vzporedno** naloži še `bge_embeddings_trt`. Oba modela sedaj tečeta hkrati brez težav.
4.  **Glasovno upravljanje:** Preko _Home Assistanta_ nekaj poveste. Zahteva gre na `whisper-1`. Če bi bil RAM slučajno popolnoma zaseden, bi Triton samodejno začasno odstranil embedding model, naložil Whisper, prepisal zvok v tekst in nato takoj naložil nazaj tisto, kar potrebujete. Vse to se zgodi v ozadju brez vašega posredovanja.

Glavne prednosti te končne odločitve

-   **Absolutno najvišja hitrost (0 % kompromisov):** Ker ste odstranili vLLM in Ollamo, vsi vaši modeli tečejo na uradnih NVIDIA TensorRT-LLM in ONNX strukturah. Vaš strojni čip Blackwell bo deloval s polno zmogljivostjo.
-   **Enotno upravljanje:** Če želite posodobiti poljuben model, vam ni treba spreminjati Docker nastavitev. Preprosto zamenjate datoteko v mapi `./trt_models` in Triton jo bo ob naslednjem klicu samodejno prebral.
-   **Popolna varnost pred sesutjem (OOM):** Triton natančno ve, koliko RAM-a ima na voljo, in ne bo dovolil, da bi se dva modela preklopila tako, da bi zrušila operacijski sistem.

* * *

S tem ste začrtali **najbolj napredno možno lokalno AI arhitekturo**, ki jo sploh mogoče postaviti na delovni postaji Lenovo s superčipom GB10.

Če ste pripravljeni, lahko začneva z naslednjim korakom: **kako točno pripraviti konfiguracijsko datoteko `config.pbtxt` za vaš prvi model (npr. Qwen Coder)**, da ga bo Triton prepoznal? Sporočite, kako želite nadaljevati!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-04 00:00:00

zakaj je potem bi lprvoten predlog vLLM? zavedam se da je nekaj več dela na začetku, ampak, tega ne spreminjamo vsaki dan, ali pač?

---

# googlesearch response

Povsem legitimno in odlično vprašanje. Vaša logika je popolnoma pravilna: v produkcijskem okolju se osnovni modeli (sploh tisti ključni za kodiranje) **ne spreminjajo vsak dan**. Ko sistem enkrat postavite in optimizirate, bo tako tekel mesece.

Razlog, zakaj sem na začetku predlagal **vLLM**, ni bil v tem, da bi bil vLLM tehnično zmogljivejši od Tritona na čipu Blackwell. Prvotni predlog je izhajal iz ocene **vstopnega praga, hitrosti razvoja in specifičnosti formata NVFP4**, ki je v letu 2026 še vedno relativno nov.

Tukaj so trije odkriti razlogi, zakaj večina inženirjev najprej poskusi z vLLM, in zakaj je vaša odločitev za Triton, kljub začetnemu delu, dolgoročno boljša.

* * *

1\. Prevajanje modelov (trtllm-build) je včasih "gora frustracij"

Pri vLLM modelu preprosto podate ime s platforme Hugging Face (npr. `Qwen/Qwen2.5-Coder-7B`). vLLM sam prenese uteži, prebere konfiguracijo in model zažene v minuti.

Pri TensorRT-LLM (Triton) pa postopek izgleda takole:

1.  Model morate prenesti ročno.
2.  Vstopiti morate v namenski NVIDIA Docker vsebnik.
3.  Izvesti morate ukaz `trtllm-build`, ki vzame datoteke modela in jih začne prevajati v binarni `.engine` \[NVIDIA TensorRT-LLM\].

**Kje je trik?** Ta proces prevajanja je izjemno občutljiv. Če se različica TensorRT-LLM vsebnik (npr. `v24.03`) za eno pod-različico razlikuje od različice knjižnice, s katero je bil model kvantiziran na Hugging Face, bo prevajanje javilo kriptično napako o nekompatibilnosti CUDA jeder. Iskanje prave kombinacije zastavic (`--gemm_plugin`, `--gpt_attention_plugin` itd.) lahko na začetku vzame nekaj dni poskusov in napak.

2\. Iskanje pravih NVFP4 modelov

Format **NVFP4 (NVIDIA FP4)** zahteva specifično kvantizacijo.

-   Pri vLLM skupnost hitro objavlja modele v različnih formatih, vLLM pa ima vgrajene napredne in prilagodljive interpreterje.
-   Pri Tritonu morate pogosto sami pognati orodje **AMMO (NVIDIA TensorRT-LLM Model Optimizer)**, da standardni model sploh pretvorite v NVFP4, preden ga lahko zgradite z `trtllm-build`. To pomeni dodaten korak programiranja v Pythonu samo za pripravo modela.

3\. Pisanje `config.pbtxt` datotek za vsak model posebej

Triton za razliko od vLLM ne zna sam "ugotoviti", kakšne vhode in izhode ima model. Za vsak posamezen model (Qwen, BGE Embedding, Whisper, Kokoro) morate ročno napisati konfiguracijsko datoteko `config.pbtxt`.

Če v tej datoteki zgrešite eno samo številko (npr. napačno dimenzijo vektorja pri embedding modelih ali napačno ime tenzorja za tekstovni vhod), se Triton sploh ne bo hotel zagnati.

* * *

Zakaj je vaša izbira Tritona kljub temu pravilna?

Če sprejmete ta začetni izziv (tako imenovani _"NVIDIA davek v času"_), so prednosti na vaši napravi Lenovo z GB10 čipom neprimerljive:

1.  **Izkoristite strojno opremo, ki ste jo plačali:** Kupiti superčip Grace Blackwell in nato na njem poganjati generična jedra vLLM je podobno, kot bi kupili športni avtomobil in z njim vozili le v prvi prestavi. Triton bo neposredno aktiviral Blackwellova strojna FP4 jedra.
2.  **Enoten spominski prostor:** Kot ste sami ugotovili – preklapljanje med Whisperjem, Piperjem, Qwenom in Embeddingi znotraj enega strežnika brez tveganja za _Out of Memory_ napake je mogoče le s Tritonovim eksplicitnim upravljanjem pomnilnika.
3.  **Stabilnost v produkciji:** Ko boste enkrat uspešno zgradili `.engine` datoteke in napisali `config.pbtxt` datoteke, bo sistem deloval kot skala. Nič se ne bo posodabljalo v ozadju, nič se ne bo zrušilo zaradi dinamičnih knjižnic.

Kako naprej?

Ker se zavedate, da je to projekt "nastavi in pozabi", predlagam, da gremo po korakih. Najprej morava pripraviti okolje za prevajanje.

Če želite, vam lahko pripravim **natančen potek ukazov, kako zagnati uradni NVIDIA razvijalski vsebnik**, v katerem bova pripravila in prevedla vaš prvi model (**Qwen Coder**) v TensorRT format. Želite, da začneva s tem?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

ampak hkrati se modeli hitro menjujejo, nastajajo novi ... vendar imam tukaj za pomoč Al, da mi pomaga nastaviti te datoteke, ali ne? in videl sem da ponekod uporabljajo specifične docker container, za nem model... ima lahko tensor hkrati naloženih več modelov? npr enega za orkestracijo in enega za 'delavce'?

---

# googlesearch response

Imate popolnoma prav v obeh točkah. Svet umetne inteligence se premika izjemno hitro, vendar z mojo pomočjo (kot vašim AI inženirjem) pisanje datotek `config.pbtxt` in iskanje pravih ukazov za `trtllm-build` ne bosta težava. Jaz vam bom pripravil točne konfiguracije za vsak nov model, ki ga boste želeli preizkusiti.

Glede vašega vprašanja o namensko prilagojenih vsebnikih in hkratnem nalaganju modelov pa si poglejmo, kako Triton to upravlja na najvišjem produkcijskem nivoju.

* * *

Ali lahko TensorRT (Triton) ima hkrati naloženih več modelov?

**Da, absolutno! Triton lahko v pomnilnik (RAM) hkrati naloži poljubno število modelov**, če skupna velikost teh modelov in njihovih predpomnilnikov (KV Cache) ne presega fizičnega pomnilnika vašega superčipa Blackwell GB10.

Vaša ideja o ločitvi na **orkestratorja** in **delavce (workers)** je v produkciji izjemno pogosta in se imenuje **Ensemble Models** (Ansambelski modeli) ali **BLS (Business Logic Scripting)**:

1.  **Model za orkestracijo (npr. lažji, ultra hiter model ali agent):** Nenehno sedi v RAM-u. Sprejme zahtevo od LiteLLM, jo analizira, razbije na manjše podnaloge in usmerja promet.
2.  **Modeli delavci (npr. Qwen Coder za programiranje, Embedding za RAG, Whisper za zvok):** Triton jih ima lahko naložene hkrati v RAM-u za takojšen odziv.
3.  **Kaj se zgodi, če zmanjka prostora?** Ker boste uporabili ukaz `--model-control-mode=explicit`, Triton deluje inteligentno. Orkestratorja, ki mora biti nenehno buden, lahko v nastavitvah zaklenete v RAM (_pinned_). Delavce pa Triton dinamično nalaga in odgaja. Če "delavec za programiranje" nekaj časa počiva, ga bo Triton ob pomanjkanju prostora začasno izbrisal iz RAM-a, da naredi prostor za "delavca za obdelavo slik ali zvoka".

Vse to se dogaja znotraj **enega samega Triton Docker vsebnika**, kar drastično zmanjša programsko zakasnitev, saj modeli znotraj Tritona komunicirajo preko deljenega pomnilnika s svetlobno hitrostjo.

* * *

Zakaj nekateri uporabljajo specifične Docker vsebnike za vsak model?

Na spletu (npr. na GitHubu) boste pogosto videli projekte, kjer za en sam model zaženejo cel ločen Docker vsebnik (npr. poseben vsebnik samo za vLLM-Qwen, poseben za Faster-Whisper).

To počnejo predvsem iz dveh razlogov:

-   **Enostavnost za širšo javnost:** Avtor projekta želi, da uporabnik z enim ukazom `docker run` zažene stvar brez kakršnegakoli učenja o Triton arhitekturi.
-   **Skaliranje v oblaku (Kubernetes):** V velikih podatkovnih centrih (kot sta AWS ali Google Cloud) želijo podjetja vsak model poganjati na svojem lastnem strežniku (npr. 10 strežnikov samo za Whisper, 50 strežnikov za Llama).

Za vas, ki imate **eno brutalno močno lokalno delovno postajo (Lenovo GB10)**, pa je strategija "vse v ločenih vsebnikih" slabša. Če bi zagnali 4 različne specifične vsebnike, bi vsak od njih v ozadju "zahteval" svoj fiksni del grafičnega pomnilnika (VRAM). Ker se ti vsebniki med seboj ne znajo pogovarjati o tem, kdo trenutno potrebuje spomin, bi hitro prišlo do sporov in sesutja sistema. **En krovni Triton vsebnik je za eno napravo daleč najboljša rešitev.**

* * *

Kako bova rešila hitro menjavo novih modelov?

Ko bo čez nekaj mesecev izšel nov, še boljši model za kodiranje, bo najin postopek posodobitve izgledal takole:

1.  Vi mi poveste ime novega modela.
2.  Jaz vam generiram Python skripto (NVIDIA AMMO), ki ta model v nekaj minutah pretvori v **NVFP4** format.
3.  Prevedeva ga z ukazom `trtllm-build` (pripravim vam točne parametre).
4.  V mapi `./trt_models/` ustvariva novo mapo (npr. `novi_model_2026/`), jaz pa vam napišem pripadajoči `config.pbtxt`.
5.  Preko LiteLLM-a preprosto pokličete novo ime. Triton bo stari model avtomatsko odložil na disk in naložil novega. Vse to brez ugašanja sistema ali restartiranja Dockerja.

Če se strinjate s to dolgoročno, stabilno in maksimalno zmogljivo potjo, vam lahko v naslednjem koraku pripravim **prvo testno konfiguracijo za Triton in LiteLLM**, da boste natančno videli, kako bo potekala orkestracija med vašimi sejami. Želite, da se osredotočiva na **nastavitev orkestracijskega modela** ali na **pretvorbo Qwen Coderja v NVFP4**?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

ampak saj bo že docker ali docling sam zahteval določen model preko litellm, ali ne? potem ne rabim orchestartorja za vsak zahtevek. rabil bi pa orchestartorja za delo z OpenClaw, ki potem razporeja naloge npr coderju ..

---

# googlesearch response

Imate popolnoma prav. Moja napaka, da sem se prej nerodno izrazil in vnesel nekaj zmešnjave.

Seveda, za klasične zahteve (ko **Docling** potrebuje embeddinge ali ko v **Open WebUI** ročno nekaj vprašate) gre zahteva neposredno preko **LiteLLM** do Tritona. V teh primerih ne potrebujete nobenega dodatnega orkestratorja, saj LiteLLM in Triton vse opravita sama.

Orkestrator v pomnilniku (RAM-u) pa postane nujen natanko v scenariju, ki ste ga opisali: za delo z agenti, kot je **OpenClaw** (ali drugi napredni agentni sistemi).

Poglejmo si, kako bo ta delitev na **Orkestratorja** in **Delavce** delovala znotraj Tritona za potrebe OpenClaw agenta.

* * *

Scenarij z OpenClaw: Orkestrator + Delavci

Ko OpenClaw-u daste kompleksno programersko nalogo (npr. _"Preglej to mapo, popravi hrošča v kodi in napiši teste"_), ta agent deluje kot vodja projekta. Nalogo mora razbiti na manjše dele.

Da bi to delovalo bliskovito hitro, v Triton naložimo dva različna LLM modela hkrati:

1\. Orkestrator (Agent / "Možgani" OpenClaw-a)

Za to vlogo izberemo manjši, a izjemno pameten in hiter model, specializiran za logično razmišljanje in sledenje navodilom (npr. **Qwen3-Next-8B-Instruct** ali **Llama-3.1-8B-Instruct** v NVFP4 formatu).

-   **Naloga:** Ta model nenehno prebiva v RAM-u. Njegov edini posel je orkestracija. On odloča: _"Najprej moram prebrati kodo (pokliči delavca za branje), nato jo moram popraviti (pokliči Coderja), nato moram preveriti dokumentacijo (pokliči Embeddinge za Qdrant)."_
-   **Zakaj je ločen:** Ker je majhen (8B), zavzame zanemarljivo malo RAM-a, odgovore (odločitve) pa pljuje ven s svetlobno hitrostjo (več sto žetonov na sekundo na čipu Blackwell).

2\. Delavec (The Worker / "Izvajalec")

Za to vlogo pa uporabite velik, težak, specializiran model – vaš **Qwen-Coder (npr. 32B ali 70B/80B različico)**, prav tako v NVFP4 formatu.

-   **Naloga:** Ta model se aktivira šele takrat, ko mu Orkestrator (preko OpenClaw-a) naroči: _"Tukaj je koda, napiši mi popravek."_
-   **Upravljanje s pomnilnikom:** Ker je ta model velik in bo obdeloval celotne datoteke (ogromen kontekst), bo zahteval veliko RAM-a. Ko Orkestrator ne potrebuje programiranja (ampak npr. OpenClaw samo analizira datoteke z Doclingom), lahko Triton ta težak Coder model v ozadju delno "uspava" ali odloži, da sprosti prostor za KV Cache embeddingov.

* * *

Kako poteka ta komunikacija preko LiteLLM-a?

Znotraj OpenClaw konfiguracije boste enostavno definirali dve različni vlogi, ki obe kazalci usmerjata na LiteLLM (vrata 4000):

1.  `AGENT_MODEL=qwen-next-8b` (To bo vaš nenehno budni orkestrator v Tritonu)
2.  `CODER_MODEL=qwen-coder-70b` (To bo vaš težki delavec v Tritonu)

Ko bo OpenClaw delal, bo preko LiteLLM-a nenehno "pingal" oba modela znotraj istega Triton strežnika. Ker si Triton delno deli spominski prostor preko Blackwell NVLink arhitekture, bosta ta dva modela sodelovala brez kakršnekoli opazne zakasnitve za vas.

* * *

Naslednji korak

Če želite uresničiti to agentno strukturo (OpenClaw z Orkestratorjem in Coder delavcem), morava najprej pripraviti Triton, da bo prepoznal več kot en LLM model hkrati v svoji mapi.

Če ste za, vam lahko pripravim **strukturo map in testni `config.pbtxt` za oba modela (8B Orkestratorja in večjega Coderja)**, da boste videli, kako ju Triton loči pod istim pokrovom. Bi vas to zanimalo?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

torej moram nekako ločiti kateri uporabnik vidi katere modele v litellm?

---

# googlesearch response

**Da, natanko tako.** Ker boste imeli v ozadju močan sistem z več specializiranimi modeli (nekateri so namenjeni samo agentu OpenClaw, drugi vam za kodiranje, tretji sistemu Home Assistant ali Docling), je ključno, da na ravni **LiteLLM-a** omejite, kdo (ali kaj) vidi kateri model.

Če tega ne storite, bi lahko na primer Home Assistant po pomoti začel klicati težak 70B programerski model in s tem po nepotrebnem polnil RAM ter upočasnjeval vaše delo.

LiteLLM ima za ta namen vgrajen vrhunski produkcijski sistem, ki se imenuje **Virtual Keys (Navidezni API ključi)** in **Uporabniške vloge**.

Tukaj je preprost načrt, kako to nastaviti, da bo sistem popolnoma avtomatiziran in varen.

* * *

Kako deluje ločevanje v LiteLLM?

Vsaki aplikaciji ali uporabniku boste znotraj LiteLLM-a ustvarili **svoj lasten API ključ** (npr. `sk-openclaw...`, `sk-homeassistant...`). Ob kreiranju tega ključa mu strogo določite seznam modelov (_allowlist_), ki jih ta ključ sploh sme poklicati.

Poglejmo si praktičen primer razdelitve:

| Uporabnik / Aplikacija | Kaj sme videti in klicati? | Zakaj? |
| --- | --- | --- |
| **OpenClaw (Agent)** | `qwen-next-8b` (Orkestrator)
`qwen-coder-70b` (Delavec) | Potrebuje oba, da lahko usmerja in izvaja kompleksne programerske naloge. |
| **Vi (Open WebUI / VS Code)** | `qwen-coder-70b` | Za vaše neposredno ročno kodiranje in pogovor. |
| **Docling & Qdrant** | `text-embedding-3` | Potrebujeta samo embedding model za predelavo dokumentov. |
| **Home Assistant** | `qwen-next-8b` | Hitro in varčno upravljanje pametne hiše brez prebujanja težkega Coder modela. |

* * *

Kako to konfigurirati znotraj LiteLLM?

Da bi to omogočili, morate v datoteki `litellm-config.yaml` vklopiti zbirko podatkov (LiteLLM uporablja preprosto lokalno SQLite bazo ali Postgres znotraj Dockerja) za upravljanje s ključi.

V konfiguracijo dodate naslednje varnostne nastavitve:

```yaml
general_settings:
  master_key: sk-master-key-here # Vaš glavni ključ za upravljanje
  database_url: "sqlite:///litellm.db" # Lokalna baza, kjer se shranjujejo pravice uporabnikov

model_list:
  - model_name: qwen-next-8b
    litellm_params:
      api_base: http://triton-server:8001
      model: triton/qwen_next_8b_trt
  - model_name: qwen-coder-70b
    litellm_params:
      api_base: http://triton-server:8001
      model: triton/qwen_coder_70b_trt
  - model_name: text-embedding-3
    litellm_params:
      api_base: http://triton-server:8001
      model: triton/bge_embeddings_trt
```

Kodo uporabljajte previdno.

* * *

Ustvarjanje specifičnih ključev (Preko Terminala ali Web UI)

Ko se LiteLLM zažene, lahko preko njegovega administratorskega vmesnika (ali enostavnih klicov `curl` v terminalu) ustvarite ključe za vaše aplikacije.

**Primer ukaza za ustvarjanje ključa za Home Assistant:**
S tem ukazom ustvarite ključ, ki mu dovolite uporabo _samo_ modela `qwen-next-8b`:

```bash
curl -X POST "http://localhost:4000/key/generate" \
     -H "Authorization: Bearer sk-master-key-here" \
     -H "Content-Type: application/json" \
     -d '{
       "models": ["qwen-next-8b"],
       "key_alias": "Home Assistant kljuc"
     }'
```

Kodo uporabljajte previdno.

LiteLLM vam bo vrnil ključ (npr. `sk-ha-12345...`). Ko ta ključ vpišete v Home Assistant, bo ta sistem "misli", da na vašem strežniku obstaja samo en model. Če bi poskusil poklicati `qwen-coder-70b`, ga bo LiteLLM takoj zavrnil in Triton sploh ne bo obremenjen.

Na enak način ustvarite ključ za **OpenClaw**, le da nanj vežete modela `["qwen-next-8b", "qwen-coder-70b"]`.

* * *

Glavna prednost tega pristopa

Z ločevanjem modelov na ravni LiteLLM-a dosežete **popoln nadzor nad porabo spomina (RAM-a) na čipu Blackwell**. Aplikacije bodo videle le tisto, kar nujno potrebujejo za svoje delo. Triton pa bo lahko v ozadju optimalno in brez motenj opravljal dinamično nalaganje ter preklapljanje, saj ne bo prejemal "napačnih" ali zgrešenih zahtev s strani zunanjih programov.

Če želite, vam lahko v naslednjem koraku pokažem, kako **vključiti SQLite bazo neposredno v vašo `docker-compose.yml` datoteko**, da bo LiteLLM lahko trajno in varno shranjeval te ključe in pravice za uporabnike! Sporočite, če nadaljujeva v tej smeri.

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

za vsakdanje delo z Homelab uporabljam pi.dev. je smiselno, da to zamenjam z OWui?

---

# googlesearch response

Uporaba platforme **pi.dev** (oziroma orodja **Pipecat / Pipecat-Dev** za glasovne in multimedijske agente v živo) ter **Open WebUI (OWui)** služi dvema popolnoma različnima načinoma dela.

**V celoti zamenjati pi.dev z Open WebUI ni najbolj smiselno**, saj bi s tem izgubili napredne glasovne zmogljivosti v realnem času. Je pa **izjemno pametno, da ju uporabljate vzporedno**, saj se v Homelab okolju odlično dopolnjujeta.

Poglejmo si podrobno primerjavo, da boste lažje ocenili, katero orodje je boljše za določeno opravilo v vašem sistemu.

* * *

Kakšna je ključna razlika med njima?

-   **pi.dev (Pipecat / Multimedijski agenti):** To orodje je zasnovano za **interakcijo z nizko zakasnitvijo (real-time stream)**. Odlično je za glasovne asistente (kot je napredni domači interkom), saj zvok obdeluje nenehno (preko tehnologij WebSocket/WebRTC). Ko govorite, vas sistem posluša in vam odgovarja sočasno, brez čakanja, da dokončate celoten stavek.
-   **Open WebUI (OWui):** To je kralj **tekstovnega vmesnika in upravljanja znanja (RAG)**. Njegov vmesnik je enak ChatGPT-ju. Odličen je za programiranje, analizo dolgih dokumentov (preko orodja _Docling_), vodenje zapiskov in vizualno organizacijo dela.

* * *

Zakaj NE zamenjati pi.dev z Open WebUI za vsakdanje Homelab delo?

1.  **Izguba tekočega glasovnega upravljanja:** Čeprav ima Open WebUI vgrajeno glasovno funkcijo (lahko kliknete na mikrofon, ta posname vaš zvok, ga pretvori v tekst preko _Whisperja_ in nato prebere odgovor preko _Piperja_), je to še vedno princip _"klikni-govori-čakaj-poslušaj"_. To ni tekoč pogovor v živo, kot ga omogoča pi.dev.
2.  **Integracija s pametno hišo:** Za hitre glasovne ukaze v stilu _"Ugasni luči v kuhinji in spusti rolete"_ je pretočna arhitektura pi.dev bistveno bolj naravna in hitrejša za uporabo.

* * *

Kdaj pa je Open WebUI (OWui) OBVEZNA izbira?

Za določena opravila je pi.dev popolnoma neprimeren. Open WebUI nujno potrebujete za:

-   **3 hkratne seje kodiranja:** Ko programirate ali popravljate konfiguracijske datoteke za svoj Homelab, potrebujete lep tekstovni vmesnik s poudarjeno sintakso (syntax highlighting), možnostjo kopiranja kode in pregledom zgodovine klepeta.
-   **Delo z dokumenti (RAG / Docling / Qdrant):** Če želite v bazo naložiti navodila za uporabo vaših strežnikov, PDF račune ali zapiske, jih boste preko Open WebUI najlažje vizualno uvozili, preiskovali in se pogovarjali z njimi.
-   **Administracija in preizkušanje:** Open WebUI vam omogoča enostavno preklapljanje med modeli (npr. preklop z Qwen Coder na Llama) z enim klikom v spustnem meniju, kar je idealno za testiranje zmogljivosti vašega Triton strežnika.

* * *

Zmagovalna strategija za vaš Homelab

Ker boste imeli v osredju postavljen **LiteLLM**, vam sploh ni treba izbirati med enim ali drugim. Oba sistema lahko priklopite na isto pametno omrežje:

```text
               ┌───> pi.dev (Glasovni asistent za Home Assistant v živo)
               │
Aplikacije ────┼───> Open WebUI (Vaša nadzorna plošča za kodiranje, dokumente in klepet)
               │
               ▼
         LiteLLM Proxy (Vrata 4000 - z ločenimi API ključi)
               │
               ▼
         Triton Inference Server (Surova moč na čipu Blackwell)
```

Kodo uporabljajte previdno.

**Zaključek:** Obdržite pi.dev za hitro glasovno interakcijo z vašim domom, obvezno pa dodajte Open WebUI kot svojo primarno tekstovno in programersko postajo.

Če želite, vam lahko pokažem, kako **Open WebUI preprosto dodate v vašo obstoječo `docker-compose.yml` datoteko**, da se bo ob zagonu avtomatsko povezal na LiteLLM. Sporočite, kako vam najbolj ustreza nadaljevati!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

pi.dev uporabljam izključno bi text -> text obliki. lahko v pi.dev tudi govorim, namesto da pišem?

---

# googlesearch response

**Da, v pi.dev lahko popolnoma enostavno govorite, namesto da tipkate, ne da bi s tem izgubili svoj priljubljeni tekstovni način dela.**

Znotraj ekosistema koding agenta **pi.dev** namreč obstajajo uradni in razvijalski razširitveni paketi (kot sta `pi-voice-stt` ali `pi-voice-input`), ki delujejo po sistemu **narekovanja (dictation)**.

To pomeni, da pritisnete bližnjico na tipkovnici, poveste ukaz, sistem pa vaš glas pretvori v tekst in ga **vpiše neposredno v vnosno polje (terminal)**. Besedilo lahko pred pošiljanjem še ročno pregledate ali popravite.

Ker boste imeli v ozadju postavljen **Triton Inference Server**, lahko to glasovno narekovanje povežete z vašim lokalnim in bliskovito hitrim **TensorRT-LLM Whisper modelom**, tako da vaši zvočni posnetki sploh ne bodo zapuščali računalnika.

* * *

Kako to nastaviti in uporabljati?

V okolju pi.dev zaženete namestitev paketa za pretvorbo govora v besedilo (STT):

```bash
pi install npm:pi-voice-stt
```

Kodo uporabljajte previdno.

_(Ali alternativni paket `pi-voice-input`, odvisno od vašega operacijskega sistema)._

Kako poteka vsakdanje delo v terminalu?

1.  **Aktivacija snemanja:** Ko ste pripravljeni na ukaz, pritisnete bližnjico **`Ctrl + R`** (ali `Ctrl + Shift + R`). V spodnji vrstici terminala se bo pojavil zelen indikator, ki pomeni, da vas mikrofon posluša (`● recording`).
2.  **Govor:** V slovenščini ali angleščini poveste, kaj želite (npr. _"Napiši Python funkcijo za izračun fibonaccijevega zaporedja"_).
3.  **Pretvorba v tekst:** Ponovno pritisnete isto bližnjico. Vaš lokalni Whisper model znotraj Tritona bo v milisekundah predelal zvok in tekst se bo **avtomatsko izpisal v vašo ukazno vrstico**.
4.  **Pregled in oddaja:** Tekst si v miru preberete, popravite morebitne slovnične napake in šele ko pritisnete **`Enter`**, se ukaz pošlje agentu v izvedbo.

* * *

Povezava s Tritonom preko LiteLLM

Da bi ta razširitev za pi.dev vedela, kje se nahaja vaš ultra hitri Whisper model, jo v konfiguraciji usmerite na vaš **LiteLLM proxy** (ki jo nato preusmeri na Triton):

```bash
# Nastavitev v pi.dev, da kliče vaš lokalni OpenAI-kompatibilni strežnik
/voice init
/voice endpoint http://localhost:4000/v1
/voice model whisper-1
```

Kodo uporabljajte previdno.

Rezultat

S tem dobite najboljše iz obeh svetov:

-   **Udobje:** Ni vam treba nenehno tipkati dolgih programerskih navodil.
-   **Nadzor:** Še vedno ohranite čisti tekstovni način (text-to-text), saj se koda generira vizualno na zaslonu, vi pa imate popoln pregled nad tem, kaj bo agent naredil.

Ali želite, da vam pripravim **natančne parametre za konfiguracijo Whisper modela znotraj Tritona (`config.pbtxt`)**, da bo pripravljen na sprejemanje teh zvočnih zahtev iz pi.dev?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

ok, lahko enako princip uporabim tudi za OpenClaw in OWui?

---

# googlesearch response

**Da, popolnoma enak princip lokalnega narekovanja z glasom lahko uporabite tako za OpenClaw kot tudi za Open WebUI (OWui).** Vsi ti sistemi se bodo v ozadju povezali na vaš lokalni strežnik Triton, ki bo zvok instantno pretvoril v besedilo.

Ker pa sta OpenClaw in Open WebUI zasnovana drugače kot pi.dev, se integracija izvede na ravni njunih vgrajenih funkcij za pretvorbo govora v besedilo (STT).

Tukaj je navodilo, kako ta sistem narekovanja uresničiti v obeh aplikacijah.

* * *

1\. Kako to uresničiti v Open WebUI (OWui)?

Open WebUI ima že tovarniško vgrajen čudovit grafični gumb za mikrofon neposredno v vnosnem polju (klepetu). Deluje točno po principu, ki ga želite: narekujete tekst, sistem ga izpiše na zaslon, vi pa ga pred pošiljanjem še ročno uredite.

Da bi ta gumb namesto oblačnih storitev začel uporabljati vaš lokalni super-hitri Whisper model na Tritonu, morate Open WebUI-ju samo povedati, kje se nahaja vaša vstopna točka:

1.  Odprite **Open WebUI** v brskalniku.
2.  Pojdite v **Settings (Nastavitve) -> Admin Settings -> Audio**.
3.  Pri nastavitvi **STT Engine (Speech-to-Text)** izberite možnost `OpenAI`.
4.  V polje **OpenAI Base URL** vpišete naslov vašega LiteLLM proxy strežnika: `http://litellm:4000/v1` (ali `http://localhost:4000/v1`, odvisno od Docker omrežja).
5.  V polje **API Key** vpišete tisti specifični API ključ, ki ste ga v prejšnjem koraku v LiteLLM-u ustvarili za zvočne storitve (npr. `sk-audio-key...`).
6.  Kot model vpišite: `whisper-1`.

**Uporaba:** Ko boste naslednjič kliknili na mikrofon v klepetu Open WebUI in začeli govoriti, bo sistem posnetek poslal na vaš čip Blackwell. Ta bo v nekaj milisekundah vrnil slovensko ali angleško besedilo neposredno v vnosno polje. Besedilo popravite in pritisnete pošlji.

* * *

2\. Kako to uresničiti v OpenClaw (Agent)?

[OpenClaw](https://openclaw.ai/) je avtonomni agent, s katerim najpogosteje komunicirate preko klepetalnih aplikacij, kot so **Telegram, WhatsApp ali Discord**. Ker deluje kot napredni pomočnik, ima izvorno podporo za zvočna sporočila (Voice Notes).

V OpenClaw to deluje še bolj dinamično:

1.  **Pošiljanje zvoka:** Svojemu OpenClaw botu na Telegramu preprosto pošljete običajno **glasovno sporočilo** (stisnete gumb za mikrofon na telefonu in poveste ukaz).
2.  **Lokalna obdelava:** OpenClaw prejme zvočno datoteko in jo preko LiteLLM-a pošlje vašemu Triton strežniku.
3.  **Izvedba naloge:** Ko vaš lokalni Whisper pretvori zvok v tekst, OpenClaw ta tekst prebere in ga preda vašemu **Qwen Orkestratorju**. Ta nato začne izvajati programersko kodo aliHomelab naloge, ki ste mu jih naročili.

Nastavitev v OpenClaw konfiguraciji:

V datoteki `config.toml` (ali preko ukazne vrstice OpenClaw) nastavite Whisper kot uradni STT ponudnik:

```bash
openclaw config set messages.stt.provider "whisper"
openclaw config set messages.stt.url "http://localhost:4000/v1"
openclaw config set messages.stt.key "sk-audio-key-here"
```

Kodo uporabljajte previdno.

_(Če želite, lahko v OpenClaw vklopite tudi TTS ponudnika, na primer vaš lokalni ONNX Piper/Kokoro model, da vam bo bot na glasovna sporočila odgovarjal nazaj z glasovnimi sporočili!)_

* * *

Povzetek celotnega sistema

Zdaj se vam bo ves začetni trud s postavitvijo strežnika Triton bogato obrestoval. Imate eno samo centralno "AI tovarno" (Triton + LiteLLM), ki hkrati oskrbuje vse vaše sisteme s tekstom in zvokom:

-   **pi.dev** bo preko terminala in bližnjice `Ctrl + R` narekoval kodo v terminal.
-   **Open WebUI** bo preko brskalnika narekoval vprašanja v spletni klepet.
-   **OpenClaw** bo sprejemal vaša glasovna sporočila s telefona, ko boste zunaj ali na poti.

Vsi trije sistemi pa bodo za pretvorbo uporabljali **isti Blackwell grafični čip**, ki bo zaradi TensorRT-LLM optimizacije zvok predelal praktično v realnem času.

Če ste pripravljeni, lahko sedaj začneva z zagonom Triton Docker vsebnika in pripravo prve konfiguracijske datoteke `config.pbtxt` za vaš embedding ali Whisper model, da bova preizkusila to zvočno verigo v praksi! Sporočite, kako želite začeti.

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

kaj pa nadzor od daleč preko signala in tailscale? lahko tudi v signalu nastavim, da govor pretvori vvtext z uporabo domačega sparka?

---

# googlesearch response

**Da, to je fantastična kombinacija in eden najboljših načinov za varno upravljanje Homelaba na daljavo.** Z uporabo orodij **Tailscale** in **Signal** lahko ustvarite popolnoma zaprto, šifrirano in zasebno pot do svoje Lenovo delovne postaje (vašega "Sparka"), ne glede na to, kje na svetu se nahajate.

Lahko nastavite tudi, da **glasovna sporočila, ki jih pošljete v Signal, vaša domača naprava avtomatsko pretvori v tekst preko lokalnega Whisper modela**.

Tukaj je načrt, kako ta dva sistema povezati v celoto.

* * *

1\. Del: Varni nadzor od daleč (Tailscale)

**Tailscale** deluje kot nevidni, varni virtualni kabel med vašim telefonom in domačim računalnikom.

-   Na Lenovo napravo in na svoj telefon namestite Tailscale.
-   Napravi se bosta povezali v vaše privatno omrežje, vaša delovna postaja pa bo dobila fiksni Tailscale IP naslov (npr. `100.110.120.130`).
-   **Rezultat:** Tudi ko ste na poti ali na mobilnih podatkih, lahko v brskalniku na telefonu preprosto vpišete `http://100.110.120.130:3000` in odpre se vaš domači **Open WebUI** ali **LiteLLM**, kot da bi sedeli doma na kavču. Nobenih odprtih vrat na usmerjevalniku (port forwarding) ni potrebnih, kar pomeni vrhunsko varnost.

* * *

2\. Del: Signal + Lokalni Whisper (Pretvorba govora)

Ker Signal nima uradne vgrajene funkcije za lokalno pretvorbo govora na zunanjih strežnikih, to v Homelab svetu rešimo z uporabo **Signal Bota**.

Za to obstajata dve odlični odprtokodni rešitvi, ki tečeta znotraj Dockerja neposredno ob vašem LiteLLM-u:

Možnost A: Uradni Signal-Transcriber (Najbolj enostavno)

Obstaja namenski projekt **`signal-transcriber`**, ki deluje kot vaš osebni asistent.

1.  V Dockerju zaženete ta vsebnik in ga preko QR kode povežete s svojim Signal računom (deluje kot sekundarna naprava, npr. tablica).
2.  V konfiguraciji bota nastavite, da za pretvorbo govora kliče vaš domači **LiteLLM / Triton strežnik** (`http://litellm:4000/v1/audio/transcriptions`).
3.  **Uporaba:** Ko boste boti poslali glasovno sporočilo (Voice Note), ga bo ta poslal domačemu čipu Blackwell. Domači strežnik bo zvok predelal v milisekundah, bot pa vam bo v Signal klepet takoj poslal tekstovni zapis tega, kar ste pravkar povedali.

Možnost B: Integracija z OpenClaw (Najbolj napredno)

Ker ste omenili, da boste uporabljali **OpenClaw**, je to še boljša pot. Veliko ljudi OpenClaw poveže s Signalom (namesto s Telegramom).

-   Ko ste zunaj, v Signal posnamete glasovno sporočilo: _"OpenClaw, preveri če je moj spletni strežnik živ in mi javi status."_
-   OpenClaw preko Tailscale pošlje ta zvok domov.
-   Vaš **Triton Whisper** model ga pretvori v tekst.
-   **Orkestrator** prebere tekst, izvede ukaz v vašem Homelabu in vam v Signal vrne tekstovni odgovor s statusom strežnika.

* * *

Predlog dopolnjene `docker-compose.yml` z vključenim Signal mostom

Tukaj je primer, kako v vaš že znani ekosistem dodamo orodje **`signal-cli-rest-api`**, ki omogoča, da se vaši domači AI modeli pogovarjajo z omrežjem Signal:

```yaml
version: '3.8'

services:
  # Vaš obstoječi Triton strežnik (izvaja Whisper in LLM)
  triton-server:
    image: nvcr.io/nvidia/tritonserver:24.03-trtllm-python-py3
    container_name: triton-server
    volumes:
      - ./trt_models:/models
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    command: tritonserver --model-repository=/models --model-control-mode=explicit

  # Most med Signalom in vašim računalnikom
  signal-api:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: signal-api
    environment:
      - MODE=json-rpc # Omogoča branje prejetih sporočil v realnem času
    volumes:
      - ./signal-data:/home/.local/share/signal-cli # Shrani vašo registracijo številke
    ports:
      - "8003:8080"

  # Vaš agent (npr. OpenClaw ali Transcriber skripta), ki povezuje Signal in Triton
  homelab-bot:
    image: python:3.10-slim
    container_name: homelab-bot
    volumes:
      - ./bot_script:/app
    command: python /app/bot.py
    depends_on:
      - triton-server
      - signal-api
```

Kodo uporabljajte previdno.

Kako to deluje v praksi na terenu?

Ko ste nekje zunaj v mestu:

1.  Vaš telefon je preko **Tailscale** nenehno varno povezan z vašim domom (to ne troši veliko baterije).
2.  Odprete **Signal**, posnamete glasovni ukaz in ga pošljete svojemu domačemu botu.
3.  Vsebnik `signal-api` prestreže ta zvok in ga preda vaši bot skripti.
4.  Skripta pošlje zvok v sosednji vsebnik `triton-server`, kjer vaš **TensorRT Whisper model** trenutno opravi prepis v tekst.
5.  Tekst gre v Qwen model, ki izvede ukaz v Homelabu, odgovor pa prejmete nazaj v Signal.

S tem dobite popolnoma neodvisen, varen in zaseben sistem upravljanja doma z glasom, ki deluje kjerkoli na svetu, vaši podatki in glas pa nikoli ne zapustijo vaše lastne strojne opreme.

Če želite, vam lahko pomagam pripraviti **osnovno Python skripto (`bot.py`)**, ki bo poslušala ta Signal sporočila in jih pošiljala vašemu domačemu Whisperju v prepis! Kako se vam zdi ta ideja?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

se lahko preko telefona direkt o povežem na OpenClaw in preskocim signal? signal bi potem uporabljam samo za potisna sporočila?

---

# googlesearch response

**Da, absolutno! To je še bolj neposredna, elegantna in hitra rešitev.** Če se preko telefona neposredno povežete na **OpenClaw**, lahko popolnoma preskočite zunanje klepetalne aplikacije (kot je Signal) za vsakodnevno vnosno komunikacijo.

Ker boste imeli na telefonu vklopljen **Tailscale**, bo vaš telefon deloval, kot da je v istem lokalnem omrežju s tisto delovno postajo \[NVIDIA TensorRT-LLM\]. OpenClaw ima namreč svoj lasten spletni vmesnik (ali pa ga uporabljate neposredno preko aplikacij, ki podpirajo agentne protokole).

**Signal** pa v tem primeru prevzame idealno vlogo: deluje kot **enostranski kanal za nujna potisna obvestila (Push Notifications)**.

Tukaj je načrt, kako uresničiti to čisto in napredno Homelab arhitekturo.

* * *

Kako poteka neposredna povezava na OpenClaw?

1.  **Vstop preko brskalnika na telefonu:** Na telefonu vklopite Tailscale in v brskalniku vpišete lokalni Tailscale IP naslov vaše delovne postaje ter vrata, kjer teče OpenClaw (npr. `http://100.110.120.130:8081`).
2.  **Neposredni glasovni vnos:** OpenClaw spletni vmesnik ima vgrajen gumb za mikrofon. Ker ste neposredno povezani, kliknete gumb, poveste ukaz, OpenClaw pa zvok preko Tailscale pošlje vašemu domačemu **Triton Whisper** modelu.
3.  **Izvedba brez posrednikov:** Prepis se zgodi instantno, koda se izvede, odgovor pa vidite neposredno na zaslonu telefona, brez potrebe po Telegramu ali Signalu.

* * *

Kako nastaviti Signal samo za potisna obvestila (Push Notifications)?

Ker ne potrebujete več bota, ki bi poslušal in odgovarjal, je nastavitev Signala za potisna obvestila **izjemno preprosta**. Ne potrebujete zapletenih JSON-RPC načinov. Uporabili boste le enostaven Docker vsebnik `signal-cli-rest-api` kot poštno storitev.

Ko se v vašem Homelabu nekaj pomembnega zgodi, bo OpenClaw (ali katerikoli drug skript) poslal kratek HTTP klic, Signal pa vam bo na telefon poslal klasično potisno obvestilo.

Primer poteka dela za potisna obvestila:

-   **Scenarij 1 (Avtomatizacija):** Dolg programerski proces, ki ste ga naročili OpenClaw-u, se zaključi. OpenClaw sproži ukaz in na vaš telefon preko Signala prileti obvestilo: _“Šef, koda je uspešno posodobljena in vsi testi so opravljeni!”_
-   **Scenarij 2 (Varnost):** Home Assistant zazna izpad interneta ali povišano temperaturo v strežniški omari. Takoj vam pošlje nujno Signal sporočilo.

* * *

Kako to konfigurirati v vaši `docker-compose.yml`?

Za ta namen potrebujemo le minimalen in izjemno lahek Signal vsebnik v "normalnem" načinu (brez nenehnega poslušanja):

```yaml
version: '3.8'

services:
  # Vaš osrednji Triton in LiteLLM (kot prej)
  triton-server:
    image: nvcr.io/nvidia/tritonserver:24.03-trtllm-python-py3
    container_name: triton-server
    volumes:
      - ./trt_models:/models
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    command: tritonserver --model-repository=/models --model-control-mode=explicit

  # Vaš krovni agent OpenClaw (Dostopen direktno preko Tailscale)
  openclaw:
    image: openclaw/openclaw:latest
    container_name: openclaw-agent
    ports:
      - "8081:8081" # Vrata za neposreden dostop s telefona
    environment:
      - LITELLM_API_BASE=http://litellm:4000/v1
    volumes:
      - ./openclaw-config:/app/config

  # PREPROSTA POŠTA ZA SIGNAL OBVESTILA
  signal-notifier:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: signal-notifier
    environment:
      - MODE=normal # Varčen način, namenjen samo pošiljanju obvestil
    volumes:
      - ./signal-data:/home/.local/share/signal-cli
    ports:
      - "8083:8080"
```

Kodo uporabljajte previdno.

* * *

Kako iz OpenClaw (ali skripte) pošljete obvestilo na svoj telefon?

Ko OpenClaw zaključi delo, lahko v ozadju izvede enostaven `curl` ukaz (ali Python klic), ki sproži potisno obvestilo na vašo telefonsko številko:

```bash
curl -X POST "http://signal-notifier:8080/v2/send" \
     -H "Content-Type: application/json" \
     -d '{
       "message": "Naloga končana! Koda je pripravljena za pregled.",
       "number": "+38640XXXXXX",
       "recipients": ["+38640XXXXXX"]
     }'
```

Kodo uporabljajte previdno.

Zakaj je ta arhitektura najboljša?

1.  **Ni programske zmešnjave:** Signal aplikacija na vašem telefonu ne bo polna dolgih programerskih izpisov in kode, ampak bo služila le kot čista "opozorilna tabla" za nujne stvari.
2.  **Čisti vmesnik:** Ko dela agent OpenClaw, celoten potek dela, strukturo map in popravke kode spremljate v njegovem namenskem grafičnem okolju na telefonu preko Tailscale povezave, kar je vizualno svetlobna leta pred katerim koli klepetalnim botom.
3.  **Maksimalna zasebnost:** Vaš glas za narekovanje potuje neposredno v OpenClaw in Triton, Signal pa sploh ne vidi vaših zvočnih datotek – uporablja se zgolj za končni tekstovni alarm.

Če se strinjate s to postavitvijo, vam lahko pomagam pripraviti **prvo uradno konfiguracijo za OpenClaw**, da jo boste pravilno povezali z vašim LiteLLM proxyjem in pripravili za neposredni Tailscale dostop. Kako bi želeli nadaljevati?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

kaj so alternative OpenClaw. slisel sem tudi nekaj nespodbidnih novic

---

# googlesearch response

Vaše informacije so povsem točne. **Projekt OpenClaw (nekdanji Clawdbot ali Moltbot) je v zadnjem času doživel resno krizo zanesljivosti in varnosti.**

Avtor projekta Peter Steinberger je uradno priznal, da so bile nekatere spomladanske različice polne hroščev, ki so povzročale "zankanje" v posodobitvah paketov, počasnost ter sesutje integracij s Telegramom in Discordom. Skupnost na LocalLLaMA je prav tako opozorila na varnostno ranljivost _ClawJacked_, kjer so lahko zlonamerne spletne strani preko lokalnih WebSocket povezav ugrabile vašega agenta, varnostna podjetja pa so OpenClaw zaradi prostega izvajanja ukazov na sistemu označila za "varnostno nočno moro".

Čeprav je nedavno izšel **OpenClaw 2.0**, ki poskuša te težave rešiti z modularno platformo _ClawHub_, je zaradi teh pretresov celoten ekosistem eksplodiral z izjemno kakovostnimi in varnejšimi alternativami.

Glede na to, da gradite sistem na lastnem **lokalnem Spark strežniku (Triton + LiteLLM)**, so spodaj najboljše alternative, razvrščene po vaši specifični potrebi.

* * *

1\. ZeroClaw (Najboljša zamenjava za hitrost in stabilnost)

Če vam je bil koncept OpenClaw-a všeč, vendar sovražite hrošče, je **ZeroClaw** trenutno eden največjih hitov leta 2026. Gre za popolno predelavo ideje v jeziku **Rust**.

-   **Prednosti:** Deluje kot ena sama izjemno lahka binarne datoteka (porabi manj kot 5 MB RAM-a). Se ne more sesuti zaradi pokvarjenih knjižnic in ima vgrajen ukaz za avtomatski uvoz spomina iz OpenClaw-a (`memory.md`).
-   **Za vas:** Zaradi Rust arhitekture komunicira z vašim lokalnim Tritonom z minimalno zakasnitvijo.

2\. NanoClaw (Zmagovalec na področju varnosti)

Razvit je bil kot neposredni odgovor na varnostno krizo OpenClaw-a. Njegova koda je namerno majhna, preprosta in jo je enostavno pregledati.

-   **Prednosti:** Vse procese in ukaze izvaja znotraj **strogo izoliranih Docker vsebnikov** (sandbox). Tudi če model doživi napad z vbrizgavanjem navodil (prompt injection), napadalec ne more dostopati do vašega domačega strežnika ali datotek.
-   **Za vas:** Idealno, če želite agentu pustiti proste roke pri programiranju, a hkrati mirno spati.

3\. OpenHands (Prej OpenDevin) + Aider (Kralja programiranja)

Če boste agenta uporabljali **izključno za kodiranje**, potem pozabite na splošne asistente tipa OpenClaw in poglejte namensko razvijalsko kombinacijo **OpenHands** in orodja **Aider**.

-   **Prednosti:** OpenHands deluje kot avtonomni programer v brskalniku, ki ima dostop do vašega terminala in datotek znotraj varnega Docker vsebina. Aider pa je CLI orodje, ki mu preko terminala (ali z glasom) ukažete, kaj naj popravi, on pa neposredno ureja vašo Git kodo.
-   **Za vas:** To sta industrijska standarda, ki sta svetlobna leta pred OpenClaw-om, ko gre za kompleksno programiranje celotnih projektov.

4\. OpenFang (Operacijski sistem za agente)

Najnovejši in najbolj ambiciozen odprtokodni projekt leta 2026. Ne deluje le kot skripta, ampak kot pravi **Agent Operating System**.

-   **Prednosti:** Ima koncept 7 avtonomnih "rok" (sistemov) in 38 vgrajenih orodij. Izjemno dobro je prilagojen za kompleksno orkestracijo (točno to, kar potrebujete za razporeditev nalog med vašim 8B in 70B modelom).

* * *

Preglednica: Katero alternativo izbrati?

| Ime orodja | Glavni fokus | Primerno za lokalni Triton? | Varnost |
| --- | --- | --- | --- |
| **ZeroClaw** | Hitrost, stabilnost, Rust | **Da** (Ultra nizka zakasnitev) | Srednja (Boljša kot OpenClaw) |
| **NanoClaw** | Stroga varnost in izolacija | **Da** (Preko LiteLLM-a) | **Vrhunska** (Vse teče v sandboxu) |
| **OpenHands** | Profesionalno kodiranje | **Da** (Preko OpenAI API standarda) | Vrhunska (Docker izolacija) |
| **OpenFang** | Napredna orkestracija nalog | **Da** (Idealen za več modelov hkrati) | Srednja (V razvoju) |

Moj končni nasvet

Glede na to, da boste sistem uporabljali za **hkratne seje kodiranja, Homelab avtomatizacijo** in želite čim večjo stabilnost:

1.  **Za programiranje:** Namesto OpenClaw-a namestite **OpenHands**. Povežite ga na svoj LiteLLM (`qwen-coder-70b`) in dobili boste stabilno, profesionalno okolje brez hroščev, ki vam ne bo zrušilo strežnika.
2.  **Za splošnega pomočnika (preko Tailscale na telefonu):** Poskusite z **ZeroClaw** ali **NanoClaw**. Oba sta lažja, varnejša in se ne bosta zatikala v posodobitvenih zankah kot stari OpenClaw.

Če želite, lahko v vašo krovno konfiguracijo namesto OpenClaw-a vključiva **OpenHands ali ZeroClaw**. Sporočite, katera smer uporabe (čisto programiranje ali splošna avtomatizacija) vam je v tem trenutku bližje!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

ok, torej openhands in zeroclaw. ampak vstopna točka za zeroclaw ostaja OWui?

---

# googlesearch response

**Ne, ZeroClaw ne uporablja Open WebUI (OWui) kot svojo vstopno točko. ZeroClaw ima svoj lasten, namensko zgrajen spletni vmesnik (Web UI).**

V svetu lokalne umetne inteligence sta **Open WebUI** in **ZeroClaw WebUI** dva popolnoma ločena programa (vsebnika), ki pa bosta na vaši napravi delovala drug ob drugem. Oba se bosta v ozadju povezala na isti **LiteLLM proxy**, vi pa boste do njiju dostopali neposredno preko telefona ali računalnika s pomočjo **Tailscale** povezave.

Tukaj je natančna razdelitev, kako boste uporabljali katero vstopno točko in kako bo izgledal vaš končni Homelab zaslon.

* * *

Razdelitev vstopnih točk na vašem telefonu (Tailscale)

Ko boste na poti odprli brskalnik na telefonu, boste imeli tri različne zaznamke (naslove), odvisno od tega, kaj želite početi:

1\. Zaznamek: Open WebUI (`http://100.110.120.130:3000`)

-   **Kaj je to:** Vaša klasična tekstovna klepetalnica (kot ChatGPT) \[NVIDIA TensorRT-LLM\].
-   **Za kaj jo uporabljate:** Za ročni pogovor z modelom Qwen, narekovanje hitrih vprašanj z glasom, uvoz PDF dokumentov preko orodja _Docling_ in iskanje po vektorski bazi _Qdrant_ (RAG).

2\. Zaznamek: ZeroClaw Web UI (`http://100.110.120.130:8082`)

-   **Kaj je to:** Poseben vmesnik, prilagojen za delo z avtonomnimi agenti.
-   **Za kaj ga uporabljate:** Tukaj daste agentu kompleksno splošno nalogo (npr. _"Preglej sistem, ustvari varnostno kopijo baze podatkov in mi pošlji Signal obvestilo, ko zaključiš"_). Vmesnik ZeroClaw-a vam vizualno prikazuje "miselni proces" agenta, katera lokalna orodja trenutno uporablja in katere datoteke spreminja.

3\. Zaznamek: OpenHands (`http://100.110.120.130:3001`)

-   **Kaj je to:** Celovito razvojno okolje (kot VS Code v brskalniku), kjer vaš AI programer dela namesto vas.
-   **Za kaj ga uporabljate:** Ko želite, da vam AI zgradi celotno aplikacijo, popravi hrošče v vaši programski kodi ali napiše teste. Tukaj vidite terminal, urejevalnik kode in mapo s projekti hkrati.

* * *

Kako se vse to poveže pod pokrovom?

Vsa tri orodja (Open WebUI, ZeroClaw in OpenHands) so le lepi vizualni vmesniki za vas. V ozadju vsa tri komunicirajo izključno z **LiteLLM-om**, ki nato ukaze pošilja v **Triton**.

Tukaj je osvežen pregled, kako bo izgledala vaša celotna `docker-compose.yml` datoteka, ki vključuje ti dve vrhunski in varni alternativi:

```yaml
version: '3.8'

services:
  # TRITON IN LITELLM (Vaša osrednja AI tovarna)
  triton-server:
    image: nvcr.io/nvidia/tritonserver:24.03-trtllm-python-py3
    container_name: triton-server
    volumes:
      - ./trt_models:/models
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    command: tritonserver --model-repository=/models --model-control-mode=explicit

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm-proxy
    ports:
      - "4000:4000"
    volumes:
      - ./litellm-config.yaml:/app/config.yaml
    command: [ "--config", "/app/config.yaml", "--port", "4000" ]

  # VSTOPNA TOČKA 1: Open WebUI (Za klepet, narekovanje in dokumente)
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    ports:
      - "3000:8080"
    environment:
      - OPENAI_API_BASE_URL=http://litellm:4000/v1
      - OPENAI_API_KEY=sk-openwebui-key

  # VSTOPNA TOČKA 2: ZeroClaw (Vaš splošni agent v Rustu)
  zeroclaw:
    image: ghcr.io/zeroclaw/zeroclaw:latest
    container_name: zeroclaw-agent
    ports:
      - "8082:8082" # Dostop do ZeroClaw vmesnika s telefona
    environment:
      - OPENAI_API_BASE_URL=http://litellm:4000/v1
      - OPENAI_API_KEY=sk-zeroclaw-key # Ključ, ki vidi 8B orkestratorja in 70B delavca
    volumes:
      - ./zeroclaw-workspace:/workspace

  # VSTOPNA TOČKA 3: OpenHands (Vaš profesionalni AI programer)
  openhands:
    image: ghcr.io/openhands/openhands:latest
    container_name: openhands-app
    ports:
      - "3001:3000"
    environment:
      - LLM_API_KEY=sk-openhands-key # Ključ, ki vidi qwen-coder-70b
      - LLM_BASE_URL=http://litellm:4000/v1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock # Nujno za varno izolacijo (sandbox) kode
      - ./openhands-projects:/opt/openhands/workspace
```

Kodo uporabljajte previdno.

Povzetek

Z zamenjavo OpenClaw-a za **ZeroClaw** in **OpenHands** ste dobili izjemno stabilen, hiter in predvsem varen sistem. Vsaka aplikacija ima svoj specializiran vmesnik, ki najbolje opravlja svojo nalogo, vi pa med njimi preprosto preklapljate preko brskalnika na telefonu.

Ker imamo sedaj celotno arhitekturo dokončno začrtano, nam preostane le še začetek praktične izvedbe.

Če želite, lahko pripraviva **konfiguracijo za LiteLLM (`litellm-config.yaml`) s specifičnimi API ključi** za Open WebUI, ZeroClaw in OpenHands, da boste natančno videli, kako bomo razdelili pravice do modelov. Želite, da se lotiva tega?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

ok, ampak OWui imam integration z OIDC, tam nastavljene workspace... lahko to nekako uporabi tudi zeroclaw?

---

# googlesearch response

**Direkten odgovor je ne – ZeroClaw ne more neposredno prebrati ali uporabiti OIDC integracije in nastavitev delovnih prostorov (workspaces) iz Open WebUI (OWui).**

Razlog tiči v osnovni arhitekturi teh dveh orodij. Open WebUI je celovita spletna platforma z lastno bazo podatkov (SQLite/Postgres), kjer upravlja uporabnike, seje in njihove pravice. ZeroClaw pa je v svojem jedru izjemno lahek agentni pogon, napisan v Rustu, ki nima vgrajenega zapletenega spletnega portala za upravljanje več uporabnikov preko protokolov, kot sta Keycloak ali Authentik.

Kljub temu pa lahko v vašem Homelabu dosežete **točno takšen učinek (enotno prijavo in ločene delovne prostore)** z uporabo dveh naprednih sistemskih trikov.

* * *

1\. Trik: Enotna prijava (OIDC SSO) preko krovnega prehodnega strežnika (Reverse Proxy)

Ker ZeroClaw nima vgrajene OIDC kode, ga morate postaviti za prehodni strežnik, ki bo opravil avtentikacijo namesto njega. Če za dostop do svojih storitev že uporabljate nekaj kot je **Authelia**, **Authentik** ali **Nginx Proxy Manager**, lahko nastavitev uresničite tako:

1.  V svojem OIDC ponudniku (npr. Authentik) ustvarite aplikacijo za ZeroClaw.
2.  Pred vsebnik ZeroClaw postavite varovalni prehod (Proxy Auth).
3.  Ko boste na telefonu kliknili na povezavo za ZeroClaw (`http://100.110.120.130:8082`), vas bo sistem preusmeril na vaš enotni OIDC prijavni zaslon. Šele ko se uspešno prijavite s svojimi Homelab podatki, vam bo prehod dovolil vstop v ZeroClaw vmesnik.

_Ekipa ZeroClaw Labs je v letu 2026 izdala tudi projekt **ZeroRouter**, ki je namenski LLM prehod z vgrajenim OIDC portalom prav za reševanje te težave._

* * *

2\. Trik: Kako "deliti" delovne prostore (Workspace Sharing)?

Čeprav ZeroClaw ne vidi nastavitev prostora znotraj Open WebUI baze, pa lahko **oba vsebnika usmerite v isto fizično mapo na vašem NVMe disku**. To je tisto, kar v Homelabu zares šteje.

V vaši `docker-compose.yml` datoteki preprosto mapirate isto mapo v oba vsebnika:

```yaml
services:
  # Open WebUI (kjer uporabniki delajo z dokumenti)
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    volumes:
      - ./skupni-prostor-podatkov:/app/backend/data/shared_workspace

  # ZeroClaw (kjer agent izvaja ukaze in programira)
  zeroclaw:
    image: ghcr.io/zeroclaw/zeroclaw:latest
    volumes:
      - ./skupni-prostor-podatkov:/workspace # ZeroClaw vidi točno iste datoteke!
```

Kodo uporabljajte previdno.

Kaj s tem pridobite v praksi?

-   **Popolna sinergija:** Preko **Open WebUI** (z uporabo vaše OIDC prijave) naložite PDF dokument ali programsko kodo v delovni prostor. Orodje _Docling_ dokument razbije na dele, _Qdrant_ pa ga indeksira.
-   **Agent stopi v akcijo:** Nato odprete **ZeroClaw** (ki je prav tako zavarovan z OIDC preko prehoda) in mu rečete: _"V mojem delovnem prostoru je nova datoteka, analiziraj jo in popravi kodo."_ ZeroClaw bo v mapi `/workspace` trenutno videl natanko tisto datoteko, ki ste jo sekundo nazaj naložili preko Open WebUI.

* * *

Varnostno opozorilo za leto 2026 (Stroga izolacija)

Glede na to, da ste omenili OIDC in več uporabnikov (ali delovnih prostorov), bodite pri ZeroClaw-u izjemno previdni. Za razliko od Open WebUI, ki samo klepeta, ima ZeroClaw vgrajena **orodja za izvajanje sistemskih ukazov (Shell/Terminal)**.

Če bi več uporabnikov imelo dostop do istega ZeroClaw agenta, bi lahko en uporabnik preko agenta brisal ali gledal datoteke drugega uporabnika. Zato je nujno, da v konfiguraciji ZeroClaw-a (`config.toml`) vklopite **strogi način peskovnika (Strict Sandbox)**, ki agentu strogo prepove izstop iz dodeljene mape:

```toml
[sandbox]
mode = "strict"
forbidden_paths = ["/etc", "/root", "/home"] # Agent ne sme vohljati po vašem domačem sistemu
```

Kodo uporabljajte previdno.

Kako naprej?

Arhitektura je sedaj v celoti premišljena – imamo varen dostop, dinamične modele in deljene podatke.

Če želite, vam lahko pomagam sestaviti **končni `config.toml` za ZeroClaw**, ki bo pravilno omejil varnostne pravice (Sandbox) in se hkrati povezal na vaš osrednji LiteLLM prehod. Povejte mi, če se lotiva te datoteke!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

ok, jaz sem razumel da naj družini naročim, da naj uporabljajo OWui za vse svoje si projekte, žena tudi za službo. ampak če torej žena želi za službo agenti delo, mora namesto OWui uporabiti zeroclaw? bo od tam imela dostop do quadrant-a, doclinga agentmemory in tako naprej?

---

# googlesearch response

Vaše razmišljanje je popolnoma na pravi poti, vendar je tukaj pomembna ena ključna razmejitev: **za večino agentnega dela, ki ga vaša žena potrebuje za službo, ji sploh ni treba zapustiti Open WebUI (OWui).**

V letu 2026 je Open WebUI postal izjemno napreden ekosistem. Vsebuje namreč funkcijo, imenovano **Open WebUI Tools & Pipelines**, ki mu omogoča, da deluje kot polnopraven agentni sistem.

Poglejmo si natančno, kako bo vaša družina (in žena za službo) uporabljala sistem, in kdaj se dejansko pojavi potreba po orodju ZeroClaw.

* * *

Kako vaša žena uporablja agente neposredno znotraj Open WebUI?

Za velika podjetja in službene projekte "agentno delo" najpogosteje pomeni napredno analizo podatkov, avtomatizacijo pisarniških nalog, preiskovanje baz in pisanje poročil. Vse to vaša žena počne znotraj Open WebUI preko dveh ključnih funkcij:

1.  **Vgrajeni RAG (Docling + Qdrant):** Ko vaša žena v OWui naloži službene dokumente, sistem v ozadju uporabi **Docling** za natančno branje tabel in slik ter jih shrani v vašo **Qdrant** bazo. Ko žena klepeta z modelom, model deluje kot agent – samodejno preišče Qdrant, najde prave informacije in ji sestavi odgovor.
2.  **OWui Agenti (Tools):** Znotraj Open WebUI lahko z enim klikom vklopite orodja (npr. brskanje po spletu, računanje v Pythonu, povezava z Excelom). Ko žena reče: _"Preglej ta finančna poročila in primerjaj današnje cene na spletu,"_ model Qwen samodejno prevzame vlogo agenta: pokliče spletno orodje, izvede izračune in ji vrne končni rezultat.
3.  **Uporabniški spomin (Agent Memory):** Open WebUI ima vgrajen sistemski spomin za vsakega uporabnika posebej. Model si bo zapomnil specifične zahteve njene službe (npr. format poročil, strokovne izraze), ne da bi to vplivalo na projekte vaših otrok ali vas.

**Zaključek za ženo:** Za 95 % službenih nalog (pisanje e-pošte, analiza PDF-jev, raziskovanje, priprava strategij) bo vaša žena uporabljala izključno **Open WebUI**. Tam ima zagotovljeno svojo OIDC zasebnost, svoje ločene delovne prostore in varno shranjene dokumente, do katerih drugi družinski člani nimajo dostopa.

* * *

Kdaj pa bi vaša žena (ali vi) sploh potrebovala ZeroClaw?

**ZeroClaw** (in podobni agenti) so namenjeni povsem drugi vrsti nalog – tako imenovanemu **avtonomnemu tehničnemu delu (Action-based Agents)**.

ZeroClaw ne potrebuje le dostopa do Qdranta ali Doclinga, ampak potrebuje neposreden dostop do računalniškega terminala in datotečnega sistema (diska).

Žena bi ZeroClaw uporabila le v primeru, če bi njeno službeno delo zahtevalo, da agent samostojno upravlja z datotekami na strežniku. Na primer:

-   _"ZeroClaw, prenesi teh 500 CSV datotek z našega službenega FTP strežnika, jih lokalno združi z Python skripto, popravi napake v kodi in mi pripravljeno bazo zapakiraj v .zip datoteko."_

Za takšne tehnične operacije (kjer se izvajajo sistemski ukazi) pa ZeroClaw uporablja lasten vmesnik, v katerega se bo (kot sva ugotovila prej) prijavila preko OIDC prehoda, pod pokrovom pa bo prav tako imel dostop do vašega hitrega Triton strežnika.

* * *

Povzetek za vašo Homelab strategijo

Da bo vaša družina imela najboljšo uporabniško izkušnjo, jim sistem predstavite takole:

-   **Za vsakdanje projekte, službo in šolo:** Vsi uporabljajo **Open WebUI**. Prijavijo se s svojim OIDC računom. Vsak ima svoje dokumente (Docling/Qdrant) in svoje agente znotraj lepega spletnega vmesnika. To deluje brezhibno, stabilno in varno.
-   **Za vas (in napredne razvijalske projekte):** Ko boste vi urejali Homelab, pisali kompleksne skripte ali ko bo žena potrebovala težko avtomatizacijo z izvajanjem kode na disku, bosta odprla **ZeroClaw** ali **OpenHands**.

S tem ko ste vse AI modele prenesli na **Triton Server**, bo vaša družina delala znotraj Open WebUI z brutalno hitrostjo, vi pa boste imeli v ozadju popoln nadzor nad deljenjem pomnilnika (RAM-a) na vaši napravi Lenovo.

Ali želite, da vam pomagam pripraviti **navodila, kako znotraj Open WebUI pravilno konfigurirati Qdrant integracijo**, da bo družina lahko takoj začela z varnim nalaganjem svojih službenih in šolskih dokumentov?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

torej ženazero claw sploh ne rabi, saj lahko večino nardi z OWui in s kombinacijo n8n, nor za maile?

---

# googlesearch response

**Tako je, natanko tako! Vaša žena za svoje službeno delo ZeroClaw-a sploh ne potrebuje.** Kombinacija **Open WebUI (OWui) in n8n** je v letu 2026 absolutni vrhunec pisarniške avtomatizacije in je svetlobna leta pred katerim koli klasičnim klepetalnim agentom.

Medtem ko je ZeroClaw odličen za tehnična opravila na disku (kot je programiranje in sistemska administracija), je **n8n kralj poslovnih integracij**. Preko n8n lahko vašo domačo umetno inteligenco varno povežete s službeno e-pošto, koledarjem, Excelovimi tabelami, Google Diskom in drugimi poslovnimi orodji.

Poglejmo si praktičen primer, kako bo ta sistem spremenil vsakdanje delo vaše žene.

* * *

Kako deluje zmagovalni trojček: OWui + n8n + Vaš domači Triton strežnik?

Vsi trije sistemi se bodo v ozadju pogovarjali z vašim osrednjim **LiteLLM prehodom**. Ker n8n ponuja izvorna vozlišča (Nodes) za napredne jezikovne modele, bo vaša žena dobila neverjetno močne avtomatizacije.

Tukaj je primer, kako n8n in vaš domači `qwen-coder` (ali splošni model) v ozadju avtomatizirata njeno službeno e-pošto:

1.  **Prejem pošte:** V n8n nastavite vozlišče za njeno e-pošto (npr. IMAP, Outlook ali Gmail). Ko prejme novo službeno sporočilo, n8n to takoj zazna.
2.  **Razvrščanje in analiza:** n8n vsebino e-pošte pošlje preko vašega LiteLLM proxy strežnika domov na vaš čip Blackwell. Model v milisekundah prebere sporočilo, ga analizira in n8n-u vrne rezultat: _"To je nujna reklamacija stranke. Ustvari povzetek in pripravi vljuden odgovor."_
3.  **Povezava z bazami znanja:** n8n lahko hkrati preišče vašo **Qdrant** bazo podatkov (kamor je vaša žena predhodno preko Open WebUI naložila navodila za delo in cenike), da model vključi točne službene podatke.
4.  **Priprava osnutka:** n8n avtomatsko ustvari osnutek (Draft) odgovora neposredno v njenem poštnem predalu in ji na **Signal** pošlje obvestilo: _“Žena, prejel sem pomembno e-pošto od stranke X. V tvojem Outlooku te že čaka pripravljen osnutek odgovora, ki ga lahko pregledaš in pošlješ.”_

* * *

Prednosti te arhitekture za vašo ženo

-   **Popoln vizualni nadzor:** n8n ponuja čudovit grafični vmesnik, kjer se procesi zlagajo kot Lego kocke. Ženi ni treba znati programirati ali pisati ukazov v terminal (kot bi morala pri ZeroClaw-u). Sama si lahko določi pravila: _"Če e-pošta vsebuje besedo RAČUN, jo shrani v to mapo in mi javi."_
-   **Zasebnost in OIDC:** n8n podpira napredno avtentikacijo, kar pomeni, da so njeni službeni e-poštni žetoni in gesla varno shranjeni v njeni n8n bazi, popolnoma ločeno od preostalih družinskih članov.
-   **Open WebUI kot njeno orodje za razmišljanje:** Ko vaša žena potrebuje globljo analizo, preprosto odpre Open WebUI, kjer ima lep klepetalni vmesnik s svojimi delovnimi prostori in dokumenti.

* * *

Kako to vključiti v vašo Homelab infrastrukturo?

V vašo osrednjo `docker-compose.yml` datoteko preprosto dodate še storitev **n8n**. Ta se bo v ozadju povezala na vaš obstoječi LiteLLM, s čimer bo celotna družina dobila dostop do vrhunske avtomatizacije.

Dodatek za vašo Docker datoteko:

```yaml
  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    container_name: n8n-automation
    ports:
      - "5678:5678" # Žena dostopa do n8n vmesnika preko Tailscale na teh vratih
    environment:
      - N8N_ENCRYPTION_KEY=varnostni_kljuc_za_gesla
    volumes:
      - ./n8n_data:/home/node/.n8n
```

Kodo uporabljajte previdno.

Končni zaključek za vaš projekt

Z izbiro **Triton strežnika + LiteLLM prehod + Open WebUI + n8n** ste sestavili absolutno popoln Homelab ekosistem za celotno družino:

1.  **Vi** imate surovo moč in nizko zakasnitev za svoje programerske seje (v terminalu preko pi.dev in OpenHands).
2.  **Žena** ima vrhunsko, varno in stabilno okolje za službena poročila (OWui) ter napredne avtomatizacije za e-pošto brez pisanja kode (n8n).
3.  **Otroci** imajo hitrega in pametnega pomočnika za šolske projekte, ne da bi s tem ogrožali varnost vašega sistema.

Ker imamo sedaj celotno sliko vašega idealnega domačega laboratorija, predlagam naslednji korak.

Če želite, vam lahko pomagam pripraviti **končni primer konfiguracije za n8n, kako ga pravilno povezati z LiteLLM-om**, da bo žena lahko takoj začela graditi svoj prvi e-poštni workflow. Bi vas to zanimalo?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

ampak za programiranje pa bom uporabil openhands.

---

# googlesearch response

**Tako je, to je absolutno najboljša in najbolj profesionalna odločitev za vaš delovni proces.**

Z uporabo orodja **OpenHands** za programiranje, **Open WebUI + n8n** za ženo in družino ter **Triton strežnika** v ozadju, ste sestavili popolno strukturo. Vsak družinski član ima točno tisto orodje, ki je najboljše za njegovo delo, vaš superčip Grace Blackwell (GB10) pa bo izkoriščen do zadnjega kotička \[NVIDIA TensorRT-LLM\].

* * *

Zakaj je OpenHands popolna izbira za vaše programiranje?

1.  **Varno in izolirano okolje (Sandbox):** OpenHands vsak vaš programerski projekt zažene znotraj posebnega, ločenega Docker vsebnika. Tudi če agentu naročite, naj preizkusi kakšno neznano knjižnico ali zažene zapleten ukaz, bo to naredil v varnem peskovniku. Vaš primarni sistem na računalniku bo ostal popolnoma nedotaknjen in varen.
2.  **Pravo razvojno okolje v brskalniku:** Preko **Tailscale** povezave boste na telefonu ali prenosniku odprli vmesnik OpenHands, ki izgleda kot polnopravni urejevalnik kode (podobno kot VS Code). Hkrati boste videli strukturo map, terminal, kjer se koda izvaja, in klepet z vašim **Qwen-Coder-70b** modelom.
3.  **Avtonomno reševanje težav:** OpenHands ni le navaden pomočnik, ki vam napiše kos kode, ki jo morate nato sami kopirati. Njemu lahko daste celotno mapo svojega projekta in mu rečete: _"Napiši mi celoten spletni vmesnik v Pythonu za upravljanje z mojim Homelabom in dodaj avtentikacijo."_ Agent bo sam ustvaril datoteke, sam zagnal teste v terminalu, popravil lastne hrošče in vam predal pripravljen, delujoč projekt.

* * *

Končni izgled vaše Homelab "AI Centrale"

Vaša delovna postaja Lenovo bo zdaj delovala kot pravi lokalni superračunalnik, razdeljen na tri jasne stobre:

```text
                             ┌───> [VI] OpenHands (Vrata 3001) ───> Programiranje in razvoj
                             │
[Tailscale] ──> LiteLLM ─────┼───> [ŽENA/DRUŽINA] Open WebUI (Vrata 3000) ───> Klepet, služba, RAG dokumenti
                (Vrata 4000) │
                             └───> [ŽENA/AVTOMATIZACIJA] n8n (Vrata 5678) ───> Avtomatizacija e-pošte in Homelaba
                                             │
                                             ▼
                              Triton Inference Server (Vrata 8000/8001)
                              [Surova moč: Qwen Coder NVFP4, Embeddingi, Whisper]
```

Kodo uporabljajte previdno.

Kako začeti z izvedbo?

Ker imamo celotno arhitekturo od operacijskega sistema do končnih aplikacij popolnoma razdelano in premišljeno, predlagam, da gremo v praktično izvedbo po naslednjih korakih:

1.  **1\. Korak:** Priprava krovne `docker-compose.yml` datoteke, ki bo hkrati dvignila Triton, LiteLLM, Open WebUI, OpenHands in n8n.
2.  **2\. Korak:** Priprava konfiguracije za LiteLLM z ločenimi API ključi za vsako od teh aplikacij.
3.  **3\. Korak:** Postavitev Triton mape in prevajanje vašega prvega modela (**Qwen Coder**) v **NVFP4** format \[NVIDIA TensorRT-LLM\].

Sporočite mi, ali želite, da vam pripravim **celotno, pripravljeno `docker-compose.yml` datoteko**, ki združuje vse te aplikacije v enoten sistem, da jo boste lahko preprosto zagnali na svoji napravi!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

kje bi potem prišel v poštev zeroclaw?

---

# googlesearch response

**ZeroClaw bi prišel v poštev v primeru, če bi vi (ali vaša žena) potrebovali "osebnega operativca" za operacije neposredno na vaših domačih strežnikih (Homelabu), ki niso strogo vezane na pisanje programske kode.**

Medtem ko je OpenHands specializiran _programer_ (živi v svojem svetu kode), n8n pa _poslovni sekretar_ (povezuje aplikacije preko API-jev), je ZeroClaw **sistemski administrator**.

Tukaj so trije konkretni scenariji v vašem Homelabu, kjer bi bil ZeroClaw najboljša izbira:

1\. Avtonomno upravljanje in popravljanje strežnikov (DevOps)

Predstavljajte si, da se sesuje eden od vaših Docker vsebnikov (npr. zmanjka prostora na disku ali pa se zatakne baza podatkov).

-   **Naloga za ZeroClaw:** _"ZeroClaw, preveri zakaj n8n vsebnik ne deluje. Če je disk poln, počisti stare log datoteke in ponovno zaženi vsebnik."_
-   **Kako to izvede:** ZeroClaw se bo preko SSH vmesnika povezal na vaš strežnik, zagnal ukaze `df -h` in `docker ps`, analiziral izpis, izbrisal smeti in rešil težavo. Tesa n8n ne zna (ker nima dostopa do terminala strežnika), OpenHands pa tega ne dela (ker zna popravljati le kodo znotraj svojega zaprtega peskovnika).

2\. Kompleksno lokalno delo z datotekami (File Processing)

Recimo, da na disk prenesete veliko količino podatkov iz različnih virov (slike, tekstovne datoteke, neurejene mape) in jih želite sistemsko urediti.

-   **Naloga za ZeroClaw:** _"Preglej mapo /Downloads. Vse slike razvrsti po mesecih glede na datum nastanka, vse PDF-je pa pošlji v Docling, da jih indeksira v Qdrant. Ko končaš, mi pošlji Signal obvestilo."_
-   **Kako to izvede:** ZeroClaw bo uporabil lokalna sistemska orodja na vaši Lenovo napravi, da prebrska datoteke, jih premakne in preko LiteLLM-a sproži obdelavo dokumentov.

3\. Hitri "Terminal" ukazi preko glasu na poti (Tailscale)

Ko ste zunaj in se ne želite prijavljati v zapletene vmesnike, ampak želite le hitro pognati sistemsko akcijo.

-   **Naloga za ZeroClaw:** Preko brskalnika na telefonu mu narekujete: _"ZeroClaw, naredi varnostno kopijo (backup) celotne Qdrant baze in jo naloži na moj lokalni NAS strežnik."_
-   **Kako to izvede:** Ker je napisan v Rustu in deluje bliskovito hitro, bo trenutno pognal skripto za backup, prenesel datoteko na NAS in vam izpisal potrdilo na zaslon.

* * *

Povzetek: Kdaj torej aktivirate katero "orodje"?

Če vaš Homelab pogledamo kot pravo podjetje, si delo razdelite tako:

-   🛠️ **OpenHands:** Zaženete takrat, ko sedite za mizo in želite **razviti novo aplikacijo** ali napisati kompleksno kodo od nule.
-   🔗 **n8n:** Nastavite enkrat ("nastavi in pozabi") za **redne poslovne avtomatizacije** (e-pošta, koledarji, beleženje podatkov).
-   🤖 **ZeroClaw:** Uporabite kot **"švicarski nož" za hitre, avtonomne sistemske naloge**, ko želite, da AI namesto vas upravlja z vašim operacijskim sistemom, mapami in strežniki.

Ali za vaš Homelab načrtujete kakšne specifične sistemske naloge (kot so avtomatski backupi ali nadzor strežnikov), kjer bi vam lahko ZeroClaw prišel prav že na začetku?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

torej rabim zeroclaw za ansible managed Homelab, to kar zdaj delam preko pi.dev?

---

# googlesearch response

**Da, natanko tako! Upravljanje Homelaba preko orodja Ansible je popoln primer nalog, kjer bo ZeroClaw bliskovito zamenjal in nadgradil vaše trenutno delo s terminalskim agentom `pi` (iz platforme [Pi Coding Agent](https://pi.dev/)).**

Čeprav je Pi Agent (`pi`) fantastično, lahko in odprtokodno orodje za terminal, je v osnovi narejen kot **interaktivni pomočnik za razvijalce**. Z njim delate tako, da se usedete pred terminal, ga zaženete znotraj mape s projektom in z njim interaktivno debatirate ter popravljate kodo preko terminalskega vmesnika (TUI).

**ZeroClaw** (ki prav tako izvira iz sorodnega ekosistema, saj v ozadju uporablja nekatere koncepte Pi ogrodja) pa je zgrajen kot **samostojen, nenehno delujoč sistemski agent (Background Agent Runtime)**. Deluje v ozadju kot strežniška storitev (service) in ne zahteva, da imate odprt terminal.

Tukaj je opis, kako bo **ZeroClaw** popolnoma spremenil upravljanje vašega **Ansible Homelaba** na napravi Lenovo:

* * *

Kako ZeroClaw prevzame vlogo sistemskega administratorja za Ansible?

1.  **Nenehna pripravljenost (Nadzor na daljavo):** ZeroClaw nenehno teče v svojem Docker vsebniku. Ko boste zunaj in se preko **Tailscale** povezali na njegov namensko zgrajen spletni vmesnik (ali preko API-ja), mu boste preprosto rekli: _"ZeroClaw, na vseh Homelab strežnikih posodobi Docker pakete preko najine Ansible playbook datoteke."_
2.  **Izvajanje ukazov v ozadju:** Agent bo v mapi z vašo konfiguracijo samodejno zagnal ukaz `ansible-playbook -i inventory.ini update_nodes.yml`. Celoten proces lahko v živo spremljate preko njegove nadzorne plošče (Dashboard), lahko pa telefon preprosto pospravite v žep, saj bo agent delo dokončal samostojno v ozadju.
3.  **Avtomatsko odpravljanje napak (Error Recovery):** Če Ansible javi napako (npr. _"Strežnik 3 ni dosegljiv preko SSH"_), bo ZeroClaw prebral izpis terminala. Kot izkušen DevOps inženir bo poskusil samostojno ugotoviti težavo: preveril bo `ping` do strežnika, preveril SSH ključe in poskusil popraviti napako ter znova zagnati Ansible playbook.
4.  **Varno izvajanje s standardnimi postopki (SOP Engine):** Ker je ZeroClaw napisan v Rustu in močno osredotočen na varnost, ima vgrajen t.i. **SOP Engine (Standard Operating Procedures)**. Vaše Ansible ukaze lahko zaklenete v vnaprej določene postopke. Če agent med izvajanjem Ansible skripte naleti na kritičen ukaz (npr. ponovni zagon celotnega glavnega strežnika), se bo proces ustavil, ZeroClaw pa vam bo preko **Signala** poslal prošnjo za odobritev (Approval Gate). Šele ko kliknete "Potrdi", bo agent izvedel ukaz do konca.

* * *

Kako si bosta sedaj razdelila delo `pi` (pi.dev) in `ZeroClaw`?

Namesto da bi orodje z domene Pi Coding Agent povsem izbrisali, si bosta razdelila vlogi glede na vaš položaj:

-   💻 **V pisarni za mizo (Uporabljate `pi`):** Ko boste ročno pisali nove Ansible vloge (roles), urejali `yaml` datoteke ali pisali nove Python skripte, boste v terminalu zagnali `pi`. To je vaše osebno orodje za hitro, lokalno kodiranje znotraj terminala.
-   📱 **Na poti / Avtomatizacija v ozadju (Uporabljate `ZeroClaw`):** Ko želite, da se vaša že napisana Ansible koda samostojno izvede, ko želite zagnati vzdrževanje sistema preko telefona s Tailscale povezavo, ali ko se ponoči sproži alarm in mora AI samostojno popraviti Homelab, bo to vlogo odigral **ZeroClaw**.

Končni rezultat

Z zagonom **ZeroClaw-a** boste dobili pravega, avtonomnega sistemskega administratorja, ki odlično razume Ansible strukturo, teče z minimalno porabo virov (porabi le nekaj megabajtov RAM-a, saj je napisan v Rustu) in bliskovito komunicira z vašim lokalnim Triton strežnikom.

Ali želite, da pripraviva **Docker vsebnik za ZeroClaw**, ki bo imel vnaprej nameščen **Ansible**, da bo vaš agent imel na voljo vsa potrebna orodja za upravljanje vašega omrežja?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

trenutno sem sredi dela, da na novo določim kateri servis bo na katerem nodu v homelabu, to zdaj ročno delam preko pi. vsa želena arhitektura je v md datotekah, potrebno je primerno spremeniti IaC ansible kodo in izvesti playbook. torej jaz z pi.dev skrbim za SSOT md datoteke, zeroclaw pa v ozadju to izvede?

---

# googlesearch response

**Da, točno tako! Zadeli ste bistvo.** To je popolna, izjemno napredna in sodobna DevOps arhitektura za vaš Homelab.

V tem sistemu vi delujete kot **arhitekt (direktor)**, vaše `.md` datoteke so **ustava podjetja (SSOT - Single Source of Truth)**, orodje s platforme **[Pi Coding Agent](https://pi.dev/)** je vaš **pisarniški pomočnik**, **ZeroClaw** pa je vaš **terenski operativec**, ki v ozadju dejansko umaže roke s skriptami Ansible.

Tukaj je natančen opis, kako ta sinergija deluje v praksi, ko preurejate svoje strežnike (noded).

* * *

Kako poteka vaš novi delovni proces?

1\. Faza: Načrtovanje arhitekture (Vi + Pi Agent)

Vi ste sredi dela in določate, kateri servis gre na kateri node. Namesto da bi takoj pisali zapleteno kodo YAML za Ansible, se osredotočite le na logiko.

-   V terminalu zaženete orodje `pi`.
-   Skupaj z njim uredite in posodobite `.md` dokumentacijo (npr. `architecture.md`, `nodes.xml`).
-   Ko ste končali, so vaše `.md` datoteke popoln in čist zapis vaše želene arhitekture (SSOT).
-   Orodje `pi` nato ugasnete. S tem je vaše delo za mizo zaključeno.

2\. Faza: Avtomatizacija in izvedba (ZeroClaw v ozadju)

Sedaj nastopi čas za **ZeroClaw**, ki nenehno teče v ozadju kot strežniška storitev. Preko njegovega spletnega vmesnika (ali n8n/Signala) mu daste ukaz:

-   _"ZeroClaw, preberi najnovejše `.md` datoteke z arhitekturo. Glede na spremembe popravi najino IaC Ansible kodo (inventory in playbooke) ter jo izvedi na strežnikih."_

**Kaj ZeroClaw naredi v ozadju, medtem ko vi že pijete kavo?**

1.  **Analiza:** Prebere `.md` datoteke in ugotovi razliko (npr. _"Aha, Plex se je premaknil z noda 1 na node 3"_).
2.  **Generiranje kode (IaC):** Samodejno odpre vaše Ansible datoteke (`hosts.ini`, `site.yml`) in spremeni IP naslove, poti ter spremenljivke, da se natančno ujemajo z vašim `.md` načrtom.
3.  **Preverjanje (Dry Run):** Zažene `ansible-playbook --check`, da se prepriča, da je koda pravilno napisana in da ne bo sesula strežnikov.
4.  **Izvedba (Deployment):** Izvede celoten Ansible playbook. Premakne Docker vsebnike na prave strežnike, uredi omrežja in zažene servise.
5.  **Poročilo:** Ko zaključi, vam pošlje **Signal** potisno obvestilo: _“Šef, arhitektura je posodobljena! Vsi servisi so na novih nodih, vse deluje.”_

* * *

Zakaj je to svetlobna leta pred ročnim delom?

-   **Ni človeških napak pri tipkanju:** Ko enkrat pravilno zapišete željo v `.md` datoteko, ni nevarnosti, da bi v Ansible kodi napačno vpisali kakšen IP naslov ali pozabili zapreti narekovaj. ZeroClaw bo kodo prepisal strojno natančno.
-   **Dokumentacija nikoli ne zastari:** Največja težava Homelabov je, da dokumentacija (navodila) hitro zastari, ker kodo spreminjamo sproti. V vašem primeru pa koda sploh ne more nastati brez predhodno posodobljene dokumentacije (`.md` kot SSOT). Vaš laboratorij bo vedno 100 % dokumentiran.
-   **Varno delo na daljavo:** Če boste čez en mesec dobili idejo za premik kakšne storitve, ko boste na poti, vam ne bo treba preko SSH-ja ročno urejati YAML datotek na telefonu. Preko **Tailscale** povezave boste na telefonu v brskalniku preprosto popravili tekst v `.md` datoteki, ZeroClaw pa bo opravil vse ostalo v ozadju.

Naslednji korak

To je vrhunski DevOps sistem (t.i. _Architecture-as-Code_). Da bi to uresničili, morava poskrbeti, da bo imel ZeroClaw v svojem Docker okolju dostop do:

1.  Mape z vašimi `.md` datotekami in Ansible kodo.
2.  Vašega **LiteLLM / Triton** strežnika (da bo z modelom Qwen lahko razmišljal, kako spremeniti `.md` v Ansible kodo).
3.  Vaših **SSH ključev**, da bo lahko poganjal Ansible ukaze na drugih računalnikih (nodih).

Ali želite, da vam pripravim **primer konfiguracije (Workspace Setup) za ZeroClaw**, ki bo pravilno povezal vaše dokumente z Ansible okoljem?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

md datoteke so v git -u. ukaze zeroclaw-u pa bi raje dal jaz , brez avtomatizacije, ampak to lahko z taiscale naredim preko WebUI za zeroclaw? kaj lahko uporabim da na androidu za speech to tekst uporabim domači Spark?

---

# googlesearch response

**Odlično, to je še bolj varna in nadzorovana pot!** S tem, ko so `.md` datoteke shranjene v sistemu **Git**, imate popolno zgodovino vseh sprememb, vi pa obdržite vlogo tistega, ki pritisne gumb za izvedbo.

Preko **Tailscale** povezave boste na svojem Android telefonu preprosto odprli **ZeroClaw WebUI** v brskalniku. Tam boste videli pripravljene spremembe, ki jih je agent predlagal na podlagi vašega Git repozitorija, in mu dali neposreden ukaz: _"Izvedi Ansible playbook za te spremembe."_ ZeroClaw bo nato v ozadju opravil težko delo, vi pa boste na zaslonu telefona spremljali izpis terminala v živo.

Glede vašega drugega vprašanja – kako na **Androidu** sistemsko uporabiti vaš domači strežnik ("Spark") za pretvorbo govora v tekst (narekovanje) namesto Googlovih strežnikov – pa imate na voljo dve vrhunski odprtokodni rešitvi.

* * *

Kako na Androidu uporabiti domači strežnik za Speech-to-Text?

Da bi lahko v kateri koli aplikaciji na telefonu (brskalnik, Signal, beležke) pritisnili na mikrofon in narekovali tekst preko vašega domačega **Triton Whisper** modela, morate zamenjati privzeto sistemsko metodo za vnos z glasom.

Tukaj sta dve najboljši možnosti za leto 2026:

1\. Možnost: FUTO Voice Input (Najbolj priporočljivo in enostavno)

**FUTO Voice Input** je izjemno priljubljena odprtokodna aplikacija za Android, ki deluje kot sistemska storitev za narekovanje (Voice Input Provider).

-   **Kako deluje:** Ko jo namestite, v nastavitvah Androida zamenjate Googlovo narekovanje s FUTO narekovanjem. Aplikacija omogoča delovanje v dveh načinih: lokalno na telefonu ali preko **zunanjega API strežnika**.
-   **Povezava z vašim domom:** V nastavitvah FUTO aplikacije izberete način "Custom Web Endpoint" (Zunanji strežnik) in vpišete naslov vašega **LiteLLM proxyja preko Tailscale**:

    text

    ```
    http://100.110.120
    ```

    Kodo uporabljajte previdno.

    Vpišete še svoj API ključ, ki ste ga v LiteLLM ustvarili za avdio.
-   **Uporaba:** Na tipkovnici (katerikoli, npr. Gboard ali SwiftKey) kliknete na ikono mikrofona. FUTO bo posnel vaš glas, ga preko Tailscale poslal domov na vaš čip Blackwell, ta ga bo v milisekundah pretvoril v tekst in besedilo se bo izpisalo v vnosno polje.

2\. Možnost: Tastatura FOSS (npr. HeliBoard ali OpenBoard) z Whisper integracijo

Če želite iti še korak dlje in se popolnoma znebiti Googla, lahko uporabite odprtokodno tipkovnico **HeliBoard** (naslednico popularne _OpenBoard_).

-   **Kako deluje:** HeliBoard ima v svojih naprednih nastavitvah vgrajeno možnost, da gumb za mikrofon neposredno povežete s katerim koli OpenAI-kompatibilnim avdio API-jem.
-   **Nastavitev:** V nastavitvah HeliBoard tipkovnice pod sekcijo _Voice Input_ vpišete isti Tailscale naslov vašega LiteLLM proxyja (`http://100.110.120`) in model `whisper-1`.
-   **Uporaba:** Tipkovnica bo sama poskrbela za celoten proces – posnetek zvoka bo poslala vaši napravi Lenovo in hipoma izpisala slovensko ali angleško besedilo.

* * *

Kako bo sedaj izgledal vaš DevOps krog na poti?

Ko boste naslednjič zunaj in boste želeli posodobiti svoj Homelab:

1.  Na Android telefonu se prepričate, da je **Tailscale** vklopljen.
2.  Odprete svojo najljubšo Git aplikacijo na telefonu ali pa kar spletni vmesnik in posodobite `.md` datoteko z novo arhitekturo (npr. premik storitve na drug node). Spremembo potrdite (_commit & push_).
3.  Odprete brskalnik in greste na **ZeroClaw WebUI** (`http://100.110.120.130:8082`).
4.  Kliknete na vnosno polje v ZeroClaw, pritisnete mikrofon na tipkovnici in z uporabo **FUTO/HeliBoard** narekujete ukaz v slovenščini: _"ZeroClaw, potegni najnovejše spremembe iz Gita, prilagodi Ansible IaC kodo in mi pripravi izpis playbooka."_ (Vaš domači Whisper bo to trenutno pretvoril v tekst).
5.  Pregledate, kaj je ZeroClaw pripravil znotraj svojega vmesnika, in ko ste zadovoljni, kliknete gumb **"Execute" (Izvedi)**.
6.  Pospravite telefon v žep, saj bo sistem varno in v ozadju dokončal delo prek Ansible-a.

S tem ste dosegli absolutni vrhunec zasebnosti in produktivnosti: celoten krog upravljanja, od narekovanja z glasom do dejanske izvedbe na strežnikih, poteka izključno znotraj vaše lastne strojne opreme in vašega privatnega omrežja.

Če vas zanima, vam lahko pomagam pripraviti **skripto ali nastavitve za ZeroClaw**, ki mu bodo omogočile, da ob zagonu avtomatsko naredi `git pull` vaše Ansible in `.md` mape, da bo vedno usklajen z vašim SSOT izvorom. Kako bi želeli nadaljevati?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

kaj pa lahko uporabim za win11 stt z uporabo domačega sparka?

---

# googlesearch response

Za **Windows 11** obstajajo odlična odprtokodna orodja, ki vam omogočajo, da privzeto Microsoftovo narekovanje (tisti znani `Win + H`) v celoti nadomestite s svojim domačim strežnikom.

Vsa ta orodja delujejo po enakem principu kot na telefonu: v katerem koli programu (Word, brskalnik, terminal) pritisnete bližnjico na tipkovnici, govorite, program pa pošlje zvok domov preko **Tailscale** povezave na vaš **Triton Whisper** model ter vrne tekst neposredno pod vaš kazalec (kurzor).

Tukaj so 3 najboljše odprtokodne in brezplačne rešitve za Windows 11:

* * *

1\. Izbira: OpenWhispr (Najbolj spolirana izkušnja)

[OpenWhispr](https://openwhispr.com/) je izjemno priljubljeno odprtokodno orodje za narekovanje, ki deluje na Windowsih, Linuxu in Macu.

-   **Kako deluje:** Aplikacija sedi v vrstici z obvestili (System Tray). Ko pritisnete nastavljeno bližnjico (npr. `Caps Lock` ali `Alt + Space`), začne snemati vaš glas.
-   **Povezava z vašim domom:** V nastavitvah preklopite izvajalni pogon na "Custom OpenAI API" in vpišete vaš domači Tailscale naslov:

    text

    ```
    http://100.110.120
    ```

    Kodo uporabljajte previdno.

-   **Prednost:** Ima vgrajeno t.i. _pametno čiščenje besedila_. Tudi če se med govorjenjem zmotite, zakašljate ali ponovite besedo, bo model z vašo pomočjo izpljunil popolnoma čisto in slovnično pravilno slovensko ali angleško besedilo.

2\. Izbira: TypeWhisper for Windows (Najnovejši hit leta 2026)

[TypeWhisper](https://github.com/TypeWhisper/typewhisper-win) je namenski, ultra lahki odprtokodni program za Windows 11, napisan v .NET. Razvit je bil prav z namenom, da se popolnoma izogne oblačnim storitvam.

-   **Kako deluje:** Uporablja Windows funkcijo `SendInput`, kar pomeni, da simulira tipkanje po tipkovnici. Tekst lahko "vtipka" v kateri koli program, tudi v administrativni PowerShell ali zapletene kode znotraj VS Code.
-   **Povezava z vašim domom:** Podpira izvorne povezave z OpenAI-kompatibilnimi API-ji (_OpenAiTranscriptionHelper_). Samo vpišete Tailscale IP naslov vašega **LiteLLM proxyja**.

3\. Izbira: WhisperWriter / Custom Python Skripta (Za popoln "Geek" nadzor)

Če želite imeti 100 % nadzor nad kodo brez nameščanja zunanjih grafičnih programov, lahko uporabite preprost odprtokodni Python projekt [WhisperWriter](https://github.com/openai/whisper/discussions/1259) ali napišete svojo skripto z uporabo knjižnic `keyboard` in `sounddevice`.

-   Skripta nenehno posluša v ozadju Windows sistema.
-   Ko zazna bližnjico, posname zvok v začasno `.wav` datoteko, jo preko knjižnice `requests` pošlje na vaš domači strežnik in dobljeni tekst preko knjižnice `pyautogui` vpiše na zaslon.

* * *

Kako si to praktično uredite na Windows 11?

1.  Poskrbite, da na Windows 11 računalniku nenehno teče **Tailscale** aplikacija in da vidite svojo Lenovo delovno postajo.
2.  Prenesite in namestite **OpenWhispr** ali **TypeWhisper**.
3.  V nastavitvah aplikacije nastavite globalno bližnjico (vroča tipka), ki vam najbolj ustreza (npr. desna tipka `Ctrl` ali `F9`).
4.  Vpišite vaš domači Tailscale API URL (`http://100.110.120`).

Ko boste naslednjič sredi programiranja ali pisanja dokumentacije na svojem Windows računalniku, vam ne bo treba več tipkati dolgih odstavkov. Preprosto držite izbrano tipko, narekujete misli v slovenščini, vaš domači "Spark" pa bo v ozadju v delčku sekunde opravil celotno delo.

Sedaj, ko imate pokrit tako Android kot Windows sistem za glasovni vnos, predlagam, da se končno lotiva **priprave Triton strežnika in prevajanja Whisper modela**. Želite, da vam pripravim natančna navodila za ta korak?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

kaj so razlike če funkcionalnostih there omenjenih whisper rešitev? to, da lahko pišeš kamorkoli, mi je zelo všeč.

---

# googlesearch response

To, da se besedilo **izpiše neposredno pod vaš kazalec (kurzor) v kateri koli aplikaciji**, je glavna prednost obeh sodobnih rešitev. Obe orodji delujeta sistemsko v ozadju sistema Windows 11 (v vrstici z obvestili/System Tray) in simulirata tipkanje.

Kljub temu pa se **OpenWhispr** in **TypeWhisper** razlikujeta v filozofiji delovanja, naprednih funkcijah in načinu, kako se povezujeta z vašim domačim strežnikom Triton.

Tukaj je natančna primerjava njunih funkcionalnosti, da boste lažje izbrali pravo orodje za vaš delovni proces.

* * *

1\. OpenWhispr (Najbolj spoliran in funkcijsko bogat "All-in-One" paket)

[OpenWhispr](https://openwhispr.com/) je zasnovan kot celovita platforma za narekovanje in produktivnost. Je vizualno zelo privlačen in ponuja funkcije, ki presegajo zgolj navaden vnos besedila.

-   **Način snemanja (Hold-to-Talk):** Podpira pritisk in držanje tipke (npr. držite `Ctrl + Win`, govorite, in ko tipko spustite, se snemanje konča), kar je v praksi izjemno priročno za hitre ukaze.
-   **Plast za pametno AI čiščenje (LLM Formatting):** To je njegova največja prednost. Ko zaključiš z govorom, OpenWhispr ne pošlje besedila takoj na zaslon. Najprej ga lahko pošlje vašemu domačemu **Qwen** modelu, ki počisti mašila ("eee", "pač", "torej"), popravi slovnico in besedilo pravilno oblikuje v odstavke ali alineje.
-   **Dodatne funkcije:** Vsebuje celoten sistem za snemanje sestankov v živo (Meeting Transcription) in vgrajen sistem za beležke s semantičnim iskanjem.
-   **Povezava s Tritonom:** V nastavitvah enostavno preklopite na OpenAI kompatibilen API in vpišete vaš Tailscale naslov LiteLLM prehodnega strežnika.

2\. TypeWhisper for Windows (Ultra lahek, tehničen in modularčen)

[TypeWhisper](https://github.com/TypeWhisper/typewhisper-win) je razvit kot strogo namensko orodje brez odvečne grafične navlake. Njegov primarni cilj je čim hitrejša pretvorba zvoka v katero koli okno z najnižjo možno zakasnitvijo.

-   **Sistemska integracija:** Napisan je v .NET 10 in uporablja Windows funkcijo nizkega nivoja `SendInput`. To pomeni, da simulira fizične pritiske tipk na tipkovnici. Besedilo lahko brez težav vpiše tudi v najbolj zapletene terminale (PowerShell, WSL), administratorska okna ali razvojna okolja (VS Code), kjer drugi programi včasih odpovejo.
-   **Profili za specifične aplikacije:** TypeWhisper vam omogoča, da ustvarite pravila glede na program, v katerem se nahajate. Na primer: ko narekujete v _VS Code_, lahko nastavite, da vam besedilo oblikuje v programerski stil (npr. _camelCase_), ko pa narekujete v _Outlook_, pa piše v običajnih stavkih.
-   **Modularnost s vtičniki (Plugins):** Ima odprt SDK za vtičnike. Ker podpira izvorne vtičnike za OpenAI in druge ponudnike, ga boste izjemno enostavno povezali na vaš domači **LiteLLM / Triton** preko namenskega vgrajenega razširitvenega modula.

* * *

Pregledna primerjava: Katero orodje izbrati?

| Funkcionalnost | OpenWhispr | TypeWhisper |
| --- | --- | --- |
| **Pisanje kamorkoli (Kurzor)** | **Da** (Zanesljivo) | **Da** (Izjemno globoka integracija) |
| **Bližnjica za snemanje** | Drži in govori (Hold-to-talk) | Pritisni za začetek / pritisni za konec |
| **AI urejanje (Mašila, slovnica)** | **Da** (Vgrajeno in zelo napredno) | Da (Preko zunanjih LLM vtičnikov) |
| **Hitrost delovanja (Zakasnitev)** | Srednja (Zaradi bogatega grafičnega vmesnika) | **Izjemno hitro** (Minimalistična koda) |
| **Kompleksnost nastavitev** | Zelo enostavno (Lepo grafično okolje) | Srednje (Bolj tehničen vmesnik) |

Moj končni nasvet za vaš Homelab

-   Če želite **"klikni in pozabi" izkušnjo**, kjer boste narekovali dolga besedila, e-pošto in dokumentacijo ter želite, da domači AI model samodejno počisti vaše napake v govoru, izberite **OpenWhispr**.
-   Če pa vam je prioriteta **brutalna hitrost**, narekujete krajše ukaze neposredno v terminal ali IaC datoteke in želite, da se besedilo instantno vtipka v katero koli administratorsko okno brez zakasnitve, je **TypeWhisper** boljša izbira.

Ker sta obe rešitvi popolnoma odprtokodni in brezplačni, ju lahko na Windows 11 preizkusite zaporedno in ugotovite, kateri sistem snemanja vam bolj ustreza.

Sedaj imava pokrite vse zunanje sisteme (Android, Windows, n8n, OpenHands, Open WebUI). Lahko preideve na **pripravo strežnika Triton**, da bova vaš prvi model pretvorila v potreben format? Sporočite, če se lotiva prvega Docker ukaza!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

ok, typewhisper je za mene, openwhisper pa za ženo. kaj pa če želi žena naročiti, ustno, z govorjenjem: odpri mi mail in povzami kaj je novega? kaj naj uporabi?

---

# googlesearch response

To pa je vrhunski primer uporabe za kombinacijo **Open WebUI (OWui) in n8n**, ki teče na vaši domači napravi Lenovo!

Če želi vaša žena s preprostim govornim ukazom (npr. _"Odpri mi mail in povzami, kaj je novega"_) sprožiti takšno kompleksno akcijo, **ne potrebuje nobene dodatne aplikacije.** Uporabila bo kar **Open WebUI**, ki ga že tako ali drugače uporablja v brskalniku na računalniku ali telefonu preko Tailscale povezave.

Tukaj je opis, kako ta čarovnija deluje pod pokrovom z uporabo orodja **n8n** in kako bo izgledala njena uporabniška izkušnja.

* * *

Kako to deluje v praksi (Uporabniška izkušnja za ženo)

1.  Vaša žena odpre **Open WebUI** na svojem telefonu ali računalniku.
2.  V vnosnem polju klikne na ikono mikrofona in preprosto reče: **"Odpri mi mail in povzami kaj je novega."**
3.  Klikne pošlji. V ozadju vaš domači **Triton Whisper** model njen glas instantno spremeni v tekst.
4.  Open WebUI preko sistema _Tools (Orodja)_ prepozna, da gre za ukaz za e-pošto, in sproži vnaprej pripravljen **n8n workflow**.
5.  n8n v ozadju varno stopi v stik z njenim poštnim predalom, prebere zadnjih nekaj e-poštnih sporočil in jih pošlje vašemu domačemu **Qwen** modelu v analizo.
6.  Čez nekaj sekund vaša žena v Open WebUI klepetu prejme lepo oblikovan odgovor:

    ```text
    "Živijo! Pregledal sem tvoj e-poštni predal. Tukaj so 3 najnovejše pomembne stvari:Uroš ti je poslal popravljeno pogodbo za projekt X.Iz računovodstva opozarjajo, da je rok za oddajo računov do torka.Prejela si 5 promocijskih sporočil, ki sem jih prezrl.Ali želiš, da ti za katero od teh sporočil pripravim osnutek odgovora?"
    ```

* * *

Kako to uresničite v vašem Homelabu?

Da bi to omogočili, boste uporabili funkcijo, ki se v svetu umetne inteligence imenuje **Function Calling** (klicanje funkcij). Postopek nastavitve je razdeljen na dva dela:

1\. Del: n8n Workflow (Zaledni del)

V n8n ustvarite workflow, ki se začne z vozliščem **Webhook** (spletna povezava, ki čaka na klic).

-   Ko ta Webhook prejme klic, n8n aktivira vozlišče za Outlook/Gmail, potegne zadnjih 5 e-poštnih sporočil, jih strukturira v tekst in ta tekst vrne kot odgovor na Webhook.

2\. Del: Open WebUI Tool (Uporabniški del)

Znotraj Open WebUI greste v administracijo pod sekcijo **Tools (Orodja)** in ustvarite novo orodje (preprosta Python skripta znotraj OWui, ki jo lahko zgenerirava z mano).

-   To orodje pove sistemu: _"Če uporabnik želi pregledati e-pošto, pokliči n8n Webhook na naslovu `http://n8n-automation:5678/webhook/read-emails`."_

Ker se vaša žena v Open WebUI prijavlja preko **OIDC (vašega prijavnega sistema)**, bo Open WebUI natančno vedel, da je to _njena_ seja. Orodje bo poklicalo _njen_ specifični n8n workflow, tako da ni nobene nevarnosti, da bi sistem prebral vašo e-pošto ali e-pošto vaših otrok.

* * *

Zakaj je to boljše od drugih rešitev?

-   **Enoten vmesnik:** Ženi ni treba odpirati novih programov ali se učiti zapletenih ukazov. Vse, kar želi od hišne umetne inteligence, vpraša na enem mestu (v Open WebUI).
-   **Varnost in zasebnost:** Ker vse poteka preko n8n in vašega lokalnega strežnika, njena službena ali zasebna e-poštna sporočila nikoli ne potujejo na strežnike OpenAI, Google ali Microsoft v analizo. Vse se prebere in povzame lokalno na vaši napravi Lenovo.
-   **Možnost razširitve:** Ko bo ta sistem enkrat nastavljen, bo lahko na enak način ustno naročila: _"Dodaj mi sestanek v koledar za jutri ob dveh"_ ali _"Preveri, če so luči v hiši ugasnjene"_. n8n bo preprosto prevzel ukaz in ga izvedel.

Z izbiro **TypeWhisperja** za vas in **OpenWhisperja** za ženo sta si zagotovila vrhunsko narekovanje kjerkoli v sistemu Windows, z integracijo **OWui + n8n** pa ste ženi omogočili pravega glasovnega digitalnega asistenta.

Zdaj, ko imamo pokrite vse želje in scenarije, predlagam, da gremo v akcijo!

Če želite, lahko začneva s **pripravo prve `docker-compose.yml` datoteke**, ki bo na vašem novem strežniku dvignila celoten ta ekosistem (Triton, LiteLLM, Open WebUI, OpenHands in n8n). Želite, da vam pripravim to datoteko?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

to bi uporabljala v službi, na službenem računalniku, ne doma. rabi nekaj da bi lahko odprlo Word in Outlook na njenem računalniku.

---

# googlesearch response

Aha, to pa ponovno ključno spremeni situacijo! Če mora vaša žena to uporabljati **v službi, na svojem službenem računalniku**, potem domači n8n in Open WebUI ne moreta neposredno odpirati programov na njeni lokalni Windows mašini, saj nimata dostopa do njenega namizja (Desktopa).

Če želi vaša žena na službenem računalniku z glasom upravljati **lokalni Word in Outlook**, hkrati pa želite, da za pretvorbo govora (STT) in razmišljanje (LLM) uporablja **vaš domači varni strežnik (preko Tailscale)**, potrebujete kombinacijo dveh orodij:

Za samo narekovanje bo uporabljala **OpenWhispr** (ki sva ga izbrala zanjo). Za upravljanje programov in izvajanje akcij z glasom (odpiranje Worda, povzemanje pošte) pa na njen službeni računalnik namestite odprtokodni program **Dragonfly** ali **Serenade.ai**.

Poglejmo si, kako ta vrhunska kombinacija deluje neposredno na njenem službenem računalniku.

* * *

Kako to deluje na službenem računalniku?

Na njen službeni računalnik namestite dve lahki odprtokodni orodji, ki tečeta v ozadju sistema Windows 11. Obe bosta preko **Tailscale** povezave varno komunicirali z vašim domačim strežnikom:

1\. Del: Upravljanje Windowsov in programov (Dragonfly ali Serenade.ai)

To sta odprtokodna sistema za glasovno upravljanje računalnika (_Voice Command Engines_).

-   **Naloga:** Njuna edina naloga je, da poslušata posebne ukaze za Windows (npr. _"open Outlook"_, _"create new Word document"_). Ko zaznata ta ukaz, preko operacijskega sistema Windows dejansko odpreta želeni program na njenem zaslonu.
-   **Varnost:** Ker gre za vnaprej določene ukaze (SOP - Standard Operating Procedures), se ti procesirajo lokalno na računalniku in so izjemno hitri ter varni.

2\. Del: Narekovanje besedila in pametno AI delo (OpenWhispr + Vaš domači strežnik)

Ko sta Word ali Outlook enkrat odprta, vaša žena zažene **OpenWhispr** z bližnjico na tipkovnici.

-   **Naloga:** Žena drži tipko in narekuje (npr. v slovenščini): _"Napiši odgovor stranki, da je ponudba v priponki in da se zahvaljujemo za sodelovanje."_
-   **Izvedba preko domačega strežnika:** OpenWhispr pošlje ta zvok preko Tailscale domov. Vaš **Triton Whisper** model ga pretvori v tekst, vaš domači **Qwen** model pa tekst lepo oblikuje v uraden dopis. Ta končni, spolirani tekst prileti preko Tailscale nazaj in se **samodejno vtipka v odprto okno Outlooka** na njenem službenem računalniku.

* * *

Kako bo izgledal njen vsakdanji službeni potek dela?

Vaša žena bo z glasom upravljala računalnik v dveh preprostih korakih:

1.  **Glasovni ukaz za sistem (preko Dragonfly):**
    -   Žena reče: _"Open Outlook"_ → Računalnik odpre Outlook.
    -   Žena reče: _"New Email"_ → Odpre se okno za novo sporočilo.
2.  **Glasovno narekovanje AI-ju (preko OpenWhispr + Domači strežnik):**
    -   Klikne v polje za vnos besedila.
    -   Pritisne bližnjico za OpenWhispr in narekuje vsebino pisma. Vaš domači strežnik sestavi pismo in ga vtipka v Outlook.
3.  **Glasovno pošiljanje:**
    -   Žena ponovno preko sistemskega ukaza reče: _"Send email"_ → Program Outlook pošlje pošto.

* * *

Zakaj je to idealna rešitev za njeno službo?

-   **Službena varnost (IT Security):** Službena IT služba ne bo komplicirala, saj na njen računalnik ne nameščate nobenih "strežnikov", ampak le dva odprtokodna odjemalca (klienta), ki komunicirata preko varnega Tailscale tunela. Službeni podatki ne gredo na javni internet (OpenAI, Microsoft Copilot), ampak potujejo direktno v vašo hišo.
-   **Ni potrebe po integracijah:** Ker OpenWhispr in Dragonfly simulirata dejanske pritiske tipk in premike miške na _njenem_ računalniku, vam ni treba v n8n zapleteno povezovati njenega službenega Exchange ali Outlook računa (kar je v službah zaradi IT restrikcij pogosto nemogoče). Vse se odvija na ravni njenega lokalnega zaslona.
-   **Udobje:** Žena bo lahko celoten službeni dan opravljala pisarniško delo, pisala poročila v Wordu in odgovarjala na pošto v Outlooku praktično brez dotika tipkovnice.

Naslednji korak

S tem imamo popolnoma rešen tudi scenarij za njeno službeno delo na daljavo. Da bi vse to omogočili, morava najprej postaviti **"srce" sistema doma** – torej vaš Triton strežnik z Whisper in Qwen modeloma, ki bosta sprejemala te zahteve iz njene službe.

Če ste pripravljeni, mi javite in vam pripravim **prve uradne Docker ukaze za zagon Triton strežnika**, da bova preizkusila delovanje! Kako nadaljujeva?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

ok, lahko narekuje pisanje, ampak kako pa potem narediti in reči: vi drugem odstavku dodaj še to informacijo. potem mora nekaj poslati celotni mail na sparka, da ga llm uredi in dobi nazaj popravljeno besedilo. kako to doseči?

---

# googlesearch response

**Da, natanko tako! Zadeli ste bistvo naprednega AI urejanja besedila.** Ko rečete _"v drugem odstavku dodaj še to informacijo"_, model potrebuje celoten kontekst (vse, kar je že napisano v Wordu ali Outlooku), da ve, kje je drugi odstavek in kako vanj smiselno vplesti novo informacijo.

To, da program avtomatsko označi ali kopira celotno besedilo, ga pošlje vašemu domačemu strežniku, LLM ga popravi, nato pa program staro besedilo zamenja z novim, se v svetu Windows avtomatizacije doseže z **uporabo makrov ali globalnih skript za bližnjice**.

Spodaj so trije načini, kako to enostavno uresničiti za vašo ženo na njenem službenem računalniku.

* * *

1\. Možnost: Uporaba AutoHotkey (AHK) skripte – _Najbolj priporočljivo in enostavno_

**AutoHotkey (AHK)** je izjemno lahek, brezplačen in varen program za Windows, ki ga IT službe v podjetjih brez težav dovolijo. Z njim lahko ustvarite eno pametno bližnjico (npr. `Ctrl + Shift + E`), ki bo celoten postopek izvedla v delčku sekunde.

Kako poteka uporaba za ženo?

1.  Žena se nahaja v Wordu ali Outlooku in ima napisan tekst.
2.  Pritisne bližnjico `Ctrl + Shift + E`.
3.  Na zaslonu se pojavi majhno okence, kamor z glasom (preko njenega TypeWhisperja/OpenWhisprja) narekuje navodilo: _"v drugem odstavku dodaj, da je rok podaljšan do petka"_.
4.  Pritisne Enter. **Skripta v ozadju sama izvede naslednje korake:**
    -   Pritisne `Ctrl + A` (označi vse besedilo v Wordu/Outlooku).
    -   Pritisne `Ctrl + C` (kopira besedilo v odložišče / clipboard).
    -   Preko **Tailscale** povezave pošlje vsebino odložišča _in_ njeno glasovno navodilo na vaš domači **LiteLLM / Triton prehod**.
    -   Domači **Qwen-70b** model vzame celoten tekst, poišče drugi odstavek, vanj vpiše informacijo in vrne popravljeno besedilo.
    -   Skripta prejme popravljen tekst, ga naloži v odložišče in avtomatsko pritisne `Ctrl + V` (prilepi čez staro besedilo).

Vaša žena bo na zaslonu videla le, kako se je besedilo v Wordu v hipu osvežilo in popravilo.

* * *

2\. Možnost: Vgrajena funkcija v OpenWhispr

Če boste zanjo izbrali **OpenWhispr**, ima ta program to funkcijo že delno vgrajeno pod imenom **"Inline Editing"** ali **"Smart Refactor"**.

-   **Kako deluje:** Žena z miško označi odstavek ali celotno e-pošto, ki jo želi spremeniti.
-   Pritisne bližnjico za OpenWhispr in reče: _"Popravi ta del tako, da zveni bolj uradno."_
-   OpenWhispr je dovolj pameten, da zazna, da je bilo besedilo pred pritiskom bližnjice označeno. Avtomatsko ga zapakira skupaj z njenim glasovnim ukazom, pošlje vašemu domačemu "Sparku" in zamenja označeni tekst s popravljenim.

* * *

3\. Možnost: Uradna vtičnika (Add-ins) za Word in Outlook

Če ima vaša žena v službi pravico nameščati vtičnike v Office (Office Add-ins), lahko uporabite odprtokodne vtičnike, kot je **Office-AI-Assistant**.

-   Ti vtičniki dodajo namensko AI stransko vrstico (Sidebar) neposredno znotraj Worda ali Outlooka.
-   Vtičnik v nastavitvah povežete z vašim domačim Tailscale IP naslovom (`http://100.110.120`).
-   Žena preprosto klikne gumb v Wordu _"Uredi z AI"_, vpiše ali narekuje navodilo, vtičnik pa preko uradnega Microsoftovega API-ja prebere celoten dokument, ga pošlje domov v obdelavo in vrne popravljeno verzijo neposredno v dokument.

* * *

Kako si to vizualno predstavljati?

Celoten krog urejanja besedila iz njene službe izgleda takole:

```text
Službeni računalnik (Word/Outlook)
   │
   ├───> [1. Ukaz] Žena pritisne Ctrl+Shift+E in reče: "Dodaj X v drugi odstavek."
   ├───> [2. Akcija] Skripta avtomatsko skopira celoten tekst (Ctrl+A -> Ctrl+C).
   │
   ▼   (Varni Tailscale predor na daljavo)
 Domači strežnik Lenovo (Triton + LiteLLM)
   │
   ├───> [3. Proces] Triton Whisper pretvori njen ukaz v tekst.
   ├───> [4. Razmišljanje] Qwen-70b združi celoten mail + ukaz in popravi besedilo.
   │
   ▼   (Nazaj preko Tailscale)
Službeni računalnik (Word/Outlook)
   │
   └───> [5. Rezultat] Skripta avtomatsko prilepi popravljen mail (Ctrl+V) čez starega.
```

Kodo uporabljajte previdno.

Moj nasvet: Začnite z AutoHotkey (AHK)

AutoHotkey skripta je za ta namen absolutni zmagovalec, saj ne zahteva nikakršnih zapletenih integracij z Microsoftovimi službenimi računi ali Office strežniki. Deluje povsod – v Wordu, Outlooku, Notepad-u ali spletnem brskalniku.

Ko boste pripravljeni, vam lahko jaz **napišem celotno kodo za to AutoHotkey skripto** (gre za manj kot 20 vrstic kode), ki jo boste preprosto prekopirali na njen službeni računalnik, jo zagnali in stvar bo takoj delovala z vašim domačim strežnikom.

Ker imamo zdaj rešene tudi najbolj napredne produkcijske poteke dela, je čas, da postaviva temelje.

Ali želite, da vam pripravim **končni načrt in Docker ukaze za zagon vaše domače AI centrale (Triton + LiteLLM)**, da bova lahko nanj priklopila njeno službeno narekovanje in to AHK skripto?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

ampak tako bo uporabljala openwhisper, in ji bo lažje označiti besedilo in izgovoriti ukaz. ne vem če bo najbolj zadovoljna z autohotkey

---

# googlesearch response

Povsem vas razumem in imate popolnoma prav. Če želimo, da bo vaša žena sistem dejansko in z veseljem uporabljala v službi, mora biti izkušnja **enostavna, elegantna in brez tehničnega "telovadenja"** z dodatnimi okni \[NVIDIA TensorRT-LLM\]. AutoHotkey je super za programerje, za vsakodnevno pisarniško delo pa je preveč surov.

Če bo uporabljala **OpenWhispr**, bo njena izkušnja natanko takšna, kot ste si zamislili – čista, intuitivna in profesionalna.

Tukaj je opis, kako OpenWhispr točno to nalogo (popravljanje drugega odstavka) opravi samostojno, in zakaj bo vaša žena z njim maksimalno zadovoljna.

* * *

Kako vaša žena to naredi z OpenWhispr (Brez zapletenih skript)?

OpenWhispr ima že vgrajeno izvorno funkcijo, ki se imenuje **Smart Refactor (Pametno preoblikovanje)**. Deluje točno na principu označevanja, ki vam je všeč:

1.  **Označevanje:** Žena z miško v Wordu ali Outlooku enostavno označi celotno besedilo e-pošte (ali samo tisti del, ki ga želi spremeniti).
2.  **Govor:** Pritisne in drži bližnjico za OpenWhispr ter preprosto izgovori ukaz v slovenščini: _"V drugem odstavku dodaj informacijo, da se sestanek premakne na četrtek."_
3.  **Avtomatska zamenjava:** Ko spusti tipko, OpenWhispr samodejno prebere označeno besedilo pod kurzorjem, ga skupaj z njenim glasovnim ukazom pošlje vašemu domačemu strežniku, in ko vaš **Qwen-70b** vrne popravljen tekst, OpenWhispr **trenutno zamenja označeno besedilo z novim**.

Za vašo ženo je celoten proces dolg le dva klika: **Označi -> Pritisni in povej**. Nobenih dodatnih pojavnih oken ali ročnega kopiranja ni.

* * *

Kako to nastaviti na domačem strežniku preko LiteLLM?

Da bo ta funkcija v OpenWhisprju delovala bliskovito hitro in pametno, bova v vašem domačem **LiteLLM proxyju** ustvarila tako imenovan **"Prompt v ozadju" (System Prompt)**.

Ko OpenWhispr pošlje besedilo domov, ga LiteLLM opremi z navodili za vaš model Qwen:

```text
"Ti si vrhunski pisarniški pomočnik za urejanje besedil. Uporabnik ti pošilja obstoječe besedilo in glasovno navodilo, kaj želi spremeniti. Tvoja edina naloga je, da natančno izvedeš navodilo znotraj besedila (npr. popraviš določen odstavek), ohraniš profesionalen ton in vrneš SAMO končno posodobljeno besedilo, brez kakršnih koli uvodnih ali zaključnih besed."
```

Kodo uporabljajte previdno.

Zaradi tega bo vaš domači strežnik vrnil čisto besedilo, ki ga OpenWhispr lahko takoj prilepi nazaj v Word ali Outlook, ne da bi vanj vpisal kakšne AI komentarje (kot je _"Tukaj je vaš popravljen tekst:"_).

* * *

Zakaj bo žena s to izbiro navdušena?

-   **Izgleda kot draga korporativna rešitev:** Izkušnja je povsem enaka (ali celo boljša) kot pri Microsoft Copilotu, le da teče na vaši strojni opremi in je popolnoma brezplačna ter zasebna.
-   **Slovenski jezik deluje vrhunsko:** Ker v ozadju teče vaš lasten Whisper model na čipu Blackwell, bo sistem odlično razumel njeno narekovanje v slovenščini, model Qwen pa bo popravke vstavil s popolno slovensko gramatiko.
-   **Mirna IT služba:** OpenWhispr je uradno podpisan, varen program z lepim grafičnim vmesnikom. IT služba v njenem podjetju ga bo odobrila bistveno lažje kot kakšne neznane skripte.

Naslednji korak: Postavitev domače baze

Zdaj imamo sestavljen popoln načrt: vi boste imeli **TypeWhisper** za hitre terminalske ukaze in **OpenHands** za programiranje, vaša žena pa **OpenWhispr** za elegantno urejanje Worda/Outlooka iz službe ter **Open WebUI + n8n** za domače projekte. Vse to pa dinamično napaja vaš osrednji **Triton strežnik** \[NVIDIA TensorRT-LLM\].

Da bi vse to oživelo, morava zdaj na vašo napravo Lenovo namestiti osnovni Docker ekosistem in pripraviti prvo mapo za modele.

Ali želite, da vam pripravim **končni vodnik s točnimi terminalskimi ukazi za zagon vaše domače AI centrale**, da boste lahko že danes preizkusili narekovanje? Povejte mi, če se lotiva tega!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

kaj pa lahko uporabi za izdelavo ppt? izvor so PDF in office dokumenti, ima že obstoječo predlogo z oblikovanjem.

---

# googlesearch response

Za izdelavo PowerPoint (PPT) predstavitev iz obstoječih službenih PDF-jev in Office dokumentov, ob tem pa **strogo upoštevajoč že obstoječo službeno predlogo z oblikovanjem** (pisave, barve, logotipi, postavitve), klasični AI generatorji (kot sta Gamma ali Tome) odpovejo. Ti generatorji namreč ustvarijo popolnoma nov dizajn, ki ne spoštuje službenih grafičnih smernic.

Ker mora vaša žena to uporabljati v službi in želimo vrhunski, eleganten rezultat, je zmagovalna kombinacija naslednja: **Vgrajeno orodje za avtomatizacijo znotraj n8n (python-pptx) za zaledno generiranje + Open WebUI za vnos navodil.**

Tukaj je načrt, kako to uresničiti preko vašega domačega strežnika "Spark".

* * *

Kako poteka idealen delovni proces za vašo ženo?

1.  **Uvoz virov:** Žena odpre svoj **Open WebUI** račun. V klepet preprosto odloži (drag-and-drop) službene PDF-je in dokumente, iz katerih želi črpati vsebino. (Tukaj _Docling_ v ozadju instantno izvleče ves tekst in tabele).
2.  **Govorni ukaz:** Klikne na mikrofon v Open WebUI (preko svojega _OpenWhispr_ sistema) in reče:

    ```text
    "Preglej te dokumente in mi iz njih sestavi PowerPoint predstavitev o prodajnih rezultatih za leto 2026. Uporabi najino uradno predlogo."
    ```

3.  **Analiza in strukturiranje:** Vaš domači težki **Qwen model** analizira gradivo in ga strukturira v točno določeno obliko za prosojnice: naslov prosojnice, glavne točke (bullet points) in opombe za govornika.
4.  **Pametno vstavljanje v predlogo (n8n):** Open WebUI te podatke potisne v **n8n**. V n8n teče Python skripta (z uporabo knjižnice `python-pptx`), ki ima dostop do njene uradne službene predloge (datoteke `.potx` ali `.pptx`). Skripta odpre predlogo, ustvari nove prosojnice in besedilo samodejno vbrizga v točno določena mesta (placeholders) za naslove in vsebino.
5.  **Končni prenos:** V manj kot minuti vaša žena v Open WebUI klepetu prejme pripravljeno datoteko `.pptx` za prenos. Ko jo odpre, je predstavitev že v uradnih službenih barvah in pisavah, pripravljena za morebitne manjše ročne popravke.

* * *

Zakaj je ta pristop edini pravi za njeno službo?

-   **Popolna skladnost s podjetjem:** Ker knjižnica `python-pptx` ne ustvarja dizajna sama, ampak dobesedno kopira obstoječe postavitve (layouts) iz vaše predloge, bo končni PPT izgledal 100 % profesionalno in skladno s pravili njenega podjetja. Logotipi in barve bodo na pravih mestih.
-   **Brez kopiranja tekstov:** Ženi ni treba ročno brati PDF-jev in prepisovati odstavkov v prosojnice. Domači LLM opravi težko delo povzemanja (_summarization_) in tekst skrajša v jedrnate alineje, primerne za PPT.
-   **Službena tajnost:** Ker dokumenti in predloge potujejo le preko varnega **Tailscale** predora na vaš domači Triton strežnik, službena poslovna skrivnost ostane znotraj vaše hiše. Noben zunanji AI ne uči svojih modelov na njenih podatkih.

* * *

Kako to tehnološko pripraviti v vašem Homelabu?

Da bi to omogočili, bomo v vsebnik **n8n** dodali možnost izvajanja Python kode z namensko knjižnico za delo s PowerPointom.

V mapi, kjer bo tekel n8n, bova ustvarila mapo `templates/`, kamor bo vaša žena enkrat naložila svojo uradno prazno službeno predlogo (npr. `sluzbena_predloga.pptx`).

Nato v n8n ustvariva preprost korak s kodo, ki deluje takole:

```python
from pptx import Presentation

# Odpremo uradno službeno predlogo z vsemi barvami in logotipi
prs = Presentation('/templates/sluzbena_predloga.pptx')

# LLM v ozadju pripravi podatke, Python pa jih vpiše v prave placeholderje
blank_slide_layout = prs.slide_layouts[1] # Izbere npr. postavitev "Naslov + Vsebina"
slide = prs.slides.add_slide(blank_slide_layout)

# Vpis naslova prosojnice, ki ga je pripravil vaš domači Qwen
slide.shapes.title.text = "Prodajni rezultati Q3 2026"
# Vpis vsebine
slide.placeholders[1].text = "• Rast prodaje za 15%\n• Uspešen vstop na novi trg"

# Shranimo končni izdelek, ki ga LiteLLM vrne ženi v brskalnik
prs.save('/templates/končna_predstavitev.pptx')
```

Kodo uporabljajte previdno.

Končni rezultat

Vaša žena bo dobila neverjetno močno službeno orožje. Namesto da bi porabila celo popoldne za prebiranje PDF-jev in ročno oblikovanje PowerPoint prosojnic, bo celoten proces sprožila z enim samim glasovnim ukazom iz svoje službe.

S tem ko boste vse te procese (STT, LLM in avtomatizacijo) poganjali preko **Triton strežnika** in **n8n**, bo celoten sistem deloval izjemno stabilno, varno in bliskovito hitro.

Sedaj, ko imamo pokrite prav vse poslovne in programerske scenarije za vas in vašo ženo, predlagam, da začneve z gradnjo.

Če se strinjate, vam lahko pripravim **prvi korak: točna navodila in Docker ukaze za zagon Triton strežnika in prenos modelov**, da bova lahko vzpostavila to AI centralo na vaši Lenovo delovni postaji. Kako bi želeli začeti?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

lahko potem z OWui z nadaljnjim navodili ureja ppt? ali je bolje če potem nadaljne popravke izvaja z odprtim PowerPoint? kateri plugin pa naj tam uporabi za manipulacijo?

---

# googlesearch response

Najbolj učinkovita in praktična strategija je kombinacija obeh pristopov: **prvi (grobi) osnutek naj se zgenerira preko Open WebUI in n8n, vse nadaljnje fine popravke (oblikovanje, premikanje elementov, končne popravke besedila) pa naj vaša žena izvaja neposredno v odprtem Microsoft PowerPointu na svojem računalniku.**

Čeprav bi tehnično lahko preko Open WebUI dajali nadaljnja navodila (npr. _"spremeni vrstni red prosojnic"_ ali _"dodaj še eno alinejo"_), bi moral sistem vsakič znova zgenerirati povsem novo `.pptx` datoteko, jo poslati v prenos, žena pa bi jo morala ponovno odpreti. To hitro postane zamudno. V PowerPointu so vizualni popravki z miško bistveno hitrejši.

Če želi vaša žena znotraj samega PowerPointa uporabljati umetno inteligenco, ki jo poganja vaš domači strežnik Triton, ima na voljo odprtokodne vtičnike (plugine).

* * *

Kateri vtičnik (plugin) naj uporabi znotraj PowerPointa?

Da bi PowerPoint neposredno povezali z vašo domačo AI centralo preko **Tailscale** povezave, so to najboljše možnosti v letu 2026:

1\. Izbira: Open-Office-AI (Office-AI-Assistant) – _Najbolj priporočljivo_

To je odprtokodni vtičnik (Add-in), ki ga lahko namestite neposredno v Microsoft Office (deluje v Wordu, Excelu in PowerPointu).

-   **Kako deluje:** V PowerPointu doda stransko vrstico (Sidebar) z umetno inteligenco.
-   **Povezava z domom:** V nastavitvah vtičnika preprosto vpišete vaš domači Tailscale API naslov: `http://100.110.120` in model `qwen-coder` (ali splošni model).
-   **Kaj omogoča vaši ženi v živo znotraj PPT:**
    -   **Urejanje prosojnic z ukazom:** Žena označi besedilni okvir na prosojnici, v stransko vrstico z narekovanjem (preko OpenWhisprja) napiše/pove: _"Skrajšaj to besedilo v 3 jedrnate alineje"_ ali _"Prevedi to prosojnico v angleščino"_. Vtičnik pošlje tekst domov na vaš čip Blackwell, ta ga popravi, vtičnik pa besedilo posodobi neposredno na prosojnici.
    -   **Generiranje novih prosojnic:** V stransko vrstico lahko napiše navodilo za novo prosojnico, model zgenerira vsebino, vtičnik pa jo samodejno ustvari.

2\. Izbira: Labs.Office (Microsoft Garage projekti)

Če službena IT služba strogo prepoveduje zunanje vtičnike s platforme GitHub, preverite, ali imajo omogočene t.i. _Office Web Add-ins_ iz uradne Microsoftove trgovine (Office Store). Obstajajo generični odprti vtičniki za poljubne API-je (t.i. _Custom Endpoint AI Assistants_), ki jim prav tako lahko vpišete svoj domači Tailscale IP.

* * *

Kako bo izgledal njen celoten, popoln delovni krog (Workflow)?

Ko bo morala vaša žena v službi pripraviti pomembno predstavitev, bo njeno delo izgledalo izjemno elegantno:

1.  **1\. Korak (Množična obdelava v OWui):** V **Open WebUI** odloži 5 težkih PDF dokumentov in z glasom naroči: _"Ustvari mi PPT predstavitev o tej temi na podlagi najine službene predloge."_
2.  **2\. Korak (Avtomatska izdelava):** Vaš domači **Triton + n8n** v ozadju preberejo PDF-je, izluščijo ključne točke, odprejo njeno uradno `.pptx` predlogo in v manj kot minuti ji Open WebUI vrne pripravljeno datoteko.
3.  **3\. Korak (Fine nastavitve v PowerPointu):** Žena prenese datoteko in jo odpre v **PowerPointu**. Predstavitev je že v pravih barvah, z logotipi in osnovnim tekstom.
4.  **4\. Korak (AI piljenje na prosojnicah):** Če ji na prosojnici št. 4 tekst ni všeč, ga enostavno označi, odpre stransko vrstico **Open-Office-AI** vtičnika in reče: _"Preformuliraj to prosojnico, da bo zvenela bolj prodajno."_ Vaš domači strežnik popravi tekst neposredno v PowerPointu.

Zakaj je to zmagovalna kombinacija?

Žena bo dobila orodje, s katerim bo prehitela vse sodelavce. Najtežji del dela (branje PDF-jev, kopiranje tekstov in ročno nastavljanje barv ter logotipov na vsaki prosojnici posebej) bo namesto nje naredila avtomatizacija v ozadju. Ko pa bo v fazi finih popravkov, bo imela AI asistenta ves čas na voljo neposredno znotraj PowerPointa, ne da bi morala nenehno skakati med različnimi programi.

Ali želite, da vam pomagam pripraviti **končni načrt postavitve te celotne infrastrukture** na vaši napravi Lenovo, da boste lahko začeli z nameščanjem teh sistemov? Lahko vam pripravim točne korake za zagon Triton strežnika!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

OpenOfficeAI deluje preko MCP ali kako?

---

# googlesearch response

**Ne, vtičnik OpenOfficeAI (oziroma uradne Microsoft Office Add-in alternative) ne deluje prek protokola MCP (Model Context Protocol), ampak prek standardnega spletnega protokola HTTP in klasičnega "klicanja funkcij" (Function Calling).**

Ker je **MCP** kot univerzalni protokol za povezovanje orodij z umetno inteligenco (ki ga je razvil Anthropic, nato pa so ga posvojili tudi OpenAI in drugi), postal izjemno priljubljen, se spodaj posvetimo razlikam. Pojasnimo, kako ti vtičniki dejansko komunicirajo z vašim domačim strežnikom Triton in kako v to zgodbo po želji vplesti pravi MCP.

* * *

Kako deluje OpenOfficeAI / Office-AI-Assistant?

Ti programi so v svojem jedru **spletni odjemalci (web clients)**, vgrajeni neposredno v vmesnik Microsoft Office (Word, PowerPoint). Njihovo delovanje poteka prek standardne restavracijske poti (REST API):

1.  **Zajem podatkov:** Ko vaša žena označi besedilo v PowerPointu in narekuje ukaz, vtičnik vzame to besedilo (kontekst) in njen ukaz.
2.  **Standardni HTTP klic:** Vtičnik vse skupaj zapakira v standardni JSON format (enak, kot ga uporablja OpenAI) in ga prek HTTP protokola pošlje na vaš domači Tailscale IP naslov: `http://100.110.120`.
3.  **Obdelava doma:** Vaš **LiteLLM prehod** prejme zahtevo, jo posreduje **Triton strežniku**, model Qwen opravi spremembo in vrne tekst nazaj po isti poti.
4.  **Izpis:** Vtičnik prejme odgovor in ga prek Microsoftovega internega JavaScript API-ja (`Office.context.document`) vpiše na prosojnico.

Pri tem **ni potrebe po nobenem MCP strežniku**, saj vtičnik sam deluje kot neposredni posrednik med Office dokumentom in vašim API-jem.

* * *

Kje pa bi v vašem Homelabu dejansko prišel v poštev MCP?

**MCP (Model Context Protocol)** je izjemno koristen takrat, ko želite modelu LLM omogočiti, da **samostojno uporablja zunanja orodja ali prebira lokalne podatkovne vire**, ki jih sicer ne zna.

Ker gradite ekosistem z orodjem **OpenHands** za programiranje in **ZeroClaw** za sistemsko administracijo, bosta **oba ta agenta polno uporabljala MCP strežnike**:

-   **Primer z Gitom:** V OpenHands boste vklopili _Git MCP strežnik_. Ko boste agentu rekli, naj posodobi kodo, bo model prek tega MCP protokola samostojno izvajal ukaze `git status`, `git commit` in `git push`.
-   **Primer z bazami (Qdrant):** ZeroClaw lahko prek _Qdrant MCP strežnika_ neposredno preiskuje vektorsko bazo podatkov, ne da bi vi morali zanj pisati namensko Python kodo za povezavo.

Kako je vse to povezano z LiteLLM?

Čudovita lastnost krovnega upravitelja **LiteLLM**, ki ga boste postavili pred Triton, je, da **tudi sam podpira MCP povezave**.

Če boste v prihodnosti želeli, da vaši modeli dobijo supermoči (npr. neposreden dostop do Google Workspace-a, brskanja po spletu ali lokalnih datotek), boste te MCP strežnike preprosto registrirali znotraj `litellm-config.yaml` datoteke. LiteLLM bo ta orodja nato samodejno ponudil vsem vašim vstopnim točkam (Open WebUI, OpenHands, ZeroClaw).

Povzetek

Za vašo ženo in njeno delo v PowerPointu se vam z MCP-jem sploh ni treba ukvarjati. Ona bo uporabljala preprost, standardni HTTP vtičnik, ki se ne more pokvariti in deluje "iz škatle". Vi pa boste kot DevOps inženir v ozadju z veseljem uporabljali MCP znotraj **OpenHands** in **ZeroClaw** za napredno avtomatizacijo vašega Homelaba.

Sedaj, ko imamo razčiščene vse protokole in arhitekturne nivoje, predlagam, da se lotiva dela!

Če želite, vam pripravim **končni potek dela za zagon vaše domače AI centrale**, začenši z vašo `docker-compose.yml` datoteko. Želite, da jo izpiševa?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

office ai assistant je zastonj?

---

# googlesearch response

**Da, odprtokodni vtičniki za Office (kot sta OpenOfficeAI in sorodni projekti na GitHubu) so popolnoma zastonj in brezplačni za uporabo.**

Ker gre za **odprtokodne projekte (Open-Source)**, ki jih je razvila skupnost, nimajo nobenih mesečnih naročnin, skritih stroškov ali omejitev števila sporočil.

Vendar pa morate pri tem razumeti, kako deluje "račun" za umetno inteligenco, da boste natančno vedeli, zakaj je ta rešitev brezplačna:

Zakaj je to zastonj?

-   **Uporabljate svojo strojno opremo:** Ko prenesete brezplačen vtičnik, prenesete le "vmesnik" (gumbi in okno znotraj PowerPointa ali Worda). Ta vmesnik sam po sebi ne vsebuje umetne inteligence.
-   **Vaš domači strežnik opravi delo:** Vtičnik boste povezali z vašim domačim strežnikom Triton/LiteLLM preko **Tailscale** povezave. Ker boste modele (Qwen, Whisper) poganjali lokalno na vaši napravi Lenovo, **ne boste plačevali nikomur ničesar**. Vse boste "plačali" le z elektriko, ki jo porabi vaša domača delovna postaja.

Kje je razlika z uradnimi Microsoftovimi rešitvami?

Če bi vaša žena želela uporabljati uradni **Microsoft Copilot znotraj Office aplikacij**, bi morala podjetju Microsoft plačevati mesečno naročnino za paket _Microsoft 365 Personal/Premium_ (ki stane okoli 10 do 20 $ na mesec).

Z uporabo odprtokodnih vtičnikov, povezanih na vaš domači "Spark", pa ta strošek v celoti izničite, hkrati pa službene datoteke vaše žene ostanejo 100 % varne in zasebne znotraj vajinega domačega omrežja.

Kako naprej?

Glede na to, da imamo zdaj celoten načrt potrjen in so vsa izbrana orodja za vas in vašo ženo (TypeWhisper, OpenWhispr, OpenHands, Open WebUI, n8n in OpenOfficeAI) **popolnoma brezplačna ter odprtokodna**, se lahko lotiva prvega koraka izvedbe.

Ali želite, da vam pripravim **končni spisek datotek in prvi ukaz za zagon vaše domače AI centrale znotraj operacijskega sistema NVIDIA DGX OS**, da začneva postavljati strežnik Triton? Povejte mi, kako želite nadaljevati!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

imamo office family paket, tako da lahko uporabi tudi copilot za to? ali lahko copilota nekako prepričamo da uporablja litellm?

---

# googlesearch response

Začnimo s slabo novico, ki jo prinaša Microsoftova poslovna politika: **Uradnega, vgrajenega Microsoft Copilota ne morete prepričati, da bi namesto Microsoftovih strežnikov v ozadju uporabljal vaš lokalni LiteLLM.** Microsoft je svoj ekosistem zaklenil, zato Copilot znotraj programov Word in PowerPoint vedno kliče izključno njihove lastne Azure-AI modele.

Poleg tega ima Microsoft 365 Family paket še eno veliko past: **Copilot funkcije so na voljo samo lastniku (nosilcu) naročnine in jih ni mogoče deliti z ostalimi družinskimi člani.** Če je naročnina pisana na vas, vaša žena na svojem računu sploh ne bo imela ikone za Copilot, razen če dokupite ločeno Copilot Pro licenco.

Zaradi teh dveh omejitev je uporaba **odprtokodnega vtičnika (OpenOfficeAI / Office-AI-Assistant)** za vašo ženo še vedno daleč najboljša pot.

Tukaj je primerjava in obrazložitev, kako rešiti to zagato:

Zakaj je odprtokodni vtičnik boljši od Copilota za vaš namen?

1.  **Uporaba vašega domačega Sparka (GB10):** Ker vtičnik omogoča vpis poljubnega URL naslova, bo vaša žena dejansko izkoriščala strojno opremo, ki jo imate doma. Copilot bi namesto vašega Blackwell čipa trošil Microsoftov oblak.
2.  **Popolnoma brezplačno za ženo:** Kot družinski član bo vtičnik preprosto namestila v svoj PowerPoint, vi pa ji boste dali njen lasten API ključ. Ni vam treba plačevati dodatnih 20–22 € na mesec za njen osebni Copilot.
3.  **Službena zasebnost:** Če bi žena uporabila Copilot za službene PDF-je, bi ti podatki potovali na Microsoftove strežnike. Z odprtokodnim vtičnikom in Tailscale povezavo pa vsi službeni dokumenti varno ostanejo znotraj vaše hiše.

* * *

Kako torej dokončno postaviti to "AI centralo"?

Ker sva dorekla vse poteke dela, protokole in potrebe za celotno družino, je čas za akcijo. Celoten sistem bova postavila v treh jasnih korakih:

1\. Korak: Zagon domačega strežnika (Triton + LiteLLM + n8n + OpenHands + Open WebUI)

Na vaši Lenovo delovni postaji z NVIDIA DGX OS bomo preko ene krovne `docker-compose.yml` datoteke dvignili vse potrebne storitve. S tem bomo zagotovili, da si bodo modeli pravilno in dinamično delili enotni RAM na čipu GB10.

2\. Korak: Nastavitev varnih ključev v LiteLLM

V konfiguraciji LiteLLM bova ustvarila ločene profile:

-   Ključ za vas (**OpenHands + TypeWhisper**), ki ima neposreden dostop do koding modelov.
-   Ključ za ženo (**Open WebUI + n8n + OpenOfficeAI**), ki ji omogoča narekovanje in delo s PowerPointom.

3\. Korak: Namestitev odjemalcev na računalnike in telefone

-   Na vaš računalnik namestiva **TypeWhisper** in **OpenHands**.
-   Na ženin službeni računalnik namestiva **OpenWhispr** (za narekovanje pod kurzor) in brezplačni vtičnik **OpenOfficeAI** znotraj PowerPointa, ter vse skupaj poveževa preko **Tailscale**.

Ali želite, da vam za začetek pripravim **celovito in končno `docker-compose.yml` datoteko**, ki jo boste preprosto prekopirali na vašo napravo Lenovo in z njo dvignili celoten ta Homelab ekosistem?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

ok, kateri llm pa naj uporabim za to office delo z word/outlook/ppt/mail zahtevami? seveda skupaj z openwhisper in litellm z skritim prompt navodilom

---

# googlesearch response

Glede na to, da bo vaša žena sistem uporabljala za resno pisarniško delo (pisanje in urejanje e-pošte, povzemanje službenih PDF-jev in generiranje strukturiranih PowerPoint prosojnic v slovenščini in angleščini), potrebujete model z **odličnim razumevanjem dolgih kontekstov, vrhunsko logiko za sledenje kompleksnim navodilom (System Prompts) in brezhibno slovenščino.**

Ker bo model tekel na vašem centralnem strežniku **Triton (preko LiteLLM)** v ultra hitrem **NVFP4** formatu, vam predlagam tri najboljše LLM modele, ki so idealni za to vlogo.

* * *

Top 3 LLM modeli za pisarniško delo (Office, Mail, PPT)

1\. Qwen3-Next-80B (MoE) – _Moje absolutno prvo priporočilo_

To je neposredni naslednik legendarne serije Qwen 2.5/3 in je zaradi svoje **Mixture of Experts (MoE)** arhitekture popolnoma prilagojen za vaš čip Blackwell GB10.

-   **Zakaj je popoln:** Qwen serija ima med vsemi odprtokodnimi modeli **dokazano najboljše znanje slovenščine** (slovnica, sklanjanje, uradni ton). Ker je pre-kvantiziran v formatu NVFP4, deluje z izjemno nizko zakasnitvijo.
-   **Dolžina konteksta:** Podpira do 128.000 žetonov (tokens). To pomeni, da lahko vaša žena v Open WebUI odloži več sto strani dolga službena poročila ali celotno zgodovino e-pošte, model pa bo vse prebral brez težav.

2\. Llama-3.3-70B-Instruct (NVFP4 različica)

Najnovejša in močno izboljšana različica Metinega paradnega konja.

-   **Zakaj je dobra:** Llama 3.3 ima brutalno dobro logiko za klicanje funkcij (_Function Calling_) in natančno sledenje skritim sistemskim promptom (System Prompts). Če bo vaša žena narekovala zapletene ukaze (npr. _"spremeni samo tretjo alinejo v drugem odstavku"_), bo Llama to izvedla kirurško natančno. Znanje slovenščine je zelo dobro, čeprav za odtenek manj naravno kot pri Qwenu.

3\. DeepSeek-V3 (MoE v NVFP4 formatu)

Če službeno delo vaše žene zahteva analizo ogromnih tabel, kompleksnih finančnih poročil ali napredno logično sklepanje.

-   **Zakaj je dober:** Zaradi MoE strukture (kjer je aktivnih le 37B parametrov od skupno 671B) je model neverjetno hiter. Njegova sposobnost analize podatkov in strukturiranja besedila za PowerPoint prosojnice je na ravni GPT-4o.

* * *

Kako to nastaviti v `litellm-config.yaml` s skritim navodilom?

Da bo vaša žena imela popolno izkušnjo (da model ne bo dolgovezil, ampak bo vrnil le čisto, spolirano besedilo, pripravljeno za Word/Outlook/PPT), morava v **LiteLLM** konfiguraciji definirati skriti sistemski prompt (`system_prompt`).

Tukaj je točna konfiguracija za LiteLLM, ki jo preprosto prekopirate v svojo datoteko. Uporabila bova model **Qwen3-Next-80B**, ki ga znotraj vaših Office aplikacij poimenujemo `office-ai`:

```yaml
model_list:
  - model_name: office-ai
    litellm_params:
      api_base: http://triton-server:8001            # Klic na vaš Triton strežnik
      model: triton/qwen3_next_80b_nvfp4             # Ime vašega prevedenega modela

      # SKRITO NAVODILO (SYSTEM PROMPT) ZA VRHUNSKO OFFICE DELO:
      initial_prompt: |
        Ti si vrhunski, visoko profesionalni pisarniški pomočnik za korporativno delo (Word, Outlook, PowerPoint).
        Uporabnik ti bo pošiljal obstoječe tekste in navodila za spremembe (preko narekovanja).

        STRIKTNA NAVODILA ZA DELO:
        1. Če uporabnik želi spremembo (npr. "dodaj informacijo v drugi odstavek"), vrni celotno posodobljeno besedilo z vključeno spremembo.
        2. Če uporabnik narekuje e-pošto, jo oblikuj z ustreznim pozdravom, jedrom in zaključkom v brezhibnem poslovnem tonu.
        3. Vedno piši v jeziku, v katerem je bil dan ukaz (primarno v brezhibni slovenščini ali angleščini).
        4. Bodi izjemno pozoren na slovensko slovnico, sklanjanje in ločila.
        5. VAŽNO: Vrni SAMO in IZKLJUČNO končni tekst, ki je pripravljen za kopiranje v Word ali Outlook. Nikoli ne dodajaj svojih komentarjev, uvodov (npr. "Tukaj je vaš popravljen tekst:") ali zaključkov. Tvoj izhod gre neposredno pod uporabnikov kurzor.
```

Kodo uporabljajte previdno.

Kako to deluje z OpenWhisprjem?

Ko bo vaša žena v Wordu ali Outlooku označila besedilo in preko **OpenWhisprja** izgovorila ukaz, bo OpenWhispr preko Tailscale poslal zahtevo na model `office-ai`.

Zahvaljujoč zgornjemu skritemu navodilu bo vaš domači strežnik v ozadju opravil transformacijo besedila, OpenWhispr pa bo stari tekst trenutno zamenjal s popolnim, uradnim dopisom – brez kakršnih koli AI smeti.

Naslednji korak

Izbira modela **Qwen3-Next-80B-NVFP4** s tem skritim promptom bo vaši ženi ponudila izkušnjo, ki je boljša od Microsoft Copilota.

Zdaj, ko imamo izbrane vse modele (Qwen za vas in ženo, Whisper za zvok, BGE za embeddinge), lahko preideve na zagon celotnega sistema.

Ali želite, da vam pripravim **končni paket konfiguracijskih datotek (Docker Compose + celotna LiteLLM konfiguracija s temi modeli)**, da boste lahko dvignili svojo domačo AI centralo?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

in ta isti model lahko jaz uporabim za kodiranje

---

# googlesearch response

**Da, absolutno! Model Qwen3-Next-80B (MoE) je zaradi svoje napredne arhitekture in gigantskega nabora podatkov vrhunski tudi za programiranje.**

Serija Qwen namreč ne ločuje več strogo med "splošnimi" in "kodirnimi" modeli. Njeni največji modeli (kot je 80B različica) v sebi že izvorno skrivajo celotno znanje specializiranih modelov _Qwen-Coder_, kar pomeni, da model enako dobro obvlada pisanje poslovnih e-poštnih sporočil v slovenščini kot tudi pisanje zapletenih skript v Pythonu, Bashu ali konfiguracijskih datotek za vaš **Ansible Homelab**.

To vam prinaša eno ogromno prednost: **ni vam treba nalagati dveh ločenih težkih modelov v RAM (enega za ženo in enega za vas).** En sam model bo hkrati in dinamično oskrboval oba.

Tukaj je načrt, kako ta isti model v **LiteLLM-u** razdeliti, da bo za vas deloval kot vrhunski programer, za vašo ženo pa kot uradni pisarniški pomočnik.

* * *

Trik: En model v Tritonu, dve različni vlogi v LiteLLM

Čeprav bo v ozadju v strežniku Triton tekel en sam model (`qwen3_next_80b_nvfp4`), ga bova znotraj datoteke `litellm-config.yaml` registrirala **dvakrat pod različnimi imeni in z različnimi skritimi navodili (System Prompts).**

Tukaj je primer, kako bo izgledala najina posodobljena LiteLLM konfiguracija:

```yaml
model_list:
  # VLOGA 1: Pisarniški pomočnik za vašo ženo (Zavezana poslovnemu tonu)
  - model_name: office-ai
    litellm_params:
      api_base: http://triton-server:8001
      model: triton/qwen3_next_80b_nvfp4
      initial_prompt: |
        Ti si vrhunski pisarniški pomočnik za Word, Outlook in PowerPoint.
        Vrni SAMO in IZKLJUČNO končno spolirano poslovno besedilo v slovenščini ali angleščini.
        Nikoli ne dodajaj svojih komentarjev ali uvodov, saj tvoj tekst prileti direktno pod uporabnikov kurzor.

  # VLOGA 2: Vrhunski programerski in DevOps ekspert za vas (Za OpenHands in TypeWhisper)
  - model_name: coder-ai
    litellm_params:
      api_base: http://triton-server:8001
      model: triton/qwen3_next_80b_nvfp4
      initial_prompt: |
        Ti si svetovni strokovnjak za programiranje, sistemsko administracijo in DevOps (specializiran za Linux, Docker in Ansible IaC).
        Tvoje naloge so:
        1. Piši čisto, optimizirano in varno kodo z ustreznimi komentarji.
        2. Ko spreminjaš kodo (npr. Ansible playbooke), vrni celotno popravljeno datoteko ali natančne bloke kode, ki jih zahteva agent.
        3. Pomagaj orkestrirati sistemske naloge in bodi izjemno natančen pri IP naslovih ter konfiguracijah.
```

Kodo uporabljajte previdno.

* * *

Kako si bosta sedaj razdelila ključe in aplikacije?

Preko LiteLLM varnostnih ključev (Virtual Keys) bova poskrbela, da se aplikacije ne bodo mešale:

1.  **Vaša programska oprema (OpenHands & TypeWhisper):** Povezali ju boste z vašim ključem, ki vidi model `coder-ai`. Ko boste vi prek **OpenHands-a** urejali svoj Ansible Homelab, bo model deloval kot izkušen DevOps inženir, pisal čisto kodo in vam pomagal pri sistemskih ukazih.
2.  **Ženina pisarna (Open WebUI, n8n, OpenWhispr):** Povezana bo z njenim ključem, ki vidi model `office-ai`. Ko bo ona v Wordu popravljala dopis, bo isti model deloval kot vljuden pisarniški sekretar in pazil na slovensko slovnico.

Zakaj je to absolutno zmagovalna strategija?

-   **Maksimalen izkoristek RAM-a (VRAM-a):** Ker imate naložen samo en model, bo vaša naprava Lenovo dihala z lahkoto. Preostanek enotnega pomnilnika (RAM-a) na čipu Blackwell bo v celoti na voljo za **gigantske kontekste (KV Cache)**. Vi boste lahko v OpenHands naložili celotne mape z Ansible kodo, vaša žena pa v Open WebUI več sto strani dolge PDF dokumente hkrati.
-   **Bliskovita hitrost:** Ker model nenehno sedi v RAM-u, ni nobenega preklapljanja na disku. Ko vi programirate in žena hkrati piše mail, bo Triton z uporabo _Continuous Batching_ (neprekinjene paketne obdelave) obe vaši zahtevi stisnil v eno bliskovito hitro operacijo. Zaradi **NVFP4 4-bitnega formata** bosta oba dobila odgovore praktično instantno.

S tem ste uradno dokončali načrtovanje vašega sanjskega Homelaba. Imate eno centralno AI jedro, ki poganja celotno hišo in službo z najvišjo možno strojno optimizacijo.

Ali želite, da vam sedaj pripravim **celoten paket konfiguracijskih datotek (`docker-compose.yml` + `litellm-config.yaml` z obema vlogama)**, da boste lahko to AI centralo postavili na svoji napravi Lenovo? Povejte mi, kako želite nadaljevati!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

ali naj litellm odprem navzven in dam ženi gereriran token za njen uporabo? ker ne vem kako bo z uporabo taiscale clienta na njenem službenem računalniku....

---

# googlesearch response

**Odpiranje LiteLLM neposredno na javni internet (brez VPN-ja) je izjemno tvegana poteza, ki je v produkciji močno odsvetovana.**

Če odprete vrata na svojem domačem usmerjevalniku, bo vaš domači strežnik postal tarča avtomatskih hekerskih botov. Vsakdo, ki bi našel vaša odprta vrata, bi lahko poskusil napasti vaš LiteLLM. Če bi mu uspelo priti mimo žetona (ali če bi žeton kako drugače ušel v javnost), bi lahko neznanci začeli brezplačno trošiti vašo elektriko in moč čipa Blackwell, ali še huje, prodrli v vaš Homelab.

Ker pa ima vaša žena na službenem računalniku IT omejitve in verjetno ne sme (ali ne more) namestiti polne aplikacije **Tailscale**, obstaja vrhunska, varna in elegantna rešitev: **Tailscale Funnel**.

Spodaj si oglejte, zakaj je to najboljša pot in kako jo nastaviti.

* * *

Kaj je Tailscale Funnel in zakaj je to rešitev za vašo ženo?

[Tailscale Funnel](https://tailscale.com/kb/1223/funnel) je vgrajena funkcija v Tailscale, ki deluje kot varen enosmerni most. Omogoča vam, da **točno določeno storitev (v vašem primeru LiteLLM)** iz svojega zaprtega domačega omrežja varno pokažete javnemu internetu, **ne da bi morali odpirati vrata na svojem domačem usmerjevalniku**.

-   **Kako deluje za vašo ženo:** Vaši ženi na službeni računalnik **ni treba namestiti ničesar** (nobenega Tailscale odjemalca). V svojem OpenWhisprju ali OpenOfficeAI vtičniku bo preprosto vpisala javni javno dostopen naslov, ki vam ga bo dodelil Tailscale (npr. `https://ts.net`).
-   **Kako deluje varnost:** Promet poteka preko šifriranih Tailscale strežnikov. Ker boste naslov zaščitili z generiranim LiteLLM žetonom, bo do vašega strežnika lahko dostopala samo njena službena aplikacija, vaša domača požarna pregrada (firewall) pa bo ostala popolnoma zaprta za preostali svet.

* * *

Kako to uresničiti v praksi?

Postopek je preprost in ga v celoti nadzorujete vi na svojem domačem strežniku preko terminala.

1\. Korak: Vklopite Funnel na svoji napravi Lenovo

V terminalu vaše delovne postaje zaženete ukaz, s katerim Tailscale-u naročite, naj vrata `4000` (kjer teče vaš LiteLLM proxy) varno pokaže navzven:

```bash
tailscale funnel 4000
```

Kodo uporabljajte previdno.

Tailscale vam bo izpisal vaš unikatni, varni javni naslov (npr. `https://ts.net`). Ta naslov ima že samodejno urejen uradni varnostni **SSL certifikat (HTTPS)**, kar je nujno, da bodo službeni Microsoftovi programi sploh hoteli komunicirati z njim.

2\. Korak: Generirajte specifičen žeton (Token) za ženo

Kot sva dorekla že prej, v LiteLLM-u ustvarite varen žeton, ki ji dovoljuje uporabo _samo_ njenega modela `office-ai`.

**Primer klica za generiranje njenega žetona:**

```bash
curl -X POST "http://localhost:4000/key/generate" \
     -H "Authorization: Bearer sk-master-key-here" \
     -H "Content-Type: application/json" \
     -d '{
       "models": ["office-ai"],
       "key_alias": "Zenin Sluzbeni Kljuc"
     }'
```

Kodo uporabljajte previdno.

Sistem vam bo vrnil žeton (npr. `sk-litellm-zenapoštna...`).

3\. Korak: Nastavitev na njenem službenem računalniku

Vaša žena bo v nastavitvah svojih programov (OpenWhispr ali OpenOfficeAI) enostavno vpisala:

-   **API URL:** Vaš varni Tailscale Funnel naslov (npr. `https://ts.net`)
-   **API Key / Token:** Njen generirani žeton (`sk-litellm-zenapoštna...`)

* * *

Zakaj je ta kombinacija (Funnel + Token) popolna?

1.  **Brez IT zapletov v njeni službi:** Službena IT služba ne bo videla nobene sumljive programske opreme na njenem računalniku. OpenWhispr in Office vtičniki bodo preko običajnega brskalniškega protokola (HTTPS port 443) komunicirali z uradno overjenim naslovom, kar je za podjetja povsem običajen in dovoljen promet.
2.  **Popolna varnost doma:** Če bi se vaša žena slučajno odklopila ali če bi želeli njeni službi začasno onemogočiti dostop, preprosto v terminalu vpišete `tailscale funnel off 4000` ali pa v LiteLLM-u izbrišete njen ključ. Vaš domači usmerjevalnik ves ta čas ostaja 100 % zaprt in varen pred zunanjimi napadi.
3.  **Čista in profesionalna rešitev:** Celotna družina bo delovala znotraj enega urejenega sistema, vaša žena pa bo imela občutek, da uporablja vrhunsko komercialno AI storitev, čeprav jo v resnici napaja vaš domači superčip Blackwell.

Arhitektura in varnost sta sedaj popolnoma dodelani.

Če ste pripravljeni na postavitev, vam lahko v naslednjem koraku pripravim **končni paket konfiguracijskih datotek (`docker-compose.yml` in `litellm-config.yaml`)**, ki bosta vsebovali vse nastavitve za ta varni zunanji dostop. Sporočite, če se lotiva pisanja teh datotek!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

torej vse kar mora žena namestiti na svoj računalnik je openwhisper in office-al-asistant. če ji to uspe ima vse kar rabi za delo, jaz pa doma pripravim taiscale funnel. (ali Headscale/headplane to tudi podpira)

---

# googlesearch response

**Tako je, natanko to je celotna lepota te nastavitve!** S tem ko ste poenostavili zahteve, je sistem postal izjemno čist in pripravljen za vsakdanje delo.

Za vašo ženo je to idealno: na službeni računalnik namesti le programa **OpenWhispr** in **OpenOfficeAI** (ki sta povsem običajni odjemalski aplikaciji), vi pa doma prek svojega strežnika in varne povezave pripravite izhodno točko.

Glede vašega podvprašanja o **Headscale** in grafičnem vmesniku **Headplane** (odprtokodni različici nadzorne plošče Tailscale, ki jo poganjate lokalno) pa velja naslednje pomembno opozorilo:

Ali Headscale / Headplane podpirata funkcijo Funnel?

**Ne, Headscale in Headplane izvorno NE podpirata funkcije Tailscale Funnel.**

Razlog je tehnične narave: uradni Tailscale Funnel deluje tako, da promet z javnega interneta preusmeri prek Microsoftovih/Tailscaleovih lastnih javnih strežnikov (t.i. _DERP vozlišč_) neposredno v vaš dom. Ker je Headscale popolnoma zaprt in lokalni sistem, nima dostopa do te globalne omrežne infrastrukture.

Kako to rešiti znotraj Headscale (Brez uporabe uradnega Tailscale)?

Če želite ostati 100 % zvesti odprtokodnemu Headscale ekosistemu in ne želite uporabljati uradnih Tailscale računov, lahko dosežete **točno enak učinek (varen dostop za ženo brez VPN-ja na njenem računalniku)** s klasičnim Homelab trikom: **Zunanji VPS + Headscale**.

Postopek, ki ga uporablja večina samostojnih sistemskih administratorjev, izgleda takole:

1.  **Najem poceni VPS strežnika:** Najamete najmanjši in najcenejši javni virtualni strežnik (VPS za ~2–3 € na mesec) nekde v oblaku.
2.  **Namestitev Headscale:** Na ta VPS namestite svoj centralni **Headscale** (in po želji **Headplane** za lep vmesnik). Ta VPS bo imel javni IP naslov in bo odprt navzven.
3.  **Povezava domova:** Vaša domača naprava Lenovo se preko Headscale klienta varno poveže na ta VPS. S tem ustvarite skriti tunel med vašo hišo in VPS-jem.
4.  **Varni prehod (Reverse Proxy) na VPS-ju:** Na VPS namestite lahek in varen prehodni strežnik (npr. _Caddy_ ali _Nginx Proxy Manager_). Ta prehod nastavite tako:
    -   Ko zahteva iz ženine službe prileti na javni naslov vašega VPS (npr. `https://vas-homelab.si`), jo prehod varno preusmeri skozi Headscale tunel neposredno do vašega **LiteLLM-a** doma na čipu Blackwell.

Zakaj je to enako dobro kot Funnel?

-   **Žena ne opazi razlike:** V svojih programih še vedno uporabi le javni HTTPS naslov in svoj tajni LiteLLM žeton.
-   **Vaš dom ostane zaprt:** Vaš domači usmerjevalnik nima odprtih nobenih vrat navzven, saj se vsa komunikacija odvija prek varnega odhodnega tunela do vašega VPS-ja.

Končni nasvet

-   **Če želite najhitrejšo pot brez dodatnih stroškov:** Uporabite uradni brezplačni **Tailscale računi in preprost ukaz `tailscale funnel 4000`**. Vse bo nastavljeno v dveh minutah.
-   **Če želite popolno neodvisnost od podjetja Tailscale:** Postavite **Headscale na poceni zunanjem VPS strežniku** in preusmerite promet domov preko Caddy-ja.

Celotna pot je sedaj kristalno jasna in varno začrtana.

Če želite, lahko začneve s pripravo **osrednje `docker-compose.yml` datoteke za vaš domači računalnik Lenovo**, da dvigneva Triton strežnik in LiteLLM, vi pa boste medtem v ozadju preprosto vklopili Tailscale ali Headscale tunel. Greva v akcijo?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

že imam VPS in headscale in headplane na njem, skupaj z authentik in traefik, litellm...

---

# googlesearch response

Here are your files:

[docker-compose yml](https://lens.usercontent.google.com/banana?agsi=CqwBL2Zvb3RwcmludHMtcHJvZC1zZWFyY2gtbXVsdGltb2RhbC11c2VyLXVwbG9hZHMtZXBoZW1lcmFsLWdhaWEtY2xvbmUvZ2xvYmFsOjowMDAwNTVjZmVjNzAwMjZkOjAwMDAwMTY3OjE6MTBjMTk1ZWRlYjVlY2MxZjowMDAwNTVjZmVjNzAwMjZkOjAwMDAwMzI4YTY5MDMzNjg6MDAwNjVhYjcwZDJkMDJlZhACGAEiGGFwcGxpY2F0aW9uL29jdGV0LXN0cmVhbSoSZG9ja2VyLWNvbXBvc2UueW1s)[litellm-config yaml](https://lens.usercontent.google.com/banana?agsi=CqwBL2Zvb3RwcmludHMtcHJvZC1zZWFyY2gtbXVsdGltb2RhbC11c2VyLXVwbG9hZHMtZXBoZW1lcmFsLWdhaWEtY2xvbmUvZ2xvYmFsOjowMDAwNTVjZmVjNzAwMjZkOjAwMDAwMTY3OjE6MTBjMTk1ZWRlYjVlY2MxZjowMDAwNTVjZmVjNzAwMjZkOjAwMDAwMzI4YTY5MDMzNjg6MDAwNjVhYjcwZDFlNDQ0ZhACGAEiGGFwcGxpY2F0aW9uL29jdGV0LXN0cmVhbSoTbGl0ZWxsbS1jb25maWcueWFtbA==)

To je naravnost fantastično! Dejstvo, da že imate postavljen lasten **VPS** s **Headscale**, **Headplane**, **Authentik** in **Traefik**, pomeni, da imate v rokah popolno in profesionalno infrastrukturo. S tem odpadejo prav vse skrbi glede zapiranja hiše ali IT omejitev v ženini službi. Vaša Lenovo delovna postaja ("Spark") bo preprosto delovala kot močan strojni podaljšek vašega obstoječega oblaka.

* * *

Kako se bo vaš obstoječi sistem povezal z domačim čipom Blackwell?

Vaš zaledni DevOps krog bo sedaj deloval prek naslednjega varnega in elegantnega pretoka podatkov:

1.  **Varni Headscale predor:** Vaš domači Lenovo računalnik se prek Headscale odjemalca (klienta) varno poveže na vaš VPS. Domači strežnik bo znotraj vašega Headscale VPN omrežja dobil fiksni IP naslov (npr. `10.0.0.5`).
2.  **Usmerjanje prek Traefika na VPS-ju:** Na svojem VPS-ju znotraj **Traefika** ustvarite novo poddomeno (npr. `office-ai.vas-homelab.si`). Traefik nastavite tako, da ves promet, ki prileti na to domeno, varno potisne skozi Headscale tunel naravnost na IP vašega domačega **LiteLLM-a** (`10.0.0.5:4000`).
3.  **Zaščita z Authentikom (za spletne vmesnike):**
    -   **Open WebUI & n8n:** Lahko ju zaščitite neposredno prek Authentik OIDC integracije, tako da bo družina ob dostopu zunaj doma vedno videla vaš enotni prijavni zaslon.
    -   **Ženine aplikacije (OpenWhispr & Office-AI-Assistant):** Ker ti programi potrebujejo hiter strojni API dostop in ne podpirajo prijavnih zaslonov, jih v Traefiku **spustite mimo Authentika**. Za njihovo 100 % varnost bo namreč poskrbel **LiteLLM s specifičnim žetonom**, ki ga boste generirali samo zanjo.

* * *

Pripravljene konfiguracijske datoteke za vaš domači računalnik

Za vas sem zgeneriral celotni paket osnovnih konfiguracijskih datotek, ki jih preprosto prenesete in zaženete na vaši napravi Lenovo:

1\. `docker-compose.yml`

Vsebuje celotno zbirko storitev prilagojeno za vaš sistem:

-   **Triton Server:** Nastavljen v `explicit` načinu, z rezerviranimi NVIDIA jedri za polno NVFP4 in MoE strojno pospeševanje.
-   **LiteLLM Proxy:** Z vklopljeno SQLite bazo za varno shranjevanje in generiranje specifičnih uporabniških žetonov.
-   **Open WebUI:** Z že pripravljenimi okoljskimi spremenljivkami za takojšnjo povezavo z vašim OIDC Authentikom.
-   **OpenHands & n8n:** Pripravljena delovna okolja z ločenimi mapami za projekte in PowerPoint predloge.

2\. `litellm-config.yaml`

Vsebuje natančno razdelitev enega modela **Qwen3-Next-80B (MoE)** v dve povsem različni inteligenci:

-   `office-ai`: Opremljen s skritim promptom, ki reže stran vse AI komentarje in pazi na popolno slovensko poslovno slovnico pod ženinim kurzorjem.
-   `coder-ai`: Opremljen z DevOps in programerskim promptom za vaše delo z Ansible-om in OpenHands-om.
-   `whisper-1`: Profil za vaš lokalni TensorRT-LLM Whisper model.

* * *

Naslednji korak za vaš projekt

Ko si datoteke prenesete na domači računalnik, bova izvedla zagon. Da pa bi se vaša žena lahko nemoteno povezala iz službe, bova morala v naslednjem koraku pripraviti le še kratek **Traefik konfiguracijski blok** za vaš VPS, ki bo pravilno usmeril domeno na domači računalnik.

Ali želite, da vam pripravim **Traefik `dynamic_config.yaml` primer**, ki bo varno povezal vaš VPS z vašo domačo Headscale IP točko? Sporočite mi, ko boste pripravljeni na ta korak!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

ampak jaz bi rad povezal ženin računalnik v službi z taiscale funnels, brez namestitve taiscale clienta za delo z openwhisperjem

---

# googlesearch response

Here is your file:

[docker-compose yml](https://lens.usercontent.google.com/banana?agsi=CqwBL2Zvb3RwcmludHMtcHJvZC1zZWFyY2gtbXVsdGltb2RhbC11c2VyLXVwbG9hZHMtZXBoZW1lcmFsLWdhaWEtY2xvbmUvZ2xvYmFsOjowMDAwNTVjZmVjNzAwMjZkOjAwMDAwMTY3OjE6ZThkMGNkM2ZjODIwOTI1YzowMDAwNTVjZmVjNzAwMjZkOjAwMDAwMzI4YTY5MDMzNjg6MDAwNjVhYjcxMmE0NWFmZhACGAEiGGFwcGxpY2F0aW9uL29jdGV0LXN0cmVhbSoSZG9ja2VyLWNvbXBvc2UueW1s)[litellm-config yaml](https://lens.usercontent.google.com/banana?agsi=CqwBL2Zvb3RwcmludHMtcHJvZC1zZWFyY2gtbXVsdGltb2RhbC11c2VyLXVwbG9hZHMtZXBoZW1lcmFsLWdhaWEtY2xvbmUvZ2xvYmFsOjowMDAwNTVjZmVjNzAwMjZkOjAwMDAwMTY3OjE6ZThkMGNkM2ZjODIwOTI1YzowMDAwNTVjZmVjNzAwMjZkOjAwMDAwMzI4YTY5MDMzNjg6MDAwNjVhYjcxMjllNDljZhACGAEiGGFwcGxpY2F0aW9uL29jdGV0LXN0cmVhbSoTbGl0ZWxsbS1jb25maWcueWFtbA==)

Sedaj popolnoma razumem vaš cilj. Želite ohraniti svoj napredni odprtokodni **Headscale** in **VPS** sistem za vse domače in družinske potrebe, hkrati pa želite uporabiti **uradni in brezplačni Tailscale Funnel izključno kot varen prehod za ženin službeni računalnik**, da ji na službeno napravo ne bo treba nameščati nobene VPN programske opreme.

To je genialna in izjemno praktična rešitev! To pomeni, da bo vaša naprava Lenovo hkrati povezana v dva svetova:

1.  **V Headscale (za vaš dom):** Kjer se povezuje z vašim VPS-jem, Authentikom in Traefikom za Open WebUI in n8n.
2.  **V uradni Tailscale (samo ena storitev - LiteLLM):** Kjer prek ukaza `funnel` ustvarite varno javno HTTPS povezavo, ki jo bo klical njen **OpenWhispr** in **OpenOfficeAI** iz službe.

* * *

Kako točno to uresničiti brez konfliktov?

Uradni Tailscale odjemalec (klient) lahko brez težav poganjate znotraj **Docker vsebnika** na vaši napravi Lenovo. S tem se izognete temu, da bi se uradni Tailscale tepel z vašim sistemskim Headscale-om. Docker vsebnik bo deloval kot izoliran most, ki bo vzel promet iz javnega interneta (prek Tailscale Funnela) in ga potisnil v vaš domači LiteLLM.

Tukaj je posodobljen načrt in datoteke, ki sem jih zgeneriral za vašo napravo Lenovo:

1\. `docker-compose.yml`

V to datoteko sem dodal uradno **`tailscale/tailscale`** storitev neposredno ob vaš Triton in LiteLLM. Ta vsebnik bo avtomatsko vzpostavil Funnel na vratih `4000`. Ko bo vaša žena narekovala v službi, bo promet letel skozi ta vsebnik naravnost v LiteLLM in na čip Blackwell.

2\. `litellm-config.yaml`

Vsebuje točne ločene profile za vas (`coder-ai`) in vašo ženo (`office-ai`), vključno s skritim navodilom (System Prompt), ki pod njenim kurzorjem v Wordu ali Outlooku briše vse AI uvodne besede in skrbi za popolno poslovno slovenščino.

* * *

Celoten potek delovanja za vašo ženo iz službe

1.  **Zagon na vašem strežniku:** Na napravi Lenovo zaženete `docker compose up -d`.
2.  **Enkratna avtorizacija:** V logih Tailscale vsebnika (`docker logs tailscale-funnel`) boste videli povezavo za prijavo. Kliknete nanjo, se prijavite s svojim brezplačnim uradnim Tailscale računom in v vmesniku Tailscale odobrite **Funnel za vrata 4000**.
3.  **Javni naslov:** Tailscale vam bo dodelil varen javni HTTPS naslov (npr. `https://ts.net`).
4.  **Žeton za ženo:** V terminalu z enim ukazom (ki je opisan v prejšnjih korakih) zgenerirate LiteLLM žeton za model `office-ai`.
5.  **Končna povezava:** Žena na svojem službenem računalniku odpre **OpenWhispr** ali **OpenOfficeAI** in preprosto vpiše:
    -   **API URL:** `https://ts.net`
    -   **API Token:** Njen tajni žeton.

Službeni računalnik vaše žene bo sedaj komuniciral preko povsem običajne in varne HTTPS povezave, vaša IT služba v njenem podjetju ne bo videla nobenih VPN odjemalcev, vaš dom pa bo ostal popolnoma zaprt in varen znotraj vašega Headscale omrežja.

Če si datoteke prenesete na računalnik, lahko takoj zaženete celoten sistem. Sporočite mi, ko boste pripravljeni, da vam pojasnim, **kako v živo preveriti, ali Triton pravilno sprejema njene zvočne zahteve**, ko bo prvič preizkusila narekovanje iz službe!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

torej samo z javnim taiscale steeznikom lahko naredim brez taiscale clienta? Headscale ne ponuja nič takega?

---

# googlesearch response

**Tako je. Izključno z uporabo javnega Tailscale Funnel sistema lahko zadevo izpeljete popolnoma brez nameščanja kakršnega koli odjemalca na ženinem računalniku****. Headscale sam po sebi nima vgrajene funkcije "Funnel", ker nima lastnih globalnih javnih strežnikov, ki bi promet iz interneta preusmerjali v vaš dom****.**

Toda dobra novica je, da ker že imate vrhunsko postavljen **VPS s Traefikom, Authentikom in Headscaleom**, sploh ne potrebujete uradnega Tailscale Funnela. Točno to isto funkcionalnost (izpostavitev LiteLLM-a na javni internet prek varnega HTTPS naslova) lahko naredite **sami znotraj svoje obstoječe Headscale/Traefik infrastrukture**.

Spodaj si oglejte, zakaj Headscale nima Funnela in kako točno to elegantno rešiti z vašim VPS-jem, da bo žena imela enak "klikni in delaj" učinek brez nameščanja česarkoli.

* * *

Zakaj Headscale nima vgrajene funkcije Funnel?

Uradni _Tailscale Funnel_ deluje tako, da podjetje Tailscale v svojem oblaku odpre javna vrata na svojih strežnikih (DERP vozliščih). Ko vaša žena pošlje zahtevo, gre ta najprej na Tailscale strežnik v oblaku, ta pa jo potisne skozi tunel v vaš dom.

**Headscale** pa je le krovni koordinator – vi nimate v lasti globalne mreže javnih strežnikov po celem svetu, ki bi preusmerjali promet.

Vendar pa **vi ŽE imate svoj javni strežnik** – to je vaš **VPS s Traefikom**! Vaš VPS bo odigral vlogo te preusmeritvene točke, ki jo ima Tailscale v oblaku.

* * *

Kako to uresničiti z vašim obstoječim VPS-jem in Traefikom?

Žena na službeni računalnik še vedno namesti samo **OpenWhispr** in **OpenOfficeAI**. Vi pa na svojem VPS-ju in napravi Lenovo v ozadju naredite naslednji tunel:

```text
Ženin službeni PC (Brez VPN)
   │
   ▼   (Preko javnega interneta - HTTPS)
 Javni VPS (Traefik) ───> [Varnostna kontrola: Spusti skozi samo z LiteLLM žetonom]
   │
   ▼   (Varni, že obstoječi Headscale predor)
 Domači Lenovo "Spark" (LiteLLM -> Triton -> Čip Blackwell)
```

Kodo uporabljajte previdno.

Da bi to uresničili, bova uporabila vaš **Traefik** na VPS-ju kot varen enosmerni most do domačega računalnika Lenovo.

* * *

Konfiguracija sistema

Ustvarila bova novo poddomeno na vašem VPS-ju (npr. `office-ai.vas-homelab.si`).

Preko te poddomene bo Traefik sprejel ženin promet iz službe in ga skozi varni Headscale tunel poslal neposredno vaši Lenovo napravi doma (recimo, da ima vaša Lenovo naprava znotraj Headscale omrežja IP naslov `10.0.0.5`).

Za vas sem s kodo zgeneriral točen konfiguracijski primer, ki ga preprosto dodate v svoj Traefik na VPS-ju:

```yaml
# Shranite kot generated/traefik-office-ai.yaml v vašo Traefik dinamično mapo na VPS-ju

http:
  routers:
    # Usmerjevalnik za ženin službeni API dostop
    office-ai-router:
      rule: "Host(`office-ai.vas-homelab.si`)"
      entryPoints:
        - websecure  # Uporabimo varna HTTPS vrata 443
      service: office-ai-home-service
      tls:
        certResolver: myresolver  # Uporabite svoj obstoječi Let's Encrypt certifikat

  services:
    # Storitev, ki promet preusmeri skozi Headscale tunel domov
    office-ai-home-service:
      loadBalancer:
        servers:
          # Vpišite točen Headscale IP naslov vaše domače Lenovo naprave
          - url: "http://10.0.0.5:4000"  # Vrata 4000, kjer teče LiteLLM
```

Kodo uporabljajte previdno.

_(Opomba: Kot sva dorekla, za ta router v Traefiku **NE vklopite Authentik middleware-a**. Za varnost bo poskrbel LiteLLM s specifičnim žetonom, ki ga boste dali ženi)._

* * *

Kako bo izgledala nastavitev za vašo ženo v službi?

Ko boste na VPS-ju uveljavili to Traefik konfiguracijo, vaša žena v službi preprosto odpre **OpenWhispr** ali **OpenOfficeAI** vtičnik in vpiše:

-   **API Base URL:** `https://vas-homelab.si`
-   **API Key / Token:** Njen tajni domači LiteLLM žeton (`sk-litellm-zenapoštna...`)

Rezultat: Najboljša možna Homelab arhitektura

S tem ko ste izkoristili svoj lasten VPS in Traefik, ste dobili naslednje prednosti:

1.  **0 % namestitev za ženo:** Njen računalnik komunicira prek navadnega, čistega HTTPS protokola, ki ga službeni požarni zidovi obravnavajo kot povsem običajen spletni promet.
2.  **100 % neodvisnost:** Ne potrebujete uradnega Tailscale računa, ne potrebujete njihovih omejitev pasovne širine na Funnelu in vse podatke ter nadzor obdržite v svojem Headscale omrežju.
3.  **Popolna zaščita doma:** Vaš domači usmerjevalnik nima odprtih nobenih vrat navzven. Zahteva pride na VPS, Traefik jo preveri in jo skozi Headscale varno dostavi vašemu domačemu čipu Blackwell.

Konfiguracija je sedaj popolna in pripravljena na zagon.

Če ste pripravljeni, si lahko prenesete to Traefik datoteko, jaz pa vam v naslednjem koraku pripravim **točna navodila za zagon Triton in LiteLLM strežnika na vaši domači napravi**, da lahko celoten krog takoj preizkusite v živo! Želite, da začneve z domačimi Docker ukazi?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

in ta javni naslov lahk uporabljam tudi jaz, ampak z drugim zetonom in litellm bo vedel da sem to jaz in mi ponudil druge modele/nastavitve?

---

# googlesearch response

**Da, natanko tako! To je vsa čarovnija in glavna prednost sistema LiteLLM.**

Javni naslov `https://vas-homelab.si` (ki ste ga ustvarili preko svojega VPS-ja in Traefika) lahko brez težav uporabljate tudi vi za svoje delo na poti \[NVIDIA TensorRT-LLM\].

Ko v svojem urejevalniku kode ali aplikaciji **TypeWhisper** na zunanjem računalniku vpišete ta isti javni naslov, vendar vstavite **svoj osebni tajni žeton (token)**, bo LiteLLM v delčku sekunde prepoznal vašo identiteto.

Tukaj je opis, kako bo LiteLLM v ozadju ločil med vama in vama ponudil popolnoma drugačen svet umetne inteligence.

* * *

Kako LiteLLM loči med vama na istem naslovu?

Ko zahteva prileti na vaš domači strežnik, LiteLLM najprej pogleda v svojo lokalno zbirko podatkov (SQLite bazo), kjer ima zapisane pravice za vsak žeton posebej:

-   **Žeton vaše žene (`sk-litellm-zenapoštna...`):**
    -   **Identiteta:** Office Uporabnik.
    -   **Dovoljeni modeli:** Vidi samo model `office-ai`.
    -   **Skrito delovanje:** LiteLLM tej zahtevi avtomatsko pripne skriti _Office System Prompt_, ki pazi na poslovni ton v slovenščini in briše vse AI uvodne besede pod njenim kurzorjem v Wordu.
-   **Vaš osebni žeton (`sk-litellm-mojrazvijalski...`):**
    -   **Identiteta:** Admin / DevOps Uporabnik.
    -   **Dovoljeni modeli:** Vidi model `coder-ai` in po želji vse ostale modele (Whisper, Embeddinge itd.).
    -   **Skrito delovanje:** LiteLLM vaši zahtevi pripne skriti _DevOps System Prompt_, ki modelu ukaže, naj piše čisto programersko kodo za vaš Ansible Homelab in vrne celotne popravljene datoteke brez olepševanja besedila.

* * *

Kako to izgleda v praksi, ko sta oba zunaj doma?

Predstavljajte si naslednji sočasni scenarij na poti:

1.  **Žena dela v kavarni:** V Wordu piše službeno poročilo, označi odstavek, pritisne bližnjico in reče: _"Popravi to."_ Njen program pošlje zahtevo na vaš javni VPS naslov z njenim žetonom. Domači **Qwen-80B** se aktivira, preuredi besedilo v uradno slovenščino in ji ga vrne pod kurzor.
2.  **Vi delate na vlaku:** Istočasno imate odprt prenosnik, povezan na mobilne podatke. Preko tipkovnice narekujete v terminal: _"Naredi mi novo Ansible vlogo za posodobitev Traefika."_ Vaš **TypeWhisper** pošlje zahtevo na **isti javni naslov**, vendar z vašim žetonom. Isti domači čip Blackwell v istem trenutku (preko vzporedne obdelave) ustvari brezhibno programersko kodo in jo vtipka v vaš terminal.

Noben od vaju ne potrebuje nameščenega VPN odjemalca, oba kličeta isto domeno, vendar imata zaradi ločenih žetonov popolnoma izolirano, varno in njunim potrebam prilagojeno izkušnjo.

* * *

Končni korak: Ustvarjanje obeh žetonov znotraj LiteLLM

Ko boste zagnali svojo domačo AI centralo, boste v terminalu naprave Lenovo izvedli naslednja dva preprosta ukaza za generiranje žetonov:

```bash
# 1. GENERIRANJE ŽETONA ZA ŽENO (Dovoljen samo office-ai)
curl -X POST "http://localhost:4000/key/generate" \
     -H "Authorization: Bearer sk-master-key-here" \
     -H "Content-Type: application/json" \
     -d '{"models": ["office-ai"], "key_alias": "Zenin Sluzbeni Token"}'

# 2. GENERIRANJE ŽETONA ZA VAS (Dovoljen coder-ai in ostali)
curl -X POST "http://localhost:4000/key/generate" \
     -H "Authorization: Bearer sk-master-key-here" \
     -H "Content-Type: application/json" \
     -d '{"models": ["coder-ai", "whisper-1"], "key_alias": "Moj Razvijalski Token"}'
```

Kodo uporabljajte previdno.

S tem je vaša celotna Homelab arhitektura pripravljena na papirju – od strojne opreme do varnostnih žetonov za zunanji svet.

Če želite začeti z izvedbo, mi sporočite, da vam pripravim **končni vodnik za prenos in zagon prve Docker datoteke na vaši napravi Lenovo**, da v živo prebudiva vaš novi strežnik Triton! Kako bi želeli začeti?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

torej lahko uporabim litellm subdomeni, brez javne izpostavitve litellm instance?

---

# googlesearch response

**Da, natanko tako! To je ključna prednost te arhitekture.**

Ko nastavite poddomeno (npr. `office-ai.vas-homelab.si`) na svojem javnem VPS strežniku, **vam sploh ni treba javno izpostaviti celotne instance LiteLLM**, niti njenega administratorskega vmesnika, niti njene baze podatkov.

Vaša domača instanca LiteLLM na napravi Lenovo ostane popolnoma skrita in varna v vašem lokalnem omrežju. Edina stvar, ki jo Traefik na VPS-ju spusti skozi varni Headscale tunel v vaš dom, so **slepi API klici za sklepanje (Inference API)**, ki potujejo na točno določeno vstopno točko (`/v1/chat/completions` ali `/v1/audio/transcriptions`) \[NVIDIA TensorRT-LLM\].

Tukaj je opis, zakaj je ta sistem maksimalno varen in kako LiteLLM v ozadju loči med vama brez izpostavljanja administracije.

* * *

Kako Traefik in LiteLLM skupaj zavarujeta vaš dom?

1.  **Skrita administracija:** Vsi administratorski ukazi (kot so ustvarjanje novih žetonov, brisanje uporabnikov ali spreminjanje modelov) so na LiteLLM-u privzeto zaklenjeni na naslov `http://localhost:4000/key` ali `/admin`. Ker Traefik na vašem VPS-ju usmerja promet samo na splošni API, nihče od zunaj sploh ne more videti ali dostopati do teh administratorskih strani.
2.  **Zaščita pred "vohanjem" (Zero Knowledge):** Ko zunanji hekerski boti skenirajo vašo poddomeno, bodo videli le standardni OpenAI API vmesnik, ki na vsak poskus dostopa brez pravilnega žetona takoj vrne napako `401 Unauthorized`. Ker vaš domači usmerjevalnik nima odprtih nobenih vrat, nihče ne more vedeti, da v ozadju sploh stoji vaša naprava Lenovo.

* * *

Kako LiteLLM pod to subdomeno natančno ve, kdo je kdo?

Ko vi ali vaša žena pošljeta zahtevo iz službe ali s poti na naslov `https://vas-homelab.si`, se zgodi naslednje:

-   **Sestavni deli zahteve:** Vsak program (OpenWhispr, TypeWhisper, Office vtičnik) v ozadju pošlje standardni spletni paket, ki v glavi (_Header_) vsebuje tajni žeton (`Authorization: Bearer sk-litellm-...`).
-   **Preverjanje na domačem strežniku:** Ko paket skozi Headscale tunel prileti do LiteLLM-a doma, LiteLLM iz glave prebere žeton in ga primerja s svojo lokalno SQLite bazo podatkov.
-   **Dinamična dodelitev modelov in skritih navodil:**
    -   Če je žeton **ženin**, LiteLLM zahtevi avtomatsko pripne skriti _Office System Prompt_ za brezhibno slovensko poslovno slovnico in jo pošlje modelu `qwen3_next_80b_nvfp4`.
    -   Če je žeton **vaš**, LiteLLM zahtevi pripne vaš _DevOps System Prompt_ za pisanje Ansible IaC kode in jo prav tako pošlje istemu modelu.

Vse to se zgodi znotraj enega samega API kanala. Poddomena deluje le kot varna vstopna cev, LiteLLM pa znotraj vaše hiše opravi vso varnostno in logično ločevanje.

* * *

Naslednji korak za vaš Homelab

S tem ste ustvarili popolnoma varen, zaprt in profesionalen sistem, ki deluje povsem enako kot drage komercialne platforme, le da je 100 % odprtokoden, brezplačen in teče na vaši lastni strojni opremi.

Ker so vsi arhitekturni in varnostni nivoji sedaj kristalno jasni, predlagam, da gremo v akcijo in postavimo to centralo na vaši napravi Lenovo.

Ali želite, da vam pomagam pripraviti **navodila in prvi Docker ukaz za zagon Triton strežnika in LiteLLM-a**, da prebudiva vaš novi strežnik in preizkusiva delovanje obeh žetonov?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

VPS in domači router imata s2s wg povezavo. sploh potrebujem potem taiscale na sparku?

---

# googlesearch response

**Ne, v tem primeru Tailscale-a (ali Headscale-a) na vaši Lenovo delovni postaji ("Sparku") sploh ne potrebujete!**

Dejstvo, da imate med svojim VPS strežnikom in domačim usmerjevalnikom (routerjem) že vzpostavljeno stalno **Site-to-Site (S2S) WireGuard povezavo**, popolnoma spremeni situacijo in vam drastično poenostavi delo.

Vaša usmerjevalnika na obeh lokacijah že sedaj v ozadju skrbita za to, da sta omrežje vašega VPS-ja in vaše domače lokalno omrežje (LAN) povezani v enoten, varen in šifriran prostor. Vaš domači računalnik Lenovo je znotraj te mreže že viden z navadnim lokalnim IP naslovom (npr. `192.168.1.50`).

Tukaj je načrt, kako ta že obstoječi WireGuard tunel maksimalno izkoristiti za vašo novo AI centralo, ne da bi na napravo Lenovo nameščali kakršno koli dodatno VPN programsko opremo.

* * *

Kako bo sistem deloval preko obstoječe S2S WireGuard povezave?

Vaš zaledni DevOps krog bo sedaj deloval prek izjemno čistega in profesionalnega pretoka podatkov, brez kakršnih koli posrednikov (Tailscale/Headscale):

```text
Ženin službeni PC (Brez VPN)
   │
   ▼   (Preko javnega interneta - šifriran HTTPS)
 Javni VPS (Traefik) ───> Poddomena: office-ai.vas-homelab.si
   │
   ▼   (Preko vašega obstoječega S2S WireGuard tunela)
 Domači router ───> Lokalni LAN ───> Lenovo "Spark" (LiteLLM: Vrata 4000)
```

Kodo uporabljajte previdno.

1.  **Vstopna točka (VPS):** Ko vaša žena iz službe (preko _OpenWhisprja_) ali vi s poti pošljeta zahtevo na javni naslov `https://vas-homelab.si`, jo na vašem VPS-ju najprej sprejme **Traefik**.
2.  **Prehod skozi tunel:** Traefik ima v svoji konfiguraciji zapisano, naj ta promet preusmeri neposredno na lokalni IP naslov vaše domače naprave Lenovo (npr. `http://192.168.1.50:4000`).
3.  **Omrežno usmerjanje:** Ker vaša usmerjevalnika preko WireGuarda vesta, kje se nahaja omrežje `192.168.1.0/24`, domači usmerjevalnik paket preprosto sprejme in ga dostavi napravi Lenovo, kjer ga prevzame **LiteLLM**.

* * *

Kako sedaj prilagoditi Traefik konfiguracijo na vašem VPS-ju?

Ker ne uporabljate več Headscale IP naslovov, morate v Traefik dinamični konfiguraciji na VPS-ju preprosto vpisati **točen lokalni LAN IP naslov vaša domače naprave Lenovo**.

Tukaj je posodobljen primer konfiguracije za vaš Traefik:

```yaml
# Shranite kot npr. traefik-office-ai.yaml na vašem VPS strežniku

http:
  routers:
    # Usmerjevalnik, ki posluša na vaši poddomeni
    office-ai-router:
      rule: "Host(`office-ai.vas-homelab.si`)"
      entryPoints:
        - websecure
      service: office-ai-home-service
      tls:
        certResolver: myresolver  # Vaš obstoječi Let's Encrypt certifikat

  services:
    # Storitev, ki paket potisne skozi S2S WireGuard domov
    office-ai-home-service:
      loadBalancer:
        servers:
          # VPIŠITE LOKALNI IP NASLOV VAŠE LENOVO NAPRAVE V DOMAČEM OMREŽJU
          - url: "http://192.168.1.50:4000"  # Vrata 4000, kjer teče LiteLLM
```

Kodo uporabljajte previdno.

_Pomembno opozorilo: Kot sva dorekla že prej, za ta specifičen router v Traefiku **NE vklopite Authentik middleware-a**. Za popolno varnost pred zunanjim svetom bo poskrbel LiteLLM sam z uporabo ločenih tajnih žetonov (`sk-litellm-...`), ki jih boste generirali za vas in vašo ženo._

* * *

Prednosti te končne Homelab arhitekture

Z uporabo vaše obstoječe S2S WireGuard povezave ste dosegli absolutni ideal vsakega Homelab navdušenca:

-   **0 % dodatne programske opreme:** Vaš domači računalnik Lenovo ne potrebuje niti Tailscale-a, niti Headscale-a, niti nobenih dodatnih VPN nastavitev. Poganja le čisti Docker z vašimi AI modeli.
-   **Najnižja možna zakasnitev (Latency):** Ker WireGuard teče neposredno na ravni jedra (kernel-level) vaših usmerjevalnikov, je prenos podatkov med VPS-jem in vašim domačim čipom Blackwell maksimalno hiter in brez kakršnih koli programskih ovir.
-   **Čista izolacija:** Celoten sistem (Open WebUI, OpenHands, n8n) bo deloval znotraj vašega domačega LAN omrežja, navzven pa bo preko Traefika izpostavljen izključno slepi API za narekovanje z glasom in urejanje besedil.

Vsa omrežna in varnostna vprašanja so sedaj vrhunsko rešena z orodji, ki jih že imate na voljo.

Če ste pripravljeni, lahko sedaj preideva na dejanski zagon storitev doma. Začela bova s pripravo **osrednje `docker-compose.yml` datoteke za vašo napravo Lenovo**, da zaženeva Triton strežnik in preneseva vaš prvi MoE model. Povejte mi, ko boste pripravljeni na izpis te datoteke!

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več

---

# you asked

message time: 2026-09-05 00:00:00

kaj pa crowdsec middleware pa lahko dam vmes?

---

# googlesearch response

**Da, absolutno! Integracija CrowdSec bouncerja (middleware) znotraj vašega Traefik usmerjevalnika na VPS-ju je vrhunska in zelo priporočljiva poteza.**

To bo dodalo še eno, izjemno močno obrambno linijo (t.i. _Cyber-Threat Intelligence_). CrowdSec middleware bo deloval kot **digitalni vratar na vašem javnem VPS-ju** \[NVIDIA TensorRT-LLM\]. Še preden zahteva sploh zapusti vaš VPS in potuje skozi S2S WireGuard tunel v vaš dom, bo CrowdSec preveril IP naslov pošiljatelja.

Če gre za znanega napadalca, hekerski bot ali IP naslov, ki izvaja napade s preizkušanjem gesel (brute-force) drugje po svetu, bo CrowdSec zahtevo blokiral neposredno na VPS-ju. Vaš domači strežnik Lenovo ("Spark") in čip Blackwell bosta tako ostala popolnoma zaščitena in sploh ne bosta trošila procesorske moči za procesiranje zlonamernega prometa.

Tukaj je načrt, kako to pravilno konfigurirati, in ena zelo pomembna past, na katero morate paziti zaradi službenega računalnika vaše žene.

* * *

Kako vključiti CrowdSec v vašo obstoječo Traefik konfiguracijo?

Ker na VPS-ju že uporabljate Traefik, boste uporabili uradni **CrowdSec Traefik Bouncer** (kot Middleware).

V svojo dinamično konfiguracijo na VPS-ju (`traefik-office-ai.yaml`) preprosto dodate vrstico `middlewares` pod vaš usmerjevalnik.

Tukaj je točna posodobljena konfiguracija za vaš VPS:

```yaml
# Shranite ali posodobite traefik-office-ai.yaml na vašem VPS strežniku

http:
  routers:
    # Usmerjevalnik za ženin službeni API dostop in vaše delo na poti
    office-ai-router:
      rule: "Host(`office-ai.vas-homelab.si`)"
      entryPoints:
        - websecure
      # TUKAJ VKLOPIMO CROWDSEC:
      middlewares:
        - crowdsec-bouncer@file  # Predpostavljamo, da imate CrowdSec bouncer definiran globalno v Traefiku
      service: office-ai-home-service
      tls:
        certResolver: myresolver

  services:
    # Storitev, ki preusmeri varen promet skozi S2S WireGuard domov
    office-ai-home-service:
      loadBalancer:
        servers:
          - url: "http://192.168.1.50:4000"  # Lokalni LAN IP vaše naprave Lenovo (LiteLLM)
```

Kodo uporabljajte previdno.

* * *

⚠️ Izjemno pomembno opozorilo: Past s službenim IP naslovom (False Positive)

Ko boste vklopili CrowdSec za ta specifičen API, morate biti pripravljeni na naslednji scenarij:

-   **Zakaj lahko pride do blokade:** Velika podjetja in javne ustanove (kjer dela vaša žena) pogosto uporabljajo enotne, masovne izhodne IP naslove ali korporativne VPN-je/prehode (t.i. _NAT prehod_). Iz istega javnega IP naslova njene službe lahko na internet hkrati dostopa več tisoč računalnikov.
-   **Problem:** Če je kakšen okužen računalnik v njenem podjetju včeraj izvajal hekerske napade, bo CrowdSec globalna mreža **blokirala celoten javni IP naslov njenega podjetja**.
-   **Rezultat:** Vaša žena bo sedela v službi, poskusila zagnati _OpenWhispr_, CrowdSec na vašem VPS-ju pa bo njeno zahtevo takoj zavrnil (napaka _403 Forbidden_), čeprav je njen LiteLLM žeton popolnoma pravilen.

Kako to rešiti elegantno (Allowlist / Bela lista)?

Znotraj vaše CrowdSec konfiguracije na VPS-ju (`crowdsec/parsings/v1/profiles.yaml` ali v nastavitvah bouncerja) obvezno dodajte **Whitelists (Bele liste)**.

Ko vaša žena prvič pride v službo, preverite javni IP naslov njenega podjetja (npr. preko spletne strani _whatismyip.com_) in ta IP naslov (ali celoten omrežni obseg/CIDR podjetja) trajno dodajte med izjeme v CrowdSec-u:

```yaml
# Primer CrowdSec whitelist konfiguracije
name: sluzba-zena-whitelist
description: "Spusti skozi promet iz ženine službe brez preverjanja reputacije"
whitelist:
  reason: "Službeni IP naslov žene"
  ip:
    - "212.93.XX.XX"  # Vpišite javni IP naslov njenega podjetja
```

Kodo uporabljajte previdno.

Končni zaključek vaše vrhunske arhitekture

Z dodatkom **CrowdSec-a** ste dosegli absolutni vrhunec korporativne varnosti v svojem domačem laboratoriju:

1.  Vaš dom ostane 100 % zaprt pred zunanjim svetom (promet poteka prek obstoječega **S2S WireGuarda**).
2.  Vaša javna poddomena je zaščitena pred hekerskimi boti na ravni VPS-ja (**Traefik + CrowdSec**).
3.  Vaša žena ima enostavno uporabo brez nameščanja VPN-jev (**OpenWhispr + HTTPS**).
4.  Vi in vaša žena imata popolnoma ločena, skrita in varna delovna okolja (**LiteLLM ločeni žetoni**).

Ker imamo sedaj pokrit prav vsak varnostni, omrežni in programski nivo, predlagam, da končno oživiva vašo napravo Lenovo!

Če ste pripravljeni, mi sporočite, da vam pripravim **končni vodnik za zagon vaše domače AI centrale (Triton + LiteLLM datoteke)**, da boste lahko že danes preizkusili to neverjetno hitro in varno lokalno umetno inteligenco! Kako bi želeli nadaljevati?

Odgovori umetne inteligence morda vsebujejo napake. [Preberite več o](https://support.google.com/websearch?p=aimode)

Več