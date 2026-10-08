<#
.SYNOPSIS
  Install and PROVE the pinned Nerd Font family for the pi seat TUI on Windows (HD-1110).
.DESCRIPTION
  The Debian sibling is scripts/install-nerd-font.sh; THIS is the leg that matters on this
  machine, because the terminal that rasterises pi's footer glyphs runs on Windows — on the
  Win11 seat directly, and on every SSH leg from here (WSL and oldsrv included). A font placed
  in a Linux home directory changes nothing you can see from this laptop.

  Per-user install, no elevation: the files go to %LOCALAPPDATA%\Microsoft\Windows\Fonts and
  are registered under HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts, which is the
  documented Windows 10+ per-user font path (no HKLM write, no admin, reversible by -Uninstall).

  Integrity: the release tag in group_vars/all/versions.yml is the boundary (nerd-fonts ships no
  per-asset checksum file — checked against the v3.5.1 release 2026-10-08), so the state file
  records the sha256 of the archive that was installed and -Check re-hashes the installed files
  against a per-file manifest. A swapped font directory reads as drift, not as success.

  WHAT THIS CANNOT PROVE: that pi LOOKS right. The font must also be selected in the TERMINAL
  PROFILE (Windows Terminal: settings.json fontFace; VS Code: terminal.integrated.fontFamily).
  Owning that choice is the operator's — pi-open-tui's `icons.mode: auto` picks Nerd glyphs from
  the terminal environment, not from the font list, and docs/pi-harness.md §5a says where to set
  it. -Check prints the font families Windows now offers so the operator can compare.
.PARAMETER Check
  Report only (default): installed release vs the pin, the manifest, and what the registry lists.
.PARAMETER Push
  Download (cached under %LOCALAPPDATA%\homelab-nerd-font\cache) and install what is missing.
.PARAMETER Uninstall
  Remove the per-user registrations + files this script installed. Nothing else is touched.
#>
[CmdletBinding()]
param(
  [switch]$Check,
  [switch]$Push,
  [switch]$Uninstall,
  [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)
$ErrorActionPreference = 'Stop'
$StateDir = Join-Path $env:LOCALAPPDATA 'homelab-nerd-font'
$StateFile = Join-Path $StateDir 'state.json'
$Cache = Join-Path $StateDir 'cache'
$UserFontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$RegPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

function Read-Pin([string]$name) {
  $line = Select-String -Path (Join-Path $RepoRoot 'IaC\ansible\group_vars\all\versions.yml') -Pattern ("^{0}:\s*(.+)" -f $name) | Select-Object -First 1
  if (-not $line) { throw "pin '$name' missing from IaC/ansible/group_vars/all/versions.yml — add it there, do not hardcode it here" }
  ($line.Matches[0].Groups[1].Value -replace '["#].*$', '').Trim()
}
function File-Sha256([string]$p) { (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower() }
function Load-State {
  if (Test-Path $StateFile) { Get-Content $StateFile -Raw | ConvertFrom-Json } else { $null }
}
function Installed-Files([string]$state) {
  if (-not $state) { return @() }
  @($state.files | ForEach-Object { $_.path })
}
function Check-Manifest($state) {
  $bad = @()
  foreach ($f in $state.files) {
    if (-not (Test-Path $f.path)) { $bad += "MISSING  $($f.path)"; continue }
    if ((File-Sha256 $f.path) -ne $f.sha256) { $bad += "HASH     $($f.path)" }
  }
  $bad
}
function Registered([string]$family) {
  if (-not (Test-Path $RegPath)) { return @() }
  (Get-Item $RegPath).Property | Where-Object { $_ -like "*$family*" }
}

$release = Read-Pin 'nerd_fonts_version'
$family  = Read-Pin 'nerd_fonts_family'
Write-Host "install-nerd-font(win): pin $family $release"

if ($Uninstall) {
  $state = Load-State
  foreach ($p in Installed-Files $state) { if (Test-Path $p) { Remove-Item -LiteralPath $p -Force } }
  foreach ($name in (Registered $family)) { Remove-ItemProperty -Path $RegPath -Name $name }
  if (Test-Path $StateFile) { Remove-Item $StateFile -Force }
  Write-Host "  removed the per-user $family this script installed (a restart or re-login releases the locked files)"
  exit 0
}

$state = Load-State
function Verdict {
  if (-not $state) { Write-Host "  MISSING: no installed $family — run: install-nerd-font.ps1 -Push"; return 1 }
  if ($state.release -ne $release) { Write-Host "  STALE: installed '$($state.release)' != pin '$release' — -Push converges"; return 1 }
  $bad = Check-Manifest $state
  if ($bad.Count -gt 0) { Write-Host "  DRIFT: installed files do not match the manifest:"; $bad | ForEach-Object { Write-Host "    $_" }; return 1 }
  $reg = Registered $family
  if ($reg.Count -eq 0) { Write-Host "  NOT REGISTERED: the files are on disk but Windows does not list '$family' — the registry half of the install is missing (-Push re-registers)"; return 1 }
  Write-Host "  OK: $family $release installed and registered per-user ($($reg.Count) entr$(if($reg.Count -eq 1){'y'}else{'ies'}))"
  Write-Host "  REMEMBER: select the font in the TERMINAL PROFILE — having it installed is not the same as the terminal drawing with it."
  return 0
}
if (-not $Push) { exit (Verdict) }

# --- push -----------------------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $Cache, $UserFontDir, $StateDir | Out-Null
if ($state -and $state.release -eq $release -and (Check-Manifest $state).Count -eq 0) {
  Write-Host "  current: $family $release verified — nothing to download"
  exit (Verdict)
}
$zip = Join-Path $Cache "$family-$release.zip"
$url = "https://github.com/ryanoasis/nerd-fonts/releases/download/$release/$family.zip"
if (-not (Test-Path $zip)) {
  Write-Host "  fetching $url"
  Invoke-WebRequest -Uri $url -OutFile "$zip.part" -UseBasicParsing
  Move-Item -Force "$zip.part" $zip
} else { Write-Host "  using the cached $zip" }
$tmp = Join-Path $env:TEMP ("nerdfont-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
  Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
  $src = @(Get-ChildItem -Path $tmp -Recurse -Include *.ttf, *.otf)
  if ($src.Count -eq 0) { throw "the archive extracted but carried no .ttf/.otf — refusing to record an empty install" }
  $files = @()
  foreach ($f in $src) {
    $dest = Join-Path $UserFontDir $f.Name
    Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
    $files += [pscustomobject]@{ path = $dest; sha256 = (File-Sha256 $dest) }
    New-ItemProperty -Path $RegPath -Name "$($f.BaseName) (TrueType)" -PropertyType String -Value $dest -Force | Out-Null
  }
  [pscustomobject]@{ release = $release; family = $family; zip_sha256 = (File-Sha256 $zip); files = $files } `
    | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $StateFile -Encoding UTF8
  # tell the window manager the font table changed, so a new terminal sees it without a reboot
  try {
    Add-Type -Namespace Nerd -Name Font -MemberDefinition '[DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);'
    $res = [IntPtr]::Zero
    [Nerd.Font]::SendMessageTimeout([IntPtr]0xffff, 0x001D, [IntPtr]::Zero, [IntPtr]::Zero, 2, 1000, [ref]$res) | Out-Null
  } catch { Write-Host "  (WM_FONTCHANGE could not be broadcast — a new terminal still sees the font)" }
  Write-Host "  installed $($files.Count) font file(s) for $family $release"
} finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
exit (Verdict)
