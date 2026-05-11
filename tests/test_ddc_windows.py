import importlib
import sys
import types
import unittest
from unittest import mock


class FakeMonitor:
    def __init__(self):
        self.set_calls = []
        self.get_feature = None

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def get_vcp_capabilities(self):
        return {"model": "Fake Display"}

    def _set_vcp_feature(self, feature, value):
        self.set_calls.append((feature, value))

    def _get_vcp_feature(self, feature):
        self.get_feature = feature
        return types.SimpleNamespace(value=17)


class WindowsDdcCompatibilityTest(unittest.TestCase):
    def setUp(self):
        sys.modules.pop("monitor_hub.agent.ddc", None)

    def tearDown(self):
        sys.modules.pop("monitor_hub.agent.ddc", None)

    def test_private_monitorcontrol_fallback_supplies_required_feature_metadata(self):
        monitor = FakeMonitor()
        monitorcontrol = types.ModuleType("monitorcontrol")
        monitorcontrol.get_monitors = lambda: [monitor]

        with mock.patch.dict(sys.modules, {"monitorcontrol": monitorcontrol}):
            with mock.patch.object(sys, "platform", "win32"):
                ddc = importlib.import_module("monitor_hub.agent.ddc")

        ddc.set_input({}, 0, 15)
        feature, value = monitor.set_calls[0]

        self.assertEqual(value, 15)
        self.assertEqual(feature.value, 0x60)
        self.assertEqual(feature.type, "rw")
        self.assertEqual(feature.function, "nc")

        self.assertEqual(ddc.get_input({}, 0), 17)
        self.assertEqual(monitor.get_feature.function, "nc")


if __name__ == "__main__":
    unittest.main()
