param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

try {
    # Return card metadata for apps-manager component
    $cardInfo = @{
        component = 'apps-manager'
        scriptPath = '/public/elements/apps-manager/component.js'
        title = 'Apps Manager'
        description = 'Manage installed PSWebHost applications'
        version = '1.0.0'
        width = 12
        height = 600
        features = @(
            'View all installed apps'
            'Check app status and versions'
            'Manage app configurations'
            'View app metadata and requirements'
        )
    }

    context_response -Response $Response -String ($cardInfo | ConvertTo-Json -Depth 10) -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'AppsManager' -Message "Error loading apps-manager card: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
