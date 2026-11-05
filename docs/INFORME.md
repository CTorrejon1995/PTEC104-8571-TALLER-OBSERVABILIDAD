# Informe técnico — Stack de Observabilidad Completo

> Documento incremental. Registrar comandos y resultados reales del entorno de ejecución. No declarar pruebas aprobadas sin ejecutarlas.

## 1. Paso a paso documentado

### PR #1 — Repository Foundation

Registrar la preparación del repositorio, estructura y validaciones de Compose ejecutadas en el entorno de desarrollo.

### PR #2 — Infrastructure & Metrics

Procedimiento reproducible:

```powershell
Copy-Item .env.example .env
.\dev.ps1 validate
.\dev.ps1 up -Build
.\dev.ps1 status
.\dev.ps1 test -Integration
```

Servicios y endpoints locales:

- Prometheus: http://localhost:9090
- Node Exporter: http://localhost:9100/metrics
- SNMP Exporter: http://localhost:9116

Incorporar capturas reales de los targets `prometheus`, `node-exporter` y `snmp-device` en estado `UP`, además de las consultas PromQL ejecutadas.

## 2. Justificación técnica

Prometheus utiliza un modelo de scraping periódico y almacena las series temporales en su TSDB. Node Exporter publica métricas del entorno Linux observado. SNMP Exporter consulta el agente SNMP y transforma los objetos IF-MIB en métricas compatibles con Prometheus.

### CPU

```promql
100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])))
```

La métrica `node_cpu_seconds_total` es un contador acumulativo de segundos de CPU por modo. `rate()` estima la tasa por segundo; al restar el modo `idle` de uno y multiplicar por cien se obtiene el porcentaje medio no ocioso.

### Tráfico de red entrante y saliente

```promql
sum by (instance, ifName) (rate(ifHCInOctets{ifName!="lo"}[5m]) * 8 / 1000000)
sum by (instance, ifName) (rate(ifHCOutOctets{ifName!="lo"}[5m]) * 8 / 1000000)
```

Los objetos `ifHCInOctets` e `ifHCOutOctets` representan contadores de octetos de 64 bits de IF-MIB. `rate()` permite derivar la tasa de crecimiento del contador; el factor ocho convierte octetos a bits y el divisor 1.000.000 expresa el resultado en Mbps decimales.

**Limitación del entorno Windows:** Node Exporter se ejecuta como contenedor Linux y observa el entorno Linux/VM de Docker Desktop, no las métricas nativas del kernel Windows. Esta distinción debe explicitarse en la interpretación de resultados.

## 3. Evidencia de funcionamiento

Pendiente de incorporar evidencias reales del entorno:

- Salida de `docker compose ps`.
- Prometheus: página Status / Targets con los tres jobs en `UP`.
- Prometheus: ejecución de la consulta de CPU.
- Prometheus: ejecución de las consultas de tráfico entrante y saliente.
- SNMP Exporter: respuesta del endpoint `/snmp` con las métricas IF-MIB.
- Resultado de ` .\dev.ps1 test -Integration`.

No incluir capturas simuladas ni resultados no ejecutados.

## 4. Conclusiones y lecciones aprendidas

Pendiente. Completar una vez ejecutadas y analizadas las pruebas de integración en el equipo de desarrollo.

## Referencias

- Prometheus Authors. (s. f.). *Query functions*. https://prometheus.io/docs/prometheus/latest/querying/functions/
- Prometheus Authors. (s. f.). *Node Exporter*. https://github.com/prometheus/node_exporter
- Prometheus Authors. (s. f.). *SNMP Exporter*. https://github.com/prometheus/snmp_exporter
- McCloghrie, K., & Kastenholz, F. (2000). *The interfaces group MIB (RFC 2863)*. Internet Engineering Task Force. https://www.rfc-editor.org/rfc/rfc2863
