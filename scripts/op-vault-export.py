#!/usr/bin/env python3
"""
op-vault-export.py — HD-258 bulk 1Password pre-pass helper.

Reads 1Password item NAMES from stdin (one per line) and emits a single JSON
object to stdout:

    { "<item>": {"username":…, "password":…, "credential":…, "bcrypt_hash":…}, … }

using ONE `op item get --reveal --format=json` process per item, run concurrently
(via ThreadPoolExecutor). This replaces ~160 per-template
`community.general.onepassword` lookups (each its own `op` spawn during the
docker_services render loop) with ~50 concurrent one-per-item fetches.

Two modes:
  * default — item names on stdin → JSON dict for exactly those items.
  * `--derive` — stdin carries a JSON object
      { "services": [template_dir,…], "map": {template_dir:[item,…],…}, "glue":[…] }
    the exporter expands services→items via `map` and fetches the deduped set
    minus the glue items. Runs per host (enabled docker_services only). Returns
    the same {item: {field}} dict.

Field→value resolution (matches community.general.onepassword semantics):
  * field matched by 1Password field label (case-insensitive), then by id.
  * absent fields on an item are emitted "" (template only reads the fields that
    item actually carries; never a silent default — the ITEM must still resolve
    or the export fails loudly).

Exit 0 on success (valid JSON always emitted); non-zero on ANY unfetchable item
so the Ansible pre-pass fails closed and does not deploy.

Security: secret VALUES go to stdout (the playbook's no_log set_fact). Never
write them to disk or to logs.
"""
import argparse
import json
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

DEFAULT_FIELD_IDS = ("username", "password", "credential", "bcrypt_hash")


def get_item(name, vault=None):
    argv = ["op", "item", "get", name, "--format=json", "--reveal"]
    if vault:
        argv += ["--vault", vault]
    p = subprocess.run(argv, capture_output=True, text=True)
    if p.returncode != 0:
        return {"__error__": f"op item get failed for {name!r}: {p.stderr.strip()}"}
    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError:
        return {"__error__": f"Failed to decode JSON for {name!r}"}


def extract_fields(item, field_ids):
    if not field_ids:
        out = {}
        for f in item.get("fields", []):
            label = f.get("label") or f.get("id")
            if label and f.get("value") is not None:
                out[label.lower()] = f.get("value")
        return out
    extracted = {}
    fields = item.get("fields", [])
    for fid in field_ids:
        found = ""
        for f in fields:
            if (f.get("label") or "").lower() == fid.lower() or f.get("id") == fid:
                v = f.get("value")
                found = v if v is not None else ""
                break
        extracted[fid] = found
    return extracted


def derive_items(services, tmap, glue):
    """services: template_dir names (enabled only). Return deduped needed items
    minus glue (the caller fetches glue AFTER its minting glue runs)."""
    needed = set()
    for d in (services or []):
        needed.update(tmap.get(d, []))
    return sorted(needed - set(glue or []))


def main():
    ap = argparse.ArgumentParser(description="Parallel 1Password vault exporter for Ansible")
    ap.add_argument("--vault", help="1Password vault name or UUID")
    ap.add_argument("--derive", action="store_true",
                    help="derive the needed set from services/map/glue (JSON on stdin or --spec-file)")
    ap.add_argument("--spec-file", help="read the {services,map,glue} spec JSON from this file")
    ap.add_argument("--all-fields", action="store_true")
    ap.add_argument("--workers", type=int, default=6,
                    help="concurrency for op item get (default 6; see HD-268 — 15 sparks heavy bursts that can trip hosted 1P rate-limits during repeated debug converges)")
    args, _ = ap.parse_known_args()

    vault = args.vault or ""
    if not vault:
        try:
            i = sys.argv.index("--")
            if i + 1 < len(sys.argv):
                vault = sys.argv[i + 1]
        except ValueError:
            vault = ""

    field_ids = [] if args.all_fields else DEFAULT_FIELD_IDS

    if args.derive:
        if args.spec_file:
            with open(args.spec_file, encoding="utf-8") as fh:
                spec = json.load(fh)
        else:
            spec = json.load(sys.stdin)
        names = derive_items(spec.get("services", []),
                             spec.get("map", {}),
                             spec.get("glue", []))
    else:
        names = [line.strip() for line in sys.stdin if line.strip()]
    if not names:
        print("{}")
        return 0

    out = {}
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futures = {ex.submit(get_item, n, args.vault or None): n for n in names}
        for fut in futures:
            name = futures[fut]
            data = fut.result()
            if "__error__" in data:
                print(f"op-vault-export: {data['__error__']}", file=sys.stderr)
                return 1
            out[name] = extract_fields(data, field_ids)

    json.dump(out, sys.stdout)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())