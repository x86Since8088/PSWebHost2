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
    # Return element configuration in standard format
    $elementConfig = @{
        status = 'success'
        component = 'task-manager'
        scriptPath = '/apps/WebHostTaskManagement/public/elements/task-manager/component.js'
        element = @{
            id = 'task-manager'
            type = 'component'
            component = 'task-manager'
            title = 'Task Management'
            icon = '📋'
            description = 'Manage scheduled tasks, background jobs, and runspaces'
            refreshable = $true
            autoRefreshInterval = 5000  # 5 seconds
            helpFile = 'public/help/task-manager.md'
            width = 12  # Full width card
            height = 800
            features = @(
                'Browse and start jobs from catalog'
                'Monitor active background jobs'
                'View and manage scheduled tasks'
                'Track runspace usage and detect leaks'
                'Stop and restart jobs'
                'Role-based job permissions'
                'Template variable support'
                'Auto-refresh every 5 seconds'
            )
        }
    }

    # Test mode
    if ($Test) {
        Write-Host "`n=== API Endpoint Test Results ===" -ForegroundColor Cyan
        Write-Host "Status: 200 OK" -ForegroundColor Green
        $elementConfig | ConvertTo-Json -Depth 10 | Write-Host
        return
    }

    # Normal HTTP response
    $jsonData = $elementConfig | ConvertTo-Json -Depth 10
    context_response -Response $Response -StatusCode 200 -String $jsonData -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity Error -Category TaskManagement -Message "Error loading task-manager UI: $($_.Exception.Message)"

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
