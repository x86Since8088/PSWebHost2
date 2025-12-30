# Check-PasswordUsers.ps1
# Verifies password users exist in database

$Global:PSWebServer = @{ Project_Root = @{ Path = 'C:\sc\PsWebHost' } }
Import-Module 'C:\sc\PsWebHost\modules\PSWebHost_Database' -Force

Write-Host "`nChecking for users with passwords..." -ForegroundColor Cyan

$query = @"
SELECT u.Email, u.PasswordHash, ap.provider, ap.data
FROM Users u
LEFT JOIN auth_user_provider ap ON u.UserID = ap.UserID
WHERE ap.provider = 'Password' OR u.PasswordHash != '';
"@

$users = Get-PSWebSQLiteData -File 'C:\sc\PsWebHost\PsWebHost_Data\pswebhost.db' -Query $query

if ($users) {
    Write-Host "`n✓ Password users found:" -ForegroundColor Green
    $users | Format-List
} else {
    Write-Host "`n✗ No password users found" -ForegroundColor Red
    Write-Host "Checking all users..." -ForegroundColor Yellow
    $allUsers = Get-PSWebSQLiteData -File 'C:\sc\PsWebHost\PsWebHost_Data\pswebhost.db' -Query 'SELECT * FROM Users;'
    $allUsers | Format-List
}
