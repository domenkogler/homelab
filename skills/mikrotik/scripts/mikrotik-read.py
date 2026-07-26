#!/usr/bin/env python3
"""
MikroTik RouterOS Configuration Reader

Reads one or more RouterOS API paths and outputs them as JSON.
Uses the routeros-api library for connectivity.

Usage:
    python mikrotik-read.py --host 10.0.0.1 --user apiuser --password secret /ip/firewall/filter

Environment variables:
    MIKROTIK_HOST, MIKROTIK_USER, MIKROTIK_PASSWORD, MIKROTIK_PORT, MIKROTIK_TIMEOUT
"""

import argparse
import json
import os
import sys
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

    # Validate required options
    missing = []
    if not args.host:
        missing.append("--host or $MIKROTIK_HOST")
    if not args.user:
        missing.append("--user or $MIKROTIK_USER")
    if not args.password:
        missing.append("--password or $MIKROTIK_PASSWORD")
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
