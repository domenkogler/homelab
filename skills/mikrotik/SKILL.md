---
name: mikrotik
description: Read MikroTik RouterOS configuration and runtime state via the RouterOS API. Use when you need to inspect firewall rules, NAT, interfaces, DHCP leases, routes, wireless clients, system health, or any other configuration path on a MikroTik device.
---

# MikroTik Skill

Connects to a MikroTik RouterOS device over the API (port 8728/TCP) using the `routeros-api` Python library to read configuration and state.

## Setup

### Requirements

- Python 3.8+
- `routeros-api` library installed globally or in a venv:

```bash
pip install routeros-api
```

If `pip` is unavailable in the current environment, install it manually from the [PyPI package](https://pypi.org/project/routeros-api/).

### Connection Details

Provide credentials and host via environment variables (recommended) or inline arguments:

| Variable | Description |
|----------|-------------|
| `MIKROTIK_HOST` | Router IP or hostname |
| `MIKROTIK_USER` | API username (recommend a read-only user) |
| `MIKROTIK_PASSWORD` | API password |
| `MIKROTIK_PORT` | API port (default: `8728`) |
| `MIKROTIK_TIMEOUT` | Connection timeout in seconds (default: `10`) |

> **Security:** Prefer environment variables or a `.env` file. Never hardcode credentials in scripts or commit them to Git. The `--password` argument reads from stdin if you pipe it, so it does not appear in `ps` output.

### Session-Only Environment Variables

To avoid typing `--host --user --password` every time without persisting them globally:

**Option 1 — Export in the current terminal:**

```bash
export MIKROTIK_HOST=10.0.0.1
export MIKROTIK_USER=apiuser
export MIKROTIK_PASSWORD="your-secret"

# Now just use paths:
python scripts/mikrotik-read.py /ip/firewall/filter /ip/address
```

These vanish when you close the terminal. To undo mid-session: `unset MIKROTIK_HOST`.

**Option 2 — One-liner (single command):**

```bash
MIKROTIK_HOST=10.0.0.1 MIKROTIK_USER=apiuser MIKROTIK_PASSWORD=secret \
  python scripts/mikrotik-read.py /ip/firewall/filter
```

Environment variables set before a command apply only to that command — they do not persist in the shell afterwards.

**Option 3 — Local `.env` file (sourced per session):**

Create a `.env` file in the skill directory (or project root) and add it to `.gitignore`:

```bash
# skills/mikrotik/.env
MIKROTIK_HOST=10.0.0.1
MIKROTIK_USER=apiuser
MIKROTIK_PASSWORD=your-secret
MIKROTIK_PORT=8728
MIKROTIK_TIMEOUT=15
```

Load it when you start working:

```bash
source skills/mikrotik/.env
```

Or make it automatic by adding to your shell rc file (optional):

```bash
# ~/.bashrc or ~/.zshrc
export AUTOMATION_ENV_DIR="$HOME/homelab/skills/mikrotik"
[ -f "$AUTOMATION_ENV_DIR/.env" ] && source "$AUTOMATION_ENV_DIR/.env"
```

**Option 4 — Shell alias (shortcut):**

```bash
alias mikrotik='MIKROTIK_HOST=10.0.0.1 MIKROTIK_USER=apiuser MIKROTIK_PASSWORD=secret python skills/mikrotik/scripts/mikrotik-read.py'

# Then:
mikrotik /ip/address
mikrotik /ip/firewall/filter /system/identity
```

Add the alias to `~/.bashrc` or `~/.zshrc` to keep it across sessions, or type it inline for the current session only.

### Option 5 — 1Password CLI (`op`) — Recommended

If you use 1Password, the CLI tool `op` can inject secrets directly without ever storing them in files or shell history.

**Prerequisite:** Install the [1Password CLI](https://developer.1password.com/docs/cli/get-started/) and sign in:

```bash
op account add --address my.1password.com --email you@example.com
eval $(op signin)
```

**Approach A — Inline with `op run`:**

Wrap the command with `op run` and use `op://` references. The secrets are fetched at runtime and never written to disk:

```bash
op run -- \
  MIKROTIK_HOST=10.0.0.1 \
  MIKROTIK_USER=apiuser \
  MIKROTIK_PASSWORD="op://Private/MikroTik Router/password" \
  python skills/mikrotik/scripts/mikrotik-read.py /ip/firewall/filter
```

Where `Private/MikroTik Router/password` is your 1Password vault/item/field path.

**Approach B — Environment via `op run` + `--env`:**

Create an env template file (safe to commit — it contains placeholders, not secrets):

```bash
# skills/mikrotik/.env.op
MIKROTIK_HOST=10.0.0.1
MIKROTIK_USER=apiuser
MIKROTIK_PASSWORD=op://Private/MikroTik Router/password
MIKROTIK_PORT=8728
```

Then run:

```bash
op run --env-file=skills/mikrotik/.env.op -- \
  python skills/mikrotik/scripts/mikrotik-read.py /ip/firewall/filter
```

`op run` resolves all `op://` references at runtime, injects them as real environment variables, and runs the command. The template file `.env.op` contains only references, never the actual password.

**Approach C — One-time fetch with `op item get`:**

For a single manual invocation without `op run`:

```bash
MIKROTIK_PASSWORD=$(op item get "MikTik Router" --fields label=password) \
  python skills/mikrotik/scripts/mikrotik-read.py /ip/firewall/filter
```

This fetches the password fresh each time and stores it only in memory for that command.

> **Tip:** Combine with a shell alias for minimal typing:
> ```bash
> alias mtr='op run --env-file=skills/mikrotik/.env.op -- python skills/mikrotik/scripts/mikrotik-read.py'
> mtr /ip/firewall/filter /ip/address
> ```

## Scripts

All scripts live under [`scripts/`](scripts/) relative to this skill directory.

### `mikrotik-read.py` — Read RouterOS Paths

Reads one or more MikroTik configuration paths and outputs them as JSON.

```bash
python scripts/mikrotik-read.py \
  --host 10.0.0.1 \
  --user apiuser \
  --password secret \
  /ip/firewall/filter /ip/address /system/identity
```

Or via environment variables:

```bash
export MIKROTIK_HOST=10.0.0.1
export MIKROTIK_USER=apiuser
export MIKROTIK_PASSWORD=secret

python scripts/mikrotik-read.py /ip/firewall/filter /ip/address
```

**Arguments:**

| Argument | Description |
|----------|-------------|
| `paths` (positional, one or more) | RouterOS API paths to read, e.g. `/ip/address`, `/ip/firewall/nat` |

**Options:**

| Flag | Default | Description |
|------|---------|-------------|
| `--host` | `$MIKROTIK_HOST` | Router hostname/IP |
| `--user` | `$MIKROTIK_USER` | API username |
| `--password` | `$MIKROTIK_PASSWORD` | API password |
| `--port` | `8728` (or `$MIKROTIK_PORT`) | API port |
| `--timeout` | `10` (or `$MIKROTIK_TIMEOUT`) | Connection timeout |
| `--plaintext-login` | `true` | Use plaintext login (required for RouterOS v6+). Pass `--no-plaintext-login` to disable. |
| `--use-ssl` | `false` | Connect via SSL/TLS (API-SSL port 8729). Pass `--use-ssl` to enable. |
| `--ssl-verify` | `true` | Verify SSL certificate. Pass `--no-ssl-verify` to skip verification. |
| `--query` | | Optional filter, e.g. `name=ether1`. Repeat for multiple filters. |
| `--indent` | `2` | JSON indentation level (`0` for compact, `null` for no indent). |

### Pagination / Large Results

By default the API fetches all matching records. If you expect thousands of items (e.g., a large address list), consider using `--query` to narrow results.

## Examples

### Firewall Rules

```bash
python scripts/mikrotik-read.py /ip/firewall/filter
```

### NAT Rules

```bash
python scripts/mikrotik-read.py /ip/firewall/nat
```

### All Interfaces With Detail

```bash
python scripts/mikrotik-read.py /interface
```

### Wireless Registration Table (Connected Clients)

```bash
python scripts/mikrotik-read.py /interface/wireless/registration-table
```

### DHCP Leases

```bash
python scripts/mikrotik-read.py /ip/dhcp-server/lease
```

### Routes

```bash
python scripts/mikrotik-read.py /ip/route
```

### System Health (Temperature, Voltage)

```bash
python scripts/mikrotik-read.py /system/health
```

### Multiple Paths in One Connection

```bash
python scripts/mikrotik-read.py \
  /system/identity \
  /system/routerboard \
  /system/resource \
  /system/clock
```

### Filtered Query

```bash
python scripts/mikrotik-read.py /ip/address --query interface=bridge
```

## Common RouterOS Paths

| Path | What You Get |
|------|-------------|
| `/system/identity` | Router name |
| `/system/resource` | CPU, uptime, free memory, version |
| `/system/health` | Temperature, voltage, fan speed |
| `/system/routerboard` | Routerboard model, firmware |
| `/system/clock` | System time, time zone, NTP sync |
| `/system/package` | Installed packages |
| `/interface` | All interfaces (physical + virtual) |
| `/interface/ethernet` | Physical ethernet ports |
| `/interface/bridge` | Bridge interfaces |
| `/interface/bridge/port` | Bridge port members |
| `/interface/vlan` | VLAN interfaces |
| `/interface/wireless` | Wireless interfaces |
| `/interface/wireless/registration-table` | Connected wireless clients |
| `/ip/address` | IP addresses configured on interfaces |
| `/ip/dhcp-client` | DHCP client config & status |
| `/ip/dhcp-server` | DHCP server configuration |
| `/ip/dhcp-server/lease` | Active & dynamic DHCP leases |
| `/ip/dhcp-server/network` | DHCP server networks |
| `/ip/dns` | DNS resolver config & cache |
| `/ip/dns/static` | Static DNS entries |
| `/ip/firewall/filter` | Firewall filter rules |
| `/ip/firewall/nat` | NAT rules |
| `/ip/firewall/mangle` | Mangle rules |
| `/ip/firewall/address-list` | Dynamic & static address lists |
| `/ip/firewall/raw` | Raw firewall rules |
| `/ip/firewall/service-port` | Service ports |
| `/ip/firewall/connection` | Active connections |
| `/ip/route` | Routing table |
| `/ip/pool` | IP address pools |
| `/ip/smb` | SMB shares on RouterOS |
| `/ip/neighbor` | Discovered CDP/LLDP neighbors |
| `/port` | Serial/USB port config |
| `/snmp/community` | SNMP community strings |
| `/user` | Local user accounts |
| `/user/group` | User groups and permissions |
| `/system/logging` | Logging rules |
| `/system/scheduler` | Scheduled scripts |
| `/system/script` | Stored scripts |
| `/tool/traceroute` | Run traceroute results |
| `/tool/netwatch` | Netwatch monitoring rules |
| `/tool/bandwidth-test` | Bandwidth test server config |
| `/certificate` | Certificates (list only, not keys) |

## Creating a Read-Only API User on the Router

It is strongly recommended to use a dedicated read-only user for this skill:

```bash
/user add name=apiuser group=read password="your-password" disabled=no
```

The `read` group has read-only access to all configuration paths and disallows any write, edit, or remove operations.

## Troubleshooting

| Problem | Likely Cause & Fix |
|---------|-------------------|
| `Connection refused` | API service not enabled on the router: `/ip/service set api disabled=no` |
| `Authentication failed` | Wrong username/password or API user missing |
| `Login type not supported` | RouterOS v6+ requires `--plaintext-login` (enabled by default) |
| `Timeout` | Firewall blocking port 8728, or router unreachable; check `--timeout` |
| `Empty result` | Path exists but no matching items; check for typos in path or query filters |
| Module not found | The `routeros-api` library is not installed; run `pip install routeros-api` |

## Reference

- [routeros-api Python library on PyPI](https://pypi.org/project/routeros-api/)
- [MikroTik API documentation](https://help.mikrotik.com/docs/display/ROS/API)
- [MikroTik REST API (alternative)](https://help.mikrotik.com/docs/display/ROS/REST+API)

See [the helper script](scripts/mikrotik-read.py) for the full implementation.
