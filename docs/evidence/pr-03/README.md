# Evidencias PR #3

Registro organizado del bloque pr-03. Las capturas y los resultados mantienen sus nombres originales.

> Las secciones documentales siguientes reproducen las notas anteriores e indican su archivo de origen; no representan nuevas ejecuciones de pruebas.

## Archivos de evidencia

| Archivo | Tipo |
|---|---|
| [pr03-config-windows.png](screenshots/pr03-config-windows.png) | screenshots |
| [pr03-containers-windows.png](screenshots/pr03-containers-windows.png) | screenshots |
| [pr03-integration-windows.png](screenshots/pr03-integration-windows.png) | screenshots |
| [pr03-native-validation.json](results/pr03-native-validation.json) | results |

## Registro: pr03-windows-validation.md

*Fuente histÃ³rica: `docs/evidence/pr03-windows-validation.md`.*

# PR #3 — Validación real en Windows

Fecha: 5 de noviembre de 2026. Ejecución realizada por Benja en su equipo Windows con Docker Desktop.

| Paso | Evidencia | Resultado observado |
|---|---|---|
| dev.ps1 validate | pr03-config-windows.png | Valid config file. No syntax issues found. Validacion estatica del stack correcta. |
| dev.ps1 up -Build y status | pr03-containers-windows.png | Siete servicios Up: cloud-logs, Loki, Promtail y los cuatro servicios de métricas. |
| dev.ps1 test -Integration | pr03-integration-windows.png | Probe nuevo recibido en Loki, filtro LogQL comprobado y severidades info/warn/error indexadas. |
| Resultado final del script | pr03-integration-windows.png | Pruebas de integracion de logs aprobadas. Pruebas de integracion del stack aprobadas. |

Las imágenes son las capturas originales proporcionadas durante la ejecución. El JSON visible del probe identifica un registro sintético de nivel error; la consulta usa job=cloud-logs, level=error y su identificador nuevo.

Esta evidencia corresponde al PR #3. No demuestra todavía dashboards, alertas Webhook ni trazas distribuidas, que corresponden a los próximos bloques.

---

