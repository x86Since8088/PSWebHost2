param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

$users = Get-PSWebSQLiteData -File "pswebhost.db" -Query "SELECT * FROM Users;"

$responseString = $users | ConvertTo-Json -Depth 5
context_reponse -Response $Response -String $responseString -ContentType "application/json"
