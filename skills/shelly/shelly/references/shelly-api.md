# Shelly API Reference — Per-Generation Endpoints

## Device Identification

Every Shelly device responds to `GET /shelly` with JSON. Use this to detect the generation.

| Generation | Response Key(s) | Example |
|-----------|-----------------|---------|
| Gen 1 | No `gen` or `app` field | `{"type":"SHSW-25", "mac":"AABBCCDDEEFF", "fw_id":"20230913-112232/v1.14.0-gcb84623", "num_outputs":2}` |
| Gen 2 | `"gen":2`, `"app"` present | `{"type":"SHSW-1PM", "mac":"AABBCCDDEEFF", "gen":2, "app":"Plus1PM", "fw_id":"20241011-090000/1.4.4-gxxxx"}` |
| Gen 3 | `"gen":3`, `"app"` present | `{"type":"S3SW-001", "mac":"AABBCCDDEEFF", "gen":3, "app":"Pro3EM", "fw_id":"20250115-120000/1.5.0-gxxxx"}` |

---

## WiFi

### Get Status

**Gen 1:**
```
GET /settings/sta
→ {"enabled":true, "ssid":"MyWiFi", "ipv4_method":"dhcp", "ip":"192.168.1.50", "gw":"192.168.1.1", "mask":"255.255.255.0", "dns":null, "rssi":-58}
```

**Gen 2 / Gen 3:**
```
GET /rpc/Wifi.GetStatus
→ {"sta_ip":"192.168.1.50", "status":"got ip", "ssid":"MyWiFi", "rssi":-58}
```

### Set SSID & Password

**Gen 1:**
```
GET /settings/sta?ssid=NewWiFi&key=NewPassword
→ {"enabled":true, "ssid":"NewWiFi", ...}
```
Device reboots WiFi after this call. Expect ~15-30s reconnection.

**Gen 2 / Gen 3:**
```
POST /rpc/Wifi.Set
Content-Type: application/json

{"config":{"sta":{"ssid":"NewWiFi","pass":"NewPassword","is_open":false,"enable":true}}}
→ {"was_restarted":true}
```
Device reboots WiFi after this call. Expect ~15-30s reconnection.

### Scan (Gen 2/3 only)

```
GET /rpc/Wifi.Scan
→ {"results":[{"ssid":"MyWiFi","auth":4,"chan":6,"rssi":-42,...}]}
```

---

## Switching (Relays)

### Get State

**Gen 1:**
```
GET /relay/{id}
→ {"ison":true, "has_timer":false, "timer_started":0, ...}
```

**Gen 2 / Gen 3:**
```
GET /rpc/Switch.GetStatus?id={id}
→ {"id":0, "source":"http", "output":true, "apower":0.0, "voltage":234.1, "current":0.0, ...}
```

Gen 3 uses `"output":true/false` instead of `"ison"`.

### Set State

**Gen 1:**
```
GET /relay/{id}?turn=on
GET /relay/{id}?turn=off
GET /relay/{id}?turn=toggle
→ {"ison":true/false, ...}
```

**Gen 2 / Gen 3:**
```
GET /rpc/Switch.Set?id={id}&on=true
GET /rpc/Switch.Set?id={id}&on=false
GET /rpc/Switch.Toggle?id={id}
→ {"was_on":false}
```

---

## Lighting (Color / White / Dimming)

### Get State

**Gen 1 (RGBW2 in color mode):**
```
GET /color/{id}
→ {"ison":true, "mode":"color", "red":255, "green":128, "blue":0, "white":0, "gain":100, "effect":0, ...}
```
In white mode (`mode":"white"`): only `white` and `gain` are relevant.

**Gen 2 / Gen 3 (Shelly Plus RGBW PM, Shelly Bulb, etc.):**
```
GET /rpc/Light.GetStatus?id={id}
→ {"id":0, "source":"http", "output":true,
   "brightness":80.0, "rgb":[255,128,0], "color_mode":"color", ...
   "temp":null}
```
White mode: `"color_mode":"white"`, relevant fields are `brightness` and `temp` (Kelvin).

### Set State

**Gen 1 (RGBW2):**
```
GET /color/{id}?turn=on&red=255&green=128&blue=0&white=0&gain=100
GET /color/{id}?turn=on&white=255&gain=80         # white mode
GET /color/{id}?turn=off
→ {"ison":true, ...}
```

**Gen 2 / Gen 3:**
```
POST /rpc/Light.Set?id={id}
Content-Type: application/json

{"on":true, "brightness":80, "rgb":[255,128,0]}
→ {"was_on":false}

# White mode (CCT):
POST /rpc/Light.Set?id={id}
{"on":true, "brightness":70, "temp":4000}
→ {"was_on":false}

# Turn off:
POST /rpc/Light.Set?id={id}
{"on":false}
→ {"was_on":true}
```

---

## Authentication

| Generation | Auth Method | URL Pattern |
|-----------|-------------|-------------|
| Gen 1 | HTTP Digest | `http://user:pass@ip/endpoint` |
| Gen 2/3 | HTTP Digest (default) or Bearer token (API key) | Same, or `Authorization: Bearer <token>` header |

The script auto-detects: if auth is provided, try Digest first. If that fails with 401, try Bearer.

Gen 2/3 API keys are set via the device web UI under Settings → Authentication.

---

## Common Device Types

| Type String | Model | Generation | Capabilities |
|-------------|-------|-----------|-------------|
| `SHSW-1` | Shelly 1 | Gen 1 | 1 relay |
| `SHSW-25` | Shelly 2.5 | Gen 1 | 2 relays, roller |
| `SHPLG-S` | Shelly Plug S | Gen 1 | 1 relay, power meter |
| `SHRGBW2` | Shelly RGBW2 | Gen 1 | 4 channels (RGBW) |
| `SHBDUO-1` | Shelly Bulb Duo | Gen 1 | White/CCT bulb |
| `SHSW-1PM` | Shelly Plus 1PM | Gen 2 | 1 relay, power meter |
| `SHPLG2-1` | Shelly Plus Plug | Gen 2 | 1 relay, power meter |
| `SHRGBWPM` | Shelly Plus RGBW PM | Gen 2 | 4 channels RGBW, power meter |
| `S3SW-001` | Shelly Pro 3EM | Gen 3 | 3-phase energy meter |
| `S3WL-001` | Shelly Pro 1 | Gen 3 | 1 relay, power meter |