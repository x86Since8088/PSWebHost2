
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    [string]$sessionID = $Context.Request.Cookies["PSWebSessionID"].Value,
    $sessiondata = $global:PSWebSessions[$sessionID]
)

# Import the database module to use Set-CardSession
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Database/PSWebHost_Database.psm1") -DisableNameChecking

# 1. Read the JSON body from the POST request
$bodyContent = Get-RequestBody -Request $Request
if ([string]::IsNullOrEmpty($bodyContent)) {
    context_reponse -Response $Response -StatusCode 400 -String "Request body is empty." -ContentType "text/plain"
    return
}
$requestBody = $bodyContent | ConvertFrom-Json -AsHashtable

# 2. Prepare data for database
$cardJson = $requestBody | ConvertTo-Json -Compress
$newGuid = [Guid]::NewGuid().ToString()
$dataBackend = $requestBody.data_backend # Assuming the card sends this

# 3. GZip and Base64 encode the card definition
$base64Definition = ConvertTo-CompressedBase64 -InputString $cardJson

# 4. Save to database
# Note: In a real app, UserID would be properly managed.
$userId = $SessionData['UserID'] | Out-String # Placeholder
if (-not $userId) { $userId = "anonymous" }

Set-CardSession -SessionID $SessionData.SessionID -UserID $userId -CardGUID $newGuid -DataBackend $dataBackend -CardDefinition $base64Definition

# 5. Build and return the new command-based response
$responseBody = $requestBody.Clone() # Start with the original properties
$responseBody.guid = $newGuid # Add the new guid

# Get card settings if user is authenticated
$endpointGuid = (Get-Content (Join-Path $PSScriptRoot 'post.json') | ConvertFrom-Json).guid
if ($userId -ne 'anonymous') {
    $cardSettings = Get-CardSettings -EndpointGuid $endpointGuid -UserId $userId
    if ($cardSettings) {
        $responseBody.settings = $cardSettings | ConvertFrom-Json
    }
}

# Create a sample update command array to demonstrate the format
$updates = @(
    @{
        Command     = "set"
        ElementName = "cardTitle"
        data        = "Title Updated by Server"
    },
    @{
        Command     = "newrecords"
        ElementName = "logContainer"
        data        = @(
            @{ timestamp = (Get-Date).ToString('o'); message = "Card state saved with GUID: $newGuid" }
        )
    },
    @{
        Command     = "clear"
        ElementName = "statusIndicator"
        data        = $null
    },
    @{
        Command     = "keepnewest"
        ElementName = "logContainer"
        data        = @{ propertyName = "logEntries"; count = 50 } # Example data format for this command
    }
)

# Add the update array to the response body
$responseBody.update = $updates

$responseJson = $responseBody | ConvertTo-Json -Depth 5

context_reponse -Response $Response -String $responseJson -ContentType "application/json"
