# Validación

Esta réplica pública separa la evidencia del caso real de los pasos que se pueden repetir con recursos de laboratorio.

## Criterios de éxito

- El runbook inicia PostgreSQL y espera `Ready` antes de iniciar AKS.
- El runbook detiene AKS antes de detener PostgreSQL.
- Los jobs terminan correctamente y dejan duración, estados y errores.
- Después de `Start`, los nodos y workloads recuperan un estado saludable.
- Los schedules respetan la zona horaria y la recurrencia configuradas.
- El rollback permite mantener los recursos encendidos mientras se investiga.

## Evidencia del caso de referencia

En la automatización real que inspira este repositorio se validó un ciclo controlado de detención y recuperación, incluyendo PostgreSQL, AKS, nodos, deployments e ingress. La validación de la operación programada se registró por separado.

Los datos públicos de este repositorio deben utilizar valores agregados o ficticios. No se deben copiar salidas de Azure que incluyan identificadores internos.

## Medición de ahorro

El ahorro debe medirse comparando periodos equivalentes en Azure Cost Management:

1. Seleccionar el mismo alcance de recursos.
2. Comparar días de operación continua contra días con schedule.
3. Separar el costo de AKS, PostgreSQL y otros recursos que permanecen encendidos.
4. Registrar el rango de fechas, moneda y fecha de consulta.
5. Evitar atribuir todo el cambio a la automatización si hubo otras modificaciones.
