# Simuladores

## Propósito
Contener fuentes de datos simuladas necesarias para reproducir escenarios de infraestructura sin depender de dispositivos o servicios cloud reales.

## Responsabilidades
- `snmp-agent/`: agente SNMP simulado para las pruebas del SNMP Exporter.
- `cloud-logs/`: generador de registros JSON que representan eventos de infraestructura.

## Estructura
```text
simulators/
├── snmp-agent/
└── cloud-logs/
```

## Dependencias
El agente SNMP se incorporará en PR #2 y el generador de logs en PR #3.

## Ejecución y validación
Cada simulador tendrá instrucciones y pruebas junto con su implementación. No se ejecutan simuladores en PR #1.
