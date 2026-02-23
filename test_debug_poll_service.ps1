# Test Debug Poll Service
# Verifies that debug polling service auto-loads for users with debug role

Write-Host "=== Testing Debug Poll Service ===" -ForegroundColor Cyan
Write-Host "`nThis test verifies the debug polling service:" -ForegroundColor Yellow
Write-Host "  1. Service script auto-injects for users with debug role" -ForegroundColor Yellow
Write-Host "  2. Polling works without requiring visible debug console card" -ForegroundColor Yellow

Write-Host "`nMANUAL TEST PROCEDURE:" -ForegroundColor Cyan
Write-Host "  1. Open browser at http://localhost:8080" -ForegroundColor White
Write-Host "  2. Log in with a user account that has 'debug' or 'system_admin' role" -ForegroundColor White
Write-Host "  3. Open browser Developer Tools (F12) -> Console tab" -ForegroundColor White
Write-Host "  4. Look for these log messages:" -ForegroundColor White
Write-Host "     - '[DebugPollService] Initializing background command polling'" -ForegroundColor Gray
Write-Host "     - '[DebugPollService] Starting polling (every 3000ms)'" -ForegroundColor Gray
Write-Host "     - '[DebugPollService] Initialized and polling started'" -ForegroundColor Gray
Write-Host "  5. Verify polling requests in Network tab:" -ForegroundColor White
Write-Host "     - Should see GET requests to /apps/WebHostDebugExtensions/api/v1/debug/commands/poll" -ForegroundColor Gray
Write-Host "     - Requests should repeat every 3 seconds" -ForegroundColor Gray
Write-Host "     - Should receive 204 (No Content) if no commands queued" -ForegroundColor Gray

Write-Host "`nCHECKING IMPLEMENTATION:" -ForegroundColor Cyan

# Check that files exist
$filesToCheck = @{
    "Debug Poll Service Script" = "apps\WebHostDebugExtensions\public\debug-poll-service.js"
    "Poll Service Endpoint" = "apps\WebHostDebugExtensions\routes\api\v1\debug\poll-service\get.ps1"
    "Poll Service Security" = "apps\WebHostDebugExtensions\routes\api\v1\debug\poll-service\get.security.json"
    "SPA Shell (with injection code)" = "routes\spa\get.ps1"
}

foreach ($name in $filesToCheck.Keys) {
    $fullPath = Join-Path $PSScriptRoot $filesToCheck[$name]
    if (Test-Path $fullPath) {
        Write-Host "  ✓ $name" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $name - NOT FOUND" -ForegroundColor Red
    }
}

Write-Host "`nCHECKING SPA INJECTION CODE:" -ForegroundColor Cyan
$spaContent = Get-Content (Join-Path $PSScriptRoot "routes\spa\get.ps1") -Raw
if ($spaContent -match "Inject debug poll service") {
    Write-Host "  ✓ SPA has debug poll service injection code" -ForegroundColor Green

    # Show the injection code
    $lines = $spaContent -split "`n"
    $injectStart = ($lines | Select-String "Inject debug poll" | Select-Object -First 1).LineNumber - 1
    if ($injectStart -ge 0) {
        Write-Host "`n  Code snippet:" -ForegroundColor Gray
        for ($i = $injectStart; $i -lt [Math]::Min($injectStart + 12, $lines.Count); $i++) {
            Write-Host "    $($lines[$i])" -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host "  ✗ SPA missing debug poll service injection code" -ForegroundColor Red
}

Write-Host "`n=== Implementation Check Complete ===" -ForegroundColor Cyan
Write-Host "`nNEXT STEPS:" -ForegroundColor Yellow
Write-Host "  Follow the manual test procedure above to verify the service works in browser" -ForegroundColor White
