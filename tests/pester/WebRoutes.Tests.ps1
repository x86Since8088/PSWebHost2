# tests\WebRoutes.Tests.ps1

Describe "Web Routes" {
    # Define the base URL for the web host
    $baseUrl = "http://localhost:8080"

    Context "SPA Handled Routes" {
        It "should serve spa-shell.html for /" {
            $uri = [System.Uri]"$baseUrl/"
            try {
                $response = Invoke-WebRequest -Uri $uri -UseBasicParsing
                Write-Host "GET / - StatusCode: $($response.StatusCode)"
                Write-Host "GET / - Content-Type: $($response.Headers["Content-Type"])"
                Write-Host "GET / - Content: $($response.Content)"
                $response.StatusCode | Should -Be 200
                ($response.Headers["Content-Type"]).Contains("text/html") | Should -Be $true
                $response.Content.Contains("<title>PsWebHost - SPA Docking System</title>") | Should -Be $true
            } catch {
                Write-Host "GET / - Error: $($_.Exception.Message)"
                throw $_ # Re-throw to fail the test
            }
        }

        It "should handle GET /get via SPA (returns spa-shell.html)" {
            $uri = [System.Uri]"$baseUrl/get?name=TestUser"
            $response = Invoke-WebRequest -Uri $uri -UseBasicParsing
            Write-Host "GET /get - Content: $($response.Content)"
            $response.StatusCode | Should -Be 200
            ($response.Headers["Content-Type"]).Contains("text/html") | Should -Be $true
            $response.Content.Contains("<title>PsWebHost - SPA Docking System</title>") | Should -Be $true
        }

        It "should handle POST /post via SPA (returns spa-shell.html)" {
            $uri = [System.Uri]"$baseUrl/post"
            $body = @{ message = "Hello from Pester!" } | ConvertTo-Json
            $response = Invoke-WebRequest -Uri $uri -Method Post -Body $body -ContentType "application/json" -UseBasicParsing
            Write-Host "POST /post - Content: $($response.Content)"
            $response.StatusCode | Should -Be 200
            ($response.Headers["Content-Type"]).Contains("text/html") | Should -Be $true
            $response.Content.Contains("<title>PsWebHost - SPA Docking System</title>") | Should -Be $true
        }

        It "should handle GET /api/v1/test via SPA (returns spa-shell.html)" {
            $uri = [System.Uri]"$baseUrl/api/v1/test"
            $response = Invoke-WebRequest -Uri $uri -UseBasicParsing
            Write-Host "GET /api/v1/test - Content: $($response.Content)"
            $response.StatusCode | Should -Be 200
            ($response.Headers["Content-Type"]).Contains("text/html") | Should -Be $true
            $response.Content.Contains("<title>PsWebHost - SPA Docking System</title>") | Should -Be $true
        }
    }

    Context "Non-existent route" {
        It "should return 404 Not Found" {
            $uri = [System.Uri]"$baseUrl/nonexistent"
            try {
                Invoke-WebRequest -Uri $uri -ErrorAction Stop -UseBasicParsing
                Write-Host "Non-existent route - No exception thrown."
                Fail "Expected a WebException for 404, but none was thrown."
            } catch {
                Write-Host "Non-existent route - Exception: $($_.Exception.Message)"
                $_.Exception | Should -BeOfType [System.Net.WebException]
                $_.Exception.Message.Contains("404 Not Found") | Should -Be $true
            }
        }
    }
}