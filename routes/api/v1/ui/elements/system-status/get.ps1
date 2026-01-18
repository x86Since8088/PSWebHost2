
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

$logData = @(
    @{ timestamp = (Get-Date).AddMinutes(-5).ToString('o'); level = 'INFO'; message = 'User admin logged in.' },
    @{ timestamp = (Get-Date).AddMinutes(-4).ToString('o'); level = 'INFO'; message = 'System check started.' },
    @{ timestamp = (Get-Date).AddMinutes(-2).ToString('o'); level = 'WARN'; message = 'CPU usage at 85%.' },
    @{ timestamp = (Get-Date).AddMinutes(-1).ToString('o'); level = 'ERROR'; message = 'Failed to connect to database.' }
)

$jsonData = $logData | ConvertTo-Json
context_response -Response $Response -String $jsonData -ContentType "application/json"
