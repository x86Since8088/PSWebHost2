# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "GET /api/v1/registration" -Tags 'Route', 'Registration', 'Auth' {
    BeforeAll {
        $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'

        # Initialize global testing hashtable if not exists
        if (-not $global:PSWebHostTesting) {
            $global:PSWebHostTesting = [hashtable]::Synchronized(@{})
        }

        # Import helper modules
        Import-Module (Join-Path $ProjectRoot 'tests\twin\helpers\Test-Helpers.psm1') -Force -ErrorAction SilentlyContinue

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
    }

    AfterAll {
        if ($global:PSWebHostTesting.WebHostStarted -and $global:PSWebHostTesting.WebHost) {
            Stop-TestWebHost -WebHost $global:PSWebHostTesting.WebHost
        }
    }

    Context "Registration form retrieval" {
        It "Should return 200 OK status" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method GET `
                -UseBasicParsing

            $response.StatusCode | Should -Be 200
        }

        It "Should return HTML content" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method GET `
                -UseBasicParsing

            $response.Headers['Content-Type'] | Should -Match 'text/html'
        }

        It "Should serve registration.html file" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method GET `
                -UseBasicParsing

            $content = $response.Content

            # Should be HTML content (not JSON)
            $content | Should -Match '(?i)<!DOCTYPE html>|<html'
        }

        It "Should include registration form or UI" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method GET `
                -UseBasicParsing

            $content = $response.Content

            # Should contain form or registration-related content
            $hasForm = $content -match '(?i)<form' -or $content -match '(?i)registration' -or $content -match '(?i)register'
            $hasForm | Should -Be $true
        }
    }

    Context "Response headers" {
        It "Should set appropriate content type" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method GET `
                -UseBasicParsing

            $response.Headers['Content-Type'] | Should -Not -BeNullOrEmpty
        }

        It "Should set session cookie" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method GET `
                -UseBasicParsing `
                -SessionVariable session

            $cookies = $session.Cookies.GetCookies($global:PSWebHostTesting.BaseUrl)
            $sessionCookie = $cookies | Where-Object { $_.Name -eq 'PSWebSessionID' }
            $sessionCookie | Should -Not -BeNullOrEmpty
        }
    }

    Context "Security considerations" {
        It "Should not expose sensitive information" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method GET `
                -UseBasicParsing

            $content = $response.Content.ToLower()

            # Should not expose database paths, credentials, etc.
            $content | Should -Not -Match 'password.*='
            $content | Should -Not -Match 'connectionstring'
        }

        It "Should handle XSS attempts in query parameters" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $scriptTag = '<script>alert(1)</script>'
            $xssParam = [System.Web.HttpUtility]::UrlEncode($scriptTag)

            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration?test=$xssParam" `
                -Method GET `
                -UseBasicParsing

            $response.StatusCode | Should -Be 200
            $response.Content | Should -Not -Match ([regex]::Escape($scriptTag))
        }
    }

    Context "Error handling" {
        It "Should handle requests gracefully" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                    -Method GET `
                    -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            # Should not return server errors
            $statusCode | Should -Not -BeIn @(500, 501, 502, 503, 504)
        }
    }

    Context "Performance" {
        It "Should return response within reasonable time" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/registration" `
                -Method GET `
                -UseBasicParsing

            $stopwatch.Stop()

            # Should complete within 5 seconds
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000
        }
    }
}
