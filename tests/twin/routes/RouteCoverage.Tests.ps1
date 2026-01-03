# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "Route Test Coverage Analysis" {
    BeforeAll {
        $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'
        $RoutesPath = Join-Path $ProjectRoot 'routes'
        $TestsPath = Join-Path $ProjectRoot 'tests\twin\routes'
    }

    Context "Route enumeration" {
        It "Should find route method files in routes directory" {
            $routeFiles = Get-ChildItem -Path $RoutesPath -Recurse -Include 'get.ps1','post.ps1','put.ps1','delete.ps1','patch.ps1'
            $routeFiles.Count | Should -BeGreaterThan 0
        }
    }

    Context "Test coverage gaps" {
        It "Should identify routes without tests" {
            # Get all route method files
            $routeFiles = Get-ChildItem -Path $RoutesPath -Recurse -Include 'get.ps1','post.ps1','put.ps1','delete.ps1','patch.ps1'

            $untestedRoutes = @()

            foreach ($routeFile in $routeFiles) {
                # Calculate relative path from routes directory
                $relativePath = $routeFile.FullName.Substring($RoutesPath.Length + 1)

                # Remove the method filename and get directory path
                $routeDir = [System.IO.Path]::GetDirectoryName($relativePath)

                # Construct expected test file path
                $methodName = [System.IO.Path]::GetFileNameWithoutExtension($routeFile.Name)
                $expectedTestFile = Join-Path $TestsPath "$routeDir\$methodName.Tests.ps1"

                if (-not (Test-Path $expectedTestFile)) {
                    $untestedRoutes += @{
                        Route = $relativePath
                        ExpectedTest = $expectedTestFile.Substring($ProjectRoot.Length + 1)
                        Method = $methodName.ToUpper()
                    }
                }
            }

            # Report untested routes
            if ($untestedRoutes.Count -gt 0) {
                Write-Host "`n  Untested Routes ($($untestedRoutes.Count)):" -ForegroundColor Yellow
                $untestedRoutes | ForEach-Object {
                    Write-Host "    [$($_.Method)] $($_.Route)" -ForegroundColor Gray
                    Write-Host "      Missing: $($_.ExpectedTest)" -ForegroundColor DarkGray
                }
                Write-Host ""

                # Group by directory to show patterns
                $byDirectory = $untestedRoutes | Group-Object { [System.IO.Path]::GetDirectoryName($_.Route) }
                Write-Host "  Untested by Directory:" -ForegroundColor Yellow
                $byDirectory | Sort-Object Count -Descending | ForEach-Object {
                    Write-Host "    $($_.Name): $($_.Count) untested" -ForegroundColor Gray
                }
                Write-Host ""
            }

            # Test will pass but report the gaps
            $totalRoutes = $routeFiles.Count
            $testedRoutes = $totalRoutes - $untestedRoutes.Count
            $coveragePercent = [math]::Round(($testedRoutes / $totalRoutes) * 100, 2)

            Write-Host "  Coverage: $testedRoutes/$totalRoutes routes tested ($coveragePercent%)" -ForegroundColor Cyan

            # Optionally fail if coverage is below threshold
            # $coveragePercent | Should -BeGreaterThan 50
            $true | Should -Be $true
        }
    }

    Context "Test file validation" {
        It "Should verify test files use proper initialization" {
            $testFiles = Get-ChildItem -Path $TestsPath -Recurse -Filter '*.Tests.ps1'

            $invalidTests = @()

            foreach ($testFile in $testFiles) {
                $content = Get-Content $testFile.FullName -Raw

                # Check for init script pattern
                if ($content -notmatch '\$InitializationScript\s*=\s*"\$\(\$psscriptroot\s+-replace') {
                    $invalidTests += $testFile.FullName.Substring($ProjectRoot.Length + 1)
                }
            }

            if ($invalidTests.Count -gt 0) {
                Write-Host "`n  Tests missing proper initialization ($($invalidTests.Count)):" -ForegroundColor Yellow
                $invalidTests | ForEach-Object {
                    Write-Host "    $_" -ForegroundColor Gray
                }
                Write-Host ""
            }

            $invalidTests.Count | Should -Be 0
        }

        It "Should verify test files follow naming convention" {
            $testFiles = Get-ChildItem -Path $TestsPath -Recurse -Filter '*.ps1' | Where-Object { $_.Name -notmatch '\.Tests\.ps1$' -and $_.Name -ne 'Run-AllTwinTests.ps1' }

            if ($testFiles.Count -gt 0) {
                Write-Host "`n  Files not following .Tests.ps1 convention:" -ForegroundColor Yellow
                $testFiles | ForEach-Object {
                    Write-Host "    $($_.FullName.Substring($TestsPath.Length + 1))" -ForegroundColor Gray
                }
                Write-Host ""
            }

            $testFiles.Count | Should -Be 0
        }
    }

    Context "Route to test path mapping" {
        It "Should correctly map route paths to test paths" {
            # Test the mapping logic
            $testCases = @(
                @{ Route = 'api\v1\auth\getauthtoken\get.ps1'; ExpectedTest = 'api\v1\auth\getauthtoken\get.Tests.ps1' }
                @{ Route = 'spa\card_settings\post.ps1'; ExpectedTest = 'spa\card_settings\post.Tests.ps1' }
            )

            foreach ($case in $testCases) {
                $routeDir = [System.IO.Path]::GetDirectoryName($case.Route)
                $methodName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileName($case.Route))
                $mappedTest = Join-Path $routeDir "$methodName.Tests.ps1"

                $mappedTest | Should -Be $case.ExpectedTest
            }
        }
    }
}
