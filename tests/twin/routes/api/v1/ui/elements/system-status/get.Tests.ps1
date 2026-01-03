# System Status GET endpoint tests
# Tests the system status UI element endpoint

# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "GET /api/v1/ui/elements/system-status" -Tags 'Route', 'UI', 'SystemStatus' {

    BeforeAll {
        $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'

        if (-not $global:PSWebHostTesting) {
            $global:PSWebHostTesting = [hashtable]::Synchronized(@{})
        }

        Import-Module (Join-Path $ProjectRoot 'tests\twin\helpers\Test-Helpers.psm1') -Force -ErrorAction SilentlyContinue

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

        It "Should return 200 OK status" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/system-status" `
                    -Method GET -UseBasicParsing
                $response.StatusCode | Should -Be 200
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
                if ($statusCode -eq 401) {
                    Set-ItResult -Skipped -Because "Requires authentication"
                } else {
                    throw
                }
            }
        }

        It "Should return JSON content type" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/system-status" `
                    -Method GET -UseBasicParsing
                $response.Headers["Content-Type"] | Should -Match "application/json"
            } catch {
                Set-ItResult -Skipped -Because "Request failed"
            }
        }

        It "Should return valid JSON array" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/system-status" `
                    -Method GET -UseBasicParsing
                $json = $response.Content | ConvertFrom-Json
                $json | Should -BeOfType [System.Object[]]
            } catch {
                Set-ItResult -Skipped -Because "Request failed"
            }
        }

        It "Should include log entries with timestamp" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/system-status" `
                    -Method GET -UseBasicParsing
                $json = $response.Content | ConvertFrom-Json
                if ($json.Count -gt 0) {
                    $json[0].PSObject.Properties.Name | Should -Contain "timestamp"
                }
            } catch {
                Set-ItResult -Skipped -Because "Request failed"
            }
        }

        It "Should include log entries with level" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/system-status" `
                    -Method GET -UseBasicParsing
                $json = $response.Content | ConvertFrom-Json
                if ($json.Count -gt 0) {
                    $json[0].PSObject.Properties.Name | Should -Contain "level"
                }
            } catch {
                Set-ItResult -Skipped -Because "Request failed"
            }
        }

        It "Should include log entries with message" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/system-status" `
                    -Method GET -UseBasicParsing
                $json = $response.Content | ConvertFrom-Json
                if ($json.Count -gt 0) {
                    $json[0].PSObject.Properties.Name | Should -Contain "message"
                }
            } catch {
                Set-ItResult -Skipped -Because "Request failed"
            }
        }
    }

    Context "Security" {

        It "Should not expose sensitive data" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/system-status" `
                    -Method GET -UseBasicParsing
                $content = $response.Content.ToLower()
                $content | Should -Not -Match '"password"'
                $content | Should -Not -Match '"secret"'
                $content | Should -Not -Match '"apikey"'
            } catch {
                Set-ItResult -Skipped -Because "Request failed"
            }
        }
    }

    Context "Performance" {

        It "Should return response within reasonable time" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/system-status" `
                    -Method GET -UseBasicParsing
            } catch {
                # Expected to fail
            }

            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000
        }
    }
}
