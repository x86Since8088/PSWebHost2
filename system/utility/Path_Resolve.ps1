#Requires -Version 7

<#
.SYNOPSIS
    Resolves logical path aliases to physical filesystem paths with authorization.

.DESCRIPTION
    Central path resolution system that:
    - Maps external aliases (User:me, Site, System:C, etc.) to internal paths
    - Validates user authorization for requested paths
    - Provides consistent path handling across all storage types

.PARAMETER LogicalPath
    The logical path with prefix (e.g., "User:me/Documents", "Site/public", "System:C/temp")

.PARAMETER UserID
    The user requesting access

.PARAMETER Roles
    Array of user's roles for authorization checking

.PARAMETER RequiredPermission
    Required permission level: 'read', 'write', or 'owner'
    Default: 'read'

.OUTPUTS
    Returns hashtable with:
    - Success: Boolean
    - PhysicalPath: Resolved filesystem path
    - BasePath: The base path for the storage type
    - RelativePath: Path relative to base
    - StorageType: Type of storage (personal, bucket, site, system)
    - AccessLevel: User's access level
    - Message: Error message if failed

.EXAMPLE
    $result = & $script -LogicalPath "User:me/Documents" -UserID "user@example.com" -Roles @("authenticated")
    # Returns: PhysicalPath = "C:\SC\PsWebHost\PsWebHost_Data\UserData\user@example.com\personal\Documents"

.EXAMPLE
    $result = & $script -LogicalPath "Site/public" -UserID "admin@example.com" -Roles @("site_admin")
    # Returns: PhysicalPath = "C:\SC\PsWebHost\public"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$LogicalPath,

    [Parameter(Mandatory=$true)]
    [string]$UserID,

    [Parameter(Mandatory=$true)]
    [array]$Roles,

    [ValidateSet('read', 'write', 'owner')]
    [string]$RequiredPermission = 'read'
)

$result = @{
    Success = $false
    PhysicalPath = $null
    BasePath = $null
    RelativePath = $null
    StorageType = $null
    AccessLevel = $null
    Message = ""
}

try {
    # Get project root
    $projectRoot = if ($Global:PSWebServer.Project_Root.Path) {
        $Global:PSWebServer.Project_Root.Path
    } else {
        Split-Path (Split-Path $PSScriptRoot)
    }

    # Parse logical path: prefix:identifier/relative/path
    if ($LogicalPath -notmatch '^([^:]+)(?::([^/]+))?(?:/(.*))?$') {
        throw "Invalid logical path format: $LogicalPath"
    }

    $prefix = $matches[1]
    $identifier = $matches[2]
    $relativePath = $matches[3]

    # Sanitize relative path
    if ($relativePath) {
        # Remove any path traversal attempts
        $relativePath = $relativePath -replace '\.\.', ''
        $relativePath = $relativePath.Trim('\', '/')
    }

    switch ($prefix) {
        'User' {
            # User:me - Personal storage
            if ($identifier -ne 'me') {
                throw "Only 'User:me' is supported (user's own storage)"
            }

            # All authenticated users have access to their own storage
            if ($Roles -notcontains 'authenticated') {
                throw "Authentication required for personal storage"
            }

            $basePath = Join-Path $projectRoot "PsWebHost_Data\UserData\$UserID\personal"
            $result.StorageType = 'personal'
            $result.AccessLevel = 'owner'
            $result.Success = $true
        }

        'Bucket' {
            # Bucket:{bucketId} - Shared bucket storage
            if (-not $identifier) {
                throw "Bucket ID required: Bucket:{bucketId}/path"
            }

            # Check bucket access using utility
            $accessCheckScript = Join-Path $PSScriptRoot "Bucket_Access_Check.ps1"
            $accessResult = & $accessCheckScript -UserID $UserID -BucketID $identifier -RequiredPermission $RequiredPermission

            if (-not $accessResult.HasAccess) {
                throw "Access denied to bucket: $identifier"
            }

            $basePath = Join-Path $projectRoot "PsWebHost_Data\SharedBuckets\$identifier"
            $result.StorageType = 'bucket'
            $result.AccessLevel = $accessResult.AccessLevel
            $result.Success = $true
        }

        'Site' {
            # Site - Project root (site_admin or system_admin only)
            if ($Roles -notcontains 'site_admin' -and $Roles -notcontains 'system_admin') {
                throw "site_admin or system_admin role required for Site access"
            }

            # site_admin can only access public/ and routes/
            if ($Roles -contains 'site_admin' -and $Roles -notcontains 'system_admin') {
                $allowedPaths = @('public', 'routes')
                $isAllowed = $false

                if (-not $relativePath) {
                    # Root level - show only allowed directories
                    $isAllowed = $true
                } else {
                    $firstSegment = ($relativePath -split '[/\\]')[0]
                    if ($allowedPaths -contains $firstSegment) {
                        $isAllowed = $true
                    }
                }

                if (-not $isAllowed) {
                    throw "site_admin can only access public/ and routes/ directories"
                }
            }

            $basePath = $projectRoot
            $result.StorageType = 'site'
            $result.AccessLevel = 'owner'
            $result.Success = $true
        }

        'System' {
            # System:{drive} - System paths (system_admin only)
            if ($Roles -notcontains 'system_admin') {
                throw "system_admin role required for System access"
            }

            if (-not $identifier) {
                throw "Drive/mount point required: System:C/path or System:root/path"
            }

            # Resolve drive/mount point
            if ($IsWindows -or $env:OS -like "Windows*") {
                # Windows: System:C means C:\
                if ($identifier -match '^[A-Z]$') {
                    $basePath = "${identifier}:\"
                } else {
                    throw "Invalid Windows drive letter: $identifier"
                }
            } else {
                # Linux: System:root means /
                if ($identifier -eq 'root') {
                    $basePath = '/'
                } else {
                    # Mount points like System:mnt-data for /mnt/data
                    $mountPath = "/$($identifier -replace '-', '/')"
                    if (Test-Path $mountPath) {
                        $basePath = $mountPath
                    } else {
                        throw "Mount point not found: $mountPath"
                    }
                }
            }

            $result.StorageType = 'system'
            $result.AccessLevel = 'owner'
            $result.Success = $true
        }

        'Manual' {
            # Manual:{name} - Manually mounted paths (future implementation)
            throw "Manual paths not yet implemented"
        }

        default {
            throw "Unknown path prefix: $prefix"
        }
    }

    # Build physical path
    if ($result.Success) {
        $result.BasePath = $basePath
        $result.RelativePath = $relativePath

        if ($relativePath) {
            $result.PhysicalPath = Join-Path $basePath $relativePath
        } else {
            $result.PhysicalPath = $basePath
        }

        # Validate permission level
        $permissionHierarchy = @{
            'owner' = 3
            'write' = 2
            'read' = 1
        }

        $userLevel = $permissionHierarchy[$result.AccessLevel]
        $requiredLevel = $permissionHierarchy[$RequiredPermission]

        if ($userLevel -lt $requiredLevel) {
            $result.Success = $false
            $result.Message = "Insufficient permissions. Required: $RequiredPermission, Has: $($result.AccessLevel)"
        }
    }
}
catch {
    $result.Success = $false
    $result.Message = $_.Exception.Message
    Write-Error "Path resolution error: $_"
}

return $result
