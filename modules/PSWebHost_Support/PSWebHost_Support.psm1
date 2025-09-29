# PSWebHost_Support.psm1

# Global hashtable for session management
if ($null -eq $global:PSWebSessions) {$global:PSWebSessions = [hashtable]::Synchronized(@{})}

#Remember to update the psd1 manifest.

function Get-RequestBody {
    param (
        [System.Net.HttpListenerRequest]$Request
    )
    if ($Request.HasEntityBody) {
        $reader = $null
        try {
            $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
            return $reader.ReadToEnd()
        } catch {
            Write-Error "Failed to read request body. Error: $_ "
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
    $memStream = $null
    $gzipStream = $null
    try {
        $inputBytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
        $memStream = New-Object System.IO.MemoryStream
        $gzipStream = New-Object System.IO.Compression.GZipStream($memStream, [System.IO.Compression.CompressionMode]::Compress)
        $gzipStream.Write($inputBytes, 0, $inputBytes.Length)
        $gzipStream.Close() # Closing the GZipStream also flushes it.
        $compressedBytes = $memStream.ToArray()
        return [System.Convert]::ToBase64String($compressedBytes)
    } catch {
        Write-Error "Failed to compress string. Error: $_ "
        return $null
    } finally {
        if ($gzipStream) { $gzipStream.Dispose() }
        if ($memStream) { $memStream.Dispose() }
    }
}

function Set-PSWebSession {
    param (
        [string]$SessionID,
        [string]$UserID,
        [string[]]$Roles,
        [string[]]$RemoveRoles,
        [string]$Provider,
        [System.Net.HttpListenerRequest]$Request
    )

    $sessionData = Get-PSWebSessions -SessionID $SessionID

    if ($UserID) { $sessionData.UserID = $UserID }
    if ($Roles) { $sessionData.Roles = @($Roles) }
    if ($RemoveRoles) { $sessionData.Roles.RemoveAll( { param($item) $RemoveRoles -contains $item } ) }
    if ($Request) { $sessionData.UserAgent = $Request.UserAgent }
    if ($Provider) { $sessionData.Provider = $Provider }
    
    $sessionData.AuthTokenExpiration = (Get-Date).AddDays(7)
    $sessionData.LastUpdated = Get-Date

    Set-LoginSession -SessionID $SessionID -UserID $sessionData.UserID -Provider $sessionData.Provider -AuthenticationTime $sessionData.LastUpdated -LogonExpires $sessionData.AuthTokenExpiration -UserAgent $sessionData.UserAgent

    Write-Verbose "Updated session data for UserID: $UserID" -Verbose
}

function Get-PSWebSessions {
    param (
        [string]$SessionID
    )
    if ($null -eq $global:PSWebSessions[$SessionID]) {
        # Try to load from DB
        $loginSession = Get-LoginSession -SessionID $SessionID
        if ($loginSession) {
            $roles = [System.Collections.ArrayList]@()
            if ($loginSession.AuthenticationState -eq 'completed' -and $loginSession.UserID -ne 'pending') {
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
            # Not in DB, create new
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
    return $global:PSWebSessions[$SessionID]    
}

function Remove-PSWebSession {
    param (
        [string]$SessionID
    )
    if ($global:PSWebSessions.ContainsKey($SessionID)) {
        $global:PSWebSessions.Remove($SessionID)
    }
    Remove-LoginSession -SessionID $SessionID
}


function Validate-UserSession {
    [cmdletbinding()]
    param (
        [System.Net.HttpListenerContext]$Context,
        [string]$SessionID = $Context.Request.Cookies["PSWebSessionID"].Value
    )
    [switch]$Verbose = $PSBoundParameters['Verbose']
    $SessionData = Get-PSWebSessions -SessionID $SessionID

    if (-not $SessionID) {
        if ($Verbose.IsPresent){Write-Verbose -Message "`t[Validate-UserSession] No session ID provided."}
        return $false 
    }

    if (-not $SessionData -or -not $SessionData.Roles -or -not ($SessionData.Roles -contains "authenticated")) {
        if ($Verbose.IsPresent){Write-Verbose -Message "`t[Validate-UserSession] User is not authenticated.`n`t`tSessionID: $(($SessionID|Inspect-Object -Depth 4| ConvertTo-YAML) -split '
' -notmatch '^	*Type:' -join "`n`t`t`t")"}
        return $false
    }

    if ($SessionData.AuthTokenExpiration -lt (Get-Date)) {
        Write-PSWebHostLog -Severity 'Info' -Category 'Session' -Message "Expired auth token for SessionID '$SessionID'." -WriteHost:$Verbose.ispresent
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
        Set-LoginSession -SessionID $SessionID -UserID $SessionData.UserID -Provider $SessionData.Provider -AuthenticationTime $SessionData.LastUpdated -LogonExpires $SessionData.AuthTokenExpiration -UserAgent $requestUserAgent
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
        $HostUIQueue = $HostUIQueue
    )

    try{$global:PSWebHostLogQueue = $using:global:PSWebHostLogQueue}catch{}
    try{$global:PSWebServer       = $using:global:PSWebServer      }catch{}
    try{$global:PSWebSessions     = $using:global:PSWebSessions    }catch{}

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

    Write-Verbose "[Process-HttpRequest] $httpMethod $requestedPath"
    $sessionCookie = $request.Cookies["PSWebSessionID"]
    if ($sessionCookie) {
        $sessionID = $sessionCookie.Value
    
    } else {
        $sessionID = [Guid]::NewGuid().ToString()
        $newCookie = New-Object System.Net.Cookie("PSWebSessionID", $sessionID)
        $newCookie.Domain = $request.Url.HostName
        $newCookie.Expires = (Get-Date).AddDays(7)
        $newCookie.Path = "/"
        $newCookie.HttpOnly = $true
        # Only set the Secure flag if the connection is actually HTTPS
        $newCookie.Secure = $request.IsSecureConnection
        
        $response.AppendCookie($newCookie)
        # Also add the cookie to the current request so it's available immediately
        $request.Cookies.Add($newCookie)
        $sessionCookie = $newCookie

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
    Write-Verbose "`t[Process-HttpRequest] Session: $($sessionID) UserID: $($session.UserID)"

    if ($requestedPath.StartsWith("/public", [System.StringComparison]::OrdinalIgnoreCase)) {
        $handled = $true
        $sanitizedPath = Sanitize-FilePath -FilePath $requestedPath.trim('/') -BaseDirectory $projectRoot
        if ($sanitizedPath.Score -eq 'pass') {
            context_reponse -Response $response -Path $sanitizedPath.Path
            return
        } else {
            Write-PSWebHostLog -Message "`t[Process-HttpRequest]  $SessionID 400 Bad Request: $($sanitizedPath.Message)" -Severity 'Warning' -Category 'Security'
            context_reponse -Response $response -StatusCode 400 -StatusDescription "Bad Request" -String $sanitizedPath.Message
            return
        }
    }

    if (-not $handled -and $requestedPath -eq "/" -and $httpMethod -eq "get") {
        context_reponse -Response $response -StatusCode 302 -RedirectLocation "/spa"
        $handled = $true
    }

    if (-not $handled) {
        $routeBaseDir = Join-Path $projectRoot "routes"
        $scriptPath = $null

        function Resolve-RouteScriptPath {
            param ([string]$UrlPath, [string]$HttpMethod, [string]$BaseDirectory)
            $trimmedUrlPath = $UrlPath.Trim('/')
            $potentialPath = Join-Path $BaseDirectory "$trimmedUrlPath/$HttpMethod.ps1"
            if (Test-Path $potentialPath -PathType Leaf) { return $potentialPath } else { return $null }
        }

        $scriptPath = Resolve-RouteScriptPath -UrlPath $requestedPath -HttpMethod $httpMethod -BaseDirectory $routeBaseDir

        if ($scriptPath) {
            $securityPath = [System.IO.Path]::ChangeExtension($scriptPath, ".security.json")

            if (-not (Test-Path $securityPath)) {
                $defaultRoles = @("unauthenticated")
                $securityContent = @{ Allowed_Roles = $defaultRoles } | ConvertTo-Json -Compress
                Set-Content -Path $securityPath -Value $securityContent
                Write-PSWebHostLog -Severity 'Info' -Category 'Security' -Message "Auto-created default security file for $requestedPath with roles: $($defaultRoles -join ', ')"
            }

            $isAuthorized = $false
            $securityConfig = Get-Content $securityPath | ConvertFrom-Json
            if ($securityConfig.Allowed_Roles) {
                $userRoles = $session.Roles
                foreach ($allowedRole in $securityConfig.Allowed_Roles) {
                    if ($userRoles -contains $allowedRole) {
                        $isAuthorized = $true
                        break
                    }
                }
            }

            if (-not $isAuthorized) {
                Write-PSWebHostLog -Severity 'Warning' -Category 'Security' -Message "Unauthorized access to $requestedPath"
                context_reponse -Response $response -StatusCode 401 -StatusDescription "Unauthorized" -String "Unauthorized"
                return
                $handled = $true
            } else {
                $scriptParams = @{
                    Context = $Context
                    SessionData = $session
                }

                if ($httpMethod -eq 'post') {
                    $guidPath = [System.IO.Path]::ChangeExtension($scriptPath, ".json")
                    if (Test-Path $guidPath) {
                        $guid = (Get-Content $guidPath | ConvertFrom-Json).guid
                        if ($guid -and $session.UserID) {
                            $cardSettingsData = Get-CardSettings -EndpointGuid $guid -UserId $session.UserID
                            if ($cardSettingsData) {
                                try {
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
                                } catch {
                                    Write-PSWebHostLog -Severity 'Error' -Category 'Settings' -Message "Failed to decompress/deserialize card settings for GUID $guid" 
                                    $_
                                }
                            }
                        }
                    }
                }

                if ($Async.ispresent) {
                    Invoke-ContextRunspace -Context $Context -ScriptPath $scriptPath -SessionID $sessionID
                } else {
                    Write-Verbose "$SessionID $httpMethod $scriptPath"
                    & $scriptPath @scriptParams
                }
                $handled = $true
            }
        }
    }

    if (-not $handled) {
        $DefaultFavicon = Join-Path $PSWebServer.Project_Root.Path "public/favicon.ico"
        if ($requestedPath -eq "/favicon.ico") {
            context_reponse -Response $response -Path $DefaultFavicon
        } else {
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
        [string]$State = 'Unspecified'
    )
    $date = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
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
    $logEntry = "$date`t$Severity`t$Category`t$escapedMessage`t$SessionID`t$UserID`t$dataString"
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
        Write-Host ($(($Callstack | Format-List -Property *|Out-String).trim('\s')))
        Write-Host $logEntry
    }
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
        if ($session.LastUpdated) {
            $dbSession = Get-LoginSession -SessionID $sessionID
            if ($dbSession) {
                $dbLastUpdated = [datetimeoffset]::FromUnixTimeSeconds([int64]$dbSession.AuthenticationTime).DateTime
                if ($session.LastUpdated -gt $dbLastUpdated) {
                    Set-LoginSession -SessionID $sessionID -UserID $session.UserID -Provider $session.Provider -AuthenticationTime $session.LastUpdated -LogonExpires $session.AuthTokenExpiration
                }
            }
        }
    }
}
