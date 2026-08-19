# Prompt: HD-160 — services-internal sibling auth (data-writing siblings need a token)

> Handoff written 2026-08-19. Goal: a supply-chain compromise in any public image on the overlay
> can't cross to a data-writing sibling.

## Task

Extend the audit's recommendation (`security.md` root §2.3 + §4) so **every data-writing sibling on
the `services-internal` network** carries its own token/header auth — not just the ones HD-59 already
covered (Ollama→llm-backend isolation, Kopia htpasswd, Prometheus bcrypt, Signal CLI token).

## Context

- HD-59 covered: Ollama (isolated onto `llm-backend`), Kopia (`--htpasswd-file`), Prometheus
  (`--web.config.file` bcrypt), Signal CLI (`SIGNAL_CLI_API_TOKEN`).
- The remaining **data-writing `services-internal` siblings** need a per-service token/header so a
  compromised public image on the overlay can't write to them.
- See `docs/deployment-compose.md` (Network Assignment: `services-internal`) + `docs/security.md` §4.

## What to do

1. **Read `docs/deployment-compose.md`** (Network Assignment table) + `docs/security.md` §4 +
   `docs/deployment-secrets.md` (secret naming: `<service>-internal_api` / `<service>_api` pattern).
2. **Inventory every data-writing sibling** on `services-internal` (DBs on `db-internal` are already
   isolated; focus on app-to-app writes: n8n→signal-cli, OpenClaw→OpenCloud WebDAV, immich-app→
   immich-ml, litellm→ollama, Grafana→Prometheus, backup agents→Kopia, etc.). For each, note whether
   it already has auth and which gap remains.
3. **For each gap**, add a **per-service token/header**:
   - 1Password item `<service>-internal_api` (`password` type) where one doesn't exist;
   - enforce on the receiving side (a small middleware/token check in the compose config, or the
     app's native auth if it has one — same precedent as HD-59);
   - document the item in `docs/deployment-secrets.md` (master list).
4. **Update `docs/security.md` §4** to mark the sibling-auth coverage complete (or list the
   deliberate exceptions with a reason, e.g. a service with no supported auth → network-isolate
   it like Ollama).
5. Update **HD-160 row in `todo.md`** (✅ IaC done; ⏳ deploy-gated: create the 1Password items +
   live-verify at Phase 1/3).
6. `bash scripts/validate-all.sh` green.

## Guardrails
- **Fail-loud (HD-65):** missing internal_api items must abort render, never `default('')`.
- Don't break existing HD-59 wiring (Ollama stays isolated on `llm-backend`).
- If a sibling genuinely has no auth mechanism, prefer **network isolation** (like Ollama) over
  inventing a proxy — flag the decision in the owning doc.
- Follow the secret naming convention exactly (`<service>-internal_api`).

## Definition of done
Every data-writing `services-internal` sibling has token/header auth (or a documented isolation
decision); secrets doc updated; security.md §4 reflects coverage; HD-160 updated; validators green.
