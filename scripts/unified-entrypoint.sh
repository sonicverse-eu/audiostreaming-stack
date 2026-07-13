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
STACK_RELOAD_MARKER="${STACK_RELOAD_MARKER_PATH:-/run/sonicverse/reload-request}"
STACK_CONFIG_PATH="${STACK_CONFIG_PATH:-/etc/sonicverse/stack.json}"
STACK_DEFAULTS_PATH="${STACK_DEFAULTS_PATH:-/opt/sonicverse/config/stack.defaults.json}"
RELOADING=0

ICECAST_PID=""
LIQUIDSOAP_PID=""
LIQUIDSOAP_CONFIG="/etc/liquidsoap/radio.liq"
ICECAST_TEMPLATE="/etc/icecast2/icecast.xml.template"
ICECAST_CONFIG="/etc/icecast2/icecast.xml"
STACK_APPLY_STATUS="/etc/sonicverse/stack.apply.json"

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

stack_reload_marker_value() {
    if [[ -f "$STACK_RELOAD_MARKER" ]]; then
        cat "$STACK_RELOAD_MARKER" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

seed_stack_config() {
    mkdir -p "$(dirname "$STACK_CONFIG_PATH")"
    if [[ ! -f "$STACK_CONFIG_PATH" && -f "$STACK_DEFAULTS_PATH" ]]; then
        log "Seeding stack config from defaults"
        cp "$STACK_DEFAULTS_PATH" "$STACK_CONFIG_PATH"
    fi
}

render_stack_config() {
    if [[ -f "$STACK_CONFIG_PATH" ]]; then
        log "Rendering stack config"
        /usr/local/bin/render-stack-config.sh
    else
        log "No stack config found; using baked-in service configs"
    fi
}

render_icecast_config() {
    if [[ -f /etc/icecast2/icecast.xml.template ]]; then
        envsubst < /etc/icecast2/icecast.xml.template > /etc/icecast2/icecast.xml
    fi
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

    if [[ -f /usr/share/nginx/html/index.html ]]; then
        log "Using rendered landing page from stack config"
    else
        envsubst '$STATION_NAME_ESC $STATION_ADMIN_EMAIL_ESC $ICECAST_HOSTNAME' \
            < /etc/nginx/index.html.template \
            > /usr/share/nginx/html/index.html
    fi

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

update_service_pid() {
    local name="$1"
    local pid="$2"
    local index

    for index in "${!SERVICE_NAMES[@]}"; do
        if [[ "${SERVICE_NAMES[$index]}" == "$name" ]]; then
            SERVICE_PIDS[$index]="$pid"
            return 0
        fi
    done

    SERVICE_NAMES+=("$name")
    SERVICE_PIDS+=("$pid")
}

start_service() {
    local name="$1"
    shift

    log "Starting $name"
    "$@" &
    local pid="$!"
    update_service_pid "$name" "$pid"

    case "$name" in
        icecast) ICECAST_PID="$pid" ;;
        liquidsoap) LIQUIDSOAP_PID="$pid" ;;
    esac
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

stop_pid() {
    local pid="$1"
    local name="$2"

    if [[ -z "$pid" ]]; then
        return 0
    fi

    if kill -0 "$pid" 2>/dev/null; then
        log "Stopping $name (pid $pid)"
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
}

backup_streaming_configs() {
    local path

    for path in "$LIQUIDSOAP_CONFIG" "$ICECAST_TEMPLATE" "$ICECAST_CONFIG"; do
        if [[ -f "$path" ]]; then
            cp "$path" "${path}.bak"
        fi
    done
}

restore_streaming_configs() {
    local path

    for path in "$LIQUIDSOAP_CONFIG" "$ICECAST_TEMPLATE" "$ICECAST_CONFIG"; do
        if [[ -f "${path}.bak" ]]; then
            cp "${path}.bak" "$path"
        fi
    done
}

write_stack_apply_status() {
    local state="$1"
    local error_message="${2:-supervised reload failed}"
    local temp="${STACK_APPLY_STATUS}.tmp.$$"
    local timestamp

    timestamp="$(date +%s)"
    mkdir -p "$(dirname "$STACK_APPLY_STATUS")"

    if [[ "$state" == "applied" ]]; then
        printf '{"state":"applied","updated_at":%s}\n' "$timestamp" > "$temp"
    else
        printf '{"state":"failed","error":"%s","updated_at":%s}\n' \
            "$error_message" "$timestamp" > "$temp"
    fi
    mv "$temp" "$STACK_APPLY_STATUS"
}

start_streaming_services() {
    icecast2 -c "$ICECAST_CONFIG" &
    ICECAST_PID="$!"
    update_service_pid "icecast" "$ICECAST_PID"

    if ! wait_for_url icecast "http://127.0.0.1:8000/status-json.xsl"; then
        return 1
    fi

    liquidsoap "$LIQUIDSOAP_CONFIG" &
    LIQUIDSOAP_PID="$!"
    update_service_pid "liquidsoap" "$LIQUIDSOAP_PID"
    return 0
}

rollback_streaming_services() {
    log "Restarting previous streaming services after reload failure"
    stop_pid "$ICECAST_PID" "icecast"
    restore_streaming_configs
    start_streaming_services
}

validate_streaming_config() {
    if ! liquidsoap --check /etc/liquidsoap/radio.liq; then
        log "Liquidsoap config validation failed"
        return 1
    fi

    if ! render_icecast_config; then
        log "Icecast config render failed"
        return 1
    fi

    return 0
}

reload_streaming_services() {
    log "Supervised streaming reload requested"
    RELOADING=1

    backup_streaming_configs

    if ! render_stack_config; then
        restore_streaming_configs
        RELOADING=0
        return 1
    fi

    if ! validate_streaming_config; then
        restore_streaming_configs
        RELOADING=0
        return 1
    fi

    stop_pid "$LIQUIDSOAP_PID" "liquidsoap"
    stop_pid "$ICECAST_PID" "icecast"

    if ! start_streaming_services; then
        rollback_streaming_services || true
        RELOADING=0
        return 1
    fi

    if nginx -t; then
        nginx -s reload || true
    fi

    RELOADING=0
    log "Supervised streaming reload complete"
    return 0
}

watch_reload_requests() {
    local last_marker
    local current_marker

    mkdir -p "$(dirname "$STACK_RELOAD_MARKER")"
    last_marker="$(stack_reload_marker_value)"

    while :; do
        sleep 2
        current_marker="$(stack_reload_marker_value)"

        if [[ "$current_marker" != "$last_marker" ]]; then
            last_marker="$current_marker"
            if reload_streaming_services; then
                write_stack_apply_status "applied"
            else
                write_stack_apply_status "failed" "supervised reload failed"
            fi
        fi
    done
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

        if [[ "$RELOADING" == "1" && ( "$failed_name" == "icecast" || "$failed_name" == "liquidsoap" ) ]]; then
            log "$failed_name exited during supervised reload (status $exit_code); continuing"
            continue
        fi

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
    /run/sonicverse \
    /etc/sonicverse \
    /usr/share/nginx/html \
    /var/cache/nginx/client_temp \
    /var/cache/nginx/proxy_temp \
    /var/cache/nginx/fastcgi_temp \
    /var/cache/nginx/uwsgi_temp \
    /var/cache/nginx/scgi_temp \
    /var/log/icecast2

seed_stack_config
render_stack_config
render_icecast_config
render_nginx_config

trap stop_services EXIT TERM INT

start_service icecast icecast2 -c /etc/icecast2/icecast.xml
wait_for_url icecast "http://127.0.0.1:8000/status-json.xsl"

if [[ "$STATUS_PANEL_ENABLED" == "1" ]]; then
    start_service status-api gunicorn \
        --chdir /opt/sonicverse/status-api \
        --bind 127.0.0.1:8080 \
        --workers 2 \
        --timeout 30 \
        server:app
    wait_for_url status-api "http://127.0.0.1:8080/api/auth-config"
fi

start_service liquidsoap liquidsoap /etc/liquidsoap/radio.liq
start_service nginx nginx -g "daemon off;"
start_service certificate-watch watch_certificate_updates
start_service stack-reload-watch watch_reload_requests

monitor_services
