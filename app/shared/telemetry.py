"""Shared SDK and W3C propagation for the two real HTTP demo processes."""

import json
import os
import re
import signal
import threading
from http.server import ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit
import uuid

import requests
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.trace.sampling import ALWAYS_ON, ParentBased
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

PROPAGATOR = TraceContextTextMapPropagator()


def configure(service):
    endpoint = os.getenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", "http://otel-collector:4318/v1/traces")
    if urlsplit(endpoint).scheme not in ("http", "https"):
        raise ValueError("OTLP traces endpoint must be an HTTP(S) URL")
    provider = TracerProvider(resource=Resource.create({
        "service.name": service, "service.version": "1.0.0",
        "deployment.environment.name": "observability-lab",
    }), sampler=ParentBased(ALWAYS_ON))
    session = requests.Session()
    session.trust_env = False  # This exporter talks only to the configured lab collector.
    exporter = OTLPSpanExporter(endpoint=endpoint, timeout=5, session=session)
    provider.add_span_processor(BatchSpanProcessor(
        exporter, schedule_delay_millis=200, max_export_batch_size=128,
    ))
    trace.set_tracer_provider(provider)
    return provider, trace.get_tracer("observability-lab", "1.0.0")


def request_parameters(path):
    parameters = parse_qs(urlsplit(path).query, keep_blank_values=True)
    if set(parameters) - {"scenario", "test_run"} or any(len(values) != 1 for values in parameters.values()):
        raise ValueError("Only one scenario and one test_run are accepted")
    scenario = parameters.get("scenario", ["slow"])[0]
    test_run = parameters.get("test_run", ["pr5-" + uuid.uuid4().hex])[0]
    if scenario not in ("fast", "slow"):
        raise ValueError("scenario must be fast or slow")
    if not re.fullmatch(r"pr5-[a-f0-9]{32}", test_run):
        raise ValueError("test_run must be pr5- followed by 32 lowercase hexadecimal digits")
    return scenario, test_run


def incoming_context(headers):
    return PROPAGATOR.extract({key.lower(): value for key, value in headers.items()})


def trace_id(span):
    return format(span.get_span_context().trace_id, "032x")


def send_json(handler, status, payload):
    body = json.dumps(payload, ensure_ascii=False, allow_nan=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(body)


def run_server(handler, provider):
    server = ThreadingHTTPServer((os.getenv("HTTP_HOST", "0.0.0.0"), int(os.getenv("HTTP_PORT", "8080"))), handler)
    def stop(_signal, _frame):
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        server.serve_forever()
    finally:
        server.server_close()
        provider.force_flush(timeout_millis=5000)
        provider.shutdown()
