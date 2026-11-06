"""Validate the public scenario input boundary used by both demo services."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "app"))
from shared.telemetry import request_parameters


class DemoRequestTests(unittest.TestCase):
    def test_browser_request_has_new_unique_trace_marker(self):
        scenario, marker = request_parameters("/checkout?scenario=fast")
        self.assertEqual(scenario, "fast")
        self.assertRegex(marker, r"^pr5-[a-f0-9]{32}$")
        self.assertNotEqual(marker, request_parameters("/checkout?scenario=fast")[1])

    def test_explicit_scenario_marker_survives_the_http_boundary(self):
        marker = "pr5-" + "a" * 32
        self.assertEqual(request_parameters("/work?scenario=slow&test_run=" + marker), ("slow", marker))

    def test_invalid_inputs_are_rejected_before_work_is_scheduled(self):
        for path in ["/work?scenario=other", "/work?scenario=fast&scenario=slow", "/work?test_run=bad", "/work?delay_ms=999999", "/work?scenario="]:
            with self.subTest(path=path), self.assertRaises(ValueError):
                request_parameters(path)


if __name__ == "__main__":
    unittest.main()
