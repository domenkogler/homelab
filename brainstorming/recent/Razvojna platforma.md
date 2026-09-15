## **TEHNIČNA SPECIFIKACIJA: HIBRIDNI AI-DEVOPS EKOSISTEM**

Ta dokument predstavlja celovit in natančen povzetek celotne seje. Zasnovan je kot **enotni vir resnice (SSOT)** in tehnični načrt za popolno implementacijo sistema brez potrebe po branju preteklega klepeta.

## ---

**1\. STRUKTURA OMREŽNIH CON (Arhitektura & Izolacija)**

Sistem je razdeljen na tri strogo izolirane omrežne cone na VPS in domači infrastrukturi, povezane preko šifriranega **Headscale VPN (Mesh VPN)** predora. Noben AI vsebnik nima neposrednega dostopa do host OS zunaj svojih pravic.

 `[ JAVNI VPS ] (Zanesljivo jedro, 100 % Uptime)`  
   `│  CONA 1 (EDGE): Traefik (mTLS, SSL) -> Authentik (OIDC, 2FA)`  
   `│  CONA 2 (DATA CORE): Forgejo Git (Kanonika) & OpenCloud (PDF ingress)`  
   `└──▶ (Varna odhodna povezava na Signal API strežnike)`  
          `▲`  
          `│ (Šifriran Signal ChatOps kanal)`  
          `▼`  
 `[ UPORABNIK / TELEFON (SIGNAL APP) ]`  
          `▲`  
          `│ (Šifriran Signal ChatOps kanal)`  
          `▼`  
 `[ DOMAČE OMREŽJE ] (Lokalna infrastruktura, visoka zmogljivost)`  
   `│`  
   `├──▶ [ DOMAČI SRV ] (CONA 3 — AI SANDBOX / Koordinacija)`  
   `│      ├─ OpenClaw (Centralni koordinator / Signal bot)`  
   `│      ├─ LiteLLM Gateway (Usmerjevalnik poizvedb)`  
   `│      ├─ Qdrant (Centralna vektorska baza)`  
   `│      ├─ Mem0 (Epizodni/Znanstveni spomin)`  
   `│      └─ MCP Armada (HA, Qdrant, Forgejo strežniki)`  
   `│`  
   `└──▶ [ DGX SPARK ] (CONA 3 — AI SANDBOX / Računsko jedro)`  
          `└─ vLLM Engine (Čisti računski RAM za LLM & Embedding)`

## ---

**2\. EVALVACIJA IDEJ (Sprejete, prilagojene in zavrnjene komponente)**

## **Sprejete in integrirane ideje**

> * **Tretji Git repozitorij za dokumentacijo (Forgejo \- Cona 2):** Ločen od C\# Backenda in React Frontenda. Služi kot krovni SSOT za Markdown specifikacije.  
> * **Shranjevanje celotnih surovih sej s povzetki v Git:** Vsaka seja se zaključi z generiranjem .md datoteke, ki vsebuje strukturirane metapodatke in povzetek na vrhu ter surov dnevnik (raw log) pogovora spodaj. To preprečuje *vendor lock-in* in omogoča prenosljivost na prihodnje RAG modele.  
> * **OpenClaw \+ Signal namesto pi.dev/Open WebUI za delo na daljavo:** Izloči potrebo po spletnih vtičnikih na VPS. Zagotavlja varen *Dark-Ops* pristop preko šifrirane Signal aplikacije.  
> * **Roslyn Parser za C\# kodo:** Uradni Microsoftov prevajalniški parser, ki rešuje tipe podatkov, reference in partial razrede.  
> * **Tree-sitter za React/TypeScript:** Sintaktični razrez frontend komponent na logične bloke.

## **Prilagojene ideje (Arhitekturni premiki)**

> * **Lokacija OpenClaw in pomožnih AI storitev:** Prvotno zamišljeni na VPS ali DGX Sparku, so premaknjeni na **domači srv**. S tem se razbremeni dragoceni KV Cache RAM na Sparku (ki gosti le vLLM), VPS pa ostane lahek in poceni.  
> * **Dvosmerna zanka Ansible Runnerjev:** Da bi se izognili zanki samoupravljanja (*self-management loop*), en sam OpenClaw (na domačem srv) upravlja dve ločeni Ansible okolji:  
  1. *Runner A (na srv):* Upravlja samo zunanji VPS.  
  2. *Runner B (na VPS):* Upravlja domači srv (s strogo prepovedjo, da bi srv spreminjal samega sebe).

## **Zavrnjene alternative (Z razlogi za zavrnitev)**

> * **Agent Memory (agent-memory.dev) kot centralna baza za znanost:** Zavrnjena za medicinski del, ker uporablja zaprto lokalno SQLite bazo in nima naprednih grafov znanja. **AM se uporabi izključno lokalno** znotraj urejevalnika (npr. Cursor) kot efemerni spomin za programerske projekte.  
> * **Docling za uvoz C\# in React kode:** Zavrnjen, ker kodo reže po številu žetonov ali odstavkih, kar uniči programersko logiko (reže sredi if/else zank). Docling je strogo omejen le na medicinske PDF-je.  
> * **10Gbps omrežna oprema (NIC & Switch) za vsakodnevno delo:** Zavrnjena kot trenutno ozko grlo. Tekstovni prompti (celo do 32k konteksta) in posamezni vektorji obsegajo le nekaj kilobajtov, kar 1Gbps prenesene v 1 milisekundi. Ozko grlo je čas GPU izračuna. Nadgradnja je smiselna le, če se gigabajtni modeli prenašajo večkrat dnevno.

## ---

**3\. PODROBEN TEHNIČNI NAČRT ZA IMPLEMENTACIJO**

## **A. Konfiguracija modelov na DGX Spark (vLLM / LiteLLM)**

Za maksimalno zmogljivost in izolacijo RAM-a na DGX Sparku zaženite izključno vLLM strežnik:

*`# Zagon generativnega programerskega modela`*  
`python3 -m vllm.entrypoints.openai.api_server \`  
    `--model Qwen/Qwen2.5-Coder-32B-Instruct \`  
    `--tensor-parallel-size 1 \`  
    `--max-model-len 32768 \`  
    `--port 8000`

*`# Zagon namenskega embedding modela za kodo in znanost`*  
`python3 -m vllm.entrypoints.openai.api_server \`  
    `--model BAAI/bge-code-v1 \`  
    `--port 8001`

## **B. Nastavitev dinamičnega konteksta v Open WebUI (Functions)**

Za ločevanje projektov (Workspacev) znotraj ene Mem0 instance, prekopirajte naslednjo Python kodo v *Workspace \> Functions*:

`import requests`

`class Filter:`  
    `def __init__(self):`  
        `self.mem0_url = "http://mcp-server-mem0:8000/v1/memories"`

    `def inlet(self, body: dict, __user__: dict = None) -> dict:`  
        `user_id = __user__.get("id", "default_user")`  
        `model_id = body.get("model", "default_model")`  
          
        `# Sestava unikatnega sestavljenega ID-ja za strogo ločitev projektov`  
        `custom_workspace_user_id = f"{user_id}-{model_id}"`  
          
        `# Pridobivanje spominov iz Mem0/Qdrant`  
        `response = requests.get(f"{self.mem0_url}?user_id={custom_workspace_user_id}")`  
        `if response.status_code == 200:`  
            `memories = response.json()`  
            `context = " ".join([m['text'] for m in memories])`  
            `# Vbrizgavanje spomina na začetek sistemskega prompta`  
            `body["messages"].insert(0, {`  
                `"role": "system",`  
                `"content": f"Relevantni pretekli kontekst tega projekta: {context}"`  
            `})`  
        `return body`

## **C. Krovna MCP Armada (mcp\_config.json na domačem srv)**

OpenClaw in Open WebUI koordinirata zunanje sisteme preko naslednje centralne konfiguracije v CONI 3:

`{`  
  `"mcpServers": {`  
    `"homeassistant": {`  
      `"command": "docker",`  
      `"args": ["exec", "-i", "mcp-server-homeassistant", "npx", "@modelcontextprotocol/server-homeassistant"],`  
      `"env": {`  
        `"HASS_URL": "http://10.0.100.5:8123",`  
        `"HASS_TOKEN": "EYJ0EXAI..."`  
      `}`  
    `},`  
    `"qdrant": {`  
      `"command": "docker",`  
      `"args": ["exec", "-i", "mcp-server-qdrant", "npx", "@modelcontextprotocol/server-qdrant"],`  
      `"env": {`  
        `"QDRANT_URL": "http://10.0.100.6:6333"`  
      `}`  
    `},`  
    `"forgejo": {`  
      `"command": "docker",`  
      `"args": ["exec", "-i", "mcp-server-forgejo", "npx", "@modelcontextprotocol/server-gitea"],`  
      `"env": {`  
        `"GITEA_URL": "https://tvojdomena.si",`  
        `"GITEA_TOKEN": "FORGEJO_SECRET_TOKEN"`  
      `}`  
    `}`  
  `}`  
`}`

## **D. Hibridni uvozni cevovod za kodo (Repomix \+ Izbrani Chunker)**

Kakovost podatkov v Qdrantu se doseže z naslednjim dvo-stopenjskim uvozom:

> 1. **Faza čiščenja in makro združevanja (Repomix):**  
>    Ustvarite repomix.config.json v C\# in React projektih, da odstranite šum:  
>    `{`  
>      `"output": { "filePath": "ai-code-blueprint.md", "style": "markdown" },`  
>      `"ignore": { "customPatterns": ["**/bin/**", "**/obj/**", "**/node_modules/**", "**/*.dll"] }`  
>    `}`

> 2. **Faza mikro AST rezanja (Roslyn / Tree-sitter):**  
>    Zaženite namenski skriptni vsebnik, ki prebere ai-code-blueprint.md in z uporabo **Roslyna** (za .cs) ter **Tree-sitterja** (za .tsx) razreže kodo natančno na mejah funkcij ter jo opremljeno z metapodatki razreda potisne v Qdrant zbirko csharp\_react\_code.

## ---

**4\. UPORABNIŠKI PROTOKOL DELOVANJA PREKO SIGNAL CHATOPS**

Celotno vodenje ekosistema se izvaja preko enega Signal klepeta z OpenClaw botom na naslednji način:

> 1. **Pisanje Specifikacije (Uporabnik):** V tretjem repozitoriju posodobite todo.md ali dodate tehnični načrt v domena-placila.md. Potisnete v Forgejo.  
> 2. **Sprožitev nalog (Preko Signala):**  
   * *Ukaz:* »@Claw, preberi posodobljeno specifikacijo za plačila v dokumentaciji in pripravi novo Git vejo v C\# projektu.«  
> 3. **Razmišljanje (Zaledje):** OpenClaw preko Qdrant MCP potegne obstoječo kodo, preveri pretekle odločitve v Mem0, DGX Spark (Qwen 32B) sestavi kodo, OpenClaw pa jo zapiše na disk v novi Git veji.  
> 4. **Križni Deployment (Ansible):**  
   * *Ukaz:* »@Claw, ko so testi uspešni, posodobi VPS.«  
   * *Izvedba:* OpenClaw preko **Ansible Runnerja A** (iz domačega srv) izvede varen deployment na javni VPS.

---

Vsi deli sistema so sedaj usklajeni v smiselno celoto. Za naslednji korak predlagam, da izberete eno specifično komponento (npr. **pripravo celotne Docker Compose datoteke za domači srv** ali **Roslyn parser skripto**), ki jo bom tehnično razpisal do nivoja pripravljene kode. Kje bi želeli začeti?