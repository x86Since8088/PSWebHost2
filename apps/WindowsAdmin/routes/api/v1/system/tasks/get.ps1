param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Task Scheduler API Endpoint
# Returns list of scheduled tasks (Windows Task Scheduler or Linux Cron)

try {
    $result = @{
        platform = $null
        tasks = @()
    }

    if ($IsWindows -or $env:OS -match 'Windows') {
        $result.platform = 'Windows'

        # Get scheduled tasks using COM
        try {
            $scheduler = New-Object -ComObject Schedule.Service
            $scheduler.Connect()
            $rootFolder = $scheduler.GetFolder('\')

            function Get-TasksRecursive {
                param($folder, $depth = 0)
                if ($depth -gt 2) { return }

                $tasks = @()
                foreach ($task in $folder.GetTasks(0)) {
                    $def = $task.Definition
                    $lastRun = if ($task.LastRunTime -and $task.LastRunTime.Year -gt 1899) {
                        $task.LastRunTime.ToString('yyyy-MM-dd HH:mm:ss')
                    } else { 'Never' }
                    $nextRun = if ($task.NextRunTime -and $task.NextRunTime.Year -gt 1899) {
                        $task.NextRunTime.ToString('yyyy-MM-dd HH:mm:ss')
                    } else { 'N/A' }

                    $tasks += @{
                        name = $task.Name
                        path = $task.Path
                        enabled = $task.Enabled
                        state = switch ($task.State) {
                            0 { 'Unknown' }
                            1 { 'Disabled' }
                            2 { 'Queued' }
                            3 { 'Ready' }
                            4 { 'Running' }
                        }
                        lastRun = $lastRun
                        nextRun = $nextRun
                        lastResult = $task.LastTaskResult
                    }
                }

                foreach ($subFolder in $folder.GetFolders(0)) {
                    $tasks += Get-TasksRecursive -folder $subFolder -depth ($depth + 1)
                }

                return $tasks
            }

            $result.tasks = @(Get-TasksRecursive -folder $rootFolder | Select-Object -First 50)
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($scheduler) | Out-Null
        }
        catch {
            $result.error = "Failed to enumerate tasks: $($_.Exception.Message)"
        }
    }
    elseif ($IsLinux) {
        $result.platform = 'Linux'

        # Get cron jobs for current user
        try {
            $cronOutput = & crontab -l 2>/dev/null
            if ($LASTEXITCODE -eq 0 -and $cronOutput) {
                $lines = $cronOutput -split "`n" | Where-Object { $_ -and $_ -notmatch '^#' }
                foreach ($line in $lines) {
                    if ($line -match '^([^\s]+\s+[^\s]+\s+[^\s]+\s+[^\s]+\s+[^\s]+)\s+(.+)$') {
                        $result.tasks += @{
                            name = $matches[2].Substring(0, [Math]::Min(50, $matches[2].Length))
                            schedule = $matches[1]
                            command = $matches[2]
                            enabled = $true
                            state = 'Scheduled'
                        }
                    }
                }
            }

            # Also check system cron
            $systemCron = Get-ChildItem /etc/cron.d/ -ErrorAction SilentlyContinue
            foreach ($file in $systemCron) {
                $result.tasks += @{
                    name = $file.Name
                    path = $file.FullName
                    enabled = $true
                    state = 'System'
                }
            }
        }
        catch {
            $result.error = "Failed to read cron: $($_.Exception.Message)"
        }
    }
    else {
        $result.platform = 'Unknown'
        $result.message = 'Task scheduling not supported on this platform'
    }

    $jsonResponse = $result | ConvertTo-Json -Depth 5
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'TaskScheduler' -Message "Error getting scheduled tasks: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
