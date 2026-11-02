# Configuraciones

## Propósito
Centralizar los archivos de configuración de los componentes de observabilidad.

## Responsabilidades
- `prometheus/`: configuración de scraping y reglas.
- `snmp-exporter/`: módulos de consulta SNMP.
- `loki/`: configuración de almacenamiento y recepción de logs.
- `promtail/`: scraping y pipeline de procesamiento JSON.
- `otel-collector/`: recepción y exportación de telemetría.

## Estructura
```text
configs/
├── prometheus/
│   └── rules/
├── snmp-exporter/
├── loki/
├── promtail/
└── otel-collector/
```

## Dependencias
Cada configuración dependerá de la versión fijada del servicio correspondiente. Las versiones y compatibilidades se verificarán antes de incorporarlas en los PR funcionales.

## Ejecución y validación
Las validaciones específicas se documentarán al incorporar cada archivo. No hay configuraciones funcionales de estos componentes en PR #1.
