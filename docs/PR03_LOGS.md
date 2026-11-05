# PR #3 — Guía para Benja

## Alcance y estado

Este bloque incorpora Loki, Promtail y logs JSON sobre la base de métricas del commit d2197d9c2a4256511bc326db0e67d1c3e185e8c0. La rama propuesta es `feature/pr-03-logs`. Grafana, Webhook, Jaeger y OTEL se incorporan en los bloques siguientes.

Se validaron las configuraciones con sus binarios oficiales y el pipeline real en procesos Linux nativos. Después, Benja comprobó los servicios nuevos en Docker Desktop para Windows: siete contenedores Up y pruebas de integración del stack aprobadas. Las capturas originales y el registro se conservan en evidence.

## 1. Aplicar los cambios

El ZIP incluye un parche y una copia de referencia del proyecto. Extraerlo en una carpeta aparte. Desde el repositorio clonado, con la rama indicada seleccionada:

Para una instalación que ya tiene el PR #3 aplicado y probado, usar el archivo PR3_CIERRE.patch del ZIP actualizado: solo agrega las evidencias de Windows y actualiza los documentos de validación. PR3.patch contiene la implementación completa para una copia que todavía está en la base PR #2.

~~~powershell
git status
$pr3Patch = (Read-Host "Pega la ruta completa del archivo PR3.patch").Trim('"')
git apply --ignore-space-change --check "$pr3Patch"
~~~

Si el chequeo termina sin error:

~~~powershell
git apply --ignore-space-change "$pr3Patch"
git status --short
~~~

El parche conserva .git y .env. Si un archivo fue modificado previamente o el parche ya está aplicado, Git debe avisarlo; resolver ese caso antes de copiar otros archivos.

La opción ignore-space-change permite aplicar el parche cuando el checkout de Windows usa finales de línea CRLF. Se comprobó tanto con LF como con CRLF.

## 2. Levantar y comprobar

Dejar Docker Desktop abierto. Todos los comandos siguientes van en PowerShell desde la raíz del repositorio.

~~~powershell
.\dev.ps1 validate
.\dev.ps1 up -Build
.\dev.ps1 status
.\dev.ps1 test -Integration
~~~

Si una nueva sesión de PowerShell tiene bloqueados los scripts, usar la habilitación temporal que ya se comprobó:

~~~powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
~~~

La primera ejecución descarga Loki y Promtail; up -Build también construye el generador. No necesita instalar Python en Windows. Deben quedar siete servicios levantados: los cuatro de métricas y loki, promtail y cloud-logs.

La prueba debe terminar con `Pruebas de integracion del stack aprobadas.` después de aprobar métricas y logs. El probe debe haber sido generado durante esa ejecución.

## 3. Consultar los errores

Loki ofrece una API; la interfaz gráfica de Grafana se agrega en PR #4.

~~~powershell
$query = [uri]::EscapeDataString('{job="cloud-logs",level="error"}')
$start = [DateTimeOffset]::UtcNow.AddMinutes(-15).ToUnixTimeMilliseconds().ToString() + '000000'
$url = "http://localhost:3100/loki/api/v1/query_range?query=$query&start=$start&limit=5"
$result = Invoke-RestMethod -Uri $url
$result.data.result | ConvertTo-Json -Depth 10
~~~

Debe haber streams con level=error y líneas JSON con el mismo nivel. Consultas LogQL para usar después en Grafana:

~~~logql
{job="cloud-logs"}
{job="cloud-logs",level="error"}
{job="cloud-logs",level="warn"}
{job="cloud-logs"} | json | level="error"
~~~

## 4. Evidencias

Guardar capturas reales de los siete contenedores, las pruebas de métricas y logs aprobadas y la consulta por severidad. Incorporarlas en `docs/evidence/` y enlazarlas desde `docs/INFORME.md`. La regla de Git que ocultaba esa carpeta se corrigió.

Los archivos `pr02-validation-windows.png` y `pr02-metrics-windows.png` corresponden a las capturas reales de la base. La prueba nativa se conserva en `pr03-native-validation.json`. Las capturas `pr03-config-windows.png`, `pr03-containers-windows.png` y `pr03-integration-windows.png` documentan el PR #3 ejecutado en Docker Desktop.

## 5. Publicar el PR

Después de pasar las pruebas de Windows y completar sus evidencias:

~~~powershell
git diff --check
git diff
git add .gitignore docker-compose.yml dev.ps1 README.md configs simulators tests docs
git diff --cached --stat
git commit -m "feat(logs): integrate Loki Promtail and JSON cloud logs"
git push -u origin feature/pr-03-logs
~~~

En GitHub crear un Pull Request hacia main. El número que asigne GitHub puede diferir del número de etapa del trabajo. Usar como título `PR #3 - Centralizacion de logs JSON con Loki y Promtail` y tomar el texto de `docs/PR03_DESCRIPCION.md`.

## Diagnóstico

~~~powershell
.\dev.ps1 logs -Service loki
.\dev.ps1 logs -Service promtail
.\dev.ps1 logs -Service cloud-logs
~~~

Cada comando sigue logs hasta presionar Ctrl+C. Si un puerto está ocupado, identificar antes qué proceso lo usa. Si falla la consulta, comprobar los endpoints http://localhost:3100/ready y http://localhost:9080/ready. El inicio de Loki puede tardar varias decenas de segundos; la prueba espera hasta 90 segundos por etapa.

`dev.ps1 down` conserva los volúmenes. `dev.ps1 clean` elimina datos y requiere confirmación; no se necesita para aplicar este PR.

## Decisiones técnicas

Se usa un volumen Docker para los archivos, evitando dependencias de rutas Linux del host Windows. El JSON conserva los campos originales. Solo level se extrae como etiqueta dinámica; request_id permanece en el contenido para no crear un stream por solicitud. Las posiciones de Promtail persisten y Loki guarda índices, chunks y WAL en su volumen, con retención de siete días.

Promtail está fuera de soporte según Grafana. Se fija 3.6.11 porque la consigna exige este agente; Loki se fija en 3.6.19 y la compatibilidad se comprobó con ingesta y consultas reales. Para una continuidad posterior al taller corresponde evaluar Alloy.

## Referencias

- https://grafana.com/docs/loki/latest/send-data/promtail/
- https://grafana.com/docs/loki/latest/configure/
- https://grafana.com/docs/loki/latest/reference/loki-http-api/
- https://github.com/grafana/loki/releases/tag/v3.6.19
- https://github.com/grafana/loki/releases/tag/v3.6.11
