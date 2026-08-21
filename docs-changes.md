# Docs Folder — Change Proposals (Audit Round 2)

> **Role:** Audit deliverable — concrete proposals for `docs/`: content cleanup, consolidation,
> rewrite, split/merge, retirement. Produced 2026-08-21 per `prompt.md`.
> **Linked from:** `prompt.md`; siblings: `docs-vs-iac.md` (the contradictions these fix),
> `iac-changes.md`, `conventions-sugestions.md`, `tracking-sugestions.md`, `architecture.md`, `security.md`.
> **Ground rule:** planning-phase styling — substantive edits only; every proposal below is content-level.

---

## 1. Sweep class: stale VPS-era claims (fix in place, no structural change)

The single biggest docs debt is text that predates the HD-135 VPS split and HD-13 Homematic parking.
Fix at the next touch of each file, or in one dedicated pass:

| File | Fix |
|------|-----|
| `backup.md` | Rewrite "What Gets Backed Up" locations to the VPS era (DBs/TSDB on VPS NVMe; oldsrv holds GPU/media/DNS state); update Kopia source list (`/var/lib/forgejo-dump` etc. → VPS paths + WG push); keep the (good) dual-layer architecture text. |
| `observability.md` | Delete the "oldsrv NVMe" Loki claim in the Pi SD section (backend = VPS); while there, resolve the two ⚠ "needs live check/decision" TODOs that are already done (Alloy per-host instance label = HD-116 done; SNMP community = HD-53 decided) — move them to a "decided" note. |
| `services-matrix.md` | Replace "runs on oldsrv" with VPS placement (matches `group_vars/vps.yml`); fix storage path + WAN-firewall sentence. |
| `hardware-nas.md` | Delete the "TODO (IaC): … doc-only" box (role implemented). |
| `storage.md` | Delete the "Proposed IaC (stub)" section (incl. the "3879 mounts" typo); the role defaults are the spec mirror now. Consider trimming the struck-through legacy Immich section to two lines (it is already marked superseded). |
| `deployment-tasks.md` | See `tracking-sugestions.md` §2 (phase text sweep — placement lists, Pi services, closed HDs). |
| `IaC/README.md` | See `iac-changes.md` §1 (this file is the worst offender but is IaC-owned). |
| Date typos | Replace stray `2025-08-16` decision dates with 2026 (`security.md` §7, `services-ai.md` §9, `deployment-tasks.md` header, changelog rationale text). |

## 2. Consolidation: one fact, one home

| Proposal | Why | How |
|----------|-----|-----|
| **Single public-record list.** Today `services.md`, `network-dns.md`, `services-traefik.md`, `services-matrix.md` each enumerate the internet-facing subdomains, and the lists disagree (see `docs-vs-iac.md` §B). | Four hand-maintained copies of derived data. | Make `roles/cloudflare_dns/vars/main.yml` the declared SSOT (it already is nominally); in docs, keep exactly one human-readable mirror — `services.md` "Domain & Subdomain Plan" — and have the others link to it. Optionally render a `public-records-generated.md` from the role vars once the record list migration (file's own "Migration plan") completes. |
| **Cert-issuer decision.** VPS-issues vs oldsrv-issues the wildcard is described both ways (`docs-vs-iac.md` §C). | Blocks the Pi cert-sync design and DR wording. | Record the decision once in `changelog.md`, then align `deployment-tasks.md` Phase 1/3, `group_vars/all.yml` comment, `smart-home-failover.md`, and `IaC/README.md` §DNS/TLS to it. |
| **Backup-location table vs storage placement table.** `backup.md` and `storage.md` both answer "where does X live" for the VPS era; backup.md's copy is stale. | Two placement SSOTs drift (they already have). | Keep `storage.md` §Service ↔ Storage Placement as the only placement table; `backup.md` should reference it and list only *backup method/target per dataset*, not location. |
| **`deployment-compose.md` length.** At ~450 lines it mixes four concerns: conventions, Authentik OIDC provisioning, media-stack storage conventions, and observability retention. | Hardest deployment doc to navigate; OIDC section alone is ~120 lines. | Split into: `deployment-compose.md` (pure conventions + patterns) and `deployment-oidc.md` (Blueprint + glue + per-service native-OIDC recipes for OpenCloud/Immich/Forgejo/Metabase). The media/*arr storage block belongs in `services-media.md` (it duplicates storage.md content). |
| **`services-office.md` vs `services-ai.md` boundary.** Both describe Open WebUI, LiteLLM, MCP bridges; office repeats the AI stack's model table. | Minor duplication, but the "Not yet implemented" lists already diverged. | Keep `services-ai.md` as the platform SSOT; reduce `services-office.md` to the office slice (ONLYOFFICE/WOPI, MS fonts, client matrix, MCP topology) and link out for LiteLLM/Ollama details. |

## 3. Structure: keep, don't add

- The 2026-08-20 refactor (HD-167–174) landed well: domain indexes (`network/hardware/smart-home/services`),
  `-review`/`-rejected` triage, `-generated` suffix, doc-map linter. **No new top-level splits proposed.**
- `docs/manual/` (Slovenian, wip): keep deferred (HD-32) — content is specified, services are not live.
  Only fix: `manual/README.md` should stop promising "10 files" (map lists 12 incl. README) — derived count again.
- `docs/assets/`: fine as-is. `Network-Devices.canvas` is marked WIP — either finish it at network-redo
  time or drop the ⚠ note into `network.md`'s map row so readers know it lags.

## 4. Small but worth doing

| File | Change |
|------|--------|
| `docs/index.md` | Add the missing dispatch rows that exist as docs but have no "Which Document to Read First" entry: storage triage (`storage-review/rejected`), VPN detail (`network-vpn.md` has none), UPS/NUT (`hardware-ups.md` exists as row ✓ — verify), and the new audit reports if kept at root. Also: the ★ legend says "authoring specs read by AI to write/correct IaC" — several ★ files (e.g. `services-finance.md`) are not authoring specs; re-star by actual role. |
| `docs/security.md` | §2 "currently latest" for traefik is false (pinned); §2 "42 templates" → point at the directory; §9 duplicated fragment line. Fold the §6a/§8/§9 status markers to the two-sided gate style used elsewhere (✅ enforced / ⏳ deploy-gated) — already mostly done. |
| `docs/network-dns.md` | Remove ghost subdomain `bck`; align the public-record list per §2 above; the "Pi-hole Configuration" section is thin — consider merging into `services-dns.md` (which owns the service) leaving only the per-VLAN policy here. |
| `docs/home-assistant-current.md` | Healthy point-in-time snapshot; add one line at top: "supersede target = HD-04 redo" already present — just re-verify the "to-confirm" items (HD-15/20/21) are still open before each redo attempt. |
| `docs/interfaces.md` | Auto-Generation Pipeline says post-deploy hook renders `inventory.md.j2 → docs/services-inventory-generated.md` — correct, but add `render_all.py` as the Windows path (HD-163) so the pipeline diagram matches scripts/README. |
| All stack docs | Standardize the deploy-gate marker: some use "⚠ Phase 1 (planned, not yet deployed)", others "⚠ Planning phase". Pick one phrasing (CONVENTIONS §3 two-sided gate) — cosmetic but cheap during the §1 sweep. |

## 5. Retirement candidates

| File | Proposal |
|------|----------|
| `docs/deployment-review.md`, `network-review.md`, `storage-review.md`, `smart-home-review.md` | All four queues are empty (by design). Keep — the §8.3 lifecycle needs the file to exist; zero action. |
| `docs/services-review.md` | Same — keep. |
| Legacy/superseded prose blocks (Immich hybrid storage in `deployment-compose.md` + `storage.md`, Proxmox VM table in `hardware-oldsrv.md`) | All three are already marked superseded/rejected and justify *why* the current design exists. Keep, but compress each to ≤5 lines: decision + link to changelog HD. The full historical tables belong in git history / `reports/`, not canonical docs. |

## 6. Suggested execution order

1. One "stale-claims sweep" PR per §1 table (mechanical, low risk, fixes every [H] contradiction).
2. Cert-issuer decision + public-record SSOT alignment (needs a human call first).
3. `deployment-compose.md` split (§2) — do together with the next compose-convention change so the
   doc-map linter update rides along.
4. Cosmetic standardization (§4) opportunistically, never as its own PR (planning-phase rule).
