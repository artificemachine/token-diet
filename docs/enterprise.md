# Enterprise & Air-Gapped Deployment

`token-diet` supports fully offline installation from audited local forks. This is ideal for restricted environments or corporate networks.

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

### 4. Install locally
```bash
# Build and install directly from local forks/ — no internet required
bash scripts/install.sh --local
```

## Security Model

| Concern | Solution |
|---|---|
| Supply chain | Build from audited forks, no upstream access at runtime |
| Telemetry | Serena usage reporting disabled (`SERENA_USAGE_REPORTING=false`) in the Docker image, compose file, and launcher |
| Network isolation | Serena Docker: `network_mode: none` |
| Remote service | Context7 is the one outbound registration in the stack; register it only on hosts allowed to reach `mcp.context7.com`, or skip `--context7-only`/pass `--skip context7` on air-gapped machines |
| Reproducibility | Pinned submodules + Cargo.lock + Docker base |
| Compliance | SBOM, license tracking, audit checklist included |
