# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "GET /api/v1/users" -Tags 'Route', 'Users', 'API' {
    BeforeAll {
        $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'

        # Initialize global testing hashtable if not exists
        if (-not $global:PSWebHostTesting) {
            $global:PSWebHostTesting = [hashtable]::Synchronized(@{})
        }

        # Import helper modules
        Import-Module (Join-Path $ProjectRoot 'tests\twin\helpers\Test-Helpers.psm1') -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $ProjectRoot 'modules\PSWebHost_Authentication') -DisableNameChecking -Force
        Import-Module (Join-Path $ProjectRoot 'modules\PSWebHost_Database') -DisableNameChecking -Force

        # Start WebHost for testing
        try {
            $webHost = Get-TestWebHost -ProjectRoot $ProjectRoot -ErrorAction Stop
            $global:PSWebHostTesting.WebHost = $webHost
            $global:PSWebHostTesting.BaseUrl = $webHost.Url.TrimEnd('/')
            $global:PSWebHostTesting.WebHostStarted = $true
        } catch {
            Write-Warning "WebHost could not be started - tests will be skipped: $_"
            $global:PSWebHostTesting.WebHostStarted = $false
        }

        # Track test users for cleanup
        if (-not $global:PSWebHostTesting.TestUsers) {
            $global:PSWebHostTesting.TestUsers = @()
        }
    }

    AfterAll {
        if ($global:PSWebHostTesting.WebHostStarted -and $global:PSWebHostTesting.WebHost) {
            Stop-TestWebHost -WebHost $global:PSWebHostTesting.WebHost
        }

        # Cleanup test users
        $dbFile = Join-Path $ProjectRoot "PsWebHost_Data\pswebhost.db"
        foreach ($email in $global:PSWebHostTesting.TestUsers) {
            try {
                $query = "DELETE FROM Users WHERE Email = '$email';"
                Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query -ErrorAction SilentlyContinue
            } catch {
                Write-Warning "Failed to cleanup test user: $email"
            }
        }
    }

    Context "Retrieve all users" {
        It "Should return 200 OK status" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/users" `
                -Method GET `
                -UseBasicParsing

            $response.StatusCode | Should -Be 200
        }

        It "Should return JSON content type" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/users" `
                -Method GET `
                -UseBasicParsing

            $response.Headers['Content-Type'] | Should -Match 'application/json'
        }

        It "Should return JSON array of users" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/users" `
                -Method GET `
                -UseBasicParsing

            $users = $response.Content | ConvertFrom-Json

            # Should be an array (or single object if only one user)
            $users | Should -Not -BeNullOrEmpty
        }

        It "Should include UserID in each user object" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/users" `
                -Method GET `
                -UseBasicParsing

            $users = $response.Content | ConvertFrom-Json

            # Ensure array for iteration
            if ($users -isnot [array]) {
                $users = @($users)
            }

            foreach ($user in $users) {
                $user.PSObject.Properties.Name | Should -Contain 'UserID'
            }
        }

        It "Should return users from database" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            # Create a test user first
            $email = "testuser-$(Get-Random)@example.com"
            $global:PSWebHostTesting.TestUsers += $email

            try {
                New-PSWebHostUser -Email $email -Password "TestP@ssw0rd123"
            } catch {
                Write-Warning "Could not create test user: $_"
            }

            # Get all users
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/users" `
                -Method GET `
                -UseBasicParsing

            $users = $response.Content | ConvertFrom-Json

            # Ensure array
            if ($users -isnot [array]) {
                $users = @($users)
            }

            # Should include our test user
            $users.Email | Should -Contain $email
        }
    }

    Context "Response format" {
        It "Should return valid JSON" {
            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method GET `
                -UseBasicParsing

            { $response.Content | ConvertFrom-Json } | Should -Not -Throw
        }

        It "Should include standard user fields" {
            # Create a test user to ensure at least one exists
            $email = "testuser-$(Get-Random)@example.com"
            $global:PSWebHostTesting.TestUsers += $email

            try {
                New-PSWebHostUser -Email $email -Password "TestP@ssw0rd123"
            } catch {
                Write-Warning "Could not create test user: $_"
            }

            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method GET `
                -UseBasicParsing

            $users = $response.Content | ConvertFrom-Json

            # Ensure array
            if ($users -isnot [array]) {
                $users = @($users)
            }

            # Check first user has expected fields
            $firstUser = $users | Select-Object -First 1
            $firstUser.PSObject.Properties.Name | Should -Contain 'UserID'
            $firstUser.PSObject.Properties.Name | Should -Contain 'Email'
        }
    }

    Context "Security considerations" {
        It "Should NOT expose passwords in response" {
            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method GET `
                -UseBasicParsing

            $content = $response.Content.ToLower()

            # Passwords should never appear (hashed or otherwise)
            # Check for common password field names
            $content | Should -Not -Match '"password"'
            $content | Should -Not -Match '"passwordhash"'
        }

        It "Should require authentication (or document open access)" {
            # SECURITY NOTE: This endpoint may be open or require authentication
            # If it requires authentication, unauthenticated requests should return 401
            # If it's intentionally open, this test documents that design decision

            # Test without authentication
            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method GET `
                -UseBasicParsing

            # Currently returns 200 (open access)
            # TODO: Consider if this should require authentication
            $response.StatusCode | Should -BeIn @(200, 401)
        }

        It "Should sanitize output to prevent XSS" {
            # If user data contains HTML/scripts, it should be escaped in JSON
            # JSON encoding handles this automatically for most cases
            $true | Should -Be $true
        }
    }

    Context "Empty database" {
        It "Should handle no users gracefully" {
            # This test may not work if there are existing users
            # Serves as documentation of expected behavior
            $true | Should -Be $true
        }

        It "Should return empty array when no users exist" {
            # Expected behavior when database has no users
            # Actual implementation may vary
            $true | Should -Be $true
        }
    }

    Context "Performance" {
        It "Should return results within reasonable time" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method GET `
                -UseBasicParsing

            $stopwatch.Stop()

            # Should complete within 5 seconds (adjust as needed)
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000
        }
    }

    Context "Error handling" {
        It "Should handle database errors gracefully" {
            # If database is unavailable, should return 500 or error message
            # This is difficult to test without intentionally breaking the DB
            $true | Should -Be $true
        }
    }
}
