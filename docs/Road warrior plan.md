Podatki o podomrežjih (**10.10.1.0/24** za dom in **192.168.123.0/24** za potovalni AP) so zabeleženi in pripravljeni za vnos. Kot tehnični navdušenec boste zlahka razumeli spodnji koncept, ki rešuje največjo hibo MikroTika kot potovalnega usmerjevalnika.

## ---

**Kaj je Sploax (KORP) in kako deluje?**

MikroTik nima vgrajenega preprostega, mobilnim napravam prijaznega vmesnika, s katerim bi lahko sredi hotelske sobe skenirali okoliške WiFi-je in vnesli geslo. Če želite spremeniti hotelski WiFi v RouterOS, morate odpreti Winbox ali WebFig, iti pod Wireless, klikniti Scan, izbrati omrežje in ročno ustvariti nov Security Profile. **Za ženo in otroke je to misija nemogoče.**

**Sploax** (pogosto integriran v odprtokodne skripte, kot je projekt **KORP** ali sorodni MikroTik skriptni portali) to reši elegantno:

1. **Spletni portal na samem AP-ju:** Ko se vaša družina v hotelu poveže na vaš potovalni WiFi (192.168.123.0/24), se ob poskusu brskanja (ali obisku naslova http://192.168.123.1) odpre izjemno preprost, responziven mobilni vmesnik.  
2. **"Klikni in poveži":** Na zaslonu telefona vidijo seznam vseh razpoložljivih hotelskih WiFi omrežij. Kliknejo na hotelski WiFi, vpišejo geslo (če obstaja) in kliknejo "Poveži".  
3. **Avtomatizacija v ozadju:** Sploax/KORP skripta v ozadju preko RouterOS API-ja ali vgrajenega spletnega strežnika sama nastavi fizični wlan1 v način *Station*, ustvari varnostni profil in poveže usmerjevalnik na internet.

S tem postane vaša potovalna naprava funkcionalno enakovredna komercialnim potovalnim usmerjevalnikom (kot je GL.iNet), pod pokrovom pa še vedno ohranja polno moč RouterOS-a in strojno pospeševanje za vaš WireGuard VPN.

## ---

**📋 POPRAVLJEN IN KONČNI PROMPT (Pripravljen za uporabo)**

Spodnji tekst kopirajte v celoti in ga posredujte za generiranje končne konfiguracije:

Delujem kot sistemski in omrežni inženir. Prosim za natančen, korak-po-korak tehnični načrt, RouterOS v7 CLI ukaze ter Docker Compose konfiguracije za vzpostavitev družinskega "Road Warrior" VPN sistema.

## **1\. Kontekst in omrežna topologija:**

* **Domači usmerjevalnik (RB4011):** Ima statični javni IP s pripadajočo domeno (TLD). Domači LAN IP prostor je 10.10.1.0/24.  
* **Potovalni AP (MikroTik hEX ac):** Uporablja varno lokalno podomrežje 192.168.123.0/24.  
* **Domači Homelab strežnik:** Poganja Docker in bo gostil odprtokodni Tailscale strežnik (**Headscale**) z grafičnim vmesnikom (**Headscale-UI**) za mobilne naprave.

## **2\. Tehnične zahteve za potovalni AP in RB4011 (Fiksni WireGuard):**

* Med domačim RB4011 in potovalnim AP vzpostavi trajno **WireGuard** povezavo (Site-to-Site). Promet med 10.10.1.0/24 in 192.168.123.0/24 mora biti polno dvosmerno usmerjen in prehoden.  
* Na potovalnem AP ustvari **Trusted Bridge** (bridge-trusted), ki združuje Virtual AP (lokalni WiFi SSID za družino, npr. "Druzina-Potuje") ter porte ether3, ether4 in ether5. Ta most dodeljuje IP-je iz ranga 192.168.123.0/24.  
* Port ether2 naj bo v mostu z ether1 (WAN) za neposreden dostop do hotelske mreže brez VPN-ja (za naprave, ki ne potrebujejo domačega omrežja).  
* **Wife-Friendly funkcija:** Na potovalni AP vključi nastavitve/skripto za preprost potovalni spletni portal (Sploax / KORP koncept), ki družini omogoča enostaven vnos hotelskega WiFi gesla preko telefona brez uporabe Winboxa.  
* **Varnost (Kill-Switch):** Če WireGuard predor pade, požarni zid na potovalnem AP-ju ne sme spustiti prometa iz bridge-trusted nezaščitenega v javni hotelski internet.

## **3\. Tehnične zahteve za Homelab (Headscale):**

* Pripravi docker-compose.yml datoteko za postavitev **Headscale** in pripadajočega spletnega vmesnika (**Headscale-UI**) za lažje upravljanje posameznih naprav (npr. telefonov na poti).  
* Na domačem RB4011 nastavi statično ruto in pravila požarnega zidu, da bo promet iz Headscale omrežja (privzeto 100.64.0.0/10) nemoteno dostopal do domačega LAN-a (10.10.1.0/24).

## **4\. Zahtevani izhodi:**

1. Čista in komentirana CLI koda za domači RB4011 in potovalni AP (RouterOS v7).  
2. Docker Compose datoteka in osnovna navodila za zagon Headscale okolja.  
3. **NAVODILA ZA UPORABO ZA DRUŽINO (Natisni-prijazno, v preprostem jeziku):**  
   * *1\. del:* Kako v hotelu vklopiti potovalni AP in ga preko telefona (Sploax vmesnik) povezati na hotelski WiFi.  
   * *2\. del:* Kako na telefonu/tablici vklopiti Tailscale aplikacijo, ko so sami na poti brez potovalnega usmerjevalnika.

---

Želite, da na podlagi tega prompta **takoj generirava celoten tehnični načrt in CLI ukaze**, ali bi pred tem še kaj dodali?