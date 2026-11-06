<#
.SYNOPSIS
  The Windows half of the Paseo coding seats: the two firewall rules and the one portproxy that
  let a phone reach the laptop seats across the tailnet, and nothing else.
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

  ORDER THAT MATTERS: the WSL daemon must already answer on 0.0.0.0:6768 (its own sign-in carrier is
  scripts/harness/win/wsl-seat-autostart.vbs) BEFORE the portproxy is useful - a proxy to a closed loopback
  forwards nothing and reads as a broken phone leg.
.PARAMETER Check
  Report only (default). Reads what it can without elevation and prints the exact elevated commands
  for whatever it cannot read. Unelevated, Get-NetFirewallRule and netsh portproxy show are both
  blocked, and a check that cannot read is reported as such - never as "absent". Where the table says the
  proxy is present it then PROBES the socket, because the table is configuration and only a connect proves a
  listener: an entry whose listen address was absent when IP Helper read the config stays unbound and reads
  present forever.
.PARAMETER Push
  Apply the three artifacts. Requires an elevated shell; without one it changes NOTHING and prints
  the commands it would have run.
.PARAMETER Show
  Print the command list and nothing else - the artifact the owner needs to run the parked leg.
.PARAMETER SelfTest
  Grade the readers (scope comparison, portproxy table, the door verdict that joins the table to the probe) against planted shapes, with no firewall,
  no netsh and no tailscale. What the -Push verdict is built from, so the verdict is proved apart from
  the machine it describes.
#>
[CmdletBinding()]
param(
  [switch]$Check,
  [switch]$Push,
  [switch]$Show,
  [switch]$SelfTest
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

function Test-TailnetScope {
  param([string]$Remote)
  # One /10 is written THREE ways by the tools that read a rule: netsh prints `100.64.0.0/10`,
  # Get-NetFirewallAddressFilter prints `100.64.0.0/255.192.0.0`, and a range form exists too. A verdict
  # that compares text therefore inherits whichever form the cmdlet chose, and a check that can never
  # pass is a check that gets scrolled past — the failure this function replaces was exactly that: a
  # correctly scoped rule reported as OPEN TO THE LAN. Normalize, then judge the network.
  if ([string]::IsNullOrWhiteSpace($Remote)) { return $false }
  foreach ($part in ($Remote -split '[,;]')) {
    $t = $part.Trim()
    if ($t -eq '') { continue }
    if ($t -match '^(\d{1,3}(?:\.\d{1,3}){3})\s*/\s*(\d{1,2}|\d{1,3}(?:\.\d{1,3}){3})$') {
      # Read BOTH groups into locals first: `-match` overwrites $Matches, so a second -match used to
      # classify the suffix would erase the very group it was deciding about (measured: the /10 form
      # fell to the mask branch and came back scoped-wrong while the mask form passed — the split that
      # proved the reader, not the rule, was the defect).
      $ip = $Matches[1]; $suffix = $Matches[2]
      $o = ([IPAddress]$ip).GetAddressBytes()
      $bits = 0
      if ($suffix.Contains('.')) {
        foreach ($b in ([IPAddress]$suffix).GetAddressBytes()) {
          for ($i = 0; $i -lt 8; $i++) { $bits += (($b -shr $i) -band 1) }
        }
      } else { $bits = [int]$suffix }
      # 100.64.0.0/10 is 100.64.0.0 – 100.127.255.255: the second octet masked with 192 must read 64.
      if ($bits -ne 10 -or $o[0] -ne 100 -or (($o[1] -band 192) -ne 64)) { return $false }
      continue
    }
    if ($t -match '^100\.64\.0\.0\s*-\s*100\.127\.255\.255$') { continue }
    return $false   # Any, an empty-list word, an FQDN list: an unknown shape never passes as scoped
  }
  return $true
}

function Get-PortProxyRows {
  param([string]$Text)
  # `netsh interface portproxy show` prints a COLUMN table and never an `ip:port` token, so a substring
  # match on "100.64.0.2:6768" cannot hit even when the entry is there — the verifier could not see what
  # the push had just written, and a correct box read as broken forever. Read the row.
  $out = @()
  foreach ($line in ($Text -split "`r?`n")) {
    if ($line -match '^\s*(\d{1,3}(?:\.\d{1,3}){3})\s+(\d+)\s+(\d{1,3}(?:\.\d{1,3}){3})\s+(\d+)\s*$') {
      $out += [pscustomobject]@{ listen = $Matches[1]; lport = [int]$Matches[2]
                                 connect = $Matches[3]; cport = [int]$Matches[4] }
    }
  }
  $out
}

function Test-PortProxy {
  param($Rows, [string]$Listen, [int]$Port)
  $mine = @($Rows | Where-Object { $_.lport -eq $Port })
  if ($mine.Count -eq 0) { return [pscustomobject]@{ state = 'absent'; detail = "no entry listens on :$Port" } }
  if ($mine.Count -gt 1) { return [pscustomobject]@{ state = 'ambiguous'; detail = "$($mine.Count) entries listen on :$Port" } }
  if ($mine[0].listen -ne $Listen) {
    return [pscustomobject]@{ state = 'stale listen address'; detail = "listens on $($mine[0].listen), this box is $Listen" }
  }
  if ($mine[0].connect -ne '127.0.0.1' -or $mine[0].cport -ne $Port) {
    return [pscustomobject]@{ state = 'wrong target'; detail = "forwards to $($mine[0].connect):$($mine[0].cport), the target must be 127.0.0.1:$Port" }
  }
  [pscustomobject]@{ state = 'present'; detail = "$Listen -> 127.0.0.1:$Port" }
}

function Test-DoorVerdict {
  param([string]$Table, [bool]$Bound)
  # "It is in the table" and "it answered a connect" are two facts and the verdict is their conjunction: a
  # proxy entry is only a path while something is bound to the listen address, and an unbound one has no
  # word of its own in the table. Only a present entry is worth probing; every other state stands alone.
  if ($Table -ne 'present') { return $Table }
  if ($Bound) { return 'listening' }
  return 'configured but not listening'
}

function Test-TcpAnswer {
  param([string]$Address, [int]$Port, [int]$TimeoutMs = 2000)
  # Ask the listener, not the registry. From this box, to that address:port, with a bounded wait so a
  # dropped SYN reports in two seconds instead of hanging the fan-out.
  $c = New-Object Net.Sockets.TcpClient
  try {
    $r = $c.BeginConnect($Address, $Port, $null, $null)
    if (-not $r.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
    # EndConnect is where a refusal surfaces: WaitOne only says SOMETHING answered the handshake.
    $c.EndConnect($r)
    return $c.Connected
  } catch {
    return $false
  } finally {
    $c.Close()
  }
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
    $bad = 0
    $unreadable = $false
    foreach ($r in $st.rules) {
      if (-not $r.present) { Write-Host ("rule      : {0} - ABSENT" -f $r.name); $bad++; continue }
      $ok = Test-TailnetScope -Remote ([string]$r.remote)
      Write-Host ("rule      : {0} - enabled={1} port={2} remote={3} action={4}{5}" -f `
        $r.name, $r.present, $r.port, $r.remote, $r.action, $(if ($ok) { '' } else { '  NEVER remote is not exactly 100.64.0.0/10 - this rule reaches past the tailnet' }))
      if (-not $ok) { $bad++ }
    }
    if ($st.tailnetIp) {
      $v = Test-PortProxy -Rows (Get-PortProxyRows -Text $st.proxy) -Listen $st.tailnetIp -Port $WslPort
      $bound = $false
      if ($v.state -eq 'present') { $bound = Test-TcpAnswer -Address $st.tailnetIp -Port $WslPort }
      $verdict = Test-DoorVerdict -Table $v.state -Bound $bound
      if ($verdict -eq 'listening') {
        Write-Host ("portproxy : {0} - a socket answers there (the seat behind it is the 401 read)" -f $v.detail)
      } elseif ($verdict -eq 'configured but not listening') {
        Write-Host ("portproxy : {0} - NEVER configured but NOT LISTENING: the entry is in the table" -f $v.detail)
        Write-Host ("            and no socket is bound to {0}:{1}, so no peer gets through. Re-run -Push" -f $st.tailnetIp, $WslPort)
        Write-Host ("            (delete then add re-binds it) and read netstat -an | findstr {0}:{1} as the verdict." -f $st.tailnetIp, $WslPort)
        $bad++
      }
      else { Write-Host ("portproxy : {0} - NEVER {1}" -f $v.state, $v.detail); $bad++ }
    } else {
      # No address to probe is not a pass. tailscale answering nothing is the unreadable case, and an
      # unreadable leg owes the fan-out the same rc 2 as a rule this shell could not list.
      Write-Host 'portproxy : UNVERIFIED - tailscale answered with no 100.64/10 address, so there is no listen'
      Write-Host '            address to probe. That is an unreadable leg, never an absent one.'
      $unreadable = $true
    }
  } else { foreach ($n in $st.notes) { Write-Host "note      : $n" } }
  # The command list is the artifact for a leg that is NOT yet done; reprinting it under a box that
  # just verified is how a correct state keeps looking unfinished.
  if (-not $st.admin -or $bad -gt 0) { Write-Host ''; Show-Commands }
  # Exit codes the fan-out understands: 0 everything owed is true, 1 a rule is off-scope/absent or the
  # proxy is not there or not bound, 2 this shell could not read the state it was asked about.
  if (-not $st.admin) { return 2 }
  if ($bad -gt 0) { return 1 }
  if ($unreadable) { return 2 }
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
              Description = 'Homelab: Paseo coding seat, tailnet-only (100.64.0.0/10).' }
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
  return (Do-Check)
}

function Do-SelfTest {
  # The verdict is only worth what its readers are worth, and no reader here can be graded against a live
  # firewall. Every shape below is one the tools really print.
  $fail = 0
  $scope = @(
    @('100.64.0.0/10',            $true,  'netsh form'),
    @('100.64.0.0/255.192.0.0',   $true,  'Get-NetFirewallAddressFilter form of the SAME /10'),
    @('100.64.0.0-100.127.255.255', $true, 'range form'),
    @('Any',                      $false, 'every source'),
    @('',                         $false, 'unread / empty'),
    @('100.64.0.0/255.255.0.0',   $false, 'a /16: wider than the tailnet'),
    @('10.10.1.0/255.255.255.0',  $false, 'the LAN'),
    @('0.0.0.0/0',                $false, 'the world'),
    @('100.64.0.0/10,8.8.8.8',    $false, 'the tailnet plus a second source'),
    @('192.168.1.0-192.168.1.255', $false, 'a LAN range')
  )
  foreach ($c in $scope) {
    $got = Test-TailnetScope -Remote $c[0]
    if ($got -ne $c[1]) { Write-Host ("NOT CAUGHT scope {0} ({1}): got {2}" -f $c[0], $c[2], $got); $fail++ }
  }
  $tbl = @"

Listen on ipv4:             Connect to ipv4:

Address         Port        Address         Port
--------------- ----------  --------------- ----------
100.64.0.2      6768        127.0.0.1       6768
"@
  $cases = @(
    @((Get-PortProxyRows -Text $tbl), '100.64.0.2', 'present', 'the table a correct box prints'),
    @((Get-PortProxyRows -Text ''),   '100.64.0.2', 'absent',  'no rows at all'),
    @((Get-PortProxyRows -Text ($tbl -replace '100\.64\.0\.2', '100.64.9.9')), '100.64.0.2', 'stale listen address', 'a proxy left from an old tailnet address'),
    @((Get-PortProxyRows -Text ($tbl -replace '127\.0\.0\.1', '172.20.40.1')),  '100.64.0.2', 'wrong target', 'an address-targeted proxy that dies at a reboot'),
    @((Get-PortProxyRows -Text ($tbl + "`n" + ($tbl -replace '100\.64\.0\.2', '100.64.9.9'))), '100.64.0.2', 'ambiguous', 'two entries on one port')
  )
  foreach ($c in $cases) {
    $got = (Test-PortProxy -Rows $c[0] -Listen $c[1] -Port 6768).state
    if ($got -ne $c[2]) { Write-Host ("NOT CAUGHT portproxy {0}: got {1}" -f $c[3], $got); $fail++ }
  }
  # The conjunction, graded on planted pairs: the shape that ships a silent dead leg is a table that says
  # 'present' over a socket nobody bound, and a reader that only looks at the table cannot see it.
  $door = @(
    @('present',      $true,  'listening',                    'the entry AND a bound listener'),
    @('present',      $false, 'configured but not listening', 'the silent dead leg: configured, bound by nobody'),
    @('absent',       $false, 'absent',                       'nothing configured, so nothing to probe'),
    @('wrong target', $true,  'wrong target',                 'a bound listener on the wrong target stays wrong'),
    @('ambiguous',    $true,  'ambiguous',                    'two entries on one port, whatever the probe says')
  )
  foreach ($d in $door) {
    $got = Test-DoorVerdict -Table $d[0] -Bound $d[1]
    if ($got -ne $d[2]) { Write-Host ("NOT CAUGHT door verdict {0}: got {1}" -f $d[3], $got); $fail++ }
  }
  # Wiring, not only readers: a reader nobody calls can never fail, so ask this file's own Check body
  # whether it actually reaches both halves. Deleting either call from Do-Check reddens this arm.
  $src = Get-Content -Raw -LiteralPath $PSCommandPath
  $body = ((($src -split 'function Do-Check')[1]) -split 'function Do-Push')[0]
  foreach ($call in @('Test-DoorVerdict', 'Test-TcpAnswer')) {
    if ($body -notmatch $call) { Write-Host ("NOT CAUGHT wiring: Do-Check never calls {0}" -f $call); $fail++ }
  }
  if ($body -notmatch 'UNVERIFIED') { Write-Host 'NOT CAUGHT wiring: Do-Check can pass a leg it could not read'; $fail++ }
  if ($fail -gt 0) { Write-Host ("self-test: {0} NOT caught" -f $fail); return 1 }
  Write-Host 'self-test: OK -- the scope reader passes every rendering of 100.64.0.0/10 and fails every wider shape, the portproxy reader parses the netsh table (present, absent, stale listen, wrong target, ambiguous), and the door verdict needs BOTH halves (a present entry over an unbound socket reads configured but not listening) -- so the -Check verdict is the state, not the string form the cmdlet happened to use'
  return 0
}

if ($SelfTest) { exit (Do-SelfTest) }
if ($Show) { Show-Commands; exit 0 }
if ($Push) { exit (Do-Push) }
exit (Do-Check)
