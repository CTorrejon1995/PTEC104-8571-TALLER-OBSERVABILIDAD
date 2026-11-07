# PR #5 — OpenTelemetry, Jaeger y microservicios

Este cambio añade cuatro servicios al stack validado del PR #4: Jaeger 2.23.0, OpenTelemetry Collector Contrib 0.164.0, service-a y service-b. El total configurado pasa de nueve a **trece servicios**. Los componentes anteriores se conservan.

**Validación realizada en Windows:** integración completa aprobada y traza abierta en Jaeger con dos servicios y seis spans. El resultado y las capturas originales están en [PR05_VALIDACION.md](PR05_VALIDACION.md).

## 1. Desplegar y validar en Windows

Docker Desktop debe estar abierto con contenedores Linux. Ejecutar desde la raíz de esta versión del proyecto:

```powershell
.\dev.ps1 validate
.\dev.ps1 up -Build
.\dev.ps1 status
.\dev.ps1 test -Integration
```

No se necesita Python instalado en Windows: las dependencias de los microservicios se instalan dentro de la imagen Docker, con versiones fijadas en `app/requirements.txt`. Se mantiene Python 3.12.12 como base de contenedor.

La validación estática comprueba Compose, Prometheus, Loki, Promtail, Grafana, Jaeger, Collector y sintaxis Python. La integración ejecuta métricas, logs, Grafana/Webhook y finalmente trazas. Deben aparecer `Pruebas de trazas distribuidas aprobadas.` y `Pruebas de integracion del stack aprobadas.` para considerar aprobada esta ejecución.

Para repetir solo trazas una vez iniciado el entorno:

```powershell
.\tests\validation\test-traces.ps1
```

| Interfaz | URL local |
|---|---|
| Aplicación service-a | <http://localhost:8082> |
| Petición rápida | <http://localhost:8082/checkout?scenario=fast> |
| Petición lenta | <http://localhost:8082/checkout?scenario=slow> |
| Jaeger UI | <http://localhost:16686> |
| Salud del Collector | <http://localhost:13133> |
| Dashboard existente | <http://localhost:3000/d/operativo-observabilidad> |

service-b no publica un puerto en Windows. service-a lo llama por la red de Compose. El endpoint /health de service-a también comprueba que el worker responde.

## 2. Recorrido de la transacción

```mermaid
flowchart LR
    A["service-a"] -->|"HTTP + traceparent"| B["service-b"]
    A -->|"OTLP/HTTP"| C["OTEL Collector"]
    B -->|"OTLP/HTTP"| C
    C -->|"OTLP/gRPC"| D["Jaeger"]
```

service-a recibe GET /checkout, ejecuta validate-request y llama a service-b. La llamada HTTP lleva el contexto W3C traceparent. service-b crea su span servidor bajo el span cliente de service-a y ejecuta simulated-db-query. Cada proceso exporta sus spans mediante el SDK OpenTelemetry a Collector; este aplica límite de memoria y batching y los entrega a Jaeger por OTLP/gRPC.

La transacción normal tiene seis spans:

1. service-a: GET /checkout, servidor raíz.
2. service-a: validate-request, unos 20 ms de trabajo simulado.
3. service-a: HTTP GET service-b/work, span cliente.
4. service-b: GET /work, span servidor hijo del cliente remoto.
5. service-b: simulated-db-query, demora deliberada de 40 ms o 600 ms.
6. service-a: render-response, unos 5 ms de trabajo simulado.

La demora está etiquetada lab.simulated=true y lab.delay_ms. No existe una base de datos real en esta aplicación. Las peticiones HTTP, el contexto distribuido, los spans y la exportación son reales.

## 3. Qué comprueba la integración

El script genera dos solicitudes nuevas, fast y slow, cada una con test_run único. Exige:

- El mismo trace_id válido en las respuestas de ambos servicios.
- Una traza recuperada realmente desde la API de Jaeger, no solo un ID impreso por la aplicación.
- Spans de service-a y service-b, con el marcador de esa solicitud.
- Referencias CHILD_OF correctas entre raíz, cliente HTTP, servidor remoto y operación interna.
- La demora configurada en las etiquetas y una duración medida coherente.
- Un span hoja de mayor duración identificado para analizar el cuello de botella.

Los spans padre incluyen el tiempo de sus hijos. No se suman todas las duraciones para calcular el tiempo total: se utiliza la duración del span raíz y se compara con los spans hoja.

La integración guarda automáticamente en docs/evidence/:

- pr05-windows-validation.json: estado, IDs, duraciones, referencias y enlaces.
- pr05-windows-fast-trace.json y pr05-windows-slow-trace.json: respuestas reales de Jaeger.
- pr05-windows-analysis.md: comparación de tiempos y operación hoja más lenta.

Un fallo se registra como failed; una traza antigua de otra solicitud no sirve para aprobar.

## 4. Abrir y analizar en Jaeger

Después de aprobar la integración:

```powershell
$pr5 = Get-Content .\docs\evidence\pr05-windows-validation.json -Raw -Encoding UTF8 | ConvertFrom-Json
Start-Process $pr5.slow.jaeger_url
```

También se puede abrir Jaeger, seleccionar service-a, buscar GET /checkout y elegir una solicitud reciente. El enlace impreso por la integración evita confundir trazas de ejecuciones distintas.

En la vista de la traza:

1. Confirmar que aparecen service-a y service-b en la misma transacción.
2. Expandir la llamada HTTP y el servidor remoto.
3. Seleccionar simulated-db-query y observar duración y etiquetas.
4. Comparar con el escenario fast usando los enlaces del informe JSON.

El escenario slow busca hacer visible el tiempo de espera de la operación simulada de service-b. El análisis generado registra los tiempos efectivamente observados; no supone que los valores nominales sean exactamente las duraciones medidas.

## 5. Evidencia y análisis observado

- [Integración completa aprobada](evidence/pr-05/screenshots/pr05-integration-windows.png).
- [Traza lenta abierta en Jaeger](evidence/pr-05/screenshots/pr05-jaeger-trace-windows.png).
- [Prueba independiente y trece contenedores Running](evidence/pr-05/screenshots/pr05-traces-windows.png).
- [Registro de observación y análisis de latencia](evidence/pr-05/README.md#registro-pr05-windows-validation-md).

La traza lenta de la ejecución completa tiene ID 50ec9f0ff81fd802f4edf1c76f4e0e62. Jaeger muestra dos servicios, seis spans y una duración total redondeada de 627 ms. La prueba midió 600.125 ms en simulated-db-query de service-b, aproximadamente el 96 % de ese total. El árbol hace visible la espera dentro de la llamada HTTP; los tiempos inclusivos de padres e hijos no se suman.

Los JSON y el análisis detallado se generan en el clon Windows. Deben conservarse y versionarse con las capturas. La imagen recibida muestra el árbol de spans; para inspeccionar los atributos en una demostración, seleccionar simulated-db-query y desplegar sus etiquetas.

## 6. Persistencia y límites del laboratorio

Jaeger utiliza un almacén en memoria de hasta 5.000 trazas. Reiniciarlo elimina su contenido; volver a generar peticiones lo repuebla. Los JSON guardados en el clon y las capturas conservan la evidencia para evaluar sin un entorno activo. El volumen jaeger-data reservado en etapas anteriores no se utiliza como almacenamiento persistente en esta modalidad.

El muestreo conserva todas las solicitudes de demostración y respeta el contexto padre. El Collector limita su memoria y agrupa envíos con timeout de 1 segundo. Estos valores sirven al volumen bajo del taller; no son una estimación de capacidad de producción.

La recepción en Collector/Jaeger y la integración del stack completo se validaron después en Docker Desktop para Windows. En preparación se habían aprobado validadores de configuración y las pruebas de los dos procesos HTTP y sus spans SDK OTLP reales, pero aquel ejecutor no exponía los PID numéricos necesarios para arrancar Jaeger. Ese límite histórico no se oculta ni se confunde con el resultado posterior de Windows.

## 7. Diagnóstico

```powershell
.\dev.ps1 logs -Service jaeger
.\dev.ps1 logs -Service otel-collector
.\dev.ps1 logs -Service service-a
.\dev.ps1 logs -Service service-b
```

Si Jaeger está vacío, generar una petición nueva y esperar el batching. Comprobar que Collector responde y que sus logs no muestran errores al exportar. La aplicación usa http://otel-collector:4318/v1/traces y Collector usa jaeger:4317 dentro de Compose; localhost desde un contenedor no identifica otro servicio.

El chequeo de Jaeger usa /api/v3/services: /api/services devuelve 404 en la versión fijada. Si aparece el error de conexión npipe dockerDesktopLinuxEngine, iniciar Docker Desktop y esperar a que el motor esté disponible antes de repetir el arranque.

Si una prueba falla, conservar su salida y el JSON de estado. No se corrige borrando volúmenes del stack ya validado.

## Referencias

- Instrumentación Python: <https://opentelemetry.io/docs/languages/python/instrumentation/>.
- Contexto W3C: <https://opentelemetry.io/docs/concepts/context-propagation/>.
- Configuración del Collector: <https://opentelemetry.io/docs/collector/configuration/>.
- Jaeger v2: <https://www.jaegertracing.io/docs/2.23/deployment/>.
- Configuración de referencia de Jaeger: <https://github.com/jaegertracing/jaeger/blob/v2.23.0/cmd/jaeger/internal/all-in-one.yaml>.
