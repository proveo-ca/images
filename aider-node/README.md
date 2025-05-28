# Aider Docker Runner

Custom wrapper for `paulgauthier/aider-full` with:

- Using `node-slim` 22 as base (has `node`, `npm` and `curl` installed)
- Monorepo easy setup (`pnpm`)
- Interactive LLM choice + key

## Build the Image

```bash
docker build -t proveo/aider-node:local .
```

## Run the Image

#### From the repo's root
```bash
docker run -it \
   -v "$PWD":/app \
   -w /app \
   proveo/aider-node
```
#### From a monorepo
```bash
docker run -it \
   -v "$PWD":/app/$(realpath --relative-to="$(git rev-parse --show-toplevel)" "$PWD") \
   -v "$(git rev-parse --show-toplevel)/.git":/app/.git \
   -v "$PWD"/.aiderignore:/app/.aiderignore \
   -w /app \
   proveo/aider-node
```
> We want to maintain the monorepo's structure for aider's repo-map to work.

#### Skip the prompt
By passing either `ANTHROPIC_API_KEY | OPENAI_API_KEY | DEEPSEEK_API_KEY`.
This sample also includes a dynamic `--name`
```bash
docker run -it --rm \
    --name "$(basename "$(git rev-parse --show-toplevel)")-$(basename "$PWD")" \
    -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
    -v "$(git rev-parse --show-toplevel)/.git":/app/.git \
    -v "$PWD":/app/$(realpath --relative-to="$(git rev-parse --show-toplevel)" "$PWD") \
    -v "$PWD"/.aiderignore:/app/.aiderignore \
    -w  /app/ \
proveo/aider-node:local
```
