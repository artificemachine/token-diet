# Security Audit Checklist — token-diet

Pre-deployment security review for the RTK + tilth + Serena stack.

## Per-Tool Audit

### RTK

| Check | Command | Pass? |
|---|---|---|
| No known vulnerabilities | `cargo audit --file forks/rtk/Cargo.lock` | ✅ 0 vulnerabilities (164 deps scanned, 2026-04-01) |
| No telemetry/analytics | `grep -r "telemetry\|analytics\|ping" forks/rtk/src/` | ✅ `analytics` = local token savings only (`rtk gain`); outbound telemetry stripped in fork (comment in `core/config.rs`) |
| No hardcoded URLs | `grep -rn "http:/\|https:/" forks/rtk/src/ --include="*.rs"` | ✅ All URL matches are in test assertions or docstring examples — not production code |
| No unwrap in production | `grep -rn "\.unwrap()" forks/rtk/src/ --include="*.rs"` (exclude tests) | ✅ All `.unwrap()` in `lazy_static!` regex init (established RTK pattern — panics on startup, not silently); remainder in `#[cfg(test)]` blocks |
| No unsafe blocks | `grep -rn "unsafe" forks/rtk/src/ --include="*.rs"` | ✅ No `unsafe { }` blocks — matches are comments and a log message |
| Shell injection review | Review `execute_command` and `Command::new` usage | ✅ `execute_command` takes `&[&str]` (no shell interpolation); `Command::new` uses literal tool names |
| Exit code propagation | Verify child process exit codes are forwarded | ✅ `std::process::exit(code)` in run() functions |
| All tests pass | `cargo test --manifest-path forks/rtk/Cargo.toml` | ⬜ Not run (requires full build) |
| Clippy clean | `cargo clippy --manifest-path forks/rtk/Cargo.toml --all-targets` | ⬜ Not run (requires full build) |

### tilth

| Check | Command | Pass? |
|---|---|---|
| No known vulnerabilities | `cargo audit --file forks/tilth/Cargo.lock` | ✅ 0 vulnerabilities (93 deps scanned, 2026-04-01) |
| No network calls | `grep -rn "reqwest\|hyper\|TcpStream\|http::" forks/tilth/src/` | ✅ No matches |
| No telemetry | `grep -rn "telemetry\|analytics\|tracking" forks/tilth/src/` | ✅ Single match is in a code comment about cycle detection — not tracking code |
| tree-sitter grammar review | Check compiled C grammars for injection | ⬜ Upstream tree-sitter grammars — review against upstream |
| File access scoping | Verify reads are scoped to project directory | ⬜ Not verified in this pass |
| Memory safety (mmap) | Review memmap2 usage for bounds checking | ⬜ Not verified in this pass |
| All tests pass | `cargo test --manifest-path forks/tilth/Cargo.toml` | ⬜ Not run (requires full build) |

### Serena

| Check | Command | Pass? |
|---|---|---|
| No known vulnerabilities | `pip-audit -r forks/serena/requirements.txt` | ✅ No known vulnerabilities (`uv export` + pip-audit, 2026-04-01; pywebview dev version skipped — not on PyPI) |
| No telemetry/phoning home | `grep -rn "requests\.\|urllib\|http" forks/serena/src/` | ✅ All `http` matches are URL strings in LSP server config (download URLs used only during install, not at runtime) |
| cmd_tools.py review | Review shell execution for injection risks | ⬜ Not verified in this pass |
| LSP server downloads | Verify no auto-download at runtime (pre-install in Docker) | ⬜ Verified structurally — Docker image pre-installs servers; not smoke-tested |
| File write scoping | Verify writes limited to project + .serena/ | ⬜ Not verified in this pass |
| Memory persistence | Review .serena/memories/ for data leakage | ⬜ Not verified in this pass |
| No eval/exec | `grep -rn "eval(\|exec(" forks/serena/src/` | ✅ No matches |
| All tests pass | `cd forks/serena && pytest` | ⬜ Not run |
| Docker non-root | Verify Dockerfile runs as non-root user | ✅ `RUN useradd -m serena && USER serena` |
| Docker no network | Verify compose.yml has `network_mode: none` | ✅ `network_mode: none` confirmed |

## Supply Chain

| Check | Status |
|---|---|
| Forks on internal Git server (no GitHub dependency) | ⬜ Submodule URLs still point to github.com/celstnblacc — update for air-gapped deploy |
| Submodule URLs point to internal server | ⬜ Same as above |
| Cargo.lock committed (pinned Rust deps) | ✅ Both `forks/rtk/Cargo.lock` and `forks/tilth/Cargo.lock` committed |
| Python deps pinned in requirements.txt | ✅ `forks/serena/uv.lock` committed |
| Docker image built from pinned base (python:3.12-slim) | ⬜ Not verified in this pass |
| No `latest` tags in production | ⬜ Not verified in this pass |
| SBOM generated (compliance/SBOM.template.json) | ✅ See `compliance/SBOM.json` |

## Network Isolation

| Check | Status |
|---|---|
| RTK: no outbound connections | ✅ No network crates in source; outbound telemetry stripped |
| tilth: no outbound connections | ✅ No network crates found in source |
| Serena Docker: `network_mode: none` | ✅ Confirmed in compose.yml |
| LSP servers pre-installed (no auto-download) | ⬜ Requires smoke-test of Docker image |
| No `uvx` at runtime (Docker-based) | ⬜ Not verified in this pass |

## Deployment

| Check | Status |
|---|---|
| Binaries signed (codesign / gpg) | ⬜ Not done — required before public distribution |
| Distribution via internal artifact store | ⬜ N/A for open source mode |
| Rollback procedure documented | ⬜ Not documented |
| Version pinning in installer scripts | ⬜ Installers use submodule commits; verify pinning |
| Changelog reviewed for each upstream merge | ✅ CHANGELOG.md maintained append-only |

## Audit Schedule

| Frequency | Action |
|---|---|
| Per upstream merge | Full diff review + cargo audit + pip-audit |
| Monthly | Dependency vulnerability scan |
| Quarterly | Full checklist re-evaluation |
| Per release | SBOM regeneration |

## Audit History

| Date | Auditor | Scope | Notes |
|---|---|---|---|
| 2026-04-01 | Claude Code (automated) | cargo audit, pip-audit, grep checks, Docker config | Initial automated pass — critical checks green; manual items marked ⬜ for next pass |
