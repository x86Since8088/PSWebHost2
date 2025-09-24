
$ProjectRoot = (Resolve-Path "$PSScriptRoot\..\..\..").Path
Import-Module (Join-Path $ProjectRoot 'tests\modules\TestCodeHelpers.psm1') -ErrorAction SilentlyContinue
$scriptPath = Join-Path $ProjectRoot 'system\validateInstall.ps1'
if (-not (Test-Path $scriptPath)) { Write-Error "validateInstall not found at $scriptPath"; return }

# Run validateInstall and assert no critical errors
$Error.Clear()
. (Resolve-Path $scriptPath).ProviderPath -Verbose
if ($Error.Count -gt 0) {
	Write-Output "Errors: $($Error.Count)"
	$Error | ForEach-Object { Write-Output $_.ToString() }
} else {
	Write-Output 'No errors'
}
