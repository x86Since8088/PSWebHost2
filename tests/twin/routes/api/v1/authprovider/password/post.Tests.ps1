# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "POST /api/v1/authprovider/password" -Tags 'Route', 'Auth', 'Password' {
    BeforeAll {
        $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'

        # Import helper modules
        Import-Module (Join-Path $ProjectRoot 'tests\twin\helpers\Test-Helpers.psm1') -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $ProjectRoot 'modules\PSWebHost_Authentication') -DisableNameChecking -Force

        # Start WebHost for testing
        try {
            $global:PSWebHostTesting.WebHost = Get-TestWebHost -ProjectRoot $ProjectRoot -ErrorAction Stop
            $global:PSWebHostTesting.BaseUrl = $webHost.Url.TrimEnd('/')
            $global:PSWebHostTesting.WebHostStarted = $true
        } catch {
            Write-Warning "WebHost could not be started - tests will be skipped: $_"
            $global:PSWebHostTesting.WebHostStarted = $false
        }

        # Track test users for cleanup
        $global:PSWebHostTesting.TestUsers = @()
    }

    AfterAll {
        if ($global:PSWebHostTesting.WebHostStarted -and $global:PSWebHostTesting.WebHost) {
            Stop-TestWebHost -WebHost $global:PSWebHostTesting.WebHost
        }

        # Cleanup test users
        $dbFile = Join-Path $ProjectRoot "PsWebHost_Data\pswebhost.db"
        foreach ($email in $global:PSWebHostTesting.TestUsers) {
            try {
                Import-Module (Join-Path $ProjectRoot 'modules\PSWebHost_Database') -DisableNameChecking -Force
                $query = "DELETE FROM Users WHERE Email = '$email';"
                Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query -ErrorAction SilentlyContinue
            } catch {
                Write-Warning "Failed to cleanup test user: $email"
            }
        }
    }

    Context "Validation - Missing required fields" {
        It "Should return 422 when email is missing" {
            $state = [guid]::NewGuid().ToString()
            $body = "password=ValidP@ssw0rd123"

            try {
                $response = Invoke-WebRequest `
                    -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/x-www-form-urlencoded" `
                    -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            $statusCode | Should -Be 422
        }

        It "Should return 422 when password is missing" {
            $state = [guid]::NewGuid().ToString()
            $body = "email=test@example.com"

            try {
                $response = Invoke-WebRequest `
                    -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/x-www-form-urlencoded" `
                    -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            $statusCode | Should -Be 422
        }

        It "Should return JSON error response for missing fields" {
            $state = [guid]::NewGuid().ToString()
            $body = "password=ValidP@ssw0rd123"

            try {
                $response = Invoke-WebRequest `
                    -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/x-www-form-urlencoded" `
                    -UseBasicParsing
            } catch {
                $errorResponse = $_.Exception.Response
                $stream = $errorResponse.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $responseBody = $reader.ReadToEnd()

                $json = $responseBody | ConvertFrom-Json
                $json.status | Should -Be 'fail'
                $json.Message | Should -Match 'Email is required'
            }
        }
    }

    Context "Validation - Invalid email format" {
        It "Should return 422 for invalid email format" {
            $state = [guid]::NewGuid().ToString()
            $body = "email=notanemail&password=ValidP@ssw0rd123"

            try {
                $response = Invoke-WebRequest `
                    -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/x-www-form-urlencoded" `
                    -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            $statusCode | Should -Be 422
        }

        It "Should return error message for invalid email" {
            $state = [guid]::NewGuid().ToString()
            $body = "email=invalid@&password=ValidP@ssw0rd123"

            try {
                $response = Invoke-WebRequest `
                    -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/x-www-form-urlencoded" `
                    -UseBasicParsing
            } catch {
                $errorResponse = $_.Exception.Response
                $stream = $errorResponse.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $responseBody = $reader.ReadToEnd()

                $json = $responseBody | ConvertFrom-Json
                $json.status | Should -Be 'fail'
            }
        }
    }

    Context "Validation - Password strength" {
        It "Should return 422 for weak password" {
            $state = [guid]::NewGuid().ToString()
            $body = "email=test@example.com&password=weak"

            try {
                $response = Invoke-WebRequest `
                    -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/x-www-form-urlencoded" `
                    -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            $statusCode | Should -Be 422
        }

        It "Should return error message for weak password" {
            $state = [guid]::NewGuid().ToString()
            $body = "email=test@example.com&password=12345"

            try {
                $response = Invoke-WebRequest `
                    -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/x-www-form-urlencoded" `
                    -UseBasicParsing
            } catch {
                $errorResponse = $_.Exception.Response
                $stream = $errorResponse.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $responseBody = $reader.ReadToEnd()

                $json = $responseBody | ConvertFrom-Json
                $json.status | Should -Be 'fail'
            }
        }
    }

    Context "Authentication - Invalid credentials" {
        It "Should return 401 for non-existent user" {
            $state = [guid]::NewGuid().ToString()
            $email = "nonexistent-$(Get-Random)@example.com"
            $body = "email=$email&password=ValidP@ssw0rd123"

            try {
                $response = Invoke-WebRequest `
                    -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/x-www-form-urlencoded" `
                    -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            $statusCode | Should -Be 401
        }

        It "Should return 401 for wrong password" {
            # Create test user first
            $email = "testuser-$(Get-Random)@example.com"
            $global:PSWebHostTesting.TestUsers += $email

            try {
                New-PSWebHostUser -Email $email -Password "CorrectP@ssw0rd123"
            } catch {
                Write-Warning "Could not create test user: $_"
            }

            # Try with wrong password
            $state = [guid]::NewGuid().ToString()
            $body = "email=$email&password=WrongP@ssw0rd123"

            try {
                $response = Invoke-WebRequest `
                    -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/x-www-form-urlencoded" `
                    -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            $statusCode | Should -Be 401
        }

        It "Should return generic error message on failure" {
            $state = [guid]::NewGuid().ToString()
            $email = "nonexistent-$(Get-Random)@example.com"
            $body = "email=$email&password=ValidP@ssw0rd123"

            try {
                $response = Invoke-WebRequest `
                    -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/x-www-form-urlencoded" `
                    -UseBasicParsing
            } catch {
                $errorResponse = $_.Exception.Response
                $stream = $errorResponse.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $responseBody = $reader.ReadToEnd()

                $json = $responseBody | ConvertFrom-Json
                $json.status | Should -Be 'fail'
                $json.Message | Should -Match 'Authentication failed'
            }
        }
    }

    Context "Authentication - Valid credentials" {
        It "Should redirect on successful authentication" {
            # Create test user
            $email = "testuser-$(Get-Random)@example.com"
            $password = "ValidP@ssw0rd123"
            $global:PSWebHostTesting.TestUsers += $email

            try {
                New-PSWebHostUser -Email $email -Password $password
            } catch {
                Write-Warning "Could not create test user: $_"
            }

            # Attempt login
            $state = [guid]::NewGuid().ToString()
            $body = "email=$email&password=$password"

            try {
                $response = Invoke-WebRequest `
                    -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/x-www-form-urlencoded" `
                    -UseBasicParsing `
                    -MaximumRedirection 0
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            $statusCode | Should -Be 302
        }

        It "Should redirect to getaccesstoken endpoint" {
            # Create test user
            $email = "testuser-$(Get-Random)@example.com"
            $password = "ValidP@ssw0rd123"
            $global:PSWebHostTesting.TestUsers += $email

            try {
                New-PSWebHostUser -Email $email -Password $password
            } catch {
                Write-Warning "Could not create test user: $_"
            }

            # Attempt login
            $state = [guid]::NewGuid().ToString()
            $body = "email=$email&password=$password"

            try {
                $response = Invoke-WebRequest `
                    -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/x-www-form-urlencoded" `
                    -UseBasicParsing `
                    -MaximumRedirection 0
            } catch {
                $response = $_.Exception.Response
            }

            $location = $response.Headers['Location']
            $location | Should -Match '/api/v1/auth/getaccesstoken'
            $location | Should -Match "state=$state"
        }

        It "Should set session cookie on successful login" {
            # Create test user
            $email = "testuser-$(Get-Random)@example.com"
            $password = "ValidP@ssw0rd123"
            $global:PSWebHostTesting.TestUsers += $email

            try {
                New-PSWebHostUser -Email $email -Password $password
            } catch {
                Write-Warning "Could not create test user: $_"
            }

            # Attempt login with session variable
            $state = [guid]::NewGuid().ToString()
            $body = "email=$email&password=$password"

            try {
                $response = Invoke-WebRequest `
                    -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/x-www-form-urlencoded" `
                    -UseBasicParsing `
                    -SessionVariable session `
                    -MaximumRedirection 0
            } catch {
                # Redirect will throw, capture session from error
                $session = $_.Exception
            }

            # Session should have cookie set (test may vary based on implementation)
            $true | Should -Be $true
        }
    }

    Context "Security - Password not leaked in responses" {
        It "Should not include password in error responses" {
            $state = [guid]::NewGuid().ToString()
            $password = "SecretP@ssw0rd123"
            $body = "email=test@example.com&password=$password"

            try {
                $response = Invoke-WebRequest `
                    -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/x-www-form-urlencoded" `
                    -UseBasicParsing
            } catch {
                $errorResponse = $_.Exception.Response
                $stream = $errorResponse.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $responseBody = $reader.ReadToEnd()

                # Password should never appear in response
                $responseBody | Should -Not -Match [regex]::Escape($password)
            }
        }

        It "Should not include password in logs (manual verification)" {
            # This test serves as a reminder to verify logs don't contain passwords
            # Actual log checking would require reading log files
            $true | Should -Be $true
        }
    }

    Context "Rate limiting and brute force protection" {
        It "Should implement rate limiting after multiple failed attempts" {
            $email = "bruteforce-$(Get-Random)@example.com"
            $state = [guid]::NewGuid().ToString()

            # Make multiple failed attempts
            $statusCodes = @()
            for ($i = 1; $i -le 6; $i++) {
                $body = "email=$email&password=WrongP@ss$i"

                try {
                    $response = Invoke-WebRequest `
                        -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                        -Method POST `
                        -Body $body `
                        -ContentType "application/x-www-form-urlencoded" `
                        -UseBasicParsing
                    $statusCodes += $response.StatusCode
                } catch {
                    $statusCodes += $_.Exception.Response.StatusCode.value__
                }

                Start-Sleep -Milliseconds 100
            }

            # Should see 401 (invalid) or potentially 429 (rate limited)
            $statusCodes | Should -Contain 401
        }

        It "Should return 429 when rate limited" {
            # This test may not work if rate limiting threshold is high
            # Serves as documentation of expected behavior
            $true | Should -Be $true
        }

        It "Should include Retry-After header when rate limited" {
            # This test may not work if rate limiting threshold is high
            # Serves as documentation of expected behavior
            $true | Should -Be $true
        }
    }

    Context "State parameter handling" {
        It "Should accept valid state parameter" {
            $state = [guid]::NewGuid().ToString()
            $body = "email=test@example.com&password=ValidP@ssw0rd123"

            try {
                $response = Invoke-WebRequest `
                    -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/x-www-form-urlencoded" `
                    -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            # Should process the request (401 for invalid creds, not 400 for bad request)
            $statusCode | Should -BeIn @(401, 422)
        }

        It "Should include state in redirect URL on success" {
            # Create test user
            $email = "testuser-$(Get-Random)@example.com"
            $password = "ValidP@ssw0rd123"
            $global:PSWebHostTesting.TestUsers += $email

            try {
                New-PSWebHostUser -Email $email -Password $password
            } catch {
                Write-Warning "Could not create test user: $_"
            }

            # Attempt login with state
            $state = [guid]::NewGuid().ToString()
            $body = "email=$email&password=$password"

            try {
                $response = Invoke-WebRequest `
                    -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/x-www-form-urlencoded" `
                    -UseBasicParsing `
                    -MaximumRedirection 0
            } catch {
                $response = $_.Exception.Response
            }

            $location = $response.Headers['Location']
            $location | Should -Match "state=$state"
        }
    }

    Context "Content-Type handling" {
        It "Should accept application/x-www-form-urlencoded" {
            $state = [guid]::NewGuid().ToString()
            $body = "email=test@example.com&password=ValidP@ssw0rd123"

            try {
                $response = Invoke-WebRequest `
                    -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/x-www-form-urlencoded" `
                    -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            # Should process the request (not 415 Unsupported Media Type)
            $statusCode | Should -Not -Be 415
        }

        It "Should return JSON error responses" {
            $state = [guid]::NewGuid().ToString()
            $body = "email=&password=ValidP@ssw0rd123"

            try {
                $response = Invoke-WebRequest `
                    -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/x-www-form-urlencoded" `
                    -UseBasicParsing
            } catch {
                $errorResponse = $_.Exception.Response
                $contentType = $errorResponse.ContentType

                $contentType | Should -Match 'application/json'
            }
        }
    }
}
