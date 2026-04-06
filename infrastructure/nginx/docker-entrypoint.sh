#!/bin/sh
set -e

HOSTNAME="${ICECAST_HOSTNAME:-localhost}"
CERT_PATH="/etc/letsencrypt/live/$HOSTNAME/fullchain.pem"

# Substitute only our custom variable, leave nginx variables ($host etc.) alone
envsubst '$ICECAST_HOSTNAME' < /etc/nginx/nginx.conf.template > /tmp/nginx-substituted.conf

# Substitute template for root index HTML with custom variables
mkdir -p /usr/share/nginx/html
export STATION_NAME="${STATION_NAME:-Radio Station}"
export STATION_ADMIN_EMAIL="${STATION_ADMIN_EMAIL:-admin@example.com}"
envsubst '$STATION_NAME $STATION_ADMIN_EMAIL $ICECAST_HOSTNAME' < /etc/nginx/index.html.template > /usr/share/nginx/html/index.html

if [ -f "$CERT_PATH" ]; then
    echo "[nginx] SSL certificate found for $HOSTNAME — enabling HTTPS"
    cp /tmp/nginx-substituted.conf /etc/nginx/nginx.conf
else
    echo "[nginx] No SSL certificate found — serving HTTP only (for ACME challenge)"
    # Strip the HTTPS server block, keep only HTTP
    sed '/# HTTPS_START/,/# HTTPS_END/d' /tmp/nginx-substituted.conf > /etc/nginx/nginx.conf
fi

rm -f /tmp/nginx-substituted.conf
exec nginx -g 'daemon off;'
