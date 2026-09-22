#Requires -Version 5.1
<#
.SYNOPSIS
    token-diet: Install Serena + ICM + Context7 on Windows.

.DESCRIPTION
    Installs the AI context optimization stack (Serena, ICM, Context7,
    token-diet CLI) and configures for
    Claude Code, Codex CLI, OpenCode (GitHub Copilot), Copilot CLI,
    VS Code, and Cowork (Claude Desktop).

.PARAMETER Tool
    Which tool(s) to install: All (default), Serena, icm, context7

.PARAMETER VerifyOnly
    Only check current installation status.

.PARAMETER Local
    Air-gapped mode: build from forks/ submodules instead of fetching from GitHub.

.PARAMETER SkipTests
    Skip clippy + tests in -Local mode (faster install).

.PARAMETER Hosts
    Comma-separated list of AI hosts to wire integrations for.
    Valid values: claude, codex, opencode, copilot, vscode, cowork
    Default: prompt when multiple hosts are detected; skip prompt when only one is found.
    Example: -Hosts "claude,vscode"

.EXAMPLE
    .\Install.ps1                           # install all, prompt for host selection
    .\Install.ps1 -Tool context7            # context7 only
    .\Install.ps1 -VerifyOnly               # check status
    .\Install.ps1 -DryRun                   # simulate install, no changes made
    .\Install.ps1 -Local                    # air-gapped build from forks/
    .\Install.ps1 -FullOutput               # show all build output + log to file
    .\Install.ps1 -Hosts "claude,vscode"    # only wire Claude Code and VS Code
#>

[CmdletBinding()]
param(
    [ValidateSet("All", "Serena", "icm", "context7")]
    [string]$Tool = "All",
    [switch]$VerifyOnly,
    [switch]$DryRun,
    [switch]$FullOutput,
    [switch]$Local,
    [switch]$SkipTests,
    [string]$Hosts = ""
)

$ErrorActionPreference = "Stop"

# 'icm' is a built-in PowerShell alias for Invoke-Command and outranks external
# commands — remove it so `icm` and Test-Cmd 'icm' resolve to the real ICM binary,
# not Invoke-Command.
Remove-Item Alias:icm -Force -ErrorAction SilentlyContinue

# --- Configuration -----------------------------------------------------------
$SERENA_REPO = "https://github.com/artificemachine/serena"
$ICM_REPO    = "https://github.com/artificemachine/icm"

# Context7: remote HTTP MCP server (no local binary, no cargo prereq).
# URL and API key come from the environment so firewalled setups can point at
# an internal gateway. The key is appended to the URL query string and is never
# printed or logged.
$Context7DefaultUrl = "https://mcp.context7.com/mcp"

$script:ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ProjectRoot = Split-Path -Parent $script:ScriptDir

# --- Helpers ------------------------------------------------------------------
function Write-Info   { param($msg) Write-Host "[info]  $msg" -ForegroundColor Cyan }
function Write-Ok     { param($msg) Write-Host "[ok]    $msg" -ForegroundColor Green }
function Write-Warn   { param($msg) Write-Host "[warn]  $msg" -ForegroundColor Yellow }
function Write-Fail   { param($msg) Write-Host "[fail]  $msg" -ForegroundColor Red; exit 1 }
function Write-Header { param($msg) Write-Host "`n--- $msg ---`n" -ForegroundColor White }
function Write-DryRun { param($msg) Write-Host "[dry-run] would run: $msg" -ForegroundColor Magenta }

# --- Log rotation + Show-Output -----------------------------------------------
$LogDir  = Join-Path $env:LOCALAPPDATA "Programs\token-diet"
$LogFile = Join-Path $LogDir "install.log"

function Rotate-Log {
    if (-not (Test-Path $LogFile)) { return }
    $size = (Get-Item $LogFile).Length
    if ($size -gt 524288) {   # 512 KB
        $rotated = "${LogFile}.1"
        Move-Item -Force $LogFile $rotated -ErrorAction SilentlyContinue
    }
}

# Show-Output — filter build output.
# -FullOutput: pass everything through and tee to install.log.
# Default:     buffer and show only last 5 lines.
function Show-Output {
    [CmdletBinding()] param([Parameter(ValueFromPipeline)]$InputObject)
    begin {
        $script:_buf = @()
    }
    process {
        if ($FullOutput) {
            $InputObject
            if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
            $InputObject | Out-File -Append -FilePath $LogFile -Encoding utf8 -ErrorAction SilentlyContinue
        } else {
            $script:_buf += @($InputObject)
        }
    }
    end {
        if (-not $FullOutput -and $script:_buf) {
            $script:_buf | Select-Object -Last 5
            $script:_buf = @()
        }
    }
}

function Test-Cmd { param([string]$Name) $null -ne (Get-Command $Name -ErrorAction SilentlyContinue) }

# Resolve the Context7 MCP endpoint. CONTEXT7_URL overrides the default;
# CONTEXT7_API_KEY is appended as a query parameter. The key is never echoed.
function Get-Context7Url {
    $url = if ($env:CONTEXT7_URL) { $env:CONTEXT7_URL } else { $Context7DefaultUrl }
    if ($env:CONTEXT7_API_KEY) {
        $sep = if ($url.Contains('?')) { '&' } else { '?' }
        $url = "$url${sep}apiKey=$([System.Uri]::EscapeDataString($env:CONTEXT7_API_KEY))"
    }
    return $url
}

# Context7 URL safe for display/logs (query string stripped).
function Get-Context7DisplayUrl {
    $url = if ($env:CONTEXT7_URL) { $env:CONTEXT7_URL } else { $Context7DefaultUrl }
    return ($url -replace '\?.*$', '')
}

function Repair-SubmoduleWorktree {
    param([string]$RelativePath)

    $fullPath = Join-Path $script:ProjectRoot $RelativePath
    if (-not (Test-Path $fullPath)) { return }

    $entries = @(Get-ChildItem -Force -LiteralPath $fullPath -ErrorAction SilentlyContinue)
    $nonGitEntries = @($entries | Where-Object { $_.Name -ne '.git' })
    if ($nonGitEntries.Count -gt 0) { return }

    Write-Warn "$RelativePath appears empty; repairing submodule worktree"
    if ($DryRun) {
        Write-DryRun "git -C $script:ProjectRoot submodule update --init --force -- $RelativePath"
        return
    }

    git -C $script:ProjectRoot submodule update --init --force -- $RelativePath 2>&1 |
        Where-Object { $_ -match 'Submodule path|checked out|error' }
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

# --- Local build verification (--Local mode only) ----------------------------
function Verify-LocalBuild {
    param([string]$Name, [string]$ManifestPath)

    if ($SkipTests) {
        Write-Info "$Name`: skipping clippy + tests (-SkipTests)"
        return
    }

    Write-Info "$Name`: running clippy..."
    $clippyOut = cargo clippy --manifest-path $ManifestPath --all-targets -- -D warnings 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "$Name clippy clean"
    } else {
        Write-Warn "$Name clippy warnings found — continuing install"
        $clippyOut | Select-Object -Last 5
    }

    Write-Info "$Name`: running tests..."
    cargo test --manifest-path $ManifestPath 2>&1 | Show-Output
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "$Name tests passed"
    } else {
        Write-Warn "$Name test failures — continuing install"
    }
}

# --- Prerequisites ------------------------------------------------------------
function Ensure-Git {
    if (-not (Test-Cmd "git")) { Write-Fail "git is required. Install from https://git-scm.com" }
    Write-Ok "git found: $(git --version)"

    # Initialize submodules so forks\ is populated for local builds
    $gitmodules = Join-Path $script:ProjectRoot ".gitmodules"
    if (Test-Path $gitmodules) {
        Write-Info "Initializing submodules (forks\serena, forks\icm)..."
        git -C $script:ProjectRoot submodule update --init --recursive 2>&1 | Where-Object { $_ -match "Cloning|already|error" }
        Repair-SubmoduleWorktree "forks\serena"
        Repair-SubmoduleWorktree "forks\icm"
        Write-Ok "Submodules ready"
    }
}

function Ensure-Rust {
    if (Test-Cmd "rustup") {
        Write-Ok "Rust found: $(rustc --version 2>$null)"
        if (-not $DryRun) { rustup update stable --no-self-update 2>$null | Out-Null }
        else { Write-DryRun "rustup update stable --no-self-update" }
    } else {
        if ($DryRun) {
            Write-DryRun "Download https://win.rustup.rs/x86_64 and install Rust toolchain"
        } else {
            Write-Info "Installing Rust toolchain..."
            $installer = Join-Path $env:TEMP "rustup-init.exe"
            Invoke-WebRequest -Uri "https://win.rustup.rs/x86_64" -OutFile $installer -UseBasicParsing
            & $installer -y --default-toolchain stable 2>&1 | Out-Null
            $env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
            if (-not (Test-Cmd "rustc")) { Write-Fail "Rust installation failed. Install from https://rustup.rs" }
            Write-Ok "Rust installed: $(rustc --version)"
        }
    }
}

function Ensure-Uv {
    if (Test-Cmd "uv") {
        Write-Ok "uv found: $(uv --version 2>$null)"
    } else {
        if ($DryRun) {
            Write-DryRun "Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression"
        } else {
            Write-Info "Installing uv..."
            Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
            $env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"
            if (-not (Test-Cmd "uv")) { Write-Fail "uv installation failed. See https://docs.astral.sh/uv/" }
            Write-Ok "uv installed: $(uv --version)"
        }
    }
}

function Ensure-Docker {
    if (-not (Test-Cmd "docker")) { Write-Fail "Docker required for local Serena install." }
    Write-Ok "docker found: $(docker --version 2>$null)"
}

# --- Host detection -----------------------------------------------------------
$script:HasClaude   = $false
$script:HasCodex    = $false
$script:HasOpenCode = $false
$script:HasCopilot  = $false
$script:HasVSCode   = $false
$script:HasCowork   = $false

function Detect-Hosts {
    Write-Header "AI Host Detection"
    $script:HasClaude   = Test-Cmd "claude"
    $script:HasCodex    = Test-Cmd "codex"
    $script:HasOpenCode = Test-Cmd "opencode"
    $script:HasCopilot  = Test-Cmd "github-copilot-cli"
    # VS Code: check 'code' CLI
    $script:HasVSCode   = Test-Cmd "code"
    # Cowork (Claude Desktop): check config dir or process
    $coworkConfig = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
    $script:HasCowork   = (Test-Path $coworkConfig) -or (Test-Cmd "claude-desktop")

    if ($script:HasClaude)   { Write-Ok "Claude Code ..... found" } else { Write-Warn "Claude Code ..... not found" }
    if ($script:HasCodex)    { Write-Ok "Codex CLI ....... found" } else { Write-Warn "Codex CLI ....... not found" }
    if ($script:HasOpenCode) { Write-Ok "OpenCode ........ found" } else { Write-Warn "OpenCode ...... not found" }
    if ($script:HasCopilot)  { Write-Ok "Copilot CLI ..... found" } else { Write-Warn "Copilot CLI ..... not found" }
    if ($script:HasVSCode)   { Write-Ok "VS Code ......... found" } else { Write-Warn "VS Code ......... not found" }
    if ($script:HasCowork)   { Write-Ok "Cowork (Desktop)  found" } else { Write-Warn "Cowork (Desktop)  not found" }

    if (-not $script:HasClaude -and -not $script:HasCodex -and -not $script:HasOpenCode `
        -and -not $script:HasCopilot -and -not $script:HasVSCode -and -not $script:HasCowork) {
        Write-Warn "No AI host detected. Tools installed but MCP/hook integration skipped."
    }
}

# --- Host selection -----------------------------------------------------------
# Applies -Hosts filter or prompts when multiple hosts are found.
# Sets $script:Has* flags to false for any host not selected.
function Confirm-Hosts {
    # Map slug -> flag variable name and display label
    $hostMap = [ordered]@{
        "claude"   = @{ Var = "HasClaude";   Label = "Claude Code" }
        "codex"    = @{ Var = "HasCodex";    Label = "Codex CLI" }
        "opencode" = @{ Var = "HasOpenCode"; Label = "OpenCode" }
        "copilot"  = @{ Var = "HasCopilot";  Label = "Copilot CLI" }
        "vscode"   = @{ Var = "HasVSCode";   Label = "VS Code" }
        "cowork"   = @{ Var = "HasCowork";   Label = "Cowork (Desktop)" }
    }

    # Build list of currently detected hosts
    $detected = @()
    foreach ($slug in $hostMap.Keys) {
        $varName = $hostMap[$slug].Var
        if ((Get-Variable -Name $varName -Scope Script -ValueOnly)) {
            $detected += $slug
        }
    }

    if ($detected.Count -le 1) { return }   # nothing to choose from

    # -Hosts flag supplied — apply it without prompting
    if ($Hosts -ne "") {
        $selected = $Hosts.ToLower() -split '[,\s]+' | Where-Object { $_ -ne "" }
        foreach ($slug in $hostMap.Keys) {
            if ($slug -notin $selected) {
                Set-Variable -Name $hostMap[$slug].Var -Scope Script -Value $false
            }
        }
        $kept = ($selected | Where-Object { $_ -in $hostMap.Keys }) -join ", "
        Write-Info "Host integrations limited to: $kept"
        return
    }

    # Interactive prompt
    Write-Host ""
    Write-Host "  Detected AI hosts:" -ForegroundColor White
    $i = 1
    $indexMap = @{}
    foreach ($slug in $detected) {
        Write-Host "    [$i] $($hostMap[$slug].Label)" -ForegroundColor Cyan
        $indexMap[$i] = $slug
        $i++
    }
    Write-Host ""
    Write-Host "  Install integrations for all detected hosts? [Y/n/list]" -ForegroundColor White
    Write-Host "    Y = all (default)  |  n = none  |  list = e.g. 1,3 or claude,vscode" -ForegroundColor DarkGray
    $answer = Read-Host "  > "

    if ($answer -eq "" -or $answer -match '^[Yy]') { return }   # keep all

    $selected = @()
    if ($answer -match '^[Nn]$') {
        # deselect all
    } else {
        # parse numbers or names
        $tokens = $answer -split '[,\s]+' | Where-Object { $_ -ne "" }
        foreach ($token in $tokens) {
            if ($token -match '^\d+$') {
                $idx = [int]$token
                if ($indexMap.ContainsKey($idx)) { $selected += $indexMap[$idx] }
            } elseif ($token.ToLower() -in $hostMap.Keys) {
                $selected += $token.ToLower()
            }
        }
    }

    foreach ($slug in $hostMap.Keys) {
        if ($slug -notin $selected) {
            Set-Variable -Name $hostMap[$slug].Var -Scope Script -Value $false
        }
    }

    if ($selected.Count -eq 0) {
        Write-Warn "No hosts selected — integrations will be skipped."
    } else {
        $kept = ($selected | ForEach-Object { $hostMap[$_].Label }) -join ", "
        Write-Info "Host integrations limited to: $kept"
    }
}

# --- Serena -------------------------------------------------------------------
function Install-Serena {
    Write-Header "Serena (IDE-like symbol navigation)"

    if ($Local) {
        # Docker-based local install
        if ($DryRun) {
            Write-DryRun "docker build -f $($script:ProjectRoot)\docker\Dockerfile.serena -t token-diet/serena:latest $($script:ProjectRoot)"
        } else {
            if (docker image inspect token-diet/serena:latest 2>$null) {
                Write-Ok "Serena Docker image already built"
            } else {
                Write-Info "Building Serena Docker image from fork (air-gapped)..."
                docker build -f (Join-Path $script:ProjectRoot "docker\Dockerfile.serena") `
                    -t token-diet/serena:latest $script:ProjectRoot 2>&1 | Select-Object -Last 10
                Write-Ok "Serena Docker image built"
            }
        }
    } else {
        if ($DryRun) {
            Write-DryRun "uvx --from git+$SERENA_REPO serena --help  (prefetch check)"
        } else {
            Write-Info "Verifying Serena via uvx..."
            try {
                uvx --from "git+$SERENA_REPO" serena --help 2>$null | Out-Null
                Write-Ok "Serena accessible via uvx"
            } catch {
                Write-Warn "Serena fetch failed. May work on first real invocation."
            }
        }
    }

    # Build the serena command/args depending on mode
    if ($Local) {
        $serenaCmdName = "docker"
        # The serena Docker image ships intentionally WITHOUT an ENTRYPOINT
        # (see docker/Dockerfile.serena, v1.11.4): the container command must
        # start with `serena start-mcp-server`, supplied here once. Host
        # registrations may pass an explicit `start-mcp-server` downstream of
        # this base without doubling it (no site appends its own copy).
        # "." not "`$(pwd)": MCP stdio hosts exec the configured argv directly
        # with no shell, so the `$(pwd)` literal never expanded and docker
        # received it verbatim (install.sh v1.15.19 fix, ported). Docker
        # resolves a relative -v path against its own invocation cwd, which
        # the host's spawn of the MCP subprocess inherits.
        $serenaArgsBase = @("run", "--rm", "-i", "-v", ".:/workspace:ro", "--network", "none", "token-diet/serena:latest", "serena", "start-mcp-server")
    } else {
        $serenaCmdName = "uvx"
        $serenaArgsBase = @("--from", "git+$SERENA_REPO", "serena", "start-mcp-server")
    }

    # Claude Code
    if ($script:HasClaude) {
        if ($Local) {
            $claudeArgs = $serenaArgsBase + @("--context=claude-code", "--open-web-dashboard", "false", "--project", "/workspace")
        } else {
            $claudeArgs = $serenaArgsBase + @("--context=claude-code", "--open-web-dashboard", "false", "--project-from-cwd")
        }
        if ($DryRun) {
            Write-DryRun "claude mcp add --scope user serena -- $serenaCmdName $($claudeArgs -join ' ')"
        } else {
            try {
                $addArgs = @("mcp", "add", "--scope", "user", "serena", "--") + @($serenaCmdName) + $claudeArgs
                & claude @addArgs 2>$null
                Write-Ok "Serena MCP: Claude Code"
            } catch { Write-Warn "Serena MCP: Claude Code failed (may already exist)" }
        }
    }

    # Codex CLI
    if ($script:HasCodex) {
        $codexConfig = Join-Path $env:USERPROFILE ".codex\config.toml"
        if ((Test-Path $codexConfig) -and (Select-String -Path $codexConfig -Pattern "serena" -Quiet)) {
            Write-Ok "Serena MCP: Codex CLI (already configured)"
        } else {
            if ($DryRun) {
                Write-DryRun "Append [mcp_servers.serena] block to $codexConfig"
            } else {
                $codexDir = Join-Path $env:USERPROFILE ".codex"
                if (-not (Test-Path $codexDir)) { New-Item -ItemType Directory -Path $codexDir -Force | Out-Null }
                if ($Local) {
                    $tomlBlock = @"

# Serena MCP server (added by token-diet, Docker mode)
[mcp_servers.serena]
command = "docker"
args = ["run", "--rm", "-i", "-v", ".:/workspace:ro", "--network", "none", "token-diet/serena:latest", "serena", "start-mcp-server", "--context=codex", "--open-web-dashboard", "false", "--project", "/workspace"]
"@
                } else {
                    $tomlBlock = @"

# Serena MCP server (added by token-diet)
[mcp_servers.serena]
command = "uvx"
args = ["--from", "git+$SERENA_REPO", "serena", "start-mcp-server", "--context=codex", "--open-web-dashboard", "false", "--project-from-cwd"]
"@
                }
                Add-Content -Path $codexConfig -Value $tomlBlock -Encoding UTF8
                Write-Ok "Serena MCP: Codex CLI (appended to $codexConfig)"
            }
        }
    }

    # VS Code — write .vscode/mcp.json template
    if ($script:HasVSCode) {
        $vscodeTplDir = Join-Path $env:APPDATA "token-diet"
        $vscodeTemplate = Join-Path $vscodeTplDir "vscode-mcp.template.json"
        if ($DryRun) {
            Write-DryRun "Write VS Code MCP template to $vscodeTemplate"
        } else {
            if (-not (Test-Path $vscodeTplDir)) { New-Item -ItemType Directory -Path $vscodeTplDir -Force | Out-Null }
            @"
{
  "servers": {
    "serena": {
      "command": "uvx",
      "args": ["--from", "git+$SERENA_REPO", "serena", "start-mcp-server", "--context=ide", "--open-web-dashboard", "false", "--project-from-cwd"]
    }
  }
}
"@ | Set-Content -Path $vscodeTemplate -Encoding UTF8
            Write-Ok "VS Code MCP template: $vscodeTemplate"
            Write-Info "  Copy to project: Copy-Item '$vscodeTemplate' '<project>\.vscode\mcp.json'"
        }
    }

    # Cowork (Claude Desktop)
    if ($script:HasCowork) {
        $coworkCfg = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
        if ($DryRun) {
            Write-DryRun "Write mcpServers.serena to $coworkCfg"
        } else {
            try {
                $data = if (Test-Path $coworkCfg) { Get-Content $coworkCfg -Raw | ConvertFrom-Json } else { [PSCustomObject]@{} }
                if (-not $data.PSObject.Properties["mcpServers"]) {
                    $data | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue ([PSCustomObject]@{})
                }
                if ($Local) {
                    $serenaEntry = [PSCustomObject]@{
                        command = "docker"
                        # "." not "`$(pwd)": no shell expands it in MCP stdio
                        # argv; see $serenaArgsBase above (v1.15.19 port).
                        args    = @("run", "--rm", "-i", "-v", ".:/workspace:ro", "--network", "none",
                                    "token-diet/serena:latest", "serena", "start-mcp-server", "--context=claude-code", "--open-web-dashboard", "false", "--project", "/workspace")
                    }
                } else {
                    $serenaEntry = [PSCustomObject]@{
                        command = "uvx"
                        args    = @("--from", "git+$SERENA_REPO", "serena", "start-mcp-server",
                                    "--context=claude-code", "--open-web-dashboard", "false", "--project-from-cwd")
                    }
                }
                $data.mcpServers | Add-Member -NotePropertyName "serena" -NotePropertyValue $serenaEntry -Force

                $data | ConvertTo-Json -Depth 10 | Set-Content -Path $coworkCfg -Encoding UTF8
                Write-Ok "Serena MCP: Cowork / Claude Desktop ($coworkCfg)"
            } catch {
                Write-Warn "Serena MCP: Cowork setup failed — $_"
            }
        }
    }

    # OpenCode
    if ($script:HasOpenCode) {
        $ocCfg = Join-Path $env:USERPROFILE ".opencode.json"
        if ($DryRun) {
            Write-DryRun "Write mcpServers.serena entry to $ocCfg"
        } else {
            try {
                $data = if (Test-Path $ocCfg) { Get-Content $ocCfg -Raw | ConvertFrom-Json } else { [PSCustomObject]@{} }
                if (-not $data.PSObject.Properties["mcpServers"]) {
                    $data | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue ([PSCustomObject]@{})
                }
                if ($Local) {
                    $serenaEntry = [PSCustomObject]@{
                        command = "docker"
                        # "." not "`$(pwd)": no shell expands it in MCP stdio
                        # argv; see $serenaArgsBase above (v1.15.19 port).
                        args    = @("run", "--rm", "-i", "-v", ".:/workspace:ro", "--network", "none",
                                    "token-diet/serena:latest", "serena", "start-mcp-server", "--context=ide", "--open-web-dashboard", "false", "--project", "/workspace")
                    }
                } else {
                    $serenaEntry = [PSCustomObject]@{
                        command = "uvx"
                        args    = @("--from", "git+$SERENA_REPO", "serena", "start-mcp-server",
                                    "--context=ide", "--open-web-dashboard", "false", "--project-from-cwd")
                    }
                }
                $data.mcpServers | Add-Member -NotePropertyName "serena" -NotePropertyValue $serenaEntry -Force
                $data | ConvertTo-Json -Depth 10 | Set-Content -Path $ocCfg -Encoding UTF8
                Write-Ok "Serena MCP: OpenCode ($ocCfg)"
            } catch {
                Write-Warn "Serena MCP: OpenCode setup failed — $_"
            }
        }
    }

    if ($script:HasCopilot) {
        Write-Ok "Serena: Copilot CLI uses VS Code MCP config (shared)"
    }

    # Disable Serena's built-in web dashboard.
    # With Serena registered in multiple hosts, web_dashboard:true spawns
    # a native pywebview app process per host — multiple windows on startup.
    # Users get a dashboard via `token-diet dashboard` instead.
    $serenaCfg = Join-Path $env:USERPROFILE ".serena\serena_config.yml"
    if ($DryRun) {
        Write-DryRun "Set web_dashboard: false + web_dashboard_open_on_launch: false in $serenaCfg"
    } elseif (Test-Path $serenaCfg) {
        $content = Get-Content $serenaCfg -Raw
        $content = $content -replace '(?m)^web_dashboard: true', 'web_dashboard: false'
        $content = $content -replace '(?m)^web_dashboard_open_on_launch: true', 'web_dashboard_open_on_launch: false'
        Set-Content -Path $serenaCfg -Value $content -Encoding UTF8
        Write-Ok "Serena: disabled built-in web dashboard ($serenaCfg)"
    }
}

# --- ICM ----------------------------------------------------------------------
# ICM (Infinite Context Memory) — cross-tool persistent memory MCP server.
# Build/install via cargo install. MCP registration mirrors Serena
# (self-written config entries). We never call `icm init`: it bakes absolute
# current_exe() paths into ~20 host configs and would violate install-decoupling.
# We register the bare-PATH command `icm serve --compact` ourselves instead.
#
# Embeddings policy (the air-gap decision):
#   -Local → lean build (--no-default-features --features tui,backend-sqlite): fastembed
#            is never compiled, so the binary physically cannot fetch a model.
#   online → embeddings compiled but DISABLED in config (embeddings.enabled=false)
#            so nothing is fetched silently. `token-diet icm warmup` performs the
#            one-time ~270 MB model download with consent; ICM then runs offline.
function Install-ICM {
    Write-Header "ICM (Infinite Context Memory)"

    if (Test-Cmd "icm") {
        Write-Ok "ICM already installed: $(icm --version 2>$null)"
        Write-Info "Upgrading..."
    }

    if ($Local) {
        $manifest = Join-Path $script:ProjectRoot "forks\icm\crates\icm-cli\Cargo.toml"
        if (-not (Test-Path $manifest)) { Write-Fail "forks\icm\crates\icm-cli\Cargo.toml not found — run: git submodule update --init --recursive" }
        Verify-LocalBuild "ICM" $manifest
        if ($DryRun) {
            Write-DryRun "cargo install --path $($script:ProjectRoot)\forks\icm\crates\icm-cli --no-default-features --features tui,backend-sqlite --force"
        } else {
            Write-Info "Building ICM from fork (keyword-only, air-gapped)..."
            cargo install --path (Join-Path $script:ProjectRoot "forks\icm\crates\icm-cli") --no-default-features --features tui,backend-sqlite --force 2>&1 | Show-Output
            Write-Ok "ICM built and installed from fork (keyword-only memory)"
        }
    } else {
        if ($DryRun) {
            Write-DryRun "cargo install --git $ICM_REPO icm-cli --force"
        } else {
            cargo install --git $ICM_REPO icm-cli --force 2>&1 | Show-Output
            Write-Ok "ICM installed: $(icm --version 2>$null)"
        }
    }

    # Verify
    if (-not $DryRun) {
        icm --version 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "ICM verification passed"
        } else {
            Write-Warn "ICM verification failed"
            return
        }
    }

    # Embeddings policy: the online build ships embeddings compiled but OFF by
    # default (config default is enabled=true upstream) so nothing is fetched
    # behind the firewall. `token-diet icm warmup` turns it on. Air-gapped builds
    # have no embedding code at all, so this is a harmless no-op there.
    if (-not $Local) {
        $icmCfg = Join-Path $env:USERPROFILE ".config\icm\config.toml"
        if ($DryRun) {
            Write-DryRun "Set [embeddings] enabled=false in $icmCfg (warmup enables it)"
        } else {
            $icmCfgDir = Split-Path -Parent $icmCfg
            if (-not (Test-Path $icmCfgDir)) { New-Item -ItemType Directory -Path $icmCfgDir -Force | Out-Null }
            $text = if (Test-Path $icmCfg) { Get-Content $icmCfg -Raw } else { "" }
            if (-not $text) { $text = "" }
            # Set enabled=false strictly inside the [embeddings] table — the config
            # has many other `enabled` keys (extraction, recall, cloud, ...) we must
            # not touch. Anchor to the table header, scope the edit to its body.
            $m = [regex]::Match($text, "(?ms)^\[embeddings\][^\n]*\n(.*?)(?=^\[|\z)")
            if ($m.Success) {
                $body = $m.Groups[1].Value
                if ($body -match "(?m)^\s*enabled\s*=") {
                    $body = [regex]::Replace($body, "(?m)^(\s*enabled\s*=\s*).*$", '${1}false', 1)
                } else {
                    $body = "enabled = false`n" + $body
                }
                $text = $text.Substring(0, $m.Groups[1].Index) + $body + $text.Substring($m.Groups[1].Index + $m.Groups[1].Length)
            } else {
                $prefix = if ($text.Trim()) { $text.TrimEnd() + "`n`n" } else { "" }
                $text = $prefix + "[embeddings]`nenabled = false`n"
            }
            Set-Content -Path $icmCfg -Value $text -Encoding UTF8 -NoNewline
            Write-Ok "ICM semantic search is OFF until warmup ($icmCfg)"
            Write-Info "  Enable cross-tool semantic recall (one-time ~270 MB model download):"
            Write-Info "    token-diet icm warmup"
        }
    }

    # --- MCP registration (self-written, NEVER 'icm init') ----------------------
    # Always the bare-PATH command 'icm serve --compact' — no repo path, no docker,
    # no uvx. Identical for local and online installs (icm is on PATH either way).
    Write-Info "Registering ICM MCP server for detected hosts..."

    # Claude Code
    if ($script:HasClaude) {
        if ($DryRun) {
            Write-DryRun "claude mcp add --scope user icm -- icm serve --compact"
        } else {
            claude mcp get icm 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "ICM MCP: Claude Code (already configured)"
            } else {
                try {
                    & claude mcp add --scope user icm -- icm serve --compact 2>$null
                    Write-Ok "ICM MCP: Claude Code"
                } catch { Write-Warn "ICM MCP: Claude Code setup failed" }
            }
        }
    }

    # Codex CLI — anchor to the actual TOML table header, never a loose substring.
    if ($script:HasCodex) {
        $codexConfig = Join-Path $env:USERPROFILE ".codex\config.toml"
        $alreadyConfigured = $false
        if (Test-Path $codexConfig) {
            $codexText = Get-Content $codexConfig -Raw -ErrorAction SilentlyContinue
            if ($codexText -and ($codexText -match '(?m)^\[mcp_servers\.icm\]')) { $alreadyConfigured = $true }
        }
        if ($alreadyConfigured) {
            Write-Ok "ICM MCP: Codex CLI (already configured)"
        } elseif ($DryRun) {
            Write-DryRun "Append [mcp_servers.icm] block to $codexConfig"
        } else {
            $codexDir = Join-Path $env:USERPROFILE ".codex"
            if (-not (Test-Path $codexDir)) { New-Item -ItemType Directory -Path $codexDir -Force | Out-Null }
            $tomlBlock = @"

# ICM MCP server (added by token-diet)
[mcp_servers.icm]
command = "icm"
args = ["serve", "--compact"]
"@
            Add-Content -Path $codexConfig -Value $tomlBlock -Encoding UTF8
            Write-Ok "ICM MCP: Codex CLI"
        }
    }

    # VS Code — merge into the shared template (servers.icm). A merge (not a heredoc)
    # so -Tool icm populates it even when Serena did not rewrite the template.
    if ($script:HasVSCode) {
        $vscodeTplDir = Join-Path $env:APPDATA "token-diet"
        $vscodeTemplate = Join-Path $vscodeTplDir "vscode-mcp.template.json"
        if ($DryRun) {
            Write-DryRun "Merge servers.icm into $vscodeTemplate"
        } else {
            if (-not (Test-Path $vscodeTplDir)) { New-Item -ItemType Directory -Path $vscodeTplDir -Force | Out-Null }
            try {
                $data = if (Test-Path $vscodeTemplate) { Get-Content $vscodeTemplate -Raw | ConvertFrom-Json } else { [PSCustomObject]@{} }
            } catch {
                $data = [PSCustomObject]@{}
            }
            if (-not $data.PSObject.Properties["servers"]) {
                $data | Add-Member -NotePropertyName "servers" -NotePropertyValue ([PSCustomObject]@{})
            }
            $icmEntry = [PSCustomObject]@{
                command = "icm"
                args    = @("serve", "--compact")
            }
            $data.servers | Add-Member -NotePropertyName "icm" -NotePropertyValue $icmEntry -Force
            $data | ConvertTo-Json -Depth 10 | Set-Content -Path $vscodeTemplate -Encoding UTF8
            Write-Ok "ICM MCP: VS Code template ($vscodeTemplate)"
        }
    }

    # OpenCode — bare-PATH command (NOT a forks\ path; icm is always on PATH).
    if ($script:HasOpenCode) {
        $ocCfg = Join-Path $env:USERPROFILE ".opencode.json"
        if ($DryRun) {
            Write-DryRun "Write mcpServers.icm entry to $ocCfg"
        } else {
            try {
                $data = if (Test-Path $ocCfg) { Get-Content $ocCfg -Raw | ConvertFrom-Json } else { [PSCustomObject]@{} }
                if (-not $data.PSObject.Properties["mcpServers"]) {
                    $data | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue ([PSCustomObject]@{})
                }
                $icmEntry = [PSCustomObject]@{
                    command = "icm"
                    args    = @("serve", "--compact")
                }
                $data.mcpServers | Add-Member -NotePropertyName "icm" -NotePropertyValue $icmEntry -Force
                $data | ConvertTo-Json -Depth 10 | Set-Content -Path $ocCfg -Encoding UTF8
                Write-Ok "ICM MCP: OpenCode ($ocCfg)"
            } catch {
                Write-Warn "ICM MCP: OpenCode setup failed — $_"
            }
        }
    }

    # Cowork (Claude Desktop)
    if ($script:HasCowork) {
        $coworkCfg = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
        if ($DryRun) {
            Write-DryRun "Write mcpServers.icm to $coworkCfg"
        } else {
            try {
                $data = if (Test-Path $coworkCfg) { Get-Content $coworkCfg -Raw | ConvertFrom-Json } else { [PSCustomObject]@{} }
                if (-not $data.PSObject.Properties["mcpServers"]) {
                    $data | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue ([PSCustomObject]@{})
                }
                $icmEntry = [PSCustomObject]@{
                    command = "icm"
                    args    = @("serve", "--compact")
                }
                $data.mcpServers | Add-Member -NotePropertyName "icm" -NotePropertyValue $icmEntry -Force
                $data | ConvertTo-Json -Depth 10 | Set-Content -Path $coworkCfg -Encoding UTF8
                Write-Ok "ICM MCP: Cowork / Claude Desktop ($coworkCfg)"
            } catch {
                Write-Warn "ICM MCP: Cowork setup failed — $_"
            }
        }
    }

    if ($script:HasCopilot) {
        Write-Ok "ICM: Copilot CLI uses VS Code MCP config (shared)"
    }
}

# --- Context7 -----------------------------------------------------------------
# Context7 — remote HTTP MCP server serving up-to-date library documentation.
# Nothing is compiled or installed: registration only. The endpoint defaults to
# https://mcp.context7.com/mcp and is overridden via CONTEXT7_URL;
# CONTEXT7_API_KEY is appended to the URL and never printed.
function Install-Context7 {
    Write-Header "Context7 (up-to-date library docs, remote HTTP MCP)"

    $ctxUrl  = Get-Context7Url
    $ctxBase = Get-Context7DisplayUrl
    $keyNote = if ($env:CONTEXT7_API_KEY) { " (api key configured)" } else { "" }
    Write-Info "Context7 endpoint: $ctxBase$keyNote"

    # Claude Code — HTTP transport registration via the claude CLI.
    if ($script:HasClaude) {
        if ($DryRun) {
            Write-DryRun "claude mcp add --scope user --transport http context7 $ctxBase"
        } else {
            & claude mcp get context7 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "Context7 MCP: Claude Code (already configured)"
            } else {
                try {
                    & claude mcp add --scope user --transport http context7 $ctxUrl 2>$null
                    Write-Ok "Context7 MCP: Claude Code"
                } catch { Write-Warn "Context7 MCP: Claude Code setup failed" }
            }
        }
    }

    # Codex CLI — TOML block with url = (HTTP server, no command).
    if ($script:HasCodex) {
        $codexConfig = Join-Path $env:USERPROFILE ".codex\config.toml"
        $alreadyConfigured = $false
        if (Test-Path $codexConfig) {
            $codexText = Get-Content $codexConfig -Raw -ErrorAction SilentlyContinue
            if ($codexText -and ($codexText -match '(?m)^\[mcp_servers\.context7\]')) { $alreadyConfigured = $true }
        }
        if ($alreadyConfigured) {
            Write-Ok "Context7 MCP: Codex CLI (already configured)"
        } elseif ($DryRun) {
            Write-DryRun "Append [mcp_servers.context7] block to $codexConfig"
        } else {
            $codexDir = Join-Path $env:USERPROFILE ".codex"
            if (-not (Test-Path $codexDir)) { New-Item -ItemType Directory -Path $codexDir -Force | Out-Null }
            $tomlBlock = @"

# Context7 MCP server (added by token-diet)
[mcp_servers.context7]
url = "$ctxUrl"
"@
            Add-Content -Path $codexConfig -Value $tomlBlock -Encoding UTF8
            Write-Ok "Context7 MCP: Codex CLI"
        }
    }

    # VS Code — merge into the shared template (servers.context7).
    if ($script:HasVSCode) {
        $vscodeTplDir = Join-Path $env:APPDATA "token-diet"
        $vscodeTemplate = Join-Path $vscodeTplDir "vscode-mcp.template.json"
        if ($DryRun) {
            Write-DryRun "Merge servers.context7 into $vscodeTemplate"
        } else {
            if (-not (Test-Path $vscodeTplDir)) { New-Item -ItemType Directory -Path $vscodeTplDir -Force | Out-Null }
            try {
                $data = if (Test-Path $vscodeTemplate) { Get-Content $vscodeTemplate -Raw | ConvertFrom-Json } else { [PSCustomObject]@{} }
            } catch {
                $data = [PSCustomObject]@{}
            }
            if (-not $data.PSObject.Properties["servers"]) {
                $data | Add-Member -NotePropertyName "servers" -NotePropertyValue ([PSCustomObject]@{})
            }
            $ctx7Entry = [PSCustomObject]@{
                type = "http"
                url  = $ctxUrl
            }
            $data.servers | Add-Member -NotePropertyName "context7" -NotePropertyValue $ctx7Entry -Force
            $data | ConvertTo-Json -Depth 10 | Set-Content -Path $vscodeTemplate -Encoding UTF8
            Write-Ok "Context7 MCP: VS Code template ($vscodeTemplate)"
        }
    }

    # OpenCode — JSON mcpServers.context7 { type: http, url }.
    if ($script:HasOpenCode) {
        $ocCfg = Join-Path $env:USERPROFILE ".opencode.json"
        if ($DryRun) {
            Write-DryRun "Write mcpServers.context7 entry to $ocCfg"
        } else {
            try {
                $data = if (Test-Path $ocCfg) { Get-Content $ocCfg -Raw | ConvertFrom-Json } else { [PSCustomObject]@{} }
                if (-not $data.PSObject.Properties["mcpServers"]) {
                    $data | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue ([PSCustomObject]@{})
                }
                $ctx7Entry = [PSCustomObject]@{
                    type = "http"
                    url  = $ctxUrl
                }
                $data.mcpServers | Add-Member -NotePropertyName "context7" -NotePropertyValue $ctx7Entry -Force
                $data | ConvertTo-Json -Depth 10 | Set-Content -Path $ocCfg -Encoding UTF8
                Write-Ok "Context7 MCP: OpenCode ($ocCfg)"
            } catch {
                Write-Warn "Context7 MCP: OpenCode setup failed — $_"
            }
        }
    }

    # Cowork (Claude Desktop) — JSON mcpServers.context7 { type: http, url }.
    if ($script:HasCowork) {
        $coworkCfg = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
        if ($DryRun) {
            Write-DryRun "Write mcpServers.context7 to $coworkCfg"
        } else {
            try {
                $data = if (Test-Path $coworkCfg) { Get-Content $coworkCfg -Raw | ConvertFrom-Json } else { [PSCustomObject]@{} }
                if (-not $data.PSObject.Properties["mcpServers"]) {
                    $data | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue ([PSCustomObject]@{})
                }
                $ctx7Entry = [PSCustomObject]@{
                    type = "http"
                    url  = $ctxUrl
                }
                $data.mcpServers | Add-Member -NotePropertyName "context7" -NotePropertyValue $ctx7Entry -Force
                $data | ConvertTo-Json -Depth 10 | Set-Content -Path $coworkCfg -Encoding UTF8
                Write-Ok "Context7 MCP: Cowork / Claude Desktop ($coworkCfg)"
            } catch {
                Write-Warn "Context7 MCP: Cowork setup failed — $_"
            }
        }
    }

    if ($script:HasCopilot) {
        Write-Ok "Context7: Copilot CLI uses VS Code MCP config (shared)"
    }
}

# --- OpenCode prompt rules injection ------------------------------------------
function Inject-OpenCodeRules {
    if (-not $script:HasOpenCode) { return }

    $ocPromptCfg = Join-Path $env:USERPROFILE ".config\opencode\opencode.json"
    $rulesFile = Join-Path $script:ScriptDir "lib\opencode-rules.md"

    if (-not (Test-Path $rulesFile)) {
        Write-Warn "OpenCode rules template missing: $rulesFile"
        return
    }
    if (-not (Test-Path $ocPromptCfg)) {
        Write-Info "OpenCode config not found at $ocPromptCfg — skipping prompt injection"
        return
    }

    if ($DryRun) {
        Write-DryRun "Inject token-diet rules into mode.build.prompt + mode.plan.prompt at $ocPromptCfg"
        return
    }

    try {
        $rulesBody = (Get-Content $rulesFile -Raw -Encoding UTF8).Trim()
        $BEGIN = "<!-- token-diet:begin -->"
        $END   = "<!-- token-diet:end -->"
        $block = "$BEGIN`n$rulesBody`n$END"

        $data = Get-Content $ocPromptCfg -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $data.PSObject.Properties["mode"]) {
            $data | Add-Member -NotePropertyName "mode" -NotePropertyValue ([PSCustomObject]@{})
        }

        foreach ($modeName in @("build", "plan")) {
            if (-not $data.mode.PSObject.Properties[$modeName]) {
                $data.mode | Add-Member -NotePropertyName $modeName -NotePropertyValue ([PSCustomObject]@{})
            }
            $existing = if ($data.mode.$modeName.PSObject.Properties["prompt"]) { $data.mode.$modeName.prompt } else { "" }
            if (-not $existing) { $existing = "" }

            if ($existing -match [regex]::Escape($BEGIN)) {
                $pattern = [regex]::Escape($BEGIN) + "[\s\S]*?" + [regex]::Escape($END)
                $new = [regex]::Replace($existing, $pattern, $block, [System.Text.RegularExpressions.RegexOptions]::None)
            } else {
                $sep = if ($existing) { "`n`n" } else { "" }
                $new = ($existing + $sep + $block).TrimStart("`n")
            }
            $data.mode.$modeName | Add-Member -NotePropertyName "prompt" -NotePropertyValue $new -Force
        }

        $data | ConvertTo-Json -Depth 10 | Set-Content -Path $ocPromptCfg -Encoding UTF8
        Write-Ok "OpenCode prompt rules injected: $ocPromptCfg"
    } catch {
        Write-Warn "OpenCode prompt injection failed: $_"
    }
}

# --- Install token-diet CLI + docs -------------------------------------------
function Install-TokenDiet {
    Write-Header "token-diet CLI + dashboard"

    $binDir = Join-Path $env:LOCALAPPDATA "Programs\token-diet"
    $srcPs1 = Join-Path $script:ScriptDir "token-diet.ps1"
    $srcDash = Join-Path $script:ScriptDir "token-diet-dashboard"
    $srcMcp = Join-Path $script:ScriptDir "token-diet-mcp"

    if (-not (Test-Path $srcPs1)) {
        Write-Warn "scripts\token-diet.ps1 not found — skipping CLI install"
        return
    }

    if ($DryRun) {
        Write-DryRun "Copy token-diet.ps1 to $binDir\token-diet.ps1"
        if (Test-Path $srcDash) { Write-DryRun "Copy token-diet-dashboard to $binDir\token-diet-dashboard" }
        if (Test-Path $srcMcp) { Write-DryRun "Copy token-diet-mcp to $binDir\token-diet-mcp" }
        Write-DryRun "Copy Uninstall.ps1 to $binDir\Uninstall.ps1"
        Write-DryRun "Write token-diet.md to ~/.claude/ and ~/.codex/"
        Write-DryRun "Add @token-diet.md to CLAUDE.md / AGENTS.md"
        Write-DryRun "Register token-diet MCP server"
        return
    }

    # Create bin dir
    if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir -Force | Out-Null }

    # Copy CLI
    Copy-Item $srcPs1 (Join-Path $binDir "token-diet.ps1") -Force
    Write-Ok "token-diet.ps1 installed: $binDir\token-diet.ps1"

    # Copy dashboard
    if (Test-Path $srcDash) {
        Copy-Item $srcDash (Join-Path $binDir "token-diet-dashboard") -Force
        Write-Ok "token-diet-dashboard installed: $binDir\token-diet-dashboard"
    }

    # Copy MCP
    if (Test-Path $srcMcp) {
        Copy-Item $srcMcp (Join-Path $binDir "token-diet-mcp") -Force
        Write-Ok "token-diet-mcp installed: $binDir\token-diet-mcp"

        # Register MCP server in codex
        $codexConfig = Join-Path $env:USERPROFILE ".codex\config.toml"
        if (Test-Path $codexConfig) {
            $content = Get-Content -Path $codexConfig -Raw
            if ($content -notmatch '\[mcp_servers\.token-diet\]') {
                Add-Content -Path $codexConfig -Value "`n[mcp_servers.token-diet]`ncommand = ""python""`nargs = [""$binDir\token-diet-mcp""]`n"
            }
        }

        # Register MCP server in JSON configs
        $configs = @(
            (Join-Path $env:USERPROFILE ".claude\settings.json"),
            (Join-Path $env:USERPROFILE ".opencode.json"),
            (Join-Path $env:APPDATA "Claude\claude_desktop_config.json")
        )
        if ($global:CoworkCfg) { $configs += $global:CoworkCfg }

        foreach ($cfg in $configs) {
            if (Test-Path $cfg) {
                try {
                    $json = Get-Content $cfg -Raw | ConvertFrom-Json
                    if (-not $json.PSObject.Properties.Match('mcpServers')) {
                        $json | Add-Member -MemberType NoteProperty -Name 'mcpServers' -Value @{}
                    }
                    $serverObj = @{ "command" = "python"; "args" = @("$binDir\token-diet-mcp") }
                    if ($json.mcpServers.PSObject.Properties.Match('token-diet')) {
                        $json.mcpServers.'token-diet' = $serverObj
                    } else {
                        $json.mcpServers | Add-Member -MemberType NoteProperty -Name 'token-diet' -Value $serverObj
                    }
                    $json | ConvertTo-Json -Depth 10 | Set-Content $cfg -Encoding UTF8
                } catch {
                    Write-Warn "Failed to register token-diet MCP in $cfg"
                }
            }
        }
    }

    # Copy installer so `token-diet verify` works standalone
    Copy-Item (Join-Path $script:ScriptDir "Install.ps1") (Join-Path $binDir "Install.ps1") -Force

    # Copy uninstaller so `token-diet uninstall` works standalone
    Copy-Item (Join-Path $script:ScriptDir "Uninstall.ps1") (Join-Path $binDir "Uninstall.ps1") -Force

    # Create a .cmd shim so 'token-diet' works from cmd.exe / PATH without typing .ps1
    $shimContent = @"
@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0token-diet.ps1" %*
if errorlevel 9009 powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0token-diet.ps1" %*
"@
    Set-Content -Path (Join-Path $binDir "token-diet.cmd") -Value $shimContent -Encoding ASCII
    Write-Ok "token-diet.cmd shim created"

    # Nudge if binDir not in PATH
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($userPath -notlike "*$binDir*") {
        Write-Info "Adding $binDir to user PATH..."
        [Environment]::SetEnvironmentVariable("PATH", "$binDir;$userPath", "User")
        $env:PATH = "$binDir;$env:PATH"
        Write-Ok "Added to user PATH: $binDir"
    }

    # Write token-diet.md into AI host config dirs and hook @token-diet.md
    $tkdDoc = @"
# Token Diet — AI Context Optimization

``token-diet`` is a unified optimization layer for AI agents. It orchestrates Serena, ICM, and Context7 to maximize context efficiency.

## Core Commands

- ``token-diet status``: Component and MCP registration status.
- ``token-diet mcp list``: Check which hosts are currently optimized.
- ``token-diet budget status``: Check project-specific token consumption.
- ``token-diet route <task>``: Ask ``token-diet`` which tool is best for your current task.
- ``token-diet doctor``: Run diagnostics if tools are unresponsive.

## Agent Guidelines

1. **Self-Monitor**: Regularly run ``token-diet budget status`` to stay within thresholds.
2. **Tool Selection**:
   - Use **Serena** for complex refactoring and symbol navigation.
   - Use **ICM** for recalling past decisions and storing facts (``icm recall``, ``icm store``).
   - Use **Context7** for up-to-date library documentation before writing integration code.
3. **Be Precise**: Prefer Serena symbol tools over re-reading whole files to minimize context waste.
4. **Optimization**: If you detect you are looping or wasting tokens, run ``token-diet doctor`` to self-audit.
"@

    $hostDirs = @(
        @{ Dir = (Join-Path $env:USERPROFILE ".claude"); InstructionFile = "CLAUDE.md" },
        @{ Dir = (Join-Path $env:USERPROFILE ".codex");  InstructionFile = "AGENTS.md" }
    )

    foreach ($entry in $hostDirs) {
        $dir = $entry.Dir
        $instrFile = Join-Path $dir $entry.InstructionFile

        if (-not (Test-Path $dir)) { continue }   # host not installed — skip

        $tkdDocFile = Join-Path $dir "token-diet.md"
        Set-Content -Path $tkdDocFile -Value $tkdDoc -Encoding UTF8
        Write-Ok "token-diet.md written: $tkdDocFile"

        # Add @token-diet.md reference if not already present
        if ((Test-Path $instrFile) -and -not (Select-String -Path $instrFile -Pattern "@token-diet.md" -Quiet)) {
            $instrContent = Get-Content $instrFile -Raw
            $instrContent += "`n@token-diet.md`n"
            Set-Content -Path $instrFile -Value $instrContent -Encoding UTF8
            Write-Ok "@token-diet.md added to: $instrFile"
        }
    }
}

# --- Verification -------------------------------------------------------------
function Verify-Stack {
    Write-Header "Token Stack Verification"

    $allOk = $true

    if (Test-Cmd "icm") {
        Write-Ok "ICM ............. $(icm --version 2>$null)"
        $icmIssue = Get-CodexMcpCommandIssue 'icm'
        if ($icmIssue) { Write-Warn $icmIssue; $allOk = $false }
    } else { Write-Warn "ICM ............. not installed"; $allOk = $false }

    if ($Local) {
        if ((Test-Cmd "docker") -and (docker image inspect token-diet/serena:latest 2>$null)) {
            Write-Ok "Serena .......... Docker image loaded"
        } else {
            Write-Warn "Serena .......... Docker image not found"
            $allOk = $false
        }
    } else {
        if (Test-Cmd "uv") {
            Write-Ok "Serena (via uv) . $(uv --version 2>$null)"
        } else { Write-Warn "Serena (uv) ..... not installed"; $allOk = $false }
    }
    $serenaIssue = Get-CodexMcpCommandIssue 'serena'
    if ($serenaIssue) { Write-Warn $serenaIssue; $allOk = $false }

    # Context7: remote HTTP MCP server — verified by host registration, no binary.
    $ctx7Base = Get-Context7DisplayUrl
    $ctx7Registered = $false
    foreach ($cfgPath in @(
        (Join-Path $env:USERPROFILE ".claude\settings.json"),
        (Join-Path $env:USERPROFILE ".opencode.json"),
        (Join-Path $env:APPDATA "Claude\claude_desktop_config.json")
    )) {
        if ((Test-Path $cfgPath) -and (Select-String -Path $cfgPath -Pattern '"context7"' -Quiet)) { $ctx7Registered = $true; break }
    }
    if (-not $ctx7Registered -and (Test-Cmd "claude")) {
        & claude mcp get context7 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $ctx7Registered = $true }
    }
    if ($ctx7Registered) {
        Write-Ok "Context7 ........ $ctx7Base (registered)"
    } else { Write-Warn "Context7 ........ not registered in any host config"; $allOk = $false }

    Write-Host ""
    if (Test-Cmd "claude")               { Write-Ok "Claude Code ..... available" } else { Write-Warn "Claude Code ..... not found" }
    if (Test-Cmd "codex")                { Write-Ok "Codex CLI ....... available" } else { Write-Warn "Codex CLI ....... not found" }
    if (Test-Cmd "opencode")             { Write-Ok "OpenCode ........ available" } else { Write-Warn "OpenCode ........ not found" }
    if (Test-Cmd "github-copilot-cli")   { Write-Ok "Copilot CLI ..... available" } else { Write-Warn "Copilot CLI ..... not found" }
    if (Test-Cmd "code")                 { Write-Ok "VS Code ......... available" } else { Write-Warn "VS Code ......... not found" }
    $coworkCfgCheck = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
    if ((Test-Path $coworkCfgCheck) -or (Test-Cmd "claude-desktop")) {
        Write-Ok "Cowork (Desktop)  available"
    } else { Write-Warn "Cowork (Desktop)  not found" }

    Write-Host ""
    if ($allOk) { Write-Ok "All tools installed. Token diet active." }
    else        { Write-Warn "Some tools missing. Re-run to install." }

    Write-Host @"

  +-----------------------------------------------------------+
  |  Claude Code / Codex / OpenCode / Copilot / VS Code       |
  |                    + Cowork (Desktop)                      |
  +-----------------------------------------------------------+
           |                |                |
     Library docs     Refactoring       Memory
           |                |                |
      +----------+      +---------+      +--------+
      | Context7 |      | Serena  |      |  ICM   |
      |  (HTTP)  |      |  (LSP)  |      | (recall)|
      +----------+      +---------+      +--------+
      current docs        LSP           cross-tool

"@
}

# --- Interactive wizard -------------------------------------------------------
function Invoke-Wizard {
    Write-Host ""
    Write-Host "  token-diet interactive installer" -ForegroundColor White
    Write-Host "  Serena + ICM + Context7 — security-patched forks + hosted docs" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  The stack — each tool is independent; install any subset:" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Serena  LSP symbol navigation" -ForegroundColor White
    Write-Host "          What: language-server rename / find-references / diagnostics." -ForegroundColor Gray
    Write-Host "          Why:  precise refactors without re-reading files." -ForegroundColor Gray
    Write-Host "          Gain: fewer wrong edits and fewer prompt turns on multi-file work." -ForegroundColor Gray
    Write-Host "  ICM     persistent cross-tool memory" -ForegroundColor White
    Write-Host "          What: a memory MCP server shared across Claude, Codex, Gemini, OpenCode." -ForegroundColor Gray
    Write-Host "          Why:  recall past decisions and facts instead of re-explaining each session." -ForegroundColor Gray
    Write-Host "          Gain: cross-session, cross-tool continuity — recall replaces re-reading." -ForegroundColor Gray
    Write-Host "  Context7 up-to-date library docs" -ForegroundColor White
    Write-Host "          What: remote HTTP MCP server serving current library documentation." -ForegroundColor Gray
    Write-Host "          Why:  models hallucinate APIs when trained on stale versions." -ForegroundColor Gray
    Write-Host "          Gain: correct, current API usage without pasting docs into context." -ForegroundColor Gray
    Write-Host ""

    # Which tools?
    $answer = Read-Host "Install the full stack (all 3)? [Y/n]  (n = choose individually)"
    if ($answer -match '^[Nn]') {
        $s = Read-Host "  + Serena   — rename / find-refs / diagnostics (LSP)?       [Y/n]"
        $i = Read-Host "  + ICM      — cross-tool memory, recall not re-explain?     [Y/n]"
        $c = Read-Host "  + Context7 — library docs via remote HTTP MCP?             [Y/n]"
        $script:WizardSerena   = $s -notmatch '^[Nn]'
        $script:WizardIcm      = $i -notmatch '^[Nn]'
        $script:WizardContext7 = $c -notmatch '^[Nn]'
    } else {
        $script:WizardSerena = $true; $script:WizardIcm = $true; $script:WizardContext7 = $true
    }

    # Local mode?
    $script:WizardLocal = $false
    $script:WizardSkipTests = $false
    $l = Read-Host "Air-gapped / local build? [y/N]"
    if ($l -match '^[Yy]') {
        $script:WizardLocal = $true
        $st = Read-Host "  Skip clippy + tests? (faster, not recommended) [y/N]"
        if ($st -match '^[Yy]') { $script:WizardSkipTests = $true }
    }

    Write-Host ""
    Write-Host "Ready to install:" -ForegroundColor White
    if ($script:WizardSerena)   { Write-Host "  + Serena"   -ForegroundColor Green }
    if ($script:WizardIcm)      { Write-Host "  + ICM"      -ForegroundColor Green }
    if ($script:WizardContext7) { Write-Host "  + Context7" -ForegroundColor Green }
    if ($script:WizardLocal)    { Write-Host "    Mode: LOCAL (air-gapped)" -ForegroundColor Yellow }
    Write-Host ""

    $confirm = Read-Host "Proceed? [Y/n]"
    if ($confirm -match '^[Nn]') { Write-Host "Aborted."; exit 0 }
}

# --- Main ---------------------------------------------------------------------
Write-Host "`n=== token-diet ===" -ForegroundColor White
Write-Host "    Serena + ICM + Context7`n" -ForegroundColor White

if ($DryRun) {
    Write-Host "    *** DRY-RUN MODE — no changes will be made ***`n" -ForegroundColor Magenta
}

if ($FullOutput) {
    Rotate-Log
    Write-Info "Full output mode — logged to $LogFile"
}

if ($VerifyOnly) { Detect-Hosts; Verify-Stack; exit 0 }

# Interactive mode when invoked with no arguments
$interactive = ($PSBoundParameters.Count -eq 0 -and $Tool -eq "All")
$script:WizardSerena   = $false
$script:WizardIcm      = $false
$script:WizardContext7 = $false

if ($interactive) {
    Invoke-Wizard
    $doSerena   = $script:WizardSerena
    $doIcm      = $script:WizardIcm
    $doContext7 = $script:WizardContext7
    if ($script:WizardLocal) { $Local = [switch]::new($true) }
    if ($script:WizardSkipTests) { $SkipTests = [switch]::new($true) }
} else {
    $doSerena   = $Tool -eq "All" -or $Tool -eq "Serena"
    $doIcm      = $Tool -eq "All" -or $Tool -eq "icm"
    $doContext7 = $Tool -eq "All" -or $Tool -eq "context7"
}

if ($Local) { Write-Host "    Mode: LOCAL (air-gapped)`n" -ForegroundColor Yellow }

Write-Header "Prerequisites"
Ensure-Git
if ($doIcm) { Ensure-Rust }
if ($doSerena -and -not $Local) { Ensure-Uv }
if ($doSerena -and $Local) { Ensure-Docker }

Detect-Hosts
Confirm-Hosts

if ($doSerena)   { Install-Serena }
if ($doIcm)      { Install-ICM }
if ($doContext7) { Install-Context7 }

# Inject token-diet usage rules into OpenCode mode prompts (idempotent)
Inject-OpenCodeRules

# Install token-diet CLI, dashboard, and host doc hooks
Install-TokenDiet

Verify-Stack
