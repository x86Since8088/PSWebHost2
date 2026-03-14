# Check if the running server has the fix loaded
Write-Host "Checking if server has Session Type Conversion Bug fix..." -ForegroundColor Cyan

# Make a request to trigger module usage and check the server's behavior
# We'll create a simple endpoint test that logs the session type

$testScript = @'
# Quick inline test - call Get-PSWebSessions and check return type
$testSessionID = [guid]::NewGuid().ToString()

# Create a test session
$global:PSWebSessions[$testSessionID] = [hashtable]::Synchronized(@{
    UserID = "test-user"
    Roles = @("debug", "system_admin")
    Provider = "Test"
})

# Retrieve it using Get-PSWebSessions
$retrieved = Get-PSWebSessions -SessionID $testSessionID

Write-Host "Session Type: $($retrieved.GetType().FullName)" -ForegroundColor $(if ($retrieved -is [hashtable]) { "Green" } else { "Red" })
Write-Host "IsArray: $($retrieved -is [System.Array])" -ForegroundColor $(if ($retrieved -is [System.Array]) { "Red" } else { "Green" })
Write-Host "Has Roles: $($ null -ne $retrieved.Roles)" -ForegroundColor $(if ($retrieved.Roles) { "Green" } else { "Red" })
Write-Host "Roles Value: $($retrieved.Roles -join ', ')" -ForegroundColor Gray

# Cleanup
$global:PSWebSessions.Remove($testSessionID)

if ($retrieved -is [hashtable] -and $retrieved.Roles) {
    Write-Host "`n✓ FIX IS ACTIVE" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n✗ FIX NOT ACTIVE" -ForegroundColor Red
    exit 1
}
'@

# Save to temp file
$tempScript = Join-Path $env:TEMP "pswebhost_module_check_$(Get-Random).ps1"
$testScript | Out-File -FilePath $tempScript -Encoding UTF8

# Execute in context where PSWebHost modules are loaded
try {
    . "$PSScriptRoot\..\..\WebHost.ps1" -InitializeEnvironmentOnly 3>$null 4>$null 6>$null | Out-Null
    & $tempScript
} finally {
    Remove-Item $tempScript -ErrorAction SilentlyContinue
}
