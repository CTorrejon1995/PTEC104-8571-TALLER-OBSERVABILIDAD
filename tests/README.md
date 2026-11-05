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

## PR #3 — Integración de logs

`dev.ps1 validate` añade los validadores nativos de Loki y Promtail. `dev.ps1 test -Integration` ejecuta primero métricas y después `validation/test-logs.ps1`.

La prueba de logs espera los endpoints ready, escribe un probe nuevo en el generador mediante Docker Compose, lo busca en Loki con level=error, comprueba el JSON almacenado y verifica las tres severidades. Falla si el registro no llega; tener contenedores en estado Up no alcanza.

Para ejecutar solo logs:

~~~powershell
.\tests\validation\test-logs.ps1
~~~

Pruebas de contrato del generador, para un entorno con Python:

~~~text
python -m unittest discover -s tests/validation -p test_generator.py -v
~~~

La prueba opcional `integration/test_logs_native.py` usa binarios oficiales de Loki y Promtail y Python estándar, sin Docker. Si se proporciona `--pwsh`, también ejecuta el mismo script PowerShell contra el pipeline vivo. Comprueba filtros, timestamps y continuidad después de reiniciar ambos servicios. Los paths y puertos de las configuraciones se adaptan a un directorio temporal; las etapas de procesamiento se conservan.

El resultado del entorno de preparación está en `docs/evidence/pr03-native-validation.json`. La ejecución posterior aprobada en Docker Desktop para Windows se registra en `docs/evidence/pr03-windows-validation.md`, con sus capturas.

## PR #4 — Grafana y Webhook

En Windows, con Docker Desktop y el stack iniciado:

```powershell
.\dev.ps1 validate
.\dev.ps1 test -Integration
```

La integración ejecuta métricas, logs y `validation/test-grafana.ps1`. Esta última verifica las dos fuentes, el dashboard, las consultas y el envío real de una alerta. Cambia temporalmente solo Grafana a umbral -1 % / 0s y restaura 80 % / 1m en `finally`. El receptor no recibe un POST artificial para aprobar la prueba. El resultado queda en `docs/evidence/pr04-windows-validation.json`.

Los mantenedores pueden ejecutar `python -m unittest discover -s tests/validation -p 'test_*.py' -v` para comprobar generador y receptor. No es necesario instalar Python en Windows para el flujo normal.

`integration/test_grafana_native.py --help` documenta las rutas de binarios requeridas por la prueba Linux sin Docker. Arranca Grafana, Prometheus, Node Exporter, Loki, Promtail, generador y receptor reales, ejecuta el mismo script PowerShell con recarga de provisioning y comprueba un reinicio de Grafana. Omite SNMP y utiliza un montaje Linux real; el informe lo declara. No reemplaza la validación Docker Desktop de Windows.
