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
docker run -it --rm --name aider-node \
   -v "$PWD":/app \
   -w /app \
   proveo/aider-node
```
#### From a monorepo
Navigate to your subfolder, (e.g. apps/api), create an `.aiderignore`:
```txt
/*
!**/api/**
```

```bash
docker run -it --rm \                                                                                                                                                                                                                              
    --name "$(basename "$(git rev-parse --show-toplevel)")-$(basename "$PWD")" \
    -v "$PWD:/app/$(git rev-parse --show-prefix | sed 's:/$::')" \
    -v "$(git rev-parse --show-toplevel)/.git:/app/.git" \
    -v "$PWD/.aiderignore:/app/.aiderignore" \
    -w /app \
    proveo/aider-node
```
> We want to maintain the monorepo's structure for aider's repo-map to work.

## Conventions
It is recommended to have a conventions file for `aider` to read, see this [sample](./2025CONVENTIONS.md).
