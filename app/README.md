# Aplicación

## Propósito
Contener los microservicios de prueba que generarán trazas distribuidas en la fase de APM.

## Responsabilidades
- `service-a`: punto de entrada de solicitudes.
- `service-b`: operación interna invocada por `service-a`.
- `shared`: código compartido estrictamente necesario.

## Estructura
```text
app/
├── service-a/
├── service-b/
└── shared/
```

## Dependencias
La instrumentación OpenTelemetry y las dependencias de ejecución se definirán en PR #5. No se incorporan dependencias de aplicación en PR #1.

## Ejecución y validación
Se incorporarán instrucciones reproducibles junto con el código de los servicios en PR #5. En esta fase solo se establece la estructura.
