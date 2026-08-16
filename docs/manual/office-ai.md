---
title: AI pomočnik in Office (Word / Excel / PowerPoint)
role: reference
domain: manual
status: wip
tags: [manual, office, ai, openwebui]
---
# AI pomočnik in Office (Word / Excel / PowerPoint)

> **Status:** 🚧 Še ni napisano v celoti — deluje, ko je most (bridge) nameščen na računalniku.
> **Za koga:** Družinski člani, ki na svojem računalniku (Windows 11) uporabljajo Office.

---

## Kaj to je

AI pomočnik (Open WebUI) ti lahko **neposredno pomaga urejati** odprt Word,
Excel ali PowerPoint dokument — prav tistega, ki ga imaš na zaslonu. Napišeš
zahtevo, npr. *"dodaj stran s pregledom na 3. slide"*, AI pa to naredi v živo
v tvojem dokumentu.

Most (povezava med Open WebUI in Officeom) se imenuje **Office Bridge** in
teče na tvojem računalniku.

---

## Kako uporabljati (kratek vodič)

1. **Odpri dokument, ki ga želiš urejati** — Word, Excel ali PowerPoint.
   Most dela na *odprtem* dokumentu na tvojem zaslonu.
2. **Odpri Open WebUI** v brskalniku → `https://ai.kogler.si`
   (ali prek začetne strani `kogler.si`).
3. **Prijavi se.** Prijava teče prek enega skupnega računa (Authentik).
4. **Napiši zahtevo**, kaj naj AI naredi, npr.:
   - *"Prepiši naslov na 1. slideu v 'Letni pregled'."*
   - *"Dodaj tabelo z 3 stolpci na Excel listu Pregled."*
   - *"Označi prvi odstavek v Word dokumentu krepko."*
5. **Pojdi nazaj na Office** in preveri — sprememba se prikaže tam.

> 💡 Če sprememb ne vidiš takoj: preveri, da je most **zagnan** (poglej spodaj)
> in da je dokument **odprt** na tvojem računalniku. AI ne more urejati
> dokumenta, ki ni odprt.

---

## Zagon Office Bridge (če ne teče)

Most mora teči v ozadju. Če je bila nameščena ikona **OfficeMcp** v opravilni
vrstici, jo samo klikni, da zaženeš most.

Če ikone ni (napredno / tehnični uporabnik):

1. Odpri **Terminal** (ukazni poziv) kot lastnik računalnika.
2. Zaženi:
   ```
   cd %ProgramFiles%\OfficeMcp
   .\.venv\Scripts\python.exe bridge.py
   ```
3. Pusti okno odprto, medtem ko uporabljaš AI z Officeom.

> ⚠️ **Excel posebej:** za Excel najprej **zapri odprte delovne zvezke**, da
> lahko AI prevzame urejanje (tako zahteva orodje za Excel).

---

## Katere programe podpira

| Program | Podprto |
|---------|---------|
| **PowerPoint** | ✅ Da — predstavitve, slidei, oblike, tabele, grafi |
| **Word** | ✅ Da — besedilo, slogi, tabele, naslovi |
| **Excel** | ✅ Da — tabele, formule, oblikovanje |
| **ONLYOFFICE (Linux)** | Delno — večinoma druge (strežniške) funkcije, brez neposrednega urejanja |

---

## Česa NE dela / nasveti

- **Ne shranjujte vsebine v pogovor z AI** — dokument se shrani na disk, ne v klepet.
- **Most deluje samo, ko je računalnik prižgan** in seznam dokumentov odprt.
- Če se zdi, da AI "ne vidi" tvojega dokumenta, **zapri in znova odpri** dokument
  ali znova zaženi most.
- Za občutljive stvari (računi, osebni podatki) bodi previden, kaj prepisuješ —
  tako kot pri vsakem spletnem pomočniku.

---

## Če ne deluje

1. Preveri, da je most zagnan (zgoraj).
2. Preveri, da si prijavljen v Open WebUI.
3. Poskusi znova odpreti dokument.
4. Če še vedno ne deluje → kontaktiraj **Domna** (tehnična oseba).

(še bo napisano)