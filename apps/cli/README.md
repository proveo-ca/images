# Proveo CLI Distribution

This app is the Cloudflare-hosted distribution surface for the consumer `proveo`
**Go** binary.

Public install URL:

```bash
curl -fsSL https://proveo.ca/cli/install.sh | bash
```

The installer downloads a platform-specific binary (`bin/proveo-{os}-{arch}`),
verifies it against `checksums.txt`, and installs to `~/.proveo/bin/proveo`.

Current layout:

```txt
public/
  cli/
    install.sh       # checksum-verified Go binary installer
    uninstall.sh     # removes ~/.proveo + PATH markers
    checksums.txt    # SHA-256 of staged binaries (written by deploy-cli / build-cli --release)
    bin/
      proveo-linux-amd64
      proveo-linux-arm64
      proveo-darwin-amd64
      proveo-darwin-arm64
    tests/
      run_tests.sh
```

Publish:

```bash
mise run build-cli -- --release   # optional: goreleaser into dist/ then stage
mise run deploy-cli               # stage proveo-{os}-{arch} + checksums, then Wrangler
```

Run the CDN install test suite:

```bash
apps/cli/public/cli/tests/run_tests.sh
```
