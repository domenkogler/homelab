Deluješ kot strokovnjak za pametni dom, Home Assistant, TileBoard (JavaScript/TypeScript konfiguracija) in Grafana nadzorne plošče. 

Moja ciljna postavitev pametnega doma vključuje:
1. TILEBOARD: Za hiter nadzor na tablici/PC-ju (upravljanje KNX luči, KNX žaluzij, Shelly RGBW trakov in Nvidia Shield/TV medijev).
2. GRAFANA: Za analitične grafe in vizualizacijo (podatki iz vremenske postaje, temperature in pretoki rekuperatorja ter mrežni podatki iz Mikrotika).

Spodaj ti prilagam seznam svojih entitet iz Home Assistanta. 

[TUKAJ PRIPEPNAJ/VPIŠI SVOJ SEZNAM ENTITET IZ HOME ASSISTANTA]

Tvoja naloga je, da mi na podlagi teh entitet pripraviš:

1. ARHITEKTURO TILEBOARD-A: 
- Predlagaj smiselno razdelitev na zavihke (strani/pages) v TileBoardu.
- Za vsako entiteto določi najboljši tip ploščice (npr. TYPES.LIGHT, TYPES.COVER, TYPES.MEDIA_PLAYER, TYPES.WEATHER, TYPES.SENSOR).

2. CONFIG.JS KODO ZA TILEBOARD:
- Pripravi strukturiran izsek kode za datoteko `config.js` za eno ključno stran (npr. Dnevna soba ali Glavni zaslon), kjer bodo pravilno konfigurirane moje KNX luči, žaluzije in Shelly RGBW trakovi z drsniki.

3. STRATEGIJO ZA GRAFANO:
- Za senzorske podatke (vreme, rekuperacija, Mikrotik) predlagaj, katere vrste grafov (npr. Time Series, Gauge, Stat, Bar Gauge) naj uporabim v Grafani za najboljšo preglednost.
- Pojasni, kako te Grafana grafe kot Iframe vgraditi nazaj v TileBoard (preko TYPES.IFRAME ploščice).

Prosim, bodi natančen pri uporabi dejanskih imen entitet, ki sem jih priložil. Koda naj bo čista in pripravljena za kopiranje.


💡 Predlogi za izboljšavo in prilagoditev tega prompta
Preden prompt pošljete, ga lahko še dodatno izboljšate z vnosom svojih specifičnih želja. Tukaj so ključne točke, ki jih je smiselno dodati:
1. Definirajte velikost zaslona (Resolucijo)
TileBoard temelji na fiksni mreži (Grid). Če AI-ju poveste, kje se bo dashboard prikazoval, bo koda natančnejša.
Izboljšava prompta: "Dashboard se bo prikazoval na tablici [vpišite model, npr. iPad 10.2 ali Samsung Galaxy Tab S8] v vodoravnem (landscape) načinu. Prilagodi velikost ploščice (tileSize) in število stolpcev."
2. Določite specifike za Shelly RGBW
Shelly RGBW trakovi imajo lahko v HA ločene entitete za svetlost in barvo, ali pa je vse združeno pod eno light. entiteto z atributi.
Izboljšava prompta: "Za Shelly RGBW trakove želim, da ploščica v TileBoardu omogoča ne le vklop/izklop, ampak tudi odpiranje barvnega kroga (color picker) za spreminjanje barv."
3. Prilagodite osveževanje za Mikrotik in Vreme (Grafana)
Grafana privzeto vleče podatke iz baze (InfluxDB). Pomembno je določiti, kako "v živo" želite videti te podatke.
Izboljšava prompta: "Za Mikrotik mrežni promet želim v Grafani graf, ki prikazuje zadnjih 24 ur s sekundnim osveževanjem. Za vremensko postajo pa naj graf prikazuje trend gibanja temperatur v zadnjih 7 dneh."
4. Izberite stil/temo (Theme)
TileBoard ponuja več vgrajenih stilov (npr. classic, transparent, flat).
Izboljšava prompta: "Želim moderen, minimalističen izgled z neprosojnimi temnimi ploščicami in belim besedilom (dark mode)."
Ko boste imeli pripravljen seznam entitet, preprosto vstavite podatke v zgornji prompt in pripravljen bom, da vam zgeneriram celotno strukturo in kodo za vaš novi sistem!
Ali želite, da vam že zdaj pripravim osnovno strukturo config.js datoteke za TileBoard, da boste videli, kako sploh izgleda sintaksa?
