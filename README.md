# Breeze Radio — Audio Streaming Stack

Docker Compose stack for live radio streaming using Liquidsoap and Icecast2.

## Architecture

```
Studio (BUTT/etc)
  ├── FLAC stream ──► :8010 ─┐
  └── Ogg stream  ──► :8011 ─┤
                              ▼
                      ┌─────────────┐
                      │  Liquidsoap  │──► HLS segments
                      │  (encoding + │
                      │   fallback)  │
                      └──────┬───────┘
                             │
                      ┌──────▼───────┐
                      │   Icecast2   │  4 mount points
                      └──────┬───────┘
                             │
                      ┌──────▼───────┐
                      │    Nginx     │  :80 (public)
                      │  HLS + proxy │
                      └──────────────┘
```

## Services

| Service | Description |
|---|---|
| **Icecast2** | Stream distribution server with multiple mount points |
| **Liquidsoap** | Stream processor — ingest, fallback chain, encoding |
| **Nginx** | Public-facing reverse proxy + HLS segment serving |
| **Analytics** | Polls Icecast stats and sends events to PostHog |

## Stream Inputs (Studio → Liquidsoap)

| Input | Port | Protocol | Format |
|---|---|---|---|
| Primary | 8010 | Icecast source | FLAC (lossless) |
| Fallback | 8011 | Icecast source | Ogg Vorbis |
| Emergency | — | Local file | `emergency-audio/fallback.mp3` |

Fallback chain: Primary → Fallback → Emergency file (automatic, no manual intervention needed).

## Stream Outputs (Listener Endpoints)

### Icecast (via Nginx reverse proxy)

| Mount | Format | Bitrate | URL |
|---|---|---|---|
| `/stream-mp3-128` | MP3 | 128 kbps | `https://<host>/listen/stream-mp3-128` |
| `/stream-mp3-320` | MP3 | 320 kbps | `https://<host>/listen/stream-mp3-320` |
| `/stream-aac-128` | AAC | 128 kbps | `https://<host>/listen/stream-aac-128` |
| `/stream-ogg-128` | Ogg Vorbis | 128 kbps | `https://<host>/listen/stream-ogg-128` |

### HLS (for mobile)

```
https://<host>/hls/live.m3u8
```

Adaptive with AAC 128k and MP3 128k variants.

## Prerequisites

### Install Docker

**Ubuntu/Debian:**
```bash
# Install Docker Engine
curl -fsSL https://get.docker.com | sh

# Add your user to the docker group (log out and back in after)
sudo usermod -aG docker $USER

# Verify installation
docker --version
docker compose version
```

**macOS:**
```bash
# Install Docker Desktop via Homebrew
brew install --cask docker

# Or download from https://www.docker.com/products/docker-desktop/
```

**Windows:**

Download and install [Docker Desktop](https://www.docker.com/products/docker-desktop/) — requires WSL 2.

## Quick Start

1. **Clone and configure**
   ```bash
   git clone https://github.com/rikvisser-dev/audiostreaming-stack.git
   cd audiostreaming-stack
   cp .env.example .env
   # Edit .env with your passwords and PostHog API key
   ```

2. **Add emergency audio**
   ```bash
   # Place a fallback audio file (loops when both live sources are down)
   cp /path/to/your/fallback.mp3 emergency-audio/fallback.mp3
   ```

3. **Obtain SSL certificate**
   ```bash
   # First run only — obtains Let's Encrypt certificate
   ./init-letsencrypt.sh
   ```

4. **Start the stack**
   ```bash
   docker compose up -d
   ```

5. **Connect your studio encoder**

   Configure BUTT (or similar) to send:
   - **Primary stream**: Host `<server-ip>`, Port `8010`, Mount `/primary`, Password from `.env`
   - **Fallback stream**: Host `<server-ip>`, Port `8011`, Mount `/secondary`, Password from `.env`

6. **Verify**
   - Icecast admin: `http://<host>/icecast-admin/`
   - Test stream: `http://<host>/listen/stream-mp3-128` in VLC
   - HLS: `http://<host>/hls/live.m3u8` in Safari/VLC

## Configuration

All secrets and settings are managed via `.env`:

| Variable | Description |
|---|---|
| `ICECAST_SOURCE_PASSWORD` | Password for Liquidsoap → Icecast connections |
| `ICECAST_ADMIN_PASSWORD` | Icecast admin panel password |
| `HARBOR_PASSWORD` | Password for studio → Liquidsoap connections |
| `ICECAST_HOSTNAME` | Public hostname for Icecast |
| `ICECAST_MAX_LISTENERS` | Maximum concurrent listeners |
| `LETSENCRYPT_EMAIL` | Email for Let's Encrypt notifications |
| `LETSENCRYPT_STAGING` | Set to `1` for test certificates |
| `POSTHOG_API_KEY` | PostHog project API key |
| `POSTHOG_HOST` | PostHog instance URL |
| `POSTHOG_POLL_INTERVAL` | Stats polling interval in seconds (default: 30) |

## Analytics

The analytics sidecar sends the following events to PostHog:

- `stream_listeners` — per-mount listener count (every poll)
- `stream_total_listeners` — aggregate listener count
- `stream_source_connected` — mount comes online
- `stream_source_disconnected` — mount goes offline

## File Structure

```
├── docker-compose.yml
├── .env.example
├── init-letsencrypt.sh
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
└── emergency-audio/
    └── fallback.mp3
```
