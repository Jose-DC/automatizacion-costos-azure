# Arquitectura y decisiones

## Alcance

Una Automation Account opera sobre un AKS y un PostgreSQL existentes. La versión pública conserva la secuencia validada en testing; no incluye IaC para cuenta, módulos, RBAC o schedules.

| Decisión | Motivo |
|---|---|
| Control externo a AKS | Un clúster detenido no ejecuta CronJobs. |
| PostgreSQL antes de AKS al iniciar | Las aplicaciones dependen de la base. Ready es estado Azure, no prueba SQL. |
| AKS antes de PostgreSQL al detener | Evitar cortar la base mientras las aplicaciones siguen activas. |
| Consultar antes de operar | Evitar repetir órdenes en transiciones conocidas; no sustituye un lock. |
| Validar Kubernetes después de Azure | Running no demuestra disponibilidad de Deployments. |

## Funciones

| Función | Responsabilidad |
|---|---|
| `Import-RequiredModules` | Importa tres módulos y comprueba cmdlets; no instala paquetes. |
| `Ensure-PostgreSqlReady` | Espera Ready, observa transiciones y solicita Start desde Stopped. |
| `Ensure-AksRunning` | Espera Running/Succeeded y solicita Start desde Stopped/Succeeded. |
| `Ensure-AksStopped` | Espera Stopped/Succeeded antes de permitir detener la base. |
| `Ensure-PostgreSqlStopped` | Espera Stopped y solicita Stop desde Ready. |
| `Assert-AksWorkloads` | Espera nodos Ready y Deployments disponibles, lista pods y comprueba ExitCode. |
| `Invoke-Start` | Coordina dependencias y validación; reintenta el flujo completo. |
| `Invoke-Stop` | Coordina detención, sin reintento global. |

Estados inesperados generan error. No se fuerzan operaciones de mantenimiento ni reparaciones automáticas.

## Esperas actuales

- Polling: 30 segundos.
- Start: 60 minutos nominales compartidos entre base, AKS y validación.
- Stop: 60 minutos de observación por recurso.
- Workloads: hasta 900 segundos por cada `kubectl wait`, limitado por el tiempo restante calculado antes del bloque.
- Flujo Start y carga de módulos: hasta dos intentos, separados por 20 segundos.
- PostgreSQL Start: hasta seis solicitudes; espera creciente de 30 a 300 segundos para los errores tratados como capacidad.
- Tras emitir Start: 90 segundos de observación antes de considerar repetirlo si sigue en Stopped.

Cmdlets síncronos y sleeps pueden exceder los deadlines. Ambos waits reciben el mismo timeout; la duración combinada puede superar el tiempo restante. No interpretar estos valores como un SLA.

## Seguridad y recuperación

La identidad evita claves en código. En el caso de referencia se usó `Azure Kubernetes Service Contributor Role` sobre AKS y `Contributor` sobre PostgreSQL; son roles más amplios que Start/Stop. Revisar un rol personalizado es una mejora pendiente.

La suscripción se selecciona, pero no se desactiva autosave ni se pasa un contexto explícito por cmdlet. Reforzar aislamiento entre jobs sigue pendiente.

`AppNamespace` se interpola en shell: admitir únicamente un namespace válido y confiable. El código no incorpora esa validación automática.

No hay bloqueo de concurrencia, prueba HTTP/SQL ni rollback automático. Ante un error, inspeccionar los recursos y seguir [operación y recuperación](operacion.md).
