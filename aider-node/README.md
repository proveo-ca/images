# Aider Docker Runner

Custom wrapper for `paulgauthier/aider-full` with:

- Using `node-alpine` 20 as base
- Monorepo easy setup (`pnpm`)
- Interactive LLM choice + key

## Build the Image

```bash
docker build -t proveo/aider-node .
```

## Run the Image
```bash
docker run -it \
   -v "$PWD":/app \
   -v "$(git rev-parse --show-toplevel)/.git":/app/.git \
   -w /app \
   proveo/aider-node
```

#### Skip the prompt
By passing either `ANTHROPIC_API_KEY | OPENAI_API_KEY | DEEPSEEK_API_KEY`.
This sample also includes a dynamic `--name`
```bash
docker run -it --rm \
  --name "aider-$(basename "$(git rev-parse --show-toplevel)")-$(basename "$PWD")" \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  -v "$PWD":/app \
  -v "$(git rev-parse --show-toplevel)/.git":/app/.git \
  -w /app \
  proveo/aider-node
```
