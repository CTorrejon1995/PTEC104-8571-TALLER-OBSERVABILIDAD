# PR #3 - Centralizacion de logs JSON con Loki y Promtail

La base solo recolectaba métricas. Este cambio incorpora un generador de eventos JSON, Promtail con extracción de timestamp y etiqueta level, y Loki con almacenamiento local persistente. Permite consultar las severidades y verificar un registro nuevo a lo largo de todo el pipeline.

Incluye validación de configuraciones, pruebas de contrato del generador, prueba PowerShell de ingesta, documentación y corrección de .gitignore para conservar capturas.

## Validación registrada

- Compose 5.6.1: modelo válido.
- Loki 3.6.19 y Promtail 3.6.11: configuraciones válidas.
- Generador: tres pruebas de contrato aprobadas.
- Pipeline nativo real: ingesta, filtro por level, timestamp JSON, reinicios y script PowerShell aprobados; ver docs/evidence/pr03-native-validation.json.
- Base de métricas en Windows: evidencia previa del estudiante.
- Docker Desktop en Windows: validación de configuraciones aprobada y siete contenedores en estado Up.
- Integración en Windows: probe nuevo recibido en Loki, filtro LogQL comprobado, severidades info/warn/error presentes y pruebas de integración del stack aprobadas.

## Evidencia y alcance

Las capturas originales están en docs/evidence/pr03-config-windows.png, pr03-containers-windows.png y pr03-integration-windows.png. El registro está en docs/evidence/pr03-windows-validation.md.

Grafana, Webhook, Jaeger y OpenTelemetry corresponden a PR #4 y PR #5. No se declara finalizado el stack completo con este bloque.
