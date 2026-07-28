# Arquitectura de la automatización

## Componentes

| Componente | Función |
|---|---|
| Azure Automation | Ejecutar el runbook fuera de AKS |
| Identidad administrada | Autenticar sin secretos almacenados |
| Schedule de inicio | Lanzar `Start` en horario laboral |
| Schedule de detención | Lanzar `Stop` fuera de horario |
| PostgreSQL Flexible Server | Base de datos del ambiente |
| AKS | Clúster que ejecuta los workloads |
| Azure Cost Management | Comparar consumo antes y después |

## Orden de dependencias

Durante el inicio, PostgreSQL debe estar disponible antes de que los workloads de AKS intenten conectarse. Durante la detención, AKS debe bajar antes que PostgreSQL para evitar errores de aplicación y conexiones pendientes.

```text
Start: PostgreSQL -> Ready -> AKS -> nodos Ready -> workloads saludables
Stop:  AKS -> detenido -> PostgreSQL -> estados confirmados
```

## Decisiones técnicas

- La automatización vive fuera de AKS: un clúster detenido no puede ejecutar su propio CronJob.
- La identidad administrada evita guardar credenciales en scripts o variables persistentes.
- Los schedules se configuran con `America/Santiago` para que el horario sea explícito.
- El alcance RBAC debe quedar limitado a los recursos objetivo; los roles integrados pueden ser un punto de partida, no necesariamente el estado final de mínimo privilegio.
