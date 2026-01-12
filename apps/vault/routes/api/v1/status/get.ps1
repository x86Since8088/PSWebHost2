param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Vault Status Endpoint
# Returns vault health and statistics

try {
    $vaultDbPath = $Global:PSWebServer.Vault.DatabasePath

    $stats = @{
        status = 'healthy'
        initialized = $true
        databaseExists = (Test-Path $vaultDbPath)
        appVersion = '1.0.0'
        timestamp = (Get-Date).ToString('o')
    }

    if ($stats.databaseExists) {
        # Get credential counts
        $countQuery = "SELECT Scope, COUNT(*) as Count FROM Vault_Credentials GROUP BY Scope;"
        $counts = Get-PSWebSQLiteData -File $vaultDbPath -Query $countQuery

        $stats.credentialsByScope = @{}
        foreach ($row in $counts) {
            $stats.credentialsByScope[$row.Scope] = $row.Count
        }

        $totalQuery = "SELECT COUNT(*) as Total FROM Vault_Credentials;"
        $total = Get-PSWebSQLiteData -File $vaultDbPath -Query $totalQuery
        $stats.totalCredentials = $total.Total

        # Get recent audit log count
        $auditQuery = "SELECT COUNT(*) as Count FROM Vault_AuditLog WHERE Timestamp > datetime('now', '-24 hours');"
        $auditCount = Get-PSWebSQLiteData -File $vaultDbPath -Query $auditQuery
        $stats.recentAuditEntries = $auditCount.Count
    } else {
        $stats.status = 'error'
        $stats.error = 'Database not found'
    }

    $jsonResponse = $stats | ConvertTo-Json -Depth 5
    context_reponse -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Vault' -Message "Error getting vault status: $($_.Exception.Message)"
    $errorResponse = @{
        error = $_.Exception.Message
        status = 'error'
    } | ConvertTo-Json
    context_reponse -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
}
