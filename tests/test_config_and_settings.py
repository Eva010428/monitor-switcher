import json
import tempfile
import unittest
from pathlib import Path

from monitor_hub.net import bind_host
from monitor_hub.server.app import create_app


class BindHostTest(unittest.TestCase):
    def test_lan_host_binds_all_interfaces_so_localhost_still_works(self):
        self.assertEqual(bind_host("192.168.50.245"), "0.0.0.0")

    def test_localhost_host_stays_localhost_only(self):
        self.assertEqual(bind_host("127.0.0.1"), "127.0.0.1")


class SystemEndpointSecurityTest(unittest.TestCase):
    def make_client(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        sources_path = Path(self.tmp.name) / "sources.json"
        config_path = Path(self.tmp.name) / "config.json"
        sources_path.write_text(json.dumps({"sources": []}))
        config_path.write_text("{}")
        app = create_app({"host": "0.0.0.0", "port": 5000}, sources_path, config_path)
        return app.test_client()

    def test_process_control_rejects_lan_callers(self):
        client = self.make_client()

        response = client.post(
            "/api/system/quit",
            environ_base={"REMOTE_ADDR": "192.168.50.10"},
        )

        self.assertEqual(response.status_code, 403)

    def test_settings_marks_localhost_requests_as_local(self):
        client = self.make_client()

        response = client.get(
            "/api/settings",
            environ_base={"REMOTE_ADDR": "127.0.0.1"},
        )

        self.assertTrue(response.get_json()["local_request"])

    def test_settings_marks_lan_requests_as_remote(self):
        client = self.make_client()

        response = client.get(
            "/api/settings",
            environ_base={"REMOTE_ADDR": "192.168.50.245"},
        )

        self.assertFalse(response.get_json()["local_request"])


if __name__ == "__main__":
    unittest.main()
