param(
    [string]$Path
)

try {
    $content = Get-Content -Raw -Path $Path -Encoding UTF8
    $json = $content | ConvertFrom-Json
    Write-Host "JSON is valid"
}
catch {
    Write-Host "JSON is invalid"
    Write-Host $_.Exception.Message
}
