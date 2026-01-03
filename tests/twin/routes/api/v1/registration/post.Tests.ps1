# Registration POST endpoint tests
# Tests the multi-step registration survey flow

# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "POST /api/v1/registration" -Tags 'Route', 'Registration', 'Auth' {

    BeforeAll {
        $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'

        # Initialize global testing hashtable if not exists
        if (-not $global:PSWebHostTesting) {
            $global:PSWebHostTesting = [hashtable]::Synchronized(@{})
        }

        # Import helper modules
        Import-Module (Join-Path $ProjectRoot 'tests\twin\helpers\Test-Helpers.psm1') -Force -ErrorAction SilentlyContinue

        # Get or start test WebHost
        try {
            $webHost = Get-TestWebHost -ProjectRoot $ProjectRoot -ErrorAction Stop
            $global:PSWebHostTesting.WebHost = $webHost
            $global:PSWebHostTesting.BaseUrl = $webHost.Url.TrimEnd('/')
            $global:PSWebHostTesting.WebHostStarted = $true
            $global:PSWebHostTesting.RegistrationTestEmails = @()

            # Wait a moment for routes to fully load
            Start-Sleep -Seconds 2
        } catch {
            Write-Warning "Failed to get test WebHost: $_"
            $global:PSWebHostTesting.WebHostStarted = $false
        }
    }

    AfterAll {
        # Clean up any test registration records if needed
        if ($global:PSWebHostTesting.RegistrationTestEmails -and $global:PSWebHostTesting.RegistrationTestEmails.Count -gt 0) {
            Write-Verbose "Test emails used: $($global:PSWebHostTesting.RegistrationTestEmails -join ', ')"
        }
    }

    Context "Initial request without page parameter" {

        It "Should return 200 OK status" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $body = ""
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $response.StatusCode | Should -Be 200
        }

        It "Should return JSON content type" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $body = ""
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $response.Headers["Content-Type"] | Should -Match "application/json"
        }

        It "Should return status 'continue'" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $body = ""
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $json = $response.Content | ConvertFrom-Json
            $json.status | Should -Be "continue"
        }

        It "Should return ProvideEmail form HTML" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $body = ""
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $json = $response.Content | ConvertFrom-Json
            $json.Html | Should -Match "Step 1: Provide Email"
        }

        It "Should include email input field in form" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $body = ""
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $json = $response.Content | ConvertFrom-Json
            $json.Html | Should -Match "type='email'"
            $json.Html | Should -Match "name='email'"
        }

        It "Should include hidden page field" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $body = ""
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $json = $response.Content | ConvertFrom-Json
            $json.Html | Should -Match "type='hidden'"
            $json.Html | Should -Match "name='page'"
            $json.Html | Should -Match "value='ProvideEmail'"
        }

        It "Should include submit button" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $body = ""
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $json = $response.Content | ConvertFrom-Json
            $json.Html | Should -Match "Send Confirmation"
        }
    }

    Context "ProvideEmail page with valid email" {

        It "Should return 200 OK for valid email" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $testEmail = "test-" + [guid]::NewGuid().ToString().Substring(0,8) + "@example.com"
            $global:PSWebHostTesting.RegistrationTestEmails += $testEmail

            $body = "page=ProvideEmail&email=$testEmail"
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $response.StatusCode | Should -Be 200
        }

        It "Should return status 'continue' for valid email" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $testEmail = "test-" + [guid]::NewGuid().ToString().Substring(0,8) + "@example.com"
            $global:PSWebHostTesting.RegistrationTestEmails += $testEmail

            $body = "page=ProvideEmail&email=$testEmail"
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $json = $response.Content | ConvertFrom-Json
            $json.status | Should -Be "continue"
        }

        It "Should return ConfirmEmail page for valid email" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $testEmail = "test-" + [guid]::NewGuid().ToString().Substring(0,8) + "@example.com"
            $global:PSWebHostTesting.RegistrationTestEmails += $testEmail

            $body = "page=ProvideEmail&email=$testEmail"
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $json = $response.Content | ConvertFrom-Json
            $json.Html | Should -Match "Step 2: Confirm Email"
        }

        It "Should include confirmation message" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $testEmail = "test-" + [guid]::NewGuid().ToString().Substring(0,8) + "@example.com"
            $global:PSWebHostTesting.RegistrationTestEmails += $testEmail

            $body = "page=ProvideEmail&email=$testEmail"
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $json = $response.Content | ConvertFrom-Json
            $json.Html | Should -Match "confirmation link has been sent"
        }

        It "Should include email in hidden field" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $testEmail = "test-" + [guid]::NewGuid().ToString().Substring(0,8) + "@example.com"
            $global:PSWebHostTesting.RegistrationTestEmails += $testEmail

            $body = "page=ProvideEmail&email=$testEmail"
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $json = $response.Content | ConvertFrom-Json
            $json.Html | Should -Match ([regex]::Escape($testEmail))
        }
    }

    Context "ProvideEmail page with invalid email format" {

        It "Should return 400 for invalid email format" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $body = "page=ProvideEmail&email=invalid-email"
            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                    -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Be 400
        }

        It "Should return 400 for email without domain" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $body = "page=ProvideEmail&email=user@"
            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                    -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Be 400
        }

        It "Should return 400 for email without TLD" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $body = "page=ProvideEmail&email=user@domain"
            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                    -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Be 400
        }

        It "Should return 400 for empty email" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $body = "page=ProvideEmail&email="
            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                    -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Be 400
        }
    }

    Context "ConfirmEmail page - email not yet confirmed" {

        It "Should return 200 OK when checking unconfirmed email" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $testEmail = "unconfirmed-" + [guid]::NewGuid().ToString().Substring(0,8) + "@example.com"
            $global:PSWebHostTesting.RegistrationTestEmails += $testEmail

            $body = "page=ConfirmEmail&email=$testEmail"
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $response.StatusCode | Should -Be 200
        }

        It "Should return status 'continue' for unconfirmed email" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $testEmail = "unconfirmed-" + [guid]::NewGuid().ToString().Substring(0,8) + "@example.com"
            $global:PSWebHostTesting.RegistrationTestEmails += $testEmail

            $body = "page=ConfirmEmail&email=$testEmail"
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $json = $response.Content | ConvertFrom-Json
            $json.status | Should -Be "continue"
        }

        It "Should show 'not confirmed yet' message" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $testEmail = "unconfirmed-" + [guid]::NewGuid().ToString().Substring(0,8) + "@example.com"
            $global:PSWebHostTesting.RegistrationTestEmails += $testEmail

            $body = "page=ConfirmEmail&email=$testEmail"
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $json = $response.Content | ConvertFrom-Json
            $json.Html | Should -Match "Not confirmed yet"
        }

        It "Should include check confirmation button" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $testEmail = "unconfirmed-" + [guid]::NewGuid().ToString().Substring(0,8) + "@example.com"
            $global:PSWebHostTesting.RegistrationTestEmails += $testEmail

            $body = "page=ConfirmEmail&email=$testEmail"
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $json = $response.Content | ConvertFrom-Json
            $json.Html | Should -Match "Check Confirmation Status"
        }
    }

    Context "Security - SQL Injection prevention" {

        It "Should not error on SQL injection in email field" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $sqlInjection = "test@example.com'; DROP TABLE users; --"
            $encodedEmail = [System.Web.HttpUtility]::UrlEncode($sqlInjection)
            $body = "page=ProvideEmail&email=$encodedEmail"

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                    -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Should return 400 (invalid email format) not 500 (server error)
            $statusCode | Should -Not -Be 500
        }

        It "Should handle SQL injection in ConfirmEmail page" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $sqlInjection = "'; DELETE FROM account_email_confirmation; --"
            $encodedEmail = [System.Web.HttpUtility]::UrlEncode($sqlInjection)
            $body = "page=ConfirmEmail&email=$encodedEmail"

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                    -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Not -Be 500
        }

        It "Should sanitize UNION SELECT injection" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $sqlInjection = "test@example.com' UNION SELECT * FROM users --"
            $encodedEmail = [System.Web.HttpUtility]::UrlEncode($sqlInjection)
            $body = "page=ConfirmEmail&email=$encodedEmail"

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                    -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Not -Be 500
        }
    }

    Context "Edge cases" {

        It "Should handle unknown page name gracefully" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $body = "page=UnknownPage"
            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                    -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Should not crash with 500
            $statusCode | Should -Not -Be 500
        }

        It "Should handle very long email address" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $longEmail = ("a" * 200) + "@example.com"
            $body = "page=ProvideEmail&email=$longEmail"

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                    -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Should handle gracefully (200 or 400), not crash
            $statusCode | Should -Not -Be 500
        }

        It "Should handle special characters in email local part" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $testEmail = "test.user+tag@example.com"
            $global:PSWebHostTesting.RegistrationTestEmails += $testEmail

            $body = "page=ProvideEmail&email=$testEmail"
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $response.StatusCode | Should -Be 200
        }

        It "Should handle empty request body" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body "" -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            # Should return initial form
            $response.StatusCode | Should -Be 200
        }

        It "Should handle duplicate registration attempts" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $testEmail = "duplicate-" + [guid]::NewGuid().ToString().Substring(0,8) + "@example.com"
            $global:PSWebHostTesting.RegistrationTestEmails += $testEmail

            $body = "page=ProvideEmail&email=$testEmail"

            # First registration
            $response1 = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            # Second registration with same email
            $response2 = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            # Should handle gracefully (may create new record or reuse existing)
            $response2.StatusCode | Should -Be 200
        }
    }

    Context "Response format validation" {

        It "Should return valid JSON structure" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $body = ""
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            { $response.Content | ConvertFrom-Json } | Should -Not -Throw
        }

        It "Should have 'status' field in response" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $body = ""
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $json = $response.Content | ConvertFrom-Json
            $json.PSObject.Properties.Name | Should -Contain "status"
        }

        It "Should have 'Html' field in response" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $body = ""
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $json = $response.Content | ConvertFrom-Json
            $json.PSObject.Properties.Name | Should -Contain "Html"
        }

        It "Should have form element in HTML response" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $body = ""
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing

            $json = $response.Content | ConvertFrom-Json
            $json.Html | Should -Match "<form"
        }
    }
}
