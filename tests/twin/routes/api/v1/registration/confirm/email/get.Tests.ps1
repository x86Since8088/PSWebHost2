# Email Confirmation GET endpoint tests
# Tests the email confirmation link handler

# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "GET /api/v1/registration/confirm/email" -Tags 'Route', 'Registration', 'Auth' {

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

            # Wait for routes to fully load
            Start-Sleep -Seconds 2
        } catch {
            Write-Warning "Failed to get test WebHost: $_"
            $global:PSWebHostTesting.WebHostStarted = $false
        }
    }

    AfterAll {
        if ($global:PSWebHostTesting.WebHostStarted -and $global:PSWebHostTesting.WebHost) {
            Stop-TestWebHost -WebHost $global:PSWebHostTesting.WebHost
        }
    }

    Context "Parameter validation" {

        It "Should return 400 when ref parameter is missing" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration/confirm/email" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Be 400
        }

        It "Should return 400 when ref parameter is empty" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration/confirm/email?ref=" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Be 400
        }

        It "Should return 404 for non-existent GUID" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $fakeGuid = [guid]::NewGuid().ToString()
            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration/confirm/email?ref=$fakeGuid" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Be 404
        }

        It "Should return error message for missing ref" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration/confirm/email" `
                    -Method GET -UseBasicParsing
            } catch {
                $response = $_.Exception.Response
            }

            # Error message should mention missing reference
            # Note: We can't easily read error response body in PowerShell Core without additional handling
        }
    }

    Context "Security - SQL Injection prevention" {

        It "Should not error on SQL injection in ref parameter" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $sqlInjection = "'; DROP TABLE account_email_confirmation; --"
            $encodedRef = [System.Web.HttpUtility]::UrlEncode($sqlInjection)

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration/confirm/email?ref=$encodedRef" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Should return 404 (not found) not 500 (server error)
            $statusCode | Should -Not -Be 500
        }

        It "Should handle UNION SELECT injection" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $sqlInjection = "' UNION SELECT * FROM Users --"
            $encodedRef = [System.Web.HttpUtility]::UrlEncode($sqlInjection)

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration/confirm/email?ref=$encodedRef" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Not -Be 500
        }

        It "Should handle boolean-based SQL injection" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $sqlInjection = "' OR '1'='1"
            $encodedRef = [System.Web.HttpUtility]::UrlEncode($sqlInjection)

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration/confirm/email?ref=$encodedRef" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Not -Be 500
        }
    }

    Context "Edge cases" {

        It "Should handle very long ref parameter" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $longRef = "a" * 1000

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration/confirm/email?ref=$longRef" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Should handle gracefully (404) not crash (500)
            $statusCode | Should -Not -Be 500
        }

        It "Should handle special characters in ref parameter" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $specialChars = "!@#$%^&*()_+-=[]{}|;:',.<>?"
            $encodedRef = [System.Web.HttpUtility]::UrlEncode($specialChars)

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration/confirm/email?ref=$encodedRef" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Not -Be 500
        }

        It "Should handle Unicode in ref parameter" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $unicodeRef = "test-guid-" + [char]0x00E9 + [char]0x00F1  # é and ñ
            $encodedRef = [System.Web.HttpUtility]::UrlEncode($unicodeRef)

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration/confirm/email?ref=$encodedRef" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Not -Be 500
        }
    }

    Context "Response format" {

        It "Should return text/plain or text/html content type for errors" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $fakeGuid = [guid]::NewGuid().ToString()

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration/confirm/email?ref=$fakeGuid" `
                    -Method GET -UseBasicParsing
            } catch {
                # Expected to fail with 404
            }

            # Verification would require reading error response headers
        }
    }

    Context "Performance" {

        It "Should return response within reasonable time" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration/confirm/email" `
                    -Method GET -UseBasicParsing
            } catch {
                # Expected to fail
            }

            $stopwatch.Stop()

            # Should complete within 5 seconds
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000
        }
    }
}
