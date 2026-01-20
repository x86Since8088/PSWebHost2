param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Helper function to create a JSON response
function New-JsonResponse($status, $message, $data = $null) {
    $response = @{ status = $status; message = $message }
    if ($data) { $response.data = $data }
    return $response | ConvertTo-Json -Compress -Depth 10
}

# Get user ID from session
if (-not $sessiondata -or -not $sessiondata.UserID) {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'User not authenticated'
    context_response -Response $Response -StatusCode 401 -String $jsonResponse -ContentType "application/json"
    return
}

$userID = $sessiondata.UserID

try {
    # Get buckets using utility script
    $getBucketsScript = Join-Path $Global:PSWebServer.Project_Root.Path "system\utility\Bucket_Get.ps1"

    if (-not (Test-Path $getBucketsScript)) {
        $jsonResponse = New-JsonResponse -status 'fail' -message 'Bucket_Get.ps1 not found'
        context_response -Response $Response -StatusCode 500 -String $jsonResponse -ContentType "application/json"
        return
    }

    # Get all buckets user has access to
    $buckets = & $getBucketsScript -UserID $userID

    # Format response with logical path prefixes
    $bucketsData = @()
    foreach ($bucket in $buckets) {
        $bucketsData += @{
            bucketId = $bucket.BucketID
            name = $bucket.Name
            description = $bucket.Description
            ownerUserId = $bucket.OwnerUserID
            accessLevel = $bucket.AccessLevel
            created = $bucket.Created
            updated = $bucket.Updated
            logicalPath = "Bucket:$($bucket.BucketID)"  # Logical path prefix for frontend
        }
    }

    # Update stats
    if ($Global:PSWebServer['WebhostFileExplorer']) {
        if (-not $Global:PSWebServer['WebhostFileExplorer'].Stats.BucketRequests) {
            $Global:PSWebServer['WebhostFileExplorer'].Stats.BucketRequests = 0
        }
        $Global:PSWebServer['WebhostFileExplorer'].Stats.BucketRequests++
    }

    $jsonResponse = New-JsonResponse -status 'success' -message "Retrieved $($bucketsData.Count) buckets" -data @{ buckets = $bucketsData }
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Buckets' -Message "Error getting buckets: $($_.Exception.Message)" -Data @{ UserID = $userID }

    # Generate detailed error report based on user role
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata

    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
