# Kako pravilno pripraviti Debian na vašem PC-ju za delo z Ansiblom?

1. Na PC-ju odprite **PowerShell kot administrator** in zaženite namestitev:

`wsl --install -d Debian`

Preverite, da teče na različici WSL 2

`wsl --list --verbose`

Če izpisuje različico 1, jo pretvorite z:

`wsl --set-version Debian 2.`

Nato sledite navodilom na zaslonu, da ustvarite svojega Linux uporabnika (npr. admin) in geslo.

Uporabniško ime in geslo shrani v 1password valut: Homelab-ansible

2. Ko se namestitev zaključi in ustvarite uporabnika, morate v Debianu na PC-ju **omogočiti systemd** (ki ga Docker in SSH nujno potrebujeta za delovanje v ozadju znotraj WSL2).V Debian terminalu na PC-ju ustvarite konfiguracijsko datoteko:

`sudo nano /etc/wsl.conf`

Vanjo prilepite naslednji dve vrstici:

`[boot]`
`systemd=true`

Shranite (Ctrl+O, Enter, Ctrl+X).

3. V Windows PowerShellu na PC-ju nato popolnoma ponovno zaženite WSL, da nastavitve stopijo v veljavo:

`wsl --shutdown`

4. Ponovno odprite Debian na PC-ju in namestite SSH strežnik, da se bo vaš prenosnik lahko povezal:

`sudo apt update && sudo apt install openssh-server -y`
`sudo systemctl enable --now ssh`

5. Preverite hostname:

`hostname -I`

6. V primeru da ip ni iz localnega omrežja:

kopiraj `.wslconfig` v `%USERPROFILE%`.
Ugasni SWL: `wsl --shutdown`
Ponovno odpri Debian v WSL2: `wsl -d Debian`

S tem je vaš PC (Debian Host) uradno pripravljen, da postane ciljna destinacija za vaš celoten IaaC projekt.