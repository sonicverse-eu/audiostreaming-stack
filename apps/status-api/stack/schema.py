"""Stack config validation."""

import json
import os
import re
from pathlib import Path

from jsonschema import Draft202012Validator

MOUNT_PATTERN = re.compile(r"^/[a-z0-9-]+$")
ICECAST_CODECS = {"mp3", "fdkaac", "vorbis"}


def _resolve_repo_root():
    env_root = os.getenv("STACK_REPO_ROOT")
    if env_root:
        return Path(env_root)

    candidate = Path(__file__).resolve().parents[3]
    if (candidate / "config" / "stack.defaults.json").exists():
        return candidate

    return Path("/opt/sonicverse")


_REPO_ROOT = _resolve_repo_root()
SCHEMA_PATH = Path(os.getenv("STACK_SCHEMA_PATH", _REPO_ROOT / "config" / "stack.schema.json"))
DEFAULTS_PATH = Path(os.getenv("STACK_DEFAULTS_PATH", _REPO_ROOT / "config" / "stack.defaults.json"))


def get_allowed_ingest_ports():
    raw = os.getenv("STACK_ALLOWED_INGEST_PORTS", "8010,8011")
    ports = set()
    for part in raw.split(","):
        part = part.strip()
        if part.isdigit():
            ports.add(int(part))
    return ports or {8010, 8011}


def load_schema():
    with SCHEMA_PATH.open(encoding="utf-8") as handle:
        return json.load(handle)


def load_defaults():
    with DEFAULTS_PATH.open(encoding="utf-8") as handle:
        return json.load(handle)


def _validate_unique(values, field_name, errors):
    seen = set()
    for value in values:
        if value in seen:
            errors.append(f"Duplicate {field_name}: {value}")
        seen.add(value)


def _format_schema_error(error):
    path = ".".join(str(part) for part in error.absolute_path)
    location = path or "config"
    return f"{location}: {error.message}"


def _validate_against_schema(config, errors):
    validator = Draft202012Validator(load_schema())
    for error in sorted(validator.iter_errors(config), key=lambda item: list(item.absolute_path)):
        errors.append(_format_schema_error(error))


def validate_stack_config(config, allowed_ports=None):
    """Validate stack config against schema and business rules."""
    errors = []

    if not isinstance(config, dict):
        return ["Config must be a JSON object"]

    _validate_against_schema(config, errors)

    if errors:
        return errors

    ingests = config["ingests"]
    outputs = config["outputs"]
    hls = config["hls"]
    processing = config["processing"]

    allowed_ports = allowed_ports or get_allowed_ingest_ports()

    enabled_ingests = [item for item in ingests if item.get("enabled")]
    if not enabled_ingests:
        errors.append("At least one ingest must be enabled")

    _validate_unique([item.get("id") for item in ingests], "ingest id", errors)
    _validate_unique([item.get("port") for item in ingests], "ingest port", errors)

    for ingest in ingests:
        port = ingest.get("port")
        if port not in allowed_ports:
            errors.append(
                f"Ingest {ingest.get('id')}: port {port} not in allowed ports "
                f"({', '.join(str(p) for p in sorted(allowed_ports))})"
            )

    enabled_outputs = [item for item in outputs if item.get("enabled")]
    enabled_hls = hls.get("enabled") and hls.get("variants")
    if not enabled_outputs and not enabled_hls:
        errors.append("At least one Icecast output or HLS variant must be enabled")

    _validate_unique([item.get("id") for item in outputs], "output id", errors)
    _validate_unique([item.get("mount") for item in outputs if item.get("enabled")], "mount", errors)

    if hls.get("enabled"):
        _validate_unique([item.get("id") for item in hls.get("variants", [])], "HLS variant id", errors)

    for key in ("crossfade_seconds", "buffer_seconds", "max_buffer_seconds"):
        if key not in processing:
            errors.append(f"Missing processing field: {key}")

    return errors


def get_schema_response():
    """Return schema metadata for API consumers."""
    return {
        "version": 1,
        "icecast_codecs": sorted(ICECAST_CODECS),
        "allowed_ingest_ports": sorted(get_allowed_ingest_ports()),
        "mount_pattern": MOUNT_PATTERN.pattern,
        "schema": load_schema(),
    }
