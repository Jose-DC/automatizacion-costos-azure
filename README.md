# Automatización horaria de recursos en Azure

Este es un proyecto personal para practicar una situación bastante común en operaciones cloud: mantener recursos encendidos fuera de su ventana real de uso, aunque nadie los esté utilizando.

El escenario es concreto: un clúster de Kubernetes administrado con Azure Kubernetes Service (AKS) y una base de datos PostgreSQL Flexible Server. No se trata de máquinas virtuales sueltas ni de apagar una suscripción completa. La misma idea puede aplicarse a ambientes de pruebas y a componentes productivos que tengan una ventana operativa aprobada; en producción no se debe apagar un servicio sin revisar antes su disponibilidad, dependencias y SLA.

## El problema

Un ambiente no productivo con AKS y PostgreSQL puede quedar funcionando durante la noche o todo el fin de semana. Lo mismo puede ocurrir con una carga productiva que tenga horarios de atención definidos. En ambos casos, el clúster, los nodos y la base de datos siguen consumiendo recursos fuera de la ventana de uso.

Apagarlo manualmente también tiene sus riesgos. No basta con detener cualquier cosa primero: si se apaga la base de datos mientras las aplicaciones siguen levantadas, pueden aparecer errores. Y si el clúster está detenido, no puede ejecutar un CronJob para volver a encenderse.

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
- Validaciones básicas de estado antes de continuar.
- Notas sobre rollback, permisos y medición del consumo.

## Ejemplo de uso

El script está preparado como referencia y usa valores ficticios. Antes de probarlo en un laboratorio hay que reemplazar las variables y revisar los permisos:

```powershell
.\automatizacion-horaria.ps1 `
  -Action Start `
  -Subscription '<SUBSCRIPTION_ID>' `
  -AksResourceGroup '<AKS_RESOURCE_GROUP>' `
  -AksName '<AKS_NAME>' `
  -DatabaseResourceGroup '<DATABASE_RESOURCE_GROUP>' `
  -DatabaseName '<POSTGRES_SERVER_NAME>'
```

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
