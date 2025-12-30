# PSWebHost_Support.psm1

# Global hashtable for session management
if ($null -eq $global:PSWebSessions) {$global:PSWebSessions = [hashtable]::Synchronized(@{})}

#Remember to update the psd1 manifest.

function Get-RequestBody {
    param (
        [System.Net.HttpListenerRequest]$Request
    )
    $MyTag = "[Get-RequestBody]"
    if ($Request.HasEntityBody) {
        $reader = $null
        try {
            $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
            return $reader.ReadToEnd()
        } catch {
            Write-Error "$($MyTag) Failed to read request body. Error: $($_) "
            return $null
        } finally {
            if ($reader) {
                $reader.Close()
            }
        }
    } else {
        return $null
    }
}



function ConvertTo-CompressedBase64 {
    param (
        [string]$InputString
    )
    $MyTag = "[ConvertTo-CompressedBase64]"
    $compressedBytes = $null
    $memStream = $null
    $gzipStream = $null
    try {
        $inputBytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
        $memStream = New-Object System.IO.MemoryStream
        $gzipStream = New-Object System.IO.Compression.GZipStream($memStream, [System.IO.Compression.CompressionMode]::Compress)
        $gzipStream.Write($inputBytes, 0, $inputBytes.Length)
        $gzipStream.Close() # Closing the GZipStream also flushes it.
        $compressedBytes = $memStream.ToArray()
        [System.Convert]::ToBase64String($compressedBytes)
    } catch {
        Write-Error "$($MyTag) Failed to compress string. Error: $($_) "
        $null
    } finally {
        if ($gzipStream) { $gzipStream.Dispose() }
        if ($memStream) { $memStream.Dispose() }
    }
}

function Resolve-RouteScriptPath {
    param (
        [string]$UrlPath,
        [string]$HttpMethod,
        [string]$BaseDirectory
    )
    $trimmedUrlPath = $UrlPath.Trim('/')
    $potentialPath = Join-Path $BaseDirectory "$trimmedUrlPath/$HttpMethod.ps1"
    Write-Verbose "$( $MyTag ) Checking for route script: $($potentialPath)"
    if (Test-Path $potentialPath -PathType Leaf) { 
        Write-Verbose "$( $MyTag ) Route script found: $($potentialPath)"
        return $potentialPath 
    } else { 
        Write-Verbose "$( $MyTag ) Route script not found: $($potentialPath)"
        return $null 
    }
}

function Ensure-SessionCookie {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response
    )
    # Returns hashtable: @{ SessionID=..., SessionCookie=... }
    $MyTag = '[Ensure-SessionCookie]'
    try { Write-Verbose "$( $MyTag ) Incoming Cookie header: $($Request.Headers['Cookie'])" } catch {}
    $sessionCookie = $Request.Cookies["PSWebSessionID"]
    if ($sessionCookie) {
        $sessionID = $sessionCookie.Value
        Write-Verbose "$( $MyTag ) Session cookie found: $($sessionID)"
    } else {
        $sessionID = [Guid]::NewGuid().ToString()
        Write-Verbose "$( $MyTag ) No session cookie found, creating new session: $($sessionID)"
        $newCookie = New-Object System.Net.Cookie("PSWebSessionID", $sessionID)
        $hostName = $Request.Url.HostName
        if ($hostName -notmatch '^(localhost|(\d{1,3}\.){3}\d{1,3}|::1)$') {
            $newCookie.Domain = $hostName
        }
        $newCookie.Expires = (Get-Date).AddDays(7)
        $newCookie.Path = "/"
        $newCookie.HttpOnly = $true
        $newCookie.Secure = $Request.IsSecureConnection
        $Response.AppendCookie($newCookie)
        try { Write-Verbose "$( $MyTag ) Response Set-Cookie header after append: $($Response.Headers['Set-Cookie'])" } catch {}
        $Request.Cookies.Add($newCookie)
        $sessionCookie = $newCookie
        Write-Verbose "$( $MyTag ) Session cookie appended to response: $($sessionID) (Secure=$($newCookie.Secure), HttpOnly=$($newCookie.HttpOnly))"
    }
    if ($sessionCookie) {
        if ($Request.IsSecureConnection -ne $sessionCookie.Secure -or -not $sessionCookie.HttpOnly) {
            $sessionCookie.Secure = $Request.IsSecureConnection
            $sessionCookie.HttpOnly = $true
            $sessionCookie.Path = "/"
        }
    }
    return @{ SessionID = $sessionID; SessionCookie = $sessionCookie }
}

# Check whether the session satisfies security requirements for a route
function Authorize-Request {
    param(
        $Session,
        [string]$SecurityPath
    )
    $MyTag = '[Authorize-Request]'
    # Ensure security file exists with sane default
    if (-not (Test-Path $SecurityPath)) {
        $defaultRoles = @('unauthenticated')
        $securityContent = @{ Allowed_Roles = $defaultRoles } | ConvertTo-Json -Compress
        Set-Content -Path $SecurityPath -Value $securityContent
        Write-Verbose "$($MyTag) Auto-created default security file with roles: $($defaultRoles -join ', ')"
    }

    try {
        $securityConfig = Get-Content $SecurityPath | ConvertFrom-Json
    } catch {
        Write-Verbose "$($MyTag) Failed to read security config: $($_)"
        return $false
    }

    if (-not $securityConfig.Allowed_Roles) { return $false }
    $userRoles = $Session.Roles
    foreach ($allowedRole in $securityConfig.Allowed_Roles) {
        if ($userRoles -contains $allowedRole) { return $true }
    }
    return $false
}
function Set-PSWebSession {
    [cmdletbinding()]
    param (
        [string]$SessionID,
        [string]$UserID,
        [string[]]$Roles,
        [string[]]$RemoveRoles,
        [string]$Provider,
        [System.Net.HttpListenerRequest]$Request
    )
    $MyTag = '[Set-PSWebSession]'
    $sessionData = Get-PSWebSessions -SessionID $SessionID

    if ($UserID) { $sessionData.UserID = $UserID }
    # Normalize Roles to an ArrayList when provided
    if ($Roles) {
        if ($Roles -is [System.Collections.ArrayList]) {
            $alist = $Roles
        } else {
            $alist = [System.Collections.ArrayList]::new()
            foreach ($r in $Roles) { if ($r -and $r.Trim() -ne '') { [void]$alist.Add($r) } }
        }
        $sessionData.Roles = $alist
    }
    if ($RemoveRoles) {
        if ($null -eq $sessionData.Roles) { $sessionData.Roles = [System.Collections.ArrayList]::new() }
        if ($sessionData.Roles -isnot [System.Collections.ArrayList]) { $sessionData.Roles = [System.Collections.ArrayList]@($sessionData.Roles) }
        foreach ($rr in $RemoveRoles) { $null = $sessionData.Roles.Remove($rr) }
    }
    if ($Request) { $sessionData.UserAgent = $Request.UserAgent }
    if ($Provider) { $sessionData.Provider = $Provider }
    
    $sessionData.AuthTokenExpiration = (Get-Date).AddDays(7)
    $sessionData.LastUpdated = Get-Date

    # Ensure Roles exists and reflects authentication status
    if (-not $sessionData.Roles) { $sessionData.Roles = [System.Collections.ArrayList]::new(); $null = $sessionData.Roles.Add('unauthenticated') }
    if ($sessionData.UserID -and $sessionData.UserID.Trim() -ne '' -and $sessionData.UserID -ne 'pending') {
        if (-not ($sessionData.Roles -contains 'authenticated')) { [void]$sessionData.Roles.Add('authenticated') }
        if ($sessionData.Roles -contains 'unauthenticated') { $null = $sessionData.Roles.Remove('unauthenticated') }
        # Mark session as authenticated unless already marked completed/authenticated
        if (-not $sessionData.AuthenticationState -or $sessionData.AuthenticationState -notin @('completed','authenticated')) {
            $sessionData.AuthenticationState = 'authenticated'
        }
    } else {
        # ensure unauthenticated role present
        if (-not ($sessionData.Roles -contains 'unauthenticated')) { [void]$sessionData.Roles.Add('unauthenticated') }
        if ($sessionData.Roles -contains 'authenticated') { $null = $sessionData.Roles.Remove('authenticated') }
        # Clear authentication state for anonymous sessions
        if ($sessionData.AuthenticationState) { $sessionData.AuthenticationState = '' }
    }

    Write-Verbose "$($MyTag) $((Get-Date -f 'yyyMMdd HH:mm:ss')) Calling: Set-LoginSession -SessionID '$SessionID' -UserID '$($sessionData.UserID)' -Provider '$($sessionData.Provider)' -AuthenticationTime '$($sessionData.LastUpdated)' -LogonExpires '$($sessionData.AuthTokenExpiration)' -UserAgent '$($sessionData.UserAgent)' | Out-Null"
    Write-PSWebHostLog -Severity 'Info' -Category 'Session' -Message "Setting PSWeb session for SessionID '$SessionID', UserID '$($sessionData.UserID)'." -Data @{ SessionID = $SessionID; UserID = $sessionData.UserID; Provider = $sessionData.Provider; UserAgent = $sessionData.UserAgent; AuthTokenExpiration = $sessionData.AuthTokenExpiration } -WriteHost:$Verbose.ispresent
    Set-LoginSession -SessionID $SessionID -UserID $sessionData.UserID -Provider $sessionData.Provider -AuthenticationTime $sessionData.LastUpdated -LogonExpires $sessionData.AuthTokenExpiration  -AuthenticationState $sessionData.AuthenticationState -UserAgent $sessionData.UserAgent | Out-Null
    Write-Verbose "$($MyTag) $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed Set-LoginSession" -Verbose
}

function Get-PSWebSessions {
    param (
        [string]$SessionID
    )
    $MyTag = '[Get-PSWebSessions]'

    # Validate SessionID
    if ([string]::IsNullOrWhiteSpace($SessionID)) {
        Write-Warning "$MyTag SessionID is null or empty, returning empty session"
        return [hashtable]::Synchronized(@{})
    }

    if ($null -eq $global:PSWebSessions[$SessionID]) {
        # Try to load from DB
        $loginSession = Get-LoginSession -SessionID $SessionID
        if ($loginSession) {
            $roles = [System.Collections.ArrayList]@()
            if ($loginSession.AuthenticationState -in @('completed','authenticated') -and $loginSession.UserID -and $loginSession.UserID -ne 'pending') {
                $roles.Add('authenticated')
                $user = Get-PSWebUser -UserID $loginSession.UserID
                if ($user) {
                    $userRoles = Get-PSWebHostRole -UserID $user.UserID
                    if ($userRoles) {
                        $roles.AddRange($userRoles)
                    }
                }
            } else {
                $roles.Add('unauthenticated')
            }

            $global:PSWebSessions[$SessionID] = [hashtable]::Synchronized(@{
                UserID = $loginSession.UserID
                Provider = $loginSession.Provider
                UserAgent = $loginSession.UserAgent
                AuthTokenExpiration = [datetimeoffset]::FromUnixTimeSeconds([int64]$loginSession.LogonExpires).DateTime
                LastUpdated = [datetimeoffset]::FromUnixTimeSeconds([int64]$loginSession.AuthenticationTime).DateTime
                Roles = $roles
            }) 
        }
        else {
            # Not in DB, create new session
            $global:PSWebSessions[$SessionID] = [hashtable]::Synchronized(@{})
        }
    }

    $NewSessionData = @{
        UserID = ""
        RemoteAddress = ""
        UserAgent = ""
        AuthToken = ""
        AccessToken = ""
        AuthTokenExpiration = (Get-Date)
        AccessTokenExpiration = (Get-Date)
        LastAccessTimestamps = [System.Collections.Generic.List[System.DateTime]]::new()
        Runspaces = [hashtable]::Synchronized(@{})
        Roles = [System.Collections.ArrayList]@('unauthenticated')
    }
    $Updates=0
    foreach($key in $NewSessionData.Keys) {
        if (-not $global:PSWebSessions[$SessionID].ContainsKey($key)) {
            $global:PSWebSessions[$SessionID][$key] = $NewSessionData[$key]
            $Updates++
        }
    }
    if ($Updates -ne 0) {
        $global:PSWebSessions[$SessionID].LastUpdated = Get-Date
    }
    $returnValue = $global:PSWebSessions[$SessionID]
    Write-Verbose "[Get-PSWebSessions] Returning session type: $($returnValue.GetType().FullName) IsArray: $($returnValue -is [System.Array])"
    return $returnValue
}

function Remove-PSWebSession {
    param (
        [string]$SessionID
    )
    $MyTag = '[Remove-PSWebSession]'
    if ($global:PSWebSessions.ContainsKey($SessionID)) {
        $global:PSWebSessions.Remove($SessionID)
    }
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Calling: Remove-LoginSession -SessionID '$SessionID'" -Verbose
    Write-PSWebHostLog -Severity 'Info' -Category 'Session' -Message "Removing PSWeb session for SessionID '$SessionID'." -Data @{ SessionID = $SessionID }
    Remove-LoginSession -SessionID $SessionID
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed Remove-LoginSession" -Verbose
}


function Validate-UserSession {
    [cmdletbinding()]
    param (
        [System.Net.HttpListenerContext]$Context,
        [string]$SessionID = $Context.Request.Cookies["PSWebSessionID"].Value
    )
    $MyTag = '[Validate-UserSession]'
    [switch]$Verbose = $PSBoundParameters['Verbose']
    $SessionData = Get-PSWebSessions -SessionID $SessionID

    if (-not $SessionID) {
        if ($Verbose.IsPresent){
            Write-PSWebHostLog -Severity 'Info' -Category 'Session' -Message "$MyTag No session ID provided."
        }
        return $false
    }

    if (-not $SessionData -or -not $SessionData.Roles -or -not ($SessionData.Roles -contains "authenticated")) {
        if ($Verbose.IsPresent){
            Write-Verbose -Message "`t$MyTag $(Get-Date -f 'yyyMMdd HH:mm:ss') User is not authenticated.`n`t`tSessionID: $(($SessionID|Inspect-Object -Depth 4| ConvertTo-YAML) -split '\n' -notmatch '^	*Type:' -join "`n`t`t`t")"
            Write-PSWebHostLog -Severity 'Info' -Category 'Session' -Message "$MyTag User is not authenticated. SessionID: '$SessionID'." -WriteHost:$Verbose.ispresent
        }
        return $false
    }

    if ($SessionData.AuthTokenExpiration -lt (Get-Date)) {
        Write-PSWebHostLog -Severity 'Info' -Category 'Session' -Message "$MyTag Expired auth token for SessionID '$SessionID'." -WriteHost:$Verbose.ispresent
        return $false
    }

    # The UserAgent must have been set when the session was created.
    # If it's missing or doesn't match, the session is invalid.
    $requestUserAgent = $Context.Request.UserAgent
    if ([string]::IsNullOrEmpty($SessionData.UserAgent)) {
        # If the stored UserAgent is blank, this is likely the first request establishing the session's identity.
        # Save the current UserAgent to the session.
        $SessionData.UserAgent = $requestUserAgent
        # Also persist this to the database record for the session.
        Set-LoginSession -SessionID $SessionID -UserID $SessionData.UserID -Provider $SessionData.Provider -AuthenticationTime $SessionData.LastUpdated -AuthenticationState 'New' -LogonExpires $SessionData.AuthTokenExpiration -UserAgent $requestUserAgent
        Write-PSWebHostLog -Severity 'Info' -Category 'Session' -Message "First User-Agent seen for SessionID '$SessionID'. Setting to: '$requestUserAgent'."
    }
    elseif ($SessionData.UserAgent -ne $requestUserAgent) {
        # If it's not blank but doesn't match, then it's a mismatch.
        Write-PSWebHostLog -Severity 'Warning' -Category 'Session' -Message "User-Agent mismatch for SessionID '$SessionID'. Expected: '$($SessionData.UserAgent)', Got: '$requestUserAgent'." -WriteHost:$Verbose.ispresent
        return $false
    }
    
    return $true
}


function Process-HttpRequest {
    [cmdletbinding()]
    param (
        [System.Net.HttpListenerContext]$Context,
        [switch]$Async = $Async.ispresent,
        $HostUIQueue = $HostUIQueue,
        [switch]$Inlineexecute
    )
    $MyTag = '[Process-HttpRequest]'
    if (!$Inlineexecute.IsPresent) {
        try{$global:PSWebHostLogQueue = $using:global:PSWebHostLogQueue}catch{}
        try{$global:PSWebServer       = $using:global:PSWebServer      }catch{}
        try{$global:PSWebSessions     = $using:global:PSWebSessions    }catch{}
    }
    Write-Verbose "$($MyTag) Starting processing request: $($httpMethod) $($requestedPath) from $($request.RemoteEndPoint)"

    $request = $Context.Request
    $response = $Context.Response
    $handled = $false
    $requestedPath = $request.Url.LocalPath
    $httpMethod = $request.HttpMethod.ToLower()
    $projectRoot = $Global:PSWebServer.Project_Root.Path
    if ($requestedPath -match '/\.well-known/') {
        return
    }
    
    # Apply debug settings from config
    if ($global:PSWebServer.config.debug_url) {
        foreach ($urlMatch in ($global:PSWebServer.config.debug_url.PSObject.Properties|Sort-Object Name)) {
            if ($requestedPath.StartsWith($urlMatch.Name)) {
                foreach ($preference in $urlMatch.Value.PSObject.Properties) {
                    Set-Variable -Name "$($preference.Name)Preference" -Value $preference.Value
                }
            }
        }
    }

    Write-Verbose "$($MyTag) $(Get-Date -f 'yyyMMdd HH:mm:ss') Request received: $($httpMethod) $($requestedPath) from $($request.RemoteEndPoint)"
    
    # Log incoming Cookie header for debugging cookie flows
    try { Write-Verbose "$($MyTag) Incoming Cookie header: $($request.Headers['Cookie'])" } catch {}
    $sessionCookie = $request.Cookies["PSWebSessionID"]
    if ($sessionCookie -and -not [string]::IsNullOrWhiteSpace($sessionCookie.Value)) {
        $sessionID = $sessionCookie.Value
        Write-Verbose "$($MyTag) Session cookie found: $($sessionID)"

    } else {
        $sessionID = [Guid]::NewGuid().ToString()
        Write-Verbose "$($MyTag) No session cookie found or empty, creating new session: $($sessionID)"

        # Create session in database and memory
        $global:PSWebSessions[$sessionID] = [hashtable]::Synchronized(@{
            UserID = ""
            Provider = ""
            UserAgent = $request.UserAgent
            AuthTokenExpiration = (Get-Date)
            LastUpdated = (Get-Date)
            Roles = [System.Collections.ArrayList]@('unauthenticated')
        })

        # Save to database
        Set-LoginSession -SessionID $sessionID -UserID "" -Provider "" -AuthenticationTime (Get-Date) -LogonExpires (Get-Date).AddDays(7) -AuthenticationState "unauthenticated" -UserAgent $request.UserAgent | Out-Null
        Write-Verbose "$($MyTag) New session created in database: $($sessionID)"

        # Set cookie
        $newCookie = New-Object System.Net.Cookie("PSWebSessionID", $sessionID)
        # Only set Domain for non-localhost and non-IP hosts to avoid browser rejection for host-only cookies
        $hostName = $request.Url.HostName
        if ($hostName -notmatch '^(localhost|(\d{1,3}\.){3}\d{1,3}|::1)$') {
            $newCookie.Domain = $hostName
        }
        $newCookie.Expires = (Get-Date).AddDays(7)
        $newCookie.Path = "/"
        $newCookie.HttpOnly = $true
        # Only set the Secure flag if the connection is actually HTTPS
        $newCookie.Secure = $request.IsSecureConnection

        $response.AppendCookie($newCookie)
        try { Write-Verbose "$($MyTag) Response Set-Cookie header after append: $($response.Headers['Set-Cookie'])" } catch {}
        Write-Verbose "$($MyTag) Session cookie appended to response: $($sessionID) (Secure=$($newCookie.Secure), HttpOnly=$($newCookie.HttpOnly))"

        # Redirect to the same page so the browser sends the cookie back
        Write-Verbose "$($MyTag) Redirecting to same page to ensure cookie is sent: $($request.Url.AbsoluteUri)"
        context_reponse -Response $response -StatusCode 302 -RedirectLocation $request.Url.AbsoluteUri
        return
    }
    if ($sessionCookie) {
        if (
            $request.IsSecureConnection -ne $sessionCookie.Secure -or
            -not $sessionCookie.HttpOnly
        ) {
            $sessionCookie.Secure = $request.IsSecureConnection
            $sessionCookie.HttpOnly = $true
            $sessionCookie.Path = "/"
        }
    }

    $session = Get-PSWebSessions -SessionID $sessionID
    Write-Verbose "`t$($MyTag) $(Get-Date -f 'yyyMMdd HH:mm:ss') Session: $($sessionID) UserID: $($session.UserID)"

    if ($requestedPath.StartsWith("/public", [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Verbose "$($MyTag) Handling public static file request: $($requestedPath)"
        $handled = $true
        $sanitizedPath = Sanitize-FilePath -FilePath $requestedPath.trim('/') -BaseDirectory $projectRoot
        if ($sanitizedPath.Score -eq 'pass') {
            Write-Verbose "$($MyTag) Static file sanitization passed, serving: $($sanitizedPath.Path)"
            context_reponse -Response $response -Path $sanitizedPath.Path
            return
        } else {
            Write-Verbose "$($MyTag) Static file sanitization failed: $($sanitizedPath.Message)"
            Write-PSWebHostLog -Message "`t$MyTag $SessionID 400 Bad Request: $($sanitizedPath.Message)" -Severity 'Warning' -Category 'Security'
            context_reponse -Response $response -StatusCode 400 -StatusDescription "Bad Request" -String $sanitizedPath.Message
            return
        }
    }

    if (-not $handled -and $requestedPath -eq "/" -and $httpMethod -eq "get") {
        Write-Verbose "$($MyTag) Root path redirect: '/' -> '/spa'"
        Write-PSWebHostLog -Severity 'Info' -Category 'Routing' -Message "$($MyTag) Redirecting '/' to '/spa'" -WriteHost:$Verbose.ispresent
        context_reponse -Response $response -StatusCode 302 -RedirectLocation "/spa"
        $handled = $true
    }

    if (-not $handled) {
        Write-Verbose "$($MyTag) No handler matched yet, attempting route resolution"
        $routeBaseDir = Join-Path $projectRoot "routes"
        $scriptPath = $null

        $scriptPath = Resolve-RouteScriptPath -UrlPath $requestedPath -HttpMethod $httpMethod -BaseDirectory $routeBaseDir

        if ($scriptPath) {
            Write-Verbose "$($MyTag) Route script found: $($scriptPath)"
            $securityPath = [System.IO.Path]::ChangeExtension($scriptPath, ".security.json")
            Write-Verbose "$($MyTag) Security config path: $($securityPath)"

            if (-not (Test-Path $securityPath)) {
                $defaultRoles = @("unauthenticated")
                $securityContent = @{ Allowed_Roles = $defaultRoles } | ConvertTo-Json -Compress
                Set-Content -Path $securityPath -Value $securityContent
                Write-Verbose "$($MyTag) Auto-created default security file with roles: $($defaultRoles -join ', ')"
                Write-PSWebHostLog -Severity 'Info' -Category 'Security' -Message "Auto-created default security file for $requestedPath with roles: $($defaultRoles -join ', ')"
            }

            $isAuthorized = $false
            $securityConfig = Get-Content $securityPath | ConvertFrom-Json
            Write-Verbose "$($MyTag) Security config loaded. Allowed roles: $($securityConfig.Allowed_Roles -join ', ')"

            Write-Verbose "$($MyTag) About to call Authorize-Request. Session type: $($session.GetType().FullName) IsArray: $($session -is [System.Array])"
            $isAuthorized = Authorize-Request -Session $session -SecurityPath $securityPath
            Write-Verbose "$($MyTag) Authorization result: $($isAuthorized)"

            if (-not $isAuthorized) {
                Write-Verbose "$MyTag Authorization failed - user not in allowed roles"
                Write-PSWebHostLog -Severity 'Warning' -Category 'Security' -Message "Unauthorized access to $requestedPath by user $($session.UserID) with roles: $($session.Roles -join ', ')"
                context_reponse -Response $response -StatusCode 401 -StatusDescription "Unauthorized" -String "Unauthorized"
                return
                $handled = $true
            } else {
                Write-Verbose "$MyTag Authorization passed, preparing to execute: $scriptPath"
                $scriptParams = @{
                    Context = $Context
                    SessionData = $session
                }
                [string[]]$ScriptParamNames = (get-command -Name $scriptPath).Parameters.keys
                ($scriptParams.Keys | Where-Object { $ScriptParamNames -notcontains $_ }) | ForEach-Object {
                    Write-Verbose "$MyTag Removing unexpected script parameter: $_"
                    $scriptParams.Remove($_)
                }

                if ($httpMethod -eq 'post') {
                    Write-Verbose "$MyTag Processing POST request, checking for card settings"
                    $guidPath = [System.IO.Path]::ChangeExtension($scriptPath, ".json")
                    if (Test-Path $guidPath) {
                        Write-Verbose "$MyTag Card settings config found: $guidPath"
                        $guid = (Get-Content $guidPath | ConvertFrom-Json).guid
                        if ($guid -and $session.UserID) {
                            Write-Verbose "$MyTag Retrieving card settings for GUID: $guid, UserID: $($session.UserID)"
                            $cardSettingsData = Get-CardSettings -EndpointGuid $guid -UserId $session.UserID
                            Write-Host -Message "$MyTag Retrieved -EndpointGuid $guid -UserId $($session.UserID) card settings data: $cardSettingsData"
                            if ($cardSettingsData) {
                                try {
                                    Write-Verbose "$MyTag Decompressing card settings data"
                                    $compressedBytes = [System.Convert]::FromBase64String($cardSettingsData)
                                    $memStream = New-Object System.IO.MemoryStream
                                    $memStream.Write($compressedBytes, 0, $compressedBytes.Length)
                                    $memStream.Position = 0
                                    $gzipStream = New-Object System.IO.Compression.GZipStream($memStream, [System.IO.Compression.CompressionMode]::Decompress)
                                    $streamReader = New-Object System.IO.StreamReader($gzipStream)
                                    $uncompressedJson = $streamReader.ReadToEnd()
                                    $ht = @{}
                                    ($uncompressedJson | ConvertFrom-Json).psobject.Properties|ForEach-Object{$ht[$_.Name] = $_.value}
                                    $scriptParams.CardSettings = $ht
                                    Write-Verbose "$MyTag Card settings decompressed and added to script parameters"
                                } catch {
                                    Write-Verbose "$MyTag Failed to decompress/deserialize card settings for GUID $guid"
                                    Write-PSWebHostLog -Severity 'Error' -Category 'Settings' -Message "Failed to decompress/deserialize card settings for GUID $guid" 
                                    $_
                                }
                            } else {
                                Write-Verbose "$MyTag No card settings data found for GUID: $guid"
                            }
                        } else {
                            Write-Verbose "$MyTag Skipping card settings retrieval: GUID=$guid, UserID=$($session.UserID)"
                        }
                    } else {
                        Write-Verbose "$MyTag Card settings config not found: $guidPath"
                    }
                }

                # Performance tracking - Start
                $requestID = [Guid]::NewGuid().ToString()
                $perfStartTime = Get-Date
                $logFilePath = $Global:PSWebServer.LogFilePath
                $logFileSizeBefore = if (Test-Path $logFilePath) { (Get-Item $logFilePath).Length } else { 0 }

                # Queue start record
                if ($Global:PSWebPerfQueue) {
                    & (Join-Path $Global:PSWebServer.Project_Root.Path "system\SQLITE_Perf_Table_Updater.ps1") -QueueData @{
                        Type = 'WebRequest'
                        Data = @{
                            Action = 'Start'
                            RequestID = $requestID
                            StartTime = $perfStartTime.ToString('u')
                            FilePath = $scriptPath
                            HttpMethod = $httpMethod
                            IPAddress = $request.RemoteEndPoint.Address.ToString()
                            UserAgent = $request.UserAgent
                            SessionID = $sessionID
                            LogFileSizeBefore = $logFileSizeBefore
                        }
                    }
                }

                if ($Async.ispresent) {
                    Write-Verbose "$MyTag Executing route script asynchronously"
                    Invoke-ContextRunspace -Context $Context -ScriptPath $scriptPath -SessionID $sessionID
                } else {
                    Write-Verbose "$MyTag Executing route script synchronously: $($httpMethod.ToUpper()) $scriptPath"
                    if ($PSBoundParameters.Verbose.ispresent) {
                        $scriptParams['Verbose'] = $true
                    }
                    try{
                        & $scriptPath @scriptParams
                        $scriptStatusCode = 200
                    }
                    catch{
                        Write-PSWebHostLog -Severity 'Error' -Category 'Routing' -Message "$MyTag Error executing route script: $($_.Exception.Message + "`n" + $_.InvocationInfo.PositionMessage)" -Data @{ ScriptPath = $scriptPath; SessionID = $sessionID; PositionMessage = $_.InvocationInfo.PositionMessage; Message = $_.Exception.Message } -WriteHost
                        context_reponse -Response $response -StatusCode 500 -StatusDescription "Internal Server Error" -String "Internal Server Error"
                        $scriptStatusCode = 500
                    }
                    Write-Verbose "$MyTag Route script execution completed"
                }

                # Performance tracking - Complete
                $perfEndTime = Get-Date
                $executionTimeMicroseconds = [long](($perfEndTime - $perfStartTime).TotalMilliseconds * 1000)
                $logFileSizeAfter = if (Test-Path $logFilePath) { (Get-Item $logFilePath).Length } else { 0 }

                # Queue complete record
                if ($Global:PSWebPerfQueue) {
                    $finalStatusCode = if ($scriptStatusCode) { $scriptStatusCode } else { $response.StatusCode }
                    $finalStatusText = if ($response.StatusDescription) { $response.StatusDescription } else { $null }

                    & (Join-Path $Global:PSWebServer.Project_Root.Path "system\SQLITE_Perf_Table_Updater.ps1") -QueueData @{
                        Type = 'WebRequest'
                        Data = @{
                            Action = 'Complete'
                            RequestID = $requestID
                            EndTime = $perfEndTime.ToString('u')
                            UserID = if ($session.UserID) { $session.UserID } else { '' }
                            AuthenticationProvider = if ($session.Provider) { $session.Provider } else { '' }
                            ExecutionTimeMicroseconds = $executionTimeMicroseconds
                            LogFileSizeBefore = $logFileSizeBefore
                            LogFileSizeAfter = $logFileSizeAfter
                            StatusCode = $finalStatusCode
                            StatusText = $finalStatusText
                        }
                    }
                }
                $handled = $true
            }
        }
    }

    if (-not $handled) {
        Write-Verbose "$MyTag No route handler matched, checking for default handlers"
        $DefaultFavicon = Join-Path $PSWebServer.Project_Root.Path "public/favicon.ico"
        if ($requestedPath -eq "/favicon.ico") {
            Write-Verbose "$MyTag Serving favicon: $DefaultFavicon"
            context_reponse -Response $response -Path $DefaultFavicon
        } else {
            Write-Verbose "$MyTag No handler found for request, returning 404: $requestedPath"
            Write-PSWebHostLog -Severity 'Info' -Category 'Routing' -Message "$MyTag 404 Not Found: $requestedPath from $($request.RemoteEndPoint)"
            context_reponse -Response $response -StatusCode 404 -String "404 Not Found" -ContentType "text/plain"
        }
    }
}

function Write-PSWebHostLog {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true)] [string]$Message,
        [Parameter(Mandatory=$true)] [ValidateSet('Critical', 'Error', 'Warning', 'Info', 'Verbose', 'Debug')]
        [string]$Severity,
        [Parameter(Mandatory=$true)] [string]$Category,
        [hashtable]$Data,
        [string]$UserID = $Session.UserID,
        [string]$SessionID = $SessionID,
        [switch]$WriteHost,
        [string]$State = 'Unspecified',
        [string]$ForeGroundColor,
        [string]$BackGroundColor = $host.UI.RawUI.BackgroundColor
    )
    if ($WriteHost.IsPresent) {
        if ($ForeGroundColor -eq '') {
            if ($Severity -eq 'Critical' -or $Severity -eq 'Error') {
                $ForeGroundColor = 'Red'
            } elseif ($Severity -eq 'Warning') {
                $ForeGroundColor = 'Yellow'
            } elseif ($Severity -eq 'Info') {
                $ForeGroundColor = 'Green'
            } else {
                $ForeGroundColor = $host.UI.RawUI.ForegroundColor
            }
        }
    }
    $date = Get-Date
    $utcTime = $date.ToUniversalTime().ToString('o')
    $localTime = $date.ToString('o')
    $escapedMessage = [regex]::Escape($Message)
    $dataString = ""
    if ($Data) {
        $json = $Data | ConvertTo-Json -Compress
        if ($json.Length -gt 1000) {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $ms = New-Object System.IO.MemoryStream
            $gs = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Compress)
            $gs.Write($bytes, 0, $bytes.Length)
            $gs.Close() # Closing the GZipStream also flushes it.
            $compressedBytes = $ms.ToArray()
            $ms.Close()
            $dataString = [System.Convert]::ToBase64String($compressedBytes)
        } else {
            $dataString = $json
        }
    }
    $logEntry = "$utcTime`t$localTime`t$Severity`t$Category`t$escapedMessage`t$SessionID`t$UserID`t$dataString"
    $global:PSWebHostLogQueue.Enqueue($logEntry)

    $eventGuid = [Guid]::NewGuid().ToString()
    if ($null -eq $global:PSWebServer.events) {
        $global:PSWebServer.events = [hashtable]::Synchronized(@{})
    }
    if ($null -eq $global:PSWebServer.eventGuid) {
        $global:PSWebServer.eventGuid = [hashtable]::Synchronized(@{})
    }
    $global:PSWebServer.events[$eventGuid] = @{
        guid = $eventGuid
        Date = $date
        Message = $Message
        Severity = $Severity
        Category = $Category
        state = 'Completed'
        UserID = $UserID
        Provider = $Category
        SessionID = $SessionID
        Data = @{ Message = $Message; Severity = $Severity; Details = $Data }
        CompletionDate = Get-Date
    }
    $global:PSWebServer.eventGuid[$date] = $eventGuid
    if ($WriteHost.IsPresent) {
        $Callstack = @()
        Get-PSCallStack | Select-Object -Skip 1 | ForEach-Object{
                if (($_.Command[0] -match '\w') -or ($_.ScriptName -and $_.ScriptName -ne '')) {
                    $Callstack += [pscustomobject]@{ 
                        Command = $_.Command
                        ScriptName = $_.ScriptName
                        FunctionName = $_.FunctionName
                        Line = $_.ScriptLineNumber
                        Arguments = $_.Arguments
                    }
                }
            }
        Write-Host ($(($Callstack | Format-List -Property *|Out-String).trim('\s'))) -ForegroundColor $ForeGroundColor -BackgroundColor $BackGroundColor
        Write-Host $logEntry
    }
}

# Standardize result objects and logging for scripts to use instead of throwing/exiting
function New-PSWebHostResult {
    [CmdletBinding()]
    param (
        [int]$ExitCode = 0,
        [string]$Message = '',
        [ValidateSet('Critical','Error','Warning','Info','Verbose','Debug')] [string]$Severity = 'Info',
        [string]$Category = 'General',
        [hashtable]$Details
    )

    $result = [pscustomobject]@{
        ExitCode = $ExitCode
        Message  = $Message
        Severity = $Severity
        Category = $Category
        Details  = $Details
        Timestamp = (Get-Date).ToString('o')
    }

    try {
        Write-PSWebHostLog -Message $Message -Severity $Severity -Category $Category -Data $Details -WriteHost:$false
    } catch {
        # Best-effort logging; don't throw.
    }

    return $result
}

function Read-PSWebHostLog {
    [cmdletbinding()]
    param (
        [datetime]$StartTime = (Get-Date).AddDays(-1),
        [datetime]$EndTime = (Get-Date),
        [string]$Category = "*",
        [string]$Severity = "*"
    )
    $baseDirectory = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data"
    $logFile = Join-Path $baseDirectory "Logs" "log.tsv"
    if (-not (Test-Path $logFile)) { Write-Warning "Log file not found at $logFile"; return }
    Import-Csv -Path $logFile -Delimiter "`t" -Header "Date", "Severity", "Category", "Message", "Data" | Where-Object {
        $_.Date -as [datetime] -ge $StartTime -and $_.Date -as [datetime] -le $EndTime -and $_.Category -like $Category -and $_.Severity -like $Severity
    }
}

function context_reponse {
    [CmdletBinding(DefaultParameterSetName = 'String')]
    param(
        [Parameter(Mandatory=$true)] [System.Net.HttpListenerResponse]$Response,
        [Parameter(Mandatory=$false, ParameterSetName='String')] [string]$String,
        [Parameter(Mandatory=$false, ParameterSetName='Bytes')] [byte[]]$Byte,
        [Parameter(Mandatory=$false, ParameterSetName='Path')] [string]$Path,
        [Parameter()] [string]$ContentType,
        [Parameter()] [int]$StatusCode = 200,
        [Parameter()] [string]$StatusDescription,
        [Parameter()] [System.Collections.IDictionary]$Headers,
        [Parameter()] [System.Net.CookieCollection]$Cookies,
        [Parameter()] [string]$RedirectLocation,
        [Parameter()] [System.Text.Encoding]$ContentEncoding = [System.Text.Encoding]::UTF8
    )

    try {
        $Response.StatusCode = $StatusCode
        if ($PSBoundParameters.ContainsKey('StatusDescription')) { $Response.StatusDescription = $StatusDescription }
        if ($PSBoundParameters.ContainsKey('Headers')) { foreach ($key in $Headers.Keys) { $Response.AddHeader($key, $Headers[$key]) } }
        if ($PSBoundParameters.ContainsKey('Cookies')) { $Response.Cookies.Add($Cookies) }
        if ($PSBoundParameters.ContainsKey('RedirectLocation')) {
            Write-Verbose "Redirecting to: $($RedirectLocation) with status code $($StatusCode)"
            $Response.Redirect($RedirectLocation)
        }

        $finalContentType = $ContentType
        if ($PSCmdlet.ParameterSetName -eq 'Path' -and -not $PSBoundParameters.ContainsKey('ContentType')) {
            $extension = [System.IO.Path]::GetExtension($Path)
            if ($Global:PSWebServer.config.MimeTypes.psobject.Properties[$extension]) {
                $finalContentType = $Global:PSWebServer.config.MimeTypes.psobject.Properties[$extension].Value
            } else {
                $finalContentType = 'application/octet-stream'
            }
        }
        if ($finalContentType) { $Response.ContentType = $finalContentType }

        $contentBytes = $null
        switch ($PSCmdlet.ParameterSetName) {
            'String' {
                $contentBytes = $ContentEncoding.GetBytes($String)
                $Response.ContentEncoding = $ContentEncoding
            }
            'Bytes'  { $contentBytes = $Byte }
            'Path'   {
                if (Test-Path -Path $Path -PathType Leaf) {
                    $contentBytes = [System.IO.File]::ReadAllBytes($Path)
                } else {
                    $Response.StatusCode = 404
                    $Response.StatusDescription = "Not Found"
                    $errorMessage = "File not found at path: $($Path -replace ([regex]::Escape($global:PSWebServer.Project_Root.Path)),'')"
                    $contentBytes = $ContentEncoding.GetBytes($errorMessage)
                    $Response.ContentType = 'text/plain'
                }
            }
        }

        if ($null -ne $contentBytes) {
            $Response.ContentLength64 = $contentBytes.Length
            $Response.OutputStream.Write($contentBytes, 0, $contentBytes.Length)
        } else {
            $Response.ContentLength64 = 0
        }
    } catch {
        Write-Error "Failed to build response. Error: $_ "
        if (-not $Response.HeadersSent) {
            $Response.StatusCode = 500
            $Response.StatusDescription = "Internal Server Error"
            $errorBytes = [System.Text.Encoding]::UTF8.GetBytes("Internal Server Error: $_ ")
            $Response.ContentLength64 = $errorBytes.Length
            $Response.OutputStream.Write($errorBytes, 0, $errorBytes.Length)
        }
    }
}

#region Event Management


function Start-PSWebHostEvent {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true)] [string]$Provider, # e.g., the function name
        [Parameter(Mandatory=$true)] [string]$UserID,
        [hashtable]$Data,
        [scriptblock]$ScriptBlock,
        [validateset('Job','Threadjob')]
        [string]$JobType
    )

    $guid = [Guid]::NewGuid().ToString()
    $eventinstance = @{
        guid     = $guid
        Date     = Get-Date
        state    = 'Active'
        UserID   = $UserID
        Provider = $Provider
        Data     = $Data
        ScriptBlock = $ScriptBlock
    }
    $global:PSWebServer.events[$guid] = $eventinstance
    return $guid
}

function Complete-PSWebHostEvent {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true)] [string]$guid,
        [hashtable]$Data
    )
    if ($global:PSWebServer.events.ContainsKey($guid)) {
        $eventinstance = $global:PSWebServer.events[$guid]
        $eventinstance.state = 'Completed'
        $eventinstance.CompletionDate = Get-Date
        if ($PSBoundParameters.ContainsKey('Data')) {
            $eventinstance.Data = $Data
        }
        $global:PSWebServer.events[$guid] = $eventinstance
    } else {
        Write-Warning "Event with GUID $guid not found for completion."
    }
}

function Get-PSWebHostEvents {
    [cmdletbinding()]
    param (
        [string]$UserID
    )

    # Placeholder for role-based access. In a real app, get this from session/DB.
    $isAdministrator = $true # or $false for testing. For now, let everyone see everything.

    $allEvents = $global:PSWebServer.events.Values

    if ($isAdministrator) {
        return $allEvents
    } else {
        return $allEvents | Where-Object { $_.UserID -eq $UserID }
    }
}

#endregion

function Sync-SessionStateToDatabase {
    [cmdletbinding()]
    param()
    foreach ($sessionID in ($global:PSWebSessions.Keys|Where-Object{$_ -match '\w'})) {
        $session = $global:PSWebSessions[$sessionID]
        if ($session.AuthenticationState -notmatch '\w' -and ((get-date) -lt $session.AuthTokenExpiration)) {
            $session.AuthenticationState = 'Authenticated'
        }
        if ($session.LastUpdated) {
            $dbSession = Get-LoginSession -SessionID $sessionID
            if ($dbSession) {
                $dbLastUpdated = [datetimeoffset]::FromUnixTimeSeconds([int64]$dbSession.AuthenticationTime).DateTime
                if ($session.LastUpdated -gt $dbLastUpdated) {
                    Set-LoginSession -SessionID $sessionID -UserID $session.UserID -Provider $session.Provider -AuthenticationTime $session.LastUpdated -AuthenticationState $session.AuthenticationState -LogonExpires $session.AuthTokenExpiration -UserAgent $session.UserAgent | Out-Null
                }
            }
        }
    }
}
