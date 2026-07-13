"""Persistent stack config store."""

import json
import os
import shutil
import time
from pathlib import Path

from stack.schema import load_defaults, validate_stack_config

STACK_CONFIG_PATH = Path(os.getenv("STACK_CONFIG_PATH", "/etc/sonicverse/stack.json"))
STACK_APPLY_STATUS_PATH = Path(
    os.getenv("STACK_APPLY_STATUS_PATH", "/etc/sonicverse/stack.apply.json")
)
STACK_CONFIG_BACKUP_PATH = STACK_CONFIG_PATH.with_suffix(".json.bak")


def _ensure_parent(path):
    path.parent.mkdir(parents=True, exist_ok=True)


def read_config():
    if not STACK_CONFIG_PATH.exists():
        return load_defaults()
    with STACK_CONFIG_PATH.open(encoding="utf-8") as handle:
        return json.load(handle)


def strip_metadata(config):
    cleaned = dict(config)
    cleaned.pop("updated_at", None)
    return cleaned


def write_config(config, backup=True):
    cleaned = strip_metadata(config)
    errors = validate_stack_config(cleaned)
    if errors:
        raise ValueError("; ".join(errors))

    _ensure_parent(STACK_CONFIG_PATH)

    if backup and STACK_CONFIG_PATH.exists():
        shutil.copy2(STACK_CONFIG_PATH, STACK_CONFIG_BACKUP_PATH)

    temp_path = STACK_CONFIG_PATH.with_suffix(".json.tmp")
    payload = {
        **cleaned,
        "updated_at": int(time.time()),
    }
    with temp_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")
    temp_path.replace(STACK_CONFIG_PATH)
    return payload


def seed_defaults_if_missing():
    if STACK_CONFIG_PATH.exists():
        return False
    defaults = load_defaults()
    write_config(defaults, backup=False)
    return True


def get_config_metadata():
    config = read_config()
    metadata = {
        "version": config.get("version", 1),
        "updated_at": config.get("updated_at"),
    }
    if STACK_CONFIG_PATH.exists():
        metadata["path"] = str(STACK_CONFIG_PATH)
        metadata["exists"] = True
    else:
        metadata["exists"] = False
    return config, metadata


def read_apply_status():
    if not STACK_APPLY_STATUS_PATH.exists():
        return {"state": "idle"}
    with STACK_APPLY_STATUS_PATH.open(encoding="utf-8") as handle:
        return json.load(handle)


def write_apply_status(status):
    _ensure_parent(STACK_APPLY_STATUS_PATH)
    temp_path = STACK_APPLY_STATUS_PATH.with_suffix(".json.tmp")
    payload = {
        **status,
        "updated_at": int(time.time()),
    }
    with temp_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")
    temp_path.replace(STACK_APPLY_STATUS_PATH)
    return payload
