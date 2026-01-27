#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
    Fix all FileExplorerHelper.ps1 dot-sourcing references to use proper module imports

.DESCRIPTION
    Replaces all instances of:
      $helperPath = Join-Path ... "FileExplorerHelper.ps1"
      . $helperPath

    With:
      Import-Module (Join-Path $PSScriptRoot "..\..\..\..\modules\FileExplorerHelper") -Force -ErrorAction Stop
#>

$ErrorActionPreference = 'Stop'

Write-Host "`n========== Fixing FileExplorerHelper References ==========" -ForegroundColor Cyan

# Find all files that reference FileExplorerHelper.ps1
$files = Get-ChildItem -Path "apps\WebhostFileExplorer\routes" -Recurse -Filter "*.ps1" |
    Where-Object { (Get-Content $_.FullName -Raw) -match "FileExplorerHelper\.ps1" }

Write-Host "`nFound $($files.Count) files to update:" -ForegroundColor Yellow
$files | ForEach-Object { Write-Host "  - $($_.FullName -replace [regex]::Escape($PWD), '.')" -ForegroundColor Gray }

$updatedCount = 0
$errorCount = 0

foreach ($file in $files) {
    Write-Host "`nProcessing: $($file.Name)" -ForegroundColor Yellow

    try {
        $content = Get-Content $file.FullName -Raw

        # Calculate the correct relative path based on file location
        $relativePath = $file.DirectoryName -replace [regex]::Escape((Get-Item "apps\WebhostFileExplorer\routes").FullName), ''
        $depth = ($relativePath.Split([IO.Path]::DirectorySeparatorChar) | Where-Object { $_ }).Count
        $backPath = ('..' + [IO.Path]::DirectorySeparatorChar) * $depth + "modules\FileExplorerHelper"
        $backPath = $backPath -replace '\\', '\\'  # Escape for regex

        # Pattern 1: Remove the $helperPath variable assignment
        $pattern1 = '(?m)^\s*\$helperPath\s*=\s*Join-Path\s+\$PSScriptRoot\s+"[^"]+FileExplorerHelper\.ps1"\s*\r?\n'

        # Pattern 2: Replace dot-sourcing with Import-Module
        $pattern2 = '(?m)(\s*# Always dot-source.*\r?\n)?\s*\.\s+\$helperPath\s*\r?\n'

        if ($content -match $pattern1) {
            # Calculate proper module path
            $moduleImport = "Import-Module (Join-Path `$PSScriptRoot `"$backPath`") -Force -ErrorAction Stop"

            # Remove $helperPath assignment and replace dot-sourcing
            $newContent = $content -replace $pattern1, ''
            $newContent = $newContent -replace $pattern2, "`n    $moduleImport`n"

            # Write back to file
            Set-Content -Path $file.FullName -Value $newContent -NoNewline

            Write-Host "  ✅ Updated successfully" -ForegroundColor Green
            $updatedCount++
        } else {
            Write-Host "  ⚠️  Pattern not found (file may already be updated)" -ForegroundColor Yellow
        }

    } catch {
        Write-Host "  ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
}

Write-Host "`n========== Summary ==========" -ForegroundColor Cyan
Write-Host "Updated: $updatedCount files" -ForegroundColor Green
Write-Host "Errors: $errorCount files" -ForegroundColor $(if ($errorCount -gt 0) { 'Red' } else { 'Gray' })
Write-Host "Total: $($files.Count) files processed" -ForegroundColor White
Write-Host ""

if ($updatedCount -gt 0) {
    Write-Host "✅ All references updated to use Import-Module" -ForegroundColor Green
    Write-Host "   Module location: apps\WebhostFileExplorer\modules\FileExplorerHelper\" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Restart the server to test the changes" -ForegroundColor White
    Write-Host "2. Verify all FileExplorer endpoints work" -ForegroundColor White
    Write-Host "3. Check server logs for any module loading errors" -ForegroundColor White
}
