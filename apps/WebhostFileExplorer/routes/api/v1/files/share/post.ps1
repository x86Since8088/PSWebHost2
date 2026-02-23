param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

<#
.SYNOPSIS
    Create file share

.DESCRIPTION
    POST /api/v1/files/share
    Body: { filePath, expiresInDays, owners: [{type, id}], editors: [...], access: [...] }
    Returns: { shareID, shareToken, shareUrl, expiresTime }

.EXAMPLE
    POST /api/v1/files/share
    Body: {
        "filePath": "System:C/shared.txt",
        "expiresInDays": 7,
        "owners": [{"type": "user", "id": "admin"}],
        "editors": [{"type": "group", "id": "editors-group"}],
        "access": [{"type": "user", "id": "viewer"}]
    }
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

# Validate required fields
if (-not $data.filePath) {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Missing required parameter: filePath'
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
    return
}

$logicalPath = $data.filePath
$expiresInDays = if ($data.expiresInDays) { [int]$data.expiresInDays } else { $null }
$owners = if ($data.owners) { $data.owners } else { @() }
$editors = if ($data.editors) { $data.editors } else { @() }
$accessRoles = if ($data.access) { $data.access } else { @() }

try {
    # Resolve path with read permission (user must have access to share the file)
    $roles = $sessiondata.Roles
    $pathResult = Resolve-WebHostFileExplorerPath -LogicalPath $logicalPath -UserID $userID -Roles $roles -Response $Response -RequiredPermission 'read'
    if (-not $pathResult) { return }

    $physicalPath = $pathResult.PhysicalPath

    # Check if file exists
    if (-not (Test-Path $physicalPath -PathType Leaf)) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'File not found'
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 404 -JsonContent $json
        return
    }

    # Generate share ID and token
    $shareID = [guid]::NewGuid().ToString()
    $shareToken = [Convert]::ToBase64String([guid]::NewGuid().ToByteArray()).Replace('=', '').Replace('+', '-').Replace('/', '_')

    # Calculate expiration
    $createdTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $expiresTime = if ($expiresInDays) {
        [DateTimeOffset]::UtcNow.AddDays($expiresInDays).ToUnixTimeSeconds()
    } else {
        $null
    }

    # Insert into File_Shares table
    $query = @"
INSERT INTO File_Shares (ShareID, FilePath, OwnerUserID, CreatedTime, ExpiresTime, IsActive, ShareToken)
VALUES (@ShareID, @FilePath, @OwnerUserID, @CreatedTime, @ExpiresTime, 1, @ShareToken)
"@

    $params = @{
        ShareID = $shareID
        FilePath = $logicalPath
        OwnerUserID = $userID
        CreatedTime = $createdTime
        ExpiresTime = $expiresTime
        ShareToken = $shareToken
    }

    db_sqlitenonquery -query $query -parameters $params

    # Insert role assignments
    foreach ($owner in $owners) {
        $roleQuery = @"
INSERT INTO File_Share_Roles (ShareID, RoleType, UserID, GroupID)
VALUES (@ShareID, 'owner', @UserID, @GroupID)
"@

        $roleParams = @{
            ShareID = $shareID
            UserID = if ($owner.type -eq 'user') { $owner.id } else { $null }
            GroupID = if ($owner.type -eq 'group') { $owner.id } else { $null }
        }

        db_sqlitenonquery -query $roleQuery -parameters $roleParams
    }

    foreach ($editor in $editors) {
        $roleQuery = @"
INSERT INTO File_Share_Roles (ShareID, RoleType, UserID, GroupID)
VALUES (@ShareID, 'editor', @UserID, @GroupID)
"@

        $roleParams = @{
            ShareID = $shareID
            UserID = if ($editor.type -eq 'user') { $editor.id } else { $null }
            GroupID = if ($editor.type -eq 'group') { $editor.id } else { $null }
        }

        db_sqlitenonquery -query $roleQuery -parameters $roleParams
    }

    foreach ($accessRole in $accessRoles) {
        $roleQuery = @"
INSERT INTO File_Share_Roles (ShareID, RoleType, UserID, GroupID)
VALUES (@ShareID, 'access', @UserID, @GroupID)
"@

        $roleParams = @{
            ShareID = $shareID
            UserID = if ($accessRole.type -eq 'user') { $accessRole.id } else { $null }
            GroupID = if ($accessRole.type -eq 'group') { $accessRole.id } else { $null }
        }

        db_sqlitenonquery -query $roleQuery -parameters $roleParams
    }

    # Generate share URL
    $shareUrl = "$($Request.Url.Scheme)://$($Request.Url.Authority)/apps/WebhostFileExplorer/share/$shareToken"

    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Created file share: $shareID for $logicalPath" -Data @{
        UserID = $userID
        ShareID = $shareID
        FilePath = $logicalPath
        ExpiresInDays = $expiresInDays
    }

    $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'File share created' -Data @{
        shareID = $shareID
        shareToken = $shareToken
        shareUrl = $shareUrl
        expiresTime = $expiresTime
    }

    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
}
catch {
    Send-WebHostFileExplorerError -ErrorRecord $_ -Context $Context -Request $Request -Response $Response -SessionData $sessiondata -LogData @{
        UserID = $userID
        FilePath = $logicalPath
    }
}
