# . (Join-Path $PSScriptRoot '..', '..', 'system', 'init.ps1')

$localUsers = Get-LocalUser

foreach ($localUser in $localUsers) {
    Write-Verbose "Checking user: $($localUser.Name)"
    $existingUser = Get-PSWebHostUser -Email $localUser.Name
    if (-not $existingUser) {
        Write-Verbose "User '$($localUser.Name)' does not exist. Creating..."
        # Create the user with a random, unusable password by default.
        # An admin should reset this password via pswebadmin.ps1
        $randomPassword = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
        $__err = $null
        Register-PSWebHostUser -UserName $localUser.Name -Email $localUser.Name -Provider "Password" -Password $randomPassword -ErrorAction SilentlyContinue -ErrorVariable __err
        if ($__err) {
            Write-Error "Failed to create user '$($localUser.Name)'. Error: $__err"
        } else {
            Write-Verbose "Successfully created user '$($localUser.Name)'."
        }
    } else {
        Write-Verbose "User '$($localUser.Name)' already exists."
    }
}
