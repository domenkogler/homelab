# prompt.md — Fanout brief: this session orchestrates three remediation workers (+ waves)

> **Role:** Active handoff. The session that reads this file is the **ORCHESTRATOR**: it fans out
> three isolated worker sessions (A/B/C), supervises them, merges their branches in order, then
> runs the follow-up waves. Supersedes the 2026-08-21 audit brief (archived in git history;
> deliverables tracked as HD-175…204).
> **Linked from:** [README.md](README.md) §2 · board: [todo.md](todo.md) · per-task detail in
> `prompt-hd*.md` · decisions: changelog HD-178…204 (fixed — do not re-open).

---

## 0. Orchestrator rules

1. Bootstrap first: read `README.md` → mandatory context chain; state environment (platform-env).
2. **Fanout mechanics:** use the subagent tool with **worktree isolation** (`worktree: true`) so
   every worker gets its own checkout + branch (`audit/a|b|c`). Workers never touch `main`;
   the orchestrator owns all merges. If subagent worktree isolation is unavailable, create the
   worktrees yourself (`git worktree add ../homelab-X audit/x`) and point each worker at its dir.
3. **Phasing:** Worker A runs FIRST alone (its early commits unblock `all.yml` + the validators).
   After A merges, Workers B and C run IN PARALLEL (their mutual overlap is small, different
   lines). Merges stay sequential: A → B → C.
4. **Gates are pre-decided** (changelog HD-178…204 + the prompt-hd* handoffs carry the chosen
   options), so workers do NOT pause mid-run: the human reviews each worker's diff at its merge
   instead. If a worker still requests a decision, relay it to the human, then steer the worker.
5. Per-task lifecycle inside every worker: implement → `bash scripts/validate-all.sh` green →
   todo row ✅/⏳ tail → done row moved to `changelog.md` → delete that task's `prompt-hd*.md`
   (A3 lifecycle) → commit on the worker branch.
6. Every worker message must include: branch name, task list, the ground rules above, and its
   `prompt-hd*.md` files to read. Workers are read-write ONLY inside their own worktree.

---

## 1. Worker A — Gate, supply chain & sweeps (branch `audit/a`, runs first)

Order: **HD-189 → HD-192 → HD-202 → HD-197 → HD-201 → HD-200**

| Task | Scope |
|------|-------|
| HD-189 (P1) | gate hardening: secrets-lint scope (+templates/vars/files), fail-open loader fix, DELETE dead `NETWORK_MAP` (decided), `_extra_templates` from role defaults, BASE_CTX mock fixes, vault-name lint + offender fixes (**only the one comment line in `roles/home_assistant/tasks/main.yml`**) |
| HD-192 (P1) | version pins: `versions.yml` + image-line sweep (~24 templates), drop `default('latest')`, ALLOWED_LATEST → zero/justified. **Finish before HD-202 (same files)** |
| HD-202 (P3) | roll `cap_drop`/`read_only` into templates (GPU/VPN/gluetun exempt); signal-captcha exception note |
| HD-197 (P3) | scripts hygiene: validate_doc_templates real-vars, rack header, doc_ips/doc_map scopes, SMART move, syntax-check gate |
| HD-201 (P3) | preseed placeholder assertions + repo grep gate |
| HD-200 (P3) | SSOT dedup: **all.yml VLAN-map dedup (FIRST commit)**, router/switch derived views, AllowedIPs cross-links, home_ip dup |

## 2. Worker B — VPS edge & public security (branch `audit/b`, parallel after A)

Order: **HD-186/190 → HD-181 → HD-188 → HD-194 → HD-195**

| Task | Scope |
|------|-------|
| HD-186 (P1) | remove authentik 3389 publish (option A); verify plan into services-vps checklist |
| HD-190 (P2) | header trust: TRUSTED_PROXIES pinning + grafana signed-header/signup-off; adds `traefik_edge_ips` to **all.yml (rebase on A)** |
| HD-181 (P1) | single issuer: `acme_issuer` flag, template conditionalization, certresolver-label sweep (~26 templates), tls.yml.j2 consumers, cert-sync retarget (oldsrv own timer); BASE_CTX var (**rebase on A's validator**) |
| HD-188 (P2) | cockpit routes: SSOT-derived IPs + crowdsec-only middleware |
| HD-194 (P3) | sso route: enforce crowdsec-only; documented exception only if callbacks break |
| HD-195 (P2) | deployment-tasks phase sweep (exclusive file) |

## 3. Worker C — Home hosts, network & backup (branch `audit/c`, parallel after A)

Order: **HD-185/72 → HD-182 → HD-187 → HD-184 → HD-183 → HD-191**
(non-template tasks first if A hasn't merged yet)

| Task | Scope |
|------|-------|
| HD-185 (P1) | Pi ordering option A (render-first): playbook reorder + role comments + regular-file guard |
| HD-72 (P1) | HA primary privileged/host-net → targeted devices/cap_add |
| HD-182 (P2) | Kids VLAN rules (bedtime scheduler, filtered-DNS force, Kids→Home drop) + DNS-parity fixes |
| HD-187 (P2) | pihole CONDITIONAL_FORWARDING_IP → dns_primary_ip (one-liner) |
| HD-184 (P1) | immich ML URL: derived var (**all.yml — rebase on A**) + publish :3003 bound to oldsrv Home IP |
| HD-183 (P1) | Homepage → VPS: move entry (**vps.yml — rebase on B's acme section**), ALLOWED_HOSTS alias |
| HD-191 (P2) | containerized Kopia agent + home_servers.yml + backup.md alignment |

---

## 4. Merge & wave plan (orchestrator)

1. Worker A completes → orchestrator reviews the diff (gate), merges `audit/a` → main,
   `bash scripts/validate-all.sh` green.
2. Launch Workers B + C in parallel (each rebased on updated main). As each finishes: review,
   merge sequentially (B then C), validate green after each.
3. **Wave 2** (one worker on main): HD-196 stale-docs sweep → HD-199 docs structure pass.
   Execute HD-198 incrementally later, as services go live (Cloudflare applies are human-gated).
4. **Wave 3** (last): HD-203 — fold-and-delete the round-2 audit reports + leftover prompt-hd*.md.

Excluded (not laptop-doable / human-blocked): ⏳ deploy-gated live-verify rows (HD-03, 06/08/09,
40A/B, 147/149…), purchases (HD-30), physical steps (HD-17/18/27).

Known small overlaps (accepted, different lines): templates/** swept by A(192/202) then B(181);
validate-docker-services.py by A(189) then B(181 BASE_CTX); vps.yml sections B(acme) vs C(homepage);
smart-home-failover.md B(sync note) vs C(ordering).
