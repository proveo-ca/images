#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${PROVEO_CECLI_IMAGE:-proveo/cecli:latest}"

# Root-free contract: non-root default user, no gosu, and any wrapper-passed
# `--user` uid gets a usable identity and writable HOME via ensure_runtime_user.
echo "── Runtime user checks ──────────────────────────────"
docker run --rm --entrypoint bash "$IMAGE_NAME" -c \
  '[ "$(id -u)" != "0" ] && [ "$(whoami)" = "cecli" ] && ! command -v gosu >/dev/null'
docker run --rm --user 4242:4242 --entrypoint bash "$IMAGE_NAME" -c \
  'source /entrypoint-lib.sh && ensure_runtime_user && [ "$(id -u)" = "4242" ] && [ -w "$HOME" ]'
echo "✅ non-root default user, no gosu, arbitrary --user uid usable"

# git and gh must be baked in, and env-provided git identity must resolve via
# `git config --get` (bridge_git_identity) so cecli never seeds placeholders.
docker run --rm --entrypoint bash "$IMAGE_NAME" -c 'git --version && gh --version'
docker run --rm --entrypoint bash "$IMAGE_NAME" -c '
  if command -v playwright >/dev/null 2>&1; then
    playwright --version
  else
    python3 -m playwright --version
  fi
  test -n "$PLAYWRIGHT_BROWSERS_PATH" \
    && test -d "$PLAYWRIGHT_BROWSERS_PATH" \
    && ls "$PLAYWRIGHT_BROWSERS_PATH" | grep -q chromium \
    && ldconfig -p | grep -q "libglib-2.0.so.0"'
echo "✅ playwright + chromium browsers + OS deps baked in"
docker run --rm --user 4242:4242 --entrypoint bash \
  -e GIT_AUTHOR_NAME="Proveo Dev" -e GIT_AUTHOR_EMAIL="dev@proveo.test" "$IMAGE_NAME" -c '
    source /entrypoint-lib.sh && ensure_runtime_user && bridge_git_identity \
      && [ "$(git config --get user.name)" = "Proveo Dev" ] \
      && [ "$(git config --get user.email)" = "dev@proveo.test" ]'
echo "✅ git + gh baked in, env git identity resolves via git config"

docker run --rm "$IMAGE_NAME" bash -c 'python3 --version && cecli --version && timeout 10s pnpm -v && test -f /opt/cecli/defaults/agents/adversarial-reviewer.md && test -f /opt/cecli/defaults/agents/security-reviewer.md && python3 - <<"PY"
from cecli.helpers.agents.service import AgentService
AgentService._global_registry = {}
AgentService.build_registry(["/opt/cecli/defaults/agents"])
registry = AgentService.get_registry()
required = {"adversarial-reviewer", "security-reviewer", "architect", "systems-design", "frontend", "backend", "sre", "devops", "monorepo-coordinator", "spec-keeper"}
missing = required - set(registry)
assert not missing, f"missing subagents: {sorted(missing)}"
assert registry["adversarial-reviewer"].prompt
assert registry["security-reviewer"].metadata.get("description")
print("subagents:", " ".join(sorted(registry)))
PY'
