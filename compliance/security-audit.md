# Security Audit Checklist — token-diet

Pre-deployment security review for the Serena + ICM + Context7 stack.

RTK and tilth were removed from the product (see CLAUDE.md) and their audit
sections are gone with them. Context7 is a remote MCP service: no code is
bundled, so its surface is the registration URL and the optional
CONTEXT7_API_KEY the installer appends to it.

## Per-Tool Audit

### Serena

| Check | Command | Pass? |
|---|---|---|
| No known vulnerabilities | `pip-audit -r forks/serena/requirements.txt` | ✅ No known vulnerabilities (`uv export` + pip-audit, 2026-04-01; pywebview dev version skipped — not on PyPI) |
| No telemetry/phoning home | `grep -rn "requests\.\|urllib\|http" forks/serena/src/` | ⚠️ **Serena phones home by default.** `forks/serena/src/serena/agent.py` `_send_usage_info()` sends a `requests.get` to `https://oraios-software.de/serena_usage.php` on **every agent start** (params: OS, version, backend, dashboard flag, context — no file or code content). It is opt-**out**: the only vars it honours are `SERENA_USAGE_REPORTING=false`, `CI`, and `GITHUB_ACTIONS`. token-diet sets `SERENA_USAGE_REPORTING=false` in the Docker image, compose file, and the uvx launcher; Docker mode is additionally covered by `--network none`. Corrected 2026-08-19 — the prior claim that all `http` matches were install-time LSP downloads was false, and the `SERENA_NO_TELEMETRY=1` previously set by token-diet is read nowhere in Serena's source (it was a no-op). |
| cmd_tools.py review | Review shell execution for injection risks | ⬜ Not verified in this pass |
| LSP server downloads | Verify no auto-download at runtime (pre-install in Docker) | ⬜ Verified structurally — Docker image pre-installs servers; not smoke-tested |
| File write scoping | Verify writes limited to project + .serena/ | ⬜ Not verified in this pass |
| Memory persistence | Review .serena/memories/ for data leakage | ⬜ Not verified in this pass |
| No eval/exec | `grep -rn "eval(\|exec(" forks/serena/src/` | ✅ No matches |
| All tests pass | `cd forks/serena && pytest` | ⬜ Not run |
| Docker non-root | Verify Dockerfile runs as non-root user | ✅ `RUN useradd -m serena && USER serena` |
| Docker no network | Verify compose.yml has `network_mode: none` | ✅ `network_mode: none` confirmed |

### ICM

| Check | Command | Pass? |
|---|---|---|
| License (Apache-2.0) | Verify `forks/icm/LICENSE` and NOTICE preserved | ✅ Apache-2.0; attribution carried in `compliance/LICENSE-THIRD-PARTY.md` |
| IPC/stdio surface review | Review `icm serve --compact` (the MCP entry point) | ⚠️ `icm serve` exposes a stdio MCP/IPC surface — it speaks JSON-RPC over stdin/stdout to the host. Not a listening network socket, but it is the trust boundary: any host that registers icm can read/write the persistent memory store |
| Network isolation (build-dependent) | Compare `--local` vs online/default build features | ⚠️ Clean **only** for `--local` builds: `cargo install --no-default-features --features tui` never compiles `fastembed`, so the binary physically cannot fetch a model. The online/default build compiles embeddings and `token-diet icm warmup` downloads ~270 MB (intfloat/multilingual-e5-base) from Hugging Face Hub on first run. Online installs write `[embeddings] enabled=false` into the ICM config file to suppress the download until warmup is run intentionally |
| No `icm init` at install | Verify installer never runs `icm init` | ✅ token-diet writes MCP host entries itself; `icm init` is never invoked (it would bake absolute `current_exe()` paths into ~20 host configs — an install-decoupling violation) |
| Bare-path MCP invocation | Verify MCP entries use `command "icm"` (no repo/forks path) | ✅ All host registrations use bare `icm serve --compact`; no `forks/` path embedded |
| Memory store data leakage | Review the persistent memory store for cross-project leakage | ⬜ Not verified in this pass |
| All tests pass | `cargo test --manifest-path forks/icm/Cargo.toml` | ⬜ Not run (requires full build) |

## Supply Chain

| Check | Status |
|---|---|
| Forks on internal Git server (no GitHub dependency) | ⬜ Submodule URLs still point to github.com/celstnblacc — update for air-gapped deploy |
| Submodule URLs point to internal server | ⬜ Same as above |
| ICM fork on internal Git server | ⬜ `forks/icm` submodule URL still points to github.com/celstnblacc/icm (pinned tag icm-v0.10.50) — needs internal mirror for air-gapped deploy |
| Cargo.lock committed (pinned Rust deps) | ✅ `forks/icm/Cargo.lock` committed |
| Python deps pinned in requirements.txt | ✅ `forks/serena/uv.lock` committed |
| Docker image built from pinned base (python:3.12-slim) | ⬜ Not verified in this pass |
| No `latest` tags in production | ⬜ Not verified in this pass |
| SBOM generated (compliance/SBOM.template.json) | ✅ See `compliance/SBOM.json` |

## Network Isolation

| Check | Status |
|---|---|
| Serena Docker: `network_mode: none` | ✅ Confirmed in compose.yml |
| ICM: no outbound connections (`--local` build) | ✅ `--no-default-features --features tui` omits `fastembed`; binary cannot fetch a model. ⚠️ Online/default build downloads ~270 MB from HF Hub on `token-diet icm warmup` — disabled by default via `[embeddings] enabled=false` in the ICM config file |
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
| 2026-05-29 | Claude Code (automated) | ICM onboarding as 4th tool — license, IPC/stdio surface, embeddings air-gap policy, supply chain | Added `### ICM` section; `--local` build is honest air-gap (no fastembed), online build fetches ~270 MB on warmup (disabled by default); submodule URL still on github.com/celstnblacc/icm — needs internal mirror |
