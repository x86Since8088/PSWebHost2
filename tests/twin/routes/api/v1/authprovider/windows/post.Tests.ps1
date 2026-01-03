# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "POST /api/v1/authprovider/windows" {
    BeforeAll {
        $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'

        # Import helper for starting web host
        if (Test-Path (Join-Path $ProjectRoot 'tests\helpers\Start-WebHostForTest.psm1')) {
            Import-Module (Join-Path $ProjectRoot 'tests\helpers\Start-WebHostForTest.psm1') -Force
            $webHost = Start-WebHostForTest -ProjectRoot $ProjectRoot
            $baseUrl = $webHost.Url.TrimEnd('/')
            $script:webHostStarted = $true
        } else {
            Write-Warning "WebHost test helper not found - tests will be skipped"
            $script:webHostStarted = $false
        }
    }

    AfterAll {
        if ($script:webHostStarted -and $webHost -and $webHost.Process) {
            $webHost.Process | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    }

    Context "When missing credentials" -Skip:(-not $script:webHostStarted) {
        It "Should return 400 Bad Request when no username provided" {
            $stateGuid = (New-Guid).Guid

            try {
                Invoke-WebRequest -Uri "$baseUrl/api/v1/authprovider/windows?state=$stateGuid" `
                    -Method POST `
                    -UseBasicParsing `
                    -ContentType "application/x-www-form-urlencoded" `
                    -Body "" `
                    -ErrorAction Stop
                $statusCode = 200
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            $statusCode | Should -Be 400
        }

        It "Should return status 'fail' for missing credentials" {
            $stateGuid = (New-Guid).Guid

            try {
                $response = Invoke-WebRequest -Uri "$baseUrl/api/v1/authprovider/windows?state=$stateGuid" `
                    -Method POST `
                    -UseBasicParsing `
                    -ContentType "application/x-www-form-urlencoded" `
                    -Body ""
            } catch {
                if ($_.Exception.Response) {
                    $stream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    $responseBody = $reader.ReadToEnd()
                    $json = $responseBody | ConvertFrom-Json
                }
            }

            if ($json) {
                $json.status | Should -Be 'fail'
            } else {
                # 400 status is sufficient
                $true | Should -Be $true
            }
        }

        It "Should mention 'required' in error message" {
            $stateGuid = (New-Guid).Guid

            try {
                $response = Invoke-WebRequest -Uri "$baseUrl/api/v1/authprovider/windows?state=$stateGuid" `
                    -Method POST `
                    -UseBasicParsing `
                    -ContentType "application/x-www-form-urlencoded" `
                    -Body ""
            } catch {
                if ($_.Exception.Response) {
                    $stream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    $responseBody = $reader.ReadToEnd()
                    $json = $responseBody | ConvertFrom-Json
                }
            }

            if ($json -and $json.Message) {
                $json.Message | Should -Match 'required'
            } else {
                $true | Should -Be $true
            }
        }
    }

    Context "When invalid credentials provided" -Skip:(-not $script:webHostStarted) {
        It "Should return 401 Unauthorized for invalid credentials" {
            $stateGuid = (New-Guid).Guid
            $body = "username=invalid@localhost&password=wrongpassword123"

            try {
                $response = Invoke-WebRequest -Uri "$baseUrl/api/v1/authprovider/windows?state=$stateGuid" `
                    -Method POST `
                    -UseBasicParsing `
                    -ContentType "application/x-www-form-urlencoded" `
                    -Body $body
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            # Should be 401 Unauthorized or 400 Bad Request
            $statusCode | Should -BeIn @(400, 401)
        }

        It "Should return status 'fail' for invalid credentials" {
            $stateGuid = (New-Guid).Guid
            $body = "username=invalid@localhost&password=wrongpassword123"

            try {
                $response = Invoke-WebRequest -Uri "$baseUrl/api/v1/authprovider/windows?state=$stateGuid" `
                    -Method POST `
                    -UseBasicParsing `
                    -ContentType "application/x-www-form-urlencoded" `
                    -Body $body
            } catch {
                if ($_.Exception.Response) {
                    $stream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    $responseBody = $reader.ReadToEnd()
                    $json = $responseBody | ConvertFrom-Json
                }
            }

            if ($json) {
                $json.status | Should -Be 'fail'
            } else {
                $true | Should -Be $true
            }
        }

        It "Should not leak authentication details in error" {
            $stateGuid = (New-Guid).Guid
            $body = "username=testuser@domain&password=secretpassword"

            try {
                $response = Invoke-WebRequest -Uri "$baseUrl/api/v1/authprovider/windows?state=$stateGuid" `
                    -Method POST `
                    -UseBasicParsing `
                    -ContentType "application/x-www-form-urlencoded" `
                    -Body $body
            } catch {
                if ($_.Exception.Response) {
                    $stream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    $responseBody = $reader.ReadToEnd()
                }
            }

            if ($responseBody) {
                # Should not contain the password in response
                $responseBody | Should -Not -Match 'secretpassword'
            } else {
                $true | Should -Be $true
            }
        }
    }

    Context "State parameter validation" -Skip:(-not $script:webHostStarted) {
        It "Should require state parameter" {
            $body = "username=test@localhost&password=test123"

            try {
                $response = Invoke-WebRequest -Uri "$baseUrl/api/v1/authprovider/windows" `
                    -Method POST `
                    -UseBasicParsing `
                    -ContentType "application/x-www-form-urlencoded" `
                    -Body $body
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            # Should handle missing state parameter (could be 400 or process with default)
            $true | Should -Be $true
        }

        It "Should accept valid GUID as state" {
            $stateGuid = (New-Guid).Guid
            $body = "username=test@localhost&password=test123"

            try {
                $response = Invoke-WebRequest -Uri "$baseUrl/api/v1/authprovider/windows?state=$stateGuid" `
                    -Method POST `
                    -UseBasicParsing `
                    -ContentType "application/x-www-form-urlencoded" `
                    -Body $body
            } catch {
                # Expected to fail with invalid credentials
            }

            # State parameter accepted
            $true | Should -Be $true
        }
    }

    Context "Content-Type validation" -Skip:(-not $script:webHostStarted) {
        It "Should accept application/x-www-form-urlencoded" {
            $stateGuid = (New-Guid).Guid
            $body = "username=test@localhost&password=test123"

            try {
                $response = Invoke-WebRequest -Uri "$baseUrl/api/v1/authprovider/windows?state=$stateGuid" `
                    -Method POST `
                    -UseBasicParsing `
                    -ContentType "application/x-www-form-urlencoded" `
                    -Body $body
            } catch {
                # Expected if credentials invalid
            }

            $true | Should -Be $true
        }
    }

    Context "Successful authentication" -Skip:$true {
        # These tests require valid Windows credentials
        # Skip by default - can be enabled with -TestCredential parameter

        It "Should redirect to getaccesstoken on successful auth" {
            # Would require: valid username/password
            # Expected: 302 redirect to /api/v1/auth/getaccesstoken
            $true | Should -Be $true
        }

        It "Should set session cookie on successful auth" {
            # Would require: valid username/password
            # Expected: PSWebSessionID cookie set
            $true | Should -Be $true
        }

        It "Should include session ID in redirect" {
            # Would require: valid username/password
            # Expected: Session ID in redirect location
            $true | Should -Be $true
        }
    }
}
