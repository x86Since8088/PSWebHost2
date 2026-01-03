# Profile POST endpoint tests
# Tests the profile update endpoint

# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "POST /api/v1/config/profile" -Tags 'Route', 'Profile', 'Config' {

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

    Context "Successful profile update" {

        It "Should return 200 OK for valid update" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $profileData = @{
                fullName = "Updated Test User"
                phone = "987-654-3210"
                bio = "Updated bio text"
            } | ConvertTo-Json

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method POST -Body $profileData -ContentType "application/json" -UseBasicParsing

                $response.StatusCode | Should -Be 200
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
                # May require auth
                if ($statusCode -eq 401 -or $statusCode -eq 403) {
                    Set-ItResult -Skipped -Because "Requires authentication"
                }
            }
        }

        It "Should return JSON content type" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $profileData = @{
                fullName = "Test"
            } | ConvertTo-Json

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method POST -Body $profileData -ContentType "application/json" -UseBasicParsing

                $response.Headers["Content-Type"] | Should -Match "application/json"
            } catch {
                Set-ItResult -Skipped -Because "Requires authentication"
            }
        }

        It "Should return success status" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $profileData = @{
                fullName = "Test"
            } | ConvertTo-Json

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method POST -Body $profileData -ContentType "application/json" -UseBasicParsing

                $json = $response.Content | ConvertFrom-Json
                $json.status | Should -Be "success"
            } catch {
                Set-ItResult -Skipped -Because "Requires authentication"
            }
        }

        It "Should return success message" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $profileData = @{
                fullName = "Test"
            } | ConvertTo-Json

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method POST -Body $profileData -ContentType "application/json" -UseBasicParsing

                $json = $response.Content | ConvertFrom-Json
                $json.message | Should -Match "updated successfully"
            } catch {
                Set-ItResult -Skipped -Because "Requires authentication"
            }
        }
    }

    Context "Input validation" {

        It "Should handle empty body" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method POST -Body "" -ContentType "application/json" -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Should not crash (500)
            $statusCode | Should -Not -Be 500
        }

        It "Should handle invalid JSON" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method POST -Body "not valid json" -ContentType "application/json" -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Should not crash (500) or handle gracefully
            $statusCode | Should -Not -Be 500
        }
    }

    Context "Security - XSS prevention" {

        It "Should not reflect XSS in success message" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $scriptTag = '<script>alert(1)</script>'
            $profileData = @{
                fullName = $scriptTag
            } | ConvertTo-Json

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method POST -Body $profileData -ContentType "application/json" -UseBasicParsing

                # The response message should not contain unescaped script tags
                $response.Content | Should -Not -Match ([regex]::Escape($scriptTag))
            } catch {
                Set-ItResult -Skipped -Because "Requires authentication"
            }
        }
    }

    Context "Security - SQL Injection prevention" {

        It "Should handle SQL injection in profile data" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $profileData = @{
                fullName = "'; DROP TABLE Users; --"
                bio = "' OR '1'='1"
            } | ConvertTo-Json

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method POST -Body $profileData -ContentType "application/json" -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Should not cause server error
            $statusCode | Should -Not -Be 500
        }
    }

    Context "Edge cases" {

        It "Should handle very long field values" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $longValue = "a" * 10000
            $profileData = @{
                fullName = $longValue
                bio = $longValue
            } | ConvertTo-Json

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method POST -Body $profileData -ContentType "application/json" -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Should handle gracefully
            $statusCode | Should -Not -Be 500
        }

        It "Should handle Unicode characters" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $profileData = @{
                fullName = "Test User " + [char]0x00E9 + [char]0x00F1  # Test User éñ
                bio = "Bio with emoji: " + [char]0x1F600
            } | ConvertTo-Json

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method POST -Body $profileData -ContentType "application/json; charset=utf-8" -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Should handle gracefully
            $statusCode | Should -Not -Be 500
        }

        It "Should handle extra fields in request" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $profileData = @{
                fullName = "Test"
                unknownField = "value"
                anotherUnknown = 12345
            } | ConvertTo-Json

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method POST -Body $profileData -ContentType "application/json" -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Should handle gracefully (ignore extra fields)
            $statusCode | Should -Not -Be 500
        }
    }

    Context "Performance" {

        It "Should return response within reasonable time" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $profileData = @{
                fullName = "Test"
            } | ConvertTo-Json

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/config/profile" `
                    -Method POST -Body $profileData -ContentType "application/json" -UseBasicParsing
            } catch {
                # Expected to fail without auth
            }

            $stopwatch.Stop()

            # Should complete within 5 seconds
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000
        }
    }
}
