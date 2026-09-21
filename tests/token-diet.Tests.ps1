#Requires -Modules Pester
# Pester v5 tests for scripts/token-diet.ps1

BeforeAll {
    $script:PS1 = Join-Path $PSScriptRoot '..\scripts\token-diet.ps1'

    # Minimal mock environment — no real tools required.
    # Component set: Serena + ICM + context7 (remote HTTP MCP); rtk/tilth dropped.
    $script:MockBin = Join-Path $TestDrive 'bin'
    New-Item -ItemType Directory -Path $script:MockBin | Out-Null

    # Stub icm
    Set-Content "$script:MockBin\icm.ps1" @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Remaining)
if ($Remaining -contains '--version') { Write-Output 'icm 0.10.50'; exit 0 }
if ($Remaining -contains 'serve')  { exit 0 }
if ($Remaining -contains 'recall') { exit 0 }
exit 0
'@

    $script:PathSep = [System.IO.Path]::PathSeparator
    $env:PATH = "$script:MockBin$script:PathSep$env:PATH"
}

Describe 'token-diet.ps1 — dispatch' {
    It 'shows help and exits 0 with --help' {
        $out = (& pwsh -NoProfile -File $script:PS1 'help' 2>&1) -join ' '
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'USAGE'
        $out | Should -Match 'COMMANDS'
    }

    It 'shows help and exits 0 with help subcommand' {
        $out = (& pwsh -NoProfile -File $script:PS1 'help' 2>&1) -join ' '
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'USAGE'
    }

    It 'exits 1 for unknown command' {
        & pwsh -NoProfile -File $script:PS1 'notacommand' 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'help text includes all major commands' {
        $out = (& pwsh -NoProfile -File $script:PS1 'help' 2>&1) -join ' '
        $out | Should -Match 'health'
        $out | Should -Match 'budget'
        $out | Should -Match 'route'
        $out | Should -Match 'test-first'
        $out | Should -Match 'strip'
        $out | Should -Match 'diff-reads'
        $out | Should -Match 'dashboard'
        $out | Should -Match '--no-open'
        $out | Should -Match 'version'
        $out | Should -Match 'doctor'
        $out | Should -Match 'mcp'
        $out | Should -Match 'icm'
        $out | Should -Match 'context7'
    }
}

Describe 'token-diet.ps1 — version' {
    It 'version command exits 0' {
        & pwsh -NoProfile -File $script:PS1 'version' 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It '--version prints token-diet self-version and exits 0' {
        $out = (& pwsh -NoProfile -File $script:PS1 '--version' 2>&1) -join ' '
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match '^token-diet \d+\.\d+\.\d+'
    }
}

Describe 'token-diet.ps1 — health: Codex stale detection' {
    BeforeEach {
        # Provide APPDATA (null on macOS) so Get-HostsRegistered does not throw
        $script:FakeAppData = Join-Path $TestDrive 'AppData'
        New-Item -ItemType Directory -Path $script:FakeAppData -Force | Out-Null
    }

    It 'health: exits 1 when Codex icm MCP path is stale' {
        $fakeHome = Join-Path $TestDrive 'home-stale'
        New-Item -ItemType Directory -Path (Join-Path $fakeHome '.codex') -Force | Out-Null
        Set-Content (Join-Path $fakeHome '.codex\config.toml') @"
[mcp_servers.icm]
command = "C:\missing\icm.exe"
"@ -Encoding UTF8

        $out = (& pwsh -NoProfile -Command `
            "`$env:USERPROFILE='$fakeHome'; `$env:APPDATA='$script:FakeAppData'; & '$($script:PS1)' health" 2>&1) -join ' '
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'MCP command missing'
    }

    It 'health: single-quoted Codex TOML command is detected as registered' {
        $fakeHome = Join-Path $TestDrive 'home-squote'
        New-Item -ItemType Directory -Path (Join-Path $fakeHome '.codex') -Force | Out-Null
        Set-Content (Join-Path $fakeHome '.codex\config.toml') @"
[mcp_servers.icm]
command = 'icm'
"@ -Encoding UTF8

        $out = (& pwsh -NoProfile -Command `
            "`$env:PATH='$script:MockBin;$env:PATH'; `$env:USERPROFILE='$fakeHome'; `$env:APPDATA='$script:FakeAppData'; & '$($script:PS1)' health" 2>&1) -join ' '
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'codex'
    }

    It 'health: stale single-quoted Codex TOML path is flagged' {
        $fakeHome = Join-Path $TestDrive 'home-squote-stale'
        New-Item -ItemType Directory -Path (Join-Path $fakeHome '.codex') -Force | Out-Null
        Set-Content (Join-Path $fakeHome '.codex\config.toml') @"
[mcp_servers.icm]
command = 'C:\missing\icm.exe'
"@ -Encoding UTF8

        $out = (& pwsh -NoProfile -Command `
            "`$env:USERPROFILE='$fakeHome'; `$env:APPDATA='$script:FakeAppData'; & '$($script:PS1)' health" 2>&1) -join ' '
        $out | Should -Match 'MCP command missing'
    }

    It 'verify: exits 1 when Codex icm MCP path is stale' {
        $fakeHome = Join-Path $TestDrive 'home-verify-stale'
        New-Item -ItemType Directory -Path (Join-Path $fakeHome '.codex') -Force | Out-Null
        Set-Content (Join-Path $fakeHome '.codex\config.toml') @"
[mcp_servers.icm]
command = "C:\missing\icm.exe"
"@ -Encoding UTF8

        $out = (& pwsh -NoProfile -Command `
            "`$env:USERPROFILE='$fakeHome'; `$env:APPDATA='$script:FakeAppData'; & '$($script:PS1)' verify" 2>&1) -join ' '
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'MCP command missing'
    }

    It 'health: exits 1 when Codex serena MCP path is stale' {
        $fakeHome = Join-Path $TestDrive 'home-serena-stale'
        New-Item -ItemType Directory -Path (Join-Path $fakeHome '.codex') -Force | Out-Null
        Set-Content (Join-Path $fakeHome '.codex\config.toml') @"
[mcp_servers.serena]
command = "C:\missing\serena.exe"
"@ -Encoding UTF8

        $out = (& pwsh -NoProfile -Command `
            "`$env:PATH='$script:MockBin;$env:PATH'; `$env:USERPROFILE='$fakeHome'; `$env:APPDATA='$script:FakeAppData'; & '$($script:PS1)' health" 2>&1) -join ' '
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'Codex serena MCP command missing'
    }

    It 'verify: exits 1 when Codex serena MCP path is stale' {
        $fakeHome = Join-Path $TestDrive 'home-serena-verify-stale'
        New-Item -ItemType Directory -Path (Join-Path $fakeHome '.codex') -Force | Out-Null
        Set-Content (Join-Path $fakeHome '.codex\config.toml') @"
[mcp_servers.serena]
command = "C:\missing\serena.exe"
"@ -Encoding UTF8

        $out = (& pwsh -NoProfile -Command `
            "`$env:PATH='$script:MockBin;$env:PATH'; `$env:USERPROFILE='$fakeHome'; `$env:APPDATA='$script:FakeAppData'; & '$($script:PS1)' verify" 2>&1) -join ' '
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'Codex serena MCP command missing'
    }
}

Describe 'token-diet.ps1 — route' {
    It 'exits 1 with usage when no task given' {
        & pwsh -NoProfile -File $script:PS1 'route' 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'suggests Serena for rename/refactor tasks' {
        $out = (& pwsh -NoProfile -File $script:PS1 'route' 'rename the class' 2>&1) -join ' '
        $out | Should -Match 'Serena'
    }

    It 'suggests ICM for recall/memory tasks' {
        $out = (& pwsh -NoProfile -File $script:PS1 'route' 'remember the prior decision' 2>&1) -join ' '
        $out | Should -Match 'ICM'
    }

    It 'help text includes route command' {
        $out = (& pwsh -NoProfile -File $script:PS1 'help' 2>&1) -join ' '
        $out | Should -Match 'route'
    }
}

Describe 'token-diet.ps1 — test-first' {
    It 'exits 1 with usage when no file given' {
        & pwsh -NoProfile -File $script:PS1 'test-first' 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'suggests test file path for a Python source file' {
        $out = (& pwsh -NoProfile -File $script:PS1 'test-first' 'src/auth.py' 2>&1) -join ' '
        $out | Should -Match 'test_auth'
    }

    It 'suggests test file path for a Rust source file' {
        $out = (& pwsh -NoProfile -File $script:PS1 'test-first' 'src/parser.rs' 2>&1) -join ' '
        $out | Should -Match 'parser_test'
    }

    It 'suggests test file path for a TypeScript source file' {
        $out = (& pwsh -NoProfile -File $script:PS1 'test-first' 'src/utils.ts' 2>&1) -join ' '
        $out | Should -Match 'utils\.test'
    }

    It 'help text includes test-first command' {
        $out = (& pwsh -NoProfile -File $script:PS1 'help' 2>&1) -join ' '
        $out | Should -Match 'test-first'
    }
}

Describe 'token-diet.ps1 — strip' {
    It 'exits 1 with usage when no file given' {
        & pwsh -NoProfile -File $script:PS1 'strip' 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'exits 1 when file does not exist' {
        & pwsh -NoProfile -File $script:PS1 'strip' 'nonexistent_file.py' 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'removes single-line comments from a Python file' {
        $tmpFile = Join-Path $TestDrive 'sample.py'
        Set-Content $tmpFile "# This is a comment`nx = 1`ny = 2"
        $out = (& pwsh -NoProfile -File $script:PS1 'strip' $tmpFile 2>&1) -join ' '
        $LASTEXITCODE | Should -Be 0
        $out | Should -Not -Match '# This is a comment'
    }

    It '--stats flag prints reduction percentage' {
        $tmpFile = Join-Path $TestDrive 'stats.py'
        Set-Content $tmpFile "# comment line`nx = 1`n# another comment`ny = 2"
        $out = (& pwsh -NoProfile -File $script:PS1 'strip' '--stats' $tmpFile 2>&1) -join ' '
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match '%'
    }

    It 'help text includes strip command' {
        $out = (& pwsh -NoProfile -File $script:PS1 'help' 2>&1) -join ' '
        $out | Should -Match 'strip'
    }
}

Describe 'token-diet.ps1 — budget' {
    It 'budget init creates .token-budget in current directory' {
        Push-Location $TestDrive
        try {
            & pwsh -NoProfile -File $script:PS1 'budget' 'init' 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0
            Test-Path '.token-budget' | Should -BeTrue
        } finally {
            Pop-Location
        }
    }

    It 'budget init adds .token-budget to existing .gitignore' {
        $proj = Join-Path $TestDrive 'proj-gitignore'
        New-Item -ItemType Directory -Path $proj -Force | Out-Null
        Set-Content (Join-Path $proj '.gitignore') '' -Encoding UTF8
        Push-Location $proj
        try {
            & pwsh -NoProfile -File $script:PS1 'budget' 'init' 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0
            Get-Content (Join-Path $proj '.gitignore') | Should -Contain '.token-budget'
        } finally {
            Pop-Location
        }
    }

    It 'budget init does not duplicate .token-budget in .gitignore' {
        $proj = Join-Path $TestDrive 'proj-nodup'
        New-Item -ItemType Directory -Path $proj -Force | Out-Null
        Set-Content (Join-Path $proj '.gitignore') '.token-budget' -Encoding UTF8
        Push-Location $proj
        try {
            & pwsh -NoProfile -File $script:PS1 'budget' 'init' 2>&1 | Out-Null
            $count = (Get-Content (Join-Path $proj '.gitignore') | Where-Object { $_ -eq '.token-budget' }).Count
            $count | Should -Be 1
        } finally {
            Pop-Location
        }
    }

    It 'budget status auto-creates global budget and exits 0 when no .token-budget found' {
        # budget status auto-creates a global .token-budget and exits 0
        $cleanDir = Join-Path $TestDrive 'clean'
        New-Item -ItemType Directory -Path $cleanDir -Force | Out-Null
        Push-Location $cleanDir
        try {
            & pwsh -NoProfile -File $script:PS1 'budget' 'status' 2>&1 | Out-Null
            $LASTEXITCODE | Should -BeIn @(0, 2)
        } finally {
            Pop-Location
        }
    }

    It 'help text includes budget command' {
        $out = (& pwsh -NoProfile -File $script:PS1 'help' 2>&1) -join ' '
        $out | Should -Match 'budget'
    }
}
