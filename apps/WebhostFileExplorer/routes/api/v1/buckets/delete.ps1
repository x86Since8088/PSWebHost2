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

# Get bucketId from query string
$bucketId = $Request.QueryString['bucketId']

if (-not $bucketId) {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'Missing required parameter: bucketId'
    context_response -Response $Response -StatusCode 400 -String $jsonResponse -ContentType "application/json"
    return
}

try {
    # Get bucket deletion script
    $deleteBucketScript = Join-Path $Global:PSWebServer.Project_Root.Path "system\utility\Bucket_Delete.ps1"

    if (-not (Test-Path $deleteBucketScript)) {
        $jsonResponse = New-JsonResponse -status 'fail' -message 'Bucket_Delete.ps1 not found'
        context_response -Response $Response -StatusCode 500 -String $jsonResponse -ContentType "application/json"
        return
    }

    # Delete bucket (will check ownership internally)
    $result = & $deleteBucketScript -BucketID $bucketId -UserID $userID

    if (-not $result.Success) {
        $statusCode = if ($result.Message -like "*owner*") { 403 } else { 400 }
        $jsonResponse = New-JsonResponse -status 'fail' -message $result.Message
        context_response -Response $Response -StatusCode $statusCode -String $jsonResponse -ContentType "application/json"
        return
    }

    # Update stats
    if ($Global:PSWebServer['WebhostFileExplorer']) {
        if (-not $Global:PSWebServer['WebhostFileExplorer'].Stats.BucketsDeleted) {
            $Global:PSWebServer['WebhostFileExplorer'].Stats.BucketsDeleted = 0
        }
        $Global:PSWebServer['WebhostFileExplorer'].Stats.BucketsDeleted++
    }

    # Format response
    $deletedData = @{
        bucketId = $result.DeletedBucket.BucketID
        name = $result.DeletedBucket.Name
    }

    $jsonResponse = New-JsonResponse -status 'success' -message $result.Message -data @{ deleted = $deletedData }
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Buckets' -Message "Error deleting bucket: $($_.Exception.Message)" -Data @{ UserID = $userID; BucketID = $bucketId }

    # Generate detailed error report based on user role
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata

    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
