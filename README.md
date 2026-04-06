# Docker Images (OCI Compliant)

https://hub.docker.com/repositories/proveo

This repository contains multiple Docker images under the `proveo/` namespace and now uses a light monorepo control-plane at the root for shared tooling and deployment workflows.

## Repository Layout

The repo is being organized around these root concepts:

```text
.
├── apps/
│   └── cli/           # Cloudflare-hosted install/distribution assets for the proveo CLI
├── packages/          # reusable tooling, libraries, or shared workspace code
├── scripts/           # maintenance and sync scripts
├── aider-node/        # container project
├── claude-code/       # container project
├── charles-proxy/     # container project
├── bin/               # CLI entrypoints
├── install.sh
├── uninstall.sh
├── package.json
├── pnpm-workspace.yaml
└── mise.toml
```

For now, the container/image folders remain at the repository root instead of moving under a dedicated `images/` directory. This keeps path churn low while still letting the repo adopt root-level monorepo tooling.

## Two Modes

This repo now has two distinct ways of interacting with the container ecosystem:

### 1. Local dev mode: `probe`

`probe` is the **developer/maintainer** workflow.

Use this mode when you are working inside this repository and need full control over:
- source files
- Docker build contexts
- test scripts
- debug workflows
- image publishing/deployment
- monorepo-aware local development

In local dev mode, you have full access to the repo and use the dev CLI to:
- build images
- test images
- run images
- debug images
- deploy images

Typical responsibilities in `probe` mode:
- develop or modify container definitions
- iterate on wrapper scripts
- update docs
- validate security/test behavior
- publish/install assets for the consumer CLI

### 2. Consumer mode: `proveo`

`proveo` is the **consumer-facing** workflow.

Use this mode when you only want to:
- install the CLI from a hosted URL
- run already-published container images
- avoid cloning this repo
- avoid build/test/debug/deploy concerns

In consumer mode, users install the lightweight CLI and then run published images such as:
- `proveo/aider-node`
- `proveo/charles-proxy`

For coding harness targets, `proveo` also supports pnpm monorepo scope selection when run from inside a git repository.

## Container Types

### Coding harness containers

Coding harness containers are interactive developer and AI-agent environments for working on source code safely and consistently across projects.

Current coding harnesses in this repo:

- `proveo/aider-node`
- `proveo/claude-standalone`
- `proveo/claude-chonky`

These containers are designed to:

- run as interactive tools, not just long-running services
- mount a host project or monorepo workspace into the container
- preserve predictable workspace paths for AI tools
- support monorepo-aware workflows
- isolate outputs and optional reference data
- be easy to build, run, debug, test, and deploy through the local dev workflow

### Other containers

Other containers are regular utility or service containers that are not coding AI harnesses.

Current non-harness container in this repo:

- `proveo/charles-proxy`

These containers may still be managed by the dev CLI, but they do not need the same monorepo and workspace conventions as coding harnesses.

## Images

### aider-node

> AI-powered coding assistant running in a Node.js environment with `curl`, `node`, `npm`, `pnpm`, and Playwright available.

See [aider-node/README.md](./aider-node/README.md) for detailed usage and configuration.

**Quick start:**

```bash
docker run -it --rm \
  -e ANTHROPIC_API_KEY="sk-ant-xxx" \
  -v "$PWD":/app \
  proveo/aider-node
```

### claude-standalone

> Claude Code container without extra MCP server configuration.

See [claude-code/README.md](./claude-code/README.md) for details.

### claude-chonky

> Claude Code container with Chonky-specific configuration and MCP integrations.

See [claude-code/README.md](./claude-code/README.md) for details.

### charles-proxy

> Charles Proxy running in a containerized headless setup.

See `charles-proxy/` for image details.

## Root Tooling

The repository now has a root workspace/tooling layer intended for local developer workflows.

### pnpm workspace

Root workspaces are declared in `pnpm-workspace.yaml` and currently cover:

- `apps/*`
- `packages/*`

The primary app workspace is currently:

- `apps/cli`
  - the Cloudflare-deployed workspace that serves install/distribution assets for the `proveo` CLI

This allows new deployable apps and reusable packages to be added without restructuring the container folders yet.

### Wrangler

`wrangler` is installed at the root as a dev dependency so Cloudflare-hosted install/distribution assets can be built and deployed from a consistent local toolchain.

### mise

`mise` is used as an optional developer toolchain manager for pinning commonly used tools such as:

- `node`
- `pnpm`

and for defining lightweight shared tasks.

Consumer installation of `proveo` still does **not** depend on `mise`, Node, or pnpm.

## CLI Asset Sync and Deploy Hierarchy

The consumer CLI files now have a clear hierarchy of responsibility.

### Source of truth

These root files are the only files that should be edited directly for the consumer CLI:

- `install.sh`
- `uninstall.sh`
- `bin/proveo`
- `bin/help.sh`

### Deploy artifacts

The Cloudflare app serves synced copies under:

- `apps/cli/public/images/install.sh`
- `apps/cli/public/images/uninstall.sh`
- `apps/cli/public/images/bin/proveo`
- `apps/cli/public/images/bin/help.sh`

These should be treated as generated deploy artifacts, not hand-maintained primary copies.

### Sync step

The sync step is handled by:

```bash
./scripts/sync-cli-assets.sh
```

It copies the root source-of-truth files into `apps/cli/public/images/...` before local dev serving or deployment.

### Deployment engine

`wrangler` is the actual deployment engine.

It is the tool that:
- reads `apps/cli/wrangler.toml`
- serves `apps/cli/public/...` locally
- deploys the assets to Cloudflare

### Command hierarchy

Recommended mental model:

```text
root source files
  -> scripts/sync-cli-assets.sh
  -> apps/cli/public/images/*
  -> wrangler dev/deploy
  -> Cloudflare
```

Developer command wrappers simply orchestrate this:

- `mise` = preferred maintainer task runner
- `package.json` scripts = Node/pnpm convenience wrappers
- `wrangler` = actual deploy engine

### Common sync/dev/deploy commands

Using `mise`:

```bash
mise run sync-cli-assets
mise run dev-cli
mise run deploy-cli
```

Using pnpm:

```bash
pnpm run sync:cli
pnpm run dev:cli
pnpm run deploy:cli
```

## Local Dev Workflow (`probe`)

Use the dev CLI from a local checkout when working on this repo.

### Common dev commands

```bash
probe help
probe list
probe build aider-node --tag latest
probe test claude-standalone
probe run aider-node
probe debug claude-chonky
probe deploy charles-proxy --tag latest
```

### What `probe` is for

`probe` is the full-access maintainer tool. Use it to:

- **build** images locally
- **test** image behavior
- **run** images during development
- **debug** containers and wrappers
- **deploy** published image tags

### Build images with `probe`

Examples:

```bash
probe build aider-node --tag latest
probe build charles-proxy --tag latest
probe build claude-standalone --tag latest
probe build claude-chonky --tag latest
```

### Test images with `probe`

Examples:

```bash
probe test aider-node
probe test charles-proxy
probe test claude-standalone
probe test claude-chonky
```

### Run images with `probe`

Examples:

```bash
probe run aider-node
probe run claude-standalone
probe run claude-chonky
probe run charles-proxy
```

### Debug images with `probe`

Examples:

```bash
probe debug aider-node
probe debug claude-standalone
probe debug claude-chonky
probe debug charles-proxy
```

### Deploy images with `probe`

Examples:

```bash
probe deploy aider-node --tag latest
probe deploy charles-proxy --tag latest
probe deploy claude-standalone --tag latest
probe deploy claude-chonky --tag latest
```

## Consumer Workflow (`proveo`)

Use the consumer CLI when you want to run published images without working on this repo.

### Install `proveo`

Hosted install flow:

```bash
wget -qO- https://proveo.ca/images/install.sh | bash
```

Or with curl:

```bash
curl -fsSL https://proveo.ca/images/install.sh | bash
```

This installs the consumer CLI into a local user directory, adds it to your PATH, and checks whether Docker is available.

### Common consumer commands

```bash
proveo help
proveo list
proveo run aider-node
proveo run claude-chonky
proveo run charles-proxy
proveo uninstall
```

### What `proveo` is for

`proveo` is the lightweight runtime CLI for consumers. Use it to:

- list available published container targets
- run published images
- uninstall the consumer CLI from your PATH

`proveo` does **not** expose:
- build
- test
- debug
- deploy

Those workflows belong to local dev mode with `probe`.

## Unified CLI Notes

For coding harness targets, the CLI can:

- detect pnpm monorepos
- read `pnpm-workspace.yaml`
- prompt you to choose repo root or a workspace
- launch the selected harness against that explicit scope

`proveo help` is backed by `bin/help.sh`. When adding, renaming, or removing container targets, update `bin/help.sh` so the installed CLI help stays accurate.

## Coding Harness Specification

A container should generally qualify as a coding harness when it is intended to help a human developer or coding AI operate on a project workspace.

### Expected behaviors

A coding harness should ideally:

1. Accept an explicit project scope
   - input directory
   - output directory
   - optional data or reference directory

2. Work for monorepos
   - support running against a repo root or a selected sub-workspace
   - avoid assuming only single-package repositories

3. Be interactive
   - support an interactive default run mode
   - support a debug shell mode

4. Be scriptable
   - provide stable build, run, and debug entrypoints
   - accept explicit flags instead of depending only on current working directory

5. Be safe by default
   - prefer reduced container privileges
   - use read-only input mounts when practical
   - isolate outputs and temporary files

6. Fit the repo conventions
   - use a `proveo/` publish name
   - integrate with `probe` / `proveo` appropriately
   - support build, run, debug, test, and deploy workflows where relevant

### Recommended interface for coding harness scripts

If you add a new coding harness, its wrapper scripts should support:

- `--input-dir <path>`
- `--output-dir <path>`
- `--data-dir <path>`

They should also allow pass-through tool arguments after wrapper-specific options.

### Recommended repository layout

A new coding harness should typically include:

- a Dockerfile
- a build script
- a run script
- a debug script
- README documentation

For example:

```text
my-harness/
├── Dockerfile
├── build.sh
├── run_harness.sh
├── debug-shell.sh
└── README.md
```

## How to add a new coding harness

1. Create the image directory
   - add its Dockerfile and wrapper scripts

2. Choose image names
   - local build tag if needed
   - publish tag under `proveo/<name>`

3. Make run and debug scripts accept explicit paths
   - `--input-dir`
   - `--output-dir`
   - `--data-dir`

4. Use predictable mount points
   - for example `/workspace/input`, `/workspace/output`, `/workspace/data`
   - or another stable structure if the tool requires it

5. Add secure defaults
   - reduced capabilities
   - `no-new-privileges`
   - tmpfs for temporary directories where appropriate

6. Add it to the dev CLI
   - target list
   - image mappings
   - build logic
   - run and debug logic
   - test and deploy logic

7. Update `bin/help.sh`
   - add the new target and its short description
   - keep the installed `proveo help` output accurate

8. Document it
   - image purpose
   - required environment variables
   - example build, run, and debug commands
   - monorepo behavior, if relevant

## Notes on monorepo support

Coding harnesses should be able to operate on:

- the repository root, or
- a selected package, app, or lib inside a monorepo

For pnpm monorepos, the CLI detects `pnpm-workspace.yaml`, enumerates matching workspaces, and prompts for scope selection.

The current implementations use two patterns:

- `aider-node`
  - preserves monorepo structure inside `/app`
  - mounts the selected workspace under its repo-relative path
  - mounts repo `.git` separately so aider repo mapping still works

- `claude-*`
  - accept explicit input, output, and data directory flags
  - can be launched directly against a chosen workspace without relying on `cd` as the control mechanism
