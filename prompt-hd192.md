# prompt-hd192 — Version-pin completion (S2/D1)

> **Role:** Task handoff for **HD-192** (todo.md §2.3). Mechanical but touches ~24 templates —
> follow the verification protocol exactly. **Linked from:** [todo.md](todo.md) (HD-192);
> audit evidence: `security.md` §2 S2, `iac-changes.md` §3, CONVENTIONS §7.

## Problem

21 compose templates reference bare `:latest`; three use mutable aliases (`ollama/ollama:rocm`,
`home_assistant_version: stable`, immich `default('release')`). CONVENTIONS §7 forbids all three
patterns; HD-134 is marked done but only covered core services. `validate-docker-services.py`
currently *allowlists* the violators (`ALLOWED_LATEST`), several of which have stable semvers
upstream (homepage, metabase, pihole, technitium).

## Protocol (per pin — do not skip)

1. **Registry-verify** the exact tag once (Docker Hub / GHCR / quay — `docker manifest inspect` or
   registry API) before writing it into `group_vars/all/versions.yml`.
2. Add `*_version` to `versions.yml` with a one-line comment (service, verification date).
   Naming: follow the existing sheet (`<svc_abbrev>_version`).
3. Template: replace the literal tag with `{{ x_version }}` — **no `| default('latest')` fallback**
   (CONVENTIONS §7 amendment: missing pin aborts the render, fail-loud like secrets).
4. Special cases:
   - `ollama:rocm` → pin the current ROCm build tag; comment the ROCm-bundling rationale.
   - HA `stable` → semver pin; note primary/standby parity (HD-39 rationale).
   - immich `default('release')` → the pinned `immich_version` already exists; just drop the
     fallback in both templates.
   - gluetun (`qm12/gluetun`) → verify the fork's tag scheme before pinning.
   - linuxserver/*arr images → pin to a dated/semver tag; keep Renovate tracking.

## Validator changes (same change)

- `ALLOWED_LATEST`: reduce to **zero entries** (or only genuinely fluid tags with a MUST-pin comment
  + todo row — Tuwunel/LiteLLM precedent). Every remaining entry needs a documented justification.
- Keep the bare-`latest` failure mode; it now enforces the law instead of waiving it.

## Steps

1. Work in service batches (edge → platform → media) to keep reviewable; run
   `bash scripts/validate-all.sh` after each batch (the pin check will fail for anything missed —
   that is the point).
2. `docs/deployment-compose.md` §*arr conventions: update the "`latest` tags, Renovate-tracked"
   sentence to the pinned reality.
3. `docs/security.md` §2: refresh the stale claims (traefik "currently latest", "42 templates").
4. todo HD-192 ✅ with `⏳ Deploy-gated:` tail: "Renovate PRs arrive for the new pins; first deploy
   pulls the pinned digests successfully". changelog row (list the pinned count).

## Constraints

- Do NOT bump versions while pinning — pin what exists today per service, let Renovate propose
  updates through the normal PR path.
- `tuwunel_version: latest` and `litellm_version: main-stable` keep their documented MUST-pin
  status (HD-121 precedent) — out of scope unless the human wants them pinned now.

**Cleanup:** delete this handoff (`prompt-hd192.md`) in the same closing change (A3 lifecycle, CONVENTIONS §4; HD-203 sweeps any leftovers).
