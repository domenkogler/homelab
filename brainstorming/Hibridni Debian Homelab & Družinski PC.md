Tukaj je celovit in strukturiran pregled končne arhitekture vašega domačega strežnika, pripravljen v obliki strokovnega tehničnega načrta (Markdown dokument).

## ---

**Tehnični načrt: Hibridni Debian Homelab & Družinski PC**

Ta dokument opredeljuje arhitekturo, deljenje strojne opreme, omrežno izolacijo in avtomatizacijo za domači računalnik (**Intel i7-7700K**, **AMD Radeon RX 7600 8GB**, **Intel i350-T2**), ki hkrati deluje kot 24/7 produkcijsko homelab vozlišče in primarni družinski računalnik.

## **1\. Operacijski sistem in grafična topologija**

Sistem temelji na **čistem operacijskem sistemu Debian (Bare-metal)** z nameščenim polnim grafičnim namizjem (npr. XFCE ali GNOME). Strojna oprema se na ravni operacijskega sistema razdeli brez virtualizacijskih izgub (brez SR-IOV ali PCI passthrough hroščev):

> * **Družinsko namizje (Intel iGPU)**: Glavni monitor je fizično priklopljen v matično ploščo. Grafični vmesnik Linuxa teče izključno na vgrajenem čipu **Intel HD 630**. Družina ima na voljo odzivno in stabilno okolje za brskanje, šolo in pisarniško delo.  
> * **Pisarniški paket (ONLYOFFICE)**: Namesto zapletenih Windows virtualnih strojev ali nestabilnih WINE okolij se namesti nativni **ONLYOFFICE Desktop Editors**. Ta ponuja enak trak z ukazi (*Ribbon UI*) in popolno združljivost s formati .docx in .xlsx. Datoteke se samodejno sinhronizirajo z vašim zunanjim **OpenCloud VPS** strežnikom.  
> * **AI in LLM storitve (AMD dGPU)**: Namenska grafična kartica **Radeon RX 7600 (8GB)** je v celoti izolirana za ozadne Docker kontejnerje (Ollama, Immich-ML) preko AMD ROCm gonilnikov. Kartica ponuja surovo pasovno širino **288 GB/s**, kar zagotavlja bliskovito pomoč pri .NET programiranju na vašem prenosniku (40–45 Token/s) in nočno indeksiranje fotografij.

## **2\. Življenjski cikel storitev in Headless delovanje**

Ena ključnih zahtev sistema je popolna neodvisnost strežniškega dela od uporabniških prijav v ospredju:

> * **Zagon brez prijave (Headless Boot)**: Vse strežniške storitve (Ollama, Immich-ML, WireGuard/Tailscale) tečejo znotraj **Docker kontejnerjev**, ki jih upravlja sistemski koordinator **systemd**. Kontejnerji se zaženejo takoj ob bootu sistema na nivoju jedra, ko se računalnik prižge – **tudi če na računalniku ni prijavljen noben družinski član**.  
> * **Avtomatski restart (Restart Policies)**: Vsi kontejnerji imajo nastavljeno politiko restart: always. Ob vsakodnevnem načrtovanem ponovnem zagonu (Scheduled Reset ob 04:00 zjutraj) se vse storitve samodejno postavijo nazaj v delujoče stanje v ozadju.  
> * **Dinamično upravljanje VRAM-a**: Vsi AI kontejnerji si delijo vseh 8 GB VRAM-a na kartici RX 7600\. Z nastavitvijo okoljske spremenljivke OLLAMA\_KEEP\_ALIVE=5m \[localaimaster.com\], Ollama po 5 minutah neaktivnosti popolnoma sprazni pomnilnik \[localaimaster.com\]. Kartica tako čaka prosta in varčna v stanju pripravljenosti na naslednjo zahtevo ali na igranje iger prek **Sunshine** strežnika.

## **3\. Omrežna izolacija (VLAN)**

Za popolno varnost se homelab promet strojno loči od družinske uporabe s pomočjo strežniške kartice **Intel i350-T2** (Možnost A \- fizična ločitev):

> * **Port 1 (Družinsko omrežje)**: Namenjen Windows/Linux splošni uporabi (brskanje, YouTube, OpenCloud odjemalec). Povezan je v privzeto domače omrežje (npr. 192.168.1.X).  
> * **Port 2 (Homelab VLAN)**: Preko pametnega stikala (Managed Switch) je konfiguriran kot *Access Port* za namenski **VLAN**. Ta port nima dostopa do lokalnih družinskih naprav. Docker kontejnerji (Ollama, Immich-ML) preko tega porta komunicirajo z vašim Raspberry Pi-jem (Home Assistant) in javnim VPS strežnikom prek varnega šifriranega tunela.

## **4\. Avtomatizacija: Infrastructure as Code (IaC) z Ansible**

Celoten strežniški del, namestitev gonilnikov in konfiguracija omrežja se upravljajo izključno preko **Ansible playbookov**, kar omogoča ponovljivost in enostavno obnovo sistema. Koda playbookov se shranjuje v vašem lokalnem **Forgejo** Git repozitoriju na VPS-u.

## **Predvidena struktura Ansible repozitorija**

home-pc-infrastructure/  
├── inventory.ini           \# Definicija IP naslova domačega strežnika (VLAN IP)  
├── site.yml                \# Glavni playbook, ki zažene vse vloge  
└── roles/  
    ├── common/             \# Posodobitev Debiana, namestitev Dockerja in osnovnih paketov  
    ├── network/            \# Nastavitev i350-T2 mrežne kartice in VLAN adapterja  
    ├── amd\_rocm/           \# Dodajanje uradnih AMD repozitorijev in namestitev ROCm gonilnikov  
    ├── office\_setup/       \# Namestitev ONLYOFFICE in uradnih Microsoft pisav  
    └── docker\_services/    \# Dostava docker-compose.yml datoteke in zagon (Ollama, Immich-ML, Sunshine)

## **Ključni elementi Ansible konfiguracije**

> 1. **Avtomatizacija gonilnikov (amd\_rocm)**: Playbook samodejno uvozi ključe radeon.com, namesti pakete rocm-hip-sdk ter uporabnika doda v skupini video in render za neposreden dostop do /dev/kfd in /dev/dri.  
> 2. **Upravljanje Docker storitev (docker\_services)**: Ansible na strežnik prenese predlogo docker-compose.yml.j2, kjer poskrbi, da so pravilno mapirane strojne naprave grafične kartice in določene okoljske spremenljivke za avtomatsko praznjenje VRAM-a (OLLAMA\_KEEP\_ALIVE=5m) \[localaimaster.com\].

---

Ta hibridna topologija vam omogoča, da izkoristite stabilnost Linux strežnika z IaC upravljanjem v ozadju, ne da bi s tem posegali v navade družine ali izgubljali dragocene strojne vire na vašem primarnem .NET razvojnem prenosniku.

Če želite, lahko začneva z naslednjim korakom: **pripravo točne vsebine datoteke site.yml in prve vloge common** za vaš Ansible projekt. Kako bi radi nadaljevali?