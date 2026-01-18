Import-Module ./ModuleDownload/powershell-yaml/0.4.2/powershell-yaml.psm1 -DisableNameChecking -WarningAction SilentlyContinue
$null = .\routes\api\v1\ui\elements\main-menu\get.ps1 -test -Roles admin
$Global:PSWebServer.MainMenu.CachedMenu | ConvertTo-Json -Depth 8 | Out-File menu-cache-full.json
Write-Host "Saved to menu-cache-full.json"

# Also check for "System Management" entry
$systemMgmt = $Global:PSWebServer.MainMenu.CachedMenu | Where-Object { $_.Name -eq "System Management" }
if ($systemMgmt) {
    Write-Host "`nFound 'System Management' entry"
    Write-Host "  Has children: $($null -ne $systemMgmt.children)"
    if ($systemMgmt.children) {
        Write-Host "  Children count: $($systemMgmt.children.Count)"
        $systemMgmt.children | ForEach-Object { Write-Host "    - $($_.Name)" }

        $webhost = $systemMgmt.children | Where-Object { $_.Name -eq "WebHost" }
        if ($webhost) {
            Write-Host "`n  Found 'WebHost' entry under System Management"
            Write-Host "    Has children: $($null -ne $webhost.children)"
            if ($webhost.children) {
                Write-Host "    Children count: $($webhost.children.Count)"
                $webhost.children | ForEach-Object { Write-Host "      - $($_.Name)" }
            }
        }
    }
} else {
    Write-Host "`n'System Management' entry NOT FOUND in cached menu"
}
