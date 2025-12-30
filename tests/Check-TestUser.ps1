# Check-TestUser.ps1
# Verifies test@W11 user exists in database

Import-Module 'C:\sc\PsWebHost\modules\PSWebHost_Database' -Force
$Global:PSWebServer = @{ Project_Root = @{ Path = 'C:\sc\PsWebHost' } }

Write-Host "`nChecking for test@W11 user..." -ForegroundColor Cyan
$user = Get-PSWebUser -Email 'test@W11'

if ($user) {
    Write-Host "`n✓ User found:" -ForegroundColor Green
    $user | Format-List
} else {
    Write-Host "`n✗ User not found" -ForegroundColor Red
}
