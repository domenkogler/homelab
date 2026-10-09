# ssh/transport-block.ps1 - the Win11 seat's ssh-BUILD block (HD-1128).
#
# This is a TEMPLATE, not a profile. scripts/seat-ssh-build.sh renders it for one seat and writes
# ONE marker-delimited block into the seat's PowerShell profile(s); it is never installed as a
# profile itself. It pairs with ssh/aliases.tmpl: that file decides WHICH HOST each name reaches,
# this one decides WHICH ssh BUILDS IT. A correct config read by the wrong build still fails - the
# measurement is in docs/network-vpn.md, section "The laptop alias contract".
#
# TEMPLATE GRAMMAR - one rule: `@SSH_BIN@` is the only placeholder and it is replaced with the
# pinned build's path by scripts/seat-ssh-build.sh. An unresolved placeholder fails the render.
# The rendered body is ASCII-only on purpose: Windows PowerShell 5.1 reads a BOM-less UTF-8 file as
# cp1252, so one em-dash in a profile is a parse error on half the seats (--self-test arm 9 holds
# that down).
#
# WHY THIS BLOCK EXISTS (measured 2026-10-09, the same seat, the same ~/.ssh/config):
#   Git-Bash /usr/bin/ssh            OpenSSH 10.5p1 / OpenSSL   -> rc 0 on all five legs
#   System32/OpenSSH/ssh.exe         9.5p2 / LibreSSL 3.8.2     -> Load key "...": invalid format
#                                                                        -> Permission denied (publickey)
# The fleet's identity halves are PKCS#8 PEM (the `BEGIN PRIVATE KEY` PEM header), the shape `op read`
# exports, and OpenSSH_for_Windows cannot parse that container. It loads no key, so the failure
# lands on the FIRST hop - the `ProxyJump vps` leg - and reads like a VPS auth problem.
# PATH decides which build a bare `ssh` is, and the machine PATH names C:\WINDOWS\System32\OpenSSH
# while Git's ssh lives in Git\usr\bin, which only Git-Bash adds. So: name the build, never PATH.
#
# WHAT THIS DOES NOT COVER, and says so rather than hiding it: `pwsh -NoProfile`, cmd.exe, and any
# child process that resolves `ssh` off PATH. Those are the operator's shell, not this profile.

# Installed by scripts/seat-ssh-build.sh - do not hand-edit: the block carries a digest line and a
# hand-edit is a REFUSAL, not a silent overwrite. Edit THIS file, then: bash scripts/seat-ssh-build.sh --push
$HomelabSshBin = '@SSH_BIN@'
$env:PI_SSH_BIN = $HomelabSshBin
function global:ssh {
  if (Test-Path -LiteralPath $HomelabSshBin) {
    & $HomelabSshBin @args
  } else {
    Write-Warning ('seat-ssh-build: the pinned ssh build ' + $HomelabSshBin + ' is not there (Git moved or uninstalled?). Falling back to PATH ssh, which on a Windows-native PATH is the System32 build that cannot load the fleet PKCS#8 keys. Fix: bash scripts/seat-ssh-build.sh --push')
    $other = Get-Command ssh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($other) { & $other.Source @args } else { Write-Error 'ssh: no ssh application found on this seat' }
  }
}
