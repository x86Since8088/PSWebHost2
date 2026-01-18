param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Register Node API Endpoint
# Adds a new PSWebHost node to the configuration

try {
    # Read request body
    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
    $body = $reader.ReadToEnd()
    $reader.Close()

    if ([string]::IsNullOrWhiteSpace($body)) {
        throw "Request body is empty"
    }

    $data = $body | ConvertFrom-Json

    # Validate required fields
    if (-not $data.url) {
        throw "Node URL is required"
    }
    if (-not $data.guid) {
        throw "Node GUID is required"
    }

    # Load current nodes config
    $nodesConfigPath = $Global:PSWebServer.NodesConfigPath
    $nodesConfig = Get-Content $nodesConfigPath -Raw | ConvertFrom-Json

    # Ensure nodes property exists
    if (-not $nodesConfig.nodes) {
        $nodesConfig | Add-Member -MemberType NoteProperty -Name 'nodes' -Value ([PSCustomObject]@{})
    }

    # Add or update node
    $nodeData = @{
        url = $data.url
        user = if ($data.user) { $data.user } else { "node_$($data.guid.Substring(0, 8))" }
        registered = (Get-Date).ToString('o')
        lastSync = $null
        status = 'pending'
    }

    # Store credential in vault if password provided
    if ($data.password) {
        try {
            Import-Module PSWebVault -Force -ErrorAction SilentlyContinue
            Set-VaultCredential -Name "node_$($data.guid)" -Username $nodeData.user -Password $data.password -Scope 'node' -Description "Credentials for node $($data.guid)" -CreatedBy $sessiondata.UserID
            $nodeData['credentialStored'] = $true
        } catch {
            Write-PSWebHostLog -Severity 'Warning' -Category 'Nodes' -Message "Failed to store node credential in vault: $($_.Exception.Message)"
            $nodeData['credentialStored'] = $false
        }
    }

    # Add to nodes config
    $nodesConfig.nodes | Add-Member -MemberType NoteProperty -Name $data.guid -Value ([PSCustomObject]$nodeData) -Force

    # Save config
    $nodesConfig | ConvertTo-Json -Depth 5 | Set-Content $nodesConfigPath -Encoding UTF8

    # Update in-memory config
    $Global:PSWebServer.NodesConfig = $nodesConfig

    $result = @{
        success = $true
        message = "Node registered successfully"
        guid = $data.guid
        url = $data.url
    }

    Write-PSWebHostLog -Severity 'Info' -Category 'Nodes' -Message "Registered new node: $($data.guid) at $($data.url)"

    $jsonResponse = $result | ConvertTo-Json -Depth 3
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Nodes' -Message "Error registering node: $($_.Exception.Message)"
    $errorResponse = @{
        success = $false
        error = $_.Exception.Message
    } | ConvertTo-Json
    context_response -Response $Response -StatusCode 400 -String $errorResponse -ContentType "application/json"
}
