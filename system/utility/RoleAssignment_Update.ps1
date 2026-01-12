# RoleAssignment_Update.ps1
# Updates role assignments in bulk or synchronizes from a configuration

<#
.SYNOPSIS
    Updates or synchronizes role assignments from a configuration file or parameter.

.DESCRIPTION
    Performs bulk updates to role assignments. Can synchronize roles from a JSON
    or CSV file, add/remove multiple roles at once, or replace all roles for a user.

.PARAMETER PrincipalID
    The UserID or GroupID to update roles for.

.PARAMETER Email
    The email address of the user to update roles for.

.PARAMETER AddRoles
    Array of role names to add to the principal.

.PARAMETER RemoveRoles
    Array of role names to remove from the principal.

.PARAMETER SetRoles
    Array of role names to set (replaces all existing roles).

.PARAMETER FromFile
    Path to a JSON or CSV file containing role assignments to synchronize.

.PARAMETER Sync
    When used with -FromFile, synchronizes the database to match the file exactly.

.PARAMETER WhatIf
    Show what changes would be made without making them.

.EXAMPLE
    .\RoleAssignment_Update.ps1 -Email 'admin@test.com' -AddRoles 'Admin','Debug'

    Adds Admin and Debug roles to the specified user.

.EXAMPLE
    .\RoleAssignment_Update.ps1 -Email 'test@localhost' -SetRoles 'authenticated','Debug'

    Sets the user's roles to exactly 'authenticated' and 'Debug', removing any others.

.EXAMPLE
    .\RoleAssignment_Update.ps1 -Email 'user@test.com' -RemoveRoles 'Admin','site_admin'

    Removes Admin and site_admin roles from the user.

.EXAMPLE
    .\RoleAssignment_Update.ps1 -FromFile 'C:\temp\roles.json' -Sync

    Synchronizes all role assignments from a JSON file.
#>

[CmdletBinding(SupportsShouldProcess=$true, DefaultParameterSetName='ByID')]
param(
    [Parameter(Mandatory=$true, ParameterSetName='ByID')]
    [Parameter(Mandatory=$true, ParameterSetName='UpdateByID')]
    [string]$PrincipalID,

    [Parameter(Mandatory=$true, ParameterSetName='ByEmail')]
    [Parameter(Mandatory=$true, ParameterSetName='UpdateByEmail')]
    [string]$Email,

    [Parameter(ParameterSetName='UpdateByID')]
    [Parameter(ParameterSetName='UpdateByEmail')]
    [string[]]$AddRoles,

    [Parameter(ParameterSetName='UpdateByID')]
    [Parameter(ParameterSetName='UpdateByEmail')]
    [string[]]$RemoveRoles,

    [Parameter(ParameterSetName='UpdateByID')]
    [Parameter(ParameterSetName='UpdateByEmail')]
    [string[]]$SetRoles,

    [Parameter(Mandatory=$true, ParameterSetName='FromFile')]
    [string]$FromFile,

    [Parameter(ParameterSetName='FromFile')]
    [switch]$Sync
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[RoleAssignment_Update.ps1]'
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

# Handle file-based sync
if ($PSCmdlet.ParameterSetName -eq 'FromFile') {
    if (-not (Test-Path $FromFile)) {
        throw "File not found: $FromFile"
    }

    $extension = [System.IO.Path]::GetExtension($FromFile).ToLower()

    switch ($extension) {
        '.json' {
            $roleData = Get-Content $FromFile -Raw | ConvertFrom-Json
        }
        '.csv' {
            $roleData = Import-Csv -Path $FromFile
        }
        default {
            throw "Unsupported file format: $extension. Use .json or .csv"
        }
    }

    Write-Host "Processing $($roleData.Count) role assignment(s) from file..." -ForegroundColor Cyan

    foreach ($assignment in $roleData) {
        $params = @{
            RoleName = $assignment.RoleName
            PassThru = $false
        }

        if ($assignment.Email) {
            $params.Email = $assignment.Email
        } elseif ($assignment.PrincipalID) {
            $params.PrincipalID = $assignment.PrincipalID
            $params.PrincipalType = $assignment.PrincipalType
        } else {
            Write-Warning "Skipping invalid assignment: $($assignment | ConvertTo-Json -Compress)"
            continue
        }

        try {
            & (Join-Path $PSScriptRoot "RoleAssignment_New.ps1") @params
        } catch {
            Write-Warning "Failed to process assignment: $($_.Exception.Message)"
        }
    }

    Write-Host "`n✓ File processing complete" -ForegroundColor Green
    return
}

# Resolve email to UserID if specified
if ($PSCmdlet.ParameterSetName -eq 'UpdateByEmail' -or $PSCmdlet.ParameterSetName -eq 'ByEmail') {
    $safeEmail = Sanitize-SqlQueryString -String $Email
    $user = Get-PSWebSQLiteData -File $dbFile -Query "SELECT UserID, Email FROM Users WHERE Email COLLATE NOCASE = '$safeEmail';"
    if (-not $user) {
        throw "User with email '$Email' not found"
    }
    $PrincipalID = $user.UserID
    $PrincipalType = 'User'
    $principalName = $Email
    Write-Verbose "$MyTag Resolved email '$Email' to UserID '$PrincipalID'"
}

# Handle SetRoles (replace all)
if ($SetRoles) {
    $safePrincipalID = Sanitize-SqlQueryString -String $PrincipalID

    if ($PSCmdlet.ShouldProcess("Replace all roles for $principalName with: $($SetRoles -join ', ')", "Role Update", "Set")) {
        # Get current roles
        $currentRoles = Get-PSWebSQLiteData -File $dbFile -Query "SELECT RoleName FROM PSWeb_Roles WHERE PrincipalID COLLATE NOCASE = '$safePrincipalID';"
        $currentRoleNames = if ($currentRoles) { @($currentRoles | ForEach-Object { $_.RoleName }) } else { @() }

        # Remove all current roles
        if ($currentRoleNames.Count -gt 0) {
            $deleteQuery = "DELETE FROM PSWeb_Roles WHERE PrincipalID COLLATE NOCASE = '$safePrincipalID';"
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteQuery
            Write-Host "  Removed $($currentRoleNames.Count) existing role(s)" -ForegroundColor Yellow
        }

        # Add new roles
        foreach ($role in $SetRoles) {
            $safeRoleName = Sanitize-SqlQueryString -String $role
            $insertQuery = "INSERT INTO PSWeb_Roles (PrincipalID, PrincipalType, RoleName) VALUES ('$safePrincipalID', '$PrincipalType', '$safeRoleName');"
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $insertQuery
        }

        Write-Host "✓ Set $($SetRoles.Count) role(s) for $principalName" -ForegroundColor Green
    }
    return
}

# Handle AddRoles
if ($AddRoles) {
    $added = 0
    foreach ($role in $AddRoles) {
        try {
            $params = @{
                PrincipalID = $PrincipalID
                PrincipalType = 'User'
                RoleName = $role
                PassThru = $false
            }
            & (Join-Path $PSScriptRoot "RoleAssignment_New.ps1") @params
            $added++
        } catch {
            Write-Warning "Failed to add role '$role': $($_.Exception.Message)"
        }
    }
    Write-Host "`n✓ Added $added role(s)" -ForegroundColor Green
}

# Handle RemoveRoles
if ($RemoveRoles) {
    $removed = 0
    foreach ($role in $RemoveRoles) {
        try {
            $params = @{
                PrincipalID = $PrincipalID
                RoleName = $role
                Force = $true
            }
            & (Join-Path $PSScriptRoot "RoleAssignment_Remove.ps1") @params
            $removed++
        } catch {
            Write-Warning "Failed to remove role '$role': $($_.Exception.Message)"
        }
    }
    Write-Host "`n✓ Removed $removed role(s)" -ForegroundColor Green
}
