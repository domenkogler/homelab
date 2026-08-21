# Conventions — Suggestions (Audit Round 2)

> **Role:** Audit deliverable — proposals for new conventions and amendments to `CONVENTIONS.md`.
> Produced 2026-08-21 per `prompt.md`. Each proposal states: the gap observed (evidence), the rule,
> and where it would live. Nothing here is adopted until the human signs off.
> **Linked from:** `prompt.md`; siblings: `docs-vs-iac.md`, `docs-changes.md`, `iac-changes.md`,
> `tracking-sugestions.md`, `architecture.md`, `security.md`.

---

## A. Amendments to existing CONVENTIONS.md sections

### A1. §2 "Values & SSOT" — extend derived-counts to *pointers*, not just counts
- **Observed:** §2 already says doc-stated counts are derived, never hand-entered. In practice every
  violation found in this audit is a cousin of that rule: hand-entered **counts** ("18 roles", "41
  templates", "44 items", "10 Slovenian files"), hand-entered **next-free IDs** ("next free = HD-114"),
  and hand-copied **lists** (public record set ×4, VLAN map ×3, AllowedIPs ×2).
- **Proposed wording (append to §2):**
  > A doc-stated **pointer** is also derived data: backlog next-free IDs, item/role/template counts,
  > and any list that exists in IaC (service lists, DNS record sets, VLAN maps) must be quoted by
  > reference ("see todo.md", "see roles/cloudflare_dns/vars") or rendered — never re-typed.
  > A stale pointer in prose is a defect, not a cosmetic.

### A2. §3 "Two-sided deploy gate" — add the third state: superseded
- **Observed:** docs carry 🔴 planned / 🟢 IaC done ⏳ / ✅ live, but not "this design was replaced"
  (Immich hybrid storage, Proxmox VM table, Doco-CD remnants). Superseded blocks currently survive as
  struck-through paragraphs of arbitrary length.
- **Proposed:** a superseded design block is compressed to ≤5 lines: what changed, decision link
  (changelog HD), where the current design lives. Full rationale lives in changelog/git history.

### A3. §4 Lifecycle — audit/report files need a defined lifecycle
- **Observed:** round 1 produced root-level audit reports (`docs-vs-iac.md`, `architecture.md`, …)
  that were folded into canonical docs and deleted (HD-153). Round 2 recreates them. Without a rule,
  the repo will accumulate both report generations or lose them ambiguously.
- **Proposed (new row in §4):**
  > **Audit reports** — root-level `*-audit*.md` / prompt-deliverable reports are **ephemeral**:
  > each actionable finding is either (a) folded into its owning doc + tracked as an HD row, or
  > (b) explicitly rejected; then the report is deleted in the same change that closes the last
  > finding (HD-153 precedent). Reports are never referenced as SSOT by other docs.

### A4. §6 Language/headers — allow the established exception explicitly
- **Observed:** `readme-humans.md` (root) is Slovenian; convention says English technical / Slovenian
  family (`docs/manual/`). The human README is a de-facto third category.
- **Proposed:** one-line amendment: "Slovenian is also used in `readme-humans.md` (family-facing root
  guide); everything else technical is English."

### A5. §7 Version-pin hygiene — close the mutable-default loophole
- **Observed:** templates use `{{ x_version | default('latest') }}` and vars like `stable`/`release`
  pass the "no bare latest" grep while violating the law (`security.md` Flaw B evidence).
- **Proposed (append to §7):**
  > A pin var must have **no fallback default** in templates; a missing pin aborts the render
  > (fail-loud, same as secrets). Mutable aliases (`stable`, `release`, `-rocm`) are bare-latest
  > equivalents and fall under the same MUST-pin precondition.

## B. New conventions proposed

### B1. Single cert issuer (decision-forcing rule)
- **Gap:** two mutually exclusive issuer stories exist (VPS Traefik vs oldsrv Traefik) across
  deployment-tasks/all.yml comment/smart-home-failover — see `docs-vs-iac.md` §C.
- **Proposed rule (owner: `deployment.md` or `services-traefik.md`):**
  > Exactly **one** ACME issuer issues the wildcard `*.kogler.si` cert. Every other edge consumes a
  > synced copy. The issuer is named in exactly one doc; all others link to it.
  The decision itself (which host) goes to changelog first.

### B2. Public-record set has one mirror
- **Gap:** four docs enumerate the internet-facing subdomains; lists disagree; IaC currently manages
  only the VPS records (see `docs-vs-iac.md` §B).
- **Proposed rule (owner: `services.md` §Domain & Subdomain Plan):**
  > The public record list is stated once (human mirror of `roles/cloudflare_dns/vars/main.yml`);
  > every other doc links to it. Until the cloudflare_dns migration completes, docs must mark the
  > list "target state — live zone may differ" instead of asserting it as fact.

### B3. Cross-host dependency declarations
- **Gap:** several service pairs span hosts over the WG tunnel (immich-app→immich-ml,
  litellm→ollama, n8n→signal-cli, Alloy→backend) but only some docs say so; availability implications
  (tunnel down = feature down) are documented inconsistently.
- **Proposed rule (owner: `services.md` catalog legend):**
  > Any service whose runtime depends on another **host** declares it in its catalog row:
  > `cross-host: <peer> via <link>` — plus the degraded behavior when the link is down.
  (Observability already models this well — generalize its pattern.)

### B4. Bootstrap-window security floor
- **Gap:** router/switch/AP bootstrap `.rsc.j2` differ in whether management services are
  interface-bound; the AP template exposes SSH over WLAN during bootstrap (evidence in `security.md` §5).
- **Proposed rule (owner: `network-ops.md`):**
  > Every bootstrap config binds management services to the Management interface (or bridge) from
  > the first line of device uptime — the rb4011 template is the canonical pattern; no template may
  > enable an unbound management service.

### B5. Placeholder discipline for preseeds/bootstrap scripts
- **Gap:** preseeds ship placeholder serials/pubkeys that fail or misfire silently if not edited
  (oldsrv's pool create has a fail-loud guard; preseeds don't).
- **Proposed rule (owner: `deployment-preseed.md`):**
  > Every placeholder in a bootstrap artifact must be (a) visually marked with a greppable token
  > (`REPLACE_ME_*`), and (b) asserted at post-install: a produced config still containing a
  > `REPLACE_ME_*` aborts loudly before reboot.

### B6. Decision-date hygiene
- **Gap:** decision entries dated 2025-08-16 in a 2026 repo (typo class) — makes the log untrustworthy.
- **Proposed:** dates in decision logs are written ISO `YYYY-MM-DD` and validated at review time;
  fix the existing `2025-08` occurrences in one sweep. (Optionally a linter could flag future-year
  impossibilities — likely overkill; a sweep suffices.)

## C. Convention candidates considered and NOT proposed

| Candidate | Why rejected |
|-----------|--------------|
| Mandatory frontmatter schema validation (JSON-schema for `domain:`/`role:` values) | check_doc_map + reviewer discipline already cover drift; a schema linter adds friction for little gain at 61 docs. |
| Forcing all compose templates through shared Jinja fragments | Rejected as a *convention* (kept as an optional IaC improvement in `iac-changes.md` §4) — per-service readability is worth more than DRY here. |
| Renaming `*-sugestions.md` audit files into `docs/` | They are ephemeral per A3; keep at root until folded/deleted. |
| Per-host docker-compose linting beyond the existing validator | Existing structural checks + compose validate step (HD-162) cover the real failure modes. |

## D. Text-ready diffs (for quick adoption)

1. **§1 Naming table, new row:**
   `| Cert issuer | exactly one ACME issuer for *.kogler.si; all other edges consume synced copies | services-traefik.md |`
2. **§2 Values & SSOT, append:** the pointer rule from A1.
3. **§3 Compose versioning row, append:** "pin vars carry no `default()` fallback (fail-loud)".
4. **§4 Lifecycle, new row:** audit-report lifecycle from A3.
5. **§7, append:** mutable-default closure from A5.
