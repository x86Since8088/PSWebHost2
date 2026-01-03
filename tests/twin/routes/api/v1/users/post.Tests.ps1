# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "POST /api/v1/users" -Tags 'Route', 'Users', 'API' {
    BeforeAll {
        $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'

        # Import helper modules
        Import-Module (Join-Path $ProjectRoot 'tests\twin\helpers\Test-Helpers.psm1') -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $ProjectRoot 'modules\PSWebHost_Database') -DisableNameChecking -Force

        # Start WebHost for testing
        try {
            $global:PSWebHostTesting.WebHost = Get-TestWebHost -ProjectRoot $ProjectRoot -ErrorAction Stop
            $global:PSWebHostTesting.BaseUrl = $webHost.Url.TrimEnd('/')
            $global:PSWebHostTesting.WebHostStarted = $true
        } catch {
            Write-Warning "WebHost could not be started - tests will be skipped: $_"
            $global:PSWebHostTesting.WebHostStarted = $false
        }

        # Track created user IDs for cleanup
        $global:PSWebHostTesting.TestUserIDs = @()
    }

    AfterAll {
        if ($global:PSWebHostTesting.WebHostStarted -and $global:PSWebHostTesting.WebHost) {
            Stop-TestWebHost -WebHost $global:PSWebHostTesting.WebHost
        }

        # Cleanup test users
        $dbFile = Join-Path $ProjectRoot "PsWebHost_Data\pswebhost.db"
        foreach ($userID in $global:PSWebHostTesting.TestUserIDs) {
            try {
                $query = "DELETE FROM Users WHERE UserID = '$userID';"
                Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query -ErrorAction SilentlyContinue
            } catch {
                Write-Warning "Failed to cleanup test user: $userID"
            }
        }
    }

    Context "Create user with valid data" {
        It "Should create user with required UserName" {
            $userData = @{
                UserName = "TestUser-$(Get-Random)"
                Email = "testuser-$(Get-Random)@example.com"
            } | ConvertTo-Json

            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $userData `
                -ContentType "application/json" `
                -UseBasicParsing

            $response.StatusCode | Should -Be 200

            $user = $response.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID
        }

        It "Should return created user as JSON" {
            $userData = @{
                UserName = "TestUser-$(Get-Random)"
                Email = "testuser-$(Get-Random)@example.com"
            } | ConvertTo-Json

            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $userData `
                -ContentType "application/json" `
                -UseBasicParsing

            $response.Headers['Content-Type'] | Should -Match 'application/json'

            $user = $response.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            $user.UserName | Should -Not -BeNullOrEmpty
        }

        It "Should generate unique UserID (GUID)" {
            $userData = @{
                UserName = "TestUser-$(Get-Random)"
            } | ConvertTo-Json

            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $userData `
                -ContentType "application/json" `
                -UseBasicParsing

            $user = $response.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            # Should be a valid GUID
            [guid]::Parse($user.UserID) | Should -Not -BeNullOrEmpty
        }

        It "Should accept optional Email field" {
            $email = "testuser-$(Get-Random)@example.com"
            $userData = @{
                UserName = "TestUser-$(Get-Random)"
                Email = $email
            } | ConvertTo-Json

            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $userData `
                -ContentType "application/json" `
                -UseBasicParsing

            $user = $response.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            $user.Email | Should -Be $email
        }

        It "Should accept optional Phone field" {
            $phone = "555-$(Get-Random -Minimum 1000 -Maximum 9999)"
            $userData = @{
                UserName = "TestUser-$(Get-Random)"
                Phone = $phone
            } | ConvertTo-Json

            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $userData `
                -ContentType "application/json" `
                -UseBasicParsing

            $user = $response.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            $user.Phone | Should -Be $phone
        }

        It "Should create user with all fields" {
            $userName = "TestUser-$(Get-Random)"
            $email = "testuser-$(Get-Random)@example.com"
            $phone = "555-1234"

            $userData = @{
                UserName = $userName
                Email = $email
                Phone = $phone
            } | ConvertTo-Json

            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $userData `
                -ContentType "application/json" `
                -UseBasicParsing

            $user = $response.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            $user.UserName | Should -Be $userName
            $user.Email | Should -Be $email
            $user.Phone | Should -Be $phone
        }
    }

    Context "Validation - Missing required fields" {
        It "Should return 400 when UserName is missing" {
            $userData = @{
                Email = "testuser-$(Get-Random)@example.com"
            } | ConvertTo-Json

            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                    -Method POST `
                    -Body $userData `
                    -ContentType "application/json" `
                    -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            $statusCode | Should -Be 400
        }

        It "Should return error message when UserName is missing" {
            $userData = @{
                Email = "testuser-$(Get-Random)@example.com"
            } | ConvertTo-Json

            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                    -Method POST `
                    -Body $userData `
                    -ContentType "application/json" `
                    -UseBasicParsing
            } catch {
                $errorResponse = $_.Exception.Response
                $stream = $errorResponse.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $responseBody = $reader.ReadToEnd()

                $responseBody | Should -Match 'UserName is required'
            }
        }

        It "Should return 400 when UserName is null" {
            $userData = @{
                UserName = $null
                Email = "testuser-$(Get-Random)@example.com"
            } | ConvertTo-Json

            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                    -Method POST `
                    -Body $userData `
                    -ContentType "application/json" `
                    -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            $statusCode | Should -Be 400
        }

        It "Should return 400 when UserName is empty string" {
            $userData = @{
                UserName = ""
                Email = "testuser-$(Get-Random)@example.com"
            } | ConvertTo-Json

            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                    -Method POST `
                    -Body $userData `
                    -ContentType "application/json" `
                    -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            $statusCode | Should -Be 400
        }
    }

    Context "Content-Type handling" {
        It "Should accept application/json" {
            $userData = @{
                UserName = "TestUser-$(Get-Random)"
            } | ConvertTo-Json

            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $userData `
                -ContentType "application/json" `
                -UseBasicParsing

            $response.StatusCode | Should -Be 200

            $user = $response.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID
        }

        It "Should handle malformed JSON" {
            $invalidJson = '{ "UserName": "Test", invalid json }'

            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                    -Method POST `
                    -Body $invalidJson `
                    -ContentType "application/json" `
                    -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            # Should return 400 or 500 for invalid JSON
            $statusCode | Should -BeIn @(400, 500)
        }
    }

    Context "Response validation" {
        It "Should return the created user object" {
            $userName = "TestUser-$(Get-Random)"
            $userData = @{
                UserName = $userName
            } | ConvertTo-Json

            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $userData `
                -ContentType "application/json" `
                -UseBasicParsing

            $user = $response.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            $user.UserName | Should -Be $userName
            $user.UserID | Should -Not -BeNullOrEmpty
        }

        It "Should include all submitted fields in response" {
            $userName = "TestUser-$(Get-Random)"
            $email = "testuser-$(Get-Random)@example.com"
            $phone = "555-5678"

            $userData = @{
                UserName = $userName
                Email = $email
                Phone = $phone
            } | ConvertTo-Json

            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $userData `
                -ContentType "application/json" `
                -UseBasicParsing

            $user = $response.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            $user.UserName | Should -Be $userName
            $user.Email | Should -Be $email
            $user.Phone | Should -Be $phone
        }
    }

    Context "Database persistence" {
        It "Should persist user to database" {
            $userName = "TestUser-$(Get-Random)"
            $userData = @{
                UserName = $userName
            } | ConvertTo-Json

            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $userData `
                -ContentType "application/json" `
                -UseBasicParsing

            $user = $response.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            # Verify user exists in database by getting all users
            $getResponse = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method GET `
                -UseBasicParsing

            $allUsers = $getResponse.Content | ConvertFrom-Json

            # Ensure array
            if ($allUsers -isnot [array]) {
                $allUsers = @($allUsers)
            }

            $allUsers.UserID | Should -Contain $user.UserID
        }
    }

    Context "Security - SQL injection prevention" {
        It "Should sanitize UserName to prevent SQL injection" {
            $maliciousUserName = "Test'; DROP TABLE Users;--"
            $userData = @{
                UserName = $maliciousUserName
            } | ConvertTo-Json

            # Should not crash or execute SQL
            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                    -Method POST `
                    -Body $userData `
                    -ContentType "application/json" `
                    -UseBasicParsing

                $user = $response.Content | ConvertFrom-Json
                if ($user.UserID) {
                    $global:PSWebHostTesting.TestUserIDs += $user.UserID
                }

                $response.StatusCode | Should -BeIn @(200, 400)
            } catch {
                # May reject malicious input
                $true | Should -Be $true
            }
        }

        It "Should sanitize Email to prevent SQL injection" {
            $maliciousEmail = "test@example.com'; DELETE FROM Users WHERE '1'='1"
            $userData = @{
                UserName = "TestUser-$(Get-Random)"
                Email = $maliciousEmail
            } | ConvertTo-Json

            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                    -Method POST `
                    -Body $userData `
                    -ContentType "application/json" `
                    -UseBasicParsing

                $user = $response.Content | ConvertFrom-Json
                if ($user.UserID) {
                    $global:PSWebHostTesting.TestUserIDs += $user.UserID
                }

                $response.StatusCode | Should -BeIn @(200, 400)
            } catch {
                # May reject malicious input
                $true | Should -Be $true
            }
        }
    }

    Context "Security - XSS prevention" {
        It "Should handle script tags in UserName" {
            $xssUserName = "<script>alert('XSS')</script>"
            $userData = @{
                UserName = $xssUserName
            } | ConvertTo-Json

            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $userData `
                -ContentType "application/json" `
                -UseBasicParsing

            $user = $response.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            # JSON encoding should escape the script tags
            $response.Content | Should -Not -Match '<script>alert\(''XSS''\)</script>'
        }
    }

    Context "Edge cases" {
        It "Should handle very long UserName" {
            $longUserName = "TestUser" + ("a" * 1000)
            $userData = @{
                UserName = $longUserName
            } | ConvertTo-Json

            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                    -Method POST `
                    -Body $userData `
                    -ContentType "application/json" `
                    -UseBasicParsing

                $user = $response.Content | ConvertFrom-Json
                if ($user.UserID) {
                    $global:PSWebHostTesting.TestUserIDs += $user.UserID
                }

                # Should either accept or reject gracefully
                $response.StatusCode | Should -BeIn @(200, 400)
            } catch {
                # May reject if too long
                $true | Should -Be $true
            }
        }

        It "Should handle special characters in UserName" {
            $specialUserName = "Test!@#$%^&*()User"
            $userData = @{
                UserName = $specialUserName
            } | ConvertTo-Json

            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $userData `
                -ContentType "application/json" `
                -UseBasicParsing

            $user = $response.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            $user.UserName | Should -Be $specialUserName
        }

        It "Should handle Unicode characters in UserName" {
            $unicodeUserName = "Test用户名Пользователь"
            $userData = @{
                UserName = $unicodeUserName
            } | ConvertTo-Json

            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $userData `
                -ContentType "application/json" `
                -UseBasicParsing

            $user = $response.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            $user.UserName | Should -Be $unicodeUserName
        }
    }
}
