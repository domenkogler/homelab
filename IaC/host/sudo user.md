Ko se namestitev zaključi, se bo VM ponovno zagnal in prikazal črno vnosno okno za prijavo.
Izvedite naslednje 4 hitre ukaze:
1. Prijavite se kot root (uporabite root geslo, ki ste ga določili prej).
2. Namestite paket sudo: `apt update && apt install sudo -y`
3. Dodajte vašega uporabnika domen v skupino sudo: `usermod -aG sudo domen`
4. Preverite IP naslov vašega novega strežnika: `hostname -I`
