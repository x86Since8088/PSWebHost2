<#
.SYNOPSIS
    Closes cards in the browser via the debug command queue

.DESCRIPTION
    Enqueues a closeCard command to close cards by ID, element type, or all cards.
    Supports session-specific targeting.

.PARAMETER CardID
    Specific card ID to close (e.g., "file-explorer-123456")

.PARAMETER ElementID
    Element type to close all instances of (e.g., "file-explorer")

.PARAMETER All
    Close all cards in the target session

.PARAMETER SessionID
    Target session ID. Defaults to "all" to target all sessions.

.PARAMETER Wait
    If specified, waits for command to complete and returns result

.PARAMETER TimeoutSeconds
    Maximum time to wait for command completion (default: 5 seconds)

.EXAMPLE
    Close-DebugCard -CardID "file-explorer-123456"

.EXAMPLE
    Close-DebugCard -ElementID "file-explorer" -Wait

.EXAMPLE
    Close-DebugCard -All -SessionID "abc123"

.OUTPUTS
    Returns command ID when launched, or result object if -Wait is specified
#>
[CmdletBinding(DefaultParameterSetName = 'CardID')]
param(
        [Parameter(Mandatory = $true, ParameterSetName = 'CardID')]
        [ValidateNotNullOrEmpty()]
        [string]$CardID,

        [Parameter(Mandatory = $true, ParameterSetName = 'ElementID')]
        [ValidateNotNullOrEmpty()]
        [string]$ElementID,

        [Parameter(Mandatory = $true, ParameterSetName = 'All')]
        [switch]$All,

        [Parameter(Mandatory = $false)]
        [string]$SessionID = "all",

        [Parameter(Mandatory = $false)]
        [switch]$Wait,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 5
    )

    $MyTag = '[Close-DebugCard]'

    try {
        # Build parameters based on parameter set
        $commandParams = @{}

        switch ($PSCmdlet.ParameterSetName) {
            'CardID' {
                $commandParams.cardId = $CardID
                Write-Verbose "$MyTag Closing card: $CardID"
            }
            'ElementID' {
                $commandParams.elementId = $ElementID
                Write-Verbose "$MyTag Closing all cards of type: $ElementID"
            }
            'All' {
                $commandParams.all = $true
                Write-Verbose "$MyTag Closing all cards"
            }
        }

        # Enqueue the command
        $enqueueScript = Join-Path $PSScriptRoot "Debug_Client_Command_Enqueue.ps1"
        $result = & $enqueueScript `
            -Command "closeCard" `
            -Type predefined `
            -Params $commandParams `
            -SessionID $SessionID

        if (-not $result.Success) {
            throw "Failed to enqueue command: $($result.Message)"
        }

        $commandId = $result.CommandID
        Write-Verbose "$MyTag Command enqueued: $commandId"

        if ($Wait) {
            Write-Verbose "$MyTag Waiting for command completion (timeout: ${TimeoutSeconds}s)..."

            $startTime = Get-Date
            $completed = $false
            $commandResult = $null

            while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
                Start-Sleep -Milliseconds 500

                # Poll history endpoint via HTTP
                try {
                    $historyResponse = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=100" -Method GET

                    $historyEntry = $historyResponse.commands | Where-Object { $_.CommandID -eq $commandId } | Select-Object -First 1

                    if ($historyEntry) {
                        $completed = $true
                        $commandResult = $historyEntry
                        break
                    }
                } catch {
                    Write-Verbose "$MyTag Error polling history: $_"
                }
            }

            if (-not $completed) {
                Write-Warning "$MyTag Command did not complete within ${TimeoutSeconds}s"
                return @{
                    Success = $false
                    CommandID = $commandId
                    Message = "Timeout waiting for command completion"
                }
            }

            Write-Verbose "$MyTag Command completed successfully"
            return @{
                Success = $true
                CommandID = $commandId
                Result = $commandResult.Result
                ClosedCards = $commandResult.Result.closedCards
                Count = $commandResult.Result.count
                Timestamp = $commandResult.CompletedTime
            }

        } else {
            # Return immediately with command ID
            return @{
                Success = $true
                CommandID = $commandId
                SessionID = $SessionID
                ParameterSet = $PSCmdlet.ParameterSetName
            }
        }

} catch {
    Write-Error "$MyTag Error closing card: $_"
    return @{
        Success = $false
        Error = $_.Exception.Message
    }
}
