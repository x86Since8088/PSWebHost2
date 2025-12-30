param(
    [int]$TailLines = 50,
    [int]$RefreshSeconds = 3
)

$logDir = 'C:\sc\PsWebHost\PsWebHost_Data\Logs'
$currentFile = $null
$lastCheck = Get-Date
$seenMessages = @{}
$startTime = Get-Date

Write-Host "Starting log tail (showing unique messages only)..."
Write-Host "Start time: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "Refresh interval: $RefreshSeconds seconds"
Write-Host "========================================`n"

while ($true) {
    # Check for the newest log file every 5 seconds
    if (((Get-Date) - $lastCheck).TotalSeconds -ge 5) {
        $newestFile = Get-ChildItem -Path $logDir -Filter 'log*.tsv' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if ($newestFile -and ($null -eq $currentFile -or $newestFile.FullName -ne $currentFile.FullName)) {
            Write-Host "`n========================================"
            Write-Host "Switching to log file: $($newestFile.Name)"
            Write-Host "Last modified: $($newestFile.LastWriteTime)"
            Write-Host "========================================`n"
            $currentFile = $newestFile
            # Clear seen messages when switching files
            $seenMessages.Clear()
        }
        $lastCheck = Get-Date
    }

    if ($currentFile -and (Test-Path $currentFile.FullName)) {
        # Read recent log entries
        $lines = Get-Content -Path $currentFile.FullName -Tail $TailLines -ErrorAction SilentlyContinue

        if ($lines) {
            foreach ($line in $lines) {
                # Parse TSV format: Timestamp, DateTimeOffset, Severity, Category, Message
                $fields = $line -split "`t"
                if ($fields.Count -ge 5) {
                    $timestamp = $fields[0]
                    $severity = $fields[2]
                    $category = $fields[3]
                    $message = $fields[4]

                    # Try to parse timestamp
                    $logTime = $null
                    try {
                        $logTime = [DateTime]::Parse($timestamp)
                    } catch {
                        # If parsing fails, skip this line
                        continue
                    }

                    # Only show messages from after start time
                    if ($logTime -gt $startTime) {
                        # Create a unique key for this message
                        $messageKey = "$severity|$category|$message"

                        # Only display if we haven't seen this message before
                        if (-not $seenMessages.ContainsKey($messageKey)) {
                            $seenMessages[$messageKey] = $logTime

                            # Color code by severity
                            $color = switch ($severity) {
                                'Error' { 'Red' }
                                'Warning' { 'Yellow' }
                                'Info' { 'Cyan' }
                                'Verbose' { 'Gray' }
                                default { 'White' }
                            }

                            Write-Host "[$($logTime.ToString('HH:mm:ss'))] " -NoNewline
                            Write-Host "[$severity] " -ForegroundColor $color -NoNewline
                            Write-Host "[$category] " -NoNewline -ForegroundColor DarkGray
                            Write-Host $message
                        }
                    }
                }
            }
        }
    }

    Start-Sleep -Seconds $RefreshSeconds
}
