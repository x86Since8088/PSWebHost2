param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    $cardInfo = @{
        component = 'file-explorer'
        scriptPath = '/apps/WebhostFileExplorer/public/elements/file-explorer/component.js'
        title = 'File Explorer'
        description = 'User file management and exploration interface for PSWebHost'
        version = '1.0.0'
        width = 12
        height = 600
        features = @(
            'User-scoped file storage and organization'
            'Hierarchical folder structure browsing'
            'File upload and download'
            'Folder creation and management'
            'File and folder renaming'
            'File and folder deletion'
            'Recursive directory tree view'
            'File metadata (size, modified date)'
            'Auto-refresh capability'
        )
    }

    context_response -Response $Response -String ($cardInfo | ConvertTo-Json -Depth 10) -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Error loading file-explorer UI endpoint: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
