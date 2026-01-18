param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Role Management API Endpoint
# Returns list of roles with their permissions and user counts

try {
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/pswebhost.db"

    # Get all unique roles
    $rolesQuery = "SELECT DISTINCT RoleName FROM PSWeb_Roles ORDER BY RoleName;"
    $dbRoles = Get-PSWebSQLiteData -File $dbFile -Query $rolesQuery

    # Built-in roles with descriptions
    $builtInRoles = @{
        'admin' = @{
            description = 'Full system access with all permissions'
            permissions = @('*')
            isBuiltIn = $true
        }
        'site_admin' = @{
            description = 'Manage site settings and users'
            permissions = @('users.manage', 'settings.edit', 'content.view')
            isBuiltIn = $true
        }
        'system_admin' = @{
            description = 'System configuration and service management'
            permissions = @('system.config', 'services.manage', 'database.access')
            isBuiltIn = $true
        }
        'authenticated' = @{
            description = 'Basic access for logged-in users'
            permissions = @('profile.view', 'cards.use', 'public.access')
            isBuiltIn = $true
        }
        'debug' = @{
            description = 'Access to debugging tools'
            permissions = @('debug.vars', 'debug.errors', 'debug.test')
            isBuiltIn = $true
        }
        'unauthenticated' = @{
            description = 'Limited access for anonymous users'
            permissions = @('login.access', 'public.view')
            isBuiltIn = $true
        }
    }

    $roles = @()

    # Add built-in roles first
    foreach ($roleName in $builtInRoles.Keys) {
        $roleInfo = $builtInRoles[$roleName]

        # Count users with this role
        $countQuery = "SELECT COUNT(*) as count FROM PSWeb_Roles WHERE RoleName = '$roleName' AND PrincipalType COLLATE NOCASE = 'user';"
        $countResult = Get-PSWebSQLiteData -File $dbFile -Query $countQuery
        $userCount = if ($countResult) { $countResult.count } else { 0 }

        $roles += @{
            name = $roleName
            description = $roleInfo.description
            permissions = $roleInfo.permissions
            userCount = $userCount
            isBuiltIn = $true
        }
    }

    # Add any custom roles from database
    if ($dbRoles) {
        foreach ($dbRole in $dbRoles) {
            $roleName = $dbRole.RoleName
            if (-not $builtInRoles.ContainsKey($roleName)) {
                $countQuery = "SELECT COUNT(*) as count FROM PSWeb_Roles WHERE RoleName = '$roleName' AND PrincipalType COLLATE NOCASE = 'user';"
                $countResult = Get-PSWebSQLiteData -File $dbFile -Query $countQuery
                $userCount = if ($countResult) { $countResult.count } else { 0 }

                $roles += @{
                    name = $roleName
                    description = 'Custom role'
                    permissions = @()
                    userCount = $userCount
                    isBuiltIn = $false
                }
            }
        }
    }

    $result = @{
        roles = $roles
        totalRoles = $roles.Count
    }

    $jsonResponse = $result | ConvertTo-Json -Depth 5
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'RoleManagement' -Message "Error getting roles: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
