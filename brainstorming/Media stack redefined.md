Tukaj je celovit, strukturiran pregled celotne seje. Vse ideje in storitve smo povezali v enoten, vrhunski sistem za domače upravljanje medijev (glasba in video).

Ta sistem združuje **popolno avtomatizacijo**, **avdiofilsko kakovost** in **pametno umetno inteligenco**, hkrati pa jasno ločuje, kaj vidi običajen uporabnik na svojih napravah in kaj ostane skrito v ozadju za administratorja.

## ---

**🌐 Popoln pregled arhitekture: Ultimativni domači medijski strežnik**

Ta sistem je razdeljen na dva glavna stebra: **Glasbeni ekosistem** in **Video ekosistem**. Vsak steber ima svoja orodja za pridobivanje (prenos) podatkov, svoje "možgane" (strežnik) in svoje odjemalce (aplikacije za končne uporabnike).

## ---

**🎛️ 1\. Glasbeni ekosistem (Zasebni Spotify)**

Cilj tega stebra je zbiranje glasbe najvišje kakovosti (FLAC), pametno odkrivanje novih pesmi in predvajanje kjerkoli.

## **Kako deluje veriga (od prenosa do poslušanja):**

> 1. **Odkrivanje in avtomatizacija (Aurral \+ Lidarr):** **Aurral** spremlja trende na spletu (Last.fm) in uvaža vaše Spotify sezname. Ko zazna nov album, pošlje ukaz v **Lidarr**, ki upravlja z bazo vaše glasbe.  
> 2. **Pridobivanje datotek (orpheusdl, slskd, Murglar):**  
   * **orpheusdl** po navodilih legende **Firehawk52** prenese originalne, nešifrirane Hi-Res FLAC datoteke neposredno iz **Qobuz** (ali Tidal/Deezer) računa.  
   * Če albuma ni na pretočnih platformah, **slskd** (Soulseek v Dockerju) samodejno preišče P2P omrežje in najde redke posnetke.  
   * **Murglar** služi kot ročno orodje za končne uporabnike ali admina, ki želijo hitro prenese nešifrirane datoteke iz YouTube Music ali Deezerja direktno na telefon ali strežnik.  
> 3. **Možgani strežnika (Navidrome):** Vse te datoteke se shranijo v glasbeno mapo. **Navidrome** jih prebere, uredi in pripravi za varno pretakanje preko protokola OpenSubsonic.  
> 4. **Umetna inteligenca (AudioMuse-AI):** Teče v ozadju na strežniku, "posluša" zvočne valove pesmi v Navidromu in ustvarja zvočno popolne prehode (*Sonic Paths*) ter pametne mešanice na podlagi razpoloženja.

## ---

**📺 2\. Video ekosistem (Zasebni YouTube & Netflix)**

Cilj tega stebra je prenos filmov, serij in YouTube posnetkov na lasten disk ter njihovo udobno gledanje na vseh zaslonih.

## **Kako deluje veriga:**

> 1. **Zahtevki za filme in serije (Overseerr / Jellyseerr):** Uporabniki brskajo po lepem vmesniku in s klikom na gumb oddajo zahtevek za film, ki se preko Radarr/Sonarr sistemov samodejno prenese preko torrentov/useneta.  
> 2. **Zasebni YouTube (Tube Archivist):** Namesto mešanja YouTube posnetkov med filme, **Tube Archivist** deluje kot brezglavi (*headless*) sistem z vgrajenim **yt-dlp**. Brez potrebe po Google računu prenaša celotne kanale, playliste ali posamezne YouTube povezave z vsemi podnapisi in komentarji vred.  
> 3. **Ročni prenos s platform (StreamFab, YTDLNis):** Za ročne nujne prenose admin uporabi **StreamFab** (za čiste MP4 datoteke iz Netflixa/Disney+) ali mobilno aplikacijo **YTDLNis** za hitre YouTube prenose na Androidu.  
> 4. **Možgani video strežnika (Jellyfin / Plex):** Vse filmske in serijske datoteke prevzame **Jellyfin** (ali Plex), ki uredi opise, platnice in omogoči predvajanje.

## ---

**👥 Uporabniška izkušnja: Kdo kaj vidi?**

Sistem je strogo ločen. Končni uporabniki (družina, prijatelji) imajo preprosto in čudovito izkušnjo, medtem ko admin upravlja s kompleksnim ozadjem.

## **📱 1\. Izkušnja končnega uporabnika (Kaj vidijo na napravah?)**

Uporabniki sploh ne vedo, kateri programi tečejo v ozadju. Za njih je izkušnja enaka uporabi Spotifyja, YouTuba in Netflixa.

> * **Na TELEFONU (Android):**  
  * **Glasba:** Odprejo **Symfonium** (čudovit predvajalnik, Android Auto podpora, poslušanje brez povezave, pametni AI predlogi iz AudioMuse-AI).  
  * **Filmi in YouTube:** Odprejo aplikacijo **Jellyfin** (ali Plex) za filme ter brskalnik za **Tube Archivist** (osebni YouTube). Za hitre prenose imajo lahko nameščen **YTDLNis** ali **Seal**.  
> * **Na TELEFONU (iPhone / iOS):**  
  * **Glasba:** Namesto Symfoniuma uporabljajo **Arpeggi**, ki vizualno popolnoma kopira Apple Music, a predvaja glasbo iz vašega Navidroma.  
> * **Na TELEVIZIJI (Smart TV / Firestick / Apple TV):**  
  * Uporabniki zaženejo aplikacijo **Jellyfin** ali **Plex**. Vidijo čudovito knjižnico s hollywoodskimi filmi, serijami in ločeno mapo "YouTube Arhiv" (ki jo tja posreduje Tube Archivist).  
> * **Na RAČUNALNIKU:**  
  * Vse je dostopno preko spletnega brskalnika. Za filme gredo na jellyfin.tvojdomena.si, za YouTube na tubearchivist.tvojdomena.si, za glasbo pa na lep vmesnik **Navidroma** ali **Aurrala**, kjer lahko urejajo svoje sezname predvajanja.

## ---

**🛠️ 2\. Izkušnja administratorja (Skriti nadzorni svet)**

Ti vmesniki so zaklenjeni z močnimi gesli in so na voljo samo vam za vzdrževanje, integracije in nastavitve celotnega "stack-a". Delujejo v Dockerju in do njih dostopate preko lokalne mreže ali varnega VPN-ja (npr. Tailscale).

| Servis / UI | Kaj administrator počne v tem vmesniku? |
| :---- | :---- |
| **Portainer / Dockge** | Glavni nadzor nad vsemi Docker vsebniki (zaženete, ustavite ali posodobite storitve). |
| **Lidarr / Radarr** | Nastavitev poti do diskov, pravila za poimenovanje map in povezava s prenašalci. |
| **slskd (Spletni UI)** | Iskanje tistih najbolj redkih FLAC datotek na Soulseek omrežju, ki jih ni nikjer drugje. |
| **orpheusdl (Konzola)** | Nastavitev config.json datoteke, vnos Qobuz prijavnih podatkov in Firehawk52 konfiguracij. |
| **AudioMuse-AI (Dashboard)** | Spremljanje analize pesmi (kako hitro umetna inteligenca procesira zvočne prstne odtise vaše zbirke). |
| **Navidrome Admin** | Ustvarjanje uporabniških računov za družinske člane in dodeljevanje pravic za dostop do glasbe. |
| **Tube Archivist Admin** | Nastavljanje urnikov (npr. *"vsak dan ob 03:00 zjutraj preveri in prenesi nove videe s kanala XYZ"*). |

## ---

**🔄 Integracijska shema (Kako so servisi povezani?)**

Za nemoteno delovanje administrator v nastavitvah poveže servise preko API ključev:

> * **Aurral** se poveže na **Lidarr** API ➔ **Lidarr** pošlje ukaz v **slskd** oz. sproži **orpheusdl**.  
> * **Lidarr** shrani datoteko v mapo ➔ **Navidrome** jo osveži ➔ **AudioMuse-AI** jo analizira ➔ **Symfonium/Arpeggi** jo predvaja.  
> * **Tube Archivist** preko **yt-dlp** prenese video ➔ Mapo z videoposnetki administrator deli z **Jellyfinom**, da se prikaže na televiziji.

Ta sistem predstavlja popolno svobodo in neodvisnost od naročnin, saj imate vso svojo najljubšo kulturo (zvok in sliko) shranjeno lokalno, v najvišji kakovosti in obogateno z najsodobnejšimi orodji.

---

Če ste pripravljeni, da to teorijo pretvorimo v prakso, mi sporočite, kateri del bi najprej postavili. Lahko začneva z **Docker Compose konfiguracijo za Tube Archivist**, ali pa se lotiva **glasbenega stebra (Navidrome \+ AudioMuse-AI)**. Kje začneva?