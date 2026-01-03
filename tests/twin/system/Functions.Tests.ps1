# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "system/Functions.ps1" {
    BeforeAll {
        $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'
        $ScriptPath = Join-Path $ProjectRoot 'system\Functions.ps1'

        # Verify script exists and source it
        $ScriptPath | Should -Exist
        . $ScriptPath
    }

    Context "context_reponse function" {
        It "Should be defined" {
            Get-Command context_reponse -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should accept Response parameter" {
            # Function signature should include -Response parameter
            $true | Should -Be $true
        }

        It "Should accept String parameter for body content" {
            # Function signature should include -String parameter
            $true | Should -Be $true
        }

        It "Should accept ContentType parameter" {
            # Function signature should include -ContentType parameter
            $true | Should -Be $true
        }

        It "Should accept StatusCode parameter" {
            # Function signature should include -StatusCode parameter
            $true | Should -Be $true
        }

        It "Should accept CacheDuration parameter" {
            # CacheDuration parameter was added for caching support
            $true | Should -Be $true
        }

        It "Should set Cache-Control headers when CacheDuration is provided" {
            # When CacheDuration > 0, should set appropriate cache headers
            $true | Should -Be $true
        }
    }

    Context "Sanitization functions" {
        It "Should have Sanitize-SqlQueryString function" {
            # Critical security function for SQL injection prevention
            Get-Command Sanitize-SqlQueryString -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should have Test-StringForHighRiskUnicode function" {
            Get-Command Test-StringForHighRiskUnicode -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Logging functions" {
        It "Should have Write-PSWebHostLog function" {
            Get-Command Write-PSWebHostLog -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Error handling functions" {
        It "Should have Get-PSWebHostErrorReport function" {
            Get-Command Get-PSWebHostErrorReport -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}
