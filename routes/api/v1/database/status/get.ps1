param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Database Status API Endpoint
# Returns database health, statistics, and table information

try {
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/pswebhost.db"
    $perfDbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/pswebhost_perf.db"

    $result = @{
        status = 'healthy'
        type = 'SQLite'
        version = ''
        fileSize = ''
        filePath = 'PsWebHost_Data/pswebhost.db'
        perfDbPath = 'PsWebHost_Data/pswebhost_perf.db'
        lastBackup = $null
        tables = @()
        performance = @{
            avgQueryTime = 'N/A'
            queriesPerSecond = 0
            cacheHitRate = 'N/A'
            activeConnections = 1
        }
    }

    # Check if database file exists
    if (-not (Test-Path $dbFile)) {
        $result.status = 'error'
        $result.message = 'Database file not found'
        $jsonResponse = $result | ConvertTo-Json -Depth 5
        context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
        return
    }

    # Get file size
    $fileInfo = Get-Item $dbFile
    $fileSizeBytes = $fileInfo.Length
    if ($fileSizeBytes -ge 1MB) {
        $result.fileSize = "{0:N2} MB" -f ($fileSizeBytes / 1MB)
    } elseif ($fileSizeBytes -ge 1KB) {
        $result.fileSize = "{0:N2} KB" -f ($fileSizeBytes / 1KB)
    } else {
        $result.fileSize = "$fileSizeBytes bytes"
    }

    # Get SQLite version
    $versionResult = Get-PSWebSQLiteData -File $dbFile -Query "SELECT sqlite_version() as version;"
    if ($versionResult) {
        $result.version = $versionResult.version
    }

    # Get list of tables with row counts and approximate sizes
    $tablesResult = Get-PSWebSQLiteData -File $dbFile -Query "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;"

    $tables = @()
    foreach ($table in $tablesResult) {
        $tableName = $table.name
        # Get row count
        $countResult = Get-PSWebSQLiteData -File $dbFile -Query "SELECT COUNT(*) as count FROM `"$tableName`";"
        $rowCount = if ($countResult) { $countResult.count } else { 0 }

        # Estimate table size using page count (approximate)
        $pageInfo = Get-PSWebSQLiteData -File $dbFile -Query "SELECT SUM(pageno) as pages FROM dbstat WHERE name='$tableName';" -ErrorAction SilentlyContinue
        $pageSize = 4096  # Default SQLite page size
        $tableSize = if ($pageInfo -and $pageInfo.pages) { $pageInfo.pages * $pageSize } else { 0 }

        $sizeString = if ($tableSize -ge 1KB) { "{0:N0} KB" -f ($tableSize / 1KB) } else { "$tableSize bytes" }

        $tables += @{
            name = $tableName
            rows = $rowCount
            size = $sizeString
        }
    }
    $result.tables = $tables

    # Check performance database if exists
    if (Test-Path $perfDbFile) {
        $perfFileInfo = Get-Item $perfDbFile
        $result.perfDbSize = "{0:N2} MB" -f ($perfFileInfo.Length / 1MB)

        # Get recent query stats from performance db if available
        try {
            $recentStats = Get-PSWebSQLiteData -File $perfDbFile -Query "SELECT AVG(response_time_ms) as avg_time, COUNT(*) as total FROM request_metrics WHERE timestamp > datetime('now', '-1 hour');"
            if ($recentStats) {
                $result.performance.avgQueryTime = "{0:N2} ms" -f $recentStats.avg_time
                $result.performance.queriesPerSecond = [math]::Round($recentStats.total / 3600, 2)
            }
        } catch {
            # Performance db may not have these tables
        }
    }

    # Check for backup files
    $backupDir = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data"
    $backups = Get-ChildItem -Path $backupDir -Filter "pswebhost_backup_*.db" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($backups -and $backups.Count -gt 0) {
        $result.lastBackup = $backups[0].LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
        $result.backupCount = $backups.Count
    }

    $jsonResponse = $result | ConvertTo-Json -Depth 5
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'DatabaseStatus' -Message "Error getting database status: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
