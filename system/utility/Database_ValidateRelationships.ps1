# Database_ValidateRelationships.ps1
# Validates referential integrity and relationship consistency in the database

[CmdletBinding()]
param(
    [switch]$FixOrphans,
    [switch]$Detailed
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[Database_ValidateRelationships.ps1]'
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Database Relationship Validation" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$issues = @()
$orphansFound = 0
$orphansFixed = 0

# 1. Check auth_user_provider -> Users
Write-Host "[1/7] Validating auth_user_provider -> Users..." -ForegroundColor Yellow
$query = @"
SELECT ap.UserID, ap.provider
FROM auth_user_provider ap
LEFT JOIN Users u ON ap.UserID = u.UserID
WHERE u.UserID IS NULL;
"@
$orphanProviders = Get-PSWebSQLiteData -File $dbFile -Query $query
if ($orphanProviders) {
    $count = @($orphanProviders).Count
    $orphansFound += $count
    $issues += "Found $count orphaned auth_user_provider records (UserID not in Users)"

    if ($Detailed) {
        $orphanProviders | ForEach-Object {
            Write-Host "  - UserID: $($_.UserID), Provider: $($_.provider)" -ForegroundColor Red
        }
    }

    if ($FixOrphans) {
        foreach ($orphan in $orphanProviders) {
            $safeUserID = Sanitize-SqlQueryString -String $orphan.UserID
            $safeProvider = Sanitize-SqlQueryString -String $orphan.provider
            $deleteQuery = "DELETE FROM auth_user_provider WHERE UserID = '$safeUserID' AND provider = '$safeProvider';"
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteQuery
            $orphansFixed++
        }
        Write-Host "  ✓ Fixed $count orphaned records" -ForegroundColor Green
    }
} else {
    Write-Host "  ✓ No issues found" -ForegroundColor Green
}

# 2. Check User_Groups_Map -> Users
Write-Host "[2/7] Validating User_Groups_Map -> Users..." -ForegroundColor Yellow
$query = @"
SELECT ugm.UserID, ugm.GroupID
FROM User_Groups_Map ugm
LEFT JOIN Users u ON ugm.UserID = u.UserID
WHERE u.UserID IS NULL;
"@
$orphanUserMaps = Get-PSWebSQLiteData -File $dbFile -Query $query
if ($orphanUserMaps) {
    $count = @($orphanUserMaps).Count
    $orphansFound += $count
    $issues += "Found $count orphaned User_Groups_Map records (UserID not in Users)"

    if ($Detailed) {
        $orphanUserMaps | ForEach-Object {
            Write-Host "  - UserID: $($_.UserID), GroupID: $($_.GroupID)" -ForegroundColor Red
        }
    }

    if ($FixOrphans) {
        foreach ($orphan in $orphanUserMaps) {
            $safeUserID = Sanitize-SqlQueryString -String $orphan.UserID
            $safeGroupID = Sanitize-SqlQueryString -String $orphan.GroupID
            $deleteQuery = "DELETE FROM User_Groups_Map WHERE UserID = '$safeUserID' AND GroupID = '$safeGroupID';"
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteQuery
            $orphansFixed++
        }
        Write-Host "  ✓ Fixed $count orphaned records" -ForegroundColor Green
    }
} else {
    Write-Host "  ✓ No issues found" -ForegroundColor Green
}

# 3. Check User_Groups_Map -> User_Groups
Write-Host "[3/7] Validating User_Groups_Map -> User_Groups..." -ForegroundColor Yellow
$query = @"
SELECT ugm.UserID, ugm.GroupID
FROM User_Groups_Map ugm
LEFT JOIN User_Groups g ON ugm.GroupID = g.GroupID
WHERE g.GroupID IS NULL;
"@
$orphanGroupMaps = Get-PSWebSQLiteData -File $dbFile -Query $query
if ($orphanGroupMaps) {
    $count = @($orphanGroupMaps).Count
    $orphansFound += $count
    $issues += "Found $count orphaned User_Groups_Map records (GroupID not in User_Groups)"

    if ($Detailed) {
        $orphanGroupMaps | ForEach-Object {
            Write-Host "  - UserID: $($_.UserID), GroupID: $($_.GroupID)" -ForegroundColor Red
        }
    }

    if ($FixOrphans) {
        foreach ($orphan in $orphanGroupMaps) {
            $safeUserID = Sanitize-SqlQueryString -String $orphan.UserID
            $safeGroupID = Sanitize-SqlQueryString -String $orphan.GroupID
            $deleteQuery = "DELETE FROM User_Groups_Map WHERE UserID = '$safeUserID' AND GroupID = '$safeGroupID';"
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteQuery
            $orphansFixed++
        }
        Write-Host "  ✓ Fixed $count orphaned records" -ForegroundColor Green
    }
} else {
    Write-Host "  ✓ No issues found" -ForegroundColor Green
}

# 4. Check PSWeb_Roles (User) -> Users
Write-Host "[4/7] Validating PSWeb_Roles (User) -> Users..." -ForegroundColor Yellow
$query = @"
SELECT r.PrincipalID, r.RoleName
FROM PSWeb_Roles r
LEFT JOIN Users u ON r.PrincipalID = u.UserID
WHERE r.PrincipalType = 'User' AND u.UserID IS NULL;
"@
$orphanUserRoles = Get-PSWebSQLiteData -File $dbFile -Query $query
if ($orphanUserRoles) {
    $count = @($orphanUserRoles).Count
    $orphansFound += $count
    $issues += "Found $count orphaned PSWeb_Roles records (User PrincipalID not in Users)"

    if ($Detailed) {
        $orphanUserRoles | ForEach-Object {
            Write-Host "  - PrincipalID: $($_.PrincipalID), RoleName: $($_.RoleName)" -ForegroundColor Red
        }
    }

    if ($FixOrphans) {
        foreach ($orphan in $orphanUserRoles) {
            $safePrincipalID = Sanitize-SqlQueryString -String $orphan.PrincipalID
            $safeRoleName = Sanitize-SqlQueryString -String $orphan.RoleName
            $deleteQuery = "DELETE FROM PSWeb_Roles WHERE PrincipalID = '$safePrincipalID' AND RoleName = '$safeRoleName';"
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteQuery
            $orphansFixed++
        }
        Write-Host "  ✓ Fixed $count orphaned records" -ForegroundColor Green
    }
} else {
    Write-Host "  ✓ No issues found" -ForegroundColor Green
}

# 5. Check PSWeb_Roles (Group) -> User_Groups
Write-Host "[5/7] Validating PSWeb_Roles (Group) -> User_Groups..." -ForegroundColor Yellow
$query = @"
SELECT r.PrincipalID, r.RoleName
FROM PSWeb_Roles r
LEFT JOIN User_Groups g ON r.PrincipalID = g.GroupID
WHERE r.PrincipalType = 'Group' AND g.GroupID IS NULL;
"@
$orphanGroupRoles = Get-PSWebSQLiteData -File $dbFile -Query $query
if ($orphanGroupRoles) {
    $count = @($orphanGroupRoles).Count
    $orphansFound += $count
    $issues += "Found $count orphaned PSWeb_Roles records (Group PrincipalID not in User_Groups)"

    if ($Detailed) {
        $orphanGroupRoles | ForEach-Object {
            Write-Host "  - PrincipalID: $($_.PrincipalID), RoleName: $($_.RoleName)" -ForegroundColor Red
        }
    }

    if ($FixOrphans) {
        foreach ($orphan in $orphanGroupRoles) {
            $safePrincipalID = Sanitize-SqlQueryString -String $orphan.PrincipalID
            $safeRoleName = Sanitize-SqlQueryString -String $orphan.RoleName
            $deleteQuery = "DELETE FROM PSWeb_Roles WHERE PrincipalID = '$safePrincipalID' AND RoleName = '$safeRoleName';"
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteQuery
            $orphansFixed++
        }
        Write-Host "  ✓ Fixed $count orphaned records" -ForegroundColor Green
    }
} else {
    Write-Host "  ✓ No issues found" -ForegroundColor Green
}

# 6. Check LoginSessions -> Users
Write-Host "[6/7] Validating LoginSessions -> Users..." -ForegroundColor Yellow
$query = @"
SELECT ls.SessionID, ls.UserID
FROM LoginSessions ls
LEFT JOIN Users u ON ls.UserID = u.UserID
WHERE u.UserID IS NULL;
"@
$orphanSessions = Get-PSWebSQLiteData -File $dbFile -Query $query
if ($orphanSessions) {
    $count = @($orphanSessions).Count
    $orphansFound += $count
    $issues += "Found $count orphaned LoginSessions records (UserID not in Users)"

    if ($Detailed) {
        $orphanSessions | ForEach-Object {
            Write-Host "  - SessionID: $($_.SessionID), UserID: $($_.UserID)" -ForegroundColor Red
        }
    }

    if ($FixOrphans) {
        foreach ($orphan in $orphanSessions) {
            $safeSessionID = Sanitize-SqlQueryString -String $orphan.SessionID
            $deleteQuery = "DELETE FROM LoginSessions WHERE SessionID = '$safeSessionID';"
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteQuery
            $orphansFixed++
        }
        Write-Host "  ✓ Fixed $count orphaned records" -ForegroundColor Green
    }
} else {
    Write-Host "  ✓ No issues found" -ForegroundColor Green
}

# 7. Check User_Data -> Users (for user-related data, not group data)
Write-Host "[7/7] Validating User_Data -> Users/Groups..." -ForegroundColor Yellow
$query = @"
SELECT ud.ID, ud.Name
FROM User_Data ud
LEFT JOIN Users u ON ud.ID = u.UserID
LEFT JOIN User_Groups g ON ud.ID = g.GroupID
WHERE u.UserID IS NULL AND g.GroupID IS NULL;
"@
$orphanData = Get-PSWebSQLiteData -File $dbFile -Query $query
if ($orphanData) {
    $count = @($orphanData).Count
    $orphansFound += $count
    $issues += "Found $count orphaned User_Data records (ID not in Users or User_Groups)"

    if ($Detailed) {
        $orphanData | ForEach-Object {
            Write-Host "  - ID: $($_.ID), Name: $($_.Name)" -ForegroundColor Red
        }
    }

    if ($FixOrphans) {
        foreach ($orphan in $orphanData) {
            $safeID = Sanitize-SqlQueryString -String $orphan.ID
            $safeName = Sanitize-SqlQueryString -String $orphan.Name
            $deleteQuery = "DELETE FROM User_Data WHERE ID = '$safeID' AND Name = '$safeName';"
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteQuery
            $orphansFixed++
        }
        Write-Host "  ✓ Fixed $count orphaned records" -ForegroundColor Green
    }
} else {
    Write-Host "  ✓ No issues found" -ForegroundColor Green
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Validation Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($issues.Count -eq 0) {
    Write-Host "✓ All relationship validations passed!" -ForegroundColor Green
    Write-Host "  Database integrity is intact." -ForegroundColor Green
} else {
    Write-Host "✗ Found $($issues.Count) relationship issue(s):" -ForegroundColor Red
    $issues | ForEach-Object {
        Write-Host "  - $_" -ForegroundColor Yellow
    }
    Write-Host "`nTotal orphaned records found: $orphansFound" -ForegroundColor Yellow

    if ($FixOrphans) {
        Write-Host "Total orphaned records fixed: $orphansFixed" -ForegroundColor Green
    } else {
        Write-Host "`nRun with -FixOrphans switch to automatically remove orphaned records" -ForegroundColor Cyan
    }
}

Write-Host "`n========================================`n" -ForegroundColor Cyan

# Return summary object
return [PSCustomObject]@{
    TotalIssues = $issues.Count
    OrphansFound = $orphansFound
    OrphansFixed = $orphansFixed
    Issues = $issues
    DatabaseIntact = ($issues.Count -eq 0)
}
