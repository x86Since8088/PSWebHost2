# Account_New_TestUser.ps1
# Primitive script to create a test user with specified roles and groups
# Reusable by other account management scripts

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Email,

    [Parameter(Mandatory=$false)]
    [string]$UserName,

    [Parameter(Mandatory=$false)]
    [string]$Password,

    [Parameter(Mandatory=$false)]
    [string[]]$Roles = @(),

    [Parameter(Mandatory=$false)]
    [string[]]$Groups = @(),

    [Parameter(Mandatory=$false)]
    [string]$Prefix = "TA"
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment (initializes SQLite and required modules)
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

# Generate test user credentials
$randomLetters = -join ((65..90) + (97..122) | Get-Random -Count 5 | ForEach-Object { [char]$_ })

if ([string]::IsNullOrEmpty($Email)) {
    $Email = "${Prefix}_$randomLetters@localhost"
}

if ([string]::IsNullOrEmpty($UserName)) {
    $UserName = "${Prefix}_$randomLetters"
}

if ([string]::IsNullOrEmpty($Password)) {
    # Generate secure random password that meets requirements:
    # - Min 8 chars, 2 uppercase, 2 lowercase, 2 numbers, 2 symbols
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower = 'abcdefghijkmnopqrstuvwxyz'
    $numbers = '23456789'
    $symbols = '!@#$%^&*'

    # Ensure minimum requirements are met
    $passwordChars = @()
    $passwordChars += $upper[(Get-Random -Maximum $upper.Length)]
    $passwordChars += $upper[(Get-Random -Maximum $upper.Length)]
    $passwordChars += $lower[(Get-Random -Maximum $lower.Length)]
    $passwordChars += $lower[(Get-Random -Maximum $lower.Length)]
    $passwordChars += $numbers[(Get-Random -Maximum $numbers.Length)]
    $passwordChars += $numbers[(Get-Random -Maximum $numbers.Length)]
    $passwordChars += $symbols[(Get-Random -Maximum $symbols.Length)]
    $passwordChars += $symbols[(Get-Random -Maximum $symbols.Length)]

    # Add 8 more random characters
    $allChars = $upper + $lower + $numbers + $symbols
    $passwordChars += (1..8) | ForEach-Object { $allChars[(Get-Random -Maximum $allChars.Length)] }

    # Shuffle the characters
    $Password = -join ($passwordChars | Get-Random -Count $passwordChars.Length)
}

Write-Verbose "Generated test user credentials:"
Write-Verbose "  Email: $Email"
Write-Verbose "  UserName: $UserName"
Write-Verbose "  Password: $Password"
Write-Verbose "  Roles: $($Roles -join ', ')"
Write-Verbose "  Groups: $($Groups -join ', ')"

# Check if user already exists
$existingUser = Get-PSWebHostUser -Email $Email
if ($existingUser) {
    Write-Warning "User with email '$Email' already exists (UserID: $($existingUser.UserID))"
    # Return existing user
    return [PSCustomObject]@{
        UserID = $existingUser.UserID
        Email = $existingUser.Email
        UserName = $UserName
        Password = $Password
        Roles = @(Get-PSWebHostRole -UserID $existingUser.UserID | Select-Object -ExpandProperty RoleName)
        Groups = @()  # TODO: Get groups if needed
        Created = Get-Date
        IsTestAccount = $true
        AlreadyExisted = $true
    }
}

# Create the user
Write-Verbose "Creating test user account for: $Email"
$user = Register-PSWebHostUser -UserName $UserName -Email $Email -Provider "Password" -Password $Password -Verbose:$VerbosePreference

if (-not $user) {
    throw "Failed to create user account"
}

Write-Verbose "User created successfully with UserID: $($user.UserID)"

# Assign roles
$assignedRoles = @()
foreach ($role in $Roles) {
    try {
        # Check if role exists, create if not
        $roleQuery = "SELECT RoleName FROM PSWeb_Roles WHERE RoleName COLLATE NOCASE = '$(Sanitize-SqlQueryString -String $role)';"
        $dbFile = Join-Path $ProjectRoot "PsWebHost_Data\pswebhost.db"
        $existingRole = Get-PSWebSQLiteData -File $dbFile -Query $roleQuery

        if (-not $existingRole) {
            Write-Verbose "Creating role: $role"
            Add-PSWebHostRole -Name $role -Verbose:$VerbosePreference
        }

        # Assign role to user
        Write-Verbose "Assigning role '$role' to user $($user.UserID)"
        Add-PSWebHostRoleAssignment -PrincipalID $user.UserID -RoleName $role -Verbose:$VerbosePreference
        $assignedRoles += $role
    } catch {
        Write-Warning "Failed to assign role '$role': $($_.Exception.Message)"
    }
}

# Assign groups
$assignedGroups = @()
foreach ($groupName in $Groups) {
    try {
        # Check if group exists, create if not
        $group = Get-PSWebHostGroup -Name $groupName
        if (-not $group) {
            Write-Verbose "Creating group: $groupName"
            Add-PSWebHostGroup -Name $groupName -Verbose:$VerbosePreference
            $group = Get-PSWebHostGroup -Name $groupName
        }

        # Add user to group
        if ($group) {
            Write-Verbose "Adding user to group '$groupName'"
            Add-PSWebHostGroupMember -UserID $user.UserID -GroupID $group.GroupID -Verbose:$VerbosePreference
            $assignedGroups += $groupName
        }
    } catch {
        Write-Warning "Failed to add user to group '$groupName': $($_.Exception.Message)"
    }
}

# Return account details as object
[PSCustomObject]@{
    UserID = $user.UserID
    Email = $user.Email
    UserName = $UserName
    Password = $Password
    Roles = $assignedRoles
    Groups = $assignedGroups
    Created = Get-Date
    IsTestAccount = $true
    AlreadyExisted = $false
}
