# Simuladores

## Propósito
Contener fuentes de datos simuladas necesarias para reproducir escenarios de infraestructura sin depender de dispositivos o servicios cloud reales.

## Responsabilidades
- `snmp-agent/`: agente Net-SNMP que representa un dispositivo de red de laboratorio.
- `cloud-logs/`: generador de registros JSON que representa eventos de infraestructura (PR #3).

## Simulador SNMP (PR #2)

`snmp-agent/` contiene:

- `Dockerfile`: construye una imagen local basada en `debian:bookworm-slim` e instala `snmpd` desde los repositorios de Debian.
- `snmpd.conf`: habilita SNMPv2c de solo lectura y expone las tablas estándar de interfaces del agente.

El agente se conecta únicamente a `observability-internal`. No publica el puerto UDP/161 en el host. La comunidad `public` se utiliza solo para el laboratorio: SNMPv2c no cifra la comunidad ni el contenido de los mensajes, por lo que esta configuración no debe reutilizarse en redes de producción.

Las métricas de tráfico corresponden a los contadores de la interfaz virtual del contenedor. El tráfico de prueba debe circular por esa interfaz para incrementar los contadores.

## Validación

```powershell
.\dev.ps1 up -Build
.\dev.ps1 test -Integration
```

Referencias:

- Net-SNMP Project. (s. f.). *snmpd.conf manual page*. http://www.net-snmp.org/docs/man/snmpd.conf.html
- Prometheus Authors. (s. f.). *SNMP exporter*. https://github.com/prometheus/snmp_exporter
