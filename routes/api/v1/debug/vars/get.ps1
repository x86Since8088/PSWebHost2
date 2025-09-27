param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    # Import required modules
    Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Formatters/PSWebHost_Formatters.psd1") -DisableNameChecking
    Import-Module powershell-yaml -DisableNameChecking

    # Get and process variables, excluding some known problematic ones
    $excludeVars = @('PSWebServer', 'Host', 'ExecutionContext', 'true', 'false', 'null', 'Context', 'Request', 'Response', 'SessionData')
    $vars = Get-Variable -Scope Global -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin $excludeVars } | ForEach-Object {
        $V = $_;
        if ($null -ne $V.Value) {
            try {
                $yamlValue = Inspect-Object -InputObject $V.Value | ConvertTo-Yaml
                [pscustomobject]@{
                    Name     = $V.Name
                    Type     = $V.Value.GetType().FullName
                    RawValue = $yamlValue
                }
            } catch {
                Write-PSWebHostLog -Severity 'Warning' -Category 'DebugVars' -Message "Could not process variable '$($V.Name)'. Error: $($_.Exception.Message)"
                # Return a placeholder for the variable that failed
                [pscustomobject]@{
                    Name     = $V.Name
                    Type     = "Error"
                    RawValue = "Error processing this variable: $($_.Exception.Message)"
                }
            }
        }
    } | Select-Object Name, Type, RawValue

    # Convert to JSON and send response
    $json = $vars | ConvertTo-Json -Depth 5
    context_reponse -Response $Response -String $json -ContentType "application/json"

} catch {
    # Catch any fatal error in the script and return a proper JSON error response
    $errorMessage = "An error occurred in /api/v1/debug/vars: $($_.Exception.Message)"
    Write-PSWebHostLog -Severity 'Error' -Category 'DebugVars' -Message $errorMessage
    $errorResponse = @{ error = $errorMessage } | ConvertTo-Json
    context_reponse -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
}
