import importlib.util
import io
import pathlib
import tempfile
import unittest
import unittest.mock as mock

import requests
from docker.errors import DockerException

SERVER_PATH = pathlib.Path(__file__).resolve().parents[1] / "server.py"
SPEC = importlib.util.spec_from_file_location("status_api_server", SERVER_PATH)
status_server = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(status_server)


class StatusApiSecurityTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)

        self.client = status_server.app.test_client()
        self.auth_headers = {"Authorization": "Bearer test-token"}

        self.original_audio_dir = status_server.EMERGENCY_AUDIO_DIR
        self.original_user = status_server.ICECAST_ADMIN_USER
        self.original_password = status_server.ICECAST_ADMIN_PASSWORD
        self.addCleanup(self.restore_globals)

        status_server.EMERGENCY_AUDIO_DIR = self.tempdir.name
        status_server.ICECAST_ADMIN_USER = "icecast-admin"
        status_server.ICECAST_ADMIN_PASSWORD = "secret-password"

    def restore_globals(self):
        status_server.EMERGENCY_AUDIO_DIR = self.original_audio_dir
        status_server.ICECAST_ADMIN_USER = self.original_user
        status_server.ICECAST_ADMIN_PASSWORD = self.original_password

    def auth_patch(self):
        return mock.patch.object(
            status_server,
            "get_appwrite_context",
            return_value={"user_id": "test-user", "roles": {"admin"}},
        )

    def test_emergency_audio_target_uses_canonical_filename(self):
        target = status_server.get_emergency_audio_target(".mp3")

        self.assertEqual(target, pathlib.Path(self.tempdir.name).resolve() / "fallback.mp3")

    def test_resolve_emergency_audio_file_rejects_path_traversal(self):
        with self.assertRaises(ValueError):
            status_server.resolve_emergency_audio_file("../fallback.mp3")

    def test_fetch_icecast_stats_requires_explicit_credentials(self):
        status_server.ICECAST_ADMIN_USER = ""
        status_server.ICECAST_ADMIN_PASSWORD = ""

        stats = status_server.fetch_icecast_stats()

        self.assertEqual(stats["error"], "Icecast admin credentials are not configured")

    def test_status_endpoint_hides_icecast_errors(self):
        with self.auth_patch(), mock.patch.object(
            status_server.requests,
            "get",
            side_effect=requests.RequestException("topsecret.internal"),
        ):
            response = self.client.get("/api/status", headers=self.auth_headers)

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json["error"], "Unable to fetch Icecast status")
        self.assertNotIn("topsecret.internal", response.get_data(as_text=True))

    def test_containers_endpoint_hides_docker_errors(self):
        with self.auth_patch(), mock.patch.object(
            status_server,
            "get_stack_containers",
            side_effect=DockerException("docker.sock unavailable"),
        ):
            response = self.client.get("/api/containers", headers=self.auth_headers)

        self.assertEqual(response.status_code, 502)
        self.assertEqual(response.json["error"], "Unable to fetch container status")
        self.assertNotIn("docker.sock", response.get_data(as_text=True))

    def test_commands_run_hides_backend_errors(self):
        commands = {
            "logs": {
                "label": "Logs",
                "requires_service": False,
                "run": mock.Mock(side_effect=DockerException("docker.sock unavailable")),
            }
        }

        with self.auth_patch(), mock.patch.object(
            status_server,
            "get_available_commands",
            return_value=commands,
        ):
            response = self.client.post(
                "/api/commands/run",
                json={"command": "logs"},
                headers=self.auth_headers,
            )

        self.assertEqual(response.status_code, 502)
        self.assertEqual(response.json["error"], "Command execution failed")
        self.assertNotIn("docker.sock", response.get_data(as_text=True))

    def test_upload_uses_canonical_storage_for_operator(self):
        existing_target = pathlib.Path(self.tempdir.name) / "fallback.mp3"
        existing_target.write_bytes(b"ID3" + (b"\x00" * 2048))

        upload = io.BytesIO(b"ID3" + (b"\x00" * 2048))

        with self.auth_patch():
            response = self.client.post(
                "/api/emergency-audio/upload",
                data={"file": (upload, "../../danger.mp3")},
                headers=self.auth_headers,
                content_type="multipart/form-data",
            )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(existing_target.exists())
        self.assertTrue((pathlib.Path(self.tempdir.name) / "fallback.mp3.backup").exists())
        self.assertFalse((pathlib.Path(self.tempdir.name) / "danger.mp3").exists())

    def test_delete_returns_404_when_file_disappears_before_unlink(self):
        target = pathlib.Path(self.tempdir.name) / "fallback.mp3"
        target.write_bytes(b"ID3" + (b"\x00" * 2048))

        with (
            self.auth_patch(),
            mock.patch.object(status_server, "resolve_emergency_audio_file", return_value=target),
            mock.patch.object(pathlib.Path, "unlink", side_effect=FileNotFoundError),
        ):
            response = self.client.post(
                "/api/emergency-audio/delete",
                json={"filename": "fallback.mp3"},
                headers=self.auth_headers,
            )

        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json, {"error": "File not found"})


if __name__ == "__main__":
    unittest.main()
