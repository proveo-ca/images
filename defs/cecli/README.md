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

`debug.sh` and `tests/` are not present yet. They are optional unless this definition graduates to require deeper troubleshooting or regression coverage.

## Image Names and Tags

`build.sh` builds both runtime variants using `IMAGE_NAME`, defaulting to `proveo/cecli`:

```bash
./build.sh
IMAGE_NAME=example/cecli ./build.sh
```

Produced tags:

- `proveo/cecli:python`
- `proveo/cecli:node`
- `proveo/cecli:latest` aliasing the Node variant
- `proveo/cecli:local` aliasing the Node variant

`run.sh` defaults to `proveo/cecli:node`. Override it with `--image` or `CECLI_IMAGE`.

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
- `CECLI_IMAGE`: image used by `run.sh`; defaults to `proveo/cecli:node`
- `CECLI_INPUT_DIR`: input workspace override
- `CECLI_OUTPUT_DIR`: output directory override
- `CECLI_INSTALL_NODE_DEPS=1`: install Node dependencies when `package.json` is present
- `CECLI_HOME`: Cecli state directory inside the container

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
PROVEO_CECLI_IMAGE=proveo/cecli:node ./test.sh
```