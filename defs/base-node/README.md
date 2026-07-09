# base-node

`proveo/base-node` = `proveo/base` + a Node 22 LTS runtime (NodeSource) + `pnpm`.
It exists so the Node harnesses share the runtime layer once instead of each
baking their own copy, while `cursor` (self-contained binary) and `cecli`
(Python) stay off it and carry no Node.

- FROM `proveo/base` (inherits git/gh/dumb-init/proveo-entrypoint/harden).
- Consumers: `opencode`, `claudecode` (mcp/solo/sol).
- Not a runnable harness — a mise build/deploy target like `base`.

Node major is pinned via `--build-arg NODE_MAJOR` (default 22). `build.sh`
ensures `proveo/base` first; harness `build.sh` scripts call this def's
`ensure.sh`.
