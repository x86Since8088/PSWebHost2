#Requires -RunAsAdministrator
# Account_AuthProvider_Windows_Set.ps1
# Updates a Windows-authenticated user account by ID
# Useful for updating account details after computer name changes

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [Alias('UserID')]
    [string]$ID,

    # Users table fields
    [Parameter(Mandatory=$false)]
    [string]$Email,

    [Parameter(Mandatory=$false)]
    [string]$Owner,

    [Parameter(Mandatory=$false)]
    [ValidateSet('User', 'Group', 'System')]
    [string]$OwnerType,

    # auth_user_provider fields
    [Parameter(Mandatory=$false)]
    [string]$UserName,

    [Parameter(Mandatory=$false)]
    [ValidateSet($true, $false, 1, 0)]
    [object]$Enabled,

    [Parameter(Mandatory=$false)]
    [ValidateSet($true, $false, 1, 0)]
    [object]$LockedOut,

    [Parameter(Mandatory=$false)]
    [string]$Expires,

    [Parameter(Mandatory=$false)]
    [string]$Data,

    # Control parameters
    [switch]$Force,

    [switch]$UpdateLocalUser,

    [Parameter(Mandatory=$false)]
    [string]$NewLocalPassword
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment (initializes SQLite and required modules)
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -InitializeEnvironmentOnly 3>$null 4>$null | Out-Null

$dbFile = Join-Path $ProjectRoot "PsWebHost_Data\pswebhost.db"

# Get current user details
$safeID = Sanitize-SqlQueryString -String $ID
$checkQuery = @"
SELECT u.*, ap.UserName, ap.provider, ap.created as ProviderCreated, ap.enabled, ap.locked_out, ap.expires, ap.data
FROM Users u
INNER JOIN auth_user_provider ap ON u.UserID = ap.UserID
WHERE u.UserID COLLATE NOCASE = '$safeID' AND ap.provider COLLATE NOCASE = 'Windows';
"@

Write-Verbose "Fetching current user data for ID: $ID"
$currentUser = Get-PSWebSQLiteData -File $dbFile -Query $checkQuery

if (-not $currentUser) {
    throw "User with ID '$ID' not found or is not a Windows provider account"
}

Write-Verbose "Current user data:"
Write-Verbose "  UserID: $($currentUser.UserID)"
Write-Verbose "  Email: $($currentUser.Email)"
Write-Verbose "  UserName: $($currentUser.UserName)"
Write-Verbose "  Owner: $($currentUser.Owner)"
Write-Verbose "  OwnerType: $($currentUser.OwnerType)"
Write-Verbose "  Enabled: $($currentUser.enabled)"
Write-Verbose "  LockedOut: $($currentUser.locked_out)"
Write-Verbose "  Expires: $($currentUser.expires)"

# Build update sets
$usersUpdates = @()
$providerUpdates = @()
$changes = @()

# Process Users table updates
if ($PSBoundParameters.ContainsKey('Email') -and $Email -ne $currentUser.Email) {
    # Check if new email is already taken
    $emailCheck = Get-PSWebHostUser -Email $Email
    if ($emailCheck -and $emailCheck.UserID -ne $ID) {
        throw "Email '$Email' is already in use by another user (UserID: $($emailCheck.UserID))"
    }
    $safeEmail = Sanitize-SqlQueryString -String $Email
    $usersUpdates += "Email = '$safeEmail'"
    $changes += "Email: '$($currentUser.Email)' → '$Email'"
}

if ($PSBoundParameters.ContainsKey('Owner') -and $Owner -ne $currentUser.Owner) {
    $safeOwner = Sanitize-SqlQueryString -String $Owner
    $usersUpdates += "Owner = '$safeOwner'"
    $changes += "Owner: '$($currentUser.Owner)' → '$Owner'"
}

if ($PSBoundParameters.ContainsKey('OwnerType') -and $OwnerType -ne $currentUser.OwnerType) {
    $safeOwnerType = Sanitize-SqlQueryString -String $OwnerType
    $usersUpdates += "OwnerType = '$safeOwnerType'"
    $changes += "OwnerType: '$($currentUser.OwnerType)' → '$OwnerType'"
}

# Process auth_user_provider table updates
if ($PSBoundParameters.ContainsKey('UserName') -and $UserName -ne $currentUser.UserName) {
    # Check if local Windows user exists with new name
    if ($UpdateLocalUser) {
        $oldLocalUser = Get-LocalUser -Name $currentUser.UserName -ErrorAction SilentlyContinue
        $newLocalUser = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue

        if (-not $oldLocalUser) {
            Write-Warning "Old local Windows user '$($currentUser.UserName)' does not exist. Proceeding with database update only."
        }
        elseif ($newLocalUser) {
            throw "Local Windows user '$UserName' already exists. Cannot rename."
        }
    }

    $safeUserName = Sanitize-SqlQueryString -String $UserName
    $providerUpdates += "UserName = '$safeUserName'"
    $changes += "UserName: '$($currentUser.UserName)' → '$UserName'"
}

if ($PSBoundParameters.ContainsKey('Enabled')) {
    $enabledValue = if ($Enabled -eq $true -or $Enabled -eq 1) { 1 } else { 0 }
    if ($enabledValue -ne $currentUser.enabled) {
        $providerUpdates += "enabled = $enabledValue"
        $changes += "Enabled: $($currentUser.enabled) → $enabledValue"
    }
}

if ($PSBoundParameters.ContainsKey('LockedOut')) {
    $lockedValue = if ($LockedOut -eq $true -or $LockedOut -eq 1) { 1 } else { 0 }
    if ($lockedValue -ne $currentUser.locked_out) {
        $providerUpdates += "locked_out = $lockedValue"
        $changes += "LockedOut: $($currentUser.locked_out) → $lockedValue"
    }
}

if ($PSBoundParameters.ContainsKey('Expires')) {
    $safeExpires = Sanitize-SqlQueryString -String $Expires
    $providerUpdates += "expires = '$safeExpires'"
    $changes += "Expires: '$($currentUser.expires)' → '$Expires'"
}

if ($PSBoundParameters.ContainsKey('Data')) {
    $safeData = Sanitize-SqlQueryString -String $Data
    $providerUpdates += "data = '$safeData'"
    $changes += "Data: Updated"
}

# Check if any changes were requested
if ($usersUpdates.Count -eq 0 -and $providerUpdates.Count -eq 0 -and -not $UpdateLocalUser) {
    Write-Warning "No changes specified. Account remains unchanged."
    return $currentUser
}

# Display proposed changes
if ($changes.Count -gt 0) {
    Write-Host "`nProposed changes for user: $($currentUser.Email) (ID: $ID)" -ForegroundColor Cyan
    foreach ($change in $changes) {
        Write-Host "  $change" -ForegroundColor Yellow
    }
    Write-Host ""
}

# Confirm changes unless -Force is used
$confirmed = $false
if ($Force) {
    $confirmed = $true
    Write-Verbose "Force parameter specified, skipping confirmation"
}
elseif ($PSCmdlet.ShouldProcess("User: $($currentUser.Email) (ID: $ID)", "Update account with $($changes.Count) change(s)")) {
    $confirmed = $true
}

if (-not $confirmed) {
    Write-Warning "Update cancelled by user"
    return $null
}

# Execute updates
$updateResults = @{
    UserID = $ID
    Email = $currentUser.Email
    UpdatedFields = @()
    Success = $true
    Errors = @()
}

try {
    # Update Users table if needed
    if ($usersUpdates.Count -gt 0) {
        $updateUsersQuery = @"
UPDATE Users
SET $($usersUpdates -join ', ')
WHERE UserID COLLATE NOCASE = '$safeID';
"@
        Write-Verbose "Executing Users table update: $updateUsersQuery"
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $updateUsersQuery
        Write-Verbose "Users table updated successfully"
        $updateResults.UpdatedFields += "Users table: $($usersUpdates.Count) field(s)"
    }

    # Update auth_user_provider table if needed
    if ($providerUpdates.Count -gt 0) {
        $updateProviderQuery = @"
UPDATE auth_user_provider
SET $($providerUpdates -join ', ')
WHERE UserID COLLATE NOCASE = '$safeID' AND provider COLLATE NOCASE = 'Windows';
"@
        Write-Verbose "Executing auth_user_provider table update: $updateProviderQuery"
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $updateProviderQuery
        Write-Verbose "auth_user_provider table updated successfully"
        $updateResults.UpdatedFields += "auth_user_provider table: $($providerUpdates.Count) field(s)"
    }

    # Update local Windows user if requested
    if ($UpdateLocalUser -and $PSBoundParameters.ContainsKey('UserName')) {
        $oldUserName = $currentUser.UserName
        $newUserName = $UserName

        $oldLocalUser = Get-LocalUser -Name $oldUserName -ErrorAction SilentlyContinue
        if ($oldLocalUser) {
            try {
                Write-Verbose "Renaming local Windows user: '$oldUserName' → '$newUserName'"
                Rename-LocalUser -Name $oldUserName -NewName $newUserName -ErrorAction Stop
                Write-Host "Local Windows user renamed successfully" -ForegroundColor Green
                $updateResults.UpdatedFields += "Local Windows user renamed"

                # Update password if provided
                if ($PSBoundParameters.ContainsKey('NewLocalPassword')) {
                    Write-Verbose "Updating local user password"
                    $securePassword = ConvertTo-SecureString $NewLocalPassword -AsPlainText -Force
                    Set-LocalUser -Name $newUserName -Password $securePassword -ErrorAction Stop
                    Write-Host "Local Windows user password updated" -ForegroundColor Green
                    $updateResults.UpdatedFields += "Local Windows user password updated"
                }
            }
            catch {
                $errorMsg = "Failed to update local Windows user: $($_.Exception.Message)"
                Write-Warning $errorMsg
                $updateResults.Errors += $errorMsg
            }
        }
        else {
            $warnMsg = "Local Windows user '$oldUserName' does not exist. Skipped local user update."
            Write-Warning $warnMsg
            $updateResults.Errors += $warnMsg
        }
    }
    elseif ($PSBoundParameters.ContainsKey('NewLocalPassword')) {
        # Update password only
        $userName = $currentUser.UserName
        $localUser = Get-LocalUser -Name $userName -ErrorAction SilentlyContinue
        if ($localUser) {
            try {
                Write-Verbose "Updating local user password for: $userName"
                $securePassword = ConvertTo-SecureString $NewLocalPassword -AsPlainText -Force
                Set-LocalUser -Name $userName -Password $securePassword -ErrorAction Stop
                Write-Host "Local Windows user password updated" -ForegroundColor Green
                $updateResults.UpdatedFields += "Local Windows user password updated"
            }
            catch {
                $errorMsg = "Failed to update local user password: $($_.Exception.Message)"
                Write-Warning $errorMsg
                $updateResults.Errors += $errorMsg
            }
        }
        else {
            $warnMsg = "Local Windows user '$userName' does not exist. Skipped password update."
            Write-Warning $warnMsg
            $updateResults.Errors += $warnMsg
        }
    }

    Write-Host "`nAccount updated successfully!" -ForegroundColor Green
    Write-Host "Updated fields: $($updateResults.UpdatedFields.Count)" -ForegroundColor Green
    foreach ($field in $updateResults.UpdatedFields) {
        Write-Host "  - $field" -ForegroundColor Gray
    }

    if ($updateResults.Errors.Count -gt 0) {
        Write-Host "`nWarnings/Errors encountered: $($updateResults.Errors.Count)" -ForegroundColor Yellow
        foreach ($error in $updateResults.Errors) {
            Write-Host "  - $error" -ForegroundColor Yellow
        }
    }

    # Fetch and return updated user data
    $updatedUser = Get-PSWebSQLiteData -File $dbFile -Query $checkQuery

    # Add update metadata
    $updatedUser | Add-Member -NotePropertyName UpdatedFields -NotePropertyValue $updateResults.UpdatedFields -Force
    $updatedUser | Add-Member -NotePropertyName UpdateDate -NotePropertyValue (Get-Date) -Force
    $updatedUser | Add-Member -NotePropertyName Changes -NotePropertyValue $changes -Force

    return $updatedUser
}
catch {
    $updateResults.Success = $false
    $updateResults.Errors += $_.Exception.Message
    Write-Error "Failed to update account: $($_.Exception.Message)"
    throw
}
