Incorpora trazas distribuidas a la aplicación: service-a llama a service-b con contexto W3C y ambos envían spans por OTLP/HTTP al Collector, que los exporta por OTLP/gRPC a Jaeger.

Añade Collector, Jaeger y los dos microservicios a Docker Compose, con versiones fijadas. Incluye escenarios fast/slow de 40/600 ms, prueba de trazas nuevas con relaciones padre-hijo, exportación de la evidencia y análisis del span hoja de mayor duración. Corrige el chequeo de disponibilidad para la API v3 de Jaeger.

Validado en Windows con Docker Desktop: trece contenedores Running e integración completa de métricas, logs, Grafana/Webhook y trazas aprobada. La captura de Jaeger muestra dos servicios, seis spans y una transacción de unos 627 ms; simulated-db-query, en service-b, concentra 600.125 ms, aproximadamente el 96 % del total.

La demora es simulada deliberadamente; HTTP, contexto W3C, SDK, Collector y Jaeger funcionan realmente. Jaeger usa memoria en este laboratorio. Se incluyen capturas originales y el informe técnico actualizado; los JSON generados en Windows se conservan en docs/evidence/.
