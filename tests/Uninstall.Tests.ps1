#Requires -Module Pester
<#
.SYNOPSIS
    Pester tests for scripts/Uninstall.ps1 (Windows).

.NOTES
    Run on Windows or WSL with PowerShell 7+:
        Invoke-Pester tests/Uninstall.Tests.ps1 -Output Detailed

    Requires Pester v5:
        Install-Module Pester -Force -SkipPublisherCheck
#>

BeforeAll {
    $ScriptPath = Join-Path $PSScriptRoot "..\scripts\Uninstall.ps1"
    # Use a temp directory as fake USERPROFILE/APPDATA for isolation
    $TmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) "token-diet-test-$(New-Guid)"
    New-Item -ItemType Directory -Path $TmpRoot -Force | Out-Null

    # Mimic Windows env vars pointing at temp dirs
    $env:USERPROFILE  = $TmpRoot
    $env:APPDATA      = Join-Path $TmpRoot "AppData\Roaming"
    $env:LOCALAPPDATA = Join-Path $TmpRoot "AppData\Local"

    foreach ($dir in @(
        (Join-Path $env:APPDATA "Claude"),
        (Join-Path $env:LOCALAPPDATA "Programs\token-diet"),
        (Join-Path $TmpRoot ".claude\hooks"),
        (Join-Path $TmpRoot ".codex"),
        (Join-Path $TmpRoot ".serena\memories")
    )) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

AfterAll {
    Remove-Item -Recurse -Force $TmpRoot -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Cycle 5.1 — Uninstall.ps1: -DryRun skeleton
# ---------------------------------------------------------------------------

Describe "Uninstall.ps1 -DryRun" {
    It "exits 0 and prints dry-run" {
        $output = & $ScriptPath -DryRun -Force 2>&1
        $LASTEXITCODE | Should -Be 0
        $output | Should -Match "(?i)dry.run"
    }

    It "does not remove a file that exists" {
        $bin = Join-Path $env:LOCALAPPDATA "Programs\token-diet\token-diet.exe"
        New-Item -ItemType File -Path $bin -Force | Out-Null

        & $ScriptPath -DryRun -Force 2>&1 | Out-Null

        $bin | Should -Exist
    }
}

# ---------------------------------------------------------------------------
# Cycle 5.2 — Uninstall.ps1: -Force removes binaries
# ---------------------------------------------------------------------------

Describe "Uninstall.ps1 -Force" {
    It "removes token-diet.exe from Programs dir" {
        $bin = Join-Path $env:LOCALAPPDATA "Programs\token-diet\token-diet.exe"
        New-Item -ItemType File -Path $bin -Force | Out-Null

        & $ScriptPath -Force 2>&1 | Out-Null

        $bin | Should -Not -Exist
    }

    It "removes MCP keys from claude_desktop_config.json" {
        $cfg = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
        @{ mcpServers = @{ tilth = @{ command = "tilth" }; serena = @{ command = "serena" } } } |
            ConvertTo-Json -Depth 5 | Set-Content $cfg -Encoding UTF8

        & $ScriptPath -Force 2>&1 | Out-Null

        $json = Get-Content $cfg -Raw | ConvertFrom-Json
        $json.mcpServers.PSObject.Properties.Name | Should -Not -Contain "tilth"
        $json.mcpServers.PSObject.Properties.Name | Should -Not -Contain "serena"
    }

    It "preserves serena memories without -IncludeData" {
        $mem = Join-Path $env:USERPROFILE ".serena\memories\test.md"
        New-Item -ItemType File -Path $mem -Force | Out-Null

        & $ScriptPath -Force 2>&1 | Out-Null

        $mem | Should -Exist
    }

    It "removes serena memories with -IncludeData" {
        $mem = Join-Path $env:USERPROFILE ".serena\memories\test.md"
        New-Item -ItemType File -Path $mem -Force | Out-Null

        & $ScriptPath -Force -IncludeData 2>&1 | Out-Null

        $mem | Should -Not -Exist
    }
}
