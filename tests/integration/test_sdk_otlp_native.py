"""Check real HTTP services and SDK OTLP protobuf on a local capture endpoint.

This protocol-level test does not run or impersonate Collector/Jaeger. It is
separate from test_traces_native.py and never certifies backend ingestion.
"""

import argparse
import contextlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.request
import uuid

from opentelemetry.proto.collector.trace.v1.trace_service_pb2 import ExportTraceServiceRequest

from test_logs_native import ROOT, stop, wait_ready


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--python', type=Path, required=True)
    parser.add_argument('--work-dir', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    work = args.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    captured = []
    lock = threading.Lock()

    class CaptureHandler(BaseHTTPRequestHandler):
        def do_POST(self):
            if self.path != '/v1/traces':
                self.send_error(404)
                return
            length = int(self.headers['Content-Length'])
            if not 0 < length < 1024 * 1024:
                self.send_error(413)
                return
            request = ExportTraceServiceRequest()
            request.ParseFromString(self.rfile.read(length))
            observed = []
            for resource in request.resource_spans:
                attributes = {item.key: item.value.string_value for item in resource.resource.attributes}
                for scope in resource.scope_spans:
                    for span in scope.spans:
                        tags = {}
                        for item in span.attributes:
                            kind = item.value.WhichOneof('value')
                            tags[item.key] = getattr(item.value, kind)
                        observed.append({'service': attributes['service.name'], 'operation': span.name,
                                         'trace_id': span.trace_id.hex(), 'span_id': span.span_id.hex(),
                                         'parent_span_id': span.parent_span_id.hex(), 'kind': span.kind,
                                         'duration_ms': (span.end_time_unix_nano - span.start_time_unix_nano) / 1e6,
                                         'tags': tags})
            with lock:
                captured.extend(observed)
            self.send_response(200)
            self.send_header('Content-Type', 'application/x-protobuf')
            self.send_header('Content-Length', '0')
            self.end_headers()

    def get_json(url):
        with urllib.request.urlopen(url, timeout=10) as response:
            return json.load(response)

    def expect_http(url, code):
        try:
            urllib.request.urlopen(url, timeout=8)
            raise AssertionError('Expected HTTP ' + str(code))
        except urllib.error.HTTPError as error:
            assert error.code == code

    with contextlib.ExitStack() as cleanup:
        capture = ThreadingHTTPServer(('127.0.0.1', 0), CaptureHandler)
        capture_thread = threading.Thread(target=capture.serve_forever, daemon=True)
        capture_thread.start()
        cleanup.callback(capture.server_close)
        cleanup.callback(capture.shutdown)
        held = []
        for _ in range(2):
            sock = socket.socket(); sock.bind(('127.0.0.1', 0)); held.append(sock)
        worker_port, frontend_port = [sock.getsockname()[1] for sock in held]
        for sock in held: sock.close()
        env = os.environ.copy()
        env.update({'PYTHONPATH': str(ROOT / 'app'), 'PYTHONDONTWRITEBYTECODE': '1',
                    'HTTP_HOST': '127.0.0.1',
                    'OTEL_EXPORTER_OTLP_TRACES_ENDPOINT': 'http://127.0.0.1:' + str(capture.server_port) + '/v1/traces'})

        def start(role, port):
            handle = (work / (role + '.log')).open('ab')
            local_env = dict(env, HTTP_PORT=str(port), WORKER_URL='http://127.0.0.1:' + str(worker_port))
            process = subprocess.Popen([str(args.python.absolute()), str(ROOT / 'app' / role / 'main.py')],
                                       cwd=work, env=local_env, stdout=handle, stderr=handle)
            cleanup.callback(handle.close); cleanup.callback(stop, process)
            return process

        worker = start('service-b', worker_port)
        wait_ready('http://127.0.0.1:' + str(worker_port) + '/health')
        start('service-a', frontend_port)
        base = 'http://127.0.0.1:' + str(frontend_port)
        wait_ready(base + '/health')
        results = []
        for scenario, delay in [('fast', 40), ('slow', 600)]:
            marker = 'pr5-' + uuid.uuid4().hex
            response = get_json(base + '/checkout?scenario=' + scenario + '&test_run=' + marker)
            identifier = response['trace_id']
            assert response['worker']['trace_id'] == identifier
            deadline = time.monotonic() + 12
            while time.monotonic() < deadline:
                with lock:
                    spans = [dict(span) for span in captured if span['trace_id'] == identifier]
                if len(spans) >= 6: break
                time.sleep(0.1)
            assert len(spans) == 6, spans
            assert {span['service'] for span in spans} == {'service-a', 'service-b'}
            by_name = {span['operation']: span for span in spans}
            root = by_name['GET /checkout']; client = by_name['HTTP GET service-b/work']
            remote = by_name['GET /work']; query = by_name['simulated-db-query']
            assert client['parent_span_id'] == root['span_id']
            assert remote['parent_span_id'] == client['span_id']
            assert query['parent_span_id'] == remote['span_id']
            assert client['kind'] == 3 and remote['kind'] == 2  # OTLP CLIENT and SERVER.
            assert root['tags']['lab.test_run'] == remote['tags']['lab.test_run'] == marker
            assert query['tags']['lab.delay_ms'] == delay and query['tags']['lab.simulated'] is True
            assert query['duration_ms'] >= delay * 0.9
            result = {'scenario': scenario, 'test_run': marker, 'trace_id': identifier,
                      'root_duration_ms': round(root['duration_ms'], 3),
                      'query_duration_ms': round(query['duration_ms'], 3), 'spans': spans}
            results.append(result)
            print(scenario, 'real HTTP + W3C propagation + six SDK OTLP spans:', identifier, flush=True)
        expect_http(base + '/checkout?scenario=invalid', 400)
        stop(worker)
        expect_http(base + '/health', 503)
        expect_http(base + '/checkout?scenario=fast', 502)
        report = {'status': 'passed', 'scope': 'SDK OTLP/HTTP protobuf capture from two real HTTP application processes',
                  'collector_jaeger_runtime_validated': False,
                  'checks': ['unique-request-markers', 'same-trace-id-across-services', 'client-server-parent-span-reference',
                             'six-real-sdk-spans-per-request', 'real-measured-delays', 'http-400-503-502-error-behavior'],
                  'scenarios': results,
                  'limitation': 'Collector and Jaeger configuration validation passed separately, but native runtime requires numeric /proc PID visibility unavailable in the preparation executor. Docker Desktop backend validation remains pending.'}
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')
        print('SDK protocol validation passed; backend ingestion is NOT certified by this test.', flush=True)


if __name__ == '__main__':
    main()
