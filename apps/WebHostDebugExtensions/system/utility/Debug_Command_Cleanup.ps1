#Requires -Version 7

<#
.SYNOPSIS
    Cleans up stale command files from outbox and inbox

.DESCRIPTION
    Removes expired command files and old result files.
    Can be run manually or scheduled via task scheduler.

.PARAMETER DataRoot
    Root data directory (default: .\PsWebHost_Data)

.PARAMETER OutboxMaxAgeMinutes
    Maximum age for outbox files in minutes (default: 60)

.PARAMETER InboxMaxAgeMinutes
    Maximum age for inbox files in minutes (default: 1440 = 24 hours)

.PARAMETER WhatIf
    Show what would be deleted without actually deleting

.EXAMPLE
    .\Debug_Command_Cleanup.ps1

.EXAMPLE
    .\Debug_Command_Cleanup.ps1 -OutboxMaxAgeMinutes 30 -WhatIf

.EXAMPLE
    .\Debug_Command_Cleanup.ps1 -InboxMaxAgeMinutes 60
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$DataRoot = ".\PsWebHost_Data",

    [Parameter()]
    [int]$OutboxMaxAgeMinutes = 60,

    [Parameter()]
    [int]$InboxMaxAgeMinutes = 1440
)

$MyTag = '[Debug-Command-Cleanup]'

try {
    # Resolve data root path
    if (-not [System.IO.Path]::IsPathRooted($DataRoot)) {
        $DataRoot = Join-Path $PSScriptRoot "..\..\..\..\$DataRoot"
        $DataRoot = [System.IO.Path]::GetFullPath($DataRoot)
    }

    $extensionsRoot = Join-Path $DataRoot "apps\WebHostDebugExtensions"
    $outboxRoot = Join-Path $extensionsRoot "outbox"
    $inboxRoot = Join-Path $extensionsRoot "inbox"

    $now = Get-Date
    $stats = @{
        OutboxFilesDeleted = 0
        InboxFilesDeleted = 0
        OutboxBytesCleaned = 0
        InboxBytesCleaned = 0
    }

    Write-Host "$MyTag Starting cleanup..." -ForegroundColor Cyan
    Write-Host "$MyTag   Outbox Max Age: $OutboxMaxAgeMinutes minutes" -ForegroundColor Gray
    Write-Host "$MyTag   Inbox Max Age: $InboxMaxAgeMinutes minutes" -ForegroundColor Gray

    # Clean outbox
    if (Test-Path $outboxRoot) {
        Write-Verbose "$MyTag Scanning outbox: $outboxRoot"

        $outboxFiles = Get-ChildItem -Path $outboxRoot -Filter "*.json" -Recurse -File -ErrorAction SilentlyContinue

        foreach ($file in $outboxFiles) {
            $age = ($now - $file.LastWriteTime).TotalMinutes

            if ($age -gt $OutboxMaxAgeMinutes) {
                if ($PSCmdlet.ShouldProcess($file.FullName, "Delete stale outbox file (age: $([math]::Round($age, 1)) min)")) {
                    $stats.OutboxBytesCleaned += $file.Length
                    $stats.OutboxFilesDeleted++
                    Remove-Item -Path $file.FullName -Force
                    Write-Verbose "$MyTag Deleted: $($file.Name) (age: $([math]::Round($age, 1)) min)"
                }
            }
        }
    }

    # Clean inbox
    if (Test-Path $inboxRoot) {
        Write-Verbose "$MyTag Scanning inbox: $inboxRoot"

        $inboxFiles = Get-ChildItem -Path $inboxRoot -Filter "*.json" -Recurse -File -ErrorAction SilentlyContinue

        foreach ($file in $inboxFiles) {
            $age = ($now - $file.LastWriteTime).TotalMinutes

            if ($age -gt $InboxMaxAgeMinutes) {
                if ($PSCmdlet.ShouldProcess($file.FullName, "Delete old inbox file (age: $([math]::Round($age, 1)) min)")) {
                    $stats.InboxBytesCleaned += $file.Length
                    $stats.InboxFilesDeleted++
                    Remove-Item -Path $file.FullName -Force
                    Write-Verbose "$MyTag Deleted: $($file.Name) (age: $([math]::Round($age, 1)) min)"
                }
            }
        }
    }

    # Clean empty session folders
    foreach ($root in @($outboxRoot, $inboxRoot)) {
        if (Test-Path $root) {
            $emptyFolders = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
                Where-Object { (Get-ChildItem -Path $_.FullName -File -ErrorAction SilentlyContinue).Count -eq 0 }

            foreach ($folder in $emptyFolders) {
                if ($PSCmdlet.ShouldProcess($folder.FullName, "Remove empty session folder")) {
                    Remove-Item -Path $folder.FullName -Force -Recurse
                    Write-Verbose "$MyTag Removed empty folder: $($folder.Name)"
                }
            }
        }
    }

    # Report
    Write-Host "`n$MyTag Cleanup Summary:" -ForegroundColor Cyan
    Write-Host "$MyTag   Outbox Files Deleted: $($stats.OutboxFilesDeleted)" -ForegroundColor $(if ($stats.OutboxFilesDeleted -gt 0) { "Yellow" } else { "Green" })
    Write-Host "$MyTag   Inbox Files Deleted:  $($stats.InboxFilesDeleted)" -ForegroundColor $(if ($stats.InboxFilesDeleted -gt 0) { "Yellow" } else { "Green" })

    $totalKB = [math]::Round(($stats.OutboxBytesCleaned + $stats.InboxBytesCleaned) / 1KB, 2)
    Write-Host "$MyTag   Total Space Freed:    $totalKB KB" -ForegroundColor Gray

    Write-Host "$MyTag Cleanup complete" -ForegroundColor Green

    return $stats

} catch {
    Write-Error "$MyTag Cleanup failed: $_"
    throw
}
