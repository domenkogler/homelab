# Vzpostavitev Debian v Hyper-V okolju


**1. Korak: Vklop Hyper-V v Windows 10**

1. V iskanje v Windows 10 vtipkajte **"Turn Windows features on or off"** (Vklop ali izklop funkcij sistema Windows).
2. Na seznamu poiščite **Hyper-V**, obkljukajte celotno mapo (Hyper-V Management Tools in Hyper-V Platform) in kliknite OK.
3. Windows vas bo pozval k ponovnemu zagonu računalnika.

**2. Korak: Ustvarjanje mrežnega mostu (External Switch)**
To je ključni korak, ki reši vaš problem z IP naslovi:
1. Po ponovnem zagonu odprite Hyper-V Manager.
2. Na desni strani kliknite Virtual Switch Manager (Upravitelj virtualnih stikal).
3. Izberite **External** (Zunanje) in kliknite **Create Virtual Switch**.
4. Poimenujte ga DomaciBridge.
5. Pod _Connection type_ izberite vašo dejansko mrežno kartico (Ethernet ali Wi-Fi), s katero je PC povezan v mrežo 10.10.1.x.
6. Obkljukajte _"Allow management operating system to share this network adapter"_ (da Windowsi ne izgubijo interneta) in kliknite Apply.

**3. Korak: Ustvarjanje Debian Virtualnega Stroja**
1. Prenesite majhno namestitveno sliko __Debian Netinst ISO__ na vaš PC.
2. V Hyper-V Managerju kliknite **New -> Virtual Machine.**
3. V čarovniku nastavite:
  - Generation: Generation 2 (sodobnejša izbira).
  - Memory: Npr. 8192 MB (8 GB je več kot dovolj za vaš celoten stack, Windowsom pa še vedno ostane vrhunskih 40 GB za igre).
  - Networking: Izberite vaš novoustvarjeni DomaciBridge.
  - Installation Options: Izberite preneseno Debian ISO datoteko.

**4. Pomembno za __Generation 2:__**
Pred zagonom pojdite v Settings (Nastavitve):
1. pod **Security** odkljukajte **Enable Secure Boot** (sicer Debian ISO ne bo hotel štartati), in izberite **Microsoft UEFI Certificate Authority**.

Zakaj je to pomembno: Če pustite predlogo Microsoft Windows, bo Hyper-V    pričakoval digitalne podpise s strani Microsofta. Debian se zaradi tega sploh ne bo mogel zagnati in bo javil napako glede varnostnega zagona. Predloga Microsoft UEFI Certificate Authority pa vsebuje certifikate, ki jih Linux distribucije uporabljajo za varen zagon.

 2. Nastavitev "Enable Trusted Platform Module" (TPM): Pustite **odkljukano (izklopljeno)**.

Zakaj: TPM (Trusted Platform Module) je nujen za sisteme, kot je Windows 11 (zaradi BitLocker šifriranja in varnostnih zahtev OS). Za standardni Linux strežnik, kjer boste poganjali Docker in Ansible, vklop navideznega TPM-ja ne prinaša nobenih prednosti, lahko pa povzroči nepotrebne zaplete pri kasnejšem prenosu/migraciji celotnega VM-ja na drug računalnik ali Proxmox.

**5. Korak: Namestitev Debiana**

Zaženite VM in sledite namestitvi.
1. hostname: deblab.kogler.si
2. domen account
3. disk: entire & lvm & all files in one partitionm
4. le **SSH Server** in **Standard system utilities.**