param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

$dbFile = "pswebhost.db"
$tablesQuery = "SELECT name FROM sqlite_master WHERE type='table';"
$tables = Get-PSWebSQLiteData -File $dbFile -Query $tablesQuery

$allTablesData = @{}

foreach ($table in $tables) {
    $tableName = $table.name
    $query = "SELECT * FROM `"$tableName`" ORDER BY ID DESC LIMIT 10;"
    $tableData = Get-PSWebSQLiteData -File $dbFile -Query $query
    $allTablesData[$tableName] = $tableData
}

$jsonData = $allTablesData | ConvertTo-Json
context_reponse -Response $Response -String $jsonData -ContentType "application/json"
