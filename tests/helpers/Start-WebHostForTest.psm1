function Start-WebHostForTest {
    [CmdletBinding()]
    param(
        [string]$ProjectRoot,
        [int]$Port = 0,
        [int]$StartupTimeoutSec = 20,
        [string]$OutDir
    )

    if ($PSBoundParameters.Verbose.IsPresent) {
        $caller = (Get-PSCallStack)[1].FunctionName
        Write-Verbose "Function 'Start-WebHostForTest' called from '$caller'."
    }

    if (-not $ProjectRoot) { $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
    # find pwsh or fallback
    $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwsh) { $pwsh = (Get-Command powershell -ErrorAction SilentlyContinue).Source }

    $webHostScript = Join-Path $ProjectRoot 'WebHost.ps1'
    if (-not (Test-Path $webHostScript)) { throw "WebHost.ps1 not found at $webHostScript" }

    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    
    # Get available URL ACLs for the current user
    $availablePorts = @()
    $availablePortsSimplePath = @()  # Ports with simple "/" path (preferred for HttpListener)
    $urlAclOutput = @(netsh http show urlacl 2>$null)
    if ($urlAclOutput.Count -gt 0) {
        $currentUser_lower = $currentUser.ToLower()
        
        # Process each line looking for URL reservations and user permissions
        for ($i = 0; $i -lt $urlAclOutput.Count; $i++) {
            $line = $urlAclOutput[$i]
            
            # Look for "Reserved URL" lines with port patterns
            if ($line -match 'Reserved URL\s+:\s+(https?)://([*+]):(\d+)(/.*)?\s*$') {
                $protocol = $matches[1]
                $wildcard = $matches[2]
                $port = [int]$matches[3]
                $pathPart = $matches[4]  # Captures everything after the port (e.g., "/+/" or "/wsman/")
                
                # Skip HTTPS ports and service-specific paths
                if ($protocol -eq 'https' -or $line -match '/(wsman|rdp|sra_|C574|116B|WMPNSSv4|MDEServer|Temporary_Listen)') { 
                    continue 
                }
                
                # Also skip wildcard * format as it may have compatibility issues
                if ($wildcard -eq '*') { continue }
                
                # Check if current user or Everyone has access (look ahead up to 20 lines for next URL)
                $hasAccess = $false
                for ($j = $i + 1; $j -lt $urlAclOutput.Count; $j++) {
                    $nextLine = $urlAclOutput[$j]
                    
                    # Stop if we hit another URL reservation
                    if ($nextLine -match 'Reserved URL\s+:') { break }
                    
                    # Check for "User: " line (handles backslashes and spaces)
                    if ($nextLine -match '^\s+User:\s+(.+)$') {
                        $userInAcl = $matches[1].Trim()
                        
                        # Check if this user matches current user or is Everyone
                        if ($userInAcl -eq $currentUser -or $userInAcl -eq '\Everyone' -or $userInAcl -eq 'BUILTIN\Users' -or $userInAcl -match $currentUser_lower) {
                            # Look for "Listen: Yes" in the next few lines
                            for ($k = $j + 1; $k -lt [Math]::Min($j + 3, $urlAclOutput.Count); $k++) {
                                if ($urlAclOutput[$k] -match 'Listen:\s*Yes') {
                                    $hasAccess = $true
                                    break
                                }
                                # Stop if we hit another User or Reserved URL
                                if ($urlAclOutput[$k] -match '^\s+User:' -or $urlAclOutput[$k] -match 'Reserved URL\s+:') { break }
                            }
                            if ($hasAccess) { break }
                        }
                    }
                }
                
                if ($hasAccess) {
                    if ($port -notin $availablePorts) {
                        $availablePorts += $port
                    }
                    # Track simple-path ports separately (prefer these for HttpListener compatibility)
                    if ([string]::IsNullOrEmpty($pathPart) -or $pathPart -eq '/' -or $pathPart -eq '') {
                        if ($port -notin $availablePortsSimplePath) {
                            $availablePortsSimplePath += $port
                        }
                    }
                }
            }
        }
    }
    
    # Prefer simple-path ports, fall back to all available ports if none found
    if ($availablePortsSimplePath.Count -gt 0) {
        $availablePorts = $availablePortsSimplePath
    }
    
    # Sort ports: prefer higher ports (less likely to conflict with system services)
    $availablePorts = $availablePorts | Sort-Object -Descending
    
    if ($PSBoundParameters.Verbose.IsPresent) {
        Write-Verbose "Available URL ACL ports for user: $($availablePorts -join ', ')"
    }
    
    if ($Port -eq 0) {
        if ($availablePorts.Count -eq 0) {
            $isAdmin = ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
            $errorMessage = "No URL ACL reservations found for user '$currentUser'. "
            if (-not $isAdmin) {
                $errorMessage += "Please run the following command in an elevated (administrator) terminal to grant permission for a test port (e.g., 8888):`n"
                $errorMessage += "netsh http add urlacl url=http://+:8888/ user='$currentUser'"
            } else {
                $errorMessage += "Please run the following command to grant permission for a test port (e.g., 8888):`n"
                $errorMessage += "netsh http add urlacl url=http://+:8888/ user='$currentUser'"
            }
            throw $errorMessage
        }
        # Prefer high ports used for testing (8080, 15099, etc.) over low ports
        # Use the first port found in URL ACLs that matches our preferred list
        $preferredPorts = @(8080, 15099, 5357, 5358) 
        $Port = $preferredPorts | Where-Object { $_ -in $availablePorts } | Select-Object -First 1
        
        # If no preferred port found, just use the first one
        if (-not $Port) {
            $Port = $availablePorts | Select-Object -First 1
        }
    } else {
        # If port is specified, verify it has URLACL permission
        $urlAcl = "http://+:$Port/"
        if ($Port -notin $availablePorts) {
            $isAdmin = ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
            $errorMessage = "URL ACL for $urlAcl is not set for user '$currentUser'. "
            if (-not $isAdmin) {
                $errorMessage += "Please run the following command in an elevated (administrator) terminal to grant permission:`n"
                $errorMessage += "netsh http add urlacl url=$urlAcl user='$currentUser'"
            } else {
                $errorMessage += "You are running as an administrator. Please run the following command to grant permission:`n"
                $errorMessage += "netsh http add urlacl url=$urlAcl user='$currentUser'"
            }
            throw $errorMessage
        }
    }

    if (-not $OutDir) { $OutDir = Join-Path $ProjectRoot 'tests\test-host-logs' }
    New-Item -Path $OutDir -ItemType Directory -Force | Out-Null
    $stdout = Join-Path $OutDir "webhost.$Port.out.txt"
    $stderr = Join-Path $OutDir "webhost.$Port.err.txt"

    $argList = @('-NoProfile','-NoLogo','-ExecutionPolicy','Bypass','-File', "$webHostScript", '-Port', "$Port", '-Verbose')

    $proc = Start-Process -FilePath $pwsh `
        -ArgumentList $argList `
        -WorkingDirectory $ProjectRoot `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru
    $baseUrl = "http://localhost:$Port/"
    Write-Host "Started WebHost process Id $($proc.Id) at $baseUrl (logs: $stdout, $stderr)"
    $deadline = (Get-Date).AddSeconds($StartupTimeoutSec)
    $ready = $false
    while ((Get-Date) -lt $deadline -and (Get-Process -ErrorAction Ignore -Id $proc.Id)) {
        try {
            $r = Invoke-WebRequest -Uri $baseUrl -UseBasicParsing -TimeoutSec 2
            if ($PSBoundParameters.Verbose.IsPresent) {
                Write-Verbose "Received status $($r.StatusCode) from $baseUrl"
            }
            # Accept 200, 302 (redirect), or 503 (unauthenticated) as signs the server is running
            if ($r.StatusCode -in @(200, 302, 503)) { $ready = $true; break }
        } catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            if ($PSBoundParameters.Verbose.IsPresent) {
                Write-Verbose "Connection failed: $($_.Exception.Message) (Status: $statusCode)"
            }
            # If we got a 503 or 302 error, that means the server is responding
            if ($statusCode -in @(503, 302)) { $ready = $true; break }
            Start-Sleep -Seconds 1
        }
    }

    return [pscustomobject]@{ Process = $proc; Url = $baseUrl; Ready = $ready; OutFiles = @{ StdOut = $stdout; StdErr = $stderr } }
}

Export-ModuleMember -Function Start-WebHostForTest
