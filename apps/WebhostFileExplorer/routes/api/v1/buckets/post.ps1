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

# Read request body
$reader = New-Object System.IO.StreamReader($Request.InputStream)
$body = $reader.ReadToEnd()
$reader.Close()

try {
    $data = $body | ConvertFrom-Json
}
catch {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'Invalid JSON in request body'
    context_response -Response $Response -StatusCode 400 -String $jsonResponse -ContentType "application/json"
    return
}

# Validate required parameters
if (-not $data.name) {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'Missing required parameter: name'
    context_response -Response $Response -StatusCode 400 -String $jsonResponse -ContentType "application/json"
    return
}

try {
    # Get bucket creation script
    $createBucketScript = Join-Path $Global:PSWebServer.Project_Root.Path "system\utility\Bucket_Create.ps1"

    if (-not (Test-Path $createBucketScript)) {
        $jsonResponse = New-JsonResponse -status 'fail' -message 'Bucket_Create.ps1 not found'
        context_response -Response $Response -StatusCode 500 -String $jsonResponse -ContentType "application/json"
        return
    }

    # Prepare parameters
    $params = @{
        BucketName = $data.name
        OwnerUserID = $userID
    }

    if ($data.description) {
        $params.Description = $data.description
    }

    if ($data.initialMembers) {
        $initialMembers = @{}
        if ($data.initialMembers.owners) { $initialMembers.Owners = $data.initialMembers.owners }
        if ($data.initialMembers.writers) { $initialMembers.Writers = $data.initialMembers.writers }
        if ($data.initialMembers.readers) { $initialMembers.Readers = $data.initialMembers.readers }
        $params.InitialMembers = $initialMembers
    }

    # Create bucket
    $result = & $createBucketScript @params

    if (-not $result.Success) {
        $jsonResponse = New-JsonResponse -status 'fail' -message $result.Message
        context_response -Response $Response -StatusCode 400 -String $jsonResponse -ContentType "application/json"
        return
    }

    # Update stats
    if ($Global:PSWebServer['WebhostFileExplorer']) {
        if (-not $Global:PSWebServer['WebhostFileExplorer'].Stats.BucketsCreated) {
            $Global:PSWebServer['WebhostFileExplorer'].Stats.BucketsCreated = 0
        }
        $Global:PSWebServer['WebhostFileExplorer'].Stats.BucketsCreated++
    }

    # Format response
    $bucketData = @{
        bucketId = $result.Bucket.BucketID
        name = $result.Bucket.Name
        description = $result.Bucket.Description
        ownerUserId = $result.Bucket.OwnerUserID
        ownerGroupId = $result.Bucket.OwnerGroupID
        readGroupId = $result.Bucket.ReadGroupID
        writeGroupId = $result.Bucket.WriteGroupID
        created = $result.Bucket.Created
        updated = $result.Bucket.Updated
        path = $result.Bucket.Path
    }

    $jsonResponse = New-JsonResponse -status 'success' -message $result.Message -data @{ bucket = $bucketData }
    context_response -Response $Response -StatusCode 201 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Buckets' -Message "Error creating bucket: $($_.Exception.Message)" -Data @{ UserID = $userID; BucketName = $data.name }

    # Generate detailed error report based on user role
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata

    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
