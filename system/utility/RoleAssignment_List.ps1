# RoleAssignment_List.ps1
# Comprehensive listing of role assignments with statistics

<#
.SYNOPSIS
    Lists all role assignments with statistics and filtering options.

.DESCRIPTION
    Provides a comprehensive view of role assignments in the system. Shows
    statistics, supports filtering, and can group by role or principal.

.PARAMETER GroupBy
    Group results by 'Role', 'User', 'Group', or 'None'. Default is 'None'.

.PARAMETER ShowStatistics
    Display summary statistics about role assignments.

.PARAMETER RoleFilter
    Filter to show only assignments for specific role(s). Supports wildcards.

.PARAMETER UserFilter
    Filter to show only assignments for users matching pattern. Supports wildcards.

.PARAMETER IncludeInactive
    Include assignments for users that are inactive or disabled.

.PARAMETER Export
    Export results to CSV file at specified path.

.EXAMPLE
    .\RoleAssignment_List.ps1

    List all role assignments in a table format.

.EXAMPLE
    .\RoleAssignment_List.ps1 -ShowStatistics

    Show role assignment statistics and summary.

.EXAMPLE
    .\RoleAssignment_List.ps1 -GroupBy Role

    List all assignments grouped by role name.

.EXAMPLE
    .\RoleAssignment_List.ps1 -RoleFilter 'Admin' -ShowStatistics

    Show only Admin role assignments with statistics.

.EXAMPLE
    .\RoleAssignment_List.ps1 -UserFilter 'test@*' -Export 'C:\temp\roles.csv'

    Export all test user role assignments to CSV.
#>

[CmdletBinding()]
param(
    [ValidateSet('None', 'Role', 'User', 'Group')]
    [string]$GroupBy = 'None',

    [switch]$ShowStatistics,

    [string]$RoleFilter,

    [string]$UserFilter,

    [switch]$IncludeInactive,

    [string]$Export
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[RoleAssignment_List.ps1]'
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

# Build query
$query = @"
SELECT
    r.PrincipalID,
    r.PrincipalType,
    r.RoleName,
    CASE
        WHEN r.PrincipalType = 'User' THEN u.Email
        WHEN r.PrincipalType = 'Group' THEN g.Name
        ELSE 'Unknown'
    END as PrincipalName
FROM PSWeb_Roles r
LEFT JOIN Users u ON r.PrincipalID = u.UserID AND r.PrincipalType COLLATE NOCASE = 'User'
LEFT JOIN User_Groups g ON r.PrincipalID = g.GroupID AND r.PrincipalType COLLATE NOCASE = 'Group'
ORDER BY r.RoleName, r.PrincipalType, PrincipalName;
"@

Write-Verbose "$MyTag Executing query: $query"
$assignments = Get-PSWebSQLiteData -File $dbFile -Query $query

if (-not $assignments) {
    Write-Host "No role assignments found in the system." -ForegroundColor Yellow
    return
}

# Ensure it's an array
$assignments = @($assignments)

# Apply filters
if ($RoleFilter) {
    $assignments = $assignments | Where-Object { $_.RoleName -like $RoleFilter }
}

if ($UserFilter) {
    $assignments = $assignments | Where-Object { $_.PrincipalName -like $UserFilter }
}

if (-not $assignments -or $assignments.Count -eq 0) {
    Write-Host "No role assignments match the specified filters." -ForegroundColor Yellow
    return
}

# Show statistics if requested
if ($ShowStatistics) {
    Write-Host "`n=== Role Assignment Statistics ===" -ForegroundColor Cyan
    Write-Host "Total Assignments: $($assignments.Count)" -ForegroundColor White

    $userAssignments = @($assignments | Where-Object { $_.PrincipalType -eq 'User' })
    $groupAssignments = @($assignments | Where-Object { $_.PrincipalType -eq 'Group' })

    Write-Host "User Assignments: $($userAssignments.Count)" -ForegroundColor White
    Write-Host "Group Assignments: $($groupAssignments.Count)" -ForegroundColor White

    $uniqueRoles = $assignments | Select-Object -ExpandProperty RoleName -Unique
    Write-Host "Unique Roles: $($uniqueRoles.Count)" -ForegroundColor White

    $uniqueUsers = $assignments | Where-Object { $_.PrincipalType -eq 'User' } | Select-Object -ExpandProperty PrincipalID -Unique
    Write-Host "Users with Roles: $($uniqueUsers.Count)" -ForegroundColor White

    $uniqueGroups = $assignments | Where-Object { $_.PrincipalType -eq 'Group' } | Select-Object -ExpandProperty PrincipalID -Unique
    Write-Host "Groups with Roles: $($uniqueGroups.Count)" -ForegroundColor White

    Write-Host "`nRole Distribution:" -ForegroundColor Cyan
    $assignments | Group-Object RoleName | Sort-Object Count -Descending | ForEach-Object {
        Write-Host ("  {0,-20} : {1,3} assignment(s)" -f $_.Name, $_.Count)
    }
    Write-Host ""
}

# Group results if requested
switch ($GroupBy) {
    'Role' {
        Write-Host "`n=== Role Assignments (Grouped by Role) ===" -ForegroundColor Cyan
        $assignments | Group-Object RoleName | Sort-Object Name | ForEach-Object {
            Write-Host "`n[$($_.Name)]" -ForegroundColor Yellow
            $_.Group | Format-Table -Property PrincipalType, PrincipalName -AutoSize
        }
    }
    'User' {
        Write-Host "`n=== Role Assignments (Grouped by User) ===" -ForegroundColor Cyan
        $userAssignments = $assignments | Where-Object { $_.PrincipalType -eq 'User' }
        $userAssignments | Group-Object PrincipalName | Sort-Object Name | ForEach-Object {
            Write-Host "`n[$($_.Name)]" -ForegroundColor Yellow
            $_.Group | Format-Table -Property RoleName -AutoSize
        }
    }
    'Group' {
        Write-Host "`n=== Role Assignments (Grouped by Group) ===" -ForegroundColor Cyan
        $groupAssignments = $assignments | Where-Object { $_.PrincipalType -eq 'Group' }
        $groupAssignments | Group-Object PrincipalName | Sort-Object Name | ForEach-Object {
            Write-Host "`n[$($_.Name)]" -ForegroundColor Yellow
            $_.Group | Format-Table -Property RoleName -AutoSize
        }
    }
    'None' {
        Write-Host "`n=== Role Assignments ===" -ForegroundColor Cyan
        $assignments | Format-Table -Property RoleName, PrincipalType, PrincipalName -AutoSize
    }
}

# Export if requested
if ($Export) {
    $assignments | Select-Object RoleName, PrincipalType, PrincipalName, PrincipalID |
        Export-Csv -Path $Export -NoTypeInformation
    Write-Host "`n✓ Exported $($assignments.Count) assignments to: $Export" -ForegroundColor Green
}
