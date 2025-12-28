$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Host "Current user: $currentUser"
Write-Host ""
Write-Host "Analyzing URL ACLs..."
Write-Host ""

$urlAclOutput = @(netsh http show urlacl 2>$null)
$currentUser_lower = $currentUser.ToLower()

$results = @()

for ($i = 0; $i -lt $urlAclOutput.Count; $i++) {
    $line = $urlAclOutput[$i]
    
    if ($line -match 'Reserved URL\s+:\s+(https?)://([*+]):(\d+)(/.*)?\s*$') {
        $protocol = $matches[1]
        $wildcard = $matches[2]
        $port = [int]$matches[3]
        $pathPart = $matches[4]
        
        $fullUrl = "$protocol"+"://$wildcard`:$port$pathPart"
        
        # Check if current user has access
        $hasAccess = $false
        for ($j = $i + 1; $j -lt $urlAclOutput.Count; $j++) {
            $nextLine = $urlAclOutput[$j]
            if ($nextLine -match 'Reserved URL\s+:') { break }
            
            if ($nextLine -match '^\s+User:\s+(.+)$') {
                $userInAcl = $matches[1].Trim()
                if ($userInAcl -eq $currentUser -or $userInAcl -eq '\Everyone' -or $userInAcl -eq 'BUILTIN\Users' -or $userInAcl -match $currentUser_lower) {
                    for ($k = $j + 1; $k -lt [Math]::Min($j + 3, $urlAclOutput.Count); $k++) {
                        if ($urlAclOutput[$k] -match 'Listen:\s*Yes') {
                            $hasAccess = $true
                            break
                        }
                    }
                }
            }
        }
        
        $isSimplePath = [string]::IsNullOrEmpty($pathPart) -or $pathPart -eq '/' -or $pathPart -eq ''
        $isFiltered = ($protocol -eq 'https' -or $fullUrl -match '/(wsman|rdp|sra_|C574|116B|WMPNSSv4|MDEServer|Temporary_Listen)')
        
        if ($hasAccess) {
            $results += @{
                Port = $port
                URL = $fullUrl
                SimplePath = $isSimplePath
                Filtered = $isFiltered
                Available = (-not $isFiltered)
            }
        }
    }
}

Write-Host "Available ports for your user:"
Write-Host "==============================="
$results | Where-Object { $_.Available } | ForEach-Object {
    Write-Host "Port $($_.Port): $($_.URL)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Filtered out (not suitable for HttpListener):"
Write-Host "=============================================="
$results | Where-Object { $_.Filtered } | ForEach-Object {
    Write-Host "Port $($_.Port): $($_.URL)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Simple-path ports (preferred):"
Write-Host "=============================="
$results | Where-Object { $_.Available -and $_.SimplePath } | ForEach-Object {
    Write-Host "Port $($_.Port): $($_.URL)" -ForegroundColor Cyan
}
