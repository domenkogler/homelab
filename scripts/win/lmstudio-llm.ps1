#Requires -Version 5.1
<#
.SYNOPSIS
    The applier for the laptop's LM Studio serving leg (HD-474) — the Windows counterpart of
    IaC/ansible/playbooks/roles/llm/tasks/90-llm-switch-model.yml, whose shape is copied on purpose:
    the catalogue decides, the applier checks the ceiling and then boots.

.DESCRIPTION
    The laptop is not in the Ansible inventory (§5 targets the Docker fleet), LM Studio runs on
    Windows, and its engine state is per-user — so scripts/laptop-llm/profiles.yml is the SSOT,
    scripts/laptop-llm.py is the brain (budget, gate, probes; stdlib only) and this script is the
    thin Windows arm that MOVES state: settings, presets, load, unload, verify.

    It hardcodes NOTHING: no profile name, no path, no model identifier, no context length, no port.
    Every value comes from the driver as JSON.

.EXAMPLE
    powershell -File scripts\win\lmstudio-llm.ps1 init
    powershell -File scripts\win\lmstudio-llm.ps1 switch -Profile agent-unified
    powershell -File scripts\win\lmstudio-llm.ps1 status
    powershell -File scripts\win\lmstudio-llm.ps1 verify

.NOTES
    Run from an ordinary (NON-elevated) shell. LM Studio's store, presets and server all live in this
    user's profile and an elevated shell resolves a different one — the classic "it re-downloaded
    everything" trap. Model bytes live on D:, so a Windows reinstall cannot orphan them.
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [ValidateSet('init','switch','status','verify','presets','gate')]
    [string]$Command = 'status',
    [string]$Profile = '',
    [switch]$AllowUncertified
)

$ErrorActionPreference = 'Strict'
Set-StrictMode -Version 2.0
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Driver   = Join-Path $RepoRoot 'scripts\laptop-llm.py'

function Invoke-Catalogue {
    param([string[]]$DriverArgs)
    # The repo's python normally lives in WSL on this box. Try a native python first, then WSL, and
    # report which one answered — a Windows python without pyyaml and a WSL python fail differently,
    # and "python3 not found" from the wrong one wastes an afternoon.
    foreach ($cand in @(@(,'python3'), @(,'python'), @('wsl','python3'))) {
        $exe = $cand[0]
        if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { continue }
        $pre = @(); if ($cand.Count -gt 1) { $pre = $cand[1..($cand.Count-1)] }
        $argv = @($pre + $Driver + $DriverArgs)
        $out = & $exe @argv 2>&1
        $txt = ($out | Out-String)
        if ($LASTEXITCODE -ne 0 -and $txt -match "No such file or directory|can't open file") { continue }
        if ($LASTEXITCODE -ne 0) { throw "laptop-llm.py $($DriverArgs -join ' ') exited $LASTEXITCODE :`n$txt" }
        return $txt
    }
    throw "No usable python3 / python / wsl python3. The catalogue driver is Python."
}

function Get-Catalogue {
    # One parse of the presets document: profile → engine settings, paths included.
    (Invoke-Catalogue @('presets')) | ConvertFrom-Json
}

function Get-ActiveProfileName {
    $line = (Invoke-Catalogue @('matrix')) -split "`n" | Where-Object { $_ -match '^\*\s+([a-z0-9\-]+)' } |
            Select-Object -First 1
    if (-not $line) { throw 'Could not read the active profile from laptop-llm.py matrix' }
    return ([regex]::Match($line, '^\*\s+([a-z0-9\-]+)')).Groups[1].Value
}

function Get-ProfileConfig {
    param([string]$Name)
    $all = Get-Catalogue
    if (-not $Name) { $Name = Get-ActiveProfileName }
    $p = $all.$Name
    if (-not $p) { throw "profile '$Name' is not in the catalogue (valid: $($all.PSObject.Properties.Name -join ', '))" }
    Add-Member -InputObject $p -NotePropertyName name -NotePropertyValue $Name -Force
    return $p
}

function Get-Lms {
    $l = [Environment]::ExpandEnvironmentVariables((Get-SettingsDoc).lms)
    if (-not (Test-Path $l)) {
        throw "lms.exe not at $l — run LM Studio's 'Install lms CLI command' once, or correct runtime.lms in profiles.yml."
    }
    return $l
}

function Get-Api { (Invoke-Catalogue @('baseurl')).Trim() }

function Assert-Gate {
    # Same policy as the spark playbook: a profile the gate rejects never reaches the engine. The
    # escape hatch is --AllowUncertified because on THIS box everything is uncertified until the
    # probes have run — and the gate still has to say out loud what is unproven before we boot it.
    param([switch]$Bypass)
    try { Write-Host (Invoke-Catalogue @('gate')) }
    catch {
        if (-not $Bypass) { throw "$($_.Exception.Message)`n(override with -AllowUncertified; the message is the point — read it)" }
        Write-Warning "gate refused; continuing on -AllowUncertified"
    }
}

function Assert-Library {
    param($Profile)
    if (-not $Profile.mmproj) { return }
    if (-not (Test-Path $Profile.mmproj)) {
        throw "vision projector not in the library: $($Profile.mmproj)`nFetch it once (LM Studio search → unsloth/Qwen3.6-35B-A3B-MTP-GGUF, mmproj-BF16.gguf) and re-run. This script never downloads ~20 GB as a side effect of switching profiles."
    }
}

function Get-SettingsDoc {
    # Paths and the owned key set come from the driver: one expander for %USERPROFILE% and
    # {host.model_library}, because two expanders is two chances to disagree about where the library
    # is — and the app gets blamed for "re-downloading" when they do.
    (Invoke-Catalogue @('settings')) | ConvertFrom-Json
}

function Set-Settings {
    <# Own exactly the keys the catalogue names, leave everything else alone. settings.json holds
       hfDownloadToken/useHFProxy, which is why the FILE is not git-tracked and why this merges
       instead of replacing. Backup first: LM Studio rewrites this file while it runs. #>
    $doc = Get-SettingsDoc
    $settingsPath = [Environment]::ExpandEnvironmentVariables($doc.settings)
    if (-not (Test-Path $settingsPath)) { throw "LM Studio settings not at $settingsPath" }
    $bak = "$settingsPath.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item $settingsPath $bak
    $j = Get-Content $settingsPath -Raw | ConvertFrom-Json
    foreach ($prop in $doc.keys.PSObject.Properties) {
        if ($null -eq $prop.Value) { continue }   # null = deliberately left to the per-model preset
        $cur = $j.($prop.Name)
        if ($cur -ne $prop.Value) {
            Write-Host "settings: $($prop.Name) = '$cur' -> '$($prop.Value)'"
            $j.($prop.Name) = $prop.Value
        }
    }
    $j | ConvertTo-Json -Depth 12 | Set-Content $settingsPath -Encoding UTF8
    Write-Host "settings written (backup: $bak). NOT committed: settings.json carries an HF token (§6)."
}

function Set-Presets {
    <# LM Studio has no Modelfile; per-model load settings are JSON under config-presets\ (path from
       the catalogue). Generating them is what makes the engine configuration reviewable in a PR
       instead of living in an app directory (§15: config that exists only here does not exist). #>
    $doc = Get-SettingsDoc
    $dir = [Environment]::ExpandEnvironmentVariables($doc.presets_dir)
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    foreach ($prop in (Get-Catalogue).PSObject.Properties) {
        $p = $prop.Value
        $body = [ordered]@{
            contextLength       = $p.contextLength
            kvCacheType         = $p.kvCacheType
            flashAttention      = [bool]$p.flashAttention
            gpuOffloadLayers    = 'max'
            speculativeDecoding = [bool]$p.speculativeDecodingMTP
            evalBatchSize       = $p.evalBatchSize
            temperature         = $p.temperature
            topP                = $p.topP
            topK                = $p.topK
        }
        $f = Join-Path $dir "homelab-$($prop.Name).json"
        $body | ConvertTo-Json | Set-Content $f -Encoding UTF8
        $warn = ''
        if ($p._warning) { $warn = "  ⚠ $($p._warning)" }
        Write-Host "preset: homelab-$($prop.Name).json (ctx $($p.contextLength), kv $($p.kvCacheType), FA $([bool]$p.flashAttention), MTP $([bool]$p.speculativeDecodingMTP))$warn"
    }
    Write-Host "Restart LM Studio to list new presets. settings.json itself stays out of git."
}

switch ($Command) {

  'gate' {
    Write-Host (Invoke-Catalogue @('gate'))
    Write-Host (Invoke-Catalogue @('gate','--self-test'))
  }

  'presets' { Set-Presets }

  'init' {
    Write-Host "== laptop serving leg init (catalogue is the SSOT) =="
    $p = Get-ProfileConfig -Name $Profile
    Set-Settings
    Set-Presets
    Assert-Library -Profile $p
    # Mirrored networking, not a NAT address: it is the difference between the pi/Continue contract
    # declaring 127.0.0.1:1234 (stable) and declaring today's gateway IP (moves when the NAT range
    # does). Read from the driver, which PROBES rather than assuming.
    $base = Get-Api
    Write-Host "API base the clients will use: $base"
    if ($base -notmatch '127\.0\.0\.1') {
        Write-Warning @"
Not on loopback — WSL is in Nat mode, so the spec's 127.0.0.1 does not reach Windows.
Fix (one-time, owner): add to /etc/wsl.conf inside the distro
    [network]
    networkingMode=mirrored
then 'wsl --shutdown' and reopen. Until then pi/Continue on the Linux seat cannot use the leg.
"@
    }
    # No firewall rule is created on purpose: the contract is a loopback listener. Opening :1234 to
    # the LAN is a decision with a cost (an unauthenticated inference endpoint on your wifi), so it
    # stays a decision and not a side effect of running an installer.
    $lms = Get-Lms
    Write-Host "`nlms: $(& $lms version 2>&1 | Select-Object -Last 1)"
    Write-Host "⚠ Record that version in profiles.yml runtime.version — the gate refuses to certify an unpinned engine (§7)."
    Write-Host "`nNext: run the probes from WSL (probe-health, probe-tools, probe-vision, probe-fim, probe-ctx), then"
    Write-Host "      record tok/s + the load log's KV line in docs/hardware-workstation.md, then set certified: true."
  }

  'switch' {
    $p = Get-ProfileConfig -Name $Profile
    Assert-Gate -Bypass:$AllowUncertified
    Assert-Library -Profile $p
    $lms = Get-Lms
    Write-Host "== switch to '$($p.name)' — engine ceiling and window come from the catalogue =="
    # Unload FIRST. Two resident models on one iGPU carve is the documented amdgpu failure mode
    # (docs/hardware-workstation.md §Memory & residency: two fit, three leak slots) and LM Studio
    # does not guarantee eviction order if you load-then-unload.
    Write-Host "unload --all"; & $lms unload --all 2>&1 | ForEach-Object { "  $_" }
    $argv = @('load', $p.identifier, '--pub', '--gpu', 'max', '--context', $p.contextLength)
    Write-Host "load: $($argv -join ' ')"
    & $lms @argv 2>&1 | ForEach-Object { "  $_" }
    if ($LASTEXITCODE -ne 0) { throw "lms load failed (exit $LASTEXITCODE)" }
    & $lms server start 2>&1 | ForEach-Object { "  $_" }
    Write-Host "`nverify with: powershell -File scripts\win\lmstudio-llm.ps1 verify"
  }

  'status' {
    $lms = Get-Lms
    Write-Host "== lms ls =="; & $lms ls 2>&1 | ForEach-Object { "  $_" }
    $base = (Get-Api) -replace '/v1$',''
    try {
        $m = Invoke-RestMethod -Uri "$base/v1/models" -TimeoutSec 5
        Write-Host "`n== served models ($base) =="
        $m.data | ForEach-Object { "  $($_.id)" }
    } catch { Write-Warning "server not reachable at $base — start it (LM Studio Local Server, or 'lms server start')" }
  }

  'verify' {
    $p = Get-ProfileConfig -Name $Profile
    Write-Host "profile: $($p.name)  expects ctx $($p.contextLength) kv $($p.kvCacheType) FA $([bool]$p.flashAttention) MTP $([bool]$p.speculativeDecodingMTP)"
    Write-Host (Invoke-Catalogue @('budget','--profile',$p.name))
    # The load-time clamp is what actually bounds the window, so verify it and never trust the
    # number in the spec — spark's probe found 20 468 usable against a nominal 32 768 (HD-376).
    Write-Host (Invoke-Catalogue @('probe-client'))
    Write-Host @"

Still to prove on this box (each one is a profile field, not a hope):
  probe-health   the seat can reach the server at all
  probe-ctx      the real usable window at load-time contextLength
  probe-tools    capabilities: [tool] — 'tool_probe: passed'
  probe-vision   input: [image] + WHERE the projector ran — 'vision_probe: passed'
  probe-fim      whether Coder-3B-Instruct really does FIM (docs:64 says no, Qwen's card says yes)
  probe-speed    tok/s + TTFT at the agent's real prompt shape (HD-401 gate 3)
"@
  }
}
