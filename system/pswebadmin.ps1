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

. "$psscriptroot\init.ps1"
$ProjectRoot = $global:PSWebServer.Project_Root.Path
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
            $guid = [guid]::NewGuid().ToString()
            
            $dbPath = Join-Path ($PSScriptRoot | Split-Path -Parent) "PsWebHost_Data/pswebhost.db"
            $insertQuery = "INSERT INTO Users (UserID, Email, GUID, PasswordHash) VALUES ('$User', '$User', '$guid', '$passwordHash');"
            
            try {
                Invoke-PSWebSQLiteNonQuery -File $dbPath -Query $insertQuery -ErrorAction Stop
                Write-Host "User '$User' created successfully with GUID $guid."
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
    if ($SetPassword) { Write-Host "(Not Implemented) Setting password for $User..." }
    if ($ResetMfa) { Write-Host "(Not Implemented) Resetting MFA for $User..." }
    if ($AssignRole) { Write-Host "(Not Implemented) Assigning role $AssignRole to $User..." }

    return
}

if ($ListUsers) {
    Write-Host "Listing all users..."
    $dbPath = Join-Path ($PSScriptRoot | Split-Path -Parent) "PsWebHost_Data/pswebhost.db"
    Get-PSWebSQLiteData -File $dbPath -Query "SELECT UserID, GUID, Email FROM Users;" | Format-Table
    return
}

# Session Management
if ($ListSessions) { Write-Host "(Not Implemented) Listing active sessions..." }
if ($DropSession) { Write-Host "(Not Implemented) Dropping session $DropSession..." }

# Database Management
if ($ValidateDatabase) {
    Write-Host "Validating database schema..."
    $validatorScript = Join-Path $PSScriptRoot "db/sqlite/validatetables.ps1"
    $configFile = Join-Path $PSScriptRoot "db/sqlite/sqliteconfig.json"
    $databaseFile = Join-Path $PSScriptRoot "../PsWebHost_Data/pswebhost.db"
    & $validatorScript -DatabaseFile $databaseFile -ConfigFile $configFile -Verbose
}

if ($BackupDatabase) { Write-Host "(Not Implemented) Backing up database..." }
