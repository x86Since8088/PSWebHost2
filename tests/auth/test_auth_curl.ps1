# Test bearer token with curl (closer to real HTTP)
Write-Host "=== Bearer Token Test with curl ===" -ForegroundColor Cyan

. "$PSScriptRoot\..\..\WebHost.ps1" -InitializeEnvironmentOnly 3>$null 4>$null 6>$null | Out-Null

Write-Host "`nCreating test bearer token..." -ForegroundColor Yellow
$token = & "$PSScriptRoot\system\utility\Account_Auth_BearerToken_New.ps1" -TestAccount -Roles 'debug','system_admin' 2>$null

if (-not $token) {
    Write-Host "Failed to create token" -ForegroundColor Red
    exit 1
}

Write-Host "Token: $($token.ApiKey.Substring(0,20))..." -ForegroundColor Green

Write-Host "`nTesting with curl..." -ForegroundColor Yellow
$uri = "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history"

try {
    $result = curl.exe -s -w "`nHTTP_CODE:%{http_code}" -H "Authorization: Bearer $($token.ApiKey)" "$uri"

    $lines = $result -split "`n"
    $httpCode = ($lines | Where-Object { $_ -match "HTTP_CODE:(\d+)" } | Select-Object -Last 1) -replace "HTTP_CODE:",""
    $body = ($lines | Where-Object { $_ -notmatch "HTTP_CODE:" }) -join "`n"

    Write-Host "HTTP Status: $httpCode" -ForegroundColor $(if ($httpCode -eq "200") { "Green" } else { "Red" })
    Write-Host "Response Body:" -ForegroundColor Cyan
    $body | Write-Host

    if ($httpCode -eq "200") {
        Write-Host "`n✓ SUCCESS!" -ForegroundColor Green
        $exitCode = 0
    } else {
        Write-Host "`n✗ FAILED!" -ForegroundColor Red
        $exitCode = 1
    }
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
}

# Cleanup
& "$PSScriptRoot\system\utility\Account_Auth_BearerToken_Remove.ps1" -KeyID $token.KeyID -Force -Confirm:$false -RemoveUser 2>&1 | Out-Null

exit $exitCode
