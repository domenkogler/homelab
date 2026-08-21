# Scripts Folder Audit (Round 2)

> **Role:** Audit deliverable — review of `scripts/`: the validation gate, renderers, and utilities.
> Findings cover correctness bugs, silent-drift risks, gate coverage gaps, and convention compliance.
> Produced 2026-08-21 per follow-up to `prompt.md`.
> **Linked from:** `prompt.md`; siblings: `docs-vs-iac.md`, `docs-changes.md`, `iac-changes.md`,
> `conventions-sugestions.md`, `tracking-sugestions.md`, `architecture.md`, `security.md`.
> **Verdict up front:** the gate is well-conceived (7 fail-closed checkers, HD-163 render umbrella,
> safe-by-default provisioner) and everything currently passes. The issues below are mostly *silent
> drift* inside the checkers themselves — mock data that no longer mirrors the SSOT, hand-maintained
> scope lists, and two checks that are weaker than their docstrings claim.

---

## 1. Inventory

| Script | LOC | Role | Health |
|--------|-----|------|--------|
| `validate-all.sh` | 51 | Gate runner — 7 checkers, `set -euo pipefail`, py-launcher fallback | ✅ good |
| `validate-docker-services.py` | 557 | Compose render + structure + pin + count lint | ⚠ F1 |
| `check_doc_map.py` | 202 | Doc-map coverage + repo-wide link resolution | ✅ good, scope note F6 |
| `validate-secrets.py` | 198 | Literal-credential lint (vars layer) | ⚠ F7 |
| `validate_blueprints.py` | 195 | Authentik Blueprint shape (custom tags, slugs, binding) | ✅ good |
| `render_all.py` | 231 | Unified render umbrella + `--check` drift mode (HD-163) | ✅ good |
| `render_network_addresses.py` | 81 | network-addresses render (Windows path) | ✅ good |
| `render_rack_connections.py` | 180 | rack MD + mermaid render | ⚠ F3 |
| `check_doc_ips.py` | 68 | IP-literal lint | ⚠ F5 |
| `check_generated_suffix.py` | 90 | `-generated` suffix discipline | ✅ good |
| `validate_doc_templates.py` | 79 | SSOT template smoke-render | ⚠ F2 (weakest checker) |
| `provision-secrets.py` | 288 | 1Password create/rotate (safe-by-default) | ⚠ minor F8 |
| `gen-htpasswd.py` | 54 | bcrypt htpasswd for Prometheus auth | ✅ minor F9 |
| `collect-smart-live.sh` / `.ps1` | 117/178 | SMART collection (live ISO / Windows) | ⚠ F10 |
| data files (`*-s*.txt`, `smart-report-*.txt`) | — | raw SMART snapshots | housekeeping F10 |

---

## 2. Findings

### F1. `validate-docker-services.py` — the workhorse has drift and dead code

| # | Sev | Finding |
|---|-----|---------|
| F1.1 | **M** | **Duplicate dict keys silently collapse (last-wins):** `NETWORK_MAP` defines `immich-app`, `immich-ml`, `sunshine` twice (the first `immich-app` entry lacks `db-internal`; only the later one survives — it works by accident today). `_EXTRA_TEMPLATES` declares the `opencloud` csp entry twice; `WEB_SERVICES` lists `traefik` twice. A future edit to the *first* occurrence silently does nothing. |
| F1.2 | **M** | **`NETWORK_MAP` is effectively dead code.** The unexpected-network check subtracts `defined_nets` (the file's own top-level `networks:`), and a separate rule already forces every referenced network to be declared `external: true` — so `svc_nets ⊆ defined_nets` always holds and the map can never fire. It also no longer mirrors reality (`ollama` mapped to `services-internal`, but HD-59 moved it to `llm-backend`; `pgvector`, `docling`, `openclaw`, `litellm`, `pairdrop`, `stirling-pdf`, `onlyoffice-docs`, `home-assistant-primary` absent). Either enforce against the map strictly (drop the `defined_nets` escape) or delete the map and rely on the external-networks rule + docs. |
| F1.3 | **M** | **`BASE_CTX` mock drift:** `op_vault: "Homelab"` (SSOT is `Homelab-ansible` — the mock perpetuates the vault-name drift into rendered comments/labels); `gpu_render_gid/gpu_video_gid = 123/124` while `group_vars/all.yml` defines render 104 / video 44 — the comment says "keep in sync" and it isn't. `crowdsec_collections` mock carries 2 collections vs 5 in group_vars. Structural checks don't care, but any template logic *branching* on these values is validated against fiction. |
| F1.4 | **L** | **`mock_default` breaks Jinja `default` semantics:** with `StrictUndefined`, the real `default` filter catches `Undefined`; the mock returns the `Undefined` object when `value is not None`, so a template using `\| default()` on a genuinely undefined var crashes the validator instead of exercising the fallback. It only passes today because every defaulted var happens to exist in `BASE_CTX` — i.e. the `default('latest')` fallback paths are never actually tested. |
| F1.5 | **L** | **`load_all_services()` is fail-open:** malformed group_vars YAML is swallowed (`except Exception: pass`) — the validator then checks fewer templates and reports PASS. Contradicts the fail-loud philosophy; abort or fail the run instead. |
| F1.6 | **L** | Stray no-op `sys` line in the `--only` error branch; docstring still says "Checks all **41** compose templates" (49 dirs); `ALLOWED_LATEST` grants "deliberate latest" to services with stable semvers available upstream (homepage, metabase, pihole, technitium) — the allowlist is where the §7 pin law gets waived, and it is broader than `deployment-compose.md` documents (cross-ref `security.md` S2). |
| F1.7 | **L** | `check_template_exists` reports "missing" when a service entry omits `template_dir`, but the convention is that it defaults to the service name — apply the same default instead of failing. |
| F1.8 | **M** | **`_EXTRA_TEMPLATES` has drifted from its deploy-time twin.** The role's `_extra_templates` (`roles/docker_services/defaults/main.yml`) and this validator's copy are hand-synced and no longer match: the role renders `headscale/policy.hujson.j2` (the validator doesn't require it), while the validator requires `home-assistant-standby/keepalived.conf.j2`, which the role never renders (the home_assistant role owns that file — the template-dir copy is a raw leftover). Fix: have the validator read the role defaults instead of duplicating the list. Cross-ref `iac-changes.md` §11 D8. |

### F2. `validate_doc_templates.py` — weaker than documented

- **Docstring/README claim "render with real group_vars context" — it doesn't.** Only `ha_vip` is
  read from `group_vars/all.yml`; `network_vlans`, `network_static_hosts`, `network_ranges` are
  **hardcoded copies inside the script**. If the SSOT VLANs change, this checker still passes against
  stale data. It is a template-syntax smoke test — either parse the YAML properly (PyYAML is already
  a dependency elsewhere) or relabel it honestly in README + docstring.
- Its mock `ansible_managed` is the **retired** header string (`Ansible managed: file edited by
  Ansible`, retired by HD-163) while `render_all.py` emits the canonical `Ansible managed` — the
  checker validates different bytes than production renders.
- `root = Path("IaC/ansible")` is **CWD-dependent** (every other script anchors on `Path(__file__)`);
  works only because `validate-all.sh` cds to repo root. Standalone invocation from elsewhere fails
  with an unhelpful traceback.
- Mock `hostvars` includes a non-existent host key (a `ha.kogler.si` DNS-secondary entry — the
  secondary is the `pi` host) and only covers 2 of the 5 render targets (subscription-table and rack
  are covered by `render_all.py --check` — fine, but the README should say so).
- No explicit exit codes / failure message: a render error escapes as a raw traceback (non-zero, so
  the gate still fails — but unfriendably).

### F3. `render_rack_connections.py` — violates the §8.2 managed-header convention

The generated `docs/network-rack-generated.md` opens with `# Rack Connections`, not the canonical
`# Ansible managed` header that CONVENTIONS §8.2 (HD-163) requires of *every* generated doc and that
the other three renders emit. `check_generated_suffix.py` checks filenames, not headers, so nothing
catches this. Fix: emit the canonical header in the renderer (one line).

### F5. `check_doc_ips.py` — scan scope narrower than its contract

- Scans only `docs/**/*.md` + `deployment-tasks.md` + `README.md`. **Not scanned:** `CONVENTIONS.md`,
  `todo.md`, `changelog.md`, `IaC/**/*.md`, and any other root-level doc (e.g. this audit round's
  reports). The docstring's rule — "every other doc refers by hostname/role" — is enforced on roughly
  half the canonical surface. (Changelog rows legitimately carry historical IPs: scan-everything with
  a changelog exemption, or extend the exempt set deliberately.)
- Docstring tail "Wire into CI once Doco-CD activates" — stale (Doco-CD dropped, HD-150; the script
  is wired into `validate-all.sh`).
- `deployment-tasks.md` is both in `EXEMPT_FILES` and appended to the file list — harmless redundancy.

### F6. `check_doc_map.py` — hand-maintained scan scope

- `ROOT_SCAN` is a fixed allowlist; **new root-level `.md` files (like this round's seven reports)
  are silently never link-checked** until someone adds them — the same derived-pointer rot the repo
  fights elsewhere. Suggest: scan all root `*.md` except `prompt-*.md` (the exclusion rule already
  exists) instead of an allowlist.
- `ROOT_DOCS` contains phantom targets (`CHANGELOG.md`, `prompt-next.md`, `readme.md`) — harmless
  as an allowlist, misleading as documentation.
- Otherwise the strongest checker in the folder: code-span/fence stripping, the changelog append-only
  stale-link allowlist, and `manual/*` resolution-only handling are all well judged.

### F7. `validate-secrets.py` — good linter, two blind spots

- **Scope gap:** scans `group_vars`, `host_vars`, `roles/*/defaults`, `roles/*/tasks` — but **not**
  `roles/*/vars/`, `roles/*/files/`, or `templates/**/*.j2`. A literal credential pasted into a
  compose template is caught by *no* gate (the compose validator's `mock_lookup` masks lookups, and
  nothing scans templates for literal `PASSWORD=`-style values). Cheap fix: add the template globs
  to `_targets()`.
- Docstring + failure message say vault `Homelab` (should be `Homelab-ansible`); one duplicated
  comment line; `_CRED_TAIL` includes `public[_-]?key` — public keys are not secrets and would
  false-positive if a pubkey ever lands in the scanned layer (none today).
- Line-based YAML parsing cannot see into block scalars — acceptable for a grep-class linter; say
  so in the docstring so nobody over-trusts it.

### F8. `provision-secrets.py` — sound design, small nits

- `bcrypt_hash()` passes the generated password as a **CLI argv** to the child python — briefly
  visible in the process list. Single-user host, low risk; pass via env/stdin for hygiene.
- `BCRYPT_PY` defaults to `py -3` (Windows launcher) — fails on WSL/Linux unless overridden;
  document or auto-detect.
- `gen_wg_key()` is dead code (defined, never called, not CLI-exposed) — either expose it as a
  `--gen-wg-key` helper (it encodes the "real WireGuard key, never a password" rule nicely) or delete.
- `existing_items()` returns `{}` on any `op item list` failure → `--create` then attempts all 21
  creates and fails noisily one-by-one; abort on auth/scope errors instead.
- Catalog vs docs: `network-snmp_api` is auto-generated here but appears as a human-gated item in
  `deployment-tasks.md` §0 — reconcile the classification in one of the two.

### F9. `gen-htpasswd.py` — fine; docstring says vault `Homelab` (name drift again).

### F10. SMART collection + data hygiene

- Output destinations are inconsistent: `collect-smart-live.sh` writes a temp dir, `collect-smart.ps1`
  writes `reports/`, while the four `*-s*.txt` disk snapshots and one `smart-report-*.txt` actually
  sit in `scripts/`. Pick one home for snapshots (README already calls them "raw snapshots, not
  tools" — move them to `reports/` and point the README there).
- `collect-smart.ps1` docstring says "Windows 10 PC" — the host is Windows 11; trivial.
- `scripts/__pycache__/` exists on disk (gitignored, untracked) with stale `.pyc` from two CPython
  versions — cosmetic.

### F11. `scripts/README.md` — the map is stale in three places

1. "all **41** `docker_services` templates" → 49 (derived count, again).
2. `provision-secrets.py` row links `proposal-1p-automation.md` — the
   file does not exist (the dead link survives because the doc-map linter's scan scope doesn't include
   `scripts/README.md` — see F6).
3. "No secrets outside 1Password `Homelab`" → `Homelab-ansible`.

---

## 3. What is genuinely good (keep)

- **Fail-closed gate culture:** `validate-all.sh` is `set -euo pipefail`, first failure stops, and
  the checkers are wired in one place with a documented owner each.
- **`check_doc_map.py`** is a model linter: fence/code-span stripping before link extraction, an
  explicit append-only allowlist for changelog history, resolution-only treatment of `manual/*`.
- **`validate_blueprints.py`**: parsing Authentik's custom YAML tags safely and asserting the
  verified-in-source invariants (flow slugs, signing key, provider binding inside the application
  entry) is exactly the right kind of local gate for a config-as-code surface.
- **`render_all.py`**: the umbrella + `--check` (render → `git diff --exit-code` → restore) is the
  correct drift-detection primitive, and importing the two authoritative renderers instead of
  re-implementing them was the right HD-163 call.
- **`provision-secrets.py`**: safe-by-default (no args = no-op, writes need flag + `--yes`), the
  `NOT_AUTO_ROTATABLE` guard list, and the coupled bcrypt-hash rotation show real threat modelling.
- **`validate-docker-services.py`'s count-lint** (orphan template dirs) and the pin check are the
  right invariants — they just need the maintenance items in F1.

## 4. Recommendations (ranked)

1. **F7 scope + F1.5 fail-open** — the two places where the gate can silently stop protecting;
   both are few-line fixes.
2. **F2** — make `validate_doc_templates.py` actually read `group_vars` (or demote its description);
   align its `ansible_managed` mock with the canonical header.
3. **F3** — canonical header in `render_rack_connections.py` (one line, closes a §8.2 violation).
4. **F1.1–F1.3** — dedupe the dict literals, fix `BASE_CTX` mock values (or better: load
   `versions.yml` + `all.yml` directly instead of hand-mirroring — the same SSOT direction the
   renderers already use).
5. **F5/F6** — widen both linters' scan scopes to "all canonical root docs" with explicit
   exemptions, killing the hand-maintained lists.
6. **F8–F11** — nits and README sweep, one pass.

## 5. Gate additions worth considering (beyond fixes)

- **Ansible syntax check** in `validate-all.sh` (WSL/CI-gated, skip on native Windows) — catches
  nonexistent-module bugs (the HD-137 class) before deploy; proposed in `iac-changes.md` §9.
- **A `--check` mode for the compose render**: `validate-docker-services.py` renders with mocks;
  a drift check of *committed rendered output* doesn't exist because compose files are rendered on
  hosts — not applicable; instead consider validating that every `*_version` referenced by a
  template exists in `versions.yml` (catches a template referencing a pin that was renamed).
- **Vault-name lint**: a one-regexp checker for the literal `Homelab` (not followed by `-ansible`)
  across docs/IaC would have caught F1.3/F7/F9/F11 and the `docs-vs-iac.md` §E drift class
  permanently — cheaper than repeated audits.
