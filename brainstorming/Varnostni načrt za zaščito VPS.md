Tukaj je urejen in pregleden povzetek varnostnih ukrepov za dokumentacijo (**Authentik \+ Traefik**), pripravljen v čistem Markdown formatu.

## ---

**Varnostni načrt za zaščito VPS (Authentik \+ Traefik)**

Pregled ključnih korakov za zaščito javno dostopnih spletnih aplikacij pred brute-force napadi, DDoS grožnjami in nepooblaščenimi vdori.

## **1\. Zaščita pred brute-force napadi: CrowdSec vs Fail2Ban**

Za blokiranje zlonamernih IP-naslovov na ravni logov izberite eno od dveh rešitev. **CrowdSec** je močno priporočljiv zaradi proaktivne skupne obrambe.

* **CrowdSec (Priporočeno)**:  
  * **Prednosti**: Deluje na principu "skupne obrambe" (blokira IP-je, ki so napadli druge uporabnike); ponuja uradno in vnaprej pripravljeno zbirko firix/authentik.  
  * **Brezplačna uporaba**: Popolnoma brezplačen za osebno uporabo/home lab (vključuje lokalno zaščito, globalno bazo groženj in brezplačno spletno nadzorno ploščo).  
  * **Implementacija**: Namestitev agenta, vklop branja Docker logov v acquis.yaml ter namestitev bouncerja na reverse proxy (Traefik).  
* **Fail2Ban (Alternativa)**:  
  * **Prednosti**: Klasično, zanesljivo in 100 % lokalno orodje.  
  * **Slabost**: Zahteva ročno pisanje regularnih izrazov (regex) za Authentik loge in ne pozna globalnih groženj.

## **2\. Implementacija večfaktorske avtentikacije (MFA)**

Gesla niso več dovolj. V Authentiku obvezno uveljavite strogo politiko MFA za vse uporabnike:

* **WebAuthn / Passkeys**: Najbolj varna zaščita (FIDO2/strojni ključi) pred ribarjenjem (phishing) za skrbniške račune.  
* **TOTP**: Standardne časovne kode (npr. Google Authenticator, Bitwarden) kot obvezna osnova za družinske člane.

## **3\. Utrjevanje varnostnih záglavij v Traefiku**

Preprečite napade, kot so XSS, clickjacking in neželeno indeksiranje v iskalnikih. V Traefik konfiguracijo dodajte varnostni middleware:

http:  
  middlewares:  
    security-headers:  
      headers:  
        browserXssFilter: true  
        contentTypeNosniff: true  
        forceSTSHeader: true  
        stsSeconds: 31536000  
        stsIncludeSubdomains: true  
        stsPreload: true  
        frameDeny: true  
        customResponseHeaders:  
          X-Robots-Tag: "none,noarchive,nosnippet,notranslate,noimageindex"

## **4\. Skrivanje javnega IP-ja (Cloudflare Proxy & Geo-Blocking)**

Če uporabljate Cloudflare za DNS, ne izpostavljajte dejanskega IP-naslova svojega VPS-a:

* **Cloudflare Proxy (Oranžni oblakec)**: Skrije vaš IP in absorbira volumetrične DDoS napade.  
* **Geo-Blocking (WAF pravila)**: Na ravni Cloudflara brezplačno blokirajte ali izzivajte (CAPTCHA) promet iz držav, kjer vaša družina ne živi in jih ne obiskuje.

## **5\. Centralizirana avtentikacija (Forward Auth)**

Nobena interna aplikacija (npr. Nextcloud, Sonarr, nadzorne plošče) ne sme imeti neposredno izpostavljenega lastnega prijavnega okna na spletu.

* Uporabite **Authentik Forward Auth** (preko Outposta) znotraj Traefika.  
* Traefik bo tako zavrnil ves promet in zahteval prijavo skozi Authentik, še preden bo paket sploh dosegel ciljno aplikacijo.

## **6\. Varnost na ravni Docker infrastrukture**

* **Izolacija omrežij**: Ne dajajte vseh kontejnerjev v eno veliko omrežje. Ustvarite ločeno traefik-public omrežje samo za komunikacijo med Traefikom in spletnimi porti aplikacij. Podatkovne baze pustite v povsem ločenih internih omrežjih.  
* **Omejevanje pravic**: Kjer je le mogoče, v docker-compose.yml dodajte cap\_drop: \[ALL\] in zaženite kontejnerje kot "non-root" uporabnik.

## **⚠️ Nujno opozorilo glede delovanja (Trusted Proxies)**

Ker promet teče preko reverse proxyja (Traefik/Cloudflare), bo Authentik v logih privzeto videl le lokalni IP vašega proxyja.

* **Posledica**: Če to pustite, bosta CrowdSec ali Fail2Ban pomotoma blokirala vaš lastni proxy in sesula celoten sistem.  
* **Rešitev**: V Authentik konfiguraciji (docker-compose.yml ali config.yml) obvezno pravilno nastavite spremenljivko AUTHENTIK\_TRUSTED\_PROXIES s pravilnimi IP naslovi vaših proxyjev.

---

Če boste med implementacijo katerega izmed korakov potrebovali **točne primere Docker Compose datotek** ali **Traefik oznak (labels)**, mi javite, kateri del bova urejala najprej.