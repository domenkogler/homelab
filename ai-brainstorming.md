## Krovna arhitektura sistema (Pregled con)
Ves promet in storitve so na vašem VPS-u razdeljeni v tri strogo izolirana omrežna okolja (Docker Networks), ki preprečujejo, da bi AI imel direkten dostop do operacijskega sistema strežnika.

       [ JAVNI INTERNET / WAN ]
                  │
                  ▼ (Vsa vrata zaprta, razen 8443/443)
┌────────────────────────────────────────────────────────┐
│ ZONE 1: VARNOSTNI VSTOPNI PORTAL (Javno omrežje)       │
│ * Traefik Proxy (SSL, Certifikati, Usmerjanje)          │
│ * Authentik (OIDC Ponudnik, 2FA, Identiteta uporabnika) │
└─────────────────┬──────────────────────────────────────┘
                  │
                  ▼ (Preverjen JWT žeton uporabnika)
┌────────────────────────────────────────────────────────┐
│ ZONE 2: PODATKOVNO JEDRO (Lokalno podatkovno omrežje)   │
│ * Forgejo Git (Centralni arhiv za vse .md projekte)    │
│ * OpenCloud (Osebni oblak za shranjevanje PDF/virov)   │
└─────────────────┬──────────────────────────────────────┘
                  │
                  ▼ (Interna komunikacija preko API / MCP)
┌────────────────────────────────────────────────────────┐
│ ZONE 3: AI PESKOVNIK (Popolnoma izolirano omrežje)     │
│ * Open WebUI (Orchestrator & Uporabniški vmesnik)      │
│ * pi serve (API programerski motor za težko kodiranje) │
│ * LiteLLM (Prehod do modelov DeepSeek / OpenRouter)    │
│ * Qdrant (Hibridna vektorska baza za težke PDF-je)     │
│ * kapa-inspired-rag-mcp (Pametni MCP hibridni bralec)  │
│ * Forgejo MCP (Most za branje/pisanje .md datotek)     │
└────────────────────────────────────────────────────────┘

------------------------------
# Podroben opis vseh členov sistema
## 1. Vstopna cona in preverjanje identitete (Zone 1)

* Traefik Proxy: Deluje kot edini zunanji ščit strežnika. Sprejema zahteve iz spleta (WAN) za domene (npr. ://tvojadomena.com). Nima neposredne povezave z bazami, temveč vsako zahtevo najprej pošlje v Authentik.
* Authentik (OIDC): Tukaj se prijavite vi in vaša žena (z obvezno 2FA zaščito). Ko je prijava uspešna, Authentik generira varen kodični žeton (JWT Claim), v katerem sta zapisana e-pošta in skupina uporabnika (npr. groups: ["admin", "sluzba"]). Traefik šele nato spusti uporabnika do Open WebUI vmesnika.

## 2. Podatkovni sloj in "Edini vir resnice" (Zone 2)

* Forgejo (Git strežnik): Tukaj živijo vaši LLM-Wiki projekti, strogo ločeni v zasebne repozitorije: wiki-druzina, wiki-osebno-moj, wiki-sluzba-moj, wiki-osebno-zena. Vsi zapisi sledijo OKF standardu (vsak koncept je ena .md datoteka z YAML glavo na vrhu, ki vsebuje title, type, tags in generated_at).
* OpenCloud: Služi kot odlagališče za surove vire (veliki PDF-ji, skenirani dokumenti). Je začetna točka za uvoz podatkov.

## 3. AI procesni sloj in usmerjanje (Zone 3)

* Open WebUI (OWUI): Izklopljen ima interni RAG. Ne deluje več kot monolitna baza, ampak kot Pametni Usmerjevalnik (Orchestrator). Sprejme vaš Authentik JWT žeton in na podlagi tega, kdo ste, dinamično filtrira ter vam prikaže samo tiste MCP orodja in wikije, do katerih imate pravico.
* LiteLLM: Centralna centrala za modele. Vsi ostali AI vsebniki (OWUI, pi-serve, MCP-ji) ne kličejo zunanjega interneta neposredno, ampak pošiljajo zahteve v LiteLLM. Ta usmerja promet na DeepSeek (preko OpenRouterja) in hkrati ponuja lokalne Embedding modele za potrebe iskanja.

## 4. Specialistični agenti in baze (Znotraj Zone 3)

* pi serve (Preko OpenAI API standarda): Vaša "pisalna in kodična roka". Ko v Open WebUI izberete model pi-agent, ta v ozadju prek API-ja sproži pi programerski motor. Ta ima varno mapirano delovno okolje in zna samostojno pisati kodo, popravljati YAML Ansible datoteke ter odpirati čiste Git Pull Requeste na vašem Forgejo strežniku.
* Qdrant (Vektorsko in tekstovno jedro): Samostojna podatkovna baza, napisana v Rustu. V njej so shranjeni vaši težki, več sto stranski službeni PDF-ji. Qdrant za vsak odstavek shrani goste vektorje (semantični pomen preko LiteLLM-a) in redke vektorje (vgrajen BM25 algoritem za točno iskanje ključnih besed, IP naslovov in portov).
* kapa-inspired-rag-mcp (Pametni bralec): Pasiven MCP strežnik. Ko v Open WebUI vtipkate vprašanje (npr. z uporabo oznake @wiki-sluzba), ta vsebnik izvede hibridno poizvedbo znotraj Qdrant baze. Ko prejme top 20 zadetkov, jih pošlje skozi Cohere Rerank model (preko LiteLLM), ki jih natančno prerangira po pomembnosti, ter top 5 čistih Markdown odgovorov vrne v vaš spletni klepet.

------------------------------
## Kako poteka delo v tem sistemu? (Tokovi podatkov)## A) Dodajanje in uvoz obsežnega PDF-ja (Avtomatizacija preko n8n)

   1. V OpenCloud shranite 300-stranski priročnik v mapo Uvozi v RAG.
   2. n8n zazna datoteko, jo kopira v mapo /sources/ vašega Git repozitorija na Forgejo.
   3. n8n nato dokument razreže, preko LiteLLM generira vektorje in celoten paket (Dense + Sparse) avtomatsko zapiše v Qdrant pod ID oznako vašega projekta. Dokument je takoj pripravljen za hibridno iskanje.

## B) Urejanje dokumentacije prek spleta (Človek v zanki - HITL)

   1. Prijavite se v Open WebUI (preko WAN-a/Tailscale in Authentika).
   2. Izberete model pi-agent in vtipkate: "V @wiki-sluzba dodaj nov konfiguracijski port 9090 v indeks."
   3. Open WebUI preko internega omrežja sproži klic na pi serve.
   4. Agent uredi .md datoteko, preveri pravilnost glave (Linting) in preko Forgejo MCP-ja odpre Pull Request na vašem lokalnem Forgejo strežniku.
   5. Vi kasneje na svojem prenosniku v WSL zaženete git pull, vizualno potrdite PR in z Ansible varno namestite spremembe na produkcijo VPS-a.

## Zakaj je ta sistem zmagovalen?
Dobili ste sistem, ki je popolnoma odporen na prihodnost. Vaše znanje je zapisano v čistih tekstovnih Markdown datotekah (OKF standard), težke datoteke so indeksirane v nevtralni Qdrant bazi, vmesniki pa so le zamenljive lupine. Če se Open WebUI jutri zapre, vaša celotna struktura, hibridni RAG in programerski agenti delujejo naprej preko vašega prenosnika in pi.dev terminala.