# Task 1 result — OpenCloud ↔ ONLYOFFICE editor round-trip (HD-166)

**Status: PARTIAL — .txt preview/edit WORKS; real office docs (.docx) do NOT open in the editor.** The ONLYOFFICE
stack is deployed and healthy, but the WOPI/app-provider path for office MIME types is NOT functional yet.
**This is the single most important open item to hand off — needs a real fix, not just a bot verify.**

## Verified live (read-only probes via WSL runner, 2026-08-24)

- Containers: `opencloud` Up, `onlyoffice-docs` Up, onlyoffice-rabbitmq/postgres/redis healthy.
- ONLYOFFICE `/healthcheck` (internal) → `true`; public routes `office.kogler.si` → 200, `file.kogler.si` → 200.
- `office.kogler.si/` → 302 → `/welcome/` → 200 (standard OnlyOffice DS first-run page; Docs Server healthy).
- opencloud env: `OC_ADD_RUN_SERVICES=collaboration`, `COLLABORATION_APP_NAME/PRODUCT=OnlyOffice`,
  `COLLABORATION_APP_ADDR=https://office.kogler.si`, `COLLABORATION_WOPI_SRC=https://file.kogler.si`,
  `COLLABORATION_STORE=nats-js-kv`, `COLLABORATION_APP_PROOF_DISABLE=false`, `COLLABORATION_APP_INSECURE=false`,
  `PROXY_CSP_CONFIG_FILE_LOCATION=/etc/opencloud/csp.yaml` (+ `opencloud-collab_password` JWT lookup).
- onlyoffice-docs env: `JWT_ENABLED`/`JWT_SECRET`/`JWT_HEADER` present (shared-JWT design).
- `/etc/opencloud/opencloud.yaml` has a real `collaboration:` block with `wopi:` subkeys.

## Owner round-trip test results (2 browsers)

| File | Result |
|---|---|
| **.txt** | ✅ Preview + editor; editing and Save work; updates persist on reopen. "updated outside this window" = save-conflict guard, not error. |
| **.docx** (real office file) | ❌ **"No preview available … download instead"** — the ONLYOFFICE editor does NOT open office docs. |

## Diagnosed root cause (high confidence, needs confirmation)

- The `.txt` "opening" is OpenCloud's **native text preview** — it never invoked the ONLYOFFICE/WOPI editor.
- Real office docs fall through to "download" because the **OpenCloud `frontend.app_handler` / app-provider is not
  registering `application/vnd.*` (office MIME) → OnlyOffice** for the editor link.
- Likely contributors (in order of suspicion):
  1. **No live-edit / app-provider store:** `COLLABORATION_STORE=nats-js-kv` but **there is NO NATS broker
     container** on the VPS — the `collaboration` service's registry/store has nowhere to announce OnlyOffice's
     office-MIME authoring. (Earlier "no NATS needed" conclusion was WRONG for `.docx` — it's not about live
     typing, it's about the app-provider registry.)
  2. **Rendered yaml says `collaboration.app.insecure: true` despite env `COLLABORATION_APP_INSECURE: "false"`**
     — env→schema mapping for this flag may not be taking effect (opencloud.yaml rendered from env at startup).
  3. `OC_ADD_RUN_SERVICES=collaboration` AND `OC_EXCLUDE_RUN_SERVICES=collaboration,idp` BOTH list it — ADD wins
     (editor/health works), EXCLUDE mention is inert; not the blocker, but confusing.

## Next-session action (real fix, not verify)

1. Investigate OpenCloud 7.4 `collaboration` service REQUIRED runtime deps: does `.docx` WOPI authoring need a
   NATS broker (`nats:2.x` on services-internal, `COLLABORATION_STORE_NODES`) or a working micro-registry?
   If yes → add the nats container to the compose + converge (other session).
2. Verify the `COLLABORATION_APP_INSECURE` env actually maps (fix env name/schema if not).
3. Confirm with OnlyOffice/OpenCloud docs that the office MIME list is registered by the app-provider.
4. Re-test `.docx` in file.kogler.si after each change.

## Security note

A live probe once dumped real secret VALUES from the container's opencloud.yaml into a transcript (violating the
HD-235 secret-hygiene rule). **No action needed on those secrets** (they belong in the container config), but future
probes MUST redact `secret/password/token/bind_password` values. Do not re-display them.

## Task 1 verdict

**NOT done.** Deploy + health verified, but `.docx` editing/round-trip is **broken** and needs the app-provider/
NATS fix above. Move this to the top of the next-session queue (owner already tested; evidence is in
deployment-journal.md).