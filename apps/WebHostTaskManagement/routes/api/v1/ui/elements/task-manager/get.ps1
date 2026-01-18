#Requires -Version 7

<#
.SYNOPSIS
    GET /apps/WebHostTaskManagement/api/v1/ui/elements/task-manager

.DESCRIPTION
    Returns the task manager UI component layout
    Component file: /apps/WebHostTaskManagement/public/elements/task-manager/component.js
#>

param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata,
    [switch]$Test,
    [string[]]$Roles = @(),
    [hashtable]$Query = @{}
)

$MyTag = '[WebHostTaskManagement:UI:TaskManager]'

try {
    # Return the card component metadata
    $cardInfo = @{
        component = 'task-manager'
        title = 'Task Management'
        description = 'Manage scheduled tasks, background jobs, and runspaces'
        scriptPath = '/apps/WebHostTaskManagement/public/elements/task-manager/component.js'
        width = 12  # Full width
        height = 800
        features = @(
            'View and enable/disable scheduled tasks'
            'Monitor background PowerShell jobs'
            'Track runspace usage and detect leaks'
            'Stop and remove jobs'
            'Auto-refresh every 5 seconds'
            'Left-side navigation menu'
            'Statistics dashboard'
        )
    }

    # Test mode
    if ($Test) {
        Write-Host "`n=== API Endpoint Test Results ===" -ForegroundColor Cyan
        Write-Host "Status: 200 OK" -ForegroundColor Green
        $cardInfo | ConvertTo-Json -Depth 10 | Write-Host
        return
    }

    # Normal HTTP response
    $jsonData = $cardInfo | ConvertTo-Json -Depth 5 -Compress
    context_response -Response $Response -StatusCode 200 -String $jsonData -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity Error -Category TaskManagement -Message "Error loading task-manager UI: $($_.Exception.Message)"

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
