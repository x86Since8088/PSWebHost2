param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $SessionData
)

# Sample status endpoint for SQL Server Manager app
try {
    $result = @{
        app = 'SQL Server Manager'
        version = '1.0.0'
        status = 'running'
        timestamp = Get-Date -Format 'o'
        category = 'Databases'
        subCategory = 'SQL Server'
    }

    context_reponse -Response $Response -String ($result | ConvertTo-Json) -ContentType 'application/json' -StatusCode 200

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'SQLServerManager' -Message "Error in status endpoint: $($_.Exception.Message)"

    context_reponse -Response $Response -StatusCode 500 -String (@{
        error = $_.Exception.Message
    } | ConvertTo-Json) -ContentType 'application/json'
}
