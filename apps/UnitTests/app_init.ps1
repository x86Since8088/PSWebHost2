param($PSWebServer, $AppRoot)

Write-Verbose "[UnitTests:Init] Initializing UnitTests app..." -Verbose

# Initialize synchronized hashtable for test execution tracking
$PSWebServer['UnitTests'] = [hashtable]::Synchronized(@{
    AppRoot = $AppRoot
    DataPath = Join-Path $Global:PSWebServer['DataRoot'] "apps\UnitTests"
    Jobs = [hashtable]::Synchronized(@{})  # Active test jobs
    History = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))  # Test run history
    Initialized = Get-Date
})

# Ensure data directory exists
$dataPath = $PSWebServer.UnitTests.DataPath
if (-not (Test-Path $dataPath)) {
    New-Item -Path $dataPath -ItemType Directory -Force | Out-Null
}

# Load test history if exists
$historyPath = Join-Path $dataPath 'test-history.json'
if (Test-Path $historyPath) {
    try {
        $history = Get-Content $historyPath -Raw | ConvertFrom-Json
        foreach ($entry in $history) {
            [void]$PSWebServer.UnitTests.History.Add($entry)
        }
        Write-Verbose "[UnitTests:Init] Loaded $($history.Count) test history entries" -Verbose
    } catch {
        Write-Warning "[UnitTests:Init] Failed to load test history: $($_.Exception.Message)"
    }
}

# Get project root
$projectRoot = $AppRoot -replace '[/\\]apps[/\\].*'
$PSWebServer.UnitTests.ProjectRoot = $projectRoot
$PSWebServer.UnitTests.TestsPath = Join-Path $projectRoot 'tests\twin'

Write-Host "[Init] Loaded app: UnitTests (v1.0.0)" -ForegroundColor Green
Write-Verbose "[UnitTests:Init] Tests path: $($PSWebServer.UnitTests.TestsPath)" -Verbose
Write-Verbose "[UnitTests:Init] UnitTests app initialization complete" -Verbose
