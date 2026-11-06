"""Entry service: a real HTTP call to service-b propagates the current trace."""

from http.server import BaseHTTPRequestHandler
import json
import os
import time
from urllib.error import URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, build_opener, ProxyHandler

from opentelemetry.trace import SpanKind, Status, StatusCode
from shared.telemetry import (PROPAGATOR, configure, incoming_context,
                              request_parameters, run_server, send_json, trace_id)


def main():
    provider, tracer = configure("service-a")
    worker_url = os.getenv("WORKER_URL", "http://service-b:8080").rstrip("/")
    jaeger_url = os.getenv("JAEGER_PUBLIC_URL", "http://localhost:16686").rstrip("/")
    opener = build_opener(ProxyHandler({}))

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            path = urlsplit(self.path).path
            if path == "/health":
                try:
                    with opener.open(worker_url + "/health", timeout=1) as response:
                        worker_health = json.loads(response.read(4096))
                    if worker_health.get("status") != "ok":
                        raise ValueError("worker not ready")
                    send_json(self, 200, {"status": "ok", "service": "service-a", "worker": "ready"})
                except (OSError, ValueError):
                    send_json(self, 503, {"status": "not_ready", "service": "service-a", "worker": "unavailable"})
                return
            if path == "/":
                send_json(self, 200, {"service": "service-a", "fast_request": "/checkout?scenario=fast",
                                      "slow_request": "/checkout?scenario=slow", "jaeger": jaeger_url,
                                      "simulation": "The worker deliberately waits 40 ms or 600 ms; HTTP calls and tracing are real."})
                return
            if path != "/checkout":
                send_json(self, 404, {"error": "not_found"})
                return
            try:
                scenario, test_run = request_parameters(self.path)
            except ValueError as error:
                send_json(self, 400, {"error": str(error)})
                return
            started = time.perf_counter()
            with tracer.start_as_current_span("GET /checkout", kind=SpanKind.SERVER,
                                               context=incoming_context(self.headers), attributes={
                    "http.request.method": "GET", "url.path": "/checkout",
                    "lab.test_run": test_run, "lab.scenario": scenario,
            }) as server_span:
                identifier = trace_id(server_span)
                try:
                    with tracer.start_as_current_span("validate-request"):
                        time.sleep(0.020)
                    with tracer.start_as_current_span("HTTP GET service-b/work", kind=SpanKind.CLIENT,
                                                       attributes={"http.request.method": "GET", "server.address": "service-b"}) as client_span:
                        headers = {}
                        PROPAGATOR.inject(headers)
                        url = worker_url + "/work?" + urlencode({"scenario": scenario, "test_run": test_run})
                        with opener.open(Request(url, headers=headers), timeout=5) as response:
                            worker = json.loads(response.read(65536))
                            client_span.set_attribute("http.response.status_code", response.status)
                    if worker["trace_id"] != identifier:
                        raise ValueError("service-b did not retain the distributed trace ID")
                    with tracer.start_as_current_span("render-response"):
                        time.sleep(0.005)
                    server_span.set_attribute("http.response.status_code", 200)
                    result = {"service": "service-a", "scenario": scenario, "test_run": test_run,
                              "trace_id": identifier, "elapsed_ms": round((time.perf_counter() - started) * 1000, 3),
                              "worker": worker, "jaeger_url": jaeger_url + "/trace/" + identifier}
                    print(json.dumps({"event": "checkout-completed", "trace_id": identifier,
                                      "test_run": test_run, "elapsed_ms": result["elapsed_ms"]}), flush=True)
                    send_json(self, 200, result)
                except (OSError, URLError, ValueError, KeyError) as error:
                    server_span.record_exception(error)
                    server_span.set_status(Status(StatusCode.ERROR, str(error)))
                    server_span.set_attribute("http.response.status_code", 502)
                    send_json(self, 502, {"error": "downstream_request_failed", "trace_id": identifier,
                                          "test_run": test_run})

    run_server(Handler, provider)


if __name__ == "__main__":
    main()
