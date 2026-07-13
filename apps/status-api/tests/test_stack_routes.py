import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest
import unittest.mock as mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from stack.schema import load_defaults  # noqa: E402

SERVER_PATH = ROOT / "server.py"
SPEC = importlib.util.spec_from_file_location("status_api_server", SERVER_PATH)
status_server = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(status_server)


class StackRouteTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)

        self.client = status_server.app.test_client()
        self.auth_headers = {"Authorization": "Bearer test-token"}

        self.config_path = pathlib.Path(self.tempdir.name) / "stack.json"
        self.apply_path = pathlib.Path(self.tempdir.name) / "stack.apply.json"

        self.stack_store = sys.modules["stack.store"]
        self.stack_apply = sys.modules["stack.apply"]

        self.original_config_path = self.stack_store.STACK_CONFIG_PATH
        self.original_apply_path = self.stack_store.STACK_APPLY_STATUS_PATH
        self.addCleanup(self.restore_paths)

        self.stack_store.STACK_CONFIG_PATH = self.config_path
        self.stack_store.STACK_APPLY_STATUS_PATH = self.apply_path
        self.stack_store.STACK_CONFIG_BACKUP_PATH = self.config_path.with_suffix(".json.bak")

        defaults = load_defaults()
        self.config_path.write_text(json.dumps(defaults), encoding="utf-8")

    def restore_paths(self):
        self.stack_store.STACK_CONFIG_PATH = self.original_config_path
        self.stack_store.STACK_APPLY_STATUS_PATH = self.original_apply_path

    def auth_patch(self):
        return mock.patch.object(
            status_server,
            "get_appwrite_context",
            return_value={"user_id": "test-user", "roles": {"admin"}},
        )

    def viewer_patch(self):
        return mock.patch.object(
            status_server,
            "get_appwrite_context",
            return_value={"user_id": "test-user", "roles": {"member"}},
        )

    def test_schema_endpoint_requires_auth(self):
        response = self.client.get("/api/stack/schema")
        self.assertEqual(response.status_code, 401)

    def test_get_config_returns_defaults(self):
        with self.auth_patch():
            response = self.client.get("/api/stack/config", headers=self.auth_headers)
        self.assertEqual(response.status_code, 200)
        body = response.json
        self.assertEqual(body["config"]["version"], 1)
        self.assertEqual(len(body["config"]["outputs"]), 6)

    def test_put_config_requires_operator(self):
        config = load_defaults()
        with self.viewer_patch():
            response = self.client.put(
                "/api/stack/config",
                json={"config": config},
                headers=self.auth_headers,
            )
        self.assertEqual(response.status_code, 403)

    def test_patch_output_bitrate(self):
        with self.auth_patch():
            response = self.client.patch(
                "/api/stack/outputs/mp3-128",
                json={"bitrate": 160},
                headers=self.auth_headers,
            )
        self.assertEqual(response.status_code, 200)
        updated = response.json["config"]
        target = next(item for item in updated["outputs"] if item["id"] == "mp3-128")
        self.assertEqual(target["bitrate"], 160)

    def test_apply_triggers_reload(self):
        with self.auth_patch(), mock.patch.object(
            self.stack_apply,
            "trigger_reload",
        ) as trigger_reload, mock.patch.object(
            self.stack_apply,
            "wait_for_apply_completion",
            return_value={"state": "applied"},
        ):
            response = self.client.post(
                "/api/stack/apply",
                json={},
                headers=self.auth_headers,
            )

        self.assertEqual(response.status_code, 200)
        trigger_reload.assert_called_once()
        self.assertTrue(response.json["ok"])

    def test_health_reports_missing_mounts(self):
        with self.auth_patch(), mock.patch.object(
            status_server,
            "fetch_icecast_stats",
            return_value={"icestats": {"source": []}},
        ):
            response = self.client.get("/api/stack/health", headers=self.auth_headers)

        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.json["healthy"])
        self.assertTrue(response.json["missing_mounts"])


if __name__ == "__main__":
    unittest.main()
