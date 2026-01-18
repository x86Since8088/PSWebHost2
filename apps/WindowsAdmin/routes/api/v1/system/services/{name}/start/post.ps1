param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Start Service Endpoint
# Starts a Windows service or Linux systemd service

try {
    # Extract service name from URL path
    $pathParts = $Request.Url.AbsolutePath -split '/'
    $serviceName = $pathParts[-2] # {name} is second from end before 'start'

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

        # Check current status
        if ($service.Status -eq 'Running') {
            $result.success = $true
            $result.message = "Service '$($service.DisplayName)' is already running"
            $result.status = 'Running'
        }
        else {
            # Try to start the service
            try {
                Start-Service -Name $serviceName -ErrorAction Stop
                $result.success = $true
                $result.message = "Service '$($service.DisplayName)' started successfully"
                $result.status = 'Running'
                Write-PSWebHostLog -Severity 'Info' -Category 'ServiceControl' -Message "Service started: $serviceName by $($sessiondata.User.Username)"
            }
            catch {
                $result.error = $_.Exception.Message
                $result.message = "Failed to start service: $($_.Exception.Message)"
                Write-PSWebHostLog -Severity 'Error' -Category 'ServiceControl' -Message "Failed to start service $serviceName : $($_.Exception.Message)"
            }
        }
    }
    elseif ($IsLinux) {
        $result.platform = 'Linux'

        # Try to start with systemctl
        try {
            $output = & systemctl start "$serviceName.service" 2>&1
            if ($LASTEXITCODE -eq 0) {
                $result.success = $true
                $result.message = "Service '$serviceName' started successfully"
                $result.status = 'active'
                Write-PSWebHostLog -Severity 'Info' -Category 'ServiceControl' -Message "Service started: $serviceName by $($sessiondata.User.Username)"
            }
            else {
                $result.error = $output -join ' '
                $result.message = "Failed to start service: $($output -join ' ')"
                Write-PSWebHostLog -Severity 'Error' -Category 'ServiceControl' -Message "Failed to start service $serviceName : $($output -join ' ')"
            }
        }
        catch {
            $result.error = $_.Exception.Message
            $result.message = "Failed to start service: $($_.Exception.Message)"
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
    Write-PSWebHostLog -Severity 'Error' -Category 'ServiceControl' -Message "Error starting service: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
