# prompt.md — Deployment Execution Handoff (successor of the 2026-08-21 remediation orchestrator)

> **Role:** Entry point for the **deployment execution** phase of the Kogler Homelab. The previous
> session (2026-08-21) completed the entire audit-remediation program (HD-181…208 + waves) and set up
> the deployment documentation system. This session **executes Phase 0/1**: VPS reinstall with the
> hardened bootstrap script, runner rebuild, then `vps.yml`.
> **Linked from:** [README.md](README.md) §2 · plan: [deployment-tasks.md](deployment-tasks.md) ·
> as-built log: [deployment-journal.md](deployment-journal.md) · human feed: [prompt-journal.md](prompt-journal.md)

---

## 0. Mandatory context (read in this order)

1. `README.md` §1 chain → `CONVENTIONS.md` (esp. **§4 Deployment ledger & journal** + Post-task housekeeping)
2. **`deployment-tasks.md`** — THE build plan (Phase 0→10, verify blocks, deploy-gated checklists)
3. **`deployment-journal.md`** — as-built record (append-only; Rules at top; entries via the feed file)
4. `todo.md` ⏳ rows (what closes when) + `changelog.md` HD-178…208 (recent decisions — never re-open)
5. Owning docs per step: `docs/services-vps.md`, `docs/deployment-preseed.md` (§netcup Custom-Script flow),
   `docs/1password.md`, `docs/deployment-secrets.md`

## 1. Environment (Windows 11 host)

- Repo ops + validators: **git-bash**, forward-slash paths, `py -3`, UTF-8 no-BOM, LF.
- Ansible runner: **WSL Debian** (`wsl -d Debian` — LOWERCASE `-d`). Quirks learned the hard way:
  git-bash mangles `wsl.exe` inline args → write a script to `%TEMP%`, run
  `cmd //c "wsl -d Debian -- bash /mnt/c/.../script.sh"`, strip `\0` from output.
- In WSL, ansible + `op` only work with the **interactive env**: use `bash -ic` or `source ~/.bashrc`;
  load the token via `source ~/.config/op/homelab-sa-token` (it contains an `export` line — NEVER `cat` it).
- `bash scripts/validate-all.sh` (git-bash) must end green before every commit; ansible `--syntax-check`
  auto-skips on Windows (WSL/CI-gated).

## 2. State snapshot (2026-08-21, main `94d7eb0`+)

- **All remediation closed:** HD-181…208 (gates/supply-chain, VPS edge/security, home hosts, docs waves,
  audit reports folded+deleted). Gates green. Branches cleaned. See `changelog.md` for each.
- **Deployment system live:** ledger = checkboxes in deployment-tasks; journal = deployment-journal.md;
  human feeds raw notes into `prompt-journal.md` DATA → AI converts (entry + tick plan + close gates +
  validate + commit + clear feed).
- **Secrets:** Table A of deployment-tasks §0 verified against the vault (5 `✗` items are LATER-phase:
  authentik_login, forgejo_api, ha_api, headscale_api, signal_api). Table B = human `Homelab (human)` vault
  (SA-invisible by design; linter exempts that exact spelling). `litellm_master_key` still unprovisioned.
- **HD-208 fixed:** both `post_install.sh` variants now write an `/etc/ssh/sshd_config.d/00-homelab-hardening.conf`
  drop-in (append-style lost to netcup's image defaults — see journal Phase 1.0).

## 3. Execution order (this session)

1. **Key continuity check** (before any wipe): compare WSL `~/.ssh/id_ed25519.pub` fingerprint vs
   `op read "op://Homelab-ansible/ansible-admin_ssh/public_key"`. If different → after rebuild, restore the
   canonical private key from the item into `~/.ssh/id_ed25519` (1P = source of truth).
2. **VPS reinstall** (box is empty, safe): build `IaC/host/vps/post_install_with_secrets.sh`
   (copy `IaC/host/vps/post_install.sh`, fill its two 1Password key placeholders with the real
   pubkeys from `laptop-domen_ssh` + `ansible-admin_ssh` per the script's own SECURITY NOTE,
   paste into netcup SCP Custom Script, DELETE the file). Field choices table:
   `docs/deployment-preseed.md` §netcup.
3. **Verify first boot** (expect no/no/3 from the drop-in alone):
   `ssh ansible-admin@vps.kogler.si` → `sudo sshd -T | grep -E 'passwordauthentication|permitrootlogin|maxauthtries'`
4. **Runner rebuild** (owner wants Phase 0 documented from true zero): `wsl --unregister Debian` →
   `wsl --install -d Debian` → clone repo → `IaC/bootstrap-ansible-client/bootstrap.sh` → `source ~/.bashrc` →
   `ansible-playbook -i IaC/ansible/inventory.ini IaC/ansible/test-1password.yml`.
5. **Phase 1 main run:** `ansible-playbook -i inventory.ini playbooks/vps.yml` (hardening → docker →
   docker_services → monitoring) → Phase 1 **Verify** + **Deploy-gated verification** blocks.
6. **Journal everything** through `prompt-journal.md` (one feed per milestone); tick checkboxes; flip
   ⏳ tails / status blocks the steps close; HD-40A/135/149 verification rows land in the journal.

## 4. Working rules (unchanged, binding)

- Validate green → commit; journal append-only; corrections = new entries.
- Secrets: 1Password item+field names only in docs/journal — never values; keys never in Git.
- Decisions made during deploy → owning doc + changelog row in the same change.
- No cosmetic edits; English technical prose; relative links.
- If a step diverges from the docs permanently → fix the owning doc in the same change, note
  `doc updated: <file>` in the journal entry.
