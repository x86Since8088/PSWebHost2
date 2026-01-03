param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

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
    context_reponse -Response $Response -StatusCode 200 -String $responseData -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'ClientLog' -Message "Error in client-log POST: $($_.Exception.Message)"

    # Generate detailed error report based on user role
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata

    context_reponse -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
