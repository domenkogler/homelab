# Office MCP Bridge — distribution / update script (HD-106)
#
# Client-side endpoint software is OUTSIDE the Ansible/GitOps server model. This repo
# folder `client/office-bridge/` is the SSOT package; it is served read-only over the
# Headscale tunnel (e.g. from oldsrv) and pushed to Windows 11 clients.
#
# install.ps1 (Windows 11):
#   1. pulls this folder (the pinned requirements + scripts)
#   2. installs pinned deps into a local venv (uv/pip)
#   3. downloads the pinned sbroenne excelcli.exe (MIT release) + verifies checksum
#   4. wires bridge.env (token from 1Password), registers a scheduled self-update
#
# update.ps1 runs on a schedule: fetches the repo folder head over Headscale, diffs the
# pinned version markers, re-installs if changed (version pinning / Flaw-B).
param(
  [string]$SourceUrl = "https://oldsrv.kogler.si/client/office-bridge",  # Headscale-only static
  [string]$Dest = "$env:ProgramFiles\OfficeMcp"
)

$ErrorActionPreference = "Stop"
Write-Host "Office MCP Bridge installer -> $Dest"

# 1. pull package
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
Write-Host "Fetching package from Headscale static: $SourceUrl"
Invoke-WebRequest -Uri "$SourceUrl/requirements.txt" -OutFile "$Dest\requirements.txt" -UseDefaultCredentials
Invoke-WebRequest -Uri "$SourceUrl/bridge.py"       -OutFile "$Dest\bridge.py" -UseDefaultCredentials
Invoke-WebRequest -Uri "$SourceUrl/excel_fallback.py" -OutFile "$Dest\excel_fallback.py" -UseDefaultCredentials

# 2. venv + pinned deps
if (-not (Test-Path "$Dest\.venv")) {
  python -m venv "$Dest\.venv"
}
& "$Dest\.venv\Scripts\python.exe" -m pip install --disable-pip-version-check -r "$Dest\requirements.txt"

# 3. sbroenne excelcli.exe (pinned release + checksum). Offline/MIT; embed the pinned
#    release URL + expected SHA256 here for Flaw-B supply-chain control.
$excelCliUrl   = "https://github.com/sbroenne/mcp-server-excel/releases/download/vX.Y.Z/excelcli.exe"
$expectedSha   = "REPLACE_WITH_PINNED_SHA256"
$excelCliPath  = "$Dest\excelcli.exe"
if (-not (Test-Path $excelCliPath)) {
  Invoke-WebRequest -Uri $excelCliUrl -OutFile $excelCliPath -UseDefaultCredentials
  $actual = (Get-FileHash -Algorithm SHA256 $excelCliPath).Hash.ToLowerInvariant()
  if ($actual -ne $expectedSha.ToLowerInvariant()) {
    throw "excelcli.exe checksum mismatch: got $actual, expected $expectedSha"
  }
}

# 4. bridge.env — copy once, fill token from 1Password. Never package real secrets here.
if (-not (Test-Path "$Dest\bridge.env")) {
  Invoke-WebRequest -Uri "$SourceUrl/bridge.env.example" -OutFile "$Dest\bridge.env" -UseDefaultCredentials
  Write-Host "Created bridge.env template. Fill OFFICE_BRIDGE_TOKEN from 1Password (Homelab)."
}

Write-Host "Install complete. Run: bridge.py (reads bridge.env)."
# TODO(HD-111): register scheduled self-update (update.ps1) + Windows firewall rule:
#   allow only source subnet / Headscale overlay on OFFICE_BRIDGE_PORT.