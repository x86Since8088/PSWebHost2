#This script synchronizes local users and groups to the PsWebHost database.

# Import necessary modules
# The path to the modules is relative to the script's location.
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Import-Module (Join-Path $PSScriptRoot "..\..\..\modules\PSWebHost_Database\PSWebHost_Database.psm1")

# Get computer name
$computerName = $env:COMPUTERNAME

# Synchronize Users
Write-Host "Synchronizing local users..."
$users = Get-LocalUser

foreach ($user in $users) {
    if ($user.Enabled) {
        $userId = "$($user.Name)@$computerName"
        $userName = $user.Name

        # Check for lockout status
        try {
            $principalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Machine')
            $userPrincipal = [System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity($principalContext, $userName)
            $lockedOut = $userPrincipal.IsAccountLockedOut()
        } catch {
            Write-Warning "Could not determine lockout status for user '$userName'. Defaulting to not locked out. Error: $_ "
            $lockedOut = $false
        }

        # Get logon hours
        $logonHours = "All"
        try {
            $netUserOutput = net user $userName
            $logonHoursLine = $netUserOutput | Select-String -Pattern "Logon hours allowed"
            if ($logonHoursLine) {
                $logonHours = ($logonHoursLine -split ':')[1].Trim()
            }
        } catch {
            Write-Warning "Could not determine logon hours for user '$userName'. Defaulting to 'All'. Error: $_ "
        }

        # Prepare user data
        $userData = @{
            Description = $user.Description
            FullName = $user.FullName
            PasswordLastSet = $user.PasswordLastSet
            PasswordRequired = $user.PasswordRequired
            UserMayNotChangePassword = $user.UserMayNotChangePassword
            LogonHours = $logonHours
        } | ConvertTo-Json

        # Add/Update user in the database
        Write-Verbose "Syncing user '$userName'"
        Set-UserProvider -UserID $userId -UserName $userName -provider 'local' -locked_out $lockedOut -expires $user.AccountExpires -enabled $user.Enabled -data $userData
    }
}

# Synchronize Groups
Write-Host "Synchronizing local groups and memberships..."
$groups = Get-LocalGroup

foreach ($group in $groups) {
    $groupName = "$computerName\$($group.Name)"
    $groupId = $groupName # Use the same for ID and Name
    $createdDate = (Get-Date).ToString("s")

    # Check if group exists
    $existingGroup = Get-PSWebGroup -Name $groupName
    if (-not $existingGroup) {
        # Add group to the database
        $query = "INSERT INTO User_Groups (GroupID, Name, Created, Updated) VALUES ('$groupId', '$groupName', '$createdDate', '$createdDate')"
        Invoke-PSWebSQLiteNonQuery -File "pswebhost.db" -Query $query
    }

    # Map system_admin role to administrators group
    if ($group.Name -eq 'Administrators') {
        Write-Verbose "Mapping 'system_admin' role to group '$groupName'"
        Set-RoleForPrincipal -PrincipalID $groupId -RoleName 'system_admin'
    }

    # Get group members
    try {
        $members = Get-LocalGroupMember -Group $group.Name -ErrorAction Stop
        foreach ($member in $members) {
            if ($member.ObjectClass -eq 'User') {
                $memberName = $member.Name.Split('\')[-1]
                $memberUserId = "$memberName@$computerName"
                Write-Verbose "Adding user '$memberName' to group '$groupName'"
                Add-UserToGroup -UserID $memberUserId -GroupID $groupId
            }
        }
    } catch {
        Write-Warning "Could not get members of group '$($group.Name)'. Error: $_ "
    }
}

Write-Host "Local accounts synchronized successfully."
