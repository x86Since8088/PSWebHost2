#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
    Update FileExplorerHelper imports to use Import-TrackedModule

.DESCRIPTION
    Replaces Import-Module with Import-TrackedModule for hot reload support
#>

$ErrorActionPreference = 'Stop'

Write-Host "`n========== Updating FileExplorerHelper for Hot Reload ==========" -ForegroundColor Cyan

$files = Get-ChildItem -Path "apps\WebhostFileExplorer\routes" -Recurse -Filter "*.ps1" |
    Where-Object { (Get-Content $_.FullName -Raw) -match "Import-Module.*FileExplorerHelper" }

Write-Host "`nFound $($files.Count) files to update:" -ForegroundColor Yellow

$updatedCount = 0

foreach ($file in $files) {
    Write-Host "`nProcessing: $($file.FullName -replace [regex]::Escape($PWD), '.')" -ForegroundColor Yellow

    try {
        $content = Get-Content $file.FullName -Raw

        # Pattern: Replace Import-Module with Import-TrackedModule
        # OLD: Import-Module (Join-Path $PSScriptRoot "..\\..\\..\\modules\\FileExplorerHelper") -Force -ErrorAction Stop
        # NEW: Import-TrackedModule -Path (Join-Path $PSScriptRoot "..\\..\\..\\modules\\FileExplorerHelper\\FileExplorerHelper.psd1")

        $pattern = 'Import-Module \(Join-Path \$PSScriptRoot "([^"]+)FileExplorerHelper"\) -Force -ErrorAction Stop'
        $replacement = 'Import-TrackedModule -Path (Join-Path $PSScriptRoot "$1FileExplorerHelper\FileExplorerHelper.psd1")'

        if ($content -match $pattern) {
            $newContent = $content -replace $pattern, $replacement

            Set-Content -Path $file.FullName -Value $newContent -NoNewline

            Write-Host "  ✅ Updated to use Import-TrackedModule" -ForegroundColor Green
            $updatedCount++
        } else {
            Write-Host "  ⚠️  Pattern not found" -ForegroundColor Yellow
        }

    } catch {
        Write-Host "  ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n========== Summary ==========" -ForegroundColor Cyan
Write-Host "Updated: $updatedCount files" -ForegroundColor Green
Write-Host "Total: $($files.Count) files" -ForegroundColor White
Write-Host ""

if ($updatedCount -gt 0) {
    Write-Host "✅ All FileExplorerHelper imports now use Import-TrackedModule" -ForegroundColor Green
    Write-Host "   Hot reload enabled - module will auto-reload when .psm1 changes" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Benefits:" -ForegroundColor Yellow
    Write-Host "  • Module changes detected automatically" -ForegroundColor White
    Write-Host "  • No server restart needed for development" -ForegroundColor White
    Write-Host "  • Tracked in `$Global:PSWebServerModules" -ForegroundColor White
}
