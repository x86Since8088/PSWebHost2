param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# List Vault Credentials Endpoint
# Returns all credentials (without secrets) or a specific credential
# Supports filtering by credentialType

try {
    Import-Module PSWebVault -Force -ErrorAction SilentlyContinue

    # Parse query parameters
    $queryParams = @{}
    if ($Request.Url.Query) {
        $Request.Url.Query.TrimStart('?').Split('&') | ForEach-Object {
            $parts = $_.Split('=', 2)
            if ($parts.Count -eq 2) {
                $queryParams[$parts[0]] = [System.Web.HttpUtility]::UrlDecode($parts[1])
            }
        }
    }

    $name = $queryParams['name']
    $scope = $queryParams['scope']
    $credentialType = $queryParams['credentialType']

    if ($name) {
        # Get specific credential
        $credential = Get-VaultCredential -Name $name -Scope ($scope ?? 'global')

        if ($credential) {
            $credResult = @{
                id = $credential.ID
                name = $credential.Name
                credentialType = $credential.CredentialType
                username = $credential.Username
                scope = $credential.Scope
                description = $credential.Description
                createdBy = $credential.CreatedBy
                createdAt = $credential.CreatedAt
                updatedAt = $credential.UpdatedAt
            }

            # Add certificate format if applicable
            if ($credential.CredentialType -eq 'Certificate' -and $credential.CertificateFormat) {
                $credResult.certificateFormat = $credential.CertificateFormat
            }

            $result = @{
                success = $true
                credential = $credResult
            }
        } else {
            $result = @{
                success = $false
                error = "Credential not found: $name"
            }
        }
    } else {
        # List all credentials with optional filtering
        $getParams = @{}
        if ($scope) {
            $getParams.Scope = $scope
        }
        if ($credentialType) {
            $getParams.CredentialType = $credentialType
        }

        $credentials = Get-VaultCredentials @getParams

        $result = @{
            success = $true
            credentials = @()
            total = 0
        }

        if ($credentials) {
            $credList = @($credentials)
            $result.credentials = $credList | ForEach-Object {
                $credResult = @{
                    id = $_.ID
                    name = $_.Name
                    credentialType = $_.CredentialType
                    username = $_.Username
                    scope = $_.Scope
                    description = $_.Description
                    createdBy = $_.CreatedBy
                    createdAt = $_.CreatedAt
                    updatedAt = $_.UpdatedAt
                }

                # Add certificate format if applicable
                if ($_.CredentialType -eq 'Certificate' -and $_.CertificateFormat) {
                    $credResult.certificateFormat = $_.CertificateFormat
                }

                $credResult
            }
            $result.total = $credList.Count
        }
    }

    $jsonResponse = $result | ConvertTo-Json -Depth 5
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Vault' -Message "Error listing credentials: $($_.Exception.Message)"
    $errorResponse = @{
        success = $false
        error = $_.Exception.Message
    } | ConvertTo-Json
    context_response -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
}
