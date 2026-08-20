# Prompt: HD-174 — Bootstrap `docs/services-review.md` + `docs/services-rejected.md`

> Handoff written 2026-08-20. Goal: seed the per-domain triage pattern for the services domain —
> an intake queue (`-review`) and an append-only decision log (`-rejected`) — and populate the latter
> from `changelog.md`. **Analysis + Q/A first.**

## Task
Create `docs/services-review.md` and `docs/services-rejected.md` following `CONVENTIONS.md` §8.3, and
populate `-rejected` with historical "we evaluated and said no" decisions from `changelog.md`.

## Context
- §8.3: `<domain>-review.md` = intake queue (near-empty); a row = service name + URL + a 3-word "why".
  `<domain>-rejected.md` = append-only decision log, **sorted by service name**, each entry
  `| <service> | <rejected|dropped|superseded> | <date> | <why, 1–2 lines + evidence link> |`.
- **Lifecycle:** (1) before adding to `-review`, check `-rejected` first (rejected is consulted, not
  auto-blocking); re-review allowed only with an exception note. (2) Promote → move row to `todo.md`
  as HD-XXX (pointer back), then delete from `-review`. (3) Stale 30 days → promote to `todo.md` or
  move to `-rejected`. Review is a queue, not a backlog.
- Changelog candidates to seed `-rejected` (services that were dropped/retired/rejected):
  Doco-CD (HD-150, dropped), Proxmox (HD-92, deferred — arguably not "rejected" but a decision),
  watchtower (HD-39, decided against), iDrive (storage, dropped), MinIO (retired, HD-135), TileBoard
  (retired, HD-24), netplan (rejected, HD-56), GoCardless/Nordigen (superseded by Enable Banking,
  services-finance), Ghostfolio (skipped, services-finance), AnythingLLM/LocPilot (retired,
  AI stack). Confirm the exact list in the Q/A.

## Sequence of Work (MANDATORY)
1. **Analysis.** Read `CONVENTIONS.md` §8.3 + `changelog.md` (all decision rows) + `docs/index.md`.
   Compile the full candidate list of historical "rejected/dropped/retired/skipped/superseded"
   decisions with their HD refs and evidence links.
2. **Q/A.** Ask (written): Confirm the entry schema (`| service | status | date | why + link |`)?
   Set the exact tolerance for defer-vs-reject (Proxmox is deferred, not rejected)? Which of the
   candidate list are truly "rejected" vs "superseded/dropped"? Any services you've rejected that are
   not yet in changelog?
3. **Execute** after Q/A:
   - Create `docs/services-review.md` (empty-ish queue; a few example rows named with URL + 3-word why).
   - Create `docs/services-rejected.md` populated from the confirmed changelog decisions, sorted by
     service name, append-only, with HD + date + evidence links.
   - Link both from `services.md` (or its index) + register both in the `docs/index.md` Document Map
     (doc-map linter enforces). Add both to `services.md`'s "Related"/index.
4. **Validate.** `validate-all.sh` green. Update HD-174 → `changelog.md`, delete `prompt-hd174.md`.

## Guardrails
- `-rejected` is **append-only** — never edit/reorder an entry after it lands; a changed decision is a
  new appended entry (mirror `changelog.md` decision-log style).
- Review rows stay **thin** (name + URL + 3-word why); a paragraph-length entry belongs in
  `brainstorming/` or a `todo.md` HD, not `-review`.
- The 30-day stale rule is the anti-tool guard — state it visibly in `-review.md`.
- Do **not** drop the SSOT fact that the rejected log mirrors `changelog.md` decisions — reviews may
  re-referrence the owning doc.

## Definition of done
Both files exist with correct headers + doc-map rows; `-rejected` is populated from changelog, sorted
by service name, append-only; `-review` is a thin queue; both link from `services.md`; `validate-all.sh`
green; HD-174 → `changelog.md`; prompt deleted.