---
title: Personal Finance Stack
role: ssot
domain: services
status: active
tags: [services, finance, budget, banking, investing]
---
# Personal Finance Stack

> **Role:** Single source of truth — personal finance services, account import strategy, Enable Banking
> integration, AI auto-categorization via local Ollama, backup rules, and the manual-import plan for
> accounts without open-banking access.
> **Links to:** `services.md`, `services-authentik.md`, `deployment-compose.md`, `storage.md`,
> `services-office.md`, `network-dns.md`
> **Linked from:** `index.md`, `services.md`

> 🟢 **IaC done, not yet live — ⏳ deploy-gated.** Actual Budget + Enable Banking are designed but **not live**
> (tracked HD-57, Stage 3/10); compose template + group_vars registry landed 2026-08-24. This doc is the
> authoring spec for the IaC (`docker_services/actual-budget/` + `group_vars/home_servers.yml`) and the
> network/DNS records.
>
> **Placement (decision 2026-08-24): oldsrv**, internal-only P+I — same plane as the media stack.
> If oldsrv is ever disposed, non-GPU state restores from Kopia/NAS backups onto any Docker host
> (see [backup.md](backup.md)); a dedicated oldsrv→VPS DR runbook is tracked in todo.md.

---

## Goals

- Track **cash flow** across all accounts (UniCredit SI, Wise, Trade Republic cash, MC World Elite card)
  in one place — **Actual Budget**.
- Track **ETF investments** (IBKR + Trade Republic) as a single tracking account inside Actual — no
  separate portfolio app needed. Only *invested vs current value* is needed; Ghostfolio is explicitly
  **not** used (see [Decisions — Ghostfolio skipped](#ghostfolio-skipped)).
- **Automatically categorize** transactions using a local LLM (Ollama, already deployed) — no cloud AI
  provider touches financial data.
- **Maximize automation:** open-banking sync via Enable Banking (UniCredit), Wise API, IBKR Flex Query.
  Accept manual CSV drops only where no API exists (TR, credit card).
- **Credit card:** manual monthly CSV import as the anchor. SMS/email notification parsing considered
  for future real-time tracking but not the initial plan.
- All services internal-only, behind Authentik Forward-Auth.

### Non-goals

- No Ghostfolio — the investment tracking inside Actual suffices for weekly fixed ETF buy orders.
- No GoCardless (Nordigen) — free personal sign-ups are discontinued.
- No TradeSight / PDF parsing — TR's native "Transactions Export" provides a structured CSV.
- No Crypto.com or Curve integration for now — both are unused; may be added later if they become active.
- No SMS/email notification parsing for the credit card in the initial deploy (deferred to future).

---

## Service Catalog

| Service | Subdomain | Network | RAM (idle/peak MB) | Description |
|---------|-----------|---------|--------------------|-------------|
| Actual Budget | budget | P+I | 60–120 / 250 | Budgeting + investment tracking (Node.js + SQLite, one container) |

- **Subdomain:** `budget.kogler.si` — **internal-only** (no public DNS record, WAN-blocked).
- **Network:** `traefik-public` + `services-internal`.
- **Auth:** Authentik Forward-Auth (same as *arr, Dozzle, etc.).
- **RAM sanity:** ≈ 60–250 MB is negligible on `oldsrv` (48 GB).

### Component breakdown

Actual Budget is a single container (`actualbudget/actual-server`). It embeds the server + API + SQLite
database. No separate Postgres, no worker processes.

---

## Account Import Strategy

All import sources converge on Actual Budget. n8n (existing) orchestrates everything that is not handled
by Actual's built-in bank-sync.

### Source matrix

| Account | Type | Automation method | Schedule | Automatic? |
|---------|------|-------------------|----------|------------|
| **UniCredit SI (current)** | Checking | **Enable Banking API → n8n bridge → Actual API** (decision 2026-08-24: stable image — NOT the nightly/native-sync build) | Daily | ✅ Yes |
| **Wise** | Multi-currency | **Wise API** → n8n → Actual API | Daily | ✅ Yes (API token needed) |
| **Trade Republic (cash)** | Cash/broker | **CSV export** (TR in-app "Transactions Export") → drop in watched folder → n8n → Actual API | Monthly manual | ⚠️ Manual CSV drop |
| **MC World Elite (UniCredit)** | Credit card | **CSV export** (UniCredit online banking) → n8n → Actual API | Monthly manual | ⚠️ Manual CSV drop |
| **IBKR (ETFs)** | Investment | **Flex Query** (Flex Web Service) → n8n fetches URL → Actual API (tracking account) | Daily | ✅ Yes (set-and-forget) |
| **TR (ETFs)** | Investment | **CSV export** (same as TR cash, includes trades) → n8n → Actual API (tracking account) | Monthly manual | ⚠️ Manual CSV drop (same file as cash) |

### Why manual steps exist

1. **Credit card (PSD2 blind spot):** Credit cards are *credit agreements*, not PSD2 "payment accounts."
   No open-banking aggregator (Enable Banking, GoCardless, Salt Edge) can legally access them. Manual
   CSV import is the only reliable path. See [Credit card — future automation](#credit-card--future-automation)
   for optional SMS/email notification parsing.

2. **Trade Republic:** No PSD2-compliant banking API (TR is a neo-broker, not a bank in PSD2 terms).
   TR offers an in-app "Transactions Export" (CSV/Excel) — manual download, then drop in watched folder.

### Enable Banking — setup

Enable Banking is the native bank-sync provider for Actual Budget, replacing GoCardless (which
discontinued free personal sign-ups). It is **free for personal use**.

**Prerequisites:**
- Account at [enablebanking.com](https://enablebanking.com/sign-in/) — already exists.
- Create an application in the [Enable Banking dashboard](https://enablebanking.com/cp/applications):
  - Mode: **Production**
  - Application Name: `Actualbudget`
  - Allowed redirect URL: `https://budget.kogler.si/enablebanking/auth_callback`
- Copy the **Application ID** (UUID) and download the **credential file**.

**Coverage:**
| Bank | ECB MFI Code | AISP (read) | PISP (pay) | Personal? | Status |
|------|-------------|-------------|------------|-----------|--------|
| UniCredit Bank Slovenia (UNICREDIT BANKA SLOVENIJA d.d.) | SI5446546 | ✅ | ✅ | ✅ Personal + Business | Confirmed supported |

**Integration (bridge mode, decision 2026-08-24):**
1. Create the Enable Banking application (Production mode, name `Actualbudget`) — the App ID +
   credential file authorize the **n8n** workflows; they live in an n8n credential, not in Actual.
2. n8n polls EB daily (`GET /api/accounts/{id}/transactions`) and pushes new transactions into Actual
   via its HTTP API (`X-ACTUAL-TOKEN`, credentials `actual-budget_login`).
3. Native Actual↔EB sync (`More → Bank Sync`) stays **unused**: it exists only on the `nightly` line,
   which violates the pin-semver law (§7). Re-evaluate only if upstream ships EB sync in a stable
   release, with a new dated decision.
4. Redirect URL: set it to a page we control (e.g. `https://budget.kogler.si/eb-callback`); verify the
   Traefik route + wildcard cert cover it before creating the EB application.

### Wise API — n8n workflow

Wise provides a personal API token per profile (Settings → API tokens). n8n workflow:

1. **HTTP Request** node → `GET /v1/profiles/{profileId}/balances` → list account IDs.
2. Loop through account IDs → `GET /v1/profiles/{profileId}/balances/{balanceId}/statement?interval=1d`.
3. **Transform** payload into Actual's import format (JSON: `date`, `amount`, `payee`, `notes`, `imported_id`).
4. **HTTP Request** → `POST /api/budgets/{budgetId}/accounts/{accountId}/import-transactions`.

### IBKR Flex Query — n8n workflow

IBKR's Flex Web Service generates XML reports on demand via a stable URL. Setup:

1. On IBKR Account Management → Reports → Flex Queries → create a new query:
   - Activity type: **Trades**
   - Include: buy/sell, corporate actions, dividends.
   - Output format: XML (n8n parses `FlexQueryResponse/FlexStatement/Trade` nodes).
2. n8n fetches the URL on a daily schedule → parses XML → transforms to Actual's format → pushes
   to the investment tracking account.

**One-time initial setup:** Manually enter the existing portfolio (ticker, shares, cost basis) into
Actual's investment account so the tracking account has a correct starting balance.

### Trade Republic — CSV workflow

TR's native "Transactions Export" (App → User settings → Transactions Export → select date range →
download) produces a CSV/Excel file containing both cash movements and trades.

n8n pipeline:
1. **Watch Folder** node (polling an OpenCloud/Nextcloud directory or filesystem path).
2. When a new CSV lands → **Read Binary** → **Parse CSV** → split into cash entries (→ cash account)
   and trade entries (→ investment tracking account).
3. Dedup against Already-imported IDs in Actual.
4. Push to Actual API.

### Credit card — manual CSV import

UniCredit's online banking provides a downloadable transaction history (CSV/XLS) for the Mastercard
World Elite card. Manual monthly: download → drop in watched folder → n8n parses and pushes.

**Credit card — future automation (deferred):** UniCredit offers SMS transaction alerts for card
charges. If email transaction alerts are not available, an Android phone with an SMS forwarding app
(SMS Forwarder / Tasker) can forward SMS → n8n webhook for near-real-time capture. The monthly CSV
remains the reconciliation anchor. This is a **post-deploy enhancement**, not in Phase 1 scope.

---

## Data Flow

```
                  ┌─────────────────── VPS (public edge) ───────────────────┐
UniCredit SI ──▶ Enable Banking API ──┐                                      │
Wise ──────────▶ Wise API ────────────┤                                       │
IBKR (ETFs) ───▶ Flex Query (auto) ───┤   n8n                                 │
TR / MC card ──▶ CSV export (manual) ─▶ watched folder                        │
                                      │                                       │
                                      ▼                                       │
                          Actual HTTP API :5006 over WG S2S                   │
                          (X-ACTUAL-TOKEN, actual-budget_login)               │
                                      │                                       ▼
                                      ├───────────────────────────▶ Actual Budget
                                      │                            oldsrv · budget.kogler.si
                      uncategorized   │                            (LAN internal)
                          txns        ▼
                          LLM node → LiteLLM spine (VPS) ── WG S2S ──▶ Ollama
                          categories written back via Actual API
```

### AI Categorization via local Ollama (LiteLLM spine)

Categorization runs inside each import workflow in **n8n**: unmapped payees go to an LLM node pointed
at the **LiteLLM spine** on the VPS (`llm-backend` isolation means nothing targets Ollama directly —
HD-59); LiteLLM routes to Ollama on the RX 7600 (small model like `llama3.2:3b`). The category is
written back to Actual via its API. No extra copilot container is onboarded — the earlier "community
AI copilot tool" idea is superseded by this n8n-native loop (decision 2026-08-24).

**No extra GPU cost:** Ollama runs on the existing AMD RX 7600 (8 GB VRAM), shared with Qwen/Llama
for office LLM use. A small model like `llama3.2:3b` or `qwen2.5:7b` handles category inference in
fractions of a second per transaction.


## Decisions

### Ghostfolio skipped

Ghostfolio was evaluated for portfolio tracking (IBKR + TR ETFs). The need is limited to *invested
vs current value* for weekly fixed buy orders — Actual's tracking account handles this with:

- Buys → outflow from cash, added to cost basis.
- Dividends → inflow to cash (income category).
- Balance = shares × latest price (updated monthly from the same CSV/Flex report).

Ghostfolio's advantages (XIRR, benchmarks, dividend calendar) are not needed. **Decision:** skip.
Simplifies the stack by one full service + Postgres + maintenance surface.

### Enable Banking over GoCardless

GoCardless (Nordigen) was the historical default for EU bank sync in Actual Budget, but **free personal
sign-ups are discontinued** for new users. Enable Banking is the alternative that:
- Is **free for personal use** (transactions + balances).
- Has **native support in Actual Budget** (experimental, nightly).
- The user **already has an account**.
- Covers **UniCredit Bank Slovenia** (AISP confirmed).

**Decision:** Enable Banking. Fallback: if native sync regresses, use Enable Banking API + n8n bridge.

### TradeSight not needed

TradeSight (kalix127/tradesight) converts TR PDF statements to CSV via Ollama vision models. Since TR
provides a native structured **CSV/Excel export** ("Transactions Export"), TradeSight is unnecessary.
**Decision:** skip.

### Stable pinned image + n8n EB bridge (nightly rejected)

*Decision 2026-08-24 (HD-57).* The native Actual↔Enable Banking sync exists only on the `nightly`
image line, which violates the pin-semver law (§7 — mutable tag, no Renovate semver trail, silent
class of breakage). **Decision:** `actual_budget_version` stays a registry-verified stable calver pin;
UniCredit sync runs as an n8n workflow polling the Enable Banking API and pushing into Actual's HTTP
API. Re-evaluate only when upstream ships EB sync in a stable release.

### Placement: oldsrv (not VPS)

*Decision 2026-08-24 (HD-57).* Actual Budget is internal-only P+I; financial data stays on the LAN
plane with the media stack, backed up to NAS + Kopia off-site. The VPS hosts only the pipeline brain
(n8n + LiteLLM), which reaches Actual over the WG S2S tunnel (:5006 bound to `oldsrv_home_ip`,
immich-ml precedent). If oldsrv is disposed, non-GPU state restores from backups onto any Docker host.

### Credit card: manual CSV first; SMS/email parsing deferred

*Decision 2026-08-24 (HD-57).* Phase-1 ingest for the MC World Elite is monthly manual CSV only.
Email-alert → mailbox automation is investigated post-deploy; SMS-forwarder is last resort.

### Seed before sync

*Decision 2026-08-24 (HD-57).* Starting balances and existing IBKR/TR positions are entered manually
BEFORE any auto-sync is enabled; sources come online one at a time (EB → Wise → Flex) with dedup
checks after each.

---

## Backup

| Data | Method | Schedule |
|------|--------|----------|
| Actual Budget state (`/srv/docker/actual-budget/data` — SQLite + user files + built-in backups) | kopia-agent snapshot (oldsrv-local path) → kopia-server → Hetzner backup Box | Daily |
| Enable Banking credentials | 1Password `Homelab-ansible` vault | — |
| Wise API token | 1Password `Homelab-ansible` vault | — |
| IBKR Flex Query token | 1Password `Homelab-ansible` vault | — |
| Actual login (`actual-budget_login`) | 1Password `Homelab-ansible` vault | — |
| n8n workflow definitions | Git repo (this repo, `IaC/`) | On commit |

Actual's backup export includes all accounts, transactions, categories, and rules. See
[`backup.md`](backup.md) for the general backup architecture.

---

## Security

- **All internal-only:** `budget.kogler.si` has **no** public DNS record (Cloudflare) and is
  WAN-blocked at the MikroTik firewall. Same posture as Sonarr/*arr, Grafana, n8n.
- **Authentik Forward-Auth:** every HTTP request to `budget.kogler.si` requires an Authentik session
  with MFA (WebAuthn/TOTP).
- **No cloud AI:** categorization runs on local Ollama — financial data never leaves the LAN.
- **Secrets in 1Password:** Enable Banking App ID + credential file, Wise API token, IBKR Flex token,
  UniCredit export mailbox credentials (if applicable).

---

## Open Questions (pre-deploy — remaining human steps)

Decided 2026-08-24: stable+n8n bridge (not nightly), oldsrv placement, CSV-first card, seed-before-sync.
Remaining before/at first deploy:

- [ ] Verify the wildcard cert + Traefik route cover `budget.kogler.si` (and the EB callback path)
      before creating the EB application.
- [ ] Create the Enable Banking application (Production, `Actualbudget`) and store App ID + credential
      file in 1Password.
- [ ] Generate Wise API token (personal, read-only) for the n8n workflow.
- [ ] Set up IBKR Flex Query in Account Management → Reports → Flex Queries and obtain the token URL.
- [ ] Create the `actual-budget_login` 1Password item (human-side ref — consumed at n8n setup, not by
      Ansible).
- [ ] Confirm whether UniCredit SI online banking allows **email transaction alerts** for the
      Mastercard World Elite (preferred over SMS for n8n automation). If yes, set up a dedicated
      mailbox for the alerts.

---

## Related

- [Service Catalog](services.md) — catalog rows, networks, the public subdomain set
- [Authentik — Identity & SSO](services-authentik.md) — Forward-Auth config for `budget.*`
- [Traefik — Reverse Proxy & Edge](services-traefik.md) — route config, wildcard cert, Forward-Auth labels
- [Local LLM & Office Tools](services-office.md) — Ollama sharing GPU with office LLM workloads
- [Storage — ZFS](storage.md) — dataset layout for backup
- [Backup Architecture](backup.md) — Kopia off-site + ZFS snapshot schedule
- [Subscriptions & Costs](subscription.md) — no new subscriptions for this stack
- [Docker Compose Conventions](deployment-compose.md) — Actual Budget compose template spec