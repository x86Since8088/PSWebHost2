param (
    [System.Net.HttpListenerContext]$Context,
    [hashtable]$SessionData
)

# In a real implementation, this would fetch user-specific profile data from the database.
# For now, we return dummy data.

$profileData = @{
    fullName = "Test User";
    email = $SessionData.UserID;
    phone = "123-456-7890";
    bio = "This is a test bio.";
}

$jsonResponse = $profileData | ConvertTo-Json
context_reponse -Response $Context.Response -String $jsonResponse -ContentType "application/json"