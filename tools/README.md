# Herramientas auxiliares

`webhook-receiver/` contiene el receptor local del PR #4. Usa la biblioteca estándar de Python, recibe las notificaciones de Grafana en `/webhook`, las guarda en SQLite y las muestra en <http://localhost:8081>.

`/health` comprueba disponibilidad; `/events` devuelve los últimos avisos reales. El contenedor corre como usuario 10001 y solo escribe en `webhook-data`. `validate_grafana.py` revisa JSON y referencias del provisioning, sin sustituir la comprobación con Grafana real.

Ver [PR04_GRAFANA.md](../docs/PR04_GRAFANA.md).
