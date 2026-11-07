# Documentacion del proyecto

Esta carpeta reune el informe academico, las guias tecnicas consolidadas por etapa y las evidencias originales de validacion. Las etapas PR03, PR04 y PR05 representan bloques funcionales del laboratorio; sus documentos historicos se han reunido sin descartar las instrucciones, limitaciones ni resultados observados.

## Por donde empezar

- [INFORME.md](INFORME.md): informe academico integrado y conclusiones, con enlaces a las evidencias.
- [PR03.md](PR03.md): centralizacion de logs JSON con Loki y Promtail, despliegue, validacion y resultados.
- [PR04.md](PR04.md): Grafana, dashboard, alertas Webhook, correccion de Windows, validacion y cierre.
- [PR05.md](PR05.md): OpenTelemetry, Collector, Jaeger, trazas distribuidas, validacion y cierre.
- [evidence/README.md](evidence/README.md): indice de capturas y resultados reales, organizados por PR.

## Carpetas

- `architecture/`: espacio reservado para diagramas y descripcion de la arquitectura.
- `evidence/pr-02/` a `evidence/pr-05/`: cada etapa tiene un `README.md` con procedencia, `screenshots/` con capturas y `results/` con resultados cuando corresponda.
- `references/`: espacio reservado para fuentes tecnicas y referencias bibliograficas.

## Como interpretar la evidencia

Los registros distinguen las ejecuciones de Docker Desktop en Windows de las comprobaciones de preparacion en otros entornos. Las capturas y los JSON versionados son evidencia historica: no se presentan como nuevas ejecuciones. Para reproducir las comprobaciones actuales, usar los comandos y pruebas del repositorio desde su raiz.

## Historial documental

Los archivos anteriores `PR03_*.md`, `PR04_*.md` y `PR05_*.md` se han integrado en los tres documentos correspondientes. Cada uno mantiene secciones identificadas por el nombre de origen para facilitar su trazabilidad en Git.
