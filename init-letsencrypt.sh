#!/bin/bash

# Obtain initial Let's Encrypt certificate for the streaming stack.
# Run this once before starting the full stack.
#
# Usage: ./init-letsencrypt.sh
#
# Requires: .env file with ICECAST_HOSTNAME and LETSENCRYPT_EMAIL set.

set -e

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

EMAIL_ARG=""
if [[ -n "$EMAIL" ]]; then
    EMAIL_ARG="--email $EMAIL"
else
    EMAIL_ARG="--register-unsafely-without-email"
fi

STAGING_ARG=""
if [[ "$STAGING" == "1" ]]; then
    STAGING_ARG="--staging"
    echo "Using Let's Encrypt staging environment (test certificates)"
fi

echo "Requesting certificate for: $ICECAST_HOSTNAME"

# Create required directories
mkdir -p certbot/conf certbot/www

# Nginx entrypoint auto-detects missing certs and runs HTTP-only mode.
# No self-signed cert needed.
echo "Starting nginx (HTTP-only mode for ACME challenge)..."
docker compose up -d --no-deps nginx

# Wait for nginx to be ready
echo "Waiting for nginx..."
sleep 3

echo "Requesting Let's Encrypt certificate..."
# Override entrypoint since docker-compose.yml sets a renewal-loop entrypoint
docker compose run --rm --entrypoint "" certbot \
    certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    $EMAIL_ARG \
    $STAGING_ARG \
    --agree-tos \
    --no-eff-email \
    -d "$ICECAST_HOSTNAME"

# Restart nginx so it picks up the real cert and enables HTTPS
echo "Restarting nginx with SSL enabled..."
docker compose restart nginx

echo ""
echo "Done! Certificate obtained for $ICECAST_HOSTNAME"
echo "Start the full stack with: docker compose up -d"
