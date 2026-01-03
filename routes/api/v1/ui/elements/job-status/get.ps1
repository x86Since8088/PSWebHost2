param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Helper function to create a JSON response
function New-JsonResponse($status, $message) {
    return @{ status = $status; Message = $message } | ConvertTo-Json
}

# Check authentication
if (-not $sessiondata -or -not $sessiondata.UserID) {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'User not authenticated'
    context_reponse -Response $Response -StatusCode 401 -String $jsonResponse -ContentType "application/json"
    return
}

try {
    # Get all background jobs
    $jobs = Get-Job | Select-Object Id, Name, State, HasMoreData, PSBeginTime, PSEndTime, @{
        Name = 'RunningTime'
        Expression = {
            if ($_.PSBeginTime) {
                if ($_.State -eq 'Running') {
                    ((Get-Date) - $_.PSBeginTime).ToString('hh\:mm\:ss')
                } else {
                    if ($_.PSEndTime) {
                        ($_.PSEndTime - $_.PSBeginTime).ToString('hh\:mm\:ss')
                    } else {
                        'N/A'
                    }
                }
            } else {
                'N/A'
            }
        }
    }

    $jobList = @()
    foreach ($job in $jobs) {
        $jobList += @{
            Id = $job.Id
            Name = $job.Name
            State = $job.State.ToString()
            HasMoreData = $job.HasMoreData
            StartTime = if ($job.PSBeginTime) { $job.PSBeginTime.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
            EndTime = if ($job.PSEndTime) { $job.PSEndTime.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
            RunningTime = $job.RunningTime
        }
    }

    # Convert to JSON
    $jsonData = $jobList | ConvertTo-Json -Depth 5 -Compress
    if ($jsonData -in @('null', '')) {
        $jsonData = '[]'
    }

    context_reponse -Response $Response -StatusCode 200 -String $jsonData -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'JobStatus' -Message "Error retrieving job status: $($_.Exception.Message)"

    # Generate detailed error report based on user role
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata

    context_reponse -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
