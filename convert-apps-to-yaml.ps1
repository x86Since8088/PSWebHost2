# Convert all app.json files to app.yaml
Import-Module powershell-yaml -ErrorAction Stop

$apps = Get-ChildItem -Path "apps/*/app.json" -Recurse

foreach ($appJson in $apps) {
    $json = Get-Content $appJson.FullName -Raw | ConvertFrom-Json
    $yamlPath = $appJson.FullName -replace '\.json$', '.yaml'

    # Convert to YAML
    $yaml = $json | ConvertTo-Yaml
    Set-Content -Path $yamlPath -Value $yaml -Encoding UTF8

    Write-Host "Converted: $($appJson.FullName) -> $yamlPath" -ForegroundColor Green
}

Write-Host "`nConversion complete. Found $($apps.Count) app.json files." -ForegroundColor Cyan
