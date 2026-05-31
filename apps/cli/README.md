# Proveo CLI Distribution

This app is the Cloudflare-hosted distribution surface for the consumer `proveo` command.

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
  images/
    bin/
      proveo
      help.sh
```

`/cli` is the durable product URL namespace. `/images/bin` is the current command asset namespace while this repository is still primarily `proveo/images`. When the CLI becomes standalone, move the command assets under `/cli` without changing the public install command.
