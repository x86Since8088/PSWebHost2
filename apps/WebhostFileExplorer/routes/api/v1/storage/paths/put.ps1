# PUT /api/v1/storage/paths
# Update storage path permissions

param($Request, $Response, $SessionData)

try {
    # Parse request body
    $body = $Request.body | ConvertFrom-Json
    $pathID = $body.pathID
    $permissions = $body.permissions  # Array of { type: 'owner'|'read'|'write', principals: [{ principalType, principalId }] }

    # Validate required fields
    if ([string]::IsNullOrEmpty($pathID)) {
        $Response.statuscode = 400
        $Response.json = @{
            status = 'error'
            message = 'Missing required field: pathID'
        } | ConvertTo-Json
        return
    }

    # Get current user and roles
    $userID = $SessionData.UserID
    if ([string]::IsNullOrEmpty($userID)) {
        $Response.statuscode = 401
        $Response.json = @{
            status = 'error'
            message = 'Authentication required'
        } | ConvertTo-Json
        return
    }

    $roles = @()
    if ($SessionData.Roles) {
        $roles = $SessionData.Roles
    }

    # Check if path exists and user has permission to modify it
    $pathQuery = "SELECT PathID, OwnerUserID, Name FROM Storage_Paths WHERE PathID = @PathID AND IsActive = 1"
    $pathResult = db_sqlitequery -query $pathQuery -parameters @{ PathID = $pathID }

    if (-not $pathResult -or $pathResult.Count -eq 0) {
        $Response.statuscode = 404
        $Response.json = @{
            status = 'error'
            message = 'Storage path not found'
        } | ConvertTo-Json
        return
    }

    $path = $pathResult[0]

    # Check if user is owner or has owner permission
    $isOwner = $path.OwnerUserID -eq $userID

    if (-not $isOwner) {
        # Check if user has owner permission via groups or roles
        $userGroupsQuery = "SELECT GroupID FROM User_Groups_Map WHERE UserID = @UserID"
        $userGroupsResult = db_sqlitequery -query $userGroupsQuery -parameters @{ UserID = $userID }
        $userGroups = @()
        if ($userGroupsResult) {
            $userGroups = $userGroupsResult | ForEach-Object { $_.GroupID }
        }

        $ownerPermQuery = @"
SELECT COUNT(*) as HasOwner
FROM Storage_Path_Permissions
WHERE PathID = @PathID AND PermissionType = 'owner'
AND (
    (PrincipalType = 'user' AND PrincipalID = @UserID)
    OR (PrincipalType = 'group' AND PrincipalID IN (SELECT value FROM json_each(@UserGroups)))
    OR (PrincipalType = 'role' AND PrincipalID IN (SELECT value FROM json_each(@Roles)))
)
"@

        $ownerPermParams = @{
            PathID = $pathID
            UserID = $userID
            UserGroups = ($userGroups | ConvertTo-Json -Compress)
            Roles = ($roles | ConvertTo-Json -Compress)
        }

        $ownerPermResult = db_sqlitequery -query $ownerPermQuery -parameters $ownerPermParams

        if (-not $ownerPermResult -or $ownerPermResult[0].HasOwner -eq 0) {
            $Response.statuscode = 403
            $Response.json = @{
                status = 'error'
                message = 'Only path owners can modify permissions'
            } | ConvertTo-Json
            return
        }
    }

    # Delete existing permissions
    $deleteQuery = "DELETE FROM Storage_Path_Permissions WHERE PathID = @PathID"
    db_sqlitenonquery -query $deleteQuery -parameters @{ PathID = $pathID }

    # Insert new permissions
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

    # Update the UpdatedTime
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $updateTimeQuery = "UPDATE Storage_Paths SET UpdatedTime = @UpdatedTime WHERE PathID = @PathID"
    db_sqlitenonquery -query $updateTimeQuery -parameters @{ PathID = $pathID; UpdatedTime = $now }

    # Return success response
    $Response.statuscode = 200
    $Response.json = @{
        status = 'success'
        data = @{
            pathID = $pathID
            permissions = $insertedPermissions
            updatedTime = $now
        }
    } | ConvertTo-Json -Depth 10

} catch {
    $Response.statuscode = 500
    $Response.json = @{
        status = 'error'
        message = "Failed to update storage path permissions: $($_.Exception.Message)"
        details = $_.Exception.ToString()
    } | ConvertTo-Json
}
