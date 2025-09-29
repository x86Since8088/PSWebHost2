Add-Type -AssemblyName System.DirectoryServices.AccountManagement

[cmdletbinding()]
param (
    [string]$Username,
    [string]$Password,
    [System.DirectoryServices.AccountManagement.ContextType]$ContextType = 'Machine'
)

if (-not $Username) { Write-Error "The -Username parameter is required."; return $false }
if (-not $Password) { Write-Error "The -Password parameter is required."; return $false }

try {
    $pc = New-Object System.DirectoryServices.AccountManagement.PrincipalContext($ContextType)
    $isValid = $pc.ValidateCredentials($Username, $Password)
    if ($isValid) {
        Write-Verbose "Windows authentication successful for user '$Username'."
    } else {
        Write-Warning "Windows authentication failed for user '$Username'."
    }
    return $isValid
} catch {
    Write-Error "An error occurred during Windows authentication: $($_.Exception.Message)"
    return $false
}
