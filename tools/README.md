# Herramientas auxiliares

## Propósito
Agrupar utilidades de soporte que no pertenecen a la aplicación ni a los componentes principales del stack.

## Responsabilidades
- `webhook-receiver/`: receptor HTTP local para demostrar la recepción de notificaciones de alertas.

## Estructura
```text
tools/
└── webhook-receiver/
```

## Dependencias
El receptor se implementará e integrará con Grafana en PR #4.

## Ejecución y validación
Las instrucciones de ejecución y la prueba de recepción se incorporarán en PR #4. PR #1 solo establece la ubicación.
