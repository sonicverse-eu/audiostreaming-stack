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

cleanup_bootstrap_nginx() {
    if [[ "$BOOTSTRAP_NGINX_STARTED" == "1" ]]; then
        docker compose --profile acme-bootstrap rm -fsv nginx-acme >/dev/null 2>&1 || true
    fi
}

trap cleanup_bootstrap_nginx EXIT INT TERM

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

echo "Requesting Let's Encrypt certificate..."
# Override entrypoint since docker-compose.yml sets a renewal-loop entrypoint
docker compose run --rm --entrypoint "" certbot \
    certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    "${EMAIL_ARGS[@]}" \
    "${STAGING_ARGS[@]}" \
    --agree-tos \
    --no-eff-email \
    -d "$ICECAST_HOSTNAME"

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
    echo "Start the full stack with: docker compose up -d"
fi
