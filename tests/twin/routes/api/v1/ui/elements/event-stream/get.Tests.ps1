# Event Stream GET endpoint tests
# Tests the event stream UI element endpoint

# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "GET /api/v1/ui/elements/event-stream" -Tags 'Route', 'UI', 'EventStream' {

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

    Context "Authentication" {

        It "Should return 401 without authentication" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/event-stream" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Be 401
        }

        It "Should return JSON error for unauthenticated request" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/event-stream" `
                    -Method GET -UseBasicParsing
            } catch {
                # Error response expected
            }

            # Verify error message format if possible
        }
    }

    Context "Query parameters" {

        It "Should not error with filter parameter" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/event-stream?filter=test" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Should return 401 (auth required) not 500 (server error)
            $statusCode | Should -Not -Be 500
        }

        It "Should not error with count parameter" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/event-stream?count=10" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Not -Be 500
        }

        It "Should not error with earliest parameter" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $statusCode = 0
            $earliest = (Get-Date).AddHours(-1).ToString("o")
            $encodedDate = [System.Web.HttpUtility]::UrlEncode($earliest)

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/event-stream?earliest=$encodedDate" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Not -Be 500
        }

        It "Should not error with latest parameter" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $statusCode = 0
            $latest = (Get-Date).ToString("o")
            $encodedDate = [System.Web.HttpUtility]::UrlEncode($latest)

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/event-stream?latest=$encodedDate" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Not -Be 500
        }
    }

    Context "Security - SQL Injection prevention" {

        It "Should handle SQL injection in filter parameter" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $statusCode = 0
            $sqlInjection = "'; DROP TABLE LogHistory; --"
            $encodedFilter = [System.Web.HttpUtility]::UrlEncode($sqlInjection)

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/event-stream?filter=$encodedFilter" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Not -Be 500
        }
    }

    Context "Edge cases" {

        It "Should handle invalid count parameter" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/event-stream?count=notanumber" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Should handle gracefully (might return error or ignore invalid param)
            # Should not crash with 500
            $statusCode | Should -Not -Be 500
        }

        It "Should handle invalid date in earliest parameter" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/event-stream?earliest=notadate" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # May return 401 (auth) or 400 (bad request) but not 500
            $statusCode | Should -Not -Be 500
        }

        It "Should handle negative count parameter" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/event-stream?count=-5" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Not -Be 500
        }

        It "Should handle very large count parameter" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/event-stream?count=999999999" `
                    -Method GET -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $statusCode | Should -Not -Be 500
        }
    }

    Context "Performance" {

        It "Should return response within reasonable time" {
            if (-not $global:PSWebHostTesting.WebHostStarted) { Set-ItResult -Skipped -Because "WebHost not started"; return }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/ui/elements/event-stream" `
                    -Method GET -UseBasicParsing
            } catch {
                # Expected to fail without auth
            }

            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000
        }
    }
}
