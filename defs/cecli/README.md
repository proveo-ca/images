# cecli Definition

Candidate coding harness definition for running Cecli in Docker.

## Contract Status

This definition exposes the required candidate harness commands:

- `Dockerfile.node` and `Dockerfile.python`
- `entrypoint.sh`
- `build.sh`
- `run.sh`
- `test.sh`
- `sample.cecli.conf.yml`
- `defaults/agents/` baked-in subagent prompts

`debug.sh` and `tests/` are not present yet. They are optional unless this definition graduates to require deeper troubleshooting or regression coverage.

## Image Names and Tags

`build.sh` builds both runtime variants using `IMAGE_NAME`, defaulting to `proveo/cecli`, and `NODE_IMAGE_NAME`, defaulting to `proveo/cecli-node`:

```bash
./build.sh
IMAGE_NAME=example/cecli ./build.sh
NODE_IMAGE_NAME=example/cecli-node ./build.sh
```

Produced tags:

- `proveo/cecli:python`
- `proveo/cecli-node:latest`
- `proveo/cecli:latest` aliasing the Node variant
- `proveo/cecli:local` aliasing the Node variant

`run.sh` defaults to `proveo/cecli-node:latest`. Override it with `--image` or `CECLI_IMAGE`.

## Mounts

`run.sh` mounts:

- input workspace at `/app`
- output directory at `/app/output`

Defaults:

- input: current directory
- output: `./reports`

Use `--read-only` to mount the input workspace read-only and place Cecli state under `/tmp/.cecli` by default.

## Environment Variables

- `IMAGE_NAME`: base image name used by `build.sh`; defaults to `proveo/cecli`
- `NODE_IMAGE_NAME`: Node image name used by `build.sh`; defaults to `proveo/cecli-node`
- `CECLI_IMAGE`: image used by `run.sh`; defaults to `proveo/cecli-node:latest`
- `CECLI_INPUT_DIR`: input workspace override
- `CECLI_OUTPUT_DIR`: output directory override
- `CECLI_INSTALL_NODE_DEPS=1`: install Node dependencies when `package.json` is present
- `CECLI_HOME`: Cecli state directory inside the container
- `CECLI_AGENT_CONFIG`: override the generated Agent Mode JSON configuration
- `CECLI_RESEED=1`: overwrite existing `$CECLI_HOME/agents/*.md` with baked-in defaults

## Baked-in Subagents

The image ships default Cecli subagent definitions in `/opt/cecli/defaults/agents/` and seeds them into `$CECLI_HOME/agents/` on startup. The entrypoint also sets a default `CECLI_AGENT_CONFIG` when one is not already provided:

```json
{"large_file_token_threshold":8192,"skip_cli_confirmations":false,"subagent_paths":["$CECLI_HOME/agents","/app/.cecli/agents"]}
```

This makes the agents available to Cecli Agent Mode through the `Delegate` tool. Project-specific agents can be added under `.cecli/agents/*.md`; they are included by the generated `subagent_paths` without modifying the image. Set `CECLI_RESEED=1` to refresh `$CECLI_HOME/agents/` from the baked-in copy.

Included defaults mirror the opencode reviewer set: `adversarial-reviewer`, `security-reviewer`, `architect`, `systems-design`, `frontend`, `backend`, `sre`, `devops`, `monorepo-coordinator`, and `spec-keeper`.

## Commands

Build images:

```bash
./build.sh
```

Run the Node variant against the current directory:

```bash
./run.sh
```

Run with explicit mounts:

```bash
./run.sh --input-dir /path/to/repo --output-dir /path/to/reports
```

Run the Python variant:

```bash
./run.sh --python
```

Run smoke tests against the latest image:

```bash
./test.sh
```

Override the image under test:

```bash
PROVEO_CECLI_IMAGE=proveo/cecli-node:latest ./test.sh
```
