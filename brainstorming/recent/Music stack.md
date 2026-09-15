Tukaj je celosten vsebinski povzetek vaše napredne glasbene postaje, prilagojene za **NVIDIA DGX Spark (GB10)**.

Murglar je iz celotne verige odstranjen, saj ga zaradi implementacije avtomatiziranega \*arr sistema ne potrebujete več.

## ---

**🏛️ Pregled komponent sistema in njihovih vlog**

## **1\. Uporabniški vmesnik za zahteve: Seerrg (Overseerr)**

> * **Vloga:** Vstopna točka za vas ali vaše bližnje.  
> * **Delovanje:** Preko lepega spletnega vmesnika poiščete izvajalca ali album in kliknete gumb za zahtevo prenosov.

## **2\. Možgani za avtomatizacijo: Lidarr**

> * **Vloga:** Upravljanje glasbene zbirke, nadzor nad prenosnimi odjemalci in urejanje datotek.  
> * **Delovanje:** Sprejme ukaz iz Seerrga, sproži iskanje po nastavljenih prioritetah in ko je glasba prenesena, jo pravilno poimenuje ter premakne v glavno mapo (/media/music).

## **3\. Primarni vir prenosov: Usenet (z indekserji in SABnzbd/NZBGet)**

> * **Vloga:** Hitro, varno in v večini primerov brezplačno pridobivanje glasbe visoke kvalitete.  
> * **Delovanje:** Lidarr preko Prowlarrja ali direktnih indekserjev najde NZB datoteko na Usenetu. SABnzbd jo prenese z maksimalno hitrostjo vaše povezave. V Lidarrju je nastavljen kot **1\. prioriteta**.

## **4\. Sekundarni vir (Fallback): Deemix / Deezer Premium**

> * **Vloga:** Rešilni jopič, ko albuma ni mogoče najti na Usenetu.  
> * **Delovanje:** Ker Murglar nima API-ja za avtomatizacijo, njegovo vlogo prevzame **Deemix** (povezan preko vmesnika *Lidarr-on-demand*). Če Usenet odpove, Lidarr samodejno preklopi na Deemix, ki z uporabo plačljivega Deezer Premium računa (oz. ARL piškotka) potegne želeni album v FLAC kakovosti neposredno iz Deezerjevih strežnikov. V Lidarrju je nastavljen kot **nizka prioriteta**.

## **5\. Glasbeni strežnik: Navidrome**

> * **Vloga:** Indeksiranje lokalne zbirke in pretakanje zvoka (deluje na OpenSubsonic protokolu).  
> * **Delovanje:** Vidi isto glasbeno mapo kot Lidarr. Ko Lidarr zaključi uvoz, preko Webhooka obvesti Navidrome, ki takoj osveži knjižnico. Skrbi za neposredno dostavo glasbenega toka na vaš telefon.

## **6\. Pametni pomočnik (Umetna inteligenca): AudioMuse-AI**

> * **Vloga:** Lokalna analiza zvoka (melodija, ritem, energija) in ustvarjanje pametnih povezav med pesmimi (Spotify AI DJ izkušnja).  
> * **Delovanje:** Povezan je z Navidromom. Ko se zbirka dopolni, AudioMuse-AI analizira zvočne valove in vnaprej zapiše AI podatke o podobnosti pesmi v bazo. Med samim predvajanjem glasbe ne troši sistemskih virov, saj Symfonium le prebere že vnaprej izračunane rezultate.

## **7\. Mobilna aplikacija: Symfonium (Android)**

> * **Vloga:** Vrhunski odjemalec za poslušanje glasbe na telefonu in v avtu (Android Auto).  
> * **Delovanje:** Poveže se na Navidrome preko OpenSubsonic protokola. Ker ta protokol podpira AudioMuse-AI razširitve, lahko v Symfoniumu sprožite funkcije, kot sta *Track Radio* ali *Artist Radio*, ki vam predvajata zvočno popolnoma ujemajoče se naslednje komade.

## ---

**🛠️ Ključni detajli implementacije na vašem strojni opremi**

> * **Faza 1: Začetni uvoz (GPU način):** Za analizo prvega velikega vala vaše glasbene zbirke AudioMuse-AI zaženete z uradno eksperimentalno Docker sliko :latest-nvidia-arm. Ta različica polno izkorišča Blackwell GPU arhitekturo vašega **DGX Sparka** in njegovih **128 GB enotnega (Unified) pomnilnika**. Analiza tisočev pesmi bo namesto več dni trajala le nekaj ur.  
> * **Faza 2: Vsakodnevno delovanje (Preklop na CPU):** Ko je začetni uvoz zaključen, v konfiguraciji preklopite na standardno ARM64 sliko :latest-arm64 in odstranite GPU rezervacijo. Sprotno dodajanje posameznih albumov iz Lidarra bodo zlahka in v nekaj minutah prežvečila procesorska ARM jedra, vaša močna grafična kartica pa ostane popolnoma prosta za druge projekte.  
> * **Integracija map:** Lidarr, Deemix in Navidrome morajo imeti v svojih kontejnerjih dostop do **iste fizične mape z glasbo**, da lahko avtomatizacija nemoteno prenaša, ureja in bere datoteke.

Če vas zanima naslednji korak, mi lahko sporočite, ali bi radi najprej uredili **povezavo med Lidarrjem in Deemixom** ali pa vas zanima točen postopek, kako iz brskalnika izvleči **Deezer ARL žeton** za zagon prenosov.