param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

try {
    # Return card metadata (JSON pattern)
    # Updated to use kubernetesmanager-home component (kubernetes-status component doesn't exist)
    $cardInfo = @{
        component = 'kubernetesmanager-home'
        scriptPath = '/public/elements/kubernetesmanager-home/component.js'
        title = 'Kubernetes Manager'
        description = 'Kubernetes cluster monitoring and management'
    }

    context_response -Response $Response -String ($cardInfo | ConvertTo-Json -Depth 10) -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'CardLoad' -Message "Error loading card: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}