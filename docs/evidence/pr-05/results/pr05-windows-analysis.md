# Analisis de latencia observado

Entorno: windows-docker-compose. Estos valores proceden de trazas reales consultadas en Jaeger, no de una imagen simulada.

| Escenario | Demora configurada (ms) | Transaccion medida (ms) | Span de consulta medido (ms) |
|---|---|---|---|
| fast | 40 | 70.02 | 40.117 |
| slow | 600 | 627.659 | 600.118 |

La solicitud lenta tiene trace_id 5bcde9b744ef07595879d505a668fa1f y enlaza service-a con service-b mediante una referencia padre-hijo entre el cliente HTTP y el servidor remoto.

El span hoja de mayor duracion fue service-b / simulated-db-query: 600.118 ms, aproximadamente 95.61 % de la duracion de la transaccion. Los spans de cliente y servidor incluyen tiempo de sus hijos; no se suman todas sus duraciones como si fueran operaciones independientes.

La demora de 600 ms es deliberada y esta etiquetada lab.simulated=true. No corresponde a una base de datos real. La peticion HTTP, el contexto W3C, los spans SDK, el Collector y la consulta de Jaeger funcionan realmente.

Abrir la transaccion: http://127.0.0.1:16686/trace/5bcde9b744ef07595879d505a668fa1f

Los JSON pr05-windows-fast-trace.json y pr05-windows-slow-trace.json conservan las trazas observadas. Jaeger usa memoria en este laboratorio: un reinicio elimina su almacenamiento, pero los JSON guardados permanecen en el clon.
