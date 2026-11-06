# Prueba de trazas en Windows: resultado observado

Evidencia original enviada por Benja: image(20261106-145314).png. La captura se conserva sin modificaciones en [pr05-traces-windows.png](pr05-traces-windows.png).

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

Este registro transcribe la captura de la prueba independiente. No sustituye ni reconstruye los JSON originales generados por el script en el equipo Windows. La integración completa posterior y la traza abierta en Jaeger están documentadas en [pr05-windows-validation.md](pr05-windows-validation.md).
