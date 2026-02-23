# Get Groups Endpoint
# Returns list of groups for file sharing permissions

param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    $groups = @()

    if ($IsWindows) {
        # Get Windows local groups
        try {
            $localGroups = Get-LocalGroup -ErrorAction SilentlyContinue
            if ($localGroups) {
                $groups = $localGroups | ForEach-Object {
                    @{
                        name = $_.Name
                        description = $_.Description
                        sid = $_.SID.Value
                        type = 'local'
                    }
                }
            }
        } catch {
            Write-PSWebHostLog -Message "Failed to get local groups: $($_.Exception.Message)" -Level 'Warning' -Facility 'FileExplorer'
        }

        # Optionally add domain groups (if needed)
        # This would require additional logic to query Active Directory

    } elseif ($IsLinux -or $IsMacOS) {
        # Get Unix/Linux groups from /etc/group
        try {
            if (Test-Path '/etc/group') {
                $groupFile = Get-Content '/etc/group' -ErrorAction SilentlyContinue
                $groups = $groupFile | ForEach-Object {
                    $parts = $_ -split ':'
                    if ($parts.Count -ge 3) {
                        @{
                            name = $parts[0]
                            gid = $parts[2]
                            description = "Group ID: $($parts[2])"
                            type = 'unix'
                        }
                    }
                } | Where-Object { $_ }
            }
        } catch {
            Write-PSWebHostLog -Message "Failed to read /etc/group: $($_.Exception.Message)" -Level 'Warning' -Facility 'FileExplorer'
        }
    }

    # Add special "Everyone" group
    $groups = @(@{
        name = 'Everyone'
        description = 'All authenticated users'
        type = 'special'
    }) + $groups

    # Return response
    $response = @{
        success = $true
        count = $groups.Count
        groups = $groups
        platform = if ($IsWindows) { 'windows' } elseif ($IsLinux) { 'linux' } elseif ($IsMacOS) { 'macos' } else { 'unknown' }
    }

    $jsonResponse = $response | ConvertTo-Json -Depth 5 -Compress
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType 'application/json'

} catch {
    Write-PSWebHostLog -Message "Error in groups GET endpoint: $($_.Exception.Message)" -Level 'Error' -Facility 'FileExplorer'

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
