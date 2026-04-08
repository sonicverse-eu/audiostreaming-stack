# Agent Instructions

This repository accepts AI-assisted changes, but agents should follow the same standards as human contributors in [CONTRIBUTING.md](CONTRIBUTING.md).

Primary project documentation is maintained at **https://docs.sonicverse.eu** and should be treated as the source of truth for setup and operations.
MCP documentation: **https://docs.sonicverse.eu/mcp**

## MCP Routing

- If a reference contains `SVAS-`, or mentions `Jira`, `jira`, or `Atlassian`, use the Jira MCP.
- If you find a reference containing `Codacy` or `codacy`, use the Codacy MCP.

## Scope

- Keep changes focused on one bug fix, feature, or cleanup.
- Prefer minimal diffs that match the existing structure and style of each service.
- Do not introduce new environment variables without updating `.env.example` and the configuration table in `README.md`.

## Service Workflow

| Service | How to iterate |
|---------|----------------|
| `dashboard` | `cd apps/dashboard && npm install && npm run dev` |
| `status-api` | Edit `apps/status-api/server.py`, then `docker compose restart status-api` |
| `analytics` | Edit `services/analytics/tracker.py`, then `docker compose restart analytics` |
| `liquidsoap` | Edit `services/streaming/liquidsoap/radio.liq`, then `docker compose restart liquidsoap` |
| `nginx` | Edit `infrastructure/nginx/nginx.conf`, then `docker compose restart nginx` |

## Required Checks

- Python changes: `ruff check services/analytics/ apps/status-api/`
- TypeScript changes: `cd apps/dashboard && npm run lint`
- Dockerfile changes: `hadolint <Dockerfile>`
- YAML changes: `yamllint -c .yamllint.yml docker-compose.yml .github/workflows/`
- Service changes that affect runtime behavior: validate with `docker compose up -d` or the smallest equivalent local check

## Formatting Requirements

- Python must satisfy the repository Ruff rules in `pyproject.toml`.
- TypeScript and TSX must stay ESLint-clean with no warnings.
- Shell scripts should follow the existing conventions: `set -e`, 4-space indentation, and `"double-quoted"` variables.
- Dockerfiles should remain hadolint-clean under the current workflow allowances.

## Pull Request Expectations

- Update `README.md` when behavior or configuration changes.
- Keep the PR template sections (Summary, Related issue) accurate and complete.
- Pull requests must link to the related issue when one exists.
