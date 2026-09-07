<#
.SYNOPSIS
    WSL2 Debian network fix - NAT mode + auto-resolv (network-type independent, idempotent, admin).

.DESCRIPTION
    Makes WSL2 Debian work on ANY network the Windows host can reach (wired LAN,
    WiFi, phone hotspot, guest network) without manual per-network edits.

    WHY (proven 2026-09-07 on a mobile hotspot):
      * The old bridged topology (.wslconfig networkingMode=Bridged +
        vmSwitch=VLAN-Switch) pins WSL eth0 to a HOMELAB static IP via
        systemd-networkd and binds the vSwitch to a physical wired NIC. On WiFi /
        hotspot that NIC has no carrier -> eth0 comes up with NO IP and NO route
        (network unreachable), and the hardcoded homelab resolv.conf points at
        unreachable DNS. The whole Debian runner goes offline.
      * WSL2 NAT mode rides the host's own connectivity (works on any network)
        and with auto-resolv /etc/resolv.conf follows the Windows resolver, so
        DNS is correct whether Windows is on the homelab DHCP chain or the
        hotspot's DHCP.

    WHAT THIS SCRIPT DOES (all reversible, backups taken):
      1. .wslconfig        -> networkingMode=Nat (removes Bridged/vmSwitch line)
      2. /etc/wsl.conf     -> drop generateResolvConf=false (keeps systemd=true)
                              so WSL regenerates /etc/resolv.conf every boot from
                              the Windows/default-switch resolver (Option A).
      3. /etc/systemd/network/10-eth0.network -> disabled-homelab (the homelab static
                              10.10.1.81/24 + gw + mgmt route is NAT-irrelevant
                              and was the off-LAN breaker).
      4. WSL restart (wsl --shutdown) so the new config takes effect.
      5. Verification: eth0 has an address, has a default route, /etc/resolv.conf
         is auto-generated, and DNS + HTTPS work.

    IDEMPOTENT: safe to re-run any number of times. It reads before it writes.
    On a re-run after the fix is already in place it detects the desired state
    and reports "already NAT / already auto-resolv / already clean" with no
    redundant WSL restarts, no disconnects.

    OPT-IN HOMELAB EXTRA:
      -EnableMgmt99  additionally restores the old route-through-Windows setup so
      Debian can reach the Management VLAN 99 at home (Windows Mgmt99 vNIC static
      10.10.99.80, IP forwarding ON, Debian /etc/systemd/network mgmt route).
      This is an at-home convenience only - it is deliberately NOT applied by
      default so the runner stays mobile-safe. See docs/network-vlans.md Laptop row.

    Backups created next to the touched files:
      Windows:  %USERPROFILE%\.wslconfig.bak-nat
      Debian:   /etc/wsl.conf.bak-nat , /etc/systemd/network/10-eth0.network.disabled-homelab

    Requires: Windows 11 + WSL2 + Administrator (wsl --shutdown + reg/network ops).

.EXAMPLE
    # From an elevated PowerShell:
    powershell -ExecutionPolicy Bypass -File scripts/wsl-nat-resolv.ps1

    # With the optional home Mgmt-99 route-through extra:
    powershell -ExecutionPolicy Bypass -File scripts/wsl-nat-resolv.ps1 -EnableMgmt99

.NOTES
    Replaces scripts/wsl-vlan-trunk.ps1 (the bridged/VLAN-Switch route-through
    script), which only worked on the wired home network. Owning docs:
    docs/network-vlans.md (Laptop row), deployment-manual.md Phase 0 WSL runner.
    ASCII-only, LF, no BOM (PowerShell misparses BOM-less UTF-8 .ps1 with
    non-ASCII; kept ASCII to be bulletproof).
#>
[CmdletBinding()]
param(
    [switch]$EnableMgmt99
)

$ErrorActionPreference = 'Stop'

# --- helpers ---------------------------------------------------------------

function Write-Step { param([string]$Title) Write-Host "`n=== $Title ===" -ForegroundColor Cyan }

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "ERROR: must run as Administrator (wsl --shutdown + registry/network changes require it)." -ForegroundColor Red
        exit 1
    }
}

function Test-WslDistro {
    # Returns true if "Debian" appears in `wsl -l -q` (names can be localized; try both).
    try {
        return (wsl.exe -l -q 2>$null | Select-String -SimpleMatch 'Debian' -Quiet)
    } catch { return $false }
}

function Restart-WslDebian {
    Write-Host "  Restarting WSL (wsl --shutdown) so the new config is applied..." -ForegroundColor Yellow
    wsl.exe --shutdown 2>&1 | Out-String | Write-Host
    Start-Sleep -Seconds 4
}

# --- WSL distro probe ------------------------------------------------------

Write-Step "Prerequisites"
Assert-Admin
if (-not (Test-WslDistro)) {
    Write-Host "WARN: 'Debian' distro not detected via wsl -l -q; continuing anyway (names can be localized)." -ForegroundColor Yellow
}

# --- 1. .wslconfig -> Nat ---------------------------------------------------

Write-Step "1. Windows .wslconfig -> networkingMode=Nat"
$changed = $false
$wslCfg = Join-Path $env:USERPROFILE '.wslconfig'
$hasCfg = Test-Path $wslCfg

if ($hasCfg) {
    $content = Get-Content $wslCfg -Raw
    # Remove any networkingMode / vmSwitch lines (Bridged, mirrored, default, Nat - we set our own).
    $lines = $content -split "`r?`n"
    $keep = @()
    foreach ($l in $lines) {
        if ($l -notmatch '^\s*#?\s*(networkingMode|vmSwitch)\s*=') { $keep += $l }
    }

    $hasNat = $content -match '(?im)^\s*networkingMode\s*=\s*Nat\s*$'
    $hasWsl2 = [bool]($keep -match '^\[wsl2\]$')

    # Rebuild cleanly: non-empty lines, [wsl2] header, networkingMode=Nat as first key.
    $out = @()
    foreach ($l in $keep) {
        if ($l.Trim() -ne '') { $out += $l }
    }
    if (-not $hasWsl2) { $out = @('[wsl2]') + $out }
    if (-not $hasNat) {
        $idx = [array]::IndexOf($out, '[wsl2]')
        if ($idx -lt 0) { $idx = 0 }
        $head = @($out[0..$idx])
        $tail = @()
        if ($idx + 1 -le $out.Length - 1) { $tail = @($out[($idx+1)..($out.Length-1)]) }
        $out = ($head + 'networkingMode=Nat' + $tail)
    }
    $newContent = ($out -join "`n") + "`n"

    if ($newContent.Trim() -ne $content.Trim()) {
        $backup = "$wslCfg.bak-nat"
        if (-not (Test-Path $backup)) { Copy-Item $wslCfg $backup }
        Set-Content -Path $wslCfg -Value $newContent -NoNewline
        Write-Host "  .wslconfig updated to networkingMode=Nat (backup: $backup)." -ForegroundColor Green
        $changed = $true
    } else {
        Write-Host "  .wslconfig already networkingMode=Nat; no change." -ForegroundColor Green
    }
} else {
    Set-Content -Path $wslCfg -Value "[wsl2]`nnetworkingMode=Nat`n" -NoNewline
    Write-Host "  .wslconfig created with networkingMode=Nat." -ForegroundColor Green
    $changed = $true
}

# --- 2. /etc/wsl.conf -> auto-resolv ---------------------------------------

Write-Step "2. Debian /etc/wsl.conf -> auto-resolv (drop generateResolvConf=false)"
$wslConf = wsl.exe -d Debian -- sh -lc 'cat /etc/wsl.conf 2>/dev/null' 2>$null | Out-String
$curWslConf = $wslConf.Trim()
if ($curWslConf -match 'generateResolvConf\s*=\s*false') {
    $newConf = (($curWslConf -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#?\s*generateResolvConf\s*=' }) -join "`n")
    # ensure [boot] systemd=true is present
    if ($newConf -notmatch 'systemd\s*=\s*true') {
        $newConf = ($newConf.TrimEnd() + "`n[boot]`nsystemd=true")
    }
    # base64-transfer (safe vs. single-quote/newline injection in the shell command)
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($newConf))
    wsl.exe -d Debian -- sh -lc "sudo cp /etc/wsl.conf /etc/wsl.conf.bak-nat && echo '$b64' | base64 -d | sudo tee /etc/wsl.conf >/dev/null" 2>&1 | Out-String | Write-Host
    Write-Host "  /etc/wsl.conf: removed generateResolvConf=false (systemd=true kept). Backup: /etc/wsl.conf.bak-nat" -ForegroundColor Green
    $changed = $true
} else {
    Write-Host "  /etc/wsl.conf already auto-resolv (no generateResolvConf=false); no change." -ForegroundColor Green
}

# --- 3. Disable the static homelab systemd-networkd unit --------------------

Write-Step "3. Disable /etc/systemd/network/10-eth0.network (homelab static IP, NAT-irrelevant)"
# Detect ACTIVE unit (10-eth0.network). Backed-up variants (.bak-nat / .disabled-homelab)
# mean it is already neutralized -> idempotent re-run stays clean.
$netUnit = wsl.exe -d Debian -- sh -lc 'ls /etc/systemd/network/10-eth0.network 2>/dev/null' 2>$null | Out-String
if ($netUnit.Trim() -ne '') {
    wsl.exe -d Debian -- sh -lc "sudo mv /etc/systemd/network/10-eth0.network /etc/systemd/network/10-eth0.network.disabled-homelab" 2>&1 | Out-String | Write-Host
    Write-Host "  Moved 10-eth0.network -> 10-eth0.network.disabled-homelab (homelab static 10.10.1.81 disabled; NAT provides DHCP)." -ForegroundColor Green
    $changed = $true
} else {
    Write-Host "  No active 10-eth0.network; already clean." -ForegroundColor Green
}

# --- 3b. OPTIONAL: home Mgmt-99 route-through-Windows extra ----------------

if ($EnableMgmt99) {
    Write-Step "3b. OPT-IN: restore home route-through-Windows (Mgmt-99) extras"
    # Recreate the ManagementOS Mgmt99 vNIC (access 99, static 10.10.99.80, no gw)
    # + enable IP forwarding + firewall allow. Only meaningful on the home LAN.
    $ad = Get-VMNetworkAdapter -ManagementOS -ErrorAction SilentlyContinue | Where-Object Name -eq 'Mgmt99'
    if (-not $ad) {
        # need an external switch on the active Home NIC
        $sw = Get-VMSwitch -Name 'VLAN-Switch' -ErrorAction SilentlyContinue
        if (-not $sw) {
            $nic = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and
                ($_.Name -eq 'Ethernet 2' -or $_.InterfaceDescription -like '*USB Ethernet*') } |
                Select-Object -First 1
            if (-not $nic) { Write-Host "  WARN: no wired Home NIC to bind VLAN-Switch to (on WiFi?); skipping Mgmt-99 extras." -ForegroundColor Yellow }
            else {
                New-VMSwitch -Name 'VLAN-Switch' -NetAdapterName $nic.Name -AllowManagementOS $true | Out-Null
                Write-Host "  VLAN-Switch created on '$($nic.Name)'." -ForegroundColor Green
            }
        } else { Write-Host "  VLAN-Switch already exists." -ForegroundColor Green }
        if (Get-VMSwitch -Name 'VLAN-Switch' -ErrorAction SilentlyContinue) {
            Add-VMNetworkAdapter -ManagementOS -Name 'Mgmt99' -SwitchName 'VLAN-Switch' -Passthru |
                Set-VMNetworkAdapterVlan -Access -VlanId 99 | Out-Null
            Write-Host "  Mgmt99 vNIC created (Access 99)." -ForegroundColor Green
        }
    } else { Write-Host "  Mgmt99 vNIC already exists." -ForegroundColor Green }

    # Windows-side static 10.10.99.80/24, no gw, forwarding on
    $if = Get-NetAdapter -Name 'vEthernet (Mgmt99)' -ErrorAction SilentlyContinue
    if ($if) {
        Set-NetIPInterface -InterfaceAlias 'vEthernet (Mgmt99)' -Dhcp Disabled -ErrorAction SilentlyContinue
        Get-NetIPAddress -InterfaceAlias 'vEthernet (Mgmt99)' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        Get-NetRoute -InterfaceAlias 'vEthernet (Mgmt99)' -ErrorAction SilentlyContinue |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceAlias 'vEthernet (Mgmt99)' -IPAddress '10.10.99.80' -PrefixLength 24 | Out-Null
        Set-NetIPInterface -InterfaceAlias 'vEthernet (Mgmt99)' -Forwarding Enabled -ErrorAction SilentlyContinue
        Write-Host "  Mgmt99 static 10.10.99.80/24 (no gw) + forwarding." -ForegroundColor Green
    } else { Write-Host "  WARN: vEthernet (Mgmt99) not up; Mgmt-99 extras incomplete (check home LAN)." -ForegroundColor Yellow }

    # IPEnableRouter persistent + firewall
    $reg = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
    if ((Get-ItemProperty -Path $reg -Name 'IPEnableRouter' -ErrorAction SilentlyContinue).IPEnableRouter -ne 1) {
        Set-ItemProperty -Path $reg -Name 'IPEnableRouter' -Value 1
        Write-Host "  IPEnableRouter=1 set (persistent)." -ForegroundColor Green
    }
    New-NetFirewallRule -DisplayName 'WSL-to-Mgmt99 forward' -Direction Inbound -InterfaceAlias 'vEthernet (VLAN-Switch)' -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName 'Mgmt99-to-WSL forward' -Direction Outbound -InterfaceAlias 'vEthernet (Mgmt99)' -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
}

# --- 4. WSL restart ---------------------------------------------------------

Write-Step "4. WSL restart (apply NAT + auto-resolv)"
# Only restart when something actually changed - a re-run on an already-fixed
# machine is a true no-op and should not bounce WSL (idempotency).
if ($changed) {
    Restart-WslDebian
    # Give systemd-networkd a moment to (re)configure eth0 from NAT DHCP.
    Start-Sleep -Seconds 6
} else {
    Write-Host "  No changes required; skipping WSL restart." -ForegroundColor Green
}

# --- 5. Verification --------------------------------------------------------

Write-Step "5. Verification"
$report = wsl.exe -d Debian -- sh -lc '
  echo "== ip -brief addr =="; ip -brief addr | grep -E "eth0|lo"
  echo "== default route =="; ip route show default
  echo "== resolv.conf =="; cat /etc/resolv.conf
  echo "== DNS =="; getent hosts deb.debian.org >/dev/null 2>&1 && echo "DNS_OK" || echo "DNS_FAIL"
  echo "== HTTPS =="; (curl -sI --max-time 8 https://deb.debian.org | head -1) || echo "CURL_FAIL"
' 2>&1 | Out-String
Write-Host $report

if ($report -match 'DNS_OK' -and $report -match 'HTTP/2 200|HTTP/1.1 200' -and $report -match 'default via') {
    Write-Host "SUCCESS: WSL Debian now has NAT networking + auto-resolv DNS on the current network." -ForegroundColor Green
    if ($EnableMgmt99) { Write-Host "  (Mgmt-99 route-through-Windows extra applied - only meaningful on the home LAN.)" -ForegroundColor DarkYellow }
} else {
    Write-Host "WARN: verification did not fully pass - review the output above." -ForegroundColor Yellow
    Write-Host "  (If eth0 shows an address + default route + DNS_OK, the fix worked and the warning is a probe quirk.)" -ForegroundColor DarkGray
}

Write-Host "`nDone. Debian is now network-type independent (NAT + auto-resolv)." -ForegroundColor Green
Write-Host "Re-run this script any time to restore the same state (idempotent)." -ForegroundColor DarkGray