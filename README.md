# Stack de Observabilidad Completo

Proyecto académico de Infraestructura TI para desplegar y validar una plataforma de observabilidad Open Source mediante Docker Compose. El objetivo final es integrar métricas, logs y trazas distribuidas en un entorno local reproducible.

## Objetivos

- Recolectar métricas de infraestructura y red.
- Centralizar y consultar registros estructurados.
- Visualizar métricas y logs y demostrar alertamiento.
- Instrumentar una aplicación de microservicios y analizar trazas distribuidas.

## Arquitectura prevista

El stack se organiza en cuatro capas:

1. **Fuentes:** sistema operativo, dispositivo de red simulado, logs JSON y microservicios.
2. **Recolección y procesamiento:** Prometheus, Node Exporter, SNMP Exporter, Promtail y OpenTelemetry Collector.
3. **Almacenamiento y consulta:** Prometheus, Loki y Jaeger.
4. **Visualización y operación:** Grafana, dashboards y notificaciones Webhook.

El desarrollo se implementa incrementalmente en seis Pull Requests. PR #1 establece la fundación del repositorio. PR #2 incorpora la recolección de métricas; los PR posteriores añadirán logs, visualización, alertas y trazas.

Esta versión incorpora métricas (PR #2), logs (PR #3) y Grafana con alertas Webhook (PR #4). Trazas (PR #5) y cierre integral (PR #6) siguen pendientes.

## PR #4 — Grafana y alerta Webhook

Grafana 12.4.14 carga automáticamente Prometheus, Loki, un Dashboard Operativo de cuatro paneles y una regla CPU > 80 % durante 1 minuto. El receptor local conserva los avisos reales en SQLite.

- Dashboard: <http://localhost:3000/d/operativo-observabilidad>.
- Usuario/contraseña iniciales: `admin` / `observability-lab`.
- Avisos Webhook: <http://localhost:8081>.
- Guía de despliegue, prueba controlada y capturas: [docs/PR04_GRAFANA.md](docs/PR04_GRAFANA.md).
- Estado de validación por entorno: [docs/PR04_VALIDACION.md](docs/PR04_VALIDACION.md).

~~~powershell
.\dev.ps1 validate
.\dev.ps1 up -Build
.\dev.ps1 status
.\dev.ps1 test -Integration
~~~

La integración comprueba métricas, logs y Grafana. Para el Webhook utiliza CPU real con umbral temporal -1 %, espera un aviso enviado por Grafana y restaura 80 % / 1 minuto. Genera un informe con el resultado real. Deben quedar nueve servicios Up. En el dashboard seleccionar el montaje `/mnt/docker-desktop-disk` de Docker Desktop.

## PR #3 — Logs JSON, Promtail y Loki

| Servicio nuevo | Versión | Función |
|---|---|---|
| Loki | grafana/loki:3.6.19 | Recibir, almacenar y consultar logs |
| Promtail | grafana/promtail:3.6.11 | Leer JSON, extraer timestamp y etiquetar level |
| cloud-logs | observability-cloud-logs:1.0.0 | Generar eventos sintéticos info, warn y error |

El generador usa Python 3.12.12 y no necesita una cuenta cloud ni Python instalado en Windows. Es una simulación explícita del origen de los logs; Promtail, Loki y las consultas funcionan realmente.

Guía completa: [docs/PR03_LOGS.md](docs/PR03_LOGS.md).

~~~powershell
.\dev.ps1 validate
.\dev.ps1 up -Build
.\dev.ps1 status
.\dev.ps1 test -Integration
~~~

La validación incluye Prometheus, Loki y Promtail. La integración comprueba métricas y logs. Para los logs escribe un registro nuevo con identificador único mediante el generador y espera encontrarlo en Loki con level=error.

Endpoints nuevos:

- Loki: http://localhost:3100/ready
- Promtail: http://localhost:9080/ready
- Targets de Promtail: http://localhost:9080/targets

Las consultas del PR #3 se prueban contra la API de Loki. El PR #4 añade la vista de logs en Grafana con filtro de severidad y actualización cada 5 segundos.

Promtail está fuera de soporte según Grafana. Se conserva por ser un componente exigido expresamente en la consigna del laboratorio; la migración futura a Alloy queda fuera de este PR.

## Estado de implementación

### PR #2 — Infrastructure & Metrics

Servicios incluidos:

| Servicio | Imagen / origen | Función |
|---|---|---|
| Prometheus | `prom/prometheus:v3.14.0` | Scraping y almacenamiento de métricas |
| Node Exporter | `prom/node-exporter:v1.12.1` | Métricas del entorno Linux de Docker |
| SNMP Exporter | `prom/snmp-exporter:v0.31.0` | Traducción de SNMP a métricas Prometheus |
| SNMP Agent | Imagen local `observability-snmp-agent:1.0.0` | Simulación de un dispositivo con Net-SNMP |

**Consideración sobre Windows y Docker Desktop:** Node Exporter es un exportador de métricas Linux. En esta configuración contenedorizada, las rutas `/proc`, `/sys` y `/` se montan desde el entorno Linux donde corre el daemon de Docker. En Docker Desktop para Windows esto corresponde al entorno Linux/VM de Docker Desktop, no al sistema operativo Windows anfitrión. Por tanto, no debe interpretarse como telemetría nativa de Windows. La recolección de métricas específicas de Windows requeriría `windows_exporter`, fuera del alcance de este PR.

El agente SNMP solo está conectado a la red Docker interna y no publica UDP/161 en el host. La comunidad SNMPv2c `public` es de laboratorio y no proporciona cifrado.

## Requisitos previos

- Windows 10/11.
- Docker Desktop instalado y en ejecución, con contenedores Linux habilitados.
- Docker Compose disponible mediante `docker compose`.
- PowerShell 5.1 o PowerShell 7.
- Git para el flujo de ramas y Pull Requests.

## Instalación

1. Clonar el repositorio.
2. Copiar `.env.example` a `.env` si aún no existe.
3. Revisar las variables locales.
4. Validar las configuraciones:

```powershell
Copy-Item .env.example .env
.\dev.ps1 validate
```

## Ejecución

Construir el simulador local e iniciar los servicios:

```powershell
.\dev.ps1 up -Build
```

Verificar el estado:

```powershell
.\dev.ps1 status
.\dev.ps1 test -Integration
```

Interfaces locales:

- Prometheus: http://localhost:9090
- Node Exporter: http://localhost:9100/metrics
- SNMP Exporter: http://localhost:9116

El agente SNMP no se expone en un puerto del host; SNMP Exporter lo consulta por la red interna de Docker.

## Consultas PromQL

### Porcentaje de utilización de CPU

```promql
100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])))
```

La consulta calcula el porcentaje de tiempo no ocioso promedio entre los CPU lógicos observados por Node Exporter. La ventana de cinco minutos suaviza variaciones puntuales.

### Ancho de banda entrante en Mbps

```promql
sum by (instance, ifName) (rate(ifHCInOctets{ifName!="lo"}[5m]) * 8 / 1000000)
```

### Ancho de banda saliente en Mbps

```promql
sum by (instance, ifName) (rate(ifHCOutOctets{ifName!="lo"}[5m]) * 8 / 1000000)
```

Los contadores SNMP se expresan en octetos. `rate()` calcula octetos por segundo; multiplicar por ocho convierte a bits por segundo y dividir por un millón convierte a megabits por segundo (Mbps, base decimal). Los nombres de interfaz se incorporan como etiqueta `ifName`.

## Validación y pruebas

```powershell
.\dev.ps1 validate
.\dev.ps1 test
.\dev.ps1 test -Integration
```

La integración requiere que el stack esté iniciado. Comprueba los jobs de métricas, los contadores CPU/red, la ingesta de logs y Grafana, incluido el envío real de la alerta de prueba y la restauración de su regla. Ver [tests/README.md](tests/README.md).

Para inspeccionar directamente el endpoint del SNMP Exporter:

```text
http://localhost:9116/snmp?target=snmp-agent:161&auth=public_v2&module=if_mib
```

La consulta de ancho de banda necesita al menos dos muestras del contador separadas por el intervalo de scraping para que `rate()` calcule una tasa. Para demostrar variación, debe circular tráfico por la interfaz del agente SNMP.

## Administración mediante dev.ps1

| Comando | Responsabilidad |
|---|---|
| `.\dev.ps1 up` | Inicia los servicios |
| `.\dev.ps1 up -Build` | Construye el simulador y levanta los servicios |
| `.\dev.ps1 down` | Detiene contenedores sin eliminar volúmenes |
| `.\dev.ps1 restart` | Reinicia servicios |
| `.\dev.ps1 status` | Muestra el estado |
| `.\dev.ps1 logs` | Sigue los logs |
| `.\dev.ps1 logs -Service prometheus` | Sigue los logs de Prometheus |
| `.\dev.ps1 validate` | Valida Compose, Prometheus, Loki, Promtail y archivos Grafana |
| `.\dev.ps1 test` | Ejecuta pruebas estáticas |
| `.\dev.ps1 test -Integration` | Comprueba métricas, logs, Grafana y alerta Webhook |
| `.\dev.ps1 clean` | Elimina contenedores, redes y volúmenes tras confirmación |

El comando `migrate` no se implementa mientras no exista una migración real que administrar.

## Estructura del repositorio

```text
.
├── docker-compose.yml
├── dev.ps1
├── README.md
├── .env.example
├── .gitignore
├── app/
├── configs/
├── dashboards/
├── simulators/
├── tools/
├── tests/
└── docs/
```

## Documentación por responsabilidad

- [Aplicación y microservicios](app/README.md)
- [Configuraciones de infraestructura](configs/README.md)
- [Dashboards y alertamiento](dashboards/README.md)
- [Simuladores](simulators/README.md)
- [Herramientas auxiliares](tools/README.md)
- [Pruebas y validación](tests/README.md)
- [Documentación técnica y evidencias](docs/README.md)

## Redes y persistencia

El PR #3 conserva las redes y servicios de métricas. Añade Loki y Promtail a `observability`. El generador trabaja sin red y comparte un volumen de archivos con Promtail, que lo monta en lectura. Loki utiliza `loki-data`; los archivos usan `cloud-logs-data` y los offsets de lectura usan `promtail-positions`. El PR #4 utiliza `grafana-data` para Grafana y añade `webhook-data` para los avisos SQLite. Jaeger sigue pendiente para el PR #5.

` .\dev.ps1 down` no elimina volúmenes. ` .\dev.ps1 clean` es destructivo y requiere confirmación.

## Referencias técnicas

- Prometheus Authors. (s. f.). *Prometheus documentation*. https://prometheus.io/docs/
- Prometheus Authors. (s. f.). *Node Exporter*. https://github.com/prometheus/node_exporter
- Prometheus Authors. (s. f.). *SNMP Exporter*. https://github.com/prometheus/snmp_exporter
- Docker, Inc. (s. f.). *Docker Compose documentation*. https://docs.docker.com/compose/
