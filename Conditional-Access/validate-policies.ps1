<#
    .SYNOPSIS
    Validates the JSON definitions for the local conditional access policies
    #>

# Set required conditional access policies
$requiredProperties = @("displayName", "conditions", "state")

# Get all local policies
$path = './policies/'

# Output directory content
dir $path

try {
    $pathExists = Test-Path -Path $path
    if ($pathExists) {
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
        else {
            Write-Host "##[error] No files exist in [$path]"
            throw "No policy files found!"
        }
    }

    $localCAPolicies = $localFileImport | ConvertFrom-Json
}
catch {
    Write-Host "##[error] Failed to fetch local policy files to validate"
    throw $_.Exception
} 

# Run validation checks
    
# Output current action
Write-Host "##[command]Importing Conditional Access Policies"
Write-Host "[INFO] Policies: $($localCAPolicies.count)"
    
foreach ($Policy in $localCAPolicies) {
    if ($Policy.displayName) {
        Write-Host "Import: Policy Name: $($Policy.displayName)"
    }
    elseif ($Policy.id) {
        Write-Host "Import: Policy Id: $($Policy.id)"
    }
    else {
        Write-Host "##[warning] Import: Policy Invalid"
    }
}

# Output current action
Write-Host "##[command]Validating Conditional Access Policies"

# For each policy, run validation checks
$InvalidPolicies = foreach ($Policy in $localCAPolicies) {

    # Check for missing properties
    $PolicyProperties = ($Policy | Get-Member -MemberType NoteProperty).name

    # Check whether each required property, exists in the list of properties for the object
    $PropertyCheck = foreach ($Property in $requiredProperties) {
        if ($Property -notin $PolicyProperties) {
            $Property
        }
    }

    # Check whether each required property has a value, if not, return property
    $PropertyValueCheck = foreach ($Property in $requiredProperties) {
        if ($null -eq $Policy.$Property) {
            $Property
        }
    }

    # Check for missing grant or session controls
    $ControlsCheck = if (!$Policy.GrantControls) {
        if (!$Policy.sessionControls) {
            Write-Host "##[warning] No grant or session controls specified, at least one must be specified"
        }
    }

    # Check for missing conditions (under applications)
    $ApplicationsProperties = ($Policy.conditions.applications | Get-Member -MemberType NoteProperty).name

    # For each condition, return true if a value exists for each condition checked
    $ConditionsCheck = foreach ($Condition in $ApplicationsProperties) {
        if ($Policy.conditions.applications.$Condition) {
            $true
        }
    }

    # If true is not in the condition check variable, it means there were no conditions that had a value
    if ($true -notin $ConditionsCheck) {
        $ConditionsCheck = Write-Host "##[warning] No application conditions specified, at least one must be specified"
    }
    else {
        $ConditionsCheck = $null
    }

    # Build and return object
    if ($PropertyCheck -or $PropertyValueCheck -or $ControlsCheck -or $ConditionsCheck) {
        $PolicyValidate = [ordered]@{}
        if ($Policy.displayName) {
            $PolicyValidate.Add("DisplayName", $Policy.displayName)
        }
        elseif ($Policy.id) {
            $PolicyValidate.Add("Id", $Policy.id)
        }
    }
    if ($PropertyCheck) {
        $PolicyValidate.Add("MissingProperties", $PropertyCheck)
    }
    if ($PropertyValueCheck) {
        $PolicyValidate.Add("MissingPropertyValues", $PropertyValueCheck)
    }
    if ($ControlsCheck) {
        $PolicyValidate.Add("MissingControls", $ControlsCheck)
    }
    if ($ConditionsCheck) {
        $PolicyValidate.Add("MissingConditions", $ConditionsCheck)
    }
    if ($PolicyValidate) {
        [PSCustomObject]$PolicyValidate
    }
}

# Return validation result for each policy
if ($InvalidPolicies) {
    Write-Host "##[command] Invalid Policies: $($InvalidPolicies.count) out of $($localCAPolicies.count) imported"
    foreach ($Policy in $InvalidPolicies) {
        if ($Policy.displayName) {
            Write-Host "##[error] INVALID: Policy Name: $($Policy.displayName)" -ForegroundColor Yellow
        }
        elseif ($Policy.id) {
            Write-Host "##[error] INVALID: Policy Id: $($Policy.id)" -ForegroundColor Yellow
        }
        else {
            Write-Host "##[error] INVALID: No displayName or Id for policy" -ForegroundColor Yellow
        }
        if ($Policy.MissingProperties) {
            Write-Host "##[warning] Required properties not present ($($Policy.MissingProperties.count)): $($Policy.MissingProperties)"
        }
        if ($Policy.MissingPropertyValues) {
            Write-Host "##[warning] Required property values not present ($($Policy.MissingPropertyValues.count)): $($Policy.MissingPropertyValues)"
        }
        if ($Policy.MissingControls) {
            Write-Host "##[warning] $($Policy.MissingControls)"
        }
        if ($Policy.MissingConditions) {
            Write-Host "##[warning] $($Policy.MissingConditions)"
        }
    }

    # Abort import
    $ErrorMessage = "Validation of policies was not successful, review configuration files and any warnings generated"
    Write-Host "##[error] $ErrorMessage"
    throw $ErrorMessage
}
else {
    # Return validated policies
    Write-Host "##[section]All policies have passed validation for required properties, values, controls and conditions" -ForegroundColor Green
}
