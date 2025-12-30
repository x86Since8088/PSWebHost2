
# Test-Webhost.ps1
# Fix: Use current script location to find project root
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Import-Module (Join-Path $ProjectRoot 'tests\helpers\Start-WebHostForTest.psm1')
try {
    $web = . Start-WebHostForTest -ProjectRoot $ProjectRoot
    if ($web) {
        Write-Host "Web host started successfully at $($web.Url)"
        $web.Process | Stop-Process -Force
        Write-host ((Get-Content $web.OutFiles.StdOut -ErrorAction SilentlyContinue) -join "`n")
        $web.OutFiles.StdOut
    }
} catch {
    Write-Host "Caught expected error:"
    $_.Exception.Message
}
Write-Host
Remove-module Start-WebHostForTest -Force