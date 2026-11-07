# Corrección de la comprobación Webhook en Windows

La primera ejecución de Benja llegó a la prueba controlada de Grafana, agotó la espera del aviso y restauró correctamente la regla normal de CPU > 80 % durante 1 minuto. La captura real está en `evidence/pr-04/screenshots/pr04-webhook-timeout-windows.png`. No se registra esa ejecución como aprobada.

## Problema encontrado

El script leía `rules.json` mediante `Get-Content -Raw` sin indicar codificación. Windows PowerShell 5.1 usa su página ANSI para archivos sin BOM. El JSON del proyecto es UTF-8 sin BOM y contiene el título `CPU alta · laboratorio`. Con Windows-1252 se convierte en `CPU alta Â· laboratorio`; la comparación por nombre falla aunque llegue el aviso.

Esta diferencia se reprodujo con PowerShell y ambas lecturas del mismo archivo. Explica una causa posible del timeout observado, pero la captura por sí sola no confirma si el receptor de Windows recibió la notificación.

## Cambios

- Lectura explícita `Get-Content -Raw -Encoding UTF8` antes de generar la regla temporal.
- Identificación del aviso por `ruleUID=cpu-high` y el identificador único `test_run`, sin depender del nombre visible.
- Se siguen exigiendo estado `firing` y un valor real de CPU válido. Los avisos `DatasourceError` y `DatasourceNoData` no aprueban la prueba.
- El informe incluye el número de eventos y un resumen de los avisos observados. Si hay otro timeout, conserva también la evaluación de reglas para diagnosticarlo.
- Se conserva la restauración de 80 % / 1 minuto al terminar.

## Aplicación sobre el PR #4 original

Aplicar una sola vez el archivo `PR4_WEBHOOK_FIX.patch` con `git apply --ignore-space-change --check` y luego `git apply --ignore-space-change`. No volver a aplicar el parche completo PR4.patch sobre un proyecto que ya lo tiene.

Después ejecutar únicamente la integración de Grafana:

```powershell
.\tests\validation\test-grafana.ps1
```

Si pasa, ejecutar la integración completa:

```powershell
.\dev.ps1 test -Integration
```

La repetición en Windows aprobó la prueba independiente y la integración completa; se recibieron además las capturas del dashboard, la regla y el receptor. El resultado actual y sus fuentes están en [PR04_VALIDACION.md](PR04_VALIDACION.md). La prueba Linux con el valor ANSI emulado documenta la regresión; la evidencia de Windows corresponde a la ejecución real posterior.

Fuente sobre la codificación de Windows PowerShell: <https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding?view=powershell-5.1>.
