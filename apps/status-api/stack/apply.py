"""Apply stack config via supervised in-container reload."""

import os
import time
from pathlib import Path

import docker
from docker.errors import DockerException, NotFound

from stack.render import render_all
from stack.schema import validate_stack_config
from stack.store import read_apply_status, read_config, strip_metadata, write_apply_status

APP_CONTAINER_NAME = os.getenv("STACK_APP_CONTAINER", "sonicverse-app")
RELOAD_MARKER_PATH = Path(os.getenv("STACK_RELOAD_MARKER_PATH", "/run/sonicverse/reload-request"))
APPLY_TIMEOUT_S = int(os.getenv("STACK_APPLY_TIMEOUT_S", "120"))

LIQUIDSOAP_OUTPUT = Path(os.getenv("STACK_LIQUIDSOAP_OUTPUT", "/etc/liquidsoap/radio.liq"))
ICECAST_TEMPLATE_OUTPUT = Path(
    os.getenv("STACK_ICECAST_TEMPLATE_OUTPUT", "/etc/icecast2/icecast.xml.template")
)
INDEX_TEMPLATE_PATH = Path(
    os.getenv("STACK_INDEX_TEMPLATE_PATH", "/etc/nginx/index.html.template")
)
INDEX_OUTPUT = Path(os.getenv("STACK_INDEX_OUTPUT", "/usr/share/nginx/html/index.html"))


def _get_docker_client():
    return docker.from_env()


def _running_in_app_container():
    return Path("/.dockerenv").exists() and Path("/usr/local/bin/sonicverse-entrypoint").exists()


def _write_reload_marker():
    RELOAD_MARKER_PATH.parent.mkdir(parents=True, exist_ok=True)
    RELOAD_MARKER_PATH.write_text(str(int(time.time())), encoding="utf-8")


def _trigger_reload_external():
    client = _get_docker_client()
    container = client.containers.get(APP_CONTAINER_NAME)
    exit_code, output = container.exec_run(
        ["/usr/local/bin/request-streaming-reload.sh"],
        demux=True,
    )
    stdout = (output[0] or b"").decode("utf-8", errors="replace").strip()
    stderr = (output[1] or b"").decode("utf-8", errors="replace").strip()
    if exit_code != 0:
        message = stderr or stdout or "reload request failed"
        raise RuntimeError(message)


def trigger_reload():
    if _running_in_app_container():
        _write_reload_marker()
        return
    _trigger_reload_external()


def pre_render_config(config):
    """Render config artifacts to disk (used by entrypoint render script)."""
    station_name = os.getenv("STATION_NAME", "Radio Station")
    contact_email = os.getenv("STATION_ADMIN_EMAIL", "admin@example.com")
    hostname = os.getenv("ICECAST_HOSTNAME", "localhost")

    artifacts = render_all(
        config,
        index_template_path=str(INDEX_TEMPLATE_PATH) if INDEX_TEMPLATE_PATH.exists() else None,
        station_name=station_name,
        contact_email=contact_email,
        hostname=hostname,
    )

    LIQUIDSOAP_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    LIQUIDSOAP_OUTPUT.write_text(artifacts["radio.liq"], encoding="utf-8")

    ICECAST_TEMPLATE_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    ICECAST_TEMPLATE_OUTPUT.write_text(artifacts["icecast.xml"], encoding="utf-8")

    if "index.html" in artifacts:
        INDEX_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        INDEX_OUTPUT.write_text(artifacts["index.html"], encoding="utf-8")

    return artifacts


def apply_config(config=None):
    """Validate config and request supervised reload in the app container."""
    config = config or read_config()
    errors = validate_stack_config(strip_metadata(config))
    if errors:
        raise ValueError("; ".join(errors))

    write_apply_status({"state": "validating"})
    try:
        write_apply_status({"state": "applying"})
        trigger_reload()
        final_status = wait_for_apply_completion()
        if final_status.get("state") == "failed":
            raise RuntimeError(final_status.get("error", "apply failed"))
        return final_status
    except (DockerException, NotFound, RuntimeError, ValueError, OSError) as exc:
        write_apply_status({
            "state": "failed",
            "error": str(exc),
        })
        raise


def wait_for_apply_completion(timeout_s=None):
    timeout_s = timeout_s or APPLY_TIMEOUT_S
    deadline = time.time() + timeout_s
    last_state = "idle"

    while time.time() < deadline:
        status = read_apply_status()
        last_state = status.get("state", "idle")
        if last_state in {"applied", "failed"}:
            return status
        time.sleep(1)

    return {
        "state": "failed",
        "error": f"Apply timed out after {timeout_s}s (last state: {last_state})",
    }
