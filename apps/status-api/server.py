"""
Sonicverse Status Panel — API backend

Serves an optional real-time dashboard showing stream health, listener
counts, source status, alert history, configuration, and container status.
Can be protected by Appwrite authentication.
"""

import functools
import ipaddress
import json
import os
import shutil
import socket
import time
from collections import deque
from pathlib import Path

import docker
import requests
from docker.errors import DockerException, NotFound
from flask import Flask, Response, g, jsonify, request
from flask_cors import CORS
from werkzeug.exceptions import RequestEntityTooLarge

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 1024 * 1024 * 1024  # 1 GiB upload limit

# CORS — set STATUS_PANEL_CORS_ORIGIN only when you expose the dashboard frontend.
def get_cors_origins():
    raw_origins = os.getenv("STATUS_PANEL_CORS_ORIGIN", "")
    origins = {origin.strip() for origin in raw_origins.split(",") if origin.strip()}
    return sorted(origins)


CORS(app, resources={r"/api/*": {"origins": get_cors_origins()}}, supports_credentials=False)

# Configuration
ICECAST_URL = os.getenv("ICECAST_URL", "http://icecast:8000")
ICECAST_ADMIN_USER = os.getenv("ICECAST_ADMIN_USER", "").strip()
ICECAST_ADMIN_PASSWORD = os.getenv("ICECAST_ADMIN_PASSWORD", "").strip()
STATION_NAME = os.getenv("STATION_NAME", "Radio Station")

# Appwrite auth
APPWRITE_ENDPOINT = os.getenv("APPWRITE_ENDPOINT", "")
APPWRITE_PROJECT_ID = os.getenv("APPWRITE_PROJECT_ID", "")
APPWRITE_TEAM_ID = os.getenv("APPWRITE_TEAM_ID", "")
APPWRITE_AUTH_CONFIGURED = bool(APPWRITE_ENDPOINT and APPWRITE_PROJECT_ID and APPWRITE_TEAM_ID)
WRITE_ROLES = {
    role.strip()
    for role in os.getenv("STATUS_PANEL_WRITE_ROLES", "owner,admin").split(",")
    if role.strip()
}
if not WRITE_ROLES:
    WRITE_ROLES = {"owner", "admin"}
ALLOW_RISKY_COMMANDS = os.getenv("STATUS_PANEL_ALLOW_RISKY_COMMANDS", "0") == "1"

# Alert history (last 50 events, in-memory)
alert_history = deque(maxlen=50)


def get_bearer_jwt():
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        return auth_header[7:]
    return None


def extract_list_items(payload):
    if isinstance(payload, list):
        return payload

    if isinstance(payload, dict):
        for key in ("memberships", "documents", "users", "teams", "data", "items"):
            value = payload.get(key)
            if isinstance(value, list):
                return value

    return []


def get_appwrite_context(jwt):
    """Verify an Appwrite JWT and collect team roles for the current user."""
    if not APPWRITE_AUTH_CONFIGURED:
        return None

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
            return None

        account_data = resp.json()
        user_id = account_data.get("$id") or account_data.get("id")
        if not user_id:
            return None

        teams_resp = requests.get(
            f"{APPWRITE_ENDPOINT}/teams/{APPWRITE_TEAM_ID}/memberships",
            headers=headers,
            timeout=5,
        )
        if teams_resp.status_code != 200:
            return None

        memberships = extract_list_items(teams_resp.json())
        roles = set()
        for membership in memberships:
            if not isinstance(membership, dict):
                continue
            if membership.get("userId") != user_id:
                continue

            membership_roles = membership.get("roles") or []
            if isinstance(membership_roles, list):
                roles.update(str(role) for role in membership_roles if role)
            break

        if not roles:
            return None

        return {
            "user_id": user_id,
            "roles": roles,
        }
    except Exception:
        return None


def verify_appwrite_session(jwt):
    return get_appwrite_context(jwt) is not None


def get_request_appwrite_context():
    context = getattr(g, "appwrite_context", None)
    if context is not None:
        return context

    jwt = get_bearer_jwt()
    if not jwt:
        return None

    context = get_appwrite_context(jwt)
    g.appwrite_context = context
    return context


def has_operator_access(context):
    if not context:
        return False

    return bool(context.get("roles", set()) & WRITE_ROLES)


def get_originating_ip():
    # Nginx appends the real client IP to X-Forwarded-For via $proxy_add_x_forwarded_for.
    xff = request.headers.get("X-Forwarded-For", "")
    if xff:
        parts = [part.strip() for part in xff.split(",") if part.strip()]
        if parts:
            return parts[-1]
    return request.remote_addr or ""


def is_private_or_loopback_ip(ip_addr):
    try:
        parsed = ipaddress.ip_address(ip_addr)
    except ValueError:
        return False
    return parsed.is_private or parsed.is_loopback


def get_bind_host():
    configured_host = os.getenv("STATUS_PANEL_HOST", "").strip() or os.getenv(
        "STATUS_PANEL_BIND_HOST",
        "",
    ).strip()
    if configured_host:
        return configured_host

    if os.path.exists("/.dockerenv"):
        try:
            return socket.gethostbyname(socket.gethostname())
        except socket.gaierror:
            pass

    return "127.0.0.1"


def require_auth(f):
    @functools.wraps(f)
    def decorated(*args, **kwargs):
        jwt = get_bearer_jwt()
        if jwt:
            context = get_appwrite_context(jwt)
            if context is not None:
                g.appwrite_context = context
                return f(*args, **kwargs)

        return Response(
            json.dumps({"error": "Authentication required"}),
            401,
            {"Content-Type": "application/json"},
        )
    return decorated


def require_operator(f):
    @functools.wraps(f)
    def decorated(*args, **kwargs):
        jwt = get_bearer_jwt()
        if not jwt:
            return Response(
                json.dumps({"error": "Authentication required"}),
                401,
                {"Content-Type": "application/json"},
            )

        context = get_appwrite_context(jwt)
        if context is not None and has_operator_access(context):
            g.appwrite_context = context
            return f(*args, **kwargs)

        if context is None:
            return Response(
                json.dumps({"error": "Authentication required"}),
                401,
                {"Content-Type": "application/json"},
            )

        return Response(
            json.dumps({"error": "Operator access required"}),
            403,
            {"Content-Type": "application/json"},
        )
    return decorated


@app.errorhandler(RequestEntityTooLarge)
def handle_request_too_large(_error):
    return jsonify({
        "error": "File too large",
        "max_bytes": app.config["MAX_CONTENT_LENGTH"],
    }), 413


# ============================================================
# Icecast stats
# ============================================================

def fetch_icecast_stats():
    try:
        resp = requests.get(
            f"{ICECAST_URL}/status-json.xsl",
            auth=get_icecast_auth(),
            timeout=5,
        )
        resp.raise_for_status()
        return resp.json()
    except RuntimeError as e:
        app.logger.warning("Icecast credentials unavailable: %s", e)
        return {"error": "Icecast admin credentials are not configured"}
    except Exception as e:
        app.logger.warning("Failed to fetch Icecast status: %s", e)
        return {"error": "Unable to fetch Icecast status"}


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
    if request.headers.get("X-Internal-Alert") == "1":
        trusted_proxy = True
    else:
        trusted_proxy = is_private_or_loopback_ip(get_originating_ip())

    if not trusted_proxy:
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
    context = get_request_appwrite_context()
    can_manage_emergency_audio = has_operator_access(context)
    can_run_risky_commands = can_manage_emergency_audio and ALLOW_RISKY_COMMANDS
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
        "can_manage_emergency_audio": can_manage_emergency_audio,
        "can_run_risky_commands": can_run_risky_commands,
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
        containers = [
            {
                "name": container.name,
                "status": format_container_status(container),
                "image": format_container_image(container),
                "ports": format_container_ports(container),
            }
            for container in get_stack_containers()
        ]
        return jsonify(containers)
    except DockerException as e:
        app.logger.warning("Failed to fetch container status: %s", e)
        return jsonify({"error": "Unable to fetch container status"}), 502


# ============================================================
# Emergency audio management
# ============================================================

EMERGENCY_AUDIO_DIR = os.getenv("EMERGENCY_AUDIO_DIR", "/emergency-audio")
ALLOWED_AUDIO_EXTENSIONS = {".mp3", ".flac", ".wav", ".ogg"}
MAX_UPLOAD_SIZE = 1024 * 1024 * 1024  # 1 GiB

# Magic bytes for audio file validation
AUDIO_MAGIC = {
    ".mp3": [b"\xff\xfb", b"\xff\xf3", b"\xff\xf2", b"ID3"],
    ".flac": [b"fLaC"],
    ".wav": [b"RIFF"],
    ".ogg": [b"OggS"],
}

EMERGENCY_AUDIO_FILENAMES = {ext: f"fallback{ext}" for ext in ALLOWED_AUDIO_EXTENSIONS}


def get_icecast_auth():
    if not ICECAST_ADMIN_USER or not ICECAST_ADMIN_PASSWORD:
        raise RuntimeError("Icecast admin credentials are not configured")

    return (ICECAST_ADMIN_USER, ICECAST_ADMIN_PASSWORD)


def get_emergency_audio_dir():
    return Path(EMERGENCY_AUDIO_DIR).resolve()


def get_emergency_audio_target(ext):
    if ext not in ALLOWED_AUDIO_EXTENSIONS:
        raise ValueError("Invalid file type")

    return get_emergency_audio_dir() / EMERGENCY_AUDIO_FILENAMES[ext]


def iter_emergency_audio_files():
    for ext in sorted(ALLOWED_AUDIO_EXTENSIONS):
        target = get_emergency_audio_target(ext)
        if target.exists():
            yield target


def resolve_emergency_audio_file(filename):
    if not filename or os.path.basename(filename) != filename:
        raise ValueError("Invalid filename")

    ext = Path(filename).suffix.lower()
    if ext not in ALLOWED_AUDIO_EXTENSIONS:
        raise ValueError("Invalid file type")

    for target in iter_emergency_audio_files():
        if target.name == filename:
            return target

    raise FileNotFoundError(filename)


@app.route("/api/emergency-audio")
@require_auth
def api_emergency_audio_list():
    """List current emergency audio files."""
    files = []
    for emergency_file in iter_emergency_audio_files():
        stat = emergency_file.stat()
        files.append({
            "filename": emergency_file.name,
            "size_bytes": stat.st_size,
            "size_mb": round(stat.st_size / (1024 * 1024), 2),
            "modified": int(stat.st_mtime),
        })
    return jsonify(sorted(files, key=lambda f: f["filename"]))


@app.route("/api/emergency-audio/upload", methods=["POST"])
@require_operator
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
    target = get_emergency_audio_target(ext)

    # Back up existing file
    if target.exists():
        backup = target.with_name(f"{target.name}.backup")
        shutil.copy2(target, backup)

    file.save(str(target))

    # Log the change
    alert = {
        "type": "emergency_audio_updated",
        "message": f"Emergency audio updated: {file.filename} ({target.stat().st_size / (1024*1024):.1f} MB)",
        "timestamp": int(time.time()),
    }
    alert_history.appendleft(alert)

    return jsonify({"ok": True, "filename": target.name, "size_bytes": target.stat().st_size})


@app.route("/api/emergency-audio/delete", methods=["POST"])
@require_operator
def api_emergency_audio_delete():
    """Delete an emergency audio file."""
    data = request.get_json() or {}
    filename = data.get("filename", "")

    try:
        filepath = resolve_emergency_audio_file(filename)
    except ValueError as e:
        app.logger.warning("Invalid emergency audio delete request: %s", e)
        return jsonify({"error": "Invalid filename"}), 400
    except FileNotFoundError:
        return jsonify({"error": "File not found"}), 404

    filepath.unlink()
    return jsonify({"ok": True})


# ============================================================
# Safe remote commands (whitelisted only)
# ============================================================

ALLOWED_SERVICES = {"icecast", "liquidsoap", "nginx", "analytics", "status-api", "certbot"}

@functools.lru_cache(maxsize=1)
def get_docker_client():
    return docker.from_env()


def get_stack_containers():
    containers = get_docker_client().containers.list(all=True, filters={"name": "sonicverse-"})
    return sorted(containers, key=lambda container: container.name)


def get_service_container(service):
    return get_docker_client().containers.get(f"sonicverse-{service}")


def format_container_status(container):
    state = container.attrs.get("State", {})
    status = state.get("Status", container.status)
    if status == "running":
        health = state.get("Health", {}).get("Status")
        if health and health != "healthy":
            return f"Up ({health})"
        return "Up"
    if status == "exited":
        exit_code = state.get("ExitCode")
        if exit_code is not None:
            return f"Exited ({exit_code})"
        return "Exited"
    return status.replace("_", " ").title()


def format_container_image(container):
    tags = container.image.tags
    if tags:
        return tags[0]
    return container.image.short_id


def format_container_ports(container):
    ports = container.attrs.get("NetworkSettings", {}).get("Ports") or {}
    formatted = []
    for container_port, bindings in ports.items():
        if not bindings:
            formatted.append(container_port)
            continue
        for binding in bindings:
            host_ip = binding.get("HostIp") or ""
            host_port = binding.get("HostPort") or ""
            host_binding = f"{host_ip}:{host_port}" if host_ip else host_port
            if host_binding:
                formatted.append(f"{host_binding}->{container_port}")
            else:
                formatted.append(container_port)
    return ", ".join(formatted)


def format_bytes(size_bytes):
    size = float(size_bytes or 0)
    units = ["B", "KiB", "MiB", "GiB", "TiB"]
    for unit in units:
        if size < 1024 or unit == units[-1]:
            if unit == "B":
                return f"{int(size)} {unit}"
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} TiB"


def run_logs(service):
    output = get_service_container(service).logs(tail=80, stdout=True, stderr=True)
    return output.decode("utf-8", errors="replace").strip() or "(no output)", 0


def run_disk_usage(_):
    df = get_docker_client().api.df()
    images = df.get("Images", [])
    containers = df.get("Containers", [])
    volumes = df.get("Volumes", [])
    build_cache = df.get("BuildCache", [])

    lines = [
        f"Images: {len(images)} total, {sum(1 for image in images if image.get('Containers'))} in use",
        f"Containers: {len(containers)} total, {sum(1 for item in containers if item.get('State') == 'running')} running",
        f"Volumes: {len(volumes)} total",
        f"Build cache entries: {len(build_cache)}",
        f"Image layers size: {format_bytes(df.get('LayersSize', 0))}",
        f"Volumes size: {format_bytes(sum(volume.get('UsageData', {}).get('Size', 0) for volume in volumes))}",
        f"Build cache size: {format_bytes(sum(item.get('Size', 0) for item in build_cache))}",
    ]
    return "\n".join(lines), 0


def run_icecast_stats(_):
    response = requests.get(
        f"{ICECAST_URL}/status-json.xsl",
        auth=get_icecast_auth(),
        timeout=10,
    )
    response.raise_for_status()
    return response.text.strip() or "(no output)", 0


def run_restart_service(service):
    container = get_service_container(service)
    container.restart(timeout=10)
    return f"Restarted {container.name}", 0


def run_restart_stack(_):
    containers = [container for container in get_stack_containers() if container.status == "running"]
    containers.sort(key=lambda container: container.name == "sonicverse-status-api")
    restarted = []
    for container in containers:
        container.restart(timeout=10)
        restarted.append(container.name)
    return f"Restarted {', '.join(restarted)}", 0


def run_renew_ssl(_):
    exit_code, output = get_service_container("certbot").exec_run(["certbot", "renew"])
    return output.decode("utf-8", errors="replace").strip() or "(no output)", exit_code


READONLY_COMMANDS = {
    "logs": {
        "label": "View recent logs",
        "run": run_logs,
        "requires_service": True,
    },
    "disk_usage": {
        "label": "Disk usage",
        "run": run_disk_usage,
        "requires_service": False,
    },
    "icecast_stats": {
        "label": "Icecast raw stats",
        "run": run_icecast_stats,
        "requires_service": False,
    },
}

RISKY_COMMANDS = {
    "restart_service": {
        "label": "Restart a service",
        "run": run_restart_service,
        "requires_service": True,
    },
    "restart_stack": {
        "label": "Restart entire stack",
        "run": run_restart_stack,
        "requires_service": False,
    },
    "renew_ssl": {
        "label": "Renew SSL certificate",
        "run": run_renew_ssl,
        "requires_service": False,
    },
}


def get_available_commands():
    commands = dict(READONLY_COMMANDS)
    if ALLOW_RISKY_COMMANDS:
        commands.update(RISKY_COMMANDS)
    return commands


@app.route("/api/commands")
@require_auth
def api_commands_list():
    """List available safe commands."""
    cmds = []
    for key, info in get_available_commands().items():
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

    commands = get_available_commands()

    if command_id not in commands:
        return jsonify({"error": f"Unknown command: {command_id}"}), 400

    cmd_info = commands[command_id]

    if command_id in RISKY_COMMANDS and not has_operator_access(get_request_appwrite_context()):
        return jsonify({"error": "Operator access required"}), 403

    if cmd_info["requires_service"]:
        if service not in ALLOWED_SERVICES:
            return jsonify({"error": f"Invalid service: {service}"}), 400

    try:
        output, exit_code = cmd_info["run"](service)
        return jsonify({
            "ok": exit_code == 0,
            "output": output.strip() or "(no output)",
            "exit_code": exit_code,
        })
    except requests.Timeout:
        return jsonify({"error": "Command timed out"}), 504
    except NotFound as e:
        app.logger.info("Command target not found for %s (%s): %s", command_id, service, e)
        return jsonify({"error": "Requested resource not found"}), 404
    except (DockerException, requests.RequestException, RuntimeError) as e:
        app.logger.warning("Command execution failed for %s (%s): %s", command_id, service, e)
        return jsonify({"error": "Command execution failed"}), 502
    except Exception:
        app.logger.exception("Unexpected command execution failure for %s (%s)", command_id, service)
        return jsonify({"error": "Unexpected command failure"}), 500


# ============================================================
# Main
# ============================================================

if __name__ == "__main__":
    bind_host = get_bind_host()
    port = int(os.getenv("STATUS_PANEL_PORT", "8080"))
    print(f"[status-api] Starting on {bind_host}:{port}")
    if APPWRITE_PROJECT_ID and not APPWRITE_AUTH_CONFIGURED:
        print("[status-api] Appwrite auth: disabled (set APPWRITE_TEAM_ID to enable access)")
    else:
        print(f"[status-api] Appwrite auth: {'enabled' if APPWRITE_AUTH_CONFIGURED else 'disabled'}")
    app.run(host=bind_host, port=port)
