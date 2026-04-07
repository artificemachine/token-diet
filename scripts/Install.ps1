#Requires -Version 5.1
<#
.SYNOPSIS
    token-diet: Install RTK + tilth + Serena on Windows.

.DESCRIPTION
    Installs the AI token optimization stack and configures for
    Claude Code, Codex CLI, OpenCode (GitHub Copilot), Copilot CLI,
    VS Code, and Cowork (Claude Desktop).

.PARAMETER Tool
    Which tool(s) to install: All (default), RTK, tilth, Serena

.PARAMETER SkipDedup
    Skip the Serena/tilth overlap fix.

.PARAMETER VerifyOnly
    Only check current installation status.

.PARAMETER Local
    Air-gapped mode: build from forks/ submodules instead of fetching from GitHub.

.PARAMETER SkipTests
    Skip clippy + tests in -Local mode (faster install).

.EXAMPLE
    .\Install.ps1                # install all
    .\Install.ps1 -Tool RTK     # RTK only
    .\Install.ps1 -VerifyOnly   # check status
    .\Install.ps1 -DryRun       # simulate install, no changes made
    .\Install.ps1 -Local         # air-gapped build from forks/
    .\Install.ps1 -FullOutput    # show all build output + log to file
#>

[CmdletBinding()]
param(
    [ValidateSet("All", "RTK", "tilth", "Serena")]
    [string]$Tool = "All",
    [switch]$SkipDedup,
    [switch]$VerifyOnly,
    [switch]$DryRun,
    [switch]$FullOutput,
    [switch]$Local,
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"

# --- Configuration -----------------------------------------------------------
$RTK_REPO    = "https://github.com/celstnblacc/rtk"
$TILTH_REPO  = "https://github.com/celstnblacc/tilth"
$SERENA_REPO = "https://github.com/celstnblacc/serena"

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
        Write-Info "Initializing submodules (forks\rtk, forks\tilth, forks\serena)..."
        git -C $script:ProjectRoot submodule update --init --recursive 2>&1 | Where-Object { $_ -match "Cloning|already|error" }
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

# --- RTK ----------------------------------------------------------------------
function Install-RTK {
    Write-Header "RTK (Rust Token Killer)"

    $rtkGainAvailable = $false
    if (Test-Cmd "rtk") {
        rtk gain --help 2>$null | Out-Null
        $rtkGainAvailable = ($LASTEXITCODE -eq 0)
    }

    if ($rtkGainAvailable) {
        Write-Ok "RTK already installed: $(rtk --version 2>$null)"
        Write-Info "Upgrading..."
    } elseif (Test-Cmd "rtk") {
        Write-Warn "Wrong 'rtk' detected. Reinstalling."
    }

    if ($Local) {
        $manifest = Join-Path $script:ProjectRoot "forks\rtk\Cargo.toml"
        if (-not (Test-Path $manifest)) { Write-Fail "forks\rtk\Cargo.toml not found — run: git submodule update --init --recursive" }
        Verify-LocalBuild "RTK" $manifest
        if ($DryRun) {
            Write-DryRun "cargo install --path $($script:ProjectRoot)\forks\rtk --force"
        } else {
            Write-Info "Building RTK from fork (air-gapped)..."
            cargo install --path (Join-Path $script:ProjectRoot "forks\rtk") --force 2>&1 | Show-Output
            Write-Ok "RTK built and installed from fork"
        }
    } else {
        if ($DryRun) {
            Write-DryRun "cargo install --git $RTK_REPO --force"
        } else {
            cargo install --git $RTK_REPO --force 2>&1 | Show-Output
            Write-Ok "RTK installed: $(rtk --version 2>$null)"
        }
    }

    # Host integration
    if ($script:HasClaude -and $script:HasOpenCode) {
        if ($DryRun) { Write-DryRun "rtk init -g --opencode" }
        else { try { rtk init -g --opencode 2>$null; Write-Ok "RTK: Claude Code + Codex + OpenCode" } catch { Write-Warn "RTK init failed" } }
    } elseif ($script:HasClaude) {
        if ($DryRun) { Write-DryRun "rtk init -g" }
        else { try { rtk init -g 2>$null; Write-Ok "RTK: Claude Code + Codex" } catch { Write-Warn "RTK init failed" } }
    }
    if ($script:HasCodex -and -not $script:HasClaude) {
        if ($DryRun) { Write-DryRun "rtk init --codex" }
        else { try { rtk init --codex 2>$null; Write-Ok "RTK: Codex CLI" } catch { Write-Warn "RTK Codex init failed" } }
    }
    if ($script:HasOpenCode -and -not $script:HasClaude) {
        if ($DryRun) { Write-DryRun "rtk init -g --opencode" }
        else { try { rtk init -g --opencode 2>$null; Write-Ok "RTK: OpenCode" } catch { Write-Warn "RTK OpenCode init failed" } }
    }
    if ($script:HasCopilot) {
        Write-Ok "RTK: Copilot CLI (uses same hooks as Claude Code)"
    }

    # Cowork (Claude Desktop) — no hook mechanism, inject awareness doc instead.
    # RTK works via shell hooks that rewrite Bash tool calls. Cowork/Claude Desktop
    # does not support the same hook dispatch, so we write an awareness markdown
    # that instructs the LLM to manually prefix commands with `rtk`.
    if ($script:HasCowork) {
        $coworkRtkDoc = @"
# RTK - Rust Token Killer (Cowork / Claude Desktop)

**Usage**: Token-optimized CLI proxy for shell commands (60-90% savings).

## Rule

Always prefix shell commands with ``rtk``. RTK compresses output to save tokens.
If RTK has no filter for a command, it passes through unchanged — always safe to use.

Examples:

``````bash
rtk git status
rtk cargo test
rtk npm run build
rtk pytest -q
rtk docker ps
rtk ls -la
``````

Even in command chains with ``&&``, prefix each command:
``````bash
rtk git add . && rtk git commit -m "msg" && rtk git push
``````

## Meta Commands

``````bash
rtk gain            # Token savings analytics
rtk gain --history  # Recent command savings history
rtk discover        # Analyze sessions for missed RTK usage
rtk proxy <cmd>     # Run raw command without filtering (debugging)
``````

## Verification

``````bash
rtk --version
rtk gain
where.exe rtk
``````
"@
        $coworkConfigDir = Join-Path $env:APPDATA "Claude"
        $coworkRtkFile = Join-Path $coworkConfigDir "rtk-awareness.md"
        if ($DryRun) {
            Write-DryRun "Write RTK awareness doc to $coworkRtkFile"
        } else {
            if (-not (Test-Path $coworkConfigDir)) { New-Item -ItemType Directory -Path $coworkConfigDir -Force | Out-Null }
            Set-Content -Path $coworkRtkFile -Value $coworkRtkDoc -Encoding UTF8
            Write-Ok "RTK: Cowork awareness doc written ($coworkRtkFile)"
            Write-Info "  Cowork has no hook support — LLM instructed to prefix commands with 'rtk'"
        }
    }
}

# --- tilth --------------------------------------------------------------------
function Install-Tilth {
    Write-Header "tilth (smart code reader)"

    if (Test-Cmd "tilth") {
        Write-Ok "tilth already installed"
        Write-Info "Upgrading..."
    }

    if ($Local) {
        $manifest = Join-Path $script:ProjectRoot "forks\tilth\Cargo.toml"
        if (-not (Test-Path $manifest)) { Write-Fail "forks\tilth\Cargo.toml not found — run: git submodule update --init --recursive" }
        Verify-LocalBuild "tilth" $manifest
        if ($DryRun) {
            Write-DryRun "cargo install --path $($script:ProjectRoot)\forks\tilth --force"
        } else {
            Write-Info "Building tilth from fork (air-gapped)..."
            cargo install --path (Join-Path $script:ProjectRoot "forks\tilth") --force 2>&1 | Show-Output
            Write-Ok "tilth built and installed from fork"
        }
    } else {
        if ($DryRun) {
            Write-DryRun "cargo install --git $TILTH_REPO --force"
        } else {
            cargo install --git $TILTH_REPO --force 2>&1 | Show-Output
            Write-Ok "tilth installed: $(tilth --version 2>$null)"
        }
    }

    # Host integration — tilth install <host>
    $hosts = @()
    if ($script:HasClaude)   { $hosts += "claude-code" }
    if ($script:HasCodex)    { $hosts += "codex" }
    if ($script:HasOpenCode) { $hosts += "opencode" }
    if ($script:HasCopilot)  { $hosts += "copilot" }
    if ($script:HasVSCode)   { $hosts += "vscode" }

    foreach ($h in $hosts) {
        if ($DryRun) {
            Write-DryRun "tilth install $h"
        } else {
            try { tilth install $h 2>$null; Write-Ok "tilth MCP: $h" }
            catch { Write-Warn "tilth MCP: $h failed (may already exist)" }
        }
    }

    if ($hosts.Count -eq 0) {
        Write-Warn "tilth: no AI host detected, skipping MCP registration"
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
        $serenaArgsBase = @("run", "--rm", "-i", "-v", "`$(pwd):/workspace:ro", "--network", "none", "token-diet/serena:latest")
    } else {
        $serenaCmdName = "uvx"
        $serenaArgsBase = @("--from", "git+$SERENA_REPO", "serena", "start-mcp-server")
    }

    # Claude Code
    if ($script:HasClaude) {
        if ($Local) {
            $claudeArgs = $serenaArgsBase + @("--context=claude-code", "--project", "/workspace")
        } else {
            $claudeArgs = $serenaArgsBase + @("--context=claude-code", "--project-from-cwd")
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
args = ["run", "--rm", "-i", "-v", ".:/workspace:ro", "--network", "none", "token-diet/serena:latest", "--context=codex", "--project", "/workspace"]
"@
                } else {
                    $tomlBlock = @"

# Serena MCP server (added by token-diet)
[mcp_servers.serena]
command = "uvx"
args = ["--from", "git+$SERENA_REPO", "serena", "start-mcp-server", "--context=codex", "--project-from-cwd"]
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
      "args": ["--from", "git+$SERENA_REPO", "serena", "start-mcp-server", "--context=ide", "--project-from-cwd"]
    },
    "tilth": {
      "command": "tilth",
      "args": ["mcp"]
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
            Write-DryRun "Write mcpServers.serena + mcpServers.tilth to $coworkCfg"
        } else {
            try {
                $data = if (Test-Path $coworkCfg) { Get-Content $coworkCfg -Raw | ConvertFrom-Json } else { [PSCustomObject]@{} }
                if (-not $data.PSObject.Properties["mcpServers"]) {
                    $data | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue ([PSCustomObject]@{})
                }
                if ($Local) {
                    $serenaEntry = [PSCustomObject]@{
                        command = "docker"
                        args    = @("run", "--rm", "-i", "-v", "`$(pwd):/workspace:ro", "--network", "none",
                                    "token-diet/serena:latest", "--context=claude-code", "--project", "/workspace")
                    }
                } else {
                    $serenaEntry = [PSCustomObject]@{
                        command = "uvx"
                        args    = @("--from", "git+$SERENA_REPO", "serena", "start-mcp-server",
                                    "--context=claude-code", "--project-from-cwd")
                    }
                }
                $data.mcpServers | Add-Member -NotePropertyName "serena" -NotePropertyValue $serenaEntry -Force

                # Also register tilth if installed
                if (Test-Cmd "tilth") {
                    $tilthEntry = [PSCustomObject]@{
                        command = "tilth"
                        args    = @("mcp")
                    }
                    $data.mcpServers | Add-Member -NotePropertyName "tilth" -NotePropertyValue $tilthEntry -Force
                }

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
                        args    = @("run", "--rm", "-i", "-v", "`$(pwd):/workspace:ro", "--network", "none",
                                    "token-diet/serena:latest", "--context=ide", "--project", "/workspace")
                    }
                } else {
                    $serenaEntry = [PSCustomObject]@{
                        command = "uvx"
                        args    = @("--from", "git+$SERENA_REPO", "serena", "start-mcp-server",
                                    "--context=ide", "--project-from-cwd")
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

# --- Overlap fix --------------------------------------------------------------
function Configure-Dedup {
    Write-Header "Overlap fix (Serena dedup)"

    if (-not (Test-Cmd "tilth")) {
        Write-Info "tilth not installed -- skipping dedup"
        return
    }

    $templateDir = Join-Path $env:USERPROFILE ".config\serena"
    if (-not (Test-Path $templateDir)) { New-Item -ItemType Directory -Path $templateDir -Force | Out-Null }

    $templateFile = Join-Path $templateDir "project.local.template.yml"
    $configSource = Join-Path $script:ProjectRoot "config\serena-dedup.template.yml"

    if ($DryRun) {
        Write-DryRun "Write serena dedup template to $templateFile"
    } else {
        if (Test-Path $configSource) {
            Copy-Item $configSource $templateFile -Force
        } else {
            @"
# Serena project.local.yml -- overlap fix when tilth is also installed
context: claude-code
disabled_tools:
  - get_symbols_overview
  - find_symbol
  - read_file
"@ | Set-Content -Path $templateFile -Encoding UTF8
        }
        Write-Ok "Dedup template: $templateFile"
    }
    Write-Info "Apply per project: Copy-Item '$templateFile' '<project>\project.local.yml'"
}

# --- Install token-diet CLI + docs -------------------------------------------
function Install-TokenDiet {
    Write-Header "token-diet CLI + dashboard"

    $binDir = Join-Path $env:LOCALAPPDATA "Programs\token-diet"
    $srcPs1 = Join-Path $script:ScriptDir "token-diet.ps1"
    $srcDash = Join-Path $script:ScriptDir "token-diet-dashboard"

    if (-not (Test-Path $srcPs1)) {
        Write-Warn "scripts\token-diet.ps1 not found — skipping CLI install"
        return
    }

    if ($DryRun) {
        Write-DryRun "Copy token-diet.ps1 to $binDir\token-diet.ps1"
        if (Test-Path $srcDash) { Write-DryRun "Copy token-diet-dashboard to $binDir\token-diet-dashboard" }
        Write-DryRun "Write token-diet.md to ~/.claude/ and ~/.codex/"
        Write-DryRun "Add @token-diet.md to CLAUDE.md / AGENTS.md"
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

    # Copy installer so `token-diet verify` works standalone
    Copy-Item (Join-Path $script:ScriptDir "Install.ps1") (Join-Path $binDir "Install.ps1") -Force

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
# TKD — token-diet unified CLI

``token-diet`` (``token-diet.ps1``) is the top-level command for the token-diet stack (RTK + tilth + Serena).

## Commands

``````powershell
token-diet gain       # Combined savings dashboard: RTK + tilth + Serena
token-diet version    # Installed versions of all three tools
token-diet verify     # Re-run installation verification
token-diet dashboard  # Open live browser dashboard
``````

## Rules

- **``token-diet`` is a real script.** Never assume it is a typo for ``rtk``.
- Run ``Get-Command token-diet`` if unsure whether it is installed.
- ``token-diet gain`` shows RTK tracked savings + tilth/Serena structural savings.
  RTK savings are exact (output compression). tilth + Serena savings are
  structural (smaller prompts, fewer turns) and shown as estimates.
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
            if ($instrContent -match '@RTK\.md') {
                # Insert before @RTK.md
                $instrContent = $instrContent -replace '(?m)^@RTK\.md', "@token-diet.md`n@RTK.md"
            } else {
                $instrContent += "`n@token-diet.md`n"
            }
            Set-Content -Path $instrFile -Value $instrContent -Encoding UTF8
            Write-Ok "@token-diet.md added to: $instrFile"
        }
    }
}

# --- Verification -------------------------------------------------------------
function Verify-Stack {
    Write-Header "Token Stack Verification"

    $allOk = $true

    $rtkGainAvailable = $false
    if (Test-Cmd "rtk") {
        rtk gain --help 2>$null | Out-Null
        $rtkGainAvailable = ($LASTEXITCODE -eq 0)
    }

    if ($rtkGainAvailable) {
        Write-Ok "RTK ............. $(rtk --version 2>$null)"
    } else { Write-Warn "RTK ............. not installed or wrong version"; $allOk = $false }

    if (Test-Cmd "tilth") {
        Write-Ok "tilth ........... $(tilth --version 2>$null)"
        $tilthIssue = Get-CodexMcpCommandIssue 'tilth'
        if ($tilthIssue) { Write-Warn $tilthIssue; $allOk = $false }
    } else { Write-Warn "tilth ........... not installed"; $allOk = $false }

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
      Code reading     Refactoring     Command output
           |                |                |
      +--------+      +---------+      +--------+
      | tilth  |      | Serena  |      |  RTK   |
      | (fast) |      |  (deep) |      | (filter)|
      +--------+      +---------+      +--------+
      tree-sitter        LSP           regex/truncate

"@
}

# --- Interactive wizard -------------------------------------------------------
function Invoke-Wizard {
    Write-Host ""
    Write-Host "  token-diet interactive installer" -ForegroundColor White
    Write-Host "  RTK + tilth + Serena — security-patched forks" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Tools:" -ForegroundColor Gray
    Write-Host "    RTK    — CLI output compression (60-90% token savings)" -ForegroundColor Gray
    Write-Host "    tilth  — smart code reading via tree-sitter AST" -ForegroundColor Gray
    Write-Host "    Serena — IDE-like symbol navigation via LSP" -ForegroundColor Gray
    Write-Host ""

    # Which tools?
    $answer = Read-Host "Install all three tools? [Y/n]"
    if ($answer -match '^[Nn]') {
        $r = Read-Host "  Install RTK?    [Y/n]"
        $t = Read-Host "  Install tilth?  [Y/n]"
        $s = Read-Host "  Install Serena? [Y/n]"
        $script:WizardRtk    = $r -notmatch '^[Nn]'
        $script:WizardTilth  = $t -notmatch '^[Nn]'
        $script:WizardSerena = $s -notmatch '^[Nn]'
    } else {
        $script:WizardRtk = $true; $script:WizardTilth = $true; $script:WizardSerena = $true
    }

    # Skip dedup?
    if ($script:WizardTilth -and $script:WizardSerena) {
        $d = Read-Host "Configure Serena/tilth overlap fix? [Y/n]"
        $script:WizardDedup = $d -notmatch '^[Nn]'
    } else {
        $script:WizardDedup = $false
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
    if ($script:WizardRtk)    { Write-Host "  + RTK"    -ForegroundColor Green }
    if ($script:WizardTilth)  { Write-Host "  + tilth"  -ForegroundColor Green }
    if ($script:WizardSerena) { Write-Host "  + Serena" -ForegroundColor Green }
    if ($script:WizardDedup)  { Write-Host "  + Overlap fix" -ForegroundColor Green }
    if ($script:WizardLocal)  { Write-Host "    Mode: LOCAL (air-gapped)" -ForegroundColor Yellow }
    Write-Host ""

    $confirm = Read-Host "Proceed? [Y/n]"
    if ($confirm -match '^[Nn]') { Write-Host "Aborted."; exit 0 }
}

# --- Main ---------------------------------------------------------------------
Write-Host "`n=== token-diet ===" -ForegroundColor White
Write-Host "    RTK + tilth + Serena`n" -ForegroundColor White

if ($DryRun) {
    Write-Host "    *** DRY-RUN MODE — no changes will be made ***`n" -ForegroundColor Magenta
}

if ($FullOutput) {
    Rotate-Log
    Write-Info "Full output mode — logged to $LogFile"
}

if ($VerifyOnly) { Detect-Hosts; Verify-Stack; exit 0 }

# Interactive mode when invoked with no arguments
$interactive = ($PSBoundParameters.Count -eq 0 -and $Tool -eq "All" -and -not $SkipDedup)
$script:WizardRtk    = $false
$script:WizardTilth  = $false
$script:WizardSerena = $false
$script:WizardDedup  = $true

if ($interactive) {
    Invoke-Wizard
    $doRtk    = $script:WizardRtk
    $doTilth  = $script:WizardTilth
    $doSerena = $script:WizardSerena
    $skipDedup = -not $script:WizardDedup
    if ($script:WizardLocal) { $Local = [switch]::new($true) }
    if ($script:WizardSkipTests) { $SkipTests = [switch]::new($true) }
} else {
    $doRtk    = $Tool -eq "All" -or $Tool -eq "RTK"
    $doTilth  = $Tool -eq "All" -or $Tool -eq "tilth"
    $doSerena = $Tool -eq "All" -or $Tool -eq "Serena"
    $skipDedup = $SkipDedup
}

if ($Local) { Write-Host "    Mode: LOCAL (air-gapped)`n" -ForegroundColor Yellow }

Write-Header "Prerequisites"
Ensure-Git
if ($doRtk -or $doTilth) { Ensure-Rust }
if ($doSerena -and -not $Local) { Ensure-Uv }
if ($doSerena -and $Local) { Ensure-Docker }

Detect-Hosts

if ($doRtk)    { Install-RTK }
if ($doTilth)  { Install-Tilth }
if ($doSerena) { Install-Serena }

if (-not $skipDedup -and $doTilth -and $doSerena) { Configure-Dedup }

# Install token-diet CLI, dashboard, and host doc hooks
Install-TokenDiet

Verify-Stack
