# AI PR Reviewer Instructions

## Purpose

- Sonicverse is a self-hosted Docker Compose stack for live radio streaming.
- It combines studio ingest, stream processing, listener delivery, health/status APIs, analytics, and operator tooling in one deployable repository.

## Architecture

- The stack is orchestrated with `docker-compose.yml`; service boundaries are intentional and should stay clear.
- `services/streaming/liquidsoap/` handles ingest, fallback, silence detection, encoding, and HLS segment generation.
- `services/streaming/icecast/` serves as the streaming distribution layer for multiple public mount points.
- `infrastructure/nginx/` is the public edge: reverse proxy, HLS serving, and TLS/bootstrap templating.
- `apps/status-api/` is a Flask API that reads stream/container state and exposes authenticated operator actions.
- `services/analytics/` polls Icecast, emits PostHog events, and sends Pushover alerts for outages and silence.
- `apps/dashboard/` is a Next.js operator UI that talks to `status-api`; keep frontend assumptions aligned with API payloads.
- Favor small, service-local changes over cross-cutting rewrites.

## Folder Structure

- `apps/dashboard/`: Next.js dashboard UI, auth wiring, API client helpers, and TSX components.
- `apps/status-api/`: Flask status/control API for the dashboard and operational endpoints.
- `services/analytics/`: Python analytics and alerting worker.
- `services/streaming/liquidsoap/`: Liquidsoap radio pipeline and streaming behavior.
- `services/streaming/icecast/`: Icecast server image and config.
- `infrastructure/nginx/`: Nginx config, HTML template, and container entrypoint.
- `docs/`: supplemental project docs; external docs remain canonical for setup/ops.

## Stack

- Python 3.12 services with Ruff linting in `apps/status-api/` and `services/analytics/`.
- Next.js 16, React 19, TypeScript, and ESLint in `apps/dashboard/`.
- Docker Compose for local/prod orchestration.
- Liquidsoap for ingest, fallback, transcoding, and HLS.
- Icecast2 for stream distribution.
- Nginx for reverse proxying and public delivery.
- Appwrite for dashboard authentication/authorization.
- PostHog and Pushover integrations for analytics and alerting.

## Testing

- There is no dedicated unit/integration test suite in this repository today.
- Treat lint and config validation as the enforced automated checks:
- Python: `ruff check services/analytics/ apps/status-api/`
- TypeScript: `cd apps/dashboard && npm run lint`
- Dockerfiles: `hadolint <Dockerfile>`
- YAML: `yamllint -c .yamllint.yml docker-compose.yml .github/workflows/`
- If runtime behavior changes, reviewers should expect a minimal service-level validation such as `docker compose up -d` or the narrowest equivalent restart/check.

## Code Style And Conventions

- Match the existing service-local style instead of introducing a repo-wide abstraction layer.
- Keep Python modules straightforward and procedural unless the surrounding file already uses a different pattern.
- Respect Ruff settings in `pyproject.toml`: line length 100, Python target 3.12, import sorting enabled.
- Keep TypeScript/TSX ESLint-clean with zero warnings.
- Use existing naming patterns: kebab-case files in the dashboard, snake_case in Python, descriptive environment-variable names in uppercase.
- Preserve the current dashboard structure of colocated components plus shared helpers under `apps/dashboard/lib/`.
- Shell scripts should keep `set -e`, 4-space indentation, and `"double-quoted"` variables.
- Avoid adding new environment variables unless `.env.example` and the `README.md` configuration table are updated in the same PR.

## PR-Specific Rules

- Keep each PR focused on one bug fix, feature, or cleanup.
- Branch from `main`.
- Reference the related issue when one exists.
- Update `README.md` when user-visible behavior or configuration changes.
- Do not mix unrelated refactors into operational changes, especially across multiple services.
- Changes to runtime behavior should stay consistent with the canonical docs at `https://docs.sonicverse.eu`.

## Common Pitfalls

- Breaking the fallback chain in `radio.liq` can take the entire station off air; review source ordering and infallibility carefully.
- API payload changes in `apps/status-api/` can silently break the dashboard if matching TypeScript types/components are not updated.
- Docker Compose, Nginx, and service env vars are tightly coupled; renames or default changes often require updates in multiple files.
- The dashboard is operator-facing; auth and write-access checks must not be weakened when adding actions.
- The analytics service mixes listener polling and alerting responsibilities; changes can affect observability and incident noise at the same time.

## Out Of Scope

- Ignore generated dependency trees and installed artifacts such as `node_modules`.
- Do not request large architectural rewrites when a service-local fix is sufficient.
- Do not treat external setup/operations docs as duplicative drift unless the PR actually changes repo behavior; `docs.sonicverse.eu` is the source of truth for ops guidance.
