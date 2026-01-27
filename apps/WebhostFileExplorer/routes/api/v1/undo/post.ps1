param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata,
    [switch]$Test,
    [string[]]$Roles = @(),
    [hashtable]$Body = @{}
)

<#
.SYNOPSIS
    Undo endpoint - Restores deleted files from trash or reverses rename operations

.EXAMPLE
    # Test undo delete operation
    .\post.ps1 -Test -Body @{ operationId = 'guid-here' }
#>

# Import File Explorer helper module functions
try {Import-TrackedModule "FileExplorerHelper"
}
catch {
    if ($Test) {
        Write-Host "`n=== File Explorer Helper Load Error ===" -ForegroundColor Red
        Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Stack Trace:" -ForegroundColor Gray
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
        Write-Host "`n=== End Error ===" -ForegroundColor Red
        return
    }
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Failed to import FileExplorerHelper module: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode 500 -String $Report.body -ContentType $Report.contentType
    return
}

# Handle test mode
if ($Test) {
    # Create mock sessiondata
    if ($Roles.Count -eq 0) {
        $Roles = @('authenticated')
    }
    $sessiondata = @{
        Roles = $Roles
        UserID = 'test-user-123'
        SessionID = 'test-session'
    }
    Write-Host "`n=== Undo POST Test Mode ===" -ForegroundColor Cyan
    Write-Host "UserID: $($sessiondata.UserID)" -ForegroundColor Yellow
    Write-Host "Roles: $($Roles -join ', ')" -ForegroundColor Yellow

    if ($Body.Count -eq 0) {
        Write-Host "`n=== Usage Examples ===" -ForegroundColor Yellow
        Write-Host ".\post.ps1 -Test -Body @{ operationId = 'guid-here' }" -ForegroundColor Gray
        return
    }
}

# Validate session
if ($Test) {
    $userID = $sessiondata.UserID
} else {
    $userID = Test-WebHostFileExplorerSession -SessionData $sessiondata -Response $Response
    if (-not $userID) { return }
}

# Read request body
if ($Test -and $Body.Count -gt 0) {
    $data = $Body
    Write-Host "Request Body: $($data | ConvertTo-Json -Compress)" -ForegroundColor Yellow
} else {
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
}

# Validate operation ID
if (-not $data.operationId) {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Missing required parameter: operationId'
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
    return
}

try {
    # Load undo data
    $dataRoot = if ($Global:PSWebServer -and $Global:PSWebServer.DataPath) {
        $Global:PSWebServer.DataPath
    } else {
        Join-Path $PSScriptRoot "..\..\..\..\..\..\PsWebHost_Data"
    }

    $undoFilePath = Join-Path $dataRoot "apps\WebhostFileExplorer\UserMetadata\$userID\undo.json"

    if (-not (Test-Path $undoFilePath)) {
        throw "No undo history found for user"
    }

    $undoData = Get-Content $undoFilePath -Raw | ConvertFrom-Json

    # Find operation
    $operation = $undoData.operations | Where-Object { $_.id -eq $data.operationId } | Select-Object -First 1

    if (-not $operation) {
        throw "Operation not found: $($data.operationId)"
    }

    # Check if already undone
    if ($operation.undone) {
        throw "Operation already undone"
    }

    # Perform undo based on action type
    $restored = @()
    $errors = @()

    switch ($operation.action) {
        'delete' {
            # Restore from trash bin (supports multi-user restore)
            foreach ($item in $operation.items) {
                try {
                    # Verify trash file exists
                    if (-not (Test-Path $item.trashPath)) {
                        $errors += @{
                            path = $item.logicalPath
                            error = "File not found in trash"
                        }
                        continue
                    }

                    # Read metadata file to verify permissions
                    $metadataPath = if ($item.metadataPath) {
                        $item.metadataPath
                    } else {
                        "$($item.trashPath).metadata.json"
                    }

                    $metadata = $null
                    $canRestore = $false

                    if (Test-Path $metadataPath) {
                        try {
                            $metadata = Get-Content $metadataPath -Raw | ConvertFrom-Json

                            # Check if current user can restore:
                            # 1. Original user who deleted it
                            if ($metadata.deletedBy.userID -eq $userID) {
                                $canRestore = $true
                            }
                            # 2. User has 'admin' or 'filemanager' role
                            elseif ($sessiondata.Roles -contains 'admin' -or $sessiondata.Roles -contains 'filemanager') {
                                $canRestore = $true
                                Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "User $userID restoring file deleted by $($metadata.deletedBy.userID) (role-based access)" -Data @{
                                    RestoringUser = $userID
                                    OriginalDeleter = $metadata.deletedBy.userID
                                    Roles = $sessiondata.Roles
                                }
                            }
                            # 3. Remote storage: check if user has credentials (placeholder)
                            # This would integrate with WebHostSMBClient or WebHostSSHFileAccess
                            elseif ($item.isRemote -and $item.accessMethod -ne 'Direct') {
                                # TODO: Check if user has stored credentials for this remote location
                                # For now, deny access
                                $canRestore = $false
                                Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "User $userID attempted to restore remote file without credentials" -Data @{
                                    RestoringUser = $userID
                                    OriginalDeleter = $metadata.deletedBy.userID
                                    AccessMethod = $item.accessMethod
                                }
                            }
                            else {
                                $canRestore = $false
                            }
                        }
                        catch {
                            Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "Failed to read metadata file: $metadataPath - $($_.Exception.Message)"
                            # If metadata can't be read, only allow original user
                            $canRestore = ($operation.deletedBy.userID -eq $userID)
                        }
                    }
                    else {
                        # No metadata file - only allow original user (from operation data)
                        if ($operation.deletedBy -and $operation.deletedBy.userID) {
                            $canRestore = ($operation.deletedBy.userID -eq $userID)
                        }
                        else {
                            # Fallback: allow restore (old operations without deletedBy field)
                            $canRestore = $true
                        }
                    }

                    if (-not $canRestore) {
                        $errors += @{
                            path = $item.logicalPath
                            error = "Permission denied: You do not have access to restore this file"
                        }
                        continue
                    }

                    # Create parent directory if needed
                    $parentDir = Split-Path $item.originalPath -Parent
                    if (-not (Test-Path $parentDir)) {
                        New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
                    }

                    # Check if original location is now occupied
                    if (Test-Path $item.originalPath) {
                        $errors += @{
                            path = $item.logicalPath
                            error = "Original location is now occupied"
                        }
                        continue
                    }

                    # Move from trash back to original location
                    Move-Item -Path $item.trashPath -Destination $item.originalPath -Force

                    # Remove metadata file
                    if (Test-Path $metadataPath) {
                        Remove-Item -Path $metadataPath -Force
                    }

                    $restored += $item.logicalPath

                    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Restored from trash: $($item.logicalPath)" -Data @{
                        RestoringUser = $userID
                        OriginalDeleter = if ($metadata) { $metadata.deletedBy.userID } else { 'unknown' }
                        OperationID = $operation.id
                        OriginalPath = $item.originalPath
                    }
                }
                catch {
                    $errors += @{
                        path = $item.logicalPath
                        error = $_.Exception.Message
                    }
                    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Failed to restore: $($item.logicalPath) - $($_.Exception.Message)" -Data @{
                        UserID = $userID
                        OperationID = $operation.id
                    }
                }
            }

            # Clean up empty trash folder if all items restored
            if ($restored.Count -gt 0) {
                # Find trash path from items (might be in operation or item)
                $trashFolders = @()
                foreach ($item in $operation.items) {
                    if ($item.trashPath) {
                        $trashFolder = Split-Path $item.trashPath -Parent
                        if ($trashFolders -notcontains $trashFolder) {
                            $trashFolders += $trashFolder
                        }
                    }
                }

                foreach ($trashFolder in $trashFolders) {
                    try {
                        if (Test-Path $trashFolder) {
                            # Only remove if empty (all items were restored)
                            $remainingItems = Get-ChildItem $trashFolder -File
                            if ($remainingItems.Count -eq 0) {
                                Remove-Item -Path $trashFolder -Recurse -Force
                            }
                        }
                    }
                    catch {
                        # Non-critical error - trash cleanup failed
                        Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "Failed to clean up trash folder: $trashFolder"
                    }
                }
            }
        }

        'batchRename' {
            # Reverse rename operations
            foreach ($item in $operation.items) {
                try {
                    # Verify new path exists
                    if (-not (Test-Path $item.newPath)) {
                        $errors += @{
                            path = $item.logicalPath
                            error = "File not found at renamed location"
                        }
                        continue
                    }

                    # Check if original name is now occupied
                    if (Test-Path $item.originalPath) {
                        $errors += @{
                            path = $item.logicalPath
                            error = "Original filename is now occupied"
                        }
                        continue
                    }

                    # Rename back to original name
                    Rename-Item -Path $item.newPath -NewName $item.oldName -Force

                    $restored += $item.logicalPath

                    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Reversed rename: $($item.newName) → $($item.oldName)" -Data @{
                        UserID = $userID
                        OperationID = $operation.id
                        NewPath = $item.newPath
                        OriginalPath = $item.originalPath
                    }
                }
                catch {
                    $errors += @{
                        path = $item.logicalPath
                        error = $_.Exception.Message
                    }
                    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Failed to reverse rename: $($item.logicalPath) - $($_.Exception.Message)" -Data @{
                        UserID = $userID
                        OperationID = $operation.id
                    }
                }
            }
        }

        default {
            throw "Unsupported undo action: $($operation.action)"
        }
    }

    # Mark operation as undone in undo.json
    if ($restored.Count -gt 0) {
        # Update operation status
        $undoData.operations | Where-Object { $_.id -eq $data.operationId } | ForEach-Object {
            $_ | Add-Member -NotePropertyName 'undone' -NotePropertyValue $true -Force
            $_ | Add-Member -NotePropertyName 'undoneAt' -NotePropertyValue (Get-Date -Format "o") -Force
            $_ | Add-Member -NotePropertyName 'restoredCount' -NotePropertyValue $restored.Count -Force
        }

        # Save updated undo data
        $undoData | ConvertTo-Json -Depth 10 | Set-Content -Path $undoFilePath -Force
    }

    # Return result
    $json = New-WebHostFileExplorerResponse -Status 'success' -Message "Restored $($restored.Count) item(s)" -Data @{
        restored = $restored
        errors = $errors
        count = $restored.Count
        operationId = $operation.id
        action = $operation.action
    }
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
}
catch {
    Send-WebHostFileExplorerError -ErrorRecord $_ -Context $Context -Request $Request -Response $Response -SessionData $sessiondata -LogData @{ UserID = $userID; OperationID = $data.operationId }
}
