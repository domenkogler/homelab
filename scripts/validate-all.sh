#!/usr/bin/env bash
# Repo validation gate — run before committing any change.
#   bash scripts/validate-all.sh          (Linux, macOS, Windows git-bash)
#
# Runs every automated checker referenced in docs/index.md → Conventions:
#   1. validate-docker-services.py  — compose templates + group_vars list
#   2. validate_blueprints.py       — Authentik ks-oidc.yml blueprint shape
#   3. check_doc_ips.py            — no internal IP literals outside the SSOT
#   3b. check_traefik_host_rules.py — no whitespace inside a Host() rule (HD-432: a
#                                     template-space bug made ha.ts.kogler.si unmatchable
#                                     for months while every converge reported success)
#   4. validate_doc_templates.py   — SSOT doc templates render with group_vars
#   5. validate-secrets.py         — no literal credentials in group_vars/templates
#   6. check_doc_map.py            — docs/index.md document map matches docs/ tree
#   7. check_generated_suffix.py    — every machine-generated doc carries the -generated suffix
#   8. check_vault_name.py          — vault is 'Homelab-ansible' (no bare Homelab refs, HD-189)
#   8b. check_ledger_state.py       — deployment-tasks.md is a LEDGER: deploy-gated items are
#                                     checkboxes, every OPEN one has a live todo.md row, every tick
#                                     carries a date (no HD status prose pasted into the blocks)
#   8c. check_runbook_purity.py     — deployment-manual.md is PROCEDURE: no status glyphs, no
#                                     dated/execution history, no duplicate headings, and its phase
#                                     numbering matches the ledger's (HD-253-class drift gate). The
#                                     capture admits a trailing a or b only, so a phase written with
#                                     any other suffix is never compared — the checker names that
#                                     hole on record and --self-test canaries it
#   8d. check_vault_docs.py         — every vault item the IaC reads has a row in the secrets master
#                                     list (an undocumented prerequisite fails a true-zero deploy).
#                                     The required set is derived from the IaC — lookups, the
#                                     `_service_vault_items` registry and every `*_item:` scalar in
#                                     host_vars AND group_vars (an item reached through a variable is
#                                     a dependency, not an optional mention). The row is also READ:
#                                     a field= cell must state a field or declare there is none
#                                     here, never claim the item does not exist (HD-1157).
#   9. check_placeholders.py        — placeholder tokens only in designated bootstrap files (HD-201)
#  10. guard-session.sh             — session-discipline hard-gate + sandboxed self-test (HD-253):
#                                     --validate-mode fails on primary+main+DIRTY; clean-main
#                                     merge-station runs pass silently; self-test fixture asserts
#                                     the guard contract inside throwaway temp repos
#  10b. guarded-converge.sh --self-test — the post-converge liveness verdict must
#                                     refuse a crash-looping container (HD-436: a
#                                     service that exits at every start still reports
#                                     Running=true between crashes; the pinned
#                                     headscale does exactly that when both
#                                     extra-record settings are set)
#  11. testdata/check-vault-items/run.sh — check-vault-items.sh scanner self-test
#                                     (HD-244/245): *_item registry-key parsing + --strict
#                                     contract asserted on a committed synthetic mini-tree.
#                                     ⚠ It was ADVERTISED AND NOT RUN from the day it was numbered:
#                                     the header echoed, then nothing invoked it (only the
#                                     portability `bash -n` sweep touched the file). 2026-10-09.
#  12. Portability sweep — bash -n (all POSIX/bash shebang scripts) + python3 -m py_compile
#                                     (all scripts/*.py), so scripts cannot regress on the
#                                     Debian/WSL ext4 primary (HD-256); bash -n is a no-op on
#                                     hosts without bash (CI/Linux only, never Windows)
#  13. sync-skills.sh --check --strict — skill drift gate (HD-254): repo skills/ must equal
#                                     ~/.pi/agent/skills (repo = SSOT). Guarded: when
#                                     $HOME/.pi/agent/skills is absent (bare CI / non-pi laptop)
#                                     the gate SKIPs so a pi-less host never breaks validation;
#                                     on a pi-configured runner deploy is via sync-skills.sh --push.
#                                     Its --self-test (HD-1135, 2026-10-12) is a separate item: the
#                                     script had NO test of its own, which is why its encoding guard
#                                     could not be made fork-free when its sibling's was — breeds drift
#                                     / untracked / artifact / CRLF / BOM / binary in a temp HOME and
#                                     refuses a canary that passes (teeth proven by mutation, not hope).
#  14. check_todo_done.py            — todo.md §4(a) sweep: flag rows marked DONE/✅ that were
#                                     not deleted (fully-done rows must be removed; only
#                                     deploy-gated rows with a real ⏳ tail stay), and stale ⏳
#                                     markers inside struck/rejected/parked fragments (2026-09-08)
#                                     + `--self-test`: the marker GRAMMAR (case-sensitive,
#                                     word-boundary). A completion marker is a ✅/✔ glyph or an
#                                     UPPERCASE word — lowercase prose is never a claim, so
#                                     "the live config", "deliver", "olive" and a var named
#                                     `OLLAMA_KEEP_ALIVE` cannot accuse an open row of being done
#  15. check_secrets.py              — secret-SHAPE scanner over the TRACKED TIP incl. the
#                                     members of tracked .tar/.tar.gz/.zip (added 2026-09-18 after
#                                     a live spark-llm_api bearer reached origin/main inside bench
#                                     logs — validate-secrets.py only covers group_vars/roles/, so
#                                     artifacts and logs were ungated). Masked output; unreadable
#                                     archives fail too. + `--self-test`: the shapes are run through
#                                     a literal PREFILTER for speed (16.5 s -> 5.0 s of a 58 s gate),
#                                     so the self-test proves every shape still fires, on a plain
#                                     file AND inside an archive member, plus a case-folded shape
#                                     (`PAſSWORD`, which a lower() prefilter skips) and a MUTATED
#                                     prefilter literal that must lose the hit — a wrong literal has
#                                     to fail the gate, not quietly narrow the scanner.
#  16. check_self_converge_guard.py — HD-413 guardrail completeness (static): every playbook
#                                     that applies a lockout-capable role (network / storage /
#                                     wireguard / vps-hardening) imports the self-converge
#                                     guard, and imports it in pre_tasks; every lockout role
#                                     has its own guard task whose tag list equals the role's
#                                     complete selectable vocabulary, recomputed from the role
#                                     dirs; no default()/failed_when in the guard (HD-399 rule);
#                                     a role that writes under --check may not claim check_safe
#  17. testdata/self-converge-guard/run.sh — HD-413 guardrail BEHAVIOUR (runtime, WSL/CI-gated):
#                                     executes the real guard against a throwaway inventory
#                                     (this host = the controller, plus a decoy that is not) and
#                                     asserts the refuse/allow verdict for 18 legs (`grep -c
#                                     '^expect '` — the header said 14 for a while and rotted).
#                                     The legs are independent and side-effect free, so they
#                                     LAUNCH concurrently now: 11.4 s -> 3.4 s, with the verdict
#                                     assertions unchanged and printed in the declared order
#                                     (mutation-checked: flipped expectation, neutered DUMMY
#                                     output, and a leg whose rc never arrives — all three go RED)
#                                     The static gate above cannot see a wrong Jinja predicate: the
#                                     first draft compared `ansible_run_tags == ['all']`, which
#                                     is always False because that magic var is a TUPLE, and
#                                     passed every static check while allowing an unfiltered
#                                     self-converge of the netdev role
#  18. check_merge_markers.py        — HD-453: no merge-conflict marker may reach a commit
#                                     (`<<<<<<<` / `>>>>>>>` / `|||||||`, plus git's exact-width
#                                     `=======` divider). A `>>>>>>>` line once survived a bad
#                                     rebase into a rebased commit of a root view file and every
#                                     gate stayed green; the gate scans the WORKING TREE, so it
#                                     also fires before the commit that would ship the marker.
#                                     `--self-test` proves it red on each marker shape and green
#                                     on the near-misses that would otherwise mute it (a Markdown
#                                     setext `=` heading; the repo's 50–60-char `=` banners in
#                                     tracked raw evidence — a first draft matching `^={7,}`
#                                     reported 78 false positives on its first run)
#  19. check_iac_backend_strings.py   — HD-404 ratchet: the count of `Prometheus|Loki` mentions under
#                                     IaC/ansible/{playbooks,group_vars} may not exceed the recorded
#                                     floor (HD-342 replaced them with VictoriaMetrics + VictoriaLogs;
#                                     the six stale claims HD-404 fixed all lived in that corpus).
#                                     A RATCHET, not a per-line lie-detector — measured: an
#                                     assertion-shaped regex caught 2 of the 4 real violations, and an
#                                     allowlist over the 28 mostly-legitimate mentions would mute the
#                                     gate (the HD-417 lesson). `--show` re-derives the count; the
#                                     self-test refuses a floor red at rest or absurdly loose
#  20. check_md_tables.py             — HD-417: no markdown table row may be WIDER than its own header.
#                                     Two misses in one session on 2026-09-21 (a swallowed newline merged two
#                                     registry rows; a description quoting `vllm|sglang` widened a 3-cell row to
#                                     12) both passed every validator because nothing counts cells. Wider-only on
#                                     purpose: 14 NARROWER rows are legal GFM (short rows, struck-through PARKED
#                                     rows) and asserting equality printed 41 findings in 12 files — a gate that
#                                     shouts gets muted. `--self-test` plants a stray pipe (inside a code span,
#                                     where it still cuts) and a merged row, and asserts clean tables stay clean
#                                     Second half (2026-10-06): a row whose FIRST CELL IS A LINK is an identity,
#                                     so one table may not carry the same link twice — added because
#                                     scripts/README.md listed install-pi-wsl.sh on two rows with every gate
#                                     green. Link-keyed only, measured: the loose "any repeated first cell" form
#                                     prints 58 findings here and would be muted; this form is 0 at rest and
#                                     still catches the real pair.
#  21. knx-hass-gen.py --self-test    — HD-439: the KNX generator's own address guard. `--check` (manual, needs
#                                     xknxproject + the .knxproj) asserts every address the generator emits is
#                                     PUBLISHED IN THE ETS PROJECT — the one invention risk left is the 19-address
#                                     hand-typed sensor appendix, because HA fails per-entity on an address the
#                                     bus does not know. This item runs the pure-stdlib half, because the runner
#                                     has no xknxproject and nothing in the repo declares it
#                                     (import xknxproject fails here — measured 2026-09-25)
#  22. check_spark_llm_gate.py        — HD-469: the spark LLM profile gate must be PROVEN OFFLINE.
#                                     `roles/spark-llm-profile` is the only thing between a one-var flip
#                                     and a global OOM that Docker reports as `OOMKilled: false`, yet its
#                                     live test costs a ~20-minute engine boot on the box that serves the
#                                     operator. The checker evaluates the ROLE'S OWN patterns (extracted
#                                     from the task YAML, never re-typed) + the group_vars constants over
#                                     every authored profile, then breeds a canary per invariant and
#                                     REFUSES a canary that passes — a gate that cannot fail is not a
#                                     gate (CONVENTIONS §6). PyYAML-only: no Ansible, no network, no box
#  23. laptop-llm.py gate --self-test — HD-474: the laptop serving-leg invariants must be
#                                     PROVEN OFFLINE, same rule as item 22. The deploy-time `gate`
#                                     is EXPECTED to fail on an unprobed box (uncertified profiles,
#                                     an unpinned LM Studio auto-updater, pending probes), so what is
#                                     committed as a hard gate is the canary self-test: 13 canaries,
#                                     one per invariant, each must FAIL. A budget that exceeds the
#                                     iGPU carve, a client window above num_ctx, an image claim on a
#                                     GGUF with no projector on disk, q8_0 KV without flash attention
#                                     (llama.cpp silently ignores it), MTP+mmproj (unsupported
#                                     together) and `certified: true` without evidence each get a
#                                     canary. Stdlib + PyYAML, no server, no token, no Windows.
#  24. laptop-llm.py probe-client       — HD-474: the client contract may not drift AHEAD of the
#                                     engine. Compares providers.laptop-lmstudio in models-spec.yml
#                                     against the ACTIVE profile (contextWindow / maxTokens / input
#                                     / reasoning). Offline: no request leaves the box. Skips itself
#                                     on a host the provider is not scoped to (`hosts:`), so CI and
#                                     the oldsrv cockpit are unaffected.

#  25. spark-llm-render-matrix.py       — HD-489: every authored profile must RENDER offline.
#  26. check_doc_path_refs.py            — HD-490: every local path a doc or IaC comment cites
#                                     resolves to something in the tree (621 files, 539 targets).
#                                     Links resolve from the containing file, bare paths from the repo
#                                     root; generated-doc templates resolve from the document
#                                     render-docs.yml puts them into. Globs, placeholders, the frozen
#                                     archives, git-ignored generated files and prose that says the
#                                     file is missing are exempt, each for a stated reason.
#                                     `--self-test` breeds a dangling ref and refuses a green run.
#  27. sync-extensions.sh --self-test + --check --strict — extension drift gate (HD-254 family):
#                                     repo pi-agent/extensions/ must equal ~/.pi/agent/extensions.
#                                     Deliberately NOT identical to item 13: a DEPLOYED-ONLY extension
#                                     (a machine-local file one seat carries on purpose) is reported
#                                     as LOCAL and does NOT fail the gate, or that seat would fail
#                                     forever and the gate would get muted (the HD-417 failure mode).
#                                     The ONE exception is the script's RETIRED list (HD-1110): names
#                                     the repo deleted — host-status.ts, remote-bash.ts, both retired
#                                     2026-10-08 — which --push removes and --check --strict fails
#                                     while still deployed, because --push preserving a deployed-only
#                                     file would otherwise keep a deleted extension loaded forever.
#                                     --self-test asserts all three halves (missing fails, extra is
#                                     kept, retired is removed). Guarded like item 13: with no
#                                     ~/.pi/agent/extensions on the host, the check SKIPs.
#                                     16 arms × the same docker-compose.yml.j2 the engine
#                                     boots from, with the parity assertions that keep the
#                                     four certified lanes byte-identical to what serves today.
#  28. check_zone_kogler_si_parity.py — HD-436: deriving the `kogler.si` answer plane from ONE list
#                                     must not CHANGE an answer. A static contract checker proves a row
#                                     follows the rules; it cannot see an answer PLANE change: an early
#                                     draft of the derivation dropped apex/litellm/logs from the primary
#                                     (a `when` gate comparing `item.name` against a var that resolved to
#                                     the STRING repr of a list, so `in` became a SUBSTRING test) and
#                                     `check_dns_seed_drift.py` — which only knew literal inline `loop:`
#                                     lists — reported '43 records' from the hand-authored era while
#                                     reading ZERO rows from the derived one. RED on the branch, GREEN on
#                                     main: a contract gate and the thing it guards can both be blind.
#                                     This gate diffs derived-vs-golden (the pre-derivation output,
#                                     captured in scripts/testdata/), fails on a dropped name, a changed
#                                     IP, a name moving between the plain and `.ts` namespaces, a
#                                     consumer that answers nothing, and a golden field silently dropped
#                                     from a row. headscale's records are rendered in BOTH key shapes —
#                                     the inline `dns.extra_records` block and the `dns.extra_records_path`
#                                     file — and must come out the same rows in the same order, so moving
#                                     the records between the keys cannot move an answer. The file shape is
#                                     parsed AS JSON, which is what headscale does to it, so a YAML body, a
#                                     comment line, or rows that differ between the two Jinja whitespace
#                                     engines are RED here and not in the control plane's first sample.
#                                     `--self-test` proves it refuses all of that PLUS the shapes a running
#                                     config cannot report: both record keys at once, a records path the
#                                     compose bind does not provide, and a `zone_kogler_si` flag flip that
#                                     fails to redden the matching surface in either shape.
#  29. install-tmux-conf.sh --self-test + --check --strict — seat terminal-harness gate
#                                     (HD-1085): repo pi-agent/tmux/tmux.conf == ~/.tmux.conf AND the
#                                     config actually TAKES EFFECT. The "and" is the whole item: a tmux
#                                     config that errors mid-load leaves the options at their DEFAULTS
#                                     while the caller gets exit 0 and empty stderr, so a byte-compare
#                                     of two identical files can sit next to a seat with no mouse and
#                                     no clipboard (measured six ways, docs/harness-pi-terminal.md §5b). The
#                                     self-test therefore mutates FIXTURES, not the checker: seven
#                                     canaries, two of them a byte-identical SSOT/target pair that is
#                                     inert by construction (one bad command mid-file; the nested
#                                     wrapped if-shell that broke the live seat) — a `cmp` says SAME on
#                                     both and the gate must still go RED. Plus the OSC 52 canary: same
#                                     fixture with the `Ms` override stripped must emit NOTHING, or the
#                                     emission arm is passing for the wrong reason. Drift check guarded
#                                     like items 13/27: with no ~/.tmux.conf on the host it SKIPs (a
#                                     stateless runner has no seat here); ineffectiveness fails in every
#                                     mode because it is a defect, not a seat state.
#  30. check_yaml_dup_keys.py    — HD-1098: no YAML mapping may declare the same key twice.
#                                     Ansible resolves a duplicate key by KEEPING THE LAST one and
#                                     printing `[WARNING]: Found duplicate mapping key … Using last
#                                     defined value only.` — the playbook still runs, --syntax-check
#                                     still passes, so the FIRST definition is dead text that keeps
#                                     looking authoritative (CONVENTIONS §6's silent-failure class).
#                                     Three were live on 2026-10-08, none caught by any gate: a task
#                                     in roles/monitoring with two `tags:` (HD-450's hygiene-exporter
#                                     task silently lost the `hygiene` tag) and two fragment vars in
#                                     group_vars/spark.yml defined twice by a duplicated section.
#                                     Walks the RAW node tree (compose_all), not loader hooks — a hook
#                                     version of this check saw 1 of the 3. `--self-test` breeds the
#                                     canary shapes, pins the legal near-misses (merge keys `<<`,
#                                     sibling mappings, multi-doc, Jinja scalars) and proves the
#                                     corpus was actually walked. Archives (brainstorming/,
#                                     docs/assets/references/, reports/) are excluded by path.
#  31. check_todo_done.py --refs   — a `prompt*.md` brief may only name a row that EXISTS.
#                                     CONVENTIONS §4 DELETES a closed row and renumbers a colliding
#                                     id, so every brief that named one keeps a pointer to nothing —
#                                     and no gate looked. The status-claim half of this checker is
#                                     blind to it by construction: a false pointer is usually a
#                                     HISTORICAL mention of closed work, never an open-work claim.
#                                     On its first run (at be7a4684) every finding was exactly that
#                                     class. FAILs naming `file:line`.
#                                     ⚠ Asymmetric ON PURPOSE, keep it that way: a STATUS claim is
#                                     read from `prompt.md` alone (that file IS the handoff), a
#                                     REFERENCE is checked across every root brief (a dead id
#                                     misleads whoever reads it). Root-level only, non-recursive: a
#                                     `prompt.md` under `brainstorming/obsolete/` is a frozen
#                                     artifact, not a handoff. Both directions are canaried by the
#                                     `check_todo_done.py --self-test` item, which also refuses a
#                                     real brief that dangles (the fixture green must not be the
#                                     only proof the pass can be green). Milliseconds: a glob over
#                                     the briefs, no subprocess, so the pool does not notice it.
#  32. check_doc_headings.py       — the ANCHOR half of a citation: a `§Section` pointer, in a doc
#                                     or in an IaC comment, must name a heading that EXISTS in the
#                                     document it points at, and a `decision #N` must cite a row of
#                                     that doc's decision table. Item 26 proves the path resolves;
#                                     nothing proved the anchor, so a heading reworded in the target
#                                     dangled every pointer to it while the suite stayed green. The
#                                     corpus carries pre-existing dangling anchors, so this runs as
#                                     a RATCHET against the committed ledger
#                                     `gate/doc_headings_baseline.txt`: frozen debt is reported and
#                                     stays green, a NEW dangling pointer fails, and so does a ledger
#                                     line whose pointer now resolves (an entry that outlives its
#                                     pointer would exempt the next one — the
#                                     `gate/iac_identifier_allowlist.txt` discipline). Keyed on
#                                     path + target + the pointer as written, never on line numbers.
#                                     `--show-baseline` re-derives the ledger; `--self-test` breeds
#                                     each anchor defect AND both halves of the ratchet.
#  33. corpus_diff.py --self-test     — the string-purge audit's proof that it can fail: the bred
#                                     classifier cases on single-line pairs plus both halves of the
#                                     accepts/baseline canary, on a throwaway repo that carries its
#                                     own baseline and accepts list — so it reads the same in every
#                                     clone and needs neither pinned file. The RUN half, `--gate`,
#                                     is deliberately NOT an item; the note at its registration
#                                     carries the measured reason. Its verdict is a function of the
#                                     window named by `gate/corpus_baseline.txt` (base rev -> now rev
#                                     under a scope), where a changed line that loses a token
#                                     outside rendered text owes an exact entry of the signed list
#                                     `gate/corpus_diff_accepts.txt`. Everything else about the audit
#                                     stays in-tree and replayable either way: deleting an entry
#                                     exposes its REJECT, and an entry whose REJECT is gone is STALE
#                                     (the `gate/iac_identifier_allowlist.txt` discipline). The digest
#                                     of what was compared makes a narrowed scope or a moved revision
#                                     a refusal rather than a smaller check, and a now end older than
#                                     one wave is refused — the staleness check
#                                     `gate/check_string_twins.py` has. Re-signing a wave is an act
#                                     the next wave notices, in the commit that publishes the fields.
#  34. render_all.py --self-test        — HD-1117: the generated-doc drift check must be able to read
#                                     GREEN. A wall clock stamped into a render made `--check` red
#                                     forever — a faithful re-render differs from the committed file
#                                     by the clock line alone, so the check could never clear and the
#                                     `*-generated.md` docs had no usable SSOT gate. The arms run the
#                                     REAL templates in a throwaway git repo (`$REPO` hook; this tree
#                                     is never the render target): green, green AGAIN (the idempotence
#                                     a stamp destroys), the tree left exactly as found, a changed
#                                     SSOT value reddens it, an uncommitted hand edit survives, a
#                                     COMMITTED hand edit reddens it, and a template that asks for a
#                                     wall clock cannot render at all — the clock is out of the
#                                     context, not merely out of the file.
#  34b. render_all.py --check --no-write — HD-1117's other half: the check over the REAL tree,
#                                     registered. What makes it legal in this file is the WRITE
#                                     policy: the render goes to a temp dir and those bytes are
#                                     compared against `git show :<path>`, so `docs/` is never the
#                                     render target. The in-place `--check` cannot be a pool item —
#                                     `write_text` truncates before it fills, and a watcher reading
#                                     the five render products while `--check` looped in this tree
#                                     took 2,383 zero-length or partial reads out of 6,669,855, so
#                                     every doc-reading checker beside it would get a window in
#                                     which the file it is scanning is EMPTY (a green that measured
#                                     nothing, or a corpus floor fired by a half-written file). It
#                                     runs AFTER the `--self-test` above, so the fixture proves the
#                                     checker before it judges the tree, and it refuses rather than
#                                     lying: if the render touches a tracked generated doc at all —
#                                     bytes OR mtime — it exits naming the file instead of printing
#                                     a green.
#  35. check_registry_prose.py       — CONVENTIONS §6, state-only docs, applied to this file: the
#                                     registry must say what each script DOES (flags, verdicts, exit
#                                     contract, declared limits) and which doc owns the detail — no
#                                     `HD-<n>` tokens, no `20YY-MM-DD` the line does not name as STATE
#                                     (an expiry/renewal is state, the day it landed is not), no
#                                     diary narrative, no completion glyphs, every row carrying its
#                                     owning-spec cell (EXACT column equality — stricter than
#                                     check_md_tables.py's wider-only — the only way to see a silently
#                                     dropped third cell), no unescaped pipe inside inline code (GFM
#                                     cuts the cell there) and no passage pasted twice inside one row.
#                                     A corpus floor refuses a walk that counts no rows. Its
#                                     `--self-test` breeds each rule, requires each exemption to stay
#                                     quiet, and refuses an empty walk — a checker that lost its
#                                     target must not be able to print OK.
#  36. check_view_registry_sync.py   — the view↔registry seam no gate ever held: `todo-table.md` §B9
#                                     must hold EXACTLY the row ids `todo.md` carries, in BOTH
#                                     directions. The registry is the record and §B9 is the index of it;
#                                     nothing compared the two id sets, which is why the view's own
#                                     header records re-syncs that found 13, 8 and 18 rows missing — each
#                                     one caught by a human typing `comm`, never by the suite. A row the
#                                     registry carries and §B9 does not is work no dispatcher reads (the
#                                     shape a commit that MINTS a row produces, since the new id belongs
#                                     to no index until someone re-derives); an id §B9 carries that the
#                                     registry does not is the view becoming a second record — a deleted
#                                     row that outlived its line, or an invented id. One regex extracts
#                                     both sides (a diff that reads the two files differently is not a
#                                     diff), the appendix is found by its heading, and the counts are
#                                     derived every run (CONVENTIONS §2). `--show-baseline` exists for a
#                                     difference the repo decides to CARRY; there is nothing to carry
#                                     here, so no baseline file is committed and a stale baseline line
#                                     reddens. It earned its first run: the tip it landed on was 3 rows
#                                     behind (§B9 said "re-derived" and the three newest ids were not in
#                                     it), which is the seam, not a false positive.
#  37. check_handoff_size.py       — the standing handoff (`prompt.md`) is the file every earlier
#                                     rule left unbounded, and the rule that was supposed to bound it —
#                                     "every prior open item appears or is explicitly resolved" — was
#                                     the regrowth mechanism: choosing "explicitly resolved" let the ✅
#                                     narrative stay as proof a decision had been made, so every
#                                     session added a story instead of deleting an item. Two rules and
#                                     one reminder now, all measured against the frozen seal
#                                     `gate/handoff_baseline.txt` so no verdict depends on the day:
#                                     SIZE (a REMINDER, non-blocking — bytes and lines over `baseline +
#                                     tolerance`; size is a proxy for the rule, never the rule, so an
#                                     ordinary two-line pointer prints nothing, a paragraph prints, and
#                                     neither one reddens — §6.4), HISTORY (a pointer-list entry marked
#                                     only with completion or
#                                     parked glyphs — the resolved item that stayed; a pending glyph or
#                                     a durable-refusal glyph exempts it, which is what keeps live work
#                                     and standing rules out of the finding), and DERIVED (a computable
#                                     count typed into the handoff — the value belongs in the seal, the
#                                     command that prints it in the owning doc, CONVENTIONS §2). Keys
#                                     are normalized text, never line numbers, and the seal fails in
#                                     BOTH directions: a site it does not carry reddens, a carried site
#                                     whose text has gone reddens too, because a line matching nothing
#                                     is the next site's free pass. Read-only here — `--reseal`, its
#                                     one write, belongs to the merge station (docs/orchestration.md
#                                     §4), never to a lane. `--self-test` proves neither size-reminder
#                                     half is dead code and neither one reddens, breeds an answered
#                                     bullet, an unsealed parked
#                                     ruling, each typed count shape, a copy of a carried story, a
#                                     frozen site whose text was deleted, and the shapes in which the
#                                     gate must refuse rather than print OK.
#  38. check_bench_provenance.py     — a timed spark leg's stamp must name a runner that was allowed to
#                                     take it. Two rules were prose-only and this is the mechanical half:
#                                     Rule 0 (never a timed spark number from a session served by spark,
#                                     incidents #3 + #6) and the designated runner station (an
#                                     externally-served run takes timed legs from the WSL Debian laptop
#                                     seat — off-box for every target, not the engine host, owner of no
#                                     converge slot). Nothing else in the repo could ask either question:
#                                     no bench script and no gate READ `PI_PROVIDER` (the mentions are all
#                                     prose — the briefs, docs/orchestration.md, one IaC comment), the
#                                     engine cannot tell operators apart because every profile arm shares
#                                     one `model_name`, and `PI_MODEL` reaches the tree in exactly one
#                                     place — the `client` column run-scenario.sh appends per leg
#                                     (`<hostname -s>/agent:<PI_MODEL>`). So the gate reads that column
#                                     and prints RULE-0 (model half names provider `spark`; no exception
#                                     excuses it — an exception is about a box, Rule 0 is about a model)
#                                     and OFF-STATION (another box, no ledger line: a PROVENANCE finding,
#                                     not a failed measurement). `gate/bench_provenance_exceptions.txt`
#                                     keys one line to one leg (`step` + `ts`) so an exception cannot
#                                     become an amnesty for a class, prints those legs as NAMED DEBT, and
#                                     reports a line whose leg is absent as NOT MATCHED. The station test
#                                     imports host_norm() from harness/render-pi-config.py rather than
#                                     re-spelling hostname equality — HD-474 is what a second opinion
#                                     about `Domen_P14s`/`DomenP14s` already cost. It reads a CSV and
#                                     touches no host, so it is safe on a spark-served seat; and a run
#                                     that could not read a stamp is NOT JUDGED (rc 2), which on a seat
#                                     with no bench CSV here is a printed SKIP, never a pass.
#  39. the spark bench instruments' --self-test — the seven instruments this wave landed under
#                                     scripts/bench/spark/ each SHIP a --self-test, and NOT ONE of
#                                     them was registered: the grep for `accuracy-gate|gate6-couple|
#                                     hd469-baseline|usable-sampler|metrics-window|needle-window|
#                                     text-only-preflight` in this file returned nothing, and the
#                                     only bench/spark item here was gate7-read.py. So every arm in
#                                     them ran only when a human remembered to run it — which is
#                                     exactly how a driver ships with a contract its own fixture
#                                     never asked about — the TERM trap that deleted a LIVE
#                                     sampler's pid file was one of those unasked contracts).
#                                     Registration criterion, applied per arm: it must be HOST-FREE,
#                                     because this gate runs on the seat whose own model is spark.
#                                     Every one of the seven routes its far side through ONE door
#                                     (host_read, with an `if [ -n "${X_SSH_CMD:-}" ]` branch, plus
#                                     accuracy-gate's HTTP through ACCURACY_GATE_CURL_CMD) and
#                                     run_self_test exports the fixture hook before its first arm;
#                                     proven by running all seven with ssh/curl/docker/op replaced
#                                     by logging tripwires on PATH — SELF-TEST OK seven times, ZERO
#                                     tripwire lines logged, ~20 s of fixture work all together.
#                                     What is NOT here, and why, is in the note by the items.
#  40. check_brief_coverage.py       — the row→brief map, with the view gate above. Which brief carries
#                                     which row is written down in THREE places — `todo-table.md` §B0's
#                                     `Rows it carries` cells, every root `prompt-<domain>.md`'s dispatch
#                                     header, and `prompt.md`'s §2 pointers (`→ [prompt-x.md]` plus the
#                                     parked table's `📋 brief` column) — and `check_view_registry_sync.py`
#                                     above proves only the §B9↔`todo.md` seam, `check_todo_done.py --refs`
#                                     only that a cited id is a live row. Nothing compared the three copies
#                                     of the MAP, so a §B0 cell could hand a row to a brief that never
#                                     mentions it (the lane is dispatched FROM the brief, so the work is
#                                     never read), a brief could claim a row the index gives to another
#                                     lane (two writers, one row), and `prompt.md` could point a row at a
#                                     brief §B0 omits. Claims come from a brief's dispatch header and
#                                     citations from its prose — containment may be lenient, a claim may
#                                     not — and all three id spellings are parsed, so a cluster tail visible
#                                     only as `HD-480/481` is its own rule (that is the half `--refs` cannot
#                                     see: it checks an abbreviated cluster by its HEAD). §B0 is bounded by
#                                     its `### 🔥 Active lanes` neighbour and its columns by their header
#                                     text, a corpus floor refuses a walk that read nothing, and every tally
#                                     (open / briefed / unbriefed) prints from the run, never from prose.
#                                     Carried debt lives in `gate/brief_coverage_baseline.txt` keyed on the
#                                     (brief, id) relation, and it reddens when a carried difference clears.
#  43. check_doc_sensitivity.py     — CONVENTIONS §8.6's data-sensitivity class, proved on the corpus instead
#                                     of remembered from a sweep's commit message. The class is the fact a run
#                                     needs BEFORE it decides where its read list may go (§8.6's egress rule,
#                                     README §3), and no shape scanner supplies it: they prove no credential
#                                     TEXT ships, not what a document is ABOUT. Four rules, each with a canary
#                                     in `--self-test`: every hand-authored doc DECLARES one (the
#                                     `-generated.md` render views inherit and declare nothing, §8.2); the
#                                     value is ONE bare lowercase slug, because a quoted or capitalised one
#                                     parses to a fourth class nothing else reads and drops the doc out of
#                                     every sibling rule silently (§8.1's `domain-shape` rule, moved to the
#                                     other axis); the owner's FLOOR is carried inside the gate, so retagging
#                                     a family or secrets doc down to `infra` reddens a commit while a
#                                     promotion stays quiet; and a `personal` doc carries no contact payload —
#                                     an off-domain email, an IBAN, a phone — measured floor 0, with each
#                                     shape's false-positive class proved quiet instead of merely asserted: a
#                                     service address on a family subdomain, an apt key fingerprint, and a byte
#                                     count written in thousands groups. The distribution is DERIVED and
#                                     printed every run, so the population never moves into this file's prose.
#  44. check_open_questions.py      — CONVENTIONS §8.3's `Options` grammar, so an open question is an
#                                     addressable section and the inventory can be LISTED. Before it the only
#                                     list of open questions was prose, and `rg '^## Options' docs/` answered
#                                     with nothing. Four rules, one canary each in `--self-test`: SHAPE (the
#                                     section carries `| Option | For | Against | Cost | Cheap test |` with a
#                                     separator line, ≥2 rows and a non-empty cheap test in every row — an
#                                     option without a cheap test is a wish, and one row is a verdict with a
#                                     table around it), KEY (the section names its `OQ-<n>` id), NO-VERDICT
#                                     (no recommend / decided / `decision:` wording inside it: an option is
#                                     never a decision dressed as an option, and the ruling lives in the doc's
#                                     state or in `<domain>-rejected.md`), and the DERIVED MINT (the id space
#                                     is read from every tracked `*.md` with the `Options` heading lines
#                                     EXCLUDED, since a rule reading the number off the line it audits can
#                                     never fire; next id = max+1, and a number above that was typed — §2's
#                                     derived-values ban). Two floors refuse a partial walk, the tree-wide
#                                     mint basis deliberately above the docs-only count. Declared blind spot:
#                                     the gate shapes what EXISTS, so a choice written as prose or as
#                                     `## Open Questions` bullets is invisible and the inventory command is a
#                                     floor, not a census.
#   + ansible-playbook --syntax-check across all playbooks (WSL/CI-gated, HD-197) — its stderr is
#                                     kept and the duplicate-mapping-key warning fails the run, the
#                                     second witness for HD-1098 (it sees role task files as ansible
#                                     loads them, at no extra ansible cost). PLAYBOOKS RUN IN
#                                     PARALLEL since 2026-10-09 (8.4 s -> 3.0 s on 8 cores): the cost
#                                     was 17 × interpreter startup, not work; each leg keeps its own
#                                     stderr file, so the duplicate-key witness is unchanged.
#  41. check_doc_size.py            — REMINDER (non-blocking, CONVENTIONS §6.4): the corpus-size nudge.
#                                     It used to be a ratchet over a per-file seal in
#                                     `gate/doc_size_baseline.txt`, and that seal is RETIRED on purpose: a
#                                     warning measured against a frozen number can only be silenced by
#                                     rewriting the number, so it either blocks (never a warning) or rots
#                                     into permanent yellow (never read). The bound is now DERIVED at run
#                                     time (2 × the new-doc reference) and a doc above it is PRINTED as a
#                                     placement hint (§8.1), never as a defect — a long doc of facts is a
#                                     split question, and this corpus has docs far above any honest
#                                     per-file number. The walk and its `walk_docs` function stay the ONE
#                                     definition of "hand-authored doc" (`check_role_docs.py` and
#                                     `check_docs_pure.py` import it, §2); `docs/*-generated.md` render
#                                     views are out of it, because their length is an IaC-render property
#                                     (§8.2, §8.5). rc 2 only for a broken root — a gate that cannot see
#                                     the files cannot remind either.
#  41b. check_docs_pure.py           — the machine half of CONVENTIONS §6 over the surface the other prose
#                                     gates never read (`docs/**/*.md` + the root `README.md`): the docs
#                                     had been used as a changelog, and §6.4 records that motive. TWO
#                                     SEVERITIES on purpose. HARD (a red): an `HD-`/`KOPS-` token whose
#                                     `todo.md` row no longer exists — an id is allowed in a doc only while
#                                     the work is open, so deleting a row WITHOUT sweeping the mentions is
#                                     what reddens, and the live-id basis is derived from the rows on every
#                                     run (nothing is listed, §2). WARN (printed, exit 0): a past-tense
#                                     evidence verb anchored to a date, a diary/supersession phrase, a run
#                                     recap — printed at SENTENCE level because the sentence is the thing to
#                                     rewrite, and a date that the line names as state (expiry, renewal,
#                                     firmware date, a live-verified marker) is never a finding. An id in
#                                     code font (`HD-1080p`) is data, not a citation.
#  42. check_role_docs.py            — HD-1200: the tree→docs half of the docs seam. A role directory
#                                     could land with no doc of its own and nothing noticed —
#                                     check_doc_path_refs.py proves the paths a doc cites exist and
#                                     check_doc_map.py proves a doc is reachable from docs/index.md, both
#                                     docs→tree; check_view_registry_sync.py diffs two hand-written views
#                                     of one id set. This one derives its role set from the IaC/ansible/
#                                     roles/ DIRECTORY listing (no role name is written in the script, so
#                                     adding or renaming a role moves the rule, not the file) and matches
#                                     it against the TEXT of the hand-authored docs/*.md, so it holds a
#                                     coverage floor rather than a view equality, and its floor sits at 0
#                                     findings: every role is already named, and the gate's whole value is
#                                     prospective — an undocumented role cannot ship. Naming is decided by
#                                     shape (a roles/<name> path, a code span, a table cell, an ansible
#                                     roles: entry) rather than by the string, because for common,
#                                     network, storage, switch and seat the bare word in prose is the
#                                     English word; a prose-only role is a finding that PRINTS its sites,
#                                     so the reader sees whether the fix is "write the doc" or "name it
#                                     where you meant it". A docs/*-generated.md render view cannot
#                                     document a role (§8.2, §8.5), and the corpus definition is imported
#                                     from check_doc_size.py rather than re-spelled (§2). --self-test
#                                     breeds and deletes a role dir in a temp tree to prove the set is
#                                     derived, proves the shape test from both sides, and refuses an empty
#                                     corpus, a missing role tree and a doc-less tree at rc 2.
#  45. lib/wsl-route.sh --self-test — the win11 seat runs part of THIS gate on the Debian engine of the
#                                     same laptop, because a fork+exec costs 16-44 ms here against
#                                     0.66 ms there and the fork-heavy legs are minutes against seconds
#                                     at the same tip. Which legs cross, and what a crossing leg may
#                                     not do (no git of this checkout, no network/vault, no seat-local
#                                     state, no seat self-classification), is decided in
#                                     scripts/lib/wsl-route.sh — seat class, the /mnt path, the probed
#                                     launcher, the far rc — and each leg says so at its own
#                                     registration line. This self-test grades the ROUTER through a
#                                     stub launcher, so an arm fails when the decision changes and not
#                                     when the host does; the leg it fences never becomes a SKIP on a
#                                     seat with no door, it runs at home.
#
# HOW THIS RUNS (2026-10-09, HD-1117): the items above are QUEUED and run CONCURRENTLY,
#   8 in flight on an 8-core runner — 32 s -> 12 s. They are independent: every check is
#   read-only over the repo (the sweeps write only gitignored __pycache__, the self-tests
#   sandbox in temp dirs / private sockets, nothing here writes to the tree). That sentence is a
#   claim the registry has to keep honouring: the one item whose SUBJECT is a write — the
#   generated-doc drift check — is registered in its write-free form for exactly that reason.
#   The numbered list above is the WHY of each check and is HISTORICAL — item numbers moved
#   when the long legs were moved to the front of the queue; `--list` prints the real set,
#   in launch order. Long items first, because queue order IS the schedule.
#
# Exit 0 only when all pass. ⚠ It no longer stops at the first failure: `set -e` could not
# survive a pool, and stopping early was worth less than the answer — one broken file used to
# hide the other nine. Every item runs, every failure prints with its own output, and the run
# ends with the list of what failed. `--serial` restores one-at-a-time (33 s) for bisecting a
# host that misbehaves under concurrency; `--only <substring>` runs a subset.
#
# ⚠ A gate that is not invoked is the same as a gate that is deleted, and this file proved it
#   on itself: while removing a DUPLICATED `check_iac_backend_strings.py` block (HD-404) the
#   edit matched both copies and deleted BOTH — every run from 223b571b to 17d8dd13 was green
#   while item 19 ran never, and the self-test that is supposed to catch a muted ratchet was
#   muted with it. The parallel rewrite restored it; `--list | wc -l` — counted at run time against
#   a previous commit, never typed here, because the count moves the moment an item is added — is
#   now the audit that catches this class; do not trust the numbered comments.
#
# HD-1137 ADDS TWO FLAGS AND CHANGES NOTHING ELSE (both are read-only over the registry):
#   --time     every item's wall (launch -> rc), then `Σ item duration` against `wall`, then the 8
#              slowest. This is the accounting HD-1135 had to do BY HAND to prove the gate was
#              spawn-bound — "Σ item duration 2365 s against wall 349 s" — from now on it is a flag.
#              It changes no verdict, no rc, and no existing line of the report.
#   --profile  `quick` = a SUBSET of the same item list for a pre-commit sanity loop. There is
#              deliberately NO second gate script and NO second item list: duplicating the entry
#              point duplicates the registry, and this repo has been burned by exactly that class
#              (`aa0bc737`: a "remove the duplicate" edit deleted a validator and every gate stayed
#              green for two commits; `50a4f609`: one table cell describing both "in order, set -e"
#              and "in a pool"). The default run is the FULL run, `--list` stays the single audit
#              (it prints the full set in every profile, the number never typed into prose —
#              CONVENTIONS §2), and a quick run ENDS with a `NOT PROVEN on this profile:` block
#              naming every item it skipped: CONVENTIONS §6 says an environment boundary prints SKIP
#              and never a verdict, and a profile is the same kind of boundary — a quick run that
#              reads like a full green is the mute-the-gate failure mode wearing a green coat.
#              `guard-session.sh --validate-mode` stays SERIAL and FAIL-FAST in every profile: a
#              profile is a way to read less, never a way to edit on primary+main.
# Every registration now carries its profile decision with it (`item_q` / `item_x "<reason>"`, same
# for `item_blk_*`); a bare `item` / `item_blk` is UNDECIDED and `--profile quick` REFUSES the run
# rather than defaulting the item in or out, because a new item silently missing from a profile is
# how coverage dies. The two sets are derived from that registry at run time and audited BEFORE
# anything launches — quick ⊆ full, full == quick ⊎ excluded, no duplicate label, no empty reason.
# `--profile` composes with `--only` (intersection); `--serial` and the exit-code contract are
# unchanged: exit 0 only when everything that the profile declared it would run came back 0.
set -euo pipefail
# HD-1118 Stage 1/4: find the repo root instead of assuming `$(dirname "$0")/..`. Found, not
# assumed — the gate that proves the tree is correct must not itself be the one file whose idea of
# "the repo" is a depth nobody checked.
_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"   # sets REPO
cd "$REPO"
# …then UNSET it. lib/repo-root.sh honours an inherited $REPO on purpose (the testdata fixtures and
# the seat driver depend on that), so a gate that leaves REPO in the environment silently overrides
# every self-test that builds a synthetic repo in /tmp and asserts the resolver found IT. The lib's
# own --self-test items were the first to notice: they passed for three stages and went red the
# moment the entry point started exporting the root.
unset REPO

# Python launcher: chosen by PROBE, not by name. WHY it is a probe (measured 2026-10-09 on the Win11
# seat): the Microsoft Store's `python3` alias STUB sits on PATH, `command -v python3` finds it, and it is
# NOT an interpreter — it prints "Python was not found; run without arguments to install from the
# Microsoft Store" and exits 49. The old name-based order therefore selected the stub, the preflight below
# correctly refused, and the `py -3` fallback written four lines further down could NEVER fire on exactly
# the host it was written for. Consequence: this seat could not reach a verdict at all — the HD-1124 class
# one step further back, a gate that dies before any validator runs. Candidates stay ordered so a
# Debian/CI runner still gets its real python3 first, and the launcher is PRINTED because a verdict has to
# say which interpreter produced it.
export PYTHONUTF8=1
# The venv is sourced BEFORE the probe (unchanged 2026-10-06 reasoning): on a Debian/WSL seat jinja2 and
# PyYAML arrive ONLY as pip deps of ansible inside ~/ansible-venv (bootstrap-runner.sh §3), and that venv
# enters PATH through a `source …activate` line in ~/.bashrc which a NON-interactive shell never reaches,
# because the file's interactivity guard returns first. Measured: from cron/pi/a converge the gate died on
# `from jinja2 import …` fifteen steps deep while the SAME commit went green from an interactive shell —
# a green-red-per-invoker gate is not a gate. NEVER required, so a bare CI runner keeps its system python3.
if [ -f "$HOME/ansible-venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  . "$HOME/ansible-venv/bin/activate"
  echo "launcher: ~/ansible-venv activated — python3=$(command -v python3 || echo absent) ansible-playbook=$(command -v ansible-playbook || echo absent)" >&2
fi
# The launcher is carried TWO ways, and both are load-bearing. `PY_CMD` is the argv ARRAY every leg is
# launched with, quoted (`"${PY_CMD[@]}"`) — CONVENTIONS §6 requires the interpreter to be quoted, and a
# Windows seat's `py -3` is TWO words: kept in a scalar and quoted, `"$PY" scripts/x.py` execs one program
# literally named `py -3` and the leg dies rc 127 without ever starting an interpreter. `PY` stays the
# human-readable form, printed by the launcher line because a verdict has to say what produced it.
PY=""; PY_CMD=()
for _cand in python3 "py -3" python; do
  # shellcheck disable=SC2086
  if $_cand -c "import jinja2, yaml" >/dev/null 2>&1; then PY="$_cand"; read -r -a PY_CMD <<<"$_cand"; break; fi
done
# Preflight, before 20 validators can fail one at a time: the interpreter chosen above must carry what the
# validators import at module scope. Without this the first signal is a traceback fifteen steps deep, which
# reads like a broken validator rather than a missing venv (that is how the 2026-10-06 incident got misread).
if [ "${#PY_CMD[@]}" -eq 0 ]; then
  echo "FAIL: no interpreter on PATH imports jinja2 + PyYAML (tried: python3, py -3, python) — the Python validators cannot run." >&2
  echo "      ⚠ A Microsoft Store alias STUB counts as present on PATH but is not an interpreter; if" >&2
  echo "        'python3' resolves to one here, install a real Python or run the gate where ~/ansible-venv exists." >&2
  echo "      On a Debian/WSL runner both arrive as pip deps of ansible inside ~/ansible-venv:" >&2
  echo "        bash scripts/ansible/bootstrap-runner.sh          # or: source ~/ansible-venv/bin/activate" >&2
  echo "      On a bare CI host:  python3 -m pip install jinja2 PyYAML" >&2
  echo "      Refusing to continue: a gate that cannot import is not a gate." >&2
  exit 1
fi
echo "launcher: $PY ($("${PY_CMD[@]}" -c 'import sys; print(sys.version.split()[0])' 2>/dev/null || echo '?'))" >&2


# --- CLI: --list (print the items and stop), --only SUBSTR (run a subset),          #
#     --serial (one at a time, the pre-parallel behaviour, for bisecting an issue),   #
#     --time (per-item accounting, HD-1137), --profile full|quick (a subset, HD-1137), #
#     --wsl auto|on|off (whether the legs that cross the door really do, HD-1202).     #
# Items registered with `item_reminder` are REMINDERS (CONVENTIONS §6.4): they run in EVERY profile,             #
# print their findings, and a non-zero answer is counted and printed but NEVER fails the run.                   #
ONLY=""; LIST=0; SERIAL=0; PROFILE=full; TIME=0; WSLMODE="${HL_WSL-auto}"
while [ $# -gt 0 ]; do
  case "$1" in
    --list)   LIST=1 ;;
    --serial) SERIAL=1 ;;
    --time)   TIME=1 ;;
    --only)   shift; [ $# -gt 0 ] || { echo "error: --only needs a substring" >&2; exit 2; }; ONLY="$1" ;;
    --only=*) ONLY="${1#--only=}" ;;
    --profile) shift; [ $# -gt 0 ] || { echo "error: --profile needs a name (full | quick)" >&2; exit 2; }; PROFILE="$1" ;;
    --profile=*) PROFILE="${1#--profile=}" ;;
    --wsl)    shift; [ $# -gt 0 ] || { echo "error: --wsl needs auto | on | off" >&2; exit 2; }; WSLMODE="$1" ;;
    --wsl=*)  WSLMODE="${1#--wsl=}" ;;
    -h|--help) echo "usage: bash scripts/validate-all.sh [--list] [--only SUBSTRING] [--serial] [--time] [--profile full|quick] [--wsl auto|on|off]"; exit 0 ;;
    *) echo "note: ignoring unknown argument '$1'" >&2 ;;
  esac
  shift
done
case "$WSLMODE" in
  auto|on|off) ;;
  *) echo "FAIL: --wsl wants auto | on | off, not '$WSLMODE'. Refusing to guess which seat you meant to run." >&2; exit 2 ;;
esac
export HL_WSL="$WSLMODE"
# An unknown profile must stop here, not quietly run the full set: a flag that is misspelled and
# obeyed-as-another-flag is the mute-the-gate class, and this one has an opposite to confuse it with.
case "$PROFILE" in
  full|quick) ;;
  *) echo "FAIL: unknown --profile '$PROFILE' — known profiles: full, quick. Refusing to guess which items you meant to run." >&2; exit 2 ;;
esac

# HD-1137: a FORK-FREE clock. A `date +%s%N` per item would be one EXEC per item on the very host whose
# whole cost is execs (~96 ms measured, HD-1135), so the stamps read bash's own EPOCHREALTIME and all
# the arithmetic is parameter expansion. One expansion per stamp, deliberately: composing a timestamp
# out of `%(...)T` PLUS EPOCHREALTIME can straddle a second boundary and print a duration wrong by 1 s.
# bash < 5 has no EPOCHREALTIME: the stamp is then empty, the read-out prints `?`, and no verdict ever
# depends on it — a degraded accounting line, never a wrong verdict.
_now() { NOW="${EPOCHREALTIME:-}"; }
# _ms_between <start> <end> -> MS as integer milliseconds ("" when either stamp is absent).
_ms_between() {
  MS=""
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 0
  MS=$(( ( ${2//[!0-9]/} - ${1//[!0-9]/} ) / 1000 ))
  return 0
}

# SERIAL, FIRST, FAIL-FAST — nothing else should run if this fails: HD-253 session
# discipline. --validate-mode hard-fails on primary+main+DIRTY; a clean-main merge-station
# run stays exempt, session worktrees and detached-HEAD/CI pass through.
if [ "$LIST" != 1 ]; then
  echo "== guard-session.sh --validate-mode (session-discipline hard gate, HD-253) =="
  bash scripts/gate/guard-session.sh --validate-mode
fi

# --------------------------------------------------------------------------- #
# Runner — the checks below are QUEUED and run CONCURRENTLY.                #
#                                                                           #
# WHY: the gate was 58 s and the trace said why — ~50 items, of which a dozen cost   #
# 0.3–5 s and thirty cost 20–80 ms, and ALL of them were waiting on each other.      #
# The checks are independent: every one of them is read-only over the repo (the two  #
# sweeps write only gitignored __pycache__, the self-tests sandbox themselves in      #
# temp dirs / private sockets, and nothing here writes to the tree). Parallelism is   #
# therefore free: 32 s → single digits, with no change to what is checked.            #
#                                                                                    #
# SEMANTICS CHANGED, on purpose: `set -e` used to stop at the FIRST failure, so one  #
# broken file hid the other nine. Now every item runs and the report prints every     #
# failure with its own output. Exit is 0 only when all passed. `--serial` restores    #
# the old one-at-a-time behaviour for debugging.                                      #
#                                                                                    #
# Two things stay SERIAL and fail fast, because everything else depends on them:      #
# the interpreter preflight above (a gate that cannot import is not a gate) and       #
# `guard-session.sh --validate-mode` (a primary+main+dirty checkout must not spend    #
# 10 s discovering that its edits are in the wrong place).                            #
# --------------------------------------------------------------------------- #
# ONE temp dir for the whole gate, removed by ONE EXIT trap. A leg must not `mktemp -d` +
# install its own `trap … EXIT`: legs run inside the item subshells created by `_queue`, and
# measured 2026-10-09 a trap set there came back to fire at the PARENT's exit — it replaced
# this one (bash keeps a single EXIT handler), leaked the directory that trap owned, and
# printed `SC_DIR: unbound variable` because the function-local it named was long gone.
# Legs that need scratch space take a subdirectory of `$RUN` (see the syntax-check leg).
RUN="$(mktemp -d)"; trap 'rm -rf "$RUN"' EXIT
GATE_T0=$SECONDS
_now; GATE_T0_US="$NOW"   # HD-1137: the wall clock for --time starts here, not at the report (fork-free)
# Windows seats get a POOL CAP, and the honest reason is CONTENTION WITH THE NEXT GATE, not speed.
# Measured 2026-10-10 on the Win11 git-bash seat, interleaved A/B, same tree, nothing else running:
#   pool 4 → 47 s   pool 8 → 43 s   pool 16 → 41 s   pool 24 → 43 s      (all within ~10 %)
# so on a QUIET seat the pool size barely matters — a fork+exec there costs 16–44 ms and 20-way
# concurrency buys ~1.7× (19 ms each against 32 ms serial). The same fork costs 0.66 ms on WSL
# Debian of the same laptop, which is why the identical gate finishes there in 7.9 s.
# What DOES hurt is two gates forking at once: while a second 24-way validate-all was running, this
# seat measured 130–185 ms per exec and the same item set took 5 min 51 s — an 8×
# degradation of a shared, non-scaling resource (process creation), not 2× the work. Capping at 16
# costs ~nothing alone and halves what one gate imposes on the other. Override: GATE_WIN_PAR.
IS_MSYS=0
case "${OSTYPE,,}" in msys*|cygwin*|mingw*) IS_MSYS=1 ;;
  *) case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) IS_MSYS=1 ;; esac ;; esac
if [ "$IS_MSYS" = 1 ]; then
  # Pin the interpreter's text encoding for every leg. The tree is UTF-8 (CONVENTIONS §6) and git answers in
  # UTF-8, but a Windows-native python decodes `text=True` output with the ANSI codepage unless told otherwise:
  # the reader thread dies on a NUL or a non-ASCII byte, `stdout` arrives as None, and a gate reports
  # `'NoneType' object has no attribute 'split'` as if it were a finding about the tree. Dozens of call sites
  # across the fleet are exposed to that and new ones are written every week, so the switch is set once for the
  # run rather than per call site — a per-file kwarg fixes one file and leaves the class free to regrow.
  export PYTHONUTF8=1
fi
MAXPAR=4
command -v nproc >/dev/null 2>&1 && MAXPAR="$(nproc)"
[ "$SERIAL" = 1 ] && MAXPAR=1
if [ "$IS_MSYS" = 1 ] && [ "$SERIAL" != 1 ]; then
  WINPAR="${GATE_WIN_PAR:-16}"
  [ "$MAXPAR" -gt "$WINPAR" ] && MAXPAR="$WINPAR"
fi
# The two ansible legs spawn children of their own; give them half the pool each so a
# nested fan-out cannot multiply the process count past the cores (8 slots → 4 each).
GATE_NPAR=4
command -v nproc >/dev/null 2>&1 && GATE_NPAR="$(( $(nproc) / 2 > 2 ? $(nproc) / 2 : 2 ))"
export GATE_NPAR
echo "gate: $MAXPAR items in flight (GATE_NPAR=$GATE_NPAR for the ansible legs)" >&2

# WHICH ENGINE RUNS A LEG, decided once, here, by lib/wsl-route.sh — the win11 seat's fork+exec costs
# 16-44 ms quiet and 0.66 ms on the Debian engine of the same laptop, so the fork-heavy legs of this
# gate take minutes here and seconds there, and the same commit is green on both. The legs that cross
# are wrapped at their registration line (`hl_wsl_route`), they read only the tree or a sandbox they
# build, and they run against THIS checkout at /mnt/<drive>/… — not a Debian clone — so the verdict
# stays about the bytes that are being graded. A leg that cannot cross runs here unchanged: the route
# never turns a check into a SKIP, and it never prints a green a leg did not earn. `--wsl off` (or
# HL_WSL=off) runs everything native, which is the engine-independent form of the same verdict.
# shellcheck source=/dev/null
hl_source_lib "${BASH_SOURCE[0]}" wsl-route.sh
# $PWD, not $REPO: this file unsets REPO on purpose (lib/repo-root.sh honours an inherited one, and a
# gate that leaves it set overrides every self-test that builds its own fixture repo). The gate has
# already `cd`-ed to the root, so $PWD IS the checkout being graded.
hl_wsl_probe "$PWD"
if [ "$HL_WSL" = on ] && [ "$HL_WSL_ON" = 0 ] && [ "$(hl_wsl_class)" != wsl ]; then
  echo "FAIL: --wsl on was asked for and the Debian engine said no: $HL_WSL_WHY" >&2
  echo "      Refusing to run: an operator who asked for the hybrid verdict should not be handed the native one." >&2
  exit 1
fi
[ "$LIST" = 1 ] || echo "route: $HL_WSL_WHY" >&2

# SLOT CONTROL without a FORK per POLL, measured 2026-10-10: the old gate checked the pool with
# `[ "$(jobs -rp | wc -l)" -ge "$MAXPAR" ]`, and `wc` is an EXEC — so a saturated pool spawned two
# processes (wc + sleep) every 50 ms purely to ask "is anything free?", which is a process per poll
# for no information on EVERY host (and 16–180 ms each on a Windows one). `wait -n` (bash 5.1+)
# blocks until a slot actually frees, at zero cost. The counter is exact: +1 per launch, -1 per reap.
# The old poll stays as the fallback for a bash without `wait -n` rather than being wrong there.
HAVE_WAITN=0
true & wait -n >/dev/null 2>&1 && HAVE_WAITN=1     # supported => reaps that `true` with rc 0
                                                   # unsupported => wait errors (rc 2) and just blocks

# --------------------------------------------------------------------------- #
# HD-1137: REGISTRATION IS NOT LAUNCHING.                                       #
# The old `_queue` launched each item while the script was still READING the      #
# item list, so no audit could see the whole set before the work started — and a  #
# profile audit that runs after the pool ran is a receipt, not a guard. Now every #
# registration is recorded first (`_reg`), the profile is audited, and only then  #
# does `_launch_all` walk the SAME list in the SAME order: launch order, labels,  #
# printed output and the exit-code contract are unchanged by the split.           #
# --------------------------------------------------------------------------- #
n_items=0; labels=(); cmds=(); cstart=(); clen=(); starts=(); ends=(); walls=()
pids=(); states=(); mems=(); whys=(); n_run=0; rc_missing=0; n_excl_launch=0

# The profile decision for the NEXT registration. A bare `item` / `item_blk` leaves P_MEM empty,
# which is UNDECIDED — and `_profile_audit` refuses a quick run rather than defaulting the item in or
# out, because an item silently missing from a profile is how coverage dies. The decision is ONE SLOT
# per registration, so `quick ⊆ full` and "nothing in both buckets" hold by construction; what the
# audit can still catch is the three things that do break.
P_MEM=""; P_WHY=""
_reminder=0
_reminders=()          # index -> 1 for every item registered as a reminder
_set_quick()    { P_MEM=q; P_WHY=""; }
_set_excluded() { P_MEM=x; P_WHY="$1"; }

_reg() {
  local label="$1"; shift
  local i=$n_items; n_items=$((n_items+1))
  labels+=("$label"); mems+=("$P_MEM"); whys+=("$P_WHY")
  _reminders[$i]="${_reminder:-0}"
  starts+=(""); ends+=(""); walls+=(""); pids+=("0"); states+=("pending")
  cstart+=("${#cmds[@]}"); clen+=("$#")
  local _w
  for _w in "$@"; do cmds+=("$_w"); done
  P_MEM=""; P_WHY=""
  if [ "$LIST" = 1 ]; then states[$i]=listed; return 0; fi
  # A profile is an INTERSECTION, not a re-ordering: `--profile quick --only X` runs what is BOTH
  # quick and matched. Profile-excluded is decided before --only, so the NOT PROVEN block stays the
  # honest list of what a quick run did not look at, whatever else filtered.
  if [ "$PROFILE" = quick ] && [ "${mems[$i]}" != q ]; then states[$i]=excluded; return 0; fi
  if [ -n "$ONLY" ] && [[ "$label" != *"$ONLY"* ]]; then states[$i]=filtered; return 0; fi
}

# item "<label>" <command...>   — one command. The *_q / *_x forms carry its profile decision.
item() { local label="$1"; shift; _reg "$label" "$@"; }
# item_reminder "<label>" <command...> — a REMINDER (CONVENTIONS §6.4): it runs in every profile, prints
# its findings, and a non-zero return is REPORTED but never fails the run. The distinction is the rule:
# a fact the tree can disprove reddens, a prose-shape or size judgement reminds — a gate that blocks on
# judgement is a gate that gets muted, and a reminder nobody sees is not enforcement either, which is why
# the report keeps counting and printing them.
item_reminder() { local label="$1"; shift; _reminder=1; _set_quick; _reg "REMINDER: $label" "$@"; _reminder=0; }
# item_blk "<label>" <function> — a multi-command block; the function is defined above
item_blk() { _reg "$1" "$2"; }
item_q()     { _set_quick; _reg "$@"; }
item_blk_q() { _set_quick; _reg "$1" "$2"; }
item_x()     { local _why="$1"; shift; _set_excluded "$_why"; _reg "$@"; }
item_blk_x() { local _why="$1"; shift; _set_excluded "$_why"; _reg "$1" "$2"; }

# Launch everything still pending, in registration order, with the slot control unchanged.
_launch_all() {
  local i pid _eng
  for i in "${!labels[@]}"; do
    [ "${states[$i]}" = pending ] || continue
    states[$i]=run
    _now; starts[$i]="$NOW"
    # rc FIRST, then the stamp: a function call clobbers `$?`, and a launch that always wrote rc 0
    # would mute the whole gate while printing a perfect report.
    ( set +e; "${cmds[@]:${cstart[$i]}:${clen[$i]}}" >"$RUN/$i.log" 2>&1; _lr=$?; _now
      printf '%s %s\n' "$_lr" "$NOW" >"$RUN/$i.rc" ) &
    pid=$!
    pids[$i]=$pid
    n_run=$((n_run+1))
    # The engine is named IN the launch line, so a reader never has to guess which seat answered a leg.
    if [ "${cmds[${cstart[$i]}]}" = hl_wsl_route ] && [ "$HL_WSL_ON" = 1 ]; then _eng='  [debian engine]'; else _eng=''; fi
    printf '  -> %2d  %s%s\n' "$i" "${labels[$i]}" "$_eng" >&2
    if [ "$MAXPAR" -le 1 ]; then
      wait "$pid" >/dev/null 2>&1 || true     # --serial: block here, no polling in the loop
      n_run=$((n_run-1))
    elif [ "$HAVE_WAITN" = 1 ]; then
      while [ "$n_run" -ge "$MAXPAR" ]; do
        wait -n >/dev/null 2>&1 || true       # reaps one finished leg; its rc already went to $RUN/$i.rc
        n_run=$((n_run-1))
      done
    else
      while [ "$(jobs -rp | wc -l)" -ge "$MAXPAR" ]; do sleep 0.05; done   # bash < 5.1: no wait -n
    fi
  done
}

# rc + finish stamp in ONE fork-free read. The old `rc="$(cat "$RUN/$i.rc" || echo 1)"` was an EXEC per
# item, TWICE per item (report loop + failure list) — on the host whose whole cost is execs that is a
# measurable tail. `read` is byte-truthful here (CONVENTIONS §6's second half is about `$( )`, which
# LOSES bytes, not about `read`, which keeps them) and the file is one short line the gate wrote. A
# MISSING rc file is recorded, not quietly read as a 1: it means the item was never accounted for,
# which is the exact thing the run-count audit exists to catch.
_read_rc() {
  RC=1; END=""; RC_MISSING=1
  local line
  [ -f "$RUN/$1.rc" ] || return 0
  RC_MISSING=0
  line=""; IFS= read -r line < "$RUN/$1.rc" || true
  [ -n "$line" ] || return 0
  RC="${line%% *}"
  END="${line#* }"
  # `if`, NOT `[ … ] && END=""`: an AND-list that ends a function RETURNS 1 when its test is false,
  # and `set -e` in the CALLER turns a perfectly accounted-for item into a dead gate. Same trap the
  # HD-1115 out-parameter note in lib/pi-seat.sh is about, on the other side of the call.
  if [ "$END" = "$line" ]; then END=""; fi   # a stamp-less rc file: the rc still counts, the wall prints ?
  return 0
}

# rc of item i as a string, 1 when it was never accounted for — one source for "did it come back?".
_rc_of() { _read_rc "$1"; printf '%s' "$RC"; }

# HD-1137: the profile audit, IN PROCESS, before a single launch, derived from the registry the queue
# just built — never from a hand-typed list. What it can catch: a registration with no decision, a
# reasonless exclusion, a label registered twice (the 223b571b "the edit matched both copies" class,
# which `--only` cannot address either), and a quick profile that selects nothing — a green that
# proves nothing (CONVENTIONS §6: a test that cannot fail is not evidence).
_profile_audit() {
  local i n_quick=0 n_excl=0 n_und=0 n_empty=0 bad="" dup
  local -A _seen=()
  for i in "${!labels[@]}"; do
    case "${mems[$i]}" in
      q) n_quick=$((n_quick+1)) ;;
      x) n_excl=$((n_excl+1))
         if [ -z "${whys[$i]}" ]; then
           n_empty=$((n_empty+1))
           bad+="  exclusion with NO REASON: ${labels[$i]}"$'\n'
         fi ;;
      *) n_und=$((n_und+1))
         bad+="  NO PROFILE DECISION: ${labels[$i]}"$'\n'
         bad+="        declare it:  item_q / item_blk_q to INCLUDE it, or"$'\n'
         bad+="        item_x \"<the actual reason>\" / item_blk_x to exclude it"$'\n' ;;
    esac
    dup="${_seen["${labels[$i]}"]:-}"
    if [ -n "$dup" ]; then
      bad+="  DUPLICATE registration (also item $dup): ${labels[$i]}"$'\n'
      bad+="        two items with one label cannot be audited by --only, and one of them may be the copy nobody meant to leave"$'\n'
    else
      _seen["${labels[$i]}"]=$i
    fi
  done
  if [ "$n_quick" -eq 0 ]; then
    bad+="  the quick profile selects NOTHING — a profile with no items is a green that proves nothing"$'\n'
  fi
  # full == quick ⊎ excluded, COUNTED. The two cases above already name what is wrong; this is the
  # arithmetic belt under them, so a bucket that loses an item cannot report a sound registry.
  if [ "$((n_quick + n_excl))" -ne "$n_items" ]; then
    bad+="  the two buckets do not cover the registry: $n_quick quick + $n_excl excluded ≠ $n_items registered"$'\n'
  fi
  if [ -n "$bad" ]; then
    {
      echo "FAIL: the --profile quick registry is not sound (HD-1137) — NOTHING ran."
      echo "      A profile that can quietly drop an item is worse than no profile: it prints a green the"
      echo "      work never earned. Registry: $n_items item(s), $n_quick in quick, $n_excl excluded."
      printf '%s' "$bad"
      echo "      The full set is: bash scripts/validate-all.sh --list"
    } >&2
    exit 1
  fi
  N_QUICK=$n_quick
}

# The honest tail of a quick run (CONVENTIONS §6: a boundary PRINTS, it never implies). Walked in queue
# order, so this block cannot disagree with what --list printed, and counted before it is printed, so
# the number in the header is the number of lines below it.
_not_proven() {
  local i n=0 body=""
  for i in "${!labels[@]}"; do
    [ "${states[$i]}" = excluded ] || continue
    n=$((n+1))
    body+="  - ${labels[$i]}"$'\n'"      because: ${whys[$i]}"$'\n'
  done
  echo
  echo "NOT PROVEN on this profile: $n item(s) did not run (profile: $PROFILE)."
  echo "This is NOT a full green. Full set: bash scripts/validate-all.sh --list  —  run it whole: drop --profile."
  printf '%s' "$body"
  if [ "$n" -ne "$n_excl_launch" ]; then
    echo "  ⚠ audit mismatch: $n excluded item(s) listed here vs $n_excl_launch counted before the launch"
  fi
  return 0
}

# HD-1137 --time: per-item wall, then Σ item duration against wall, then the 8 slowest. Pure bash — the
# table is the whole point of the flag and a `date` per row, or a `sort` in a pipe, would make the
# instrument slower than the thing it measures. This function PRINTS; it never decides anything.
_time_report() {
  local i v best bs j sum=0 n=0 wall_ms=""
  local -A taken=()
  _now; _ms_between "$GATE_T0_US" "$NOW"; wall_ms="$MS"
  printf '\n--time per item (launch -> rc, launch order):\n'
  for i in "${!labels[@]}"; do
    [ "${states[$i]}" = run ] || continue
    n=$((n+1))
    v="${walls[$i]}"
    if [ -n "$v" ]; then
      sum=$((sum+v))
      printf '  %7d ms  %3d  %s\n' "$v" "$i" "${labels[$i]}"
    else
      printf '        ?  %3d  %s   (no launch->rc wall: no EPOCHREALTIME, or no result file)\n' "$i" "${labels[$i]}"
    fi
  done
  printf -- '--time: Σ item duration %d.%03d s over %d item(s)' "$((sum/1000))" "$((sum%1000))" "$n"
  if [ -n "$wall_ms" ]; then
    printf ' | wall %d.%03d s | Σ/wall ' "$((wall_ms/1000))" "$((wall_ms%1000))"
    # integer hundredths, printed as %d.%02d — a bare substring of "23" printed ".23x" for 0.23.
    printf '%d.%02dx\n' "$(( (sum * 100 / (wall_ms > 0 ? wall_ms : 1)) / 100 ))" \
                       "$(( (sum * 100 / (wall_ms > 0 ? wall_ms : 1)) % 100 ))"
  else
    printf ' | wall unknown (bash without EPOCHREALTIME)\n'
  fi
  printf -- '--time slowest 8 (Σ against wall is the spawn-bound proof: HD-1135 found 6.8x this way)\n'
  for j in 1 2 3 4 5 6 7 8; do
    best=-1; bs=""
    for i in "${!walls[@]}"; do
      v="${walls[$i]}"; [ -n "$v" ] || continue
      [ -z "${taken[$i]:-}" ] || continue
      if [ "$best" = -1 ] || [ "$v" -gt "$best" ]; then best="$v"; bs="$i"; fi
    done
    if [ "$best" = -1 ]; then break; fi
    taken[$bs]=1
    printf '  %7d ms  %3d  %s\n' "$best" "$bs" "${labels[$bs]}"
  done
  return 0
}
# --------------------------------------------------------------------------- #
# HD-1117 — the red-run diagnosis, printed ONLY when an item failed.                            #
# Four items in this pool are on record as reddening under pool pressure and passing solo, and   #
# every one of those red runs reported a verdict with NO measurement attached — so the next      #
# session could only re-run it, and a re-run that goes green proves nothing. So the run now      #
# prints, per failed item, its own wall and how many sibling legs were in flight with it, plus   #
# the pool width and this host's load. Pool-level starvation of a fork-heavy arm and a genuinely #
# broken item look identical in a verdict line and completely different in these numbers.        #
# Built from the start/END stamps the launcher already writes (`_now` → EPOCHREALTIME), so it    #
# costs one awk on a run that already failed, changes no verdict, and prints nothing on green.   #
# A number this cannot obtain prints as `?` or SKIP, never as a reassuring zero (CONVENTIONS §6). #
# --------------------------------------------------------------------------- #
_diagnose_fails() {
  local i rows="" load="SKIP — /proc/loadavg is unreadable here (an environment boundary, not a verdict)"
  local cores="?" _l1="" _l5="" _l15=""
  if [ -r /proc/loadavg ]; then
    IFS=' ' read -r _l1 _l5 _l15 _ < /proc/loadavg || true
    load="${_l1:-?} ${_l5:-?} ${_l15:-?}"
  fi
  command -v nproc >/dev/null 2>&1 && cores="$(nproc 2>/dev/null || echo '?')"
  for i in "${!labels[@]}"; do
    [ "${states[$i]}" = "run" ] || continue
    # ONE ROW PER ITEM THAT RAN: start, end, wall-ms, failed?, label. awk decides who gets named.
    # -1 = a reminder that answered non-zero: it stays in the population (it really was in flight, and
    # the sibling count must count it) but awk never names it as a failure (CONVENTIONS §6.4).
    local _f=0; [ "$(_rc_of "$i")" != "0" ] && _f=1
    [ "${_reminders[$i]:-0}" = 1 ] && _f=-1
    rows+="${starts[$i]:-0}"$'\t'"${ends[$i]:-0}"$'\t'"${walls[$i]:-0}"$'\t'"$_f"$'\t'"${labels[$i]}"$'\n'
  done
  printf '%s' "$rows" | awk -F'\t' -v par="$MAXPAR" -v npar="$GATE_NPAR" -v cores="$cores" -v lavg="$load" '
    { s[NR] = $1 + 0; e[NR] = $2 + 0; w[NR] = $3 + 0; bad[NR] = $4 + 0; nm[NR] = $5; n = NR }
    END {
      printf "\nPOOL DIAGNOSTIC (HD-1117) — the pool was %s wide (GATE_NPAR %s) on %s core(s); load 1/5/15: %s\n",
             par, npar, cores, lavg
      for (i = 1; i <= n; i++) {
        if (bad[i] <= 0) continue
        infl = 0
        for (j = 1; j <= n; j++) if (s[j] < e[i] && e[j] > s[i]) infl++   # legs overlapping THIS one
        printf "  %8.1f s wall, %2d sibling leg(s) in flight, rc!=0   %s\n", w[i] / 1000, infl - 1, nm[i]
      }
      printf "  ⚠ The sibling count is the number to read: pool-level starvation of a fork-heavy arm looks\n"
      printf "    like a flaky item and is not one — the same arm passes SOLO and fails beside this many.\n"
    }'
}

_report() {
  local i rc fails=0 rem=0 ran=0 filt=0 excl=0 never=""
  for i in "${!labels[@]}"; do
    local label="${labels[$i]}"
    case "${states[$i]}" in
      listed)   continue ;;
      filtered) filt=$((filt+1)); continue ;;
      excluded) excl=$((excl+1)); continue ;;
      # HD-1137: registered but NEVER LAUNCHED. Counting it as ran would let the run-count audit agree
      # with a runner that dropped work, so it is NOT counted and the audit says so by name.
      pending) never+="${labels[$i]}"$'\n'; continue ;;
    esac
    printf '\n== %s ==\n' "$label"
    wait "${pids[$i]}" >/dev/null 2>&1 || true
    _read_rc "$i"; rc="$RC"
    [ "$RC_MISSING" = 1 ] && rc_missing=$((rc_missing+1))
    _ms_between "${starts[$i]}" "$END"; walls[$i]="$MS"; ends[$i]="${END:-${starts[$i]}}"
    [ -f "$RUN/$i.log" ] && cat "$RUN/$i.log"
    ran=$((ran+1))
    if [ "$rc" != "0" ]; then
      if [ "${_reminders[$i]:-0}" = 1 ]; then
        # A reminder that came back non-zero is REPORTED and counted, never a failure (CONVENTIONS §6.4):
        # the finding is the point, the red is not. rc 2 (could not measure) prints the same way — the
        # output below carries that word, so a blind reminder is visible without stopping a merge.
        printf 'REMINDER not clean (rc %s): %s\n' "$rc" "$label"
        rem=$((rem+1))
      else
        printf 'FAILED (rc %s): %s\n' "$rc" "$label"
        fails=$((fails+1))
      fi
    fi
  done
  # Say how fast the HOST was, not only how long the gate took. WHY: "why is the gate slow?" was
  # answered three different ways on this repo in one day — 31 s quiet, 351 s with a second gate
  # running — and none of those numbers describe the gate. The per-exec number does: it is 0.66 ms on
  # WSL Debian, 16–44 ms on a quiet Win11 git-bash seat, and 130–185 ms on that same seat while
  # another 24-way pool is forking with it (or an AV scan is mid-flight). Five execs to measure it.
  local _ft0 _ft1 _fc=5 _fe=/bin/true _ms
  command -v true >/dev/null 2>&1 && _fe="$(command -v true)"
  _ft0=$EPOCHREALTIME
  for i in $(seq "$_fc"); do "$_fe" >/dev/null 2>&1 || true; done
  _ft1=$EPOCHREALTIME
  _ms="$(echo "$_ft1 $_ft0" | awk -v n="$_fc" '{printf "%.1f", ($1-$2)/n*1000}')"
  printf '\ngate: %ss wall, %d items, %s ms/exec on this host (WSL Debian: 0.7)\n' \
    "$(( SECONDS - GATE_T0 ))" "$ran" "$_ms"
  case "$(echo "$_ms" | awk '{print ($1 > 60) ? "degraded" : (($1 > 2) ? "slow" : "fast")}')" in
    degraded) echo "      ⚠ process creation is DEGRADED on this host (a quiet Win11 git-bash seat is 16-44 ms)."
              echo "        Another validate-all is forking with you, or a real-time AV scan is mid-flight: the"
              echo "        the whole set cost 31 s quiet and 351 s with a second 24-way pool running (2026-10-10)." ;;
    slow)     if [ "$IS_MSYS" = 1 ]; then
                echo "      ℹ this host pays for FORKS, not validators — every leg costs ~1 process + its work."
                echo "        Where forks are cheap the same gate is ~5x faster: wsl -d Debian bash -c"
                echo "        'cd <clone> && bash scripts/validate-all.sh'  (7.9 s measured on ext4, the same set)."
              else
                echo "      ℹ a Linux seat should be under ~1 ms/exec; at this rate something is intercepting"
                echo "        process creation here (an AV scan, a heavily loaded host, or I/O on a 9P /mnt/ mount)."
              fi ;;
  esac
  # ---- HD-1137 --time: the accounting. Additive: no existing line moves, no verdict changes. ----
  [ "$TIME" = 1 ] && _time_report
  # ---- HD-1137 run-count audit ---------------------------------------------- #
  # The registry is the only claim about what a run owes, and this is the half of the `--list | wc -l`
  # audit that lives INSIDE the gate: every registered item must land in exactly one bucket — ran,
  # filtered by --only, excluded by the profile — and every one that ran must have LEFT A RESULT FILE.
  # With no --only and no profile the first line reads exactly `completed N, registered N`: a default
  # run executing the same count `--list` prints is what proves the new code path dropped no work. A
  # missing rc file is the shape a dropped accounting line takes — the run looks clean because nothing
  # was ever asked about that item. Silent at rest, like every good assertion.
  local _l
  local _want=$(( n_items - filt - excl ))
  if [ "$ran" -ne "$_want" ] || [ "$rc_missing" -gt 0 ]; then
    {
      echo "FAIL: the gate did not ACCOUNT for its own work (HD-1137) — a defect in the RUNNER, not in the tree."
      printf '      completed %d item(s); registered %d minus %d filtered by --only minus %d excluded by profile = %d\n' \
        "$ran" "$n_items" "$filt" "$excl" "$_want"
      printf '      profile %s%s%s — an item that never launched, or launched and was never reaped, is a check that ran never.\n' \
        "$PROFILE" "${ONLY:+, --only }" "${ONLY:-}"
      if [ -n "$never" ]; then
        printf '      registered and NEVER LAUNCHED:\n'
        _l=""
        while IFS= read -r _l; do
          if [ -n "$_l" ]; then printf '        - %s\n' "$_l"; fi
        done <<< "$never"
      fi
      if [ "$rc_missing" -gt 0 ]; then
        printf '      %d item(s) left NO result file: they launched and never reported — a leg that cannot be seen cannot fail.\n' "$rc_missing"
      fi
      echo "      This is the 223b571b class (an item ran never while every gate said green). Do not shrug it."
    } >&2
    exit 1
  fi
  # ---- HD-1117: a RED run carries its own diagnosis ------------------------------------------- #
  if [ "$fails" -gt 0 ]; then _diagnose_fails; fi
  [ "$fails" -eq 0 ] || { printf '\n%d of %d items FAILED:\n' "$fails" "$ran"
    for i in "${!labels[@]}"; do
      [ "${states[$i]}" = "run" ] || continue
      [ "${_reminders[$i]:-0}" = 1 ] && continue      # a reminder is never in the failed list
      [ "$(_rc_of "$i")" != "0" ] && printf '  - %s\n' "${labels[$i]}"
    done; exit 1; }
  [ "$filt" -gt 0 ] && echo "($filt items filtered by --only)"
  echo "OK: all validators passed"
  if [ "$rem" -gt 0 ]; then
    echo "   $rem REMINDER item(s) had findings — non-blocking by design (CONVENTIONS §6.4): the session"
    echo "   that wrote the line clears it, and a reminder nobody clears for weeks is retuned, not promoted."
  fi
  # The quick profile's last words must be what it did NOT prove (CONVENTIONS §6 applied to a profile:
  # a boundary prints, it never implies). After the verdict, so it is the last thing anyone reads.
  # An `if`, not `[ … ] &&`: as the function's LAST statement an AND-list would return 1 on a full run
  # and the whole gate would exit 1 while printing "OK: all validators passed".
  if [ "$PROFILE" = quick ]; then _not_proven; fi
  return 0
}

# --------------------------------------------------------------------------- #
# Blocks too big to be a single `item` line. They are the SAME commands that   #
# used to sit inline; moving them here is what lets them run in the background. #
# --------------------------------------------------------------------------- #

# The HD-413 guard fixture and the playbook syntax loop each fan out over ansible
# themselves. GATE_NPAR bounds that fan-out when the parent pool is smaller than the
# box, so the two legs together stay inside the core count.
blk_guard_fixture() {
  bash scripts/testdata/self-converge-guard/run.sh
}

blk_ansible_syntax() {
  # HD-256: like ansible-run.sh, export ANSIBLE_CONFIG + ANSIBLE_ROLES_PATH so the
  # role path resolves when running from the repo root on the Debian/WSL primary
  # (otherwise ansible finds no config here and every `roles: - xxx` fails to resolve).
  # Kept INSIDE this item: the other items must not inherit an Ansible environment they
  # never asked for.
  local REPO_ROOT; REPO_ROOT="$(pwd)"
  export ANSIBLE_CONFIG="$REPO_ROOT/IaC/ansible/ansible.cfg"
  export ANSIBLE_ROLES_PATH="$REPO_ROOT/IaC/ansible/roles"
  if command -v ansible-playbook >/dev/null 2>&1 && ansible-playbook --version >/dev/null 2>&1; then
    # Measured on the 8-core runner: serial 8.4 s, concurrent 3.0 s, and per playbook
    # 0.37-1.5 s of which ~95 % is ansible-playbook interpreter startup — there is no
    # work here to optimise, only waiting. Syntax-checking is read-only and every
    # playbook gets its own stderr/rc file, so the duplicate-key witness below still sees
    # exactly what ansible printed for each playbook, and one playbook cannot affect another's rc.
    local SC_DIR="$RUN/syntax-check.$BASHPID"; mkdir -p "$SC_DIR"  # a $RUN subdir: the gate's single EXIT trap owns it — never re-trap here
    local names=() files=() i=0 pb n rc_all=0 rc in_flight=0
    for pb in IaC/ansible/site.yml IaC/ansible/playbooks/*.yml; do
      n="pb$i"
      # HD-1135/HD-1117: the ACQUIRE the pool runner above already uses. This loop used to launch and
      # then ask `jobs -rp | wc -l` every 50 ms — 37 forks (27 wc + 10 sleep) for its 16 playbooks at
      # GATE_NPAR=12, counted 2026-10-19 on the WSL Debian seat with wc/sleep shimmed onto PATH — and
      # those forks land on the same process-creation queue as the items running beside this one in
      # the pool, which is the contention HD-1117 is about. Waiting is exact and costs nothing.
      if [ "${HAVE_WAITN:-0}" = 1 ]; then
        while [ "$in_flight" -ge "$GATE_NPAR" ]; do
          wait -n >/dev/null 2>&1 || true
          in_flight=$((in_flight - 1))
        done
      else
        while [ "$(jobs -rp | wc -l)" -ge "$GATE_NPAR" ]; do sleep 0.05; done   # bash < 5.1: no wait -n
      fi
      ( ansible-playbook -i IaC/ansible/inventory.ini "$pb" --syntax-check \
          >/dev/null 2>"$SC_DIR/$n.err"; echo "$?" > "$SC_DIR/$n.rc" ) &
      in_flight=$((in_flight + 1))
      names+=("$n"); files+=("$pb"); i=$((i+1))
    done
    wait
    # HD-1098: ansible's own parser is the second witness for duplicate mapping keys. It
    # prints `Found duplicate mapping key … Using last defined value only.` on stderr and
    # carries on, so the warning has to be caught here or the FIRST definition stays dead.
    for j in "${!names[@]}"; do
      n="${names[$j]}"; pb="${files[$j]}"; rc=0
      [ -f "$SC_DIR/$n.rc" ] && rc="$(cat "$SC_DIR/$n.rc")" || rc=1
      if grep -q "Found duplicate mapping key" "$SC_DIR/$n.err" 2>/dev/null; then
        echo "FAIL: ansible reported a duplicate mapping key while parsing $pb — it keeps the LAST"
        echo "      definition and drops the first, so the earlier one is dead (HD-1098):"
        grep -A3 "Found duplicate mapping key" "$SC_DIR/$n.err" | sed 's/^/  /'
        exit 1
      fi
      if [ "$rc" -ne 0 ]; then
        # unchanged HD-197 semantics: a real syntax failure still fails this item (the
        # duplicate-key leg above must not have turned this loop into a warning collector)
        echo "FAIL: ansible-playbook --syntax-check failed for $pb (rc $rc)" >&2
        cat "$SC_DIR/$n.err" >&2
        rc_all="$rc"
      fi
    done
    [ "$rc_all" -eq 0 ] || exit "$rc_all"
    echo "OK: all playbooks pass --syntax-check (parallel, $GATE_NPAR at a time)"
  else
    echo "SKIP: ansible-playbook not functional on this host (absent or native-Windows WinError 87) — syntax gate runs under WSL/CI"
  fi
}

# Portability sweep, HD-256. Split into its two halves so they overlap: both used to
# sit in one serial block. bash -n is a no-op on hosts without bash (Windows); the
# py_compile half deliberately uses python3, not $PY — the claim is about python3.
blk_bash_n_sweep() {
  if command -v bash >/dev/null 2>&1; then
    local f first bash_fail=0
    for f in scripts/*.sh scripts/testdata/check-vault-items/run.sh \
             scripts/testdata/self-converge-guard/run.sh \
             scripts/testdata/rsync-max-delete/run.sh; do
      [ -f "$f" ] || continue
      # `$(head -n1 "$f")` was one EXEC PER FILE — an extra ~90 processes to ask what the shebang
      # says. `read` answers it in-process; with -r the CR of a CRLF checkout survives, exactly as it
      # did through head, so the *bash|*sh match below is unchanged.
      first=""; IFS= read -r first < "$f" || true
      case "$first" in
        *bash|*sh)
          bash -n "$f" >/dev/null 2>&1 || { echo "bash -n FAIL: $f" >&2; bash_fail=$((bash_fail+1)); }
          ;;
      esac
    done
    [ "$bash_fail" -eq 0 ] || exit 1
    echo "OK: all bash/sh scripts pass bash -n"
  else
    echo "SKIP: bash not on PATH — bash -n sweep runs under WSL/CI"
  fi
}

blk_py_compile_sweep() {
  # Usability, not existence (2026-10-09): on a Win11 seat `python3` resolves to the Microsoft Store alias
  # STUB — it is on PATH, it is not an interpreter, and `command -v` cannot tell. Gating on existence made
  # every file print `py_compile FAIL` on that seat, which is a misleading RED, not a gate; CONVENTIONS §6
  # requires an environment boundary to print SKIP naming the reason. $PY (probed above) carries the sweep
  # when python3 is unusable, so the portability claim still runs — under a named interpreter.
  local -a _pc=(${PY_CMD[@]:-python3}); local f py_fail=0
  if python3 -c "import sys" >/dev/null 2>&1; then _pc=(python3); fi
  # ONE interpreter start for the whole sweep, not one per file: py_compile takes a LIST of files, and
  # an interpreter start here costs 0.2-0.35 s, so the per-file loop was ~57 starts for ~1 s of work
  # (measured: this leg cost 10.8 s solo on the Win11 seat, 0.7 s on the Debian one).
  # The per-file loop is kept as the FAIL PATH, so a broken file is still NAMED, not just counted.
  local -a pys=()
  for f in scripts/*.py; do [ -f "$f" ] && pys+=("$f"); done
  if [ "${#pys[@]}" -gt 0 ] && ! "${_pc[@]}" -m py_compile "${pys[@]}" >/dev/null 2>&1; then
    for f in "${pys[@]}"; do
      # shellcheck disable=SC2086
      "${_pc[@]}" -m py_compile "$f" >/dev/null 2>&1 || { echo "py_compile FAIL ($f) under ${_pc[*]}" >&2; py_fail=$((py_fail+1)); }
    done
  fi
  [ "$py_fail" -eq 0 ] || exit 1
  echo "OK: all scripts/*.py compile under ${_pc[*]} (${#pys[@]} files, one interpreter start)"
}

# The seat/host-state gates: each SKIPs where the thing it checks is absent, so a
# stateless runner is never broken by them (and a SKIP is printed, never counted green).
blk_skills_drift() {
  if [ -d "$HOME/.pi/agent/skills" ]; then
    bash scripts/harness/sync-skills.sh --check --strict
  else
    echo "SKIP: no ~/.pi/agent/skills on this host (bare CI / non-pi laptop) — skill gate runs where pi is configured"
  fi
}

blk_extensions_check() {
  if [ -d "$HOME/.pi/agent/extensions" ]; then
    bash scripts/harness/sync-extensions.sh --check --strict
  else
    echo "SKIP: no ~/.pi/agent/extensions on this host — extension gate runs where pi is configured (deploy: sync-extensions.sh --push)"
  fi
}

blk_tmux_check() {
  if [ -f "$HOME/.tmux.conf" ]; then
    bash scripts/harness/install-tmux-conf.sh --check --strict
  else
    echo "SKIP: no ~/.tmux.conf on this host — the seat harness gate runs where tmux is installed (deploy: install-tmux-conf.sh --push)"
  fi
}

# The bench provenance eye. Its rc 2 is NOT JUDGED: the results CSV is a bench artifact that lives on the
# seat that ran the legs, so a tree without one has no evidence either way. Printed, never passed off as
# a clean provenance read — the same shape as the leak eye below and the rsync cap above.
blk_bench_provenance() {
  local rc_prov=0
  "${PY_CMD[@]}" scripts/gate/check_bench_provenance.py || rc_prov=$?
  case "$rc_prov" in
    0) return 0 ;;
    2) echo "SKIP: no results CSV was read — the legs this item would judge are not in this tree. A provenance"; echo "      read that read no stamp is not a pass: run it with --csv <results-v2.csv> where the legs landed."; return 0 ;;
    *) return "$rc_prov" ;;
  esac
}

# The leak eye. Its own SKIP semantics: no `op`, no importable Server SDK, or an unreadable vault is
# an environment boundary (rc 2), printed and never counted green — the check compares captured bytes
# against the vault's CURRENT values, so without them it has no idea what a leak would look like. The
# whole-vault read is the ONE batched read of scripts/lib/vault_read.py, and the run prints its
# request count. It judges three classes (the working tree, the seat's run captures, and every blob a ref still reaches); a run asked
# to read less says which class it did NOT look at instead of reading as a full green.
blk_secret_leak() {
  local rc_leak=0
  "${PY_CMD[@]}" scripts/gate/check_secret_leak.py "$@" || rc_leak=$?
  case "$rc_leak" in
    0) return 0 ;;
    2) echo "SKIP: the vault is not readable here — reason above; a leak check without current values cannot judge, and a SKIP is not a pass"; return 0 ;;
    *) return "$rc_leak" ;;
  esac
}

# The debt register's checker. Same rc-2 semantics as the leak eye, for the same reason: it decides
# `rotated yet?` from the vault's per-item VERSION numbers, so a seat that cannot read the vault knows
# nothing either way and prints SKIP. Its rc 1 is a classified red, not "a debt is open": the checker
# grades every verdict into BLOCKING (REFUSED — a close no version move backs; UNLEDGERED — a CURRENT
# value the ledger rightly does not mute, which is the leak gate's own red restated) and REMINDER
# (NOT ROTATED, CANDIDATE — an act someone named still owes). Redding on a reminder would be permanent
# for the register's `path: none` lines, and a permanent red is the mute CONVENTIONS §6.4 exists to
# prevent; the classification and its arms are in docs/deployment-secrets.md §Creation & Rotation
# Workflow item 9.
blk_secret_debt() {
  local rc_debt=0
  "${PY_CMD[@]}" scripts/gate/check_secret_debt.py "$@" || rc_debt=$?
  case "$rc_debt" in
    0) return 0 ;;
    2) echo "SKIP: the vault or the register is not readable here — reason above; a debt check that read"; echo "      no versions judges nothing, and a SKIP is not a pass"; return 0 ;;
    *) return "$rc_debt" ;;
  esac
}

# rc 2 = no pi binary here = SKIP, printed and never counted green (CONVENTIONS: a SKIP
# is not a pass). BEHIND and AHEAD are both drift — a seat ahead of its pin is the shape
# every file plane misses.
blk_pi_self_check() {
  local rc_piself=0
  bash scripts/harness/pi-self-update.sh --check --strict || rc_piself=$?
  case "$rc_piself" in
    0) echo "OK: the pi build on this host equals pi_host_npm_version" ;;
    2) echo "SKIP: no pi binary on this host — the pi-self plane runs where pi is installed (pi-seat-sync.sh --push)" ;;
    *) echo "FAIL: the pi build drifts from pi_host_npm_version — run: bash scripts/harness/pi-self-update.sh --push"; exit 1 ;;
  esac
}

blk_pi_settings_check() {
  if [ -f "$HOME/.pi/agent/settings.json" ]; then
    bash scripts/harness/pi-settings-config.sh --check --strict
  else
    echo "SKIP: no ~/.pi/agent/settings.json on this host — the settings plane runs where pi is configured (deploy: pi-seat-sync.sh --push)"
  fi
}

blk_pi_tui_check() {
  if [ -f "$HOME/.pi/agent/open-tui.json" ]; then
    bash scripts/harness/pi-tui-config.sh --check --strict
  else
    echo "SKIP: no ~/.pi/agent/open-tui.json on this host — the TUI footer gate runs where pi-open-tui is installed"
  fi
}

# The font plane is the one item that is allowed to be red without failing the gate, and
# that is deliberate (the Windows leg is scripts/harness/win/install-nerd-font.ps1). It is printed
# as a NOTE so a green run still says which plane it did not prove.
blk_font_check() {
  if [ -d "${NERD_FONT_DIR:-$HOME/.local/share/fonts}" ] || command -v fc-list >/dev/null 2>&1; then
    NERD_FONT_DIR="${NERD_FONT_DIR:-$HOME/.local/share/fonts}"/JetBrainsMono-Nerd-Font \
      bash scripts/harness/install-nerd-font.sh --check --strict \
      || echo "NOTE: the font plane is not green on this host — on the Windows seat the leg that matters is scripts/harness/win/install-nerd-font.ps1"
  else
    echo "SKIP: no user font dir / no fontconfig here — the font plane runs where the TUI's glyphs are drawn"
  fi
}

# The seat's ssh BUILD plane (HD-1128): the alias plane can be byte-perfect and the leg still dies, so
# this asks the shell which binary answers. rc 2 = a boundary (no Windows here, or no PowerShell profile
# loads), printed and never counted green; rc 1 = drift; rc 3 = a refusal a human must reconcile.
blk_seat_ssh_check() {
  local rc_ssh=0
  bash scripts/harness/seat-ssh-build.sh --check --strict || rc_ssh=$?
  case "$rc_ssh" in
    0) echo "OK: a profile-loaded shell on this seat resolves the OpenSSL ssh build" ;;
    2) echo "SKIP: the ssh-build plane owns only the win11 seat's PowerShell profiles (or no shell here loads a profile) — deploy on that seat with: bash scripts/harness/seat-ssh-build.sh --push" ;;
    3) echo "FAIL: the seat's ssh-build block was hand-edited or is shadowed by another ssh definition — reconcile it, then: bash scripts/harness/seat-ssh-build.sh --push"; exit 1 ;;
    *) echo "FAIL: this seat's ssh-build block is missing or stale, or a profile-loaded shell still resolves the LibreSSL build (which cannot load the fleet's PKCS#8 keys) — run: bash scripts/harness/seat-ssh-build.sh --push"; exit 1 ;;
  esac
}

# The seat's BASH BUILD plane: the same HD-1128 defect on the other binary. A bare `bash` on a
# Windows-native PATH is the WSL launcher, and every harness command in this repo is written
# `bash scripts/...` — so a seat can read the right repo through /mnt and the WRONG $HOME, and a
# settings-plane finding there describes a file that is not this seat's. rc 2 is a boundary (not
# Windows here, no Git bash resolves, or no shell loads a profile), never a green.
blk_seat_bash_check() {
  local rc_sbash=0
  bash scripts/harness/seat-bash-build.sh --check --strict || rc_sbash=$?
  case "$rc_sbash" in
    0) echo "OK: a profile-loaded shell on this seat resolves Git-Bash for a bare bash (not the WSL launcher)" ;;
    2) echo "SKIP: the bash-build plane owns only the win11 seat's PowerShell profiles (or no shell here loads a profile) — deploy on that seat with: bash scripts/harness/seat-bash-build.sh --push" ;;
    3) echo "FAIL: the seat's bash-build block was hand-edited, duplicated, or is shadowed by another bash definition — reconcile it, then: bash scripts/harness/seat-bash-build.sh --push"; exit 1 ;;
    *) echo "FAIL: this seat's bash-build block is missing or stale, or a profile-loaded shell still resolves the WSL launcher (which runs the harness in another distro's HOME) — run: bash scripts/harness/seat-bash-build.sh --push"; exit 1 ;;
  esac
}

# --------------------------------------------------------------------------- #
# The queue. Longest items FIRST — the pool launches in this order, so putting #
# the multi-second items here is the scheduling, not a priority system.        #
# --------------------------------------------------------------------------- #

# --------------------------------------------------------------------------- #
# The queue. Longest items FIRST — the pool launches in this order, so putting #
# the multi-second items here is the scheduling, not a priority system.        #
#                                                                            #
# HD-1137: every registration here also declares its PROFILE decision:        #
#   item_q / item_blk_q                  runs in `--profile quick` too         #
#   item_x "<reason>" / item_blk_x       excluded from quick — the reason is   #
#                                        MANDATORY, and it must be an argument #
#                                        (CONVENTIONS §6: under ~40 chars is    #
#                                        "not an argument")                     #
#   item / item_blk (bare)               UNDECIDED → `--profile quick` refuses #
# The quick set is a subset of THIS list, read from THIS list at run time: there #
# is no second registry to keep in step, which is the whole reason there is no  #
# second gate script (see the header, and `aa0bc737`).                          #
# --------------------------------------------------------------------------- #

# The two ansible legs (each fans out internally).
item_blk_x "runs the real ansible-playbook against a throwaway inventory: needs ~/ansible-venv, and it is the longest leg in the gate — a pre-commit loop buys this at a converge, not at a commit" "testdata/self-converge-guard/run.sh (HD-413 verdict matrix, runtime)" blk_guard_fixture
item_blk_x "ansible is absent or dies WinError 87 on the Windows seat, so this SKIPs here anyway; on a WSL/CI runner it is the syntax half that a quick loop does not need per keystroke" "ansible-playbook --syntax-check (WSL/CI-gated)" blk_ansible_syntax

# The corpus walkers.
# The corpus walkers. Longest leg first, per the pool note in the header.
item_x "reads the vault to know what a leak is: ONE batched read whose request count the run prints itself (the Server SDK answers the vault's ~143 items in 1 list + 3 get_all chunks; the labelled `op item get` FALLBACK costs 1 list + 1 read per item until the seat step in docs/1password.md runs), then a content search over the seat's run captures (~560 MB) and the working tree, then the git-history leg (11 942 blobs reachable from refs, ~525 MB — ~9 s cold, and ~0.2 s once the cache in the object store is warm, which the run prints either way). About 23 s on this seat, which is the whole pre-commit budget and more; it also only means something where a vault token exists" "check_secret_leak.py (current vault values vs the run-capture class, the working tree, and every blob a ref still reaches)" blk_secret_leak
item_q "check_secret_leak.py --self-test (the shapes that leaked must each redden, the finding text must disclose nothing, the vault boundary must SKIP, the ledger must mute only what it names, a published-then-deleted value must still redden through the history leg, a partial sweep must say PARTIAL, a partial VAULT READ must say so and may not shorten the ledger, and --update-ledger must not delete a line it cannot prove — and every mutant of the scanner must be caught, the count is printed by the run)" "${PY_CMD[@]}" scripts/gate/check_secret_leak.py --self-test
item_x "reads the vault a second time for the debt register's VERSION column (the names-only list is tried first and, on an SDK whose list rows carry no versions, the batched read answers for 4 — the run prints which route answered and what it cost). Then a per-line verdict over the register, the twin arm against provision-secrets.py's NOT_ROTATABLE, and the seat-locality rule; ~2 s on this seat, and it only means something where a vault token exists" "check_secret_debt.py (who acts on each leak debt, on which seat, and whether the value behind it has rotated)" blk_secret_debt
item_q "check_secret_debt.py --self-test (the four verdicts must each be reachable, the version-bump arm must move ONE line and no other, a foreign seat's line may never close, a store-less run may not close its own, the two no-rotation-path sets must disagree loudly in both directions, a bad register line reddens rather than shortening the book, EVERY verdict must land in the exit class it is filed under with an unplaced word reddening rather than going quietly green, and nothing but an 8-char id prefix is ever printed)" "${PY_CMD[@]}" scripts/gate/check_secret_debt.py --self-test
item_x "walks the whole tracked tip, 99 MB with archive members included and no cache of any kind, so every profile pays the full walk; the arm is parked OUT of the pre-commit loop because that walk is the whole budget of one" "check_secrets.py (secret shapes in the tracked tip, archive members included)" "${PY_CMD[@]}" scripts/gate/check_secrets.py
item_x "re-execs itself per archive/casefold arm: a shape-grammar self-test, not a tree check — rerun it when the scanner changes, not per commit" "check_secrets.py --self-test (the speed prefilter must not have narrowed a shape)" "${PY_CMD[@]}" scripts/gate/check_secrets.py --self-test
item_q "check_yaml_dup_keys.py (HD-1098: a duplicate YAML key is a silent no-op)" "${PY_CMD[@]}" scripts/gate/check_yaml_dup_keys.py
item_q "check_yaml_dup_keys.py --self-test (HD-1098 canaries + corpus probe)" "${PY_CMD[@]}" scripts/gate/check_yaml_dup_keys.py --self-test
item_q "check_zone_kogler_si_parity.py (derived zone answers what the hand-authored sources did, HD-436)" "${PY_CMD[@]}" scripts/gate/check_zone_kogler_si_parity.py
item_q "check_zone_kogler_si_parity.py --self-test" "${PY_CMD[@]}" scripts/gate/check_zone_kogler_si_parity.py --self-test
item_q "check_dns_seed_drift.py (Technitium split-horizon seed contract, HD-341 parity)" "${PY_CMD[@]}" scripts/gate/check_dns_seed_drift.py
item_q "check_dns_policy_drift.py (the DNS policy SSOT, its one writer, and its asserted read-back)" "${PY_CMD[@]}" scripts/gate/check_dns_policy_drift.py
item_q "check_dns_seed_prune_guard.py (the seed delete leg cannot delete a listed record)" "${PY_CMD[@]}" scripts/gate/check_dns_seed_prune_guard.py
item_q "check_dns_seed_prune_guard.py --self-test (the refusal must be seen to fail three ways)" "${PY_CMD[@]}" scripts/gate/check_dns_seed_prune_guard.py --self-test
item_q "check_self_converge_guard.py (HD-413 guardrail completeness, static)" "${PY_CMD[@]}" scripts/gate/check_self_converge_guard.py
item_q "check_hd_mint_space.py (the backlog id space: no fixture id outside the reserved block, no row inside it)" "${PY_CMD[@]}" scripts/gate/check_hd_mint_space.py
item_q "check_hd_mint_space.py --self-test (each rule bred on a throwaway repo; the legal shapes must stay green)" "${PY_CMD[@]}" scripts/gate/check_hd_mint_space.py --self-test
item_q "check_net_manager.py (per-host config-manager declaration: no implied manager, no implied render leg)" "${PY_CMD[@]}" scripts/gate/check_net_manager.py
item_q "check_net_manager.py --self-test (each rule bred on a tree copy: canaries must redden, the legal shapes must stay green)" "${PY_CMD[@]}" scripts/gate/check_net_manager.py --self-test
item_q "probe-net-manager.sh --self-test (the config-manager verdict still separates the states it names)" bash scripts/ansible/probe-net-manager.sh --self-test
# The live half of the next item is deliberately NOT registered: a read tool must never fail a commit
# (the same reason `ansible_query.py` gates only its fixture). What IS gated is the offline proof that
# the verdict can still redden — a dark monitoring host emits NO series, so no metric rule can see it
# and the only instrument is the inventory's expected set compared against one live query.
item_q "check_host_reporting.py --self-test (the expected-set verdict: a dark host, an undeclared reporter and the two stale shapes must each redden)" "${PY_CMD[@]}" scripts/gate/check_host_reporting.py --self-test
item_x "walks every byte under IaC/ for twin groups and its self-test re-derives a 2,300-group baseline — minutes on this host, and a pre-commit edit does not rename a twin" "check_string_twins.py (a string two files shipped byte-equal at the wave baseline may not be renamed on one side)" "${PY_CMD[@]}" scripts/gate/check_string_twins.py
# The plain run above cannot tell a gate that has lost its teeth from a gate that passed: on a
# green tree both print one OK line, and the cases that prove the verdict (a sever inside a long
# change run, a twin renamed on every side, an agreed value in the wrong kind of literal) never
# ran in the suite. Every other check here registers its self-test too; this one did not.
item_x "its positive control re-populates a real git tree to prove the verdict: the most expensive leg in the gate, and the wave-boundary act owns when it is owed" "check_string_twins.py --self-test (the verdict cases: planted severs, the 8b28edd3 control, presence-proven renames)" "${PY_CMD[@]}" scripts/gate/check_string_twins.py --self-test
item_q "validate-docker-services.py" "${PY_CMD[@]}" scripts/gate/validate-docker-services.py
item_x "renders 16 arms of the spark compose template: a profile-matrix check, not a tree check — buy it when a profile changes" "spark-llm-render-matrix.py (HD-489: every profile must RENDER, not just validate)" "${PY_CMD[@]}" scripts/bench/spark-llm-render-matrix.py
item_q "check_doc_path_refs.py (HD-490: a path a doc cites must exist)" "${PY_CMD[@]}" scripts/gate/check_doc_path_refs.py
item_q "check_doc_path_refs.py --self-test (HD-490 canary)" "${PY_CMD[@]}" scripts/gate/check_doc_path_refs.py --self-test
item_q "check_doc_headings.py (the ANCHOR half: a § pointer must name a heading that exists; the committed ledger makes it growth-only)" "${PY_CMD[@]}" scripts/gate/check_doc_headings.py
item_q "check_doc_headings.py --self-test (anchor canaries + both halves of the ledger ratchet)" "${PY_CMD[@]}" scripts/gate/check_doc_headings.py --self-test
item_q "check_handoff_size.py (the standing handoff keeps its shape: answered-item history and typed counts reddens against the frozen seal; the size half is a REMINDER only, because size is the proxy and the changelog is the rule)" "${PY_CMD[@]}" scripts/gate/check_handoff_size.py
item_q "check_handoff_size.py --self-test (both size-reminder halves proved live and non-blocking, the marker exemptions, each count shape, and both halves of the seal ratchet)" "${PY_CMD[@]}" scripts/gate/check_handoff_size.py --self-test
item_q "check_registry_prose.py (CONVENTIONS §6 on this file: registry states facts + owning spec, no ids/dates/narrative/glyphs/pipe-in-code/dup-paragraph)" "${PY_CMD[@]}" scripts/gate/check_registry_prose.py
item_q "check_registry_prose.py --self-test (each prose rule bred + every exemption kept quiet + the empty-corpus refusal)" "${PY_CMD[@]}" scripts/gate/check_registry_prose.py --self-test
item_q "validate_doc_templates.py" "${PY_CMD[@]}" scripts/gate/validate_doc_templates.py
item_q "render_all.py --self-test (HD-1117: the generated-doc drift check reads green twice, and an SSOT change still reddens it)" "${PY_CMD[@]}" scripts/render_all.py --self-test
# The fixture first, then the tree it judges: the arms above prove the checker can read green AND
# can still redden, so a red from the real-tree leg below is a drift finding, not a broken checker.
# `--no-write` is what makes the real-tree leg legal in a POOL — it renders into a temp dir, so no
# item beside it can ever read a generated doc that is mid-write (an in-place `--check` measured
# 2,383 zero-length or partial reads out of 6.67 M for a concurrent reader in this tree).
item_q "render_all.py --check --no-write (HD-1117: every *-generated.md must equal the render of its SSOT; rendered in a temp dir, so docs/ is never the target)" "${PY_CMD[@]}" scripts/render_all.py --check --no-write
item_q "check_vault_name.py" "${PY_CMD[@]}" scripts/gate/check_vault_name.py
item_q "check_placeholders.py" "${PY_CMD[@]}" scripts/gate/check_placeholders.py
item_q "bash -n sweep (HD-256 portability, all scripts/*.sh)" blk_bash_n_sweep
item_q "python3 -m py_compile sweep (HD-256 portability, all scripts/*.py)" blk_py_compile_sweep

# Seat planes — self-tests run everywhere (sandboxed), the --check half SKIPs per host.
# A seat with no node is the one exception the sentence never held: a seat with NO usable node cannot run a
# node-driven self-test at all, and the script answers that with rc 2 + a printed SKIP, the shape its
# --check half uses. rc 2 is a boundary, not a verdict about the harness, so it is printed and NOT
# counted — the same mapping blk_pi_self and the seat-*-build checks apply to that rc. Deleting the
# mapping reddens `oldsrv`, which is the seat that proved the need for it.
st_pi_settings_selftest() {
  local rc=0
  bash scripts/harness/pi-settings-config.sh --self-test || rc=$?
  case "$rc" in
    0) return 0 ;;
    2) echo "SKIP: no usable node on this seat — the settings-plane self-test ran NOTHING (the harness is not broken, the seat has no node; a SKIP is not a pass)"; return 0 ;;
    *) return "$rc" ;;
  esac
}
st_pi_tui_selftest() {
  local rc=0
  bash scripts/harness/pi-tui-config.sh --self-test || rc=$?
  case "$rc" in
    0) return 0 ;;
    2) echo "SKIP: no usable node on this seat — the pi-open-tui footer self-test ran NOTHING (the harness is not broken, the seat has no node; a SKIP is not a pass)"; return 0 ;;
    *) return "$rc" ;;
  esac
}
# HD-1137: a seat DEPLOY half (--check --strict on a real ~/.pi) is deliberately NOT in quick: it
# reads and can converge THIS host's seat state, which is not what a pre-commit sanity read claims.
# The sandboxed --self-test halves stay in quick; the expensive ones carry their cost as the reason.
item_x "installs into a fixture HOME through stub installers across a dozen CLI launches — a harness self-test, not a tree check: rerun it when the installer changes" "install-nerd-font.sh --self-test (HD-1110: the pinned nerd-font release + sha256 manifest)" bash scripts/harness/install-nerd-font.sh --self-test
# NOTE (HD-1128): seat-ssh-build.sh --self-test is deliberately NOT gated. It is 27 assertions that pass
# standalone, but they run ~25 nested bash spawns and cost 98 s WALL / 72 s SYS on the Windows seat - inside
# the pool that starves sibling self-tests (measured: pi-seat-sync.sh --self-test printed 5 canaries NOT
# caught in the concurrent run and passed standalone, the documented pool-flake class). The cheap and
# meaningful half IS gated: the --check --strict item below.
item_x "~25 CLI launches against a fixture settings.json: HD-1135 measured 97 s on this seat even after the fork diet — a self-test for the settings harness, not a tree check" "pi-settings-config.sh --self-test (HD-1110: the harness keys of ~/.pi/agent/settings.json)" st_pi_settings_selftest
# The clone's own pre-push gate. The SELF-TEST is gated; the `--check --strict` half is NOT, on
# the HD-1137 rule: a clone's hooks are deploy state, and an item that reddens every session
# worktree that has not yet run `install-hooks.sh --push` would make one lane's unset-up seat
# another lane's red gate. The half that reports it is the seat plane `git-hooks` in
# lib/seat-planes.yml, which `pi-seat-sync.sh --check` fans out and prints as DRIFT.
item_q "install-hooks.sh --self-test (HD-1219: a canary blocks a real push, a clean tree passes and says what it did not scan, an unreachable vault SKIPs loudly, a crashed eye is never called a leak, and a second worktree of the same clone finds the hook — the arm the naive `dirname --git-dir` path fails)" bash scripts/git/install-hooks.sh --self-test
item_q "pi-tui-config.sh --self-test (HD-1110: the pi-open-tui footer hostname key)" st_pi_tui_selftest
item_x "drives every seat plane through stubbed seats in a temp HOME: HD-1135 measured 46 s on this seat — the fan-out driver's own harness, not a tree check" "pi-seat-sync.sh --self-test (HD-1110: the fan-out driver verdicts, on stubbed seats)" hl_wsl_route bash scripts/harness/pi-seat-sync.sh --self-test
item_x "arms sandboxed installers and a canary package name across every probe layout — an installer harness, and it must never touch a real registry" "pi-self-update.sh --self-test (HD-1115: BEHIND and AHEAD are both drift)" hl_wsl_route bash scripts/harness/pi-self-update.sh --self-test
item_x "spawns a real tmux per canary to prove the config TAKES EFFECT: where tmux is absent it can print no verdict at all (CONVENTIONS §6), so a pre-commit loop buys only waiting here" "install-tmux-conf.sh --self-test (HD-1085: config == repo AND actually takes effect)" bash scripts/harness/install-tmux-conf.sh --self-test
item_x "seat deploy state, not a tree check: it converges this host's ~/.tmux.conf, and where tmux is absent it prints SKIP either way" "install-tmux-conf.sh --check --strict (seat tmux drift)" blk_tmux_check
item_x "seat deploy state, not a tree check: it asks a profile-loaded PowerShell on THIS seat which ssh binary answers (win11 only)" "seat-ssh-build.sh --check --strict (HD-1128: which ssh build a seat shell resolves)" blk_seat_ssh_check
item_x "seat deploy state, not a tree check: it asks a profile-loaded PowerShell on THIS seat what a bare `bash` IS (win11 only; the WSL launcher is not a bash seat)" "seat-bash-build.sh --check --strict (which bash build a seat shell resolves)" blk_seat_bash_check
item_x "seat deploy state, not a tree check: the pi build against pi_host_npm_version, converged by pi-seat-sync.sh --push where pi is installed" "pi-self-update.sh --check --strict (the pi build vs pi_host_npm_version)" blk_pi_self_check
item_x "seat deploy state, not a tree check: it reads and can rewrite ~/.pi/agent/settings.json on this host" "pi-settings-config.sh --check --strict (settings.json vs settings-ssot.json)" blk_pi_settings_check
item_x "seat deploy state, not a tree check: the pi-open-tui footer key in this host's ~/.pi/agent/open-tui.json" "pi-tui-config.sh --check --strict (open-tui.json footer key)" blk_pi_tui_check
item_x "seat deploy state, not a tree check: the font plane is host state, and on the Windows seat the leg that matters is the .ps1 this item cannot run" "install-nerd-font.sh --check --strict (font dir vs pin)" blk_font_check
item_x "sixteen end-to-end CLI launches in a temp HOME (the HD-1135 record says so): it re-runs the per-assertion legs for its exit-code contract — a harness self-test, not a tree check" "sync-skills.sh --self-test (HD-254: drift, untracked, artifacts, CRLF/BOM/binary guard)" hl_wsl_route bash scripts/harness/sync-skills.sh --self-test
item_x "seat deploy state, not a tree check: repo skills/ against this host's ~/.pi/agent/skills, deployed by sync-skills.sh --push" "sync-skills.sh --check --strict (skill drift gate, HD-254)" blk_skills_drift
item_x "a sandboxed fixture over the same 16 arms as its sibling: an extension-harness self-test, not a tree check" "sync-extensions.sh --self-test (HD-254 family: missing fails, extra kept, retired removed)" hl_wsl_route bash scripts/harness/sync-extensions.sh --self-test
item_x "seat deploy state, not a tree check: repo pi-agent/extensions against this host's deployed extensions" "sync-extensions.sh --check --strict (repo pi-agent/extensions == deployed)" blk_extensions_check

# lib/ helpers — the root resolvers are the ONE thing every other item silently depends on, so
# they carry their own proof (HD-1118 Stage 1). The depth arms cannot be exercised by the real
# tree, which has exactly one depth, so each self-test builds a two-depth fixture: a resolver that
# still counts `..` passes the shallow arm and fails the deep one — that is the canary, and it is
# what makes Stage 3's folder moves a mechanical sweep instead of a gamble.
item_q "lib/repo-root.sh --self-test (HD-1118: the bash root resolves at TWO depths, loud when absent)" bash scripts/lib/repo-root.sh --self-test
item_q "lib/repo_root.py --self-test (HD-1118: the python twin + require_corpus + script_path)" "${PY_CMD[@]}" scripts/lib/repo_root.py --self-test
item_x "its pin() half resolves every real plane with grep|head|sed|tr PER pin — the fork tail HD-1135 still bills as open, so the fork diet owns this leg, not a pre-commit loop" "lib/pi-seat.sh --self-test (HD-1118: a missing pin STOPS the caller; no subshell pin call site may return)" bash scripts/lib/pi-seat.sh --self-test
# The hybrid route's own witness: it drives a STUB engine, so it grades this seat's decisions rather
# than the distro installed on it, and it runs in a tenth of a second. It is excluded from quick
# because it tests the router, not the tree — rerun it when the routing or the seat classes change.
item_x "a router self-test over a stub engine, not a tree check: rerun it when the routing, the seat classes, or the eligibility rule changes" "lib/wsl-route.sh --self-test (the win11 seat's hybrid route: which legs cross to the Debian engine, and what makes a leg ineligible)" bash scripts/lib/wsl-route.sh --self-test
# The credential rule the vault legs share. Sandboxed: a stub door, a throwaway HOME, synthesised
# fixture values — it reads no vault and needs no token, and its ratchet arm reads the tree, so it
# runs NATIVE (a wrapped leg must not read this checkout through a Linux git).
item_x "~40 bash spawns plus the ratchet's git grep (measured 11 s on the win11 seat, 1 s on Debian): a self-test of the credential rule, not a tree check — rerun it when the resolution order or a refusal changes" "lib/vault-env.sh --self-test (one credential rule for every vault leg: env → this seat's 0600 install → the Debian engine's install across the WSL door, and the refusals that must never fall back to the desktop app)" bash scripts/lib/vault-env.sh --self-test
item_x "~2 bash spawns and a fixture map in a temp dir: the python face is proved without ONE vault read, which is what makes it gradeable on a day the account's request budget is spent" "lib/vault_env.py --self-test (the ID map: read, honored, fallen back from, and shared with the bash face — a name-addressed read costs 3 of an account ceiling of 1000 requests/24 h)" "${PY_CMD[@]}" scripts/lib/vault_env.py --self-test
# The ONE batched reader (docs/1password.md §What a gate run costs the vault). QUICK and vault-free:
# fixture route (HL_VAULT_READ_FIXTURE, zero requests) or stubbed routes — the batched SDK arm, the
# labelled op fan-out arm, the no-credential boundary, the TTY refusal, the get_all chunking. The
# account's request bucket is never touched by the profile, which is the whole point of the module.
item_q "lib/vault_read.py --self-test (the ONE reader: both route arms, the get_all chunking, what each mode costs the account, the partial read that never stays silent, the byte-exact ASCII value pipe, the boundary SKIP and both tty refusals — proved at ZERO vault requests)" "${PY_CMD[@]}" scripts/lib/vault_read.py --self-test

# Everything else — cheap, but they add up, so they are in the pool too.
item_q "guard-session.sh --self-test (sandboxed guard fixture, HD-253)" hl_wsl_route bash scripts/gate/guard-session.sh --self-test
item_q "guarded-converge.sh --self-test (post-converge liveness verdict, HD-436)" bash scripts/ansible/guarded-converge.sh --self-test
item_x "drives every 1Password refusal state through a fake op binary in a sandbox: a CLI-contract self-test, not a tree check — rerun it when the bootstrap script changes" "git-bootstrap.sh --self-test (each 1Password refusal state says the right thing)" hl_wsl_route bash scripts/git/git-bootstrap.sh --self-test
# A rotated service-account token has to REACH the seats, and until HD-495 the repo's answer was a pipe
# form the operator types by hand while the superseded generation is still alive. The self-test grades
# the install with a fake op + a stubbed transport: atomic, proven by a vault ANSWER before it swaps,
# value-blind in both modes, never half-installed. Runs on the engine (the modes are real there).
item_q "reseat-vault-token.sh --self-test (HD-495: a rotation lands on the seats by command, is proved by a vault answer, and prints no value)" hl_wsl_route bash scripts/secrets/reseat-vault-token.sh --self-test
# The Windows sibling's contract, proved with a fixture op + a throwaway HOME, so it runs on a Debian
# seat too and a seat that is not present never makes it a SKIP: the raise is fill-in-only, never
# clobbers, always derives the pub, and the route verdict keys on "can a git call WAIT?" rather than on
# the signing key that signing's retirement removed.
item_q "git-bootstrap-win11.sh --self-test (the seat payload is raised safely, and the route verdict cannot confuse a retired key with a broken route)" bash scripts/git/git-bootstrap-win11.sh --self-test
item_x "runs the real check-vault-items.sh over a synthetic tree per case: the *_item registry-key parse is only honest if the CLI runs, which is exactly the waiting a fast loop is not buying" "testdata/check-vault-items/run.sh (scanner self-test, HD-244/245)" hl_wsl_route bash scripts/testdata/check-vault-items/run.sh
item_q "validate_blueprints.py" "${PY_CMD[@]}" scripts/gate/validate_blueprints.py
item_q "check_doc_ips.py" "${PY_CMD[@]}" scripts/gate/check_doc_ips.py
item_q "check_traefik_host_rules.py" "${PY_CMD[@]}" scripts/gate/check_traefik_host_rules.py
item_q "validate-secrets.py" "${PY_CMD[@]}" scripts/gate/validate-secrets.py
item_q "check_doc_map.py" "${PY_CMD[@]}" scripts/gate/check_doc_map.py
# The map above proves a doc is REACHABLE; nothing proved a doc CLAIMS a domain, or that a domain has
# exactly one entry point. HD-1119(b): the domain set is DERIVED from the docs' own frontmatter, so a
# retag moves the rule and this file never has to.
item_q "check_doc_domain.py (every doc claims a domain, every domain has one entry point; the set is derived, never listed)" "${PY_CMD[@]}" scripts/gate/check_doc_domain.py
item_q "check_doc_domain.py --self-test (each rule seen RED on a fixture mutation, the legal fixture GREEN, an empty walk refused)" "${PY_CMD[@]}" scripts/gate/check_doc_domain.py --self-test
item_q "check_generated_suffix.py" "${PY_CMD[@]}" scripts/gate/check_generated_suffix.py
item_q "check_ledger_state.py (ledger = checkboxes, open rows only, ticks dated)" "${PY_CMD[@]}" scripts/gate/check_ledger_state.py
item_q "check_runbook_purity.py (runbook = imperative procedure only)" "${PY_CMD[@]}" scripts/gate/check_runbook_purity.py
item_q "check_runbook_purity.py --self-test (phase-alignment arms seen RED then GREEN; every single-letter phase suffix proved compared; a blind walk or a missing input refused, never OK: 0 phases)" "${PY_CMD[@]}" scripts/gate/check_runbook_purity.py --self-test
item_q "check_vault_docs.py (every IaC-read vault item is documented, and every §Master Secret List row states its field shape rather than a claim about the item)" "${PY_CMD[@]}" scripts/gate/check_vault_docs.py
item_q "check_vault_docs.py --self-test (an item named only in a group_vars *_item: scalar is required; a field= cell that denies its own item reddens; the dash and the pointer stay quiet; an empty walk refused)" "${PY_CMD[@]}" scripts/gate/check_vault_docs.py --self-test
item_q "check_todo_done.py (CONVENTIONS §4(a) done-row sweep)" "${PY_CMD[@]}" scripts/gate/check_todo_done.py
item_q "check_view_registry_sync.py (todo-table.md §B9 holds exactly todo.md's row ids, in both directions — the dispatch view cannot silently lose a row, and cannot invent one)" "${PY_CMD[@]}" scripts/gate/check_view_registry_sync.py
item_q "check_view_registry_sync.py --self-test (a row missing from §B9 must redden AND an id §B9 carries that the registry lacks must redden; the ratchet line whose difference cleared must go STALE)" "${PY_CMD[@]}" scripts/gate/check_view_registry_sync.py --self-test
item_q "check_brief_coverage.py (the row→brief map is ONE map, not three — todo-table.md §B0's cells, every root brief's dispatch header and prompt.md's pointers name the same rows, in every id spelling)" "${PY_CMD[@]}" scripts/gate/check_brief_coverage.py
item_q "check_brief_coverage.py --self-test (one canary per rule plus its reconciled twin; a vanished §B0, an empty §B0, a brief with no dispatch header and a link carried only by cluster shorthand must all be loud)" "${PY_CMD[@]}" scripts/gate/check_brief_coverage.py --self-test
item_q "check_todo_done.py --refs (an HD id named by any root prompt brief must still be a row)" "${PY_CMD[@]}" scripts/gate/check_todo_done.py --refs
item_x "breeds both directions of the marker grammar and the reference rule in a synthetic tree: a checker self-test, not a tree check — and HD-1117 names this leg as a pool flake" "check_todo_done.py --self-test (marker grammar + reference-existence canaries, both directions)" "${PY_CMD[@]}" scripts/gate/check_todo_done.py --self-test
item_q "check_merge_markers.py (HD-453: no conflict markers in tracked files)" "${PY_CMD[@]}" scripts/gate/check_merge_markers.py
item_q "check_merge_markers.py --self-test (HD-453 canary)" "${PY_CMD[@]}" scripts/gate/check_merge_markers.py --self-test
item_q "check_md_tables.py (HD-417 width rule + 2026-10-06 duplicate-key rule)" "${PY_CMD[@]}" scripts/gate/check_md_tables.py
item_q "check_md_tables.py --self-test (HD-417 cell-count canary + duplicate-key canary)" "${PY_CMD[@]}" scripts/gate/check_md_tables.py --self-test
item_q "check_iac_backend_strings.py (HD-404: retired-backend mentions may not regrow)" "${PY_CMD[@]}" scripts/gate/check_iac_backend_strings.py
item_q "check_iac_backend_strings.py --self-test (HD-404 ratchet canary)" "${PY_CMD[@]}" scripts/gate/check_iac_backend_strings.py --self-test
item_q "check_script_layout.py (HD-1118 Stage 4: registry ≡ tree, depth ratchet, one-of-each, clean root)" "${PY_CMD[@]}" scripts/gate/check_script_layout.py
item_q "check_script_layout.py --self-test (HD-1118: each rule seen to fail, corpus floor included)" "${PY_CMD[@]}" scripts/gate/check_script_layout.py --self-test
item_q "check_iac_identifiers.py (no changelog identifier may live in IaC/)" "${PY_CMD[@]}" scripts/gate/check_iac_identifiers.py
item_q "check_iac_identifiers.py --self-test (canary)" "${PY_CMD[@]}" scripts/gate/check_iac_identifiers.py --self-test
# A filtered converge can execute a fraction of a role and still recap `failed=0`: a tag on a playbook
# `roles:` entry cascades into every task of the role, a tag on the `include_tasks` LINE decides only
# whether the FILE loads (its children are then filtered on their own tags), and an untagged dynamic
# include is never expanded by a filtered run at all — `tags: always` children included, because
# `always` can only rescue a task that was parsed. The two items below are the static half: they walk
# the tree, name the include line and the task, and cost half a second. The lab after them asks
# ansible-playbook the same four questions about itself (debug-only legs, the literal `localhost`
# inventory), which is why it is NOT in the quick profile.
item_q "check_tag_coverage.py (a task below a dynamic include must be selectable by some tag)" "${PY_CMD[@]}" scripts/gate/check_tag_coverage.py
item_q "check_tag_coverage.py --self-test (each cascade rule planted in a temp tree; a missing tree exits 2)" "${PY_CMD[@]}" scripts/gate/check_tag_coverage.py --self-test
item_x "every leg executes real ansible-playbook against the literal localhost inventory: it needs ~/ansible-venv, and the static walk above already judges THIS tree — the lab proves the rules the walk reasons with, so buy it when a tag or an include line changes, not per keystroke" "testdata/check_tag_coverage/run.sh (the four cascade rules, asked of ansible itself)" bash scripts/testdata/check_tag_coverage/run.sh
# The child-lane contract (delegation default, ≤2 children, inherit-only model, 2 h deadline) lives in
# four files at once; this is the only thing that keeps those four agreeing. Run + canaries.
item_q "check_subagent_contract.py (the subagent contract agrees across settings SSOT + the three rule docs)" "${PY_CMD[@]}" scripts/gate/check_subagent_contract.py
item_q "check_subagent_contract.py --self-test (each rule bred, plus the silence canaries)" "${PY_CMD[@]}" scripts/gate/check_subagent_contract.py --self-test
# The spark bench's provenance half: it reads a results CSV and touches no host, so a spark-served seat
# runs it safely (it is the check that would have named a Rule 0 violation instead of prose hoping).
# The rc 2 half is NOT JUDGED — no CSV here, a CSV with no `client` column, an unreadable ledger — printed
# as a SKIP and never counted as a pass, because a seat with no bench rows has proved nothing about them.
item_q "check_bench_provenance.py (a timed leg's client stamp must name an allowed runner: Rule 0 + the designated station)" blk_bench_provenance
item_q "check_bench_provenance.py --self-test (each verdict on fixtures, then a mutation of its own parser — including the leg a ledger line must NOT excuse)" "${PY_CMD[@]}" scripts/gate/check_bench_provenance.py --self-test
# corpus_diff.py --gate IS in the pool, and what made that possible is the token anchor on the
# add/drop-line rule. Its verdict is a pure function of the two revisions pinned in
# gate/corpus_baseline.txt, so it reads identically at every commit until the staleness cap trips it
# (~300 commits; a wave measured 176) — and THAT red is the scheduled re-sign announcing itself, not
# a regression. Measured at one tip BEFORE the anchor: 203 REJECTs, 194 of them ordinary development
# that removed no token and 7 that lost one, i.e. a window green only in the commit that signed it.
# A changed line that loses an HD-/KOPS-/date token outside rendered text still owes an exact entry
# of gate/corpus_diff_accepts.txt, and so does every block the window adds or drops: 18 entries now,
# each naming the change that made it, none a standing permission. Re-signing at a wave tip is the
# commit that publishes the six fields:
#   python3 scripts/gate/corpus_diff.py --gate --show-baseline             # the fields to publish
#   git diff --name-only --no-renames <baseline_rev> <compare_rev> -- IaC/ > /tmp/window.txt
#   python3 scripts/gate/corpus_diff.py . <baseline_rev> --list /tmp/window.txt \
#           --against <compare_rev> --accept scripts/gate/corpus_diff_accepts.txt   # rc 0 = audited
# A directory walk is NOT the same population: the pinned run derives its file set from the two
# revisions, and naming `IaC/` as a path argument adds files the window never compared, which enter
# as REJECT "not in base ref" and redden a window that is otherwise clean. The self-test item below
# stays registered too: its arms build their own throwaway repo, baseline and accepts list, so the
# proof that the audit can still fail does not depend on the pinned window's contents.
# stays registered too: its arms build their own throwaway repo, baseline and accepts list, so the
# proof that the audit can still fail does not depend on the pinned window's contents.
# ADVISORY since 2026-10-26 (CONVENTIONS §6.4): a REJECT list from a window that has aged past the
# staleness cap is a re-sign reminder, not a regression, and hundreds of true-but-irrelevant REJECTs on
# ordinary development is exactly how an audit gets muted. So --gate now prints its verdict and exits 0;
# rc 2 (could not measure) still surfaces, because a gate that cannot read its window has no verdict to
# soften. The hard form is `--strict`, and the self-test item below stays a hard item either way.
item_reminder "corpus_diff.py --gate (REMINDER, non-blocking: replays the pinned purge window and prints what the window does not explain — re-signing the baseline at a wave tip is the act that clears it, CONVENTIONS §6.4)" "${PY_CMD[@]}" scripts/gate/corpus_diff.py --gate
item_q "corpus_diff.py --self-test (classifier cases + both halves of the accepts/baseline canary)" "${PY_CMD[@]}" scripts/gate/corpus_diff.py --self-test
# homelab-llm.json is GENERATED: a hand-edit that diverges from the generator is silent otherwise.
# `--check` only compares, it writes nothing — the write-half (adapt-vllm-dashboards.py --inplace) is
# deliberately NOT gated: a suite that mutates the tree is worse than the drift it would catch.
item_q "build-llm-dashboard.py --check (the generated dashboard may not drift from its generator)" "${PY_CMD[@]}" scripts/ansible/build-llm-dashboard.py --check
item_q "check_spark_llm_gate.py (HD-469: spark LLM profile matrix + gate canaries)" "${PY_CMD[@]}" scripts/gate/check_spark_llm_gate.py
item_q "knx-hass-gen.py --self-test (HD-439: emitted addresses must exist in the ETS project)" "${PY_CMD[@]}" scripts/ansible/knx-hass-gen.py --self-test
item_q "laptop-llm.py gate --self-test (HD-474: laptop serving-leg gate must be PROVEN OFFLINE)" "${PY_CMD[@]}" scripts/bench/laptop-llm.py gate --self-test
item_q "laptop-llm.py probe-client (HD-474: client contract may not drift ahead of the engine)" "${PY_CMD[@]}" scripts/bench/laptop-llm.py probe-client
item_q "gate7-read.py --self-test (HD-489 gate-7 bucketing: mixed-pid artifact, bounded fill, leak)" "${PY_CMD[@]}" scripts/bench/spark/gate7-read.py --self-test
# The spark instruments' own verdicts. Each of these seven SHIPPED a --self-test and none of them
# was registered, so the arms ran only when a human remembered them — the defect this registers.
# The criterion for being here is HOST-FREE, not "has a test": a gate item runs on the seat whose
# own model is spark, so an arm that could reach a box is un-registerable at any cost. How each
# one is kept off the box, read out of the files rather than asserted: every far side goes through
# ONE door — `host_read`, whose first branch is `if [ -n "${MW_SSH_CMD:-}" ]` (and the HD469_,
# HD494_, GATE6_, NEEDLE_, PREFLIGHT_ twins; accuracy-gate's HTTP goes through
# ACCURACY_GATE_CURL_CMD and its bearer read is skipped outright under FIXTURE=1) — and each file's
# run_self_test EXPORTS its hook before its first arm re-enters the script. That was then checked,
# not trusted: all seven run with ssh, curl, docker and `op` on PATH replaced by tripwires that log
# and fail → 7× SELF-TEST OK, 0 tripwire lines, ~20 s together; text-only-preflight carries its own
# ssh tripwire arm for the same question.
# NOT registered, and that is a finding rather than an omission: gate 7's `--self-test` needs the
# gpu_top_mib samples of a timed watchdog window, and run-scenario.sh — the only writer of those
# rows — has no fixture hook, so minting them here would mean the timed leg this seat is barred
# from. The READER half is already gated above (check_bench_provenance.py and its --self-test, both
# in the quick profile); what stays unproven is run-scenario.sh's row shape, and it stays unproven
# honestly: no stub can stand in for a row a timed leg is the only thing that writes.
item_q "accuracy-gate.sh --self-test (the un-flagged battery body is byte-identical to the pre-change one, --max-tokens reaches the wire and changes nothing else, a bad budget is refused before any request)" hl_wsl_route bash scripts/bench/spark/accuracy-gate.sh --self-test
item_q "gate6-couple.sh --self-test (Rule 0 refused before anything is read, the pairing guard seen from both sides, no mutate verb on the transport)" hl_wsl_route bash scripts/bench/spark/gate6-couple.sh --self-test
item_q "hd469-baseline.sh --self-test (the KV/capacity verdicts on hand-valued fixtures + every command the driver sends is a read)" hl_wsl_route bash scripts/bench/spark/hd469-baseline.sh --self-test
item_q "usable-sampler.sh --self-test (the MemAvailable−CmaFree verdict on fixtures, the transport path, and no mutate verb)" hl_wsl_route bash scripts/bench/spark/usable-sampler.sh --self-test
item_q "metrics-window.sh --self-test (the /metrics parser, the hit-rate arithmetic, append-not-truncate, and the sampler pid file — including the two-sampler case that must not delete a file it does not own)" hl_wsl_route bash scripts/bench/spark/metrics-window.sh --self-test
item_q "needle-window.sh --self-test (the depth floor with teeth, a FAIL-DEPTH recorded as a result, the run's own commands on fixtures)" hl_wsl_route bash scripts/bench/spark/needle-window.sh --self-test
item_q "text-only-preflight.sh --self-test (the HD-400 pre-flight verdicts on fixtures, with an ssh tripwire that must never have been fired)" hl_wsl_route bash scripts/bench/spark/text-only-preflight.sh --self-test
# Not the query itself — a read tool must never fail a commit — but its offline fixture is a real
# verdict, and it is the witness for the venv-guard predicate render-pi-config.py copies verbatim.
item_q "testdata/rsync-max-delete/run.sh --self-test (--max-delete is a CAP: exactly N/2 deleted + rc 25, asserted as numbers; every weakening reddens a canary)" hl_wsl_route bash scripts/testdata/rsync-max-delete/run.sh --self-test
item_q "testdata/rsync-max-delete/run.sh (the shape-parity arm + the two real rsync fires over N=100 files)" blk_rsync_max_delete
item_q "ansible_query.py --self-test (HD-456 fixtures + the venv re-exec guard both seat planes depend on)" "${PY_CMD[@]}" scripts/ansible/ansible_query.py --self-test
# HD-1199: the doc corpus had no size bound at all — this is the ratchet, cheap enough for the quick
# profile because it reads 75 docs' line counts and nothing else.
item_reminder "check_doc_size.py (REMINDER, non-blocking: the hand-authored docs/**/*.md against a DERIVED soft ceiling — a long doc of facts is a placement question (§8.1), never a red; the per-file seal this used to be measured against is retired, CONVENTIONS §6.4)" "${PY_CMD[@]}" scripts/gate/check_doc_size.py
item_reminder "check_doc_size.py --self-test (the reminder half proved live so this is never a silent cap, the ceiling proved derived rather than sealed, a render view invisible to the walk, the retired baseline proved absent, and a broken root refusing to print a corpus line)" "${PY_CMD[@]}" scripts/gate/check_doc_size.py --self-test
# HD-1200: the other direction of the docs seam — a role directory with no doc is invisible to every
# docs→tree gate. Two reads and a substring scan, so it belongs in quick too.
item_q "check_docs_pure.py (CONVENTIONS §6/§6.4: a doc may cite an HD/KOPS id only while its todo.md row lives — a dangling id reddens and the row's closing change must sweep it; changelog-shaped prose is printed as a reminder and never reddens)" "${PY_CMD[@]}" scripts/gate/check_docs_pure.py
item_q "check_docs_pure.py --self-test (both severities bred: a dangling id reddens, an open row's id passes, a code-font HD-shaped value and an in-row recap stay silent, a live-verified date is state, a dated event sentence warns without reddening, fences and render views are invisible, a missing todo.md and a walk below the corpus floor both refuse at rc 2)" "${PY_CMD[@]}" scripts/gate/check_docs_pure.py --self-test
item_q "check_role_docs.py (HD-1200: every dir under IaC/ansible/roles/ is named by a hand-authored docs/*.md — the role set is derived from the tree, never listed, and naming is decided by shape rather than by the string)" "${PY_CMD[@]}" scripts/gate/check_role_docs.py
item_q "check_role_docs.py --self-test (a role bred and deleted in a temp tree to prove the set is derived, a prose-only role reddening with its sites printed while one code-font mention clears it, a render view unable to document a role, and an empty corpus / missing role tree / doc-less tree all refusing to print OK)" "${PY_CMD[@]}" scripts/gate/check_role_docs.py --self-test

# CONVENTIONS §8.6's `sensitivity:` class had nothing reading it: the shape scanners prove no credential TEXT
# ships, which is not the same fact as what a document is ABOUT — and §8.6's egress rule needs that fact before
# a run decides where its read list may go. The class is declared in frontmatter, so the gate is a frontmatter
# reader plus the owner's floor map, and the payload rule is the one place the family plane can hurt.
item_q "check_doc_sensitivity.py (every hand-authored doc declares one sensitivity class at or above its floor, and the personal docs carry no contact payload — the distribution is derived, never listed)" "${PY_CMD[@]}" scripts/gate/check_doc_sensitivity.py
item_q "check_doc_sensitivity.py --self-test (each rule seen RED on a mutation and the legal tree GREEN: a missing or mis-spelled class, a downgrade below the floor, one canary per payload shape, and the near-misses — a family-subdomain address, a key fingerprint, a grouped byte count — seen quiet)" "${PY_CMD[@]}" scripts/gate/check_doc_sensitivity.py --self-test

# §8.3 made an open question a SECTION so the inventory could be listed; nothing read the shape, so "the table
# is shaped to the grammar" stayed a row's word. This gate is also the only reader of the OQ id space: it prints
# max + the sorted list so the next id is derived at the moment of minting instead of typed from memory.
item_q "check_open_questions.py (every Options section is shaped, keyed by its OQ id, and verdict-free; the id space is derived and printed with the inventory command it mirrors)" "${PY_CMD[@]}" scripts/gate/check_open_questions.py
item_q "check_open_questions.py --self-test (each rule seen RED on a shaped section and quiet on its legal twin: no table, a near-miss header, one row, an empty cheap test, a shifted row, no id, each verdict wording, a typed id above max+1, and both corpus floors at their boundary)" "${PY_CMD[@]}" scripts/gate/check_open_questions.py --self-test

# The state-only rule for the work-tracking surfaces had no checker — the earlier sweep trimmed
# the retrospective prose, and without a gate the next session refills the space. The narrative rules are
# marker-based (a marker grammar is checkable; "is this sentence a story?" is not), and the size half is a
# REMINDER and nothing else — the same place `check_doc_size.py` landed (§6.4): a row or brief that grew
# with owed work may grow, and only the changelog half decides. Cheap (two file reads), so it belongs
# in quick too.
item_q "check_backlog_prose.py (todo.md rows and the prompt-*.md briefs stay state-only — narrative finding counts are sealed and their growth reddens, while row bytes and brief lines only print a REMINDER, because size is the proxy and the changelog is the rule; the grammar targets the verb, not the date, because ISO decision dates stay legal in the queue)" "${PY_CMD[@]}" scripts/gate/check_backlog_prose.py
item_q "check_backlog_prose.py --self-test (all four narrative rules catch their canary while a state date stays legal and are the only thing that reddens, the size half prints WHICH state it is from both surfaces and never reddens, a deleted row and a dead brief are NOTEs and never findings — closing a row must never redden the gate — and a missing/malformed baseline and an empty corpus refuse to print OK)" "${PY_CMD[@]}" scripts/gate/check_backlog_prose.py --self-test

# The rsync `--max-delete` fixture. rc 2 is a BOUNDARY, printed and never counted green: the two
# deletion arms need an rsync binary, which the WSL Debian seat does not carry, while the shape-parity
# arm and every canary run there (the self-test beside this item is what is gated for real).
blk_rsync_max_delete() {
  local rc_md=0
  bash scripts/testdata/rsync-max-delete/run.sh || rc_md=$?
  case "$rc_md" in
    0) return 0 ;;
    2) echo "NOTE: the two rsync arms did not run here (no rsync binary on this host) — the parity arm did,"; echo "      and --self-test beside this item proves both halves of the verdict can still redden."
       return 0 ;;
    *) return "$rc_md" ;;
  esac
}

# --------------------------------------------------------------------------- #
# Drain and report.                                                           #
# --------------------------------------------------------------------------- #
if [ "$LIST" = 1 ]; then
  # The audit is `--list` counted with wc -l, and it prints the FULL set in EVERY profile — that is
  # the point: selecting a profile must never make the registry look smaller than it is. A non-default
  # profile only ADDS a mark column (`*` in quick, `-` excluded with its reason in the NOT PROVEN
  # block, `?` = a decision nobody made), so `--profile quick --list` is the same list, diffed against
  # an earlier commit exactly as CONVENTIONS §2 wants. Plain `--list` keeps its exact historical bytes.
  if [ "$PROFILE" = full ]; then
    for i in "${!labels[@]}"; do printf '%2d  %s\n' "$i" "${labels[$i]}"; done
  else
    echo "profile '$PROFILE' marks (* in quick, - excluded, ? no decision made) — the FULL set, same order as always" >&2
    for i in "${!labels[@]}"; do
      case "${mems[$i]}" in q) _m='*' ;; x) _m='-' ;; *) _m='?' ;; esac
      printf '%2d %s %s\n' "$i" "$_m" "${labels[$i]}"
    done
  fi
  exit 0
fi

# HD-1137: a profile is AUDITED before a single item launches, and the two sets are DERIVED from the
# registry this file just built — never from a list someone typed elsewhere. A full run needs no such
# audit because it runs whatever is registered; its risk is the opposite one (work silently dropped),
# and `_report` counts that against the same registry.
if [ "$PROFILE" = quick ]; then
  _profile_audit
  n_excl_launch=$(( n_items - N_QUICK ))   # derived from the audited counts, not typed
  echo "profile: quick — $N_QUICK of $n_items registered item(s) run; $n_excl_launch excluded, each named with its reason in the NOT PROVEN block. Full set: --list" >&2
fi
_launch_all
wait
_report
