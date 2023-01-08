<#
  .SYNOPSIS
  Script to Apply Conditional Access changes. 
  .DESCRIPTION
  This script fetches policies from the chosen directories, and creates a API request to deploy or remove said policies
  
#>

Param (
    [Parameter(Mandatory = $true)] [string] $clientId,
    [Parameter(Mandatory = $true)] [string] $clientSecret,
    [Parameter(Mandatory = $true)] [string] $tenantId
)

# Import get graph token module
Write-Host "##[command]Importing Graph Token module"
Import-Module -Name './scripts/get-graph-token.psm1'

# main script starts here

$ErrorActionPreference = "Stop"

# Get Graph token
Write-Host "[INFO] Fetching Graph API Token..."

try {
    $token = Get-GraphToken -clientId $clientId -tenantId  $tenantId -clientSecret $clientSecret
}
catch {
    Write-Host "##[error] Failed to fetch Api Token using Client ID [$clientId] & tenant ID [$tenantId]"
    throw $_.Exception
}

Write-Host "##[section]API token fetched successfully."

# Properties to remove from policies that are not valid
$cleanUpProperties = @(
    "id",
    "createdDateTime",
    "modifiedDateTime"
)

# Deploy new policy
$newPoliciesDir = './new'
$newExists = Test-Path -Path $newPoliciesDir
if ($newExists) {
    Write-Host "[INFO] Fetching all local Json files stored under [$newPoliciesDir]..."
    $newPoliciesPath = (Get-ChildItem -Path $newPoliciesDir -Filter "*.json" -Recurse).FullName
}
else {
    Write-Host "##[section]No new policies to deploy as no new JSON policies found"
}
if ($newPoliciesPath.count -gt 0) {
    $method = "POST"
    $contentType = "application/json"
    $header = @{Authorization = "Bearer $($token)" }
    foreach ($policy in $newPoliciesPath) {
        $jsonPolicy = Get-Content -Raw -Path $policy
        $policyName = ($jsonPolicy | ConvertFrom-Json).displayName
        foreach ($object in ($jsonPolicy | ConvertFrom-Json)) {
            foreach ($property in $cleanUpProperties) {
                $object.PSObject.Properties.Remove($property)
            }
        }
        $jsonBody = $object | ConvertTo-Json -Depth 9
        $apiUri = "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies"
        Write-Host "[INFO] Deploying new policy [$policyName]"
        try {
            $request = (Invoke-WebRequest -Headers $header -Uri $apiUri -Method $method -ContentType $contentType -Body $jsonBody)
            if ($request.StatusCode -lt 300) {
                Write-Host "##[section]New policy [$policyName] deployed successfully!" -ForegroundColor Green
            }
            else {
                Write-Host "##[error] New policy [$policyName] deployment was unsuccessful!" -ForegroundColor Red
                Write-Host $request.StatusCode
                Write-Host $request.StatusDescription
            }
        }
        catch {
            Write-Host "##[error] Failed to deploy new policy [$policyName]!"
            Write-Host "##[error] Response details [$request] - full exception: [$_]!"
            throw $_.Exception
        } 
    }
}
else {
    Write-Host "[INFO] No new policies to deploy as no JSON policies found under $newPoliciesDir"
}

# Remove policy 
$removePoliciesDir = './remove'
$removeExists = Test-Path -Path $removePoliciesDir
if ($removeExists) {
    Write-Host "[INFO] Fetching all remote Json files stored under [$removePoliciesDir]..."
    $removePoliciesPath = (Get-ChildItem -Path $removePoliciesDir -Filter "*.json" -Recurse).FullName
}
else {
    Write-Host "##[section]No policies to remove as no remove JSON policies found"
}
if ($removePoliciesPath.count -gt 0) {
    $method = "DELETE"
    $header = @{Authorization = "Bearer $($token)" }
    foreach ($policy in $removePoliciesPath) {
        $jsonPolicy = Get-Content -Raw -Path $policy
        $policyName = ($jsonPolicy | ConvertFrom-Json).displayName
        $policyID = ($jsonPolicy | ConvertFrom-Json).id
        $apiUri = "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$policyID"
        Write-Host "[INFO] Removing policy [$policyName] with ID [$policyID]"
        try {
            $request = (Invoke-WebRequest -Headers $header -Method $method -Uri $apiUri)
            if ($request.StatusCode -lt 300) {
                Write-Host "##[section]Policy [$policyName] with ID [$policyID] removed successfully!" -ForegroundColor Green
            }
            else {
                Write-Host $request.StatusCode
                Write-Host $request.StatusDescription
            }
        }
        catch {
            Write-Host "##[error] Failed to remove policy [$policyName] with ID [$policyID]!"
            throw $_.ErrorDetails.Message
        }
    }
}
else {
    Write-Host "[INFO] No policies to remove as no remote JSON policies found under $removePoliciesDir"
}

# Deploy update policy
$updatePoliciesDir = './update'
$updateExists = Test-Path -Path $updatePoliciesDir
if ($updateExists) {
    Write-Host "[INFO] Fetching all local Json files stored under [$updatePoliciesDir]..."
    $updatePoliciesPath = (Get-ChildItem -Path $updatePoliciesDir -Filter "*.json" -Recurse).FullName
}
else {
    Write-Host "##[section]No policies to update as no updated JSON policies found"
}
if ($updatePoliciesPath.count -gt 0) {
    $method = "PATCH"
    $contentType = "application/json"
    $header = @{Authorization = "Bearer $($token)" }
    foreach ($policy in $updatePoliciesPath) {
        $jsonPolicy = Get-Content -Raw -Path $policy
        $policyName = ($jsonPolicy | ConvertFrom-Json).displayName
        $policyID = ($jsonPolicy | ConvertFrom-Json).id
        foreach ($object in ($jsonPolicy | ConvertFrom-Json)) {
            foreach ($property in $cleanUpProperties) {
                $object.PSObject.Properties.Remove($property)
            }
        }
        $jsonBody = $object | ConvertTo-Json -Depth 9
        $apiUri = "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$policyID"
        Write-Host "[INFO] Updating policy [$policyName] with ID [$policyID]"
        try {
            $request = (Invoke-WebRequest -Headers $header -Uri $apiUri -Method $method -ContentType $contentType -Body $jsonBody)
            if ($request.StatusCode -lt 300) {
                Write-Host "##[section]Policy [$policyName] with ID [$policyID] updated successfully!" -ForegroundColor Green
            }
            else {
                Write-Host $request.StatusCode
                Write-Host $request.StatusDescription
            }
        }
        catch {
            Write-Host "##[error] Failed to update policy [$policyName] with ID [$policyID]!"
            throw $_.ErrorDetails.Message
        }
    }
}
else {
    Write-Host "[INFO] No policies to update as no JSON policies found under $updatePoliciesDir"
}
