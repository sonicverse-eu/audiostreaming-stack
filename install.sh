#!/bin/bash

# ============================================================
# Sonicverse — Radio Audio Streaming Stack Installer
# Remote-safe installation script compatible with curl piping
# ============================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================
# Remote Execution Detection & Setup
# ============================================================
# If being run via 'curl | bash' (stdin is not a terminal),
# clone the repository first and recursively call the cloned script.
read -t 0 _ 2>/dev/null && STDIN_AVAILABLE=true || STDIN_AVAILABLE=false

if [ "$STDIN_AVAILABLE" = "true" ] || [ -f "docker-compose.yml" ]; then
    # stdin is available (interactive) OR we're already in the repo directory
    RUNNING_LOCALLY=true
    WORK_DIR="$(pwd)"
else
    # stdin is piped (from curl), and not in repo directory
    RUNNING_LOCALLY=false
    
    # Define minimal info/error for remote setup
    _info() { echo -e "  ${BLUE}ℹ${NC}  $1"; }
    _error() { echo -e "  ${RED}✗${NC}  $1"; }
    
    # Create a temporary directory for the clone
    WORK_DIR="/tmp/audiostreaming-stack-$(date +%s)"
    mkdir -p "$WORK_DIR"
    
    _info "Cloning audiostreaming-stack to $WORK_DIR"
    
    # Clone the repository with shallow clone for speed
    if ! git clone --depth 1 https://github.com/sonicverse-eu/audiostreaming-stack.git "$WORK_DIR" 2>/dev/null; then
        _error "Failed to clone repository. Ensure git is installed and you have internet connectivity."
        exit 1
    fi
    
    _info "Starting installer from cloned repository..."
    
    # Execute the script from within the cloned directory
    cd "$WORK_DIR"
    bash ./install.sh "$@"
    exit $?
fi

print_banner() {
    echo ""
    echo -e "${CYAN}${BOLD}"
    echo "  ╔════════════════════════════════════════════════╗"
    echo "  ║   Sonicverse — Radio Audio Streaming Stack     ║"
    echo "  ║   Liquidsoap + Icecast2 + HLS + PostHog        ║"
    echo "  ╚════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_mode_info() {
    local mode="$1"
    if [ "$mode" = "dev" ]; then
        echo -e "  ${BLUE}ℹ${NC}  Development mode enabled — installing Node/Python dependencies"
    elif [ "$mode" = "local" ]; then
        echo -e "  ${BLUE}ℹ${NC}  Local build mode enabled — building containers locally"
    else
        echo -e "  ${BLUE}ℹ${NC}  Minimal Docker Hub deployment (default) — using pre-built images"
    fi
    echo ""
}

info()    { echo -e "  ${BLUE}ℹ${NC}  $1"; }
success() { echo -e "  ${GREEN}✓${NC}  $1"; }
warn()    { echo -e "  ${YELLOW}!${NC}  $1"; }
error()   { echo -e "  ${RED}✗${NC}  $1"; }
step()    { echo -e "\n${BOLD}[$1/$TOTAL_STEPS] $2${NC}"; }

prompt() {
    local var_name="$1" prompt_text="$2" default="$3"
    if [ -n "$default" ]; then
        read -rp "  → $prompt_text [$default]: " value
        eval "$var_name=\"${value:-$default}\""
    else
        read -rp "  → $prompt_text: " value
        eval "$var_name=\"$value\""
    fi
}

prompt_secret() {
    local var_name="$1" prompt_text="$2"
    read -rsp "  → $prompt_text: " value
    echo ""
    eval "$var_name=\"$value\""
}

generate_password() {
    openssl rand -base64 16 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c 20 || \
    cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | head -c 20
}

usage() {
    cat <<'EOF'
Sonicverse Radio Streaming Stack Installer

Usage:
  ./install.sh [OPTIONS]

Options:
  --dev              Install Node/Python dependencies for local development.
                     Required for: building dashboard, running analytics/API locally.
                                         Skip this if using Docker Hub pre-built images (recommended for deployment).
    --build-local      Build container images locally instead of pulling from Docker Hub.
                     Use this if you need to modify Dockerfile or container code.
  -h, --help         Show this help message.

Deployment scenarios:
    Minimal Docker Hub deployment (easiest, default):
    $ ./install.sh

  Full development environment:
    $ ./install.sh --dev

  Build containers locally (advanced):
    $ ./install.sh --build-local

EOF
}

TOTAL_STEPS=6

# Parse flags
USE_PREBUILT=true
DEV_MODE=false
for arg in "$@"; do
    case "$arg" in
        --build-local) USE_PREBUILT=false ;;
        --dev) DEV_MODE=true ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "Error: Unknown option '$arg'" >&2
            echo "Use --help for usage information." >&2
            exit 1
            ;;
    esac
done

# Adjust total steps based on whether we're installing dev dependencies
TOTAL_STEPS=6
if [ "$DEV_MODE" = "true" ]; then
    TOTAL_STEPS=7
fi

# ============================================================

print_banner

if [ "$DEV_MODE" = "true" ]; then
    print_mode_info "dev"
elif [ "$USE_PREBUILT" = "false" ]; then
    print_mode_info "local"
else
    print_mode_info "ghcr"
fi

# ----------------------------------------------------------
# Detect existing installation
# ----------------------------------------------------------
EXISTING_STACK=false
if docker compose ps --quiet 2>/dev/null | head -1 | grep -q .; then
    EXISTING_STACK=true
    echo ""
    warn "Existing streaming stack detected!"
    echo ""
    echo "  Choose an action:"
    echo "    1) Update — rebuild and restart containers (keeps .env and data)"
    echo "    2) Clean reinstall — stop, remove containers/images, reconfigure"
    echo "    3) Cancel"
    echo ""
    read -rp "  → Choice [1/2/3]: " update_choice

    case "$update_choice" in
        1)
            info "Updating stack..."
            echo ""
            info "Pulling latest changes..."
            git pull 2>/dev/null || true
            echo ""
            info "Pulling fresh images (bypassing cache)..."
            docker compose pull --no-parallel || true
            echo ""
            info "Rebuilding any local images..."
            docker compose build
            echo ""
            info "Restarting with updated images..."
            docker compose down
            docker compose up -d
            echo ""
            success "Stack updated successfully!"
            echo ""
            docker compose ps
            echo ""
            exit 0
            ;;
        2)
            info "Stopping and removing existing stack..."
            docker compose down --rmi local --remove-orphans
            docker volume rm audiostreaming-stack_hls-data audiostreaming-stack_icecast-logs 2>/dev/null || true
            success "Old stack removed"
            echo ""
            info "Continuing with fresh install..."
            ;;
        3)
            info "Cancelled."
            exit 0
            ;;
        *)
            error "Invalid choice."
            exit 1
            ;;
    esac
elif docker compose ps -a --quiet 2>/dev/null | head -1 | grep -q .; then
    warn "Stopped containers from a previous install detected."
    read -rp "  → Remove them before continuing? (Y/n): " remove_old
    if [[ ! "$remove_old" =~ ^[Nn]$ ]]; then
        docker compose down --rmi local --remove-orphans
        success "Old containers removed"
    fi
fi

# ----------------------------------------------------------
# Step 1: Check prerequisites
# ----------------------------------------------------------
step 1 "Checking prerequisites"

# Check Docker
if command -v docker &>/dev/null; then
    DOCKER_VERSION=$(docker --version | head -1)
    success "Docker found: $DOCKER_VERSION"
else
    warn "Docker is not installed."
    echo ""

    OS="$(uname -s)"
    case "$OS" in
        Linux)
            read -rp "  → Install Docker now? (y/N): " install_docker
            if [[ "$install_docker" =~ ^[Yy]$ ]]; then
                info "Installing Docker via get.docker.com..."
                curl -fsSL https://get.docker.com | sh
                sudo usermod -aG docker "$USER" 2>/dev/null || true
                success "Docker installed. You may need to log out and back in for group changes."
            else
                error "Docker is required. Install it and re-run this script."
                exit 1
            fi
            ;;
        Darwin)
            if command -v brew &>/dev/null; then
                read -rp "  → Install Docker Desktop via Homebrew? (y/N): " install_docker
                if [[ "$install_docker" =~ ^[Yy]$ ]]; then
                    brew install --cask docker
                    info "Open Docker Desktop from Applications to complete setup, then re-run this script."
                    exit 0
                fi
            fi
            error "Docker is required. Install Docker Desktop from https://docker.com/products/docker-desktop/"
            exit 1
            ;;
        *)
            error "Docker is required. Install it from https://docs.docker.com/get-docker/"
            exit 1
            ;;
    esac
fi

# Check Docker Compose
if docker compose version &>/dev/null; then
    success "Docker Compose found: $(docker compose version --short 2>/dev/null || echo 'available')"
else
    error "Docker Compose (v2) is required but not found."
    error "It should be included with Docker Desktop or docker-ce-cli."
    exit 1
fi

# Check Docker daemon
if docker info &>/dev/null; then
    success "Docker daemon is running"
else
    error "Docker daemon is not running. Start Docker and re-run this script."
    exit 1
fi

# ----------------------------------------------------------
# Step 2: Configure environment
# ----------------------------------------------------------
step 2 "Configuring environment"

if [ -f .env ]; then
    warn ".env file already exists."
    read -rp "  → Overwrite with fresh configuration? (y/N): " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
        info "Keeping existing .env"
        SKIP_ENV=true
    fi
fi

if [ "${SKIP_ENV}" != "true" ]; then
    echo ""
    info "Let's configure your streaming stack."
    echo ""

    # Station identity
    prompt STATION_NAME        "Station name" "My Radio Station"
    prompt STATION_LOCATION    "Station location" "Netherlands"
    prompt STATION_ADMIN_EMAIL "Station admin email" "admin@example.com"

    # Hostname
    echo ""
    prompt ICECAST_HOSTNAME "Public hostname" "stream.example.com"

    # Generate secure passwords
    echo ""
    info "Generating secure passwords (press Enter to accept, or type your own)..."
    DEFAULT_SOURCE_PASS=$(generate_password)
    DEFAULT_ADMIN_PASS=$(generate_password)
    DEFAULT_HARBOR_PASS=$(generate_password)

    prompt ICECAST_SOURCE_PASSWORD "Icecast source password" "$DEFAULT_SOURCE_PASS"
    prompt ICECAST_ADMIN_PASSWORD  "Icecast admin password"  "$DEFAULT_ADMIN_PASS"
    prompt HARBOR_PASSWORD         "Studio harbor password"   "$DEFAULT_HARBOR_PASS"
    prompt ICECAST_ADMIN_USER      "Icecast admin username"   "admin"
    prompt ICECAST_MAX_LISTENERS   "Max concurrent listeners" "500"

    # Let's Encrypt
    echo ""
    prompt LETSENCRYPT_EMAIL "Let's Encrypt email" "admin@example.com"
    read -rp "  → Use Let's Encrypt staging (test certs)? (y/N): " use_staging
    LETSENCRYPT_STAGING=0
    if [[ "$use_staging" =~ ^[Yy]$ ]]; then
        LETSENCRYPT_STAGING=1
    fi

    # Pushover alerts
    echo ""
    prompt PUSHOVER_USER_KEY  "Pushover user key (leave empty to skip alerts)" ""
    prompt PUSHOVER_APP_TOKEN "Pushover app token" ""

    # Appwrite (status panel auth)
    echo ""
    prompt APPWRITE_ENDPOINT   "Appwrite endpoint" "https://cloud.appwrite.io/v1"
    prompt APPWRITE_PROJECT_ID "Appwrite project ID" ""
    prompt APPWRITE_TEAM_ID    "Appwrite team ID (members get panel access)" ""
    prompt STATUS_PANEL_CORS_ORIGIN "Status panel frontend URL(s) for CORS" "https://status.example.com"
    prompt STATUS_PANEL_WRITE_ROLES "Operator roles for writes (comma-separated)" "owner,admin"
    prompt STATUS_PANEL_ALLOW_RISKY_COMMANDS "Allow destructive panel commands? (0/1)" "0"

    # PostHog
    echo ""
    prompt POSTHOG_API_KEY  "PostHog API key (leave empty to skip analytics)" ""
    prompt POSTHOG_HOST     "PostHog host" "https://posthog.sonicverse.eu"
    prompt POSTHOG_POLL_INTERVAL "Analytics poll interval (seconds)" "30"

    # Ports
    echo ""
    prompt HARBOR_PRIMARY_PORT  "Studio primary port (FLAC)" "8010"
    prompt HARBOR_FALLBACK_PORT "Studio fallback port (Ogg)"  "8011"

    # Write .env
    cat > .env <<ENVFILE
# Station
STATION_NAME=${STATION_NAME}
STATION_LOCATION=${STATION_LOCATION}
STATION_ADMIN_EMAIL=${STATION_ADMIN_EMAIL}

# Icecast
ICECAST_SOURCE_PASSWORD=${ICECAST_SOURCE_PASSWORD}
ICECAST_RELAY_PASSWORD=$(generate_password)
ICECAST_ADMIN_USER=${ICECAST_ADMIN_USER}
ICECAST_ADMIN_PASSWORD=${ICECAST_ADMIN_PASSWORD}
ICECAST_HOSTNAME=${ICECAST_HOSTNAME}
ICECAST_MAX_LISTENERS=${ICECAST_MAX_LISTENERS}

# Liquidsoap harbor (studio → liquidsoap)
HARBOR_PRIMARY_PORT=${HARBOR_PRIMARY_PORT}
HARBOR_FALLBACK_PORT=${HARBOR_FALLBACK_PORT}
HARBOR_PASSWORD=${HARBOR_PASSWORD}

# Let's Encrypt
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
LETSENCRYPT_STAGING=${LETSENCRYPT_STAGING}

# Pushover alerts
PUSHOVER_USER_KEY=${PUSHOVER_USER_KEY}
PUSHOVER_APP_TOKEN=${PUSHOVER_APP_TOKEN}
SILENCE_THRESHOLD_DB=-40
SILENCE_DURATION=15

# Appwrite (status panel auth)
APPWRITE_ENDPOINT=${APPWRITE_ENDPOINT}
APPWRITE_PROJECT_ID=${APPWRITE_PROJECT_ID}
APPWRITE_TEAM_ID=${APPWRITE_TEAM_ID}
STATUS_PANEL_CORS_ORIGIN=${STATUS_PANEL_CORS_ORIGIN}
STATUS_PANEL_WRITE_ROLES=${STATUS_PANEL_WRITE_ROLES}
STATUS_PANEL_ALLOW_RISKY_COMMANDS=${STATUS_PANEL_ALLOW_RISKY_COMMANDS}

# PostHog
POSTHOG_API_KEY=${POSTHOG_API_KEY}
POSTHOG_HOST=${POSTHOG_HOST}
POSTHOG_POLL_INTERVAL=${POSTHOG_POLL_INTERVAL}
ENVFILE

    success ".env file created"
fi

# ----------------------------------------------------------
# Step 3: Install development dependencies (optional)
# ----------------------------------------------------------
STEP_NUM=3
if [ "$DEV_MODE" = "true" ]; then
    step "$STEP_NUM" "Installing development dependencies"
    echo ""
    info "Installing Node.js and Python dependencies..."
    echo ""
    if [ -f "install-all.sh" ]; then
        bash ./install-all.sh
        success "Development dependencies installed"
    else
        error "install-all.sh not found"
        exit 1
    fi
    STEP_NUM=$((STEP_NUM + 1))
else
    info "Skipping development dependencies (use --dev to install)"
fi

# ----------------------------------------------------------
# Step $STEP_NUM: Emergency fallback audio
# ----------------------------------------------------------
step "$STEP_NUM" "Emergency fallback audio"

if ls emergency-audio/*.mp3 emergency-audio/*.flac emergency-audio/*.wav 2>/dev/null | head -1 &>/dev/null; then
    success "Fallback audio found in emergency-audio/"
else
    warn "No fallback audio file found in emergency-audio/"
    echo ""
    read -rp "  → Path to fallback audio file (or press Enter to skip): " fallback_path
    if [ -n "$fallback_path" ] && [ -f "$fallback_path" ]; then
        cp "$fallback_path" emergency-audio/fallback.mp3
        success "Copied to emergency-audio/fallback.mp3"
    else
        warn "Skipped. Add a file to emergency-audio/ before going live."
    fi
fi

# Increment to next step
STEP_NUM=$((STEP_NUM + 1))

# ----------------------------------------------------------
# Step $STEP_NUM: Build containers
# ----------------------------------------------------------
step "$STEP_NUM" "Building containers"

if [ "$USE_PREBUILT" = "true" ]; then
    info "Pulling pre-built images from Docker Hub or configured registry (no cache)..."
    echo ""
    docker compose pull --no-parallel || { error "Pull failed. Images may not exist yet. Run with --build-local to build locally instead."; exit 1; }
    echo ""
    success "All images pulled (fresh, no cache)"
else
    info "Building containers locally. This may take a few minutes on first run..."
    echo ""
    docker compose build
    echo ""
    success "All containers built successfully"
fi

# Increment to next step
STEP_NUM=$((STEP_NUM + 1))

# ----------------------------------------------------------
# Step $STEP_NUM: SSL certificate
# ----------------------------------------------------------
step "$STEP_NUM" "SSL certificate"

# Source .env for hostname
source .env 2>/dev/null || true

# Check for stale/invalid cert (e.g. from a failed previous run)
if [ -f "certbot/conf/live/${ICECAST_HOSTNAME}/fullchain.pem" ]; then
    CERT_SIZE=$(wc -c < "certbot/conf/live/${ICECAST_HOSTNAME}/fullchain.pem" 2>/dev/null || echo 0)
    if [ "$CERT_SIZE" -lt 1500 ]; then
        warn "Found a possibly invalid/stale certificate (${CERT_SIZE} bytes). Removing it..."
        rm -rf "certbot/conf/live/${ICECAST_HOSTNAME}"
        rm -rf "certbot/conf/archive/${ICECAST_HOSTNAME}"
        rm -f  "certbot/conf/renewal/${ICECAST_HOSTNAME}.conf"
        success "Stale certificate removed"
    fi
fi

if [ -f "certbot/conf/live/${ICECAST_HOSTNAME}/fullchain.pem" ]; then
    success "SSL certificate already exists for ${ICECAST_HOSTNAME}"
else
    echo ""
    read -rp "  → Obtain Let's Encrypt SSL certificate now? (Y/n): " get_cert
    if [[ ! "$get_cert" =~ ^[Nn]$ ]]; then
        info "Make sure DNS for ${ICECAST_HOSTNAME} points to this server!"
        read -rp "  → DNS is configured and ready? (y/N): " dns_ready
        if [[ "$dns_ready" =~ ^[Yy]$ ]]; then
            bash ./init-letsencrypt.sh
            success "SSL certificate obtained"
        else
            warn "Skipped. Run ./init-letsencrypt.sh when DNS is ready."
        fi
    else
        warn "Skipped. Run ./init-letsencrypt.sh before going live."
    fi
fi

# Increment to next step
STEP_NUM=$((STEP_NUM + 1))

# ----------------------------------------------------------
# Step $STEP_NUM: Launch
# ----------------------------------------------------------
step "$STEP_NUM" "Launch"

echo ""
read -rp "  → Start the streaming stack now? (Y/n): " start_now
if [[ ! "$start_now" =~ ^[Nn]$ ]]; then
    docker compose up -d
    echo ""
    success "Streaming stack is running!"
else
    info "Start later with: docker compose up -d"
fi

# ----------------------------------------------------------
# Summary
# ----------------------------------------------------------
echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║            Setup Complete!               ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${BOLD}Studio connections:${NC}"
echo -e "    Primary (FLAC):  ${GREEN}${ICECAST_HOSTNAME:-<host>}:${HARBOR_PRIMARY_PORT:-8010}${NC}  mount: /primary"
echo -e "    Fallback (Ogg):  ${GREEN}${ICECAST_HOSTNAME:-<host>}:${HARBOR_FALLBACK_PORT:-8011}${NC}  mount: /secondary"
echo ""
echo -e "  ${BOLD}Listener URLs:${NC}"
echo -e "    MP3 128k:  ${GREEN}https://${ICECAST_HOSTNAME:-<host>}/listen/stream-mp3-128${NC}"
echo -e "    MP3 320k:  ${GREEN}https://${ICECAST_HOSTNAME:-<host>}/listen/stream-mp3-320${NC}"
echo -e "    AAC 128k:  ${GREEN}https://${ICECAST_HOSTNAME:-<host>}/listen/stream-aac-128${NC}"
echo -e "    Ogg 128k:  ${GREEN}https://${ICECAST_HOSTNAME:-<host>}/listen/stream-ogg-128${NC}"
echo -e "    HLS:       ${GREEN}https://${ICECAST_HOSTNAME:-<host>}/hls/live.m3u8${NC}"
echo ""
echo -e "  ${BOLD}Admin:${NC}"
echo -e "    Icecast:   ${GREEN}https://${ICECAST_HOSTNAME:-<host>}/icecast-admin/${NC}"
echo ""
echo -e "  ${BOLD}Useful commands:${NC}"
echo "    docker compose logs -f          # Follow all logs"
echo "    docker compose logs liquidsoap  # Liquidsoap logs only"
echo "    docker compose restart           # Restart all services"
echo "    docker compose down              # Stop everything"
echo ""
