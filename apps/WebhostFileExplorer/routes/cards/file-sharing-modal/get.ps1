param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

try {
    # Return card metadata (JSON pattern)
    $cardInfo = @{
        component = 'file-sharing-modal'
        scriptPath = '/public/elements/file-sharing-modal/component.js'
        title = 'File Sharing Modal'
        description = 'Card component'
    }

    context_response -Response $Response -String ($cardInfo | ConvertTo-Json -Depth 10) -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'CardLoad' -Message "Error loading card: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}