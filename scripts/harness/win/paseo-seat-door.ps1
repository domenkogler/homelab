<#
.SYNOPSIS
  The Windows half of the Paseo coding seats: the two firewall rules and the one portproxy that
  let a phone reach the laptop seats across the tailnet, and nothing else (HD-411).
.DESCRIPTION
  WHAT THIS IS FOR. Each laptop seat runs its own Paseo daemon and binds 0.0.0.0 (the desktop app
  arrives at localhost, the phone at the laptop's tailnet address). NEVER The tailnet IP itself is
  never bound: a listener on that address cannot bind while Tailscale is down, and with
  manageBuiltInDaemon on the desktop app loses its own daemon with it. The boundary therefore
  moves into the FIREWALL: inbound is allowed for the tailnet range 100.64.0.0/10 and for nothing
  else, so the LAN never gets a socket even though the daemon listens on every interface.

  Three artifacts, all machine-wide, all elevation-required (this is the owner's leg, O4):

    1. rule 'Paseo daemon (tailnet only)'   inbound tcp 6767 for %LOCALAPPDATA%\Programs\Paseo\
                                            Paseo.exe, remote 100.64.0.0/10. Windows binds a rule
                                            to the PROCESS IMAGE, so the pile of node.exe allow
                                            rules already on this box proves nothing about the
                                            desktop-managed daemon - Paseo.exe is its image.
    2. rule 'Paseo WSL seat (tailnet only)' inbound tcp 6768, remote 100.64.0.0/10, NO program:
                                            the listener is the kernel portproxy, which has no
                                            image to name. This is what admits the phone to the
                                            WSL seat's port on the laptop's tailnet address.
    3. portproxy  <tailnet-ip>:6768 -> 127.0.0.1:6768. The target is LOOPBACK, never the distro's
                                            NAT address: localhostForwarding finishes that hop, so
                                            the rule survives a reboot while an address-targeted
                                            entry points at a DHCP lease that has since moved.
                                            The tailnet address is read at run time from
                                            `tailscale ip -4`, because it is not stable text.

  WHAT THIS DOES NOT DO. It starts no daemon and writes no config.json - those are the `paseo`
  seat plane (scripts/harness/seat-paseo.sh) and, on the WSL side, `daemon.listen`. It does not
  touch the mirrored-networking question: NEVER do not switch the distro to mirrored networking to
  dodge the portproxy, because the dns-route and llm-path planes derive the WSL NAT gateway from
  `ip route` and would go blind. And it never opens a port to the LAN: every rule here is scoped
  to 100.64.0.0/10.

  ORDER THAT MATTERS: the WSL daemon must already answer on 0.0.0.0:6768 (todo HD-411, the step
  this carrier exists to unblock) BEFORE the portproxy is useful - a proxy to a closed loopback
  forwards nothing and reads as a broken phone leg.
.PARAMETER Check
  Report only (default). Reads what it can without elevation and prints the exact elevated commands
  for whatever it cannot read. Unelevated, Get-NetFirewallRule and netsh portproxy show are both
  blocked, and a check that cannot read is reported as such - never as "absent".
.PARAMETER Push
  Apply the three artifacts. Requires an elevated shell; without one it changes NOTHING and prints
  the commands it would have run.
.PARAMETER Show
  Print the command list and nothing else - the artifact the owner needs to run the parked leg.
#>
[CmdletBinding()]
param(
  [switch]$Check,
  [switch]$Push,
  [switch]$Show
)
$ErrorActionPreference = 'Stop'

$TailnetRange = '100.64.0.0/10'
$WinPort      = 6767          # paseo_ports.win11 (group_vars/all/main.yml) - keep the two in step
$WslPort      = 6768          # paseo_ports.wsl
$PaseoExe     = Join-Path $env:LOCALAPPDATA 'Programs\Paseo\Paseo.exe'
$RuleWin      = 'Paseo daemon (tailnet only)'
$RuleWsl      = 'Paseo WSL seat (tailnet only)'

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-TailnetIp {
  # The laptop's own tailnet address, read now. It is a 100.64/10 address and it does move, which
  # is why the portproxy is re-run rather than written down once.
  $ts = Get-Command tailscale -ErrorAction SilentlyContinue
  if (-not $ts) { return $null }
  $raw = (& tailscale ip -4 2>$null) | Out-String
  $m = [regex]::Match($raw, '\b(100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3})\b')
  if ($m.Success) { return $m.Groups[1].Value }
  return $null
}

function Get-Commands {
  # ONE source for the command text: -Show prints these, -Push runs them, -Check quotes them. A
  # second spelling of a command is a command that drifts from the one that actually runs.
  $ip = Get-TailnetIp
  $listen = if ($ip) { $ip } else { '<tailscale-ip>' }
  @(
    "New-NetFirewallRule -DisplayName '$RuleWin' -Direction Inbound -Action Allow -Protocol TCP -LocalPort $WinPort -Program `"$PaseoExe`" -RemoteAddress $TailnetRange -Profile Any",
    "New-NetFirewallRule -DisplayName '$RuleWsl' -Direction Inbound -Action Allow -Protocol TCP -LocalPort $WslPort -RemoteAddress $TailnetRange -Profile Any",
    "netsh interface portproxy add v4tov4 listenaddress=$listen listenport=$WslPort connectaddress=127.0.0.1 connectport=$WslPort",
    "netsh interface portproxy show all",
    "Get-NetFirewallRule -DisplayName '$RuleWin','$RuleWsl' | Get-NetFirewallPortFilter | Format-List"
  )
}

function Show-Commands {
  Write-Host 'Elevated (run from an Administrator PowerShell):'
  foreach ($c in Get-Commands) { Write-Host "  $c" }
  Write-Host ''
  Write-Host "Precondition: the WSL daemon answers on 0.0.0.0:$WslPort, and the Windows one on"
  Write-Host "0.0.0.0:$WinPort - both are the 'paseo' seat plane's push half, not this script's."
  Write-Host 'Never bind the tailnet address itself, and never switch the distro to mirrored'
  Write-Host 'networking to avoid the portproxy (the dns-route and llm-path planes read ip route).'
}

function Get-State {
  # Everything readable without elevation. An unreadable read is reported as unreadable: a rule
  # this shell could not list is NOT a rule that is absent, and printing it as absent is how a
  # green read lies about a locked door.
  $st = [ordered]@{ admin = Test-Admin; PaseoExe = $PaseoExe; ExePresent = (Test-Path $PaseoExe)
                    tailnetIp = (Get-TailnetIp); rules = @(); proxy = $null; notes = @() }
  if (-not $st.admin) {
    $st.notes += 'unelevated: Get-NetFirewallRule and netsh portproxy show are both blocked here,'
    $st.notes += 'so the two rules and the proxy are UNVERIFIED, not missing.'
    return $st
  }
  foreach ($name in @($RuleWin, $RuleWsl)) {
    $r = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
    if (-not $r) { $st.rules += [pscustomobject]@{ name = $name; present = $false } ; continue }
    $pf = $r | Get-NetFirewallPortFilter
    $ra = ($r | Get-NetFirewallAddressFilter).RemoteAddress
    $st.rules += [pscustomobject]@{ name = $name; present = [bool]$r.Enabled
      port = $pf.LocalPort; remote = $ra; action = $r.Action; program = ($r |
      Get-NetFirewallApplicationFilter).Program }
  }
  $st.proxy = (netsh interface portproxy show all) -join "`n"
  $st
}

function Do-Check {
  $st = Get-State
  Write-Host ("admin     : {0}" -f $(if ($st.admin) { 'yes' } else { 'no - the rules cannot be listed from here' }))
  Write-Host ("daemon    : {0} ({1})" -f $st.PaseoExe, $(if ($st.ExePresent) { 'present' } else { 'NOT PRESENT - a rule for a missing image allows nothing' }))
  Write-Host ("tailnet   : {0}" -f $(if ($st.tailnetIp) { $st.tailnetIp } else { 'tailscale did not answer - the portproxy cannot be targeted' }))
  if ($st.admin) {
    foreach ($r in $st.rules) {
      if (-not $r.present) { Write-Host ("rule      : {0} - ABSENT" -f $r.name); continue }
      $ok = ($r.remote -eq $TailnetRange)
      Write-Host ("rule      : {0} - enabled={1} port={2} remote={3} action={4}{5}" -f `
        $r.name, $r.present, $r.port, $r.remote, $r.action, $(if ($ok) { '' } else { '  NEVER remote is not the tailnet range - this rule is open to the LAN' }))
    }
    if ($st.tailnetIp) {
      $want = "{0}:{1}" -f $st.tailnetIp, $WslPort
      if ($st.proxy -match [regex]::Escape($want) -and $st.proxy -match '127\.0\.0\.1' ) {
        Write-Host ("portproxy : {0} -> 127.0.0.1:{1} - present" -f $st.tailnetIp, $WslPort)
      } else {
        Write-Host ("portproxy : no entry for {0} -> 127.0.0.1:{1}" -f $st.tailnetIp, $WslPort)
      }
    }
  } else { foreach ($n in $st.notes) { Write-Host "note      : $n" } }
  Write-Host ''
  Show-Commands
  # Exit codes the fan-out understands: 0 everything owed is true, 1 a rule is off-scope/absent or
  # the proxy is not there, 2 this shell could not read the state it was asked about.
  if (-not $st.admin) { return 2 }
  $bad = ($st.rules | Where-Object { -not $_.present -or ($_.remote -ne $TailnetRange) }).Count
  if ($st.tailnetIp -and $st.proxy -notmatch [regex]::Escape(("{0}:{1}" -f $st.tailnetIp, $WslPort))) { $bad++ }
  if ($bad -gt 0) { return 1 }
  return 0
}

function Do-Push {
  if (-not (Test-Admin)) {
    Write-Host 'REFUSAL: this shell is not elevated - NOTHING was changed. Run from an Administrator PowerShell:'
    Show-Commands
    return 1
  }
  $ip = Get-TailnetIp
  if (-not $ip) { Write-Host 'FAIL: tailscale did not answer with a 100.64/10 address - no portproxy was written, because a proxy bound to the wrong address forwards to nobody.'; return 1 }
  foreach ($spec in @(
    @{ name = $RuleWin; port = $WinPort; program = $PaseoExe },
    @{ name = $RuleWsl; port = $WslPort; program = $null }
  )) {
    $existing = Get-NetFirewallRule -DisplayName $spec.name -ErrorAction SilentlyContinue
    $args = @{ DisplayName = $spec.name; Direction = 'Inbound'; Action = 'Allow'; Protocol = 'TCP'
              LocalPort = $spec.port; RemoteAddress = $TailnetRange; Profile = 'Any'
              Description = 'Homelab HD-411: Paseo coding seat, tailnet-only (100.64.0.0/10).' }
    if ($spec.program) {
      if (-not (Test-Path $spec.program)) {
        Write-Host ("FAIL: {0} is not on disk - a firewall rule naming a missing image allows nothing. Install the Paseo desktop app first." -f $spec.program)
        return 1
      }
      $args.Program = $spec.program
    }
    if ($existing) { Set-NetFirewallRule @args | Out-Null; Write-Host ("updated  : {0}" -f $spec.name) }
    else { New-NetFirewallRule @args | Out-Null; Write-Host ("created  : {0}" -f $spec.name) }
  }
  # Replace rather than add: a stale entry left from a previous tailnet address keeps forwarding to
  # a lease that no longer exists, and two entries for one port make the answer ambiguous.
  netsh interface portproxy delete v4tov4 listenaddress=$ip listenport=$WslPort | Out-Null
  netsh interface portproxy add v4tov4 listenaddress=$ip listenport=$WslPort `
    connectaddress=127.0.0.1 connectport=$WslPort | Out-Null
  Write-Host ("portproxy: {0}:{1} -> 127.0.0.1:{1} (loopback target, so it survives a reboot)" -f $ip, $WslPort)
  Do-Check
}

if ($Show) { Show-Commands; exit 0 }
if ($Push) { exit (Do-Push) }
exit (Do-Check)
