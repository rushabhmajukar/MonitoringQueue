$buildUrl = "$($envContext["COLLECTIONURL"])/$($envContext["PROJECT"])/_apis/build/builds?statusFilter=notStarted,inProgress&api-version=6.0"
$builds = (Invoke-RestMethod -Uri $buildUrl -Headers $headers).value

# Get agent pool ID for your target pool
$poolUrl = "$($envContext["COLLECTIONURL"])/_apis/distributedtask/pools?api-version=6.0"
$pools = (Invoke-RestMethod -Uri $poolUrl -Headers $headers).value
$poolId = ($pools | Where-Object { $_.name -eq $envContext["AGENTPOOL"] }).id

$buildsUsingPool = @()

foreach ($build in $builds) {
    if ($build.orchestrationPlan) {
        $timelineUrl = "$($envContext["COLLECTIONURL"])/$($envContext["PROJECT"])/_apis/build/builds/$($build.id)/timeline?api-version=6.0"
        $timeline = Invoke-RestMethod -Uri $timelineUrl -Headers $headers

        # Find records that represent jobs running on agents
        $agentRecords = $timeline.records | Where-Object { $_.recordType -eq "Job" -and $_.agentId }
        foreach ($record in $agentRecords) {
            # Get agent details
            $agentUrl = "$($envContext["COLLECTIONURL"])/_apis/distributedtask/pools/$poolId/agents/$($record.agentId)?api-version=6.0"
            try {
                $agent = Invoke-RestMethod -Uri $agentUrl -Headers $headers -ErrorAction Stop
                if ($agent) {
                    $buildsUsingPool += $build
                    break # This build uses the pool, move to the next build
                }
            } catch {
                # Agent not found in this pool
            }
        }
    }
}

Write-Host "Builds using agent pool $($envContext["AGENTPOOL"]): $($buildsUsingPool.Count)"
