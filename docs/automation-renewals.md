# n8n — Subscription Renewal Reminder Workflow (infrastructure)

> **Status:** 🚧 Infrastructure-prepared, NOT live. Create this workflow in the n8n
> UI (`auto.kogler.si`) **after deployment** (point 3: wait until CalDAV/Signal/SMTP
> are live). Do not enable until those channels are wired.
>
> This workflow turns `group_vars/subscriptions.yml` renewal dates into a **push
> reminder** via Signal (and/or SMTP email), complementing the always-on Homepage
> tiles + calendar widget. It is the third consumer of the single `subscriptions`
> SSOT.

## Goal
Periodically (e.g. daily) scan the subscription list; for any subscription whose
`valid_until` is within `reminder_days` (default 30), send a reminder.

Single source of truth: **`group_vars/subscriptions.yml`** — same data the Homepage
tiles and calendar widget render from. No separate copy.

## Data
The list lives in IaC, not in n8n. Two ways to source it at run time:

- **Option A (recommended, true SSOT):** a scheduled Ansible/render step (or a
  webhook from the `docker_services` post-deploy hook / `render-docs.yml`) POSTs the
  `subscriptions` list (or a pre-computed `renewals` view) to an n8n **webhook**.
  The workflow listens and acts on the incoming JSON. Zero duplication.
- **Option B (fallback):** the workflow holds a small static copy of the
  `renewals` to alert on. Simpler, but drifts from IaC — avoid unless Option A is
  not feasible.

## Suggested nodes
1. **Schedule Trigger** — cron, daily (e.g. `0 8 * * *` Europe/Ljubljana).
2. **HTTP Request / Webhook** — fetch the renewals JSON (Option A payload).
3. **Code (filter)** — keep entries where `days_to_renewal <= reminder_days` and
   `status == active` and `valid_until` is set. Compute `days_to_renewal`.
4. **SMTP / Signal send** — one notification per due renewal (or an aggregate
   digest). Use the existing `signal-api` (`signal-internal_api`) and/or the SMTP
   relay (`grafana-smtp_login` / `nut-smtp_login`) — same channels Grafana alerting
   already uses (see `deployment-secrets.md`).
5. **(optional)** IFrame/card update is NOT needed — Homepage calendar widget
   already shows upcoming dates visually.

## Notification message (Slovenian, family-facing)
```
⏰ Obnovitev: {{ name }} · {{ cost }} €/mesec · do {{ valid_until }}
({{ days_to_renewal }} dni)
```

## Channels / secrets
| Channel | Node | Secret (1Password `Homelab`) |
|---------|------|------------------------------|
| Signal | `@signal-cli` / HTTP to `signal-api` | `signal-internal_api` (token), `signal_api` (phone) |
| Email  | SMTP (`mail.smtp2go.com:587` STARTTLS) | `grafana-smtp_login` / `nut-smtp_login` |

## Rollout checklist (post-deploy)
- [ ] CalDAV (kSuite, HD-30) live → populate `calendar_url` in `subscriptions.yml`
      (unlocks the Homepage calendar widget too).
- [ ] Confirm Signal + SMTP relay reachable from n8n (`services-internal`).
- [ ] Create the webhook + workflow in n8n UI per this spec.
- [ ] Enable the Schedule Trigger; test with a deliberately imminent date.
- [ ] Wire Option A data feed (post-deploy hook or scheduled render) so n8n reads
      the live `subscriptions` SSOT, not a copy.