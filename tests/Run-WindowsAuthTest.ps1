# Run-WindowsAuthTest.ps1
# Helper script to run Windows auth test and capture output

$testScript = Join-Path $PSScriptRoot "Test-WindowsAuthFlow.ps1"
$outputFile = Join-Path $env:TEMP "WindowsAuthTest_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

Write-Host "Running Windows Authentication Test as Administrator..." -ForegroundColor Cyan
Write-Host "Output will be saved to: $outputFile`n" -ForegroundColor Gray

$scriptBlock = {
    param($TestScript, $OutputFile)
    & $TestScript -UseTestAccount *>&1 | Tee-Object -FilePath $OutputFile
}

$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(
    "& { $($scriptBlock.ToString()) } -TestScript '$testScript' -OutputFile '$outputFile'"
))

Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCommand" -Verb RunAs -Wait

# Display output
if (Test-Path $outputFile) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Test Output:" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    Get-Content $outputFile
}
else {
    Write-Host "Output file not found: $outputFile" -ForegroundColor Red
}
