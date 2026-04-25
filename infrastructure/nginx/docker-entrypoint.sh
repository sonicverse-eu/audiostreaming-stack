#!/bin/sh
set -e

HOSTNAME="${ICECAST_HOSTNAME:-localhost}"
CERT_PATH="/etc/letsencrypt/live/$HOSTNAME/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$HOSTNAME/privkey.pem"
STATUS_PANEL_ENABLED="${ENABLE_STATUS_PANEL:-0}"
RENDERED_CONFIG_PATH="/etc/nginx/rendered/nginx.conf"
FINAL_CONFIG_PATH="/etc/nginx/nginx.conf"
RELOAD_MARKER="/etc/letsencrypt/.nginx-reload"

# Substitute only our custom variable, leave nginx variables ($host etc.) alone
envsubst '$ICECAST_HOSTNAME' < /etc/nginx/nginx.conf.template > "$RENDERED_CONFIG_PATH"

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

write_nginx_config() {
    if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
        echo "[nginx] SSL certificate found for $HOSTNAME — enabling HTTPS"
        cp "$RENDERED_CONFIG_PATH" "$FINAL_CONFIG_PATH"
    else
        echo "[nginx] No SSL certificate found — serving HTTP only (for ACME challenge)"
        sed '/# HTTPS_START/,/# HTTPS_END/d' "$RENDERED_CONFIG_PATH" > "$FINAL_CONFIG_PATH"
    fi

    if [ "$STATUS_PANEL_ENABLED" != "1" ]; then
        echo "[nginx] Status panel API disabled — removing /api routes"
        sed -i '/# STATUS_API_START/,/# STATUS_API_END/d' "$FINAL_CONFIG_PATH"
    fi
}

marker_value() {
    if [ -f "$RELOAD_MARKER" ]; then
        cat "$RELOAD_MARKER" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

watch_certificate_updates() {
    last_marker="$(marker_value)"

    while :; do
        sleep 30
        current_marker="$(marker_value)"

        if [ "$current_marker" != "$last_marker" ]; then
            last_marker="$current_marker"
            echo "[nginx] Certificate update detected — reloading nginx"
            write_nginx_config
            nginx -t && nginx -s reload
        fi
    done
}

write_nginx_config

watch_certificate_updates &
exec nginx -g 'daemon off;'
