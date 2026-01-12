param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $SessionData
)

# Validate user is authenticated
if (-not $SessionData -or -not $SessionData.UserID) {
    return context_reponse -Response $Response -StatusCode 401 -String (@{
        error = "Unauthorized"
        message = "User must be authenticated to save menu preferences"
    } | ConvertTo-Json) -ContentType "application/json"
}

try {
    # Parse request body
    $body = Get-RequestBody -Request $Request
    if (-not $body) {
        return context_reponse -Response $Response -StatusCode 400 -String (@{
            error = "Bad Request"
            message = "Request body is required"
        } | ConvertTo-Json) -ContentType "application/json"
    }

    $preferences = $body | ConvertFrom-Json

    # Validate preferences structure (should be an object/hashtable)
    if ($null -eq $preferences) {
        return context_reponse -Response $Response -StatusCode 400 -String (@{
            error = "Bad Request"
            message = "Invalid preferences format"
        } | ConvertTo-Json) -ContentType "application/json"
    }

    # Convert to JSON for storage
    $preferencesJson = $preferences | ConvertTo-Json -Compress -Depth 10

    # Save using existing card_settings pattern
    # endpoint_guid = "main-menu" for menu preferences
    $result = Set-CardSettings -EndpointGuid "main-menu" -UserId $SessionData.UserID -Data $preferencesJson

    if ($result) {
        Write-Verbose "[main-menu/preferences] Saved menu preferences for user: $($SessionData.UserID)"

        return context_reponse -Response $Response -StatusCode 200 -String (@{
            success = $true
            message = "Menu preferences saved successfully"
        } | ConvertTo-Json) -ContentType "application/json"
    } else {
        Write-Warning "[main-menu/preferences] Failed to save preferences for user: $($SessionData.UserID)"

        return context_reponse -Response $Response -StatusCode 500 -String (@{
            error = "Internal Server Error"
            message = "Failed to save menu preferences"
        } | ConvertTo-Json) -ContentType "application/json"
    }

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Menu' -Message "Error saving menu preferences: $($_.Exception.Message)"

    return context_reponse -Response $Response -StatusCode 500 -String (@{
        error = "Internal Server Error"
        message = $_.Exception.Message
    } | ConvertTo-Json) -ContentType "application/json"
}
