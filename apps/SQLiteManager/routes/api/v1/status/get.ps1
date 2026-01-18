param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $SessionData
)

# Sample status endpoint for SQLite Manager app
try {
    $result = @{
        app = 'SQLite Manager'
        version = '1.0.0'
        status = 'running'
        timestamp = Get-Date -Format 'o'
        category = 'Databases'
        subCategory = 'SQLite'
    }

    context_response -Response $Response -String ($result | ConvertTo-Json) -ContentType 'application/json' -StatusCode 200

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'SQLiteManager' -Message "Error in status endpoint: $($_.Exception.Message)"

    context_response -Response $Response -StatusCode 500 -String (@{
        error = $_.Exception.Message
    } | ConvertTo-Json) -ContentType 'application/json'
}
