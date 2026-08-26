#!/usr/bin/env python3
"""
op-vault-export.py — HD-258 bulk 1Password pre-pass helper.

Reads a list of 1Password item NAMES (one per line on stdin) and emits a single
JSON object to stdout:

    { "<item>": {"username":…, "password":…, "credential":…, "bcrypt_hash":…},
      … }

using exactly ONE `op item get --reveal --format=json` process per item (the
control node's `op` CLI, authenticated via OP_SERVICE_ACCOUNT_TOKEN). This
replaces the ~160 per-template `community.general.onepassword` lookups that each
spawned their own `op` invocation during the docker_services render loop with
~55 one-per-item fetches.

How field→value is resolved (matches community.general.onepassword semantics):
  * The field is looked up by its 1Password field *label* (case-insensitive),
    falling back to its *id*. Values are taken from the item's `fields` list.
  * Fields that are deliberately absent on a given item are emitted as `""`
    (e.g. `bcrypt_hash` only exists on `prometheus-internal_api`). The consuming
    template only ever reads the fields that item actually carries, so an empty
    sibling is harmless AND never a silent default — the item itself must still
    resolve or the whole export fails loudly (rc != 0).

Exit code 0 on success (valid JSON always emitted); non-zero on ANY item that
cannot be fetched, so the Ansible pre-pass fails closed without deploying.

Security: values go to stdout (a pipe the playbook consumes into a no_log
set_fact); never write them to disk, and never log them.
"""
import json
import subprocess
import sys

VAULT = None
FIELD_IDS = ("username", "password", "credential", "bcrypt_hash")


def get_item(name, vault):
    """Return the parsed item document for `name` (one `op` invocation)."""
    argv = ["op", "item", "get", name, "--format=json", "--reveal"]
    if vault:
        argv.append("--vault=" + vault)
    p = subprocess.run(argv, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"op item get failed for {name!r}: {p.stderr.strip()}")
    return json.loads(p.stdout)


def field_of(item, field):
    """Resolve a field by label (case-insensitive) then by id. Returns None if absent."""
    for f in item.get("fields", []):
        if (f.get("label") or "").lower() == field.lower() or f.get("id") == field:
            v = f.get("value") or ""
            # op returns CONCEALED values under the standard 'value' key; some
            # field types nest it. Guard empties -> "".
            return v if v is not None else ""
    return ""


def main():
    global VAULT
    args = sys.argv[1:]
    if "--" in args:
        idx = args.index("--")
        VAULT = args[idx + 1] if idx + 1 < len(args) else None
    # vault can also be passed via --vault=...
    for a in args:
        if a.startswith("--vault="):
            VAULT = a.split("=", 1)[1]

    names = [line.strip() for line in sys.stdin if line.strip()]
    out = {}
    for name in names:
        try:
            item = get_item(name, VAULT)
        except RuntimeError as e:
            print(f"op-vault-export: {e}", file=sys.stderr)
            sys.exit(1)
        out[name] = {fid: field_of(item, fid) for fid in FIELD_IDS}
    json.dump(out, sys.stdout)
    print()


if __name__ == "__main__":
    main()