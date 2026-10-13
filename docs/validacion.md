# Evidencia y validación

| Aspecto | Evidencia disponible | Límite |
|---|---|---|
| Testing | Caso documentado y confirmado por el autor. | Logs internos no publicados. |
| Orden y reintentos | Código inspeccionable. | Código no demuestra nueva ejecución Azure. |
| Schedules | Antecedentes del caso de referencia. | Sin export público de configuración. |
| Kubernetes | Wait de nodos y Deployments, revisión ExitCode. | Sin prueba HTTP/SQL. |
| Costos | Observaciones preliminares. | Sin ahorro mensual cuantificado. |

## Validación offline

Revisión del 12-10-2026: parser PowerShell sin errores, ayuda reconocida por Get-Help y comparación de tokens ejecutables equivalente a la versión previa. Se actualizaron comentarios y documentación; no se ejecutaron cmdlets contra Azure.

Revisar sintaxis sin autenticar ni ejecutar:

```powershell
$tokens = $null
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PWD 'automatizacion-horaria.ps1'), [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    $parseErrors | Format-List
    throw 'Errores de sintaxis en el runbook.'
}
```

`Get-Help ./automatizacion-horaria.ps1 -Full` muestra ayuda sin operar recursos. Esto no prueba RBAC, módulos ni API de Azure.

## Matriz para testing autorizado o mocks

| Escenario | Esperado |
|---|---|
| Ambos detenidos | Base → AKS → validación. |
| Ambos activos | Consultar estados y validar Kubernetes. |
| Base en transición | Esperar sin otra orden mientras se observa la transición. |
| AKS falla al iniciar | Error, base conservada para diagnóstico. |
| Deployment no disponible | Error y salida de diagnóstico. |
| Ambos activos y Stop | AKS detenido antes que la base. |
| Falla al detener AKS | No detener PostgreSQL. |
| Ambos detenidos y Stop | Comprobar estados y terminar. |

Pendientes: mocks, versiones del runtime, capturas sanitizadas de jobs y costos comparables. No provocar fallas en ambientes compartidos para completar esta matriz. No publicar IDs, nombres internos, tokens, URLs ni datos de usuarios.
