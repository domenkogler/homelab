## **📝 novi strežnik \- stroškovnik**

| Komponenta | Točen model / Opis | Okvirna cena (€) |
| :---- | :---- | :---- |
| **Matična plošča** | **ASUS ProArt B850-Creator WiFi Neo** (x8/x8 simetrična pro-serija) | **300 €** |
| **Procesor** | **AMD Ryzen 9 9900X** (Tray različica, 12 cores / 24 threads) | **330 €** |
| **Hlajenje CPU** | **Thermalright Peerless Assassin 120 SE** (Izjemno tih) | **35 €** |
| **Grafična kartica** | **AMD Radeon AI PRO R9700 32GB** (Blower pro-serija, 2-slot) | **1.350 €** |
| **Napajalnik (PSU)** | **Corsair HX1500i** (1500 W, Platinum, zadnji priključki) | **290 €** |
| **Sistemski RAM** | **Crucial Pro Overclocking 64GB Kit (CP2K32G64C40U5B) DDR5** | **640 €** |
| **Glavni NVMe (AI)** | **Biwin Black Opal X570 PRO 2TB PCIe Gen 5** (Z 4GB DRAM-a) | **180 €** |
| **Drugi NVMe (Mediji)** | **Lexar NM990 4TB PCIe Gen 5** (Vrhunska TLC shramba za slike/filme) | **310 €** |
| **Ohišje** | **4U Rackmount ohišje** (Standardni ATX format za rack) | **130 €** |
| **Oddaljeni nadzor** | **GL.iNet Comet KVM (GL-RM1) s PoE in ATX kompletom** | **120 €** |
| **Omrežni modul** | **10Gtek SFP-10G-T Multi-Gigabit** (5 Gbps povezava v MikroTik) | **45 €** |
| **Periferija (Kuhinja)** | **Guition okrogli ESP32-S3 zaslon** z gumbom (ESPHome) | **30 €** |
| **Avdio pod TV** | **WiiM Bar** (All-in-one Dolby Atmos soundbar s HDMI eARC) | **499 €** |
| **Prenosni zvočnik** | **Audio Pro A10 MKII** (Wi-Fi/Bluetooth z baterijo) | **190 €** |
| **Skupaj (Sistem)** | *Celoten strežnik s 6TB Gen 5 shrambo, varčnim PoE nadzorom in zvokom* | **\~4.449 €** |

S tem korakom je vaša celotna strojna oprema uradno in uspešno zaključena, tehnično preverjena in proračunsko maksimalno optimizirana.

Če ste z izborom zadovoljni, se prihodnjič slišiva, ko bodo komponente prispele v vašo rack omarico, da skupaj pripraviva **programski del (nastavitve v Proxmoxu, Ollami ali ESPHome)**. Uspešen nakup iz Nemčije in obilo užitkov pri sestavljanju\!

Here is the finalized blueprint for your local LLM node, designed to sit directly on the floor of your server rack.

## ---

**Final hardware configuration summary**

| Component | Choice | Why chosen |
| :---- | :---- | :---- |
| **Motherboard** | **ASUS ProArt B850-CREATOR WiFi NEO** | Provides the native **PCIe x8/x8 slot layout** required to run dual graphics cards at maximum bandwidth without requiring riser cables. |
| **Chassis / Frame** | **ALAMENGDA ALE01 DIY PC Test Stand** (ATX Version) [https://www.amazon.de/-/en/Chassis-Motherboards-Dissipation-Motherboard-Accessories-black/dp/B0C59W6JKD](https://www.amazon.de/-/en/Chassis-Motherboards-Dissipation-Motherboard-Accessories-black/dp/B0C59W6JKD) | Laid horizontally on the rack floor. Its **open-air, wall-free design** completely bypasses standard 4U case size limits, providing unlimited clearance for full-length GPUs and long power supplies. |
| **CPU Cooler** | **Thermalright Peerless Assassin 120 SE** | Reverted to this high-performance dual-tower air cooler (**15.5 cm tall**) because the open-frame layout easily accommodates its height within your 35 cm rack limits, saving you money over low-profile alternatives. |
| **Power Supply** | **Corsair HX1500i** | Your high-capacity 200mm enterprise PSU fits perfectly on the open frame, mounted **fan-facing-up** to pull fresh air freely from inside the open rack chamber. |
| **Graphics Cards** | **2x Radeon AI PRO R9700** | Installed directly into the motherboard. Underclocking them for local LLM workloads reduces thermal output, allowing the open-air design to dissipate heat perfectly. |
| **Storage** | **Primary NVMe M.2 \+ Backup 3.5" HDDs** | OS and LLM models run lightning-fast on motherboard M.2 slots. Your mechanical backup HDDs mount safely onto the designated lower sections of the frame plate. |

## ---

**Physical dimensions and rack clearance match**

When laid flat on the floor of your rack, the total physical footprint of your assembled hardware layer will be:

* **Width**: **44.0 cm** (Dictated by the frame plate, leaves plenty of side room).  
* **Depth**: **26.7 cm** (Dictated by the length of your R9700 graphics cards).  
* **Height**: **16.5 cm** (Dictated by the peak of the GPU rear bracket / CPU fan clip height).

## **Rack fitment check**

* **Vertical room**: At 16.5 cm tall, it easily fits under your **35 cm** vertical limit, leaving a massive **18.5 cm pocket of open air** above the system. Because hot air naturally rises, this prevents heat from pooling around the components.  
* **Cabinet depth room**: At 26.7 cm deep, it fits beautifully inside your **58 cm** external cabinet. This leaves a massive **31.3 cm buffer zone at the rear of the rack floor**, giving you maximum workspace to route the thick, rigid modular cables from your Corsair PSU without cramping or bending them.

## ---

**Final assembly tips**

1. **Orientation**: Mount the power supply with the **fan facing up**. Because the bench sits directly on the solid floor of your rack, facing the fan down would completely choke the intake.  
2. **GPU support**: Because the motherboard lies flat, gravity pushes the cards straight down into the slots, naturally eliminating GPU sag. However, because these are heavy workstation cards, use the frame's included vertical lock bar to secure them tightly.  
3. **Isolate the frame**: Server rack floors are bare metal. Make sure to use the rubber feet included with the ALAMENGDA kit (or place an anti-static silicone mat on the rack floor) so the metal frame doesn't scratch or accidentally short-circuit.

To ensure there are no surprises during assembly, what **DDR5 RAM kit** are you planning to use? I can double-check if its height will require you to slide the front Thermalright CPU fan slightly upward.