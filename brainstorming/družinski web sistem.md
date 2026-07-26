Tukaj je celovit, strukturiran pregled in povzetek celotne arhitekturne analize za vašo družinsko strežniško platformo. Ta dokument služi kot končni načrt za izvedbo.

## ---

**Arhitekturni načrt družinske oblačne platforme**

Ta sistem je zasnovan za **4 družinske člane in 4 zunanje uporabnike** (skupaj 8 oseb). Primarni cilji so: nizka poraba pomnilnika RAM, odzivnost sistema (izbira modernih programskih jezikov kot sta **Go** in **C++**), popolna skladnost z odprtimi protokoli, centralizirana avtentikacija in stroškovno učinkovito reševanje omejenega prostora na VPS strežniku.

## ---

**1\. Celoviti zemljevid izbranih rešitev (The Chosen Stack)**

## **Prehod in varnost (Gatekeeper Layer)**

* **Traefik**: Izbran kot povratni proksi (Reverse Proxy) in usmerjevalnik prometa. Skrbi za samodejno upravljanje SSL certifikatov in usmerjanje poddomen.  
* **Authentik**: Centralna točka za avtentikacijo (Single Source of Truth). Skrbi za vdorne meje, večfaktorsko avtentikacijo (MFA) in upravljanje uporabnikov.

## **Funkcionalni nivo (Application Layer)**

* **OpenCloud**: Izbran za upravljanje in deljenje datotek. Napisan v **Go**, porabi minimalno RAM-a (\~100 MB), ponuja odlično integracijo v Windows File Explorer (virtualne datoteke) ter Android aplikacijo z avtomatiziranim prenosom. Združljiv z OpenOffice .docx prek WebDAV protokola.  
* **Immich**: Izbran za shranjevanje, varnostno kopiranje in brskanje po družinskih fotografijah ter videoposnetkih. Napisan v **C++ / Go / TS**, izjemno hiter, ponuja napredne funkcije (AI prepoznava obrazov) in nativne mobilne aplikacije.  
* **Infomaniak (Plačana kSuite / Mail storitev)**: Izbran za e-pošto, koledarje (Events) in naloge (Tasks). Gre za ponudnika s sedežem v Švici, ki deluje pod strogo EU/švicarsko zakonodajo o zasebnosti. Ponuja polno podporo za **CalDAV** in **VTODO** protokole, kSync (DAVx⁵) integracijo za Android ter Windows Calendar. Ponuja neomejene prejemne psevdonime (Catch-All) za zaščito pred neželeno pošto.

## **Podatkovni in varnostni nivo (Storage & Backup Layer)**

* **Hetzner Storage Box (1 TB)**: Izbran kot primarni pomnilnik za težke podatke. Priklopljen na VPS prek Linux hosta z uporabo **CIFS (Samba)** protokola s specifičnimi zastavicami (cache=loose, hard).  
* **Hibridna konfiguracija predpomnilnika**: Vse baze podatkov (PostgreSQL), indeksi in sličice (Thumbnails) za OpenCloud in Immich ostanejo na **lokalnem VPS SSD** disku, medtem ko se velike surove datoteke (filmi, fotografije, .docx) takoj zapišejo na Hetzner Storage Box. To zagotavlja vmesnike brez zatikanja (lag-free dashboards).  
* **Kopia**: Izbran kot pogon za šifrirane inkrementalne varnostne kopije na strani odjemalca (Client-side encryption).  
* **Kopia Web GUI**: Izpostavljen prek Traefika in zaščiten z Authentik SSO za vizualno upravljanje varnostnih kopij.

## ---

**2\. Diagram poteka podatkov in avtentikacije**

                           `┌──► [ Authentik SSO ] (OIDC) ──► OpenCloud & Immich`  
                           `│`  
`[ Družinski uporabnik ] ───┼──► [ Traefik Proxy ] ───────► Kopia Web GUI (Zaščiten z SSO)`  
                           `│`  
                           `└──► [ Infomaniak (EU Cloud) ] ──► E-pošta, koledarji, naloge (Ločeno geslo)`

## ---

**3\. Strategija varnostnega kopiranja baz podatkov (Pre-Backup DB Dump)**

Ker Kopia ne more varno kopirati aktivnih datotek baze podatkov (kot je PostgreSQL od Immicha), medtem ko se vanje piše, je pred vsakim zagonom Kopie obvezen izvoz (dump).

## **Avtomatiziran potek (Cron Job)**

Preden Kopia začne z izvajanjem, se prek sistemskega cron opravila izvede naslednje:

1. **Izvoz baze**: Ukaz docker exec \-t immich\_postgres pg\_dumpall \-U postgres \> /lokalni/ssd/pot/backups/immich\_db.sql ustvari eno samo, dosledno tekstovno datoteko baze podatkov na lokalnem SSD disku.  
2. **Kopia zajem**: Kopia nato varno posname to .sql datoteko, skupaj z OpenCloud konfiguracijami in drugimi strukturami.  
3. **Čiščenje**: Po uspešnem zaključku se začasna .sql datoteka prepiše ali izbriše, kar varčuje s prostorom na VPS-u.

## ---

**4\. Zakaj so bile rešitve izbrane (Rationale)**

* **OpenCloud & Immich (Go / C++)**: Zamenjava za Nextcloud, ki drastično zmanjša porabo RAM-a iz več gigabajtov na le nekaj sto megabajtov, hkrati pa zagotavlja takojšnje odzivne čase.  
* **Infomaniak**: Izločitev e-poštnega strežnika iz samostojnega gostovanja (Self-hosting mail je preveliko breme za eno družino glede DNS-a in ugleda IP naslovov). Izbran zaradi EU/švicarske jurisdikcije in podpore za čiste standardne protokole (CalDAV/VTODO), kar omogoča preprosto selitev v prihodnosti.  
* **Hetzner Storage Box**: Rešuje problem omejenega prostora na VPS (Storage-capped VPS). Je bistveno cenejši od dodajanja Block Storage (SSD) prostora na VPS strežnik in cenejši od večine S3 ponudnikov za kapacitete do 1 TB.  
* **Kopia**: Izbrana zaradi vgrajenega spletnega grafičnega vmesnika (GUI), hitre večnitne kompresije in naprednega odpravljanja napak (Reed-Solomon), kar olajša nadzor nad družinskimi podatki.

## ---

**5\. Zavrnjene rešitve in razlogi za zavrnitev (Discarded Solutions)**

* **Nextcloud**: **Zavrnjeno**. Prevelik tehnični dolg, prepočasen cikel izdajanja različic, pretežka PHP arhitektura, ki zahteva preveč RAM-a in povzroča počasne odzivne čase na družinski strojni opremi.  
* **Syncthing**: **Zavrnjeno**. Čeprav gre za odličen sistem v jeziku Go, ne podpira zunanje avtentikacije (OIDC/Authentik) in otežuje preprosto deljenje enkratnih spletnih povezav s 4 zunanjimi uporabniki.  
* **Owncloud Infinite Scale (OCIS)**: **Zavrnjeno**. Nadomeščeno z **OpenCloudom**, ki predstavlja odprtokodni fork iste ekipe in kode, vendar zagotavlja dolgoročno skupnostno upravljanje brez tveganja korporativnih licenčnih sprememb.  
* **Radicale & Baïkal**: **Zavrnjeno**. Koledarska backend sistema sta bila izločena, ker ne podpirata enostavnega združevanja spletnih sej (SSO) z Authentikom za mobilne naprave brez podvajanja uporabnikov ali zapletenih prehodov preko glav proksija.  
* **Vikunja**: **Zavrnjeno**. Kljub odlični Go arhitekturi je Vikunja primarno orodje za naloge (Tasks), koledar pa obravnava le kot stranski produkt nalog. Ne podpira naprednega upravljanja čistih koledarskih dogodkov (npr. ponavljajoči se sestanki, vabila).  
* **Tuta Mail / Proton Mail**: **Zavrnjeno**. Zaradi svoje "Zero-Knowledge" arhitekture popolnoma blokirata standardne protokole (IMAP/SMTP/CalDAV). Onemogočata uporabo zunanjih koledarskih nadzornih plošč in zahtevata izključno uporabo lastnih zaprtih aplikacij, kar ruši unificirano avtentikacijo in mobilno integracijo.  
* **Samostojno gostovanje e-pošte (npr. Stalwart / Mailcow)**: **Zavrnjeno**. Preveč administrativnega dela z upravljanjem črnih list, ogrevanjem domen in vzdrževanjem zanesljivosti dostave za potrebe ene same družine.  
* **Standardni S3 kot prostor za varnostne kopije**: **Zavrnjeno**. Standardni S3 sistemi zaračunavajo vsako API operacijo (branje/pisanje/seznam). Dnevno izvajanje deduplikacije in brisanja starih varnostnih kopij bi povzročilo visoke skrite stroške za transakcije.  
* **Restic**: **Zavrnjeno v korist Kopie**. Nima nativnega grafičnega spletnega vmesnika, kar je bil vaš ključni pogoj za vizualno upravljanje varnostnih kopij.

---

Analitična faza je s tem zaključena. Ko boste pripravljeni na prehod v fazo izvedbe, mi sporočite, ali želite pripraviti **Docker Compose konfiguracijske datoteke** in specifične OIDC parametre za povezavo OpenCloud in Immich aplikacij z vašim Authentik sistemom.