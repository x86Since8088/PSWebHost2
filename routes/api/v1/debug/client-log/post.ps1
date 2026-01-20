param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Initialize rate limiter in global state if not exists
if (-not $Global:PSWebServer['ClientLogRateLimiter']) {
    $Global:PSWebServer['ClientLogRateLimiter'] = @{
        MessageHistory = @{}  # Hash -> Array of timestamps
        BlockedMessages = @{} # Hash -> Block expiry time
    }
}

try {
    # Read request body
    $reader = New-Object System.IO.StreamReader($Request.InputStream)
    $body = $reader.ReadToEnd()
    $reader.Close()

    $logData = $body | ConvertFrom-Json

    # Extract log details
    $level = if ($logData.level) { $logData.level } else { 'Info' }
    $category = if ($logData.category) { $logData.category } else { 'ClientLog' }
    $message = if ($logData.message) { $logData.message } else { 'No message' }

    # Create message signature for rate limiting (hash of key fields)
    $messageSignature = "$level|$category|$message"
    $messageHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($messageSignature))).Replace('-','').Substring(0, 16)

    $rateLimiter = $Global:PSWebServer['ClientLogRateLimiter']
    $now = [DateTime]::UtcNow

    # Check if message is currently blocked
    if ($rateLimiter.BlockedMessages.ContainsKey($messageHash)) {
        $blockExpiry = $rateLimiter.BlockedMessages[$messageHash]
        if ($now -lt $blockExpiry) {
            # Message is blocked, return 429
            $responseData = @{
                status = 'fail'
                message = 'Log message rate limited - repeated too frequently'
                blocked_until = $blockExpiry.ToString('o')
            } | ConvertTo-Json -Compress
            context_response -Response $Response -StatusCode 429 -String $responseData -ContentType "application/json"
            return
        } else {
            # Block expired, remove it
            $rateLimiter.BlockedMessages.Remove($messageHash)
        }
    }

    # Track message occurrence
    if (-not $rateLimiter.MessageHistory.ContainsKey($messageHash)) {
        $rateLimiter.MessageHistory[$messageHash] = @()
    }

    # Add current timestamp
    $rateLimiter.MessageHistory[$messageHash] += $now

    # Clean up old timestamps (older than 2 seconds)
    $cutoffTime = $now.AddSeconds(-2)
    $rateLimiter.MessageHistory[$messageHash] = @($rateLimiter.MessageHistory[$messageHash] | Where-Object { $_ -gt $cutoffTime })

    # Check if message has been repeated 5 times in last 2 seconds
    if ($rateLimiter.MessageHistory[$messageHash].Count -ge 5) {
        # Block this message for 10 seconds
        $blockExpiry = $now.AddSeconds(10)
        $rateLimiter.BlockedMessages[$messageHash] = $blockExpiry

        Write-PSWebHostLog -Severity 'Warning' -Category 'ClientLog' -Message "Client log message rate limited: $messageSignature (repeated 5+ times in 2s, blocked for 10s)"

        # Return 429 for this request too
        $responseData = @{
            status = 'fail'
            message = 'Log message rate limited - repeated too frequently (5+ times in 2s)'
            blocked_until = $blockExpiry.ToString('o')
        } | ConvertTo-Json -Compress
        context_response -Response $Response -StatusCode 429 -String $responseData -ContentType "application/json"
        return
    }

    # Safely serialize client data
    $clientDataStr = ''
    if ($logData.data) {
        try {
            $clientDataStr = $logData.data | ConvertTo-Json -Compress -Depth 3
        } catch {
            $clientDataStr = $logData.data.ToString()
        }
    }

    # Add user info if available
    $userID = if ($sessiondata -and $sessiondata.UserID) { $sessiondata.UserID } else { 'anonymous' }

    # Build enriched data as simple string to avoid serialization issues
    $enrichedMessage = "$message | User: $userID | URL: $($logData.url) | Data: $clientDataStr"

    # Log to server - use simple string instead of complex object
    Write-PSWebHostLog -Severity $level -Category $category -Message $enrichedMessage

    # Return success
    $responseData = @{ status = 'success' } | ConvertTo-Json -Compress
    context_response -Response $Response -StatusCode 200 -String $responseData -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'ClientLog' -Message "Error in client-log POST: $($_.Exception.Message)"

    # Generate detailed error report based on user role
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata

    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
