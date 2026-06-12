#!/usr/bin/env bash
set -euo pipefail

declare -a SERVICE_PIDS=()
declare -a SERVICE_NAMES=()

HOSTNAME="${ICECAST_HOSTNAME:-localhost}"
CERT_PATH="/etc/letsencrypt/live/$HOSTNAME/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$HOSTNAME/privkey.pem"
STATUS_PANEL_ENABLED="${ENABLE_STATUS_PANEL:-0}"
RENDERED_CONFIG_PATH="/etc/nginx/rendered/nginx.conf"
FINAL_CONFIG_PATH="/etc/nginx/nginx.conf"
RELOAD_MARKER="/etc/letsencrypt/.nginx-reload"

log() {
    echo "[entrypoint] $*"
}

escape_html() {
    echo "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"
}

marker_value() {
    if [[ -f "$RELOAD_MARKER" ]]; then
        cat "$RELOAD_MARKER" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

render_icecast_config() {
    envsubst < /etc/icecast2/icecast.xml.template > /etc/icecast2/icecast.xml
}

write_nginx_config() {
    if [[ -f "$CERT_PATH" && -f "$KEY_PATH" ]]; then
        log "SSL certificate found for $HOSTNAME; enabling HTTPS"
        cp "$RENDERED_CONFIG_PATH" "$FINAL_CONFIG_PATH"
    else
        log "No SSL certificate found; serving HTTP only for ACME/bootstrap"
        sed '/# HTTPS_START/,/# HTTPS_END/d' "$RENDERED_CONFIG_PATH" > "$FINAL_CONFIG_PATH"
    fi

    if [[ "$STATUS_PANEL_ENABLED" != "1" ]]; then
        log "Status panel API disabled; removing /api routes"
        sed -i '/# STATUS_API_START/,/# STATUS_API_END/d' "$FINAL_CONFIG_PATH"
    fi
}

render_nginx_config() {
    envsubst '$ICECAST_HOSTNAME' < /etc/nginx/nginx.conf.template > "$RENDERED_CONFIG_PATH"

    mkdir -p /usr/share/nginx/html
    export FINAL_RADIO_NAME="${RADIO_NAME:-${STATION_NAME:-Radio Station}}"
    export FINAL_CONTACT_EMAIL="${CONTACT_EMAIL:-${STATION_ADMIN_EMAIL:-admin@example.com}}"
    export STATION_NAME_ESC
    export STATION_ADMIN_EMAIL_ESC
    STATION_NAME_ESC="$(escape_html "$FINAL_RADIO_NAME")"
    STATION_ADMIN_EMAIL_ESC="$(escape_html "$FINAL_CONTACT_EMAIL")"

    envsubst '$STATION_NAME_ESC $STATION_ADMIN_EMAIL_ESC $ICECAST_HOSTNAME' \
        < /etc/nginx/index.html.template \
        > /usr/share/nginx/html/index.html

    write_nginx_config
}

watch_certificate_updates() {
    local last_marker
    local current_marker

    last_marker="$(marker_value)"

    while :; do
        sleep 30
        current_marker="$(marker_value)"

        if [[ "$current_marker" != "$last_marker" ]]; then
            last_marker="$current_marker"
            log "Certificate update detected; reloading nginx"
            write_nginx_config
            if nginx -t; then
                nginx -s reload
            else
                log "nginx config test failed; skipping reload until next marker change"
            fi
        fi
    done
}

start_service() {
    local name="$1"
    shift

    log "Starting $name"
    "$@" &
    SERVICE_NAMES+=("$name")
    SERVICE_PIDS+=("$!")
}

wait_for_url() {
    local name="$1"
    local url="$2"
    local attempts="${3:-30}"

    for _ in $(seq 1 "$attempts"); do
        if curl -fsS "$url" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done

    log "$name did not become ready at $url"
    return 1
}

stop_services() {
    local pid

    trap - EXIT TERM INT

    for pid in "${SERVICE_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done

    wait || true
}

service_name_for_pid() {
    local pid="$1"
    local index

    for index in "${!SERVICE_PIDS[@]}"; do
        if [[ "${SERVICE_PIDS[$index]}" == "$pid" ]]; then
            echo "${SERVICE_NAMES[$index]}"
            return 0
        fi
    done

    echo "unknown"
}

monitor_services() {
    local exit_code
    local failed_pid
    local failed_name

    while :; do
        failed_pid=""
        set +e
        wait -n -p failed_pid
        exit_code="$?"
        set -e

        failed_name="$(service_name_for_pid "$failed_pid")"
        log "$failed_name exited with status $exit_code; stopping container"
        stop_services
        exit "$exit_code"
    done
}

mkdir -p \
    /etc/nginx/rendered \
    /emergency-audio \
    /hls \
    /run/nginx \
    /usr/share/nginx/html \
    /var/cache/nginx/client_temp \
    /var/cache/nginx/proxy_temp \
    /var/cache/nginx/fastcgi_temp \
    /var/cache/nginx/uwsgi_temp \
    /var/cache/nginx/scgi_temp \
    /var/log/icecast2

render_icecast_config
render_nginx_config

trap stop_services EXIT TERM INT

start_service icecast icecast2 -c /etc/icecast2/icecast.xml
wait_for_url icecast "http://127.0.0.1:8000/status-json.xsl"

start_service analytics python -u /opt/sonicverse/analytics/tracker.py

start_service liquidsoap liquidsoap /etc/liquidsoap/radio.liq
start_service nginx nginx -g "daemon off;"
start_service certificate-watch watch_certificate_updates

monitor_services
