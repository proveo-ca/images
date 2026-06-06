# Proveo CLI Distribution

This app is the Cloudflare-hosted distribution surface for the consumer `proveo` command.

The consumer CLI here is the base command. Maintainer workflows live in the repo's `mise` tasks and `lib/*.sh` helpers, which are not part of the distributed install lifecycle.

Public install URL:

```bash
curl -fsSL https://proveo.ca/cli/install.sh | bash
```

Current layout:

```txt
public/
  cli/
    install.sh      # product-facing installer
    uninstall.sh    # product-facing uninstaller
    bin/
      proveo
      help.sh
      init.sh
    tests/
      run_tests.sh  # distributable CLI smoke/regression tests
```

`/cli` is the durable product URL namespace and contains every asset needed by the installer. This keeps the install flow independent from `/images` while the repository is still primarily `proveo/images`.

Run the distributable CLI test suite with:

```bash
apps/cli/public/cli/tests/run_tests.sh
```
