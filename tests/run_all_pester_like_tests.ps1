# Run all pester-style tests in tests/pester using the repo's TestCodeHelpers shim
# This runner lives in the repo and is executed via "pwsh -NoProfile -File .\tests\run_all_pester_like_tests.ps1"

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

# Ensure we run from the repository root
$repoRoot = (Resolve-Path "$PSScriptRoot\..").ProviderPath
Set-Location $repoRoot

Write-Host "Repo root: $repoRoot"

# Import the test helpers (shims)
$helper = Join-Path $repoRoot 'tests\modules\TestCodeHelpers.psm1'
if (Test-Path $helper) {
    Import-Module $helper -Force -Verbose -ErrorAction Stop
} else {
    Write-Host "Test helper module not found at: $helper"; exit 2
}

$failed = $false
$files = Get-ChildItem -Path (Join-Path $repoRoot 'tests\pester') -Filter *.ps1 -File | Sort-Object Name
if (-not $files) { Write-Host 'No pester-style test files found under tests/pester'; exit 0 }

foreach ($f in $files) {
    Write-Host "--- RUN: $($f.Name)"
    try {
        # Dot-source the test file using a single-quoted literal to avoid accidental parsing of test content
        $path = (Resolve-Path $f.FullName).ProviderPath
        Invoke-Expression (". '$path'")
    } catch {
        Write-Host "*** TEST FILE ERROR: $($f.Name) $($_.Exception.Message)"
        $failed = $true
    }
}

if ($failed) { Write-Host 'Some test files failed'; exit 1 } else { Write-Host 'All pester-style test files passed'; exit 0 }
