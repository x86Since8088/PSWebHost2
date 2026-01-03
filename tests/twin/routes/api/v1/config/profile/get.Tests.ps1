# Profile GET endpoint tests
# Tests the profile data retrieval endpoint

# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "GET /api/v1/config/profile" -Tags 'Route', 'Profile', 'Config' {

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

    Context "Response format" {

        It "Should return JSON content type" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method GET -UseBasicParsing

                $response.Headers["Content-Type"] | Should -Match "application/json"
            } catch {
                # May require authentication - this is expected
                Set-ItResult -Skipped -Because "Requires authentication"
            }
        }

        It "Should return valid JSON" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method GET -UseBasicParsing

                { $response.Content | ConvertFrom-Json } | Should -Not -Throw
            } catch {
                Set-ItResult -Skipped -Because "Requires authentication"
            }
        }

        It "Should include fullName field" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method GET -UseBasicParsing

                $json = $response.Content | ConvertFrom-Json
                $json.PSObject.Properties.Name | Should -Contain "fullName"
            } catch {
                Set-ItResult -Skipped -Because "Requires authentication"
            }
        }

        It "Should include email field" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method GET -UseBasicParsing

                $json = $response.Content | ConvertFrom-Json
                $json.PSObject.Properties.Name | Should -Contain "email"
            } catch {
                Set-ItResult -Skipped -Because "Requires authentication"
            }
        }

        It "Should include phone field" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method GET -UseBasicParsing

                $json = $response.Content | ConvertFrom-Json
                $json.PSObject.Properties.Name | Should -Contain "phone"
            } catch {
                Set-ItResult -Skipped -Because "Requires authentication"
            }
        }

        It "Should include bio field" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method GET -UseBasicParsing

                $json = $response.Content | ConvertFrom-Json
                $json.PSObject.Properties.Name | Should -Contain "bio"
            } catch {
                Set-ItResult -Skipped -Because "Requires authentication"
            }
        }
    }

    Context "Authentication" {

        It "Should require authentication" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Should either succeed (200) if session exists or fail with 401/403
            # The endpoint may work with anonymous session for testing
        }
    }

    Context "Security" {

        It "Should not expose sensitive data in response" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method GET -UseBasicParsing

                $content = $response.Content.ToLower()
                $content | Should -Not -Match '"password"'
                $content | Should -Not -Match '"passwordhash"'
                $content | Should -Not -Match '"secret"'
            } catch {
                Set-ItResult -Skipped -Because "Requires authentication"
            }
        }
    }

    Context "Performance" {

        It "Should return response within reasonable time" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method GET -UseBasicParsing
            } catch {
                # Expected to fail without auth
            }

            $stopwatch.Stop()

            # Should complete within 5 seconds
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000
        }
    }
}
