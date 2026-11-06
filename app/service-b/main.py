"""Worker: deliberately simulated lookup latency inside an exported child span."""

from http.server import BaseHTTPRequestHandler
import time
from urllib.parse import urlsplit

from opentelemetry.trace import SpanKind
from shared.telemetry import (configure, incoming_context, request_parameters,
                              run_server, send_json, trace_id)


def main():
    provider, tracer = configure("service-b")

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            path = urlsplit(self.path).path
            if path == "/health":
                send_json(self, 200, {"status": "ok", "service": "service-b"})
                return
            if path != "/work":
                send_json(self, 404, {"error": "not_found"})
                return
            try:
                scenario, test_run = request_parameters(self.path)
            except ValueError as error:
                send_json(self, 400, {"error": str(error)})
                return
            delay_ms = 40 if scenario == "fast" else 600
            with tracer.start_as_current_span("GET /work", kind=SpanKind.SERVER,
                                               context=incoming_context(self.headers), attributes={
                    "http.request.method": "GET", "url.path": "/work",
                    "lab.test_run": test_run, "lab.scenario": scenario,
            }) as server_span:
                with tracer.start_as_current_span("simulated-db-query", attributes={
                    "lab.simulated": True, "lab.delay_ms": delay_ms,
                }):
                    time.sleep(delay_ms / 1000)
                server_span.set_attribute("http.response.status_code", 200)
                send_json(self, 200, {"service": "service-b", "scenario": scenario,
                                      "test_run": test_run, "trace_id": trace_id(server_span),
                                      "simulated_delay_ms": delay_ms})

    run_server(Handler, provider)


if __name__ == "__main__":
    main()
