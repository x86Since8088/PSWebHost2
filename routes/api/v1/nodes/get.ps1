param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Nodes API Endpoint
# Returns list of registered PSWebHost nodes

try {
    $nodesConfig = $Global:PSWebServer.NodesConfig

    $nodes = @()
    if ($nodesConfig -and $nodesConfig.nodes) {
        foreach ($nodeGuid in ($nodesConfig.nodes | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)) {
            $node = $nodesConfig.nodes.$nodeGuid
            $nodes += @{
                guid = $nodeGuid
                url = $node.url
                user = $node.user
                registered = $node.registered
                lastSync = $node.lastSync
                status = $node.status
            }
        }
    }

    $result = @{
        success = $true
        thisNode = @{
            guid = $Global:PSWebServer.NodeGuid
            url = "http://localhost:$($Global:PSWebServer.Config.WebServer.Port)"
        }
        nodes = $nodes
        total = $nodes.Count
    }

    $jsonResponse = $result | ConvertTo-Json -Depth 5
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Nodes' -Message "Error getting nodes: $($_.Exception.Message)"
    $errorResponse = @{
        success = $false
        error = $_.Exception.Message
    } | ConvertTo-Json
    context_response -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
}
