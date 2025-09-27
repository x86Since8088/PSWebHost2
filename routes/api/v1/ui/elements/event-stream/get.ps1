
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)
#$VerbosePreference = 'Continue'
# Get events using the new function. It handles permissions internally.
# In a real app, the UserID would come from the validated session.
[string]$userId = $SessionData['UserID'] | Out-String
if ('' -eq $userId) { 
    context_reponse -Response $Response -String '{"Status": "Not Authenticated"}' -ContentType "application/json"
} # Treat empty string as null
if (-not $userId) { $userId = "anonymous" }
Write-Verbose "Event-Stream User ID: $userId"
$events = Get-PSWebHostEvents -UserID $userId
Write-Verbose "`tEvent-Stream Event Count: $($events.count))"

# Sort events: Active first, then by date descending
$sortedEvents = $events | Sort-Object -Property @{Expression={ $_.state -ne 'Active' }; Ascending=$true}, @{Expression={ $_.Date }; Descending=$true}
if ($verbose.ispresent -or $VerbosePreference -eq 'Continue') {
    Write-Verbose "`tEvent-Stream Sorted Event Count: $($sortedEvents.count)"
}

[string]$jsonData = $sortedEvents | ConvertTo-Json -Depth 5
if ($jsonData -in @('null', '')) { $jsonData = '[]' } # Ensure valid JSON array if no events
Write-Verbose "`tEvent Stream Data: `n`t`t$($jsonData -split '\n' -join "`n`t`t")"
context_reponse -Response $Response -String $jsonData -ContentType "application/json"
