<#
.SYNOPSIS
    token-diet — token optimization stack dashboard (Windows)
.DESCRIPTION
    Shows combined token savings and health across RTK + tilth + Serena.
    Equivalent to the bash token-diet CLI for Windows / PowerShell.
.EXAMPLE
    .\token-diet.ps1 gain
    .\token-diet.ps1 health
    .\token-diet.ps1 route 'search for the function'
#>
param(
    [string]$Command = 'gain',
    [switch]$Version,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$SubArgs
)

if (-not $SubArgs) { $SubArgs = @() }
if ($args -and $args.Count -gt 0) { $SubArgs += $args }

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TD_VERSION = '1.3.6'
if ($Version) { Write-Output "token-diet $script:TD_VERSION"; exit 0 }
$ScriptDir = $PSScriptRoot

# --- Helpers ------------------------------------------------------------------

function Find-Python {
    foreach ($cmd in @('python3', 'python')) {
        if (Get-Command $cmd -ErrorAction SilentlyContinue) { return $cmd }
    }
    return $null
}
$script:Py = Find-Python

function Invoke-Python {
    param([string]$Code, [string[]]$PyArgs = @())
    if (-not $script:Py) { throw 'python3/python not found — required for this command' }
    $tmp = [System.IO.Path]::GetTempFileName() + '.py'
    Set-Content -Path $tmp -Value $Code -Encoding UTF8
    try   { return & $script:Py $tmp @PyArgs 2>&1 }
    finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
}

function Test-Tool([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Format-Tokens([long]$n) {
    if ($n -ge 1000000) { return '{0:0.0}M' -f ($n / 1000000) }
    if ($n -ge 1000)    { return '{0:0.0}K' -f ($n / 1000) }
    return "$n"
}

function Format-Ms([long]$ms) {
    if ($ms -ge 60000) {
        $m = [int]($ms / 60000); $s = [int](($ms % 60000) / 1000)
        return "${m}m ${s}s"
    }
    if ($ms -ge 1000) { return '{0:0.0}s' -f ($ms / 1000) }
    return "${ms}ms"
}

# Use Write-Output so output is captured in tests; colour via Write-Host only for TTY
function Write-Ok  ([string]$Msg) { Write-Host "  [OK] $Msg" -ForegroundColor Green  }
function Write-Miss([string]$Msg) { Write-Host "  [!]  $Msg" -ForegroundColor Yellow }
function Write-Warn([string]$Msg) { Write-Host "  [W]  $Msg" -ForegroundColor Yellow }
function Write-Err ([string]$Msg) { Write-Host "  [X]  $Msg" -ForegroundColor Red    }

function Get-HostsRegistered([string]$Tool) {
    $hosts = @()
    $paths = @(
        @( (Join-Path $env:USERPROFILE '.claude\settings.json'),                        'claude-code'    ),
        @( (Join-Path $env:APPDATA 'Claude\claude_desktop_config.json'),                'claude-desktop' ),
        @( (Join-Path $env:USERPROFILE '.opencode.json'),                               'opencode'       )
    )
    foreach ($pair in $paths) {
        $path, $label = $pair[0], $pair[1]
        if (Test-Path $path) {
            try {
                $cfg = Get-Content $path -Raw | ConvertFrom-Json
                $servers = if ($cfg.PSObject.Properties['mcpServers']) { $cfg.mcpServers } else { $cfg.mcp }
                if ($servers -and $servers.PSObject.Properties.Name -contains $Tool) { $hosts += $label }
            } catch { }
        }
    }
    if ($null -ne (Get-CodexMcpCommand $Tool)) { $hosts += 'codex' }
    if ($hosts.Count -eq 0) { return 'none' }
    return $hosts -join ','
}

# Extract the configured command for [mcp_servers.<tool>] from Codex TOML.
function Get-CodexMcpCommand([string]$Tool) {
    $codexCfg = Join-Path $env:USERPROFILE '.codex\config.toml'
    if (-not (Test-Path $codexCfg)) { return $null }
    $text = Get-Content $codexCfg -Raw -ErrorAction SilentlyContinue
    if (-not $text) { return $null }
    $escaped = [regex]::Escape($Tool)
    $blockMatch = [regex]::Match($text, "(?ms)^\[mcp_servers\.$escaped\]\s*(.*?)(?=^\[|\z)")
    if (-not $blockMatch.Success) { return $null }
    $block = $blockMatch.Groups[1].Value
    if ($block -match '(?m)^command\s*=\s*"([^"]+)"\s*$') { return $Matches[1] }
    if ($block -match "(?m)^command\s*=\s*'([^']+)'\s*`$") { return $Matches[1] }
    return $null
}

function Test-McpCommandExists([string]$CommandValue) {
    if ($CommandValue -match '[/\\]') { return (Test-Path $CommandValue -PathType Leaf) }
    return [bool](Get-Command $CommandValue -ErrorAction SilentlyContinue)
}

function Get-CodexMcpCommandIssue([string]$Tool) {
    $cmd = Get-CodexMcpCommand $Tool
    if (-not $cmd) { return $null }
    if (-not (Test-McpCommandExists $cmd)) { return "Codex $Tool MCP command missing: $cmd" }
    return $null
}

function Get-RtkSummary {
    if (-not (Test-Tool 'rtk')) { return $null }
    try { return (& rtk gain --format json 2>$null | ConvertFrom-Json).summary } catch { return $null }
}

function Get-RtkHistory {
    if (-not (Test-Tool 'rtk')) { return $null }
    try { return & rtk gain --history 2>$null | ConvertFrom-Json } catch { return $null }
}

# --- Commands -----------------------------------------------------------------

function Invoke-Gain {
    Write-Output "`n=== token-diet gain ===`n"
    Write-Output 'RTK — command output compression'

    $s = Get-RtkSummary
    if ($s) {
        Write-Output ('  Commands filtered:     {0}' -f $s.total_commands)
        Write-Output ('  Tokens in:             {0}' -f (Format-Tokens $s.total_input))
        Write-Output ('  Tokens saved:          {0}  ({1}%)' -f (Format-Tokens $s.total_saved), [math]::Round($s.avg_savings_pct,1))
        Write-Output ('  Exec time:             {0}' -f (Format-Ms $s.total_time_ms))
        Write-Ok "RTK $(& rtk --version 2>$null) — active"
    } else {
        Write-Miss 'RTK not installed  ->  run: Install.ps1 -RtkOnly'
    }

    Write-Output ''
    Write-Output 'tilth — AST-aware code reading (tree-sitter)'
    if (Test-Tool 'tilth') {
        $tv = & tilth --version 2>$null
        Write-Output "  Version:   $tv"
        Write-Output "  MCP hosts: $(Get-HostsRegistered 'tilth')"
        Write-Ok "tilth $tv — active"
    } else {
        Write-Miss 'tilth not installed  ->  run: Install.ps1 -TilthOnly'
    }

    Write-Output ''
    Write-Output 'Serena — LSP symbol navigation'
    $serenaOk = (Test-Tool 'uvx') -or (Test-Tool 'uv')
    if ($serenaOk) {
        $memDir = Join-Path $env:USERPROFILE '.serena\memories'
        $logDir = Join-Path $env:USERPROFILE '.serena\logs'
        Write-Output "  MCP hosts:    $(Get-HostsRegistered 'serena')"
        Write-Output "  Memories:     $(if (Test-Path $memDir) { @(Get-ChildItem $memDir).Count } else { 0 }) files"
        Write-Output "  Session logs: $(if (Test-Path $logDir) { @(Get-ChildItem $logDir).Count } else { 0 }) days"
        Write-Ok 'Serena — active'
    } else {
        Write-Miss 'Serena not installed  ->  run: Install.ps1 -SerenaOnly'
    }

    $active = ([int][bool]$s) + ([int](Test-Tool 'tilth')) + ([int]$serenaOk)
    Write-Output ''
    Write-Output "  Tools active: $active/3"
    if ($active -eq 3)     { Write-Output "`n  Full stack active. Maximum token savings." }
    elseif ($active -gt 0) { Write-Output "`n  Partial stack — run Install.ps1 to complete setup." }
    else                   { Write-Output "`n  No tools installed — run Install.ps1 to get started." }
    Write-Output ''
}

function Invoke-Version {
    Write-Output "`ntoken-diet stack versions`n"
    if (Test-Tool 'rtk')  { Write-Ok  "RTK    $(& rtk --version 2>$null)" } else { Write-Miss 'RTK    not installed' }
    if (Test-Tool 'tilth'){ Write-Ok  "tilth  $(& tilth --version 2>$null)" } else { Write-Miss 'tilth  not installed' }
    if (Test-Tool 'uvx')  { Write-Ok  "Serena (uvx: $(& uvx --version 2>$null))" }
    elseif (Test-Tool 'uv'){ Write-Ok "Serena (uv: $(& uv --version 2>$null))" }
    else                  { Write-Miss 'Serena not installed' }
    Write-Output ''
}

function Invoke-Verify {
    Write-Output '=== Token Stack Verification ==='
    $allOk = $true
    if (Test-Tool 'rtk')   { Write-Output "  [OK] RTK ........... $(& rtk --version 2>$null)" }
    else                   { Write-Output '  [!]  RTK ........... not installed'; $allOk = $false }
    if (Test-Tool 'tilth') {
        Write-Output "  [OK] tilth ......... $(& tilth --version 2>$null)"
        $tilthIssue = Get-CodexMcpCommandIssue 'tilth'
        if ($tilthIssue) { Write-Output "  [!]  $tilthIssue"; $allOk = $false }
    } else { Write-Output '  [!]  tilth ......... not installed'; $allOk = $false }
    if ((Test-Tool 'uvx') -or (Test-Tool 'uv')) {
        $v = if (Test-Tool 'uvx') { & uvx --version 2>$null } else { & uv --version 2>$null }
        Write-Output "  [OK] Serena (uv) ... $v"
    } else { Write-Output '  [!]  Serena ........ not installed'; $allOk = $false }
    Write-Output ''
    if ($allOk) { Write-Output '  [OK] All tools installed. Token diet active.' }
    else        { Write-Output '  [W]  Some tools or MCP registrations need attention.'; Write-Output ''; exit 1 }
    Write-Output ''
}

function Invoke-Health {
    $issues = 0
    Write-Output "`ntoken-diet health`n"
    if (Test-Tool 'rtk') {
        Write-Ok "RTK $(& rtk --version 2>$null)"
    } else { Write-Miss 'RTK not found'; $issues++ }
    if (Test-Tool 'tilth') {
        Write-Ok "tilth $(& tilth --version 2>$null)  (hosts: $(Get-HostsRegistered 'tilth'))"
        $tilthIssue = Get-CodexMcpCommandIssue 'tilth'
        if ($tilthIssue) { Write-Warn $tilthIssue; $issues++ }
    } else { Write-Miss 'tilth not found'; $issues++ }
    if ((Test-Tool 'uvx') -or (Test-Tool 'uv')) {
        Write-Ok "Serena  (hosts: $(Get-HostsRegistered 'serena'))"
    } else { Write-Miss 'Serena not found  (uvx or uv required)'; $issues++ }
    Write-Output ''
    if ($issues -eq 0) { Write-Output '  All tools healthy'; Write-Output ''; return }
    Write-Output "  $issues issue(s) found — reinstall tools or repair MCP registrations"
    Write-Output ''
    exit 1
}

function Invoke-Dashboard([string[]]$Remaining) {
    if ($Remaining -contains '--help' -or $Remaining -contains '-h' -or $Remaining -contains 'help') {
        Write-Output 'Usage: token-diet.ps1 dashboard [--port N]'
        return
    }
    $dashBin = Join-Path $ScriptDir 'token-diet-dashboard'
    if (-not (Test-Path $dashBin)) { Write-Error 'token-diet-dashboard not found — run: Install.ps1'; exit 1 }
    $py = Find-Python
    if (-not $py) { Write-Error 'python3/python not found'; exit 1 }
    & $py $dashBin @Remaining
}

function Invoke-Service([string[]]$Remaining) {
    $sub      = if ($Remaining.Count -gt 0) { $Remaining[0] } else { 'help' }
    $taskName = 'token-diet-dashboard'
    $logDir   = Join-Path $env:LOCALAPPDATA 'token-diet'
    $logFile  = Join-Path $logDir 'dashboard.log'
    $py       = Find-Python
    $dashBin  = Join-Path $ScriptDir 'token-diet-dashboard'
    if (-not (Test-Path $dashBin)) {
        $dashBin = (Get-Command 'token-diet-dashboard' -ErrorAction SilentlyContinue)?.Source
    }

    switch ($sub) {
        'install' {
            if (-not $py)      { Write-Error 'python3/python not found'; exit 1 }
            if (-not $dashBin) { Write-Error 'token-diet-dashboard not found — run: Install.ps1'; exit 1 }
            New-Item -ItemType Directory -Force -Path $logDir | Out-Null
            # Remove stale task if present
            schtasks /Delete /TN $taskName /F 2>$null | Out-Null
            $action  = "cmd /c `"$py `"$dashBin`" >> `"$logFile`" 2>&1`""
            $trigger = 'ONLOGON'
            schtasks /Create /TN $taskName /TR $action /SC $trigger /RL HIGHEST /F | Out-Null
            schtasks /Run /TN $taskName | Out-Null
            Write-Ok  "Service installed (Windows Task Scheduler) — runs on every login"
            Write-Ok  "Log: $logFile"
            Write-Ok  "Dashboard: http://127.0.0.1:7384"
        }
        'uninstall' {
            schtasks /End  /TN $taskName 2>$null | Out-Null
            schtasks /Delete /TN $taskName /F 2>$null | Out-Null
            Write-Ok "Service removed (Windows Task Scheduler)"
        }
        'start' {
            schtasks /Run /TN $taskName
            Write-Ok "Dashboard started"
        }
        'stop' {
            schtasks /End /TN $taskName
            Write-Ok "Dashboard stopped"
        }
        'status' {
            $info = schtasks /Query /TN $taskName /FO LIST 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "Service registered (Task Scheduler)"
                $info | Select-String 'Status|Last Run|Next Run' | ForEach-Object { Write-Output "  $_" }
                $proc = Get-Process -Name python* -ErrorAction SilentlyContinue |
                        Where-Object { $_.CommandLine -like "*token-diet-dashboard*" }
                if ($proc) { Write-Ok "Running — PID $($proc.Id) — http://127.0.0.1:7384" }
                else       { Write-Warn "Registered but process not found" }
            } else {
                Write-Miss "Not installed — run: token-diet.ps1 service install"
            }
        }
        default {
            $serviceHelp = @'
Usage: token-diet.ps1 service <subcommand>

  install     Register dashboard as a Task Scheduler job (runs on login, restarts on failure)
  uninstall   Remove the scheduled task
  start       Start the dashboard now
  stop        Stop the running dashboard
  status      Show task and process status
'@
            Write-Output $serviceHelp
        }
    }
}

function Invoke-Breakdown([string[]]$Remaining) {
    $limit = 10
    for ($i = 0; $i -lt $Remaining.Count; $i++) {
        if ($Remaining[$i] -eq '--limit' -and ($i + 1) -lt $Remaining.Count) { $limit = [int]$Remaining[$i+1]; $i++ }
    }
    if (-not (Test-Tool 'rtk')) { Write-Output '  [X] RTK not installed — breakdown requires RTK'; exit 1 }
    $hist = Get-RtkHistory
    if (-not $hist -or -not $hist.commands) { Write-Output '  No RTK history yet — run some commands first'; return }
    Write-Output "`n=== token-diet breakdown ===`n"
    Write-Output "Top commands by tokens saved  (limit: $limit)"
    $json = $hist | ConvertTo-Json -Depth 10 -Compress
    $breakdownCode = @'
import json, sys
data  = json.loads(sys.argv[1]); limit = int(sys.argv[2])
cmds  = sorted(data.get("commands",[]), key=lambda c: c.get("total_saved",0), reverse=True)[:limit]
for i,c in enumerate(cmds,1):
    s=c.get("total_saved",0); pct=c.get("avg_pct",0); n=c.get("count",0); inp=c.get("total_input",0)
    sk=f"{s/1000:.1f}K" if s>=1000 else str(s); ik=f"{inp/1000:.1f}K" if inp>=1000 else str(inp)
    print(f"  {i:>2}. {c['cmd'][:34]:<36} {sk:>7} saved  {pct:>5.1f}%  ({n}x, {ik} in)")
'@
    Invoke-Python -Code $breakdownCode -PyArgs @($json, "$limit")
    Write-Output ''
}

function Invoke-Explain([string[]]$Remaining) {
    $target = if ($Remaining.Count -gt 0) { $Remaining[0] } else { '' }
    if (-not $target) { Write-Output 'Usage: token-diet explain <command>'; exit 1 }
    if (-not (Test-Tool 'rtk')) { Write-Output '  [X] RTK not installed'; exit 1 }
    $hist = Get-RtkHistory
    if (-not $hist -or -not $hist.commands) { Write-Output '  No RTK history yet'; exit 1 }
    $json   = $hist | ConvertTo-Json -Depth 10 -Compress
    $explainCode = @'
import json,sys
data=json.loads(sys.argv[1]); target=sys.argv[2]
m=next((c for c in data.get("commands",[]) if c["cmd"]==target),None)
if not m: sys.exit(1)
s=m.get("total_saved",0); inp=m.get("total_input",0); pct=m.get("avg_pct",0); cnt=m.get("count",0)
print(f"cmd={m['cmd']}\ncount={cnt}\ninput={inp}\noutput={inp-s}\nsaved={s}\npct={pct}")
'@
    $result = Invoke-Python -Code $explainCode -PyArgs @($json, $target)
    if (-not $result) { Write-Output "  No data for '$target' — not found in RTK history"; exit 1 }
    $kv = @{}; $result | ForEach-Object { $p=$_ -split '=',2; if($p.Count-eq 2){$kv[$p[0]]=$p[1]} }
    Write-Output "`n=== token-diet explain ===`n"
    Write-Output "$($kv['cmd'])  ($($kv['count']) runs)"
    Write-Output ('  Tokens in:    {0}' -f (Format-Tokens [long]$kv['input']))
    Write-Output ('  Tokens out:   {0}' -f (Format-Tokens [long]$kv['output']))
    Write-Output ('  Tokens saved: {0}  ({1}%)' -f (Format-Tokens [long]$kv['saved']), $kv['pct'])
    Write-Output ''
}

function Invoke-Budget([string[]]$Remaining) {
    $subcmd = if ($Remaining.Count -gt 0) { $Remaining[0] } else { 'status' }
    switch ($subcmd) {
        'init' {
            $isGlobal = $Remaining -contains '--global'
            $target   = if ($isGlobal) { Join-Path $env:USERPROFILE '.token-budget' } else { Join-Path (Get-Location) '.token-budget' }
            if (Test-Path $target) { Write-Output "  .token-budget already exists at $target"; return }
            $baseline = 0L
            $s = Get-RtkSummary; if ($s) { $baseline = [long]$s.total_input }
            @{ warn=1500000; hard=0; installed_at=(Get-Date -Format 'yyyy-MM-dd'); baseline_tokens=$baseline } |
                ConvertTo-Json | Set-Content $target -Encoding UTF8
            $label = if ($isGlobal) { "global $target" } else { $target }
            Write-Output "  [OK] Created $label  (warn: 1.5M, hard: unlimited, baseline: $(Format-Tokens $baseline))"
            $gitignore = Join-Path (Get-Location) '.gitignore'
            if (Test-Path $gitignore) {
                $lines = Get-Content $gitignore
                if ($lines -notcontains '.token-budget') {
                    Add-Content $gitignore "`n.token-budget"
                    Write-Output "  [OK] Added .token-budget to .gitignore"
                }
            } elseif (& git rev-parse --git-dir 2>$null) {
                Set-Content $gitignore '.token-budget' -Encoding UTF8
                Write-Output "  [OK] Created .gitignore with .token-budget"
            }
        }
        'status' {
            $globalBudget = Join-Path $env:USERPROFILE '.token-budget'
            $rtkSummary   = Get-RtkSummary
            if (-not (Test-Path $globalBudget)) {
                $bl = if ($rtkSummary) { [long]$rtkSummary.total_input } else { 0L }
                @{ warn=1500000; hard=0; installed_at=(Get-Date -Format 'yyyy-MM-dd'); baseline_tokens=$bl } |
                    ConvertTo-Json | Set-Content $globalBudget -Encoding UTF8
            }
            # Walk up from cwd to find project override
            $budgetFile = $null
            $dir = (Get-Location).Path; $homeDir = $env:USERPROFILE
            while ($dir -and $dir.StartsWith($homeDir, [StringComparison]::OrdinalIgnoreCase)) {
                $c = Join-Path $dir '.token-budget'
                if (Test-Path $c) { $budgetFile = $c; break }
                $p = Split-Path $dir -Parent
                if ($p -eq $dir) { break }
                $dir = $p
            }
            if (-not $budgetFile) { $budgetFile = $globalBudget }
            $isOverride = ($budgetFile -ne $globalBudget)

            function Show-BudgetSection([string]$file, [string]$label, $summary) {
                $cfg      = Get-Content $file -Raw | ConvertFrom-Json
                $warnT    = [long]$cfg.warn; $hardT = [long]$cfg.hard
                $unlimited = $hardT -eq 0
                $baseline = if ($cfg.PSObject.Properties['baseline_tokens']) { [long]$cfg.baseline_tokens } else { 0L }
                $rawTotal = if ($summary) { [long]$summary.total_input } else { 0L }
                $used     = [Math]::Max(0L, $rawTotal - $baseline)
                $pct      = if (-not $unlimited -and $hardT -gt 0) { [int]($used * 100 / $hardT) } else { 0 }
                Write-Output "`ntoken-diet budget  [$label]  ($file)`n"
                Write-Output ('  Used:      {0}' -f (Format-Tokens $used))
                Write-Output ('  Warn at:   {0}' -f (Format-Tokens $warnT))
                Write-Output ('  Hard stop: {0}' -f $(if ($unlimited) { 'unlimited' } else { Format-Tokens $hardT }))
                Write-Output ('  Remaining: {0}' -f $(if ($unlimited) { 'unlimited' } else { Format-Tokens ($hardT - $used) }))
                if (-not $unlimited) { Write-Output ('  Burn-down: {0}%' -f $pct) }
                Write-Output ''
                if (-not $unlimited -and $used -ge $hardT) { Write-Output "  HARD STOP ($pct%)"; return 3 }
                elseif ($used -ge $warnT)                  { Write-Output "  WARN ($pct%)";      return 2 }
                else                                       { Write-Output '  Budget OK' }
            }

            Show-BudgetSection $budgetFile $(if ($isOverride) { 'project' } else { 'global' }) $rtkSummary
            if ($isOverride -and (Test-Path $globalBudget)) {
                $gc = Get-Content $globalBudget -Raw | ConvertFrom-Json
                $gw = [long]$gc.warn; $gh = [long]$gc.hard
                Write-Output "  global ($globalBudget)"
                Write-Output ('    Warn at:   {0}' -f (Format-Tokens $gw))
                Write-Output ('    Hard stop: {0}' -f $(if ($gh -eq 0) { 'unlimited' } else { Format-Tokens $gh }))
                Write-Output ''
            }
        }
        default { Write-Output 'Usage: token-diet budget <init|status>'; exit 1 }
    }
}

function Invoke-Loops {
    if (-not (Test-Tool 'rtk')) { Write-Output '  [X] RTK not installed — loop detection requires RTK'; exit 1 }
    $hist = Get-RtkHistory
    if (-not $hist) { Write-Output '  No RTK history yet'; return }
    $json  = $hist | ConvertTo-Json -Depth 10 -Compress
    $loopsCode = @'
import json,sys
data=json.loads(sys.argv[1]); t=int(sys.argv[2])
for c in sorted([c for c in data.get("commands",[]) if c.get("count",0)>=t],key=lambda c:c["count"],reverse=True):
    print(f'{c["cmd"]}\t{c["count"]}\t{c.get("total_input",0)-c.get("total_saved",0)}')
'@
    $found = Invoke-Python -Code $loopsCode -PyArgs @($json, '3')
    Write-Output "`n=== token-diet loops ===`n"
    if (-not $found) { Write-Output '  [OK] No loops detected — all commands run < 3 times'; Write-Output ''; return }
    Write-Output 'Repeated commands  (>=3 runs — potential agent loops)'
    $found -split "`n" | Where-Object { $_ } | ForEach-Object {
        $p = $_ -split "`t"
        Write-Output ("  [X]  {0}  — {1}x  (~{2} tokens lost)" -f $p[0], $p[1], (Format-Tokens [long]$p[2]))
    }
    Write-Output ''
    Write-Output '  Tip: instruct your agent to cache results or use tilth for repeated reads'
    Write-Output ''; exit 1
}

function Invoke-Leaks {
    if (-not (Test-Tool 'rtk')) { Write-Output '  RTK not installed — leaks detection requires RTK history'; exit 1 }
    $hist = Get-RtkHistory
    if (-not $hist) { Write-Output '  RTK history unavailable'; exit 1 }
    $json  = $hist | ConvertTo-Json -Depth 10 -Compress
    $leaksCode = @'
import sys,json,re
data=json.loads(sys.argv[1]); FR=re.compile(r'\b(?:cat|head|tail|tilth\s+read|tilth_read)\s+(\S+\.\w+)')
found=[]
for c in data.get("commands",[]):
    m=FR.search(c.get("cmd",""))
    if m and c.get("count",0)>=2: found.append((m.group(1),c["count"],c.get("total_input",0)))
for f,cnt,tok in sorted(found,key=lambda x:x[1],reverse=True):
    print(f"{f}\t{cnt}\t{tok}")
'@
    $leaks = Invoke-Python -Code $leaksCode -PyArgs @($json)
    if (-not $leaks) { Write-Output '  [OK] No leaks detected — no files read multiple times'; return }
    Write-Output 'Context leaks — files read multiple times:'
    Write-Output ''
    $leaks -split "`n" | Where-Object { $_ } | ForEach-Object {
        $p = $_ -split "`t"
        Write-Output ("  [W]  {0}  ({1}x, ~{2} tokens)" -f $p[0], $p[1], (Format-Tokens [long]$p[2]))
    }
    Write-Output ''
    Write-Output '  Tip: use tilth_read with offset/limit to read only changed sections'
    exit 1
}

function Invoke-Route([string[]]$Remaining) {
    $task = $Remaining -join ' '
    if (-not $task) { Write-Output 'Usage: token-diet route <task description>'; exit 1 }
    $lower = $task.ToLower()
    if ($lower -match 'rename|refactor|reference|diagnostic|navigate|symbol|lsp|find.*def|go.to') {
        Write-Output '-> Serena (LSP navigation)'
        Write-Output '  Best for: rename, refactor, find references, diagnostics, symbol search'
        Write-Output '  Command:  use serena MCP tools (rename_symbol, find_referencing_symbols)'
    } elseif ($lower -match 'run|build|test|install|npm|cargo|make|git|docker|pip|exec|deploy') {
        Write-Output '-> RTK (output compression)'
        Write-Output '  Best for: CLI commands whose output would flood context'
        Write-Output '  Command:  rtk <your-command>'
    } elseif ($lower -match 'read|search|find|list|outline|grep|cat|show|view|open|import|deps') {
        Write-Output '-> tilth (AST-aware reading)'
        Write-Output '  Best for: reading files, searching symbols, exploring structure'
        Write-Output '  Command:  use tilth MCP tools (tilth_read, tilth_search, tilth_files)'
    } else {
        Write-Output 'No clear match — all three tools may apply:'
        Write-Output ''; Write-Output '  tilth   — reading/searching code (AST-aware, fast)'
        Write-Output '  Serena  — renaming/navigating symbols (LSP-powered)'
        Write-Output '  RTK     — running CLI commands (output compression)'
    }
}

function Invoke-TestFirst([string[]]$Remaining) {
    $file = if ($Remaining.Count -gt 0) { $Remaining[0] } else { '' }
    if (-not $file) { Write-Output 'Usage: token-diet test-first <file>'; exit 1 }
    $base = Split-Path $file -Leaf
    $name = [System.IO.Path]::GetFileNameWithoutExtension($base)
    $ext  = [System.IO.Path]::GetExtension($base).TrimStart('.')
    $dir  = Split-Path $file -Parent; if (-not $dir) { $dir = '.' }
    Write-Output "Test candidates for ${file}:"; Write-Output ''
    switch ($ext) {
        'py'                       { Write-Output "  tests/test_${name}.py"; Write-Output "  test_${name}.py"; Write-Output "  $dir/test_${name}.py" }
        'rs'                       { Write-Output "  tests/${name}_test.rs"; Write-Output "  tests/test_${name}.rs"; Write-Output "  $dir/${name}_test.rs  (inline #[cfg(test)] module)" }
        { $_ -in 'ts','tsx' }      { Write-Output "  $dir/${name}.test.ts"; Write-Output "  $dir/${name}.spec.ts"; Write-Output "  tests/${name}.test.ts" }
        { $_ -in 'js','jsx' }      { Write-Output "  $dir/${name}.test.js"; Write-Output "  $dir/${name}.spec.js"; Write-Output "  tests/${name}.test.js" }
        'go'                       { Write-Output "  $dir/${name}_test.go" }
        default                    { Write-Output "  tests/test_${name}.${ext}"; Write-Output "  $dir/test_${name}.${ext}" }
    }
    Write-Output ''
    Write-Output '  Tip: read the test file first to understand expected behavior before the implementation'
}

function Invoke-Strip([string[]]$Remaining) {
    $stats = $false; $file = ''
    foreach ($a in $Remaining) {
        if     ($a -eq '--stats') { $stats = $true }
        elseif ($a -like '-*')    { Write-Output "Unknown option: $a"; exit 1 }
        else                      { $file = $a }
    }
    if (-not $file)          { Write-Output 'Usage: token-diet strip [--stats] <file>'; exit 1 }
    if (-not (Test-Path $file)) { Write-Output "File not found: $file"; exit 1 }
    $ext = [System.IO.Path]::GetExtension($file).TrimStart('.')
    $code = if ($ext -in @('js','ts','jsx','tsx','java','c','cpp','h','cs','go','swift','kt')) {
@'
import sys,re
with open(sys.argv[1],encoding='utf-8') as f: content=f.read()
print('\n'.join(re.sub(r'\s*//.*$','',l) for l in content.splitlines()))
'@
    } else {
@'
import sys,re
with open(sys.argv[1],encoding='utf-8') as f: lines=f.readlines()
out=[]
for orig,s in zip(lines,[re.sub(r'\s+#[^!\n].*$','',re.sub(r'^\s*#.*\n?','',l).rstrip('\n')) for l in lines]):
    if orig.strip().startswith('#'): continue
    out.append(s)
print('\n'.join(out))
'@
    }
    $stripped = Invoke-Python -Code $code -PyArgs @($file)
    if ($stats) {
        $origLines = (Get-Content $file).Count
        $stripLines = ($stripped -split "`n").Count
        $saved = $origLines - $stripLines
        $pct = if ($origLines -gt 0) { [math]::Round($saved * 100.0 / $origLines, 1) } else { 0 }
        Write-Output $stripped
        Write-Output ''
        Write-Output "Lines: $origLines -> $stripLines  (saved $saved lines, $pct% reduction)"
    } else {
        Write-Output $stripped
    }
}

function Invoke-DiffReads([string[]]$Remaining) {
    $file = if ($Remaining.Count -gt 0) { $Remaining[0] } else { '' }
    if (-not $file)             { Write-Output 'Usage: token-diet diff-reads <file>'; exit 1 }
    if (-not (Test-Path $file)) { Write-Output "File not found: $file"; exit 1 }
    $abs  = (Resolve-Path $file).Path
    $root = & git -C (Split-Path $abs -Parent) rev-parse --show-toplevel 2>$null
    if (-not $root) { Write-Output "Not a git repository: $file"; exit 1 }
    $rel  = [System.IO.Path]::GetRelativePath($root, $abs) -replace '\\','/'
    $diff  = @(& git -C $root diff HEAD -- $rel 2>$null) + @(& git -C $root diff --cached -- $rel 2>$null) -join "`n"
    if (-not $diff.Trim()) { $diff = @(& git -C $root diff HEAD~1 HEAD -- $rel 2>$null) -join "`n" }
    if (-not $diff.Trim()) { Write-Output "No recent changes detected for: $rel"; Write-Output 'Suggest reading the full file.'; return }
    Write-Output "Changed regions in ${rel}:"; Write-Output ''
    $diffReadsCode = @'
import sys,re
hunks=re.findall(r'@@ [^@]+ \+(\d+)(?:,(\d+))? @@',sys.argv[1])
if not hunks: print("  (no line range info available)")
else:
    for s,c in hunks:
        start=int(s); count=int(c) if c else 1; end=start+count-1
        if count==0: print(f"  (deletion at line {start})")
        elif start==end: print(f"  line {start}")
        else: print(f"  lines {start}-{end}  (Read offset={start-1} limit={count})")
'@
    Invoke-Python -Code $diffReadsCode -PyArgs @($diff)
}

function Invoke-Uninstall([string[]]$Remaining) {
    $ps1 = Join-Path $ScriptDir 'Uninstall.ps1'
    if (Test-Path $ps1) { & $ps1 @Remaining } else { Write-Error "Uninstall.ps1 not found"; exit 1 }
}

function Invoke-Help {
    $helpText = @"

token-diet — token optimization stack dashboard

USAGE
  token-diet.ps1 [command]

COMMANDS
  gain                    Show token savings dashboard across RTK + tilth + Serena  (default)
  health                  Quick health check: tools responding + MCP hosts registered
  breakdown               Top commands by tokens saved  [--limit N]
  explain <cmd>           Token cost breakdown for a specific command
  budget <init|status>    Per-project token budget with warn/hard thresholds
  loops                   Detect agent loop patterns (commands run 3+ times)
  route <task>            Suggest which tool (tilth/Serena/RTK) best fits the task
  leaks                   Detect files read multiple times in RTK history
  test-first <file>       Suggest test file counterpart for an implementation file
  strip [--stats] <file>  Strip comments from source file to reduce tokens
  diff-reads <file>       Suggest line ranges to read based on recent git diff
  dashboard               Open live browser dashboard  [--port N]
  service <sub>           Always-on dashboard daemon  (install|uninstall|start|stop|status)
  version                 Show installed versions of all three tools
  verify                  Re-run installation verification
  uninstall               Remove all token-diet components  [-DryRun] [-Force]
  --help                  Show this help

TOOLS
  RTK    Command output compression       60-90% savings (tracked)
  tilth  AST-aware code reading           38-44% savings (structural)
  Serena LSP symbol navigation            fewer prompt turns (structural)

INSTALL
  .\Install.ps1             Install all tools
  .\Install.ps1 -DryRun     Preview what would be installed

"@
    Write-Output $helpText
}

# --- Dispatch -----------------------------------------------------------------
switch ($Command) {
    'gain'                              { Invoke-Gain }
    'health'                            { Invoke-Health }
    'breakdown'                         { Invoke-Breakdown  $SubArgs }
    'explain'                           { Invoke-Explain    $SubArgs }
    'budget'                            { Invoke-Budget     $SubArgs }
    'loops'                             { Invoke-Loops }
    'dashboard'                         { Invoke-Dashboard  $SubArgs }
    'service'                           { Invoke-Service    $SubArgs }
    { $_ -in 'version','versions' }     { Invoke-Version }
    'verify'                            { Invoke-Verify }
    'route'                             { Invoke-Route      $SubArgs }
    'leaks'                             { Invoke-Leaks }
    'test-first'                        { Invoke-TestFirst  $SubArgs }
    'strip'                             { Invoke-Strip      $SubArgs }
    'diff-reads'                        { Invoke-DiffReads  $SubArgs }
    'uninstall'                         { Invoke-Uninstall  $SubArgs }
    { $_ -in '--help','-h','help' }     { Invoke-Help }
    default {
        Write-Output "Unknown command: $Command"
        Invoke-Help
        exit 1
    }
}
