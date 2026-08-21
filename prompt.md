# prompt.md — Fanout: three parallel audit-remediation sessions (+ waves)

> **Role:** Active handoff — supersedes the 2026-08-21 audit brief (archived in git history; all its
> deliverables are done and tracked as HD-175…204). Organizes the remaining laptop-doable work into
> three disjoint sessions plus follow-up waves.
> **Linked from:** [README.md](README.md) §2 · task board: [todo.md](todo.md) · per-task detail in
> the `prompt-hd*.md` handoffs · decisions: changelog HD-178…204.

---

## 0. Ground rules (every session, read first)

1. Bootstrap: read `README.md` → mandatory context chain; state your environment (platform-env).
2. **Own branch:** `git checkout -b audit/a` (or `audit/b`, `audit/c`). Never commit to `main`.
3. One task at a time: implement → `bash scripts/validate-all.sh` green → update the todo row
   (✅ / ⏳ tail) → move the done row to `changelog.md` → delete that task's `prompt-hd*.md`
   (A3 lifecycle) → commit.
4. **AI + gate rows pause for human review before merge:** HD-181, HD-182, HD-183, HD-185, HD-186.
5. Decisions are already made (changelog HD-178…204) — do not re-open them.
6. Merge order is **A → B → C**: later sessions rebase onto main after the earlier one merges
   (see §4). `group_vars/all.yml` protocol: Session A commits its all.yml change in its FIRST
   commit; B and C rebase, then append their vars in clearly-commented sections.

---

## 1. Session A — Gate, supply chain & sweeps (branch `audit/a`)

In-session order: **HD-189 → HD-192 → HD-202 → HD-197 → HD-201 → HD-200**

| Task | Scope |
|------|-------|
| HD-189 (P1) gate hardening | `validate-secrets.py` scope (+templates/vars/files), fail-open loader fix, DELETE dead `NETWORK_MAP` (decided), `_extra_templates` from role defaults, BASE_CTX mock fixes, new vault-name lint + offender fixes (**only the one comment line in `roles/home_assistant/tasks/main.yml` — C owns that role**) |
| HD-192 (P1) version pins | `versions.yml` + image-line sweep over ~24 templates; drop `default('latest')`; ALLOWED_LATEST → zero/justified; validator denylist. **Finish before starting HD-202 (same files)** |
| HD-202 (P3) container hardening | roll `cap_drop`/`read_only` into templates (GPU/VPN/gluetun exempt); signal-captcha exception note |
| HD-197 (P3) scripts hygiene | validate_doc_templates real-vars, rack header, doc_ips/doc_map scopes, SMART files move, syntax-check gate |
| HD-201 (P3) preseed assertions | placeholder asserts in post_install + repo grep gate |
| HD-200 (P3) SSOT dedup | **all.yml VLAN-map dedup (FIRST commit of the session)**, router/switch derive views, AllowedIPs cross-links, home_ip dup |

Owns exclusively: `scripts/*`, `versions.yml`, `validate-all.sh`, image-tag lines, preseeds, reports/.

---

## 2. Session B — VPS edge & public security (branch `audit/b`)

In-session order: **HD-186/190 → HD-181 → HD-188 → HD-194 → HD-195**

| Task | Scope |
|------|-------|
| HD-186 (P1) S1 bypass | remove authentik 3389 publish; option B documented already (security.md §8); verify plan into services-vps checklist |
| HD-190 (P2) header trust | authentik TRUSTED_PROXIES pinning + grafana signed-header/signup-off; adds `traefik_edge_ips` to **all.yml (rebase on A)** |
| HD-181 (P1) single issuer | `acme_issuer` flag, traefik template conditionalization, certresolver-label sweep (~26 templates), tls.yml.j2 consumers, cert-sync retarget (oldsrv own timer — decided), BASE_CTX var (**rebase on A's validator**) |
| HD-188 (P2) cockpit routes | derive IPs from SSOT + crowdsec-only middleware |
| HD-194 (P3) sso route | enforce crowdsec-only; documented exception only if outpost callbacks break |
| HD-195 (P2) phase sweep | `deployment-tasks.md` only (exclusive) |

Owns exclusively: nftables/vps-hardening, traefik/authentik/grafana/cockpit template security bits,
services-traefik.md, services-vps.md, deployment-tasks.md.

---

## 3. Session C — Home hosts, network & backup (branch `audit/c`)

In-session order: **HD-185/72 → HD-182 → HD-187 → HD-184 → HD-183 → HD-191**
(non-template tasks first if A hasn't merged yet)

| Task | Scope |
|------|-------|
| HD-185 (P1) Pi ordering | option A render-first (decided): playbook reorder + role comments + regular-file guard |
| HD-72 (P1) HA caps | privileged/host-net → targeted devices/cap_add |
| HD-182 (P2) Kids VLAN + DNS parity | router role rules (bedtime scheduler, filtered DNS force, Kids→Home drop) + secondary-resolver forward rule |
| HD-187 (P2) pihole CF IP | one-liner: CONDITIONAL_FORWARDING_IP → dns_primary_ip |
| HD-184 (P1) immich ML URL | derived URL var (**all.yml — rebase on A**) + publish :3003 bound to oldsrv Home IP |
| HD-183 (P1) Homepage → VPS | move entry home_servers.yml→vps.yml (**rebase on B for acme flag section**), ALLOWED_HOSTS alias, route note |
| HD-191 (P2) Kopia agent | containerized agent template + home_servers.yml + backup.md alignment |

Owns exclusively: home_servers.yml service list, router role tasks, network-vlans.md, HA/Pi roles,
pihole/immich/homepage/kopia-agent templates, backup.md.

---

## 4. Merge & wave plan

1. **Merge A → main** when its session ends (or incrementally per task). B and C rebase.
2. **Merge B**, then **C** (C last: its template edits rebase on A's sweeps + B's labels).
3. At each merge: `bash scripts/validate-all.sh` green on main before continuing.
4. **Wave 2 (after A+B+C merged, one session):** HD-196 stale-docs sweep → HD-199 docs structure
   pass → execute HD-198 incrementally as services go live (Cloudflare applies are human-gated).
5. **Wave 3 (last, single session):** HD-203 — fold-and-delete the round-2 audit reports +
   any leftover prompt-hd*.md (A3 lifecycle).

Excluded (not laptop-doable / human-blocked): all ⏳ deploy-gated live-verify rows (HD-03, 06/08/09,
40A/B, 147/149…), purchases (HD-30), physical steps (HD-17/18/27).

Known small overlaps (accepted, different lines): templates/** swept by A(192/202) then B(181);
validate-docker-services.py touched by A(189) then B(181 BASE_CTX); vps.yml sections B(acme) vs
C(homepage); smart-home-failover.md B(sync note) vs C(ordering).
