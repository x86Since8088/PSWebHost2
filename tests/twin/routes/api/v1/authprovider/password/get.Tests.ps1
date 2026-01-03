# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "GET /api/v1/authprovider/password" -Tags 'Route', 'Auth', 'Password' {
    BeforeAll {
        $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'

        # Import helper modules
        Import-Module (Join-Path $ProjectRoot 'tests\twin\helpers\Test-Helpers.psm1') -Force -ErrorAction SilentlyContinue

        # Start WebHost for testing
        try {
            $global:PSWebHostTesting.WebHost = Get-TestWebHost -ProjectRoot $ProjectRoot -ErrorAction Stop
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

    Context "Login form retrieval" {
        It "Should return 200 OK status" {
            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password" `
                -Method GET `
                -UseBasicParsing

            $response.StatusCode | Should -Be 200
        }

        It "Should return HTML content" {
            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password" `
                -Method GET `
                -UseBasicParsing

            $response.Headers['Content-Type'] | Should -Match 'text/html'
        }

        It "Should include login form elements" {
            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password" `
                -Method GET `
                -UseBasicParsing

            $content = $response.Content

            # Should contain form elements
            $content | Should -Match ([regex]::Escape('<form'))
            $content | Should -Match 'email'
            $content | Should -Match 'password'
        }

        It "Should include email input field" {
            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password" `
                -Method GET `
                -UseBasicParsing

            $content = $response.Content
            $content | Should -Match "type=[`"`']?email[`"`']?|name=[`"`']?email[`"`']?"
        }

        It "Should include password input field" {
            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password" `
                -Method GET `
                -UseBasicParsing

            $content = $response.Content
            $content | Should -Match "type=[`"`']?password[`"`']?"
        }

        It "Should include submit button or action" {
            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password" `
                -Method GET `
                -UseBasicParsing

            $content = $response.Content
            $hasSubmit = ($content -match "type=[`"`']?submit[`"`']?") -or ($content -match ([regex]::Escape('<button')))
            $hasSubmit | Should -Be $true
        }

        It "Should set session cookie" {
            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password" `
                -Method GET `
                -UseBasicParsing `
                -SessionVariable session

            $session.Cookies.GetCookies($global:PSWebHostTesting.BaseUrl) | Where-Object { $_.Name -eq 'PSWebSessionID' } | Should -Not -BeNullOrEmpty
        }
    }

    Context "State parameter handling" {
        It "Should accept state parameter in query string" {
            $state = [guid]::NewGuid().ToString()

            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password?state=$state" `
                -Method GET `
                -UseBasicParsing

            $response.StatusCode | Should -Be 200
        }

        It "Should work without state parameter" {
            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password" `
                -Method GET `
                -UseBasicParsing

            $response.StatusCode | Should -Be 200
        }
    }

    Context "Security headers" {
        It "Should not cache the login form" {
            $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/authprovider/password" `
                -Method GET `
                -UseBasicParsing

            # Login forms should not be cached for security
            if ($response.Headers['Cache-Control']) {
                $response.Headers['Cache-Control'] | Should -Match 'no-cache|no-store|private'
            }
        }
    }

    Context "Error handling" {
        It "Should handle invalid query parameters gracefully" {
            $scriptTag = '<script>alert(1)</script>'
            $xssParam = [System.Web.HttpUtility]::UrlEncode($scriptTag)
            $response = Invoke-WebRequest -Uri "$($global:PSWebHostTesting.BaseUrl)/api/v1/authprovider/password?invalid=$xssParam" `
                -Method GET `
                -UseBasicParsing

            $response.StatusCode | Should -Be 200
            $response.Content | Should -Not -Match ([regex]::Escape($scriptTag))
        }
    }
}
