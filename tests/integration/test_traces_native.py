"""Run the pinned Jaeger/Collector and both Python services without Docker.

Actual SDK spans must pass Collector -> Jaeger and the same PowerShell checker
used by Windows must verify the distributed parent references and latency.
"""

import argparse
import contextlib
import json
import os
from pathlib import Path
import socket
import subprocess
import time
import urllib.error
import urllib.request

from test_logs_native import ROOT, stop


def main():
    os.environ["POWERSHELL_TELEMETRY_OPTOUT"] = "1"
    os.environ["POWERSHELL_UPDATECHECK"] = "Off"
    os.environ["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1"
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("jaeger", "collector", "python", "pwsh", "work-dir", "report"):
        parser.add_argument("--" + name, required=True, type=Path)
    args = parser.parse_args()
    if not Path('/proc/' + str(os.getpid()) + '/stat').exists():
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps({
            'status': 'not_run_environment_limit',
            'reason': 'Executor does not expose numeric process IDs in /proc; Jaeger/Collector internal process metric initialization cannot start.',
            'backend_runtime_validated': False,
            'next_validation': 'Run the real backend with Docker Desktop and tests/validation/test-traces.ps1.',
        }, indent=2) + '\n')
        print('Native backend test not run: /proc PID visibility is unavailable; Docker validation remains pending.', flush=True)
        raise SystemExit(2)
    work = args.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    names = ("jaeger-query", "jaeger-grpc", "jaeger-http", "jaeger-health", "jaeger-metrics",
             "collector-grpc", "collector-http", "collector-health", "collector-metrics", "service-a", "service-b")
    ports = {}
    with contextlib.ExitStack() as held:
        for name in names:
            sock = socket.socket()
            held.callback(sock.close)
            sock.bind(("127.0.0.1", 0))
            ports[name] = sock.getsockname()[1]
    url = lambda name: "http://127.0.0.1:" + str(ports[name])

    jaeger_text = (ROOT / "configs/jaeger/jaeger.yml").read_text()
    for default, key in [(4317, "jaeger-grpc"), (4318, "jaeger-http"), (16686, "jaeger-query"), (13134, "jaeger-health")]:
        jaeger_text = jaeger_text.replace("0.0.0.0:" + str(default), "127.0.0.1:" + str(ports[key]))
    jaeger_text = jaeger_text.replace("port: 8889", "port: " + str(ports["jaeger-metrics"]))
    jaeger_text = jaeger_text.replace("host: 0.0.0.0", "host: 127.0.0.1")
    (work / "jaeger.yml").write_text(jaeger_text)
    collector_text = (ROOT / "configs/otel-collector/otel-collector.yml").read_text()
    for default, key in [(4317, "collector-grpc"), (4318, "collector-http"), (13133, "collector-health")]:
        collector_text = collector_text.replace("0.0.0.0:" + str(default), "127.0.0.1:" + str(ports[key]))
    collector_text = collector_text.replace("jaeger:4317", "127.0.0.1:" + str(ports["jaeger-grpc"]))
    collector_text = collector_text.replace("port: 8888", "port: " + str(ports["collector-metrics"]))
    collector_text = collector_text.replace("host: 0.0.0.0", "host: 127.0.0.1")
    (work / "collector.yml").write_text(collector_text)

    with contextlib.ExitStack() as cleanup:
        def start(command, name, env=None):
            handle = (work / (name + ".log")).open("ab")
            process = subprocess.Popen([str(x) for x in command], cwd=work, env=env, stdout=handle, stderr=handle)
            cleanup.callback(handle.close)
            cleanup.callback(stop, process)
            return process

        def wait_component(endpoint, process, name):
            deadline = time.monotonic() + 60
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    detail = (work / (name + ".log")).read_text(errors="replace")[-2500:]
                    if 'failed to register process metrics: process does not exist' in detail:
                        args.report.parent.mkdir(parents=True, exist_ok=True)
                        args.report.write_text(json.dumps({
                            'status': 'not_run_environment_limit',
                            'reason': name + ' cannot initialize process metrics: numeric /proc PID visibility is unavailable in this executor.',
                            'backend_runtime_validated': False,
                            'next_validation': 'Run the real backend with Docker Desktop and tests/validation/test-traces.ps1.',
                        }, indent=2) + '\n')
                        print('Native backend runtime unavailable in this executor; Docker validation remains pending.', flush=True)
                        raise SystemExit(2)
                    raise AssertionError(name + " exited before becoming ready: " + detail)
                try:
                    with urllib.request.urlopen(endpoint, timeout=3):
                        return
                except OSError:
                    time.sleep(0.25)
            raise AssertionError(name + " readiness timeout; see " + str(work))

        jaeger = start([args.jaeger.resolve(), "--config", work / "jaeger.yml"], "jaeger")
        wait_component(url("jaeger-query") + "/api/v3/services", jaeger, "jaeger")
        collector = start([args.collector.resolve(), "--config", work / "collector.yml"], "collector")
        wait_component(url("collector-health"), collector, "collector")
        common_env = os.environ.copy()
        common_env.update({"PYTHONPATH": str(ROOT / "app"), "PYTHONDONTWRITEBYTECODE": "1",
                           "HTTP_HOST": "127.0.0.1", "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT": url("collector-http") + "/v1/traces"})
        b_env = dict(common_env, HTTP_PORT=str(ports["service-b"]))
        worker = start([args.python.absolute(), ROOT / "app/service-b/main.py"], "service-b", b_env)
        wait_component(url("service-b") + "/health", worker, "service-b")
        a_env = dict(common_env, HTTP_PORT=str(ports["service-a"]), WORKER_URL=url("service-b"), JAEGER_PUBLIC_URL=url("jaeger-query"))
        frontend = start([args.python.absolute(), ROOT / "app/service-a/main.py"], "service-a", a_env)
        wait_component(url("service-a") + "/health", frontend, "service-a")
        print("Jaeger, Collector and both real application processes ready.", flush=True)
        command = [args.pwsh.resolve(), "-NoLogo", "-NoProfile", "-File", ROOT / "tests/validation/test-traces.ps1",
                   "-ApplicationBaseUrl", url("service-a"), "-JaegerBaseUrl", url("jaeger-query"),
                   "-CollectorHealthUrl", url("collector-health"), "-TimeoutSeconds", "45",
                   "-EnvironmentLabel", "linux-native-real-processes", "-EvidencePath", args.report.resolve()]
        result = subprocess.run([str(x) for x in command], capture_output=True, text=True, timeout=150)
        (work / "powershell-output.txt").write_text(result.stdout + result.stderr)
        print(result.stdout, flush=True)
        assert result.returncode == 0, result.stdout + result.stderr
        report = json.loads(args.report.read_text())
        assert report["status"] == "passed"

        # Check real HTTP failure behavior, rather than accepting a successful SDK setup alone.
        try:
            urllib.request.urlopen(url("service-a") + "/checkout?scenario=invalid", timeout=3)
            raise AssertionError("Invalid scenario was accepted")
        except urllib.error.HTTPError as error:
            assert error.code == 400
        stop(worker)
        for path, expected in [("/health", 503), ("/checkout?scenario=fast", 502)]:
            try:
                urllib.request.urlopen(url("service-a") + path, timeout=8)
                raise AssertionError("Unavailable downstream service was accepted")
            except urllib.error.HTTPError as error:
                assert error.code == expected
        report["checks"].extend(["invalid-scenario-http-400", "unavailable-worker-readiness-503-and-checkout-502"])
        report["versions"] = {"jaeger": "2.23.0", "collector_contrib": "0.164.0", "opentelemetry_python": "1.45.2"}
        report["native_adaptations"] = "Local filesystem paths, ports and service URLs; trace pipelines unchanged."
        report["windows_docker_validation"] = "Pending execution on student PC; native test does not run existing metrics/logs/Grafana Docker services"
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print("Native distributed tracing and HTTP failure checks passed.", flush=True)


if __name__ == "__main__":
    main()
