Tukaj je kratek povzetek najinega pogovora in načrt, kako lahko s pomočjo **n8n**, **OnlyOffice**, **Stirling-PDF** in **Docling** zgradiš popolnoma avtomatiziran sistem.

## **Kratek povzetek niti (Thread Summary)**

> * **Paperless-ngx** je tvoja digitalna omara za končne dokumente (računi, pogodbe), medtem ko je **Open WebUI \+ Qdrant \+ Docling** tvoj pametni AI sistem za klepet s podatki.  
> * **Nimaš potrebe po Gotenberg in Apache Tika** kontejnerjih. Ker že imaš zmogljiva orodja, bi to bila le potrata sistemskega pomnilnika (RAM-a).  
> * **n8n deluje kot pametni prometni policaj.** Namesto da bi Paperless-ngx sam pretvarjal datoteke s slabšim LibreOffice motorjem (Gotenberg), n8n prestreže datoteke in uporabi tvoje obstoječe sisteme (OnlyOffice, Stirling-PDF, Docling) za vrhunsko pretvorbo in branje besedila.

## ---

**Avtomatizirane poti za različne dokumente (Workflows)**

N8n bo upravljal tri ločene poti glede na to, od kod dokument pride in v kakšni obliki je. Vse poti se na koncu združijo v isti cilj: urejen arhiv v Paperless-ngx in pametni klepet v Open WebUI.

## **1\. Pot za Wordove dokumente (.docx / .xlsx)**

*Uporabljamo OnlyOffice za popolno ohranitev oblike (dizajna).*

`[ Prejeta .docx datoteka ]`  
           `│`  
           `▼`  
     `[   n8n   ]`  
           `│`  
           `├───► [ OnlyOffice API ] ───(Pretvori v popoln PDF)───┐`  
           `│                                                     ▼`  
           `├───► [ Docling API ] ──────(Izvleče strukturiran Markdown)`  
           `│                                                     │`  
           `▼                                                     ▼`  
  `[ Paperless-ngx ]                                         [ Qdrant / Open WebUI ]`  
`(Shrani urejen PDF)                                       (Takojšen klepet z vsebino)`

## **2\. Pot za skenirane dokumente ali slike (Telefon / Skener)**

*Uporabljamo Docling za pametno branje tabel/stolpcev in Stirling-PDF za sestavo končne datoteke.*

`[ Skenirana slika / Neberljiv PDF ]`  
           `│`  
           `▼`  
     `[   n8n   ]`  
           `│`  
           `├───► [ Docling API ] ──────(Prepozna strukturo in besedilo) ──┐`  
           `│                                                            │`  
           `├───► [ Stirling-PDF API ] ◄──(Združi sliko + besedilo v PDF/A)┘`  
           `│               │`  
           `▼               ▼`  
  `[ Paperless-ngx ]   [ Qdrant / Open WebUI ]`  
 `(Vrhunski iskalni      (Urejen Markdown za`  
     `rezultati)             AI analizo)`

## **3\. Pot za PDF priponke iz e-pošte (Mail Attachment)**

*Uporabljamo n8n za avtomatsko prenos in takojšnjo obdelavo brez ročnega dela.*

`[ Prejeta e-pošta s PDF računom ]`  
           `│`  
           `▼`  
     `[   n8n ] ───(IMAP / Gmail Trigger zazna in prenese priponko)`  
           `│`  
           `├───► [ Docling API ] ──────(Prebere tabelo računa v Markdown)`  
           `│                                                     │`  
           `▼                                                     ▼`  
  `[ Paperless-ngx ]                                         [ Qdrant / Open WebUI ]`  
`(Račun je arhiviran)                                      (AI ve, koliko si porabil)`

---

Ta celoten sistem ti omogoča, da preprosto "odvržeš" ali pošlješ dokument kamorkoli, tvoj domači strežnik pa v ozadju naredi vse težko delo brez podvajanja programov in trošenja odvečnega RAM-a.

Ali želiš, da začneva graditi **n8n pot za e-poštne priponke** ali te zanimajo specifični **API klici za Stirling-PDF / OnlyOffice** znotraj n8n?