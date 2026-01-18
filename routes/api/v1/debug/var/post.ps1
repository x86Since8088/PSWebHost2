param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

# Expect JSON body: { Name: "...", OriginalType: "System.String", NewText: "..." }
$body = Get-RequestBody -Request $Request
if (-not $body) {
    context_response -Response $Response -StatusCode 400 -String "Empty body"
    return
}

try {
    $payload = $body | ConvertFrom-Json
} catch {
    context_response -Response $Response -StatusCode 400 -String "Invalid JSON: $_"
    return
}

if (-not $payload.Name) { context_response -Response $Response -StatusCode 400 -String "Missing Name"; return }

$name = $payload.Name -replace '^\$',''
$origType = $payload.OriginalType
$newText = if ($null -eq $payload.NewText) { '' } else { [string]$payload.NewText }

# Whitelist of supported type families
function Convert-TextToType($txt, $typeName){
    # Return a standardized result hashtable instead of throwing.
    # @{ Success = $true/false; Value = <value>; Error = <string> }
    if (-not $typeName -or $typeName -eq '' -or $typeName -eq 'System.String') {
        return @{ Success = $true; Value = [string]$txt }
    }

    # Booleans
    if ($typeName -match 'Boolean') {
        $t = $txt.Trim().ToLowerInvariant()
        if ($t -in @('true','1','yes')) { return @{ Success = $true; Value = $true } }
        if ($t -in @('false','0','no')) { return @{ Success = $true; Value = $false } }
        $parsed = $null
        try { $parsed = [bool]::Parse($txt) } catch { }
        if ($parsed -ne $null) { return @{ Success = $true; Value = $parsed } }
        return @{ Success = $false; Error = "Cannot parse boolean from '$txt'" }
    }

    # Integer types
    if ($typeName -match 'Int(16|32|64|128)?') {
        $parsed = $null
        try { $parsed = [int64]::Parse($txt) } catch { }
        if ($parsed -ne $null) { return @{ Success = $true; Value = $parsed } }
        return @{ Success = $false; Error = "Cannot parse integer from '$txt'" }
    }

    # Floating point
    if ($typeName -match 'Double|Single|Decimal|Float') {
        $parsed = $null
        try { $parsed = [double]::Parse($txt) } catch { }
        if ($parsed -ne $null) { return @{ Success = $true; Value = $parsed } }
        return @{ Success = $false; Error = "Cannot parse float from '$txt'" }
    }

    # DateTime
    if ($typeName -match 'DateTime') {
        $parsed = $null
        try { $parsed = [datetime]::Parse($txt) } catch { }
        if ($parsed -ne $null) { return @{ Success = $true; Value = $parsed } }
        return @{ Success = $false; Error = "Cannot parse DateTime from '$txt'" }
    }

    # Arrays and objects: expect JSON
    $__err = $null
    $parsed = $null
    try {
        $parsed = $txt | ConvertFrom-Json -ErrorAction SilentlyContinue -ErrorVariable __err
    } catch {}
    if ($parsed) { return @{ Success = $true; Value = $parsed } }
    # fallback: if original type is object but value is empty string, return $null success
    if (($txt -eq '') -and ($typeName -eq 'System.Object')) { return @{ Success = $true; Value = $null } }
    $errMsg = if ($__err) { $__err } else { 'Expected JSON for complex type; parsing failed' }
    return @{ Success = $false; Error = $errMsg }
}

$conversion = Convert-TextToType -txt $newText -typeName $origType
if (-not $conversion.Success) {
    context_response -Response $Response -StatusCode 400 -String "Failed to convert variable '$name': $($conversion.Error)"
    return
}

# set variable in global scope, overwrite if exists
Set-Variable -Name $name -Value $conversion.Value -Scope Global -Force
context_response -Response $Response -StatusCode 200 -String "OK"