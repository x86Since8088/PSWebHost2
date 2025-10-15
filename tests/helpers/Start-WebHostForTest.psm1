function Start-WebHostForTest {
    param(
        [string]$ProjectRoot,
        [int]$Port = 0,
        [int]$StartupTimeoutSec = 20,
        [string]$OutDir
    )

    if (-not $ProjectRoot) { $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
    # find pwsh or fallback
    $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwsh) { $pwsh = (Get-Command powershell -ErrorAction SilentlyContinue).Source }

    $webHostScript = Join-Path $ProjectRoot 'WebHost.ps1'
    if (-not (Test-Path $webHostScript)) { throw "WebHost.ps1 not found at $webHostScript" }

    if ($Port -eq 0) {
        do { $Port = Get-Random -Minimum 20000 -Maximum 60000 } while (Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue)
    }

    if (-not $OutDir) { $OutDir = Join-Path $ProjectRoot 'tests\test-host-logs' }
    New-Item -Path $OutDir -ItemType Directory -Force | Out-Null
    $stdout = Join-Path $OutDir "webhost.$Port.out.txt"
    $stderr = Join-Path $OutDir "webhost.$Port.err.txt"

    $argList = @('-NoProfile','-NoLogo','-ExecutionPolicy','Bypass','-File',(Resolve-Path $webHostScript).ProviderPath,'-Port',$Port)

    $proc = Start-Process -FilePath $pwsh -ArgumentList $argList -WorkingDirectory $ProjectRoot -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru

    $baseUrl = "http://localhost:$Port/"
    $deadline = (Get-Date).AddSeconds($StartupTimeoutSec)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest -Uri $baseUrl -UseBasicParsing -TimeoutSec 2
            if ($r.StatusCode -eq 200) { $ready = $true; break }
        } catch { Start-Sleep -Seconds 1 }
    }

    return [pscustomobject]@{ Process = $proc; Url = $baseUrl; Ready = $ready; OutFiles = @{ StdOut = $stdout; StdErr = $stderr } }
}

Export-ModuleMember -Function Start-WebHostForTest
