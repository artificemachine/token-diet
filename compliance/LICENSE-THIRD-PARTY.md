# Third-Party Licenses

The token-diet stack bundles four tools: RTK, tilth, and Serena are MIT-licensed; ICM is Apache-2.0.

## Direct Dependencies

| Component | Version | License | Source |
|---|---|---|---|
| RTK (Rust Token Killer) | 0.34.3 | MIT | https://github.com/rtk-ai/rtk |
| tilth | 0.5.7 | MIT | https://github.com/jahala/tilth |
| Serena | 0.1.4 | MIT | https://github.com/oraios/serena |
| ICM (Infinite Context Memory) | 0.10.50 | Apache-2.0 | https://github.com/rtk-ai/icm |

## Transitive Dependencies

Generate full dependency lists with:

```bash
# Rust (RTK + tilth)
cd forks/rtk && cargo license --json > ../../compliance/rtk-licenses.json
cd forks/tilth && cargo license --json > ../../compliance/tilth-licenses.json

# Python (Serena)
cd forks/serena && pip-licenses --format=json > ../../compliance/serena-licenses.json
```

## Known Copyleft Dependencies

Review before enterprise deployment:

```bash
# Check for GPL/LGPL/AGPL in Rust deps
cd forks/rtk && cargo license | grep -i "gpl"
cd forks/tilth && cargo license | grep -i "gpl"

# Check Python deps
cd forks/serena && pip-licenses | grep -i "gpl"
```

## License Compliance Checklist

- [ ] All MIT — include copyright notice in distributions
- [ ] Apache-2.0 (ICM) — preserve the NOTICE file and include attribution + license text per Apache-2.0 §4 in distributions
- [ ] No GPL/AGPL — no copyleft contamination
- [ ] No proprietary — all source available
- [ ] SBOM generated and reviewed (compliance/SBOM.template.json)
- [ ] `cargo license` clean for both Rust projects
- [ ] `pip-licenses` clean for Serena
