param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

<#
.SYNOPSIS
    Save transfer state for current user

.DESCRIPTION
    Saves the transfers array to user's app data directory as transfers.json
    Only saves transfers that are in progress or failed (not completed)

.EXAMPLE
    POST /api/v1/transfers
    Body: { "transfers": [...] }
    Response: { "status": "success" }
#>

# Import File Explorer helper module functions
try {
    Import-TrackedModule "FileExplorerHelper"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Failed to import FileExplorerHelper module: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode 500 -String $Report.body -ContentType $Report.contentType
    return
}

# Validate session
$userID = Test-WebHostFileExplorerSession -SessionData $sessiondata -Response $Response
if (-not $userID) { return }

# Read request body
$reader = New-Object System.IO.StreamReader($Request.InputStream)
$body = $reader.ReadToEnd()
$reader.Close()

try {
    $data = $body | ConvertFrom-Json
}
catch {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Invalid JSON in request body'
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
    return
}

# Validate transfers parameter
if (-not $data.transfers) {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Missing required parameter: transfers'
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
    return
}

try {
    # Get user's app data directory
    $projectRoot = $Global:PSWebServer.Project_Root.Path
    $userAppDataPath = Join-Path $projectRoot "PsWebHost_Data\UserData\$userID\apps\WebhostFileExplorer"
    $transfersFilePath = Join-Path $userAppDataPath "transfers.json"

    # Ensure directory exists
    if (-not (Test-Path $userAppDataPath)) {
        New-Item -ItemType Directory -Path $userAppDataPath -Force | Out-Null
    }

    # Filter out completed transfers (only save in-progress and failed)
    $transfersToSave = @()
    foreach ($transfer in $data.transfers) {
        if ($transfer.status -in @('uploading', 'downloading', 'failed')) {
            $transfersToSave += $transfer
        }
    }

    # Create transfers data structure
    $transfersData = @{
        transfers = $transfersToSave
        savedAt = (Get-Date).ToString('o')
        userID = $userID
    }

    # Save to file
    $transfersJson = $transfersData | ConvertTo-Json -Depth 10 -Compress
    Set-Content -Path $transfersFilePath -Value $transfersJson -Force -ErrorAction Stop

    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Saved transfers state" -Data @{
        UserID = $userID
        TransferCount = $transfersToSave.Count
        TotalReceived = $data.transfers.Count
    }

    # Return success
    $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Transfers saved' -Data @{
        savedCount = $transfersToSave.Count
        skippedCompleted = $data.transfers.Count - $transfersToSave.Count
    }
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
}
catch {
    Send-WebHostFileExplorerError -ErrorRecord $_ -Context $Context -Request $Request -Response $Response -SessionData $sessiondata -LogData @{
        UserID = $userID
        TransferCount = $data.transfers.Count
    }
}
