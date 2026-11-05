# Dashboards y alertamiento

El PR #4 implementa Grafana 12.4.14 con provisioning reproducible:

- `provisioning/datasources/sources.yml`: Prometheus y Loki con UID estable.
- `provisioning/dashboards/provider.yml`: carpeta Observabilidad y ruta de dashboard.
- `dashboards/operativo.json`: CPU, storage seleccionable, red SNMP y logs.
- `alerting/rules.json`: CPU > 80 % durante 1 minuto.
- `alerting/contact-points.json`: contacto Webhook local.
- `alerting/policies.json`: enrutamiento y agrupación.

Abrir <http://localhost:3000/d/operativo-observabilidad>. Valores locales iniciales: `admin` / `observability-lab`.

La edición se hace en archivos y se versiona; la UI no sustituye esos archivos. La prueba de integración usa una copia temporal de alertas y restaura la regla normal. Guía y evidencias: [PR04_GRAFANA.md](../docs/PR04_GRAFANA.md).
