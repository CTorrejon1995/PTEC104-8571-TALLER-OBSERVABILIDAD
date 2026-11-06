# Configuraciones

## Propósito
Centralizar los archivos de configuración de los componentes de observabilidad.

## Responsabilidades
- `prometheus/`: configuración de scraping y reglas de métricas.
- `snmp-exporter/`: autenticación y módulos SNMP expuestos a Prometheus.
- `loki/`: configuración de almacenamiento y recepción de logs (PR #3).
- `promtail/`: scraping y pipeline de procesamiento JSON (PR #3).
- `otel-collector/`: recepción OTLP, límite de memoria, batching y exportación a Jaeger (PR #5).
- `jaeger/`: Jaeger v2 con API/UI y almacenamiento de laboratorio en memoria.

## Configuraciones implementadas

PR #3 añade `loki/loki.yml` (TSDB v13, filesystem, WAL y retención de siete días) y `promtail/promtail.yml` (lectura JSON, timestamp RFC3339 y etiqueta level). PR #5 añade otel-collector/otel-collector.yml y jaeger/jaeger.yml para recibir OTLP y almacenar/consultar trazas en memoria.

- `prometheus/prometheus.yml`: define los jobs `prometheus`, `node-exporter` y `snmp-device`.
- `snmp-exporter/snmp.yml`: perfil reducido IF-MIB para consultar contadores de octetos de 64 bits, nombre y estado operacional de interfaces. Utiliza el perfil `public_v2` de SNMPv2c.

El módulo `if_mib` incluido aquí es una configuración mínima propia del laboratorio; no es una copia íntegra del `snmp.yml` distribuido por el proyecto SNMP Exporter. El nombre del módulo y el perfil de autenticación siguen el patrón recomendado por su documentación oficial.

## Dependencias
Las versiones de las imágenes se fijan en `docker-compose.yml`: Prometheus `v3.14.0` y SNMP Exporter `v0.31.0` para este PR.

## Validación
Desde la raíz del repositorio:

```powershell
.\dev.ps1 validate
```

El script valida Compose y ejecuta los validadores nativos de Prometheus, Loki, Promtail, Jaeger y Collector dentro de sus imágenes fijadas; también comprueba los archivos de Grafana y la sintaxis de los microservicios.

## Referencias

- Prometheus Authors. (s. f.). *Configuration*. https://prometheus.io/docs/prometheus/latest/configuration/configuration/
- Prometheus Authors. (s. f.). *SNMP exporter*. https://github.com/prometheus/snmp_exporter
