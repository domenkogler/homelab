---
title: Klepet (Matrix)
role: reference
domain: manual
status: wip
tags: [manual, chat, matrix]
---
# Klepet (Matrix)

> **Status:** 🚧 Še ni napisano — počaka na postavitev storitve (Phase 1). Jezik: slovenščina.
> Tehnično ozadje: [`services-matrix.md`](../services-matrix.md).

## Kako do klepeta

- Odpri **`https://chat.kogler.si`** v brskalniku (ali Element X na telefonu).
- Prijava: gumb **"Log in with SSO"** → prijava prek Authentik (geslo / 1Password passkey). Brez posebnega
  drugega uporabniškega imena — Matrix račun ustvariš ob prvi prijavi.

## Povezava z drugimi aplikacijami

- **WhatsApp / Messenger / Signal** so povezani prek mostov (bridges) — iz klepeta se pišeš z istimi
  stiki kot v teh aplikacijah, brez preklapljanja med aplikacijami.
- Če most ne deluje / zahteva ponovno povezavo: pokliči [tehnični kontakt](contacts.md).

## Pravila

- Nič ni shranjeno pri tujih ponudnikih; vse teče na domačem strežniku.
- Ne izklapljaj strežnika (glej [server-restart.md](server-restart.md)), sicer klepet ne bo dosegljiv.
