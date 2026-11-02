# Pruebas y validación

## Propósito
Organizar las pruebas automatizadas y los procedimientos de verificación del stack.

## Responsabilidades
- `validation/`: validaciones estáticas y verificaciones individuales.
- `integration/`: pruebas entre componentes una vez desplegados.

## Estructura
```text
tests/
├── integration/
└── validation/
```

## Dependencias
Las pruebas se incorporarán junto con cada componente. La integración completa corresponde a PR #6.

## Ejecución y validación
En PR #1, ejecutar `.\dev.ps1 validate` y `.\dev.ps1 test` desde PowerShell con Docker Desktop activo. Las pruebas de integración quedan pendientes hasta disponer de servicios.
