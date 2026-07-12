# Plan 5 — White-labelling: Brand Manifest + Build-time Templating

**Paradigm imported from omnigent:** omnigent already models the discipline this repo lacks — its
diagrams pull identity from **one** upstream include (`proveo.puml`): *"change it once upstream and
every diagram updates."* Generalize that from diagrams to the whole product: one brand source of
truth, consumed by build and runtime.

## Problem (from the adversarial review)
`proveo` is compiled into ~91 tracked files (~483 hits under `defs/`) with no central constant:
- **function names** (`proveo_egress_*`, `proveo_git_identity_env_args`)
- **paths** (`/opt/proveo/lib`, `/etc/proveo/mitmproxy-ca-cert.pem`)
- **env prefix** (`PROVEO_*` — the hard one; a literal token across every shell file)
- **image org** (`proveo/*` in `image_name`, smoke array, egress preflight)
- **container names** (`proveo-dind-*`, `proveo-smoke-*`), **smoke sentinel** (`PROVEO_SMOKE_READY`)
- **installer domain** (`proveo.ca` in `install.sh`, READMEs), **wrangler** (`name = "proveo-cli"`)
- **dashboard title** ("Proveo Egress Dashboard", hardcoded), **ASCII logo** (duplicated in 2 files)
- **puml `!includeurl`** to `proveo-ca/identity` (docs can't render without that URL)
- **personal directive**: `CONVENTIONS.md`/`AGENTS.md` = *"Address me as 'Executor'"* — advertised
  by the README as "collaboration conventions."

## Design
`brand.env` (or `branding.sh`) — the single source of truth:
```sh
BRAND_NAME="Proveo"                 # human-facing (dashboard title, banners, logo alt)
BRAND_SLUG="proveo"                 # env prefix + fn namespace + /opt/<slug> path base
BRAND_IMAGE_ORG="proveo"            # docker org
BRAND_ASSET_BASE_URL="https://proveo.ca/cli"
BRAND_IDENTITY_PUML="https://raw.githubusercontent.com/proveo-ca/identity/refs/heads/main/proveo.iuml"
```
Consumption in two layers:
- **Build-time templating** — Dockerfiles and baked paths (`/opt/${BRAND_SLUG}`) resolve at
  `build.sh`; the image ships already-branded so runtime stays fast.
- **Runtime indirection** — image org, asset/install URLs, dashboard title, logo, and the puml
  include become variables read from `brand.env`. The `PROVEO_*` env prefix and `proveo_*` fn
  namespace need a one-time mechanical rename to `${BRAND_SLUG^^}_*` / `${BRAND_SLUG}_*` (guarded
  by tests so nothing is missed).

## Work items — staged by mechanical difficulty
- [ ] **Stage A (variables, immediate):** dashboard title, ASCII logo (dedupe to one source),
      image org default, `install.sh`/README asset URLs, `wrangler.toml` name, puml `!includeurl`.
- [ ] **Stage B (build-time paths):** `/opt/proveo` → `/opt/${BRAND_SLUG}` templated in Dockerfiles
      + entrypoints.
- [ ] **Stage C (env prefix + fn namespace):** scripted rename `PROVEO_` → `${SLUG^^}_`,
      `proveo_` → `${SLUG}_`, with a compatibility shim reading legacy `PROVEO_*` for one release.
- [ ] **Stage D (de-personalize):** move *"Address me as 'Executor'"* out of the reusable
      `CONVENTIONS.md`/`AGENTS.md` template into a local-only override; ship a neutral conventions
      template the README can honestly point at.
- [ ] A `make rebrand` / `brand.sh apply` that regenerates templated files from `brand.env`, plus a
      test asserting no residual hardcoded `proveo` outside `brand.env` (allowlist the upstream org
      URL until identity is forked).

## Acceptance criteria
- Changing `BRAND_NAME`/`BRAND_SLUG`/`BRAND_IMAGE_ORG` in `brand.env` + one apply step rebrands the
  product; a test proves no stray hardcoded brand token remains.
- Docs render without depending on a live `proveo-ca` URL once the identity include is a variable
  (fork target documented).
- The reusable template carries no personal persona directive.
- Spec-first: `_spec/README.md` (theme/identity section) documents `brand.env` as the identity
  source of truth *before* the rename.
