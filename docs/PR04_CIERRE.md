# Cierre del PR #4 — Benja

El código de Grafana y Webhook está validado en Windows. Este cierre incorpora las capturas originales y actualiza el informe y la descripción del PR; no cambia servicios ni reglas.

## 1. Descargar y extraer

Descargar la versión actualizada de `PR4_Grafana_Benja.zip` y extraerla en la misma carpeta que ya utilizaste:

`C:\Users\benja\Desktop\PR4_Grafana_Benja`

Debe existir `C:\Users\benja\Desktop\PR4_Grafana_Benja\PR4_CIERRE.patch`. El archivo es nuevo en esta versión del ZIP. La carpeta `proyecto/` es una copia de referencia, no es necesario copiarla sobre el clon.

## 2. Aplicar solo el cierre

En PowerShell, ejecutar uno por uno:

```powershell
Set-Location "C:\Users\benja\proyectos\PTEC104-8571-TALLER-OBSERVABILIDAD"
git branch --show-current
git apply --ignore-space-change --check "C:\Users\benja\Desktop\PR4_Grafana_Benja\PR4_CIERRE.patch"
```

La rama debe ser `feature/pr-04-grafana-alertas`. Si `--check` vuelve al prompt sin mensajes, la comprobación fue correcta. Si hay un error, conservarlo y revisarlo antes de continuar.

```powershell
git apply --ignore-space-change "C:\Users\benja\Desktop\PR4_Grafana_Benja\PR4_CIERRE.patch"
git diff --check
git status --short
```

Aplicar este parche una sola vez. El clon ya tiene PR4.patch y PR4_WEBHOOK_FIX.patch aplicados; no repetir esos dos. `PR4_CIERRE.patch` conserva el informe JSON que la integración generó en tu PC y no lo sustituye por datos reconstruidos.

## 3. Revisar y crear el commit

```powershell
git add .env.example .gitignore README.md dev.ps1 docker-compose.yml dashboards tools tests docs
git diff --cached --stat
```

Revisar que aparezcan las configuraciones, scripts, documentación y capturas del PR #4. También debe incorporarse tu archivo generado `docs/evidence/pr04-windows-validation.json`.

```powershell
git commit -m "feat(grafana): add operational dashboard and CPU webhook alert"
git push -u origin feature/pr-04-grafana-alertas
```

No hace falta repetir la integración para este cierre: las últimas modificaciones son documentación y evidencias. La prueba completa ya aprobó métricas, logs, Grafana y Webhook y restauró la regla normal.

## 4. Crear el Pull Request

En GitHub elegir:

- Base: `main`.
- Comparación: `feature/pr-04-grafana-alertas`.
- Título: `feat(grafana): add operational dashboard and CPU webhook alert`.
- Descripción: contenido de `docs/PR04_DESCRIPCION.md`.

Para leer la descripción en PowerShell sin alterar caracteres:

```powershell
Get-Content .\docs\PR04_DESCRIPCION.md -Raw -Encoding UTF8
```

El número automático de GitHub puede ser distinto del nombre de la etapa PR #4. Después de revisar e integrar ese PR, actualizar main antes de crear la rama del PR #5 de trazas.

## Evidencias incluidas

- Integración completa de Windows aprobada.
- Dashboard con CPU, storage, red y logs.
- Regla normal de CPU >80 %, con período de 1 minuto comprobado por el script.
- Receptor con eventos firing y resolved para el mismo test_run.
- Informe técnico actualizado y descripción del PR.

El proyecto completo aún requiere Jaeger, OpenTelemetry Collector, microservicios y análisis de una traza en el PR #5, además del cierre final de la práctica.
