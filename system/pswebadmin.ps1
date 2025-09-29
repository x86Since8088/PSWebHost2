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
$ScriptRoot = $PSScriptRoot
$ProjectRoot = (Resolve-Path (Join-Path $ScriptRoot '..')).Path
if ($null -eq $Global:PSWebServer) {
    # Dot-source the main init script to load the environment
    $InitScript = $ProjectRoot
    'system','init.ps1'|ForEach-Object{$InitScript = Join-Path $InitScript $_} 
    . $InitScript
} 
# If the environment is already loaded, we can get the ProjectRoot from the global variable
else {
    $ProjectRoot = $global:PSWebServer.Project_Root.Path
}

# Now that the environment is loaded, we can safely import modules
Import-Module "PSWebHost_Database"
Import-Module "PSWebHost_Authentication"


# --- Argument Completers ---
try {
    Register-ArgumentCompleter -CommandName 'pswebadmin.ps1' -ParameterName 'User' -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        # This requires Get-PSWebHostUsers to be a valid function in the loaded modules
        (Get-PSWebHostUsers) | Where-Object { $_ -like "*$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new("'$_'", $_, 'ParameterValue', $_)
        }
    }
} catch {
    Write-Warning "Argument completer registration failed: $_"
}

# --- Helper for SecureString to PlainText ---
function ConvertTo-PlainText {
    param([System.Security.SecureString]$SecureString)
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}


# --- Main Logic ---

# User Management
if ($PSBoundParameters.ContainsKey('User')) {
    $userObj = Get-PSWebHostUser -Email $User

    if ($Create) {
        if ($userObj) {
            Write-Error "User '$User' already exists."
        } else {
            Write-Verbose "Creating new user: $User..."
            $password = Read-Host -Prompt "Enter password for $User" -AsSecureString
            $passwordConfirm = Read-Host -Prompt "Confirm password" -AsSecureString

            $plainPassword = ConvertTo-PlainText -SecureString $password
            $plainPasswordConfirm = ConvertTo-PlainText -SecureString $passwordConfirm

            if ($plainPassword -ne $plainPasswordConfirm) {
                Write-Error "Passwords do not match."
                return
            }

            try {
                $newUser = New-PSWebHostUser -Email $User -Password $plainPassword -ErrorAction Stop
                Write-Verbose "User ' $($newUser.Email)' created successfully with UserID $($newUser.UserID)."
            } catch {
                Write-Error "Failed to create user. Error: $($_.Exception.Message)"
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
        Write-Verbose "Displaying details for user: $User"
        $userObj | Format-List | Out-String | Write-Output
    }

    if ($SetPassword) {
        Write-Verbose "Setting new password for user '$User'..."
        $password = Read-Host -Prompt "Enter new password for $User" -AsSecureString
        $passwordConfirm = Read-Host -Prompt "Confirm new password" -AsSecureString
        
        $plainPassword = ConvertTo-PlainText -SecureString $password
        $plainPasswordConfirm = ConvertTo-PlainText -SecureString $passwordConfirm

        if ($plainPassword -ne $plainPasswordConfirm) {
            Write-Error "Passwords do not match."
            return
        }
        
        try {
            Set-PSWebHostUserPassword -UserID $userObj.UserID -Password $plainPassword -ErrorAction Stop
            Write-Verbose "Password for user '$User' has been updated successfully."
        } catch {
            Write-Error "Failed to update password. Error: $($_.Exception.Message)"
        }
    }
    if ($ResetMfa) {
        Write-Warning "The -ResetMfa feature is not implemented yet."
        # TODO: Implement MFA reset logic
        # Write-Verbose "Resetting MFA for user '$User'..."
        # Remove-PSWebAuthProvider -UserID $User -Provider 'tokenauthenticator'
        # Write-Verbose "MFA has been reset. The user can re-register on their next login."
    }
    if ($AssignRole) {
        Write-Warning "The -AssignRole feature is not implemented yet."
        # TODO: Implement role assignment logic. Requires Set-RoleForPrincipal function.
        # Write-Verbose "Assigning role '$AssignRole' to user '$User'..."
        # Set-RoleForPrincipal -PrincipalID $userObj.ID -RoleName $AssignRole
        # Write-Verbose "Role assigned."
    }
    if ($RemoveRole) {
        Write-Warning "The -RemoveRole feature is not implemented yet."
        # TODO: Implement role removal logic. Requires Remove-RoleForPrincipal function.
        # Write-Verbose "Removing role '$RemoveRole' from user '$User'..."
        # Remove-RoleForPrincipal -PrincipalID $userObj.ID -RoleName $RemoveRole
        # Write-Verbose "Role removed."
    }
    if ($AddToGroup) {
        Write-Warning "The -AddToGroup feature is not implemented yet."
        # TODO: Implement group logic.
        # Write-Verbose "Adding user '$User' to group '$AddToGroup'..."
        # $group = Get-PSWebGroup -Name $AddToGroup
        # if ($group) {
        #     Add-UserToGroup -UserID $userObj.ID -GroupID $group.GroupID
        #     Write-Verbose "User added to group."
        # } else {
        #     Write-Error "Group '$AddToGroup' not found."
        # }
    }
    if ($RemoveFromGroup) {
        Write-Warning "The -RemoveFromGroup feature is not implemented yet."
        # TODO: Implement group logic.
        # Write-Verbose "Removing user '$User' from group '$RemoveFromGroup'..."
        # $group = Get-PSWebGroup -Name $RemoveFromGroup
        # if ($group) {
        #     Remove-UserFromGroup -UserID $userObj.ID -GroupID $group.GroupID
        #     Write-Verbose "User removed from group."
        # } else {
        #     Write-Error "Group '$RemoveFromGroup' not found."
        # }
    }

    return
}

if ($ListUsers) {
    Write-Verbose "Listing all users..."
    Get-PSWebHostUser -Listall | Select-Object UserID, Email | Format-Table | Out-String | Write-Output
    return
}

# Session Management
if ($ListSessions) {
    Write-Verbose "Listing all active sessions..."
    $dbPath = Join-Path ($PSScriptRoot | Split-Path -Parent) "PsWebHost_Data/pswebhost.db"
    Get-PSWebSQLiteData -File $dbPath -Query "SELECT SessionID, UserID, Provider, datetime(AuthenticationTime, 'unixepoch') as AuthTime, UserAgent FROM LoginSessions;" | Format-Table | Out-String | Write-Output
}
if ($DropSession) {
    Write-Verbose "Dropping session '$DropSession'..."
    $dbPath = Join-Path ($PSScriptRoot | Split-Path -Parent) "PsWebHost_Data/pswebhost.db"
    Invoke-PSWebSQLiteNonQuery -File $dbPath -Query "DELETE FROM LoginSessions WHERE SessionID = '$DropSession'"
    Write-Verbose "Session dropped."
}

# Database Management
if ($ValidateDatabase) {
    Write-Verbose "Validating database schema..."
    $validatorScript = Join-Path $PSScriptRoot "db/sqlite/validatetables.ps1"
    $configFile = Join-Path $PSScriptRoot "db/sqlite/sqliteconfig.json"
    $databaseFile = Join-Path $PSScriptRoot "../PsWebHost_Data/pswebhost.db"
    & $validatorScript -DatabaseFile $databaseFile -ConfigFile $configFile -Verbose
}

if ($BackupDatabase) {
    Write-Verbose "Backing up database..."
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
        Write-Verbose "Database successfully backed up to: $backupPath"
    } catch {
        Write-Error "Failed to back up database. Error: $($_.Exception.Message)"
    }
}