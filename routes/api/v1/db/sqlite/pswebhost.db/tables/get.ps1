param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

$dbFile = "pswebhost.db"
$query = "SELECT name FROM sqlite_master WHERE type='table';"

$tables = Get-PSWebSQLiteData -File $dbFile -Query $query

$jsonData = $tables | ConvertTo-Json
context_reponse -Response $Response -String $jsonData -ContentType "application/json"
