---
title: Film, serije in glasba
role: reference
domain: manual
status: wip
tags: [manual, slovenian, media]
---
# Film, serije in glasba

> **Za vse.** Ogled filmov/serij (Jellyfin), zahtevanje novih vsebin (Seerr), poslušanje glasbe (Navidrome).

## Jellyfin — ogled filmov in serij

- Odpri `https://media.kogler.si` (doma na Wi-Fi, oddaljeno prek Tailscale).
- Prijava: **uporabniško ime in geslo Jellyfin** (vohunsko lokalno, ne Authentik).

## Seerr — zahtevanje novih filmov in serij

- Odpri `https://seerr.kogler.si`, prijavi se **z Jellyfin računom**.
- Poišči film/serijo in klikni **Request** — vsebina se naroči (poišče Prowlarr, prenese SABnzbd/qBittorrent) in pojavi v Jellyfin.

## Navidrome — glasba

- Odpri `https://music.kogler.si`. Prijava lokalna (ali SSO, kadar je na voljo).
- Aplikacije za telefon: katerikoli Subsonic odjemalec (npr. Symfonium, play:Sub).

## Oddaljen dostop (Tailscale)

- Ko ste zunaj doma: vklopite Tailscale → `media.`/`seerr.`/`music.` delujejo prek tunela.
- Če želite slovenski IP (npr. za RTV SLO): v Tailscale aplikaciji izberite **Pi kot izhodno vozlišče (exit node)** — samo ko ga potrebujete, potem izklopite.

## Navodila za napake

- **Nekaj se ne predvaja / ne najde:** preverite, ali je Jellyfin/Serr dosegljiv na `media.`/`seerr.`; znova zaženite odjemalec.
- **Prenos ni dokončan:** prenosi so hitri, vendar odvisni od interneta; počakajte in poskusite znova.
- Če vam karkoli ne deluje, pokličite Domna.