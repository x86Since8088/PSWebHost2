# e:\sc\git\PsWebHost\routes\api\ManageWindows\post.ps1
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Import the database module
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Database/PSWebHost_Database.psm1") -DisableNameChecking

$statusCode = 200
$responseObject = @{}

# 1. Authentication Validation (using SessionData)
$userId = $SessionData['UserID'] | Out-String
if (-not $userId) {
    $statusCode = 401
    $responseObject = @{ Status = "Error"; Message = "Authentication failed." }
} else {
    # Get card settings
    $endpointGuid = (Get-Content (Join-Path $PSScriptRoot 'post.json') | ConvertFrom-Json).guid
    $cardSettings = Get-CardSettings -EndpointGuid $endpointGuid -UserId $userId
    if ($cardSettings) {
        $responseObject.settings = $cardSettings | ConvertFrom-Json
    }

    # 2. Read and Parse JSON Body
    if ($Request.HasEntityBody) {
        try {
            $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
            $bodyContent = $reader.ReadToEnd()
            $reader.Close()
            $jsonData = $bodyContent | ConvertFrom-Json

            # 3. Process Data (Placeholder)
            $logMessage = "Received management data for computer: $($jsonData.ComputerName)"
            Write-PSWebHostLog -Severity 'Info' -Category 'ManageWindows' -Message $logMessage -Data $jsonData

            $statusCode = 200
            $responseObject.Status = "Success"
            $responseObject.Message = "Data received for $($jsonData.ComputerName)"

        } catch {
            $statusCode = 400
            $responseObject = @{ Status = "Error"; Message = "Invalid JSON format or processing error." ; ErrorDetails = $_.Exception.Message }
        }
    } else {
        $statusCode = 400
        $responseObject = @{ Status = "Error"; Message = "Request body is empty." }
    }
}

# 4. Send Centralized Response
$responseString = $responseObject | ConvertTo-Json
context_reponse -Response $Response -StatusCode $statusCode -String $responseString -ContentType "application/json"
