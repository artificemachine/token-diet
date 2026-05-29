#Requires -Version 5.1
<#
.SYNOPSIS
    token-diet uninstaller for Windows.

.DESCRIPTION
    Reverses all changes made by Install.ps1: removes binaries, MCP registrations,
    config files, hooks, and doc files written by the token-diet installer.

.PARAMETER DryRun
    Preview what would be removed without making any changes.

.PARAMETER Force
    Skip confirmation prompts.

.PARAMETER IncludeData
    Also remove ~/.serena/memories (preserved by default).

.PARAMETER IncludeDocker
    Also remove the token-diet/serena Docker image.

.EXAMPLE
    .\Uninstall.ps1 -DryRun
    .\Uninstall.ps1 -Force
    .\Uninstall.ps1 -Force -IncludeData
#>
param(
    [switch]$DryRun,
    [switch]$Force,
    [switch]$IncludeData,
    [switch]$IncludeDocker
)

$ErrorActionPreference = "Stop"

# --- Helpers ------------------------------------------------------------------
function Write-Ok      { param($msg) Write-Host "  [ok]      $msg" -ForegroundColor Green }
function Write-Miss    { param($msg) Write-Host "  [skip]    $msg (not found)" -ForegroundColor DarkGray }
function Write-DryMsg  { param($msg) Write-Host "  [dry-run] $msg" -ForegroundColor Magenta }
function Write-Header  { param($msg) Write-Host "`n$msg" -ForegroundColor White }

function Remove-TokenDietFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        Write-Miss $Path
        return
    }
    if ($DryRun) {
        Write-DryMsg "Remove-Item '$Path'"
    } else {
        Remove-Item -Force -Recurse -Path $Path -ErrorAction SilentlyContinue
        Write-Ok "Removed $Path"
    }
}

function Remove-JsonMcpKey {
    param([string]$ConfigPath, [string]$Key)
    if (-not (Test-Path $ConfigPath)) {
        Write-Miss "$ConfigPath (mcpServers.$Key)"
        return
    }
    if ($DryRun) {
        Write-DryMsg "Remove mcpServers.$Key from $ConfigPath"
        return
    }
    try {
        $json = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        if ($json.mcpServers -and $json.mcpServers.PSObject.Properties[$Key]) {
            $json.mcpServers.PSObject.Properties.Remove($Key)
            $json | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding UTF8
            Write-Ok "Removed mcpServers.$Key from $ConfigPath"
        } else {
            Write-Miss "$ConfigPath (mcpServers.$Key)"
        }
    } catch {
        Write-Host "  [warn]    Failed to update $ConfigPath`: $_" -ForegroundColor Yellow
    }
}

function Remove-VsCodeTemplateServer {
    param([string]$ConfigPath, [string]$Key)
    if (-not (Test-Path $ConfigPath)) {
        Write-Miss "$ConfigPath (servers.$Key)"
        return
    }
    if ($DryRun) {
        Write-DryMsg "Remove servers.$Key from $ConfigPath"
        return
    }
    try {
        $json = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        if ($json.servers -and $json.servers.PSObject.Properties[$Key]) {
            $json.servers.PSObject.Properties.Remove($Key)
            $json | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding UTF8
            Write-Ok "Removed servers.$Key from $ConfigPath"
        } else {
            Write-Miss "$ConfigPath (servers.$Key)"
        }
    } catch {
        Write-Host "  [warn]    Failed to update $ConfigPath`: $_" -ForegroundColor Yellow
    }
}

function Remove-LineFromFile {
    param([string]$FilePath, [string]$Pattern)
    if (-not (Test-Path $FilePath)) {
        Write-Miss "$FilePath ($Pattern)"
        return
    }
    if ($DryRun) {
        Write-DryMsg "Remove '$Pattern' from $FilePath"
        return
    }
    $lines = Get-Content $FilePath | Where-Object { $_ -notmatch [regex]::Escape($Pattern) }
    $lines | Set-Content $FilePath -Encoding UTF8
    Write-Ok "Removed '$Pattern' from $FilePath"
}

function Confirm-Continue {
    param([string]$Message)
    if ($Force) { return }
    Write-Host $Message -ForegroundColor Yellow
    $reply = Read-Host "Continue? [y/N]"
    if ($reply -notmatch '^[Yy]') {
        Write-Host "Aborted." -ForegroundColor Gray
        exit 0
    }
}

# --- Paths --------------------------------------------------------------------
$UserProfile  = $env:USERPROFILE
$AppData      = $env:APPDATA
$LocalAppData = $env:LOCALAPPDATA

$BinDir       = Join-Path $LocalAppData "Programs\token-diet"
$CargoBin     = Join-Path $UserProfile ".cargo\bin"
$ClaudeConfig = Join-Path $AppData "Claude\claude_desktop_config.json"
$OpenCode     = Join-Path $UserProfile ".opencode.json"
$CodexToml    = Join-Path $UserProfile ".codex\config.toml"
$ClaudeDir    = Join-Path $UserProfile ".claude"
$CodexDir     = Join-Path $UserProfile ".codex"
$ClaudeMd     = Join-Path $ClaudeDir "token-diet.md"
$CodexMd      = Join-Path $CodexDir "token-diet.md"
$SerenaDir    = Join-Path $UserProfile ".serena"
$ConfigDir    = Join-Path $AppData "token-diet"
# ICM honors ~/.config/icm/config.toml on all platforms (matches install.sh).
$IcmConfig    = Join-Path $UserProfile ".config\icm\config.toml"
# Shared VS Code MCP template (top-level "servers" key), written by the installer.
$VsCodeTemplate = Join-Path $ConfigDir "vscode-mcp.template.json"

# --- Main ---------------------------------------------------------------------
Write-Host "`ntoken-diet uninstall (Windows)`n" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "  Dry-run mode — no files will be removed`n" -ForegroundColor DarkGray
}

if (-not $Force -and -not $DryRun) {
    Confirm-Continue "This will remove token-diet binaries, MCP registrations, and config files."
}

# Binaries
Write-Header "Binaries"
Remove-TokenDietFile (Join-Path $BinDir "token-diet.exe")
Remove-TokenDietFile (Join-Path $BinDir "token-diet-dashboard")
Remove-TokenDietFile (Join-Path $BinDir "token-diet-mcp")

# Rust binaries
Write-Header "Rust binaries (cargo uninstall)"
if (Get-Command cargo -ErrorAction SilentlyContinue) {
    foreach ($crate in @("rtk", "tilth", "icm")) {
        if ($DryRun) {
            Write-DryMsg "cargo uninstall $crate"
        } else {
            $result = cargo uninstall $crate 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "cargo uninstall $crate"
            } else {
                Write-Miss "$crate (not installed)"
            }
        }
    }
} else {
    Write-Miss "cargo not found — skipping Rust binary removal"
}

# MCP registrations — Claude Desktop
Write-Header "MCP registrations — Claude Desktop"
Remove-JsonMcpKey $ClaudeConfig "tilth"
Remove-JsonMcpKey $ClaudeConfig "serena"
Remove-JsonMcpKey $ClaudeConfig "icm"

# MCP registrations — OpenCode
Write-Header "MCP registrations — OpenCode"
Remove-JsonMcpKey $OpenCode "tilth"
Remove-JsonMcpKey $OpenCode "serena"
Remove-JsonMcpKey $OpenCode "icm"

# MCP registrations — VS Code template (uses top-level "servers", not "mcpServers")
Write-Header "MCP registrations — VS Code template"
Remove-VsCodeTemplateServer $VsCodeTemplate "icm"

# MCP registrations — Codex TOML
Write-Header "MCP registrations — Codex TOML"
if (Test-Path $CodexToml) {
    if ($DryRun) {
        Write-DryMsg "Remove [mcp_servers.{tilth,serena,icm}] from $CodexToml"
    } else {
        $content = Get-Content $CodexToml -Raw
        $content = $content -replace '(?ms)\[mcp_servers\.(tilth|serena|icm)\][^\[]*', ''
        Set-Content $CodexToml -Value $content -Encoding UTF8
        Write-Ok "Removed mcp_servers.{tilth,serena,icm} from $CodexToml"
    }
} else {
    Write-Miss $CodexToml
}

# Hooks and docs
Write-Header "Hooks and docs"
Remove-TokenDietFile (Join-Path $ClaudeDir "hooks\rtk-rewrite.sh")
Remove-TokenDietFile $ClaudeMd
Remove-TokenDietFile $CodexMd

# Instruction file references
Write-Header "Instruction file references"
Remove-LineFromFile (Join-Path $ClaudeDir "CLAUDE.md")  "@token-diet.md"
Remove-LineFromFile (Join-Path $CodexDir  "AGENTS.md")   "@token-diet.md"

# Config directories
Write-Header "Config directories"
Remove-TokenDietFile $ConfigDir

# Serena memories + ICM config (opt-in)
if ($IncludeData) {
    Write-Header "Serena memories (-IncludeData)"
    Remove-TokenDietFile (Join-Path $SerenaDir "memories")

    Write-Header "ICM config (-IncludeData)"
    Remove-TokenDietFile $IcmConfig
}

# Docker image (opt-in)
if ($IncludeDocker) {
    Write-Header "Docker image (-IncludeDocker)"
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-DryMsg "docker rmi token-diet/serena:latest"
        } else {
            docker rmi token-diet/serena:latest 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "Removed Docker image token-diet/serena:latest"
            } else {
                Write-Miss "token-diet/serena:latest (not found)"
            }
        }
    } else {
        Write-Miss "docker not found"
    }
}

Write-Host ""
if ($DryRun) {
    Write-Host "  Dry-run complete — no changes made" -ForegroundColor DarkGray
} else {
    Write-Host "  token-diet uninstalled" -ForegroundColor Green
}
Write-Host ""
exit 0
