<#
.SYNOPSIS
  Administration script for PsWebHost.

.DESCRIPTION
  This script is the central command-line utility for managing the PsWebHost instance,
  including users, roles, sessions, and database maintenance.
#>

[CmdletBinding()]
param(
    # User Management
    [string]$User,
    [switch]$ListUsers,
    [switch]$Create,
    [switch]$SetPassword,
    [switch]$ResetMfa,
    [string]$AssignRole,
    [string]$RemoveRole,
    [string]$AddToGroup,
    [string]$RemoveFromGroup,

    # Session Management
    [switch]$ListSessions,
    [string]$DropSession,

    # Database Management
    [switch]$ValidateDatabase,
    [switch]$BackupDatabase
)

if ($null -eq $Global:PSWebServer) {
    # Resolve the project root, which is one level up from this script's location
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot -Path '..')).Path
    # Dot-source the main init script to load the environment
    . (Join-Path $ProjectRoot 'system', 'init.ps1')
} 
# If the environment is already loaded, we can get the ProjectRoot from the global variable
else {
    $ProjectRoot = $global:PSWebServer.Project_Root.Path
}

# Now that the environment is loaded, we can safely import modules
Import-Module "$ProjectRoot\modules\PSWebHost_Database"

# --- Argument Completers ---
try {
    Register-ArgumentCompleter -CommandName 'pswebadmin.ps1' -ParameterName 'User' -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        # This requires Get-PSWebHostUsers to be a valid function in the loaded modules
        # Example: Get-PSWebSQLiteData -File 'pswebhost.db' -Query "SELECT UserID FROM Users;" | Select-Object -ExpandProperty UserID
        $dbPath = Join-Path ($PSScriptRoot | Split-Path -Parent) "PsWebHost_Data/pswebhost.db"
        (Get-PSWebSQLiteData -File $dbPath -Query "SELECT UserID FROM Users WHERE UserID LIKE '%$wordToComplete%';").UserID | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new("'$_'", $_, 'ParameterValue', $_)
        }
    }
} catch {
    Write-Warning "Argument completer registration failed: $_"
}

# --- Main Logic ---

# User Management
if ($PSBoundParameters.ContainsKey('User')) {
    $userObj = Get-PSWebHostUser -Email $User # Assumes this function exists in a module

    if ($Create) {
        if ($userObj) {
            Write-Error "User '$User' already exists."
        } else {
            Write-Host "Creating new user: $User..."
            $password = Read-Host -Prompt "Enter password for $User" -AsSecureString
            $passwordConfirm = Read-Host -Prompt "Confirm password" -AsSecureString

            if ($password.ToString() -ne $passwordConfirm.ToString()) { # Note: This comparison is illustrative.
                Write-Error "Passwords do not match."
                return
            }

            $passwordHash = Hash-String -String (ConvertTo-UnsecureString -SecureString $password) # Assumes Hash-String exists
            $id = [guid]::NewGuid().ToString()
            
            $dbPath = Join-Path ($PSScriptRoot | Split-Path -Parent) "PsWebHost_Data/pswebhost.db"
            $userData = @{
                ID = $id
                UserID = $User
                Email = $User
                PasswordHash = $passwordHash
            }
            
            try {
                Invoke-PSWebSQLiteNonQuery -File $dbPath -Verb 'INSERT' -TableName 'Users' -Data $userData -ErrorAction Stop
                Write-Host "User '$User' created successfully with ID $id."
            } catch {
                Write-Error "Failed to create user in database. Error: $($_.Exception.Message)"
            }
        }
        return
    }

    if (-not $userObj) {
        Write-Error "User not found: $User"
        return
    }

    # If no other action is specified, just display user info
    if ($PSBoundParameters.Count -eq 1) {
        Write-Host "Displaying details for user: $User"
        $userObj | Format-List
    }

    # Placeholder for other user actions
    if ($SetPassword) {
        Write-Host "Setting new password for user '$User'..."
        $password = Read-Host -Prompt "Enter new password for $User" -AsSecureString
        $passwordConfirm = Read-Host -Prompt "Confirm new password" -AsSecureString

        if ($password.ToString() -ne $passwordConfirm.ToString()) { # Note: This comparison is illustrative.
            Write-Error "Passwords do not match."
            return
        }

        $passwordHash = Hash-String -String (ConvertTo-UnsecureString -SecureString $password) # Assumes Hash-String exists
        $dbPath = Join-Path ($PSScriptRoot | Split-Path -Parent) "PsWebHost_Data/pswebhost.db"
        
        try {
            Invoke-PSWebSQLiteNonQuery -File $dbPath -Verb 'UPDATE' -TableName 'Users' -Data @{ PasswordHash = $passwordHash } -Where "UserID = '$User'" -ErrorAction Stop
            Write-Host "Password for user '$User' has been updated successfully."
        } catch {
            Write-Error "Failed to update password in database. Error: $($_.Exception.Message)"
        }
    }
    if ($ResetMfa) {
        Write-Host "Resetting MFA for user '$User'..."
        Remove-PSWebAuthProvider -UserID $User -Provider 'tokenauthenticator'
        Write-Host "MFA has been reset. The user can re-register on their next login."
    }
    if ($AssignRole) {
        Write-Host "Assigning role '$AssignRole' to user '$User'..."
        Set-RoleForPrincipal -PrincipalID $userObj.ID -RoleName $AssignRole
        Write-Host "Role assigned."
    }
    if ($RemoveRole) {
        Write-Host "Removing role '$RemoveRole' from user '$User'..."
        Remove-RoleForPrincipal -PrincipalID $userObj.ID -RoleName $RemoveRole
        Write-Host "Role removed."
    }
    if ($AddToGroup) {
        Write-Host "Adding user '$User' to group '$AddToGroup'..."
        $group = Get-PSWebGroup -Name $AddToGroup
        if ($group) {
            Add-UserToGroup -UserID $userObj.ID -GroupID $group.GroupID
            Write-Host "User added to group."
        } else {
            Write-Error "Group '$AddToGroup' not found."
        }
    }
    if ($RemoveFromGroup) {
        Write-Host "Removing user '$User' from group '$RemoveFromGroup'..."
        $group = Get-PSWebGroup -Name $RemoveFromGroup
        if ($group) {
            Remove-UserFromGroup -UserID $userObj.ID -GroupID $group.GroupID # Assumes this function will be created
            Write-Host "User removed from group."
        } else {
            Write-Error "Group '$RemoveFromGroup' not found."
        }
    }

    return
}

if ($ListUsers) {
    Write-Host "Listing all users..."
    $dbPath = Join-Path ($PSScriptRoot | Split-Path -Parent) "PsWebHost_Data/pswebhost.db"
    Get-PSWebSQLiteData -File $dbPath -Query "SELECT ID, UserID, Email FROM Users;" | Format-Table
    return
}

# Session Management
if ($ListSessions) {
    Write-Host "Listing all active sessions..."
    $dbPath = Join-Path ($PSScriptRoot | Split-Path -Parent) "PsWebHost_Data/pswebhost.db"
    Get-PSWebSQLiteData -File $dbPath -Query "SELECT SessionID, UserID, Provider, datetime(AuthenticationTime, 'unixepoch') as AuthTime, UserAgent FROM LoginSessions;" | Format-Table
}
if ($DropSession) {
    Write-Host "Dropping session '$DropSession'..."
    $dbPath = Join-Path ($PSScriptRoot | Split-Path -Parent) "PsWebHost_Data/pswebhost.db"
    Invoke-PSWebSQLiteNonQuery -File $dbPath -Verb 'DELETE' -TableName 'LoginSessions' -Where "SessionID = '$DropSession'"
    Write-Host "Session dropped."
}

# Database Management
if ($ValidateDatabase) {
    Write-Host "Validating database schema..."
    $validatorScript = Join-Path $PSScriptRoot "db/sqlite/validatetables.ps1"
    $configFile = Join-Path $PSScriptRoot "db/sqlite/sqliteconfig.json"
    $databaseFile = Join-Path $PSScriptRoot "../PsWebHost_Data/pswebhost.db"
    & $validatorScript -DatabaseFile $databaseFile -ConfigFile $configFile -Verbose
}

if ($BackupDatabase) {
    Write-Host "Backing up database..."
    $dbPath = Join-Path $ProjectRoot "PsWebHost_Data/pswebhost.db"
    $backupDir = Join-Path $ProjectRoot "backups"
    
    if (-not (Test-Path $backupDir)) {
        New-Item -Path $backupDir -ItemType Directory | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    $backupFileName = "pswebhost_backup_$timestamp.db"
    $backupPath = Join-Path $backupDir $backupFileName

    try {
        Copy-Item -Path $dbPath -Destination $backupPath -ErrorAction Stop
        Write-Host "Database successfully backed up to: $backupPath"
    } catch {
        Write-Error "Failed to back up database. Error: $($_.Exception.Message)"
    }
}
