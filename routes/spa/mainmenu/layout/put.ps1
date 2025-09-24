param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

function New-JsonResponse($status, $message) {
    return @{ status = $status; Message = $message } | ConvertTo-Json
}

# Read the new layout from the request body
$newLayoutContent = Get-RequestBody -Request $Request

# Validate the JSON
try {
    $null = $newLayoutContent | ConvertFrom-Json
} catch {
    $jsonResponse = New-JsonResponse -status 'fail' -message "Invalid JSON: $($_.Exception.Message)"
    context_reponse -Response $Response -StatusCode 400 -String $jsonResponse -ContentType "application/json"
    return
}

$layoutJsonPath = Join-Path $Global:PSWebServer.Project_Root.Path "public/layout.json"
$backupDir = Join-Path $Global:PSWebServer.Project_Root.Path "backups"

# Backup the old layout
if (Test-Path $layoutJsonPath) {
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $backupFile = Join-Path $backupDir "layout.json.$timestamp.bak"
    Copy-Item -Path $layoutJsonPath -Destination $backupFile
}

# Save the new layout
Set-Content -Path $layoutJsonPath -Value $newLayoutContent

$jsonResponse = New-JsonResponse -status 'success' -message "Layout saved successfully."
context_reponse -Response $Response -String $jsonResponse -ContentType "application/json"
