# Contributing to Sonicverse

Thank you for your interest in contributing. This document covers how to get started, submit changes, and report issues.

Primary documentation lives at **https://docs.sonicverse.eu**. Use it as the canonical source for setup and operational guidance.

Task tracking for this repository uses GitHub Issues. Prefer opening or linking a GitHub issue for bugs, feature work, and follow-up tasks so PRs stay connected to the active record of work.

## Code of Conduct

This project follows [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). By participating, you agree to follow its expectations for respectful and constructive collaboration.

If you are using an AI coding agent, also follow [AGENTS.md](AGENTS.md).

## Getting Started

### Option A: Full interactive setup (recommended for most contributors)

```bash
git clone https://github.com/sonicverse-eu/audiostreaming-stack.git
cd audiostreaming-stack
./install.sh --dev
```

This installs Node/Python dependencies and walks you through stack configuration interactively.

### Option B: Manual setup (for advanced users)

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
| `dashboard` | `cd apps/dashboard && npm install && npm run dev` |
| `status-api` | Edit `apps/status-api/server.py`, then `docker compose restart status-api` |
| `analytics` | Edit `services/analytics/tracker.py`, then `docker compose restart analytics` |
| `liquidsoap` | Edit `services/streaming/liquidsoap/radio.liq`, then `docker compose restart liquidsoap` |
| `nginx` | Edit `infrastructure/nginx/nginx.conf`, then `docker compose restart nginx` |

## Code Style

- **Python** — `ruff check services/analytics/ apps/status-api/` (config in `pyproject.toml`)
- **TypeScript** — `npm run lint` inside `apps/dashboard/`
- **Shell** — follow existing style: `set -e`, 4-space indent, `"double-quoted"` variables
- **Dockerfiles** — `hadolint` clean (run `hadolint <Dockerfile>`)

## Submitting a Pull Request

1. Create a branch from `main` (`git checkout -b feat/my-feature`)
2. Make your changes; keep each PR focused on a single feature or fix
3. Run linters locally before pushing
4. Fill in the pull request template completely
5. Reference any related GitHub issue with `Closes #123`

## Adding Environment Variables

If your change introduces new environment variables:
- Add them to `.env.example` with a sensible default or blank value
- Document them in the configuration table in `README.md`

## Reporting Bugs

Use the **Bug report** GitHub Issue template. Include your OS, Docker version, and relevant logs (`docker compose logs --tail=50 <service>`).

For behavioral or conduct concerns, report through the process in [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Security Issues

See [SECURITY.md](SECURITY.md). **Do not open a public issue for security vulnerabilities.**
