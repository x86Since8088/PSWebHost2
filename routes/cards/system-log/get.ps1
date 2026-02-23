# System Log API Endpoint
# Returns the current log file content

param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

try {
    # Get the logs directory from global config
    if (-not $Global:PSWebServer) {
        $json = @{Message = "PSWebServer global variable not found"} | ConvertTo-Json
        context_response -Response $Response -StatusCode 501 -String $json -ContentType "application/json"
        return
    }
    if (-not $Global:PSWebServer.LogDirectory) {
        $json = @{Message = "PSWebServer.LogDirectory is null or empty"} | ConvertTo-Json
        context_response -Response $Response -StatusCode 501 -String $json -ContentType "application/json"
        return
    }
    if (-not $Global:PSWebServer.LogFilePath) {
        $json = @{Message = "PSWebServer.LogFilePath is null or empty"} | ConvertTo-Json
        context_response -Response $Response -StatusCode 501 -String $json -ContentType "application/json"
        return
    }

    $logsDir = $Global:PSWebServer.LogDirectory
    $currentLogFile = $Global:PSWebServer.LogFilePath

    # Parameters for filtering
    $lines = 100  # Default to last 100 lines
    if ($Request.QueryString.lines) {
        $lines = [int]$Request.QueryString.lines
    }

    $filter = $null
    if ($Request.QueryString.filter) {
        $filter = $Request.QueryString.filter
    }

    # Get all log files (timestamped)
    $logFiles = Get-ChildItem -Path $logsDir -Filter "log_*.tsv" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    # Build response object
    $responseData = @{
        status = 'success'
        component = 'system-log'
        scriptPath = '/public/elements/system-log/component.js'
        title = 'System Log'
        description = 'Real-time system log viewer'
        currentLog = $currentLogFile
        logFiles = @($logFiles | Select-Object Name, LastWriteTime, @{N='Size';E={$_.Length}})
        entries = @()
    }

    # Read the current log file
    if (Test-Path $currentLogFile) {
        $logContent = Get-Content $currentLogFile -ErrorAction SilentlyContinue

        # Apply filter if specified
        if ($filter) {
            $logContent = $logContent | Where-Object { $_ -like "*$filter*" }
        }

        # Get the last N lines
        $entries = $logContent | Select-Object -Last $lines

        # Parse TSV entries into objects
        $responseData.entries = @($entries | ForEach-Object {
            $parts = $_ -split "`t"
            if ($parts.Count -ge 3) {
                @{
                    timestamp = $parts[0]
                    level = $parts[1]
                    category = $parts[2]
                    message = if ($parts.Count -gt 3) { $parts[3] } else { '' }
                    data = if ($parts.Count -gt 4) { $parts[4] } else { '' }
                }
            } else {
                @{
                    raw = $_
                }
            }
        })
    }

    # Return as JSON
    $jsonResponse = $responseData | ConvertTo-Json -Depth 5 -Compress
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'SystemLog' -Message "Error in system-log GET: $($_.Exception.Message)"

    # Generate detailed error report based on user role
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata

    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
