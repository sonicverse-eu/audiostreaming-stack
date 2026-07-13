import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from stack.render import normalize_whitespace, render_icecast, render_liquidsoap  # noqa: E402
from stack.schema import load_defaults, validate_stack_config  # noqa: E402


class StackSchemaTests(unittest.TestCase):
    def test_defaults_are_valid(self):
        config = load_defaults()
        errors = validate_stack_config(config)
        self.assertEqual(errors, [])

    def test_rejects_duplicate_mounts(self):
        config = load_defaults()
        config["outputs"].append({
            "id": "dup",
            "type": "icecast",
            "mount": "/stream-mp3-128",
            "codec": "mp3",
            "bitrate": 64,
            "samplerate": 44100,
            "channels": 2,
            "enabled": True,
        })
        errors = validate_stack_config(config)
        self.assertTrue(any("Duplicate mount" in error for error in errors))

    def test_rejects_disallowed_ingest_port(self):
        config = load_defaults()
        config["ingests"].append({
            "id": "extra",
            "type": "harbor",
            "port": 9999,
            "priority": 3,
            "enabled": True,
        })
        errors = validate_stack_config(config, allowed_ports={8010, 8011})
        self.assertTrue(any("not in allowed ports" in error for error in errors))

    def test_rejects_all_disabled_ingests(self):
        config = load_defaults()
        for ingest in config["ingests"]:
            ingest["enabled"] = False
        errors = validate_stack_config(config)
        self.assertIn("At least one ingest must be enabled", errors)


class StackRenderTests(unittest.TestCase):
    def setUp(self):
        self.config = load_defaults()
        repo_root = pathlib.Path(__file__).resolve().parents[3]
        self.radio_liq = (repo_root / "services/streaming/liquidsoap/radio.liq").read_text(
            encoding="utf-8"
        )
        self.icecast_xml = (repo_root / "services/streaming/icecast/icecast.xml").read_text(
            encoding="utf-8"
        )

    def test_liquidsoap_renders_all_mounts(self):
        rendered = render_liquidsoap(self.config)
        for mount in (
            "/stream-mp3-128",
            "/stream-mp3-192",
            "/stream-mp3-320",
            "/stream-aac-128",
            "/stream-aac-192",
            "/stream-ogg-128",
        ):
            self.assertIn(f'mount="{mount}"', rendered)

    def test_liquidsoap_renders_harbor_ports(self):
        rendered = render_liquidsoap(self.config)
        self.assertIn("port=8010", rendered)
        self.assertIn("port=8011", rendered)

    def test_icecast_renders_all_mounts(self):
        rendered = render_icecast(self.config)
        for mount in (
            "/stream-mp3-128",
            "/stream-mp3-192",
            "/stream-mp3-320",
            "/stream-aac-128",
            "/stream-aac-192",
            "/stream-ogg-128",
        ):
            self.assertIn(f"<mount-name>{mount}</mount-name>", rendered)

    def test_liquidsoap_matches_static_structure(self):
        rendered = normalize_whitespace(render_liquidsoap(self.config))
        static = normalize_whitespace(self.radio_liq)
        for marker in (
            "output.icecast(",
            "output.file.hls(",
            "input.harbor(",
            "blank.detect(",
        ):
            self.assertIn(marker, rendered)
            self.assertIn(marker, static)


if __name__ == "__main__":
    unittest.main()
