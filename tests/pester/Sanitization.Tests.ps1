# tests\Sanitization.Tests.ps1

<#
  Purpose: unit tests for the Sanitization module.
  These tests validate HTML encoding and path sanitization helpers.
  The module is loaded via a relative path to keep tests portable across
  developer machines and CI environments.
#>

$modulePath = Join-Path $PSScriptRoot '..\modules\Sanitization\Sanitization.psm1'
$repoModulePath = Join-Path (Resolve-Path "$PSScriptRoot\..\.." ).ProviderPath 'modules\Sanitization\Sanitization.psm1'
if (Test-Path $modulePath) {
    Import-Module (Resolve-Path $modulePath).ProviderPath -Force -ErrorAction Continue -DisableNameChecking
} elseif (Test-Path $repoModulePath) {
    Import-Module (Resolve-Path $repoModulePath).ProviderPath -Force -ErrorAction Continue -DisableNameChecking
} else {
    Write-Host "Sanitization module not found at: $modulePath or $repoModulePath - skipping tests"
}

Describe 'Sanitize-HtmlInput' {
    Context 'basic encoding' {
        It 'encodes script tags and single quotes' {
            Sanitize-HtmlInput -InputString "<script>alert('XSS')</script>" | Should -Be "&lt;script&gt;alert(&#39;XSS&#39;)&lt;/script&gt;"
        }

        It 'returns empty string for empty input' {
            Sanitize-HtmlInput -InputString "" | Should -Be ""
        }

        It 'leaves safe strings untouched' {
            Sanitize-HtmlInput -InputString 'Hello World' | Should -Be 'Hello World'
        }

        It 'encodes mixed content' {
            Sanitize-HtmlInput -InputString 'User: <John Doe> & Co.' | Should -Be 'User: &lt;John Doe&gt; &amp; Co.'
        }
    }
}

Describe 'Sanitize-FilePath' {
    $testBaseDir = Join-Path ([System.IO.Path]::GetTempPath()) "PesterTest_SanitizeFilePath_$(New-Guid)"

    BeforeAll {
        New-Item -Path $testBaseDir -ItemType Directory -Force | Out-Null
    }
    AfterAll {
        if (Test-Path $testBaseDir) { Remove-Item -Path $testBaseDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'returns a normalized path inside the base directory' {
        $filePath = 'subfolder\file.txt'
        $expected = @{Score='pass'; Path = [System.IO.Path]::GetFullPath((Join-Path $testBaseDir $filePath))}
        $SanitizedFilePathCheck = Sanitize-FilePath -FilePath $filePath -BaseDirectory $testBaseDir | Should -Be $expected
    }

    It 'rejects path traversal attempts' {
        $filePath = 'subfolder\..\..\..\Windows\win.ini'
        { (Sanitize-FilePath -FilePath $filePath -BaseDirectory $testBaseDir).Score } | Should -Be 'fail'
    }

    It 'rejects absolute paths outside the base directory' {
        $filePath = 'C:\Windows\win.ini'
        { (Sanitize-FilePath -FilePath $filePath -BaseDirectory $testBaseDir).Score } | Should -Be 'fail'
    }

    It 'returns base directory when given empty file path' {
        (Sanitize-FilePath -FilePath '' -BaseDirectory $testBaseDir|where-object{$_.Score -eq 'pass'}).Path | Should -Be ([System.IO.Path]::GetFullPath($testBaseDir))
    }
}