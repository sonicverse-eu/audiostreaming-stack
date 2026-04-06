# Sonicverse — Radio Audio Streaming Stack

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/sonicverse-eu/audiostreaming-stack/actions/workflows/lint.yml/badge.svg)](https://github.com/sonicverse-eu/audiostreaming-stack/actions/workflows/lint.yml)
[![GHCR](https://img.shields.io/badge/Images-GHCR-blue?logo=github)](https://github.com/sonicverse-eu/audiostreaming-stack/pkgs/container/audiostreaming-stack%2Ficecast)
[![Docker Hub](https://img.shields.io/badge/Images-Docker%20Hub-2496ED?logo=docker&logoColor=white)](https://hub.docker.com/u/sonicverse)
[![Join Sonicverse OSS Slack](https://img.shields.io/badge/Join-Sonicverse%20OSS%20Slack-4A154B?logo=slack&logoColor=white)](https://join.slack.com/t/sonicverse-oss/shared_invite/zt-3u969i5rr-cmfgEycFAi8V7Baj0uBx0A)

Self-hosted Docker Compose stack for live radio streaming. Ingest from any studio encoder, deliver via Icecast2 and HLS adaptive bitrate, with automatic fallback, silence detection, PostHog analytics, Pushover alerts, and a real-time operator dashboard.

## Documentation

For setup, operations, and troubleshooting, use the official Sonicverse docs as the single source of truth:

**https://docs.sonicverse.eu**

This repository README is a quick project overview. If local instructions differ from the external docs, follow docs.sonicverse.eu.

Contributing to this project means following the [Code of Conduct](CODE_OF_CONDUCT.md).

Join the Sonicverse OSS Slack for community support, implementation questions, and contributor collaboration.

## Architecture

```
Studio (BUTT/etc)
   ├── MP3 320k stream ──► :8010 ─┐
   └── MP3 192k stream ──► :8011 ─┤
                              ▼
                      ┌─────────────┐
                      │  Liquidsoap  │──► HLS segments
                      │  (encoding + │
                      │   fallback)  │
                      └──────┬───────┘
                             │
                      ┌──────▼───────┐
                      │   Icecast2   │  6 mount points
                      └──────┬───────┘
                             │
                      ┌──────▼───────┐
                      │    Nginx     │  :80 / :443
                      │  HLS + proxy │
                      └──────────────┘
```

## Services

| Service | Description |
|---|---|
| **Icecast2** | Stream distribution server with multiple mount points |
| **Liquidsoap** | Stream processor — ingest, fallback chain, encoding, HLS |
| **Nginx** | Public-facing reverse proxy + HLS segment serving |
| **Status Panel** | Flask API backend — stream health, container status, emergency audio management |
| **Analytics** | Polls Icecast stats and sends events to PostHog + Pushover alerts |
| **Certbot** | Automatic Let's Encrypt certificate renewal |

## Repository Structure

- `.github/` contains repository automation and project metadata, including issue templates and GitHub Actions workflows.
- `.vscode/` contains editor settings and recommended workspace configuration for contributors using VS Code.
- `apps/` contains operator-facing applications: the Next.js dashboard in `apps/dashboard/` and the Flask status API in `apps/status-api/`.
- `services/` contains deployable runtime services, grouped by domain: streaming services in `services/streaming/` and telemetry in `services/analytics/`.
- `infrastructure/` contains edge and routing infrastructure definitions, currently the Nginx reverse proxy in `infrastructure/nginx/`.
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
- Python / pip (analytics & API already built into image)

**Time:** ~2–5 minutes (mostly downloading ~500MB of container images)

### Container registries

Pre-built service images are published to both registries:

- **Primary (default): Docker Hub** under `sonicverse`.
- **Mirror:** GHCR under `ghcr.io/sonicverse-eu/audiostreaming-stack`.

The Build & Push Docker Images workflow verifies cross-registry parity per expected runtime platform
for `linux/amd64`, `linux/arm64`, and configured `linux/386` targets.
The check fails when a required platform is missing in either registry or when per-platform digests differ.

Docker Hub image names:

- `docker.io/sonicverse/audiostreaming-stack-icecast:latest`
- `docker.io/sonicverse/audiostreaming-stack-liquidsoap:latest`
- `docker.io/sonicverse/audiostreaming-stack-nginx:latest`
- `docker.io/sonicverse/audiostreaming-stack-status-api:latest`
- `docker.io/sonicverse/audiostreaming-stack-analytics:latest`

GHCR mirror names:

- `ghcr.io/sonicverse-eu/audiostreaming-stack/icecast:latest`
- `ghcr.io/sonicverse-eu/audiostreaming-stack/liquidsoap:latest`
- `ghcr.io/sonicverse-eu/audiostreaming-stack/nginx:latest`
- `ghcr.io/sonicverse-eu/audiostreaming-stack/status-api:latest`
- `ghcr.io/sonicverse-eu/audiostreaming-stack/analytics:latest`

### 📦 Full development environment

If you plan to modify the dashboard, analytics, or API:

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
- Python dependencies (analytics & API development)

**Time:** ~5–10 minutes depending on your network and system

### 🔨 Build containers locally (advanced)

Build container images locally instead of pulling pre-built images — use this if you need to modify Dockerfile or container code:

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

**Time:** ~15–30 minutes (building ~3 container images locally)

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
   - Icecast admin: `http://<host>/icecast-admin/`
   - Test stream: `http://<host>/listen/stream-mp3-128` in VLC
   - HLS: `http://<host>/hls/live.m3u8` in Safari/VLC

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
- **Python** dependencies for analytics and status API (`services/analytics/`, `apps/status-api/`)

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
| `STATION_NAME` | Station name (used in stream metadata and alerts) |
| `STATION_LOCATION` | Station location (Icecast server info) |
| `STATION_ADMIN_EMAIL` | Admin contact email |
| `ICECAST_SOURCE_PASSWORD` | Password for Liquidsoap → Icecast connections |
| `ICECAST_ADMIN_PASSWORD` | Icecast admin panel password |
| `HARBOR_PASSWORD` | Password for studio → Liquidsoap connections |
| `ICECAST_HOSTNAME` | Public hostname |
| `ICECAST_MAX_LISTENERS` | Maximum concurrent listeners |
| `LETSENCRYPT_EMAIL` | Email for Let's Encrypt notifications |
| `LETSENCRYPT_STAGING` | Set to `1` for test certificates |
| `PUSHOVER_USER_KEY` | Pushover user key for silence/failover alerts |
| `PUSHOVER_APP_TOKEN` | Pushover application token |
| `SILENCE_THRESHOLD_DB` | Silence detection threshold in dB (default: `-40`) |
| `SILENCE_DURATION` | Seconds of silence before alerting (default: `15`) |
| `APPWRITE_ENDPOINT` | Appwrite API endpoint |
| `APPWRITE_PROJECT_ID` | Appwrite project ID |
| `APPWRITE_TEAM_ID` | Appwrite team ID (only members get panel access) |
| `STATUS_PANEL_CORS_ORIGIN` | Status dashboard URL(s) for CORS, comma-separated (e.g. `https://status.example.com`) |
| `STATUS_PANEL_WRITE_ROLES` | Appwrite team roles allowed to manage emergency audio (default: `owner,admin`) |
| `STATUS_PANEL_ALLOW_RISKY_COMMANDS` | Enable remote restart/SSL renewal commands (`0` by default) |
| `POSTHOG_API_KEY` | PostHog project API key |
| `POSTHOG_HOST` | PostHog instance URL |
| `POSTHOG_POLL_INTERVAL` | Stats polling interval in seconds (default: `30`) |

## Status Panel

Real-time broadcast engineer dashboard with Appwrite team-based authentication.

**Features:**
- Live listener counts and mount point status (5s refresh)
- Container health monitoring
- Stack configuration overview
- Recent alerts timeline
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

The API backend runs in the Docker stack and is proxied through nginx at `/api/`.

## Analytics & Alerts

The analytics service sends the following events to PostHog:

- `stream_listeners` — per-mount listener count (every poll)
- `stream_total_listeners` — aggregate listener count
- `stream_source_connected` / `stream_source_disconnected` — mount online/offline
- `stream_silence_detected` / `stream_silence_resolved` — dead air events

### Pushover Alerts

| Alert | Priority | Trigger |
|---|---|---|
| Silence detected | High (siren) | Audio below threshold for configured duration |
| Audio resumed | Low | Audio returns after silence |
| Stream outage | High (siren) | One or more Icecast outputs disconnect |
| Primary harbor down | High (siren) | Primary studio input disconnects |
| Secondary harbor down | High / Critical | Secondary disconnects; escalates when primary is also down |

Alerts have a 5-minute cooldown to prevent spam.

## File Structure

```
├── docker-compose.yml
├── .env.example
├── install-dev-deps.sh
├── install-dev-deps.ps1
├── install-all.sh
├── install-all.ps1
├── install.sh
├── init-letsencrypt.sh
├── setup-firewall.sh
├── apps/
│   ├── status-api/            ← API backend (Docker)
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   └── server.py
│   └── dashboard/             ← Next.js frontend (Appwrite Sites)
│       ├── app/
│       ├── components/
│       ├── lib/
│       └── package.json
├── services/
│   ├── analytics/
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   └── tracker.py
│   └── streaming/
│       ├── icecast/
│       │   ├── Dockerfile
│       │   └── icecast.xml
│       └── liquidsoap/
│           ├── Dockerfile
│           └── radio.liq
├── infrastructure/
│   └── nginx/
│       ├── Dockerfile
│       └── nginx.conf
└── emergency-audio/
    └── fallback.mp3
```

## GitHub Workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| **Lint** | Push / PR to `main` | Runs component-aware checks: Ruff (Python), ESLint (TypeScript), hadolint (Dockerfiles), yamllint (YAML) |
| **Docker Build & Push** | Push / PR to `main`, tags `v*.*.*` | Builds service images and publishes to GHCR + Docker Hub; on PRs, only changed services are built |
| **AI Autolabel Issues** | Issue opened / edited / reopened | Applies `Type:`, `Scope:`, and `Priority:` labels via GitHub Models (GPT-4o-mini) |
| **Sync Status Labels** | Issue / PR labeled or unlabeled | Keeps `Status:` labels in sync between an issue and its connected PRs (issue → PR, one-way) |
| **Mirror Issue Labels to PRs** | PR opened / edited / synchronize; issue labeled / unlabeled | Copies all labels from a linked issue to its connected PRs (one-way, add-only). |

The Docker Build & Push workflow verifies that GHCR and Docker Hub both expose the expected runtime platforms for each service before it compares digests.

### CI path-based triggering

To reduce CI time and avoid unnecessary jobs, pull request checks are scoped by changed paths.

- Documentation-only changes (`docs/**` or `**/*.md`) run only lightweight "docs-only" marker jobs and skip code/build jobs.
- Lint workflow mapping:
   - Python lint runs when `services/analytics/**`, `apps/status-api/**`, related Python requirements files, or `pyproject.toml` change.
   - TypeScript lint runs when `apps/dashboard/**` or its TypeScript, ESLint, Prettier, config, or lock files change.
   - Dockerfile lint runs when any `Dockerfile` or `docker-compose.yml` changes.
   - YAML lint runs when any `*.yml` or `*.yaml` changes, and validates all tracked YAML files in the repository.
- Docker Build & Push workflow mapping (PRs):
   - Builds only the services whose directories changed: `services/streaming/icecast/**`, `services/streaming/liquidsoap/**`, `infrastructure/nginx/**`, `apps/status-api/**`, `services/analytics/**`.
   - Builds all services when `docker-compose.yml` changes.
- Pushes to `main` and release tags keep full coverage (no PR path filtering) for safety.

### Mirror Issue Labels — maintenance notes

- The workflow uses the `GITHUB_TOKEN` built-in secret — no extra secrets needed.
- It avoids automation loops by skipping events triggered by bot actors (login ending in `[bot]` or matching `copilot-*`).
- Cross-reference discovery is capped at 100 events per issue (GitHub GraphQL page-size limit). Issues with more than 100 linked PRs may not be fully synced in a single run.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

See [SECURITY.md](SECURITY.md). Do not open public issues for security vulnerabilities.

## License

MIT — see [LICENSE](LICENSE).
