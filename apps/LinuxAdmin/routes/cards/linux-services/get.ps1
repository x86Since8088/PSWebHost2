# PLACEHOLDER - Component not implemented yet
# See: C:\SC\PsWebHost\apps\LinuxAdmin\DUPLICATION_ISSUE.md
# This functionality already exists in WindowsAdmin and needs to be extracted to a shared module first

param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

try {
    # Return error indicating this component is not yet implemented
    $errorInfo = @{
        error = 'Not Implemented'
        message = 'Linux Services component is pending implementation. See DUPLICATION_ISSUE.md for details.'
        status = 'placeholder'
        recommendedAction = 'Use WindowsAdmin app for cross-platform service management until LinuxAdmin is fully implemented.'
    }

    context_response -Response $Response -StatusCode 501 -String ($errorInfo | ConvertTo-Json -Depth 10) -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'CardLoad' -Message "Error loading card: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}

# ORIGINAL CODE (commented out):
# try {
#     # Return card metadata (JSON pattern)
#     $cardInfo = @{
#         component = 'linux-services'
#         scriptPath = '/public/elements/linux-services/component.js'
#         title = 'Linux Services'
#         description = 'Card component'
#     }
#
#     context_response -Response $Response -String ($cardInfo | ConvertTo-Json -Depth 10) -ContentType "application/json"
#
# } catch {
#     Write-PSWebHostLog -Severity 'Error' -Category 'CardLoad' -Message "Error loading card: $($_.Exception.Message)"
#     $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
#     context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
# }