param (
    [System.Net.HttpListenerContext]$Context,
    [hashtable]$SessionData
)

$body = Get-RequestBody -Request $Context.Request

# In a real implementation, this would save the profile data to the database.
# For now, we just log the data.
Write-PSWebHostLog -Severity 'Info' -Category 'Profile' -Message "Received profile update for user $($SessionData.UserID)." -Data @{ ProfileData = $body }

$response = @{
    status = 'success';
    message = 'Profile updated successfully.'
} | ConvertTo-Json

context_reponse -Response $Context.Response -String $response -ContentType "application/json"