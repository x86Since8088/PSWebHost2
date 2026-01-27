#Requires -Version 7

<#
.SYNOPSIS
    Resolves user patterns to UserID for User:others admin browsing

.DESCRIPTION
    Resolves user identification patterns to UserID by querying the user database.
    Supports three pattern types:
    1. email@example.com/1234 - Email with last 4 of UserID
    2. {userID-guid} - Direct UserID lookup
    3. email@example.com - Email-only lookup

.PARAMETER Pattern
    User identification pattern to resolve

.PARAMETER DatabasePath
    Optional path to user database (defaults to system database)

.EXAMPLE
    .\User_Resolve.ps1 -Pattern "test@example.com/abc123"
    # Returns: { Success = $true; UserID = "...abc123"; Email = "test@example.com"; Pattern = "email/last4" }

.EXAMPLE
    .\User_Resolve.ps1 -Pattern "f8a9b7c6-d5e4-3f2a-1b0c-9d8e7f6a5b4c"
    # Returns: { Success = $true; UserID = "f8a9b7c6-..."; Email = "user@example.com"; Pattern = "userID" }

.NOTES
    This utility is used by Path_Resolve.ps1 to support User:others admin browsing.
    Requires system_admin role (caller must validate).
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Pattern,

    [Parameter()]
    [string]$DatabasePath
)

# Initialize result object
$result = @{
    Success = $false
    UserID = $null
    Email = $null
    Pattern = $null
    Message = ""
}

try {
    # Determine database path
    if (-not $DatabasePath) {
        # Use default system database path
        if ($Global:PSWebServer -and $Global:PSWebServer['Config']) {
            $dbConfig = $Global:PSWebServer['Config'].Database
            if ($dbConfig -and $dbConfig.Path) {
                $DatabasePath = $dbConfig.Path
            }
            elseif ($Global:PSWebServer['Project_Root']) {
                # Fallback to default location
                $DatabasePath = Join-Path $Global:PSWebServer['Project_Root'].Path "system\db\sqlite\PSWebHost.db"
            }
        }

        # Last resort: relative to script location
        if (-not $DatabasePath -or -not (Test-Path $DatabasePath)) {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $DatabasePath = Join-Path $projectRoot "system\db\sqlite\PSWebHost.db"
        }
    }

    # Verify database exists
    if (-not (Test-Path $DatabasePath)) {
        $result.Message = "User database not found: $DatabasePath"
        return $result
    }

    # Pattern 1: email@example.com/1234 (Email with last 4 of UserID)
    if ($Pattern -match '^([^/]+)/([a-zA-Z0-9]{4,})$') {
        $email = $matches[1]
        $last4 = $matches[2]

        # Query user by email
        $query = "SELECT UserID, Email FROM Users WHERE Email = @Email COLLATE NOCASE LIMIT 1;"
        $users = Invoke-PSWebSQLiteQuery -File $DatabasePath -Query $query -Parameters @{ Email = $email }

        if ($users -and $users.Count -gt 0) {
            $user = $users[0]
            $userIdLast4 = $user.UserID.Substring([Math]::Max(0, $user.UserID.Length - $last4.Length))

            # Verify last 4 matches
            if ($userIdLast4 -eq $last4) {
                $result.Success = $true
                $result.UserID = $user.UserID
                $result.Email = $user.Email
                $result.Pattern = "email/last4"
                $result.Message = "User resolved via email/last4"
            }
            else {
                $result.Message = "Last 4 characters of UserID do not match. Expected: $userIdLast4, Got: $last4"
            }
        }
        else {
            $result.Message = "User not found with email: $email"
        }
    }
    # Pattern 2: {userID-guid} (Direct UserID lookup)
    elseif ($Pattern -match '^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$') {
        $userId = $Pattern

        # Query user by UserID
        $query = "SELECT UserID, Email FROM Users WHERE UserID = @UserID LIMIT 1;"
        $users = Invoke-PSWebSQLiteQuery -File $DatabasePath -Query $query -Parameters @{ UserID = $userId }

        if ($users -and $users.Count -gt 0) {
            $user = $users[0]
            $result.Success = $true
            $result.UserID = $user.UserID
            $result.Email = $user.Email
            $result.Pattern = "userID"
            $result.Message = "User resolved via UserID"
        }
        else {
            $result.Message = "User not found with UserID: $userId"
        }
    }
    # Pattern 3: email@example.com (Email-only lookup)
    elseif ($Pattern -match '^[^@]+@[^@]+\.[^@]+$') {
        $email = $Pattern

        # Query user by email
        $query = "SELECT UserID, Email FROM Users WHERE Email = @Email COLLATE NOCASE LIMIT 1;"
        $users = Invoke-PSWebSQLiteQuery -File $DatabasePath -Query $query -Parameters @{ Email = $email }

        if ($users -and $users.Count -gt 0) {
            $user = $users[0]
            $result.Success = $true
            $result.UserID = $user.UserID
            $result.Email = $user.Email
            $result.Pattern = "email"
            $result.Message = "User resolved via email"
        }
        else {
            $result.Message = "User not found with email: $email"
        }
    }
    # Pattern 4: Short UserID (last 8+ chars)
    elseif ($Pattern -match '^[a-fA-F0-9]{8,}$') {
        # Try to find user where UserID ends with this pattern
        $query = "SELECT UserID, Email FROM Users;"
        $users = Invoke-PSWebSQLiteQuery -File $DatabasePath -Query $query

        $matchingUser = $users | Where-Object {
            $_.UserID -like "*$Pattern"
        } | Select-Object -First 1

        if ($matchingUser) {
            $result.Success = $true
            $result.UserID = $matchingUser.UserID
            $result.Email = $matchingUser.Email
            $result.Pattern = "short_userID"
            $result.Message = "User resolved via short UserID suffix"
        }
        else {
            $result.Message = "User not found with UserID suffix: $Pattern"
        }
    }
    else {
        $result.Message = "Invalid user pattern format. Expected: email/last4, userID, or email"
    }
}
catch {
    $result.Message = "Error resolving user: $($_.Exception.Message)"
}

# Return result as object
return [PSCustomObject]$result
