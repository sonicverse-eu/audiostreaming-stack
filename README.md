# Sonicverse — Radio Audio Streaming Stack

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/sonicverse-eu/audiostreaming-stack/actions/workflows/lint.yml/badge.svg)](https://github.com/sonicverse-eu/audiostreaming-stack/actions/workflows/lint.yml)
[![GHCR](https://img.shields.io/badge/Image-GHCR-blue?logo=github)](https://github.com/sonicverse-eu/audiostreaming-stack/pkgs/container/audiostreaming-stack)
[![Docker Hub](https://img.shields.io/badge/Images-Docker%20Hub-2496ED?logo=docker&logoColor=white)](https://hub.docker.com/u/sonicverse)
[![Join Sonicverse OSS Slack](https://img.shields.io/badge/Join-Sonicverse%20OSS%20Slack-4A154B?logo=slack&logoColor=white)](https://join.slack.com/t/sonicverse-oss/shared_invite/zt-3u969i5rr-cmfgEycFAi8V7Baj0uBx0A)

> [!WARNING]
> **Early Development — Not Production Ready.** This project is under active development. APIs, configuration, and behaviour may change without notice. Do not use in production environments without thorough evaluation and testing.

Self-hosted Docker Compose stack for live radio streaming. Ingest from any studio encoder, deliver via Icecast2 and HLS adaptive bitrate, with automatic fallback, silence detection, and an optional real-time operator dashboard. The runtime services ship in one consolidated Docker image managed by a single container entrypoint.

## Documentation

For setup, operations, and troubleshooting, use the official Sonicverse docs as the single source of truth:

**https://docs.sonicverse.tech**

This repository README is a quick project overview. If local instructions differ from the external docs, follow docs.sonicverse.tech.

Contributing to this project means following the [Code of Conduct](CODE_OF_CONDUCT.md).

Project planning and task tracking currently live in GitHub Issues. When contributing work, link the relevant GitHub issue in your pull request whenever one exists.

Join the Sonicverse OSS Slack for community support, implementation questions, and contributor collaboration.

## Architecture

```
Studio (BUTT/etc)
   ├── MP3 320k stream ──► :8010 ─┐
   └── MP3 192k stream ──► :8011 ─┤
                              ▼
                   ┌───────────────────────┐
                   │ sonicverse app image  │
                   │                       │
                   │ Liquidsoap ─► HLS     │
                   │     │                 │
                   │     ▼                 │
                   │ Icecast2 ─► Nginx     │
                   │ Status API            │
                   └──────────┬────────────┘
                              │
                         :80 / :443
```

## Services

| Service | Description |
|---|---|
| **Icecast2** | Stream distribution server with multiple mount points |
| **Liquidsoap** | Stream processor — ingest, fallback chain, encoding, HLS |
| **Nginx** | Public-facing reverse proxy + HLS segment serving |
| **Status Panel** | Optional Flask API backend for the operator dashboard and service management |
| **Certbot** | Automatic Let's Encrypt certificate renewal with app reload signaling |

## Repository Structure

- `.github/` contains repository automation and project metadata, including issue templates and GitHub Actions workflows.
- `.vscode/` contains editor settings and recommended workspace configuration for contributors using VS Code.
- `apps/` contains operator-facing applications: the Next.js dashboard in `apps/dashboard/` and the Flask status API in `apps/status-api/`.
- `services/` contains runtime streaming service code under `services/streaming/`.
- `infrastructure/` contains edge and routing infrastructure definitions, currently the Nginx reverse proxy in `infrastructure/nginx/`.
- `Dockerfile` builds the unified runtime image and `scripts/unified-entrypoint.sh` supervises the processes inside the container.
- `emergency-audio/` stores local fallback media used when both studio streams are unavailable (operator-created during setup).

## Stream Inputs (Studio → Liquidsoap)

| Input | Port | Protocol | Format |
|---|---|---|---|
| Primary | 8010 | Icecast source | MP3 CBR 320 kbps |
| Fallback | 8011 | Icecast source | MP3 CBR 192 kbps |
| Emergency | — | Local file | `emergency-audio/fallback.mp3` |

Fallback chain: Primary → Fallback → Emergency file (automatic, no manual intervention needed).

## Stream Outputs (Listener Endpoints)

### Icecast (via Nginx reverse proxy)

| Mount | Format | Bitrate | URL |
|---|---|---|---|
| `/stream-mp3-128` | MP3 | 128 kbps | `https://<host>/listen/stream-mp3-128` |
| `/stream-mp3-192` | MP3 | 192 kbps | `https://<host>/listen/stream-mp3-192` |
| `/stream-mp3-320` | MP3 | 320 kbps | `https://<host>/listen/stream-mp3-320` |
| `/stream-aac-128` | AAC | 128 kbps | `https://<host>/listen/stream-aac-128` |
| `/stream-aac-192` | AAC | 192 kbps | `https://<host>/listen/stream-aac-192` |
| `/stream-ogg-128` | Ogg Vorbis | 128 kbps | `https://<host>/listen/stream-ogg-128` |

### HLS (for mobile)

```
https://<host>/hls/live.m3u8
```

Adaptive bitrate with 3 AAC quality tiers — players automatically select the best quality for the connection.

## Quick Start

Choose your setup based on your needs:

### ⚡ One-liner Installation (Fastest!)

For the quickest setup with minimal typing:

```bash
bash <(curl -fsSL https://sonicverse.short.gy/install-audiostack)
```

This works from any directory and automatically handles cloning the repository, checking prerequisites, and configuring your stack. Equivalent to the "Minimal container-image deployment" option below.

**Features:**
- Works from any directory (automatic git clone)
- Interactive configuration
- Installs only essentials for running (no development dependencies)
- ~2–5 minutes total

### 🚀 Recommended: Minimal container-image deployment (default)

Fastest option for production deployments — no building or local dependencies required:

```bash
git clone https://github.com/sonicverse-eu/audiostreaming-stack.git
cd audiostreaming-stack
./install.sh
```

This installs **only what's needed to run**:
- Docker/Docker Compose (auto-installed if missing)
- Configuration file (`.env`)
- Pre-built images (published to GHCR and Docker Hub)

**What's _not_ installed:**
- Node.js / npm (dashboard already built into image)
- Python / pip (status API already built into image)

**Time:** ~2–5 minutes (mostly downloading the unified runtime image)

### Container registries

The pre-built runtime image is published to both registries:

- **Primary (default): Docker Hub** under `sonicverse`.
- **Mirror:** GHCR under `ghcr.io/sonicverse-eu/audiostreaming-stack`.

The Build & Push Docker Image workflow builds the same multi-process runtime image for
`linux/amd64` and `linux/arm64`.

Docker Hub image name:

- `docker.io/sonicverse/audiostreaming-stack:latest`

GHCR mirror name:

- `ghcr.io/sonicverse-eu/audiostreaming-stack:latest`

### 📦 Full development environment

If you plan to modify the dashboard or API:

**Via short link:**
```bash
bash <(curl -fsSL https://sonicverse.short.gy/install-audiostack) --dev
```

**Or clone first:**
```bash
git clone https://github.com/sonicverse-eu/audiostreaming-stack.git
cd audiostreaming-stack
./install.sh --dev
```

This includes everything above **plus**:
- Node.js dependencies (dashboard development)
- Python dependencies (API development)

**Time:** ~5–10 minutes depending on your network and system

### 🔨 Build containers locally (advanced)

Build the runtime image locally instead of pulling a pre-built image - use this if you need to modify Dockerfile or container code:

**Via short link:**
```bash
bash <(curl -fsSL https://sonicverse.short.gy/install-audiostack) --build-local
```

**Or to combine with dev dependencies:**
```bash
bash <(curl -fsSL https://sonicverse.short.gy/install-audiostack) --build-local --dev
```

**Or clone first:**
```bash
git clone https://github.com/sonicverse-eu/audiostreaming-stack.git
cd audiostreaming-stack
./install.sh --build-local
```

Or for both local build and development dependencies:

```bash
./install.sh --build-local --dev
```

**Time:** ~15–30 minutes (building the unified runtime image locally)

### Manual setup

1. **Clone and configure**
   ```bash
   git clone https://github.com/sonicverse-eu/audiostreaming-stack.git
   cd audiostreaming-stack
   cp .env.example .env
   # Edit .env with your values
   ```

2. **Add emergency audio**
   ```bash
   cp /path/to/your/fallback.mp3 emergency-audio/fallback.mp3
   ```

3. **Obtain SSL certificate**
   ```bash
   ./init-letsencrypt.sh
   ```
   This script reuses the main `app` service when it is already running, or starts a temporary ACME-only nginx container for the HTTP challenge when the stack is not up yet. That temporary bootstrap container avoids port conflicts during first-time certificate provisioning.

4. **Start the stack**
   ```bash
   docker compose up -d
   ```

5. **Connect your studio encoder**

   Configure BUTT (or similar) to send:
   - **Primary stream**: Host `<server-ip>`, Port `8010`, Mount `/primary`, Password from `.env`, MIME `audio/mpeg`, bitrate `320 kbps`
   - **Fallback stream**: Host `<server-ip>`, Port `8011`, Mount `/secondary`, Password from `.env`, MIME `audio/mpeg`, bitrate `192 kbps`

   **Command-line encoder profile (LAME):**
   - Primary: `lame.exe -r -s 44.1 -b 320 -x - -`
   - Fallback: `lame.exe -r -s 44.1 -b 192 -x - -`

6. **Verify**
   - Icecast admin: `https://<host>/icecast-admin/`
   - Test stream: `https://<host>/listen/stream-mp3-128` in VLC
   - HLS: `https://<host>/hls/live.m3u8` in Safari/VLC

## Install Development Dependencies Separately

If you've already run `./install.sh` without `--dev` and now want to install development dependencies:

```bash
./install-dev-deps.sh
```

Or use the equivalent alias:

```bash
./install-all.sh
```

These scripts install (according to your needs):
- **Node.js** dependencies for the dashboard (`apps/dashboard/`)
- **Python** dependencies for the status API (`apps/status-api/`)

**When to use:**
- After a minimal deployment if you want to edit the dashboard or APIs
- For local development without using the full interactive installer
- For CI/CD pipelines

Optional flags:

- `--ci` for deterministic CI-friendly installs (uses lockfiles like `package-lock.json`, `pnpm-lock.yaml`)
- `--python-user` to install Python packages with `--user`
- `--skip-node` to skip JavaScript dependency installation
- `--skip-python` to skip Python dependency installation

**Examples:**

```bash
# Development: install everything
./install-all.sh

# CI: deterministic installs
./install-all.sh --ci

# API-only development (skip dashboard)
./install-all.sh --skip-node

# Dashboard-only development (skip backend services)
./install-all.sh --skip-python
```

**Windows PowerShell:**

```powershell
.\install-dev-deps.ps1
# or
.\install-all.ps1
```

Same flags as above are supported.

## Prerequisites

### Docker

**Ubuntu/Debian:**
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

**macOS / Windows:** Install [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Windows requires WSL 2).

### Firewall

| Port | Purpose |
|---|---|
| 80 | HTTP (Let's Encrypt ACME + redirect) |
| 443 | HTTPS (streams + HLS + admin) |
| 8010 | Studio primary input |
| 8011 | Studio fallback input |

**Automated UFW setup:**
```bash
sudo ./setup-firewall.sh

# Restrict studio ports to a specific IP (recommended):
sudo ./setup-firewall.sh --studio-ip 203.0.113.50
```

## Configuration

All settings are managed via `.env` (copy from `.env.example`):

| Variable | Description |
|---|---|
| `STATION_NAME` | Station name (used in stream metadata) |
| `STATION_LOCATION` | Station location (Icecast server info) |
| `STATION_ADMIN_EMAIL` | Admin contact email |
| `ICECAST_SOURCE_PASSWORD` | Password for Liquidsoap → Icecast connections |
| `ICECAST_ADMIN_USER` | Icecast admin username for the status API |
| `ICECAST_ADMIN_PASSWORD` | Icecast admin panel password |
| `HARBOR_PASSWORD` | Password for studio → Liquidsoap connections |
| `ICECAST_HOSTNAME` | Public hostname |
| `ICECAST_MAX_LISTENERS` | Maximum concurrent listeners |
| `LETSENCRYPT_EMAIL` | Email for Let's Encrypt notifications |
| `LETSENCRYPT_STAGING` | Set to `1` for test certificates |
| `SILENCE_THRESHOLD_DB` | Silence detection threshold in dB (default: `-40`) |
| `SILENCE_DURATION` | Seconds of silence before detection (default: `15`) |
| `ENABLE_STATUS_PANEL` | Set to `1` to expose the internal status API service through nginx |
| `APPWRITE_ENDPOINT` | Optional Appwrite API endpoint for dashboard auth |
| `APPWRITE_PROJECT_ID` | Optional Appwrite project ID |
| `APPWRITE_TEAM_ID` | Optional Appwrite team ID (required when `APPWRITE_PROJECT_ID` is set; only members get panel access) |
| `STATUS_PANEL_CORS_ORIGIN` | Optional dashboard URL(s) for CORS, comma-separated |
| `STATUS_PANEL_HOST` | Optional bind host for status API (default: `127.0.0.1`; auto-uses container IP in Docker when unset) |
| `STATUS_PANEL_WRITE_ROLES` | Appwrite team roles allowed to manage emergency audio (default: `owner,admin`) |
| `STATUS_PANEL_ALLOW_RISKY_COMMANDS` | Enable remote restart/SSL renewal commands (`0` by default) |
The status API now requires `ICECAST_ADMIN_USER` and `ICECAST_ADMIN_PASSWORD`
to be set explicitly in `.env`; they no longer fall back to built-in example credentials.

## Status Panel

Optional real-time broadcast engineer dashboard with Appwrite team-based authentication.

Set `ENABLE_STATUS_PANEL=1` to expose the internal status API service through nginx. If you manage the stack manually instead of using `./install.sh`, update `.env` and restart the app:

```bash
docker compose up -d --force-recreate app status-api
```

**Features:**
- Live listener counts and mount point status (5s refresh)
- Container health monitoring
- Stack configuration overview
- Emergency audio upload/management
- Role-based write access

### Deployment on Appwrite Sites

```bash
cd apps/dashboard
cp .env.local.example .env.local
# Edit .env.local with your streaming server URL and Appwrite credentials
npm install && npm run build
# Deploy the out/ directory to Appwrite Sites
```

The API backend runs as an internal-only Compose service and is proxied through nginx at `https://<host>/api/`.

## File Structure

```
├── docker-compose.yml
├── Dockerfile
├── .env.example
├── install-dev-deps.sh
├── install-dev-deps.ps1
├── install-all.sh
├── install-all.ps1
├── install.sh
├── init-letsencrypt.sh
├── setup-firewall.sh
├── scripts/
│   └── unified-entrypoint.sh
├── apps/
│   ├── status-api/            ← API backend process
│   │   ├── requirements.txt
│   │   └── server.py
│   └── dashboard/             ← Next.js frontend (Appwrite Sites)
│       ├── app/
│       ├── components/
│       ├── lib/
│       └── package.json
├── services/
│   └── streaming/
│       ├── icecast/
│       │   └── icecast.xml
│       └── liquidsoap/
│           └── radio.liq
├── infrastructure/
│   └── nginx/
│       └── nginx.conf
└── emergency-audio/
    └── fallback.mp3
```

## GitHub Workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| **Lint** | Push / PR to `main` | Runs component-aware checks: Ruff (Python), ESLint (TypeScript), hadolint (Dockerfiles), yamllint (YAML) |
| **TruffleHog Secret Scan** | Push / PR to `main` | Scans commit history for verified leaked secrets using TruffleHog's CLI flags |
| **Docker Build & Push** | Push / PR to `main`, tags `v*.*.*` | Builds the unified runtime image and publishes it to GHCR + Docker Hub |
| **AI Autolabel Issues** | Issue opened / edited / reopened | Applies `Type:`, `Scope:`, and `Priority:` labels via GitHub Models (GPT-4o-mini) |
| **Sync Status Labels** | Issue / PR labeled or unlabeled | Keeps `Status:` labels in sync between an issue and its connected PRs (issue → PR, one-way) |
| **Mirror Issue Labels to PRs** | PR opened / edited / synchronize; issue labeled / unlabeled | Copies all labels from a linked issue to its connected PRs (one-way, add-only). |

All repository workflows run on standard GitHub-hosted `ubuntu-24.04` runners; Docker image builds use official `docker/*` GitHub Actions.

### CI path-based triggering

To reduce CI time and avoid unnecessary jobs, pull request checks are scoped by changed paths.

- Documentation-only changes (`docs/**` or `**/*.md`) run only lightweight "docs-only" marker jobs and skip code/build jobs.
- Lint workflow mapping:
   - Python lint runs when `apps/status-api/**`, related Python requirements files, or `pyproject.toml` change.
   - TypeScript lint runs when `apps/dashboard/**` or its TypeScript, ESLint, Prettier, config, or lock files change.
   - Dockerfile lint runs when any `Dockerfile` or `docker-compose.yml` changes.
   - YAML lint runs when any `*.yml` or `*.yaml` changes, and validates all tracked YAML files in the repository.
- Docker Build & Push workflow mapping (PRs):
   - Builds the unified image when runtime paths change: `Dockerfile`, `docker-compose.yml`, `scripts/unified-entrypoint.sh`, `services/**`, `apps/status-api/**`, `infrastructure/nginx/**`, or the workflow itself.
- Pushes to `main` and release tags keep full coverage (no PR path filtering) for safety.

### SonarQube Cloud automatic analysis

This repository includes a `.sonarcloud.properties` file for SonarQube Cloud automatic analysis. It excludes the repository's bootstrap and host-administration shell scripts from analysis:

- `install.sh`
- `install-all.sh`
- `install-dev-deps.sh`
- `init-letsencrypt.sh`
- `setup-firewall.sh`

These scripts run in operator-controlled environments rather than the deployed application runtime, so excluding them keeps SonarQube Cloud focused on the services and app code that ship with the stack. If you need finer-grained rule suppression than file-level exclusions, configure that in the SonarQube Cloud project UI.

### Mirror Issue Labels — maintenance notes

- The workflow uses the `GITHUB_TOKEN` built-in secret — no extra secrets needed.
- It avoids automation loops by skipping events triggered by bot actors (login ending in `[bot]` or matching `copilot-*`).
- Cross-reference discovery is capped at 100 events per issue (GitHub GraphQL page-size limit). Issues with more than 100 linked PRs may not be fully synced in a single run.

## Secret Scanning

This repository uses [TruffleHog](https://trufflesecurity.com/open-source/trufflehog) to detect secrets and sensitive data leaks. Scanning runs automatically on every push and pull request to `main` via the **TruffleHog Secret Scan** workflow (see `.github/workflows/trufflehog.yml`).

The workflow reports only **verified** secrets and runs with a fixed concurrency of 4 to keep scans consistent.

### Run TruffleHog locally

Scan the full git history:

```bash
trufflehog git file://. --results=verified --concurrency=4
```

Scan only the current working tree (no history):

```bash
trufflehog filesystem . --results=verified --concurrency=4 --no-git
```

Install TruffleHog if you don't have it:

```bash
curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

See [SECURITY.md](SECURITY.md). Do not open public issues for security vulnerabilities.

## License

MIT — see [LICENSE](LICENSE).
