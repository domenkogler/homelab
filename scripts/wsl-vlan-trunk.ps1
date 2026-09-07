<#
.SYNOPSIS
    Kogler Homelab - WSL Debian Mgmt-99 via Windows route-through (idempotent, admin).

.DESCRIPTION
    Makes WSL Debian reach the Management VLAN (99) by routing THROUGH the
    Windows host, which is dual-homed (Home untagged + Mgmt-99 tagged).
    This is the working architecture for WSL2 + Hyper-V vSwitch:

      Windows 11 (dual-homed):
        vEthernet (VLAN-Switch) = Home 10.10.1.80/24  (DHCP, gw 10.10.1.1)
        vEthernet (Mgmt99)      = Mgmt 10.10.99.80/24 (static, NO default gw)
        IP forwarding ON        -> routes WSL's 10.10.99.0/24 via 10.10.1.80

      Debian (WSL2, bridged vmSwitch=VLAN-Switch):
        eth0 static 10.10.1.81/24 (systemd-networkd), gw 10.10.1.1
        route 10.10.99.0/24 via 10.10.1.80   (Windows is the 99 hop)

    Why not vNIC trunking? WSL2's VM vNIC is hidden from Hyper-V management
    (Get-VM is empty), so Set-VMNetworkAdapterVlan on the WSL vNIC is
    impossible; mirrored mode gives a view but no independently routable leg
    (ARP FAIL). Route-through-Windows is the supported, robust path.

    Idempotent, safe to re-run; reads before it writes; touches no secrets.
    Requires: Windows 11 + Hyper-V + Administrator (UAC).

.EXAMPLE
    # From an elevated PowerShell:
    powershell -ExecutionPolicy Bypass -File scripts/wsl-vlan-trunk.ps1

.NOTES
    Owning spec: docs/network-vlans.md Port Type Reference (Laptop row),
    docs/network-ops.md. Windows-only by design (Hyper-V).
    ASCII-only, LF, no BOM (PowerShell misparses BOM-less UTF-8 .ps1 with
    non-ASCII; kept ASCII to be bulletproof).
#>

$ErrorActionPreference = 'Continue'

function Write-Step { param([string]$Title) Write-Host "`n=== $Title ===" -ForegroundColor Cyan }

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "ERROR: must run as Administrator (Hyper-V + net config require it)." -ForegroundColor Red
        exit 1
    }
}

function Ensure-VlanSwitch {
    # External vSwitch on the physical Home NIC (creates vEthernet (VLAN-Switch) = 10.10.1.80).
    $sw = Get-VMSwitch -Name 'VLAN-Switch' -ErrorAction SilentlyContinue
    if ($sw) {
        Write-Host "  VLAN-Switch exists ($($sw.SwitchType))." -ForegroundColor Green
        return
    }
    $nic = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and
        ($_.Name -eq 'Ethernet 2' -or $_.InterfaceDescription -like '*USB Ethernet*') } |
        Select-Object -First 1
    if (-not $nic) { Write-Host "  ERROR: no physical Home NIC found." -ForegroundColor Red; return }
    New-VMSwitch -Name 'VLAN-Switch' -NetAdapterName $nic.Name -AllowManagementOS $true | Out-Null
    Write-Host "  VLAN-Switch created on '$($nic.Name)'." -ForegroundColor Green
}

function Ensure-Mgmt99 {
    # ManagementOS vNIC tagged Access 99, static 10.10.99.80/24, NO default gw,
    # DHCP off. Windows holds .80 (SSOT laptop-domen); WSL routes 99 through it.
    $ad = Get-VMNetworkAdapter -ManagementOS -ErrorAction SilentlyContinue | Where-Object Name -eq 'Mgmt99'
    if (-not $ad) {
        Add-VMNetworkAdapter -ManagementOS -Name 'Mgmt99' -SwitchName 'VLAN-Switch' -Passthru |
            Set-VMNetworkAdapterVlan -Access -VlanId 99
        Write-Host "  Mgmt99 vNIC created (Access 99)." -ForegroundColor Green
    } else {
        Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName 'Mgmt99' -Access -VlanId 99 -ErrorAction SilentlyContinue
        Write-Host "  Mgmt99 vNIC exists, pinned Access 99." -ForegroundColor Green
    }
    # Windows-side IP: static 10.10.99.80/24, no gateway, DHCP off.
    $if = Get-NetAdapter -Name 'vEthernet (Mgmt99)' -ErrorAction SilentlyContinue
    if (-not $if) { Write-Host "  WARN: vEthernet (Mgmt99) not up yet." -ForegroundColor Yellow; return }
    Set-NetIPInterface -InterfaceAlias 'vEthernet (Mgmt99)' -Dhcp Disabled -ErrorAction SilentlyContinue
    Get-NetIPAddress -InterfaceAlias 'vEthernet (Mgmt99)' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    Get-NetRoute -InterfaceAlias 'vEthernet (Mgmt99)' -ErrorAction SilentlyContinue |
        Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceAlias 'vEthernet (Mgmt99)' -IPAddress '10.10.99.80' -PrefixLength 24 |
        Out-Null
    Write-Host "  Mgmt99 static 10.10.99.80/24 (no gw)." -ForegroundColor Green
}

function Enable-Forwarding {
    # Windows becomes the 99 hop for WSL: forwarding ON both legs + firewall allow.
    Set-NetIPInterface -InterfaceAlias 'vEthernet (VLAN-Switch)' -Forwarding Enabled -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceAlias 'vEthernet (Mgmt99)'      -Forwarding Enabled -ErrorAction SilentlyContinue
    # Persist: IPEnableRouter=1 (survives reboot).
    $reg = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
    if ((Get-ItemProperty -Path $reg -Name 'IPEnableRouter' -ErrorAction SilentlyContinue).IPEnableRouter -ne 1) {
        Set-ItemProperty -Path $reg -Name 'IPEnableRouter' -Value 1
        Write-Host "  IPEnableRouter=1 set in registry (persistent)." -ForegroundColor Green
    }
    # Firewall: allow forward between the two legs (idempotent adds).
    New-NetFirewallRule -DisplayName 'WSL-to-Mgmt99 forward' -Direction Inbound -InterfaceAlias 'vEthernet (VLAN-Switch)' -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName 'Mgmt99-to-WSL forward' -Direction Outbound -InterfaceAlias 'vEthernet (Mgmt99)' -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
    Write-Host "  IP forwarding + firewall allow configured." -ForegroundColor Green
}

function Verify {
    Write-Step "Verification"
    Write-Host "-- Windows adapters:"
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceAlias -match 'VLAN-Switch|Mgmt99' } |
        Select-Object InterfaceAlias,IPAddress | Format-Table -AutoSize
    Write-Host "-- Default routes (Mgmt99 must have NO default via 10.10.99.1):"
    Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Select-Object InterfaceAlias,NextHop,RouteMetric | Format-Table -AutoSize
    Write-Host "-- From Debian (expected):"
    Write-Host "     eth0 10.10.1.81/24 (static), default via 10.10.1.1"
    Write-Host "     route 10.10.99.0/24 via 10.10.1.80"
    Write-Host "     ping -c2 10.10.99.2 (switch) / 10.10.99.20 (Pi) should reply"
}

Write-Step "Prerequisites"
Assert-Admin

Write-Step "vSwitch (VLAN-Switch, external)"
Ensure-VlanSwitch

Write-Step "Mgmt99 vNIC (Access 99, static 10.10.99.80, no gw)"
Ensure-Mgmt99

Write-Step "IP forwarding + firewall (Windows = 99 hop for WSL)"
Enable-Forwarding

Write-Step "WSL restart (apply bridged vmSwitch config)"
& wsl.exe --shutdown 2>&1 | Out-String | Write-Host
Start-Sleep -Seconds 3
Write-Host "  WSL shut down; start Debian to verify." -ForegroundColor Green

Verify
Write-Host "`nDone. In Debian, ensure systemd-networkd static eth0 (10.10.1.81)"
Write-Host "with route 10.10.99.0/24 via 10.10.1.80 (repo network role pattern)."