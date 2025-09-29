param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

# Expect JSON body: { Name: "...", OriginalType: "System.String", NewText: "..." }
$body = Get-RequestBody -Request $Request
if (-not $body) {
    context_reponse -Response $Response -StatusCode 400 -String "Empty body"
    return
}

try {
    $payload = $body | ConvertFrom-Json
} catch {
    context_reponse -Response $Response -StatusCode 400 -String "Invalid JSON: $_"
    return
}

if (-not $payload.Name) { context_reponse -Response $Response -StatusCode 400 -String "Missing Name"; return }

$name = $payload.Name -replace '^\$',''
$origType = $payload.OriginalType
$newText = if ($null -eq $payload.NewText) { '' } else { [string]$payload.NewText }

# Whitelist of supported type families
function Convert-TextToType($txt, $typeName){
    if (-not $typeName -or $typeName -eq '' -or $typeName -eq 'System.String') {
        return [string]$txt
    }

    # Booleans
    if ($typeName -match 'Boolean') {
        $t = $txt.Trim().ToLowerInvariant()
        if ($t -in @('true','1','yes')) { return $true }
        if ($t -in @('false','0','no')) { return $false }
        try { return [bool]::Parse($txt) } catch { throw "Cannot parse boolean from '$txt'" }
    }

    # Integer types
    if ($typeName -match 'Int(16|32|64|128)?') {
        try { return [int64]::Parse($txt) } catch { throw "Cannot parse integer from '$txt'"; }
    }

    # Floating point
    if ($typeName -match 'Double|Single|Decimal|Float') {
        try { return [double]::Parse($txt) } catch { throw "Cannot parse float from '$txt'"; }
    }

    # DateTime
    if ($typeName -match 'DateTime') {
        try { return [datetime]::Parse($txt) } catch { throw "Cannot parse DateTime from '$txt'"; }
    }

    # Arrays and objects: expect JSON
    try {
        $parsed = $txt | ConvertFrom-Json -ErrorAction Stop
        return $parsed
    } catch {
        # fallback: if original type is object but value is empty string, return $null
        if (($txt -eq '') -and ($typeName -eq 'System.Object')) { return $null }
        throw "Expected JSON for complex type; parsing failed: $_"
    }
}

try {
    $valueToSet = Convert-TextToType -txt $newText -typeName $origType
    # set variable in global scope, overwrite if exists
    Set-Variable -Name $name -Value $valueToSet -Scope Global -Force
    context_reponse -Response $Response -StatusCode 200 -String "OK"
} catch {
    context_reponse -Response $Response -StatusCode 400 -String "Failed to convert/set variable: $_"
}