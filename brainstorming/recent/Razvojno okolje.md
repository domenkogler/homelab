Tukaj je celovit, strukturiran in natančen tehnični povzetek celotne seje. Vsebuje vse raziskane ideje (tudi izključene) ter natančna navodila za končno implementacijo na vašem prenosniku Lenovo P14s z operacijskim sistemom Windows 11 Pro, ob zagotavljanju popolne prenosljivosti za celotno ekipo (Windows, Mac, Linux / Rider, VS Code, VS Community).

## ---

**📑 TEHNIČNI POVZETEK RAZVOJNE ARHITEKTURE**

## **1\. Pregled raziskanih in izključenih idej**

Med sejo smo analizirali več pristopov in izločili tiste, ki bi rušili prenosljivost kode ali varnost lokalnega omrežja:

> * **❌ Izključeno: Nativno upravljanje VLAN znotraj Windows 11 Pro**  
  * *Razlog:* Windows 11 desktop različice ne omogočajo nativne razdelitve ene fizične mrežne kartice na več virtualnih (tagged/untagged) vmesnikov preko standardnih grafičnih menijev.  
> * **❌ Izključeno: Docker Desktop za Windows**  
  * *Razlog:* Docker Desktop ustvari lastno izolirano okolje, ki bi se zaradi kompleksnih omrežnih nastavitev (VLAN) zapletlo v konflikte z WSL bridged stikalom. Prav tako otežuje delo s Podmanom.  
> * **❌ Izključeno: Nameščanje Podmana/Dockerja neposredno v Debian VLAN instanco**  
  * *Razlog:* Mešanje razvojnih kontejnerjev in specifičnih omrežnih VLAN nastavitev znotraj iste Linux distribucije bi ogrozilo izolacijo in varnost omrežij.  
> * **❌ Izključeno: Shranjevanje .mdf ali .bak datotek SQL baz v Git**  
  * *Razlog:* Binarne datoteke so prevelike in upočasnjujejo Git. Namesto tega uporabljamo kodne migracije in skripte.  
> * **❌ Izključeno: Skupni (centralni) razvojni SQL strežnik**  
  * *Razlog:* Razvijalci bi si medsebojno prebrisali testne podatke in bili odvisni od stalne omrežne povezave.  
> * **❌ Izključeno: Uporaba Testcontainers znotraj .NET Aspire ekosistema**  
  * *Razlog:* Orodji uporabljata povsem različne pogone (DCP vs Testcontainers API) in ne moreta neposredno brati nastavitev drug od drugega.  
> * **✔️ Izbrana končna sinteza:** Uporaba Hyper-V virtualnega stikala, ločene Debian instance za VLAN, ročno ustvarjene Ubuntu instance s Podmanom za razvoj, Portainerja za vizualizacijo ter .NET Aspire \+ Respawn \+ .http datotek za prenosljivo in deterministično testiranje v vseh operacijskih sistemih in IDE-jih.

## ---

**2\. Arhitektura sistema kot smiselna celota**

Sistem deluje kot triplastni izolirani model na enem računalniku:

> 1. **Windows 11 Pro (Gostitelj):** Poganja IDE orodja (Rider, VS Code, VS), komunicira z ne-označenim (untagged) omrežjem za internet in preko WSL upravlja z obema Linux distribucijama.  
> 2. **WSL Debian (Omrežna plast):** Ekskluzivno povezan na Hyper-V stikalo. Prejema tagged VLAN promet in ima edini dostop do tega zaščitenega omrežja. Windows aplikacije ga ne vidijo.  
> 3. **WSL Ubuntu (Razvojna plast):** Nastavljen kot privzeta WSL instanca. Poganja Podman in Portainer preko standardnega interneta. Služi kot univerzalna "baza" za Devcontainers in .NET Aspire, ki jo vidijo vsi vaši IDE-ji.

## ---

**3\. Natančna navodila za korak-po-korak implementacijo**

## **Korak 1: Omrežna izolacija (VLAN na Debianu)**

> 1. V Windowsih vklopite **Hyper-V** (*Turn Windows features on or off* \-\> označite Hyper-V \-\> Restart).  
> 2. Odprite **PowerShell (Admin)** in poiščite ime svoje žične kartice:  
>    `Get-NetAdapter`  
>    *(Predpostavimo, da je ime v stolpcu Name Ethernet).*  
> 3. Ustvarite virtualno stikalo (Virtual Switch), ki bo prevzelo untagged promet za Windows:  
>    `New-VMSwitch -Name "VLAN-Switch" -NetAdapterName "Ethernet" -AllowManagementOS $true`

> 4. Nastavite prenosni način (Bridged) za WSL. V vaši Windows mapi %USERPROFILE% ustvarite ali uredite datoteko .wslconfig:  
>    `[wsl2]`  
>    `networkingMode=bridged`  
>    `vmSwitch=VLAN-Switch`

> 5. Ponovno zaženite WSL s stikalom v PowerShellu: wsl \--shutdown.  
> 6. Odprite **WSL Debian** terminal, preverite ime vmesnika (ip link, predpostavimo eth0) in ročno aktivirajte VLAN vmesnik (npr. za **VLAN ID 10**):  
>    `sudo ip link add link eth0 name eth0.10 type vlan id 10`  
>    `sudo ip link set dev eth0.10 up`  
>    `sudo dhclient eth0.10`  
>    *(Windows 11 ne vidi tega vmesnika, Debian pa ima sedaj IP naslov iz VLAN omrežja).*

## **Korak 2: Priprava razvojne baze (Ubuntu \+ Podman \+ Portainer)**

> 1. V Windows PowerShell namestite namensko Ubuntu distribucijo in jo nastavite kot privzeto za razvojna orodja:  
>    `wsl --install -d Ubuntu`  
>    `wsl --set-default Ubuntu`

> 2. Odprite **Ubuntu** terminal in namestite ter zaženite **Podman**:  
>    `sudo apt update && sudo apt install -y podman`

> 3. Ustvarite povezavo med Windowsom in Podmanom. Pridobite svoj Linux UID z ukazom id \-u (običajno je 1000). Nato zaženite Podman API servis, ki bo hkrati poslušal na lokalnem Linux Unix socketu (za Rider/VS Code) in TCP portu (za Windows Docker CLI):  
>    `podman system service --time=0 unix:///run/user/1000/podman/podman.sock tcp://localhost:12345 &`

> 4. Namestite **Portainer** znotraj Ubuntuja za vizualni pregled kontejnerjev:  
>    `podman run -d -p 9000:9000 --name portainer --restart=always -v /run/user/1000/podman/podman.sock:/var/run/docker.sock:Z portainer/portainer-ce:latest`  
>    *Nadzorna plošča je sedaj v Windows brskalniku dostopna na http://localhost:9000.*

## **Korak 3: Nastavitev IDE orodij na Windows 11**

> * **JetBrains Rider:**  
  * *Settings \-\> Build, Execution, Deployment \-\> Docker*.  
  * Kliknite \+, izberite možnost **WSL**.  
  * V spustnem meniju izberite vašo **Ubuntu** distribucijo. Pot za Docker Compose usmerite na /usr/bin/podman.  
> * **VS Code (Devcontainers):**  
  * Namestite razširitev *Dev Containers*.  
  * V nastavitvah VS Code (settings.json) nastavite pot do Podmana: "dev.containers.dockerPath": "podman".  
> * **Visual Studio Community / Windows CLI:**  
  * Namestite Docker CLI preko Windows terminala: winget install Docker.DockerCLI.  
  * V Windows okoljske spremenljivke (Environment Variables) dodajte: DOCKER\_HOST=tcp://localhost:12345.  
  * V Visual Studiu pod *Tools \-\> Options \-\> Container Tools* nastavite Container Runtime na **Podman**.

## ---

**4\. Prenosljiva koda za projekt (Deljenje preko Gita)**

Te datoteke postavite neposredno v projekt. Delovale bodo "out of the box" pri vseh razvijalcih na vseh operacijskih sistemih.

## **A. Konfiguracija okolja (.devcontainer/devcontainer.json)**

`{`  
  `"name": "Skupni .NET Razvojni Kontejner",`  
  `"build": {`  
    `"dockerfile": "Dockerfile"`  
  `},`  
  `"customizations": {`  
    `"vscode": {`  
      `"extensions": [`  
        `"ms-dotnettools.csdevkit",`  
        `"humao.rest-client"`  
      `]`  
    `},`  
    `"jetbrains": {`  
      `"plugins": [`  
        `"com.microsoft.toolkits.internal.rider"`  
      `]`  
    `}`  
  `},`  
  `"remoteUser": "vscode"`  
`}`

## **B. Kontejnersko okolje (.devcontainer/Dockerfile)**

`FROM ://microsoft.com`  
*`# Izbira baznega SDK okolja, ki je enako za vse razvijalce`*

## **C. Lokalna nastavitev za .NET Aspire in Podman (Samo na vaši napravi)**

Da .NET Aspire na vašem računalniku ve, da mora uporabiti Podman (medtem ko ekipa uporablja Docker), dodajte v svojo Ubuntu \~/.bashrc datoteko naslednjo vrstico:

`export DOTNET_ASPIRE_CONTAINER_RUNTIME=podman`

## **D. Deterministični integracijski testi (xUnit \+ Aspire \+ Respawn)**

Ta koda omogoča, da Aspire enkratno zažene bazo iz AppHost konfiguracije, **Respawn** pa pred vsakim testom bliskovito očisti podatke, kar zagotavlja 100-odstotno ponovljivost brez podvajanja nastavitev:

`public class IntegracijskiTestiBaze : IAsyncLifetime`  
`{`  
    `private DistributedApplication _app;`  
    `private string _connectionString;`  
    `private Respawner _respawner;`

    `public async Task InitializeAsync()`  
    `{`  
        `// Aspire samodejno dvigne SQL Server iz AppHost konfiguracije`  
        `var appHost = await DistributedApplicationTestingBuilder.CreateAsync<Projects.MyApp_AppHost>();`  
        `_app = await appHost.BuildAsync();`  
        `await _app.StartAsync();`

        `_connectionString = await _app.GetConnectionStringAsync("sql");`

        `// EF Core izvede migracije nad svežim kontejnerjem`  
        `using var context = new MojDbContext(new DbContextOptionsBuilder<MojDbContext>().UseSqlServer(_connectionString).Options);`  
        `await context.Database.MigrateAsync();`

        `// Inicializacija orodja Respawn za čiščenje podatkov`  
        `_respawner = await Respawner.CreateAsync(_connectionString, new RespawnerOptions { DbAdapter = DbAdapter.SqlServer });`  
    `}`

    `[Fact]`  
    `public async Task Test_Uporabnik_Obstaja_Po_Vnosu()`  
    `{`  
        `// Pred vsakim testom Respawn pobriše podatke v nekaj milisekundah`  
        `await _respawner.ResetAsync(_connectionString);`

        `var client = _app.CreateHttpClient("api");`  
        `var response = await client.PostAsJsonAsync("/api/uporabniki", new { Ime = "Test" });`  
          
        `Assert.Equal(HttpStatusCode.Created, response.StatusCode);`  
    `}`

    `public async Task DisposeAsync()`  
    `{`  
        `await _app.DisposeAsync(); // Popolno čiščenje kontejnerja po koncu serije testov`  
    `}`  
`}`

## **E. Ročno testiranje API-jev (api-testi.http v Gitu)**

Tekstovna datoteka za proženje zahtev neposredno iz IDE-ja. V **Riderju** ob zagonu Aspire-a izberete okolje aspire \[wsl.dev\]. V **VS Code** dodate datoteko http-client.env.json z definicijo naslova {{base\_url}}.

V vaš Program.cs dodajte razvojno točko za ponastavitev baze preko HTTP zahtev:

`if (app.Environment.IsDevelopment())`  
`{`  
    `app.MapPost("/api/test/reset-db", async (IConfiguration config) =>`  
    `{`  
        `var connectionString = config.GetConnectionString("sql");`  
        `var respawner = await Respawner.CreateAsync(connectionString);`  
        `await respawner.ResetAsync(connectionString);`  
        `return Results.Ok(new { status = "Baza je očiščena!" });`  
    `});`  
`}`

Tako izgleda vaša prenosljiva .http datoteka:

`### 1. Ponastavi bazo na začetno stanje (Zagotavljanje determinističnosti)`  
`POST {{base_url}}/api/test/reset-db`

`### 2. Izvedba dejanskega testa (FE del lahko poganjate z Aspire, BE pa klasično na F5)`  
`POST {{base_url}}/api/uporabniki`  
`Content-Type: application/json`

`{`  
  `"ime": "Razvijalec X"`  
`}`

S to specifikacijo imate celotno razvojno in testno okolje popolnoma dokumentirano ter pripravljeno za neposredno implementacijo.

---

Za uspešen začetek dela predlagam naslednji korak: **najprej izvedite ukaze iz Koraka 1**, da preverite, ali vaša mrežna kartica Lenovo pravilno sprejema VLAN pakete znotraj Debiana. Sporočite, ko boste pripravljeni na naslednjo fazo\!