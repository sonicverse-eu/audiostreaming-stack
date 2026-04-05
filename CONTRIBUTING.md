# Contributing to Sonicverse

Thank you for your interest in contributing. This document covers how to get started, submit changes, and report issues.

If you are using an AI coding agent, also follow [AGENTS.md](AGENTS.md).

## Getting Started

1. Fork the repository and clone your fork
2. Install local development dependencies from the repository root:

   ```bash
    ./install-dev-deps.sh
    ```

    Compatibility alias (same behavior): `./install-all.sh`

   On Windows PowerShell, use:

   ```powershell
    .\install-dev-deps.ps1
    ```

    Compatibility alias (same behavior): `.\install-all.ps1`

3. Copy `.env.example` to `.env` and fill in your values
4. Add at least one fallback audio file to `emergency-audio/` (MP3, FLAC, or WAV)
5. Build and start the stack:

   ```bash
    docker compose build
    docker compose up -d
    ```

## Development Workflow

| Service | How to iterate |
|---------|----------------|
| `status-dashboard` | `cd status-dashboard && npm install && npm run dev` |
| `status-panel` | Edit `server.py`, then `docker compose restart status-panel` |
| `analytics` | Edit `tracker.py`, then `docker compose restart analytics` |
| `liquidsoap` | Edit `radio.liq`, then `docker compose restart liquidsoap` |
| `nginx` | Edit `nginx.conf`, then `docker compose restart nginx` |

## Code Style

- **Python** — `ruff check analytics/ status-panel/` (config in `pyproject.toml`)
- **TypeScript** — `npm run lint` inside `status-dashboard/`
- **Shell** — follow existing style: `set -e`, 4-space indent, `"double-quoted"` variables
- **Dockerfiles** — `hadolint` clean (run `hadolint <Dockerfile>`)

## Submitting a Pull Request

1. Create a branch from `main` (`git checkout -b feat/my-feature`)
2. Make your changes; keep each PR focused on a single feature or fix
3. Run linters locally before pushing
4. Fill in the pull request template completely
5. Reference any related issue with `Closes #123`

## Adding Environment Variables

If your change introduces new environment variables:
- Add them to `.env.example` with a sensible default or blank value
- Document them in the configuration table in `README.md`

## Reporting Bugs

Use the **Bug report** issue template. Include your OS, Docker version, and relevant logs (`docker compose logs --tail=50 <service>`).

## Security Issues

See [SECURITY.md](SECURITY.md). **Do not open a public issue for security vulnerabilities.**
