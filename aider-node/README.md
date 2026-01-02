# Aider Docker Runner

Custom wrapper for `paulgauthier/aider-full` with:

- `node-slim` 22 as base (has `node`, `npm` and `curl` installed)
- Monorepo easy setup (`pnpm`)
- Interactive LLM choice + key fallbacks

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
Navigate to your subfolder, (e.g. `apps/api/`), create an `.aiderignore`:
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

---

## Working with an Agent

When using aider as an AI coding agent, follow a structured workflow to maximize effectiveness. This mirrors how professional developers approach complex tasks.

## Parallelism

For large projects, you can run multiple aider instances in parallel:
- Each instance should work on a **separate, isolated scope** (different files/features)
- Use separate terminal sessions or tmux panes
- Avoid overlapping file edits to prevent git conflicts
- Consider using `--no-auto-commits` when coordinating multiple agents

**Git Worktrees Limitation:**
Aider currently has difficulties with git worktrees—it may fail to detect the repository correctly or have issues with commit operations. If you need true parallel development:

| Alternative | Use Case |
|-------------|----------|
| **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** | Anthropic's CLI agent with better worktree support |
| **[Codex CLI](https://github.com/openai/codex)** | OpenAI's coding agent |
| **[Cursor](https://cursor.sh)** | IDE with multi-file AI editing |
| **Separate clones** | Clone the repo multiple times instead of using worktrees |

For now, the safest parallel approach with aider is running instances on **completely separate file sets** within the same repo, or using separate full clones.

---

## Scope

**Define what the agent can see and modify.**

Use aider commands to build context:

| Command | Purpose |
|---------|---------|
| `/add <file>` | Add files the agent can edit |
| `/read-only <file>` | Add reference files (won't be modified) |
| `/web <url>` | Fetch and include web content as context |

**Example:**
```
/add src/api/users.ts
/read-only src/types/user.d.ts
/web https://docs.example.com/api-spec
```

> **Tip:** Start narrow. Add only the files directly relevant to your task. Aider's repo-map helps it understand the broader codebase structure.

---

## Spec

**Clarify requirements before coding.**

Use `/ask` mode to have aider help you write a specification without making changes:

```
/ask I need to build a CLI tool that converts PlantUML files to SVG. 
Help me write a spec following this template: 
/web https://raw.githubusercontent.com/proveo-ca/spec/refs/heads/main/_spec/template.txt
```

A good spec includes:
- **Overview** – What does this do?
- **Architecture** – Component layers and responsibilities
- **Execution flow** – Step-by-step behavior
- **CLI design** – Arguments, flags, options
- **Project structure** – File organization

The template above provides a comprehensive pattern for CLI tools with Docker encapsulation.

---

## Plan

**Break the spec into actionable steps.**

Continue in `/ask` mode to create an implementation plan:

```
/ask Based on the spec above, create a step-by-step implementation plan.
List each file to create/modify and what changes are needed.
```

A good plan:
- Orders tasks by dependency (create types before implementations)
- Identifies which files need creation vs modification
- Breaks large changes into reviewable chunks
- Notes potential risks or edge cases

---

## Execute

**Implement the plan using architect mode.**

Switch to `/architect` for complex, multi-file changes:

```
/architect Implement step 1 from the plan: Create the Dockerfile with 
Java runtime, PlantUML, and Graphviz dependencies.
```

The architect model will:
1. Propose changes across multiple files
2. Show you the edit plan
3. Hand off to the editor model for implementation

For simpler single-file changes, use `/code` directly.

---

## Eval

**Verify the implementation with linting and tests.**

Aider provides several commands for validation:

| Command | Purpose |
|---------|---------|
| `/lint` | Run linter on chat files (or all dirty files) and auto-fix issues |
| `/test <cmd>` | Run tests; on failure, output is added to chat for fixing |
| `/run <cmd>` | Run any shell command, optionally add output to chat |

### Linting

Run `/lint` to check and fix code style issues:

```
/lint
```

If you have a linter configured (e.g., `eslint`, `ruff`), aider will run it and attempt to fix any issues automatically.

### Testing

Use aider to create "black box" test cases that validate behavior without accessing implementation details:

```
/add tests/test_commands.py
```

Then ask aider to write tests:

```
Add a test for cmd_add that passes in 'foo.txt' and 'bar.txt' 
and ensures they have both been created after the test. 
Run the test in a tmp dir.
```

Run tests with `/test`:

```
/test pytest tests/test_commands.py
```

**Key behavior:** `/test` only adds output to the chat when the command fails (non-zero exit). This triggers aider to analyze the error and propose fixes automatically.

Configure a default test command in `.aider.conf.yml`:

```yaml
test-cmd: pytest tests/
lint-cmd: eslint --fix .
```

Then run `/test` or `/lint` without arguments.

### Running arbitrary commands

Use `/run` (or `!` alias) to execute any shell command:

```
/run npm run build
```

You'll be prompted whether to add the output to the chat—useful for sharing build errors or command output with aider.

### The eval loop

The iterative cycle is:
1. **Code** → Make changes
2. **Lint** → `/lint` to fix style issues
3. **Test** → `/test` to verify behavior
4. **Fix** → Aider auto-fixes failures
5. **Repeat** until green

### Auto-testing

Configure aider to automatically run tests after every code change using `auto-test`:

```yaml
# .aider.conf.yml
test-cmd: ./scripts/test-endpoints.sh
auto-test: true
```

Create a test script that exits non-zero on failure:

```bash
#!/usr/bin/env bash
# scripts/test-endpoints.sh
set -e

# Smoke test your API endpoints
curl -sf http://localhost:3000/api/health || exit 1
curl -sf http://localhost:3000/api/users || exit 1

echo "✅ Endpoints OK"
```

**How it works:**
1. Aider makes code changes
2. `auto-test: true` triggers `test-cmd` automatically
3. If the command fails (non-zero exit), output is added to chat
4. Aider analyzes the failure and attempts to fix it

### File-pattern triggers

For smarter testing, make your script detect which files changed and run only relevant tests:

```bash
#!/usr/bin/env bash
# scripts/smart-test.sh
set -e

changed_files=$(git diff --name-only HEAD~1 2>/dev/null || echo "")

# API changes → test endpoints
if echo "$changed_files" | grep -q "src/api/"; then
  echo "🔍 API files changed, testing endpoints..."
  curl -sf http://localhost:3000/api/health || exit 1
fi

# Schema changes → validate migrations
if echo "$changed_files" | grep -q "prisma/schema"; then
  echo "🔍 Schema changed, validating..."
  npx prisma validate || exit 1
fi

# Component changes → run unit tests
if echo "$changed_files" | grep -q "src/components/"; then
  echo "🔍 Components changed, running tests..."
  npm test -- --testPathPattern=components || exit 1
fi

echo "✅ All checks passed"
```

> **Tip:** Keep auto-test scripts fast (under 5 seconds). Slow tests break the feedback loop. For comprehensive test suites, use `/test` manually.

> **Reference:** See [aider's test creation example](https://aider.chat/examples/add-test.html) for a complete walkthrough of black-box test generation.
