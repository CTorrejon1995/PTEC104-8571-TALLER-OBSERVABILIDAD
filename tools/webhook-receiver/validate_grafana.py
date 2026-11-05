"""Check local JSON provisioning and cross-file references before startup."""

import json
from pathlib import Path
import sys


def validate(root):
    dashboard = json.loads((root / "dashboards/operativo.json").read_text(encoding="utf-8-sig"))
    rules = json.loads((root / "alerting/rules.json").read_text(encoding="utf-8-sig"))
    contacts = json.loads((root / "alerting/contact-points.json").read_text(encoding="utf-8-sig"))
    policies = json.loads((root / "alerting/policies.json").read_text(encoding="utf-8-sig"))
    panels = {p["id"]: p for p in dashboard["panels"]}
    assert dashboard["uid"] == "operativo-observabilidad"
    assert len(panels) >= 4 and {"timeseries", "gauge", "logs"}.issubset({p["type"] for p in panels.values()})
    rule = rules["groups"][0]["rules"][0]
    assert rule["uid"] == "cpu-high" and rule["for"] == "1m"
    queries = {q["refId"]: q for q in rule["data"]}
    assert rule["condition"] == "C" and queries["B"]["model"]["expression"] == "A"
    assert queries["C"]["model"]["expression"] == "B"
    assert queries["C"]["model"]["conditions"][0]["evaluator"] == {"params": [80], "type": "gt"}
    assert queries["A"]["model"]["expr"] == panels[1]["targets"][0]["expr"]
    assert rule["annotations"]["__dashboardUid__"] == dashboard["uid"]
    assert int(rule["annotations"]["__panelId__"]) in panels
    contact = contacts["contactPoints"][0]
    assert policies["policies"][0]["receiver"] == contact["name"]
    assert contact["receivers"][0]["settings"]["url"] == "http://webhook-receiver:8080/webhook"
    assert "test_run" not in rule["labels"], "The committed rule must not contain a test override"
    for filename in ("provisioning/datasources/sources.yml", "provisioning/dashboards/provider.yml"):
        assert (root / filename).is_file(), filename
    print("Grafana: JSON y referencias locales correctos; regla normal CPU > 80 % por 1 minuto.")
    print("La carga de los YAML y las consultas se comprueba con Grafana iniciado en la integracion.")


if __name__ == "__main__":
    validate(Path(sys.argv[1] if len(sys.argv) > 1 else "/project-dashboards"))
