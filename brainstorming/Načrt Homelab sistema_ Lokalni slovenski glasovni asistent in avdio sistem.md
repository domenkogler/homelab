Tukaj je pregleden in strukturiran **vodič za prihodnjo referenco**, ki povzema celotno zasnovo vašega domačega laboratorija (homelab), izbrane komponente in argumente za zavrnitev nekaterih naprav.

## ---

**📝 Načrt Homelab sistema: Lokalni slovenski glasovni asistent in avdio sistem**

Ta dokument služi kot tehnična podlaga za postavitev pametne hiše z odprtim, lokalnim delovanjem (**Local-Only / Cloud-Free**), ki bo prijazna do Android naprav in bo estetsko poenotena z vašim stanovanjem.

## ---

**🏗️ 1\. Možgani sistema: Proxmox in lokalni AI**

Za poganjanje celotnega sistema in procesiranje slovenskega jezika je izbrana strojna oprema z visoko mrežno prepustnostjo in namenskim čipom za umetno inteligenco.

* **Izbrana komponenta**: **Minisforum MS-A2**  
  * **Zakaj ta naprava**: Vsebuje procesor AMD Ryzen s tehnično naprednim **NPU** čipom, ki bo lokalno poganjal slovenski STT (Prepoznava govora preko *Whisper* modela) in lokalni LLM v Home Assistantu. Ponuja tudi **2x 10G SFP+** mrežna vrata in več NVMe rež za hiter homelab.  
  * **Upravljanje na daljavo**: Namesto kompleksnega enterprise IPMI čipa uporablja **AMD DASH** (Out-of-band management), kar je za potrebe homelaba v Proxmoxu več kot dovolj za oddaljen vklop/izklop in spremljanje sistema.  
* **Zavrnjeno**: **Supermicro E300-9D**  
  * **Razlog**: Čeprav ima pravi strojni IPMI (BMC), uporablja enterprise Xeon/Atom procesorje, ki **nimajo NPU čipa** za AI, kar pomeni, da bi lokalno procesiranje slovenskega jezika teklo prepočasi ali pa bi potrebovali potratno grafično kartico.

## ---

**🎙️ 2\. Ušesa in oči: Glasovni zajem in kuhinjski časovnik**

Za zajem glasovnih ukazov in nadzor nad kuhanjem se uporablja kombinacija namenskega hardverja in obstoječih naprav.

* **Izbrana komponenta za kuhinjo**: **Guition okrogli ESP32-S3 zaslon** (z vrtljivim gumbom)  
  * **Zakaj ta naprava**: Teče na odprtem sistemu **ESPHome**, stane med **20 € in 35 €** in se napaja preko stalnega USB-C kabla (nima baterije, saj mikrofon stalno posluša aktivacijsko besedo). Fizični vrtljivi gumb je idealen za kuhinjo, ko imate mokre ali umazane prste od moke. Sprednje steklo je odporno na kapljice vode (ni pa uradno vodoodporno). Deloval bo kot vizualni odštevalnik (timer) za kuhanje.  
* **Izbrana komponenta za ostale prostore**: **Android telefoni družinskih članov**  
  * **Zakaj ta rešitev**: Brezplačna možnost z vrhunskimi mikrofoni, ki že imajo vgrajeno odpravo šumov. Preko uradne aplikacije *Home Assistant Companion* ali aplikacij v ozadju (npr. *Willow*) se telefon spremeni v lokalni satelit.  
* **Zavrnjeno**: **Vgrajeni mikrofoni na pametnih zvočnikih (Sonos/Bose/JBL)**  
  * **Razlog**: Ti zvočniki imajo popolnoma zaprt ekosistem. Surovega zvoka iz njihovih mikrofonov ni mogoče preusmeriti v vaš lokalni slovenski LLM. Delujejo lahko le z Alexo ali Google Assistantom v oblaku.

## ---

**🔊 3\. Usta: Avdio sistem (Soundbar in prenosni zvočnik)**

Za predvajanje glasbe in zvoka iz TV-ja je izbran sistem, ki podpira Android naprave in lokalno komunikacijo znotraj domačega omrežja.

* **Izbrana komponenta za TV**: **WiiM Bar** (Soundbar)  
  * **Zakaj ta naprava**: Gre za "vse-v-enem" (All-in-One) Dolby Atmos soundbar, ki ponuja bogat zvok in bas učinke brez potrebe po dodatnih škatlah na tleh. Poveže se preko **HDMI eARC** s TV-jem (brez zakasnitve zvoka). Ima vgrajen **Chromecast** za nemoteno predvajanje iz katerega koli Android telefona v hiši. Vizualno se z unikatnim okrogli zaslonom popolnoma ujema z Guition zaslonom v kuhinji.  
* **Izbrana komponenta za prenos**: **Audio Pro (WiiM/Linkplay kompatibilen baterijski zvočnik)** ali **WiiM Mini** povezan na poljuben baterijski zvočnik z AUX vhodom.  
  * **Zakaj ta naprava**: Omogoča, da prenosni zvočnik deluje v istem Wi-Fi omrežju kot soundbar za večprostorski (multiroom) zvok, ko pa ga odnesete ven, deluje preko Bluetootha.

## **Zakaj so bili ostali avdio sistemi zavrnjeni?**

* **Sonos**: **ZAVRNJEN**. Nima vgrajene sistemske podpore za Android (nima Chromecasta), zato je pošiljanje poljubnega zvoka iz Android telefonov zakomplicirano. Ekosistem je preveč zaprt.  
* **JBL Authentics**: **ZAVRNJEN**. Ponuja sicer odlično podporo za Android, vendar ima izrazit **retro/usnjen videz**, ki ne paše v vaše stanovanje. Večina njihovih zmogljivih soundbarov pa za dobro delovanje zahteva velik, ločen **nizkotonec (woofer) na tleh**, kar oblikovno ni sprejemljivo za vašo ženo.  
* **Bose & Denon (HEOS)**: **ZAVRNJENI**. Oba sistema imata preveliko odvisnost od oblaka (**Cloud Dependency**) in računov. Bose je v preteklosti že ukinil podporo za starejše linije zvočnikov v oblaku (velika nevarnost za homelab), Denon pa zahteva stalno prijavo v oblak in ima opazne zakasnitve pri združevanju zvočnikov v skupine preko Home Assistanta.

## ---

**🌐 4\. Kako bo sistem deloval skupaj (Data Flow)**

\[Vaš Glas\] ➡️ \[Guition v kuhinji / Android telefon\] ➡️ (Wi-Fi) ➡️ \[Minisforum MS-A2 (Proxmox)\]  
                                                                           ↓  
                                                                  \[NPU procesira slovenski STT\]  
                                                                           ↓  
                                                                  \[Lokalni LLM ustvari odgovor\]  
                                                                           ↓  
\[WiiM Bar / Audio Pro zvočnik\] ⬅️ (Hitri Local Push) ⬅️ (Wi-Fi) ⬅️ \[Home Assistant izvede ukaz\]

Sistem je popolnoma neodvisen od zunanjega interneta. Če zunanje omrežje pade, bo vaša pametna hiša še vedno lokalno poslušala, procesirala in odgovarjala v slovenščini preko vaših WiiM zvočnikov.

---

Ko boste imeli opremo pripravljeno, me obvestite in skupaj bova pripravila **ESPHome programsko kodo za vaš novi okrogli Guition zaslon** ali pa nastavila **Whisper/Wyoming integracijo v Home Assistantu**\!