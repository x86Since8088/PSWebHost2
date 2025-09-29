param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

# Expect query parameter 'name' (variable name without leading $)
$name = $Request.QueryString['name']
if (-not $name) {
    context_reponse -Response $Response -StatusCode 400 -String "Missing 'name' parameter"
    return
}
$name = $name -replace '^\$',''
Write-Verbose "Deleting variable: $name"
try {
    $existing = Get-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        Remove-Variable -Name $name -Scope Global -ErrorAction Stop
        context_reponse -Response $Response -StatusCode 200 -String "Deleted"
    } else {
        context_reponse -Response $Response -StatusCode 404 -String "Not found"
    }
} catch {
    context_reponse -Response $Response -StatusCode 500 -String "Failed to delete variable: $_"
}