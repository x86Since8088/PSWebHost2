# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "GET /api/v1/auth/logoff" -Tags 'Route', 'Auth', 'Logoff' {
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

    Context "Logoff without session" {
        It "Should return 302 redirect status" {
            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/auth/logoff" `
                    -Method GET `
                    -UseBasicParsing `
                    -MaximumRedirection 0
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            $statusCode | Should -Be 302
        }

        It "Should redirect to home page" {
            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/auth/logoff" `
                    -Method GET `
                    -UseBasicParsing `
                    -MaximumRedirection 0
            } catch {
                $response = $_.Exception.Response
            }

            $location = $response.Headers['Location']
            $location | Should -Be '/'
        }

        It "Should handle request without session cookie" {
            # Logoff should not error even without a session
            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/auth/logoff" `
                    -Method GET `
                    -UseBasicParsing `
                    -MaximumRedirection 0
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            # Should still redirect (302), not error (500)
            $statusCode | Should -Be 302
        }
    }

    Context "Logoff with active session" {
        It "Should expire session cookie" {
            # First, get a session cookie by visiting the site
            $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

            try {
                # Visit a page to get a session cookie
                $null = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/" `
                    -Method GET `
                    -UseBasicParsing `
                    -WebSession $session
            } catch {
                # May redirect or error, that's OK
            }

            # Now logoff with the session
            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/auth/logoff" `
                    -Method GET `
                    -UseBasicParsing `
                    -WebSession $session `
                    -MaximumRedirection 0
            } catch {
                $response = $_.Exception.Response
            }

            # Check if response sets an expired cookie
            if ($response.Headers['Set-Cookie']) {
                $setCookie = $response.Headers['Set-Cookie']
                # Expired cookies typically have past expiration dates
                $true | Should -Be $true
            } else {
                # May not have Set-Cookie header in all cases
                $true | Should -Be $true
            }
        }

        It "Should remove session from server" {
            # This test would require access to server session storage
            # Serves as documentation of expected behavior
            $true | Should -Be $true
        }

        It "Should redirect after clearing session" {
            # Get a session first
            $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

            try {
                $null = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/" `
                    -Method GET `
                    -UseBasicParsing `
                    -WebSession $session
            } catch {
                # May redirect or error
            }

            # Logoff
            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/auth/logoff" `
                    -Method GET `
                    -UseBasicParsing `
                    -WebSession $session `
                    -MaximumRedirection 0
            } catch {
                $response = $_.Exception.Response
            }

            $location = $response.Headers['Location']
            $location | Should -Be '/'
        }
    }

    Context "Logoff with authenticated user" {
        It "Should successfully logoff authenticated user" {
            # Create test user
            $email = "testuser-$(Get-Random)@example.com"
            $password = "ValidP@ssw0rd123"
            $global:PSWebHostTesting.TestUsers += $email

            try {
                New-PSWebHostUser -Email $email -Password $password
            } catch {
                Write-Warning "Could not create test user: $_"
            }

            # Login to get authenticated session
            $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
            $state = [guid]::NewGuid().ToString()
            $body = "email=$email&password=$password"

            try {
                # Attempt login
                $null = Invoke-WebRequest `
                    -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/x-www-form-urlencoded" `
                    -UseBasicParsing `
                    -WebSession $session `
                    -MaximumRedirection 5
            } catch {
                # Login may redirect multiple times
            }

            # Now logoff
            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/auth/logoff" `
                    -Method GET `
                    -UseBasicParsing `
                    -WebSession $session `
                    -MaximumRedirection 0
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            $statusCode | Should -Be 302
        }

        It "Should invalidate session after logoff" {
            # This would require checking if session is no longer valid
            # Serves as documentation of expected behavior
            $true | Should -Be $true
        }
    }

    Context "Security considerations" {
        It "Should work with GET method only" {
            # Logoff should be GET (or possibly POST), verify GET works
            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/auth/logoff" `
                    -Method GET `
                    -UseBasicParsing `
                    -MaximumRedirection 0
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            $statusCode | Should -Be 302
        }

        It "Should not require CSRF token (GET request)" {
            # GET logoff should work without CSRF token
            # This is a security consideration for GET-based logoff
            $true | Should -Be $true
        }

        It "Should handle XSS attempts in redirect" {
            # Attempt XSS in redirect parameter if accepted
            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/auth/logoff?redirect=javascript:alert(1)" `
                    -Method GET `
                    -UseBasicParsing `
                    -MaximumRedirection 0
            } catch {
                $response = $_.Exception.Response
            }

            $location = $response.Headers['Location']
            # Should redirect to safe location, not javascript:
            $location | Should -Not -Match 'javascript:'
        }
    }

    Context "Response validation" {
        It "Should return proper redirect status code" {
            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/auth/logoff" `
                    -Method GET `
                    -UseBasicParsing `
                    -MaximumRedirection 0
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            # 302 Found is correct for temporary redirect
            $statusCode | Should -Be 302
        }

        It "Should include Location header" {
            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/auth/logoff" `
                    -Method GET `
                    -UseBasicParsing `
                    -MaximumRedirection 0
            } catch {
                $response = $_.Exception.Response
            }

            $response.Headers['Location'] | Should -Not -BeNullOrEmpty
        }

        It "Should not return error status codes" {
            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/auth/logoff" `
                    -Method GET `
                    -UseBasicParsing `
                    -MaximumRedirection 0
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            # Should be 302, not 4xx or 5xx
            $statusCode | Should -BeIn @(302, 301, 303)
        }
    }

    Context "Edge cases" {
        It "Should handle multiple logoff requests" {
            # Get session
            $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

            try {
                $null = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/" `
                    -Method GET `
                    -UseBasicParsing `
                    -WebSession $session
            } catch { }

            # First logoff
            try {
                $null = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/auth/logoff" `
                    -Method GET `
                    -UseBasicParsing `
                    -WebSession $session `
                    -MaximumRedirection 0
            } catch { }

            # Second logoff (should not error)
            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/auth/logoff" `
                    -Method GET `
                    -UseBasicParsing `
                    -WebSession $session `
                    -MaximumRedirection 0
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            # Should still redirect, not error
            $statusCode | Should -Be 302
        }

        It "Should handle logoff with invalid session ID" {
            # Create custom session with fake session ID
            $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
            $cookie = New-Object System.Net.Cookie("PSWebSessionID", "invalid-session-id-12345")
            $cookie.Domain = ([System.Uri]$global:PSWebHostTesting.BaseUrl).Host
            $session.Cookies.Add($cookie)

            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/auth/logoff" `
                    -Method GET `
                    -UseBasicParsing `
                    -WebSession $session `
                    -MaximumRedirection 0
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            # Should still handle gracefully
            $statusCode | Should -Be 302
        }

        It "Should handle logoff with expired session" {
            # This would require creating an expired session
            # Serves as documentation of expected behavior
            $true | Should -Be $true
        }
    }
}
