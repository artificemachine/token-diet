# Enterprise & Air-Gapped Deployment

`token-diet` supports fully offline installation from audited local forks. This is ideal for restricted environments or corporate networks.

## Deployment Workflow

### 1. Fork upstream repos
Clone the upstream repositories and push them to your internal Git server (Gitea, Forgejo, GitLab, etc.):

```bash
# Example for RTK
git clone https://github.com/rtk-ai/rtk.git
cd rtk && git remote add internal https://gitea.internal/token-diet/rtk.git
git push internal main
```
*Repeat for tilth and serena.*

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
| Telemetry | Stripped in forks (RTK analytics, Serena tiktoken) |
| Network isolation | Serena Docker: `network_mode: none` |
| Reproducibility | Pinned submodules + Cargo.lock + Docker base |
| Compliance | SBOM, license tracking, audit checklist included |
