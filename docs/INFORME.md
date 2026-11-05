# Informe técnico — Stack de Observabilidad

Estado de esta versión: métricas (PR #2), logs (PR #3), Grafana y alertas Webhook (PR #4) implementados y validados. La trazabilidad distribuida del PR #5 y el cierre integral de la práctica siguen pendientes; este documento es una memoria técnica incremental.

## 1. Paso a paso documentado

### Preparación y ejecución

Benja preparó Windows con Ubuntu en WSL 2, Docker Desktop con contenedores Linux y Git, clonó el repositorio y comprobó los comandos de Docker y Compose antes de aplicar los cambios por ramas. VirtualBox no se utiliza en este procedimiento.

Desde la raíz de **esta versión del proyecto**, ya sea el clon actualizado o la carpeta `proyecto/` del paquete:

```powershell
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
.\dev.ps1 validate
.\dev.ps1 up -Build
.\dev.ps1 status
.\dev.ps1 test -Integration
```

Si Windows PowerShell bloquea scripts, `Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned` habilita el procedimiento solo para esa ventana. La guía detallada está en [PR04_GRAFANA.md](PR04_GRAFANA.md).

La configuración hasta PR #4 define nueve servicios: Prometheus, Node Exporter, SNMP Exporter, agente SNMP simulado, Loki, Promtail, generador cloud-logs, Grafana y receptor Webhook. Los datos se conservan en volúmenes; `dev.ps1 down` detiene el entorno sin eliminarlos.

### Métricas y logs

Prometheus obtiene métricas de sí mismo, de Node Exporter y del agente de red mediante SNMP Exporter. La integración verificó los tres targets UP y la disponibilidad de node_cpu_seconds_total, ifHCInOctets e ifHCOutOctets.

El generador escribe JSON en un volumen compartido; Promtail extrae timestamp y level y envía las líneas a Loki. La integración crea un probe nuevo, lo encuentra mediante LogQL con level=error y verifica info, warn y error. No se acepta un log histórico cualquiera como prueba de ingesta actual. Guía: [PR03_LOGS.md](PR03_LOGS.md).

### Dashboard y alerta

Abrir <http://localhost:3000/d/operativo-observabilidad> con `admin` / `observability-lab` como credenciales iniciales de laboratorio. El provisioning crea automáticamente las fuentes Prometheus/Loki, el dashboard y las alertas. En storage se selecciona `/mnt/docker-desktop-disk`, identificado en las métricas reales del equipo.

El Dashboard Operativo reúne CPU, storage, tráfico SNMP y logs JSON con filtro de severidad y actualización de 5 segundos. Para streaming de logs se puede abrir Explore, elegir Loki y activar Live con `{job="cloud-logs"}`.

La regla normal evalúa CPU >80 % durante 1 minuto, cada 10 segundos. La prueba controlada mantiene la consulta real pero cambia temporalmente el umbral a -1 % y la espera a 0s, recibe un Webhook firing con UID y test_run únicos y restaura 80 % / 1 minuto. Esta prueba no demuestra una sobrecarga real por encima de 80 %.

### Validación realizada

La ejecución completa de Windows aprobó validación estática, métricas, logs y Grafana/Webhook. El terminal informó `Pruebas de integracion del stack aprobadas.` y verificó la restauración de la regla normal. Las capturas posteriores muestran el dashboard, la regla Normal y avisos firing/resolved para la misma prueba. El estado y los registros están en [PR04_VALIDACION.md](PR04_VALIDACION.md).

El script escribió `docs/evidence/pr04-windows-validation.json` en el PC de Benja. Debe conservarse y añadirse al commit desde ese clon; no se inventa aquí su contenido. La preparación Linux tiene sus propios informes nativos y no se presenta como ejecución Docker de Windows.

## 2. Justificación técnica

### CPU

```promql
100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{job="node-exporter",mode="idle"}[5m])))
```

El contador acumula segundos de CPU por modo. `rate()` estima la proporción de tiempo ocioso; restarla de uno y multiplicar por cien produce el porcentaje medio no ocioso. La ventana de 5 minutos suaviza variaciones. En la alerta, A obtiene el porcentaje, B reduce al último valor y C compara con 80. El período de permanencia de 1 minuto evita alertar por una sola evaluación; es distinto de la ventana de cálculo y de la evaluación cada 10 segundos.

`NoData` y `Error` se mantienen explícitos para distinguir una pérdida de telemetría de un estado sano. El test no acepta avisos DatasourceNoData o DatasourceError como prueba de una alerta real de CPU.

### Tráfico SNMP en Mbps

```promql
sum by (instance, ifName) (rate(ifHCInOctets{job="snmp-device",ifName!="lo"}[5m]) * 8 / 1000000)
sum by (instance, ifName) (rate(ifHCOutOctets{job="snmp-device",ifName!="lo"}[5m]) * 8 / 1000000)
```

IF-MIB proporciona contadores de octetos de 64 bits. `rate()` calcula octetos por segundo; multiplicar por ocho convierte a bits y dividir por un millón expresa Mbps decimales. ifName permite separar interfaces y se excluye loopback. La captura del laboratorio muestra tráfico pequeño y Grafana ajusta visualmente la escala a b/s; la consulta conserva la conversión a Mbps.

### Storage y alcance de las métricas

```promql
100 * (1 - node_filesystem_avail_bytes{job="node-exporter",mountpoint="/mnt/docker-desktop-disk"} / node_filesystem_size_bytes{job="node-exporter",mountpoint="/mnt/docker-desktop-disk"})
```

El panel calcula espacio no disponible para usuarios normales, incluidos bloques reservados. El montaje se elige con un selector; no se fija /dev/sdf porque el dispositivo puede cambiar al reiniciar. En la captura, el resultado fue 5,5 %.

Node Exporter observa el entorno Linux de Docker Desktop/WSL. CPU y storage no son telemetría nativa de Windows ni una medición del disco C:. Esta limitación forma parte de la interpretación del laboratorio.

### Logs y etiquetas

```logql
{job="cloud-logs",level="error"}
{job="cloud-logs",level="error"} |= "pr3-probe-"
```

level tiene pocos valores estables y permite filtrar severidad sin crear un stream por solicitud. request_id y el mensaje quedan en el cuerpo JSON para evitar alta cardinalidad. Promtail aplica el timestamp UTC del evento y conserva el registro para inspección.

El generador rota archivos a 5 MiB con tres respaldos. Loki usa almacenamiento persistente, WAL, índices TSDB y retención de siete días. Las posiciones de Promtail permiten continuar la lectura después de reiniciar; las pruebas nativas verificaron recuperación de registros y reanudación de ingesta.

### Provisioning, enrutamiento y prueba controlada

Los UID estables vinculan fuentes, dashboard y reglas sin repetir configuración manual. La política agrupa por carpeta, regla y ejecución de prueba y envía al contacto `webhook-laboratorio`, que llama al receptor por la red de Compose. SQLite conserva los avisos para revisión; la evaluación de Grafana y el HTTP son reales, aunque el destino representa una simulación local de notificaciones.

La prueba utiliza un test_run único y exige ruleUID=cpu-high, estado firing y un valor válido de CPU. La lectura UTF-8 explícita evita que Windows PowerShell altere el título al leer JSON sin BOM. El primer timeout motivó esa corrección y el reemplazo de la comparación por nombre por un UID estable; la repetición posterior de Windows pasó.

## 3. Evidencia de funcionamiento

### Métricas y logs anteriores

![Validación de métricas en Windows](evidence/pr02-validation-windows.png)

![Métricas y contenedores en Windows](evidence/pr02-metrics-windows.png)

![Siete contenedores hasta PR #3](evidence/pr03-containers-windows.png)

![Probe nuevo recibido en Loki](evidence/pr03-integration-windows.png)

Registros: [logs en Windows](evidence/pr03-windows-validation.md) e [integración nativa de logs](evidence/pr03-native-validation.json).

### Integración completa hasta PR #4

![Integración de métricas, logs y Grafana/Webhook aprobada](evidence/pr04-stack-integration-windows.png)

El registro de esta captura está en [pr04-stack-windows-validation.md](evidence/pr04-stack-windows-validation.md). Confirma targets UP, métricas disponibles, un probe nuevo en Loki, fuentes Grafana OK, aviso Webhook recibido y regla normal restaurada.

### Dashboard Operativo

![Dashboard con CPU, storage, red y logs](evidence/pr04-dashboard-windows.png)

El montaje seleccionado es /mnt/docker-desktop-disk; se observan datos de CPU, 5,5 % de espacio no disponible, series de eth0 y eventos JSON. [Registro de observación](evidence/pr04-dashboard-windows.md).

### Regla normal

![Regla CPU >80 con estado Normal](evidence/pr04-alert-rule-windows.png)

La captura muestra CPU de aproximadamente 1,21 %, condición C `Is above 80`, estado Normal y evaluación cada 10 segundos. Su descripción menciona 1 minuto; el campo for=1m fue comprobado por la integración. [Registro de observación](evidence/pr04-alert-rule-windows.md).

### Webhook de activación y aviso posterior

![Aviso firing recibido por el receptor](evidence/pr04-webhook-windows.png)

![Aviso resolved de la misma ejecución](evidence/pr04-webhook-resolved-windows.png)

Los eventos 9 y 10 comparten test_run `pr4-784177d6acb445e7ac34db2aae24f07a`. La CPU registrada ronda 1,6248 %, suficiente para el umbral temporal -1 %, no para presentar un incidente real >80 %. El aviso resolved incluye MissingSeries al retirarse la serie de prueba; la restauración de la regla se comprobó por separado. [Registro del receptor](evidence/pr04-webhook-windows.md).

### Alcance y archivos de evidencia

La integración real de Windows y las tres vistas requeridas por PR #4 están documentadas con capturas originales. [Resumen derivado de esas capturas](evidence/pr04-windows-evidence-summary.json).

La preparación Linux consta en [pr04-native-validation.json](evidence/pr04-native-validation.json): pipeline real, valor predeterminado ANSI emulado, Webhook, restauración y reinicio de Grafana. Omite SNMP y utiliza un filesystem Linux local; la ejecución de Windows cubrió las consultas SNMP y el montaje de Docker Desktop.

Queda pendiente la transacción distribuida y su análisis de latencia en Jaeger, junto a la validación de OpenTelemetry Collector y microservicios del PR #5. No se incluyen trazas ficticias ni se considera finalizada toda la práctica.

## 4. Conclusiones y lecciones aprendidas

Prometheus permitió comprobar disponibilidad, CPU y red; Loki añadió registros filtrables por severidad y conservó el timestamp del evento. Grafana reunió estas señales en una vista operativa y la notificación Webhook demostró evaluación, enrutamiento, entrega e inspección de avisos.

Los identificadores únicos evitaron aceptar datos antiguos como prueba de funcionamiento actual. La persistencia de logs y avisos separa los datos del ciclo de vida de los contenedores. El incidente de codificación mostró la importancia de declarar UTF-8 y usar UID estables en validaciones entre plataformas.

La prueba de alertas evitó sobrecargar el equipo: cambió temporalmente una condición, registró el aviso y comprobó su restauración. Elegir el montaje a partir de las métricas observadas evitó atribuir el almacenamiento de Docker a Windows de forma incorrecta. El próximo paso es añadir trazas para localizar latencia entre servicios y completar el tercer pilar.

Promtail se mantiene por exigencia del enunciado pese a su fin de soporte; una evolución del proyecto deberá evaluar un agente mantenido como Alloy. Las conclusiones siguen siendo parciales hasta incorporar y validar las trazas del PR #5 y cerrar la entrega completa.

## Referencias

- Prometheus, funciones PromQL: <https://prometheus.io/docs/prometheus/latest/querying/functions/>.
- Node Exporter: <https://github.com/prometheus/node_exporter>.
- SNMP Exporter: <https://github.com/prometheus/snmp_exporter>.
- IF-MIB, RFC 2863: <https://www.rfc-editor.org/rfc/rfc2863>.
- Grafana, provisioning de alertas: <https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/file-provisioning/>.
- Microsoft, codificación de Windows PowerShell: <https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding?view=powershell-5.1>.
