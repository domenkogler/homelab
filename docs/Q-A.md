---
title: Q&A — docs SSOT cleanup session
role: scratch
domain: meta
status: temporary
tags: [qa, cleanup]
---
# Q&A — docs cleanup (session `docs-ssot-cleanup`, 2026-09-20)

> **Role:** Open questions from the docs-cleanup session. **Answer inline under each `**A:**`** — the
> answers steer the rest of the sweep. This file is session-scoped scratch: it is deleted before the
> session's final commit (it is listed in `index.md` only so `check_doc_map.py` stays green meanwhile).
> **Path note:** this lives in the session worktree
> `../homelab-wt-20260920-0114/docs/Q-A.md`, not the primary checkout.

---

## Q1 — Do the `✅ live` markers stay in the docs?

The sweep removes dated execution narrative ("LIVE 2026-09-08", "converged failed=0", "verified this
session"). But `README.md` §2 says the owning-doc **✅ status lines are the live-vs-authored-only proof**,
second only to the `deployment-tasks.md` ledger. Removing them entirely would lose "is this actually
running?" knowledge, which *is* current state.

**My working rule (already applied to `network-vlans.md`):** keep a short glyph — `✅ live` /
`⏳ deploy-gated <what remains>` / `planned` — and drop the date + the narration of the run that proved it.

**A:**

## Q2 — Do `HD-XXX` references stay in the docs?

HD numbers are the `todo.md` backlog IDs. Some doc sentences are pure history whose only content is
"HD-339 done". I keep HD refs where they point at a *live* backlog item or name a decision, and drop them
when the sentence's only payload was "this happened".

**A:**

## Q3 — Domains with no `-rejected.md`

`observability`, `security`, `interfaces`, `pi-harness`, `backup`/`storage`-adjacent decisions sometimes
have nowhere to land. `services-rejected.md` already absorbs observability/spark-monitoring decisions.

Options: (a) keep appending them to the nearest domain log (currently `services-rejected.md`);
(b) create `observability-rejected.md` + `security-rejected.md` (needs an `index.md` map line + the
`<domain>` header convention).

**My default:** (a) — no new files, no map churn.

**A:**

## Q4 — `spark-incidents.md` and `*-review.md`

Both are explicitly append-only logs. You said `-review`/`-rejected` must not be truncated — I read that
as covering `spark-incidents.md` too: **untouched**, except removing nothing. Confirm? (It is 291 lines of
dated incident narrative, which is exactly the shape you dislike — but it is a deliberate log, so I keep it.)

**A:**

## Q5 — `-generated.md` drift

If a generated doc disagrees with IaC, the fix is in IaC (and possibly a live converge), not the MD.
**My default:** never hand-edit generated docs; I record the drift as a finding in the final report + a
`todo.md` row only if a row already exists. Say otherwise if you want new HD rows opened for drift I find.

**A:**

## Q6 — `docs/manual/` (family, Slovenian)

**My default:** out of scope — no dated-narrative sweep of the family guides (they are procedure for
humans, and mostly still deferred/stubs). Only touched if a link breaks.

**A:**

## Q7 — Where does "obsolete but never actually decided" go?

E.g. a capability we tried and found does not exist (MikroTik per-MAC VLAN), a value that was wrong and is
now corrected (`/32` → `/24`), a flag that was reverted. These are not rejections of a candidate tool.
**My default:** they still go in the domain `-rejected.md` with status `superseded` / `corrected` /
`not-a-capability`, because that log is where the *reason the doc changed* belongs, and it is append-only
so nothing is destroyed. Alternative: a separate "corrections" section. Tell me if you want a different
status vocabulary.

**A:**

## Q8 — Concurrency with `session/ai-vision-tier-placement`

That lane will likely edit `services-ai.md`, `services-ai-bench.md`, `hardware-gpu.md`, `hardware-spark.md`,
`spark-incidents.md`, `todo.md`. I am doing the **other** domains first, checking `main` before every
commit, and will re-apply the AI-tier docs last (merging their version as the base). Tell me if that lane
is about to land something bigger (e.g. a new doc file) and I will avoid that area entirely.

**A:**

## Q9 — How aggressive on `deployment-*.md` "live-verified" prose?

`deployment-*` docs are authoring specs (★) for IaC. They carry a lot of "this was fixed live on <date>"
justification inside spec text. Removing it can also remove the *reason* a spec rule exists (which is
current knowledge: "the task must do X because Y fails otherwise"). **My default:** keep the mechanism and
the failure mode, delete the date and the session narration.

**A:**

## Q10 — Is it OK to delete a whole section?

Some sections are 100 % history (e.g. a "Phase 1 static-IP sweep DONE" list whose surviving content is a
checkmark). If every fact in it is already stated elsewhere in the same doc, I delete the section; if any
fact survives only there, I keep that fact as a plain spec line. **Nothing gets deleted just because it is
old.** Confirm that is the intent, or say "never delete a heading, only rewrite it".

**A:**

---

## Findings in **IaC**, not docs — deliberately not touched by this sweep

Each of these is a stale *fact in code/config*, found while reading docs. Docs now say the true thing
or flag the item; the fix belongs in a code commit with its own validation.

1. **`roles/amd_rocm` still writes `OLLAMA_KEEP_ALIVE` to `/etc/environment`**
   (`tasks/main.yml:69`) although there is no host Ollama. Harmless but misleading; the pinned tier is
   `llama-server`/`whisper-server`, which ignore it.
2. **`group_vars/all/main.yml:323` describes the `llm-backend` bridge as "LLM backend (Ollama) ↔ LiteLLM"**
   — that string flows into the generated `network-addresses-generated.md`, so the generated doc still
   names Ollama. Change the purpose string, don't hand-edit the generated file.
3. **VPS LiteLLM scoped-key allow-lists are still Ollama-era** (`group_vars/vps.yml`):
   `openclaw` allows `ollama/*`, `owui-int` allows `ollama/bge-m3,ollama/bge-reranker-v2-m3`, and the
   `open-webui` row is `openai/gpt-5.5` + `anthropic/claude-opus-4-8` with no spark/local model.
   `docs/services-ai.md` §Consumers now states the intended shape and marks this ⏳ (same fix as HD-384:
   consumers have no `litellm_user_id`, so spend tracking 400s and `/key/update` cannot extend them).
4. **`home-assistant-primary` compose renders HA `environment: {}`** while `services-ai.md` documents
   `LITELLM_BASE_URL`/`LITELLM_API_KEY` as the mechanism — HA today cannot reach the gateway at all.
   Needs the env wiring (or an explicit decision that HA's Assist uses something else).
5. **`docs/services-ai-bench.md` §4 still names `tailscale-scale-test-...:8443` as the live
   `SPARK_LLM_BASE_URL`** while §4a records it as torn down and the live edge being `llm.kogler.si`.
   Docs now point at §4a; the bench file's own §4 is a measurement record, so it was left alone.
