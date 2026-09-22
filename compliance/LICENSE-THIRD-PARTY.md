# Third-Party Licenses

The token-diet stack bundles two tools: Serena is MIT-licensed; ICM is
Apache-2.0. Context7 is a remote service registered by the installer — no
Context7 code is bundled or vendored.

## Direct Dependencies

| Component | Version | License | Source |
|---|---|---|---|
| Serena | 0.1.4 | MIT | https://github.com/oraios/serena |
| ICM (Infinite Context Memory) | 0.10.50 | Apache-2.0 | https://github.com/artificemachine/icm |

## Transitive Dependencies

Generate full dependency lists with:

```bash
# Rust (ICM)
cd forks/icm && cargo license --json > ../../compliance/icm-licenses.json

# Python (Serena)
cd forks/serena && pip-licenses --format=json > ../../compliance/serena-licenses.json
```

## Known Copyleft Dependencies

Review before enterprise deployment:

```bash
# Check for GPL/LGPL/AGPL in Rust deps
cd forks/icm && cargo license | grep -i "gpl"

# Check Python deps
cd forks/serena && pip-licenses | grep -i "gpl"
```

## License Compliance Checklist

- [ ] All MIT — include copyright notice in distributions
- [ ] Apache-2.0 (ICM) — preserve the NOTICE file and include attribution + license text per Apache-2.0 §4 in distributions
- [ ] No GPL/AGPL — no copyleft contamination
- [ ] No proprietary — all source available
- [ ] SBOM generated and reviewed (compliance/SBOM.template.json)
- [ ] `cargo license` clean for the Rust project
- [ ] `pip-licenses` clean for Serena
