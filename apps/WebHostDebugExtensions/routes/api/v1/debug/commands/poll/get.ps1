#Requires -Version 7

param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

$MyTag = '[DebugExtensions:Commands:Poll]'

try {
    # Get current session ID
    $currentSessionID = $sessiondata.SessionID

    # Outbox root
    $outboxRoot = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\apps\WebHostDebugExtensions\outbox"

    if (-not (Test-Path $outboxRoot)) {
        # No outbox, return 204 No Content
        context_response -Response $Response -StatusCode 204 -String "" -ContentType "text/plain"
        return
    }

    # Check session-specific outbox and "all" outbox
    $sessionOutbox = Join-Path $outboxRoot $currentSessionID
    $allOutbox = Join-Path $outboxRoot "all"

    $pendingCommands = @()
    $now = Get-Date

    # Helper function to process outbox folder
    function Get-CommandsFromOutbox {
        param([string]$OutboxPath)

        if (-not (Test-Path $OutboxPath)) {
            return @()
        }

        $commands = @()
        $files = Get-ChildItem -Path $OutboxPath -Filter "*.json" -ErrorAction SilentlyContinue

        foreach ($file in $files) {
            try {
                # Read command file
                $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
                $cmd = $content | ConvertFrom-Json

                # Check if expired
                if ($cmd.TimeoutAt) {
                    $timeoutDate = [DateTime]::Parse($cmd.TimeoutAt)
                    if ($timeoutDate -le $now) {
                        # Expired - delete file
                        Write-Verbose "$MyTag Deleting expired command: $($cmd.CommandID)"
                        Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
                        continue
                    }
                }

                # Mark as executing - add properties using Add-Member for PSCustomObject
                $cmd | Add-Member -MemberType NoteProperty -Name 'Status' -Value 'executing' -Force
                $cmd | Add-Member -MemberType NoteProperty -Name 'ExecutedAt' -Value $now.ToString('o') -Force

                $commands += $cmd

                # Delete from outbox (browser has received it)
                Write-Verbose "$MyTag Delivering command $($cmd.CommandID) to session $currentSessionID"
                Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue

            } catch {
                Write-Warning "$MyTag Error processing command file $($file.Name): $_"
            }
        }

        return $commands
    }

    # Get commands from session-specific outbox
    $pendingCommands += Get-CommandsFromOutbox -OutboxPath $sessionOutbox

    # Get commands from "all" outbox
    $pendingCommands += Get-CommandsFromOutbox -OutboxPath $allOutbox

    # Return commands or 204 No Content
    if ($pendingCommands.Count -gt 0) {
        $responseData = @{
            commands = $pendingCommands
        } | ConvertTo-Json -Depth 5 -Compress

        context_response -Response $Response -StatusCode 200 -String $responseData -ContentType "application/json"
    } else {
        context_response -Response $Response -StatusCode 204 -String "" -ContentType "text/plain"
    }

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'DebugExtensions' -Message "$MyTag Error: $($_.Exception.Message)"

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
