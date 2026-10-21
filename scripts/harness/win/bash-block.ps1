# Installed by scripts/harness/seat-bash-build.sh - do not hand-edit: this block carries a digest
# line and a hand-edit is a REFUSAL, not a silent overwrite. Edit the template
# (scripts/harness/win/bash-block.ps1), then:  bash scripts/harness/seat-bash-build.sh --push
#
# WHY: on this seat a bare `bash` is C:\WINDOWS\system32\bash.exe - the WSL launcher - because the
# Windows PATH names C:\WINDOWS\system32 and only Git\cmd, and Git's bash sits in Git\bin, which no
# PATH entry adds. The repo writes its harness commands as `bash scripts/...`, so that is the binary
# an operator gets from PowerShell. WSL keeps the Windows working directory (D:\x arrives as
# /mnt/d/x), so the repo is found, and brings its OWN $HOME and its OWN node: the harness then reads
# the right repo and the wrong seat, which is how a settings-plane check on a Windows box named a
# /home/user file and called an unread file "not parseable JSON". PATH decides which bash a bare
# name is, and PATH is the accident; so the block names the build instead.
#
# WHAT IT DOES NOT TOUCH: PATH (that would change which bash every other program on the box gets),
# the WSL distro list, or any other shell. cmd.exe is not covered and says so in docs.
$env:PI_BASH_BIN = '@BASH_BIN@'
function global:bash {
  if (Test-Path -LiteralPath $env:PI_BASH_BIN) {
    & $env:PI_BASH_BIN @args
  } else {
    Write-Warning ('seat-bash-build: the pinned bash build ' + $env:PI_BASH_BIN + ' is not there (Git moved or uninstalled?). Falling back to PATH bash - on a Windows-native PATH that is the WSL launcher, which runs this repo inside a Linux distro with a different HOME and a different node. Fix: bash scripts/harness/seat-bash-build.sh --push')
    $other = Get-Command bash -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($other) { & $other.Source @args } else { Write-Error 'bash: no bash application found on this seat' }
  }
}
