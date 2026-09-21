# Forks

This directory contains git submodules pointing to your audited forks of:

- **serena/** — IDE-like symbol navigation (LSP-powered)
- **icm/** — persistent cross-tool memory

## Setup

1. Fork each upstream repo to your internal Git server:

```bash
# On your Gitea/Forgejo/GitLab instance, create repos:
#   token-diet/serena
#   token-diet/icm

# Clone upstream and push to internal
git clone https://github.com/oraios/serena.git
cd serena && git remote add internal https://your-gitea.internal/token-diet/serena.git
git push internal main

# Repeat for icm
```

2. Update `.gitmodules` URLs to point to your internal server.

3. Initialize submodules:

```bash
git submodule update --init --recursive
```

## Syncing with upstream

```bash
# Add upstream remote (one-time)
cd forks/serena
git remote add upstream https://github.com/oraios/serena.git

# Fetch and review changes before merging
git fetch upstream
git log upstream/main --oneline -20
git diff main..upstream/main --stat

# Merge after review
git merge upstream/main
# Resolve conflicts, run security audit, then push to internal
```

## Security checklist before merging upstream

- [ ] Review diff for new dependencies (`Cargo.toml`, `pyproject.toml`)
- [ ] Check for telemetry/analytics additions
- [ ] Check for new network calls
- [ ] Run `cargo audit` (Rust) or `pip-audit` (Python)
- [ ] Run SAST scan
- [ ] Build and run tests locally
