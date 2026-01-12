param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Delete Node API Endpoint
# Removes a PSWebHost node from the configuration

try {
    # Read request body
    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
    $body = $reader.ReadToEnd()
    $reader.Close()

    if ([string]::IsNullOrWhiteSpace($body)) {
        throw "Request body is empty"
    }

    $data = $body | ConvertFrom-Json

    if (-not $data.guid) {
        throw "Node GUID is required"
    }

    # Load current nodes config
    $nodesConfigPath = $Global:PSWebServer.NodesConfigPath
    $nodesConfig = Get-Content $nodesConfigPath -Raw | ConvertFrom-Json

    # Check if node exists
    if (-not ($nodesConfig.nodes | Get-Member -Name $data.guid -MemberType NoteProperty)) {
        throw "Node not found: $($data.guid)"
    }

    # Remove from vault if credential was stored
    try {
        Import-Module PSWebVault -Force -ErrorAction SilentlyContinue
        Remove-VaultCredential -Name "node_$($data.guid)" -Scope 'node' -RemovedBy $sessiondata.UserID -ErrorAction SilentlyContinue
    } catch {
        # Ignore if credential doesn't exist
    }

    # Remove the node property by rebuilding the nodes object
    $newNodes = [PSCustomObject]@{}
    foreach ($nodeGuid in ($nodesConfig.nodes | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)) {
        if ($nodeGuid -ne $data.guid) {
            $newNodes | Add-Member -MemberType NoteProperty -Name $nodeGuid -Value $nodesConfig.nodes.$nodeGuid
        }
    }
    $nodesConfig.nodes = $newNodes

    # Save config
    $nodesConfig | ConvertTo-Json -Depth 5 | Set-Content $nodesConfigPath -Encoding UTF8

    # Update in-memory config
    $Global:PSWebServer.NodesConfig = $nodesConfig

    $result = @{
        success = $true
        message = "Node removed successfully"
        guid = $data.guid
    }

    Write-PSWebHostLog -Severity 'Info' -Category 'Nodes' -Message "Removed node: $($data.guid)"

    $jsonResponse = $result | ConvertTo-Json -Depth 3
    context_reponse -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Nodes' -Message "Error removing node: $($_.Exception.Message)"
    $errorResponse = @{
        success = $false
        error = $_.Exception.Message
    } | ConvertTo-Json

    $statusCode = if ($_.Exception.Message -like "*not found*") { 404 } else { 400 }
    context_reponse -Response $Response -StatusCode $statusCode -String $errorResponse -ContentType "application/json"
}
