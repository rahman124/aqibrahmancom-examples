function Get-GraphToken {

    <#
    .SYNOPSIS
    Azure AD OAuth Application Token for Graph API
    Get OAuth token for a AAD Application (returned as $token
    #>

    # Application (client) ID, tenant ID and secret
    Param(
        [parameter(Mandatory = $true)]
        $clientId,
        [parameter(Mandatory = $true)]
        $tenantId,
        [parameter(Mandatory = $true)]
        $clientSecret
    )
    
    # Construct URI
    $uri = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
     
    # Construct Body
    $body = @{
        client_id     = $clientId
        scope         = "https://graph.microsoft.com/.default"
        client_secret = $clientSecret
        grant_type    = "client_credentials"
    }
     
    # Get OAuth 2.0 Token
    $tokenRequest = Invoke-WebRequest -Method Post -Uri $uri -ContentType "application/x-www-form-urlencoded" -Body $body -UseBasicParsing
     
    # Access Token
    $token = ($tokenRequest.Content | ConvertFrom-Json).access_token
    
    #Returns token
    return $token
}

function Get-ConditionalAccessPolicies {

    <#
    .SYNOPSIS
    Returns a report of Conditional Access Policies in a tenant
    #>

    # Application (client) ID, tenant ID and secret
    Param(
        [parameter(Mandatory = $true)]
        $clientId,
        [parameter(Mandatory = $true)]
        $tenantId,
        [parameter(Mandatory = $true)]
        $clientSecret
    )

    $apiUri = "https://graph.microsoft.com/beta/identity/conditionalAccess/policies"
    $token = Get-GraphToken -clientId $clientId -tenantId  $tenantId -clientSecret $clientSecret

    $policiesRaw = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)" } -Uri $apiUri -Method Get
    $policies = $policiesRaw.value

    foreach ($policy in $policies) {
        $policy.displayName
        $policy | ConvertTo-Json -Depth 9 | out-file ("$($policy.id).json").replace('[', '').replace(']', '').replace('/', '').replace(':', '').replace(' ', '_')
    }
}
