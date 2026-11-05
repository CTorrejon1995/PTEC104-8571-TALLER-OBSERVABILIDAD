"""Contract tests for the real generator CLI; only Python's stdlib is required."""

from datetime import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "simulators/cloud-logs/generate_logs.py"


class GeneratorContractTests(unittest.TestCase):
    def test_probe_round_trip_preserves_json_severity_and_unicode(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "nested/events.jsonl"
            command = [
                sys.executable, str(GENERATOR), "--output", str(output),
                "--once", "--level", "error", "--message", "Fallo de prueba: ñ á",
            ]
            result = subprocess.run(command, capture_output=True, text=True, check=True)
            lines = output.read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(lines), 1)
            event = json.loads(lines[0])
            self.assertEqual(event, json.loads(result.stdout))
            self.assertEqual(event["level"], "error")
            self.assertEqual(event["message"], "Fallo de prueba: ñ á")
            self.assertIs(event["simulated"], True)
            self.assertIsNotNone(datetime.fromisoformat(event["timestamp"].replace("Z", "+00:00")).tzinfo)
            self.assertRegex(event["request_id"], r"^[a-f0-9]{32}$")

    def test_invalid_settings_fail_before_writing(self):
        for arguments in [
            ["--interval", "0"], ["--interval", "nan"],
            ["--max-bytes", "1"], ["--backup-count", "0"],
        ]:
            with self.subTest(arguments=arguments), tempfile.TemporaryDirectory() as folder:
                output = Path(folder) / "events.jsonl"
                result = subprocess.run(
                    [sys.executable, str(GENERATOR), "--output", str(output), *arguments],
                    capture_output=True, timeout=5,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(output.exists())

    def test_continuous_generation_rotates_and_emits_all_severities(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "events.jsonl"
            process = subprocess.Popen(
                [sys.executable, str(GENERATOR), "--output", str(output),
                 "--interval", "0.01", "--max-bytes", "1024", "--backup-count", "2"],
                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
            )
            try:
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline and not Path(str(output) + ".2").exists():
                    time.sleep(0.025)
                self.assertTrue(Path(str(output) + ".2").exists(), "Rotation did not occur")
            finally:
                process.terminate()
                process.wait(timeout=5)
                stderr = process.stderr.read()
                process.stderr.close()
            if os.name == "posix":
                self.assertEqual(process.returncode, 0, stderr.decode())
            files = list(Path(folder).glob("events.jsonl*"))
            self.assertLessEqual(len(files), 3)
            events = [
                json.loads(line)
                for path in files for line in path.read_text(encoding="utf-8").splitlines()
            ]
            self.assertEqual({event["level"] for event in events}, {"info", "warn", "error"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
