"""Jinja2 rendering for stack config."""

import os
import re
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, select_autoescape

from stack.schema import _resolve_repo_root

_REPO_ROOT = _resolve_repo_root()


def _first_existing_path(*candidates):
    for candidate in candidates:
        if not candidate:
            continue
        path = Path(candidate)
        if path.exists():
            return path
    for candidate in reversed(candidates):
        if candidate:
            return Path(candidate)
    raise FileNotFoundError("No template directory candidates provided")


TEMPLATE_DIRS = {
    "liquidsoap": _first_existing_path(
        os.getenv("STACK_LIQUIDSOAP_TEMPLATE_DIR", ""),
        "/etc/liquidsoap",
        _REPO_ROOT / "services" / "streaming" / "liquidsoap",
    ),
    "icecast": _first_existing_path(
        os.getenv("STACK_ICECAST_TEMPLATE_DIR", ""),
        "/etc/icecast2",
        _REPO_ROOT / "services" / "streaming" / "icecast",
    ),
    "nginx": _first_existing_path(
        os.getenv("STACK_NGINX_TEMPLATE_DIR", ""),
        "/etc/nginx",
        _REPO_ROOT / "infrastructure" / "nginx",
    ),
}

OUTPUT_LABELS = {
    ("mp3", 128): ("MP3 (128kbps)", "Standard quality • Widely compatible"),
    ("mp3", 192): ("MP3 (192kbps)", "High quality • Widely compatible"),
    ("mp3", 320): ("MP3 (320kbps)", "High quality • Maximum compatibility"),
    ("fdkaac", 128): ("AAC (128kbps)", "Modern codec • Mobile optimized"),
    ("fdkaac", 192): ("AAC (192kbps)", "High quality • Mobile optimized"),
    ("vorbis", 128): ("Ogg Vorbis (128kbps)", "Open format • Linux friendly"),
}


def _create_env(template_dir):
    return Environment(
        loader=FileSystemLoader(str(template_dir)),
        autoescape=select_autoescape(default=False),
        trim_blocks=True,
        lstrip_blocks=True,
        keep_trailing_newline=True,
    )


def _output_cards(config):
    cards = []
    for output in config.get("outputs", []):
        if not output.get("enabled"):
            continue
        codec = output.get("codec")
        bitrate = output.get("bitrate")
        label, description = OUTPUT_LABELS.get(
            (codec, bitrate),
            (f"{codec.upper()} ({bitrate}kbps)", "Stream output"),
        )
        cards.append({
            **output,
            "label": label,
            "description": description,
        })
    return cards


def render_liquidsoap(config):
    env = _create_env(TEMPLATE_DIRS["liquidsoap"])
    template = env.get_template("radio.liq.j2")
    return template.render(
        ingests=config.get("ingests", []),
        outputs=config.get("outputs", []),
        hls=config.get("hls", {}),
        processing=config.get("processing", {}),
    )


def render_icecast(config):
    env = _create_env(TEMPLATE_DIRS["icecast"])
    template = env.get_template("icecast.xml.j2")
    return template.render(outputs=config.get("outputs", []))


def render_stream_cards(config):
    env = _create_env(TEMPLATE_DIRS["nginx"])
    template = env.get_template("index.streams.html.j2")
    return template.render(
        outputs=_output_cards(config),
        hls=config.get("hls", {}),
    )


def render_index_html(config, index_template_path, station_name, contact_email, hostname):
    """Render full landing page by replacing the streams section in index.html.template."""
    template_path = Path(index_template_path)
    base_html = template_path.read_text(encoding="utf-8")
    stream_cards = render_stream_cards(config)

    marker_start = '<div class="section-title">Available Streams</div>'
    marker_end = '<div class="contact-info">'

    start_idx = base_html.find(marker_start)
    end_idx = base_html.find(marker_end)
    if start_idx == -1 or end_idx == -1:
        raise ValueError("index.html.template is missing stream section markers")

    station_name_esc = _escape_html(station_name)
    contact_email_esc = _escape_html(contact_email)

    prefix = base_html[:start_idx]
    suffix = base_html[end_idx:]

    rendered = prefix + stream_cards + "\n        \n        " + suffix
    rendered = rendered.replace("${STATION_NAME_ESC}", station_name_esc)
    rendered = rendered.replace("${STATION_ADMIN_EMAIL_ESC}", contact_email_esc)
    rendered = rendered.replace("${ICECAST_HOSTNAME}", hostname)
    return rendered


def _escape_html(value):
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&#39;")
    )


def render_all(config, index_template_path=None, station_name=None, contact_email=None, hostname=None):
    """Render all stack config artifacts."""
    artifacts = {
        "radio.liq": render_liquidsoap(config),
        "icecast.xml": render_icecast(config),
    }

    if index_template_path:
        artifacts["index.html"] = render_index_html(
            config,
            index_template_path,
            station_name or os.getenv("STATION_NAME", "Radio Station"),
            contact_email or os.getenv("STATION_ADMIN_EMAIL", "admin@example.com"),
            hostname or os.getenv("ICECAST_HOSTNAME", "localhost"),
        )

    return artifacts


def normalize_whitespace(text):
    """Collapse runs of blank lines for stable snapshot comparison."""
    return re.sub(r"\n{3,}", "\n\n", text.strip()) + "\n"
