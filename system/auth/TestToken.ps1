# . (Join-Path $PSScriptRoot '..', '..', 'system', 'init.ps1')

# $user = Get-PSWebUser -Email 'admin@localhost.com'
# $authProvider = Get-PSWebAuthProvider -UserID $user.UserID -Provider 'tokenauthenticator'
# $secret = ($authProvider.data|ConvertFrom-Json).secret

# $totp = New-Object "Otp.Models.Totp" -ArgumentList $secret
# $totp.Now()

Write-Warning "This script is currently disabled because it relies on functions that no longer exist (e.g., Get-PSWebAuthProvider)."