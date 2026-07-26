Tukaj je celovit in pregleden čistopis celotne strojne in programske arhitekture vašega prihodnjega domačega laboratorija (**Homelab**). Vse komponente so izbrane z mislijo na **100-odstotno lokalno delovanje (brez oblaka)**, energetsko učinkovitost v mirovanju, stabilnost pri neprekinjenem delovanju (**24/7**) ter prijaznost do **Android** ekosistema.

## ---

**🏢 Čistopis Homelab sistema: Lokalni AI, Programiranje in Avdio**

Sistem je zasnovan za vgradnjo v namensko **standardno rack omarico (2U ali 4U)**, kar rešuje težave s pregrevanjem in hrupom manjših ohišij ob uporabi močnih računskih komponent.

## ---

**🎛️ 1\. Osrednje strojne komponente (Strežnik)**

* **Matična plošča**: **MSI PRO X870E WIFI**  
  * *Argumenti*: Ponuja strojno podporo za delitev linij v načinu **PCIe x8 / x8** neposredno iz procesorja za dve grafični kartici v prihodnosti. Ima maksimalen fizični razmak med režama za optimalno hlajenje in namenski dodaten 8-pin PCIe priključek na dnu plošče za stabilno napajanje dveh GPU kartic. MSI-jeva programska oprema (BIOS) prinaša vrhunsko stabilnost pri umerjanju DDR5 pomnilnika, hitre čase ponovnega zagona ter čisto IOMMU ločevanje naprav.  
* **Procesor**: **AMD Ryzen 7000 / 9000** (platforma AM5, npr. Ryzen 7 9700X ali Ryzen 9 9900X)  
  * *Argumenti*: Zagotavlja polno hitrost in neposredne linije PCIe 5.0 do primarne grafične kartice in glavnega diska brez strojno povzročenih zakasnitev. Uradno podpira **Unbuffered ECC (UDIMM) pomnilnik** za zaščito pred poškodbami podatkov (data corruption).  
* **Grafična kartica**: **AMD Radeon AI PRO R9700 32GB** (na začetku 1 kos, v prihodnosti 2 kosa)  
  * *Argumenti*: Ponuja ogromnih 32 GB hitrega VRAM-a na napredni 4nm arhitekturi (RDNA 4), kar zagotavlja veliko prostora za velike programerske modele in sočasne modele za pametno hišo. Ima nižjo porabo pod polno obremenitvijo (300 W max) in varčen headless idle način (\~12 W). *Blower* sistem hlajenja je idealen za rack ohišja.  
* **Napajalnik (PSU)**: **Corsair HX1500i** (1500 W, 80 Plus Platinum)  
  * *Argumenti*: Zagotavlja vrhunsko stabilnost in industrijske japonske komponente za delovanje 24/7. Na začetku z eno kartico deluje v svoji optimalni coni učinkovitosti (okoli 30-odstotna obremenitev) in v popolnoma pasivnem, neslišnem načinu (Zero RPM do 600 W). Vsebuje digitalni procesor (DSP) za spremljanje porabe v realnem času. Že prvi dan je pripravljen na takojšen priklop druge R9700 kartice brez menjave kablov.  
* **Shramba**: Hibridni sistem  
  * *AI in OS*: **1x vrhunski in izjemno hiter NVMe Gen 5 / Gen 4 disk** (npr. Samsung 990 Pro ali Crucial T700) v prvi M.2 reži, povezani neposredno na CPU. Skrbi za bliskovit prenos modelov v VRAM (cca 300 ms).  
  * *Mediji (Družinske slike in filmi)*: **2.5-palčni SATA SSD diski** (neslišni, varčni) ali **3.5-palčni klasični trdi diski (HDD)** za visoko kapaciteto po nizki ceni. Priključeni so preko SATA vrat na čipsetu, s čimer ne odžirajo PCIe linij grafičnima karticama.

## ---

**🌐 2\. Upravljanje in omrežje na daljavo (Headless)**

* **Upravljanje na daljavo**: **Zunanja naprava PiKVM**  
  * *Argumenti*: Priključi se na vgrajeno grafiko procesorja (iGPU) preko HDMI izhoda na matični plošči, s čimer se izogne vplivu na porabo namenskih AI kartic. Zagotavlja popoln bios-level nadzor, daljinski vklop/izklop/reset preko fizičnih žic ter virtual media (nalaganje ISO slik) brez enterprise licenc, tudi če celoten operacijski sistem strežnika zamrzne.  
* **Prihodnja omrežna kartica**: **Intel X710-DA2 (SFP+)** (projekt v prihodnosti)  
  * *Argumenti*: Vstavljena bo v spodnjo prosto PCIe režo preko čipseta. Za razliko od starejših enterprise kartic uradno podpira **PCIe ASPM varčevanje z energijo**, kar omogoča procesorju AMD Ryzen, da v mirovanju nemoteno pade v najgloblja varčna stanja (C6/C8 state). Povezava se izvede preko energetsko najbolj varčnega **DAC (Direct Attach Copper) kabla**.

## ---

**🎙️ 3\. Periferija (Ušesa, Oči in Usta)**

* **Kuhinja**: **Guition okrogli ESP32-S3 zaslon** z vrtljivim gumbom  
  * *Argumenti*: Teče na odprtem protokolu **ESPHome** in je preko stalnega USB-C napajanja vedno pripravljen na poslušanje slovenske aktivacijske besede (Wake Word). Fizični vrtljivi gumb je idealen za kuhinjsko rokovanje z mokrimi ali umazanimi prsti. Deluje kot lokalni mikrofon in vizualni kuhinjski časovnik (timer).  
* **Ostali prostori**: Obstoječi **Android telefoni družinskih članov** (preko aplikacije Home Assistant Companion / Willow).  
* **Avdio (Dnevna soba / TV)**: **WiiM Bar** (Dolby Atmos soundbar) \+ **Audio Pro** (prenosni baterijski zvočnik).  
  * *Argumenti*: Celoten avdio sistem deluje **100 % lokalno in brez odvisnosti od zunanjega oblaka (Cloud-Free)**. Soundbar se s prihodnjim TV-jem poveže preko HDMI eARC (brez zakasnitev). Za Android naprave ponuja nativno sistemsko podporo preko protokola **Google Chromecast built-in**. Okrogli zaslon na soundbaru se estetsko sklada z Guition zaslonom v kuhinji.

## ---

**🐳 4\. Programski koncept delovanja (Data Flow)**

* **Hipervizor**: **Proxmox VE** deluje kot osnova celotnega homelaba.  
* **AI okolje**: **Unprivileged LXC vsebnik**, v katerega se preko AMD ROCm 7.x gonilnikov neposredno mapirajo jedra grafične kartice. To omogoča stabilno delovanje brez t.i. "AMD GPU reset bug-a" ter možnost, da kartico sočasno uporablja več storitev (Ollama, Plex, itd.).  
* **AI Vmesnik**: **Ollama** (kot optimiziran wrapper za llama.cpp). Omogoča polno hitrost inference na grafični kartici in ponuja vgrajen pametni krmilnik za **dinamično nalaganje modelov na zahtevo (On-Demand via keep\_alive)**.

## **Režim delovanja pomnilnika (VRAM Management):**

1. **Način "Programiranje"**: Ko delate sami, Ollama v delčku sekunde naloži težak programerski model (npr. *Qwen 2.5-Coder 32B*) in izkoristi celotnih 32 GB VRAM-a.  
2. **Način "Družina doma"**: Ko niste aktivni ali ko se telefoni družine povežejo na domači Wi-Fi, Home Assistant preko API-ja izprazni koder model. Ollama v VRAM sočasno naloži manjše modele za pametno hišo (*Whisper STT*, *Llama HA LLM* in *Piper TTS* — skupaj \~7 GB). Ker so modeli stalno prisotni v hitrem VRAM-u, je odzivni čas glasovnih ukazov pod **2 sekundama**.  
3. **Način "Spanje/Služba"**: Ob vnaprej določenem urniku ali ko je hiša prazna, se vsi modeli odstranijo iz pomnilnika. Grafična kartica se spusti v globok spanec (poraba pade na minimalnih **\~12 W**), napajalnik Corsair pa popolnoma izklopi svoj ventilator.

## ---

**Zakaj so bili nekateri koncepti zavrnjeni?**

* **SFF / Mini PC**: Zavrnjen zaradi pregrevanja, hrupa majhnih ventilatorjev in pomanjkanja PCIe linij ob vgradnji dveh grafičnih kartic.  
* **Sonos avdio**: Zavrnjen zaradi zaprtosti in odsotnosti sistemske Chromrecast podpore za Android telefone.  
* **Bose & Denon avdio**: Zavrnjeni zaradi stroge odvisnosti od zunanjega oblaka (Cloud Dependency), ki ogroža dolgoročno delovanje homelaba.  
* **JBL Authentics**: Zavrnjen zaradi retro usnjenega videza, ki ne ustreza vašemu stanovanju, in potrebe po velikem ločenem nizkotoncu na tleh.  
* **Intel Core Ultra (Namizna platforma)**: Zavrnjena zaradi uradno potrjene strojne napake z zakasnitvami (latenco) na linijah za najhitrejše PCIe 5.0 NVMe diske ter nesorazmerno dragih matičnih plošč s x8/x8 podporo.

Ta dokument sedaj predstavlja vaš končni strojni in programski kažipot. Ko boste pripravljeni na naslednji korak, mi preprosto sporočite\! S čim bomo nadaljevali, ko bo čas za to?