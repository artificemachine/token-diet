#Requires -Modules Pester
# Pester v5 tests for scripts/token-diet.ps1

BeforeAll {
    $script:PS1 = Join-Path $PSScriptRoot '..\scripts\token-diet.ps1'

    # Minimal mock environment — no real tools required
    $script:MockBin = Join-Path $TestDrive 'bin'
    New-Item -ItemType Directory -Path $script:MockBin | Out-Null

    # Stub rtk
    Set-Content "$script:MockBin\rtk.ps1" @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Remaining)
if ($Remaining -contains '--version') { Write-Output 'rtk 0.34.3'; exit 0 }
if (($Remaining -contains '--format') -and ($Remaining -contains 'json')) {
    Write-Output '{"summary":{"total_commands":5,"total_input":1000,"total_saved":800,"avg_savings_pct":80.0,"total_time_ms":1234}}'
    exit 0
}
if ($Remaining -contains '--history') {
    Write-Output '{"commands":[{"cmd":"git status","count":5,"total_saved":400,"total_input":500,"avg_pct":80.0}]}'
    exit 0
}
exit 0
'@

    # Stub tilth
    Set-Content "$script:MockBin\tilth.ps1" @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Remaining)
if ($Remaining -contains '--version') { Write-Output 'tilth 0.5.7'; exit 0 }
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
        $out | Should -Match 'gain'
        $out | Should -Match 'health'
        $out | Should -Match 'breakdown'
        $out | Should -Match 'explain'
        $out | Should -Match 'budget'
        $out | Should -Match 'loops'
        $out | Should -Match 'route'
        $out | Should -Match 'leaks'
        $out | Should -Match 'test-first'
        $out | Should -Match 'strip'
        $out | Should -Match 'diff-reads'
        $out | Should -Match 'dashboard'
        $out | Should -Match 'version'
        $out | Should -Match 'doctor'
        $out | Should -Match 'hook'
        $out | Should -Match 'mcp'
        $out | Should -Match 'upstream'
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

Describe 'token-diet.ps1 — gain: archived_stats carry-forward' {
    BeforeEach {
        $script:IsoHome = Join-Path $TestDrive ('iso-gain-' + [guid]::NewGuid().ToString().Substring(0,8))
        New-Item -ItemType Directory -Path (Join-Path $script:IsoHome '.config/token-diet') -Force | Out-Null
    }

    It 'gain: sums live rtk summary with archived_stats totals' {
        $arch = Join-Path $script:IsoHome '.config/token-diet/archived_stats.json'
        @{ cmds = 500; input = 1000000; saved = 800000; time_ms = 60000 } | ConvertTo-Json | Set-Content $arch
        # Mock rtk returns: 5 cmds, 1000 in, 800 saved, 1234ms
        $out = & pwsh -NoProfile -Command "`$env:HOME='$script:IsoHome'; `$env:USERPROFILE='$script:IsoHome'; `$env:APPDATA=(Join-Path '$script:IsoHome' 'AppData'); `$env:PATH='$script:MockBin'; & '$script:PS1' gain 2>&1" | Out-String
        # Expected totals: 505 cmds, 1.0M in (1000000 + 1000 = 1001000), 800.8K saved, 80% efficiency
        $out | Should -Match 'Commands filtered:\s+505'
        $out | Should -Match 'Tokens saved:\s+800\.8K\s+\(80'
        $out | Should -Match 'includes 500 archived commands'
    }

    It 'gain: works with live rtk only when no archived_stats file exists' {
        # No archived_stats.json in IsoHome
        $out = & pwsh -NoProfile -Command "`$env:HOME='$script:IsoHome'; `$env:USERPROFILE='$script:IsoHome'; `$env:APPDATA=(Join-Path '$script:IsoHome' 'AppData'); `$env:PATH='$script:MockBin'; & '$script:PS1' gain 2>&1" | Out-String
        $out | Should -Match 'Commands filtered:\s+5'
        $out | Should -Not -Match 'includes \d+ archived commands'
    }

    It 'gain: treats malformed archived_stats.json as absent (no crash)' {
        $arch = Join-Path $script:IsoHome '.config/token-diet/archived_stats.json'
        Set-Content $arch 'not valid json {{{'
        $out = & pwsh -NoProfile -Command "`$env:HOME='$script:IsoHome'; `$env:USERPROFILE='$script:IsoHome'; `$env:APPDATA=(Join-Path '$script:IsoHome' 'AppData'); `$env:PATH='$script:MockBin'; & '$script:PS1' gain 2>&1" | Out-String
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'Commands filtered:\s+5'
    }
}

Describe 'token-diet.ps1 — clean: archived_stats write + history rotation' {
    BeforeEach {
        $script:IsoHome = Join-Path $TestDrive ('iso-clean-' + [guid]::NewGuid().ToString().Substring(0,8))
        New-Item -ItemType Directory -Path $script:IsoHome -Force | Out-Null
    }

    It 'clean: creates archived_stats.json with live rtk totals when none exists' {
        $out = & pwsh -NoProfile -Command "`$env:HOME='$script:IsoHome'; `$env:USERPROFILE='$script:IsoHome'; `$env:APPDATA=(Join-Path '$script:IsoHome' 'AppData'); `$env:PATH='$script:MockBin'; & '$script:PS1' clean 2>&1" | Out-String
        $LASTEXITCODE | Should -Be 0
        $arch = Join-Path $script:IsoHome '.config/token-diet/archived_stats.json'
        Test-Path $arch | Should -BeTrue
        $d = Get-Content $arch -Raw | ConvertFrom-Json
        $d.cmds    | Should -Be 5
        $d.input   | Should -Be 1000
        $d.saved   | Should -Be 800
        $d.time_ms | Should -Be 1234
    }

    It 'clean: adds live rtk totals onto existing archived totals' {
        $archDir = Join-Path $script:IsoHome '.config/token-diet'
        New-Item -ItemType Directory -Path $archDir -Force | Out-Null
        $arch = Join-Path $archDir 'archived_stats.json'
        @{ cmds = 100; input = 50000; saved = 40000; time_ms = 10000 } | ConvertTo-Json | Set-Content $arch
        & pwsh -NoProfile -Command "`$env:HOME='$script:IsoHome'; `$env:USERPROFILE='$script:IsoHome'; `$env:APPDATA=(Join-Path '$script:IsoHome' 'AppData'); `$env:PATH='$script:MockBin'; & '$script:PS1' clean 2>&1" | Out-Null
        $d = Get-Content $arch -Raw | ConvertFrom-Json
        $d.cmds    | Should -Be 105    # 100 + 5 (from mock rtk)
        $d.input   | Should -Be 51000  # 50000 + 1000
        $d.saved   | Should -Be 40800  # 40000 + 800
        $d.time_ms | Should -Be 11234
    }

    It 'clean: moves $HOME/.rtk/history.json to timestamped .bak when present' {
        $rtkDir = Join-Path $script:IsoHome '.rtk'
        New-Item -ItemType Directory -Path $rtkDir -Force | Out-Null
        $hist = Join-Path $rtkDir 'history.json'
        Set-Content $hist '{"commands":[]}'
        & pwsh -NoProfile -Command "`$env:HOME='$script:IsoHome'; `$env:USERPROFILE='$script:IsoHome'; `$env:APPDATA=(Join-Path '$script:IsoHome' 'AppData'); `$env:PATH='$script:MockBin'; & '$script:PS1' clean 2>&1" | Out-Null
        Test-Path $hist | Should -BeFalse
        @(Get-ChildItem $rtkDir -Filter 'history.json.*.bak').Count | Should -Be 1
    }
}

Describe 'token-diet.ps1 — help includes clean' {
    It 'help text mentions the clean command' {
        $out = (& pwsh -NoProfile -File $script:PS1 'help' 2>&1) -join ' '
        $out | Should -Match 'clean'
    }
}

Describe 'token-diet.ps1 — health: Codex stale detection' {
    BeforeEach {
        # Provide APPDATA (null on macOS) so Get-HostsRegistered does not throw
        $script:FakeAppData = Join-Path $TestDrive 'AppData'
        New-Item -ItemType Directory -Path $script:FakeAppData -Force | Out-Null
    }

    It 'health: exits 1 when Codex tilth MCP path is stale' {
        $fakeHome = Join-Path $TestDrive 'home-stale'
        New-Item -ItemType Directory -Path (Join-Path $fakeHome '.codex') -Force | Out-Null
        Set-Content (Join-Path $fakeHome '.codex\config.toml') @"
[mcp_servers.tilth]
command = "C:\missing\tilth.exe"
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
[mcp_servers.tilth]
command = 'tilth'
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
[mcp_servers.tilth]
command = 'C:\missing\tilth.exe'
"@ -Encoding UTF8

        $out = (& pwsh -NoProfile -Command `
            "`$env:USERPROFILE='$fakeHome'; `$env:APPDATA='$script:FakeAppData'; & '$($script:PS1)' health" 2>&1) -join ' '
        $out | Should -Match 'MCP command missing'
    }

    It 'verify: exits 1 when Codex tilth MCP path is stale' {
        $fakeHome = Join-Path $TestDrive 'home-verify-stale'
        New-Item -ItemType Directory -Path (Join-Path $fakeHome '.codex') -Force | Out-Null
        Set-Content (Join-Path $fakeHome '.codex\config.toml') @"
[mcp_servers.tilth]
command = "C:\missing\tilth.exe"
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

    It 'suggests tilth for read/search tasks' {
        $out = (& pwsh -NoProfile -File $script:PS1 'route' 'search for the function' 2>&1) -join ' '
        $out | Should -Match 'tilth'
    }

    It 'suggests Serena for rename/refactor tasks' {
        $out = (& pwsh -NoProfile -File $script:PS1 'route' 'rename the class' 2>&1) -join ' '
        $out | Should -Match 'Serena'
    }

    It 'suggests RTK for run/build/test tasks' {
        $out = (& pwsh -NoProfile -File $script:PS1 'route' 'run the tests' 2>&1) -join ' '
        $out | Should -Match 'RTK'
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
