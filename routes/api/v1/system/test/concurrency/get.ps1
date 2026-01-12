param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $SessionData
)

# Concurrency test endpoint - simulates long-running request
# Query parameters:
#   delay (int): Seconds to sleep (default: 5, max: 30)
#   id (string): Optional identifier for tracking this request

$queryParams = $Request.QueryString
$delay = [int]($queryParams['delay'] ?? 5)
$requestId = $queryParams['id'] ?? (New-Guid).ToString().Substring(0, 8)

# Limit delay to prevent abuse
if ($delay -lt 1) { $delay = 1 }
if ($delay -gt 30) { $delay = 30 }

$startTime = Get-Date

Write-Host "[Concurrency Test] Request $requestId started at $($startTime.ToString('HH:mm:ss.fff')) - will delay for $delay seconds" -ForegroundColor Cyan

# Simulate long-running work
Start-Sleep -Seconds $delay

$endTime = Get-Date
$actualDuration = ($endTime - $startTime).TotalSeconds

Write-Host "[Concurrency Test] Request $requestId completed at $($endTime.ToString('HH:mm:ss.fff')) - actual duration: $([math]::Round($actualDuration, 2))s" -ForegroundColor Green

$result = @{
    requestId = $requestId
    requestedDelay = $delay
    actualDuration = [math]::Round($actualDuration, 3)
    startTime = $startTime.ToString('o')
    endTime = $endTime.ToString('o')
    threadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
    runspaceId = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId.ToString()
    success = $true
}

context_reponse -Response $Response -String ($result | ConvertTo-Json) -ContentType 'application/json' -StatusCode 200
