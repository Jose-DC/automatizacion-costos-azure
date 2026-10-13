# Preparación, operación y recuperación

## Responsabilidades y requisitos

El responsable del ambiente aprueba la ventana; el administrador de acceso asigna RBAC; el operador configura y verifica el runbook. Usar testing, revisar consumidores externos y registrar suscripción, recursos y namespace.

1. Preparar Automation Account con identidad administrada y runtime compatible.
2. Añadir `Az.Accounts`, `Az.Aks` y `Az.PostgreSql`; registrar versiones y comprobar los cmdlets requeridos.
3. Asignar permisos sobre recursos objetivo y verificar acceso a AKS Run Command.
4. Importar el `.ps1` como runbook PowerShell y proporcionar parámetros sin marcadores.
5. Ejecutar Start y Stop manualmente sobre el ambiente autorizado antes de programarlos.

Az.Accounts debe estar disponible antes de Connect-AzAccount. El chequeo de módulos dentro del flujo no cubre una falla inicial de autenticación.

Referencias: [runtime](https://learn.microsoft.com/en-us/azure/automation/manage-runtime-environment), [identidad administrada](https://learn.microsoft.com/en-us/azure/automation/learn/powershell-runbook-managed-identity) y [restricciones Start/Stop AKS](https://learn.microsoft.com/en-us/azure/aks/start-stop-cluster).

## Validación y programación

Registrar PostgreSQL Ready, AKS Running/Succeeded, nodos Ready y Deployments disponibles. Realizar una prueba funcional aparte: HTTP, SQL o transacción representativa.

Para Stop comprobar primero AKS Stopped/Succeeded y luego PostgreSQL Stopped. Publicar el runbook probado y vincular dos schedules con Action Start/Stop y los mismos recursos, usando America/Santiago. Confirmar cambio estacional y evitar jobs superpuestos.

El script no crea schedules. Revisar los primeros ciclos en los streams Output, Warning y Error; un schedule habilitado no demuestra recuperación funcional.

## Troubleshooting

| Síntoma | Revisión y acción |
|---|---|
| Autenticación o cmdlet no disponible | Identidad, runtime, módulos y contexto. Corregir antes de repetir. |
| AuthorizationFailed | Recurso y alcance de RBAC, incluida ejecución Run Command. |
| Base en transición | Inspeccionar operación activa y esperar, sin reenviar órdenes incompatibles. |
| Falta de capacidad | Revisar error y reintentos; escalar sin modificar automáticamente región o tamaño. |
| AKS no inicia | PowerState, ProvisioningState y Activity Log. Conservar PostgreSQL para diagnóstico. |
| Workloads no disponibles | Namespace, pods, eventos y probes; realizar prueba funcional separada. |

## Recuperación

No existe rollback automático. Recuperar significa volver a un ambiente disponible, no revertir cambios de datos.

1. Deshabilitar schedules y revisar jobs activos; deshabilitar recurrencia no cancela un job iniciado.
2. Inspeccionar estados y operaciones en curso.
3. Con autorización, iniciar PostgreSQL, esperar Ready y luego iniciar AKS.
4. Validar nodos, Deployments y funcionamiento de la aplicación.
5. Corregir la causa y registrar el incidente antes de reactivar recurrencia.

Comprobaciones manuales de solo lectura con Azure CLI y nombres ficticios:

```bash
az account show --query '{subscription:id,name:name}'
az aks show -g rg-demo-aks -n aks-demo --query '{power:powerState.code,provisioning:provisioningState}'
az postgres flexible-server show -g rg-demo-db -n pg-demo --query state
```
