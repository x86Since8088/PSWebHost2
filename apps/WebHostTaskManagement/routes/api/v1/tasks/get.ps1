#Requires -Version 7

<#
.SYNOPSIS
    GET /apps/WebHostTaskManagement/api/v1/tasks

.DESCRIPTION
    Returns all task definitions (default + runtime overrides)

.PARAMETER Context
    HttpListenerContext object

.PARAMETER Request
    HttpListenerRequest object

.PARAMETER Response
    HttpListenerResponse object

.PARAMETER sessiondata
    Session data for the current user

.PARAMETER Test
    Test mode - outputs to console

.PARAMETER Roles
    User roles for testing

.PARAMETER Query
    Query parameters for testing
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

$MyTag = '[WebHostTaskManagement:API:Tasks:Get]'

try {
    # Get all task definitions
    $tasks = Get-AllTaskDefinitions

    # Enrich with runtime status
    $enrichedTasks = foreach ($task in $tasks) {
        $runningJob = Get-RunningTaskJob -Task $task

        [PSCustomObject]@{
            name = $task.name
            description = $task.description
            appName = $task.appName
            source = $task.source
            enabled = $task.enabled
            schedule = $task.schedule
            scriptPath = $task.scriptPath
            termination = $task.termination
            environment = $task.environment
            notifications = $task.notifications
            tags = $task.tags
            custom = $task.custom
            overridden = $task.overridden
            isRunning = $null -ne $runningJob
            lastRun = $Global:PSWebServer.Tasks.LastRun[$task.name]
            failureCount = $Global:PSWebServer.Tasks.FailureCount[$task.name] ?? 0
        }
    }

    $response_data = @{
        success = $true
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        tasks = @($enrichedTasks)
        count = $enrichedTasks.Count
    }

    # Test mode
    if ($Test) {
        Write-Host "`n=== API Endpoint Test Results ===" -ForegroundColor Cyan
        Write-Host "Endpoint: GET /apps/WebHostTaskManagement/api/v1/tasks" -ForegroundColor White
        Write-Host "Status: 200 OK" -ForegroundColor Green
        Write-Host "`nResponse:" -ForegroundColor White
        $response_data | ConvertTo-Json -Depth 10 | Write-Host
        return
    }

    # Normal HTTP response
    $Response.StatusCode = 200
    $Response.ContentType = "application/json"
    $json = $response_data | ConvertTo-Json -Depth 10
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.Close()

} catch {
    Write-Error "$MyTag $_"

    $error_response = @{
        success = $false
        error = $_.Exception.Message
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }

    if ($Test) {
        Write-Host "`n=== API Endpoint Test Results ===" -ForegroundColor Cyan
        Write-Host "Status: 500 Internal Server Error" -ForegroundColor Red
        Write-Host "`nError:" -ForegroundColor Red
        $error_response | ConvertTo-Json -Depth 10 | Write-Host
        return
    }

    $Response.StatusCode = 500
    $Response.ContentType = "application/json"
    $json = $error_response | ConvertTo-Json -Depth 10
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.Close()
}
