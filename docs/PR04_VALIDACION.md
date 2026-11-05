# Validación — PR #4

**Estado: integración completa aprobada en Windows y evidencias visuales recibidas.** La implementación y la documentación del PR #4 están listas para revisión. Las trazas del PR #5 y el cierre integral de la entrega siguen pendientes.

## Comprobaciones y evidencia

| Comprobación | Resultado y evidencia | Alcance |
|---|---|---|
| Compose, configuraciones y scripts | Validación estática aprobada en la ejecución completa de Windows | Captura `evidence/pr04-stack-integration-windows.png` |
| Pruebas del generador y receptor | Tres pruebas del generador y tres pruebas HTTP/SQLite aprobadas en preparación | Registro `evidence/pr04-preparation-checks.json` |
| Pipeline real Linux y reinicio | Aprobado, incluida la lectura UTF-8 con valor predeterminado ANSI emulado | `evidence/pr04-native-validation.json`; omite SNMP y utiliza un filesystem Linux local |
| Métricas en Docker Desktop | Prometheus READY; prometheus, node-exporter y snmp-device UP; CPU y contadores de red disponibles | Integración completa de Windows |
| Ingesta de logs | Probe nuevo recibido en Loki; filtro level=error y severidades info/warn/error comprobados | Integración completa de Windows |
| Fuentes y consultas de Grafana | Prometheus/Loki OK; consultas de CPU, storage, SNMP y logs aprobadas | Integración completa de Windows |
| Dashboard | Cuatro paneles con datos; montaje /mnt/docker-desktop-disk; actualización de 5 segundos | `evidence/pr04-dashboard-windows.png` |
| Regla normal | Estado Normal, CPU alrededor de 1,21 %, umbral >80 y evaluación cada 10 segundos; la integración verificó for=1m | `evidence/pr04-alert-rule-windows.png` y salida de integración |
| Webhook controlado | Evento 9 firing y evento 10 resolved para el mismo test_run | `evidence/pr04-webhook-windows.png` y `evidence/pr04-webhook-resolved-windows.png` |
| Restauración | CPU >80 % / 1 minuto, sin configuración de prueba, verificada al terminar | Mensaje de restauración y aprobación en la integración completa |

El proyecto define nueve servicios hasta este PR. La evidencia de Windows demuestra sus recorridos funcionales; no se añade una captura inexistente de `docker compose ps` con esos nueve servicios.

## Prueba de notificación

La prueba conserva la consulta real de CPU y baja temporalmente el umbral a -1 % con espera 0s. Exige un aviso firing de ruleUID=cpu-high con el test_run único y un porcentaje real de CPU válido. No acepta una notificación de DatasourceError o DatasourceNoData como éxito. Finalmente restaura 80 % / 1 minuto.

El Webhook contiene la anotación de prueba controlada. El aviso posterior resolved incluye MissingSeries al retirarse la serie de prueba; no se presenta como un incidente real de CPU por encima del 80 % ni como evidencia de una caída de CPU.

## Corrección de compatibilidad

El primer intento de Windows agotó la espera al reconocer el Webhook y restauró la regla normal. Se detectó una lectura ANSI implícita de un JSON UTF-8 y una comparación por nombre sensible a esa corrupción. Se corrigió con `-Encoding UTF8` y reconocimiento por UID estable. La diferencia UTF-8/Windows-1252 se reprodujo y la integración real pasó con el valor ANSI predeterminado emulado. Después Benja aprobó tanto la prueba independiente de Grafana como la integración completa en Windows.

La primera captura fallida se conserva para documentar el diagnóstico, no como resultado aprobado. Detalles: [PR04_WEBHOOK_FIX.md](PR04_WEBHOOK_FIX.md).

## Registros

- [Integración completa de Windows](evidence/pr04-stack-windows-validation.md).
- [Prueba independiente de Grafana/Webhook](evidence/pr04-grafana-windows-validation.md).
- [Dashboard](evidence/pr04-dashboard-windows.md).
- [Regla normal](evidence/pr04-alert-rule-windows.md).
- [Avisos firing y resolved](evidence/pr04-webhook-windows.md).
- [Resumen derivado de capturas originales](evidence/pr04-windows-evidence-summary.json).

El script guarda `evidence/pr04-windows-validation.json` en el PC de Benja. Ese archivo debe permanecer en su clon y añadirse al commit. No se reconstruyen aquí sus bytes: el paquete incluye las capturas originales y un resumen identificado expresamente como derivado de ellas.
