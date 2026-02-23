# GET /api/v1/storage/paths
# List all registered storage paths accessible to the current user

param($Request, $Response, $SessionData)

try {
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

    # Get user's groups
    $userGroupsQuery = "SELECT GroupID FROM User_Groups_Map WHERE UserID = @UserID"
    $userGroupsResult = db_sqlitequery -query $userGroupsQuery -parameters @{ UserID = $userID }
    $userGroups = @()
    if ($userGroupsResult) {
        $userGroups = $userGroupsResult | ForEach-Object { $_.GroupID }
    }

    # Build permission query - user has access if:
    # 1. They are the owner
    # 2. They have explicit user permission
    # 3. They belong to a group with permission
    # 4. They have a role with permission
    $pathsQuery = @"
SELECT DISTINCT
    sp.PathID,
    sp.LogicalPath,
    sp.PhysicalPath,
    sp.Name,
    sp.Description,
    sp.OwnerUserID,
    sp.CreatedTime,
    sp.UpdatedTime,
    sp.IsActive
FROM Storage_Paths sp
LEFT JOIN Storage_Path_Permissions spp ON sp.PathID = spp.PathID
WHERE sp.IsActive = 1
AND (
    sp.OwnerUserID = @UserID
    OR (spp.PrincipalType = 'user' AND spp.PrincipalID = @UserID)
    OR (spp.PrincipalType = 'group' AND spp.PrincipalID IN (SELECT value FROM json_each(@UserGroups)))
    OR (spp.PrincipalType = 'role' AND spp.PrincipalID IN (SELECT value FROM json_each(@Roles)))
)
ORDER BY sp.Name
"@

    $pathsParams = @{
        UserID = $userID
        UserGroups = ($userGroups | ConvertTo-Json -Compress)
        Roles = ($roles | ConvertTo-Json -Compress)
    }

    $pathsResult = db_sqlitequery -query $pathsQuery -parameters $pathsParams

    # Build response with permissions for each path
    $paths = @()
    if ($pathsResult) {
        foreach ($path in $pathsResult) {
            # Get all permissions for this path
            $permissionsQuery = @"
SELECT PermissionType, PrincipalType, PrincipalID
FROM Storage_Path_Permissions
WHERE PathID = @PathID
ORDER BY PermissionType, PrincipalType, PrincipalID
"@
            $permissionsResult = db_sqlitequery -query $permissionsQuery -parameters @{ PathID = $path.PathID }

            # Group permissions by type
            $permissionsGrouped = @{
                owner = @()
                read = @()
                write = @()
            }

            if ($permissionsResult) {
                foreach ($perm in $permissionsResult) {
                    $principal = @{
                        principalType = $perm.PrincipalType
                        principalId = $perm.PrincipalID
                    }

                    # Resolve principal name
                    switch ($perm.PrincipalType) {
                        'user' {
                            $userQuery = "SELECT UserID FROM Users WHERE UserID = @UserID LIMIT 1"
                            $userResult = db_sqlitequery -query $userQuery -parameters @{ UserID = $perm.PrincipalID }
                            if ($userResult -and $userResult.Count -gt 0) {
                                $principal.name = $userResult[0].UserID
                            } else {
                                $principal.name = $perm.PrincipalID
                            }
                        }
                        'group' {
                            $groupQuery = "SELECT Name FROM User_Groups WHERE GroupID = @GroupID LIMIT 1"
                            $groupResult = db_sqlitequery -query $groupQuery -parameters @{ GroupID = $perm.PrincipalID }
                            if ($groupResult -and $groupResult.Count -gt 0) {
                                $principal.name = $groupResult[0].Name
                            } else {
                                $principal.name = $perm.PrincipalID
                            }
                        }
                        'role' {
                            $principal.name = $perm.PrincipalID
                        }
                    }

                    $permissionsGrouped[$perm.PermissionType] += $principal
                }
            }

            # Determine user's effective permissions for this path
            $userPermissions = @()

            # Check if owner
            if ($path.OwnerUserID -eq $userID) {
                $userPermissions += 'owner'
            }

            # Check explicit permissions
            if ($permissionsResult) {
                foreach ($perm in $permissionsResult) {
                    $hasAccess = $false

                    switch ($perm.PrincipalType) {
                        'user' {
                            if ($perm.PrincipalID -eq $userID) {
                                $hasAccess = $true
                            }
                        }
                        'group' {
                            if ($userGroups -contains $perm.PrincipalID) {
                                $hasAccess = $true
                            }
                        }
                        'role' {
                            if ($roles -contains $perm.PrincipalID) {
                                $hasAccess = $true
                            }
                        }
                    }

                    if ($hasAccess -and ($perm.PermissionType -notin $userPermissions)) {
                        $userPermissions += $perm.PermissionType
                    }
                }
            }

            $paths += @{
                pathID = $path.PathID
                logicalPath = $path.LogicalPath
                physicalPath = $path.PhysicalPath
                name = $path.Name
                description = $path.Description
                ownerUserID = $path.OwnerUserID
                createdTime = $path.CreatedTime
                updatedTime = $path.UpdatedTime
                isActive = $path.IsActive -eq 1
                permissions = $permissionsGrouped
                userPermissions = $userPermissions
            }
        }
    }

    # Return success response
    $Response.statuscode = 200
    $Response.json = @{
        status = 'success'
        data = @{
            paths = $paths
            count = $paths.Count
        }
    } | ConvertTo-Json -Depth 10

} catch {
    $Response.statuscode = 500
    $Response.json = @{
        status = 'error'
        message = "Failed to retrieve storage paths: $($_.Exception.Message)"
        details = $_.Exception.ToString()
    } | ConvertTo-Json
}
