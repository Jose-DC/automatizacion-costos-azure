param(
    [ValidateSet('Start', 'Stop')]
    [string]$Action = 'Start',
    [string]$Subscription = '<SUBSCRIPTION_ID>',
    [string]$AksResourceGroup = '<AKS_RESOURCE_GROUP>',
    [string]$AksName = '<AKS_NAME>',
    [string]$DatabaseResourceGroup = '<DATABASE_RESOURCE_GROUP>',
    [string]$DatabaseName = '<POSTGRES_SERVER_NAME>'
)

# Ejemplo educativo. Revisar nombres, permisos y dependencias antes de usarlo.
# La intención es mostrar la secuencia, no entregar un script listo para producción.
$ErrorActionPreference = 'Stop'

# Consulta el estado de PostgreSQL para no iniciar AKS antes de tiempo.
function Get-PostgresState {
    az postgres flexible-server show `
        --subscription $Subscription `
        --resource-group $DatabaseResourceGroup `
        --name $DatabaseName `
        --query state `
        --output tsv
}

# Consulta el estado de energía del clúster AKS.
function Get-AksPowerState {
    az aks show `
        --subscription $Subscription `
        --resource-group $AksResourceGroup `
        --name $AksName `
        --query powerState.code `
        --output tsv
}

# Al iniciar, PostgreSQL debe estar disponible antes de recuperar el clúster.
if ($Action -eq 'Start') {
    Write-Output "Iniciando PostgreSQL: $DatabaseName"
    az postgres flexible-server start --subscription $Subscription --resource-group $DatabaseResourceGroup --name $DatabaseName

    # Espera a que Azure confirme que la base de datos está lista.
    do {
        Start-Sleep -Seconds 30
        $databaseState = Get-PostgresState
        Write-Output "Estado PostgreSQL: $databaseState"
    } while ($databaseState -ne 'Ready')

    # Solo después se solicita el inicio de AKS.
    Write-Output "Iniciando AKS: $AksName"
    az aks start --subscription $Subscription --resource-group $AksResourceGroup --name $AksName
}
else {
    # Al detener, primero se baja AKS para que los workloads no pierdan la base de datos.
    Write-Output "Deteniendo AKS: $AksName"
    az aks stop --subscription $Subscription --resource-group $AksResourceGroup --name $AksName

    # Espera a que el clúster confirme el estado detenido.
    do {
        Start-Sleep -Seconds 30
        $aksState = Get-AksPowerState
        Write-Output "Estado AKS: $aksState"
    } while ($aksState -ne 'Stopped')

    # PostgreSQL se detiene al final de la secuencia.
    Write-Output "Deteniendo PostgreSQL: $DatabaseName"
    az postgres flexible-server stop --subscription $Subscription --resource-group $DatabaseResourceGroup --name $DatabaseName
}
