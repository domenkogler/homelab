# Task 1 result — OpenCloud ↔ ONLYOFFICE editor round-trip wiring (HD-166)

**Status:** verified as far as a read-only agent can (2026-08-24; no mutation, no secret values).
**Final human step (owner):** open a `.docx` in the file.kogler.si web UI and confirm the ONLYOFFICE iframe loads + edits round-trip.

## Verified live (read-only probes via WSL runner)

- Containers: `opencloud` Up, `onlyoffice-docs` Up, `onlyoffice-rabbitmq/postgres/redis` healthy.
- ONLYOFFICE `/healthcheck` (internal) → `true` (the earlier `/healthcheck` 404 was my wrong probe path, not a real fault).
- Public routes: `office.kogler.si` → 200, `file.kogler.si` → 200 (Traefik + certs OK per HD-231).
- opencloud container env (names, values redacted): `OC_ADD_RUN_SERVICES=collaboration`,
  `COLLABORATION_APP_NAME/PRODUCT=OnlyOffice`, `COLLABORATION_APP_ADDR=https://office.kogler.si`,
  `COLLABORATION_WOPI_SRC=https://file.kogler.si`, `COLLABORATION_STORE=nats-js-kv`,
  `COLLABORATION_APP_PROOF_DISABLE=false`, `COLLABORATION_APP_INSECURE=false`,
  `PROXY_CSP_CONFIG_FILE_LOCATION=/etc/opencloud/csp.yaml` (+ `opencloud-collab_password` JWT lookup).
- onlyoffice-docs env: `JWT_ENABLED`, `JWT_SECRET`, `JWT_HEADER` present (JWT auth on, same-shared-JWT design).
- `/etc/opencloud/opencloud.yaml` inside the container contains a real `collaboration:` block with `wopi:` subkeys — the WOPI integration is registered.

## Flag (real, needs a decision)

`OC_ADD_RUN_SERVICES=collaboration` AND `OC_EXCLUDE_RUN_SERVICES=collaboration,idp` are BOTH set on the opencloud container. The `exclude` explicitly lists `collaboration`, which could disable the very service the `add` tries to start. Precedence in OpenCloud's runtime is not obvious from config alone; the collaboration svc has no separate port answering (one in-process binary). **Recommendation:** confirm via the owner's actual docx-open test; if the iframe fails to load, remove `collaboration` from `OC_EXCLUDE_RUN_SERVICES` (keep `idp`) and restart opencloud — then re-test. The duplicate mention is likely an artifact of wiring `collaboration` into both lists while cloning the `idp` exclusion.

## Task 1 conclusion

HD-166 stack is deployed and healthy; the one thing a bot cannot do is click "open document" in a browser. Owner round-trip test is the single remaining gate — the prompt.md §3b-1 item resolves once that's done.