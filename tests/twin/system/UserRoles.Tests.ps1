# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe 'User and Role Management' -Tags 'UserRoles' {
    BeforeAll {
        $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'

        # Import required modules
        Import-Module (Join-Path $ProjectRoot 'modules\PSWebHost_Database') -DisableNameChecking -Force
        Import-Module (Join-Path $ProjectRoot 'modules\PSWebHost_Authentication') -DisableNameChecking -Force

        # Track created test data for cleanup
        $script:testUsers = @()
        $script:testRoles = @()
    }

    AfterAll {
        # Cleanup test users and roles
        $dbFile = Join-Path $ProjectRoot "PsWebHost_Data\pswebhost.db"

        foreach ($email in $script:testUsers) {
            try {
                $query = "DELETE FROM Users WHERE Email = '$email';"
                Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query -ErrorAction SilentlyContinue
            } catch {
                Write-Warning "Failed to cleanup test user: $email"
            }
        }

        foreach ($roleName in $script:testRoles) {
            try {
                Remove-PSWebHostRole -RoleName $roleName -ErrorAction SilentlyContinue
            } catch {
                Write-Warning "Failed to cleanup test role: $roleName"
            }
        }
    }

    Context "User creation" {
        It "Should create a new user with valid email and password" {
            $email = "testuser-$(Get-Random)@example.com"
            $script:testUsers += $email

            $user = New-PSWebHostUser -Email $email -Password "Password123!"

            $user | Should -Not -BeNullOrEmpty
            $user.Email | Should -Be $email
            $user.UserID | Should -Not -BeNullOrEmpty
        }

        It "Should enforce password requirements" {
            $email = "testuser-$(Get-Random)@example.com"
            $script:testUsers += $email

            # Weak password should fail
            { New-PSWebHostUser -Email $email -Password "weak" } | Should -Throw
        }

        It "Should enforce unique email addresses" {
            $email = "testuser-$(Get-Random)@example.com"
            $script:testUsers += $email

            New-PSWebHostUser -Email $email -Password "Password123!"

            # Creating duplicate should fail
            { New-PSWebHostUser -Email $email -Password "Password123!" } | Should -Throw
        }

        It "Should validate email format" {
            # Invalid email should fail
            { New-PSWebHostUser -Email "notanemail" -Password "Password123!" } | Should -Throw
        }
    }

    Context "Role creation" {
        It "Should create a new role" {
            $roleName = "test-role-$(Get-Random)"
            $script:testRoles += $roleName

            Add-PSWebHostRole -RoleName $roleName

            $roles = Get-PSWebHostRole
            $roles.RoleName | Should -Contain $roleName
        }

        It "Should retrieve created role" {
            $roleName = "test-role-$(Get-Random)"
            $script:testRoles += $roleName

            Add-PSWebHostRole -RoleName $roleName

            $role = Get-PSWebHostRole -RoleName $roleName
            $role | Should -Not -BeNullOrEmpty
            $role.RoleName | Should -Be $roleName
        }

        It "Should handle role names with special characters" {
            $roleName = "test-role-special-$(Get-Random)"
            $script:testRoles += $roleName

            Add-PSWebHostRole -RoleName $roleName

            $role = Get-PSWebHostRole -RoleName $roleName
            $role.RoleName | Should -Be $roleName
        }
    }

    Context "Role assignment" {
        It "Should assign a role to a user" {
            $email = "testuser-$(Get-Random)@example.com"
            $script:testUsers += $email
            $roleName = "test-role-$(Get-Random)"
            $script:testRoles += $roleName

            $user = New-PSWebHostUser -Email $email -Password "Password123!"
            Add-PSWebHostRole -RoleName $roleName
            Add-PSWebHostRoleAssignment -UserID $user.UserID -RoleName $roleName

            # Verify role assignment
            $userWithRoles = Get-PSWebHostUser -UserID $user.UserID
            $userWithRoles.Roles | Should -Contain $roleName
        }

        It "Should allow multiple roles per user" {
            $email = "testuser-$(Get-Random)@example.com"
            $script:testUsers += $email
            $role1 = "test-role-1-$(Get-Random)"
            $role2 = "test-role-2-$(Get-Random)"
            $script:testRoles += $role1, $role2

            $user = New-PSWebHostUser -Email $email -Password "Password123!"
            Add-PSWebHostRole -RoleName $role1
            Add-PSWebHostRole -RoleName $role2
            Add-PSWebHostRoleAssignment -UserID $user.UserID -RoleName $role1
            Add-PSWebHostRoleAssignment -UserID $user.UserID -RoleName $role2

            $userWithRoles = Get-PSWebHostUser -UserID $user.UserID
            $userWithRoles.Roles | Should -Contain $role1
            $userWithRoles.Roles | Should -Contain $role2
        }

        It "Should prevent duplicate role assignments" {
            $email = "testuser-$(Get-Random)@example.com"
            $script:testUsers += $email
            $roleName = "test-role-$(Get-Random)"
            $script:testRoles += $roleName

            $user = New-PSWebHostUser -Email $email -Password "Password123!"
            Add-PSWebHostRole -RoleName $roleName
            Add-PSWebHostRoleAssignment -UserID $user.UserID -RoleName $roleName

            # Assigning same role again should be handled gracefully
            { Add-PSWebHostRoleAssignment -UserID $user.UserID -RoleName $roleName } | Should -Not -Throw
        }
    }

    Context "Role removal" {
        It "Should remove a role from a user" {
            $email = "testuser-$(Get-Random)@example.com"
            $script:testUsers += $email
            $roleName = "test-role-$(Get-Random)"
            $script:testRoles += $roleName

            $user = New-PSWebHostUser -Email $email -Password "Password123!"
            Add-PSWebHostRole -RoleName $roleName
            Add-PSWebHostRoleAssignment -UserID $user.UserID -RoleName $roleName

            # Remove role assignment
            Remove-PSWebHostRoleAssignment -UserID $user.UserID -RoleName $roleName

            $userWithRoles = Get-PSWebHostUser -UserID $user.UserID
            $userWithRoles.Roles | Should -Not -Contain $roleName
        }

        It "Should handle removing non-existent role assignment" {
            $email = "testuser-$(Get-Random)@example.com"
            $script:testUsers += $email

            $user = New-PSWebHostUser -Email $email -Password "Password123!"

            # Removing role that was never assigned should not throw
            { Remove-PSWebHostRoleAssignment -UserID $user.UserID -RoleName "NonExistentRole" } | Should -Not -Throw
        }
    }

    Context "User retrieval" {
        It "Should get user by UserID" {
            $email = "testuser-$(Get-Random)@example.com"
            $script:testUsers += $email

            $user = New-PSWebHostUser -Email $email -Password "Password123!"
            $retrievedUser = Get-PSWebHostUser -UserID $user.UserID

            $retrievedUser | Should -Not -BeNullOrEmpty
            $retrievedUser.Email | Should -Be $email
            $retrievedUser.UserID | Should -Be $user.UserID
        }

        It "Should get user by Email" {
            $email = "testuser-$(Get-Random)@example.com"
            $script:testUsers += $email

            $user = New-PSWebHostUser -Email $email -Password "Password123!"
            $retrievedUser = Get-PSWebHostUser -Email $email

            $retrievedUser | Should -Not -BeNullOrEmpty
            $retrievedUser.Email | Should -Be $email
            $retrievedUser.UserID | Should -Be $user.UserID
        }

        It "Should include roles when getting user" {
            $email = "testuser-$(Get-Random)@example.com"
            $script:testUsers += $email
            $roleName = "test-role-$(Get-Random)"
            $script:testRoles += $roleName

            $user = New-PSWebHostUser -Email $email -Password "Password123!"
            Add-PSWebHostRole -RoleName $roleName
            Add-PSWebHostRoleAssignment -UserID $user.UserID -RoleName $roleName

            $retrievedUser = Get-PSWebHostUser -UserID $user.UserID
            $retrievedUser.Roles | Should -Not -BeNullOrEmpty
            $retrievedUser.Roles | Should -Contain $roleName
        }

        It "Should return null for non-existent user" {
            $retrievedUser = Get-PSWebHostUser -UserID "nonexistent-$(Get-Random)"
            $retrievedUser | Should -BeNullOrEmpty
        }
    }

    Context "Get all users" {
        It "Should retrieve multiple users" {
            # Create multiple test users
            $email1 = "testuser1-$(Get-Random)@example.com"
            $email2 = "testuser2-$(Get-Random)@example.com"
            $script:testUsers += $email1, $email2

            New-PSWebHostUser -Email $email1 -Password "Password123!"
            New-PSWebHostUser -Email $email2 -Password "Password123!"

            $allUsers = Get-PSWebHostUsers
            $allUsers.Email | Should -Contain $email1
            $allUsers.Email | Should -Contain $email2
        }
    }
}
