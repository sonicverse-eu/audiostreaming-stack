#!/bin/bash

# ============================================================
# Sonicverse — Radio Audio Streaming Stack Installer
# Remote-safe installation script compatible with curl piping
# ============================================================

set -e

# Default installation directory
INSTALL_DIR="/opt/audiostreamingstack"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Output functions (defined early for use during setup)
info()    { echo -e "  ${BLUE}ℹ${NC}  $1"; }
success() { echo -e "  ${GREEN}✓${NC}  $1"; }
warn()    { echo -e "  ${YELLOW}!${NC}  $1"; }

# ============================================================
# Remote Execution Detection & Setup
# ============================================================
# If being run via 'curl | bash' (stdin is not a terminal),
# clone the repository first and recursively call the cloned script.
read -t 0 _ 2>/dev/null && STDIN_AVAILABLE=true || STDIN_AVAILABLE=false

# Default installation directory
INSTALL_DIR="/opt/audiostreamingstack"

if [[ "$STDIN_AVAILABLE" == "true" || -f "docker-compose.yml" ]]; then
    # stdin is available (interactive) OR we're already in the repo directory
    WORK_DIR="$(pwd)"

    # Check if we should move to the default installation directory
    if [[ "$WORK_DIR" != "$INSTALL_DIR" && -d "$INSTALL_DIR" ]]; then
        echo ""
        echo "An installation already exists at $INSTALL_DIR"
        read -rp "  → Replace it? This will stop containers and remove all data. (y/N): " replace_existing
        if [[ "$replace_existing" =~ ^[Yy]$ ]]; then
            info "Stopping existing stack..."
            (cd "$INSTALL_DIR" && docker compose down 2>/dev/null || true)
            info "Removing existing installation..."
            sudo rm -rf "$INSTALL_DIR"
            info "Creating new installation at $INSTALL_DIR..."
            sudo mkdir -p "$INSTALL_DIR"
            sudo chown -R "$(whoami)" "$INSTALL_DIR" || true
            sudo cp -r . "$INSTALL_DIR"
            cd "$INSTALL_DIR"
            WORK_DIR="$INSTALL_DIR"
            echo "Installation moved to $INSTALL_DIR"
        elif [[ "$WORK_DIR" != "$INSTALL_DIR" ]]; then
            echo "Staying in current directory. Note: $INSTALL_DIR already exists."
            echo "Run the installer from $INSTALL_DIR for updates."
        fi
    elif [[ "$WORK_DIR" != "$INSTALL_DIR" && -d "$WORK_DIR/.git" ]]; then
        # We're in a git repo but not at INSTALL_DIR - offer to set up there
        echo ""
        echo "  The default install location is: $INSTALL_DIR"
        read -rp "  → Install there now? (y/N): " install_there
        if [[ "$install_there" =~ ^[Yy]$ ]]; then
            sudo mkdir -p "$INSTALL_DIR"
            sudo chown -R "$(whoami)" "$INSTALL_DIR" || true
            sudo cp -r . "$INSTALL_DIR"
            cd "$INSTALL_DIR"
            WORK_DIR="$INSTALL_DIR"
            info "Installation set up at $INSTALL_DIR"
        fi
    fi
else
    # stdin is piped (from curl), and not in repo directory

    # Define minimal info/error for remote setup
    _info() { echo -e "  ${BLUE}ℹ${NC}  $1"; }
    _error() { echo -e "  ${RED}✗${NC}  $1"; }

    # Check if installation directory already exists
    if [[ -d "$INSTALL_DIR" ]]; then
        _info "Existing installation found at $INSTALL_DIR"
        _info "Cloning to temporary directory to preserve existing installation..."

        # Ensure parent directory exists
        sudo mkdir -p "$(dirname "$INSTALL_DIR")"

        # Create a temporary directory next to the install dir (same filesystem for atomic mv)
        TEMP_DIR="$(sudo mktemp -d "${INSTALL_DIR}.tmp.XXXXXX")"
        sudo chown -R "$(whoami)" "$TEMP_DIR" || true

        # Clone the repository to temp directory with shallow clone for speed
        if ! git clone --depth 1 https://github.com/sonicverse-eu/audiostreaming-stack.git "$TEMP_DIR" 2>/dev/null; then
            _error "Failed to clone repository. Existing installation at $INSTALL_DIR remains intact."
            _error "Ensure git is installed and you have internet connectivity."
            sudo rm -rf "$TEMP_DIR"
            exit 1
        fi

        # Clone succeeded, now safe to replace the existing installation
        _info "Clone successful. Replacing existing installation..."
        sudo rm -rf "$INSTALL_DIR"
        sudo mv "$TEMP_DIR" "$INSTALL_DIR"
        sudo chown -R "$(whoami)" "$INSTALL_DIR" || true

        WORK_DIR="$INSTALL_DIR"
    else
        _info "Installing to $INSTALL_DIR"

        # Clone into the installation directory
        WORK_DIR="$INSTALL_DIR"
        sudo mkdir -p "$WORK_DIR"
        sudo chown -R "$(whoami)" "$WORK_DIR" || true

        # Clone the repository with shallow clone for speed
        if ! git clone --depth 1 https://github.com/sonicverse-eu/audiostreaming-stack.git "$WORK_DIR" 2>/dev/null; then
            _error "Failed to clone repository. Ensure git is installed and you have internet connectivity."
            exit 1
        fi
    fi

    _info "Starting installer from $INSTALL_DIR..."

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
    if [[ "$mode" == "dev" ]]; then
        echo -e "  ${BLUE}ℹ${NC}  Development mode enabled — installing Node/Python dependencies"
    elif [[ "$mode" == "local" ]]; then
        echo -e "  ${BLUE}ℹ${NC}  Local build mode enabled — building containers locally"
    else
        echo -e "  ${BLUE}ℹ${NC}  Minimal Docker Hub deployment (default) — using pre-built images"
    fi
    echo ""
}

success() { echo -e "  ${GREEN}✓${NC}  $1"; }
warn()    { echo -e "  ${YELLOW}!${NC}  $1"; }
error()   { echo -e "  ${RED}✗${NC}  $1"; }
step()    { echo -e "\n${BOLD}[$1/$TOTAL_STEPS] $2${NC}"; }

COMPOSE_PROFILE_ARGS=()

refresh_compose_profile_args() {
    local enabled="${ENABLE_STATUS_PANEL:-}"

    if [[ -z "$enabled" && -f .env ]]; then
        enabled="$(grep '^ENABLE_STATUS_PANEL=' .env 2>/dev/null | tail -n 1 | cut -d= -f2-)"
    fi

    if [[ "$enabled" == "1" ]]; then
        COMPOSE_PROFILE_ARGS=(--profile status-panel)
    else
        COMPOSE_PROFILE_ARGS=()
    fi
}

docker_compose() {
    refresh_compose_profile_args

    CERTBOT_LINKED=0
    if [[ -d "$XDG_CACHE_HOME/audiostreaming-stack-installer" || -d "$HOME/.cache/audiostreaming-stack-installer" ]]; then
        local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/audiostreaming-stack-installer"
        local latest_clone
        latest_clone="$(ls -td "$cache_dir"/clone-* 2>/dev/null | head -1)"
        if [[ -n "$latest_clone" && -d "$latest_clone/certbot" && ! -L "$(pwd)/certbot" ]]; then
            if [[ ! -d "certbot" ]]; then
                ln -s "$latest_clone/certbot" ./certbot
                CERTBOT_LINKED=1
            fi
        fi
    fi

    docker compose "${COMPOSE_PROFILE_ARGS[@]}" "$@"
}

compose_up_command() {
    refresh_compose_profile_args
    if [[ "${#COMPOSE_PROFILE_ARGS[@]}" -gt 0 ]]; then
        echo "docker compose --profile status-panel up -d"
    else
        echo "docker compose up -d"
    fi
}

compose_down_command() {
    refresh_compose_profile_args
    if [[ "${#COMPOSE_PROFILE_ARGS[@]}" -gt 0 ]]; then
        echo "docker compose --profile status-panel down"
    else
        echo "docker compose down"
    fi
}

remove_conflicting_named_container() {
    local service="$1"
    local fixed_name="sonicverse-$service"
    local current_id existing_id

    current_id="$(docker_compose ps -q "$service" 2>/dev/null | head -n 1)"
    existing_id="$(docker ps -aq --filter "name=^/${fixed_name}$" 2>/dev/null | head -n 1)"

    if [[ -n "$existing_id" && "$existing_id" != "$current_id" ]]; then
        warn "Removing conflicting container ${fixed_name}"
        docker rm -f "$existing_id" >/dev/null
    fi
}

clear_conflicting_stack_container_names() {
    local service
    for service in icecast liquidsoap nginx certbot status-api analytics; do
        remove_conflicting_named_container "$service"
    done
}

prompt() {
    local var_name="$1" prompt_text="$2" default="$3"
    if [[ -n "$default" ]]; then
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
    LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 20
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
if [[ "$DEV_MODE" == "true" ]]; then
    TOTAL_STEPS=7
fi

# ============================================================

print_banner

if [[ "$DEV_MODE" == "true" ]]; then
    print_mode_info "dev"
elif [[ "$USE_PREBUILT" == "false" ]]; then
    print_mode_info "local"
else
    print_mode_info "ghcr"
fi

# ----------------------------------------------------------
# Detect existing installation
# ----------------------------------------------------------
if docker_compose ps --quiet 2>/dev/null | head -1 | grep -q .; then
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
            backup_file="$(mktemp -t sonicverse-image-backup.XXXXXX)"
            backup_stamp="$(date +%s)"
            trap 'rm -f "$backup_file"' EXIT

            info "Backing up currently running service images..."
            backup_count=0
            for service in $(docker_compose config --services 2>/dev/null || true); do
                container_id="$(docker_compose ps -q "$service" 2>/dev/null || true)"
                if [[ -z "$container_id" ]]; then
                    continue
                fi

                original_image="$(docker inspect --format '{{.Config.Image}}' "$container_id" 2>/dev/null || true)"
                current_image_id="$(docker inspect --format '{{.Image}}' "$container_id" 2>/dev/null || true)"
                if [[ -z "$original_image" || -z "$current_image_id" ]]; then
                    continue
                fi

                backup_image="sonicverse-backup/${service}:${backup_stamp}"
                if docker tag "$current_image_id" "$backup_image" 2>/dev/null; then
                    echo "${original_image}|${backup_image}" >> "$backup_file"
                    backup_count=$((backup_count + 1))
                fi
            done
            success "Backed up $backup_count image(s)."
            echo ""
            info "Pulling latest changes..."
            git pull 2>/dev/null || true
            echo ""
            info "Pulling latest images..."
            docker_compose pull || true
            echo ""
            info "Rebuilding any local images..."
            docker_compose build
            echo ""
            info "Applying updates with zero downtime..."
            clear_conflicting_stack_container_names
            if ! docker_compose up -d --remove-orphans; then
                error "Failed to update stack. Rolling back..."
                if [[ -s "$backup_file" ]]; then
                    info "Restoring previously running images..."
                    while IFS='|' read -r original_image backup_image; do
                        if [[ -n "$original_image" && -n "$backup_image" ]] && docker image inspect "$backup_image" >/dev/null 2>&1; then
                            docker tag "$backup_image" "$original_image" || true
                        fi
                    done < "$backup_file"
                else
                    warn "No image backups found; retrying with current images."
                fi
                clear_conflicting_stack_container_names
                docker_compose up -d --remove-orphans || true
                exit 1
            fi
            echo ""
            success "Stack updated successfully!"
            echo ""
            docker_compose ps
            echo ""
            exit 0
            ;;
        2)
            info "Stopping and removing existing stack..."
            docker_compose down --rmi local --remove-orphans
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
elif docker_compose ps -a --quiet 2>/dev/null | head -1 | grep -q .; then
    warn "Stopped containers from a previous install detected."
    read -rp "  → Remove them before continuing? (Y/n): " remove_old
    if [[ ! "$remove_old" =~ ^[Nn]$ ]]; then
        docker_compose down --rmi local --remove-orphans
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

if [[ -f .env ]]; then
    warn ".env file already exists."
    read -rp "  → Overwrite with fresh configuration? (y/N): " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
        info "Keeping existing .env"
        SKIP_ENV=true
    fi
fi

if [[ "${SKIP_ENV}" != "true" ]]; then
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

    # Optional status dashboard
    echo ""
    read -rp "  → Enable the optional status dashboard API now? (y/N): " configure_status_dashboard
    if [[ "$configure_status_dashboard" =~ ^[Yy]$ ]]; then
        ENABLE_STATUS_PANEL="1"
        prompt APPWRITE_ENDPOINT   "Appwrite endpoint" "https://cloud.appwrite.io/v1"
        prompt APPWRITE_PROJECT_ID "Appwrite project ID" ""
        prompt APPWRITE_TEAM_ID    "Appwrite team ID (members get panel access)" ""
        if [[ -n "${APPWRITE_PROJECT_ID}" && -z "${APPWRITE_TEAM_ID}" ]]; then
            warn "APPWRITE_TEAM_ID is required when APPWRITE_PROJECT_ID is set."
            while [[ -z "${APPWRITE_TEAM_ID}" ]]; do
                prompt APPWRITE_TEAM_ID "Appwrite team ID (required for panel access)" ""
                if [[ -z "${APPWRITE_TEAM_ID}" ]]; then
                    warn "Team ID cannot be empty while Appwrite panel auth is enabled."
                fi
            done
        fi
        prompt STATUS_PANEL_CORS_ORIGIN "Status panel frontend URL(s) for CORS" ""
        prompt STATUS_PANEL_WRITE_ROLES "Operator roles for writes (comma-separated)" "owner,admin"
        prompt STATUS_PANEL_ALLOW_RISKY_COMMANDS "Allow destructive panel commands? (0/1)" "0"
    else
        ENABLE_STATUS_PANEL="0"
        APPWRITE_ENDPOINT=""
        APPWRITE_PROJECT_ID=""
        APPWRITE_TEAM_ID=""
        STATUS_PANEL_CORS_ORIGIN=""
        STATUS_PANEL_WRITE_ROLES="owner,admin"
        STATUS_PANEL_ALLOW_RISKY_COMMANDS="0"
    fi

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
HOSTNAME=${ICECAST_HOSTNAME}
EMAIL=${LETSENCRYPT_EMAIL}

# Pushover alerts
PUSHOVER_USER_KEY=${PUSHOVER_USER_KEY}
PUSHOVER_APP_TOKEN=${PUSHOVER_APP_TOKEN}
SILENCE_THRESHOLD_DB=-40
SILENCE_DURATION=15

# Appwrite (status panel auth)
ENABLE_STATUS_PANEL=${ENABLE_STATUS_PANEL}
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
if [[ "$DEV_MODE" == "true" ]]; then
    step "$STEP_NUM" "Installing development dependencies"
    echo ""
    info "Installing Node.js and Python dependencies..."
    echo ""
    if [[ -f "install-all.sh" ]]; then
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
    if [[ -n "$fallback_path" && -f "$fallback_path" ]]; then
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

if [[ "$USE_PREBUILT" == "true" ]]; then
    info "Pulling pre-built images from Docker Hub or configured registry..."
    echo ""
    docker_compose pull || { error "Pull failed. Images may not exist yet. Run with --build-local to build locally instead."; exit 1; }
    echo ""
    success "All images pulled successfully"
else
    info "Building containers locally. This may take a few minutes on first run..."
    echo ""
    docker_compose build
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
if [[ -f "certbot/conf/live/${ICECAST_HOSTNAME}/fullchain.pem" ]]; then
    CERT_SIZE=$(wc -c < "certbot/conf/live/${ICECAST_HOSTNAME}/fullchain.pem" 2>/dev/null || echo 0)
    if [[ "$CERT_SIZE" -lt 1500 ]]; then
        warn "Found a possibly invalid/stale certificate (${CERT_SIZE} bytes). Removing it..."
        sudo rm -rf "certbot/conf/live/${ICECAST_HOSTNAME}"
        sudo rm -rf "certbot/conf/archive/${ICECAST_HOSTNAME}"
        sudo rm -f  "certbot/conf/renewal/${ICECAST_HOSTNAME}.conf"
        success "Stale certificate removed"
    fi
fi

if [[ -f "certbot/conf/live/${ICECAST_HOSTNAME}/fullchain.pem" ]]; then
    success "SSL certificate already exists for ${ICECAST_HOSTNAME}"
    chmod -R 755 certbot/conf 2>/dev/null || true
else
    echo ""
    read -rp "  → Obtain Let's Encrypt SSL certificate now? (Y/n): " get_cert
    if [[ ! "$get_cert" =~ ^[Nn]$ ]]; then
        info "Make sure DNS for ${ICECAST_HOSTNAME} points to this server!"
        read -rp "  → DNS is configured and ready? (y/N): " dns_ready
        if [[ "$dns_ready" =~ ^[Yy]$ ]]; then
            bash ./init-letsencrypt.sh
            success "SSL certificate obtained"
            chmod -R 755 certbot/conf 2>/dev/null || true
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
    clear_conflicting_stack_container_names
    docker_compose up -d
    echo ""
    success "Streaming stack is running!"
else
    info "Start later with: $(compose_up_command)"
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
echo "    cd $(pwd)  # IMPORTANT: always run docker compose from this directory"
echo "    docker compose logs -f          # Follow all logs"
echo "    docker compose logs liquidsoap  # Liquidsoap logs only"
if [[ "${ENABLE_STATUS_PANEL:-0}" == "1" ]]; then
echo "    docker compose --profile status-panel restart  # Restart all services"
echo "    docker compose --profile status-panel down     # Stop everything"
else
echo "    docker compose restart           # Restart all services"
echo "    docker compose down              # Stop everything"
fi
echo ""
