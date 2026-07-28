# Troubleshooting

| Síntoma | Revisión inicial | Acción segura |
|---|---|---|
| PostgreSQL no llega a `Ready` | Estado del servidor y Activity Log | No iniciar AKS; revisar operación y mantener el ambiente encendido |
| AKS no inicia | Activity Log, capacidad regional y estado previo | Mantener PostgreSQL encendido y diagnosticar antes de reintentar |
| Workloads no recuperan réplicas | Nodos, eventos, pods, PVC e imágenes | No cambiar configuración automáticamente; validar dependencias |
| Job sin permisos | Scope y asignaciones RBAC de la identidad | Corregir el scope; no ampliar a la suscripción sin aprobación |
| Schedule ejecuta en hora inesperada | Zona horaria y próxima ejecución | Confirmar `America/Santiago` y deshabilitar mientras se corrige |
| Costos no bajan | Recursos que siguen encendidos y periodo comparado | Revisar Cost Management antes de cambiar más recursos |

## Rollback

1. Deshabilitar los schedules.
2. Iniciar PostgreSQL y esperar `Ready`.
3. Iniciar AKS y validar nodos y workloads.
4. Mantener ambos recursos encendidos.
5. Registrar la causa y la evidencia antes de volver a habilitar la recurrencia.
