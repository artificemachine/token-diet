# token-diet

## Identity
You are working for the project owner.

## This Project
- What: token-diet — installer and compliance kit for the RTK + tilth + Serena + ICM token optimization stack
- Stack: Bash (CLI), PowerShell (Windows CLI), Python (dashboard, tests), Rust (RTK + tilth + ICM forks), Docker (Serena)
- Status: active

## Cross-Agent Protocol
- Read `.superharness/contract.yaml` before starting work.
- Keep task status, ledger, and handoff updated before stopping.

## Strict Installation Decoupling

Once installed to a user-local bin directory, the project binary must NEVER depend on the local repository path (the cloned source checkout) for execution, configuration, or data. All paths must be relative to the installation root or use standard XDG system config directories.
