# Docker Images (OCI Compliant)

https://hub.docker.com/repositories/proveo

## Images

### aider-node

> AI-powered coding assistant running in Node.js environment with `curl`, `node`, `npm` & `pnpm` available.

See [aider-node/README.md](./aider-node/README.md) for detailed usage and configuration.

**Quick start:**

```bash
docker run -it --rm \
   -e ANTHROPIC_API_KEY="sk-ant-xxx" \
   -v "$PWD":/app \
   proveo/aider-node
```
