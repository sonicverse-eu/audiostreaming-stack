"""
Sonicverse — Icecast Listener Analytics → PostHog + Pushover Alerts

Polls Icecast stats endpoint and sends listener metrics to PostHog.
Receives silence detection webhooks from Liquidsoap and sends Pushover alerts.
"""

import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

import requests

# Configuration
ICECAST_URL = os.getenv("ICECAST_URL", "http://icecast:8000")
ICECAST_ADMIN_USER = os.getenv("ICECAST_ADMIN_USER", "admin")
ICECAST_ADMIN_PASSWORD = os.getenv("ICECAST_ADMIN_PASSWORD", "changeme")
POSTHOG_API_KEY = os.getenv("POSTHOG_API_KEY", "")
POSTHOG_HOST = os.getenv("POSTHOG_HOST", "https://posthog.sonicverse.eu")
POLL_INTERVAL = int(os.getenv("POSTHOG_POLL_INTERVAL", "30"))
DISTINCT_ID = "sonicverse-streaming-stack"

# Station
STATION_NAME = os.getenv("STATION_NAME", "Radio Station")

# Pushover
PUSHOVER_USER_KEY = os.getenv("PUSHOVER_USER_KEY", "")
PUSHOVER_APP_TOKEN = os.getenv("PUSHOVER_APP_TOKEN", "")
PUSHOVER_API_URL = "https://api.pushover.net/1/messages.json"

# Alert cooldown — avoid spamming repeated silence alerts (seconds)
ALERT_COOLDOWN = 300  # 5 minutes between repeated alerts
last_alert_time = 0

# Track the last outage signature so we only send one combined alert per change.
last_outage_signature = None

# Harbor state is tracked so secondary-down can escalate if primary is already down.
harbor_states = {
    "primary": True,
    "secondary": True,
}

# Initialize PostHog (only if a real key is provided)
posthog_client = None
if POSTHOG_API_KEY and POSTHOG_API_KEY.startswith("phc_"):
    from posthog import Posthog
    posthog_client = Posthog(project_api_key=POSTHOG_API_KEY, host=POSTHOG_HOST)
else:
    POSTHOG_API_KEY = ""  # treat invalid keys as unconfigured

# Track previous state for failover detection
previous_sources = {}


# ============================================================
# Pushover Alerts
# ============================================================

def send_pushover(title, message, priority=1):
    """Send a Pushover notification. Priority: -1=low, 0=normal, 1=high."""
    if not PUSHOVER_USER_KEY or not PUSHOVER_APP_TOKEN:
        print(f"[alerts] Pushover not configured, skipping: {title}", file=sys.stderr)
        return

    try:
        resp = requests.post(PUSHOVER_API_URL, data={
            "token": PUSHOVER_APP_TOKEN,
            "user": PUSHOVER_USER_KEY,
            "title": title,
            "message": message,
            "priority": priority,
            "sound": "siren" if priority >= 1 else "pushover",
        }, timeout=10)
        if resp.ok:
            print(f"[alerts] Pushover sent: {title}")
        else:
            print(f"[alerts] Pushover failed ({resp.status_code}): {resp.text}", file=sys.stderr)
    except Exception as e:
        print(f"[alerts] Pushover error: {e}", file=sys.stderr)


def handle_silence_alert(alert_type):
    """Handle silence start/end alerts from Liquidsoap."""
    global last_alert_time

    now = time.time()

    if alert_type == "silence_start":
        # Respect cooldown to avoid alert spam
        if now - last_alert_time < ALERT_COOLDOWN:
            print("[alerts] Silence alert suppressed (cooldown active)")
            return

        last_alert_time = now
        send_pushover(
            f"{STATION_NAME} — Silence Detected",
            "Dead air detected on the stream. Check the studio connection and source encoders.",
            priority=1,
        )

        if POSTHOG_API_KEY:
            posthog_client.capture(
                distinct_id=DISTINCT_ID,
                event="stream_silence_detected",
            )

    elif alert_type == "silence_end":
        send_pushover(
            f"{STATION_NAME} — Audio Resumed",
            "Audio is back on the stream.",
            priority=-1,
        )

        if POSTHOG_API_KEY:
            posthog_client.capture(
                distinct_id=DISTINCT_ID,
                event="stream_silence_resolved",
            )


def handle_stream_outage(disconnected_mounts):
    """Send a single combined alert for all disconnected Icecast outputs."""
    global last_outage_signature

    if not disconnected_mounts:
        return

    outage_signature = tuple(sorted(disconnected_mounts))
    if outage_signature == last_outage_signature:
        return

    last_outage_signature = outage_signature

    send_pushover(
        f"{STATION_NAME} — Stream Outage",
        f"The following stream outputs went offline: {', '.join(disconnected_mounts)}.",
        priority=1,
    )

    if POSTHOG_API_KEY:
        posthog_client.capture(
            distinct_id=DISTINCT_ID,
            event="stream_outage_detected",
            properties={"disconnected_mounts": disconnected_mounts},
        )


def handle_harbor_state(harbor_name, is_up):
    """Track harbor connectivity and emit Pushover on disconnect transitions."""
    global harbor_states

    if harbor_name not in harbor_states:
        harbor_states[harbor_name] = True

    previous_state = harbor_states[harbor_name]
    harbor_states[harbor_name] = is_up

    if is_up:
        if POSTHOG_API_KEY and previous_state is False:
            posthog_client.capture(
                distinct_id=DISTINCT_ID,
                event="harbor_connected",
                properties={"harbor": harbor_name},
            )
        print(f"[alerts] Harbor connected: {harbor_name}")
        return

    if previous_state is False:
        return

    if POSTHOG_API_KEY:
        posthog_client.capture(
            distinct_id=DISTINCT_ID,
            event="harbor_disconnected",
            properties={"harbor": harbor_name},
        )

    if harbor_name == "primary":
        priority = 1
        message = "The primary studio input is offline. Check the FLAC encoder and the studio connection."
        if harbor_states.get("secondary", True) is False:
            message += " The secondary harbor is also down, so the stream is in critical failover."
    else:
        priority = 2 if harbor_states.get("primary", True) is False else 1
        message = "The secondary studio input is offline. "
        if priority == 2:
            message += "Both harbors are down, so the stream is in critical failover."
        else:
            message += "Failover should still be carrying the stream."
    send_pushover(
        f"{STATION_NAME} — {harbor_name.title()} Harbor Down",
        message,
        priority=priority,
    )


def handle_alert(alert_type):
    if alert_type in ("silence_start", "silence_end"):
        handle_silence_alert(alert_type)
    elif alert_type == "harbor_primary_up":
        handle_harbor_state("primary", True)
    elif alert_type == "harbor_primary_down":
        handle_harbor_state("primary", False)
    elif alert_type == "harbor_secondary_up":
        handle_harbor_state("secondary", True)
    elif alert_type == "harbor_secondary_down":
        handle_harbor_state("secondary", False)


# ============================================================
# Webhook server (receives alerts from Liquidsoap)
# ============================================================

class AlertHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/alert":
            params = parse_qs(parsed.query)
            alert_type = params.get("type", ["unknown"])[0]
            print(f"[alerts] Received alert: {alert_type}")
            handle_alert(alert_type)
            self.send_response(200)
            self.end_headers()
        elif parsed.path == "/health":
            self.send_response(200)
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # Suppress default request logging


def start_webhook_server():
    server = HTTPServer(("0.0.0.0", 8888), AlertHandler)
    print("[alerts] Webhook server listening on :8888")
    server.serve_forever()


# ============================================================
# Icecast stats polling → PostHog
# ============================================================

def fetch_icecast_stats():
    """Fetch stats from Icecast status-json.xsl endpoint."""
    try:
        resp = requests.get(
            f"{ICECAST_URL}/status-json.xsl",
            auth=(ICECAST_ADMIN_USER, ICECAST_ADMIN_PASSWORD),
            timeout=10,
        )
        resp.raise_for_status()
        return resp.json()
    except Exception as e:
        print(f"[analytics] Failed to fetch Icecast stats: {e}", file=sys.stderr)
        return None


def parse_sources(stats):
    """Extract source/mount information from Icecast stats JSON."""
    icestats = stats.get("icestats", {})
    sources = icestats.get("source", [])

    # Icecast returns a single dict if only one source, list if multiple
    if isinstance(sources, dict):
        sources = [sources]

    return sources


def track_listeners(sources):
    """Send per-mount listener counts to PostHog."""
    if not POSTHOG_API_KEY:
        return

    total_listeners = 0

    for source in sources:
        mount = source.get("listenurl", "unknown")
        # Extract just the mount path
        if "/" in mount:
            mount = "/" + mount.split("/", 3)[-1] if mount.count("/") >= 3 else mount

        listeners = source.get("listeners", 0)
        total_listeners += listeners

        posthog_client.capture(
            distinct_id=DISTINCT_ID,
            event="stream_listeners",
            properties={
                "mount": mount,
                "listeners": listeners,
                "peak_listeners": source.get("listener_peak", 0),
                "genre": source.get("genre", ""),
                "title": source.get("title", ""),
                "audio_info": source.get("audio_info", ""),
                "server_name": source.get("server_name", ""),
            },
        )

    posthog_client.capture(
        distinct_id=DISTINCT_ID,
        event="stream_total_listeners",
        properties={
            "total_listeners": total_listeners,
            "active_mounts": len(sources),
        },
    )


def track_source_status(sources):
    """Detect source connect/disconnect and emit one combined outage alert."""
    global previous_sources

    current_mounts = {s.get("listenurl", "unknown") for s in sources}
    prev_mounts = set(previous_sources.keys())

    # Detect new sources
    for mount in current_mounts - prev_mounts:
        if POSTHOG_API_KEY:
            posthog_client.capture(
                distinct_id=DISTINCT_ID,
                event="stream_source_connected",
                properties={"mount": mount},
            )
        print(f"[analytics] Source connected: {mount}")

    # Detect disconnected sources
    disconnected_mounts = sorted(prev_mounts - current_mounts)

    for mount in disconnected_mounts:
        if POSTHOG_API_KEY:
            posthog_client.capture(
                distinct_id=DISTINCT_ID,
                event="stream_source_disconnected",
                properties={"mount": mount},
            )
        print(f"[analytics] Source disconnected: {mount}")

    if disconnected_mounts:
        handle_stream_outage(disconnected_mounts)

    # Update state
    previous_sources = {s.get("listenurl", "unknown"): s for s in sources}


def polling_loop():
    """Main polling loop for Icecast stats."""
    while True:
        stats = fetch_icecast_stats()

        if stats:
            sources = parse_sources(stats)
            track_listeners(sources)
            track_source_status(sources)
            if POSTHOG_API_KEY:
                posthog_client.flush()

        time.sleep(POLL_INTERVAL)


# ============================================================
# Main
# ============================================================

def main():
    print("[analytics] Starting Sonicverse analytics + alerts service")

    if not POSTHOG_API_KEY and not PUSHOVER_USER_KEY:
        print("[analytics] Neither POSTHOG_API_KEY nor PUSHOVER_USER_KEY set.", file=sys.stderr)
        print("[analytics] Running webhook server only (for Liquidsoap silence alerts logging).", file=sys.stderr)

    if POSTHOG_API_KEY:
        print(f"[analytics] PostHog events → {POSTHOG_HOST}")
        print(f"[analytics] Polling {ICECAST_URL} every {POLL_INTERVAL}s")
    if PUSHOVER_USER_KEY:
        print(f"[alerts] Pushover alerts enabled (cooldown: {ALERT_COOLDOWN}s)")

    # Start webhook server in background thread
    webhook_thread = threading.Thread(target=start_webhook_server, daemon=True)
    webhook_thread.start()

    if POSTHOG_API_KEY:
        # Start polling loop (blocks forever)
        polling_loop()
    else:
        # No PostHog — just keep the webhook server alive
        print("[analytics] No PostHog key — skipping Icecast polling, webhook server active")
        webhook_thread.join()


if __name__ == "__main__":
    main()
