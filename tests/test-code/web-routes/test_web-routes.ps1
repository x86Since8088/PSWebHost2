
# Use $ProjectRoot and Start-WebHostForTest for web host lifecycle
$ProjectRoot = (Resolve-Path "$PSScriptRoot\..\..\..").Path
Import-Module (Join-Path $ProjectRoot 'tests\modules\TestCodeHelpers.psm1') -ErrorAction SilentlyContinue
Import-Module (Join-Path $ProjectRoot 'tests\helpers\Start-WebHostForTest.psm1') -ErrorAction SilentlyContinue

$web = Start-WebHostForTest -ProjectRoot $ProjectRoot
try {
    if (-not $web.Ready) { throw "Web host did not start on $($web.Url)" }
    $r = Invoke-WebRequest -Uri $web.Url -UseBasicParsing -TimeoutSec 5
    Assert-Equal -Actual $r.StatusCode -Expected 200 -Message 'GET / returns 200' | Out-Null
    $ct = $r.Headers['Content-Type']
    Assert-True -Condition ($ct -and $ct -match 'text/html') -Message 'Content-Type is text/html' | Out-Null
} catch {
    Write-Error "Web host not reachable: $($_.Exception.Message)"
} finally {
    if ($web.Process) { $web.Process | Stop-Process -Force }
}