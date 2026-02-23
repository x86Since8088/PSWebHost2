#Requires -Version 7

<#
.SYNOPSIS
    Starts an authenticated client session for PSWebHost API interactions

.DESCRIPTION
    Creates and caches authentication credentials for making API calls to PSWebHost.
    Automatically provisions temporary bearer token if no credentials provided.
    Token is stored in script scope for reuse within the session.

.PARAMETER BearerToken
    SecureString bearer token for authentication (if not provided, auto-provisions)

.PARAMETER Credential
    PSCredential for basic authentication (alternative to BearerToken)

.PARAMETER ServerUrl
    Base URL of PSWebHost server (default: http://localhost:8080)

.PARAMETER Roles
    Array of roles to assign when auto-provisioning bearer token
    Default: @('debug', 'admin', 'site_admin', 'server_admin', 'authenticated')

.PARAMETER Persistent
    Keep the auto-provisioned token (don't clean up at session end)
    Default: False (token is cleaned up)

.EXAMPLE
    $session = .\Session_Client_Start.ps1
    # Auto-provisions temporary token with default roles

.EXAMPLE
    $token = ConvertTo-SecureString "your-api-key" -AsPlainText -Force
    $session = .\Session_Client_Start.ps1 -BearerToken $token
    # Uses provided bearer token

.EXAMPLE
    $session = .\Session_Client_Start.ps1 -Roles @('debug') -Persistent
    # Creates persistent token with only debug role

.OUTPUTS
    Returns session object with authentication details
#>

[CmdletBinding()]
param(
    [Parameter()]
    [SecureString]$BearerToken,

    [Parameter()]
    [PSCredential]$Credential,

    [Parameter()]
    [string]$ServerUrl = "http://localhost:8080",

    [Parameter()]
    [string[]]$Roles = @('debug', 'admin', 'site_admin', 'server_admin', 'authenticated'),

    [Parameter()]
    [switch]$Persistent
)

$MyTag = '[Session_Client_Start]'
$sessionData = @{
    ServerUrl = $ServerUrl
    BearerToken = $null
    Credential = $null
    AutoProvisioned = $false
    TokenInfo = $null
    Created = Get-Date
}

try {
    # Auto-provision bearer token if no auth provided
    if (-not $BearerToken -and -not $Credential) {
        Write-Verbose "$MyTag No authentication provided, auto-provisioning temporary bearer token..."

        $tokenScript = Join-Path $PSScriptRoot "Account_Auth_BearerToken_New.ps1"

        if (-not (Test-Path $tokenScript)) {
            throw "Cannot find bearer token script at: $tokenScript"
        }

        # Create test account
        $tokenResult = & $tokenScript -TestAccount -Roles $Roles -ErrorAction Stop

        if (-not $tokenResult -or -not $tokenResult.ApiKey) {
            throw "Failed to auto-provision bearer token"
        }

        Write-Host "✓ Auto-provisioned bearer token: $($tokenResult.KeyID)" -ForegroundColor Green
        Write-Host "  Roles: $($Roles -join ', ')" -ForegroundColor Gray

        $BearerToken = ConvertTo-SecureString $tokenResult.ApiKey -AsPlainText -Force
        $sessionData.AutoProvisioned = $true
        $sessionData.TokenInfo = $tokenResult
    }

    # Store authentication
    if ($BearerToken) {
        $sessionData.BearerToken = $BearerToken
    } elseif ($Credential) {
        $sessionData.Credential = $Credential
    }

    # Register cleanup handler if auto-provisioned and not persistent
    if ($sessionData.AutoProvisioned -and -not $Persistent) {
        Write-Verbose "$MyTag Registering cleanup handler for temporary token"

        Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
            try {
                $tokenInfo = $using:sessionData.TokenInfo
                if ($tokenInfo) {
                    $deleteScript = Join-Path $using:PSScriptRoot "Account_Auth_BearerToken_Delete.ps1"

                    if (Test-Path $deleteScript) {
                        & $deleteScript -KeyID $tokenInfo.KeyID -ErrorAction SilentlyContinue 2>&1 | Out-Null
                    }
                }
            } catch {
                # Silent cleanup failure
            }
        } | Out-Null
    }

    Write-Host "✓ Client session started: $ServerUrl" -ForegroundColor Green

    if ($sessionData.AutoProvisioned) {
        if ($Persistent) {
            Write-Host "⚠ Token is PERSISTENT - will not be auto-cleaned" -ForegroundColor Yellow
            Write-Host "  KeyID: $($sessionData.TokenInfo.KeyID)" -ForegroundColor Gray
            Write-Host "  To delete: .\Account_Auth_BearerToken_Delete.ps1 -KeyID $($sessionData.TokenInfo.KeyID)" -ForegroundColor Gray
        } else {
            Write-Host "ℹ Token will be auto-cleaned when PowerShell session ends" -ForegroundColor Cyan
        }
    }

    return [PSCustomObject]$sessionData

} catch {
    Write-Error "$MyTag Failed to start client session: $_"
    throw
}
