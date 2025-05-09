$subscriptionId = "xxx"
$tenantId = "xxx"
$clientId = "xxx"
$clientSecret = "xxx"

$securePassword = ConvertTo-SecureString $clientSecret -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($clientId, $securePassword)

Connect-AzAccount -ServicePrincipal -TenantId $tenantId -Credential $cred
Set-AzContext -SubscriptionId $subscriptionId

$collectionUrl = "Organization url of ADO"
$projectName = "xxx"
$pat = "xx"
$agentPoolId = xx  
$vmList = @("abc", "def", "etc")  
$resourceGroupName = "xxx"

$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
$headers = @{
    Authorization = "Basic $base64AuthInfo"
    "Content-Type" = "application/json"
}

$buildQueueUrl = "$collectionUrl/$projectName/_apis/build/builds?statusFilter=notStarted&api-version=6.0"
$buildQueue = Invoke-RestMethod -Uri $buildQueueUrl -Headers $headers -Method Get
$queuedCount = $buildQueue.count

if ($queuedCount -gt 0) {
    Write-Host "There are $($queuedCount) builds in the queue. Checking agents..."
    
    $agentsUrl = "$collectionUrl/_apis/distributedtask/pools/$agentPoolId/agents?api-version=6.0"
    $agentData = Invoke-RestMethod -Uri $agentsUrl -Headers $headers -Method Get

    $offlineAgents = $agentData.value | Where-Object { $_.status -eq "offline" }

    foreach ($agent in $offlineAgents) {
        $vmName = $vmList | Where-Object { $_ -like "*$($agent.name)*" }
        if ($vmName) {
            Write-Host "Starting VM for agent: $($agent.name)"
            Start-AzVM -Name $vmName -ResourceGroupName $resourceGroupName
        }
    }
} else {
    Write-Host "No builds in queue. Checking for idle agents..."

    $agentsUrl = "$collectionUrl/_apis/distributedtask/pools/$agentPoolId/agents?includeAssignedRequest=true&api-version=6.0"
    $agentData = Invoke-RestMethod -Uri $agentsUrl -Headers $headers -Method Get

    $idleAgents = $agentData.value | Where-Object { $_.status -eq "online" -and -not $_.assignedRequest }
    
    if ($idleAgents.count -gt 1) {
        $agentsToStop = $idleAgents | Select-Object -Skip 1

        foreach ($agent in $agentsToStop) {
            $vmName = $vmList | Where-Object { $_ -like "*$($agent.name)*" }
            if ($vmName) {
                Write-Host "Stopping idle VM: $($agent.name)"
                Stop-AzVM -Name $vmName -ResourceGroupName $resourceGroupName -Force
            }
        }
    } else {
        Write-Host "Only one agent is idle or available. No VMs will be shut down."
    }
}
