# DELETE /api/v1/storage/paths?pathID=XXXX
# Deactivate a storage path (soft delete)

param($Request, $Response, $SessionData)

try {
    # Get pathID from query string
    $pathID = $Request.query.pathID

    # Validate required field
    if ([string]::IsNullOrEmpty($pathID)) {
        $Response.statuscode = 400
        $Response.json = @{
            status = 'error'
            message = 'Missing required parameter: pathID'
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

    # Check if path exists and user has permission to delete it
    $pathQuery = "SELECT PathID, OwnerUserID, Name FROM Storage_Paths WHERE PathID = @PathID AND IsActive = 1"
    $pathResult = db_sqlitequery -query $pathQuery -parameters @{ PathID = $pathID }

    if (-not $pathResult -or $pathResult.Count -eq 0) {
        $Response.statuscode = 404
        $Response.json = @{
            status = 'error'
            message = 'Storage path not found or already deactivated'
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
                message = 'Only path owners can delete storage paths'
            } | ConvertTo-Json
            return
        }
    }

    # Soft delete: set IsActive = 0
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $deactivateQuery = "UPDATE Storage_Paths SET IsActive = 0, UpdatedTime = @UpdatedTime WHERE PathID = @PathID"
    db_sqlitenonquery -query $deactivateQuery -parameters @{ PathID = $pathID; UpdatedTime = $now }

    # Return success response
    $Response.statuscode = 200
    $Response.json = @{
        status = 'success'
        data = @{
            pathID = $pathID
            name = $path.Name
            deactivated = $true
            updatedTime = $now
        }
    } | ConvertTo-Json -Depth 10

} catch {
    $Response.statuscode = 500
    $Response.json = @{
        status = 'error'
        message = "Failed to deactivate storage path: $($_.Exception.Message)"
        details = $_.Exception.ToString()
    } | ConvertTo-Json
}
