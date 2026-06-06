# Project Specifications

A collection of compressed prompt inputs used to architect, scale, and communicate modules in a project.

> Keeping the code and throwing away the prompts is the 2025 equivalent of throwing away the source and keeping the binary.
>
> - Tobi Lutke https://x.com/tobi/status/2009788652218695727

This is a generic blueprint. Drop it into any project's `_spec/` directory and adapt the examples — the conventions below are deliberately project-agnostic so diagrams look and read the same everywhere.

## SPEC references

Source files link to their spec via a top-line comment:

```ts
// SPEC: _spec/apps/web/model-grid/row-loading-lifecycle.puml
```

```yaml
# SPEC: _spec/.github/dev-deployment-workflow.puml
```

When a source file implements more than one diagram, list them on a **single**
`SPEC:` line as **comma-separated** paths — not multiple `SPEC:` lines:

```sh
# SPEC: _spec/defs/claudecode/claudecode-topology.puml, _spec/defs/claudecode/claudecode-egress-topology.puml
```

### SPEC lifecycle rules

- **Every new `.puml` MUST be referenced from at least one source file** via a `// SPEC:` / `# SPEC:` comment. A diagram with no inbound reference is an orphan — readers can't discover it from the code, and it will silently rot when the code it describes evolves. If the right source file is auto-generated (e.g. client stubs or constants emitted by a code generator), attach the reference to the upstream definition that drives the generator (the schema, the config file), not the generated file. If the diagram covers a cross-cutting invariant (tenant isolation, error envelopes), attach it to every file that enforces the invariant, not just one. **Exception:** diagrams under `_spec/_refactors/` are intentionally frozen historical snapshots and are not required to be referenced from current source.
- **When a source file with a `// SPEC` comment is deleted or renamed**, do not delete the `.puml`. Instead, find the new file(s) or approach that replaced the spec'd behavior and update the SPEC reference there.
- **Only delete a `.puml`** when the entire feature it describes has been removed from the codebase. If a feature was merely reimplemented on a different technology, mark the diagram `OUTDATED` rather than deleting it — the _behavior_ still exists under a different implementation.
- **When refactoring** moves logic to a new file, move the `// SPEC` comment to the new file and update the `.puml` if the architecture changed.

## Diagram conventions

Specifications under `_spec/` should optimize for:

- architectural communication
- current-state accuracy
- visual consistency
- separation of critical vs secondary paths

### Color palette

The palette is owned by the shared proveo identity theme (see [Theme and stylesheet](#theme-and-stylesheet)). Use these roles consistently across `.puml` files:

- `#005F7F` `COLOR_MAIN` — dark teal — first-party applications and runtime services
- `#00BAC6` `COLOR_ALT` — bright cyan — cloud / external / third-party systems and groupings
- `#CBDB2A` `COLOR_ACCENT` — yellow-green — actors, async / event-driven / queued systems
- `#009532` `COLOR_SUCCESS` — forest green — healthy / completed / success transitions, persistence accents
- `#6E1100` `COLOR_ERROR` — dark red — destructive / failure / warning-critical flows
- `#585858` `COLOR_GRAY` — medium gray — neutral state, persistence stores, notes

### Standard visual mapping

The theme styles elements by their PlantUML keyword — choose the keyword that matches the role and the color follows automatically. Reach for an explicit color only when the keyword can't carry the meaning.

#### Apps / runtime services — `component`

Rendered in `COLOR_MAIN` (`#005F7F`). Use for first-party application components:

- web frontends
- API servers
- orchestration runtimes
- workers
- deterministic / background compute services

#### Cloud / third-party systems — `cloud`

Bordered in `COLOR_ALT` (`#00BAC6`). Use for systems you don't own:

- external SaaS
- external auth providers
- external messaging systems
- vendor APIs
- cloud platforms

#### Databases / persistence — `database`

Gray fill with a `COLOR_SUCCESS` green border. Use for:

- relational schemas
- caches / key-value stores
- object storage presented as persistence
- state stores

#### Actors / users — `actor`

Rendered in `COLOR_ACCENT` (`#CBDB2A`). Use for human users and external initiators of a flow.

#### Eventing / async systems — `queue`

Rendered in `COLOR_ACCENT` (`#CBDB2A`). Prefer when a component is primarily:

- queue-driven
- event bus oriented
- scheduler / async dispatcher
- eventual consistency boundary

#### Host / platform boundary — `node`

Light fill, gray border. Use for:

- host machine
- local platform boundary
- operator-controlled runtime boundary
- deployment substrate when diagramming local/owned infrastructure

#### Groupings — `frame` / `folder`

`frame` borders in `COLOR_MAIN`, `folder` borders in `COLOR_ALT`. Use to group related nodes or denote a bounded context.

#### Errors / dangerous transitions

Use `COLOR_ERROR` (`#6E1100`) sparingly — via the `errorLabel()` macro or an inline `-[#6E1100,bold]->` arrow — for:

- destructive actions
- explicit error paths
- invalidation / failure hot paths
- security-sensitive or dangerous transitions

### Arrow conventions

Use arrows intentionally:

- `-->` primary / critical / synchronous runtime path
- `..>` secondary / supporting / indirect / optional dependency
- `-->>` explicit response when useful in sequence diagrams
- `..>>` non-critical async or informational response
- `-\\` or grouped async sections only when it materially improves readability

Do not make every dependency primary.

A good default:

- primary user/runtime/control path = solid arrows
- supporting integrations, metadata lookups, validators, optional subsystems = dotted arrows

#### Path weight and colored intent

The theme defines two line weights — use them to separate critical from supporting edges:

| Define        | Expands to    | Use for                         |
| ------------- | ------------- | ------------------------------- |
| `PATH_MAIN`   | `thickness=3` | primary / critical runtime path |
| `PATH_COMMON` | `thickness=1` | secondary / supporting edge     |

For diagrams (especially state machines and lifecycles) where the **intent** of each edge matters, color the arrow with its palette role rather than leaving every edge default. Recommended conventions:

| Arrow                      | Use for                                              |
| -------------------------- | ---------------------------------------------------- |
| `-[#005F7F,PATH_MAIN]->`   | user-driven / synchronous happy path                 |
| `-[#585858,PATH_COMMON]->` | re-run / resume / retry / pause / supporting alt      |
| `-[#6E1100,bold]->`        | failure or cancel transition                         |
| `-[#CBDB2A,bold]->`        | internal async hand-off (background task, event bus) |
| `-[#00BAC6,dashed,bold]->` | transition driven by an external system result       |

Usage:

```puml
A -[#005F7F,PATH_MAIN]->   B : ""startSession()""
B -[#CBDB2A,bold]->        C : background task
C -[#00BAC6,dashed,bold]-> D : external system finished
D -[#585858,PATH_COMMON]-> E : re-run path
D -[#6E1100,bold]->        F : failure
```

Rules of thumb:

- pick the color by edge **intent** — don't paint a happy-path edge red just because it crosses a sad-path node
- reserve the cyan/external arrow for edges whose trigger is an external system completing (vendor response, webhook); a background task that stays inside your process is the lime/async arrow
- mixing colored arrows with raw `-->` / `..>` is fine when raw arrows already carry enough meaning (e.g. component diagrams where color is on the nodes, not the edges)

#### Label macros

The theme ships three colored-text macros for arrow labels and notes:

| Macro             | Renders as          | Use for                          |
| ----------------- | ------------------- | -------------------------------- |
| `errorLabel(x)`   | bold dark-red text  | failure / rejection annotations  |
| `successLabel(x)` | bold green text     | success / completion annotations |
| `dbLabel(x)`      | bold gray text      | persistence / state annotations  |

```puml
A --> B : successLabel(committed)
B --> C : errorLabel(rejected)
```

### Text formatting (Creole)

PlantUML labels and notes accept a small subset of Creole markup. Use it to distinguish prose from code-level references.

Inline emphasis:

| Markup                                    | Renders as        | Use for                                                                             |
| ----------------------------------------- | ----------------- | ----------------------------------------------------------------------------------- |
| `**bold**`                                | **bold**          | section labels inside notes, callouts                                               |
| `//italic//`                              | _italic_          | conceptual emphasis, never code                                                     |
| `""monospaced""`                          | `monospaced`      | code identifiers: function/class/RPC names, constants, fields, file paths, env vars |
| `__underline__`                           | underline         | rare — use only when bold is already taken                                          |
| `--strikethrough--` / `~~strikethrough~~` | ~~strikethrough~~ | deprecated paths in transitional diagrams                                           |

Block-level formatting (legal inside notes):

- headers via `<size:N>...</size>` or `**Title**` lines
- color via `<color:#6E1100>text</color>`
- background via `<back:#585858>text</back>`
- explicit font via `<font:Courier>text</font>` (prefer `""..."" ` for monospace)
- lists with `* item` / `# item`
- horizontal rule via a line of `====` or `----`
- inline images via `<img:url>`

#### Single quotes for string literals

PlantUML treats `""` (two double-quotes) as Creole monospace delimiters, so embedded literal `"` characters in a label make the parser count quote pairs incorrectly. Convention: when a label needs to reference a string-literal value from code (e.g. an enum value, a kwarg, a header name), **use single quotes**:

```puml
A --> B : ""StopSession(action='pause')""\n[""session.status"" == 'executing']
```

Single quotes are only special at the start of a logical line (full-line comment), so they're safe inside labels and notes. Reserve `""..."" ` for the surrounding identifier wrapping. `&quot;` is supported as a literal-quote escape but produces noisy, grep-hostile source — avoid it unless you have a reason.

#### What to wrap

Wrap in `""..."" ` whenever the reader benefits from knowing "this is the exact name you'll find in code":

- function and method calls: `""updateStatus(sessionId, orgId)""`
- class / RPC / type names: `""SessionOrchestrator""`, `""CreateSession""`
- constants: `""MAX_CONCURRENT_WORKERS""`, `""FAILED_PRECONDITION""`
- field / column / JSON keys: `""plan_json""`, `""session.status""`
- file paths: `""apps/web/src/lib/model-grid.ts""`
- env vars and channel formats: `""DATABASE_URL""`, `""org:{orgId}:{resource}:{id}""`

Do **not** wrap:

- plain prose words ("session", "executing", "the orchestrator")
- node IDs that already appear as styled boxes in the diagram
- numbers, units, or natural-language verbs

### Naming conventions

Prefer explicit names over generic boxes.

Good:

- `apps/web Model Grid UI`
- `apps/api Session Routes`
- `apps/worker Background Processor`

Less good:

- `Frontend`
- `Backend`
- `Service Layer`

### Historical diagrams

`_spec/_refactors/` contains frozen-in-time diagrams documenting past design decisions (before/after comparisons, migration snapshots). These do **not** follow the current theme or conventions and should be ignored by default — do not update, lint, or validate them against current source code.

### Current state vs future direction

Diagrams should default to **current implementation truth**.

If future direction is relevant:

- keep it in notes
- do not rename current components to future-state abstractions
- avoid implying systems exist before they do

Example:

- acceptable: a note saying the current architecture is a stepping stone toward a future event-sourced platform
- not acceptable: labeling current relational schemas as the future service abstraction they're meant to grow into

### Validating diagrams

Run `plantuml -checkonly path/to/file.puml` on every new or edited `.puml`. Empty stdout + exit code `0` means clean; otherwise the message names the line number where the parser broke.

Install if missing:

```bash
brew install plantuml      # macOS
# or: apt install plantuml  # Debian/Ubuntu
# or: download the jar from https://plantuml.com/download and alias `plantuml='java -jar /path/to/plantuml.jar'`
```

Sweep an entire directory:

```bash
for f in _spec/**/*.puml; do
  out=$(plantuml -checkonly "$f" 2>&1)
  [ -n "$out" ] && echo "FAIL: $f"$'\n'"$out" || echo "ok:   $f"
done
```

Common errors you'll hit:

- **Mixing diagram types.** A file that opens with `class …` is parsed as a class diagram and rejects component-diagram primitives (`cloud`, `database`, `folder`, `component`). Convert those to `class "name" as X <<stereotype>> #color` form (class diagrams accept a single `#color` after the stereotype).
- **Nested `[ ]` in `component [...]` labels.** Type annotations like `dict[str, Fact]` collide with the bracket-form parser — move the detail into a `note`, or use `rectangle "label" as X` instead.
- **Nested `""..."" ` Creole monospace inside quoted declarations.** `participant "..."`, `actor "..."`, `database "..."`, `component "..."` use the first inner `"` as their closing delimiter. Drop the monospace in the declaration label or switch to the bracket form `[...]`.
- **Deprecated `#color:text;` activity-node prefix.** New form is `:text; <<#color>>`.
- **Arrow labels that are entirely `""..."" ` monospace lose their formatting.** When the label after `:` starts with the Creole double-quote pair, PlantUML treats `""…""` as a quoted-string delimiter and strips the inner content instead of rendering it monospace. Wrap the whole label in outer double quotes so PlantUML keeps the Creole markers intact:

  ```puml
  ' Wrong — renders as plain text or breaks:
  EX --> FR : ""registry.add(fact)""

  ' Right — outer "" makes the label a string, inner ""..."" renders monospaced:
  EX --> FR : " ""registry.add(fact)"" "
  ```

  Only needed when the entire label is monospace. Mixed prose like `: invokes ""add(fact)""` is fine as-is.

### Theme and stylesheet

All `.puml` files should pull in the shared proveo identity theme via remote include:

```puml
!includeurl https://raw.githubusercontent.com/proveo-ca/identity/refs/heads/main/proveo.iuml
```

This is the single source of truth for color across every proveo project — change it once upstream and every diagram updates.

The theme provides:

- a `<style>` block setting `root`, `component`, `node`, `database`, `actor`, `queue`, `arrow`, `note`, `cloud`, `frame`, and `folder` defaults (Padauk font, `#FAFAFA` background, rounded corners, shadows)
- `!define` macros for the palette
- `!define` macros for path weights and colored labels

Palette defines:

| Define          | Value     | Role                                        |
| --------------- | --------- | ------------------------------------------- |
| `COLOR_MAIN`    | `#005F7F` | first-party applications / runtime services |
| `COLOR_ALT`     | `#00BAC6` | cloud / external systems, groupings         |
| `COLOR_ACCENT`  | `#CBDB2A` | actors, async / queued systems              |
| `COLOR_SUCCESS` | `#009532` | healthy / completed / success               |
| `COLOR_ERROR`   | `#6E1100` | destructive / failure / warning-critical    |
| `COLOR_GRAY`    | `#585858` | neutral state, persistence, notes           |

Path + label defines:

| Define            | Expands to      | Use for                     |
| ----------------- | --------------- | --------------------------- |
| `PATH_MAIN`       | `thickness=3`   | primary / critical path     |
| `PATH_COMMON`     | `thickness=1`   | secondary / supporting edge |
| `errorLabel(x)`   | bold red text   | failure annotations         |
| `successLabel(x)` | bold green text | success annotations         |
| `dbLabel(x)`      | bold gray text  | persistence annotations     |

Because the theme styles by element keyword, you get the right color simply by choosing the right primitive — no per-node color needed in most diagrams:

```puml
component "apps/web"      as web
database  "Primary Store" as db
cloud     "Vendor API"    as vendor
queue     "Event Bus"     as bus
actor     "Operator"      as op
node      "Host"          as host
```

When you do need an explicit color, use the defines instead of raw hex:

```puml
component "apps/web" as web COLOR_MAIN
database "Redis" as redis COLOR_GRAY
cloud "External" as ext COLOR_ALT
```

Diagram-specific settings (e.g. `skinparam linetype polyline`, `!pragma layout smetana`, `skinparam defaultFontSize 11`) stay in the individual file after the `!includeurl`.

### Layout hints

PlantUML's auto-layout often clusters components awkwardly. Use **hidden arrows** (no arrowhead) to space elements for readability.

Rules:

- wrap all hidden arrows in a clearly marked block so agents and editors know to skip them
- use `-[hidden]-` (no arrowhead) — never `-[hidden]->`
- group them in one place, don't scatter through the file

Format:

```puml
' --- IGNORE: layout hints (do not edit) ---
A -[hidden]- B
C -[hidden]- D
' --- END IGNORE ---
```

Common patterns:

- **horizontal spacing** within a container: `web -[hidden]- worker` to spread siblings
- **vertical ordering** between sections: `DEPLOY -down[hidden]-- INFRA` to push infra below deploy
- **adjacent alignment**: `GH -right[hidden]- BUILD` to place build phase beside trigger

### Practical rule of thumb

Each diagram should answer one of these clearly:

- what is the primary runtime path?
- what is state vs compute vs orchestration?
- which dependencies are core and which are supporting?
- what is current reality vs future intent?
