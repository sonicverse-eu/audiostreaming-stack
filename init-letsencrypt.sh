#!/bin/bash

# Obtain an initial Let's Encrypt certificate for the streaming stack.
# If the main nginx service is already running, reuse it for the ACME challenge.
# Otherwise start a temporary ACME-only nginx container that does not depend on
# the fixed sonicverse-nginx container name.
#
# Usage: ./init-letsencrypt.sh
#
# Requires: .env file with ICECAST_HOSTNAME and LETSENCRYPT_EMAIL set.

set -e

BOOTSTRAP_NGINX_STARTED=0
MAIN_NGINX_WAS_RUNNING=0
CERTBOT_SERVICE_RUNNING=0
ENABLE_STATUS_PANEL="${ENABLE_STATUS_PANEL:-0}"

cleanup_bootstrap_nginx() {
    if [[ "$BOOTSTRAP_NGINX_STARTED" == "1" ]]; then
        docker compose --profile acme-bootstrap rm -fsv nginx-acme >/dev/null 2>&1 || true
    fi
}

remove_conflicting_named_container() {
    local service="$1"
    local fixed_name="sonicverse-$service"
    local current_id existing_id

    current_id="$(docker compose ps -q "$service" 2>/dev/null | head -n 1)"
    existing_id="$(docker ps -aq --filter "name=^/${fixed_name}$" 2>/dev/null | head -n 1)"

    if [[ -n "$existing_id" && "$existing_id" != "$current_id" ]]; then
        echo "Removing conflicting container: $fixed_name"
        docker rm -f "$existing_id" >/dev/null
    fi
}

trap cleanup_bootstrap_nginx EXIT INT TERM

compose_up_command() {
    if [[ "$ENABLE_STATUS_PANEL" == "1" ]]; then
        echo "docker compose --profile status-panel up -d"
    else
        echo "docker compose up -d"
    fi
}

setup_certbot_directory() {
    local target_dir="$(pwd)"
    local cache_dir=""

    if [[ -d "$XDG_CACHE_HOME/audiostreaming-stack-installer" ]]; then
        cache_dir="$XDG_CACHE_HOME/audiostreaming-stack-installer"
    elif [[ -d "$HOME/.cache/audiostreaming-stack-installer" ]]; then
        cache_dir="$HOME/.cache/audiostreaming-stack-installer"
    fi

    if [[ -n "$cache_dir" && -d "$cache_dir" ]]; then
        local latest_clone
        latest_clone="$(ls -td "$cache_dir"/clone-* 2>/dev/null | head -1)"
        if [[ -n "$latest_clone" && -d "$latest_clone/certbot" && "$latest_clone" != "$target_dir" ]]; then
            if [[ ! -d "$target_dir/certbot" ]]; then
                ln -s "$latest_clone/certbot" "$target_dir/certbot"
                echo "Linked certbot directory from $latest_clone"
            fi
        fi
    fi
}

setup_certbot_directory

# Load .env
if [[ -f .env ]]; then
    export $(grep -v '^#' .env | xargs)
fi

if [[ -z "$ICECAST_HOSTNAME" ]]; then
    echo "Error: ICECAST_HOSTNAME not set in .env"
    exit 1
fi

# Check if cert already exists
if [[ -f "certbot/conf/live/$ICECAST_HOSTNAME/fullchain.pem" ]]; then
    echo "Certificate already exists for $ICECAST_HOSTNAME"
    read -rp "Renew/replace it? (y/N): " renew
    if [[ ! "$renew" =~ ^[Yy]$ ]]; then
        echo "Keeping existing certificate."
        exit 0
    fi
    echo "Removing old certificate files..."
    rm -rf "certbot/conf/live/$ICECAST_HOSTNAME"
    rm -rf "certbot/conf/archive/$ICECAST_HOSTNAME"
    rm -f  "certbot/conf/renewal/$ICECAST_HOSTNAME.conf"
    echo "Old certificate removed."
fi

EMAIL="${LETSENCRYPT_EMAIL:-}"
STAGING="${LETSENCRYPT_STAGING:-0}"

EMAIL_ARGS=()
if [[ -n "$EMAIL" ]]; then
    EMAIL_ARGS=(--email "$EMAIL")
else
    EMAIL_ARGS=(--register-unsafely-without-email)
fi

STAGING_ARGS=()
if [[ "$STAGING" == "1" ]]; then
    STAGING_ARGS=(--staging)
    echo "Using Let's Encrypt staging environment (test certificates)"
fi

DEPLOY_HOOK='printf "%s\n" "$(date -u +%s)" > /etc/letsencrypt/.nginx-reload'

echo "Requesting certificate for: $ICECAST_HOSTNAME"

# Create required directories
mkdir -p certbot/conf certbot/www

RUNNING_SERVICES="$(docker compose ps --status running --services 2>/dev/null || true)"
if printf '%s\n' "$RUNNING_SERVICES" | grep -qx "nginx"; then
    MAIN_NGINX_WAS_RUNNING=1
    echo "Main nginx service is already running; reusing it for the ACME challenge."
else
    echo "Starting temporary ACME-only nginx service..."
    if ! docker compose --profile acme-bootstrap up -d --no-deps nginx-acme; then
        echo "Error: failed to start temporary nginx-acme service for the ACME challenge."
        exit 1
    fi
    BOOTSTRAP_NGINX_STARTED=1

    echo "Waiting for temporary nginx-acme to be ready..."
    ready=0
    for _ in {1..15}; do
        if curl -fsS "http://127.0.0.1/healthz" >/dev/null 2>&1; then
            ready=1
            break
        fi
        sleep 1
    done

    if [[ "$ready" != "1" ]]; then
        echo "Error: temporary nginx-acme did not become ready on http://127.0.0.1/healthz"
        exit 1
    fi
fi

if printf '%s\n' "$RUNNING_SERVICES" | grep -qx "certbot"; then
    CERTBOT_SERVICE_RUNNING=1
else
    CERTBOT_CONTAINER_ID="$(docker compose ps -q certbot 2>/dev/null | head -n 1)"
    if [[ -n "$CERTBOT_CONTAINER_ID" ]]; then
        echo "Starting existing certbot service for certificate issuance..."
        docker compose up -d certbot >/dev/null
        CERTBOT_SERVICE_RUNNING=1
    else
        remove_conflicting_named_container "certbot"
    fi
fi

echo "Requesting Let's Encrypt certificate..."
if [[ "$CERTBOT_SERVICE_RUNNING" == "1" ]]; then
    docker compose exec -T certbot \
        certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --deploy-hook "$DEPLOY_HOOK" \
        "${EMAIL_ARGS[@]}" \
        "${STAGING_ARGS[@]}" \
        --agree-tos \
        --no-eff-email \
        -d "$ICECAST_HOSTNAME"
else
    # Override entrypoint since docker-compose.yml sets a renewal-loop entrypoint.
    docker compose run --rm --no-deps --entrypoint "" certbot \
        certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --deploy-hook "$DEPLOY_HOOK" \
        "${EMAIL_ARGS[@]}" \
        "${STAGING_ARGS[@]}" \
        --agree-tos \
        --no-eff-email \
        -d "$ICECAST_HOSTNAME"
fi

cleanup_bootstrap_nginx
BOOTSTRAP_NGINX_STARTED=0

if [[ "$MAIN_NGINX_WAS_RUNNING" == "1" ]]; then
    echo "Restarting nginx with SSL enabled..."
    docker compose restart nginx
fi

echo ""
echo "Done! Certificate obtained for $ICECAST_HOSTNAME"
if [[ "$MAIN_NGINX_WAS_RUNNING" == "1" ]]; then
    echo "Nginx was restarted and is now serving the new certificate."
else
    echo "Start the full stack with: $(compose_up_command)"
fi
