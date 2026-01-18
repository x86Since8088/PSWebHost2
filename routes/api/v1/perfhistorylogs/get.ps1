param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

# Performance History Logs API Endpoint (Adapter)
# Bridges generic metrics-fetcher API to the metrics/history backend
# Maps: dataset, startTime/endTime, granularity, aggregation, metrics[], resolution
# To: metric, starting/ending, granularity

try {
    # Parse query parameters from metrics-fetcher format
    $dataset = $Request.QueryString["dataset"] ?? "system_metrics"
    $startTime = $Request.QueryString["startTime"] ?? $Request.QueryString["starting"]
    $endTime = $Request.QueryString["endTime"] ?? $Request.QueryString["ending"]
    $granularity = $Request.QueryString["granularity"]
    $aggregation = $Request.QueryString["aggregation"] ?? "avg"
    $metricsParam = $Request.QueryString["metrics"]  # Can be comma-separated
    $resolution = $Request.QueryString["resolution"]

    # Fallback to timerange if startTime not provided
    $timeRange = $Request.QueryString["timerange"]

    # Map dataset to specific metric type
    # metrics-fetcher uses generic dataset names, metrics/history uses specific types
    $metricType = switch -Regex ($dataset) {
        'cpu|processor|core' { 'cpu' }
        'memory|mem|ram' { 'memory' }
        'disk|storage|io' { 'disk' }
        'network|net|ethernet' { 'network' }
        default {
            # Try to extract from metrics parameter
            if ($metricsParam) {
                $firstMetric = ($metricsParam -split ',')[0].ToLower()
                switch -Regex ($firstMetric) {
                    'cpu|processor' { 'cpu' }
                    'memory|mem' { 'memory' }
                    'disk|io' { 'disk' }
                    'network|net' { 'network' }
                    default { 'cpu' }  # Default to CPU
                }
            } else {
                'cpu'  # Default to CPU if can't determine
            }
        }
    }

    # Build metrics/history API query
    $params = @{}
    $params.metric = $metricType

    if ($startTime) {
        $params.starting = $startTime
    }
    if ($endTime) {
        $params.ending = $endTime
    }
    if ($timeRange) {
        $params.timerange = $timeRange
    }
    if ($granularity) {
        # Ensure granularity is in 5s or 60s format
        $params.granularity = switch -Regex ($granularity) {
            '^\d+s$' {
                $seconds = [int]($granularity -replace 's', '')
                if ($seconds -le 5) { '5s' } else { '60s' }
            }
            '^\d+m$' { '60s' }  # Minutes -> 60s
            default { '5s' }  # Default to 5s
        }
    }

    # Convert params to query string
    $queryString = ($params.GetEnumerator() | ForEach-Object { "$($_.Key)=$([System.Uri]::EscapeDataString($_.Value))" }) -join '&'

    # Internal request to metrics/history endpoint
    Write-PSWebHostLog -Severity 'Info' -Category 'Metrics' -Message "[perfhistorylogs] Proxying to /api/v1/metrics/history with params: $queryString"

    # Build internal URL
    $internalUrl = "http://localhost:$($Context.Request.LocalEndPoint.Port)/api/v1/metrics/history?$queryString"

    try {
        # Make internal HTTP request
        $webRequest = [System.Net.WebRequest]::Create($internalUrl)
        $webRequest.Method = "GET"
        $webRequest.Timeout = 30000  # 30 seconds

        # Copy session cookie if present
        if ($Request.Cookies -and $Request.Cookies["sessionid"]) {
            $cookie = New-Object System.Net.Cookie
            $cookie.Name = "sessionid"
            $cookie.Value = $Request.Cookies["sessionid"].Value
            $cookie.Domain = "localhost"
            $webRequest.CookieContainer = New-Object System.Net.CookieContainer
            $webRequest.CookieContainer.Add($cookie)
        }

        $webResponse = $webRequest.GetResponse()
        $reader = New-Object System.IO.StreamReader($webResponse.GetResponseStream())
        $responseContent = $reader.ReadToEnd()
        $reader.Close()
        $webResponse.Close()

        # Parse response
        $historyData = $responseContent | ConvertFrom-Json

        # Transform to metrics-fetcher expected format
        # metrics/history returns: { status, metric, startTime, endTime, granularity, sampleCount, data: { datasets: [] } }
        # metrics-fetcher expects: array of data points or similar structure

        if ($historyData.status -eq 'success') {
            # Return the data in a format compatible with metrics-fetcher
            $response = @{
                status = 'success'
                dataset = $dataset
                metric = $metricType
                startTime = $historyData.startTime
                endTime = $historyData.endTime
                granularity = $historyData.granularity
                sampleCount = $historyData.sampleCount
                aggregation = $aggregation
                data = $historyData.data  # Pass through Chart.js format
            }

            $responseJson = $response | ConvertTo-Json -Depth 10 -Compress
            context_response -Response $Response -String $responseJson -ContentType "application/json"
        } else {
            # Error from metrics/history
            Write-PSWebHostLog -Severity 'Warning' -Category 'Metrics' -Message "[perfhistorylogs] Error from metrics/history: $($historyData.message)"

            $errorResponse = @{
                status = 'error'
                message = "Metrics history error: $($historyData.message)"
                dataset = $dataset
                metric = $metricType
            } | ConvertTo-Json

            context_response -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
        }

    } catch {
        Write-PSWebHostLog -Severity 'Error' -Category 'Metrics' -Message "[perfhistorylogs] Error proxying to metrics/history: $($_.Exception.Message)"

        $errorResponse = @{
            status = 'error'
            message = "Error fetching metrics history: $($_.Exception.Message)"
            dataset = $dataset
            metric = $metricType
        } | ConvertTo-Json

        context_response -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
    }

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Metrics' -Message "[perfhistorylogs] Error in perfhistorylogs API: $($_.Exception.Message)"

    $errorResponse = @{
        status = 'error'
        message = "Error processing performance history logs: $($_.Exception.Message)"
    } | ConvertTo-Json

    context_response -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
}
