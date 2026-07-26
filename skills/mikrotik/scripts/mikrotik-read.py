#!/usr/bin/env python3
"""
MikroTik RouterOS Configuration Reader

Reads one or more RouterOS API paths and outputs them as JSON.
Uses the routeros-api library for connectivity.

Usage:
    python mikrotik-read.py --host 10.0.0.1 --user apiuser --password secret /ip/firewall/filter

Environment variables:
    MIKROTIK_HOST, MIKROTIK_USER, MIKROTIK_PASSWORD, MIKROTIK_PORT, MIKROTIK_TIMEOUT,
    MIKROTIK_OP_ENV_FILE, MIKROTIK_OP_CACHE_DIR, MIKROTIK_OP_CACHE_TTL

Use --op-env-file to point to an .env.op file with op:// references. The script
resolves ALL secrets in a single `op run --no-masking` call internally and caches
them, so you typically get a confirmation prompt only once per session.
"""

import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
from typing import Any

try:
    import routeros_api
except ImportError:
    print(
        "Error: The 'routeros-api' library is not installed.\n"
        "Install it with: pip install routeros-api",
        file=sys.stderr,
    )
    sys.exit(1)


DEFAULT_CACHE_TTL = 28800  # 8 hours — covers a full work session


def _cache_path(env_file_path: str, cache_dir: str) -> str:
    """Return the cache file path for a given .env.op file."""
    abs_path = os.path.abspath(env_file_path)
    key = hashlib.sha256(abs_path.encode("utf-8")).hexdigest()[:16]
    return os.path.join(cache_dir, f"{key}.env")


def _read_cache(cache_path: str, env_file_path: str, ttl: int) -> dict[str, str] | None:
    """Read cached resolved secrets if still valid.

    Returns None if cache is missing, expired, or the source file changed.
    """
    try:
        cache_mtime = os.path.getmtime(cache_path)
        source_mtime = os.path.getmtime(env_file_path)
    except FileNotFoundError:
        return None

    now = time.time()
    if now - cache_mtime > ttl:
        return None  # cache expired

    resolved: dict[str, str] = {}
    with open(cache_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("# source-mtime:"):
                cached_source_mtime = float(line.split(":", 1)[1].strip())
                if cached_source_mtime != source_mtime:
                    return None  # source file changed
                continue
            if "=" in line:
                key, _, encoded = line.partition("=")
                try:
                    value = base64.b64decode(encoded.strip()).decode("utf-8")
                    resolved[key.strip()] = value
                except Exception:
                    return None  # corrupt cache entry

    return resolved if resolved else None


def _write_cache(cache_path: str, env_file_path: str, resolved: dict[str, str]) -> None:
    """Write resolved secrets to cache (base64-encoded)."""
    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
    source_mtime = os.path.getmtime(env_file_path)
    with open(cache_path, "w") as f:
        f.write(f"# source-mtime: {source_mtime}\n")
        f.write(f"# created: {time.time()}\n")
        for key, value in resolved.items():
            encoded = base64.b64encode(value.encode("utf-8")).decode("ascii")
            f.write(f"{key}={encoded}\n")
    # Restrict permissions to owner only
    try:
        os.chmod(cache_path, 0o600)
    except OSError:
        pass


def resolve_op_env_file(
    env_file_path: str,
    cache_dir: str | None = None,
    cache_ttl: int = DEFAULT_CACHE_TTL,
) -> dict[str, str]:
    """Resolve all op:// references in an env file, using cache if possible.

    Tries cache first. On miss, runs `op run --no-masking --env-file=<file> -- printenv`
    and caches the result for subsequent calls.

    Args:
        env_file_path: Path to the .env.op file.
        cache_dir: Directory for caching resolved secrets (None = use default).
        cache_ttl: Cache time-to-live in seconds.

    Returns:
        Dict of resolved environment variables (only keys from the env file).
    """
    if cache_dir is None:
        cache_dir = os.path.join(
            os.environ.get("HOME") or os.environ.get("USERPROFILE") or tempfile.gettempdir(),
            ".cache",
            "mikrotik-op",
        )

    # Read the env file to know which variables to expect
    var_names: list[str] = []
    try:
        with open(env_file_path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    key = line.split("=", 1)[0].strip()
                    if key:
                        var_names.append(key)
    except FileNotFoundError:
        print(f"Error: Env file not found: '{env_file_path}'", file=sys.stderr)
        return {}

    if not var_names:
        print(f"Error: No variable assignments found in '{env_file_path}'", file=sys.stderr)
        return {}

    # Try cache first
    cache_path = _cache_path(env_file_path, cache_dir)
    cached = _read_cache(cache_path, env_file_path, cache_ttl)
    if cached is not None:
        return cached

    # Cache miss — resolve via op run
    try:
        result = subprocess.run(
            ["op", "run", "--no-masking", "--env-file", env_file_path, "--", "printenv"],
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        )
    except FileNotFoundError:
        print(
            "Error: The 'op' CLI is not installed or not on PATH. "
            "Install it from https://developer.1password.com/docs/cli/get-started/",
            file=sys.stderr,
        )
        return {}
    except subprocess.CalledProcessError as e:
        print(f"Error: 'op run' failed: {e.stderr.strip()}", file=sys.stderr)
        return {}
    except subprocess.TimeoutExpired:
        print("Error: 'op run' timed out after 30 seconds.", file=sys.stderr)
        return {}

    # Parse the resolved variables
    var_set = set(var_names)
    resolved: dict[str, str] = {}
    for line in result.stdout.strip().split("\n"):
        if "=" in line:
            key, _, value = line.partition("=")
            if key in var_set:
                resolved[key] = value

    # Cache for next time
    if resolved:
        _write_cache(cache_path, env_file_path, resolved)

    return resolved


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Read MikroTik RouterOS configuration paths via the API.",
        epilog=(
            "Examples:\n"
            "  %(prog)s --host 10.0.0.1 --user admin --password pwd /ip/address\n"
            "  %(prog)s /ip/firewall/filter /ip/route /system/identity\n"
            "  %(prog)s /ip/address --query interface=bridge\n"
            "  %(prog)s /interface/bridge/port --indent 0\n"
            "  %(prog)s --op-env-file skills/mikrotik/.env.op /ip/address\n"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    # Connection options
    parser.add_argument(
        "--host",
        default=os.environ.get("MIKROTIK_HOST", ""),
        help="Router hostname or IP (default: $MIKROTIK_HOST)",
    )
    parser.add_argument(
        "--user",
        default=os.environ.get("MIKROTIK_USER", ""),
        help="API username (default: $MIKROTIK_USER)",
    )
    parser.add_argument(
        "--password",
        default=os.environ.get("MIKROTIK_PASSWORD", ""),
        help="API password (default: $MIKROTIK_PASSWORD)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("MIKROTIK_PORT", "8728")),
        help="API port (default: 8728, or $MIKROTIK_PORT)",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=int(os.environ.get("MIKROTIK_TIMEOUT", "10")),
        help="Connection timeout in seconds (default: 10, or $MIKROTIK_TIMEOUT)",
    )
    parser.add_argument(
        "--plaintext-login",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Use plaintext login (default: True; required for RouterOS v6+)",
    )
    parser.add_argument(
        "--use-ssl",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Connect via SSL/TLS (API-SSL port 8729, default: False)",
    )
    parser.add_argument(
        "--ssl-verify",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Verify SSL certificate (default: True)",
    )

    # 1Password integration (resolved before password validation)
    parser.add_argument(
        "--op-env-file",
        default=os.environ.get("MIKROTIK_OP_ENV_FILE", ""),
        help="Path to an .env.op file with op:// references. The script resolves ALL "
             "secrets in a single `op run --no-masking` call and caches them. "
             "Overrides --host/--user/--password. (default: $MIKROTIK_OP_ENV_FILE)",
    )
    parser.add_argument(
        "--op-cache-dir",
        default=os.environ.get("MIKROTIK_OP_CACHE_DIR", ""),
        help="Directory for caching resolved 1Password secrets "
             "(default: ~/.cache/mikrotik-op/ or $MIKROTIK_OP_CACHE_DIR)",
    )
    parser.add_argument(
        "--op-cache-ttl",
        type=int,
        default=int(os.environ.get("MIKROTIK_OP_CACHE_TTL", str(DEFAULT_CACHE_TTL))),
        help=f"Cache TTL in seconds (default: {DEFAULT_CACHE_TTL}, or $MIKROTIK_OP_CACHE_TTL)",
    )

    # Query / output options
    parser.add_argument(
        "--query",
        action="append",
        default=[],
        dest="queries",
        help="Optional filter, e.g. 'name=ether1'. Repeat for multiple filters.",
    )
    parser.add_argument(
        "--indent",
        type=lambda v: None if v.lower() == "none" else int(v),
        default=2,
        help="JSON indentation level (default: 2; use 0 for compact, 'none' for no indent)",
    )

    # Positional paths
    parser.add_argument(
        "paths",
        nargs="+",
        help="One or more RouterOS API paths, e.g. /ip/address /ip/firewall/filter",
    )

    args = parser.parse_args(argv)

    # Resolve --op-env-file if provided (with caching, single op run on cache miss)
    if args.op_env_file:
        cache_dir = args.op_cache_dir or None
        resolved = resolve_op_env_file(args.op_env_file, cache_dir, args.op_cache_ttl)
        if not resolved:
            parser.error(f"Failed to resolve 1Password secrets from '{args.op_env_file}'")
        # Apply resolved values, overriding any CLI/env values
        for key, value in resolved.items():
            if key == "MIKROTIK_HOST":
                args.host = value
            elif key == "MIKROTIK_USER":
                args.user = value
            elif key == "MIKROTIK_PASSWORD":
                args.password = value
            elif key == "MIKROTIK_PORT":
                args.port = int(value)
            elif key == "MIKROTIK_TIMEOUT":
                args.timeout = int(value)

    # Validate required options
    missing = []
    if not args.host:
        missing.append("--host or $MIKROTIK_HOST")
    if not args.user:
        missing.append("--user or $MIKROTIK_USER")
    if not args.password:
        missing.append("--password, $MIKROTIK_PASSWORD, or --op-env-file ($MIKROTIK_OP_ENV_FILE)")
    if missing:
        parser.error(f"Missing required connection details: {', '.join(missing)}")

    return args


def parse_query_filters(queries: list[str]) -> list[tuple[str, str]]:
    """Parse --query key=value arguments into a list of (key, value) tuples.

    Supports operators beyond equality by splitting on the first '=' or
    '~' character.
    """
    filters: list[tuple[str, str]] = []
    for q in queries:
        if "=" in q:
            key, _, value = q.partition("=")
            filters.append((key.strip(), value.strip()))
        elif "~" in q:
            key, _, value = q.partition("~")
            filters.append((key.strip(), value.strip()))
        else:
            print(f"Warning: Skipping malformed query '{q}' (expected key=value)", file=sys.stderr)
    return filters


def connect(args: argparse.Namespace) -> routeros_api.RouterOsApiPool:
    """Create and return an authenticated connection pool to the router."""
    pool = routeros_api.RouterOsApiPool(
        args.host,
        username=args.user,
        password=args.password,
        port=args.port,
        plaintext_login=args.plaintext_login,
        use_ssl=args.use_ssl,
        ssl_verify=args.ssl_verify,
    )
    return pool


def read_path(
    api: routeros_api.RouterOsApiPool,
    path: str,
    filters: list[tuple[str, str]],
) -> list[dict[str, Any]]:
    """Read a single RouterOS API path and return parsed results.

    Args:
        api: An authenticated API connection.
        path: RouterOS path, e.g. '/ip/address' or '/system/identity'.
        filters: List of (key, value) tuples for query filtering.

    Returns:
        A list of dictionaries representing the returned resources.
    """
    # Normalize path: strip leading/trailing slashes
    clean_path = path.strip("/")

    # Get the resource
    resource = api.get_resource(clean_path)

    # Build parameters dict from filters
    params: dict[str, str | bool] = {}
    for key, value in filters:
        params[key] = value

    try:
        result = resource.get(**params) if params else resource.get()
    except routeros_api.exceptions.RouterOsApiCommunicationError as e:
        print(f"Error reading '{path}': {e}", file=sys.stderr)
        return []
    except Exception as e:
        print(f"Unexpected error reading '{path}': {e}", file=sys.stderr)
        return []

    # Convert result to plain Python list of dicts
    parsed: list[dict[str, Any]] = []
    for item in result:
        parsed.append(dict(item))

    return parsed


def format_output(data: dict[str, list[dict[str, Any]]], indent: int | None) -> str:
    """Format the output dictionary as JSON."""
    return json.dumps(data, indent=indent, default=str, ensure_ascii=False)


def main() -> None:
    """Main entry point."""
    args = parse_args()
    filters = parse_query_filters(args.queries)

    # Connect
    try:
        pool = connect(args)
    except routeros_api.exceptions.RouterOsApiConnectionError as e:
        print(f"Connection failed: {e}", file=sys.stderr)
        sys.exit(1)
    except routeros_api.exceptions.RouterOsApiError as e:
        print(f"Login failed: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected connection error: {e}", file=sys.stderr)
        sys.exit(1)

    api = pool.get_api()

    # Read all requested paths
    results: dict[str, list[dict[str, Any]]] = {}
    for path in args.paths:
        entries = read_path(api, path, filters)
        results[path] = entries

    # Disconnect
    pool.disconnect()

    # Output JSON
    output = format_output(results, indent=args.indent)
    print(output)


if __name__ == "__main__":
    main()