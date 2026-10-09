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
    powershell -File scripts\win\lmstudio-llm.ps1 switch -Profile fim-coder-3b
    powershell -File scripts\win\lmstudio-llm.ps1 switch -Profile vision-qwen3vl-30b
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

# 'Strict' is not an ActionPreference value (it belongs to Set-StrictMode below): as committed this
# line threw on EVERY invocation of the applier (HD-474, measured 2026-09-29). 'Stop' is not the
# repair either — measured on this box `lms` writes stdout only when it succeeds (version 530 B
# out/0 B err, ls 1222 B/0 B) and stderr + rc!=0 when it fails (nosuchcmd 0 B/35 B/rc 1), and this
# script pipes every lms call with 2>&1: under 'Stop' the first failing `lms load` would raise a
# NativeCommandError INSTEAD of reaching the script's own explicit throw, i.e. the diagnostic the
# script was written to print would never print. Strictness here comes from Set-StrictMode plus
# those explicit throws, so 'Continue' (the default) is the honest value.
$ErrorActionPreference = 'Continue'
Set-StrictMode -Version 2.0
# The driver reads a UTF-8 catalogue and prints ⚠/→/—; a Windows PowerShell child inherits the
# cp1252 console codec and died with UnicodeDecodeError before the gate could speak (HD-474,
# measured 2026-09-29). The driver now forces UTF-8 itself; this is the same belt on the child env.
$env:PYTHONUTF8 = '1'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Driver   = Join-Path $RepoRoot 'scripts\laptop-llm.py'

function Invoke-Catalogue {
    param([string[]]$DriverArgs, [switch]$AllowFail)
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
        # -AllowFail is for the calls whose NONZERO EXIT IS THE PRODUCT. `gate` exists to print why
        # a profile is refused; wrapping that in a PowerShell RuntimeException buried the very text
        # the operator came to read, and stopped `gate` ever reaching its own --self-test (measured
        # 2026-09-30 while the agent leg was still uncertified).
        if ($LASTEXITCODE -ne 0 -and -not $AllowFail) { throw "laptop-llm.py $($DriverArgs -join ' ') exited $LASTEXITCODE :`n$txt" }
        if ($LASTEXITCODE -ne 0) { return ($txt.TrimEnd() + "`n[catalogue exited $LASTEXITCODE — that is a result, not a crash]") }
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
        # StrictMode 2.0 throws on a property that is not there, and _warning is emitted only for
        # the rows that need it — so ask the object before reading it.
        $warn = ''
        if ($p.PSObject.Properties.Name -contains '_warning') { $warn = "  ⚠ $($p._warning)" }
        Write-Host "preset: homelab-$($prop.Name).json (ctx $($p.contextLength), kv $($p.kvCacheType), FA $([bool]$p.flashAttention), MTP $([bool]$p.speculativeDecodingMTP))$warn"
    }
    Write-Host "Restart LM Studio to list new presets. settings.json itself stays out of git."
}

switch ($Command) {

  'gate' {
    # Both lines print even when the gate is red — see Invoke-Catalogue -AllowFail.
    Write-Host (Invoke-Catalogue @('gate') -AllowFail)
    Write-Host (Invoke-Catalogue @('gate','--self-test') -AllowFail)
  }

  'presets' { Set-Presets }

  'init' {
    Write-Host "== laptop serving leg init (catalogue is the SSOT) =="
    $p = Get-ProfileConfig -Name $Profile
    Set-Settings
    Set-Presets
    Assert-Library -Profile $p
    # The seat decision (owner, 2026-09-29): local models are served to pi.dev running ON Win11.
    # /etc/wsl.conf stays exactly as it is — WSL2 is configured the way it is for reasons that
    # outlive this leg, and the loopback contract does not need mirrored mode once the client is
    # native. So this reports the seat rather than asking you to reconfigure the guest.
    $base = Get-Api
    Write-Host "API base the clients will use: $base"
    if ($base -notmatch '127\.0\.0\.1') {
        Write-Warning @"
The driver could not answer on loopback from here, so it fell back to the discovered WSL gateway. That is fine for DEBUGGING from the Linux guest; it is NOT the contract. models-spec.yml marks this provider native_only, so pi on Win11 uses 127.0.0.1:1234 and the WSL render omits it on purpose. Do not reconfigure /etc/wsl.conf to make a WSL probe pass.
"@
    }
    Write-Host "seat: Windows-native pi.dev is the contracted client. pi.dev inside WSL does not get
    this provider (models-spec.yml: native_only) — with networkingMode=Nat, 127.0.0.1 there is the guest."
    # No firewall rule is created on purpose: the contract is a loopback listener. Opening :1234 to
    # the LAN is a decision with a cost (an unauthenticated inference endpoint on your wifi), so it
    # stays a decision and not a side effect of running an installer.
    $lms = Get-Lms
    Write-Host "`nlms: $(& $lms version 2>&1 | Select-Object -Last 1)"
    Write-Host "⚠ Record that version in profiles.yml runtime.version — the gate refuses to certify an unpinned engine (§7)."
    Write-Host "`nNext: run the probes against the loaded profile - probe-health, probe-tools, probe-vision,"
    Write-Host "      probe-fim, probe-ctx, probe-speed (see"
    Write-Host "      reports/hd474-laptop-leg/raw/88_certify.py for a driver that runs them in order), record"
    Write-Host "      tok/s + the PDH dedicated-memory figure, then set certified: true in"
    Write-Host "      scripts/laptop-llm/profiles.yml and re-run 'gate'."
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

    # The load line, verified against `lms load --help` on 0.4.25 (HD-474, 2026-09-30). The previous
    # draft of this line read `--pub --context <N>`, and NEITHER flag exists in 0.4.25 - `switch`
    # could never have worked. The whole accepted set is:
    #   --gpu --identifier -c -y --parallel --ttl --estimate-only --speculative-*
    # so: context is `-c`, there is no `--pub` (publishing is the server's job), and `-y` is
    # MANDATORY because an unmatched or ambiguous key otherwise hangs on an interactive TTY picker -
    # which in an unattended run is an hour of nothing, not an error. `--identifier <servedId>` is
    # what makes the client contract true: /v1/models must list exactly the id models-spec.yml names.
    # There is deliberately NO mmproj flag: `lms load` has no vision switch. The projector attaches
    # because the mmproj-*.gguf sits beside the weights (asserted by Assert-Library above), which is
    # also why the text-only agent leg loads a folder WITHOUT that file instead of a flag combo.
    if (-not $p.loadable) { throw "profile '$($p.name)' is not loadable: $($p._warning)" }
    $argv = @('load', $p.identifier, '--gpu', 'max', '-c', $p.contextLength,
              '--identifier', $p.servedId, '-y')
    if ($p.parallel) { $argv += @('--parallel', $p.parallel) }
    Write-Host "load: $($argv -join ' ')"
    & $lms @argv 2>&1 | ForEach-Object { "  $_" }
    if ($LASTEXITCODE -ne 0) { throw "lms load failed (exit $LASTEXITCODE)" }
    & $lms server start 2>&1 | ForEach-Object { "  $_" }
    # Prove the thing the client is about to rely on (CONVENTIONS §6: prove, do not reason).
    $ps = & $lms ps 2>&1 | Out-String
    if ($ps -notmatch [regex]::Escape($p.servedId)) {
        throw "loaded but the server does not list '$($p.servedId)' - models-spec.yml names that id, " +
              "so pi would 400. `lms ps` said:`n$ps"
    }
    Write-Host ("serving id: " + (($ps -split "`n" | Where-Object { $_ -match $p.servedId }) -join '').Trim())
    Write-Host "`nverify with: powershell -File scripts\win\lmstudio-llm.ps1 verify"
  }

  'status' {
    $lms = Get-Lms
    Write-Host "== lms ls =="; & $lms ls 2>&1 | ForEach-Object { "  $_" }
    Write-Host "`n== lms ps =="; & $lms ps 2>&1 | ForEach-Object { "  $_" }
    $base = (Get-Api) -replace '/v1$',''
    try {
        $m = Invoke-RestMethod -Uri "$base/v1/models" -TimeoutSec 5
        Write-Host "`n== served models ($base) =="
        $m.data | ForEach-Object { "  $($_.id)" }
        Write-Host "  (JIT loading is OFF on this install, so this list is exactly the RESIDENT set -"
        Write-Host "   a model that is indexed but not loaded is invisible to the client by design.)"
    } catch { Write-Warning "server not reachable at $base — start it (LM Studio Local Server, or 'lms server start')" }
  }

  'verify' {
    $p = Get-ProfileConfig -Name $Profile
    Write-Host "profile: $($p.name)  expects ctx $($p.contextLength) kv $($p.kvCacheType) FA $([bool]$p.flashAttention) MTP $([bool]$p.speculativeDecodingMTP) serving-as $($p.servedId)"
    Write-Host (Invoke-Catalogue @('budget','--profile',$p.name))
    # The load-time clamp is what actually bounds the window, so verify it and never trust the
    # number in the spec — spark's probe found 20 468 usable against a nominal 32 768 (HD-376).
    Write-Host (Invoke-Catalogue @('probe-client') -AllowFail)
    Write-Host @"

What this profile still owes is exactly what 'gate' refuses - it reads tool_probe, vision_probe,
fim_probe and certified out of the catalogue, so 'gate' cannot go stale the way a hardcoded list
here did (this block used to claim probe-fim was an open question after it had passed).

    python scripts\laptop-llm.py gate          # the debt, in the catalogue's own words
    python scripts\laptop-llm.py probe-speed --model $($p.servedId) --ttft --prompt-file ...
                                               # the tok/s claim is a DOC number, not a gate
                                               # invariant (HD-401 gate 3), so measure it anyway
"@
  }
}
