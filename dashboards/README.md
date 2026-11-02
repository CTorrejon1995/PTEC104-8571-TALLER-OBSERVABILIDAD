# Dashboards y alertamiento

## Propósito
Agrupar el aprovisionamiento de Grafana, los dashboards y las reglas de alertamiento.

## Responsabilidades
- `provisioning/`: configuración declarativa de Grafana y datasources.
- `dashboards/`: definición exportable del Dashboard Operativo.
- `alerting/`: reglas y configuración de notificaciones.

## Estructura
```text
dashboards/
├── provisioning/
├── dashboards/
└── alerting/
```

## Dependencias
Grafana y sus datasources Prometheus y Loki se integrarán en PR #4.

## Ejecución y validación
La carga del dashboard y la prueba de alertas se documentarán en PR #4. Esta fase no contiene dashboards ni reglas operativas.
