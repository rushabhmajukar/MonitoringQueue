$collectionUrl = $env:CollectionURL
$project = $env:Project
$agentPoolName = $env:Agent_Pool_Name

$resourceGroupName = $env:Az_RG
$agentVMs = @("$env:Az_VM") 

$pat = $env:ADO_PAT

$clientId = $env:Az_Client_ID
$clientSecret = $env:Az_Client_Secret
$tenantId = $env:Az_Tenant_ID
$subscriptionId = $env:Az_Subscription_ID

$securePassword = ConvertTo-SecureString $clientSecret -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($clientId, $securePassword)

Connect-AzAccount -ServicePrincipal -Credential $cred -TenantId $tenantId | Out-Null
Set-AzContext -SubscriptionId $subscriptionId | Out-Null

$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
$headers = @{ Authorization = "Basic $base64AuthInfo" }

function Get-QueuedBuildCount {
    $url = "$collectionUrl/$project/_apis/build/builds?statusFilter=notStarted&api-version=6.0"
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    return $response.count
}

function Get-AgentPoolId {
    $url = "$collectionUrl/_apis/distributedtask/pools?api-version=6.0"
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    return ($response.value | Where-Object { $_.name -eq $agentPoolName }).id
}

function Get-OfflineAgents {
    $poolId = Get-AgentPoolId
    $url = "$collectionUrl/_apis/distributedtask/pools/$poolId/agents?api-version=6.0"
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    return $response.value | Where-Object { $_.status -eq "offline" }
}

function Get-OnlineAgents {
    $poolId = Get-AgentPoolId
    $url = "$collectionUrl/_apis/distributedtask/pools/$poolId/agents?api-version=6.0"
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    return $response.value | Where-Object { $_.status -eq "online" }
}

$queuedBuilds = Get-QueuedBuildCount
Write-Host "Queued Builds: $queuedBuilds"

if ($queuedBuilds -gt 0) {
    $offlineAgents = Get-OfflineAgents
    foreach ($agent in $offlineAgents) {
        $vmName = $agentVMs | Where-Object { $agent.name -like "*$_*" }
        if ($vmName) {
            Write-Host "Starting VM: $vmName"
            Start-AzVM -Name $vmName -ResourceGroupName $resourceGroupName
        }
    }
} else {
    $onlineAgents = Get-OnlineAgents
    foreach ($agent in $onlineAgents) {
        $vmName = $agentVMs | Where-Object { $agent.name -like "*$_*" }
        if ($vmName) {
            Write-Host "Stopping VM: $vmName"
            Stop-AzVM -Name $vmName -ResourceGroupName $resourceGroupName -Force
        }
    }
}
