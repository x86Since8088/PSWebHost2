#Requires -Version 7

<#
.SYNOPSIS
    WebHostTaskManagement Main Loop

.DESCRIPTION
    Executes in the main WebHost.ps1 loop with access to $Global:PSWebServer.Jobs
    Processes job command queue and manages job lifecycle

.NOTES
    Called from WebHost.ps1 main loop every cycle
    Has direct access to $Global:PSWebServer.Jobs for processing commands
    API endpoints can access $Global:PSWebServer from runspaces via synchronized hashtables
#>

param()

$MyTag = '[WebHostTaskManagement:MainLoop]'
$AppFolder = $PSScriptRoot

try {
    # Ensure job system is initialized
    if (-not $Global:PSWebServer.Jobs) {
        return Write-PSWebHostLog -Severity 'Error' -Category 'JobSystem' -Message "$MyTag Global:PSWebServer.Jobs is null."
    }

    # Ensure PSWebHost_Jobs module functions are available
    if (-not (Get-Command Process-PSWebHostJobCommandQueue -ErrorAction SilentlyContinue)) {
        $modulePath = Join-Path $PSWebServer.Project_Root.Path 'modules\PSWebHost_Jobs'
        return Write-PSWebHostLog -Severity 'Error' -Category 'JobSystem' -Message "Command not loaded: Process-PSWebHostJobCommandQueue. Loading module '$modulePath'"
        Import-Module $modulePath -DisableNameChecking
    }

    # Process job command queue - this executes queued start/stop/restart commands
    # Commands are added to the queue by API endpoints running in runspaces
    $processedCommands = Process-PSWebHostJobCommandQueue

    # Log when commands are processed
    if ($processedCommands -gt 0) {
        Write-Verbose "$MyTag Processed $processedCommands job command(s)"
    }

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'JobSystem' -Message "Error in TaskManagement main loop: $($_.Exception.Message)"
}

