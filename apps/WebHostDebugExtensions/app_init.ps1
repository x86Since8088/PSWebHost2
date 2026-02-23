#Requires -Version 7

# WebHostDebugExtensions App Initialization Script
# This script runs during PSWebHost startup when the WebHostDebugExtensions app is loaded

param(
    [hashtable]$PSWebServer,
    [string]$AppRoot
)

$MyTag = '[WebHostDebugExtensions:Init]'

Write-Host "$MyTag Initializing debug extensions system..." -ForegroundColor Cyan

try {
    # Initialize debug command queue in $Global:PSWebServer
    if (-not $Global:PSWebServer.DebugCommands) {
        $Global:PSWebServer.DebugCommands = [hashtable]::Synchronized(@{
            Queue = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
            History = [System.Collections.Concurrent.ConcurrentBag[hashtable]]::new()
            MaxQueueSize = 100
            MaxHistorySize = 500
        })

        Write-Host "$MyTag Debug command queue initialized" -ForegroundColor Green
        Write-Host "$MyTag   Max Queue Size: 100" -ForegroundColor Gray
        Write-Host "$MyTag   Max History Size: 500" -ForegroundColor Gray
    } else {
        Write-Host "$MyTag Debug command queue already initialized" -ForegroundColor Yellow
    }

    # Note: Utility scripts in system\utility\ are now HTTP client scripts
    # They should be called externally, not dot-sourced during server init
    # Examples:
    #   .\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1
    #   .\apps\WebHostDebugExtensions\system\utility\Launch-DebugCard.ps1
    #   etc.

    Write-Host "$MyTag Utility scripts available in system/utility/ (call externally)" -ForegroundColor Green

    # Create helper accessor functions for command history
    if (-not (Get-Command Get-DebugCommandHistory -ErrorAction SilentlyContinue)) {
        function global:Get-DebugCommandHistory {
            <#
            .SYNOPSIS
                Retrieves debug command history
            .PARAMETER Limit
                Maximum number of commands to return (default: all)
            .PARAMETER CommandID
                Filter by specific command ID
            .PARAMETER Status
                Filter by status (pending, completed, failed)
            #>
            [CmdletBinding()]
            param(
                [int]$Limit = 0,
                [string]$CommandID,
                [ValidateSet('pending', 'completed', 'failed')]
                [string]$Status
            )

            if (-not $Global:PSWebServer.DebugCommands -or -not $Global:PSWebServer.DebugCommands.History) {
                return @()
            }

            $history = $Global:PSWebServer.DebugCommands.History

            # Filter by CommandID
            if ($CommandID) {
                $history = $history | Where-Object { $_.CommandID -eq $CommandID }
            }

            # Filter by Status
            if ($Status) {
                $history = $history | Where-Object { $_.Status -eq $Status }
            }

            # Sort by completion time, most recent first
            $history = $history | Sort-Object CompletedAt -Descending

            # Limit results
            if ($Limit -gt 0) {
                $history = $history | Select-Object -First $Limit
            }

            return $history
        }
    }

    if (-not (Get-Command Get-DebugCommandQueue -ErrorAction SilentlyContinue)) {
        function global:Get-DebugCommandQueue {
            <#
            .SYNOPSIS
                Retrieves pending commands from the debug command queue
            #>
            [CmdletBinding()]
            param()

            if (-not $Global:PSWebServer.DebugCommands -or -not $Global:PSWebServer.DebugCommands.Queue) {
                return @()
            }

            return $Global:PSWebServer.DebugCommands.Queue.ToArray()
        }
    }

    if (-not (Get-Command Get-DebugCommandResult -ErrorAction SilentlyContinue)) {
        function global:Get-DebugCommandResult {
            <#
            .SYNOPSIS
                Retrieves debug command result from disk or memory
            .PARAMETER CommandID
                The command ID to retrieve
            .PARAMETER FromDisk
                Force read from disk even if in memory
            #>
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [string]$CommandID,

                [switch]$FromDisk
            )

            # Try memory first unless FromDisk is specified
            if (-not $FromDisk) {
                $memoryResult = Get-DebugCommandHistory -CommandID $CommandID
                if ($memoryResult) {
                    return $memoryResult
                }
            }

            # Try disk
            $resultsDir = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\debug_results"
            if (-not (Test-Path $resultsDir)) {
                return $null
            }

            $filePath = Join-Path $resultsDir "$CommandID.json"
            if (Test-Path $filePath) {
                try {
                    $content = Get-Content -Path $filePath -Raw -Encoding UTF8
                    return $content | ConvertFrom-Json
                } catch {
                    Write-Warning "Failed to read result from disk: $($_.Exception.Message)"
                    return $null
                }
            }

            return $null
        }
    }

    if (-not (Get-Command Get-AllDebugCommandResults -ErrorAction SilentlyContinue)) {
        function global:Get-AllDebugCommandResults {
            <#
            .SYNOPSIS
                Retrieves all debug command results from disk
            .PARAMETER Limit
                Maximum number of results to return (most recent first)
            #>
            [CmdletBinding()]
            param(
                [int]$Limit = 0
            )

            $resultsDir = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\debug_results"
            if (-not (Test-Path $resultsDir)) {
                return @()
            }

            $files = Get-ChildItem -Path $resultsDir -Filter "*.json" | Sort-Object LastWriteTime -Descending

            if ($Limit -gt 0) {
                $files = $files | Select-Object -First $Limit
            }

            $results = @()
            foreach ($file in $files) {
                try {
                    $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
                    $results += $content | ConvertFrom-Json
                } catch {
                    Write-Warning "Failed to read $($file.Name): $($_.Exception.Message)"
                }
            }

            return $results
        }
    }

    Write-Host "$MyTag Helper functions registered:" -ForegroundColor Green
    Write-Host "$MyTag   - Get-DebugCommandHistory" -ForegroundColor Gray
    Write-Host "$MyTag   - Get-DebugCommandQueue" -ForegroundColor Gray
    Write-Host "$MyTag   - Get-DebugCommandResult" -ForegroundColor Gray
    Write-Host "$MyTag   - Get-AllDebugCommandResults" -ForegroundColor Gray
    Write-Host "$MyTag Initialization complete" -ForegroundColor Cyan

} catch {
    Write-Error "$MyTag Failed to initialize: $($_.Exception.Message)"
    Write-Error "$MyTag Stack Trace: $($_.ScriptStackTrace)"
}
