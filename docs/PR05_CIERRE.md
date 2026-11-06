# Cierre documental — PR #5

## Resultado verificado

La integración completa en Docker Desktop para Windows aprobó métricas, logs, Grafana/Webhook y trazas. Jaeger muestra dos servicios y seis spans; la transacción lenta dura unos 627 ms y simulated-db-query de service-b concentra 600.125 ms. Las capturas originales y el análisis están incorporados a INFORME.md.

El parche de cierre solo modifica documentación y añade capturas originales. No modifica configuraciones de ejecución ni sobrescribe los JSON de validación generados en Windows.

## Aplicar el cierre

Para una instalación que ya tiene PR5 y la corrección /api/v3/services, aplicar únicamente PR5_CIERRE.patch desde la raíz del clon. No reaplicar PR5.patch.

En PowerShell, ejecutar uno por uno:

```powershell
Set-Location "C:\Users\benja\proyectos\PTEC104-8571-TALLER-OBSERVABILIDAD"
git apply --ignore-space-change --check "C:\Users\benja\Desktop\PR5_Trazas_Benja\PR5_CIERRE.patch"
git apply --ignore-space-change "C:\Users\benja\Desktop\PR5_Trazas_Benja\PR5_CIERRE.patch"
git branch --show-current
git status --short
git diff --check
```

La rama prevista es feature/pr-05-trazas. Si git apply vuelve al prompt sin mensajes, terminó correctamente. Si aparece un error, conservarlo y detener los pasos siguientes.

## Conservar el resultado del equipo Windows

La prueba genera en docs/evidence/ pr05-windows-validation.json, pr05-windows-fast-trace.json, pr05-windows-slow-trace.json y pr05-windows-analysis.md. Deben permanecer en el clon y añadirse al commit junto a las capturas. El parche no genera ni reconstruye esos archivos.

Revisar el informe y las capturas antes del commit. Desde la rama prevista:

```powershell
git add README.md app configs dev.ps1 docker-compose.yml tests docs
git diff --cached --stat
git commit -m "feat(tracing): add OpenTelemetry collector Jaeger and traced microservices"
git push -u origin feature/pr-05-trazas
```

Abrir el Pull Request con base main y comparación feature/pr-05-trazas. El título puede ser el mismo del commit; el texto de docs/PR05_DESCRIPCION.md está actualizado para copiar en su descripción. El número asignado por GitHub puede diferir del nombre de esta etapa.

Las pruebas de runtime ya aprobaron antes de este cierre, que solo añade documentación y capturas. La aprobación técnica no significa que el commit, el push o la fusión del Pull Request ya se hayan realizado.
