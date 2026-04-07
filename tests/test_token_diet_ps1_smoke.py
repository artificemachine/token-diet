"""Smoke tests for scripts/token-diet.ps1 command dispatch.

These tests intentionally validate command routing and basic output shape,
not full tool installation state. Some commands are state-dependent and may
legitimately return non-zero when RTK history/tools are absent.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import pytest


PS_SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "token-diet.ps1"


def _run_ps1(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["pwsh", "-NoProfile", "-File", str(PS_SCRIPT), *args],
        capture_output=True,
        text=True,
        timeout=60,
    )


@pytest.mark.skipif(
    shutil.which("pwsh") is None or sys.platform != "win32",
    reason="PS1 smoke tests require Windows + pwsh",
)
@pytest.mark.parametrize(
    "args,expected_codes,needle",
    [
        (["help"], {0}, "USAGE"),
        (["gain"], {0}, "token-diet gain"),
        (["health"], {0, 1}, "token-diet health"),
        (["breakdown", "--limit", "3"], {0, 1}, "RTK"),
        (["explain", "rtk git status"], {0, 1}, "RTK"),
        (["budget", "status"], {0}, "token-diet budget"),
        (["loops"], {0, 1}, "RTK"),
        (["route", "run tests"], {0}, "RTK"),
        (["leaks"], {0, 1}, "RTK"),
        (["test-first", "scripts/token-diet.ps1"], {0}, "Test candidates"),
        (["strip", "--stats", str(PS_SCRIPT)], {0}, "Lines:"),
        (["diff-reads", str(PS_SCRIPT)], {0}, "Changed regions"),
        (["dashboard", "--help"], {0}, "Usage: token-diet.ps1 dashboard"),
        (["service", "help"], {0}, "Usage: token-diet.ps1 service"),
        (["service", "status"], {0, 1}, "service"),
        (["version"], {0}, "token-diet stack versions"),
        (["verify"], {0, 1}, "Token Stack Verification"),
        (["uninstall", "-DryRun", "-Force"], {0}, "token-diet uninstall"),
    ],
)
def test_token_diet_ps1_command_smoke(
    args: list[str], expected_codes: set[int], needle: str
) -> None:
    result = _run_ps1(args)
    output = (result.stdout or "") + (result.stderr or "")

    assert result.returncode in expected_codes, (
        f"args={args} exit={result.returncode}\n"
        f"stdout:\n{result.stdout}\n\n"
        f"stderr:\n{result.stderr}"
    )
    assert needle.lower() in output.lower(), (
        f"args={args} missing '{needle}'\n"
        f"stdout:\n{result.stdout}\n\n"
        f"stderr:\n{result.stderr}"
    )
