# POST /apps/WebHostMetrics/api/v1/token
# Creates a metrics-only API token for browser-based workers
# Token expires when the user's session expires

param($Request, $Response, $Session)

$ErrorActionPreference = 'Stop'
$MyTag = '[WebHostMetrics/api/v1/token]'

# Ensure Response object exists
if (-not $Response) {
    Write-Error "$MyTag Response object is null - this endpoint requires HTTP context"
    return
}

# Get session data
$sessiondata = $null
if ($Session) {
    $sessiondata = Get-PSWebSession -SessionID $Session.ID
}

# Require authentication (session-based, not bearer token)
if (-not $sessiondata -or 'authenticated' -notin $sessiondata.Roles) {
    $errorResponse = @{
        status = 'error'
        message = 'Authentication required. This endpoint requires session-based authentication, not bearer tokens.'
    }
    context_response -Response $Response -StatusCode 401 -String ($errorResponse | ConvertTo-Json -Compress)
    return
}

try {
    $userID = $sessiondata.UserID
    $user = Get-PSWebHostUser -UserID $userID

    if (-not $user) {
        throw "User not found"
    }

    # Calculate token expiration based on session
    $sessionExpiresAt = $null
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $safeSessionID = Sanitize-SqlQueryString -String $Session.ID

    $sessionInfo = Get-PSWebSQLiteData -File $dbFile -Query "SELECT ExpiresAt FROM Sessions WHERE SessionID = '$safeSessionID' LIMIT 1;"

    if ($sessionInfo -and $sessionInfo.ExpiresAt) {
        # Parse the expiration time
        $sessionExpiresAt = [DateTime]::Parse($sessionInfo.ExpiresAt)
    } else {
        # Default: 24 hours from now if no session expiration found
        $sessionExpiresAt = (Get-Date).AddHours(24)
    }

    Write-Verbose "$MyTag Creating metrics token for user $($user.Email), expires: $sessionExpiresAt"

    # Check if user already has a metrics token that's still valid
    $safeUserID = Sanitize-SqlQueryString -String $userID
    $existingTokenQuery = @"
SELECT k.KeyID, k.ApiKey, k.ExpiresAt
FROM API_Keys k
JOIN Users u ON k.UserID = u.UserID
WHERE u.Owner = '$safeUserID'
  AND u.OwnerType = 'User'
  AND k.Name LIKE 'MetricsWorker_%'
  AND (k.ExpiresAt IS NULL OR k.ExpiresAt > datetime('now'))
ORDER BY k.CreatedAt DESC
LIMIT 1
"@

    $existingToken = Get-PSWebSQLiteData -File $dbFile -Query $existingTokenQuery

    if ($existingToken -and $existingToken.ApiKey) {
        # Return existing valid token
        $response = @{
            status = 'success'
            token = $existingToken.ApiKey
            expiresAt = $existingToken.ExpiresAt
            message = 'Existing token returned'
        }
        context_response -Response $Response -StatusCode 200 -String ($response | ConvertTo-Json -Compress)
        return
    }

    # Create new metrics token using the bearer token script
    $tokenScript = Join-Path $Global:PSWebServer.Project_Root.Path "system\utility\Account_Auth_BearerToken_New.ps1"

    $tokenName = "MetricsWorker_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

    # Create the token with only the 'metrics' role
    $tokenResult = & $tokenScript -UserID $userID -Name $tokenName -Roles @('metrics') -ExpiresAt $sessionExpiresAt -Verbose:$false 6>$null 3>$null 4>$null 5>$null

    if (-not $tokenResult -or -not $tokenResult.ApiKey) {
        throw "Failed to create metrics token"
    }

    Write-Verbose "$MyTag Created metrics token: $($tokenResult.KeyID)"

    $response = @{
        status = 'success'
        token = $tokenResult.ApiKey
        expiresAt = $sessionExpiresAt.ToString('o')
        keyId = $tokenResult.KeyID
        message = 'New token created'
    }

    context_response -Response $Response -StatusCode 200 -String ($response | ConvertTo-Json -Compress)
}
catch {
    Write-Error "$MyTag Error: $($_.Exception.Message)"
    if ($Response) {
        $errorResponse = @{
            status = 'error'
            message = $_.Exception.Message
        }
        context_response -Response $Response -StatusCode 500 -String ($errorResponse | ConvertTo-Json -Compress)
    }
}
