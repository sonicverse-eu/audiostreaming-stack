"""
Broadcast Engineer Status Panel — API backend

Serves a real-time dashboard showing stream health, listener counts,
source status, alert history, configuration, and container status.
Protected by Appwrite authentication.
"""

import functools
import json
import os
import subprocess
import time
from collections import deque

import glob as globmod
import shutil

import requests
from flask import Flask, jsonify, request, Response
from flask_cors import CORS

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 100 * 1024 * 1024  # 100 MB upload limit

# CORS — allow the current and legacy Breeze Radio panel origins.
DEFAULT_CORS_ORIGINS = {
    "https://status.breezeradio.nl",
    "https://broadcast-status.breezeradio.nl",
}


def get_cors_origins():
    raw_origins = os.getenv("STATUS_PANEL_CORS_ORIGIN", "")
    origins = {origin.strip() for origin in raw_origins.split(",") if origin.strip()}

    if not origins:
        origins = set(DEFAULT_CORS_ORIGINS)
    elif "https://status.breezeradio.nl" in origins or "https://broadcast-status.breezeradio.nl" in origins:
        origins |= DEFAULT_CORS_ORIGINS

    return sorted(origins)


CORS(app, resources={r"/api/*": {"origins": get_cors_origins()}}, supports_credentials=False)

# Configuration
ICECAST_URL = os.getenv("ICECAST_URL", "http://icecast:8000")
ICECAST_ADMIN_USER = os.getenv("ICECAST_ADMIN_USER", "admin")
ICECAST_ADMIN_PASSWORD = os.getenv("ICECAST_ADMIN_PASSWORD", "changeme")
STATION_NAME = os.getenv("STATION_NAME", "Radio Station")

# Appwrite auth
APPWRITE_ENDPOINT = os.getenv("APPWRITE_ENDPOINT", "")
APPWRITE_PROJECT_ID = os.getenv("APPWRITE_PROJECT_ID", "")
APPWRITE_TEAM_ID = os.getenv("APPWRITE_TEAM_ID", "")

# Alert history (last 50 events, in-memory)
alert_history = deque(maxlen=50)


def verify_appwrite_session(jwt):
    """Verify an Appwrite JWT and check team membership."""
    if not APPWRITE_ENDPOINT or not APPWRITE_PROJECT_ID:
        return False

    headers = {
        "X-Appwrite-Project": APPWRITE_PROJECT_ID,
        "X-Appwrite-JWT": jwt,
    }

    try:
        # Verify the JWT is valid
        resp = requests.get(
            f"{APPWRITE_ENDPOINT}/account",
            headers=headers,
            timeout=5,
        )
        if resp.status_code != 200:
            return False

        # If a team ID is configured, verify membership
        if APPWRITE_TEAM_ID:
            teams_resp = requests.get(
                f"{APPWRITE_ENDPOINT}/teams/{APPWRITE_TEAM_ID}/memberships",
                headers=headers,
                timeout=5,
            )
            if teams_resp.status_code != 200:
                return False

        return True
    except Exception:
        return False


def require_auth(f):
    @functools.wraps(f)
    def decorated(*args, **kwargs):
        # Check for Appwrite JWT in Authorization header
        auth_header = request.headers.get("Authorization", "")
        if auth_header.startswith("Bearer "):
            jwt = auth_header[7:]
            if verify_appwrite_session(jwt):
                return f(*args, **kwargs)

        return Response(
            json.dumps({"error": "Authentication required"}),
            401,
            {"Content-Type": "application/json"},
        )
    return decorated


# ============================================================
# Icecast stats
# ============================================================

def fetch_icecast_stats():
    try:
        resp = requests.get(
            f"{ICECAST_URL}/status-json.xsl",
            auth=(ICECAST_ADMIN_USER, ICECAST_ADMIN_PASSWORD),
            timeout=5,
        )
        resp.raise_for_status()
        return resp.json()
    except Exception as e:
        return {"error": str(e)}


def parse_stats(stats):
    if "error" in stats:
        return {"status": "error", "error": stats["error"], "mounts": [], "total_listeners": 0}

    icestats = stats.get("icestats", {})
    sources = icestats.get("source", [])
    if isinstance(sources, dict):
        sources = [sources]

    mounts = []
    total_listeners = 0

    for src in sources:
        listen_url = src.get("listenurl", "")
        mount = listen_url.split("/")[-1] if "/" in listen_url else listen_url
        listeners = src.get("listeners", 0)
        total_listeners += listeners

        mounts.append({
            "mount": f"/{mount}" if not mount.startswith("/") else mount,
            "listeners": listeners,
            "peak_listeners": src.get("listener_peak", 0),
            "name": src.get("server_name", ""),
            "description": src.get("server_description", ""),
            "audio_info": src.get("audio_info", ""),
            "genre": src.get("genre", ""),
            "title": src.get("title", ""),
            "content_type": src.get("server_type", ""),
            "stream_start": src.get("stream_start", ""),
        })

    return {
        "status": "ok",
        "station_name": STATION_NAME,
        "server_id": icestats.get("server_id", ""),
        "total_listeners": total_listeners,
        "mounts": sorted(mounts, key=lambda m: m["mount"]),
        "timestamp": int(time.time()),
    }


# ============================================================
# Routes — public (no auth)
# ============================================================

@app.route("/api/auth-config")
def api_auth_config():
    """Return Appwrite config for the frontend (non-sensitive)."""
    return jsonify({
        "endpoint": APPWRITE_ENDPOINT,
        "projectId": APPWRITE_PROJECT_ID,
    })


@app.route("/api/alert", methods=["POST", "GET"])
def api_alert():
    """Receive alerts from the analytics service or Liquidsoap (internal only).
    Only accepts requests from Docker internal network (non-routable IPs)."""
    remote_ip = request.remote_addr or ""
    # Allow Docker bridge network (172.x), localhost, and private ranges
    if not (remote_ip.startswith("172.") or remote_ip.startswith("10.") or
            remote_ip.startswith("192.168.") or remote_ip in ("127.0.0.1", "::1")):
        return Response(json.dumps({"error": "Forbidden"}), 403,
                        {"Content-Type": "application/json"})

    alert_type = request.args.get("type", "unknown")
    message = request.args.get("message", "")

    alert = {
        "type": alert_type,
        "message": message,
        "timestamp": int(time.time()),
    }
    alert_history.appendleft(alert)
    return jsonify({"ok": True})


# ============================================================
# Routes — authenticated
# ============================================================

@app.route("/api/status")
@require_auth
def api_status():
    stats = fetch_icecast_stats()
    return jsonify(parse_stats(stats))


@app.route("/api/config")
@require_auth
def api_config():
    """Return current stack configuration (non-sensitive)."""
    return jsonify({
        "station_name": STATION_NAME,
        "icecast_url": ICECAST_URL,
        "hostname": os.getenv("ICECAST_HOSTNAME", ""),
        "harbor_primary_port": os.getenv("HARBOR_PRIMARY_PORT", "8010"),
        "harbor_fallback_port": os.getenv("HARBOR_FALLBACK_PORT", "8011"),
        "silence_threshold_db": os.getenv("SILENCE_THRESHOLD_DB", "-40"),
        "silence_duration_s": os.getenv("SILENCE_DURATION", "15"),
        "max_listeners": os.getenv("ICECAST_MAX_LISTENERS", "500"),
        "posthog_enabled": bool(os.getenv("POSTHOG_API_KEY")),
        "pushover_enabled": bool(os.getenv("PUSHOVER_USER_KEY")),
    })


@app.route("/api/alerts")
@require_auth
def api_alerts():
    return jsonify(list(alert_history))


@app.route("/api/containers")
@require_auth
def api_containers():
    """Get Docker container status for all stack services."""
    try:
        result = subprocess.run(
            ["docker", "ps", "-a", "--filter", "name=breezeradio-", "--format",
             '{"name":"{{.Names}}","status":"{{.Status}}","image":"{{.Image}}","ports":"{{.Ports}}"}'],
            capture_output=True, text=True, timeout=5,
        )
        containers = []
        for line in result.stdout.strip().split("\n"):
            if line:
                containers.append(json.loads(line))
        return jsonify(containers)
    except Exception as e:
        return jsonify({"error": str(e)})


# ============================================================
# Emergency audio management
# ============================================================

EMERGENCY_AUDIO_DIR = os.getenv("EMERGENCY_AUDIO_DIR", "/emergency-audio")
ALLOWED_AUDIO_EXTENSIONS = {".mp3", ".flac", ".wav", ".ogg"}
MAX_UPLOAD_SIZE = 100 * 1024 * 1024  # 100 MB

# Magic bytes for audio file validation
AUDIO_MAGIC = {
    ".mp3": [b"\xff\xfb", b"\xff\xf3", b"\xff\xf2", b"ID3"],
    ".flac": [b"fLaC"],
    ".wav": [b"RIFF"],
    ".ogg": [b"OggS"],
}


@app.route("/api/emergency-audio")
@require_auth
def api_emergency_audio_list():
    """List current emergency audio files."""
    files = []
    for ext in ALLOWED_AUDIO_EXTENSIONS:
        for f in globmod.glob(os.path.join(EMERGENCY_AUDIO_DIR, f"*{ext}")):
            stat = os.stat(f)
            files.append({
                "filename": os.path.basename(f),
                "size_bytes": stat.st_size,
                "size_mb": round(stat.st_size / (1024 * 1024), 2),
                "modified": int(stat.st_mtime),
            })
    return jsonify(sorted(files, key=lambda f: f["filename"]))


@app.route("/api/emergency-audio/upload", methods=["POST"])
@require_auth
def api_emergency_audio_upload():
    """Upload or replace an emergency audio file."""
    if "file" not in request.files:
        return jsonify({"error": "No file provided"}), 400

    file = request.files["file"]
    if not file.filename:
        return jsonify({"error": "No filename"}), 400

    ext = os.path.splitext(file.filename)[1].lower()
    if ext not in ALLOWED_AUDIO_EXTENSIONS:
        return jsonify({"error": f"Unsupported format. Allowed: {', '.join(ALLOWED_AUDIO_EXTENSIONS)}"}), 400

    # Check file size
    file.seek(0, 2)
    size = file.tell()
    file.seek(0)
    if size > MAX_UPLOAD_SIZE:
        return jsonify({"error": f"File too large. Max {MAX_UPLOAD_SIZE // (1024*1024)} MB"}), 400
    if size < 1024:
        return jsonify({"error": "File too small — doesn't look like valid audio"}), 400

    # Validate magic bytes
    header = file.read(4)
    file.seek(0)
    valid_magic = AUDIO_MAGIC.get(ext, [])
    if not any(header.startswith(m) for m in valid_magic):
        return jsonify({"error": "File content doesn't match audio format"}), 400

    # Save as fallback.<ext> (the name Liquidsoap expects)
    target = os.path.join(EMERGENCY_AUDIO_DIR, f"fallback{ext}")

    # Back up existing file
    if os.path.exists(target):
        backup = os.path.join(EMERGENCY_AUDIO_DIR, f"fallback{ext}.backup")
        shutil.copy2(target, backup)

    file.save(target)

    # Log the change
    alert = {
        "type": "emergency_audio_updated",
        "message": f"Emergency audio updated: {file.filename} ({os.path.getsize(target) / (1024*1024):.1f} MB)",
        "timestamp": int(time.time()),
    }
    alert_history.appendleft(alert)

    return jsonify({"ok": True, "filename": f"fallback{ext}", "size_bytes": os.path.getsize(target)})


@app.route("/api/emergency-audio/delete", methods=["POST"])
@require_auth
def api_emergency_audio_delete():
    """Delete an emergency audio file."""
    data = request.get_json() or {}
    filename = data.get("filename", "")

    if not filename or "/" in filename or "\\" in filename or ".." in filename:
        return jsonify({"error": "Invalid filename"}), 400

    ext = os.path.splitext(filename)[1].lower()
    if ext not in ALLOWED_AUDIO_EXTENSIONS:
        return jsonify({"error": "Invalid file type"}), 400

    filepath = os.path.join(EMERGENCY_AUDIO_DIR, filename)
    if not os.path.exists(filepath):
        return jsonify({"error": "File not found"}), 404

    os.remove(filepath)
    return jsonify({"ok": True})


# ============================================================
# Safe remote commands (whitelisted only)
# ============================================================

ALLOWED_SERVICES = {"icecast", "liquidsoap", "nginx", "analytics", "status-panel", "certbot"}

SAFE_COMMANDS = {
    "restart_service": {
        "label": "Restart a service",
        "build": lambda svc: ["docker", "restart", f"breezeradio-{svc}"],
        "requires_service": True,
    },
    "logs": {
        "label": "View recent logs",
        "build": lambda svc: ["docker", "logs", "--tail", "80", f"breezeradio-{svc}"],
        "requires_service": True,
    },
    "restart_stack": {
        "label": "Restart entire stack",
        "build": lambda _: ["docker", "compose", "restart"],
        "requires_service": False,
    },
    "renew_ssl": {
        "label": "Renew SSL certificate",
        "build": lambda _: ["docker", "compose", "run", "--rm", "--entrypoint", "",
                            "certbot", "certbot", "renew"],
        "requires_service": False,
    },
    "disk_usage": {
        "label": "Disk usage",
        "build": lambda _: ["docker", "system", "df"],
        "requires_service": False,
    },
    "icecast_stats": {
        "label": "Icecast raw stats",
        "build": lambda _: ["curl", "-s", f"{ICECAST_URL}/status-json.xsl",
                            "-u", f"{ICECAST_ADMIN_USER}:{ICECAST_ADMIN_PASSWORD}"],
        "requires_service": False,
    },
}


@app.route("/api/commands")
@require_auth
def api_commands_list():
    """List available safe commands."""
    cmds = []
    for key, info in SAFE_COMMANDS.items():
        cmds.append({
            "id": key,
            "label": info["label"],
            "requires_service": info["requires_service"],
        })
    return jsonify({
        "commands": cmds,
        "services": sorted(ALLOWED_SERVICES),
    })


@app.route("/api/commands/run", methods=["POST"])
@require_auth
def api_commands_run():
    """Execute a whitelisted command and return output."""
    data = request.get_json() or {}
    command_id = data.get("command", "")
    service = data.get("service", "")

    if command_id not in SAFE_COMMANDS:
        return jsonify({"error": f"Unknown command: {command_id}"}), 400

    cmd_info = SAFE_COMMANDS[command_id]

    if cmd_info["requires_service"]:
        if service not in ALLOWED_SERVICES:
            return jsonify({"error": f"Invalid service: {service}"}), 400

    try:
        cmd = cmd_info["build"](service)
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
        )
        output = result.stdout
        if result.stderr:
            output += ("\n" if output else "") + result.stderr

        return jsonify({
            "ok": result.returncode == 0,
            "output": output.strip() or "(no output)",
            "exit_code": result.returncode,
        })
    except subprocess.TimeoutExpired:
        return jsonify({"error": "Command timed out (30s)"}), 504
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ============================================================
# Main
# ============================================================

if __name__ == "__main__":
    port = int(os.getenv("STATUS_PANEL_PORT", "8080"))
    print(f"[status-panel] Starting on port {port}")
    print(f"[status-panel] Appwrite auth: {'enabled' if APPWRITE_ENDPOINT else 'disabled'}")
    app.run(host="0.0.0.0", port=port)
