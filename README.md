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
| `/stream-mp3-192` | MP3 | 192 kbps | `https://<host>/listen/stream-mp3-192` |
| `/stream-mp3-320` | MP3 | 320 kbps | `https://<host>/listen/stream-mp3-320` |
| `/stream-aac-128` | AAC | 128 kbps | `https://<host>/listen/stream-aac-128` |
| `/stream-aac-192` | AAC | 192 kbps | `https://<host>/listen/stream-aac-192` |
| `/stream-ogg-128` | Ogg Vorbis | 128 kbps | `https://<host>/listen/stream-ogg-128` |
| `/stream-flac` | FLAC | Lossless | `https://<host>/listen/stream-flac` |

### HLS (for mobile)

```
https://<host>/hls/live.m3u8
```

Adaptive bitrate with 4 AAC quality tiers (48k, 96k, 128k, 256k) — players automatically select the best quality for the connection.

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

### Firewall

Open the following ports on your server:

| Port | Protocol | Purpose |
|---|---|---|
| 80 | TCP | HTTP (Let's Encrypt ACME + redirect to HTTPS) |
| 443 | TCP | HTTPS (listener streams + HLS + admin) |
| 8010 | TCP | Studio primary input (FLAC) |
| 8011 | TCP | Studio fallback input (Ogg) |

**Ubuntu/Debian (ufw):**
```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 8010/tcp
sudo ufw allow 8011/tcp
sudo ufw reload
```

**CentOS/RHEL (firewalld):**
```bash
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=8010/tcp
sudo firewall-cmd --permanent --add-port=8011/tcp
sudo firewall-cmd --reload
```

**iptables:**
```bash
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8010 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8011 -j ACCEPT
```

**Automated setup (UFW):**
```bash
# Open all required ports (unrestricted)
sudo ./setup-firewall.sh

# Recommended: restrict studio ports to your studio's IP
sudo ./setup-firewall.sh --studio-ip 203.0.113.50
```

The script ensures SSH access is preserved, opens the required ports, and optionally restricts studio source ports to a specific IP.

## Quick Start

### One-line install

```bash
git clone https://github.com/rikvisser-dev/audiostreaming-stack.git
cd audiostreaming-stack
./install.sh
```

The installer walks you through Docker checks, configuration, SSL setup, and launching the stack interactively.

### Manual setup

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
| `STATION_NAME` | Radio station name (used in stream metadata and alerts) |
| `STATION_LOCATION` | Station location (Icecast server info) |
| `STATION_ADMIN_EMAIL` | Admin contact email (Icecast server info) |
| `ICECAST_SOURCE_PASSWORD` | Password for Liquidsoap → Icecast connections |
| `ICECAST_ADMIN_PASSWORD` | Icecast admin panel password |
| `HARBOR_PASSWORD` | Password for studio → Liquidsoap connections |
| `ICECAST_HOSTNAME` | Public hostname for Icecast |
| `ICECAST_MAX_LISTENERS` | Maximum concurrent listeners |
| `LETSENCRYPT_EMAIL` | Email for Let's Encrypt notifications |
| `LETSENCRYPT_STAGING` | Set to `1` for test certificates |
| `PUSHOVER_USER_KEY` | Pushover user key for silence/failover alerts |
| `PUSHOVER_APP_TOKEN` | Pushover application token |
| `SILENCE_THRESHOLD_DB` | Silence detection threshold in dB (default: -40) |
| `SILENCE_DURATION` | Seconds of silence before alerting (default: 15) |
| `APPWRITE_ENDPOINT` | Appwrite API endpoint |
| `APPWRITE_PROJECT_ID` | Appwrite project ID |
| `APPWRITE_TEAM_ID` | Appwrite team ID (only members get panel access) |
| `STATUS_PANEL_CORS_ORIGIN` | Frontend URL for CORS (e.g. `https://status.breezeradio.nl`) |
| `POSTHOG_API_KEY` | PostHog project API key |
| `POSTHOG_HOST` | PostHog instance URL |
| `POSTHOG_POLL_INTERVAL` | Stats polling interval in seconds (default: 30) |

## Status Panel

Real-time broadcast engineer dashboard with Appwrite authentication. Only members of the configured Appwrite team can access the panel.

**Features:**
- Live listener counts and mount point status (5s refresh)
- Container health monitoring
- Stack configuration overview
- Recent alerts timeline
- Emergency audio upload/management
- Useful CLI commands (click to copy)
- Databases & storage overview

### Deployment on Appwrite Sites

The dashboard frontend is a static site deployed separately on Appwrite Sites:

1. In your Appwrite console, create a new Site
2. Point it to the `status-panel/static/` directory
3. Edit `status-panel/static/env.js` with your streaming server URL and Appwrite credentials
4. Deploy via Appwrite CLI or Git integration

The API backend runs in the Docker stack and is proxied through nginx at `/api/`.

## Analytics & Alerts

The analytics sidecar sends the following events to PostHog:

- `stream_listeners` — per-mount listener count (every poll)
- `stream_total_listeners` — aggregate listener count
- `stream_source_connected` / `stream_source_disconnected` — mount online/offline
- `stream_silence_detected` / `stream_silence_resolved` — dead air events

### Pushover Alerts

Liquidsoap monitors the audio stream for silence and triggers Pushover notifications:

| Alert | Priority | Trigger |
|---|---|---|
| Silence detected | High (siren) | Audio below -40 dB for 15 seconds |
| Audio resumed | Low | Audio returns after silence |
| Source disconnected | Normal | An Icecast mount goes offline |

Alerts have a 5-minute cooldown to prevent spam. Configure thresholds via `SILENCE_THRESHOLD_DB` and `SILENCE_DURATION` in `.env`.

## File Structure

```
├── docker-compose.yml
├── .env.example
├── install.sh
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
├── status-panel/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── server.py
│   └── static/           ← deploy this to Appwrite Sites
│       ├── index.html
│       ├── env.js
│       └── appwrite.json
├── setup-firewall.sh
└── emergency-audio/
    └── fallback.mp3
```
