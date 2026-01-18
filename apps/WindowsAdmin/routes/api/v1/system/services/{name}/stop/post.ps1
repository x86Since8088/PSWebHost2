param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Stop Service Endpoint
# Stops a Windows service or Linux systemd service

try {
    # Extract service name from URL path
    $pathParts = $Request.Url.AbsolutePath -split '/'
    $serviceName = $pathParts[-2] # {name} is second from end before 'stop'

    if ([string]::IsNullOrWhiteSpace($serviceName)) {
        $errorResult = @{
            success = $false
            error = 'Service name is required'
        } | ConvertTo-Json
        context_response -Response $Response -StatusCode 400 -String $errorResult -ContentType "application/json"
        return
    }

    $result = @{
        success = $false
        serviceName = $serviceName
        platform = $null
        message = $null
        error = $null
    }

    if ($IsWindows -or $env:OS -match 'Windows') {
        $result.platform = 'Windows'

        # Check if service exists
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if (-not $service) {
            $result.error = "Service '$serviceName' not found"
            $jsonResponse = $result | ConvertTo-Json
            context_response -Response $Response -StatusCode 404 -String $jsonResponse -ContentType "application/json"
            return
        }

        # Check if service can be stopped
        if (-not $service.CanStop) {
            $result.error = "Service '$($service.DisplayName)' cannot be stopped"
            $result.message = "Service cannot be stopped (system critical service)"
            $jsonResponse = $result | ConvertTo-Json
            context_response -Response $Response -StatusCode 403 -String $jsonResponse -ContentType "application/json"
            return
        }

        # Check current status
        if ($service.Status -eq 'Stopped') {
            $result.success = $true
            $result.message = "Service '$($service.DisplayName)' is already stopped"
            $result.status = 'Stopped'
        }
        else {
            # Try to stop the service
            try {
                Stop-Service -Name $serviceName -Force -ErrorAction Stop
                $result.success = $true
                $result.message = "Service '$($service.DisplayName)' stopped successfully"
                $result.status = 'Stopped'
                Write-PSWebHostLog -Severity 'Info' -Category 'ServiceControl' -Message "Service stopped: $serviceName by $($sessiondata.User.Username)"
            }
            catch {
                $result.error = $_.Exception.Message
                $result.message = "Failed to stop service: $($_.Exception.Message)"
                Write-PSWebHostLog -Severity 'Error' -Category 'ServiceControl' -Message "Failed to stop service $serviceName : $($_.Exception.Message)"
            }
        }
    }
    elseif ($IsLinux) {
        $result.platform = 'Linux'

        # Try to stop with systemctl
        try {
            $output = & systemctl stop "$serviceName.service" 2>&1
            if ($LASTEXITCODE -eq 0) {
                $result.success = $true
                $result.message = "Service '$serviceName' stopped successfully"
                $result.status = 'inactive'
                Write-PSWebHostLog -Severity 'Info' -Category 'ServiceControl' -Message "Service stopped: $serviceName by $($sessiondata.User.Username)"
            }
            else {
                $result.error = $output -join ' '
                $result.message = "Failed to stop service: $($output -join ' ')"
                Write-PSWebHostLog -Severity 'Error' -Category 'ServiceControl' -Message "Failed to stop service $serviceName : $($output -join ' ')"
            }
        }
        catch {
            $result.error = $_.Exception.Message
            $result.message = "Failed to stop service: $($_.Exception.Message)"
        }
    }
    else {
        $result.platform = 'Unknown'
        $result.error = 'Service control not supported on this platform'
    }

    $statusCode = if ($result.success) { 200 } else { 500 }
    $jsonResponse = $result | ConvertTo-Json -Depth 3
    context_response -Response $Response -StatusCode $statusCode -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'ServiceControl' -Message "Error stopping service: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
