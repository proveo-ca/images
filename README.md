# Docker Images (OCI Compliant)

https://hub.docker.com/repositories/proveo

This repository contains multiple Docker images under the `proveo/` namespace.

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
- be easy to build, run, debug, test, and deploy through `bin/proveo`

### Other containers

Other containers are regular utility or service containers that are not coding AI harnesses.

Current non-harness container in this repo:

- `proveo/charles-proxy`

These containers may still be managed by `bin/proveo`, but they do not need the same monorepo and workspace conventions as coding harnesses.

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

## Unified CLI

Use the repo-level CLI to manage containers consistently:

```bash
bin/proveo help
bin/proveo list
bin/proveo build aider-node
bin/proveo run aider-node
bin/proveo debug claude-standalone
bin/proveo test claude-chonky
bin/proveo deploy charles-proxy --tag latest
bin/proveo uninstall
```

For coding harness targets, `bin/proveo` can:

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
   - integrate with `bin/proveo`
   - support build, run, debug, test, and deploy workflows

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

6. Add it to `bin/proveo`
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

For pnpm monorepos, `bin/proveo` detects `pnpm-workspace.yaml`, enumerates matching workspaces, and prompts for scope selection.

The current implementations use two patterns:

- `aider-node`
  - preserves monorepo structure inside `/app`
  - mounts the selected workspace under its repo-relative path
  - mounts repo `.git` separately so aider repo mapping still works

- `claude-*`
  - accept explicit input, output, and data directory flags
  - can be launched directly against a chosen workspace without relying on `cd` as the control mechanism
