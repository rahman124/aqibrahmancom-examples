<#
  .SYNOPSIS
  Script to Plan Conditional Access changes. 

  .DESCRIPTION
  This script fetches remote policies from Azure, and compares to local policies, outputting any differences for inspection.
  
#>

Param (
    [Parameter(Mandatory = $true)] [string] $clientId,
    [Parameter(Mandatory = $true)] [string] $clientSecret,
    [Parameter(Mandatory = $true)] [string] $tenantId
)

# Import get graph token module
Write-Host "##[command]Importing Graph Token module"
Import-Module -Name './scripts/get-graph-token.psm1'

# Get Local and Remote Policies
Function Get-Policies {

    Param(
        [parameter(Mandatory = $true)]
        $clientId,
        [parameter(Mandatory = $true)]
        $tenantId,
        [parameter(Mandatory = $true)]
        $clientSecret
    )

    # Get all remote policies
    $apiUri = "https://graph.microsoft.com/beta/identity/conditionalAccess/policies"
    Write-Host "##[command]Fetching Graph API Token..."

    try {
        $token = Get-GraphToken -clientId $clientId -tenantId  $tenantId -clientSecret $clientSecret
    }
    catch {
        Write-Host "##[error] Failed to fetch Api Token using Client ID [$clientId] & tenant ID [$tenantId]"
        throw $_.Exception
    }
    
    Write-Host "##[section]API token fetched successfully."
    Write-Host "##[command]Fetching Live Conditional Access Policies..."

    try {
        $remotePoliciesRaw = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)" } -Uri $apiUri -Method Get
    }
    catch {
        Write-Host "##[error] Failed to fetch remote policies from [$apiUri]"
        throw $_.Exception
    }

    Write-Host "##[section]Successfully fetched [$($remotePoliciesRaw.value.Count)] policies."

    $script:remoteCAPolicies = $remotePoliciesRaw.value

    # Get all local policies
    $path = './policies/'

    $pathExists = Test-Path -Path $path
    if ($pathExists) {
        Write-Host "##[command]Fetching all local/source controlled Json files stored under [$path]..."
        $filePath = (Get-ChildItem -Path $path -Filter "*.json" -Recurse).FullName
    }
    else {
        Write-Host "##[error] No local path exists at [$path]"
        throw "No file path found!"

    }

    $localFileImport = foreach ($file in $filePath) {
        $filePathExists = Test-Path -Path $file
        if ($filePathExists) {
            Get-Content -Raw -Path $file
        }
    }

    Write-Host "##[section]Successfully loaded [$($filePath.Count)] policies from local source control."
    
    if ($filePath.Count -eq $remotePoliciesRaw.value.Count) {
        Write-Host "##[section]Local and remote policy count matches at [$($filePath.Count)]. Proceeding."
    }
    else {
        Write-Host "##[warning] Local policy count [$($filePath.Count)] and remote policy count [$($remotePoliciesRaw.value.Count)] mismatch..."
        Write-Host "##[warning] Ensure new/removed policies are as per expected plan!"
    }

    $script:localCAPolicies = $localFileImport | ConvertFrom-Json
}

Function Get-JsonPaths {

    <#
        .SYNOPSIS
        Get Paths of all local Json properties to Nth depth.
        Recursive function to get all the nest json property paths to allow for comparisons.

    #>

    Param(
        [parameter(Mandatory = $true)]
        $localpol,
        [parameter(Mandatory = $true)]
        $parent
    )
    
    foreach ($item in $localpol.PSObject.Properties) {
        # PsCustomObject means we are not yet at a leaf
        # Recurse to go deeper
        if ($item.TypeNameOfValue -eq "System.Management.Automation.PSCustomObject") {
            Get-JsonPaths $item.Value $($parent + "." + $item.Name)
        }
        else {
            $itemLocation = "$parent.$($item.Name)"
            $jsonPaths.Add($itemLocation) | Out-Null
            # Add local and remote policy paths to separate lists for comparison as a soft check
            if ($checkLocalPaths) {
                $localJsonPaths.Add($itemLocation) | Out-Null
            }
            if ($checkRemotePaths) {
                $remoteJsonPaths.Add($itemLocation) | Out-Null
            }
        }
    }
}

# main script starts here
$ErrorActionPreference = "Stop"

# Get remote and local policies
Get-Policies -ClientID $clientId -ClientSecret $clientSecret -tenantid $tenantId

# Set up hashtable and list
$policyAdds = [ordered]@{}
$policyRemovals = [ordered]@{}
$newPolicies = [System.Collections.ArrayList]@()
$unControlledPolicies = [System.Collections.ArrayList]@()

$jsonPaths = [System.Collections.ArrayList]@()

# Get JSON paths from local policies
$checkLocalPaths = $false
$localJsonPaths = [System.Collections.ArrayList]@()
foreach ($policy in $localCAPolicies) {
    $checkLocalPaths = $true
    Get-JsonPaths $policy ""
}

# Get JSON paths from remote policies
$checkRemotePaths = $false
$remoteJsonPaths = [System.Collections.ArrayList]@()
foreach ($policy in $remoteCAPolicies) {
    $checkRemotePaths = $true
    Get-JsonPaths $policy ""
}

# Soft check to see if remote JSON schema has changed
$compareJsonPaths = (Compare-Object -ReferenceObject ($remoteJsonPaths | select -Unique) -DifferenceObject ($localJsonPaths | select -Unique))
if ($compareJsonPaths) {
    Write-Host "##[warning] Remote JSON schema has been updated!"
    foreach ($compareJsonPath in $compareJsonPaths | Where-Object { $_.sideindicator -eq "=>" }) {
        Write-Host "##[warning] Remote JSON schema has new values: [$($compareJsonPaths.InputObject)]"
    }
    foreach ($compareJsonPath in $compareJsonPaths | Where-Object { $_.sideindicator -eq "<=" }) {
        Write-Host "##[warning] Remote JSON schema has removed values: [$($compareJsonPaths.InputObject)]"
    }
}

# Select unique items from path list
$jsonPathUnique = ($jsonPaths | Select-Object -Unique)

# Compare remote and local policies using path list
foreach ($localpol in $localCAPolicies) {
    $policyMatch = $False

    foreach ($remotepol in $remoteCAPolicies) {
        if ($localpol.id -eq $remotepol.id) {
        
            $policyMatch = $True # We have a matched ID
            $PolicyChange = $False # Default to no changes detected for this ID

            $additionalProperties = [ordered]@{}
            $removedProperties = [ordered]@{}

            Write-Host "[INFO] Checking policy id [$($localpol.id)]..."

            foreach ($jsonPath in $jsonPathUnique) {
                # Invoke Expression to get the leaf value
                if ($jsonPath -inotmatch "@odata") {
                    $remotePolicySourceValue = Invoke-Expression "`$remotepol$jsonPath" 
                    $localPolicyDestValue = Invoke-Expression "`$localpol$jsonPath"
                }
                # If both remote and local have a value set...
                if (($null -ne $remotePolicySourceValue) -and ($null -ne $localPolicyDestValue)) {
                    if ($jsonPath -eq '.modifiedDateTime') {
                        $modifiedDateTimeCompare = (Compare-Object -ReferenceObject @($remotePolicySourceValue | Select-Object) -DifferenceObject @($localPolicyDestValue | Select-Object))
                        if ($modifiedDateTimeCompare) {
                            Write-Host "[INFO] Property [modifiedDateTime] will be updated for policy [$($remotepol.displayName)] with ID [$($remotepol.id)]"
                        }
                    }
                    $comparison = (Compare-Object -ReferenceObject @($remotePolicySourceValue | Select-Object) -DifferenceObject @($localPolicyDestValue | Select-Object))
                    if ($comparison) {
                        $PolicyChange = $True 
                        $addproperty = $comparison | Where-Object { $_.sideindicator -eq "=>" }
                        $removeproperty = $comparison | Where-Object { $_.sideindicator -eq "<=" }
                        
                        if ($jsonPath -ne '.modifiedDateTime') {
                            $additionalProperties.Add($jsonPath.TrimStart(".", [char]0x0020), $addproperty.InputObject) # [char]0x0020 is unicode whitespace.
                            $removedProperties.Add($jsonPath.TrimStart(".", [char]0x0020), $removeproperty.InputObject) # Trim the dot for clearer formatting later      
                        }
                   
                    }
                }
                # Exclusive or on Null (if both null we have a match)
                elseif (($null -eq $remotePolicySourceValue) -xor ($null -eq $localPolicyDestValue)) {
                    Write-Debug "[INFO] Null Value Changing at [$jsonPath] [$remotePolicySourceValue] [$localPolicyDestValue]..."
                    #remote policy has the value
                    if ($remotePolicySourceValue) {
                        Write-Debug "[INFO] Null value is local (we have an remove)"
                        $additionalProperties.Add($jsonPath.TrimStart(".", [char]0x0020), $localPolicyDestValue)
                        $removedProperties.Add($jsonPath.TrimStart(".", [char]0x0020), $remotePolicySourceValue) 

                    }
                    else {
                        Write-Debug "[INFO] Null value is remote (we have an add)"
                        $additionalProperties.Add($jsonPath.TrimStart(".", [char]0x0020), $localPolicyDestValue)
                        $removedProperties.Add($jsonPath.TrimStart(".", [char]0x0020), $remotePolicySourceValue) 
                    }

                }
                
            }
            if ($PolicyChange) {
                $policyAdds.add($localpol.id, $additionalProperties)
                $policyRemovals.add($localpol.id, $removedProperties)
            }

        }

    }
    if (!$policyMatch) {
        Write-Host "##[warning] Local Policy [$($localpol.displayName)] was not detected in the remote!"
        Write-Host "##[warning] This means we will be deploying a new policy."
        $newPolicies += $localpol
    }
}

# Check if we should be removing any policies from remote as they don't exist in source control
# Note! These may simply be missing and not necessarily deleted.

foreach ($remotepol in $remoteCAPolicies) {
    $policyMatch = $False

    foreach ($localpol in $localCAPolicies) {
        if ($localpol.id -eq $remotepol.id) {
            $policyMatch = $True
        }
    }
    if (!$policyMatch) {
        Write-Output "[INFO] Policy [$($remotepol.id)] exists remotely but not in source control!"
        $unControlledPolicies += $remotepol

    }
}

Write-Host "##[section]All policy ID checked and compared.`n`n"

# Check if there are any changes
if (($policyAdds.Count -eq 0) -and ($policyRemovals.Count -eq 0) -and ($newPolicies.Count -eq 0)) { 
    Write-Host "##[section]No changes detected, local policy definitions matches the remote." -ForegroundColor Green
}
else {
    Write-Host "##[warning] There are changes detected between Local and Remote policies. Details are output below"
    Write-Host "##[warning] Ensure the changes are carefully examined before proceeding with any changes!!`n"
}

# Output plan
if ($policyAdds.Count -gt 0) {
    foreach ($changingPolicy in $policyAdds.GetEnumerator()) {
        Write-Output "[INFO] Property Changes for policy [$(($remoteCAPolicies | ? -Property id -EQ $changingPolicy.Name).displayName)] with ID [$($changingPolicy.Name)]`n"
        @"
        ##[group] Live JSON policy: [$(($remoteCAPolicies | ? -Property id -EQ $changingPolicy.Name).displayName)]
        $($remoteCAPolicies | ? -Property id -EQ $changingPolicy.Name | ConvertTo-Json -Depth 9)
        ##[endgroup]
        ##[group] Local JSON policy: [$(($localCAPolicies | ? -Property id -EQ $changingPolicy.Name).displayName)]
        $($localCAPolicies | ? -Property id -EQ $changingPolicy.Name | ConvertTo-Json -Depth 9)
        ##[endgroup]
"@
        foreach ($path in $changingPolicy.Value.GetEnumerator()) {
            Write-Output "[INFO] Property Changing: [$($path.Name)]"
            Write-Output "[INFO] Currently deployed value: [$($policyRemovals.$($changingPolicy.Name).$($path.Name))]"
            Write-Output "[INFO] New value which will be deployed: [$($path.Value)]`n"
        }
        Write-Output "-----------------------"
    }
}

if ($newPolicies.Count -gt 0) {
    foreach ($newPolicy in $newPolicies) {
        Write-Output "`n[INFO] New policy being deployed with name [$($newPolicy.displayName)]`n`n"
        $newPolicy | ConvertTo-Json -Depth 9
        Write-Output "-----------------------"
    }
}

if ($unControlledPolicies.Count -gt 0) {
    Write-Host "`n##[warning] We also have some policies deployed which are not source controlled - these will be marked for deletion"
    Write-Host "##[warning] These could be new manual policies, or these could be redudant old policies!"

    foreach ($uncontrolledPolicy in $unControlledPolicies) {
        Write-Output "`n[INFO] Remote policy with ID [$($uncontrolledPolicy.id)] and name [$($uncontrolledPolicy.displayName)] not in source control`n`n"
        $uncontrolledPolicy | ConvertTo-Json -Depth 9
        Write-Output "-----------------------"
    }
}

# Begin exporting new/removed policies

# Create directories for artifacts if it does not exist
$policyAddsDir = Test-Path './update/'
if (!$policyAddsDir) {
    New-Item -Path './update' -ItemType Directory | Out-Null
}
$newPoliciesDir = Test-Path './new/'
if (!$newPoliciesDir) {
    New-Item -Path './new' -ItemType Directory | Out-Null
}
$uncontrolledPoliciesDir = Test-Path './remove/'
if (!$uncontrolledPoliciesDir) {
    New-Item -Path './remove' -ItemType Directory | Out-Null
}

# Export policies to update
if ($policyAdds.Count -gt 0) {
    Write-Output "[INFO] Exporting policies to update"
    foreach ($policyAdd in $policyAdds.Keys) {
        "[$($policyAdd)] - [$(($localCAPolicies | ? -Property id -EQ $policyAdd).displayName)]"
        $localCAPolicies | ? -Property id -EQ $policyAdd | ConvertTo-Json -Depth 9 | Out-File -FilePath ./update/"$policyAdd.json"
    }
}

# Export policies to create
if ($newPolicies.Count -gt 0) {
    Write-Output "[INFO] Exporting policies to create"
    foreach ($newPolicy in $newPolicies) {
        "[$($newPolicy.displayName)]"
        $localCAPolicies | ? -Property displayName -EQ $newPolicy.displayName | ConvertTo-Json -Depth 9 | Out-File -FilePath ./new/"$($newpolicy.id).json"
    }
}

# Export policies to remove
if ($unControlledPolicies.Count -gt 0) {
    Write-Output "[INFO] Exporting policies to remove"
    foreach ($uncontrolledPolicy in $unControlledPolicies) {
        "[$($uncontrolledPolicy.id)] - [$(($remoteCAPolicies | ? -Property id -EQ $uncontrolledPolicy.id).displayName)]"
        $remoteCAPolicies | ? -Property id -EQ $uncontrolledPolicy.id | ConvertTo-Json -Depth 9 | Out-File -FilePath ./remove/"$($uncontrolledPolicy.id).json"
    }
}
