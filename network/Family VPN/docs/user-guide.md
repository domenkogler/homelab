# Travel Wi‑Fi – How to Get Online 🌍

> **You only need to do this once per hotel.**  
> After that, you’re online just like at home.

---

## What You Need

- A phone, tablet, or laptop.
- The hotel’s Wi‑Fi name and password (usually on a card at reception or in your room).
- The travel router (the small white MikroTik box) — it should be plugged in and powered on.

---

## Step 1: Connect to the Travel Wi‑Fi

1. Open your device’s Wi‑Fi settings.
2. Look for the network named **Family-Traveling**.
3. Tap it and enter the password:
   ```
   <YOUR_WIFI_PASSPHRASE>
   ```
4. Tap **Connect**.

> **Don’t worry** if your phone says “No Internet” — that’s normal until we set up the hotel connection.

---

## Step 2: Open the Setup Page

1. Open your browser (Chrome, Safari, Firefox, whatever you use).
2. In the address bar, type:
   ```
   potovalni.vpn
   ```
   …and press **Go** / **Enter**.
3. You should see a purple page with a hotel icon 🏨 and the title **“Hotel Wi‑Fi Setup”**.

> **If you don’t see the page:**  
> Make sure you’re connected to `Family-Traveling` (Step 1).  
> Try typing `http://potovalni.vpn` (with `http://` in front).

---

## Step 3: Enter the Hotel Wi‑Fi Details

There are two boxes on the page:

| Box | What to type |
|-----|-------------|
| **Hotel Wi‑Fi name (SSID)** | The exact name of the hotel’s Wi‑Fi network. Watch out for capital letters and spaces! |
| **Hotel Wi‑Fi password** | The hotel’s Wi‑Fi password. |

1. Type the hotel Wi‑Fi name in the first box (e.g. `HotelFreeWiFi`).
2. Type the hotel Wi‑Fi password in the second box.
3. Tap the **🔗 Connect** button.

---

## Step 4: Wait a Moment

The router will now connect to the hotel’s Wi‑Fi. This takes about **5–10 seconds**.

- If everything worked, the page will reload and you’ll be online.
- Try opening any website (e.g. `google.com`) to confirm.

> **✨ Pro tip:** If the hotel has a wired Ethernet port in the room, plug the cable into the **first port** (labeled `ether1`) on the travel router. It’s faster and more reliable than Wi‑Fi!

---

## How to Check the VPN is Working

The VPN makes it look like you’re browsing from **home**, not from the hotel.

1. Open a browser and go to: `whatismyip.com`
2. The IP address shown should be your **home** IP address (not the hotel’s).

If you see your home IP — everything is working! 🎉

---

## Troubleshooting

### “I can’t see the Family-Traveling Wi‑Fi”
- Make sure the travel router is plugged in and the power light is on.
- Wait 1–2 minutes after plugging it in — it needs time to boot.
- Move closer to the router.

### “The setup page doesn’t load”
- Make sure you typed `potovalni.vpn` (not `.com` or `.si`).
- Try typing `http://192.168.123.1` instead.
- Turn Wi‑Fi off and on again on your device, then reconnect to `Family-Traveling`.

### “I enter the hotel details but nothing happens”
- Check the hotel Wi‑Fi name for typos — it must match exactly (capital letters, spaces, everything).
- The hotel might use a **captive portal** (a page where you have to click “Accept” or enter a room number). In that case:
  1. Connect to `Family-Traveling` on your phone.
  2. Go through the setup (Steps 1–3 above).
  3. Wait 30 seconds, then open a browser and try going to any website — the hotel’s own login page might appear.
  4. Complete the hotel’s login page, and you’ll be online.

### “The internet is slow”
- Try plugging an Ethernet cable into `ether1` (the first port). Wired is always faster.
- Move the travel router closer to a window or higher up — hotel walls can be thick.
- Restart the travel router (unplug power, wait 5 seconds, plug back in).

### “Still doesn’t work?”
- Call or text the person who set this up for you. They can check the router remotely.
- **Emergency fallback:** Connect your device directly to the hotel Wi‑Fi (skip the travel router). You won’t have the VPN, but you’ll have internet.

---

## Quick Reference Card (Print & Pack)

```
┌─────────────────────────────────────────────┐
│                                             │
│   🏨  FAMILY TRAVEL WI‑FI                   │
│                                             │
│   1. Connect to:  Family-Traveling          │
│      Password:    <YOUR_WIFI_PASSPHRASE>    │
│                                             │
│   2. Open browser →  potovalni.vpn          │
│                                             │
│   3. Enter hotel Wi‑Fi name & password      │
│      Tap Connect                            │
│                                             │
│   4. Done! 🌍                               │
│                                             │
│   Check VPN:  whatismyip.com                │
│   (should show your home IP)                │
│                                             │
└─────────────────────────────────────────────┘
```