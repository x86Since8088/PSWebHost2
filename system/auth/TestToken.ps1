[cmdletbinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$State,

    [Parameter(Mandatory=$false)]
    [string]$SessionID = '%',

    [Parameter(Mandatory=$false)]
    [string]$UserID = '%',

    [Parameter(Mandatory=$false)]
    [string]$Provider = '%',

    [Parameter(Mandatory=$false)]
    [string]$AuthenticationState,

    [Parameter(Mandatory=$false)]
    [switch]$Completed
)

if ($null -eq $global:PSWebServer) {
    $ProjectRoot = $PSScriptRoot -replace '[\\/]system[\\/].*'
    . "$ProjectRoot\system\init.ps1"
}

$DatabaseFile = "pswebhost.db"

# Cleanup expired and incomplete sessions first
$cleanupTime = (Get-Date).AddMinutes(-5).ToUniversalTime()
$cleanupTimeUnix = [int64]((Get-Date $cleanupTime) - (Get-Date "1970-01-01 00:00:00Z")).TotalSeconds
$cleanupQuery = "DELETE FROM LoginSessions WHERE AuthenticationTime < $cleanupTimeUnix AND (AuthenticationState IS NOT 'completed' OR AuthenticationState IS NULL);"
Invoke-PSWebSQLiteNonQuery -File $DatabaseFile -Query $cleanupQuery

# Handle state updates
if ($PSBoundParameters.ContainsKey('AuthenticationState') -or $Completed) {
    if ($SessionID -eq '%') {
        Write-Error "A specific SessionID must be provided to update AuthenticationState."
        return
    }
    $newState = if ($Completed) { 'completed' } else { $AuthenticationState }
    Write-Verbose "[TestToken.ps1] Attempting to set state to '$newState' for SessionID $SessionID."

    $setClauses = @("AuthenticationState = '$newState'")
    if ($UserID -ne '%') {
        $setClauses += "UserID = '$UserID'"
    }
    if ($Provider -ne '%') {
        $setClauses += "Provider = '$Provider'"
    }
    $setStatement = $setClauses -join ', '

    $updateQuery = "UPDATE LoginSessions SET $setStatement WHERE SessionID = '$SessionID'"

    Write-Verbose "[TestToken.ps1] Executing query: $updateQuery"
    Invoke-PSWebSQLiteNonQuery -File $DatabaseFile -Query $updateQuery
    return
}

# Handle state validation
Write-Verbose "[TestToken.ps1] Attempting to validate state '$State' for SessionID $SessionID."
$query = "SELECT * FROM LoginSessions WHERE SessionID LIKE '$SessionID' AND UserID LIKE '$UserID' AND Provider LIKE '$Provider' ORDER BY AuthenticationTime DESC;"
$results = Get-PSWebSQLiteData -File $DatabaseFile -Query $query
Write-Verbose "[TestToken.ps1] Found $($results.Count) matching sessions."

if ($null -ne $State) {
    foreach ($result in $results) {
        if ($result.AuthenticationState -eq $State) {
            Write-Verbose "[TestToken.ps1] Match found! AuthenticationState is '$($result.AuthenticationState)'. Clearing state and returning object."
            # State matches, clear it to prevent reuse, and return the session object
            $updateQuery = "UPDATE LoginSessions SET AuthenticationState = NULL WHERE SessionID = '$($result.SessionID)';"
            Invoke-PSWebSQLiteNonQuery -File $DatabaseFile -Query $updateQuery
            return $result
        }
    }
    # If no session matched the state
    Write-Verbose "[TestToken.ps1] No session found with matching state."
    return $null
}

# If no state is provided for validation, just return the query results
return $results
