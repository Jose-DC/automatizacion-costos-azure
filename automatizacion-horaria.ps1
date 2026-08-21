<#
    Ejemplo educativo con nombres ficticios. Revisar permisos, nombres y
    dependencias antes de usarlo. Muestra el diseño real (idempotencia,
    reintentos, validacion de workloads), no un script listo para copiar
    y pegar en produccion.
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Start", "Stop")]
    [string]$Action,

    [string]$SubscriptionName = "<SUBSCRIPTION_NAME>",
    [string]$AksResourceGroup = "<AKS_RESOURCE_GROUP>",
    [string]$AksName = "<AKS_NAME>",
    [string]$PostgreSqlResourceGroup = "<POSTGRES_RESOURCE_GROUP>",
    [string]$PostgreSqlName = "<POSTGRES_SERVER_NAME>",
    [string]$AppNamespace = "<APP_NAMESPACE>"
)

$ErrorActionPreference = "Stop"

$PollSeconds = 30
$TimeoutMinutes = 60
$StartTimeoutMinutes = 60
$WorkloadTimeoutSeconds = 900
$MaxAttempts = 2
$RetryDelaySeconds = 20
$PostgreSqlStartMaxAttempts = 6
$CapacityRetryBaseSeconds = 30
$CapacityRetryMaxSeconds = 300
$PostgreSqlStartObservationSeconds = 90
$RequiredModules = @("Az.Accounts", "Az.Aks", "Az.PostgreSql")
$RequiredCommands = @(
    "Connect-AzAccount",
    "Set-AzContext",
    "Get-AzAksCluster",
    "Start-AzAksCluster",
    "Stop-AzAksCluster",
    "Invoke-AzAksRunCommand",
    "Get-AzPostgreSqlFlexibleServer",
    "Start-AzPostgreSqlFlexibleServer",
    "Stop-AzPostgreSqlFlexibleServer"
)

# Antes de operar, confirma que los modulos y cmdlets necesarios esten
# disponibles. Un runbook real fallo una vez por esto: el runtime no
# encontraba un cmdlet a tiempo. Este chequeo explicito evita ese error.
function Import-RequiredModules {
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            foreach ($moduleName in $RequiredModules) {
                Import-Module -Name $moduleName -Force -ErrorAction Stop
            }

            foreach ($commandName in $RequiredCommands) {
                if ($null -eq (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
                    throw "Cmdlet requerido no disponible: $commandName"
                }
            }

            Write-Output "Modulos y cmdlets requeridos disponibles."
            return
        }
        catch {
            if ($attempt -eq $MaxAttempts) {
                throw "No fue posible cargar los modulos Azure requeridos despues de $MaxAttempts intentos. Detalle: $($_.Exception.Message)"
            }

            Write-Warning "Carga de modulos fallida en intento $attempt/$MaxAttempts. Reintentando en $RetryDelaySeconds segundos."
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}

# Patron idempotente: revisa el estado real antes de actuar, y reintenta
# con espera creciente si Azure no tiene capacidad disponible de inmediato.
function Ensure-PostgreSqlReady {
    param([datetime]$Deadline)

    $capacityAttempt = 0
    $startRequestIssued = $false
    $startObservationDeadline = $null

    do {
        $postgresql = Get-AzPostgreSqlFlexibleServer `
            -ResourceGroupName $PostgreSqlResourceGroup `
            -Name $PostgreSqlName

        $state = [string]$postgresql.State
        Write-Output "PostgreSQL: $state"

        if ($state -eq "Ready") {
            return
        }

        if ($state -in @("Starting", "Stopping", "Updating", "Restarting", "Reconfiguring")) {
            Write-Output "PostgreSQL esta en transicion ($state). Se espera sin emitir otra operacion."
            Start-Sleep -Seconds $PollSeconds
            continue
        }

        if ($state -ne "Stopped") {
            throw "PostgreSQL quedo en un estado no esperado para el inicio: $state."
        }

        if ($startRequestIssued -and ((Get-Date) -lt $startObservationDeadline)) {
            Write-Output "PostgreSQL aun reporta Stopped tras solicitar el inicio. Se espera la propagacion sin reenviar la orden."
            Start-Sleep -Seconds $PollSeconds
            continue
        }

        $startRequestIssued = $false

        if ($capacityAttempt -ge $PostgreSqlStartMaxAttempts) {
            throw "PostgreSQL no pudo iniciarse despues de $PostgreSqlStartMaxAttempts intentos por falta de capacidad."
        }

        try {
            $capacityAttempt++
            Write-Output "Iniciando PostgreSQL desde Stopped. Intento $capacityAttempt/$PostgreSqlStartMaxAttempts."
            Start-AzPostgreSqlFlexibleServer `
                -ResourceGroupName $PostgreSqlResourceGroup `
                -Name $PostgreSqlName `
                -Confirm:$false `
                -ErrorAction Stop | Out-Null

            $startRequestIssued = $true
            $startObservationDeadline = (Get-Date).AddSeconds($PostgreSqlStartObservationSeconds)
            Start-Sleep -Seconds $PollSeconds
        }
        catch {
            $message = $_.Exception.Message

            if ($message -notmatch "capacity|Capacity is not available|ServerIsNotStopped|busy") {
                throw
            }

            if ($message -match "ServerBusyWithOtherOperation|busy") {
                $startRequestIssued = $true
                $startObservationDeadline = (Get-Date).AddSeconds($PostgreSqlStartObservationSeconds)
                Write-Warning "PostgreSQL ya tiene una operacion de inicio en curso. Se espera sin reenviar la orden."
                Start-Sleep -Seconds $PollSeconds
                continue
            }

            # Reintento con espera creciente si Azure no tiene capacidad disponible.
            $retryDelay = [int][Math]::Min(
                $CapacityRetryMaxSeconds,
                $CapacityRetryBaseSeconds * [Math]::Pow(2, $capacityAttempt - 1)
            )

            Write-Warning "Azure no pudo asignar capacidad para PostgreSQL. Reintento en $retryDelay segundos."
            Start-Sleep -Seconds $retryDelay
        }
    }
    while ((Get-Date) -lt $Deadline)

    throw "PostgreSQL no alcanzo Ready dentro del timeout de $TimeoutMinutes minutos."
}

function Ensure-AksRunning {
    param([datetime]$Deadline)

    do {
        $aks = Get-AzAksCluster -ResourceGroupName $AksResourceGroup -Name $AksName
        $powerState = [string]$aks.PowerState.Code
        $provisioningState = [string]$aks.ProvisioningState
        Write-Output "AKS: PowerState=$powerState ProvisioningState=$provisioningState"

        if (($powerState -eq "Running") -and ($provisioningState -eq "Succeeded")) {
            return
        }

        if (($powerState -in @("Starting", "Stopping")) -or ($provisioningState -in @("Creating", "Updating"))) {
            Write-Output "AKS esta en transicion. Se espera sin emitir otra operacion."
            Start-Sleep -Seconds $PollSeconds
            continue
        }

        if (($powerState -eq "Stopped") -and ($provisioningState -eq "Succeeded")) {
            Write-Output "Iniciando AKS..."
            Start-AzAksCluster -ResourceGroupName $AksResourceGroup -Name $AksName -Confirm:$false -ErrorAction Stop | Out-Null
            Start-Sleep -Seconds $PollSeconds
            continue
        }

        throw "AKS quedo en un estado no esperado para el inicio: PowerState=$powerState ProvisioningState=$provisioningState."
    }
    while ((Get-Date) -lt $Deadline)

    throw "AKS no alcanzo Running/Succeeded dentro del timeout de $TimeoutMinutes minutos."
}

function Ensure-AksStopped {
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)

    do {
        $aks = Get-AzAksCluster -ResourceGroupName $AksResourceGroup -Name $AksName
        $powerState = [string]$aks.PowerState.Code
        $provisioningState = [string]$aks.ProvisioningState
        Write-Output "AKS: PowerState=$powerState ProvisioningState=$provisioningState"

        if (($powerState -eq "Stopped") -and ($provisioningState -eq "Succeeded")) {
            return
        }

        if (($powerState -in @("Starting", "Stopping")) -or ($provisioningState -in @("Creating", "Updating"))) {
            Write-Output "AKS esta en transicion. Se espera sin emitir otra operacion."
            Start-Sleep -Seconds $PollSeconds
            continue
        }

        if (($powerState -eq "Running") -and ($provisioningState -eq "Succeeded")) {
            Write-Output "Deteniendo AKS..."
            Stop-AzAksCluster -ResourceGroupName $AksResourceGroup -Name $AksName -Confirm:$false -ErrorAction Stop | Out-Null
            Start-Sleep -Seconds $PollSeconds
            continue
        }

        throw "AKS quedo en un estado no esperado para la detencion: PowerState=$powerState ProvisioningState=$provisioningState."
    }
    while ((Get-Date) -lt $deadline)

    throw "AKS no alcanzo Stopped/Succeeded dentro del timeout de $TimeoutMinutes minutos."
}

function Ensure-PostgreSqlStopped {
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)

    do {
        $postgresql = Get-AzPostgreSqlFlexibleServer -ResourceGroupName $PostgreSqlResourceGroup -Name $PostgreSqlName
        $state = [string]$postgresql.State
        Write-Output "PostgreSQL: $state"

        if ($state -eq "Stopped") {
            return
        }

        if ($state -in @("Starting", "Stopping", "Updating", "Restarting", "Reconfiguring")) {
            Write-Output "PostgreSQL esta en transicion ($state). Se espera sin emitir otra operacion."
            Start-Sleep -Seconds $PollSeconds
            continue
        }

        if ($state -eq "Ready") {
            Write-Output "Deteniendo PostgreSQL..."
            Stop-AzPostgreSqlFlexibleServer -ResourceGroupName $PostgreSqlResourceGroup -Name $PostgreSqlName -Confirm:$false -ErrorAction Stop | Out-Null
            Start-Sleep -Seconds $PollSeconds
            continue
        }

        throw "PostgreSQL quedo en un estado no esperado para la detencion: $state."
    }
    while ((Get-Date) -lt $deadline)

    throw "PostgreSQL no alcanzo Stopped dentro del timeout de $TimeoutMinutes minutos."
}

# Valida que la aplicacion realmente responda, no solo que el servicio
# administrado reporte "Running". Ejecuta kubectl dentro del propio
# cluster mediante el comando administrado de AKS.
function Assert-AksWorkloads {
    param([datetime]$Deadline)

    $remainingSeconds = [int][Math]::Floor(($Deadline - (Get-Date)).TotalSeconds)
    if ($remainingSeconds -le 0) {
        throw "No queda tiempo dentro del timeout global de inicio para validar workloads."
    }

    $workloadTimeoutSeconds = [int][Math]::Min($WorkloadTimeoutSeconds, $remainingSeconds)

    $command = @"
set -e
kubectl wait --for=condition=Ready nodes --all --timeout=${workloadTimeoutSeconds}s
kubectl wait --for=condition=available deployment --all -n $AppNamespace --timeout=${workloadTimeoutSeconds}s
kubectl get deployments -n $AppNamespace
kubectl get pods -n $AppNamespace -o wide
"@

    Write-Output "Validando nodos, deployments y pods en namespace $AppNamespace..."

    $result = Invoke-AzAksRunCommand `
        -ResourceGroupName $AksResourceGroup `
        -Name $AksName `
        -Command $command `
        -Force `
        -Confirm:$false `
        -ErrorAction Stop

    if ($result.Logs) {
        Write-Output $result.Logs
    }

    if ([int]$result.ExitCode -ne 0) {
        throw "Validacion de workloads fallida. ExitCode=$($result.ExitCode)."
    }

    Write-Output "Validacion de workloads completada: nodos Ready y deployments disponibles."
}

function Invoke-Start {
    $startDeadline = (Get-Date).AddMinutes($StartTimeoutMinutes)

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            if ((Get-Date) -ge $startDeadline) {
                throw "Inicio no alcanzo el estado saludable dentro del timeout global de $StartTimeoutMinutes minutos."
            }

            Write-Output "Inicio: intento $attempt/$MaxAttempts."
            Import-RequiredModules
            Ensure-PostgreSqlReady -Deadline $startDeadline
            Ensure-AksRunning -Deadline $startDeadline
            Assert-AksWorkloads -Deadline $startDeadline

            Write-Output "Inicio completado y validado: PostgreSQL Ready, AKS Running y workloads saludables."
            return
        }
        catch {
            if ($attempt -eq $MaxAttempts) {
                throw "Inicio fallido despues de $MaxAttempts intentos. Detalle: $($_.Exception.Message)"
            }

            Write-Warning "El intento de inicio no termino correctamente. Se reintenta el flujo completo en $RetryDelaySeconds segundos."
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}

function Invoke-Stop {
    Import-RequiredModules
    Ensure-AksStopped
    Ensure-PostgreSqlStopped
    Write-Output "Detencion completada: AKS Stopped y PostgreSQL Stopped."
}

# La identidad administrada autentica sin secretos persistidos.
Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
Set-AzContext -Subscription $SubscriptionName | Out-Null

Write-Output "Accion solicitada: $Action"

if ($Action -eq "Start") {
    Invoke-Start
}
else {
    Invoke-Stop
}
