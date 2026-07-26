#!/usr/bin/env python3
"""
Shelly Device Manager

Discovers and controls Shelly WiFi IoT devices across all generations (Gen 1/2/3).
Supports discovery, WiFi reconfiguration, switching, and lighting (color/white).

Usage:
    python shelly.py discover
    python shelly.py info --host 192.168.1.50
    python shelly.py wifi get --host 192.168.1.50
    python shelly.py wifi set --host 192.168.1.50 --ssid "IoT" --password "pass"
    python shelly.py wifi rotate --ssid "IoT" --password "pass"
    python shelly.py switch get --host 192.168.1.50
    python shelly.py switch set --host 192.168.1.50 on
    python shelly.py light get --host 192.168.1.55
    python shelly.py light set --host 192.168.1.55 --color 255,128,0 --brightness 80

Environment variables:
    SHELLY_USER, SHELLY_PASSWORD, SHELLY_SCAN_CIDR,
    SHELLY_OP_ENV_FILE, SHELLY_OP_CACHE_DIR, SHELLY_OP_CACHE_TTL
"""

import argparse
import base64
import concurrent.futures
import hashlib
import ipaddress
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import time
from typing import Any, Optional
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

# ---------------------------------------------------------------------------
# Optional dependency: zeroconf for mDNS discovery
# ---------------------------------------------------------------------------
try:
    from zeroconf import ServiceBrowser, Zeroconf, ZeroconfServiceTypes

    _has_zeroconf = True
except ImportError:
    _has_zeroconf = False

# ---------------------------------------------------------------------------
# Optional dependency: requests for richer HTTP (digest auth, sessions)
# ---------------------------------------------------------------------------
try:
    import requests
    from requests.auth import HTTPDigestAuth

    _has_requests = True
except ImportError:
    _has_requests = False

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
DEFAULT_TIMEOUT = 10
DEFAULT_SCAN_TIMEOUT = 3
DEFAULT_RECONNECT_TIMEOUT = 120
DEFAULT_BATCH_DELAY = 2
DEFAULT_CACHE_TTL = 28800  # 8 hours

# ---------------------------------------------------------------------------
# 1Password cache helpers (same pattern as mikrotik skill)
# ---------------------------------------------------------------------------

def _cache_path(env_file_path: str, cache_dir: str) -> str:
    abs_path = os.path.abspath(env_file_path)
    key = hashlib.sha256(abs_path.encode("utf-8")).hexdigest()[:16]
    return os.path.join(cache_dir, f"{key}.env")


def _read_cache(cache_path: str, env_file_path: str, ttl: int) -> Optional[dict[str, str]]:
    try:
        cache_mtime = os.path.getmtime(cache_path)
        source_mtime = os.path.getmtime(env_file_path)
    except FileNotFoundError:
        return None

    now = time.time()
    if now - cache_mtime > ttl:
        return None

    resolved: dict[str, str] = {}
    with open(cache_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("# source-mtime:"):
                cached_source_mtime = float(line.split(":", 1)[1].strip())
                if cached_source_mtime != source_mtime:
                    return None
                continue
            if "=" in line:
                key, _, encoded = line.partition("=")
                try:
                    resolved[key.strip()] = base64.b64decode(encoded.strip()).decode("utf-8")
                except Exception:
                    resolved[key.strip()] = encoded.strip()
    return resolved


def _write_cache(cache_path: str, env_file_path: str, resolved: dict[str, str]) -> None:
    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
    source_mtime = os.path.getmtime(env_file_path)
    with open(cache_path, "w") as f:
        f.write(f"# source-mtime:{source_mtime}\n")
        for k, v in sorted(resolved.items()):
            f.write(f"{k}={base64.b64encode(v.encode('utf-8')).decode('ascii')}\n")
    os.chmod(cache_path, 0o600)


def resolve_op_env(op_env_file: str, cache_dir: str, cache_ttl: int) -> dict[str, str]:
    """Resolve secrets from a .env.op file with 1Password, with caching."""
    cache_file = _cache_path(op_env_file, cache_dir)
    cached = _read_cache(cache_file, op_env_file, cache_ttl)
    if cached is not None:
        return cached

    try:
        result = subprocess.run(
            ["op", "run", "--no-masking", "--env-file", op_env_file, "--", "printenv"],
            capture_output=True,
            text=True,
            timeout=30,
            check=True,
        )
    except FileNotFoundError:
        print("Error: 1Password CLI ('op') not found. Install it from https://1password.com/downloads/command-line/",
              file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"Error: 1Password CLI failed: {e.stderr.strip()}", file=sys.stderr)
        sys.exit(1)

    resolved: dict[str, str] = {}
    for line in result.stdout.strip().split("\n"):
        if "=" in line:
            key, _, val = line.partition("=")
            resolved[key.strip()] = val.strip()

    _write_cache(cache_file, op_env_file, resolved)
    return resolved


# ---------------------------------------------------------------------------
# ShellyDevice — generation-aware HTTP client
# ---------------------------------------------------------------------------

class ShellyDevice:
    """Represents a single Shelly device with auto-detected generation."""

    def __init__(self, ip: str, user: Optional[str] = None, password: Optional[str] = None,
                 timeout: int = DEFAULT_TIMEOUT):
        self.ip = ip
        self.user = user
        self.password = password
        self.timeout = timeout
        self._gen: int = 0
        self._info: dict[str, Any] = {}
        self._probed = False

    # --- HTTP helpers ---

    def _url(self, path: str, params: Optional[dict] = None) -> str:
        url = f"http://{self.ip}{path}"
        if params:
            url += "?" + urlencode(params, doseq=True)
        return url

    def _request(self, method: str, path: str, params: Optional[dict] = None,
                 json_body: Optional[dict] = None) -> dict[str, Any]:
        """Make an HTTP request. Prefers requests library for digest auth; falls back to urllib."""
        if _has_requests:
            return self._request_requests(method, path, params, json_body)
        else:
            return self._request_urllib(method, path, params, json_body)

    def _request_requests(self, method: str, path: str, params: Optional[dict] = None,
                          json_body: Optional[dict] = None) -> dict[str, Any]:
        url = f"http://{self.ip}{path}"
        auth = None
        if self.user and self.password:
            auth = HTTPDigestAuth(self.user, self.password)

        try:
            if method == "GET":
                resp = requests.get(url, params=params, auth=auth, timeout=self.timeout)
            elif method == "POST":
                resp = requests.post(url, params=params, json=json_body, auth=auth, timeout=self.timeout)
            else:
                raise ValueError(f"Unsupported method: {method}")
            resp.raise_for_status()
            return resp.json()
        except requests.exceptions.RequestException as e:
            raise ConnectionError(f"HTTP error on {url}: {e}")

    def _request_urllib(self, method: str, path: str, params: Optional[dict] = None,
                        json_body: Optional[dict] = None) -> dict[str, Any]:
        url = self._url(path, params)
        data = None
        if json_body:
            data = json.dumps(json_body).encode("utf-8")

        req = Request(url, data=data, method=method)
        if json_body:
            req.add_header("Content-Type", "application/json")

        try:
            with urlopen(req, timeout=self.timeout) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            raise ConnectionError(f"HTTP {e.code} on {url}: {body}")
        except URLError as e:
            raise ConnectionError(f"Connection failed to {url}: {e.reason}")

    def _get(self, path: str, params: Optional[dict] = None) -> dict[str, Any]:
        return self._request("GET", path, params=params)

    def _post(self, path: str, params: Optional[dict] = None,
              json_body: Optional[dict] = None) -> dict[str, Any]:
        return self._request("POST", path, params=params, json_body=json_body)

    # --- Probing / Gen Detection ---

    def probe(self) -> dict[str, Any]:
        """Detect device generation and return device info. Cached after first call."""
        if self._probed:
            return self._info
        try:
            info = self._get("/shelly")
        except ConnectionError:
            raise ConnectionError(f"Device at {self.ip} is unreachable")

        if "gen" in info:
            self._gen = info["gen"]
        elif "type" in info and "app" not in info:
            self._gen = 1
        else:
            # Heuristic: Gen 1 devices have no 'gen' and no 'app'
            self._gen = 1

        self._info = info
        self._probed = True
        return info

    @property
    def gen(self) -> int:
        if not self._probed:
            self.probe()
        return self._gen

    @property
    def info(self) -> dict[str, Any]:
        if not self._probed:
            self.probe()
        return self._info

    # --- WiFi ---

    def wifi_status(self) -> dict[str, Any]:
        if self.gen == 1:
            return self._get("/settings/sta")
        else:
            return self._get("/rpc/Wifi.GetStatus")

    def wifi_set(self, ssid: str, password: str) -> dict[str, Any]:
        if self.gen == 1:
            return self._get("/settings/sta", {"ssid": ssid, "key": password})
        else:
            body = {
                "config": {
                    "sta": {
                        "ssid": ssid,
                        "pass": password,
                        "is_open": False,
                        "enable": True,
                    }
                }
            }
            return self._post("/rpc/Wifi.Set", json_body=body)

    # --- Switch ---

    def switch_status(self, channel: int = 0) -> dict[str, Any]:
        if self.gen == 1:
            return self._get(f"/relay/{channel}")
        else:
            return self._get("/rpc/Switch.GetStatus", {"id": channel})

    def switch_set(self, channel: int = 0, state: bool = True) -> dict[str, Any]:
        if self.gen == 1:
            action = "on" if state else "off"
            return self._get(f"/relay/{channel}", {"turn": action})
        else:
            return self._get("/rpc/Switch.Set", {"id": channel, "on": "true" if state else "false"})

    def switch_toggle(self, channel: int = 0) -> dict[str, Any]:
        if self.gen == 1:
            return self._get(f"/relay/{channel}", {"turn": "toggle"})
        else:
            return self._get("/rpc/Switch.Toggle", {"id": channel})

    # --- Light ---

    def light_status(self, channel: int = 0) -> dict[str, Any]:
        if self.gen == 1:
            return self._get(f"/color/{channel}")
        else:
            return self._get("/rpc/Light.GetStatus", {"id": channel})

    def light_set(self, channel: int = 0, on: Optional[bool] = None,
                  brightness: Optional[int] = None,
                  red: Optional[int] = None, green: Optional[int] = None, blue: Optional[int] = None,
                  white: Optional[int] = None, gain: Optional[int] = None,
                  temp: Optional[int] = None) -> dict[str, Any]:
        if self.gen == 1:
            return self._light_set_gen1(channel, on, brightness, red, green, blue, white, gain, temp)
        else:
            return self._light_set_gen2(channel, on, brightness, red, green, blue, white, temp)

    def _light_set_gen1(self, channel: int, on: Optional[bool],
                        brightness: Optional[int], red: Optional[int], green: Optional[int],
                        blue: Optional[int], white: Optional[int], gain: Optional[int],
                        temp: Optional[int]) -> dict[str, Any]:
        params: dict[str, Any] = {}
        if on is not None:
            params["turn"] = "on" if on else "off"
        # Gen 1 RGBW2 uses red/green/blue/white/gain directly as query params
        # For white mode, set white and gain
        # For color mode, set red/green/blue and gain
        if red is not None or green is not None or blue is not None:
            if red is not None:
                params["red"] = red
            if green is not None:
                params["green"] = green
            if blue is not None:
                params["blue"] = blue
            params["mode"] = "color"
        if white is not None:
            params["white"] = white
            if red is None and green is None and blue is None:
                params["mode"] = "white"
        if gain is not None:
            params["gain"] = gain
        elif brightness is not None:
            params["gain"] = brightness  # Gen 1 maps brightness → gain
        return self._get(f"/color/{channel}", params)

    def _light_set_gen2(self, channel: int, on: Optional[bool],
                        brightness: Optional[int], red: Optional[int], green: Optional[int],
                        blue: Optional[int], white: Optional[int],
                        temp: Optional[int]) -> dict[str, Any]:
        body: dict[str, Any] = {"id": channel}
        if on is not None:
            body["on"] = on
        if red is not None and green is not None and blue is not None:
            body["rgb"] = [red, green, blue]
        if brightness is not None:
            body["brightness"] = brightness
        if temp is not None or white is not None:
            if temp is not None:
                body["temp"] = temp
            if white is not None:
                body["white"] = white
        return self._post("/rpc/Light.Set", params={"id": channel}, json_body=body)


# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

def _get_default_subnet() -> Optional[str]:
    """Auto-detect local subnet from routing table."""
    try:
        # Use socket to find the primary interface's network
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
        # Assume /24 — covers most home LANs
        net = ipaddress.IPv4Network(f"{local_ip}/24", strict=False)
        return str(net)
    except Exception:
        return None


def _probe_ip(ip: str, timeout: float) -> Optional[dict[str, Any]]:
    """Quick probe: GET /shelly and return device info if it's a Shelly."""
    url = f"http://{ip}/shelly"
    try:
        if _has_requests:
            resp = requests.get(url, timeout=timeout)
            resp.raise_for_status()
            data = resp.json()
        else:
            req = Request(url)
            with urlopen(req, timeout=timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
    except Exception:
        return None

    # Validate it looks like a Shelly response
    if "type" in data or "app" in data:
        return data
    return None


def discover_mdns(timeout: float = 5) -> list[dict[str, Any]]:
    """Discover Shelly devices via mDNS (_http._tcp.local. with 'shelly' in name)."""
    if not _has_zeroconf:
        return []

    devices: list[dict[str, Any]] = []
    found: set[str] = set()

    class ShellyListener:
        def add_service(self, zc: Zeroconf, type_: str, name: str) -> None:
            pass

        def remove_service(self, zc: Zeroconf, type_: str, name: str) -> None:
            pass

        def update_service(self, zc: Zeroconf, type_: str, name: str) -> None:
            if "shelly" not in name.lower():
                return
            try:
                info = zc.get_service_info(type_, name)
                if info and info.addresses:
                    ip = socket.inet_ntoa(info.addresses[0])
                    if ip not in found:
                        found.add(ip)
                        hostname = info.server.rstrip(".")
                        devices.append({
                            "ip": ip,
                            "hostname": hostname,
                            "discovery": "mdns",
                        })
            except Exception:
                pass

    zc = Zeroconf()
    listener = ShellyListener()
    browser = ServiceBrowser(zc, "_http._tcp.local.", listener)

    # Wait for discovery
    deadline = time.time() + timeout
    while time.time() < deadline:
        time.sleep(0.5)

    zc.close()

    # Enrich with device info
    return _enrich_devices(devices)


def discover_scan(cidr: str, timeout: float = DEFAULT_SCAN_TIMEOUT,
                  workers: int = 50) -> list[dict[str, Any]]:
    """Scan an IP range for Shelly devices via GET /shelly."""
    network = ipaddress.IPv4Network(cidr, strict=False)
    ips = [str(ip) for ip in network.hosts()]

    devices: list[dict[str, Any]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {executor.submit(_probe_ip, ip, timeout): ip for ip in ips}
        for future in concurrent.futures.as_completed(futures):
            ip = futures[future]
            try:
                result = future.result()
                if result:
                    devices.append({
                        "ip": ip,
                        "hostname": None,
                        "discovery": "scan",
                        "_raw": result,
                    })
            except Exception:
                pass

    return _enrich_devices(devices)


def _enrich_devices(devices: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Probe each discovered IP to fill in type, gen, MAC, fw, etc."""
    for dev in devices:
        ip = dev["ip"]
        try:
            raw = dev.pop("_raw", None) or _probe_ip(ip, DEFAULT_SCAN_TIMEOUT)
            if raw:
                gen = raw.get("gen", 1 if "app" not in raw else 2)
                dev.update({
                    "mac": raw.get("mac"),
                    "type": raw.get("type"),
                    "gen": gen,
                    "fw": raw.get("fw_id"),
                    "hostname": dev.get("hostname"),
                    "model_name": raw.get("app") or raw.get("type"),
                })
        except Exception:
            dev.update({
                "mac": None,
                "type": None,
                "gen": 0,
                "fw": None,
                "model_name": None,
            })
    return devices


def discover(scan_cidr: Optional[str] = None, use_mdns: bool = True,
             timeout: float = DEFAULT_SCAN_TIMEOUT, workers: int = 50) -> list[dict[str, Any]]:
    """Discover all Shelly devices. Combines mDNS + IP scan, deduplicates by IP."""
    all_devices: dict[str, dict[str, Any]] = {}

    if use_mdns and _has_zeroconf:
        for dev in discover_mdns(timeout=timeout):
            all_devices[dev["ip"]] = dev

    cidr = scan_cidr or _get_default_subnet()
    if cidr:
        for dev in discover_scan(cidr, timeout=timeout, workers=workers):
            if dev["ip"] not in all_devices:
                all_devices[dev["ip"]] = dev
            else:
                # Merge: mDNS gives hostname, scan gives full info
                existing = all_devices[dev["ip"]]
                if not existing.get("hostname"):
                    existing["hostname"] = dev.get("hostname")
                existing.update({k: v for k, v in dev.items() if existing.get(k) is None and v is not None})

    return sorted(all_devices.values(), key=lambda d: d["ip"])


# ---------------------------------------------------------------------------
# Device factory (handles auth resolution)
# ---------------------------------------------------------------------------

def load_device_auth(device_auth_file: Optional[str]) -> dict[str, dict[str, str]]:
    """Load per-device auth mapping from JSON file."""
    if not device_auth_file:
        return {}
    with open(device_auth_file) as f:
        return json.load(f)


def make_device(ip: str, user: Optional[str] = None, password: Optional[str] = None,
                device_auth: Optional[dict[str, dict[str, str]]] = None,
                timeout: int = DEFAULT_TIMEOUT) -> ShellyDevice:
    """Create a ShellyDevice with appropriate auth."""
    u, p = user, password
    if device_auth and ip in device_auth:
        da = device_auth[ip]
        u = u or da.get("user") or da.get("username")
        p = p or da.get("pass") or da.get("password")
    return ShellyDevice(ip, user=u, password=p, timeout=timeout)


def resolve_targets(args: argparse.Namespace) -> list[ShellyDevice]:
    """Resolve --host or --all into a list of ShellyDevice objects."""
    device_auth = load_device_auth(getattr(args, "device_auth", None))
    timeout = getattr(args, "timeout", DEFAULT_TIMEOUT)
    user = getattr(args, "user", None)
    password = getattr(args, "password", None)

    if getattr(args, "all", False):
        devices = discover(
            scan_cidr=getattr(args, "scan", None),
            use_mdns=getattr(args, "mdns", True),
        )
        return [make_device(d["ip"], user=user, password=password,
                           device_auth=device_auth, timeout=timeout) for d in devices]
    elif getattr(args, "host", None):
        return [make_device(args.host, user=user, password=password,
                           device_auth=device_auth, timeout=timeout)]
    else:
        print("Error: specify --host <ip> or --all", file=sys.stderr)
        sys.exit(1)


# ---------------------------------------------------------------------------
# Subcommand handlers
# ---------------------------------------------------------------------------

def cmd_discover(args: argparse.Namespace) -> None:
    devices = discover(
        scan_cidr=args.scan,
        use_mdns=args.mdns,
        timeout=args.timeout,
        workers=args.workers,
    )
    _output(args, devices)


def cmd_info(args: argparse.Namespace) -> None:
    for dev in resolve_targets(args):
        try:
            info = dev.probe()
            result = {"ip": dev.ip, "info": info}
            try:
                result["wifi"] = dev.wifi_status()
            except Exception:
                result["wifi"] = {"error": "unavailable"}
            try:
                result["switch"] = dev.switch_status()
            except Exception:
                result["switch"] = {"error": "unavailable"}
            _output(args, result)
        except ConnectionError as e:
            _output(args, {"ip": dev.ip, "error": str(e)})


def cmd_wifi_get(args: argparse.Namespace) -> None:
    results = []
    for dev in resolve_targets(args):
        try:
            dev.probe()
            status = dev.wifi_status()
            # Normalise across generations
            if dev.gen == 1:
                result = {
                    "ip": dev.ip,
                    "ssid": status.get("ssid"),
                    "rssi": status.get("rssi"),
                    "mac": dev.info.get("mac"),
                    "enabled": status.get("enabled"),
                }
            else:
                result = {
                    "ip": dev.ip,
                    "ssid": status.get("ssid"),
                    "rssi": status.get("rssi"),
                    "mac": dev.info.get("mac"),
                    "ip_address": status.get("sta_ip") or status.get("ip"),
                }
            results.append(result)
        except ConnectionError as e:
            results.append({"ip": dev.ip, "error": str(e)})
    _output(args, results)


def cmd_wifi_set(args: argparse.Namespace) -> None:
    if not args.ssid or not args.password:
        print("Error: --ssid and --password are required", file=sys.stderr)
        sys.exit(1)

    devices = resolve_targets(args)
    if args.dry_run:
        print(f"[DRY RUN] Would set WiFi on {len(devices)} device(s):")
        for dev in devices:
            print(f"  {dev.ip}: SSID='{args.ssid}'")
        return

    results = []
    for dev in devices:
        try:
            dev.probe()
            prev = dev.wifi_status()
            if dev.gen == 1:
                prev_ssid = prev.get("ssid", "")
            else:
                prev_ssid = prev.get("ssid", "")
            response = dev.wifi_set(args.ssid, args.password)
            results.append({
                "ip": dev.ip,
                "gen": dev.gen,
                "previous_ssid": prev_ssid,
                "new_ssid": args.ssid,
                "response": response,
            })
        except ConnectionError as e:
            results.append({"ip": dev.ip, "error": str(e)})
    _output(args, results)


def cmd_wifi_rotate(args: argparse.Namespace) -> None:
    if not args.ssid or not args.password:
        print("Error: --ssid and --password are required", file=sys.stderr)
        sys.exit(1)

    # Load or discover devices
    state_file = args.state_file
    devices_data: list[dict[str, Any]] = []
    if state_file and os.path.exists(state_file):
        with open(state_file) as f:
            devices_data = json.load(f)
        print(f"Loaded {len(devices_data)} devices from state file: {state_file}", file=sys.stderr)
    else:
        devices_data = discover(
            scan_cidr=args.scan,
            use_mdns=getattr(args, "mdns", True),
        )
        if state_file:
            with open(state_file, "w") as f:
                json.dump(devices_data, f, indent=2)
            print(f"Saved {len(devices_data)} devices to state file: {state_file}", file=sys.stderr)

    if not devices_data:
        print("No devices found", file=sys.stderr)
        sys.exit(1)

    # Construct device objects
    device_auth = load_device_auth(getattr(args, "device_auth", None))
    timeout = getattr(args, "timeout", DEFAULT_TIMEOUT)
    user = getattr(args, "user", None)
    password = getattr(args, "password", None)
    devices = [make_device(d["ip"], user=user, password=password,
                          device_auth=device_auth, timeout=timeout) for d in devices_data]

    # Handle rollback
    if getattr(args, "rollback", False):
        _wifi_rollback(devices, devices_data, args)
        return

    # Dry-run
    if args.dry_run:
        print(f"[DRY RUN] Would rotate WiFi on {len(devices)} device(s):", file=sys.stderr)
        for dev in devices:
            try:
                dev.probe()
                status = dev.wifi_status()
                cur_ssid = status.get("ssid", "?")
                print(f"  {dev.ip} (gen {dev.gen}): {cur_ssid} → {args.ssid}", file=sys.stderr)
            except ConnectionError:
                print(f"  {dev.ip}: UNREACHABLE", file=sys.stderr)
        return

    _wifi_rotate_execute(devices, devices_data, args)


def _wifi_rotate_execute(devices: list[ShellyDevice], devices_data: list[dict[str, Any]],
                         args: argparse.Namespace) -> None:
    """Execute WiFi rotation: snapshot, update, verify."""
    results: list[dict[str, Any]] = []
    batch_delay = args.batch_delay if hasattr(args, 'batch_delay') else DEFAULT_BATCH_DELAY
    reconnect_timeout = args.reconnect_timeout if hasattr(args, 'reconnect_timeout') else DEFAULT_RECONNECT_TIMEOUT
    failure_threshold = args.failure_threshold if hasattr(args, 'failure_threshold') else 0

    # Phase 1: Snapshot current config
    snapshots: dict[str, dict] = {}
    for dev in devices:
        try:
            dev.probe()
            snapshots[dev.ip] = {
                "mac": dev.info.get("mac"),
                "previous_ssid": dev.wifi_status().get("ssid", ""),
            }
        except ConnectionError:
            results.append({"ip": dev.ip, "status": "unreachable_pre", "error": "Device unreachable before rotation"})
            snapshots[dev.ip] = {"mac": devices_data[0].get("mac") if devices_data else None, "previous_ssid": None}

    if failure_threshold > 0:
        pre_failures = [r for r in results if r.get("status") == "unreachable_pre"]
        if len(pre_failures) > failure_threshold:
            print(f"Aborting: {len(pre_failures)} devices unreachable (threshold: {failure_threshold})", file=sys.stderr)
            _output(args, results)
            sys.exit(1)

    # Update state file with snapshots
    state_file = args.state_file
    if state_file:
        for dd in devices_data:
            dd["_snapshot"] = snapshots.get(dd["ip"], {})
        with open(state_file, "w") as f:
            json.dump(devices_data, f, indent=2)

    # Phase 2: Apply changes
    updated_devices: list[ShellyDevice] = []
    for i, dev in enumerate(devices):
        if dev.ip in [r["ip"] for r in results]:
            continue  # Already failed in pre-check
        try:
            response = dev.wifi_set(args.ssid, args.password)
            results.append({
                "ip": dev.ip,
                "status": "updated",
                "previous_ssid": snapshots[dev.ip].get("previous_ssid"),
                "new_ssid": args.ssid,
                "response": response,
            })
            updated_devices.append(dev)
        except ConnectionError as e:
            results.append({"ip": dev.ip, "status": "update_failed", "error": str(e)})

        if i < len(devices) - 1 and batch_delay > 0:
            time.sleep(batch_delay)

    # Phase 3: Poll for reconnection
    if updated_devices:
        deadline = time.time() + reconnect_timeout
        pending = set(dev.ip for dev in updated_devices)
        mac_map = {dev.ip: snapshots[dev.ip].get("mac") for dev in updated_devices}

        while pending and time.time() < deadline:
            time.sleep(5)
            reconnected = set()
            # Re-discover to find devices at possibly new IPs
            current_devices = discover(
                scan_cidr=args.scan if hasattr(args, 'scan') else None,
                use_mdns=getattr(args, 'mdns', True),
                timeout=5,
            )
            current_macs = {d.get("mac"): d["ip"] for d in current_devices if d.get("mac")}

            for original_ip in pending:
                mac = mac_map.get(original_ip)
                if mac and mac in current_macs:
                    new_ip = current_macs[mac]
                    for r in results:
                        if r.get("ip") == original_ip:
                            r["status"] = "reconnected"
                            r["new_ip"] = new_ip
                            break
                    reconnected.add(original_ip)

            pending -= reconnected

        for original_ip in pending:
            for r in results:
                if r.get("ip") == original_ip and r.get("status") == "updated":
                    r["status"] = "reconnect_timeout"

    _output(args, results)


def _wifi_rollback(devices: list[ShellyDevice], devices_data: list[dict[str, Any]],
                   args: argparse.Namespace) -> None:
    """Roll back devices to their previous WiFi config from state file."""
    results = []
    for dev in devices:
        snapshot = None
        for dd in devices_data:
            if dd.get("ip") == dev.ip:
                snapshot = dd.get("_snapshot", {})
                break
        previous_ssid = snapshot.get("previous_ssid") if snapshot else None
        if not previous_ssid:
            results.append({"ip": dev.ip, "status": "no_snapshot", "error": "No previous SSID in state file"})
            continue

        try:
            dev.probe()
            dev.wifi_set(previous_ssid, args.password)  # password from args (assumed old password)
            results.append({"ip": dev.ip, "status": "rolled_back", "ssid": previous_ssid})
        except ConnectionError as e:
            results.append({"ip": dev.ip, "status": "rollback_failed", "error": str(e)})
    _output(args, results)


def cmd_switch_get(args: argparse.Namespace) -> None:
    results = []
    for dev in resolve_targets(args):
        try:
            dev.probe()
            status = dev.switch_status(args.id)
            results.append({"ip": dev.ip, "gen": dev.gen, "channel": args.id, **status})
        except ConnectionError as e:
            results.append({"ip": dev.ip, "error": str(e)})
    _output(args, results)


def cmd_switch_set(args: argparse.Namespace) -> None:
    state = args.state.lower()
    if state not in ("on", "off", "toggle"):
        print("Error: state must be on, off, or toggle", file=sys.stderr)
        sys.exit(1)

    devices = resolve_targets(args)
    if args.dry_run:
        print(f"[DRY RUN] Would set switch on {len(devices)} device(s): {state}", file=sys.stderr)
        return

    results = []
    for dev in devices:
        try:
            dev.probe()
            if state == "toggle":
                response = dev.switch_toggle(args.id)
            else:
                response = dev.switch_set(args.id, state == "on")
            results.append({"ip": dev.ip, "gen": dev.gen, "channel": args.id, "action": state, "response": response})
        except ConnectionError as e:
            results.append({"ip": dev.ip, "error": str(e)})
    _output(args, results)


def cmd_light_get(args: argparse.Namespace) -> None:
    results = []
    for dev in resolve_targets(args):
        try:
            dev.probe()
            status = dev.light_status(args.id)
            results.append({"ip": dev.ip, "gen": dev.gen, "channel": args.id, **status})
        except ConnectionError as e:
            results.append({"ip": dev.ip, "error": str(e)})
    _output(args, results)


def cmd_light_set(args: argparse.Namespace) -> None:
    devices = resolve_targets(args)

    on: Optional[bool] = None
    if args.light_state == "on":
        on = True
    elif args.light_state == "off":
        on = False

    red, green, blue = None, None, None
    if args.color:
        parts = args.color.split(",")
        if len(parts) == 3:
            red, green, blue = int(parts[0]), int(parts[1]), int(parts[2])

    white = True if args.white else None

    if args.dry_run:
        desc = f"light_state={args.light_state}"
        if args.brightness is not None:
            desc += f", brightness={args.brightness}"
        if args.color:
            desc += f", color={args.color}"
        if args.temp is not None:
            desc += f", temp={args.temp}K"
        print(f"[DRY RUN] Would set light on {len(devices)} device(s): {desc}", file=sys.stderr)
        return

    results = []
    for dev in devices:
        try:
            dev.probe()
            response = dev.light_set(
                channel=args.id,
                on=on,
                brightness=args.brightness if args.brightness is not None else None,
                red=red, green=green, blue=blue,
                white=white,
                temp=args.temp if args.temp is not None else None,
            )
            results.append({"ip": dev.ip, "gen": dev.gen, "channel": args.id, "response": response})
        except ConnectionError as e:
            results.append({"ip": dev.ip, "error": str(e)})
    _output(args, results)


# ---------------------------------------------------------------------------
# Output formatting
# ---------------------------------------------------------------------------

def _output(args: argparse.Namespace, data: Any) -> None:
    fmt = getattr(args, "format", "json")
    if fmt == "table":
        _output_table(data)
    else:
        print(json.dumps(data, indent=2, default=str))


def _output_table(data: Any) -> None:
    """Simple columnar output for lists of dicts."""
    if isinstance(data, list) and all(isinstance(d, dict) for d in data):
        if not data:
            return
        keys = list(data[0].keys())
        cols = max(len(k) for k in keys)
        for row in data:
            for k in keys:
                val = row.get(k, "")
                if isinstance(val, dict):
                    val = json.dumps(val)
                print(f"  {k:<{cols}} : {val}")
            print()
    else:
        print(json.dumps(data, indent=2, default=str))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Shelly Device Manager — discover and control Shelly WiFi IoT devices.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--user", help="Device username (default: admin)")
    parser.add_argument("--password", help="Device password")
    parser.add_argument("--device-auth", help="JSON file mapping IPs to {user, pass}")
    parser.add_argument("--op-env-file", help="Path to .env.op file with op:// references")
    parser.add_argument("--op-cache-dir", default=os.path.expanduser("~/.cache/shelly-op/"),
                        help="Cache directory for resolved secrets")
    parser.add_argument("--op-cache-ttl", type=int, default=DEFAULT_CACHE_TTL,
                        help="Cache TTL in seconds")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT, help="HTTP request timeout (seconds)")
    parser.add_argument("--dry-run", action="store_true", help="Show what would happen without changes")
    parser.add_argument("--format", choices=["json", "table"], default="json",
                        help="Output format (default: json)")

    sub = parser.add_subparsers(dest="command", required=True)

    # --- discover ---
    p_discover = sub.add_parser("discover", help="Find all Shelly devices on the LAN")
    p_discover.add_argument("--scan", help="CIDR range to scan (e.g., 192.168.1.0/24)")
    p_discover.add_argument("--mdns", action="store_true", default=True, help="Use mDNS discovery (default)")
    p_discover.add_argument("--no-mdns", action="store_false", dest="mdns", help="Skip mDNS")
    p_discover.add_argument("--workers", type=int, default=50, help="Concurrent scan workers")
    p_discover.set_defaults(func=cmd_discover)

    # --- info ---
    p_info = sub.add_parser("info", help="Dump full device identity and status")
    p_info.add_argument("--host", required=True, help="Target device IP")
    p_info.set_defaults(func=cmd_info)

    # --- wifi get ---
    p_wifi_get = sub.add_parser("wifi", help="WiFi management").add_subparsers(dest="wifi_command")
    p_wifi_get_get = p_wifi_get.add_parser("get", help="Show current WiFi config")
    p_wifi_get_get.add_argument("--host")
    p_wifi_get_get.add_argument("--all", action="store_true")
    p_wifi_get_get.set_defaults(func=cmd_wifi_get)

    # --- wifi set ---
    p_wifi_set = p_wifi_get.add_parser("set", help="Change SSID/password")
    p_wifi_set.add_argument("--host")
    p_wifi_set.add_argument("--all", action="store_true")
    p_wifi_set.add_argument("--ssid", required=True, help="New WiFi SSID")
    p_wifi_set.add_argument("--password", required=True, help="New WiFi password")
    p_wifi_set.set_defaults(func=cmd_wifi_set)

    # --- wifi rotate ---
    p_wifi_rotate = p_wifi_get.add_parser("rotate", help="Bulk WiFi password rotation")
    p_wifi_rotate.add_argument("--ssid", required=True, help="New WiFi SSID")
    p_wifi_rotate.add_argument("--password", required=True, help="New WiFi password")
    p_wifi_rotate.add_argument("--state-file", help="Save/restore device snapshot (JSON)")
    p_wifi_rotate.add_argument("--batch-delay", type=float, default=DEFAULT_BATCH_DELAY,
                               help="Delay between device updates in seconds")
    p_wifi_rotate.add_argument("--reconnect-timeout", type=int, default=DEFAULT_RECONNECT_TIMEOUT,
                               help="Max seconds to wait for reconnect")
    p_wifi_rotate.add_argument("--failure-threshold", type=int, default=0,
                               help="Abort if more than N devices unreachable pre-rotation")
    p_wifi_rotate.add_argument("--rollback", action="store_true",
                               help="Roll back to previous config from state file")
    p_wifi_rotate.add_argument("--scan", help="CIDR range for discovery")
    p_wifi_rotate.add_argument("--mdns", action="store_true", default=True)
    p_wifi_rotate.add_argument("--no-mdns", action="store_false", dest="mdns")
    p_wifi_rotate.set_defaults(func=cmd_wifi_rotate, wifi_command="rotate")

    # --- switch get ---
    p_switch = sub.add_parser("switch", help="Relay/switch management").add_subparsers(dest="switch_command")
    p_switch_get = p_switch.add_parser("get", help="Read switch state")
    p_switch_get.add_argument("--host")
    p_switch_get.add_argument("--all", action="store_true")
    p_switch_get.add_argument("--id", type=int, default=0, help="Channel/relay index")
    p_switch_get.set_defaults(func=cmd_switch_get)

    # --- switch set ---
    p_switch_set = p_switch.add_parser("set", help="Set switch state")
    p_switch_set.add_argument("--host")
    p_switch_set.add_argument("--all", action="store_true")
    p_switch_set.add_argument("state", help="on, off, or toggle")
    p_switch_set.add_argument("--id", type=int, default=0, help="Channel/relay index")
    p_switch_set.set_defaults(func=cmd_switch_set)

    # --- light get ---
    p_light = sub.add_parser("light", help="Lighting management").add_subparsers(dest="light_command")
    p_light_get = p_light.add_parser("get", help="Read light state")
    p_light_get.add_argument("--host")
    p_light_get.add_argument("--all", action="store_true")
    p_light_get.add_argument("--id", type=int, default=0, help="Light channel")
    p_light_get.set_defaults(func=cmd_light_get)

    # --- light set ---
    p_light_set = p_light.add_parser("set", help="Set light color/brightness/temperature")
    p_light_set.add_argument("--host")
    p_light_set.add_argument("--all", action="store_true")
    p_light_set.add_argument("light_state", nargs="?", default=None,
                             help="on or off (omit to leave unchanged)")
    p_light_set.add_argument("--id", type=int, default=0, help="Light channel")
    p_light_set.add_argument("--color", help="RGB as R,G,B (e.g., 255,128,0)")
    p_light_set.add_argument("--white", action="store_true", help="Use white mode")
    p_light_set.add_argument("--brightness", type=int, help="Brightness 0-100")
    p_light_set.add_argument("--temp", type=int, help="White temperature in Kelvin (e.g., 2700, 4000, 6500)")
    p_light_set.set_defaults(func=cmd_light_set)

    args = parser.parse_args()

    # Resolve 1Password if needed
    op_env_file = args.__dict__.pop("op_env_file", None) or os.environ.get("SHELLY_OP_ENV_FILE")
    if op_env_file:
        op_cache_dir = args.__dict__.pop("op_cache_dir", None) or os.environ.get("SHELLY_OP_CACHE_DIR",
                                                                                   os.path.expanduser("~/.cache/shelly-op/"))
        op_cache_ttl = args.__dict__.pop("op_cache_ttl", None) or int(
            os.environ.get("SHELLY_OP_CACHE_TTL", str(DEFAULT_CACHE_TTL)))
        resolved = resolve_op_env(op_env_file, op_cache_dir, op_cache_ttl)
        # Apply to args
        if not args.user:
            args.user = resolved.get("SHELLY_USER", "admin")
        if not args.password:
            args.password = resolved.get("SHELLY_PASSWORD")
        if not getattr(args, "scan", None):
            args.scan = resolved.get("SHELLY_SCAN_CIDR")

    args.func(args)


if __name__ == "__main__":
    main()