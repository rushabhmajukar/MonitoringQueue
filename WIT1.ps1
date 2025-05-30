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

# Get builds that are notStarted or inProgress
$buildUrl = "$collectionUrl/$project/_apis/build/builds?statusFilter=notStarted,inProgress&api-version=6.0"
$builds = (Invoke-RestMethod -Uri $buildUrl -Headers $headers).value
Write-Host "Total builds in queue (not started/in progress): $($builds.Count)"

$buildsUsingPool = @()

foreach ($build in $builds) {
    if ($build.orchestrationPlan) {
        $timelineUrl = "$collectionUrl/$project/_apis/build/builds/$($build.id)/timeline?api-version=6.0"
        try {
            $timeline = Invoke-RestMethod -Uri $timelineUrl -Headers $headers -ErrorAction Stop

            # Find job records with an agent assigned
            $agentRecords = $timeline.records | Where-Object { $_.recordType -eq "Job" -and $_.agentId }
            foreach ($record in $agentRecords) {
                # Check if the agent belongs to the specified pool
                $agentUrl = "$collectionUrl/_apis/distributedtask/pools/$poolId/agents/$($record.agentId)?api-version=6.0"
                try {
                    $agent = Invoke-RestMethod -Uri $agentUrl -Headers $headers -ErrorAction Stop
                    if ($agent) {
                        $buildsUsingPool += $build
                        Write-Host "Build $($build.id) is using agent pool $agentPoolName."
                        break # Build is using this pool, skip to next build
                    }
                } catch {
                    # Agent not found in this pool, skip
                }
            }
        } catch {
            Write-Warning "Could not get timeline for build $($build.id): $_"
        }
    }
}

Write-Host "`nBuilds using agent pool '$agentPoolName': $($buildsUsingPool.Count)"
Write-Host "Build IDs: $($buildsUsingPool.id -join ', ')"

# Disconnect to avoid session clutter
Disconnect-AzAccount -ErrorAction SilentlyContinue

