# Conventions for the AI Agentic Assistant

> **Scope** These conventions standardize how we design, code, test, and operate the *AI agentic assistant* that powers the Node.js backend.  They are living rules, raise a PR to propose changes.

---

## 1 Runtime & Language

| Topic               | Convention                                                                                                                                                                         |
| ------------------- |------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Node.js**         | `^22` (lts) – make sure your local toolchain and CI use `node@22`.<br>▪︎ Release notes: [https://nodejs.org/en/blog/release/v22.16.0](https://nodejs.org/en/blog/release/v22.16.0) |
| **TypeScript**      | `^5.8` in **strict** mode.<br>▪︎ Handbook: [https://www.typescriptlang.org/docs/handbook/intro.html](https://www.typescriptlang.org/docs/handbook/intro.html)                      |
| **Package‑manager** | `pnpm^10.11` (workspaces).  Lock‑file (`pnpm-lock.yaml`) is source‑controlled.                                                                                                     |

### 1.1 Compiler & Linting

* `tsconfig.json` (strict + incremental builds).
* **ESLint** (`@typescript-eslint`) + **Prettier**: run `pnpm lint` locally & in CI.
* Path aliases live in `tsconfig.paths.json`; mirror them in `eslint-import-resolver`.

### 1.2 PNPM monorepo
* This is a monorepo. You will apply installs and run commands using `apps/api/package.json`, use `pnpm -r`.
---

## 2 Framework: Fastify v5

* **Version**: `fastify@^5` (requires Node 20+).  Migration guide: [https://fastify.io/docs/v5.3.x/Guides/Migration-Guide-V5/](https://fastify.io/docs/v5.3.x/Guides/Migration-Guide-V5/).
* **Autoload**

    * `src/routes/**\/*.ts` – route files
    * `src/plugins/**\/*.ts` – plugins (prefixed with `plugin.` when sensible)
    * Register with [https://github.com/fastify/fastify-autoload](https://github.com/fastify/fastify-autoload).
* **Best practices** (see [https://fastify.io/docs/v5.1.x/Guides/Recommendations/](https://fastify.io/docs/v5.1.x/Guides/Recommendations/)):

    1. **Schema‑first**– every route exports `schema` (typed with `JSONSchemaToTS`).
    2. **Serialize** responses with `fast-json-stringify` (enabled by default).
    3. **Security** – `@fastify/helmet`, CORS defaults locked down, rate‑limit `@fastify/rate-limit`.
    4. **Observability** – built‑in `pino` logger (pretty in dev, JSON in prod), `@fastify/metrics` for Prom / OpenTelemetry.
    5. **Hooks order** – keep async hooks minimal; heavy logic lives in services/use‑cases.
* **Error Handling**

    * Use Fastify’s`setErrorHandler` once—in `src/plugins/error-handler.ts`.
    * Never `throw` raw errors from domain layer; wrap in `AppError` variants.

---

## 3 Clean Architecture Layers

```
src/
├── domain          # Entities, value objects, business rules (pure TS)
├── application     # Use‑cases & orchestrators (depends on domain only)
├── infrastructure  # External adapters (DB, HTTP, LLM APIs, queues)
├── routes          # Fastify route/controllers, DTO mappers, schemas
└── plugins         # Cross‑cutting Fastify plugins (auth, DI container)
```

* **Dependency Rule**– lower layers **never** import from higher layers.
* DI container (`tsyringe`) registers implementations in `infrastructure/*` at boot.
* Pure functions where possible; side‑effects live behind interfaces.
* Useful reference: [https://medium.com/@vitalii-zdanovskyi/a-definitive-guide-to-building-a-nodejs-app-using-clean-architecture-and-typescript-41d01c6badfa](https://medium.com/@vitalii-zdanovskyi/a-definitive-guide-to-building-a-nodejs-app-using-clean-architecture-and-typescript-41d01c6badfa).

---

## 4 Testing Strategy

* **Unit**: Vitest + `@fastify/inject` for handlers.
* **Integration**: Use `curl` on the modified route, with the needed method, body and headers. Assert the expected response.
* Coverage target **80%+** lines/branches.

---

## 5 CI / CD Pipeline
> // TODO
--- 

## 6 Commit & PR Conventions

| Rule                      | Example                                               |
| ------------------------- | ----------------------------------------------------- |
| Conventional Commits      | `feat(router): add /chat/completions stream endpoint` |
| One logical change per PR | Small, reviewable, passes CI                          |
| Linked issue & checklist  | Use `Fixes #123`                                      |

---

## 7 Environment & Config

* `.env.example` documents required vars (`DATABASE_URL`, etc.).
* Validate at runtime with `@fastify/env-schema`.

---

## 8 Security & Compliance

* OWASP Top 10 audits each release.
* Use `npm audit --production` in CI (fail on *high* severity).
* Enable Dependabot weekly.

---

## 9 Performance Notes

* Prefer native `fetch` (Node 22) over axios; enable `globalThis.fetch` polyfill when targeting earlier Node.
* Use Fastify’s built‑in `keepAliveTimeout` defaults (8s as of v5).  Adjust via env var if behind a load balancer.
* Heavy CPU tasks go to Worker Threads or external micro‑services.

---

## 10 Reference Links

* **Node 22 release notes**– [https://nodejs.org/en/blog/release/v22.0.0](https://nodejs.org/en/blog/release/v22.0.0)
* **Fastify v5 docs**– [https://fastify.io/docs/v5.3.x/](https://fastify.io/docs/v5.3.x/)
* **Fastify recommendations**– [https://fastify.io/docs/v5.1.x/Guides/Recommendations/](https://fastify.io/docs/v5.1.x/Guides/Recommendations/)
* **Clean Architecture overview**– [https://8thlight.com/blog/uncle-bob/2012/08/13/the-clean-architecture.html](https://8thlight.com/blog/uncle-bob/2012/08/13/the-clean-architecture.html)
* **DI with tsyringe**– [https://github.com/microsoft/tsyringe](https://github.com/microsoft/tsyringe)
* **Vitest**- [https://vitest.dev/](https://vitest.dev/)
* **Pino logger**– [https://getpino.io/](https://getpino.io/)
* **OpenTelemetry Node**– [https://opentelemetry.io/docs/instrumentation/js/](https://opentelemetry.io/docs/instrumentation/js/)

---
