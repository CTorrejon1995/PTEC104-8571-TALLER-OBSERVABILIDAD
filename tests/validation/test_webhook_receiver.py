"""Exercise the HTTP boundary and SQLite persistence of the local sink."""

import importlib.util
from http.client import HTTPConnection
import json
from pathlib import Path
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("webhook_receiver", ROOT / "tools/webhook-receiver/receiver.py")
receiver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(receiver)


class ReceiverTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.database = Path(self.directory.name) / "events.sqlite3"
        self.store = receiver.EventStore(self.database)
        self.server = receiver.make_server("127.0.0.1", 0, self.store)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.shutdown)
        self.base = "http://127.0.0.1:" + str(self.server.server_port)

    def shutdown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=3)

    def post(self, body, content_type="application/json", path="/webhook"):
        request = Request(self.base + path, data=body, headers={"Content-Type": content_type}, method="POST")
        return urlopen(request, timeout=3)

    def test_received_notification_survives_store_reopen(self):
        payload = {"status": "firing", "alerts": [{"labels": {"alertname": "CPU alta · laboratorio"}}]}
        with self.post(json.dumps(payload).encode()) as response:
            self.assertEqual(response.status, 202)
        with urlopen(self.base + "/events", timeout=3) as response:
            events = json.load(response)["events"]
        self.assertEqual(events[0]["payload"], payload)
        self.assertEqual(receiver.EventStore(self.database).events(), events)

    def test_malformed_or_non_grafana_payload_cannot_create_evidence(self):
        for body in [b"{broken", b"[]", b'{"status":"firing"}', b'{"status":"invented","alerts":[]}', b'{"status":"firing","alerts":[],"x":NaN}']:
            with self.subTest(body=body), self.assertRaises(HTTPError) as error:
                self.post(body)
            self.assertEqual(error.exception.code, 400)
        self.assertEqual(self.store.events(), [])

    def test_http_type_size_and_route_are_enforced(self):
        for body, kind, path, code in [(b"{}", "text/plain", "/webhook", 415), (b"{}", "application/json", "/unknown", 404)]:
            with self.subTest(code=code), self.assertRaises(HTTPError) as error:
                self.post(body, kind, path)
            self.assertEqual(error.exception.code, code)
        # The server rejects an oversized Content-Length before reading the body.
        connection = HTTPConnection("127.0.0.1", self.server.server_port, timeout=3)
        self.addCleanup(connection.close)
        connection.putrequest("POST", "/webhook")
        connection.putheader("Content-Type", "application/json")
        connection.putheader("Content-Length", str(receiver.MAX_BODY + 1))
        connection.endheaders()
        self.assertEqual(connection.getresponse().status, 413)
        self.assertEqual(self.store.events(), [])


if __name__ == "__main__":
    unittest.main()
