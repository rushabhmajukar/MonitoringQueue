# ------------------- CONFIGURATION -------------------
# Replace these with your actual details
$collectionUrl = "http://DomainName.local/Pro/tfs"
$project = "YourProject"
$agentPoolName = "ProAB"
$adoPat = "YOUR_PERSONAL_ACCESS_TOKEN"

# -----------------------------------------------------
# Base64 encode PAT for authentication
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$adoPat"))
$headers = @{
    Authorization = "Basic $base64AuthInfo"
    "Content-Type" = "application/json"
}

# Get agent pool ID
$poolUrl = "$collectionUrl/_apis/distributedtask/pools?api-version=6.0"
$pools = (Invoke-RestMethod -Uri $poolUrl -Headers $headers).value
$poolId = ($pools | Where-Object { $_.name -eq $agentPoolName }).id
Write-Host "Agent Pool ID: $poolId"

# Get agent queues in this pool
$queueUrl = "$collectionUrl/$project/_apis/distributedtask/queues?poolIds=$poolId&api-version=6.0"
$queues = (Invoke-RestMethod -Uri $queueUrl -Headers $headers).value
$queueIds = $queues.id
Write-Host "Agent Queue IDs in pool '$agentPoolName': $($queueIds -join ', ')"

# Get builds that are notStarted or inProgress
$buildUrl = "$collectionUrl/$project/_apis/build/builds?statusFilter=notStarted,inProgress&api-version=6.0"
$builds = (Invoke-RestMethod -Uri $buildUrl -Headers $headers).value
Write-Host "Total builds in queue (not started/in progress): $($builds.Count)"

$buildsUsingPool = @()

foreach ($build in $builds) {
    if ($queueIds -contains $build.queue.id) {
        $buildsUsingPool += $build
        Write-Host "Build $($build.id) is using a queue in pool '$agentPoolName'."
    }
}

Write-Host "`nBuilds using agent pool '$agentPoolName': $($buildsUsingPool.Count)"
Write-Host "Build IDs: $($buildsUsingPool.id -join ', ')"

# Disconnect to avoid session clutter
Disconnect-AzAccount -ErrorAction SilentlyContinue
