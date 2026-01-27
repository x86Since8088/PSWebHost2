#Requires -Version 7

<#
.SYNOPSIS
    POST /apps/WebHostTaskManagement/api/v1/jobs/start

.DESCRIPTION
    Starts a job from the job catalog

.EXAMPLE
    POST /apps/WebHostTaskManagement/api/v1/jobs/start
    Body: {
        "jobId": "WebHostMetrics/CollectMetrics",
        "variables": { "Interval": "30" }
    }
#>

param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata,
    [switch]$Test,
    [string[]]$Roles = @(),
    [hashtable]$Query = @{},
    [hashtable]$Body = @{}
)

$MyTag = '[WebHostTaskManagement:API:Jobs:Start:Post]'

try {
    # Validate session
    if (-not $sessiondata.UserID) {
        throw "Unauthorized: No user ID in session"
    }

    # Get request body
    if ($Test -and $Body.Count -gt 0) {
        $requestData = $Body
    } else {
        $reader = [System.IO.StreamReader]::new($Request.InputStream)
        $bodyText = $reader.ReadToEnd()
        $reader.Close()

        if ([string]::IsNullOrWhiteSpace($bodyText)) {
            throw "Request body is required"
        }

        $requestData = $bodyText | ConvertFrom-Json
    }

    # Validate required fields
    if (-not $requestData.jobId) {
        throw "Field 'jobId' is required"
    }

    $jobId = $requestData.jobId
    $variables = if ($requestData.variables) {
        # Convert PSCustomObject to hashtable
        $varHash = @{}
        foreach ($prop in $requestData.variables.PSObject.Properties) {
            $varHash[$prop.Name] = $prop.Value
        }
        $varHash
    } else {
        @{}
    }

    # Get user roles
    $userRoles = $Roles
    if (-not $userRoles -or $userRoles.Count -eq 0) {
        $userRoles = @('authenticated')
    }

    # Import PSWebHost_Jobs module if not available
    if (-not (Get-Command Start-PSWebHostJob -ErrorAction SilentlyContinue)) {
        $modulePath = Join-Path $Global:PSWebServer.Project_Root.Path "modules\PSWebHost_Jobs\PSWebHost_Jobs.psd1"
        if (Test-Path $modulePath) {
            Import-Module $modulePath -DisableNameChecking -Force -ErrorAction Stop
        } else {
            throw "PSWebHost_Jobs module not found. Server may need restart."
        }
    }

    # Start the job
    try {
        $result = Start-PSWebHostJob `
            -JobID $jobId `
            -UserID $sessiondata.UserID `
            -SessionID $sessiondata.SessionID `
            -Variables $variables `
            -Roles $userRoles

        # Process command queue to actually start the job
        if (Get-Command Process-PSWebHostJobCommandQueue -ErrorAction SilentlyContinue) {
            $processed = Process-PSWebHostJobCommandQueue
            Write-Verbose "$MyTag Processed $processed command(s)"
        }

        $response_data = @{
            success = $true
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            message = "Job started successfully"
            jobId = $jobId
            executionId = $result.ExecutionID
            status = $result.Status
        }
    }
    catch {
        # Handle permission errors specially
        if ($_.Exception.Message -match "permission") {
            $Response.StatusCode = 403
            $response_data = @{
                success = $false
                error = "Access denied: You do not have permission to start this job"
                detail = $_.Exception.Message
                timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            }
        } else {
            throw
        }
    }

    # Test mode
    if ($Test) {
        Write-Host "`n=== API Endpoint Test Results ===" -ForegroundColor Cyan
        if ($response_data.success) {
            Write-Host "Status: 200 OK" -ForegroundColor Green
        } else {
            Write-Host "Status: $($Response.StatusCode)" -ForegroundColor Yellow
        }
        $response_data | ConvertTo-Json -Depth 10 | Write-Host
        return
    }

    # Normal HTTP response
    if (-not $Response.StatusCode -or $Response.StatusCode -eq 200) {
        $Response.StatusCode = 200
    }
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
        Write-Host "Status: 500 Internal Server Error" -ForegroundColor Red
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
