<#
.SYNOPSIS
    Gets list of currently open cards in the browser

.DESCRIPTION
    Queries the browser for all currently open cards using the listCards predefined command.
    Returns card metadata including card IDs, element types, and URLs.

.PARAMETER SessionID
    Target session ID. Defaults to "all" to query all sessions.

.PARAMETER ElementID
    Optional filter to return only cards of specific element type

.PARAMETER TimeoutSeconds
    Maximum time to wait for command completion (default: 5 seconds)

.EXAMPLE
    Get-DebugOpenCards

.EXAMPLE
    Get-DebugOpenCards -ElementID "file-explorer"

.EXAMPLE
    Get-DebugOpenCards -SessionID "abc123"

.OUTPUTS
    Returns array of card objects with cardId, elementId, and url properties
#>
[CmdletBinding()]
param(
        [Parameter(Mandatory = $false)]
        [string]$SessionID = "all",

        [Parameter(Mandatory = $false)]
        [string]$ElementID,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 5
    )

    $MyTag = '[Get-DebugOpenCards]'

    try {
        Write-Verbose "$MyTag Querying open cards (Session: $SessionID)"

        # Enqueue the listCards command
        $enqueueScript = Join-Path $PSScriptRoot "Debug_Client_Command_Enqueue.ps1"
        $result = & $enqueueScript `
            -Command "listCards" `
            -Type predefined `
            -SessionID $SessionID

        if (-not $result.Success) {
            throw "Failed to enqueue command: $($result.Message)"
        }

        $commandId = $result.CommandID
        Write-Verbose "$MyTag Command enqueued: $commandId"

        # Wait for command completion
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
            return @()
        }

        # Parse result
        $cards = $commandResult.Result

        if ($cards -is [string]) {
            # Handle error messages
            if ($cards -match 'not available') {
                Write-Warning "$MyTag $cards"
                return @()
            }
            return @()
        }

        # Filter by ElementID if specified
        if ($ElementID) {
            $cards = $cards | Where-Object { $_.elementId -eq $ElementID }
            Write-Verbose "$MyTag Filtered to $($cards.Count) cards of type: $ElementID"
        } else {
            Write-Verbose "$MyTag Found $($cards.Count) open cards"
        }

        return $cards

} catch {
    Write-Error "$MyTag Error querying cards: $_"
    return @()
}
