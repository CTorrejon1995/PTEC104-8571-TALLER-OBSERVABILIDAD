# Evidencias PR #5

Registro organizado del bloque pr-05. Las capturas y los resultados mantienen sus nombres originales.

> Las secciones documentales siguientes reproducen las notas anteriores e indican su archivo de origen; no representan nuevas ejecuciones de pruebas.

## Archivos de evidencia

| Archivo | Tipo |
|---|---|
| [pr05-integration-windows.png](screenshots/pr05-integration-windows.png) | screenshots |
| [pr05-jaeger-trace-windows.png](screenshots/pr05-jaeger-trace-windows.png) | screenshots |
| [pr05-native-backend-check.json](results/pr05-native-backend-check.json) | results |
| [pr05-native-sdk-validation.json](results/pr05-native-sdk-validation.json) | results |
| [pr05-preparation-checks.json](results/pr05-preparation-checks.json) | results |
| [pr05-traces-windows.png](screenshots/pr05-traces-windows.png) | screenshots |
| [pr05-windows-analysis.md](results/pr05-windows-analysis.md) | results |
| [pr05-windows-fast-trace.json](results/pr05-windows-fast-trace.json) | results |
| [pr05-windows-slow-trace.json](results/pr05-windows-slow-trace.json) | results |
| [pr05-windows-validation.json](results/pr05-windows-validation.json) | results |

## Registro: pr05-traces-windows.md

*Fuente histÃ³rica: `docs/evidence/pr05-traces-windows.md`.*

# Prueba de trazas en Windows: resultado observado

Evidencia original enviada por Benja: image(20261106-145314).png. La captura se conserva sin modificaciones en [pr05-traces-windows.png](screenshots/pr05-traces-windows.png).

La terminal muestra la ejecución de `./dev.ps1 up` con los trece contenedores en Running y después `./tests/validation/test-traces.ps1`.

Resultados visibles:

- OpenTelemetry Collector: READY.
- Jaeger: READY.
- service-a: READY.
- Traza fast: `37786ea6da9ad1ef1588891b5560984c`, servicios enlazados service-a -> service-b.
- Traza slow: `4998182f9d550c1cee6af13e42e7d006`, servicios enlazados service-a -> service-b.
- Mayor span hoja de la solicitud lenta: service-b / simulated-db-query, 600.115 ms.
- Mensaje final: `Pruebas de trazas distribuidas aprobadas.`

El retardo de simulated-db-query es deliberado; no representa una base de datos física. La prueba ejecuta solicitudes HTTP instrumentadas y consulta las trazas almacenadas en Jaeger.

Este registro transcribe la captura de la prueba independiente. No sustituye ni reconstruye los JSON originales generados por el script en el equipo Windows. La integración completa posterior y la traza abierta en Jaeger están documentadas en [pr05-windows-validation.md](#registro-pr05-windows-validation-md).

---

## Registro: pr05-windows-validation.md

*Fuente histÃ³rica: `docs/evidence/pr05-windows-validation.md`.*

# Integración y Jaeger: evidencia original de Windows

La ejecución de Benja del 6 de noviembre de 2026 aprobó la integración completa del stack. Este registro se deriva de dos capturas originales; no reconstruye los JSON generados en su equipo.

## Capturas y procedencia

| Archivo conservado | Original proporcionado | Contenido |
|---|---|---|
| [pr05-integration-windows.png](screenshots/pr05-integration-windows.png) | image(20261106-150128).png | Resultado de la integración completa |
| [pr05-jaeger-trace-windows.png](screenshots/pr05-jaeger-trace-windows.png) | image(20261106-150150).png | Transacción lenta abierta en Jaeger |

La [prueba independiente anterior](#registro-pr05-traces-windows-md) también muestra los trece contenedores Running. Las capturas se copiaron sin modificar sus píxeles.

## Integración completa observada

- Validación estática del stack: correcta.
- Prometheus READY; targets prometheus, node-exporter y snmp-device UP.
- Métricas node_cpu_seconds_total, ifHCInOctets e ifHCOutOctets disponibles.
- Loki y Promtail READY; probe nuevo recibido; filtro LogQL y severidades info, warn y error comprobados.
- Fuentes Prometheus/Loki y consultas de CPU, storage, red y logs en Grafana: correctas.
- Webhook controlado recibido, evento 15; regla normal CPU >80 % durante 1 minuto restaurada.
- OpenTelemetry Collector, Jaeger y service-a READY.
- Traza fast nueva: `98f67688c60037654dab141424e9c0ee`.
- Traza slow nueva: `50ec9f0ff81fd802f4edf1c76f4e0e62`.
- Ambos recorridos enlazan service-a con service-b.
- Mensajes finales: `Pruebas de trazas distribuidas aprobadas.` y `Pruebas de integracion del stack aprobadas.`

El script exige referencias padre-hijo, marcadores de solicitud y duraciones coherentes, además de recuperar una traza nueva de la API de Jaeger. El chequeo de disponibilidad usa /api/v3/services, compatible con Jaeger 2.23.

## Transacción observada y cuello de botella

| Dato | Valor visible | Fuente |
|---|---|---|
| Identificador | 50ec9f0ff81fd802f4edf1c76f4e0e62 | Terminal; la UI muestra el mismo prefijo |
| Duración total | Aproximadamente 627 ms | Cabecera de Jaeger, valor redondeado |
| Servicios | 2 | Cabecera y árbol de Jaeger |
| Spans | 6 | Cabecera y árbol de Jaeger |
| Profundidad | 4 | Cabecera de Jaeger |
| Mayor span hoja | service-b / simulated-db-query | Terminal y árbol |
| Duración del span lento | 600.125 ms | Terminal de la prueba |
| Proporción aproximada del total | 95.7 % | 600.125 / 627; total redondeado |

La jerarquía muestra GET /checkout en service-a, el cliente HTTP GET service-b/work, GET /work en service-b y simulated-db-query. También aparecen validate-request, de unos 20.1 ms, y render-response, de unos 5.1 ms.

El span de 600.125 ms concentra aproximadamente el 96 % de la duración total. Es el principal tiempo de espera de esta transacción. Los spans de cliente y servidor incluyen el tiempo de sus hijos; sus duraciones no deben sumarse como si fueran trabajos independientes.

La demora de 600 ms es deliberada y se identifica como simulada en la aplicación. No representa una consulta a una base de datos física. La llamada HTTP entre contenedores, el contexto W3C, la exportación por SDK, el Collector y la consulta a Jaeger sí funcionan realmente.

La captura no tiene abierto el detalle de atributos del span; no se presenta como una imagen de esas etiquetas.

## Archivos originales del equipo Windows

La terminal confirma que la prueba guardó evidencia y análisis en docs/evidence/. El script produce pr05-windows-validation.json, pr05-windows-fast-trace.json, pr05-windows-slow-trace.json y pr05-windows-analysis.md. Esos archivos se conservan y se añaden al commit desde el clon Windows; este registro no sustituye sus bytes ni inventa valores ausentes de las imágenes.

Jaeger usa memoria. Reiniciarlo elimina las trazas activas; los JSON y las capturas versionadas conservan la evidencia de esta ejecución.

---

