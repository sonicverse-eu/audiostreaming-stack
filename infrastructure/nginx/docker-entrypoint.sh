#!/bin/sh
set -e

HOSTNAME="${ICECAST_HOSTNAME:-localhost}"
CERT_PATH="/etc/letsencrypt/live/$HOSTNAME/fullchain.pem"
STATUS_PANEL_ENABLED="${ENABLE_STATUS_PANEL:-0}"

# Substitute only our custom variable, leave nginx variables ($host etc.) alone
envsubst '$ICECAST_HOSTNAME' < /etc/nginx/nginx.conf.template > /tmp/nginx-substituted.conf

# Substitute template for root index HTML with custom variables
mkdir -p /usr/share/nginx/html
# Fallback support for requested aliases
export FINAL_RADIO_NAME="${RADIO_NAME:-${STATION_NAME:-Radio Station}}"
export FINAL_CONTACT_EMAIL="${CONTACT_EMAIL:-${STATION_ADMIN_EMAIL:-admin@example.com}}"

escape_html() {
    echo "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"
}

export STATION_NAME_ESC="$(escape_html "$FINAL_RADIO_NAME")"
export STATION_ADMIN_EMAIL_ESC="$(escape_html "$FINAL_CONTACT_EMAIL")"

envsubst '$STATION_NAME_ESC $STATION_ADMIN_EMAIL_ESC $ICECAST_HOSTNAME' < /etc/nginx/index.html.template > /usr/share/nginx/html/index.html

if [ -f "$CERT_PATH" ]; then
    echo "[nginx] SSL certificate found for $HOSTNAME — enabling HTTPS"
    cp /tmp/nginx-substituted.conf /etc/nginx/nginx.conf
else
    echo "[nginx] No SSL certificate found — serving HTTP only (for ACME challenge)"
    # Strip the HTTPS server block, keep only HTTP
    sed '/# HTTPS_START/,/# HTTPS_END/d' /tmp/nginx-substituted.conf > /etc/nginx/nginx.conf
fi

if [ "$STATUS_PANEL_ENABLED" != "1" ]; then
    echo "[nginx] Status panel API disabled — removing /api routes"
    sed -i '/# STATUS_API_START/,/# STATUS_API_END/d' /etc/nginx/nginx.conf
fi

rm -f /tmp/nginx-substituted.conf
exec nginx -g 'daemon off;'
