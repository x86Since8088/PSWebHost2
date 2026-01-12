#Requires -Version 7

<#
.SYNOPSIS
    Browser Console Log Collection Endpoint
.DESCRIPTION
    Receives browser console logs from ConsoleAPILogger and stores them for analysis
#>

param($Request, $Response, $Session)

try {
    # Read request body
    $reader = [System.IO.StreamReader]::new($Request.InputStream)
    $bodyJson = $reader.ReadToEnd()
    $reader.Close()

    if ([string]::IsNullOrWhiteSpace($bodyJson)) {
        $Response.StatusCode = 400
        $Response.Write('{"error": "Empty request body"}')
        return
    }

    # Parse JSON payload
    $payload = $bodyJson | ConvertFrom-Json

    # Validate payload structure
    if (-not $payload.logs -or $payload.logs.Count -eq 0) {
        $Response.StatusCode = 400
        $Response.Write('{"error": "No logs provided"}')
        return
    }

    # Get app namespace
    $appNamespace = $Global:PSWebServer['UI_Uplot']
    if (-not $appNamespace) {
        Write-Warning "[UI_Uplot] App namespace not initialized"
    }

    # Create logs directory if it doesn't exist
    $logsDir = Join-Path $appNamespace.DataPath 'logs'
    if (-not (Test-Path $logsDir)) {
        New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
    }

    # Organize logs by date and level
    $timestamp = Get-Date
    $dateStr = $timestamp.ToString('yyyy-MM-dd')
    $logFile = Join-Path $logsDir "browser-logs-$dateStr.jsonl"

    # Append logs to JSONL file (one JSON object per line)
    foreach ($logEntry in $payload.logs) {
        # Enrich log entry with server-side metadata
        $enrichedLog = @{
            timestamp = $logEntry.timestamp
            level = $logEntry.level
            message = $logEntry.message
            app = $logEntry.app
            url = $logEntry.url
            userAgent = $logEntry.userAgent
            stackTrace = $logEntry.stackTrace
            sessionId = $payload.session
            serverReceivedAt = $timestamp.ToString('o')
            userId = $Session.User.UserId
            username = $Session.User.Username
        }

        # Write as JSONL (newline-delimited JSON)
        $jsonLine = ($enrichedLog | ConvertTo-Json -Compress)
        Add-Content -Path $logFile -Value $jsonLine -Encoding UTF8
    }

    # Also log errors to server console for immediate visibility
    $errorLogs = $payload.logs | Where-Object { $_.level -eq 'error' }
    if ($errorLogs) {
        foreach ($errorLog in $errorLogs) {
            Write-Warning "[UI_Uplot Browser Error] $($errorLog.message)"
            if ($errorLog.stackTrace) {
                Write-Warning "Stack trace: $($errorLog.stackTrace)"
            }
        }
    }

    # Update statistics
    if ($appNamespace.Stats) {
        $appNamespace.Stats['BrowserLogsReceived'] += $payload.logs.Count
        $appNamespace.Stats['LastLogReceived'] = $timestamp
    }

    # Return success response
    $response_data = @{
        success = $true
        logsReceived = $payload.logs.Count
        timestamp = $timestamp.ToString('o')
    } | ConvertTo-Json

    $Response.ContentType = 'application/json'
    $Response.StatusCode = 200
    $Response.Write($response_data)

} catch {
    Write-Error "[UI_Uplot] Error processing browser logs: $_"

    $Response.StatusCode = 500
    $Response.ContentType = 'application/json'
    $errorResponse = @{
        error = $_.Exception.Message
        timestamp = Get-Date -Format 'o'
    } | ConvertTo-Json

    $Response.Write($errorResponse)
}
