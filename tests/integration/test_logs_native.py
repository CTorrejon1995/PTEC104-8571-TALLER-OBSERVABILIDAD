"""Run real Loki, Promtail and generator binaries without a Docker daemon.

For maintainers/CI. The Windows user flow remains dev.ps1 test -Integration.
Binary versions must match the pinned images in docker-compose.yml.
"""

import argparse
import contextlib
from datetime import datetime, timezone
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
import uuid


ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "simulators/cloud-logs/generate_logs.py"


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def get_json(url):
    with urllib.request.urlopen(url, timeout=5) as response:
        return json.load(response)


def wait_ready(url, timeout=90):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=3):
                return
        except Exception as exc:
            last_error = exc
            time.sleep(0.25)
    raise AssertionError(f"Endpoint not ready: {url}: {last_error}")


def query(base, expression):
    now_ns = time.time_ns()
    parameters = urllib.parse.urlencode({
        "query": expression, "start": str(now_ns - 900_000_000_000),
        "end": str(now_ns), "limit": "1000",
    })
    data = get_json(base + "/loki/api/v1/query_range?" + parameters)
    assert data["status"] == "success", data
    return data["data"]["result"]


def wait_probe(base, probe, level="error", timeout=30):
    expression = '{job="cloud-logs",level="' + level + '"} |= "' + probe + '"'
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = query(base, expression)
        if result:
            return result
        time.sleep(0.25)
    raise AssertionError("Fresh generator probe was not ingested: " + probe)


def stop(process):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=12)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--loki-binary", required=True, type=Path)
    parser.add_argument("--promtail-binary", required=True, type=Path)
    parser.add_argument("--pwsh", type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    processes = []
    handles = []
    checks = []
    report = {
        "executed_at": datetime.now(timezone.utc).isoformat(),
        "environment": "Linux native processes; no Docker daemon",
        "loki": "3.6.19", "promtail": "3.6.11", "checks": checks,
        "windows_docker_validation": "Pending execution on the user's PC",
    }
    try:
        with tempfile.TemporaryDirectory(prefix="observability-pr3-") as folder, contextlib.ExitStack() as cleanup:
            work = Path(folder)
            data = work / "data"
            data.mkdir()
            logs = work / "events.jsonl"
            loki_port, promtail_port, grpc_port = free_port(), free_port(), free_port()
            loki_url = f"http://127.0.0.1:{loki_port}"
            promtail_url = f"http://127.0.0.1:{promtail_port}"
            loki_config = work / "loki.yml"
            promtail_config = work / "promtail.yml"
            # Only filesystem paths and listening ports differ from Docker.
            loki_text = (ROOT / "configs/loki/loki.yml").read_text()
            loki_config.write_text(
                loki_text.replace("/loki", str(data))
                .replace("http_listen_port: 3100", f"http_listen_port: {loki_port}")
                .replace("grpc_listen_port: 9096", f"grpc_listen_port: {grpc_port}")
            )
            promtail_text = (ROOT / "configs/promtail/promtail.yml").read_text()
            promtail_config.write_text(
                promtail_text.replace("http://loki:3100", loki_url)
                .replace("/var/log/cloud/events.jsonl", str(logs))
                .replace("/positions/positions.yaml", str(work / "positions.yaml"))
                .replace("http_listen_port: 9080", f"http_listen_port: {promtail_port}")
            )

            def start(command, name):
                handle = (work / (name + ".txt")).open("ab")
                handles.append(handle)
                process = subprocess.Popen(
                    [str(x) for x in command], cwd=work, stdout=handle, stderr=handle
                )
                processes.append(process)
                cleanup.callback(handle.close)
                cleanup.callback(stop, process)
                return process

            generator = start(
                [sys.executable, GENERATOR, "--output", logs, "--interval", "0.1"], "generator"
            )
            loki_command = [args.loki_binary.resolve(), "-config.file=" + str(loki_config)]
            loki = start(loki_command, "loki")
            print("Waiting for native Loki...", flush=True)
            wait_ready(loki_url + "/ready")
            promtail_command = [args.promtail_binary.resolve(), "-config.file=" + str(promtail_config)]
            promtail = start(promtail_command, "promtail")
            print("Waiting for native Promtail...", flush=True)
            wait_ready(promtail_url + "/ready")
            checks.append("Real Loki and Promtail ready endpoints")

            def emit_probe():
                probe = "pr3-probe-" + uuid.uuid4().hex
                subprocess.run(
                    [sys.executable, str(GENERATOR), "--output", str(logs), "--once",
                     "--level", "error", "--message", probe],
                    check=True, stdout=subprocess.DEVNULL,
                )
                wait_probe(loki_url, probe)
                return probe

            probe = emit_probe()
            print("Fresh generator probe received by Loki.", flush=True)
            checks.append("Fresh file log ingested through Promtail and filtered by level")
            assert not query(loki_url, '{job="cloud-logs",level="info"} |= "' + probe + '"')
            checks.append("Wrong severity filter excludes the error probe")
            streams = query(loki_url, '{job="cloud-logs"}')
            assert {stream["stream"]["level"] for stream in streams} >= {"info", "warn", "error"}
            for stream in streams:
                assert "request_id" not in stream["stream"]
                for timestamp, line in stream["values"]:
                    event = json.loads(line)
                    assert event["level"] == stream["stream"]["level"]
                    assert event["simulated"] is True
                    date = datetime.fromisoformat(event["timestamp"].replace("Z", "+00:00"))
                    expected = int(date.timestamp()) * 1_000_000_000 + date.microsecond * 1000
                    assert int(timestamp) == expected, "JSON event timestamp was not used by Promtail"
            checks.append("All JSON severities and event timestamps extracted correctly")

            if args.pwsh:
                command = [
                    str(args.pwsh.resolve()), "-NoLogo", "-NoProfile", "-File",
                    str(ROOT / "tests/validation/test-logs.ps1"),
                    "-LokiBaseUrl", loki_url, "-PromtailBaseUrl", promtail_url,
                    "-ExistingProbeId", probe, "-TimeoutSeconds", "15",
                ]
                result = subprocess.run(command, capture_output=True, text=True, timeout=60)
                report["powershell_output"] = result.stdout
                assert result.returncode == 0, result.stdout + result.stderr
                checks.append("Real PowerShell log integration script against the live pipeline")
                missing_probe = "pr3-probe-" + uuid.uuid4().hex
                command[command.index("-ExistingProbeId") + 1] = missing_probe
                command[command.index("-TimeoutSeconds") + 1] = "5"
                negative = subprocess.run(command, capture_output=True, text=True, timeout=30)
                assert negative.returncode != 0, "Missing probe incorrectly passed"
                checks.append("PowerShell test rejects a missing fresh probe")

            stop(promtail)
            assert (work / "positions.yaml").exists()
            promtail = start(promtail_command, "promtail")
            wait_ready(promtail_url + "/ready")
            emit_probe()
            checks.append("Promtail restart resumes collection using its positions file")
            stop(loki)
            loki = start(loki_command, "loki")
            wait_ready(loki_url + "/ready")
            wait_probe(loki_url, probe)
            emit_probe()
            checks.append("Loki restart recovers stored logs and accepts new logs")
            report["status"] = "passed"
    except Exception as exc:
        report["status"] = "failed"
        report["error"] = str(exc)
        raise
    finally:
        for process in reversed(processes):
            stop(process)
        for handle in handles:
            handle.close()
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps(report, ensure_ascii=False, indent=2), flush=True)


if __name__ == "__main__":
    main()
