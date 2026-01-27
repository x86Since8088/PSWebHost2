# Build MemoryAnalyzer Tool

[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Building MemoryAnalyzer ===" -ForegroundColor Cyan
Write-Host "Configuration: $Configuration" -ForegroundColor Gray

$projectPath = $PSScriptRoot

Push-Location $projectPath

try {
    # Restore packages
    Write-Host "`nRestoring NuGet packages..." -ForegroundColor Yellow
    dotnet restore

    if ($LASTEXITCODE -ne 0) {
        throw "dotnet restore failed with exit code $LASTEXITCODE"
    }

    # Build
    Write-Host "`nBuilding project..." -ForegroundColor Yellow
    dotnet build -c $Configuration --no-restore

    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed with exit code $LASTEXITCODE"
    }

    # Show output location
    $outputPath = Join-Path $projectPath "bin\$Configuration\net8.0\MemoryAnalyzer.exe"

    if (Test-Path $outputPath) {
        Write-Host "`n✓ Build successful!" -ForegroundColor Green
        Write-Host "Executable: $outputPath" -ForegroundColor White

        # Show file size
        $fileSize = [math]::Round((Get-Item $outputPath).Length / 1KB, 2)
        Write-Host "Size: ${fileSize}KB" -ForegroundColor Gray

        # Test run
        Write-Host "`nTesting executable..." -ForegroundColor Yellow
        & $outputPath 2>&1 | Select-Object -First 5

        Write-Host "`n✓ Test successful!" -ForegroundColor Green
    }
    else {
        throw "Executable not found at expected location: $outputPath"
    }
}
catch {
    Write-Host "`n✗ Build failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    Pop-Location
}

Write-Host "`nUsage:" -ForegroundColor Cyan
Write-Host "  $outputPath <dump_file> [options]" -ForegroundColor White
Write-Host "  $outputPath <dump_file> -top 20 -strings -hashtables" -ForegroundColor Gray
Write-Host ""
