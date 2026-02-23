#Requires -Version 7

param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

$MyTag = '[DebugExtensions:Commands:History]'

try {
    # Get query parameters
    $limit = if ($Request.QueryString['limit']) { [int]$Request.QueryString['limit'] } else { 50 }
    $sessionFilter = $Request.QueryString['session']

    # Get history
    $history = $Global:PSWebServer.DebugCommands.History.ToArray()

    # Filter by session if specified
    if ($sessionFilter) {
        $history = $history | Where-Object { $_.SessionID -eq $sessionFilter }
    }

    # Sort by CompletedAt descending, take limit
    $history = $history |
        Sort-Object CompletedAt -Descending |
        Select-Object -First $limit

    $responseData = @{
        count = $history.Count
        commands = $history
    } | ConvertTo-Json -Depth 5 -Compress

    context_response -Response $Response -StatusCode 200 -String $responseData -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'DebugExtensions' -Message "$MyTag Error: $($_.Exception.Message)"

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
