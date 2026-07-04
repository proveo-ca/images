#!/usr/bin/env bash
# SPEC: _spec/defs/opencode/opencode-topology.puml, _spec/defs/opencode/opencode.paradigm.md
set -e

# Source shared entrypoint library if present
if [[ -f /entrypoint-lib.sh ]]; then
  source /entrypoint-lib.sh
fi

# ── Make the run-as UID usable (root-free) ─────────────────
# The wrapper runs us as the caller's host uid via `docker run --user`; give
# that uid a passwd entry and a writable HOME (shared across harnesses).
ensure_runtime_user

# ── Working directory ──────────────────────────────────────
set_working_directory "/app"

# ── Source .env file if present ────────────────────────────
load_env

# ── Git identity from environment ──────────────────────────
# Bridge wrapper-forwarded GIT_* env into git's config-env so `git config --get`
# resolves file-free; repo-local identity stays authoritative.
bridge_git_identity

# ── Git context (repo / remote / identity / gh session) ────
report_git_context

# ── Optional: attach RTK repo ──────────────────────────────
attach_rtk

# ── Bridge common .env model aliases to opencode config vars ─────────
# Uses shared declarative environment variable bridges
apply_env_bridges
# ── Seed global defaults (~/.config/opencode) ──────────────
# Only seed files that are missing, unless OPENCODE_RESEED=1 forces a full re-seed.
write_minimal_opencode_config() {
  local target="$1"
  cat >"$target" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {},
  "model": "{env:OPENCODE_MODEL}",
  "small_model": "{env:OPENCODE_SMALL_MODEL}",
  "autoupdate": false,
  "agent": {
    "plan": {
      "description": "Read-only planner. Produces specs and step lists; never edits or runs shell.",
      "mode": "primary",
      "model": "{env:OPENCODE_MODEL}",
      "temperature": 0.1,
      "permission": { "edit": "deny", "bash": "deny" }
    },
    "build": {
      "description": "Implementer. Edits allowed; bash requires human approval per command.",
      "mode": "primary",
      "model": "{env:OPENCODE_BUILD_MODEL}",
      "temperature": 0.2,
      "permission": { "edit": "allow", "bash": "ask" }
    }
  }
}
EOF
}
seed_opencode_config() {
  local target="$1"
  local candidate
  local candidates=(
    "${HOME}/.config/opencode/sample_opencode.json"
    "${HOME}/Library/Application Support/opencode/sample_opencode.json"
    "/opt/opencode/sample_opencode.json"
    "/opt/homebrew/share/opencode/sample_opencode.json"
    "/usr/local/share/opencode/sample_opencode.json"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      cp -f "$candidate" "$target"
      return 0
    fi
  done

  write_minimal_opencode_config "$target"
}

seed_defaults() {
  local src="/opt/opencode/defaults"
  local dst="${HOME}/.config/opencode"
  mkdir -p "$dst" "$dst/agents"

  if [[ "${OPENCODE_RESEED:-0}" == "1" ]]; then
    echo "🔁 OPENCODE_RESEED=1 — re-seeding $dst from baked-in defaults"
    seed_opencode_config "$dst/opencode.json"
    if [[ -d "$src/agents" ]]; then
      for f in "$src/agents/"*.md; do
        [[ -e "$f" ]] || continue
        cp -f "$f" "$dst/agents/"
      done
    fi
    return 0
  fi

  local seeded=()
  [[ -f "$dst/opencode.json" ]] || { seed_opencode_config "$dst/opencode.json"; seeded+=("opencode.json"); }
  if [[ -d "$src/agents" ]]; then
    for f in "$src/agents/"*.md; do
      [[ -e "$f" ]] || continue
      local name; name="$(basename "$f")"
      [[ -f "$dst/agents/$name" ]] || { cp "$f" "$dst/agents/$name"; seeded+=("agents/$name"); }
    done
  fi
  if (( ${#seeded[@]} > 0 )); then
    echo "🌱 Seeded global defaults into $dst: ${seeded[*]}"
  fi
}
seed_defaults

# ── Seed project-level AGENTS.md if missing ───────────────
seed_project_agents_md() {
  local src="/opt/opencode/defaults/AGENTS.md"
  local dst="AGENTS.md"
  [[ -f "$src" ]] || return 0

  if [[ "${OPENCODE_RESEED:-0}" == "1" ]]; then
    cp -f "$src" "$dst"
    echo "🔁 Re-seeded AGENTS.md into workspace"
  elif [[ ! -f "$dst" ]]; then
    cp "$src" "$dst"
    echo "🌱 Seeded AGENTS.md into workspace"
  fi
}
seed_project_agents_md

detect_workspace_lsps() {
  local scan_root="${1:-$(pwd)}"

  SCAN_ROOT="$scan_root" python3 - <<'PY'
import os
import shutil
from collections import Counter, defaultdict

scan_root = os.environ["SCAN_ROOT"]
skip_dirs = {".git", "node_modules", ".next", "dist", "build", "target", "vendor"}

# Lower rank wins ties when two languages have the same number of detected files.
popularity = {
    "typescript": 0,
    "python": 1,
    "java": 2,
    "cpp": 3,
    "go": 4,
    "rust": 5,
    "php": 6,
    "ruby": 7,
    "bash": 8,
    "json": 9,
    "yaml": 10,
    "docker": 11,
    "html": 12,
    "css": 13,
    "markdown": 14,
    "toml": 15,
    "terraform": 16,
    "lua": 17,
    "nix": 18,
    "zig": 19,
    "plantuml": 20,
}

servers = {
    "typescript": ("typescript-language-server", ["--stdio"]),
    "python": ("pyright-langserver", ["--stdio"]),
    "bash": ("bash-language-server", ["start"]),
    "docker": ("docker-langserver", ["--stdio"]),
    "yaml": ("yaml-language-server", ["--stdio"]),
    "json": ("vscode-json-language-server", ["--stdio"]),
    "html": ("vscode-html-language-server", ["--stdio"]),
    "css": ("vscode-css-language-server", ["--stdio"]),
    "markdown": ("marksman", ["server"]),
    "toml": ("taplo", ["lsp", "stdio"]),
    "terraform": ("terraform-ls", ["serve"]),
    "lua": ("lua-language-server", []),
    "go": ("gopls", []),
    "rust": ("rust-analyzer", []),
    "java": ("jdtls", []),
    "cpp": ("clangd", []),
    "ruby": ("ruby-lsp", []),
    "php": ("intelephense", ["--stdio"]),
    "nix": ("nil", []),
    "zig": ("zls", []),
    "plantuml": ("plantuml-lsp", []),
}

extension_lang = {
    ".ts": "typescript", ".tsx": "typescript", ".js": "typescript", ".jsx": "typescript",
    ".mts": "typescript", ".cts": "typescript", ".mjs": "typescript", ".cjs": "typescript",
    ".vue": "typescript", ".svelte": "typescript",
    ".py": "python", ".pyi": "python",
    ".go": "go",
    ".rs": "rust",
    ".sh": "bash", ".bash": "bash", ".zsh": "bash", ".ksh": "bash",
    ".json": "json", ".jsonc": "json",
    ".yml": "yaml", ".yaml": "yaml",
    ".html": "html", ".htm": "html",
    ".css": "css", ".scss": "css", ".sass": "css", ".less": "css",
    ".md": "markdown", ".mdx": "markdown",
    ".toml": "toml",
    ".tf": "terraform", ".tfvars": "terraform",
    ".lua": "lua",
    ".java": "java",
    ".c": "cpp", ".h": "cpp", ".cc": "cpp", ".cpp": "cpp", ".cxx": "cpp", ".hpp": "cpp", ".hh": "cpp",
    ".rb": "ruby",
    ".php": "php",
    ".nix": "nix",
    ".zig": "zig",
    ".puml": "plantuml", ".plantuml": "plantuml",
}

marker_lang = {
    "package.json": "typescript",
    "tsconfig.json": "typescript",
    "jsconfig.json": "typescript",
    "pyproject.toml": "python",
    "requirements.txt": "python",
    "setup.py": "python",
    "Pipfile": "python",
    "go.mod": "go",
    "Cargo.toml": "rust",
    "Dockerfile": "docker",
    "Containerfile": "docker",
    "docker-compose.yml": "docker",
    "docker-compose.yaml": "docker",
    "Gemfile": "ruby",
    "composer.json": "php",
    ".terraform.lock.hcl": "terraform",
    "Terraform.lock.hcl": "terraform",
}

lang_counts = Counter()
lang_extensions = defaultdict(Counter)

for root, dirs, files in os.walk(scan_root):
    dirs[:] = [d for d in dirs if d not in skip_dirs]
    for filename in files:
        path = os.path.join(root, filename)
        marker = marker_lang.get(filename)
        lang = marker
        filetype = filename if lang in {"docker"} else None

        if lang is None:
            _, ext = os.path.splitext(filename)
            lang = extension_lang.get(ext)
            filetype = ext if lang else None

        if lang is None and ("Dockerfile" in filename or "Containerfile" in filename):
            lang = "docker"
            filetype = filename

        if not lang:
            continue

        # Count readable source files only; broken symlinks or permission errors are ignored.
        if not os.path.isfile(path):
            continue
        lang_counts[lang] += 1
        if filetype:
            lang_extensions[lang][filetype] += 1

        # Marker files can imply a project LSP but are also normal typed files.
        if marker:
            _, marker_ext = os.path.splitext(filename)
            marker_ext_lang = extension_lang.get(marker_ext)
            if marker_ext and marker_ext_lang:
                lang_counts[marker_ext_lang] += 1
                lang_extensions[marker_ext_lang][marker_ext] += 1

for lang in sorted(lang_counts, key=lambda item: (-lang_counts[item], popularity.get(item, 999), item)):
    server = servers.get(lang)
    if not server:
        continue
    command, args = server
    if not shutil.which(command):
        continue
    extensions = sorted(lang_extensions[lang], key=lambda item: (-lang_extensions[lang][item], item))
    fields = [lang, str(lang_counts[lang]), command, *args, ",".join(extensions)]
    print("|".join(fields))
PY
}

configure_workspace_lsps() {
  local config_file="${HOME}/.config/opencode/opencode.json"
  local matched_json

  matched_json="$(detect_workspace_lsps "$(pwd)" | python3 -c '
import json, sys
result = {}
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    lang, count, command, *args_and_extensions = line.split("|")
    extension_field = args_and_extensions.pop() if args_and_extensions else ""
    extensions = extension_field.split(",") if extension_field else []
    result[lang] = {"command": [command, *args_and_extensions], "extensions": extensions}
print(json.dumps(result, separators=(",", ":")))
')"

  echo "── Workspace LSP Match ──────────────────────────────"
  if [[ -z "$matched_json" || "$matched_json" == "{}" ]]; then
    echo "🔎 No installed LSP matched files under $(pwd)"
    echo "─────────────────────────────────────────────────────"
    return 0
  fi

  mkdir -p "$(dirname "$config_file")"
  MATCHED_LSP_JSON="$matched_json" CONFIG_FILE="$config_file" python3 - <<'PY'
import json, os
config_file = os.environ["CONFIG_FILE"]
matched = json.loads(os.environ["MATCHED_LSP_JSON"])
try:
    with open(config_file, "r", encoding="utf-8") as fh:
        config = json.load(fh)
except Exception:
    config = {}
existing = config.get("lsp")
if existing is True:
    existing = {}
elif not isinstance(existing, dict):
    existing = {}
for name, value in matched.items():
    existing.setdefault(name, value)
config["lsp"] = existing
with open(config_file, "w", encoding="utf-8") as fh:
    json.dump(config, fh, indent=2)
    fh.write("\n")
PY

  printf '✅ Enabled matching LSPs by workspace popularity:'
  MATCHED_LSP_JSON="$matched_json" python3 - <<'PY'
import json, os
print(' ' + ' '.join(json.loads(os.environ["MATCHED_LSP_JSON"]).keys()))
PY
  echo "Config: $config_file"
  echo "─────────────────────────────────────────────────────"
}
command_version() {
  command_version_opencode "$@"
}

echo "opencode version:   $(command_version opencode unknown --version)"
echo "Paradigm: GStack subagent crew (software engineering team)"
echo "node version:       $(command_version node unknown --version)"
echo "pnpm version:       $(command_version pnpm n/a -v)"
configure_workspace_lsps

echo "── Team Workflow ────────────────────────────────────"
echo "Lead flow: classify → plan/design → delegate → build → verify → review"
echo "Review gates: @adversarial-reviewer always; @security-reviewer for sensitive changes; @spec-keeper for _spec/docs contracts"
echo "HITL: approve risky bash, destructive ops, publishes, deploys, secrets, and network/security changes"
echo "─────────────────────────────────────────────────────"

# ── Verification command discovery ────────────────────────
if [[ -f /opt/proveo/lib/detect-verify.sh ]]; then
  # shellcheck source=/dev/null
  source /opt/proveo/lib/detect-verify.sh
  echo "── Verification Commands ────────────────────────────"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    cat <<< "  $line"
  done < <(detect_verify_commands "$(pwd)")
  echo "─────────────────────────────────────────────────────"
fi

# ── Configuration check ────────────────────────────────────
echo "── Configuration Check ──────────────────────────────"
if [[ -f opencode.json ]]; then
  echo "✅ Found opencode.json"
elif [[ -f opencode.jsonc ]]; then
  echo "✅ Found opencode.jsonc"
else
  echo "🔎 No project opencode.json"
fi
if [[ -f AGENTS.md ]]; then echo "✅ Found AGENTS.md"; else echo "🔎 No AGENTS.md"; fi

# Surface available subagents (global + project)
agent_files=()
[[ -d "${HOME}/.config/opencode/agents" ]] && \
  while IFS= read -r f; do agent_files+=("@$(basename "${f%.md}")"); done \
  < <(find "${HOME}/.config/opencode/agents" -maxdepth 1 -name '*.md' 2>/dev/null | sort)
[[ -d .opencode/agents ]] && \
  while IFS= read -r f; do agent_files+=("@$(basename "${f%.md}") (project)"); done \
  < <(find .opencode/agents -maxdepth 1 -name '*.md' 2>/dev/null | sort)
if (( ${#agent_files[@]} > 0 )); then
  echo "🧑‍💻 Subagents available: ${agent_files[*]}"
fi
echo "─────────────────────────────────────────────────────"

if [[ "${PROVEO_SMOKE_TEST:-0}" == "1" ]]; then
  echo "✅ PROVEO_SMOKE_READY ${PROVEO_SMOKE_TARGET:-opencode}"
  exec sleep infinity
fi

# ── Ensure node deps if this is a Node project ─────────────
ensure_node_deps() {
  ensure_node_deps_common
}
ensure_node_deps
ensure_project_tools

# ── API key detection ──────────────────────────────────────
has_api_key() {
  [[ -n "$ANTHROPIC_API_KEY" ]] || \
  [[ -n "$OPENAI_API_KEY" ]] || \
  [[ -n "$OPENROUTER_API_KEY" ]] || \
  [[ -n "$XAI_API_KEY" ]] || \
  [[ -n "$GEMINI_API_KEY" ]] || \
  [[ -n "$GOOGLE_API_KEY" ]] || \
  [[ -n "$GOOGLE_GENERATIVE_AI_API_KEY" ]] || \
  [[ -n "$DEEPSEEK_API_KEY" ]] || \
  [[ -n "$GROQ_API_KEY" ]] || \
  [[ -n "$MISTRAL_API_KEY" ]]
}

has_project_config() {
  [[ -f opencode.json ]] || [[ -f opencode.jsonc ]]
}

if ! has_api_key && ! has_project_config; then
  echo "⚠️  No provider API key env vars and no opencode.json detected."
  echo "   Set one of: ANTHROPIC_API_KEY, OPENAI_API_KEY, OPENROUTER_API_KEY,"
  echo "   XAI_API_KEY, GEMINI_API_KEY, DEEPSEEK_API_KEY, GROQ_API_KEY, ..."
  echo "   Or run 'opencode auth login' to configure credentials interactively."
fi

# ── Launch ─────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
  echo "🚀 Launching: opencode $*"
  exec opencode "$@"
fi

echo "🚀 Launching opencode TUI..."
exec opencode
