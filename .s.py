import io
def rw(p, pairs, label):
    s = io.open(p, encoding='utf-8', newline='').read()
    for a, b in pairs:
        if a not in s: raise SystemExit('ANCHOR MISSING in %s: %s' % (p, a[:70]))
        s = s.replace(a, b, 1)
    io.open(p, 'w', encoding='utf-8', newline='').write(s)
    print('ok', label)

rw('CONVENTIONS.md', [(
 "- **Commit signing (HD-265/270/495):** every commit is signed (`commit.gpgsign=true`, `gpg.format=ssh`).",
 "- **Commit signing (HD-265/270/495, RETIRED by owner decision 2026-10-08, HD-1116):** commits are **not** signed \u2014 `commit.gpgsign=false`. The rule above held while the SSH signing key was registered on GitHub; the owner deleted it, so signing became a hang (git waits on an agent for a key that can no longer be validated) dressed as a policy. The mechanism documented in HD-265/270/495 stays valid as history and in [docs/deployment-secrets.md](docs/deployment-secrets.md): it is how a rebuild used to recover signing, and it is what must change if the owner ever re-registers a key.")], 'CONVENTIONS')

rw('scripts/git/gitconfig-nightly', [
 ("[commit]\n\tgpgsign = true\n[tag]\n\tgpgsign = true",
  "# Commit signing is RETIRED by owner decision 2026-10-08 (HD-1116): the SSH signing key is no\n"
  "# longer registered on GitHub, so gpgsign=true does not produce a signature, it produces a\n"
  "# HANG \u2014 git blocks on an agent that cannot validate a key the remote deleted. This file is\n"
  "# the seat default, so leaving it true meant a rebuild silently restored a broken policy\n"
  "# (HD-495's mechanism, now pointing the other way). The key FILE entries above stay for\n"
  "# reference; to bring signing back, register a key, then flip both values to true.\n[commit]\n\tgpgsign = false\n[tag]\n\tgpgsign = false")],
 'gitconfig-nightly')

rw('scripts/git-bootstrap.sh', [
 ("    git config gpg.format ssh\n    git config commit.gpgsign true",
  "    git config gpg.format ssh\n    # Commit signing RETIRED 2026-10-08 (HD-1116, owner decision): the key is gone from GitHub,\n"
  "    # so signing would hang the next non-interactive committer (cron, a converge, pi's bash).\n"
  "    # The key files and the form choice above are kept: if a key is ever re-registered, this\n"
  "    # line is the one thing that flips back.\n"
  "    git config commit.gpgsign false")], 'git-bootstrap.sh')

rw('deployment-manual.md', [
 ("bash scripts/git-bootstrap.sh --ssh-auth                # idempotent; pulls both keys, ssh-adds them,\n                                                        # sets gpg.format=ssh + gpgsign=true +",
  "bash scripts/git-bootstrap.sh --ssh-auth                # idempotent; pulls both keys, ssh-adds them,\n                                                        # sets gpg.format=ssh + gpgsign=false (commit signing retired \u2014\n                                                        # [docs/deployment-secrets.md](docs/deployment-secrets.md)) +")],
 'deployment-manual')

rw('scripts/README.md', [
 ("sets `gpg.format=ssh`/`gpgsign=true`/`allowedSignersFile`",
  "sets `gpg.format=ssh`/`gpgsign=false`/`allowedSignersFile` \u2014 **signing is retired by owner decision (HD-1116)**: the SSH key is no longer registered on GitHub, so `gpgsign=true` would hang the next non-interactive committer instead of signing anything")],
 'scripts/README')

rw('docs/deployment-secrets.md', [
 ("* **The repo's own `.git/config` outranks every global file**",
  "* **Retired 2026-10-08 (owner decision, HD-1116): commits are no longer signed.** The SSH signing key\n"
  "  was deleted from GitHub, which turns `commit.gpgsign=true` from a policy into a HANG \u2014 git blocks\n"
  "  waiting for an agent to sign with a key nothing can validate any more, and it does that in the\n"
  "  shells nobody watches (cron, a converge, pi's bash). Applied on this host in `~/.gitconfig-github`\n"
  "  and `~/.gitconfig-nightly` (`gpgsign=false` in `[commit]` and `[tag]`), and in the two places that\n"
  "  would otherwise restore it on a rebuild: `scripts/git-bootstrap.sh --ssh-auth` and the repo template\n"
  "  `scripts/git/gitconfig-nightly`. Everything else on this page stays true as the record of HOW\n"
  "  signing worked and what to change if a key is ever registered again.\n"
  "* **The repo's own `.git/config` outranks every global file**")],
 'deployment-secrets')

