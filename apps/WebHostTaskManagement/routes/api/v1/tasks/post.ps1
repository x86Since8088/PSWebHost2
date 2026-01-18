#Requires -Version 7

<#
.SYNOPSIS
    POST /apps/WebHostTaskManagement/api/v1/tasks

.DESCRIPTION
    Updates task configuration (enable/disable, schedule changes, etc.)

.PARAMETER Context
    HttpListenerContext object
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

$MyTag = '[WebHostTaskManagement:API:Tasks:Post]'

try {
    # Read request body
    if ($Test) {
        $body = $Query.body
    } else {
        $reader = New-Object System.IO.StreamReader($Request.InputStream)
        $body = $reader.ReadToEnd()
        $reader.Close()
    }

    $data = $body | ConvertFrom-Json

    # Validate required fields
    if (-not $data.taskName) {
        throw "Missing required field: taskName"
    }

    # Load runtime config
    $runtimeConfigFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\config\tasks.json"

    if (Test-Path $runtimeConfigFile) {
        $runtimeConfig = Get-Content $runtimeConfigFile -Raw | ConvertFrom-Json
    } else {
        $runtimeConfig = @{
            version = "1.0"
            lastModified = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            tasks = @()
        }
    }

    # Find or create task override
    $existingTask = $runtimeConfig.tasks | Where-Object { $_.name -eq $data.taskName -and $_.appName -eq $data.appName }

    if ($existingTask) {
        # Update existing override
        if ($null -ne $data.enabled) { $existingTask.enabled = $data.enabled }
        if ($data.schedule) { $existingTask.schedule = $data.schedule }
        if ($data.environment) { $existingTask.environment = $data.environment }
        if ($null -ne $data.deleted) { $existingTask.deleted = $data.deleted }

        $message = "Task '$($data.taskName)' configuration updated"
    } else {
        # Create new override
        $newOverride = @{
            name = $data.taskName
            appName = $data.appName
            enabled = $data.enabled ?? $true
        }

        if ($data.schedule) { $newOverride.schedule = $data.schedule }
        if ($data.environment) { $newOverride.environment = $data.environment }
        if ($data.scriptPath) {
            $newOverride.scriptPath = $data.scriptPath
            $newOverride.custom = $true
        }

        $runtimeConfig.tasks += $newOverride
        $message = "Task '$($data.taskName)' override created"
    }

    # Update lastModified
    $runtimeConfig.lastModified = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")

    # Save runtime config
    $configDir = Split-Path $runtimeConfigFile -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }

    $runtimeConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $runtimeConfigFile

    $response_data = @{
        success = $true
        message = $message
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }

    # Test mode
    if ($Test) {
        Write-Host "`n=== API Endpoint Test Results ===" -ForegroundColor Cyan
        Write-Host "Status: 200 OK" -ForegroundColor Green
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
        Write-Host "Status: 400 Bad Request" -ForegroundColor Red
        $error_response | ConvertTo-Json -Depth 10 | Write-Host
        return
    }

    $Response.StatusCode = 400
    $Response.ContentType = "application/json"
    $json = $error_response | ConvertTo-Json -Depth 10
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.Close()
}
