#!/usr/bin/env python3
"""Lint: every vault item the IaC reads is documented in the secrets master list.

`docs/deployment-secrets.md` §Master Secret List is the human-facing catalog a from-zero deployer
works from: the runbook tells them to seed what §1.1/§P3.1 lists, and `check-vault-items.sh`
answers "does the vault HAVE it". Neither answers the other question — **"is the item written
down anywhere?"** — and the answer was silently wrong for five items (`technitium_login` among
them: a hard gate whose absence fails the very first DNS seed of a true-zero rebuild).

The check derives the required set from the IaC itself, not from a hand-kept list:
  * every `lookup('community.general.onepassword', '<item>' ...)` in the playbooks/roles,
  * every item named in `roles/docker_services/defaults/main.yml` `_service_vault_items`
    (declared-but-unconsumed entries count too — a scanner-required item has to be documented
    even if no task reads it yet; the doc row is where that oddity gets explained), and
  * every `*_item:` registry-key scalar in BOTH `host_vars/` and `group_vars/` (HD-1157): an item
    reached through a VARIABLE appears in no template, so a `group_vars`-only item was optional —
    deleting its doc row kept the gate green while the deploy lost the source of the value.

PRESENCE ALONE IS NOT THE CLAIM. A backticked item name travelling through the doc used to be the
whole proof, so the prose beside it was never read — and a row could state that its own item
`does not exist yet` while the gate printed OK over it (HD-1157). So the §Master Secret List table
is read row by row as well as searched: a `field=` cell must carry a field name, or DECLARE that
this item has no field here (a dash, optionally with the reason, optionally a pointer to the doc
that owns the fields). A cell that is prose or a state claim is a finding.

Run:   python3 scripts/gate/check_vault_docs.py [--root DIR] [--show]
       python3 scripts/gate/check_vault_docs.py --self-test
Exit:  0 = every referenced item is documented and every table row states its field shape;
      1 = undocumented item(s) or unreadable `field=` cell(s); 2 = the corpus is too small to
      trust.  Wired into validate-all.sh.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# HD-1118 Stage 1: FOUND, not assumed from a depth — scripts/lib/repo_root.py.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import require_corpus, root as _hl_root  # noqa: E402
ROOT_DEFAULT = _hl_root(__file__)
LOOKUP_RE = re.compile(r"onepassword['\"]\s*,\s*['\"]([a-z0-9_.-]+)['\"]")
LOOKUP_CALL_RE = re.compile(r"onepassword\(\s*['\"]([a-z0-9_.-]+)['\"]")
# `*_item:` scalars — the registry-key class, consumed through a variable so no template carries a
# literal lookup. Same rule in host_vars and group_vars; a comment line is prose, not a dependency.
ITEM_KEY_RE = re.compile(r"[A-Za-z0-9_]+_item:[ \t]*['\"]?([a-z0-9][a-z0-9_.-]+)['\"]?")
MASTER_HEADING = "## Master Secret List"
# What a `field=` cell must do: name a field, or declare that this item has no field here.
FIELD_CELL_TOKEN = re.compile(r"`([A-Za-z][A-Za-z0-9_ ]{1,})`")
# A state claim about the item instead of a field: the shape that hid a missing item behind its own
# row. Narrow on purpose — `not consumed by Ansible` and `not live` are facts about a real item.
STATE_CLAIM = re.compile(
    r"(?:does|do) not exist|doesn.t exist|never (?:created|seeded|minted|provisioned)|"
    r"not (?:yet )?(?:created|seeded|written|provisioned|minted|documented|implemented)"
    r"|to be (?:created|seeded|written|minted)|\bTBD\b|\bTODO\b",
    re.I)
# The declared no-field-here shape: a dash, an optional reason in parentheses, optional prose that
# points at the doc owning the fields. Anything else with no field name is prose.
DASH_DECLARED = re.compile(r"^\s*[\u2014\u2013-]\s*(?:\([^)]*\))?\s*$")
POINTS_TO_DOC = re.compile(r"\.md[)\]]|\.md\b|runbook", re.I)


def referenced_items(root: Path) -> dict[str, set[str]]:
    refs: dict[str, set[str]] = {}
    ansible = root / "IaC" / "ansible"
    for path in list(ansible.rglob("*.yml")) + list(ansible.rglob("*.j2")):
        text = path.read_text(encoding="utf-8", errors="ignore")
        for found in (LOOKUP_RE.findall(text) + LOOKUP_CALL_RE.findall(text)):
            refs.setdefault(found, set()).add(str(path.relative_to(root)))
    defaults = ansible / "roles" / "docker_services" / "defaults" / "main.yml"
    if defaults.exists():
        for line in defaults.read_text(encoding="utf-8").splitlines():
            for item in re.findall(r"'([a-z0-9_.-]+)'", line):
                if item.endswith(("_api", "_login", "_password", "_db")) and "<" not in item:
                    refs.setdefault(item, set()).add(f"{defaults.relative_to(root)} (registry)")
    # Registry-key class in host_vars:
    # a `*_item:` scalar whose value is an item NAME, consumed through a VARIABLE — so no
    # template contains a literal lookup and the pass above can never see it. Found here:
    # storage_samba_users[].vault_item (roles/storage, the NAS Samba logins) and
    # cockpit_maint_vault_item (roles/cockpit). Comment lines are skipped — naming an item in
    # prose is not a dependency. Same class, same rule as check-vault-items.sh.
    # HD-1157: BOTH variable scopes. `seat_pi_web_vault_item` lives in `group_vars/all/seat.yml`, so
    # a host_vars-only walk made an item named only in a group var optional.
    for scope in ("host_vars", "group_vars"):
        base = ansible / scope
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.yml")):
            for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
                if line.lstrip().startswith("#"):
                    continue
                for item in ITEM_KEY_RE.findall(line):
                    refs.setdefault(item, set()).add(f"{path.relative_to(root)} (registry)")
    return refs


def master_table(text: str) -> list[tuple[int, str, str]]:
    """[(line_no, item cell, field cell)] for the §Master Secret List table only — located by its
    `field=` header, not by a line number, and stopping at the first non-row line so a second table
    further down the section is not mistaken for an item row."""
    lines = text.splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.startswith(MASTER_HEADING))
    except StopIteration:
        return []
    rows: list[tuple[int, str, str]] = []
    header_seen = False
    for i in range(start, len(lines)):
        raw = lines[i]
        stripped = raw.strip()
        if stripped.startswith("|"):
            cells = re.split(r"(?<!\\)\|", stripped.strip("|"))
            if not header_seen:
                if len(cells) >= 2 and "field=" in cells[1]:
                    header_seen = True
                continue
            if set(stripped) <= set("|-: ") or len(cells) < 3:
                continue
            rows.append((i + 1, cells[0].strip(), cells[1].strip()))
        elif header_seen and not stripped:
            continue
        elif header_seen:
            break
    return rows


def field_cell_verdict(item_cell: str, field_cell: str) -> str:
    """'' when the cell states the field shape, else the finding text. Three shapes are legal: a
    field name (backticked, or an explicit `field=`), a dash that DECLARES there is no field here,
    and a pointer to the doc that owns the fields. A state claim is never legal — a row whose own
    item "does not exist yet" is a row that denies the item it documents."""
    m = STATE_CLAIM.search(field_cell)
    if m:
        return ("state claim in a `field=` cell — the row denies its own item "
                f"({m.group(0)!r})")
    if FIELD_CELL_TOKEN.search(field_cell) or "field=" in field_cell:
        return ""
    if DASH_DECLARED.match(field_cell) or POINTS_TO_DOC.search(field_cell):
        return ""
    return "`field=` cell is prose — no field name, no dash declaring there is no field here"


def check(root: Path, ref_floor: int = 20, row_floor: int = 60, show: bool = False) -> int:
    doc = root / "docs" / "deployment-secrets.md"
    if not doc.exists():
        print(f"FAIL: {doc} not found")
        return 1
    text = doc.read_text(encoding="utf-8")
    documented = set(re.findall(r"`([a-z0-9_.-]+)`", text))

    refs = referenced_items(root)
    missing = {k: v for k, v in refs.items() if k not in documented}
    rows = master_table(text)
    unreadable = []
    for line_no, item_cell, field_cell in rows:
        why = field_cell_verdict(item_cell, field_cell)
        if why:
            unreadable.append((line_no, item_cell, field_cell, why))

    if show:
        print(f"vault docs: {len(refs)} derived item(s), {len(rows)} table row(s), "
              f"{len(missing)} undocumented, {len(unreadable)} unreadable `field=` cell(s)")
        return 0

    if missing:
        print(f"FAIL: {len(missing)} vault item(s) consumed by the IaC but absent from "
              f"docs/deployment-secrets.md §Master Secret List:")
        for item in sorted(missing):
            where = sorted(missing[item])[:2]
            print(f"  - {item}  ({'; '.join(where)})")
        print("\nAdd a row per item: type, consumer, who seeds it, and whether it is a "
              "placeholder-then-swap or deploy-provisioned value.")
        return 1
    if unreadable:
        print(f"FAIL: {len(unreadable)} row(s) of §Master Secret List whose `field=` cell states a "
              "STATE or prose instead of a field — the item name proved presence, nobody read the "
              "sentence about it:")
        for line_no, item_cell, field_cell, why in unreadable:
            print(f"  - docs/deployment-secrets.md:{line_no} {item_cell[:48]} — {why}")
            print(f"      cell: {field_cell[:110]}")
        print("\nName the field (`password`, `credential`, `api`, `username`, …); when this item "
              "genuinely has no field here, say so with a dash and the reason, or point at the doc "
              "that owns the fields. A row that says the item does not exist is not documentation.")
        return 1
    require_corpus(len(refs), ref_floor, "check_vault_docs IaC vault-reference set")
    require_corpus(len(rows), row_floor, "check_vault_docs §Master Secret List rows")
    print(f"OK: all {len(refs)} IaC-referenced vault items are documented in "
          f"deployment-secrets.md, and all {len(rows)} §Master Secret List row(s) state their "
          "field shape")
    return 0


def self_test() -> int:
    """The arms this gate was missing: it must fail on a row that DENIES its own item, on a `field=`
    cell that is prose, and on an item named only in a `group_vars` `*_item:` scalar — and stay quiet
    on the shapes that are legitimately field-less. Built in a temp tree, so the assertions are about
    the reader and not about what this checkout documents today."""
    import tempfile

    fails = []

    def arm(name, cond, detail=""):
        print(f"  {'ok  ' if cond else 'FAIL'} {name}{'' if cond else ' -- ' + detail}")
        if not cond:
            fails.append(name)

    table_head = ("## Master Secret List (canonical)\n\n"
                  "| Item name | `field=` | Used By |\n|---|---|---|\n")
    clean_rows = ("| `good_api` | `password` | the consumer |\n"
                  "| `conn_ref` | \u2014 (connection ref) | account reference only |\n"
                  "| `pointer_api` | \u2014 | see [other doc](other-doc.md) |\n"
                  "| `grouponly_api` | `credential` | rendered through a group var |\n"
                  "| `hostonly_api` | `api` | rendered through a host var |\n")

    def build(extra_doc="", group_vars="seat_pi_web_vault_item: grouponly_api\n",
              host_vars="some_role_vault_item: hostonly_api\n", rows=clean_rows):
        tmp = Path(tempfile.mkdtemp(prefix="check-vault-docs-"))
        (tmp / "docs").mkdir(parents=True)
        (tmp / "IaC" / "ansible" / "group_vars" / "all").mkdir(parents=True)
        (tmp / "IaC" / "ansible" / "host_vars").mkdir(parents=True)
        (tmp / "docs" / "deployment-secrets.md").write_text(table_head + rows + extra_doc,
                                                             encoding="utf-8")
        (tmp / "IaC" / "ansible" / "group_vars" / "all" / "seat.yml").write_text(
            group_vars, encoding="utf-8")
        (tmp / "IaC" / "ansible" / "host_vars" / "host.k.example.yml").write_text(
            host_vars, encoding="utf-8")
        return tmp

    import io
    import contextlib

    def run(**kw):
        # Floors are 0 here: the fixture tree is deliberately tiny, and the empty-corpus arm below
        # asks the SAME function with real floors.
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = check(build(**kw), ref_floor=0, row_floor=0)
        return rc, buf.getvalue()

    rc, out = run()
    arm("clean fixture: every item documented, every cell states its shape", rc == 0, out.strip()[:200])

    rc, out = run(group_vars="seat_pi_web_vault_item: grouponly_api\nunlisted_vault_item: "
                              "never-documented_api\n")
    arm("the widening: an item named ONLY in a group_vars `*_item:` scalar is required, not "
        "optional — a doc that never mentions it reddens", rc == 1 and "never-documented_api" in out,
        out.strip()[:200])

    rc, out = run(group_vars="", host_vars="other_vault_item: hostonly_api\n")
    arm("the widening, other direction: with no group_vars reference the same item is not demanded "
        "(the set is derived, never hand-kept)", rc == 0, out.strip()[:200])

    rc, out = run(rows=clean_rows + "| `denied_api` | does not exist yet | nothing yet |\n"
                  "`denied_api`\n")
    arm("the state-word read: a row whose `field=` cell DENIES its own item reddens the presence "
        "gate (the shape the token-membership test could not see)",
        rc == 1 and "denies its own item" in out, out.strip()[:200])

    rc, out = run(rows=clean_rows + "| `prose_api` | the operator knows what to put here | x |\n"
                  "`prose_api`\n")
    arm("a `field=` cell that is prose is a finding", rc == 1 and "cell is prose" in out,
        out.strip()[:200])

    rc, out = run(rows="| `dash_api` | \u2014 | connection reference only |\n"
                       "| `link_api` | see [x](other-doc.md) | x |\n"
                       "| `explicit_api` | `credential` (not `api`) | x |\n"
                       "| `hostonly_api` | `api` | the host var |\n" +
                  "`dash_api` `link_api` `explicit_api`\n", group_vars="",
                  host_vars="other_vault_item: hostonly_api\n")
    arm("the declared shapes stay quiet: the dash, the pointer to the owning doc, the field name "
        "with a correction beside it", rc == 0, out.strip()[:200])

    rc, out = run(rows=clean_rows + "| `claim_api` | TBD | x |\n`claim_api`\n")
    arm("a `field=` cell that says TBD is a state claim, not a field", rc == 1 and
        "denies its own item" in out, out.strip()[:200])

    empty = Path(tempfile.mkdtemp(prefix="check-vault-docs-empty-"))
    (empty / "docs").mkdir(parents=True)
    (empty / "docs" / "deployment-secrets.md").write_text("nothing here\n", encoding="utf-8")
    try:
        rc = check(empty, ref_floor=20, row_floor=60)
        arm("an empty corpus fails loud, never OK", False, f"returned rc {rc}")
    except SystemExit as e:
        msg = str(getattr(e, "code", ""))
        arm("an empty corpus fails loud, never OK", "CORPUS FLOOR" in msg, msg[:120])

    print("self-test:", "FAILED" if fails else "OK")
    return 1 if fails else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(ROOT_DEFAULT))
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--show", action="store_true", help="counts only, no verdict")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    return check(Path(args.root).resolve(), show=args.show)


if __name__ == "__main__":
    sys.exit(main())
