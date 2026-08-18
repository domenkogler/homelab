#!/usr/bin/env python3
"""Generate a bcrypt htpasswd line for Prometheus `--web.config.file` (HD-59).

Prometheus's `basic_auth_users` REQUIRES bcrypt-hashed passwords. This helper emits
`user:bcrypt` for a given username + password so you can seed the web-config secret
(external_secrets / 1Password `prometheus-internal_api`) without hand-rolling bcrypt.

Usage:
    python scripts/gen-htpasswd.py USERNAME        # prompts for password on STDIN
    python scripts/gen-htpasswd.py USERNAME PASSWORD

The bcrypt cost factor is fixed at 12 (Prometheus's documented default). Output is a
single line — paste it into the htpasswd secret. Never commit the password or the
generated hash to the repo (secrets live in 1Password `Homelab` only).
"""
import getpass
import sys
from pathlib import Path

# Try bcrypt from a number of common installs (PIP `bcrypt`, `passlib`[bcrypt]).
try:
    import bcrypt  # type: ignore
except ImportError:  # pragma: no cover - env dependent
    sys.stderr.write(
        "error: the `bcrypt` module is required.\n"
        "  pip install bcrypt   (on the host that generates the hash)\n"
    )
    sys.exit(2)


def main() -> int:
    if len(sys.argv) not in (2, 3):
        sys.stderr.write("usage: gen-htpasswd.py USERNAME [PASSWORD]\n")
        return 2

    username = sys.argv[1]
    if not username:
        sys.stderr.write("error: username must not be empty\n")
        return 2

    password = sys.argv[2] if len(sys.argv) == 3 else getpass.getpass("Password: ")
    if not password:
        sys.stderr.write("error: password must not be empty\n")
        return 2

    salt = bcrypt.gensalt(rounds=12)
    hashed = bcrypt.hashpw(password.encode("utf-8"), salt).decode("ascii")
    # NOTE (security): printing the hash is implementation detail (for pasting into the
    # secret store), not a secret leak — bcrypt hashes are one-way.
    print(f"{username}:{hashed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())