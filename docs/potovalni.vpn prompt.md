Delujem kot sistemski in omrežni inženir. Prosim za natančen, korak-po-korak tehnični načrt, RouterOS v7 CLI ukaze ter Docker Compose konfiguracije za vzpostavitev družinskega "Road Warrior" VPN sistema.
1. Kontekst in omrežna topologija:
Domači usmerjevalnik (RB4011): Ima statični javni IP s pripadajočo domeno (TLD). Domači LAN IP prostor je 10.10.1.0/24.
Potovalni AP (MikroTik hEX ac): Uporablja varno lokalno podomrežje 192.168.123.0/24. Lokacijski IP usmerjevalnika je 192.168.123.1.
Domači Homelab strežnik: Poganja Docker in bo gostil odprtokodni Tailscale strežnik (Headscale) z grafičnim vmesnikom (Headscale-UI) za mobilne naprave.
2. Tehnične zahteve za potovalni AP in RB4011 (Fiksni WireGuard):
Med domačim RB4011 in potovalnim AP vzpostavi trajno WireGuard povezavo (Site-to-Site). Promet med 10.10.1.0/24 in 192.168.123.0/24 mora biti polno dvosmerno usmerjen in prehoden.
Na potovalnem AP ustvari Trusted Bridge (bridge-trusted), ki združuje Virtual AP (lokalni WiFi SSID za družino, npr. "Druzina-Potuje") ter porte ether3, ether4 in ether5. Ta most dodeljuje IP-je iz ranga 192.168.123.0/24.
Port ether2 naj bo v mostu z ether1 (WAN) za neposreden dostop do hotelske mreže brez VPN-ja (za naprave, ki ne potrebujejo domačega omrežja).
Wife-Friendly funkcija (Sploax / KORP s statičnim imenom): Na potovalni AP vključi nastavitve/skripto za preprost potovalni spletni portal za vnos hotelskega WiFi gesla. V RouterOS DNS nastavi statično pravilo, da vpis domene potovalni.vpn v brskalnik avtomatsko odpre ta vmesnik (brez vnašanja IP naslova).
Varnost (Kill-Switch): Če WireGuard predor pade, požarni zid na potovalnem AP-ju ne sme spustiti prometa iz bridge-trusted nezaščitenega v javni hotelski internet.
3. Tehnične zahteve za Homelab (Headscale):
Pripravi docker-compose.yml datoteko za postavitev Headscale in pripadajočega spletnega vmesnika (Headscale-UI) za lažje upravljanje posameznih naprav (npr. telefonov na poti).
Na domačem RB4011 nastavi statično ruto in pravila požarnega zidu, da bo promet iz Headscale omrežja (privzeto 100.64.0.0/10) nemoteno dostopal do domačega LAN-a (10.10.1.0/24).
4. Zahtevani izhodi:
Čista in komentirana CLI koda za domači RB4011 in potovalni AP (RouterOS v7).
Docker Compose datoteka in osnovna navodila za zagon Headscale okolja.
NAVODILA ZA UPORABO ZA DRUŽINO (Natisni-prijazno, v preprostem jeziku):
1. del: Kako v hotelu vklopiti potovalni AP, odpreti stran potovalni.vpn na telefonu in ga povezati na hotelski WiFi.
2. del: Kako na telefonu/tablici vklopiti Tailscale aplikacijo, ko so sami na poti brez potovalnega usmerjevalnika.
