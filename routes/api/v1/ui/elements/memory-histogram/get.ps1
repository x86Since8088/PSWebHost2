param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

# Memory Histogram UI Element
# Returns element configuration for memory usage histogram

$elementConfig = @{
    status = 'success'
    element = @{
        id = 'memory-histogram'
        type = 'component'
        component = 'memory-histogram'
        title = 'Memory Usage History'
        icon = $null
        refreshable = $true
        helpFile = 'public/help/memory-histogram.md'
    }
}

$jsonResponse = $elementConfig | ConvertTo-Json -Depth 10
context_reponse -Response $Response -String $jsonResponse -ContentType "application/json"
