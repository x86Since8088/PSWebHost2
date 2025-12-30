Import-Module PSWebHost_Database
BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\system\init.ps1')
}

Describe 'User and Role Management' -Tags 'UserRoles' {
    It 'Should create a new user' {
        $email = "testuser-$(Get-Random)@example.com"
        $user = New-PSWebHostUser -Email $email -Password "Password123!"
        $user | Should -Not -BeNull
        $user.Email | Should -Be $email
    }

    It 'Should create a new role' {
        $roleName = "test-role-$(Get-Random)"
        New-PSWebHostRole -RoleName $roleName
        $roles = Get-PSWebRoles
        $roles | Should -Contain $roleName
    }

    It 'Should assign a role to a user' {
        $email = "testuser-$(Get-Random)@example.com"
        $user = New-PSWebHostUser -Email $email -Password "Password123!"
        $roleName = "test-role-$(Get-Random)"
        New-PSWebHostRole -RoleName $roleName
        Add-PSWebHostUserToRole -UserID $user.UserID -RoleName $roleName
        $userRoles = Get-UserRoles -UserID $user.UserID
        $userRoles | Should -Contain $roleName
    }

    It 'Should get a user with roles' {
        $email = "testuser-$(Get-Random)@example.com"
        $user = New-PSWebHostUser -Email $email -Password "Password123!"
        $roleName = "test-role-$(Get-Random)"
        New-PSWebHostRole -RoleName $roleName
        Add-PSWebHostUserToRole -UserID $user.UserID -RoleName $roleName

        $retrievedUser = Get-PSWebUser -UserID $user.UserID
        $retrievedUser.Roles | Should -Not -BeNull
        $retrievedUser.Roles | Should -Contain $roleName
    }
}