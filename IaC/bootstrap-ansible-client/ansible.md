# Namestitev in priprava Debian distribucije v WSL2

Če še nimate nameščenega Debiana v WSL2, odprite Windows Terminal (PowerShell) kot administrator in zaženite naslednje ukaze:

## Powershell

`# Namestitev Debian distribucije`
`wsl --install -d Debian`

`# Preverite, da teče na različici WSL 2`
`wsl --list --verbose`

Če izpisuje različico 1, jo pretvorite z:

`wsl --set-version Debian 2`.

Nato sledite navodilom na zaslonu, da ustvarite svojega Linux uporabnika (npr. admin) in geslo.

Uporabniško ime in geslo shrani v 1password valut: Homelab

# Priprava okolja za upravljanje

Bootstrap.sh zaženeš znotraj wsl2 Debian:
`bash bootstrap.sh`