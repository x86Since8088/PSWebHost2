param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

$dbFile = "pswebhost.db"

# Read the query from the request body
$query = Get-RequestBody -Request $Request

if (-not ([string]::IsNullOrWhiteSpace($query))) {
    $data = Get-PSWebSQLiteData -File $dbFile -Query $query
    $jsonData = $data | ConvertTo-Json
    context_reponse -Response $Response -String $jsonData -ContentType "application/json"
} else {
    context_reponse -Response $Response -StatusCode 400 -String "Query cannot be empty."
}
