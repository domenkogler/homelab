# prompt-hd189 — Gate hardening bundle (validators)

> **Role:** Task handoff for **HD-189** (todo.md §2.3). Pure tooling — no IaC behavior changes.
> **Linked from:** [todo.md](todo.md) (HD-189); audit evidence: `scripts.md` F1.1/F1.2/F1.3/F1.5/
> F1.8/F7, `docs-vs-iac.md` §E.

## Scope (three work items)

### 1. `validate-secrets.py` — close the template blind spot

`_targets()` covers group_vars/host_vars/roles defaults+tasks only. Add:

- `IaC/ansible/templates/**/*.j2`
- `IaC/ansible/roles/*/vars/*.yml`, `roles/*/files/*`

A literal credential pasted into a compose template is currently caught by **no** gate. Keep the
existing placeholder/Jinja exemptions; expect the new scan to surface any current hits and fix them
in the same change (or exempt-with-comment if genuinely not a secret).

### 2. `validate-docker-services.py` — correctness pass

- **Fail-open loader:** `load_all_services()` swallows malformed YAML (`except: pass`) → fewer
  templates validated, still PASS. Abort with file+error instead.
- **Duplicate dict keys:** `NETWORK_MAP` (`immich-app`, `immich-ml`, `sunshine` ×2),
  `_EXTRA_TEMPLATES` (`opencloud` ×2), `WEB_SERVICES` (`traefik` ×2). Then decide NETWORK_MAP's
  fate: it is dead code (the `defined_nets` subtraction makes the check unfireable) AND stale
  (`ollama` → `services-internal`, but HD-59 moved it to `llm-backend`). Either enforce strictly
  (drop the `defined_nets` escape) or delete the map + rely on the external-networks rule. State
  the choice in the commit.
- **`_EXTRA_TEMPLATES` twin-list drift:** read the list from
  `roles/docker_services/defaults/main.yml` (parse the YAML) instead of the duplicated literal;
  delete the local copy. Note: role renders `headscale/policy.hujson.j2` (validator missed it);
  validator requires `home-assistant-standby/keepalived.conf.j2` (role never renders it — drop that
  expectation; the home_assistant role owns the file).
- **`BASE_CTX` mock drift:** `op_vault: "Homelab"` → `"Homelab-ansible"`; GPU gids 123/124 →
  104/44; `crowdsec_collections` mock → mirror group_vars. Better: load `versions.yml` + the needed
  `all.yml` vars directly so the mock can't drift again (preferred if cheap).
- Stray no-op `sys` line (~line 472) + stale "41 templates" docstring.

### 3. New checker: vault-name lint

`scripts/check_vault_name.py`: flag literal `Homelab` NOT followed by `-ansible` in canonical .md +
IaC yml/j2 (same scan-scope rules as `check_doc_map.py`'s `_iter_scan_files`). Wire into
`validate-all.sh` (8th checker) + `scripts/README.md` table. Fix the offenders it finds on first run
(known: `IaC/router/README.md`, `playbooks/dns.yml` + `render-routeros.yml` comments,
`scripts/README.md`, `gen-htpasswd.py` docstring, `validate-secrets.py` docstring/message,
`roles/home_assistant/tasks/main.yml` "vault 'Homelab'" comment). Allowlist `Homelab-ansible`
obviously; watch false positives like "1Password Homelab family vault" prose — prefer fixing text
over allowlisting.

## Steps

1. Implement in the order above; after each checker change run it standalone, then
   `bash scripts/validate-all.sh` — must end green with the new/expanded checks active.
2. Red/green test at least one new check (temporarily break a file → gate fails → restore).
3. Update `scripts/README.md` (checker table row for the new lint; fix "41 templates" → point at
   the directory; remove the dead `proposal-1p-automation.md` link; `Homelab` naming).
4. todo.md HD-189 ✅; changelog row; note anything found-by-the-new-scan as fixed-in-same-change.

## Constraints

- No behavior changes to rendered output (mock value fixes may alter validator-rendered bytes —
  that is fine and intended; call it out).
- Keep checker output format consistent (`FAIL:`/file:line style) for gate readability.

**Cleanup:** delete this handoff (`prompt-hd189.md`) in the same closing change (A3 lifecycle, CONVENTIONS §4; HD-203 sweeps any leftovers).
