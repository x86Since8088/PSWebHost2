param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata,
    [switch]$Test,
    [string[]]$Roles = @()
)

# Memory Histogram UI Element
# Returns element configuration for memory usage histogram

# Handle test mode
if ($Test) {
    # Read and display security configuration
    $securityFile = Join-Path $PSScriptRoot "get.security.json"
    if (Test-Path $securityFile) {
        $securityConfig = Get-Content $securityFile -Raw | ConvertFrom-Json
        Write-Host "`n=== Security Configuration ===" -ForegroundColor Cyan
        Write-Host "Allowed Roles: $($securityConfig.Allowed_Roles -join ', ')" -ForegroundColor Yellow
        Write-Host "================================`n" -ForegroundColor Cyan
    }

    # Create mock sessiondata
    if ($Roles.Count -eq 0) {
        $Roles = @('authenticated')
    }
    else {
        # Ensure 'authenticated' is always included when roles are specified
        if ('authenticated' -notin $Roles) {
            $Roles = @('authenticated') + $Roles
        }
    }
    $sessiondata = @{
        Roles = $Roles
        UserID = 'test-user'
        SessionID = 'test-session'
    }
}

$elementConfig = @{
    status = 'success'
    scriptPath = '/apps/WebHostMetrics/public/elements/memory-histogram/component.js'
    element = @{
        id = 'memory-histogram'
        type = 'component'
        component = 'memory-histogram'
        title = 'Memory Usage History'
        icon = $null
        refreshable = $true
        helpFile = 'public/help/memory-histogram.md'
    }
}

$jsonResponse = $elementConfig | ConvertTo-Json -Depth 10

# Test mode output
if ($Test) {
    Write-Host "`n=== API Endpoint Test Results ===" -ForegroundColor Cyan
    Write-Host "Status: 200 OK" -ForegroundColor Green
    Write-Host "Content-Type: application/json" -ForegroundColor Gray
    Write-Host "`nResponse Data:" -ForegroundColor Cyan
    $elementConfig | ConvertTo-Json -Depth 10 | Write-Host
    Write-Host "`n=== End Test Results ===" -ForegroundColor Cyan
    return
}

context_response -Response $Response -String $jsonResponse -ContentType "application/json"
