param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# System Services API Endpoint
# Returns list of services with status (Windows Services or Linux systemd)

try {
    $result = @{
        platform = $null
        services = @()
    }

    if ($IsWindows -or $env:OS -match 'Windows') {
        $result.platform = 'Windows'

        # Get Windows services - focus on common important services
        $importantServices = @(
            'wuauserv',      # Windows Update
            'BITS',          # Background Intelligent Transfer
            'Spooler',       # Print Spooler
            'W32Time',       # Windows Time
            'EventLog',      # Event Log
            'WinRM',         # Windows Remote Management
            'LanmanServer',  # File/Print Sharing
            'LanmanWorkstation', # Workstation
            'Dhcp',          # DHCP Client
            'Dnscache',      # DNS Client
            'TermService',   # Remote Desktop
            'MpsSvc'         # Windows Firewall
        )

        $services = Get-Service -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -in $importantServices -or $_.Status -eq 'Running'
        } | Select-Object -First 50

        foreach ($svc in $services) {
            $result.services += @{
                name = $svc.Name
                displayName = $svc.DisplayName
                status = $svc.Status.ToString()
                startType = $svc.StartType.ToString()
                canStop = $svc.CanStop
                canPause = $svc.CanPauseAndContinue
            }
        }
    }
    elseif ($IsLinux) {
        $result.platform = 'Linux'

        # Get systemd services
        $systemctlOutput = & systemctl list-units --type=service --all --no-pager --plain 2>/dev/null
        if ($LASTEXITCODE -eq 0 -and $systemctlOutput) {
            $lines = $systemctlOutput -split "`n" | Where-Object { $_ -match '\.service' }
            foreach ($line in $lines | Select-Object -First 50) {
                $parts = $line -split '\s+', 5
                if ($parts.Count -ge 4) {
                    $result.services += @{
                        name = $parts[0] -replace '\.service$', ''
                        displayName = $parts[0]
                        status = $parts[3]
                        load = $parts[1]
                        active = $parts[2]
                        description = if ($parts.Count -ge 5) { $parts[4] } else { '' }
                    }
                }
            }
        }
    }
    else {
        $result.platform = 'Unknown'
        $result.message = 'Service management not supported on this platform'
    }

    $jsonResponse = $result | ConvertTo-Json -Depth 5
    context_reponse -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'ServiceControl' -Message "Error getting service status: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_reponse -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
