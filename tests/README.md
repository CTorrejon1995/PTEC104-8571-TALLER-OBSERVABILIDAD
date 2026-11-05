# Pruebas y validación

## Propósito
Organizar las pruebas estáticas, funcionales e integración del stack.

## Estructura

```text
tests/
├── integration/
└── validation/
    └── test-metrics.ps1
```

## PR #2 — Infrastructure & Metrics

La validación estática se ejecuta con:

```powershell
.\dev.ps1 validate
.\dev.ps1 test
```

Incluye la validación del modelo Compose y `prometheus.yml` mediante `promtool`.

La prueba de integración requiere que los contenedores estén levantados:

```powershell
.\dev.ps1 up -Build
.\dev.ps1 test -Integration
```

El script `validation/test-metrics.ps1` comprueba que Prometheus esté listo, que los jobs `prometheus`, `node-exporter` y `snmp-device` estén `UP`, y que existan las métricas `node_cpu_seconds_total`, `ifHCInOctets` e `ifHCOutOctets`.

La prueba no genera carga de red artificial; solo verifica que los contadores SNMP estén disponibles. La demostración de tráfico requiere producir solicitudes sobre la red del simulador y observar el incremento de los contadores.

La validación integral del stack corresponde al PR #6.
