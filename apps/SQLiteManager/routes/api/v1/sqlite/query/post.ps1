param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# SQLite Query Execution Endpoint
# Executes SQL queries against the PSWebHost SQLite database

try {
    # Read request body
    $reader = [System.IO.StreamReader]::new($Request.InputStream)
    $body = $reader.ReadToEnd()
    $reader.Close()

    if ([string]::IsNullOrWhiteSpace($body)) {
        $errorResult = @{
            success = $false
            error = 'Request body is required'
        } | ConvertTo-Json
        context_response -Response $Response -StatusCode 400 -String $errorResult -ContentType "application/json"
        return
    }

    $requestData = $body | ConvertFrom-Json

    if ([string]::IsNullOrWhiteSpace($requestData.query)) {
        $errorResult = @{
            success = $false
            error = 'SQL query is required'
        } | ConvertTo-Json
        context_response -Response $Response -StatusCode 400 -String $errorResult -ContentType "application/json"
        return
    }

    # Get database file path
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/pswebhost.db"

    if (-not (Test-Path $dbFile)) {
        $errorResult = @{
            success = $false
            error = 'Database file not found'
        } | ConvertTo-Json
        context_response -Response $Response -StatusCode 404 -String $errorResult -ContentType "application/json"
        return
    }

    $result = @{
        success = $false
        query = $requestData.query
        rows = @()
        rowCount = 0
        columns = @()
        executionTime = 0
        error = $null
        queryType = $null
    }

    # Determine query type
    $queryUpper = $requestData.query.Trim().ToUpper()
    if ($queryUpper -match '^SELECT') {
        $result.queryType = 'SELECT'
    }
    elseif ($queryUpper -match '^INSERT') {
        $result.queryType = 'INSERT'
    }
    elseif ($queryUpper -match '^UPDATE') {
        $result.queryType = 'UPDATE'
    }
    elseif ($queryUpper -match '^DELETE') {
        $result.queryType = 'DELETE'
    }
    elseif ($queryUpper -match '^CREATE') {
        $result.queryType = 'CREATE'
    }
    elseif ($queryUpper -match '^DROP') {
        $result.queryType = 'DROP'
    }
    elseif ($queryUpper -match '^ALTER') {
        $result.queryType = 'ALTER'
    }
    else {
        $result.queryType = 'UNKNOWN'
    }

    # Execute query with timing
    $startTime = Get-Date

    try {
        # Execute the query
        $queryResult = Get-PSWebSQLiteData -File $dbFile -Query $requestData.query -ErrorAction Stop

        $executionTime = ((Get-Date) - $startTime).TotalMilliseconds

        # Process results for SELECT queries
        if ($result.queryType -eq 'SELECT' -and $queryResult) {
            # Convert results to array of hashtables
            $rows = @()
            $columns = @()

            if ($queryResult -is [array] -and $queryResult.Count -gt 0) {
                # Get column names from first row
                $columns = $queryResult[0].PSObject.Properties.Name

                # Convert each row
                foreach ($row in $queryResult) {
                    $rowHash = @{}
                    foreach ($prop in $row.PSObject.Properties) {
                        $rowHash[$prop.Name] = $prop.Value
                    }
                    $rows += $rowHash
                }
            }
            elseif ($queryResult -isnot [array]) {
                # Single row result
                $columns = $queryResult.PSObject.Properties.Name
                $rowHash = @{}
                foreach ($prop in $queryResult.PSObject.Properties) {
                    $rowHash[$prop.Name] = $prop.Value
                }
                $rows += $rowHash
            }

            $result.rows = $rows
            $result.rowCount = $rows.Count
            $result.columns = $columns
        }
        else {
            # For non-SELECT queries, just indicate success
            $result.rowCount = 0
            $result.columns = @()
        }

        $result.success = $true
        $result.executionTime = [math]::Round($executionTime, 2)

        Write-PSWebHostLog -Severity 'Info' -Category 'SQLiteManager' -Message "Query executed by $($sessiondata.User.Username): $($requestData.query.Substring(0, [Math]::Min(100, $requestData.query.Length)))"
    }
    catch {
        $result.error = $_.Exception.Message
        $result.executionTime = [math]::Round(((Get-Date) - $startTime).TotalMilliseconds, 2)
        Write-PSWebHostLog -Severity 'Error' -Category 'SQLiteManager' -Message "Query execution failed: $($_.Exception.Message)"
    }

    $statusCode = if ($result.success) { 200 } else { 400 }
    $jsonResponse = $result | ConvertTo-Json -Depth 10
    context_response -Response $Response -StatusCode $statusCode -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'SQLiteManager' -Message "Error in query endpoint: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
