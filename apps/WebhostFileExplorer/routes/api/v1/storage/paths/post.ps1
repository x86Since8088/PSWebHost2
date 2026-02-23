# POST /api/v1/storage/paths
# Register a new storage path with permissions

param($Request, $Response, $SessionData)

try {
    # Parse request body
    $body = $Request.body | ConvertFrom-Json
    $logicalPath = $body.logicalPath
    $physicalPath = $body.physicalPath
    $name = $body.name
    $description = $body.description
    $permissions = $body.permissions  # Array of { type: 'owner'|'read'|'write', principals: [{ principalType, principalId, autoCreate }] }
    $autoCreateGroups = $body.autoCreateGroups  # Optional: auto-create groups for path

    # Validate required fields
    if ([string]::IsNullOrEmpty($logicalPath) -or [string]::IsNullOrEmpty($physicalPath) -or [string]::IsNullOrEmpty($name)) {
        $Response.statuscode = 400
        $Response.json = @{
            status = 'error'
            message = 'Missing required fields: logicalPath, physicalPath, name'
        } | ConvertTo-Json
        return
    }

    # Verify physical path exists
    if (-not (Test-Path -Path $physicalPath -PathType Container)) {
        $Response.statuscode = 400
        $Response.json = @{
            status = 'error'
            message = "Physical path does not exist: $physicalPath"
        } | ConvertTo-Json
        return
    }

    # Get current user
    $userID = $SessionData.UserID
    if ([string]::IsNullOrEmpty($userID)) {
        $Response.statuscode = 401
        $Response.json = @{
            status = 'error'
            message = 'Authentication required'
        } | ConvertTo-Json
        return
    }

    # Generate path ID
    $pathID = [guid]::NewGuid().ToString()
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    # Auto-create groups if requested
    $createdGroups = @()
    if ($autoCreateGroups -eq $true) {
        $safeName = $name -replace '[^a-zA-Z0-9_-]', '_'

        # Create Owner group
        $ownerGroupID = [guid]::NewGuid().ToString()
        $ownerGroupName = "${safeName}_owners"
        $ownerGroupQuery = "INSERT INTO User_Groups (GroupID, Name, Created, Updated) VALUES (@GroupID, @Name, @Created, @Updated)"
        $ownerGroupParams = @{
            GroupID = $ownerGroupID
            Name = $ownerGroupName
            Created = (Get-Date).ToString('o')
            Updated = (Get-Date).ToString('o')
        }

        try {
            db_sqlitenonquery -query $ownerGroupQuery -parameters $ownerGroupParams
            $createdGroups += @{
                groupID = $ownerGroupID
                name = $ownerGroupName
                type = 'owner'
            }
        } catch {
            if ($_.Exception.Message -notlike "*UNIQUE constraint failed*") {
                throw
            }
            # Group already exists, fetch its ID
            $existingQuery = "SELECT GroupID FROM User_Groups WHERE Name = @Name"
            $existingResult = db_sqlitequery -query $existingQuery -parameters @{ Name = $ownerGroupName }
            if ($existingResult -and $existingResult.Count -gt 0) {
                $ownerGroupID = $existingResult[0].GroupID
            }
        }

        # Create Read group
        $readGroupID = [guid]::NewGuid().ToString()
        $readGroupName = "${safeName}_readers"
        $readGroupQuery = "INSERT INTO User_Groups (GroupID, Name, Created, Updated) VALUES (@GroupID, @Name, @Created, @Updated)"
        $readGroupParams = @{
            GroupID = $readGroupID
            Name = $readGroupName
            Created = (Get-Date).ToString('o')
            Updated = (Get-Date).ToString('o')
        }

        try {
            db_sqlitenonquery -query $readGroupQuery -parameters $readGroupParams
            $createdGroups += @{
                groupID = $readGroupID
                name = $readGroupName
                type = 'read'
            }
        } catch {
            if ($_.Exception.Message -notlike "*UNIQUE constraint failed*") {
                throw
            }
            $existingQuery = "SELECT GroupID FROM User_Groups WHERE Name = @Name"
            $existingResult = db_sqlitequery -query $existingQuery -parameters @{ Name = $readGroupName }
            if ($existingResult -and $existingResult.Count -gt 0) {
                $readGroupID = $existingResult[0].GroupID
            }
        }

        # Create Write group
        $writeGroupID = [guid]::NewGuid().ToString()
        $writeGroupName = "${safeName}_writers"
        $writeGroupQuery = "INSERT INTO User_Groups (GroupID, Name, Created, Updated) VALUES (@GroupID, @Name, @Created, @Updated)"
        $writeGroupParams = @{
            GroupID = $writeGroupID
            Name = $writeGroupName
            Created = (Get-Date).ToString('o')
            Updated = (Get-Date).ToString('o')
        }

        try {
            db_sqlitenonquery -query $writeGroupQuery -parameters $writeGroupParams
            $createdGroups += @{
                groupID = $writeGroupID
                name = $writeGroupName
                type = 'write'
            }
        } catch {
            if ($_.Exception.Message -notlike "*UNIQUE constraint failed*") {
                throw
            }
            $existingQuery = "SELECT GroupID FROM User_Groups WHERE Name = @Name"
            $existingResult = db_sqlitequery -query $existingQuery -parameters @{ Name = $writeGroupName }
            if ($existingResult -and $existingResult.Count -gt 0) {
                $writeGroupID = $existingResult[0].GroupID
            }
        }

        # Auto-add created groups to permissions
        if (-not $permissions) { $permissions = @() }
        $permissions += @{
            type = 'owner'
            principals = @(@{ principalType = 'group'; principalId = $ownerGroupID })
        }
        $permissions += @{
            type = 'read'
            principals = @(@{ principalType = 'group'; principalId = $readGroupID })
        }
        $permissions += @{
            type = 'write'
            principals = @(@{ principalType = 'group'; principalId = $writeGroupID })
        }
    }

    # Insert storage path
    $insertPathQuery = @"
INSERT INTO Storage_Paths (PathID, LogicalPath, PhysicalPath, Name, Description, OwnerUserID, CreatedTime, UpdatedTime, IsActive)
VALUES (@PathID, @LogicalPath, @PhysicalPath, @Name, @Description, @OwnerUserID, @CreatedTime, @UpdatedTime, 1)
"@

    $pathParams = @{
        PathID = $pathID
        LogicalPath = $logicalPath
        PhysicalPath = $physicalPath
        Name = $name
        Description = if ($description) { $description } else { "" }
        OwnerUserID = $userID
        CreatedTime = $now
        UpdatedTime = $now
    }

    db_sqlitenonquery -query $insertPathQuery -parameters $pathParams

    # Insert permissions
    $insertedPermissions = @()
    if ($permissions -and $permissions.Count -gt 0) {
        foreach ($perm in $permissions) {
            $permType = $perm.type
            $principals = $perm.principals

            if (-not $principals -or $principals.Count -eq 0) {
                continue
            }

            foreach ($principal in $principals) {
                $principalType = $principal.principalType
                $principalId = $principal.principalId

                # Validate principal type
                if ($principalType -notin @('role', 'group', 'user')) {
                    continue
                }

                # Validate permission type
                if ($permType -notin @('owner', 'read', 'write')) {
                    continue
                }

                $insertPermQuery = @"
INSERT INTO Storage_Path_Permissions (PathID, PermissionType, PrincipalType, PrincipalID)
VALUES (@PathID, @PermissionType, @PrincipalType, @PrincipalID)
"@

                $permParams = @{
                    PathID = $pathID
                    PermissionType = $permType
                    PrincipalType = $principalType
                    PrincipalID = $principalId
                }

                db_sqlitenonquery -query $insertPermQuery -parameters $permParams

                $insertedPermissions += @{
                    permissionType = $permType
                    principalType = $principalType
                    principalId = $principalId
                }
            }
        }
    }

    # Return success response
    $Response.statuscode = 201
    $Response.json = @{
        status = 'success'
        data = @{
            pathID = $pathID
            logicalPath = $logicalPath
            physicalPath = $physicalPath
            name = $name
            createdGroups = $createdGroups
            permissions = $insertedPermissions
        }
    } | ConvertTo-Json -Depth 10

} catch {
    $Response.statuscode = 500
    $Response.json = @{
        status = 'error'
        message = "Failed to register storage path: $($_.Exception.Message)"
        details = $_.Exception.ToString()
    } | ConvertTo-Json
}
