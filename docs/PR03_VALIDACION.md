# Validación del paquete PR #3

La comprobación del paquete se realizó el 5 de noviembre de 2026. Se distinguen el entorno de preparación y el equipo Windows del estudiante.

| Comprobación | Entorno | Resultado |
|---|---|---|
| Modelo de Compose | Compose 5.6.1, sin daemon | Aprobado |
| Configuración de Loki | Binario oficial 3.6.19 | Aprobado |
| Configuración de Promtail | Binario oficial 3.6.11 | Aprobado |
| Sintaxis de scripts PowerShell | Parser PowerShell 7 | Aprobado |
| Aplicación del parche a una copia limpia | Finales de línea LF y CRLF | Aprobado |
| Contrato, Unicode, rotación y argumentos del generador | Python | Tres pruebas aprobadas |
| Log nuevo, severidades, timestamp, reinicios y prueba PowerShell | Procesos reales Linux | Aprobado |
| Base de métricas PR #2 | Windows del estudiante | Aprobado previamente; capturas incluidas |
| Arranque Docker Desktop del PR #3 y ejecución completa | Windows del estudiante | Aprobado; siete contenedores Up y pruebas del stack aprobadas |
| Grafana, Webhook, Jaeger y OTEL | PR #4 y PR #5 | Fuera de este bloque |

Los binarios de prueba se obtuvieron de los releases oficiales y sus SHA-256 se comprobaron contra los digests publicados en esos releases. No se incluyen binarios ni datos de volúmenes en el ZIP.

La prueba nativa adapta únicamente los paths de archivos y puertos a un directorio temporal. Usa el generador y el pipeline JSON del proyecto; las consultas llegan a Loki real. El script PowerShell se ejecuta contra ese mismo pipeline.

Después, Benja ejecutó la validación, el arranque y la integración completa en Docker Desktop para Windows. Esta ejecución también comprobó la inserción del probe mediante Docker Compose. Ver [evidence/pr-03/README.md#registro-pr03-windows-validation-md](evidence/pr-03/README.md#registro-pr03-windows-validation-md) y sus tres capturas originales.

El registro de preparación está en [evidence/pr-03/results/pr03-native-validation.json](evidence/pr-03/results/pr03-native-validation.json). Su campo Windows pendiente describe el estado histórico de esa ejecución; la validación posterior de Windows se documenta por separado. Las capturas de Grafana y Jaeger corresponden a los siguientes PR.
