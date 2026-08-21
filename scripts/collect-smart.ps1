<#
.SYNOPSIS
    Collects SMART data from all physical disks for homelab storage planning.
    Run on the i7-7700K Windows 11 PC with all 6 HDDs attached via hot-plug SATA.

.DESCRIPTION
    - Installs smartmontools via winget if not present
    - Enumerates all physical (non-USB, non-NVMe) disks
    - Runs smartctl -a on each and saves to a timestamped report
    - Outputs a compact summary table to console
    - Saves full raw output to .\reports\smart-report-YYYYMMDD-HHMMSS.txt

.USAGE
    PowerShell.exe -ExecutionPolicy Bypass -File .\scripts\collect-smart.ps1
    Or run interactively in an elevated PowerShell terminal.
#>

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path "$scriptDir\.."
$reportDir = Join-Path $repoRoot "reports"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportFile = Join-Path $reportDir "smart-report-$timestamp.txt"

# Ensure report directory exists
if (-not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir | Out-Null
}

# --- Check / install smartmontools ---
$smartctl = Get-Command smartctl -ErrorAction SilentlyContinue
if (-not $smartctl) {
    Write-Host "smartmontools not found. Installing via winget..." -ForegroundColor Yellow
    winget install --id=smartmontools.smartmontools -e --silent --accept-source-agreements
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    $smartctl = Get-Command smartctl -ErrorAction Stop
    Write-Host "smartmontools installed successfully." -ForegroundColor Green
}

Write-Host "smartctl found at: $($smartctl.Source)" -ForegroundColor Green
Write-Host "Report will be saved to: $reportFile`n" -ForegroundColor Cyan

# --- Collect disk info ---
$allDisks = Get-Disk | Where-Object {
    # Exclude USB and NVMe — we only want SATA HDDs
    $_.BusType -notin @('USB', 'NVMe', 'FileBackedVirtual')
}

if ($allDisks.Count -eq 0) {
    Write-Host "ERROR: No SATA disks found! Attach the HDDs and re-run." -ForegroundColor Red
    exit 1
}

Write-Host "Found $($allDisks.Count) SATA disk(s):`n" -ForegroundColor White

# --- Summary table header ---
$summary = @()
$reportLines = @()
$reportLines += "========================================================================"
$reportLines += "  HOMELAB SMART REPORT — $timestamp"
$reportLines += "  Machine: $env:COMPUTERNAME"
$reportLines += "========================================================================"
$reportLines += ""

# --- Process each disk ---
$diskIndex = 0
foreach ($disk in $allDisks | Sort-Object Number) {
    $diskIndex++
    $diskNum = $disk.Number
    $physDisk = Get-PhysicalDisk -DeviceId $diskNum -ErrorAction SilentlyContinue
    $model = if ($physDisk) { $physDisk.FriendlyString -replace '^SATA\s+','' } else { $disk.FriendlyName }
    $sizeGB = [math]::Round($disk.Size / 1GB, 0)
    $serial = if ($physDisk.SerialNumber) { $physDisk.SerialNumber } else { "N/A" }

    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host "[$diskIndex/$($allDisks.Count)] PhysicalDisk $diskNum — $model ($sizeGB GB)" -ForegroundColor Yellow
    Write-Host "      Serial: $serial" -ForegroundColor White

    # Physical SCSI path for smartctl on Windows: /dev/pdN
    $smartOutput = & smartctl -a "pd$diskNum" 2>&1
    $exitCode = $LASTEXITCODE

    # Parse key attributes
    $smartLines = $smartOutput -split "`r`n|`n"
    $attrs = @{}
    $inAttrSection = $false
    foreach ($line in $smartLines) {
        if ($line -match '^ID#\s+ATTRIBUTE_NAME') { $inAttrSection = $true; continue }
        if ($inAttrSection -and $line -match '^\s*$') { $inAttrSection = $false }
        if ($inAttrSection -and $line -match '^\s*(\d+)\s+(\S[\S ]+?)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)') {
            $attrName = $Matches[2].Trim()
            $rawVal  = $Matches[10]
            $attrs[$attrName] = $rawVal
        }
    }

    # Also grab model & serial from smartctl for cross-check
    $smartModel = ""
    $smartSerial = ""
    $hours = "N/A"
    foreach ($line in $smartLines) {
        if ($line -match 'Device Model:\s+(.+)') { $smartModel = $Matches[1].Trim() }
        if ($line -match 'Serial Number:\s+(.+)') { $smartSerial = $Matches[1].Trim() }
        if ($line -match 'Power_On_Hours') {
            if ($line -match '(\d+)\s*$') { $hours = $Matches[1] }
        }
    }

    $reallocated   = if ($attrs['Reallocated_Sector_Ct'])    { $attrs['Reallocated_Sector_Ct'] }    else { "-" }
    $pending       = if ($attrs['Current_Pending_Sector'])   { $attrs['Current_Pending_Sector'] }   else { "-" }
    $uncorrectable = if ($attrs['Offline_Uncorrectable'])    { $attrs['Offline_Uncorrectable'] }    else { "-" }
    $spinupTime    = if ($attrs['Spin_Up_Time'])             { $attrs['Spin_Up_Time'] }             else { "-" }
    $startStop     = if ($attrs['Start_Stop_Count'])         { $attrs['Start_Stop_Count'] }         else { "-" }
    $loadCycle     = if ($attrs['Load_Cycle_Count'])         { $attrs['Load_Cycle_Count'] }         else { "-" }
    $temp          = if ($attrs['Temperature_Celsius'])      { $attrs['Temperature_Celsius'] }      else { "-" }

    # Health flags
    $flags = @()
    if ($reallocated -ne "-" -and [int]$reallocated -gt 0) { $flags += "⚠️ REALLOCATED=$reallocated" }
    if ($pending -ne "-" -and [int]$pending -gt 0)         { $flags += "🔴 PENDING=$pending" }
    if ($uncorrectable -ne "-" -and [int]$uncorrectable -gt 0) { $flags += "🔴 UNCORRECTABLE=$uncorrectable" }
    $health = if ($flags.Count -eq 0) { "✅ OK" } else { ($flags -join ', ') }

    # Write to report
    $reportLines += "────────────────────────────────────────────────────────────────────────"
    $reportLines += "DISK $diskIndex : PhysicalDisk $diskNum"
    $reportLines += "  Model       : $model"
    $reportLines += "  Serial      : $serial"
    $reportLines += "  Size        : $sizeGB GB"
    $reportLines += "  Hours       : $hours"
    $reportLines += "  Reallocated : $reallocated"
    $reportLines += "  Pending     : $pending"
    $reportLines += "  Uncorrect.  : $uncorrectable"
    $reportLines += "  SpinUp Time : $spinupTime"
    $reportLines += "  Start/Stop  : $startStop"
    $reportLines += "  Load Cycles : $loadCycle"
    $reportLines += "  Temperature : $temp °C"
    $reportLines += "  HEALTH      : $health"
    $reportLines += ""
    $reportLines += "--- RAW SMARTCTL OUTPUT ---"
    $reportLines += $smartOutput
    $reportLines += ""

    # Console summary
    Write-Host "  Model       : $smartModel" -ForegroundColor White
    Write-Host "  Hours       : $hours" -ForegroundColor White
    Write-Host "  Reallocated : $reallocated | Pending: $pending | Uncorrect: $uncorrectable" -ForegroundColor White
    Write-Host "  SpinUp Time : $spinupTime | StartStop: $startStop | LoadCycles: $loadCycle" -ForegroundColor White
    Write-Host "  Temperature : $temp °C" -ForegroundColor White
    Write-Host "  HEALTH      : $health" -ForegroundColor $(if ($flags.Count -gt 0) { "Red" } else { "Green" })

    $summary += [PSCustomObject]@{
        Disk    = "pd$diskNum"
        Model   = $smartModel
        SizeGB  = $sizeGB
        Hours   = $hours
        Realloc = $reallocated
        Pending = $pending
        Uncorr  = $uncorrectable
        SpinUp  = $spinupTime
        StartStop = $startStop
        Temp    = $temp
        Health  = $health
    }
}

# --- Save report ---
$reportLines | Out-File -FilePath $reportFile -Encoding UTF8

# --- Print summary table ---
Write-Host "`n========================================================================" -ForegroundColor Cyan
Write-Host "  SUMMARY TABLE" -ForegroundColor Cyan
Write-Host "========================================================================`n" -ForegroundColor Cyan
$summary | Format-Table -AutoSize -Wrap

Write-Host "Full report saved to: $reportFile" -ForegroundColor Green
Write-Host "`nNext step: Copy this file to the homelab repo and commit it." -ForegroundColor Green
Write-Host "  cp $reportFile D:\source\domenkogler\homelab\reports\"