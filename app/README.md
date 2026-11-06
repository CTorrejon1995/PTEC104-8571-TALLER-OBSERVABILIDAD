# Aplicación de prueba — PR #5

Dos procesos HTTP reales con OpenTelemetry Python 1.45.2:

- service-a/main.py: GET /checkout, validación, llamada HTTP al worker y respuesta con trace_id.
- service-b/main.py: GET /work, span servidor y operación simulated-db-query.
- shared/telemetry.py: SDK, recursos service.name, batching, exportador OTLP/HTTP y contexto W3C.
- requirements.txt: dependencias directas y transitivas fijadas a las usadas en preparación.

La demora de la operación es deliberada: 40 ms en fast y 600 ms en slow. Está etiquetada como simulación; no se crea una base de datos ficticia. HTTP y los spans exportados son reales.

Docker usa Python 3.12.12, usuario 10001, raíz de contenedor de lectura y biblioteca estándar para servir HTTP. service-a se publica en http://localhost:8082; service-b solo se alcanza dentro de la red de Compose. /health de service-a comprueba también al worker.

Procedimiento, trazas y evidencias: [PR05_TRAZAS.md](../docs/PR05_TRAZAS.md). No se requiere Python en Windows para ejecutar el flujo Docker.
