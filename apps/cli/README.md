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
    bin/
      proveo
      help.sh
```

`/cli` is the durable product URL namespace and contains every asset needed by the installer. This keeps the install flow independent from `/images` while the repository is still primarily `proveo/images`.
