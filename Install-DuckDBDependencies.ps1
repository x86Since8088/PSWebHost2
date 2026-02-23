<#
.SYNOPSIS
    Downloads DuckDB-WASM and Apache Arrow dependencies to local server

.DESCRIPTION
    Downloads required JavaScript libraries from NPM/CDN and stores them locally
    in public/lib/ directory for offline usage and faster loading.

.PARAMETER Force
    Force re-download even if files exist

.EXAMPLE
    .\Install-DuckDBDependencies.ps1

.EXAMPLE
    .\Install-DuckDBDependencies.ps1 -Force
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$MyTag = '[Install-DuckDBDependencies]'
$libPath = Join-Path $PSScriptRoot "public\lib"

# Ensure lib directory exists
if (-not (Test-Path $libPath)) {
    New-Item -Path $libPath -ItemType Directory -Force | Out-Null
    Write-Host "$MyTag Created directory: $libPath" -ForegroundColor Green
}

# Define dependencies
$dependencies = @(
    @{
        Name = "DuckDB-WASM (MVP)"
        Url = "https://cdn.jsdelivr.net/npm/@duckdb/duckdb-wasm@1.28.0/dist/duckdb-mvp.wasm.js"
        LocalPath = "duckdb-mvp.wasm.js"
        Size = "~200KB"
    },
    @{
        Name = "DuckDB-WASM (WASM binary)"
        Url = "https://cdn.jsdelivr.net/npm/@duckdb/duckdb-wasm@1.28.0/dist/duckdb-mvp.wasm"
        LocalPath = "duckdb-mvp.wasm"
        Size = "~4MB"
    },
    @{
        Name = "DuckDB-WASM (Worker)"
        Url = "https://cdn.jsdelivr.net/npm/@duckdb/duckdb-wasm@1.28.0/dist/duckdb-browser-mvp.worker.js"
        LocalPath = "duckdb-browser-mvp.worker.js"
        Size = "~50KB"
    },
    @{
        Name = "Apache Arrow (ES2015)"
        Url = "https://cdn.jsdelivr.net/npm/apache-arrow@14.0.2/Arrow.es2015.min.js"
        LocalPath = "apache-arrow.es2015.min.js"
        Size = "~500KB"
    }
)

Write-Host "`n$MyTag ===== DuckDB-WASM Dependency Installer =====" -ForegroundColor Cyan
Write-Host "$MyTag Target directory: $libPath`n" -ForegroundColor Cyan

$downloadedCount = 0
$skippedCount = 0
$failedCount = 0

foreach ($dep in $dependencies) {
    $localFile = Join-Path $libPath $dep.LocalPath
    $fileExists = Test-Path $localFile

    Write-Host "$MyTag Processing: $($dep.Name)" -ForegroundColor Yellow

    if ($fileExists -and -not $Force) {
        Write-Host "$MyTag   → Already exists, skipping (use -Force to re-download)" -ForegroundColor Gray
        $skippedCount++
        continue
    }

    try {
        Write-Host "$MyTag   → Downloading from: $($dep.Url)" -ForegroundColor Cyan
        Write-Host "$MyTag   → Expected size: $($dep.Size)" -ForegroundColor Cyan

        # Download with progress
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $dep.Url -OutFile $localFile -UseBasicParsing -TimeoutSec 60

        # Verify download
        if (Test-Path $localFile) {
            $fileSize = (Get-Item $localFile).Length
            $fileSizeKB = [math]::Round($fileSize / 1KB, 2)
            $fileSizeMB = [math]::Round($fileSize / 1MB, 2)

            $sizeDisplay = if ($fileSizeMB -gt 1) { "${fileSizeMB}MB" } else { "${fileSizeKB}KB" }

            Write-Host "$MyTag   ✓ Downloaded successfully: $sizeDisplay" -ForegroundColor Green
            $downloadedCount++
        } else {
            throw "File not created after download"
        }

    } catch {
        Write-Host "$MyTag   ✗ Download failed: $_" -ForegroundColor Red
        $failedCount++
    }
}

Write-Host "`n$MyTag ===== Download Summary =====" -ForegroundColor Cyan
Write-Host "$MyTag Downloaded: $downloadedCount" -ForegroundColor Green
Write-Host "$MyTag Skipped: $skippedCount" -ForegroundColor Gray
Write-Host "$MyTag Failed: $failedCount" -ForegroundColor $(if ($failedCount -gt 0) { "Red" } else { "Green" })

if ($failedCount -eq 0) {
    Write-Host "`n$MyTag ✓ All dependencies ready!" -ForegroundColor Green
    Write-Host "$MyTag Next step: Update metrics-worker.js to use local paths" -ForegroundColor Cyan
} else {
    Write-Host "`n$MyTag ⚠ Some downloads failed. Retry or check network connection." -ForegroundColor Yellow
    exit 1
}

# Create dependency manifest
$manifest = @{
    GeneratedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    DuckDBVersion = "1.28.0"
    ApacheArrowVersion = "14.0.2"
    Dependencies = $dependencies | ForEach-Object {
        @{
            Name = $_.Name
            LocalPath = $_.LocalPath
            SourceUrl = $_.Url
            FileExists = Test-Path (Join-Path $libPath $_.LocalPath)
            FileSize = if (Test-Path (Join-Path $libPath $_.LocalPath)) {
                (Get-Item (Join-Path $libPath $_.LocalPath)).Length
            } else { 0 }
        }
    }
}

$manifestPath = Join-Path $libPath "duckdb-dependencies.json"
$manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $manifestPath -Encoding UTF8

Write-Host "$MyTag Manifest saved to: $manifestPath" -ForegroundColor Cyan
