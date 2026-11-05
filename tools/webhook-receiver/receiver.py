"""Local laboratory Webhook sink. Stores actual received JSON in SQLite."""

import argparse
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import sqlite3
from urllib.parse import urlsplit

MAX_BODY = 1024 * 1024
MAX_EVENTS = 1000


def reject_nonfinite_json(value):
    raise ValueError("Non-finite JSON number: " + value)


class EventStore:
    def __init__(self, filename):
        self.filename = str(filename)
        Path(filename).parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as db:
            db.execute("CREATE TABLE IF NOT EXISTS events "
                       "(id INTEGER PRIMARY KEY AUTOINCREMENT, received_at TEXT NOT NULL, payload TEXT NOT NULL)")

    def connect(self):
        return sqlite3.connect(self.filename, timeout=10)

    def append(self, payload):
        received_at = datetime.now(timezone.utc).isoformat()
        with self.connect() as db:
            cursor = db.execute("INSERT INTO events(received_at,payload) VALUES (?,?)",
                                (received_at, json.dumps(payload, ensure_ascii=False, allow_nan=False)))
            identifier = cursor.lastrowid
            db.execute("DELETE FROM events WHERE id NOT IN "
                       "(SELECT id FROM events ORDER BY id DESC LIMIT ?)", (MAX_EVENTS,))
        return identifier

    def events(self):
        with self.connect() as db:
            rows = db.execute("SELECT id,received_at,payload FROM events ORDER BY id DESC").fetchall()
        return [{"id": row[0], "received_at": row[1], "payload": json.loads(row[2])} for row in rows]


def make_server(host, port, store):
    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(10)

        def reply(self, status, value, content_type="application/json; charset=utf-8"):
            body = (json.dumps(value, ensure_ascii=False, allow_nan=False).encode("utf-8")
                    if content_type.startswith("application/json") else value.encode("utf-8"))
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            path = urlsplit(self.path).path
            if path == "/health":
                self.reply(200, {"status": "ok", "stored_events": len(store.events())})
            elif path == "/events":
                self.reply(200, {"events": store.events()})
            elif path == "/":
                self.reply(200, """<!doctype html><html lang="es"><meta charset="utf-8">
<title>Avisos recibidos · Observabilidad</title>
<style>body{font:16px system-ui;background:#101823;color:#edf2fa;max-width:1000px;margin:40px auto;padding:0 20px}h1{font-size:26px}pre{background:#1a293b;padding:22px;border-radius:10px;white-space:pre-wrap;overflow-wrap:anywhere}a{color:#7ad7ff}</style>
<h1>Avisos Webhook recibidos</h1><p>Notificaciones enviadas por Grafana al receptor local del laboratorio. Actualización cada 3 segundos.</p>
<p><a href="/events">Ver JSON original</a></p><pre id="events">Cargando…</pre>
<script>async function load(){try{const r=await fetch('/events');const d=await r.json();document.getElementById('events').textContent=d.events.length?JSON.stringify(d,null,2):'Todavía no se han recibido avisos.'}catch(e){document.getElementById('events').textContent='No se pudo consultar el receptor.'}}load();setInterval(load,3000)</script></html>""",
                           "text/html; charset=utf-8")
            else:
                self.reply(404, {"error": "not_found"})

        def do_POST(self):
            if urlsplit(self.path).path != "/webhook":
                self.reply(404, {"error": "not_found"})
                return
            if self.headers.get("Content-Type", "").split(";")[0].lower() != "application/json":
                self.reply(415, {"error": "application_json_required"})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                length = 0
            if length <= 0 or length > MAX_BODY:
                self.reply(413, {"error": "invalid_body_size"})
                return
            try:
                body = self.rfile.read(length)
                if len(body) != length:
                    raise ValueError("Incomplete request body")
                payload = json.loads(body.decode("utf-8"), parse_constant=reject_nonfinite_json)
                if not isinstance(payload, dict) or not isinstance(payload.get("alerts"), list):
                    raise ValueError("Expected a Grafana Webhook object with alerts")
                if payload.get("status") not in ("firing", "resolved"):
                    raise ValueError("Expected firing or resolved status")
            except (ValueError, UnicodeError, TimeoutError):
                self.reply(400, {"error": "invalid_grafana_json"})
                return
            identifier = store.append(payload)
            print(json.dumps({"event_id": identifier, "status": payload["status"],
                              "alert_count": len(payload["alerts"])}), flush=True)
            self.reply(202, {"accepted": True, "event_id": identifier})

    return ThreadingHTTPServer((host, port), Handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--database", default="/data/events.sqlite3")
    args = parser.parse_args()
    server = make_server(args.host, args.port, EventStore(args.database))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
