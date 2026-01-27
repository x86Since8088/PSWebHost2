#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
    Clean up remaining FileExplorerHelper.ps1 references

.DESCRIPTION
    Removes leftover $helperPath checks and updates error messages
#>

$ErrorActionPreference = 'Stop'

Write-Host "`n========== Cleaning Up FileExplorerHelper References ==========" -ForegroundColor Cyan

$files = Get-ChildItem -Path "apps\WebhostFileExplorer\routes" -Recurse -Filter "*.ps1" |
    Where-Object { (Get-Content $_.FullName -Raw) -match "FileExplorerHelper" }

Write-Host "`nFound $($files.Count) files to clean:" -ForegroundColor Yellow

$updatedCount = 0

foreach ($file in $files) {
    Write-Host "`nProcessing: $($file.Name)" -ForegroundColor Yellow

    try {
        $content = Get-Content $file.FullName -Raw
        $originalContent = $content

        # Fix 1: Update comment "Dot-source" to "Import"
        $content = $content -replace '# Dot-source File Explorer helper', '# Import File Explorer helper module'

        # Fix 2: Remove Test-Path check for $helperPath (no longer needed)
        $content = $content -replace '(?ms)\s*if \(-not \(Test-Path \$helperPath\)\) \{\s*throw "Helper file not found: \$helperPath"\s*\}\s*', ''

        # Fix 3: Update error message from "FileExplorerHelper.ps1" to "FileExplorerHelper module"
        $content = $content -replace 'Failed to load FileExplorerHelper\.ps1', 'Failed to import FileExplorerHelper module'

        if ($content -ne $originalContent) {
            Set-Content -Path $file.FullName -Value $content -NoNewline
            Write-Host "  ✅ Cleaned successfully" -ForegroundColor Green
            $updatedCount++
        } else {
            Write-Host "  ⚠️  No changes needed" -ForegroundColor Gray
        }

    } catch {
        Write-Host "  ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n========== Summary ==========" -ForegroundColor Cyan
Write-Host "Cleaned: $updatedCount files" -ForegroundColor Green
Write-Host ""
