# prompt-hd181 — Single cert issuer: `acme_issuer` flag (HD-178 decision)

> **Role:** Task handoff for **HD-181** (todo.md §2.4). **AI + gate.** The subtle part is the
> consumer-TLS strategy — read this fully before touching templates.
> **Linked from:** [todo.md](todo.md); decisions: changelog HD-178; audit: `docs-vs-iac.md` J3/C1.

## Goal

Exactly one host runs ACME for `*.kogler.si`: the **VPS** (HD-178). oldsrv's internal Traefik and
the Pi `traefik-ha` become cert **consumers** (synced pair). Docs are already aligned ✅ — this task
is the IaC mechanism + the S1 verify line.

## Mechanism

1. Var: `traefik_acme_issuer` — default `false` in `roles/docker_services/defaults/main.yml`
   (role-internal knob per conventions), override `true` in `group_vars/vps.yml`.
2. `traefik/docker-compose.yml.j2` — wrap in `{% if traefik_acme_issuer %}`:
   `CF_DNS_API_TOKEN` env, the four `--certificatesresolvers.letsencrypt.*` command flags,
   the `./acme` volume, and the whole `certs-dumper` service. Consumer side adds a **read-only
   certs mount**: `./certs:/etc/traefik/certs:ro`.
3. **Consumer TLS strategy — the trap:** ~26 templates carry
   `traefik.http.routers.X.tls.certresolver: letsencrypt` labels, and consumers have no such
   resolver → routers fail to load in Traefik. Strategy:
   - Wrap every certresolver label line in `{% if traefik_acme_issuer %}…{% endif %}`
     (use `{% if traefik_acme_issuer is defined and traefik_acme_issuer %}` — Undefined-safe with
     the validator's mock filters; add `traefik_acme_issuer: true` to validator `BASE_CTX` so the
     issuer path stays tested).
   - Consumers serve TLS from the **default store**: new extra template
     `traefik/dynamic/tls.yml.j2` declaring `tls.certificates` + `stores.default.defaultCertificate`
     pointing at `/etc/traefik/certs/{{ wildcard_cert_file }}/-key.pem`; content wrapped so it
     renders empty on the issuer (avoids missing-file errors before first issuance).
   - File-provider routes (`traefik/dynamic/routes.yml.j2` ha route, cockpit template,
     `traefik-ha/dynamic/routes.yml.j2`) currently say `certResolver: letsencrypt` with no resolver
     defined — **pre-existing latent bug on the Pi edge**; switch them to rely on the default store
     (drop the certResolver key) or explicit certFile/keyFile pairs.
4. Cert-sync retarget: `roles/home_assistant/templates/ha-cert-sync.sh.j2` pulls from oldsrv —
   retarget to the VPS (`ansible_host` from SSOT; path `/opt/traefik/certs`). Key authorization on
   the VPS is a live step → ⏳ tail. oldsrv also needs the pair locally: same sync (second consumer)
   or an oldsrv-side pull timer — pick one, document in smart-home-failover.md.

## Steps

1. Flag + traefik template conditionalization + tls.yml.j2 + label sweep (scripted sed over
   `templates/docker_services/*/*.j2` + `*/*/*.j2`, then eyeball `git diff`).
2. traefik-ha routes fix; cockpit template follows HD-188 (coordinate, don't duplicate).
3. Sync-script retarget + doc touch-ups left in the four aligned docs (remove "⏳ HD-181" markers).
4. Validator: BASE_CTX var + confirm all 49 render; `bash scripts/validate-all.sh` green.
5. todo HD-181 ✅ IaC; ⏳ tails: VPS first issuance, Pi/oldsrv sync verified, S1 verify line added
   to services-vps checklist. changelog row closing J3/C1/W11.
