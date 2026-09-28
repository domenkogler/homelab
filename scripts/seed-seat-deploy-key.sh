#!/usr/bin/env bash
# =====================================================================
# seed-seat-deploy-key.sh — HD-449(a): give the oldsrv SEAT clone (`domen`) its own
# write-capable GitHub credential, and PROVE it, without ever touching the runner clone.
#
# "Push by seat, pull by runner" (owner decision 2026-09-25, docs/deployment-ansible.md
# §Runner placement): `/home/ansible-admin/source/homelab` converges and pulls read-only
# HTTPS with `github-homelab-deploy_api`; `/home/domen/source/homelab` is authored and
# pushes with the repo-scoped SSH deploy key held in 1Password `GitHub-homelab-deploy_ssh`.
# Two git paths on one box is the decision, so this script installs under `domen` ONLY and
# asserts at the end that the runner's remote and `~ansible-admin/.ssh` are untouched.
#
# The GitHub remote is **PUBLIC** (measured 2026-09-28: api.github.com returns `private: false`),
# so reading it needs no credential. That is why `--check` can clone before the key works, and
# why the read-only token below is about scope + a non-interactive identity, not secrecy.
#
# Run ON the seat host as root (it needs to write into another account's home):
#     ssh oldsrv 'sudo bash -s' -- --check < scripts/seed-seat-deploy-key.sh
#     ssh oldsrv 'sudo bash -s'           < scripts/seed-seat-deploy-key.sh
# Needs only the read-scope SA token file (/etc/op/provision-token, HD-442), so it works on
# a headless runner. Modes: `--check` = report without writing anything; `--force` = rewrite
# a key/config this script already wrote. Idempotent: an existing matching key is a no-op.
#
# ⛔ Never prints a private half — lengths, fingerprints and booleans only (CONVENTIONS §6).
# Expected fingerprint: SHA256:dGe193grwS3d74i7I8YsOv4E6gewyin6aENEfFAgLeY — a mismatch means
# the vault rotated, so re-read the item rather than shipping a key GitHub will not accept.
#
# Two measured traps this script exists to dodge:
#  1. `op item get --fields <SSHKEY field>` returns a PRETTY-WRAPPED PEM that ssh-keygen
#     cannot load ("error in libcrypto"). `op read op://…/<field>` returns the real value.
#  2. `IdentitiesOnly yes` is not decoration: without it ssh offers every identity it can
#     find (including the vault-canonical ansible-admin key) and GitHub's first-match policy
#     attributes a seat push to the wrong credential.
# Exit codes: 0 = write path proven; 3 = key installed but GitHub refused it (the deploy key
# is not registered on the repo — an owner browser act); 1 = anything else.
# =====================================================================
set -uo pipefail

ITEM='GitHub-homelab-deploy_ssh'
VAULT='Homelab-ansible'
EXPECT_FP='SHA256:dGe193grwS3d74i7I8YsOv4E6gewyin6aENEfFAgLeY'
KEYNAME=github-homelab-deploy_ed25519
SEAT=domen
DHOME=/home/domen
SSHDIR=$DHOME/.ssh
SRC=$DHOME/source
REPO=$SRC/homelab
REMOTE='git@github.com:domenkogler/homelab.git'
MARK='hd449-seat-git: github deploy key'
CHECK=0; FORCE=0
for a in "$@"; do case "$a" in
  --check) CHECK=1 ;; --force) FORCE=1 ;;
  *) echo "unknown argument: $a (known: --check, --force)" >&2; exit 2 ;;
esac; done

[ "$(id -u)" = 0 ] || { echo "run it as root on the target host:  ssh <host> 'sudo bash -s' < scripts/seed-seat-deploy-key.sh" >&2; exit 1; }
[ -d "$DHOME" ] || { echo "FATAL no $DHOME — the seat account does not exist" >&2; exit 1; }
[ -r /etc/op/provision-token ] || { echo "FATAL /etc/op/provision-token missing (HD-442)" >&2; exit 1; }
export OP_SERVICE_ACCOUNT_TOKEN="$(cat /etc/op/provision-token)"
TMP=$(mktemp -d /dev/shm/seatkey.XXXXXX); trap 'rm -rf "$TMP"' EXIT
umask 077

say() { printf '%s\n' "$*"; }
[ "$CHECK" = 1 ] && say "== --check: reporting only, writing nothing"

# ── 1. the keypair out of the vault, verified before it lands anywhere ────────────────────
op read "op://$VAULT/$ITEM/private_key" > "$TMP/pk"  2>"$TMP/err" || true
op read "op://$VAULT/$ITEM/public_key"  > "$TMP/pub" 2>/dev/null || true
op read "op://$VAULT/$ITEM/fingerprint" > "$TMP/fp"  2>/dev/null || true
[ -s "$TMP/pk" ] || { say "FATAL vault read failed: $(tail -2 "$TMP/err" | tr '\n' ' ')"; exit 1; }
say "private field: bytes=$(wc -c < "$TMP/pk") first-line=$(head -1 "$TMP/pk")"
ssh-keygen -yf "$TMP/pk" > "$TMP/derived.pub" 2>"$TMP/kg" || { say "FATAL cannot derive pub: $(tail -1 "$TMP/kg")"; exit 1; }
FP=$(ssh-keygen -lf "$TMP/derived.pub" | awk '{print $2}')
FP_ITEM=$(tr -d ' \n' < "$TMP/fp")
FP_PUBITEM=$(ssh-keygen -lf "$TMP/pub" 2>/dev/null | awk '{print $2}')
say "fingerprint: derived=$FP item=$FP_ITEM"
[ "$FP" = "$FP_ITEM" ]     || { say "FATAL derived pair does not match the item fingerprint"; exit 1; }
[ "$FP" = "$FP_PUBITEM" ]  || { say "FATAL derived public half differs from the item public_key field"; exit 1; }
[ "$FP" = "$EXPECT_FP" ]   || say "⚠ fingerprint differs from the one recorded here — the vault may have rotated; verify before trusting it"
say "pair consistent and matches the item (public_key + fingerprint fields)"

# ── 2. install under the seat account only ────────────────────────────────────────────────
if [ -f "$SSHDIR/$KEYNAME" ]; then
  FP_OLD=$(ssh-keygen -lf "$SSHDIR/$KEYNAME.pub" 2>/dev/null | awk '{print $2}')
  if [ "$FP_OLD" = "$FP" ] && [ "$FORCE" != 1 ]; then
    say "key already installed ($KEYNAME, $FP) — nothing to write (use --force to rewrite)"
  elif [ "$FP_OLD" = "$FP" ]; then
    say "--force: rewriting the identical key"
  else
    say "FATAL $SSHDIR/$KEYNAME holds a DIFFERENT key ($FP_OLD). Identify it before replacing it — this script does not overwrite keys it cannot name."
    exit 1
  fi
else
  [ "$CHECK" = 1 ] && say "--check: would install $SSHDIR/$KEYNAME ($FP)" || say "installing $SSHDIR/$KEYNAME"
fi
if [ "$CHECK" != 1 ]; then
  install -d -m 700 -o "$SEAT" -g "$SEAT" "$SSHDIR" "$SRC"
  install -m 600 -o "$SEAT" -g "$SEAT" "$TMP/pk"       "$SSHDIR/$KEYNAME"
  install -m 644 -o "$SEAT" -g "$SEAT" "$TMP/derived.pub" "$SSHDIR/$KEYNAME.pub"
  # marker-delimited block, same discipline as seed-runner-ssh.sh: never rewrite a config
  # this script did not write, replace its own block in place.
  BLOCK=$(printf '# >>> %s >>>\nHost github.com\n  HostName github.com\n  User git\n  IdentityFile ~/.ssh/%s\n  IdentitiesOnly yes\n# <<< %s <<<\n' "$MARK" "$KEYNAME" "$MARK")
  touch "$SSHDIR/config"; chown "$SEAT:$SEAT" "$SSHDIR/config"; chmod 600 "$SSHDIR/config"
  if grep -qF ">>> $MARK >>>" "$SSHDIR/config"; then
    python3 - "$SSHDIR/config" "$MARK" "$BLOCK" <<'PY'
import sys
path, mark, block = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path).read().splitlines(True)
out, inside = [], False
for l in lines:
    if f">>> {mark} >>>" in l: inside = True; continue
    if f"<<< {mark} <<<" in l: inside = False; continue
    if not inside: out.append(l)
open(path, 'w').write(''.join(out) + block)
PY
    say "ssh config: this script's github block replaced in place"
  else
    printf '%s' "$BLOCK" >> "$SSHDIR/config"
    say "ssh config: github block appended"
  fi
fi

# ── 3. github.com's host key, PINNED, not TOFU'd ─────────────────────────────────────────
# GitHub publishes the keys at api.github.com/meta and the fingerprints at docs.github.com;
# take the keys from the API and assert them against the published fingerprints, so a
# silently different key on the wire cannot be trusted into known_hosts.
curl -s -m 25 -o "$TMP/meta.json" https://api.github.com/meta
python3 - "$TMP/meta.json" "$TMP/known_hosts" <<'PY'
import json, sys, hashlib, base64
keys = json.load(open(sys.argv[1])).get('ssh_keys', [])
published = {
  'SHA256:uNiVztksCsDhcc0u9e8BujQXVUpKZIDTMczCvj3tD2s': 'ssh-rsa',
  'SHA256:p2QAMXNIC1TJYWeIOttrVc98/R1BUFWu3/LiyKgUfQM': 'ecdsa-sha2-nistp256',
  'SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU': 'ssh-ed25519',
}
out = []
for k in keys:
    alg, b64 = k.split(' ', 1)
    if alg not in published.values():
        continue
    dig = 'SHA256:' + base64.b64encode(hashlib.sha256(base64.b64decode(b64)).digest()).decode().rstrip('=')
    ok = published.get(dig) == alg
    print(f"  meta key {alg:22s} {dig} matches-docs={ok}")
    if ok:
        out.append(f"github.com {k}")
assert out, 'no github host key verified against the published fingerprints'
open(sys.argv[2], 'w').write('\n'.join(out) + '\n')
PY
if [ "$CHECK" != 1 ]; then
  touch "$SSHDIR/known_hosts"; chown "$SEAT:$SEAT" "$SSHDIR/known_hosts"; chmod 600 "$SSHDIR/known_hosts"
  ADDED=0
  while read -r line; do
    grep -qxF "$line" "$SSHDIR/known_hosts" || { printf '%s\n' "$line" >> "$SSHDIR/known_hosts"; ADDED=$((ADDED+1)); }
  done < "$TMP/known_hosts"
  say "known_hosts: $ADDED github host key(s) added, $(wc -l < "$SSHDIR/known_hosts") lines total"
fi

# cross-check what the wire actually presents against the pin (`# ...` probe lines skipped —
# keyscan prints them and they would match everything, which is a test that cannot fail)
say "wire agrees with the pin:"
ssh-keyscan -t ed25519,rsa,ecdsa github.com 2>/dev/null | grep -v '^#' | while read -r _ alg rest; do
  fp=$(printf '%s %s\n' "$alg" "$rest" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
  if [ -n "$fp" ] && grep -qF "$rest" "$SSHDIR/known_hosts"; then say "   $fp pinned"
  else say "   ${fp:-<unparsable>} NOT PINED — the wire differs from api.github.com/meta"; fi
done

# ── 4. prove the credential, then (only if proven) create the seat clone ──────────────────
# ⚠ `-n` + `</dev/null` are load-bearing, not style: this script is fed to `bash -s` over ssh,
# so ssh's stdin IS the rest of this script. A bare `ssh -T` swallows everything after it and the
# run silently ends at the last executed line with THAT status — which reads as the thing under
# test failing. Measured the hard way here: with the deploy key ACCEPTED, the run stopped after
# the host-key loop and exited 1 without ever reaching the dry-run. Same trap, opposite symptom.
probe=$(sudo -u "$SEAT" -H env SSH_AUTH_SOCK= GIT_SSH_COMMAND="ssh -o BatchMode=yes -o IdentityAgent=none" \
        ssh -n -T git@github.com </dev/null 2>&1 | head -2)
say "auth probe: $probe"
case "$probe" in
  *"successfully authenticated"*) say "GitHub accepts this deploy key" ;;
  *"Permission denied (publickey)"*)
    say "⛔ GitHub does not know this key. The public half is not registered as a deploy key on"
    say "   domenkogler/homelab — an owner browser act, from the vault item itself:"
    say "   op read op://$VAULT/$ITEM/public_key   →   https://github.com/domenkogler/homelab/settings/keys/new"
    say "   ⚠ 'Allow write access' MUST be ticked, or the seat clones and cannot push."
    say "   Nothing else here needs redoing: key, ssh config and host pin are already in place."
    # The remote is PUBLIC (measured 2026-09-28: api.github.com returns private:false), so a READ
    # needs no credential at all: materialise the tree over anonymous HTTPS, then point origin at
    # the ruled SSH remote so the seat exists for authoring and the retry after the owner act is
    # just this script again. Every sync then fails CLOSED at the key — that is the point.
    if [ "$CHECK" != 1 ] && [ ! -d "$REPO/.git" ]; then
      sudo -u "$SEAT" -H env GIT_TERMINAL_PROMPT=0 git clone --quiet "https://github.com/domenkogler/homelab.git" "$REPO" \
        && say "seat clone materialised anonymously (public read — no credential planted)"
      sudo -u "$SEAT" -H git -C "$REPO" remote set-url origin "$REMOTE"
      say "  origin = $(sudo -u "$SEAT" -H git -C "$REPO" remote get-url origin)  (the ruled shape)"
      say "  ⚠ it cannot fetch or push until the key is registered; nothing here degrades to HTTPS silently,"
      say "    because origin is SSH for BOTH directions — no pushurl split, no second git path."
    fi
    exit 3 ;;
  *) say "⛔ unexpected auth result — not continuing"; exit 1 ;;
esac

if [ "$CHECK" = 1 ]; then say "--check: stopping before the clone"; exit 0; fi
if [ ! -d "$REPO/.git" ]; then
  sudo -u "$SEAT" -H env SSH_AUTH_SOCK= git clone --quiet "$REMOTE" "$REPO" && say "seat clone created over the deploy key" || { say "CLONE FAILED"; exit 1; }
else
  say "seat clone already present"
  sudo -u "$SEAT" -H env SSH_AUTH_SOCK= git -C "$REPO" fetch --quiet origin </dev/null && say "  fetch over the deploy key: ok" || say "  FETCH FAILED over the deploy key"
fi
say "  remote: $(sudo -u "$SEAT" -H git -C "$REPO" remote get-url origin)"
say "  HEAD:   $(sudo -u "$SEAT" -H git -C "$REPO" rev-parse --short HEAD) $(sudo -u "$SEAT" -H git -C "$REPO" rev-parse --abbrev-ref HEAD)"

# ACCEPTANCE (owner ruling 2026-09-25): a push --dry-run, never the key's existence.
# It IS a discriminating test: --dry-run still requests git-receive-pack, which GitHub
# authorizes BEFORE any transfer. Negative control, same host, same day: the read-only HTTPS
# deploy token on the runner clone gets `403 Permission to domenkogler/homelab.git denied`
# from the identical --dry-run command — so a rc 0 here means the write grant is real.
sudo -u "$SEAT" -H env SSH_AUTH_SOCK= git -C "$REPO" push --dry-run origin HEAD:refs/heads/hd449-write-probe </dev/null > "$TMP/dry" 2>&1
RC=$?
sed 's/^/   | /' "$TMP/dry"
say "push --dry-run rc=$RC $([ "$RC" = 0 ] && echo '→ WRITE PATH PROVEN (nothing was written: dry-run)' || echo '→ NOT PROVEN')"

# ── 5. the decision stays intact: the runner clone never sees this key ────────────────────
say "runner clone untouched:"
say "   remote: $(sudo -u ansible-admin -H git -C /home/ansible-admin/source/homelab remote get-url origin 2>/dev/null || echo '(no runner clone here)')"
say "   ansible-admin .ssh deploy keys: $(ls /home/ansible-admin/.ssh 2>/dev/null | grep -c 'deploy' ) (must be 0)"
exit "$RC"
