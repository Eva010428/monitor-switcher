import json
import tempfile
import unittest
from pathlib import Path

from monitor_hub.server.app import create_app


class SourcesAndSwitchApiTest(unittest.TestCase):
    def make_client(self, sources):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        sources_path = Path(self.tmp.name) / "sources.json"
        config_path = Path(self.tmp.name) / "config.json"
        sources_path.write_text(json.dumps({"sources": sources}))
        config_path.write_text("{}")
        app = create_app({}, sources_path, config_path)
        return app.test_client(), sources_path

    def test_add_source_persists_per_monitor_vcp_codes(self):
        client, sources_path = self.make_client([])

        response = client.post("/api/sources", json={
            "name": "Windows",
            "vcp_codes": {"0": 15, "1": 17},
        })

        self.assertEqual(response.status_code, 201)
        data = json.loads(sources_path.read_text())
        self.assertEqual(data["sources"][0]["vcp_codes"], {"0": 15, "1": 17})
        self.assertTrue(data["sources"][0]["vcp_code_confirmed"])

    def test_single_vcp_edit_clears_stale_per_monitor_codes(self):
        client, sources_path = self.make_client([{
            "id": "src-1",
            "name": "Windows",
            "vcp_codes": {"0": 15, "1": 17},
            "vcp_code_confirmed": True,
        }])

        response = client.put("/api/sources/src-1", json={
            "name": "Windows",
            "vcp_code": 18,
        })

        self.assertEqual(response.status_code, 200)
        data = json.loads(sources_path.read_text())
        self.assertEqual(data["sources"][0]["vcp_code"], 18)
        self.assertNotIn("vcp_codes", data["sources"][0])


if __name__ == "__main__":
    unittest.main()
