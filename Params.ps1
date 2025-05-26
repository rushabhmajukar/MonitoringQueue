param (
    [Parameter(Mandatory)]
    [string[]]$EnvironmentPrefixes,

    [Parameter(Mandatory)]
    [string]$CollectionUrl,

    [Parameter(Mandatory)]
    [string]$Project,

    [Parameter(Mandatory)]
    [string]$AgentPool,

    [Parameter(Mandatory)]
    [string[]]$AzVMs,

    [Parameter(Mandatory)]
    [string]$AzResourceGroup,

    [Parameter(Mandatory)]
    [string]$AdoPAT,

    [Parameter(Mandatory)]
    [string]$AzTenantId,

    [Parameter(Mandatory)]
    [string]$AzClientId,

    [Parameter(Mandatory)]
    [string]$AzClientSecret,

    [Parameter(Mandatory)]
    [string]$AzSubscriptionId
)

function Monitor-And-Scale {
    param (
        [string]$Prefix,
        [string]$CollectionUrl,
        [string]$Project,
        [string]$AgentPool,
        [string[]]$AzVMs,
        [string]$AzResourceGroup,
        [string]$AdoPAT,
        [string]$AzTenantId,
        [string]$AzClientId,
        [string]$AzClientSecret,
        [string]$AzSubscriptionId
    )

    Write-Host "`n===== Checking: $Prefix ($AgentPool) ====="

    # Azure Login
    $securePassword = ConvertTo-SecureString $AzClientSecret -AsPlainText -Force
    $cred = New-Object PSCredential ($AzClientId, $securePassword)
    Connect-AzAccount -ServicePrincipal -TenantId $AzTenantId -Credential $cred | Out-Null
    Set-AzContext -SubscriptionId $AzSubscriptionId | Out-Null

    # Azure DevOps API Auth
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$AdoPAT"))
    $headers = @{
        Authorization = "Basic $base64AuthInfo"
        "Content-Type" = "application/json"
    }

    # Get Agent Pool ID
    $poolUrl = "$CollectionUrl/_apis/distributedtask/pools?api-version=6.0"
    $poolResp = Invoke-RestMethod -Uri $poolUrl -Headers $headers -Method Get
    $poolId = ($poolResp.value | Where-Object { $_.name -eq $AgentPool }).id

    # Check queued builds
    $buildUrl = "$CollectionUrl/$Project/_apis/build/builds?statusFilter=notStarted&api-version=6.0"
    $buildResp = Invoke-RestMethod -Uri $buildUrl -Headers $headers -Method Get
    $queuedCount = $buildResp.count

    if ($queuedCount -gt 0) {
        Write-Host "Builds in queue: $queuedCount"

        $agentsUrl = "$CollectionUrl/_apis/distributedtask/pools/$poolId/agents?api-version=6.0"
        $agents = (Invoke-RestMethod -Uri $agentsUrl -Headers $headers).value
        $offlineAgents = $agents | Where-Object { $_.status -eq "offline" }

        foreach ($agent in $offlineAgents) {
            $vmName = $AzVMs | Where-Object { $_ -like "*$($agent.name)*" }
            if ($vmName) {
                Write-Host "Starting VM: $vmName"
                Start-AzVM -Name $vmName -ResourceGroupName $AzResourceGroup
            }
        }
    } else {
        Write-Host "No builds in queue. Checking idle agents..."

        $agentsUrl = "$CollectionUrl/_apis/distributedtask/pools/$poolId/agents?includeAssignedRequest=true&api-version=6.0"
        $agents = (Invoke-RestMethod -Uri $agentsUrl -Headers $headers).value
        $idleAgents = $agents | Where-Object { $_.status -eq "online" -and -not $_.assignedRequest }

        if ($idleAgents.Count -gt 1) {
            $agentsToStop = $idleAgents | Select-Object -Skip 1
            foreach ($agent in $agentsToStop) {
                $vmName = $AzVMs | Where-Object { $_ -like "*$($agent.name)*" }
                if ($vmName) {
                    Write-Host "Stopping VM: $vmName"
                    Stop-AzVM -Name $vmName -ResourceGroupName $AzResourceGroup -Force
                }
            }
        } else {
            Write-Host "Only one idle agent; skipping shutdown."
        }
    }

    # Close Azure session
    Disconnect-AzAccount -Scope Process -ErrorAction SilentlyContinue
}

# Main Loop
foreach ($prefix in $EnvironmentPrefixes) {
    try {
        Monitor-And-Scale `
            -Prefix $prefix `
            -CollectionUrl $CollectionUrl `
            -Project $Project `
            -AgentPool $AgentPool `
            -AzVMs $AzVMs `
            -AzResourceGroup $AzResourceGroup `
            -AdoPAT $AdoPAT `
            -AzTenantId $AzTenantId `
            -AzClientId $AzClientId `
            -AzClientSecret $AzClientSecret `
            -AzSubscriptionId $AzSubscriptionId
    } catch {
        Write-Error "Failed for environment prefix '$prefix': $_"
    }
}
