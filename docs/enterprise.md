# Enterprise & Air-Gapped Deployment

`token-diet` can use audited local forks in restricted environments. A fully
offline install requires prepared toolchains, dependencies, and container
images. `--local` chooses local source; it does not enforce network isolation.

## Deployment Workflow

### 1. Fork upstream repos
Clone the upstream repositories and push them to your internal Git server (Gitea, Forgejo, GitLab, etc.):

```bash
# Example for Serena
git clone https://github.com/oraios/serena.git
cd serena && git remote add internal https://gitea.internal/token-diet/serena.git
git push internal main
```
*Repeat for icm.*

### 2. Update submodule URLs
Edit `.gitmodules` in the `token-diet` repo to point to your internal server, then:

```bash
git submodule update --init --recursive
```

### 3. Verify the forks
```bash
# Build + test all forks
bash scripts/build.sh --release
```

### 4. Prepare the offline environment

Before disconnecting, initialize the pinned submodules, install Rust/Cargo and
Docker, and build/load the `token-diet/serena:latest` image. That image build
uses base images, apt, uv/pip, and npm downloads. Cache the Rust dependency
sources needed by `cargo install` for the target platform as well.

For an isolated Cargo install, set `CARGO_NET_OFFLINE=true` so missing cached
dependencies fail instead of initiating downloads. Verify the complete install
in an isolated test environment before relying on it for an air-gapped host.
No clean-room offline installation is implied by a successful online build.

### 5. Install the local components
```bash
# Use prepared local inputs and omit the remote Context7 registration
CARGO_NET_OFFLINE=true bash scripts/install.sh --local --serena-only --icm-only
```

## Security Model

| Concern | Solution |
|---|---|
| Supply chain | Build local components from pinned audited forks; prepare dependency inputs before isolating the host |
| Telemetry | Serena usage reporting disabled (`SERENA_USAGE_REPORTING=false`) in the Docker image, compose file, and launcher |
| Network isolation | Serena Docker: `network_mode: none` |
| Remote service | Context7 requires `mcp.context7.com`; omit it with `--serena-only --icm-only` on isolated hosts. There is no `--skip context7` installer option. |
| Reproducibility | Pinned submodules + Cargo.lock + Docker base |
| Compliance | SBOM, license tracking, audit checklist included |
