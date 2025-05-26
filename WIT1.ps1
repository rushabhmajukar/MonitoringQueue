# Variables
$organization = "your_organization"
$project = "your_project"
$pat = "your_pat_here"   # 🔴 Use a PAT with work item read permissions

# Base64-encoded PAT for authentication
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)"))

# Get today's date and calculate 10 days ago
$tenDaysAgo = (Get-Date).AddDays(-10).ToString("yyyy-MM-ddTHH:mm:ssZ")

# Query to find requirements assigned to you that changed in the last 10 days
$query = @"
SELECT [System.Id]
FROM WorkItems
WHERE
    [System.WorkItemType] = 'Requirement'
    AND [System.AssignedTo] = @Me
    AND [System.ChangedDate] >= '$tenDaysAgo'
"@

# Create query in Azure DevOps
$wiqlBody = @{
    query = $query
} | ConvertTo-Json

$uri = "https://dev.azure.com/$organization/$project/_apis/wit/wiql?api-version=7.1-preview.2"

$response = Invoke-RestMethod -Uri $uri -Method Post -Body $wiqlBody -Headers @{
    Authorization = "Basic $base64AuthInfo"
    "Content-Type" = "application/json"
}

# Extract work item IDs
$workItemIds = $response.workItems.id

if ($workItemIds.Count -eq 0) {
    Write-Output "No requirements found assigned to you in the last 10 days."
    return
}

# Create a list to hold all revision history entries
$historyList = @()

# Loop through work item IDs and get their revisions
foreach ($id in $workItemIds) {
    Write-Output "`n=== Work Item ID: $id ==="
    $revisionsUri = "https://dev.azure.com/$organization/$project/_apis/wit/workitems/$id/revisions?api-version=7.1-preview.3"
    $revisions = Invoke-RestMethod -Uri $revisionsUri -Headers @{Authorization = "Basic $base64AuthInfo"}
    
    foreach ($rev in $revisions.value) {
        $entry = [PSCustomObject]@{
            WorkItemId = $id
            Revision = $rev.rev
            ChangedBy = $rev.fields."System.ChangedBy".displayName
            ChangedDate = $rev.fields."System.ChangedDate"
            State = $rev.fields."System.State"
            Title = $rev.fields."System.Title"
        }
        # Add to the list
        $historyList += $entry
    }
}

# Output to CSV file
$outputPath = "C:\Temp\RevisionHistory.csv"
$historyList | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8

Write-Output "Revision history saved to $outputPath"
