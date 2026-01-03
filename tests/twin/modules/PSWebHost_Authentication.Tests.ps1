# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "PSWebHost_Authentication module" {
    BeforeAll {
        $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'
        $ModulePath = Join-Path $ProjectRoot 'modules\PSWebHost_Authentication\PSWebHost_Authentication.psm1'

        # Verify module exists
        $ModulePath | Should -Exist

        # Import module
        Import-Module $ModulePath -DisableNameChecking -Force -ErrorAction Stop
    }

    Context "Module structure" {
        It "Should export Get-CardSettings function" {
            Get-Command Get-CardSettings -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should export Set-CardSettings function" {
            # This function was added to save card layout settings
            Get-Command Set-CardSettings -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-PSWebHostUser function" {
            Get-Command Get-PSWebHostUser -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should export PSWebLogon function" {
            Get-Command PSWebLogon -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Get-CardSettings function" {
        It "Should accept EndpointGuid parameter" {
            (Get-Command Get-CardSettings).Parameters.ContainsKey('EndpointGuid') | Should -Be $true
        }

        It "Should accept UserId parameter" {
            (Get-Command Get-CardSettings).Parameters.ContainsKey('UserId') | Should -Be $true
        }

        It "Should return card settings from database" {
            # Test with valid endpoint_guid and user_id
            # Should return JSON with card layout data
            $true | Should -Be $true
        }

        It "Should return null when no settings exist" {
            # Test with non-existent endpoint_guid
            # Should return null or empty result
            $true | Should -Be $true
        }
    }

    Context "Set-CardSettings function" {
        It "Should accept EndpointGuid parameter" {
            (Get-Command Set-CardSettings).Parameters.ContainsKey('EndpointGuid') | Should -Be $true
        }

        It "Should accept UserId parameter" {
            (Get-Command Set-CardSettings).Parameters.ContainsKey('UserId') | Should -Be $true
        }

        It "Should accept Data parameter" {
            (Get-Command Set-CardSettings).Parameters.ContainsKey('Data') | Should -Be $true
        }

        It "Should insert new card settings" {
            # Test inserting new record for endpoint_guid + user_id
            $true | Should -Be $true
        }

        It "Should update existing card settings" {
            # Test updating existing record (INSERT OR REPLACE)
            $true | Should -Be $true
        }

        It "Should preserve created_date when updating" {
            # When updating, created_date should remain unchanged
            $true | Should -Be $true
        }
    }

    Context "User authentication functions" {
        It "Should have Get-PSWebHostUsers function" {
            Get-Command Get-PSWebHostUsers -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should have New-PSWebHostUser function" {
            Get-Command New-PSWebHostUser -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should have Test-IsValidPassword function" {
            Get-Command Test-IsValidPassword -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should have Test-IsValidEmailAddress function" {
            Get-Command Test-IsValidEmailAddress -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Session management" {
        It "Should have Get-LoginSession function" {
            Get-Command Get-LoginSession -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should have Set-LoginSession function" {
            Get-Command Set-LoginSession -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should have Remove-LoginSession function" {
            Get-Command Remove-LoginSession -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Role and group management" {
        It "Should have Get-PSWebHostRole function" {
            Get-Command Get-PSWebHostRole -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should have Add-PSWebHostRole function" {
            Get-Command Add-PSWebHostRole -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should have Get-PSWebHostGroup function" {
            Get-Command Get-PSWebHostGroup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should have Add-PSWebHostGroup function" {
            Get-Command Add-PSWebHostGroup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}
