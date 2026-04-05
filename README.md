# Sonicverse — Radio Audio Streaming Stack

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/sonicverse-eu/audiostreaming-stack/actions/workflows/lint.yml/badge.svg)](https://github.com/sonicverse-eu/audiostreaming-stack/actions/workflows/lint.yml)
[![GHCR](https://img.shields.io/badge/Images-GHCR-blue?logo=github)](https://github.com/sonicverse-eu/audiostreaming-stack/pkgs/container/audiostreaming-stack%2Ficecast)
[![Join Sonicverse OSS Slack](https://img.shields.io/badge/Join-Sonicverse%20OSS%20Slack-4A154B?logo=slack&logoColor=white)](https://join.slack.com/t/sonicverse-oss/shared_invite/zt-3u969i5rr-cmfgEycFAi8V7Baj0uBx0A)

Self-hosted Docker Compose stack for live radio streaming. Ingest from any studio encoder, deliver via Icecast2 and HLS adaptive bitrate, with automatic fallback, silence detection, PostHog analytics, Pushover alerts, and a real-time operator dashboard.

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

### Option A — Pull pre-built images from GHCR (fastest)

```bash
git clone https://github.com/sonicverse-eu/audiostreaming-stack.git
cd audiostreaming-stack
./install.sh --use-prebuilt
```

### Option B — Build locally

```bash
git clone https://github.com/sonicverse-eu/audiostreaming-stack.git
cd audiostreaming-stack
./install.sh
```

The installer walks you through Docker checks, configuration, SSL setup, and launching the stack interactively.

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

## Install Development Dependencies From Root

Use the root installers when you only need local development dependencies (without running the full interactive stack installer):

```bash
./install-dev-deps.sh
```

Compatibility alias (same behavior): `./install-all.sh`

This installs:

- `status-dashboard` JavaScript dependencies (auto-detects `npm`, `yarn`, or `pnpm` lockfiles)
- `analytics` Python dependencies from `analytics/requirements.txt`
- `status-panel` Python dependencies from `status-panel/requirements.txt`

Optional flags:

- `./install-dev-deps.sh --ci` for deterministic CI-friendly installs when lockfiles exist
- `./install-dev-deps.sh --python-user` to install Python packages with `--user`
- `./install-dev-deps.sh --skip-node` or `./install-dev-deps.sh --skip-python` for partial installs

On Windows PowerShell:

```powershell
.\install-dev-deps.ps1
```

Compatibility alias (same behavior): `.\install-all.ps1`

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
cd status-dashboard
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
├── icecast/
│   ├── Dockerfile
│   └── icecast.xml
├── liquidsoap/
│   ├── Dockerfile
│   └── radio.liq
├── nginx/
│   ├── Dockerfile
│   └── nginx.conf
├── analytics/
│   ├── Dockerfile
│   ├── requirements.txt
│   └── tracker.py
├── status-panel/              ← API backend (Docker)
│   ├── Dockerfile
│   ├── requirements.txt
│   └── server.py
├── status-dashboard/          ← Next.js frontend (Appwrite Sites)
│   ├── app/
│   ├── components/
│   ├── lib/
│   └── package.json
└── emergency-audio/
    └── fallback.mp3
```

## GitHub Workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| **Lint** | Push / PR to `main` | Runs component-aware checks: Ruff (Python), ESLint (TypeScript), hadolint (Dockerfiles), yamllint (YAML) |
| **Docker Build & Push** | Push / PR to `main`, tags `v*.*.*` | Builds service images; on PRs, only changed services are built |
| **AI Autolabel Issues** | Issue opened / edited / reopened | Applies `Type:`, `Scope:`, and `Priority:` labels via GitHub Models (GPT-4o-mini) |
| **Sync Status Labels** | Issue / PR labeled or unlabeled | Keeps `Status:` labels in sync between an issue and its connected PRs (issue → PR, one-way) |
| **Mirror Issue Labels to PRs** | PR opened / edited / synchronize; issue labeled / unlabeled | Copies all labels from a linked issue to its connected PRs (one-way, add-only). |

### CI path-based triggering

To reduce CI time and avoid unnecessary jobs, pull request checks are scoped by changed paths.

- Documentation-only changes (`docs/**` or `**/*.md`) run only lightweight "docs-only" marker jobs and skip code/build jobs.
- Lint workflow mapping:
   - Python lint runs when `analytics/**`, `status-panel/**`, related Python requirements files, or `pyproject.toml` change.
   - TypeScript lint runs when `status-dashboard/**` or its TypeScript, ESLint, Prettier, config, or lock files change.
   - Dockerfile lint runs when any `Dockerfile` or `docker-compose.yml` changes.
   - YAML lint runs when any `*.yml` or `*.yaml` changes, and validates all tracked YAML files in the repository.
- Docker Build & Push workflow mapping (PRs):
   - Builds only the services whose directories changed: `icecast/**`, `liquidsoap/**`, `nginx/**`, `status-panel/**`, `analytics/**`.
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
