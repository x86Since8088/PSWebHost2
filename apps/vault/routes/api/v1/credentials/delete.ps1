param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Delete Vault Credential Endpoint
# Removes a credential from the vault

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

    $scope = if ($data.scope) { $data.scope } else { 'global' }

    # Remove the credential
    $result = Remove-VaultCredential -Name $data.name -Scope $scope -RemovedBy $sessiondata.UserID

    # Log the action
    Add-VaultAuditLog -Action 'API:Delete' -CredentialName $data.name -Scope $scope -UserID $sessiondata.UserID -IPAddress $Request.RemoteEndPoint.Address.ToString()

    $response = @{
        success = $true
        message = "Credential '$($data.name)' removed successfully"
        name = $data.name
        scope = $scope
    }

    $jsonResponse = $response | ConvertTo-Json -Depth 3
    context_reponse -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Vault' -Message "Error removing credential: $($_.Exception.Message)"
    $errorResponse = @{
        success = $false
        error = $_.Exception.Message
    } | ConvertTo-Json

    $statusCode = if ($_.Exception.Message -like "*not found*") { 404 } else { 400 }
    context_reponse -Response $Response -StatusCode $statusCode -String $errorResponse -ContentType "application/json"
}
