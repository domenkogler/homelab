---
name: shelly
description: Manage WiFi Shelly IoT devices — discover, switch, dim, change colors, and reconfigure WiFi SSID/password across all generations (Gen 1/2/3). Use when interacting with Shelly relays, bulbs, plugs, or RGBW controllers on the local network.
---

# Shelly Skill

Interacts with Shelly WiFi IoT devices over their local HTTP API. Supports all three device generations transparently — Gen 1 (classic), Gen 2 (Plus/Pro), and Gen 3 (latest Pro/EM).

## Setup

### Requirements

- Python 3.8+
- `requests` library (for HTTP calls)
- `zeroconf` library (for mDNS discovery; optional — falls back to IP scan)

```bash
pip install requests zeroconf
```

### Device Authentication

Shelly devices may have authentication enabled. Provide credentials using one of:

| Method | Flag / Env | Notes |
|--------|-----------|-------|
| Shared credentials | `--user admin --password secret` | Applied to all target devices |
| Per-device file | `--device-auth devices.json` | JSON: `{"192.168.1.50":{"user":"admin","pass":"x"}}` |
| 1Password references | `--op-env-file .env.op` | Same caching logic as the mikrotik skill |

If no auth is provided, the script assumes open access (no credentials required).

#### 1Password Integration (Recommended)

Same pattern as the mikrotik skill. Create a `.env.op` file:

```bash
# skills/shelly/.env.op
SHELLY_USER=admin
SHELLY_PASSWORD=op://Private/Shelly Devices/password
```

Then use:

```bash
python scripts/shelly.py --op-env-file .env.op discover
```

**How caching works:**
1. First invocation resolves secrets via `op run --no-masking` (one auth prompt)
2. Resolved values cached to `~/.cache/shelly-op/` for 8 hours
3. Subsequent calls use cached values (zero prompts)
4. Cache invalidated if the `.env.op` source file changes

| Env / Flag | Default | Description |
|-----------|---------|-------------|
| `SHELLY_OP_ENV_FILE` / `--op-env-file` | — | Path to `.env.op` file with `op://` references |
| `SHELLY_OP_CACHE_DIR` / `--op-cache-dir` | `~/.cache/shelly-op/` | Cache directory for resolved secrets |
| `SHELLY_OP_CACHE_TTL` / `--op-cache-ttl` | `28800` (8h) | Cache validity in seconds |

## Scripts

All scripts live under [`scripts/`](scripts/) relative to this skill directory.

### `shelly.py` — Unified Device CLI

Single script with subcommands for all operations.

```bash
python scripts/shelly.py <subcommand> [options]
```

**Global options** (available on all subcommands):

| Option | Description |
|--------|-------------|
| `--host HOST` | Target device IP. Required unless `--all` or discovery subcommand. |
| `--all` | Operate on all discovered devices instead of `--host`. |
| `--user USER` | Device username (if auth enabled). Default: `admin`. |
| `--password PASS` | Device password. |
| `--device-auth FILE` | JSON file mapping IPs to `{"user":"...","pass":"..."}`. |
| `--op-env-file FILE` | Path to `.env.op` with `op://` references. |
| `--op-cache-dir DIR` | Cache directory (default: `~/.cache/shelly-op/`). |
| `--op-cache-ttl SEC` | Cache TTL in seconds (default: `28800`). |
| `--timeout SEC` | HTTP request timeout (default: `10`). |
| `--format json\|table` | Output format (default: `json`). |
| `--dry-run` | Show what would happen without making changes. |

---

### Subcommands

#### `discover` — Find all Shelly devices on the LAN

```bash
python scripts/shelly.py discover [--scan 192.168.1.0/24] [--mdns]
```

| Option | Description |
|--------|-------------|
| `--scan CIDR` | IP range to scan (e.g., `192.168.1.0/24`). Default: auto-detect from routing table. |
| `--mdns` | Use mDNS (Zeroconf) for discovery. Enabled by default if `zeroconf` is installed. |
| `--no-mdns` | Skip mDNS, use IP scan only. |
| `--timeout SEC` | Per-host probe timeout for IP scan (default: `3`). |
| `--workers N` | Concurrent workers for IP scan (default: `50`). |

**Output** (JSON):
```json
[
  {
    "ip": "192.168.1.50",
    "hostname": "shellyplus1pm-abc123.local",
    "mac": "AA:BB:CC:DD:EE:FF",
    "type": "SHSW-1PM",
    "gen": 2,
    "fw": "20241011-090000/1.4.4-gxxxx",
    "model_name": "Shelly Plus 1PM"
  }
]
```

#### `info` — Dump full device identity and status

```bash
python scripts/shelly.py info --host 192.168.1.50
```

Outputs the combined `GET /shelly` response plus WiFi status and switch/light state blocks.

#### `wifi get` — Show current WiFi configuration

```bash
python scripts/shelly.py wifi get --host 192.168.1.50
python scripts/shelly.py wifi get --all               # all discovered devices
```

Output per device: `{ip, hostname, ssid, rssi, ip_address, mac}`.

#### `wifi set` — Change SSID/password on one or all devices

```bash
python scripts/shelly.py wifi set --host 192.168.1.50 --ssid "NewWiFi" --password "newpass"
python scripts/shelly.py wifi set --all --ssid "NewWiFi" --password "newpass"
```

| Option | Description |
|--------|-------------|
| `--ssid SSID` | **Required.** New WiFi SSID. |
| `--password PASS` | **Required.** New WiFi password. |
| `--host HOST` | Single device IP. |
| `--all` | All discovered devices. |

The device will reboot its WiFi after the change and reconnect within 15-30 seconds.
When using `--all`, the script waits for all devices to reconnect (polling with `--reconnect-timeout`).

#### `wifi rotate` — Bulk-update WiFi on all discovered devices

Designed for password rotation workflows. **This does NOT update the AP** — change the AP password separately (e.g., via mikrotik skill). This command re-points all Shelly devices to the new credentials.

```bash
# Dry-run first to see what will happen:
python scripts/shelly.py wifi rotate --ssid "NewWiFi" --password "newpass" --dry-run

# Execute:
python scripts/shelly.py wifi rotate --ssid "NewWiFi" --password "newpass"
```

| Option | Description |
|--------|-------------|
| `--ssid SSID` | **Required.** New SSID. |
| `--password PASS` | **Required.** New WiFi password. |
| `--state-file FILE` | Save/restore device snapshot (JSON). Reuses discovery data on retry. |
| `--batch-delay SEC` | Delay between device updates in seconds (default: `2`). Prevents AP auth flood. |
| `--reconnect-timeout SEC` | Max wait for devices to reconnect after update (default: `120`). |
| `--failure-threshold N` | Abort if more than N devices fail (default: `0` = never abort). |
| `--rollback FILE` | Roll back failed devices to previous config from state file. |

**Workflow:**
1. Discovers all Shelly devices (or loads from `--state-file`)
2. Snapshot current WiFi config of each device → saved to state file
3. Updates each device sequentially with `--batch-delay` between them
4. Polls each device for reconnection (MAC-matched from snapshot, tolerates IP changes)
5. Reports success/failure per device
6. On failure, use `--rollback <state-file>` to restore original credentials

#### `switch get` — Read relay/switch state

```bash
python scripts/shelly.py switch get --host 192.168.1.50
python scripts/shelly.py switch get --host 192.168.1.50 --id 1    # second channel
```

#### `switch set` — Turn relay on/off/toggle

```bash
python scripts/shelly.py switch set --host 192.168.1.50 on
python scripts/shelly.py switch set --host 192.168.1.50 off
python scripts/shelly.py switch set --host 192.168.1.50 toggle
python scripts/shelly.py switch set --all off                      # all devices
```

| Argument | Description |
|----------|-------------|
| `state` | `on`, `off`, or `toggle` |
| `--id N` | Channel/relay index (default: `0`). |

#### `light get` — Read light/color state

```bash
python scripts/shelly.py light get --host 192.168.1.55
```

Output: `{output, brightness, rgb, color_mode, temp, ...}`.

#### `light set` — Set light color/brightness/white temperature

```bash
# Color mode:
python scripts/shelly.py light set --host 192.168.1.55 --color 255,128,0 --brightness 80

# White temperature mode:
python scripts/shelly.py light set --host 192.168.1.55 --white --temp 4000 --brightness 70

# Turn off:
python scripts/shelly.py light set --host 192.168.1.55 off

# Turn on with last settings:
python scripts/shelly.py light set --host 192.168.1.55 on
```

| Option | Description |
|--------|-------------|
| `on\|off` | Turn on or off (positional). Omit to leave on/off unchanged. |
| `--color R,G,B` | RGB values (0-255). Sets color mode. |
| `--white` | Use white mode instead of color. |
| `--brightness N` | Brightness 0-100. |
| `--temp K` | White temperature in Kelvin (e.g., `2700` warm, `6500` cool). Requires `--white`. |
| `--id N` | Light channel (default: `0`). |

---

## Examples

### Discover all devices

```bash
python scripts/shelly.py discover
```

### View device info

```bash
python scripts/shelly.py info --host 192.168.1.50
```

### Check WiFi on all devices

```bash
python scripts/shelly.py wifi get --all
```

### Change WiFi on a single device

```bash
python scripts/shelly.py wifi set --host 192.168.1.50 --ssid "IoT-Net" --password "s3cret!"
```

### Rotate WiFi password on all devices (dry-run)

```bash
python scripts/shelly.py wifi rotate --ssid "IoT-Net" --password "new-pass" --dry-run
```

### Turn all lights off at night

```bash
python scripts/shelly.py switch set --all off
```

### Set warm white in the living room

```bash
python scripts/shelly.py light set --host 192.168.1.55 --white --temp 2700 --brightness 60
```

### Set mood lighting (color)

```bash
python scripts/shelly.py light set --host 192.168.1.55 --color 255,80,0 --brightness 50
```

---

## Troubleshooting

| Problem | Likely Cause & Fix |
|---------|-------------------|
| `Connection refused` | Device unreachable or powered off. Check IP, verify device is online. |
| `401 Unauthorized` | Device has auth enabled. Provide `--user` and `--password`. |
| `No devices found` | No Shelly devices on the scanned subnet. Try `--scan` with a wider range, or enable `--mdns`. |
| `zeroconf not installed` | mDNS discovery unavailable. `pip install zeroconf` or use `--scan`. |
| Device unreachable after wifi set | Normal — WiFi reboots. Wait up to 30s. With `wifi rotate`, the script polls automatically. |
| Gen detection fails | Very old firmware may return unexpected `/shelly` response. Update device firmware. |
| `light set` changes unexpectedly | Gen 1 RGBW2 uses `gain` (0-100) not `brightness`. Script translates automatically. |

## Reference

See [references/shelly-api.md](references/shelly-api.md) for the complete per-generation API endpoint table, auth details, and common device type strings.