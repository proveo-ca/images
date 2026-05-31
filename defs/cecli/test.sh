#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${PROVEO_CECLI_IMAGE:-proveo/cecli:latest}"

docker run --rm "$IMAGE_NAME" bash -lc 'python --version && cecli --version && timeout 10s pnpm -v && test -f /opt/cecli/defaults/agents/adversarial-reviewer.md && test -f /opt/cecli/defaults/agents/security-reviewer.md && python - <<"PY"
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
