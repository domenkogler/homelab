#!/usr/bin/env python3
"""HD-432: no whitespace inside a traefik Host() rule.

Why this exists
---------------
`traefik-internal/dynamic/routes.yml.j2` shipped, from 2026-09 until this file, as:

    rule: "Host(`ha. {{ tailnet_base_domain }} `) || Host(` {{ tailnet_oldsrv_node_name }} . {{ ... }} `)"

Jinja renders that faithfully, spaces and all, so the live rule was
`Host(`ha. ts.kogler.si `)`. A Host matcher with a space in the name can never match a
request, and traefik answers its default 404 — so `ha.ts.kogler.si` looked *deployed*
(extra_record published, entrypoint listening, backend pointing at the VIP) while being
structurally unable to serve a single byte. Nothing failed a converge, because a rule
that never matches is not an error to traefik, and nothing looked at the rendered string.

The bug class is template whitespace, not schema: `{{ x }}` next to a literal inside a
backtick is invisible in review and invisible to `--check`. So we look at the shape.

Rule: inside a Host(`...`) literal, every character that survives Jinja-expression
stripping must be hostname-safe. A whitespace character there is always a bug — no
hostname contains one, and a legitimate Jinja filter (`{{ sub | default('logs') }}`)
loses its spaces to the strip and so passes.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
TEMPLATE_ROOT = REPO / "IaC" / "ansible" / "templates"

# Host(`...`) — the backticked literal is what traefik matches byte-for-byte.
_HOST_RE = re.compile(r"Host\(\s*`([^`]*)`\s*\)")
# Jinja expressions are collapsed to a single non-space sentinel: their internal
# whitespace is template formatting, not rendered output.
_JINJA_RE = re.compile(r"\{\{.*?\}\}|\{%.*?%\}", re.S)
_SENTINEL = "X"

HOSTNAME_OK = re.compile(r"^[A-Za-z0-9.*!_-]+$")  # traefik host matchers incl. wildcards


def find_offenders(text: str) -> list[str]:
    """Return human-readable problems found in one rendered-or-template rule string."""
    out = []
    for raw in _HOST_RE.findall(text):
        collapsed = _JINJA_RE.sub(_SENTINEL, raw)
        if collapsed != collapsed.strip():
            out.append(f"leading/trailing whitespace in Host(`{raw}`)")
        elif re.search(r"\s", collapsed):
            out.append(f"whitespace inside Host(`{raw}`)")
        elif re.search(r"\{\{|\{%", collapsed) is None and not HOSTNAME_OK.match(collapsed or " "):
            out.append(f"not a valid hostname in Host(`{raw}`)")
    return out


def scan() -> list[str]:
    problems = []
    for path in sorted(TEMPLATE_ROOT.rglob("*")):
        if not path.is_file():
            continue
        if path.suffix not in {".j2", ".yml", ".yaml"}:
            continue
        try:
            text = path.read_text()
        except UnicodeDecodeError:
            continue
        if "Host(" not in text:
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue  # a comment may quote a broken rule to explain it
            for problem in find_offenders(line):
                problems.append(f"{path.relative_to(REPO)}:{lineno}: {problem}")
    return problems


# --- self-test: a check that cannot fail is not evidence -------------------
_CASES = [
    # (snippet, must_be_flagged)
    ("rule: \"Host(`ha. {{ tailnet_base_domain }} `) || …\"", True),   # the shipped bug
    ("rule: \"Host(` {{ node }}.{{ base }}`)", True),                   # leading space
    ("rule: \"Host(`a b.kogler.si`)", True),                            # bare space
    ("rule: \"Host(`{{ svc.subdomain | default('logs') }}.kogler.si`)", False),  # legit Jinja spacing
    ("rule: \"Host(`media.kogler.si`) || Host(`media.ts.kogler.si`)", False),
    ("rule: \"Host(`ha.{{ tailnet_base_domain }}`)", False),
    ("rule: \"HostRegexp(`^{any:.+}$`)\"", False),                       # not a Host()
]


def self_test() -> int:
    failures = 0
    for snippet, must_flag in _CASES:
        flagged = bool(find_offenders(snippet))
        ok = flagged is must_flag
        print(f"  {'OK  ' if ok else 'FAIL'} expected={'flag' if must_flag else 'pass '} "
              f"got={'flag' if flagged else 'pass '} :: {snippet[:72]}")
        failures += 0 if ok else 1
    print(f"check_traefik_host_rules self-test: {len(_CASES) - failures}/{len(_CASES)} cases green")
    return 1 if failures else 0


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()
    problems = scan()
    if problems:
        print("ERROR: traefik Host() rules that cannot match (HD-432 whitespace class):")
        for p in problems:
            print(f"  {p}")
        print("  A Host matcher is compared byte-for-byte: one stray space and the router")
        print("  silently serves nothing while every deploy reports success.")
        return 1
    print("OK: no whitespace inside any Host() rule")
    return 0


if __name__ == "__main__":
    sys.exit(main())
