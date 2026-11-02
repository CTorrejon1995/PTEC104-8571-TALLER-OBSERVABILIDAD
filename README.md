# Stack de Observabilidad Completo

Proyecto académico de Infraestructura TI para desplegar y validar una plataforma de observabilidad Open Source mediante Docker Compose. El objetivo final es integrar métricas, logs y trazas distribuidas en un entorno local reproducible.

## Objetivos

- Recolectar métricas de infraestructura y red.
- Centralizar y consultar registros estructurados.
- Visualizar métricas y logs y demostrar alertamiento.
- Instrumentar una aplicación de microservicios y analizar trazas distribuidas.

## Arquitectura prevista

El stack se organiza en cuatro capas:

1. **Fuentes:** sistema operativo, dispositivo de red simulado, logs JSON y microservicios.
2. **Recolección y procesamiento:** Prometheus, SNMP Exporter, Promtail y OpenTelemetry Collector.
3. **Almacenamiento y consulta:** Prometheus, Loki y Jaeger.
4. **Visualización y operación:** Grafana, dashboards y notificaciones Webhook.

La arquitectura se implementará incrementalmente en seis Pull Requests. Este PR #1 crea únicamente la estructura, la base de Docker Compose y la automatización inicial; no despliega todavía componentes funcionales de observabilidad.

## Tecnologías previstas

Docker Compose, PowerShell, Prometheus, Node Exporter, SNMP Exporter, Loki, Promtail, Grafana, OpenTelemetry Collector y Jaeger. Las imágenes de los servicios se incorporarán con versiones explícitas y compatibles en los PR correspondientes.

## Requisitos previos

- Windows 10/11.
- Docker Desktop instalado y en ejecución.
- Docker Compose v2 disponible mediante `docker compose`.
- PowerShell 5.1 o PowerShell 7.
- Git para el flujo de ramas y Pull Requests.

## Instalación

1. Clonar el repositorio.
2. Copiar `.env.example` a `.env`.
3. Revisar las variables locales de `.env`.
4. Ejecutar la validación:

```powershell
Copy-Item .env.example .env
.\dev.ps1 validate
```

No se requieren puertos publicados ni servicios en ejecución durante PR #1.

## Ejecución y administración

El script `dev.ps1` centraliza las operaciones disponibles:

| Comando | Responsabilidad |
|---|---|
| `.\dev.ps1 validate` | Valida el modelo de Docker Compose. |
| `.\dev.ps1 up` | Prepara el despliegue; informa si aún no hay servicios. |
| `.\dev.ps1 up -Build` | Construye imágenes antes de iniciar servicios, cuando existan. |
| `.\dev.ps1 down` | Detiene y elimina contenedores y redes, sin eliminar volúmenes. |
| `.\dev.ps1 restart` | Reinicia los servicios definidos. |
| `.\dev.ps1 status` | Muestra el estado de los contenedores. |
| `.\dev.ps1 logs` | Sigue los logs del proyecto. |
| `.\dev.ps1 logs -Service nombre` | Sigue los logs de un servicio específico. |
| `.\dev.ps1 test` | Ejecuta la validación estática disponible en esta fase. |
| `.\dev.ps1 test -Integration` | Informa que las pruebas de integración se habilitarán cuando existan servicios. |
| `.\dev.ps1 clean` | Elimina contenedores, redes y volúmenes, previa confirmación. |
| `.\dev.ps1 clean -Force` | Ejecuta la limpieza destructiva sin pregunta interactiva. |

El comando `migrate` no se implementa en esta fase: no existe aún una migración real que administrar. Se añadirá únicamente si una necesidad técnica concreta lo justifica.

## Estructura del repositorio

```text
.
├── docker-compose.yml
├── dev.ps1
├── README.md
├── .env.example
├── .gitignore
├── app/
├── configs/
├── dashboards/
├── simulators/
├── tools/
├── tests/
└── docs/
```

## Documentación por responsabilidad

- [Aplicación y microservicios](app/README.md)
- [Configuraciones de infraestructura](configs/README.md)
- [Dashboards y alertamiento](dashboards/README.md)
- [Simuladores](simulators/README.md)
- [Herramientas auxiliares](tools/README.md)
- [Pruebas y validación](tests/README.md)
- [Documentación técnica y evidencias](docs/README.md)

## Redes y volúmenes

Compose define dos redes: `observability` (bridge) para comunicación general y `observability-internal` (bridge interno) para componentes que no requieran salida externa. También declara volúmenes nombrados reservados para la persistencia de métricas, logs, Grafana y trazas. Los servicios se conectarán a estas redes y volúmenes en los PR funcionales.

## Estado de la entrega

PR #1 — Repository Foundation: estructura y archivos base. La validación real con Docker Compose debe ejecutarse en el equipo de desarrollo; este paquete no afirma que Docker haya sido ejecutado en ese entorno.

## Licencia y uso académico

Material desarrollado para la práctica final integradora de Infraestructura TI.
