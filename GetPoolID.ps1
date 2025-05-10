# Azure DevOps Server details
$collectionUrl = "org url"
$pat = "xxx" 

# Authentication setup
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
$headers = @{
    Authorization = "Basic $base64AuthInfo"
    "Content-Type" = "application/json"
}

# Fetch all agent pools
$poolsUrl = "$collectionUrl/_apis/distributedtask/pools?api-version=6.0"
$response = Invoke-RestMethod -Uri $poolsUrl -Headers $headers -Method Get

# Display all pool names with IDs
$response.value | Format-Table id, name
