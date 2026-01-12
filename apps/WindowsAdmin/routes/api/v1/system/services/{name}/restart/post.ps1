param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Restart Service Endpoint
# Restarts a Windows service or Linux systemd service

try {
    # Extract service name from URL path
    $pathParts = $Request.Url.AbsolutePath -split '/'
    $serviceName = $pathParts[-2] # {name} is second from end before 'restart'

    if ([string]::IsNullOrWhiteSpace($serviceName)) {
        $errorResult = @{
            success = $false
            error = 'Service name is required'
        } | ConvertTo-Json
        context_reponse -Response $Response -StatusCode 400 -String $errorResult -ContentType "application/json"
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
            context_reponse -Response $Response -StatusCode 404 -String $jsonResponse -ContentType "application/json"
            return
        }

        # Check if service can be stopped (needed for restart)
        if ($service.Status -eq 'Running' -and -not $service.CanStop) {
            $result.error = "Service '$($service.DisplayName)' cannot be stopped"
            $result.message = "Service cannot be restarted (system critical service)"
            $jsonResponse = $result | ConvertTo-Json
            context_reponse -Response $Response -StatusCode 403 -String $jsonResponse -ContentType "application/json"
            return
        }

        # Try to restart the service
        try {
            if ($service.Status -eq 'Stopped') {
                # If stopped, just start it
                Start-Service -Name $serviceName -ErrorAction Stop
                $result.message = "Service '$($service.DisplayName)' was stopped, now started"
            }
            else {
                # If running, restart it
                Restart-Service -Name $serviceName -Force -ErrorAction Stop
                $result.message = "Service '$($service.DisplayName)' restarted successfully"
            }
            $result.success = $true
            $result.status = 'Running'
            Write-PSWebHostLog -Severity 'Info' -Category 'ServiceControl' -Message "Service restarted: $serviceName by $($sessiondata.User.Username)"
        }
        catch {
            $result.error = $_.Exception.Message
            $result.message = "Failed to restart service: $($_.Exception.Message)"
            Write-PSWebHostLog -Severity 'Error' -Category 'ServiceControl' -Message "Failed to restart service $serviceName : $($_.Exception.Message)"
        }
    }
    elseif ($IsLinux) {
        $result.platform = 'Linux'

        # Try to restart with systemctl
        try {
            $output = & systemctl restart "$serviceName.service" 2>&1
            if ($LASTEXITCODE -eq 0) {
                $result.success = $true
                $result.message = "Service '$serviceName' restarted successfully"
                $result.status = 'active'
                Write-PSWebHostLog -Severity 'Info' -Category 'ServiceControl' -Message "Service restarted: $serviceName by $($sessiondata.User.Username)"
            }
            else {
                $result.error = $output -join ' '
                $result.message = "Failed to restart service: $($output -join ' ')"
                Write-PSWebHostLog -Severity 'Error' -Category 'ServiceControl' -Message "Failed to restart service $serviceName : $($output -join ' ')"
            }
        }
        catch {
            $result.error = $_.Exception.Message
            $result.message = "Failed to restart service: $($_.Exception.Message)"
        }
    }
    else {
        $result.platform = 'Unknown'
        $result.error = 'Service control not supported on this platform'
    }

    $statusCode = if ($result.success) { 200 } else { 500 }
    $jsonResponse = $result | ConvertTo-Json -Depth 3
    context_reponse -Response $Response -StatusCode $statusCode -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'ServiceControl' -Message "Error restarting service: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_reponse -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
