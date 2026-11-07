# Validación — PR #5

**Estado: integración completa aprobada en Docker Desktop para Windows y traza observada en Jaeger.** Las capturas originales y su transcripción están en [evidence/pr-05/README.md#registro-pr05-windows-validation-md](evidence/pr-05/README.md#registro-pr05-windows-validation-md).

| Comprobación | Resultado | Evidencia o alcance |
|---|---|---|
| Modelo Compose y configuraciones | Aprobados | Preparación y validación estática de Windows |
| Pruebas unitarias de preparación | Nueve aprobadas | Tres de parámetros de app y seis existentes de generador/receptor |
| Dos procesos HTTP, contexto W3C y SDK OTLP | Aprobados en preparación | Captura protobuf real; seis spans por solicitud; errores 400/503/502 comprobados |
| Backend nativo en el ejecutor de preparación | No pudo arrancar | Limitación histórica de visibilidad del PID en /proc; no se presenta como aprobado |
| Trece contenedores Docker | Running | [Prueba independiente de Windows](evidence/pr-05/screenshots/pr05-traces-windows.png) |
| Métricas y logs | Aprobados en Windows | Targets UP, contadores disponibles y probe nuevo en Loki |
| Grafana y Webhook | Aprobados en Windows | Fuentes y consultas correctas, evento 15 y regla normal restaurada |
| Collector y Jaeger | READY en Windows | [Integración completa](evidence/pr-05/screenshots/pr05-integration-windows.png) |
| Ingesta y consulta de trazas nuevas | Aprobadas en Windows | Solicitudes fast/slow con ambos servicios y verificación de referencias padre-hijo |
| Integración de todo el stack | Aprobada en Windows | Mensaje final de aprobación después de métricas, logs, Grafana y trazas |
| Evidencia visual de Jaeger | Recibida | [Transacción lenta](evidence/pr-05/screenshots/pr05-jaeger-trace-windows.png): dos servicios y seis spans |
| Análisis de latencia | Documentado | Transacción de unos 627 ms; mayor span hoja de 600.125 ms, aproximadamente 96 % del total |

## Corrección de compatibilidad

La primera prueba de disponibilidad consultaba /api/services y recibió HTTP 404. Se corrigieron el script Windows y el runner nativo para usar /api/v3/services, conforme a la [migración oficial de Jaeger](https://github.com/jaegertracing/jaeger/pull/9260). La consulta individual de /api/traces/{traceID} conservada en esta versión sigue validando el contenido real de las trazas. Después de la corrección aprobaron tanto la prueba independiente como la integración completa de Windows.

## Evidencia y trazabilidad

- [Prueba independiente y trece contenedores Running](evidence/pr-05/README.md#registro-pr05-traces-windows-md).
- [Integración completa y análisis de la captura de Jaeger](evidence/pr-05/README.md#registro-pr05-windows-validation-md).
- [Resultados históricos de SDK y protocolo OTLP](evidence/pr-05/results/pr05-native-sdk-validation.json).
- [Límite del backend nativo en preparación](evidence/pr-05/results/pr05-native-backend-check.json).
- [Versiones, assets y verificaciones de preparación](evidence/pr-05/results/pr05-preparation-checks.json).

Los campos Windows pendiente de los informes de preparación describen el estado histórico de esa ejecución. El resultado posterior de Docker Desktop se documenta por separado con las capturas originales.

Los JSON de Windows y el análisis detallado se generan en el clon mediante el script y se versionan desde ese equipo. No se han reconstruido a partir de las imágenes. El retardo de la operación es una simulación explícita; la instrumentación, la exportación y el almacenamiento/consulta en Jaeger son reales.
