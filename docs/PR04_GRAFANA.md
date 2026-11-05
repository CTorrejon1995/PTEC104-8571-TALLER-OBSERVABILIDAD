# PR #4 — Grafana, Dashboard Operativo y alerta Webhook

Este cambio añade Grafana y un receptor Webhook local a los siete servicios de métricas y logs. No requiere VirtualBox, Python instalado en Windows ni una cuenta cloud. La instrumentación de trazas corresponde al PR #5.

## 1. Preparación y despliegue en Windows

Requisitos: Docker Desktop abierto con contenedores Linux, Git y PowerShell. Ejecutar desde la raíz del repositorio. Si PowerShell bloquea los scripts, habilitarlos solo para esta ventana:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
```

Si aún no existe `.env`, copiarlo sin sobrescribirlo:

```powershell
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
.\dev.ps1 validate
.\dev.ps1 up -Build
.\dev.ps1 status
.\dev.ps1 test -Integration
```

`validate` comprueba Compose, Prometheus, Loki, Promtail y la coherencia de los JSON de Grafana. La integración comprueba además que Grafana carga los recursos y ejecuta consultas reales. Deben quedar **nueve servicios en estado Up**; los contenedores temporales de validación se eliminan al terminar.

Los valores predeterminados de Grafana son `admin` / `observability-lab`. Se pueden cambiar mediante `GRAFANA_ADMIN_USER` y `GRAFANA_ADMIN_PASSWORD` en `.env`. La prueba obtiene las credenciales resueltas de Compose sin imprimirlas. En un volumen de Grafana ya inicializado, cambiar estas variables no modifica una contraseña previamente guardada.

## 2. Dashboard y logs

Abrir <http://localhost:3000/d/operativo-observabilidad> e iniciar sesión. El dashboard se carga por archivos, dentro de la carpeta **Observabilidad**.

| Panel | Consulta o fuente | Interpretación |
|---|---|---|
| CPU | `100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{job="node-exporter",mode="idle"}[5m])))` | Porcentaje medio no ocioso del entorno Linux observado |
| Storage | `100 * (1 - node_filesystem_avail_bytes / node_filesystem_size_bytes)` filtrado por montaje | Porcentaje no disponible para usuarios normales; incluye bloques reservados |
| Red | `rate(ifHCInOctets[5m]) * 8 / 1000000` y `ifHCOutOctets`, por interfaz | Mbps entrantes y salientes de IF-MIB |
| Logs | `{job="cloud-logs",level=~"$nivel"}` | JSON de Loki con filtro de severidad |

En **Montaje de storage**, seleccionar `/mnt/docker-desktop-disk`, observado en la captura de Benja. No se fija `/dev/sdf`, porque el nombre del dispositivo puede cambiar al reiniciar. En otro sistema, elegir un montaje existente en el selector. CPU y storage corresponden a Linux/Docker/WSL; no son métricas nativas del disco C: ni de Windows.

El dashboard se actualiza cada **5 segundos**. El selector de severidad permite `info`, `warn` y `error`. Para ver streaming de logs, abrir **Explore**, elegir Loki, ejecutar `{job="cloud-logs"}` y activar **Live**.

La tasa de red requiere al menos dos muestras SNMP (scraping cada 30 segundos). Cero Mbps es un resultado válido con poco tráfico. La prueba espera hasta tres minutos para las tasas y rechaza series ausentes.

## 3. Alerta y aviso simulado

La regla **CPU alta · laboratorio**, UID `cpu-high`, consulta el mismo porcentaje del panel de CPU. Evalúa cada 10 segundos y alerta al superar **80 % durante 1 minuto**. La ventana de cálculo es de 5 minutos; es distinta del minuto de permanencia de la condición.

La consulta A obtiene CPU de Prometheus; B reduce al último valor y C compara con 80. La regla tiene estados explícitos `NoData` y `Error` para evitar tratar una pérdida de telemetría como estado sano. Una notificación de esos estados no sirve como evidencia de una alerta real de CPU.

El contacto `webhook-laboratorio` envía POST a `http://webhook-receiver:8080/webhook` por la red de Compose. La política agrupa por carpeta, nombre y ejecución de prueba, espera 5 segundos antes de notificar y admite avisos de resolución. No se necesita Alertmanager adicional ni un servicio externo.

Abrir:

- Reglas: <http://localhost:3000/alerting/list>.
- Contactos: <http://localhost:3000/alerting/notifications>.
- Avisos realmente recibidos: <http://localhost:8081>.
- JSON del receptor: <http://localhost:8081/events>.

### Prueba controlada reproducible

```powershell
.\dev.ps1 test -Integration
```

La prueba:

1. Verifica fuentes de datos, dashboard, consultas reales de CPU/storage/red y logs.
2. Copia los archivos de alertas a un directorio temporal ignorado por Git.
3. Cambia temporalmente el umbral a **-1 %** y la espera a **0 segundos**, conservando la consulta de CPU real. Añade un identificador `test_run` único. No aumenta la carga del equipo.
4. Recrea solamente Grafana para cargar esa configuración. El resto del stack sigue funcionando.
5. Espera una notificación `firing` enviada por Grafana al receptor, con el identificador de esta ejecución y el valor real de CPU. No envía manualmente un aviso para simular éxito.
6. En un bloque `finally`, restaura el montaje de archivos original, recrea Grafana y verifica **80 % / 1 minuto**, sin etiqueta de prueba.
7. Guarda `docs/evidence/pr04-windows-validation.json`, incluyendo resultado, valores y el aviso recibido. Un error queda registrado como `failed`, nunca como aprobado.

Esta prueba demuestra evaluación, enrutamiento y entrega del Webhook. **No demuestra que el equipo haya superado realmente el 80 %.** El aviso conserva la anotación de prueba para distinguirlo de un incidente normal.

Durante la prueba Grafana se reinicia dos veces; es normal que su interfaz no responda unos segundos. Dejar terminar el comando. Si se interrumpe cerrando la consola y queda aplicada la configuración temporal, abrir una nueva PowerShell en el proyecto y ejecutar:

```powershell
Remove-Item Env:GRAFANA_ALERTING_DIR -ErrorAction SilentlyContinue
docker compose up -d --no-deps --force-recreate grafana
```

Después comprobar en Grafana que la regla normal vuelve a 80 % / 1 minuto. No borrar volúmenes para corregirlo. No fijar `GRAFANA_ALERTING_DIR` en `.env`; la variable está reservada para la prueba.

## 4. Evidencias de Windows y cómo reproducirlas

Guardar capturas reales con estos nombres en `docs/evidence/`:

1. `pr04-dashboard-windows.png`: dashboard con CPU, storage, red y logs visibles; montaje correcto y datos presentes.
2. `pr04-alert-rule-windows.png`: regla normal con umbral 80 % y espera 1 minuto, después de la restauración.
3. `pr04-webhook-windows.png`: receptor mostrando el aviso `firing`, su `test_run`, valor de CPU y anotación de prueba controlada.

El archivo JSON de la integración se genera solo. Las capturas reales ya incorporadas muestran el dashboard, la regla normal, el receptor firing y el aviso resolved posterior. [PR04_VALIDACION.md](PR04_VALIDACION.md) documenta la integración aprobada en Windows y distingue su alcance de la preparación nativa. Para una nueva ejecución, guardar también el JSON generado en ese PC.

## 5. Diagnóstico

Si una versión anterior de la prueba termina con `No llego un Webhook firing real...`, aplicar la [corrección de UTF-8 y reconocimiento por UID](PR04_WEBHOOK_FIX.md) y repetir `tests/validation/test-grafana.ps1`. El script corregido lee el JSON como UTF-8 también en Windows PowerShell 5.1.


```powershell
.\dev.ps1 logs -Service grafana
.\dev.ps1 logs -Service webhook-receiver
```

Si el panel de storage está vacío, revisar el selector de montaje y consultar:

```powershell
(Invoke-RestMethod 'http://localhost:9090/api/v1/query?query=node_filesystem_size_bytes').data.result.metric | Select-Object mountpoint,fstype,device
```

Si la regla muestra `NoData`, comprobar primero los targets de Prometheus. Si la prueba no puede autenticar en Grafana, verificar la contraseña de ese volumen; no publicar `.env` ni borrar volúmenes como primer recurso.

## 6. Archivos y persistencia

- `dashboards/provisioning/`: fuentes y proveedor del dashboard.
- `dashboards/dashboards/operativo.json`: dashboard reproducible.
- `dashboards/alerting/`: regla, contacto Webhook y política de notificaciones.
- `tools/webhook-receiver/`: receptor Python estándar sin dependencias externas.
- `grafana-data`: base de datos y estado de Grafana.
- `webhook-data`: SQLite con los últimos 1.000 avisos recibidos; cada POST está limitado a 1 MiB.

El receptor escucha solo en `127.0.0.1:8081` del host y conserva avisos tras reiniciar. El simulador es el destino de notificaciones, mientras que la evaluación en Grafana y el envío HTTP son reales.

## Fuentes técnicas

- Grafana, provisioning de fuentes y dashboards: <https://grafana.com/docs/grafana/latest/administration/provisioning/>.
- Grafana, provisioning de alertas, contactos y políticas: <https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/file-provisioning/>.
- Grafana, API administrativa para recarga usada solo por el harness nativo: <https://grafana.com/docs/grafana/latest/developer-resources/api-reference/http-api/admin/>.
- Grafana 12.4.14, versión fijada: <https://github.com/grafana/grafana/releases/tag/v12.4.14>.
