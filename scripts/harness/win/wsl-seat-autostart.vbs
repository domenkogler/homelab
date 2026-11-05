' wsl-seat-autostart.vbs - the `wsl` seat's sign-in carrier: a per-user Startup entry, no elevation.
' Installed at:  %APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\wsl-seat-autostart.vbs
' This file is the source of record: edit it here, then re-copy it to the Startup folder.
'
' WHAT IT DOES, EVERY SIGN-IN: it asks for two daemons on the Debian seat - the Paseo daemon and the
' mcp-server launcher's unit - and neither of them is started twice on top of a live one.
'
' WHY A STARTUP ENTRY AND NOT A UNIT.  A WSL distro does not run until Windows asks for it, and a systemd
' process holds the instance open for no one, so the only carrier that reaches this seat is a Windows act
' that starts the distro and then starts the daemon inside it. `paseo daemon start` leaves its supervisor as
' a child of WSL's `/init`, which is the process shape that keeps the instance alive; a user unit would
' neither start without a login session nor keep the distro up, and at `Linger=no` it ends with the logout.
' Mechanism, the five reads, and the ports map: docs/services-ai.md section 9b-1 and docs/harness-pi-seats.md section 1.
'
' bash -lc IS NOT STYLE.  A bare `wsl.exe ... -- paseo ...` is a non-login exec whose PATH ends with the
' Windows interop PATH, so `paseo` resolves to `...\Volta\bin\paseo` - the win11 CLI, on another home and
' another listener, which is the one daemon the win11 seat forbids starting. Every act below goes through
' `bash -lc`. Prove which binary a form reaches with `wsl.exe -d Debian -u domen -- bash -lc "command -v
' paseo"` before reading a port: a `/mnt/c` answer is the wrong seat's daemon.
'
' THE PROBE RUNS FIRST on the one act that is not a no-op. Any HTTP answer means the port is served: 401 is
' the Paseo auth gate doing its job. A reply either way IS "already running"; silence is the only trigger.
' Both loopbacks are probed because WSL's localhostForwarding is seen on the IPv4 leg on this box and naming
' one address is how a live daemon reads as down - see the mcp-server plane's same rule in
' scripts/harness/seat-mcp-server.sh.
'
' Do not add a variable named err to the Dim line: it shadows the built-in Err object, the probe's
' Err.Number test stops answering, and the start line is never reached.
Dim sh, wsl
Set sh = CreateObject("WScript.Shell")
wsl = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\wsl.exe"

Function Served(url)
  Dim h, ok
  ok = False
  On Error Resume Next
  Set h = CreateObject("WinHttp.WinHttpRequest.5.1")
  h.SetTimeouts 1500, 1500, 1500, 1500
  h.Open "GET", url, False
  h.Send
  If Err.Number = 0 Then ok = True
  On Error GoTo 0
  Set h = Nothing
  Served = ok
End Function

' The Paseo daemon of the `wsl` seat - the port is paseo_ports.wsl, the same number the portproxy dials.
' `paseo daemon start` on a live daemon with live agents is not a no-op, so this act is gated by the probe
' above and by nothing else.
If Not (Served("http://127.0.0.1:6768/api/agents") Or Served("http://localhost:6768/api/agents")) Then
  sh.Run """" & wsl & """ -d Debian -u domen -- bash -lc ""paseo daemon start""", 0, False
End If

' The mcp-server launcher on the same seat: its carrier is the unit scripts/harness/seat-mcp-server.sh
' renders, so the act asks this seat's user manager for it. NO PROBE HERE, and the asymmetry with the block
' above is measured, not stylistic: this laptop's WINDOWS loopback 7777 is held by the win11 seat's
' AmazingMCP.exe, so a Windows-side GET to that port answers 400 whether or not the distro's unit is up -
' a probe that cannot fail is not evidence. `systemctl --user start` on an active unit is a no-op, so the act
' is safe to run at every sign-in; the retry covers a cold distro where the user manager can lose the race
' with the start above.
sh.Run """" & wsl & """ -d Debian -u domen -- bash -lc ""systemctl --user start amazingmcp.service || { sleep 5; systemctl --user start amazingmcp.service; }""", 0, False
