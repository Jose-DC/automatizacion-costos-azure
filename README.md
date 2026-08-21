# Automatización horaria de recursos en Azure

Este es un proyecto personal para practicar una situación bastante común en operaciones cloud: mantener recursos encendidos fuera de su ventana real de uso, aunque nadie los esté utilizando.

El escenario es concreto: un clúster de Kubernetes administrado con Azure Kubernetes Service (AKS) y una base de datos PostgreSQL Flexible Server. No se trata de máquinas virtuales sueltas ni de apagar una suscripción completa. La misma idea puede aplicarse a ambientes de pruebas y a componentes productivos que tengan una ventana operativa aprobada; en producción no se debe apagar un servicio sin revisar antes su disponibilidad, dependencias y SLA.

## El problema

En Azure, un clúster AKS y su PostgreSQL pueden seguir generando consumo durante la noche, los fines de semana o cualquier tramo fuera de la ventana de operación. En pruebas ocurre cuando nadie está usando la plataforma; en producción puede ocurrir con servicios o workloads que tienen horarios definidos.

El problema es pagar capacidad que no se necesita y depender de una detención manual que puede hacerse en el orden incorrecto. Si PostgreSQL se apaga mientras las aplicaciones siguen levantadas, pueden aparecer errores; y si el clúster está detenido, no puede ejecutar un CronJob para volver a encenderse. En producción, este patrón solo debe aplicarse cuando la ventana esté autorizada y sea compatible con la disponibilidad esperada.

## La solución

La automatización se ejecuta fuera de AKS usando Azure Automation:

1. En el horario de inicio, se enciende PostgreSQL.
2. Se espera hasta que la base de datos quede en estado `Ready`.
3. Se inicia AKS.
4. Se revisan los nodos y los workloads.
5. En el horario de detención, primero se apaga AKS.
6. Cuando el clúster ya está detenido, se apaga PostgreSQL.

El runbook usa una identidad administrada para que Azure Automation pueda operar mediante RBAC, sin repartir contraseñas ni tokens entre scripts o personas.

Los dos schedules quedaron habilitados para ejecutar el flujo de forma automática en los horarios definidos: uno inicia PostgreSQL y AKS al comienzo de la jornada, y el otro detiene primero AKS y luego PostgreSQL al terminarla. La prueba manual del runbook se realizó antes de dejar activa la recurrencia.

```text
Inicio:    PostgreSQL -> Ready -> AKS -> validar workloads
Detención: AKS -> detenido -> PostgreSQL -> validar estados
```

## Qué se necesita en Azure

Para montar este flujo se necesitan varios componentes y permisos. La cuenta que configura los recursos no necesariamente es la misma identidad que ejecuta el runbook.

- Una cuenta de Azure Automation con identidad administrada asignada por el sistema.
- Dos schedules: uno para iniciar y otro para detener, configurados con la zona horaria `America/Santiago`.
- Un runbook de PowerShell con un parámetro para decidir entre `Start` y `Stop`.
- Acceso a Azure CLI y a los módulos de Azure Automation/Az usados por el entorno.
- Permisos para consultar y operar el AKS y PostgreSQL seleccionados.

En el escenario de referencia, la identidad administrada recibió roles integrados con alcance directo a los recursos: `Azure Kubernetes Service Contributor Role` sobre AKS y `Contributor` sobre PostgreSQL Flexible Server. Esto permite operar los recursos sin guardar claves, pero `Contributor` es más amplio que un permiso estrictamente mínimo. Una mejora posterior sería crear un rol personalizado con solo las acciones de lectura, inicio y detención necesarias.

Para asignar esos roles se necesita un Owner o una persona con permisos de administración de acceso (RBAC). Un usuario con `Contributor` puede crear recursos, pero normalmente no puede crear asignaciones de roles por sí solo. Esa separación de responsabilidades fue parte importante de la implementación.

## Qué incluye este repositorio

- Un script de ejemplo en PowerShell con la secuencia de inicio y detención.
- Variables reemplazables para usar nombres ficticios de recursos.
- Diseño idempotente: revisa el estado real de cada recurso antes de actuar y no repite una operación que ya está en curso.
- Reintentos con espera creciente cuando Azure no tiene capacidad disponible de inmediato para iniciar la base de datos.
- Validación de módulos y cmdlets requeridos antes de operar, y reintento del flujo completo si falla.
- Validación final de workloads ejecutada dentro del propio clúster (no solo el estado del servicio administrado).
- Notas sobre rollback, permisos y medición del consumo.

## Ejemplo de uso

El script está preparado como referencia y usa valores ficticios. Antes de probarlo en un laboratorio hay que reemplazar las variables y revisar los permisos:

```powershell
.\automatizacion-horaria.ps1 `
  -Action Start `
  -SubscriptionName '<SUBSCRIPTION_NAME>' `
  -AksResourceGroup '<AKS_RESOURCE_GROUP>' `
  -AksName '<AKS_NAME>' `
  -PostgreSqlResourceGroup '<POSTGRES_RESOURCE_GROUP>' `
  -PostgreSqlName '<POSTGRES_SERVER_NAME>' `
  -AppNamespace '<APP_NAMESPACE>'
```

## Troubleshooting

- **Proveedor no registrado:** falta registrar el namespace de Azure Automation en la suscripción; se corrige registrándolo y validando el estado `Registered`.
- **Error de autorización RBAC:** la identidad administrada no tiene permiso sobre ese recurso puntual; se revisa el alcance de la asignación, sin ampliarla a toda la suscripción.
- **PostgreSQL no llega a `Ready`:** puede ser una operación en curso o falta de capacidad regional; no se reintenta el inicio mientras el estado siga en transición.
- **AKS no inicia:** se revisa el Activity Log antes de reintentar, manteniendo PostgreSQL encendido mientras se diagnostica.
- **Un primer encendido automático falló** por un problema transitorio al cargar módulos de PowerShell. Se resolvió agregando la validación explícita de módulos y cmdlets, más un reintento completo del flujo antes de declarar error (ver `Import-RequiredModules` en el script).

El orden de las operaciones es la parte más importante del ejemplo. En un ambiente real también se deberían revisar consumidores externos, ventanas de mantenimiento, alertas y reglas de rollback antes de activar un horario recurrente.

El ejemplo no crea máquinas virtuales ni administra nodos directamente. AKS sigue siendo un servicio administrado de Azure; el script solo solicita las acciones de inicio y detención del clúster y espera sus estados antes de continuar.

## Tecnologías

- Azure Automation
- Azure Kubernetes Service (AKS)
- PostgreSQL Flexible Server
- Azure CLI
- PowerShell
- Identidad administrada y RBAC
- Azure Cost Management

## Cómo comprobar si realmente se ahorra

No basta con mirar que el clúster esté apagado. Para medir el resultado se deben comparar periodos equivalentes en Azure Cost Management, separando el costo de AKS, PostgreSQL y cualquier otro recurso que siga encendido.

También conviene anotar las fechas, la moneda y si hubo otros cambios en el ambiente. De esa forma el ahorro no se presenta como una suposición.

Una revisión preliminar en el ambiente de referencia mostró un gasto aproximado de USD 12 al día con los recursos encendidos, frente a USD 2,65 acumulados durante un fin de semana completo con todo apagado. Es una señal de ahorro real, pero un solo fin de semana no permite fijar un porcentaje mensual confiable: falta repetir la medición por al menos dos semanas con el mismo alcance y métrica.

## Aprendizajes

Este proyecto sirve para practicar una automatización pequeña, pero con varias decisiones de operación detrás:

- Diseñar dependencias entre servicios.
- Ejecutar automatizaciones fuera del clúster.
- Usar identidad administrada en vez de secretos.
- Mantener los permisos acotados al alcance necesario.
- Validar la recuperación y no solo el comando de apagado.
- Relacionar una decisión técnica con una medición de costos.

## Estado

La automatización quedó implementada y funcionando con ejecución programada. Este repositorio público es una versión simplificada y anonimizada para mostrar el diseño y el aprendizaje sin exponer información interna.
