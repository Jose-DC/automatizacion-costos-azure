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
$ErrorActionPreference = 'Stop'

function Get-PostgresState {
    az postgres flexible-server show `
        --subscription $Subscription `
        --resource-group $DatabaseResourceGroup `
        --name $DatabaseName `
        --query state `
        --output tsv
}

function Get-AksPowerState {
    az aks show `
        --subscription $Subscription `
        --resource-group $AksResourceGroup `
        --name $AksName `
        --query powerState.code `
        --output tsv
}

if ($Action -eq 'Start') {
    Write-Output "Iniciando PostgreSQL: $DatabaseName"
    az postgres flexible-server start --subscription $Subscription --resource-group $DatabaseResourceGroup --name $DatabaseName

    do {
        Start-Sleep -Seconds 30
        $databaseState = Get-PostgresState
        Write-Output "Estado PostgreSQL: $databaseState"
    } while ($databaseState -ne 'Ready')

    Write-Output "Iniciando AKS: $AksName"
    az aks start --subscription $Subscription --resource-group $AksResourceGroup --name $AksName
}
else {
    Write-Output "Deteniendo AKS: $AksName"
    az aks stop --subscription $Subscription --resource-group $AksResourceGroup --name $AksName

    do {
        Start-Sleep -Seconds 30
        $aksState = Get-AksPowerState
        Write-Output "Estado AKS: $aksState"
    } while ($aksState -ne 'Stopped')

    Write-Output "Deteniendo PostgreSQL: $DatabaseName"
    az postgres flexible-server stop --subscription $Subscription --resource-group $DatabaseResourceGroup --name $DatabaseName
}
