# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe 'Sanitization Module' {
    BeforeAll {
        $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'
        $ModulePath = Join-Path $ProjectRoot 'modules\Sanitization\Sanitization.psm1'

        # Verify module exists
        $ModulePath | Should -Exist

        # Import module
        Import-Module $ModulePath -Force -DisableNameChecking -ErrorAction Stop
    }

    Context 'Module structure' {
        It 'Should export Sanitize-HtmlInput function' {
            Get-Command Sanitize-HtmlInput -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Sanitize-FilePath function' {
            Get-Command Sanitize-FilePath -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Describe 'Sanitize-HtmlInput' {
        Context 'Basic encoding' {
            It 'Should encode script tags and single quotes' {
                $result = Sanitize-HtmlInput -InputString "<script>alert('XSS')</script>"
                $result | Should -Be "&lt;script&gt;alert(&#39;XSS&#39;)&lt;/script&gt;"
            }

            It 'Should return empty string for empty input' {
                $result = Sanitize-HtmlInput -InputString ""
                $result | Should -Be ""
            }

            It 'Should leave safe strings untouched' {
                $result = Sanitize-HtmlInput -InputString 'Hello World'
                $result | Should -Be 'Hello World'
            }

            It 'Should encode mixed content' {
                $result = Sanitize-HtmlInput -InputString 'User: <John Doe> & Co.'
                $result | Should -Be 'User: &lt;John Doe&gt; &amp; Co.'
            }

            It 'Should encode double quotes' {
                $result = Sanitize-HtmlInput -InputString 'Say "hello"'
                $result | Should -Match '&quot;|&#34;'
            }

            It 'Should handle null input' {
                $result = Sanitize-HtmlInput -InputString $null
                $result | Should -Be ""
            }
        }

        Context 'XSS attack vectors' {
            It 'Should block <img> tag with onerror' {
                $result = Sanitize-HtmlInput -InputString '<img src=x onerror=alert(1)>'
                $result | Should -Not -Match '<img'
                $result | Should -Match '&lt;img'
            }

            It 'Should block <svg> with onload' {
                $result = Sanitize-HtmlInput -InputString '<svg onload=alert(1)>'
                $result | Should -Not -Match '<svg'
                $result | Should -Match '&lt;svg'
            }

            It 'Should block javascript: protocol' {
                $result = Sanitize-HtmlInput -InputString '<a href="javascript:alert(1)">Click</a>'
                $result | Should -Not -Match 'javascript:'
                $result | Should -Match '&lt;a'
            }
        }
    }

    Describe 'Sanitize-FilePath' {
        BeforeAll {
            $testBaseDir = Join-Path ([System.IO.Path]::GetTempPath()) "PesterTest_SanitizeFilePath_$(New-Guid)"
            New-Item -Path $testBaseDir -ItemType Directory -Force | Out-Null
        }

        AfterAll {
            if (Test-Path $testBaseDir) {
                Remove-Item -Path $testBaseDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        Context 'Valid paths' {
            It 'Should return normalized path inside base directory' {
                $filePath = 'subfolder\file.txt'
                $result = Sanitize-FilePath -FilePath $filePath -BaseDirectory $testBaseDir
                $result.Score | Should -Be 'pass'
                $result.Path | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $testBaseDir $filePath)))
            }

            It 'Should handle forward slashes' {
                $filePath = 'subfolder/file.txt'
                $result = Sanitize-FilePath -FilePath $filePath -BaseDirectory $testBaseDir
                $result.Score | Should -Be 'pass'
            }

            It 'Should return base directory for empty path' {
                $result = Sanitize-FilePath -FilePath '' -BaseDirectory $testBaseDir
                $result.Score | Should -Be 'pass'
                $result.Path | Should -Be ([System.IO.Path]::GetFullPath($testBaseDir))
            }
        }

        Context 'Path traversal attacks' {
            It 'Should reject path traversal with ..' {
                $filePath = 'subfolder\..\..\..\Windows\win.ini'
                $result = Sanitize-FilePath -FilePath $filePath -BaseDirectory $testBaseDir
                $result.Score | Should -Be 'fail'
            }

            It 'Should reject absolute path outside base' {
                $filePath = 'C:\Windows\win.ini'
                $result = Sanitize-FilePath -FilePath $filePath -BaseDirectory $testBaseDir
                $result.Score | Should -Be 'fail'
            }

            It 'Should reject UNC paths' {
                $filePath = '\\server\share\file.txt'
                $result = Sanitize-FilePath -FilePath $filePath -BaseDirectory $testBaseDir
                $result.Score | Should -Be 'fail'
            }

            It 'Should reject paths with double dots' {
                $filePath = '..\..\Windows\System32'
                $result = Sanitize-FilePath -FilePath $filePath -BaseDirectory $testBaseDir
                $result.Score | Should -Be 'fail'
            }
        }

        Context 'Edge cases' {
            It 'Should handle paths with spaces' {
                $filePath = 'folder with spaces\file name.txt'
                $result = Sanitize-FilePath -FilePath $filePath -BaseDirectory $testBaseDir
                $result.Score | Should -Be 'pass'
            }

            It 'Should handle paths with special characters' {
                $filePath = 'folder_123\file-name.txt'
                $result = Sanitize-FilePath -FilePath $filePath -BaseDirectory $testBaseDir
                $result.Score | Should -Be 'pass'
            }
        }
    }
}
