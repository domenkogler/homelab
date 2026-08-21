# prompt-journal — standing handoff: human input → deployment-journal entry

> **Role:** Standing feed file for [`deployment-journal.md`](deployment-journal.md). The human pastes raw
> notes into the **DATA** block below; the AI session converts them into a proper append-only journal entry,
> ticks the plan, closes any gates the step satisfies, validates, commits, and clears this DATA block.
> Never delete this file (unlike task `prompt-hd*.md` handoffs) — it is reused for every deploy action.
> **Linked from:** [deployment-journal.md](deployment-journal.md), [deployment-tasks.md](deployment-tasks.md)

---

## AI instructions (execute top-to-bottom when this file's DATA block is non-empty)

1. Read `deployment-journal.md` **Rules** first — they define entry format, ordering, secret policy.
2. Determine the **Phase + step** from the DATA (Phase numbering = `deployment-tasks.md`). If ambiguous,
   pick the most likely and say so in the commit message rather than blocking.
3. Append a **new `###` entry at the bottom of that phase's section** in `deployment-journal.md`
   (chronological order — never insert above older entries):
   - title `### YYYY-MM-DD — Phase X.Y · <short what>` (today's date; add `[MANUAL]` if human-executed);
   - **commands as run** verbatim in fenced ```bash blocks (clean up shell prompts, keep flags);
   - **settings chosen** as bullet values; **secrets** by `<item>.<field>` name ONLY, never values;
   - **verification evidence**: short output snippets the DATA contains (`zpool status`, `sshd -T`, HTTP codes…);
   - **deviations** from `deployment-tasks.md` / owning docs, each ending with `(doc updated: <file>)` if you
     fixed the doc in this same change (promotion loop — required when the divergence is permanent).
4. Tick the matching checkbox in `deployment-tasks.md` (`- [x]` + date; add `**[MANUAL]**` if missing).
   If the plan step isn't checkbox-formatted yet, convert that step to `- [x]` form while ticking.
5. If the step closes a deploy-gated item: trim/update the todo.md `⏳` tail and the owning-doc status
   block (🔴→🟢→✅) in the same change.
6. Run `bash scripts/validate-all.sh` — must end green.
7. Commit everything as one change: `journal: Phase X.Y · <slug>` (+ co-updated files listed).
8. **Clear the DATA block** back to the empty placeholder below, then commit that reset separately
   (`journal-feed: data consumed`) — git history preserves the raw input via the journal entry itself.

If the DATA is too vague to journal safely: make the best-effort entry, mark unknowns `⚠ not captured`,
and list your open questions at the top of the commit message for the human to answer in the next feed.

---

## DATA (human fills — raw notes, pasted outputs, half-sentences; any format goes)

ansible-admin@vps:~$ cat /etc/os-release | head -2; uname -r
PRETTY_NAME="Debian GNU/Linux 13 (trixie)"
NAME="Debian GNU/Linux"
6.12.101+deb13-amd64
ansible-admin@vps:~$ lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT; df -h /
NAME     SIZE TYPE FSTYPE MOUNTPOINT
sr0     1024M rom
vda      512G disk
├─vda1   243M part vfat   /boot/efi
├─vda2   977M part ext4   /boot
└─vda3 510.8G part ext4   /
Filesystem      Size  Used Avail Use% Mounted on
/dev/vda3       503G  1.8G  481G   1% /
ansible-admin@vps:~$ id; cut -d: -f1 /etc/passwd | grep -E 'admin|ansible|domen'
   ls -la /root/.ssh/ 2>/dev/null; cat /root/.ssh/authorized_keys 2>/dev/null | wc -l
   grep -rn "PasswordAuthentication\|PermitRootLogin\|MaxAuthTries" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null
   systemctl is-active ssh; ss -tlnp | grep :22
uid=1000(ansible-admin) gid=1000(ansible-admin) groups=1000(ansible-admin)
ansible-admin
0
/etc/ssh/sshd_config:34:#MaxAuthTries 6
/etc/ssh/sshd_config:56:#PasswordAuthentication yes
/etc/ssh/sshd_config:80:# PasswordAuthentication.  Depending on your PAM configuration,
/etc/ssh/sshd_config:83:# PAM authentication, then enable this but set PasswordAuthentication
/etc/ssh/sshd_config:124:PasswordAuthentication yes
/etc/ssh/sshd_config:125:PermitRootLogin yes
/etc/ssh/sshd_config:128:PasswordAuthentication no
/etc/ssh/sshd_config:129:PermitRootLogin no
active
LISTEN 0      128          0.0.0.0:22        0.0.0.0:*
LISTEN 0      128             [::]:22           [::]:*
ansible-admin@vps:~$ for k in /etc/ssh/ssh_host_*_key.pub; do ssh-keygen -lf $k; done
256 SHA256:aPEyZBN0xmIMhqV2SsWSy0OANMRdbmIOYYcYWtgejzI root@vps (ECDSA)
256 SHA256:DfRE+i6EiZUYD2Bot2hanIh+Ey47tTpzv352boxB3fY root@vps (ED25519)
3072 SHA256:LpwYdCSTDcIZ0fvGUj8mRFJOgLXabbMYU+7VTr+tWIE root@vps (RSA)
ansible-admin@vps:~$ dpkg -l 2>/dev/null | grep -cE "docker|fail2ban"; nft list ruleset 2>/dev/null | head -5; free -h; ip -br addr
0
               total        used        free      shared  buff/cache   available
Mem:            15Gi       405Mi        14Gi       512Ki       670Mi        15Gi
Swap:             0B          0B          0B
lo               UNKNOWN        127.0.0.1/8 ::1/128
eth0             UP             159.195.111.66/22 2a0a:4cc0:60:fcc:d820:9dff:fe4f:95f5/64 fe80::d820:9dff:fe4f:95f5/64
ansible-admin@vps:~$ cat /etc/debian_version; lsblk; df -h /
   for k in /etc/ssh/ssh_host_*_key.pub; do ssh-keygen -lf $k; done
   sudo sshd -T | grep -E 'passwordauthentication|permitrootlogin|maxauthtries'
13.6
NAME   MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
sr0     11:0    1  1024M  1 rom
vda    254:0    0   512G  0 disk
├─vda1 254:1    0   243M  0 part /boot/efi
├─vda2 254:2    0   977M  0 part /boot
└─vda3 254:3    0 510.8G  0 part /
Filesystem      Size  Used Avail Use% Mounted on
/dev/vda3       503G  1.8G  481G   1% /
256 SHA256:aPEyZBN0xmIMhqV2SsWSy0OANMRdbmIOYYcYWtgejzI root@vps (ECDSA)
256 SHA256:DfRE+i6EiZUYD2Bot2hanIh+Ey47tTpzv352boxB3fY root@vps (ED25519)
3072 SHA256:LpwYdCSTDcIZ0fvGUj8mRFJOgLXabbMYU+7VTr+tWIE root@vps (RSA)
maxauthtries 6
permitrootlogin yes
passwordauthentication yes
ansible-admin@vps:~$


*(empty — paste deploy info above this line)*

<!-- Fill between the markers, then tell the AI session: "read prompt-journal.md".
     Useful things to dump: what you did, terminal output, panel settings, dates,
     what broke, what you decided differently than the docs say. Secrets: names only! -->

<!-- end of data -->

