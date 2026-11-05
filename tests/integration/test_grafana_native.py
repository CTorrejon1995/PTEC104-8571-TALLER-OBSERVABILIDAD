"""Real native Grafana/Prometheus/Loki pipeline; no Docker or fabricated metrics.

SNMP/Docker Desktop mounts are checked separately by the Windows integration.
Only local paths, service URLs, scrape speed and ports are adapted for this harness.
"""

import argparse
import contextlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request

from test_logs_native import ROOT, free_port, get_json, stop, wait_ready


def main():
    # Keep the local test pipeline local, including PowerShell's startup telemetry.
    os.environ["POWERSHELL_TELEMETRY_OPTOUT"] = "1"
    os.environ["POWERSHELL_UPDATECHECK"] = "Off"
    os.environ["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1"
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("grafana-home", "prometheus-binary", "node-exporter-binary", "loki-binary", "promtail-binary", "pwsh", "work-dir", "report"):
        parser.add_argument("--" + name, required=True, type=Path)
    parser.add_argument("--legacy-ansi-default", action="store_true",
                        help="Emulate Windows PowerShell's ANSI input default while running the real pipeline")
    args = parser.parse_args()
    work = args.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    ports = {name: free_port() for name in ("grafana", "prometheus", "node", "loki", "loki-grpc", "promtail", "webhook")}
    urls = {name: f"http://127.0.0.1:{port}" for name, port in ports.items()}
    with contextlib.ExitStack() as cleanup:
        def wait_grafana(process, timeout=120):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    detail = (work / "grafana.log").read_text(errors="replace")[-2500:]
                    raise AssertionError("Grafana exited before becoming ready: " + detail)
                try:
                    with urllib.request.urlopen(urls["grafana"] + "/api/health", timeout=3):
                        return
                except OSError:
                    time.sleep(0.5)
            raise AssertionError("Grafana readiness timeout; see " + str(work / "grafana.log"))

        def start(command, name, env=None):
            handle = (work / (name + ".log")).open("ab")
            process = subprocess.Popen([str(x) for x in command], cwd=work, env=env, stdout=handle, stderr=handle)
            cleanup.callback(handle.close)
            cleanup.callback(stop, process)
            return process

        data = work / "loki-data"
        data.mkdir(exist_ok=True)
        log_file = work / "events.jsonl"
        loki_config = work / "loki.yml"
        loki_config.write_text((ROOT / "configs/loki/loki.yml").read_text().replace("/loki", str(data))
                              .replace("http_listen_port: 3100", "http_listen_port: " + str(ports["loki"]))
                              .replace("grpc_listen_port: 9096", "grpc_listen_port: " + str(ports["loki-grpc"])))
        promtail_config = work / "promtail.yml"
        promtail_config.write_text((ROOT / "configs/promtail/promtail.yml").read_text()
                                  .replace("http://loki:3100", urls["loki"])
                                  .replace("/var/log/cloud/events.jsonl", str(log_file))
                                  .replace("/positions/positions.yaml", str(work / "positions.yaml"))
                                  .replace("http_listen_port: 9080", "http_listen_port: " + str(ports["promtail"])))
        prometheus_config = work / "prometheus.yml"
        prometheus_config.write_text(f'''global:
  scrape_interval: 2s
scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ['127.0.0.1:{ports["prometheus"]}']
  - job_name: node-exporter
    static_configs:
      - targets: ['127.0.0.1:{ports["node"]}']
''')
        start([args.node_exporter_binary.resolve(), "--web.listen-address=127.0.0.1:" + str(ports["node"]),
               "--collector.disable-defaults", "--collector.cpu", "--collector.filesystem",
               "--collector.filesystem.fs-types-exclude=^(tmpfs|proc|sysfs|devpts|cgroup2?)$"], "node-exporter")
        start([args.prometheus_binary.resolve(), "--config.file=" + str(prometheus_config),
               "--storage.tsdb.path=" + str(work / "prometheus-data"),
               "--web.listen-address=127.0.0.1:" + str(ports["prometheus"])], "prometheus")
        start([sys.executable, ROOT / "simulators/cloud-logs/generate_logs.py", "--output", log_file, "--interval", "0.2"], "generator")
        start([args.loki_binary.resolve(), "-config.file=" + str(loki_config)], "loki")
        wait_ready(urls["loki"] + "/ready")
        start([args.promtail_binary.resolve(), "-config.file=" + str(promtail_config)], "promtail")
        wait_ready(urls["promtail"] + "/ready")
        start([sys.executable, ROOT / "tools/webhook-receiver/receiver.py", "--host", "127.0.0.1", "--port", str(ports["webhook"]),
               "--database", work / "webhook.sqlite3"], "webhook")
        provisioning = work / "provisioning"
        shutil.copytree(ROOT / "dashboards/provisioning", provisioning, dirs_exist_ok=True)
        shutil.copytree(ROOT / "dashboards/alerting", provisioning / "alerting", dirs_exist_ok=True)
        (provisioning / "plugins").mkdir(exist_ok=True)
        (work / "grafana-plugins").mkdir(exist_ok=True)
        sources = provisioning / "datasources/sources.yml"
        sources.write_text(sources.read_text().replace("http://prometheus:9090", urls["prometheus"]).replace("http://loki:3100", urls["loki"]))
        provider = provisioning / "dashboards/provider.yml"
        provider.write_text(provider.read_text().replace("/var/lib/grafana/dashboards", str(ROOT / "dashboards/dashboards")))
        contact = provisioning / "alerting/contact-points.json"
        contact.write_text(contact.read_text().replace("http://webhook-receiver:8080", urls["webhook"]))
        env = os.environ.copy()
        env.update({
            "GF_PATHS_DATA": str(work / "grafana-data"), "GF_PATHS_LOGS": str(work / "grafana-logs"),
            "GF_PATHS_PLUGINS": str(work / "grafana-plugins"), "GF_PATHS_PROVISIONING": str(provisioning),
            "GF_SERVER_HTTP_ADDR": "127.0.0.1", "GF_SERVER_HTTP_PORT": str(ports["grafana"]),
            "GF_SECURITY_ADMIN_USER": "admin", "GF_SECURITY_ADMIN_PASSWORD": "observability-lab",
            "GF_ANALYTICS_REPORTING_ENABLED": "false", "GF_ANALYTICS_CHECK_FOR_UPDATES": "false",
            "GF_PLUGINS_CHECK_FOR_UPDATES": "false", "GF_PLUGINS_PREINSTALL_DISABLED": "true",
            "GF_UNIFIED_ALERTING_ENABLED": "true",
            "GF_UNIFIED_ALERTING_ALERTMANAGER_CONFIG_POLL_INTERVAL": "5s",
        })
        grafana_command = [args.grafana_home.resolve() / "bin/grafana", "server", "--homepath", args.grafana_home.resolve()]
        grafana = start(grafana_command, "grafana", env=env)
        print("Waiting for real Grafana, Prometheus, Loki and receiver...", flush=True)
        wait_grafana(grafana)
        wait_ready(urls["webhook"] + "/health")
        wait_ready(urls["prometheus"] + "/-/ready")
        # Discover a real native filesystem; Windows uses its observed Docker mount.
        storage_query = urllib.parse.urlencode({"query": 'node_filesystem_size_bytes{job="node-exporter"}'})
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            filesystems = get_json(urls["prometheus"] + "/api/v1/query?" + storage_query)["data"]["result"]
            if filesystems:
                break
            time.sleep(0.5)
        assert filesystems, "Node Exporter did not expose a real native filesystem"
        mountpoint = filesystems[0]["metric"]["mountpoint"]
        command = [args.pwsh.resolve(), "-NoLogo", "-NoProfile", "-File", ROOT / "tests/validation/test-grafana.ps1",
                   "-GrafanaBaseUrl", urls["grafana"], "-WebhookBaseUrl", urls["webhook"],
                   "-NativeAlertingDirectory", provisioning / "alerting", "-StorageMountpoint", mountpoint,
                   "-SkipSnmp", "-TimeoutSeconds", "90", "-EvidencePath", args.report.resolve()]
        if args.legacy_ansi_default:
            def ps_quote(value):
                return "'" + str(value).replace("'", "''") + "'"

            # Run the exact integration script with a legacy default. An explicit
            # -Encoding UTF8 must preserve the non-ASCII alert title regardless.
            wrapper = work / "legacy-ansi-test.ps1"
            tokens = [ps_quote(command[4])]
            tokens.extend(str(value) if str(value).startswith("-") else ps_quote(value) for value in command[5:])
            wrapper.write_text("$ErrorActionPreference = 'Stop'\n"
                               "$PSDefaultParameterValues['Get-Content:Encoding'] = 'windows-1252'\n"
                               "& " + " ".join(tokens) + "\n", encoding="utf-8-sig")
            command = [args.pwsh.resolve(), "-NoLogo", "-NoProfile", "-File", wrapper]
        result = subprocess.run([str(x) for x in command], capture_output=True, text=True, timeout=260)
        (work / "powershell-output.txt").write_text(result.stdout + result.stderr)
        print(result.stdout, flush=True)
        if result.returncode:
            print(result.stderr, flush=True)
            raise AssertionError("PowerShell integration failed; see " + str(work))
        report = json.loads(args.report.read_text())
        assert report["status"] == "passed" and report["restored_normal_rule"]
        expected_title = json.loads((ROOT / "dashboards/alerting/rules.json").read_text())["groups"][0]["rules"][0]["title"]
        received_alert = report["webhook_event"]["payload"]["alerts"][0]
        assert received_alert["labels"]["alertname"] == expected_title
        assert received_alert["ruleUID"] == "cpu-high"
        if args.legacy_ansi_default:
            report["checks"].append("utf8-alert-title-preserved-under-emulated-legacy-ansi-default")
        report["legacy_ansi_default_emulated"] = args.legacy_ansi_default
        # Restart the same Grafana database: provisioning, dashboard and normal rule survive.
        stop(grafana)
        grafana = start(grafana_command, "grafana", env=env)
        wait_grafana(grafana)
        import base64
        from urllib.request import Request, urlopen
        headers = {"Authorization": "Basic " + base64.b64encode(b"admin:observability-lab").decode()}
        for path in ("/api/dashboards/uid/operativo-observabilidad", "/api/v1/provisioning/alert-rules/cpu-high"):
            with urlopen(Request(urls["grafana"] + path, headers=headers), timeout=10) as response:
                value = json.load(response)
            if "alert-rules" in path:
                assert value["for"] in ("1m", "1m0s", "60s")
                condition = next(x for x in value["data"] if x["refId"] == "C")
                assert condition["model"]["conditions"][0]["evaluator"]["params"] == [80]
                assert "test_run" not in value["labels"]
        report["checks"].append("grafana-restart-retains-dashboard-and-normal-rule")
        report["versions"] = {"grafana": "12.4.14", "prometheus": "3.14.0", "node_exporter": "1.12.1", "loki": "3.6.19", "promtail": "3.6.11"}
        report["windows_docker_validation"] = "Pending; native harness omits SNMP and uses a real Linux filesystem"
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print("Native Grafana integration and restart checks passed.", flush=True)


if __name__ == "__main__":
    main()
