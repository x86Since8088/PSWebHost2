param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata,
    [switch]$Test,
    [string[]]$Roles = @()
)

<#
.SYNOPSIS
    File operations endpoint (create folder, rename, delete, etc.)

.DESCRIPTION
    Handles file operations including create folder, rename, delete, copy, move, and batch operations.
    Request body is read from the HTTP request input stream and parsed as JSON.

.EXAMPLE
    # Test mode is not supported for this endpoint
    # Use the web interface or API client to test file operations
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
    Write-Host "`n=== File Operations POST Test Mode ===" -ForegroundColor Red
    Write-Host "Test mode is not supported for this endpoint." -ForegroundColor Yellow
    Write-Host "Use the web interface or API client to test file operations." -ForegroundColor Yellow
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

# Validate action
if (-not $data.action) {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Missing required parameter: action'
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
    return
}

try {
    # Update stats
    if ($Global:PSWebServer['WebhostFileExplorer']) {
        $Global:PSWebServer['WebhostFileExplorer'].Stats.FileOperations++
        $Global:PSWebServer['WebhostFileExplorer'].Stats.LastOperation = Get-Date
    }

    switch ($data.action) {
        'createFolder' {
            # Create a new folder
            if (-not $data.name) {
                throw "Missing required parameter: name"
            }

            # Get logical path (default to User:me if not specified)
            $logicalPath = if ($data.path) { $data.path } else { "User:me" }

            # Parse path format: local|localhost|User:me/Documents
            if ($logicalPath -match '^([^|]+)\|([^|]+)\|(.+)$') {
                $logicalPath = $matches[3]  # Extract just the logical path part
            }

            # Resolve path with write permission
            $pathResult = Resolve-WebHostFileExplorerPath -LogicalPath $logicalPath -UserID $userID -Roles $sessiondata.Roles -Response $Response -RequiredPermission 'write'
            if (-not $pathResult) { return }

            # Create folder at physical path
            $targetPath = Join-Path $pathResult.PhysicalPath $data.name
            New-Item -Path $targetPath -ItemType Directory -Force | Out-Null

            $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Folder created successfully' -Data @{
                path = "$logicalPath/$($data.name)"
            }
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
        }

        'uploadFile' {
            # Upload/save a file
            if (-not $data.name -or -not $data.content) {
                throw "Missing required parameters: name, content"
            }

            # Get logical path (default to User:me if not specified)
            $logicalPath = if ($data.path) { $data.path } else { "User:me" }

            # Parse path format: local|localhost|User:me/Documents
            if ($logicalPath -match '^([^|]+)\|([^|]+)\|(.+)$') {
                $logicalPath = $matches[3]  # Extract just the logical path part
            }

            # Resolve path with write permission
            $pathResult = Resolve-WebHostFileExplorerPath -LogicalPath $logicalPath -UserID $userID -Roles $sessiondata.Roles -Response $Response -RequiredPermission 'write'
            if (-not $pathResult) { return }

            # Create target folder if it doesn't exist
            if (-not (Test-Path $pathResult.PhysicalPath)) {
                New-Item -Path $pathResult.PhysicalPath -ItemType Directory -Force | Out-Null
            }

            $targetPath = Join-Path $pathResult.PhysicalPath $data.name

            # Decode base64 content if present
            if ($data.encoding -eq 'base64') {
                $bytes = [System.Convert]::FromBase64String($data.content)
                [System.IO.File]::WriteAllBytes($targetPath, $bytes)
            }
            else {
                Set-Content -Path $targetPath -Value $data.content -Force
            }

            $result = Get-Item $targetPath

            $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'File uploaded successfully' -Data @{
                file = $result.Name
            }
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
        }

        'rename' {
            # Rename a file or folder
            if (-not $data.path -or -not $data.newName) {
                throw "Missing required parameters: path, newName"
            }

            # Parse path format: local|localhost|User:me/Documents
            $logicalPath = $data.path
            if ($logicalPath -match '^([^|]+)\|([^|]+)\|(.+)$') {
                $logicalPath = $matches[3]  # Extract just the logical path part
            }

            # Resolve full logical path with write permission
            $pathResult = Resolve-WebHostFileExplorerPath -LogicalPath $logicalPath -UserID $userID -Roles $sessiondata.Roles -Response $Response -RequiredPermission 'write'
            if (-not $pathResult) { return }

            # Get parent directory and build new path
            $parentDir = Split-Path $pathResult.PhysicalPath -Parent
            $newPath = Join-Path $parentDir $data.newName

            # Rename the item
            Rename-Item -Path $pathResult.PhysicalPath -NewName $data.newName -Force
            $result = Get-Item $newPath

            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Renamed: $($data.path) to $($data.newName)" -Data @{
                UserID = $userID
                OldPath = $pathResult.PhysicalPath
                NewPath = $newPath
            }

            $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Item renamed successfully' -Data @{
                newName = $result.Name
                newPath = $newPath
            }
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
        }

        'batchRename' {
            # Batch rename files/folders with conflict checking
            if (-not $data.renames -or $data.renames.Count -eq 0) {
                throw "Missing required parameter: renames"
            }

            $renamed = @()
            $conflicts = @()
            $errors = @()

            # First pass: Validate all paths and check for conflicts
            $renameOperations = @()
            foreach ($operation in $data.renames) {
                try {
                    if (-not $operation.path -or -not $operation.newName) {
                        $errors += @{
                            oldName = $operation.path
                            newName = $operation.newName
                            error = "Missing path or newName"
                        }
                        continue
                    }

                    # Parse path format: local|localhost|User:me/Documents
                    $logicalPath = $operation.path
                    if ($logicalPath -match '^([^|]+)\|([^|]+)\|(.+)$') {
                        $logicalPath = $matches[3]  # Extract just the logical path part
                    }

                    # Resolve path with write permission
                    $pathResult = Resolve-WebHostFileExplorerPath -LogicalPath $logicalPath -UserID $userID -Roles $sessiondata.Roles -Response $Response -RequiredPermission 'write'
                    if (-not $pathResult) {
                        $errors += @{
                            oldName = (Split-Path $operation.path -Leaf)
                            newName = $operation.newName
                            error = "Access denied or path not found"
                        }
                        continue
                    }

                    # Get parent directory and build new path
                    $parentDir = Split-Path $pathResult.PhysicalPath -Parent
                    $newPath = Join-Path $parentDir $operation.newName

                    # Check for conflict: target file/folder already exists
                    if (Test-Path $newPath) {
                        # Only conflict if it's a different file (not renaming to itself)
                        if ($pathResult.PhysicalPath -ne $newPath) {
                            $conflicts += @{
                                oldName = (Split-Path $pathResult.PhysicalPath -Leaf)
                                newName = $operation.newName
                                error = "File or folder already exists"
                            }
                            continue
                        }
                    }

                    # Valid operation - add to pending list
                    $renameOperations += @{
                        LogicalPath = $operation.path
                        PhysicalPath = $pathResult.PhysicalPath
                        NewName = $operation.newName
                        NewPath = $newPath
                    }
                }
                catch {
                    $errors += @{
                        oldName = (Split-Path $operation.path -Leaf)
                        newName = $operation.newName
                        error = $_.Exception.Message
                    }
                }
            }

            # If conflicts or errors found, return failure response
            if ($conflicts.Count -gt 0 -or $errors.Count -gt 0) {
                $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Conflicts or errors detected' -Data @{
                    renamed = 0
                    conflicts = $conflicts
                    errors = $errors
                }
                Send-WebHostFileExplorerResponse -Response $Response -StatusCode 409 -JsonContent $json
                return
            }

            # Second pass: Perform all renames
            $undoItems = @()
            foreach ($op in $renameOperations) {
                try {
                    $oldFileName = Split-Path $op.PhysicalPath -Leaf
                    Rename-Item -Path $op.PhysicalPath -NewName $op.NewName -Force
                    $renamed += $op.LogicalPath

                    # Track for undo
                    $undoItems += @{
                        originalPath = $op.PhysicalPath
                        newPath = $op.NewPath
                        logicalPath = $op.LogicalPath
                        oldName = $oldFileName
                        newName = $op.NewName
                        type = if (Test-Path -Path $op.NewPath -PathType Container) { 'folder' } else { 'file' }
                    }

                    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Batch renamed: $($op.LogicalPath) to $($op.NewName)" -Data @{
                        UserID = $userID
                        OldPath = $op.PhysicalPath
                        NewPath = $op.NewPath
                    }
                }
                catch {
                    $errors += @{
                        oldName = (Split-Path $op.PhysicalPath -Leaf)
                        newName = $op.NewName
                        error = $_.Exception.Message
                    }
                    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Failed to rename: $($op.LogicalPath) - $($_.Exception.Message)" -Data @{
                        UserID = $userID
                        Error = $_.Exception.Message
                    }
                }
            }

            # Save undo data if any renames succeeded
            $undoId = $null
            if ($undoItems.Count -gt 0) {
                $operationID = [guid]::NewGuid().ToString()
                $undoOperation = @{
                    id = $operationID
                    timestamp = Get-Date -Format "o"
                    action = 'batchRename'
                    itemCount = $undoItems.Count
                    items = $undoItems
                }
                Save-WebHostFileExplorerUndoData -UserID $userID -UndoOperation $undoOperation
                $undoId = $operationID
            }

            # Return success (even if some failed in second pass)
            $json = New-WebHostFileExplorerResponse -Status 'success' -Message "Renamed $($renamed.Count) item(s)" -Data @{
                renamed = $renamed.Count
                errors = $errors
                conflicts = @()
                undoId = $undoId
            }
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
        }

        'delete' {
            $deleteOperationStart = Get-Date

            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE OPERATION] START" -Data @{
                UserID = $userID
                Timestamp = Get-Date -Format "o"
            }

            # Delete one or more files/folders (moves to trash bin for undo capability)

            # Support both single path and array of paths
            $pathsToDelete = @()
            if ($data.path) {
                $pathsToDelete += $data.path
            }
            if ($data.paths) {
                $pathsToDelete += $data.paths
            }

            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE OPERATION] Received $($pathsToDelete.Count) path(s) to delete" -Data @{
                UserID = $userID
                PathCount = $pathsToDelete.Count
                Paths = $pathsToDelete
            }

            if ($pathsToDelete.Count -eq 0) {
                throw "Missing required parameter: path or paths"
            }

            # Phase 1: Validate and resolve all paths
            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE OPERATION] Phase 1: START - Path validation and resolution" -Data @{
                UserID = $userID
            }

            $validationStart = Get-Date
            $itemsToDelete = @()
            $errors = @()

            foreach ($rawLogicalPath in $pathsToDelete) {
                $pathIndex = $pathsToDelete.IndexOf($rawLogicalPath) + 1

                # Parse path format: local|localhost|User:me/Documents
                $logicalPath = $rawLogicalPath
                if ($logicalPath -match '^([^|]+)\|([^|]+)\|(.+)$') {
                    $logicalPath = $matches[3]  # Extract just the logical path part
                }

                Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE OPERATION] Phase 1: Validating path $pathIndex of $($pathsToDelete.Count)" -Data @{
                    UserID = $userID
                    PathIndex = $pathIndex
                    RawPath = $rawLogicalPath
                    LogicalPath = $logicalPath
                }

                try {
                    # Resolve path with write permission (delete requires write)
                    $pathResult = Resolve-WebHostFileExplorerPath -LogicalPath $logicalPath -UserID $userID -Roles $sessiondata.Roles -Response $Response -RequiredPermission 'write'
                    if (-not $pathResult) {
                        $errors += @{
                            path = $logicalPath
                            error = "Access denied or path not found"
                        }
                        Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "[DELETE OPERATION] Phase 1: Path validation FAILED - Access denied" -Data @{
                            UserID = $userID
                            LogicalPath = $logicalPath
                        }
                        continue
                    }

                    $itemsToDelete += @{
                        LogicalPath = $logicalPath
                        PhysicalPath = $pathResult.PhysicalPath
                    }

                    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE OPERATION] Phase 1: Path validation SUCCESS" -Data @{
                        UserID = $userID
                        LogicalPath = $logicalPath
                        PhysicalPath = $pathResult.PhysicalPath
                    }
                }
                catch {
                    $errors += @{
                        path = $logicalPath
                        error = $_.Exception.Message
                    }
                    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "[DELETE OPERATION] Phase 1: Path validation ERROR - $($_.Exception.Message)" -Data @{
                        UserID = $userID
                        LogicalPath = $logicalPath
                        Error = $_.Exception.Message
                    }
                }
            }

            $validationDuration = (Get-Date) - $validationStart
            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE OPERATION] Phase 1: COMPLETE - Validation finished" -Data @{
                UserID = $userID
                ValidatedItems = $itemsToDelete.Count
                FailedItems = $errors.Count
                DurationMs = [int]$validationDuration.TotalMilliseconds
            }

            # Phase 2: Move items to trash bin
            if ($itemsToDelete.Count -gt 0) {
                Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE OPERATION] Phase 2: START - Moving items to trash" -Data @{
                    UserID = $userID
                    ItemCount = $itemsToDelete.Count
                }

                $trashOperationStart = Get-Date
                try {
                    $trashResult = Move-WebHostFileExplorerToTrash -UserID $userID -Items $itemsToDelete -Action 'delete' -SessionData $sessiondata
                    $trashOperationDuration = (Get-Date) - $trashOperationStart

                    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE OPERATION] Phase 2: COMPLETE - Trash operation finished" -Data @{
                        UserID = $userID
                        MovedItems = $trashResult.movedItems.Count
                        Errors = $trashResult.errors.Count
                        DurationMs = [int]$trashOperationDuration.TotalMilliseconds
                    }

                    # Add any errors from trash operation
                    if ($trashResult.errors) {
                        $errors += $trashResult.errors
                    }

                    # Phase 3: Save undo data
                    if ($trashResult.movedItems.Count -gt 0) {
                        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE OPERATION] Phase 3: START - Saving undo data" -Data @{
                            UserID = $userID
                            OperationID = $trashResult.operation.id
                        }

                        $undoSaveStart = Get-Date
                        try {
                            Save-WebHostFileExplorerUndoData -UserID $userID -UndoOperation $trashResult.operation
                            $undoSaveDuration = (Get-Date) - $undoSaveStart

                            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE OPERATION] Phase 3: COMPLETE - Undo data saved" -Data @{
                                UserID = $userID
                                OperationID = $trashResult.operation.id
                                DurationMs = [int]$undoSaveDuration.TotalMilliseconds
                            }
                        }
                        catch {
                            $undoSaveDuration = (Get-Date) - $undoSaveStart
                            Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "[DELETE OPERATION] Phase 3: WARNING - Failed to save undo data: $($_.Exception.Message)" -Data @{
                                UserID = $userID
                                Error = $_.Exception.Message
                                DurationMs = [int]$undoSaveDuration.TotalMilliseconds
                            }
                            # Continue anyway - files are already in trash
                        }
                    }

                    # Return result
                    $totalDuration = (Get-Date) - $deleteOperationStart
                    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE OPERATION] SUCCESS - Operation complete" -Data @{
                        UserID = $userID
                        DeletedItems = $trashResult.movedItems.Count
                        FailedItems = $errors.Count
                        TotalDurationMs = [int]$totalDuration.TotalMilliseconds
                        OperationID = if ($trashResult.operation) { $trashResult.operation.id } else { $null }
                    }

                    $json = New-WebHostFileExplorerResponse -Status 'success' -Message "Deleted $($trashResult.movedItems.Count) item(s)" -Data @{
                        deleted = $trashResult.movedItems | ForEach-Object { $_.logicalPath }
                        errors = $errors
                        count = $trashResult.movedItems.Count
                        undoId = if ($trashResult.operation) { $trashResult.operation.id } else { $null }
                    }
                    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
                }
                catch {
                    $trashOperationDuration = (Get-Date) - $trashOperationStart
                    $totalDuration = (Get-Date) - $deleteOperationStart

                    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "[DELETE OPERATION] FAILED - Trash operation error: $($_.Exception.Message)" -Data @{
                        UserID = $userID
                        ItemCount = $itemsToDelete.Count
                        Error = $_.Exception.Message
                        StackTrace = $_.ScriptStackTrace
                        TrashDurationMs = [int]$trashOperationDuration.TotalMilliseconds
                        TotalDurationMs = [int]$totalDuration.TotalMilliseconds
                    }
                    throw "Failed to move items to trash: $($_.Exception.Message)"
                }
            }
            else {
                $totalDuration = (Get-Date) - $deleteOperationStart
                Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "[DELETE OPERATION] FAILED - All items failed validation" -Data @{
                    UserID = $userID
                    ErrorCount = $errors.Count
                    TotalDurationMs = [int]$totalDuration.TotalMilliseconds
                }

                # All items failed validation
                $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Failed to delete items" -Data @{
                    deleted = @()
                    errors = $errors
                    count = 0
                }
                Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
            }
        }

        default {
            throw "Unknown action: $($data.action)"
        }
    }
}
catch {
    Send-WebHostFileExplorerError -ErrorRecord $_ -Context $Context -Request $Request -Response $Response -SessionData $sessiondata -LogData @{ UserID = $userID; Action = $data.action }
}
