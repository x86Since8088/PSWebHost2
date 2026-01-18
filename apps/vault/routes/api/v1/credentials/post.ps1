param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Store Vault Credential Endpoint
# Creates or updates a credential in the vault
# Supports credential types: Password, Certificate, API_Key

try {
    Import-Module PSWebVault -Force -ErrorAction SilentlyContinue

    # Read request body
    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
    $body = $reader.ReadToEnd()
    $reader.Close()

    if ([string]::IsNullOrWhiteSpace($body)) {
        throw "Request body is empty"
    }

    $data = $body | ConvertFrom-Json

    # Validate required fields
    if (-not $data.name) {
        throw "Name is required"
    }

    # Determine credential type (default to Password for backwards compatibility)
    $credentialType = if ($data.credentialType) { $data.credentialType } else { 'Password' }

    # Validate credential type
    $validTypes = @('Password', 'Certificate', 'API_Key')
    if ($credentialType -notin $validTypes) {
        throw "Invalid credentialType. Must be one of: $($validTypes -join ', ')"
    }

    # Validate required secret based on type
    switch ($credentialType) {
        'Password' {
            if (-not $data.password) {
                throw "Password is required for credential type 'Password'"
            }
        }
        'Certificate' {
            if (-not $data.certificate) {
                throw "Certificate data is required for credential type 'Certificate'"
            }
            if ($data.certificateFormat -and $data.certificateFormat -notin @('PFX', 'PEM', 'CER')) {
                throw "Invalid certificateFormat. Must be one of: PFX, PEM, CER"
            }
        }
        'API_Key' {
            if (-not $data.apiKey) {
                throw "API key is required for credential type 'API_Key'"
            }
        }
    }

    # Build parameters for Set-VaultCredential
    $params = @{
        Name = $data.name
        CredentialType = $credentialType
        Scope = if ($data.scope) { $data.scope } else { 'global' }
        CreatedBy = $sessiondata.UserID
    }

    # Add type-specific secret
    switch ($credentialType) {
        'Password' {
            $params.Password = $data.password
        }
        'Certificate' {
            $params.Certificate = $data.certificate
            if ($data.certificateFormat) {
                $params.CertificateFormat = $data.certificateFormat
            }
        }
        'API_Key' {
            $params.ApiKey = $data.apiKey
        }
    }

    # Add optional fields
    if ($data.username) {
        $params.Username = $data.username
    }
    if ($data.description) {
        $params.Description = $data.description
    }
    if ($data.metadata) {
        $params.Metadata = ($data.metadata | ConvertTo-Json -Compress)
    }

    $result = Set-VaultCredential @params

    # Log the action
    Add-VaultAuditLog -Action 'API:Create' -CredentialName $data.name -Scope $params.Scope -UserID $sessiondata.UserID -IPAddress $Request.RemoteEndPoint.Address.ToString() -Details "Type: $credentialType"

    $response = @{
        success = $true
        message = "Credential '$($data.name)' stored successfully"
        name = $data.name
        credentialType = $credentialType
        scope = $params.Scope
    }

    $jsonResponse = $response | ConvertTo-Json -Depth 3
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Vault' -Message "Error storing credential: $($_.Exception.Message)"
    $errorResponse = @{
        success = $false
        error = $_.Exception.Message
    } | ConvertTo-Json
    context_response -Response $Response -StatusCode 400 -String $errorResponse -ContentType "application/json"
}
