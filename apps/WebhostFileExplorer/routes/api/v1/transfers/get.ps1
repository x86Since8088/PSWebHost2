param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

<#
.SYNOPSIS
    Get persisted transfer state for current user

.DESCRIPTION
    Returns the saved transfers.json file from user's app data directory

.EXAMPLE
    GET /api/v1/transfers
    Response: { "status": "success", "data": { "transfers": [...] } }
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

try {
    # Get user's app data directory
    $projectRoot = $Global:PSWebServer.Project_Root.Path
    $userAppDataPath = Join-Path $projectRoot "PsWebHost_Data\UserData\$userID\apps\WebhostFileExplorer"
    $transfersFilePath = Join-Path $userAppDataPath "transfers.json"

    # Check if file exists
    if (-not (Test-Path $transfersFilePath)) {
        # No saved transfers - return empty array
        $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'No saved transfers' -Data @{
            transfers = @()
        }
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
        return
    }

    # Read transfers file
    $transfersJson = Get-Content -Path $transfersFilePath -Raw -ErrorAction Stop
    $transfersData = $transfersJson | ConvertFrom-Json -ErrorAction Stop

    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Loaded transfers state" -Data @{
        UserID = $userID
        TransferCount = $transfersData.transfers.Count
    }

    # Return transfers
    $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Transfers loaded' -Data @{
        transfers = $transfersData.transfers
        savedAt = $transfersData.savedAt
    }
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
}
catch {
    Send-WebHostFileExplorerError -ErrorRecord $_ -Context $Context -Request $Request -Response $Response -SessionData $sessiondata -LogData @{
        UserID = $userID
    }
}
