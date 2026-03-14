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

function Backup-ConfigurationFile {
    <#
    .SYNOPSIS
        Backs up a configuration file if it has changed since the last backup

    .DESCRIPTION
        When a configuration file is read, this function:
        1. Checks for the most recent backup of the file
        2. Compares LastWriteTime between current file and most recent backup
        3. If different (or no backup exists), creates a timestamped copy
        4. Preserves relative subfolder path in the backup directory

    .PARAMETER ConfigFilePath
        Full path to the configuration file to backup

    .PARAMETER ProjectRoot
        Root directory of the project (defaults to $Global:PSWebServer.Project_Root.Path)

    .EXAMPLE
        Backup-ConfigurationFile -ConfigFilePath "C:\SC\PsWebHost\apps\MyApp\app.yaml"

    .EXAMPLE
        Backup-ConfigurationFile -ConfigFilePath $securityPath -ProjectRoot $projectRoot
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigFilePath,

        [string]$ProjectRoot = $Global:PSWebServer.Project_Root.Path
    )

    $MyTag = "[Backup-ConfigurationFile]"

    # Validate config file exists
    if (-not (Test-Path $ConfigFilePath)) {
        Write-Verbose "$MyTag Configuration file not found: $ConfigFilePath"
        return
    }

    # Only backup specific configuration file types
    $extension = [System.IO.Path]::GetExtension($ConfigFilePath)
    if ($extension -notin @('.yaml', '.yml', '.json')) {
        Write-Verbose "$MyTag Skipping backup for non-config file: $ConfigFilePath"
        return
    }

    try {
        # Get current file info
        $currentFile = Get-Item $ConfigFilePath
        $currentLastWrite = $currentFile.LastWriteTime

        # Determine backup directory
        $backupRoot = Join-Path $ProjectRoot "backups\config"

        # Calculate relative path from project root
        $relativePath = $ConfigFilePath.Replace($ProjectRoot, '').TrimStart('\', '/')
        $relativeDir = Split-Path $relativePath -Parent
        $fileName = Split-Path $relativePath -Leaf

        # Create backup subdirectory preserving relative path
        $backupDir = Join-Path $backupRoot $relativeDir
        if (-not (Test-Path $backupDir)) {
            New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
            Write-Verbose "$MyTag Created backup directory: $backupDir"
        }

        # Find most recent backup for this file
        $filePattern = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $existingBackups = Get-ChildItem -Path $backupDir -Filter "$filePattern*$extension" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending

        $needsBackup = $false

        if ($existingBackups.Count -eq 0) {
            # No backups exist
            $needsBackup = $true
            Write-Verbose "$MyTag No existing backups found for: $fileName"
        }
        else {
            # Check if most recent backup has different LastWriteTime
            $mostRecentBackup = $existingBackups[0]

            # Extract timestamp from backup filename (format: filename__yyyyMMddHHmmss.ext)
            # We need to check the actual content timestamp, not the backup file's timestamp
            # Read the backup's original timestamp from its LastWriteTime or embedded in name
            if ($mostRecentBackup.Name -match '__(\d{14})\.') {
                $backupTimestamp = [datetime]::ParseExact($matches[1], 'yyyyMMddHHmmss', $null)

                # Compare timestamps (allow 1 second tolerance for file system precision)
                $timeDiff = [Math]::Abs(($currentLastWrite - $backupTimestamp).TotalSeconds)

                if ($timeDiff -gt 1) {
                    $needsBackup = $true
                    Write-Verbose "$MyTag File modified since last backup. Current: $currentLastWrite, Backup: $backupTimestamp"
                }
                else {
                    Write-Verbose "$MyTag File unchanged since last backup: $fileName"
                }
            }
            else {
                # Old backup format or first backup - create new one
                $needsBackup = $true
                Write-Verbose "$MyTag Existing backup has old format, creating new backup"
            }
        }

        # Create timestamped backup if needed
        if ($needsBackup) {
            $timestamp = $currentLastWrite.ToString('yyyyMMddHHmmss')
            $backupFileName = "$filePattern`__$timestamp$extension"
            $backupPath = Join-Path $backupDir $backupFileName

            # Copy file to backup location
            Copy-Item -Path $ConfigFilePath -Destination $backupPath -Force

            # Preserve original LastWriteTime in the backup
            (Get-Item $backupPath).LastWriteTime = $currentLastWrite

            Write-Verbose "$MyTag Created backup: $backupPath"
            Write-PSWebHostLog -Severity 'Info' -Category 'Config' -Message "Backed up configuration file: $relativePath -> $backupFileName"

            # Cleanup old backups (keep last 10)
            $allBackupsForFile = Get-ChildItem -Path $backupDir -Filter "$filePattern*$extension" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending

            if ($allBackupsForFile.Count -gt 10) {
                $toDelete = $allBackupsForFile | Select-Object -Skip 10
                foreach ($oldBackup in $toDelete) {
                    Remove-Item $oldBackup.FullName -Force
                    Write-Verbose "$MyTag Removed old backup: $($oldBackup.Name)"
                }
            }
        }
    }
    catch {
        Write-Warning "$MyTag Failed to backup configuration file $ConfigFilePath : $($_.Exception.Message)"
        Write-PSWebHostLog -Severity 'Warning' -Category 'Config' -Message "Failed to backup config file $ConfigFilePath : $($_.Exception.Message)"
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
        # Backup configuration file if it has changed
        Backup-ConfigurationFile -ConfigFilePath $SecurityPath

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

    if ($UserID) {
        $sessionData.UserID = $UserID
        # Look up user's configured roles from database
        $userRoles = Get-PSWebHostRole -UserID $UserID
        if ($userRoles) {
            Write-Verbose "$MyTag Found roles for UserID $UserID`: $($userRoles -join ', ')"
            if (-not $Roles) {
                # No explicit roles passed, use database roles
                $Roles = $userRoles
            } else {
                # Merge passed roles with database roles
                $Roles = @($Roles) + @($userRoles) | Select-Object -Unique
            }
        }
    }
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

    # Ensure PSWebSessions exists (may not be initialized in runspace)
    if ($null -eq $global:PSWebSessions) {
        Write-Warning "$MyTag PSWebSessions global not initialized - runspace issue?"
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
    return [hashtable]$returnValue
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

function context_response {
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
        [Parameter()] [System.Text.Encoding]$ContentEncoding = [System.Text.Encoding]::UTF8,
        [Parameter()] [int]$CacheDuration = 0
    )

    try {
        # Check if the response is already closed or client disconnected
        if ($null -eq $Response -or $null -eq $Response.OutputStream) {
            Write-Verbose "Response object is null or output stream is closed, client may have disconnected"
            return
        }

        $Response.StatusCode = $StatusCode
        if ($PSBoundParameters.ContainsKey('StatusDescription')) { $Response.StatusDescription = $StatusDescription }
        if ($PSBoundParameters.ContainsKey('Headers')) { foreach ($key in $Headers.Keys) { $Response.AddHeader($key, $Headers[$key]) } }
        if ($PSBoundParameters.ContainsKey('Cookies')) { $Response.Cookies.Add($Cookies) }
        if ($PSBoundParameters.ContainsKey('RedirectLocation')) {
            Write-Verbose "Redirecting to: $($RedirectLocation) with status code $($StatusCode)"
            $Response.Redirect($RedirectLocation)
        }

        # Add cache control headers if CacheDuration is specified
        if ($CacheDuration -gt 0) {
            $cacheControl = "public, max-age=$CacheDuration, stale-while-revalidate=$([math]::Min($CacheDuration * 2, 1800)), stale-if-error=$([math]::Min($CacheDuration * 3, 3600))"
            $Response.AddHeader("Cache-Control", $cacheControl)
            $expiresDate = (Get-Date).AddSeconds($CacheDuration).ToUniversalTime().ToString("r")
            $Response.AddHeader("Expires", $expiresDate)
            # Add ETag for cache validation
            $etag = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$StatusCode-$((Get-Date).Ticks)"))
            $Response.AddHeader("ETag", "`"$etag`"")
        } elseif ($CacheDuration -eq 0) {
            # Explicitly disable caching
            $Response.AddHeader("Cache-Control", "no-store, no-cache, must-revalidate")
            $Response.AddHeader("Pragma", "no-cache")
            $Response.AddHeader("Expires", "0")
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
    } catch [System.Net.HttpListenerException] {
        # Client disconnected or network error - this is expected, just log and return
        $errorCode = $_.Exception.ErrorCode
        if ($errorCode -eq 64 -or $errorCode -eq 1229) {
            # Error 64 = "The specified network name is no longer available"
            # Error 1229 = "An operation was attempted on a nonexistent network connection"
            Write-Verbose "Client disconnected during response: $($_.Exception.Message)"
        } else {
            Write-PSWebHostLog -Severity 'Warning' -Category 'Response' -Message "Network error during response: $($_.Exception.Message) (ErrorCode: $errorCode)"
        }
    } catch [System.InvalidOperationException] {
        # Response already sent or stream closed
        if ($_.Exception.Message -match 'response has been submitted|stream.*closed') {
            Write-Verbose "Response already sent or stream closed: $($_.Exception.Message)"
        } else {
            Write-PSWebHostLog -Severity 'Error' -Category 'Response' -Message "Invalid operation in context_response: $($_.Exception.Message)"
        }
    } catch {
        # Other errors - try to send error response only if possible
        $errorMessage = "Failed to build response. Error: $_ "
        Write-PSWebHostLog -Severity 'Error' -Category 'Response' -Message $errorMessage

        try {
            # Only attempt to send error response if headers haven't been sent and stream is available
            if (-not $Response.HeadersSent -and $null -ne $Response.OutputStream) {
                $Response.StatusCode = 500
                $Response.StatusDescription = "Internal Server Error"
                $errorBytes = [System.Text.Encoding]::UTF8.GetBytes("Internal Server Error: $_ ")
                $Response.ContentLength64 = $errorBytes.Length
                $Response.OutputStream.Write($errorBytes, 0, $errorBytes.Length)
            }
        } catch {
            # If we can't send the error response, just log it
            Write-Verbose "Unable to send error response (client may have disconnected): $($_.Exception.Message)"
        }
    }
}

function Invoke-HttpRequestPublic {
    <#
    .SYNOPSIS
        Handles public static file requests from /public/ and /apps/[appname]/public/ paths.

    .DESCRIPTION
        Serves static files without session requirements. Uses MIME types from config.
        Handles both project root /public/ and app /apps/[appname]/public/ paths consistently.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context
    )

    $MyTag = '[Invoke-HttpRequestPublic]'
    $request = $Context.Request
    $response = $Context.Response
    $requestedPath = $request.Url.LocalPath
    $projectRoot = $Global:PSWebServer.Project_Root.Path

    Write-Verbose "$MyTag Handling public static file request: $requestedPath"

    # Determine base directory and file path based on URL pattern
    if ($requestedPath -match '^/apps/(?<appname>[a-zA-Z0-9_-]+)/public/(?<filepath>.+)$') {
        # App public file: /apps/[appname]/public/...
        $appName = $matches.appname
        $filePath = $matches.filepath

        if ($Global:PSWebServer.Apps -and $Global:PSWebServer.Apps.ContainsKey($appName)) {
            $appInfo = $Global:PSWebServer.Apps[$appName]
            $baseDirectory = $appInfo.PublicPath
            Write-Verbose "$MyTag App public file: app=$appName, file=$filePath, base=$baseDirectory"
            # For app public files, baseDirectory is already the public folder, so don't prepend "public/"
            $filePathToSanitize = $filePath
        } else {
            Write-Verbose "$MyTag App '$appName' not found"
            context_response -Response $response -StatusCode 404 -StatusDescription "Not Found" -String "App not found"
            return
        }
    } elseif ($requestedPath -match '^/public/(?<filepath>.+)$') {
        # Project root public file: /public/...
        $filePath = $matches.filepath
        $baseDirectory = $projectRoot
        Write-Verbose "$MyTag Project public file: $filePath"
        # For project root, baseDirectory is project root, so we need to prepend "public/"
        $filePathToSanitize = "public/$filePath"
    } else {
        Write-Verbose "$MyTag Invalid public path pattern: $requestedPath"
        context_response -Response $response -StatusCode 400 -StatusDescription "Bad Request" -String "Invalid path"
        return
    }

    # Sanitize and resolve file path
    $sanitizedPath = Sanitize-FilePath -FilePath $filePathToSanitize -BaseDirectory $baseDirectory

    if ($sanitizedPath.Score -ne 'pass') {
        Write-Verbose "$MyTag Sanitization failed: $($sanitizedPath.Message)"
        Write-PSWebHostLog -Severity 'Warning' -Category 'Security' -Message "$MyTag Path sanitization failed: $($sanitizedPath.Message)"
        context_response -Response $response -StatusCode 400 -StatusDescription "Bad Request" -String $sanitizedPath.Message
        return
    }

    if (-not (Test-Path $sanitizedPath.Path -PathType Leaf)) {
        # Special handling for /public/elements/ - search in app directories
        if ($requestedPath -match '^/public/elements/(?<fullpath>.+)$') {
            $fullPath = $matches.fullpath
            Write-Verbose "$MyTag Component file not in project root, searching apps: $fullPath"

            # Try searching all apps
            if ($Global:PSWebServer.Apps) {
                foreach ($appName in $Global:PSWebServer.Apps.Keys) {
                    $appInfo = $Global:PSWebServer.Apps[$appName]
                    $appPublicDir = $appInfo.PublicPath
                    $componentFilePath = Join-Path $appPublicDir "elements/$fullPath"

                    if (Test-Path $componentFilePath -PathType Leaf) {
                        Write-Verbose "$MyTag Component file found in app '$appName': $componentFilePath"
                        context_response -Response $response -Path $componentFilePath
                        return
                    }
                }
            }
        }

        Write-Verbose "$MyTag File not found: $($sanitizedPath.Path)"
        context_response -Response $response -StatusCode 404 -StatusDescription "Not Found" -String "File not found"
        return
    }

    Write-Verbose "$MyTag Serving file: $($sanitizedPath.Path)"
    context_response -Response $response -Path $sanitizedPath.Path
}

function Invoke-HttpRequestRoute {
    <#
    .SYNOPSIS
        Handles route execution for both app routes and default routes.

    .DESCRIPTION
        Unified route handler for:
        - Bearer token authentication (API keys)
        - App routes: /apps/[appname]/... (excluding /public/)
        - Default routes: /* (resolved from /routes/ directory)
        - Card routes: /cards/* (searched in main routes and app routes)

        Handles authorization, card settings, performance tracking, and script execution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory)]
        [System.Net.HttpListenerRequest]$Request,

        [Parameter(Mandatory)]
        [string]$SessionID,

        [switch]$Async,

        $HostUIQueue
    )

    $MyTag = '[Invoke-HttpRequestRoute]'
    $response = $Context.Response
    $requestedPath = $Request.Url.LocalPath
    $httpMethod = $Request.HttpMethod.ToLower()
    $projectRoot = $Global:PSWebServer.Project_Root.Path
    $scriptPath = $null

    Write-Verbose "$MyTag Handling route request: $httpMethod $requestedPath"

    # --- API Key Bearer Token Authentication ---
    # Check Authorization header for Bearer token - enhances/overrides session auth
    $apiKeyAuthenticated = $false
    $authHeader = $Request.Headers['Authorization']
    if ($authHeader -and $authHeader.StartsWith('Bearer ', [System.StringComparison]::OrdinalIgnoreCase)) {
        $bearerToken = $authHeader.Substring(7).Trim()
        Write-Verbose "$MyTag Authorization Bearer token detected, validating API key..."

        $remoteIP = $Request.RemoteEndPoint.Address.ToString()
        Write-Verbose "$MyTag Remote IP for API key validation: $remoteIP"

        try {
            $apiKeyResult = Test-Authentication_API_Key_Bearer -BearerToken $bearerToken -RemoteIP $remoteIP
        } catch {
            Write-PSWebHostLog -Severity 'Error' -Category 'Authentication' -Message "$MyTag Error calling Test-Authentication_API_Key_Bearer: $($_.Exception.Message)"
            Write-Host "$MyTag Error calling Test-Authentication_API_Key_Bearer: $($_.Exception.Message)" -ForegroundColor Red
            $apiKeyResult = $null
        }

        if ($apiKeyResult -and $apiKeyResult.Authenticated) {
            Write-Verbose "$MyTag API key authentication successful: $($apiKeyResult.KeyName) from $($apiKeyResult.Source)"
            $apiKeyAuthenticated = $true

            # Update the in-memory session with API key authentication
            # Use a default UserAgent for API key auth if none provided (common for CLI/script clients)
            $apiUserAgent = if ($Request.UserAgent) { $Request.UserAgent } else { 'API_Key_Client' }
            $global:PSWebSessions[$SessionID] = [hashtable]::Synchronized(@{
                UserID = $apiKeyResult.UserID
                Provider = "API_Key"
                UserAgent = $apiUserAgent
                AuthTokenExpiration = (Get-Date).AddHours(1)
                LastUpdated = (Get-Date)
                AuthenticationState = "completed"
                Roles = $apiKeyResult.Roles
                ApiKeyName = $apiKeyResult.KeyName
                ApiKeySource = $apiKeyResult.Source
            })

            Write-Verbose "$MyTag API_Key session created in memory for UserID: $($apiKeyResult.UserID), SessionID: $SessionID"
            Write-PSWebHostLog -Severity 'Info' -Category 'Authentication' -Message "$MyTag API key authenticated: $($apiKeyResult.KeyName) from $remoteIP with roles: $($apiKeyResult.Roles -join ', '), SessionID: $SessionID"

            # Set session cookie for bearer auth session
            $sessionCookie = New-Object System.Net.Cookie("PSWebSessionID", $SessionID)
            $hostName = $Request.Url.HostName
            if ($hostName -notmatch '^(localhost|(\d{1,3}\.){3}\d{1,3}|::1)$') {
                $sessionCookie.Domain = $hostName
            }
            $sessionCookie.Expires = (Get-Date).AddDays(7)
            $sessionCookie.Path = "/"
            $sessionCookie.HttpOnly = $true
            $sessionCookie.Secure = $Request.IsSecureConnection
            $response.AppendCookie($sessionCookie)
            Write-Verbose "$MyTag Session cookie set for bearer auth: $SessionID"
        } else {
            Write-Verbose "$MyTag API key authentication failed for bearer token"
            Write-PSWebHostLog -Severity 'Warning' -Category 'Security' -Message "$MyTag Invalid API key bearer token from $($Request.RemoteEndPoint.Address)"
            context_response -Response $response -StatusCode 401 -StatusDescription "Unauthorized" -String "Invalid API key"
            return
        }
    }

    # Get session (either updated by bearer token auth or existing cookie session)
    $Session = Get-PSWebSessions -SessionID $SessionID
    Write-Verbose "$MyTag Session retrieved: $SessionID UserID: $($Session.UserID)"

    # --- App Route Resolution ---
    if ($requestedPath -match '^/apps/(?<appname>[a-zA-Z0-9_-]+)/(?<routepath>.+)$') {
        $appName = $matches.appname
        $routePath = $matches.routepath

        # Skip if this is a public file (should have been handled by Invoke-HttpRequestPublic)
        if ($routePath.StartsWith("public/")) {
            Write-Verbose "$MyTag Public path in app route handler (should not happen): $requestedPath"
            context_response -Response $response -StatusCode 500 -StatusDescription "Internal Server Error" -String "Routing error"
            return
        }

        Write-Verbose "$MyTag App route request: app=$appName, route=$routePath"

        if ($Global:PSWebServer.Apps -and $Global:PSWebServer.Apps.ContainsKey($appName)) {
            $appInfo = $Global:PSWebServer.Apps[$appName]
            $manifest = $appInfo.Manifest

            # Check if app requires specific roles
            if ($manifest.requiredRoles -and $manifest.requiredRoles.Count -gt 0) {
                $hasRequiredRole = $false
                foreach ($reqRole in $manifest.requiredRoles) {
                    if ($Session.Roles -contains $reqRole) {
                        $hasRequiredRole = $true
                        break
                    }
                }
                if (-not $hasRequiredRole) {
                    Write-Verbose "$MyTag User lacks required roles for app '$appName': $($manifest.requiredRoles -join ', ')"
                    Write-PSWebHostLog -Severity 'Warning' -Category 'Security' -Message "Unauthorized app access: $appName requires roles: $($manifest.requiredRoles -join ', ')"
                    context_response -Response $response -StatusCode 401 -StatusDescription "Unauthorized" -String "Unauthorized - App requires: $($manifest.requiredRoles -join ', ')"
                    return
                }
            }

            $appRoutesDir = $appInfo.RoutesPath
            if (Test-Path $appRoutesDir) {
                # Ensure routePath has leading slash for resolution
                if (-not $routePath.StartsWith("/")) {
                    $routePath = "/$routePath"
                }
                $scriptPath = Resolve-RouteScriptPath -UrlPath $routePath -HttpMethod $httpMethod -BaseDirectory $appRoutesDir
                if ($scriptPath) {
                    Write-Verbose "$MyTag App route script found: $scriptPath"
                    # Execute with app-specific defaults
                    Invoke-RouteScript -Context $Context -Session $Session -SessionID $SessionID `
                                      -ScriptPath $scriptPath -DefaultRoles @("authenticated") `
                                      -Async:$Async -HostUIQueue $HostUIQueue
                    return
                }
            }
        } else {
            Write-Verbose "$MyTag App '$appName' not found"
            context_response -Response $response -StatusCode 404 -StatusDescription "Not Found" -String "App not found"
            return
        }
    }

    # --- Card Route Resolution ---
    if ($requestedPath -match '^/cards/') {
        Write-Verbose "$MyTag Card route request: $requestedPath"

        # First try main routes/cards directory
        $routeBaseDir = Join-Path $projectRoot "routes"
        $scriptPath = Resolve-RouteScriptPath -UrlPath $requestedPath -HttpMethod $httpMethod -BaseDirectory $routeBaseDir

        # If not found in main routes, search app routes
        if (-not $scriptPath -and $Global:PSWebServer.Apps) {
            foreach ($appName in $Global:PSWebServer.Apps.Keys) {
                $appInfo = $Global:PSWebServer.Apps[$appName]
                $appRoutesDir = $appInfo.RoutesPath
                if ($appRoutesDir -and (Test-Path $appRoutesDir)) {
                    $scriptPath = Resolve-RouteScriptPath -UrlPath $requestedPath -HttpMethod $httpMethod -BaseDirectory $appRoutesDir
                    if ($scriptPath) {
                        Write-Verbose "$MyTag Card route found in app '$appName': $scriptPath"
                        break
                    }
                }
            }
        } elseif ($scriptPath) {
            Write-Verbose "$MyTag Card route found in main routes: $scriptPath"
        }
    }

    # --- Default Route Resolution ---
    if (-not $scriptPath) {
        Write-Verbose "$MyTag Attempting default route resolution"
        $routeBaseDir = Join-Path $projectRoot "routes"
        $scriptPath = Resolve-RouteScriptPath -UrlPath $requestedPath -HttpMethod $httpMethod -BaseDirectory $routeBaseDir
    }

    # --- Execute Script or 404 ---
    if ($scriptPath) {
        Write-Verbose "$MyTag Route script found: $scriptPath"
        Invoke-RouteScript -Context $Context -Session $Session -SessionID $SessionID `
                          -ScriptPath $scriptPath -DefaultRoles @("unauthenticated") `
                          -Async:$Async -HostUIQueue $HostUIQueue
    } else {
        # Special case: favicon
        if ($requestedPath -eq "/favicon.ico") {
            $DefaultFavicon = Join-Path $projectRoot "public/favicon.ico"
            Write-Verbose "$MyTag Serving favicon: $DefaultFavicon"
            context_response -Response $response -Path $DefaultFavicon
        } else {
            Write-Verbose "$MyTag No handler found, returning 404: $requestedPath"
            Write-PSWebHostLog -Severity 'Info' -Category 'Routing' -Message "$MyTag 404 Not Found: $requestedPath from $($request.RemoteEndPoint)"
            context_response -Response $response -StatusCode 404 -String "404 Not Found" -ContentType "text/plain"
        }
    }
}

function Invoke-RouteScript {
    <#
    .SYNOPSIS
        Executes a route script with authorization, card settings, and performance tracking.

    .DESCRIPTION
        Internal helper for route script execution. Handles:
        - Security configuration and authorization
        - Card settings retrieval and decompression
        - Performance tracking
        - Async vs sync execution
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory)]
        [hashtable]$Session,

        [Parameter(Mandatory)]
        [string]$SessionID,

        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [Parameter(Mandatory)]
        [string[]]$DefaultRoles,

        [switch]$Async,

        $HostUIQueue
    )

    $MyTag = '[Invoke-RouteScript]'
    $request = $Context.Request
    $response = $Context.Response
    $requestedPath = $request.Url.LocalPath
    $httpMethod = $request.HttpMethod.ToLower()

    Write-Verbose "$MyTag Executing route script: $ScriptPath"

    # --- Security Configuration ---
    $securityPath = [System.IO.Path]::ChangeExtension($ScriptPath, ".security.json")
    Write-Verbose "$MyTag Security config path: $securityPath"

    if (-not (Test-Path $securityPath)) {
        $securityContent = @{ Allowed_Roles = $DefaultRoles } | ConvertTo-Json -Compress
        Set-Content -Path $securityPath -Value $securityContent
        Write-Verbose "$MyTag Auto-created default security file with roles: $($DefaultRoles -join ', ')"
        Write-PSWebHostLog -Severity 'Info' -Category 'Security' -Message "Auto-created default security file for $requestedPath with roles: $($DefaultRoles -join ', ')"
    }

    # Backup configuration file if it has changed
    Backup-ConfigurationFile -ConfigFilePath $securityPath

    # --- Authorization ---
    $securityConfig = Get-Content $securityPath | ConvertFrom-Json
    Write-Verbose "$MyTag Security config loaded. Allowed roles: $($securityConfig.Allowed_Roles -join ', ')"

    $isAuthorized = Authorize-Request -Session $Session -SecurityPath $securityPath
    Write-Verbose "$MyTag Authorization result: $isAuthorized"

    if (-not $isAuthorized) {
        Write-Verbose "$MyTag Authorization failed - user not in allowed roles"
        Write-PSWebHostLog -Severity 'Warning' -Category 'Security' -Message "Unauthorized access to $requestedPath by user $($Session.UserID) with roles: $($Session.Roles -join ', ')"
        context_response -Response $response -StatusCode 401 -StatusDescription "Unauthorized" -String "Unauthorized"
        return
    }

    # --- Prepare Script Parameters ---
    $scriptParams = @{
        Context = $Context
        SessionData = $Session
    }

    [string[]]$ScriptParamNames = (Get-Command -Name $ScriptPath).Parameters.keys
    ($scriptParams.Keys | Where-Object { $ScriptParamNames -notcontains $_ }) | ForEach-Object {
        Write-Verbose "$MyTag Removing unexpected script parameter: $_"
        $scriptParams.Remove($_)
    }

    # --- Card Settings Handling (POST requests) ---
    if ($httpMethod -eq 'post') {
        Write-Verbose "$MyTag Processing POST request, checking for card settings"
        $guidPath = [System.IO.Path]::ChangeExtension($ScriptPath, ".json")
        if (Test-Path $guidPath) {
            Write-Verbose "$MyTag Card settings config found: $guidPath"
            $guid = (Get-Content $guidPath | ConvertFrom-Json).guid
            if ($guid -and $Session.UserID) {
                Write-Verbose "$MyTag Retrieving card settings for GUID: $guid, UserID: $($Session.UserID)"
                $cardSettingsData = Get-CardSettings -EndpointGuid $guid -UserId $Session.UserID
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
                        ($uncompressedJson | ConvertFrom-Json).psobject.Properties | ForEach-Object { $ht[$_.Name] = $_.value }
                        $scriptParams.CardSettings = $ht
                        Write-Verbose "$MyTag Card settings decompressed and added to script parameters"
                    } catch {
                        Write-Verbose "$MyTag Failed to decompress/deserialize card settings for GUID $guid"
                        Write-PSWebHostLog -Severity 'Error' -Category 'Settings' -Message "Failed to decompress/deserialize card settings for GUID $guid"
                    }
                } else {
                    Write-Verbose "$MyTag No card settings data found for GUID: $guid"
                }
            } else {
                Write-Verbose "$MyTag Skipping card settings retrieval: GUID=$guid, UserID=$($Session.UserID)"
            }
        } else {
            Write-Verbose "$MyTag Card settings config not found: $guidPath"
        }
    }

    # --- Performance Tracking - Start ---
    $requestID = [Guid]::NewGuid().ToString()
    $perfStartTime = Get-Date
    $logFilePath = $Global:PSWebServer.LogFilePath
    $logFileSizeBefore = if (Test-Path $logFilePath) { (Get-Item $logFilePath).Length } else { 0 }

    if ($Global:PSWebPerfQueue) {
        & (Join-Path $Global:PSWebServer.Project_Root.Path "system\SQLITE_Perf_Table_Updater.ps1") -QueueData @{
            Type = 'WebRequest'
            Data = @{
                Action = 'Start'
                RequestID = $requestID
                StartTime = $perfStartTime.ToString('u')
                FilePath = $ScriptPath
                HttpMethod = $httpMethod
                IPAddress = $request.RemoteEndPoint.Address.ToString()
                UserAgent = $request.UserAgent
                SessionID = $SessionID
                LogFileSizeBefore = $logFileSizeBefore
            }
        }
    }

    # --- Execute Script ---
    $scriptStatusCode = $null
    if ($Async.IsPresent) {
        Write-Verbose "$MyTag Executing route script asynchronously via runspace pool"
        if ($global:AsyncRunspacePool -and $global:AsyncRunspacePool.Initialized) {
            $asyncFunc = $global:AsyncRunspacePool.Functions['Invoke-AsyncHttpRequest']
            if ($asyncFunc) {
                & $asyncFunc -Context $Context -ScriptPath $ScriptPath -ScriptParams $scriptParams -SessionID $SessionID
            } else {
                Write-Warning "$MyTag Invoke-AsyncHttpRequest function not found in pool, falling back to legacy"
                Invoke-ContextRunspace -Context $Context -ScriptPath $ScriptPath -SessionID $SessionID
            }
        } else {
            Invoke-ContextRunspace -Context $Context -ScriptPath $ScriptPath -SessionID $SessionID
        }
    } else {
        Write-Verbose "$MyTag Executing route script synchronously: $($httpMethod.ToUpper()) $ScriptPath"
        if ($PSBoundParameters.Verbose.IsPresent) {
            $scriptParams['Verbose'] = $true
        }
        try {
            & $ScriptPath @scriptParams
            $scriptStatusCode = 200
        } catch {
            Write-PSWebHostLog -Severity 'Error' -Category 'Routing' -Message "$MyTag Error executing route script: $($_.Exception.Message + "`n" + $_.InvocationInfo.PositionMessage)" -Data @{ ScriptPath = $ScriptPath; SessionID = $SessionID; PositionMessage = $_.InvocationInfo.PositionMessage; Message = $_.Exception.Message } -WriteHost
            context_response -Response $response -StatusCode 500 -StatusDescription "Internal Server Error" -String "Internal Server Error"
            $scriptStatusCode = 500
        }
        Write-Verbose "$MyTag Route script execution completed"
    }

    # --- Performance Tracking - Complete ---
    $perfEndTime = Get-Date
    $executionTimeMicroseconds = [long](($perfEndTime - $perfStartTime).TotalMilliseconds * 1000)
    $logFileSizeAfter = if (Test-Path $logFilePath) { (Get-Item $logFilePath).Length } else { 0 }

    if ($Global:PSWebPerfQueue) {
        $finalStatusCode = if ($scriptStatusCode) { $scriptStatusCode } else { $response.StatusCode }
        $finalStatusText = if ($response.StatusDescription) { $response.StatusDescription } else { $null }

        & (Join-Path $Global:PSWebServer.Project_Root.Path "system\SQLITE_Perf_Table_Updater.ps1") -QueueData @{
            Type = 'WebRequest'
            Data = @{
                Action = 'Complete'
                RequestID = $requestID
                EndTime = $perfEndTime.ToString('u')
                UserID = if ($Session.UserID) { $Session.UserID } else { '' }
                AuthenticationProvider = if ($Session.Provider) { $Session.Provider } else { '' }
                ExecutionTimeMicroseconds = $executionTimeMicroseconds
                LogFileSizeBefore = $logFileSizeBefore
                LogFileSizeAfter = $logFileSizeAfter
                StatusCode = $finalStatusCode
                StatusText = $finalStatusText
            }
        }
    }
}

function Process-HttpRequest {
    <#
    .SYNOPSIS
        Main HTTP request processing dispatcher.

    .DESCRIPTION
        Handles session management, authentication, and routes requests to specialized handlers:
        - Public static files: Invoke-HttpRequestPublic (no session required)
        - Route execution: Invoke-HttpRequestRoute (session required)
    #>
    [CmdletBinding()]
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

    $request = $Context.Request
    $response = $Context.Response
    $requestedPath = $request.Url.LocalPath
    $httpMethod = $request.HttpMethod.ToLower()

    Write-Verbose "$($MyTag) Starting processing request: $httpMethod $requestedPath from $($request.RemoteEndPoint)"

    # Early exit for .well-known paths
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

    Write-Verbose "$($MyTag) $(Get-Date -f 'yyyMMdd HH:mm:ss') Request received: $httpMethod $requestedPath from $($request.RemoteEndPoint)"

    # --- Session Cookie Handling ---
    try { Write-Verbose "$($MyTag) Incoming Cookie header: $($request.Headers['Cookie'])" } catch {}
    $sessionCookie = $request.Cookies["PSWebSessionID"]
    if ($sessionCookie -and -not [string]::IsNullOrWhiteSpace($sessionCookie.Value)) {
        $sessionID = $sessionCookie.Value
        Write-Verbose "$($MyTag) Session cookie found: $($sessionID)"
    } else {
        $sessionID = [Guid]::NewGuid().ToString()
        Write-Verbose "$($MyTag) No session cookie found or empty, creating new session: $($sessionID)"

        # Create session in memory only for unauthenticated sessions
        $global:PSWebSessions[$sessionID] = [hashtable]::Synchronized(@{
            UserID = ""
            Provider = ""
            UserAgent = $request.UserAgent
            AuthTokenExpiration = (Get-Date)
            LastUpdated = (Get-Date)
            Roles = [System.Collections.ArrayList]@('unauthenticated')
        })
        Write-Verbose "$($MyTag) New unauthenticated session created in memory: $($sessionID)"

        # Set cookie
        $newCookie = New-Object System.Net.Cookie("PSWebSessionID", $sessionID)
        $hostName = $request.Url.HostName
        if ($hostName -notmatch '^(localhost|(\d{1,3}\.){3}\d{1,3}|::1)$') {
            $newCookie.Domain = $hostName
        }
        $newCookie.Expires = (Get-Date).AddDays(7)
        $newCookie.Path = "/"
        $newCookie.HttpOnly = $true
        $newCookie.Secure = $request.IsSecureConnection

        $response.AppendCookie($newCookie)
        try { Write-Verbose "$($MyTag) Response Set-Cookie header after append: $($response.Headers['Set-Cookie'])" } catch {}
        Write-Verbose "$($MyTag) Session cookie appended to response: $($sessionID) (Secure=$($newCookie.Secure), HttpOnly=$($newCookie.HttpOnly))"
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

    # --- Request Routing Dispatcher ---
    # Route public files BEFORE cookie/auth (no authentication required)
    # All other routes AFTER session establishment (authentication handled in route handler)

    Write-Verbose "$($MyTag) Dispatching request: $requestedPath"

    switch -regex ($requestedPath) {
        # PUBLIC STATIC FILES - No session/cookie/auth required
        '^/public/' {
            Write-Verbose "$($MyTag) Routing to public handler: /public/"
            Invoke-HttpRequestPublic -Context $Context
            return
        }
        '^/apps/[^/]+/public/' {
            Write-Verbose "$($MyTag) Routing to public handler: /apps/.../public/"
            Invoke-HttpRequestPublic -Context $Context
            return
        }
        default {
            # ALL OTHER ROUTES - Require session cookie (unless bearer token provided)
            # Check for Authorization header first (bearer token auth doesn't need cookie)
            $authHeader = $request.Headers['Authorization']
            $hasBearerToken = $authHeader -and $authHeader.StartsWith('Bearer ', [System.StringComparison]::OrdinalIgnoreCase)

            # Ensure cookie is established for non-public routes (unless bearer auth)
            if (-not $sessionCookie -and -not $hasBearerToken) {
                Write-Verbose "$($MyTag) Redirecting to establish cookie: $($request.Url.AbsoluteUri)"
                context_response -Response $response -StatusCode 302 -RedirectLocation $request.Url.AbsoluteUri
                return
            }

            # Root redirect
            if ($requestedPath -eq "/" -and $httpMethod -eq "get") {
                Write-Verbose "$($MyTag) Root path redirect: '/' -> '/spa'"
                Write-PSWebHostLog -Severity 'Info' -Category 'Routing' -Message "$($MyTag) Redirecting '/' to '/spa'"
                context_response -Response $response -StatusCode 302 -RedirectLocation "/spa"
                return
            }

            # All app routes and default routes (bearer token auth handled inside)
            Write-Verbose "$($MyTag) Routing to route handler"
            Invoke-HttpRequestRoute -Context $Context -SessionID $sessionID -Request $request -Async:$Async -HostUIQueue $HostUIQueue
            return
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
        [string]$UserID,
        [string]$SessionID,
        [string]$Source,
        [string]$ActivityName,
        [int]$PercentComplete = -1,
        [string]$RunspaceID,
        [switch]$WriteHost,
        [string]$State = 'Unspecified',
        [string]$ForeGroundColor,
        [string]$BackGroundColor = ($host.UI.RawUI.BackgroundColor, "Black"|Where-Object{$_ -match '\w'}|Select-Object -First 1),
        [string]$EventGUID
    )

    # Auto-detect Source from calling script if not provided
    if ([string]::IsNullOrWhiteSpace($Source)) {
        try {
            $callStack = Get-PSCallStack
            # Skip the current function (Write-PSWebHostLog) and get the caller
            if ($callStack.Count -gt 1) {
                $caller = $callStack[1]
                if ($caller.ScriptName) {
                    # Get relative path from project root
                    $projectRoot = $Global:PSWebServer.Project_Root.Path
                    if ($projectRoot -and $caller.ScriptName.StartsWith($projectRoot)) {
                        $Source = $caller.ScriptName.Substring($projectRoot.Length).TrimStart('\', '/')
                    } else {
                        $Source = Split-Path $caller.ScriptName -Leaf
                    }
                    # Include function name if available
                    if ($caller.FunctionName -and $caller.FunctionName -ne '<ScriptBlock>') {
                        $Source = "$Source::$($caller.FunctionName)"
                    }
                } elseif ($caller.FunctionName -and $caller.FunctionName -ne '<ScriptBlock>') {
                    $Source = $caller.FunctionName
                } else {
                    $Source = "Unknown"
                }
            } else {
                $Source = "Unknown"
            }
        } catch {
            $Source = "Unknown"
        }
    }

    # Auto-detect UserID from session if not provided
    if ([string]::IsNullOrWhiteSpace($UserID)) {
        try {
            if ($null -ne $Session -and $null -ne $Session.UserID) {
                $UserID = $Session.UserID
            } elseif ($null -ne $sessiondata -and $null -ne $sessiondata.UserID) {
                $UserID = $sessiondata.UserID
            } else {
                $UserID = ""
            }
        } catch {
            $UserID = ""
        }
    }

    # Auto-detect SessionID from various sources if not provided
    if ([string]::IsNullOrWhiteSpace($SessionID)) {
        try {
            if ($null -ne $Session -and $null -ne $Session.SessionID) {
                $SessionID = $Session.SessionID
            } elseif ($null -ne $sessiondata -and $null -ne $sessiondata.SessionID) {
                $SessionID = $sessiondata.SessionID
            } elseif ($null -ne $PSBoundParameters['SessionID']) {
                $SessionID = $PSBoundParameters['SessionID']
            } else {
                $SessionID = ""
            }
        } catch {
            $SessionID = ""
        }
    }

    # Auto-detect RunspaceID if not provided
    if ([string]::IsNullOrWhiteSpace($RunspaceID)) {
        try {
            $RunspaceID = [runspace]::DefaultRunspace.Id.ToString()
        } catch {
            $RunspaceID = ""
        }
    }

    # Auto-detect ActivityName from calling function/script if not provided
    if ([string]::IsNullOrWhiteSpace($ActivityName)) {
        try {
            $callStack = Get-PSCallStack
            if ($callStack.Count -gt 1) {
                $caller = $callStack[1]
                if ($caller.FunctionName -and $caller.FunctionName -ne '<ScriptBlock>') {
                    $ActivityName = $caller.FunctionName
                } elseif ($caller.Command) {
                    $ActivityName = $caller.Command
                } else {
                    $ActivityName = ""
                }
            } else {
                $ActivityName = ""
            }
        } catch {
            $ActivityName = ""
        }
    }
    if ($WriteHost.IsPresent) {
        if ($ForeGroundColor -eq '') {
            if ($Severity -eq 'Critical' -or $Severity -eq 'Error') {
                $ForeGroundColor = 'Red'
            } elseif ($Severity -eq 'Warning') {
                $ForeGroundColor = 'Yellow'
            } elseif ($Severity -eq 'Info') {
                $ForeGroundColor = 'Green'
            } else {
                # Default to Gray if host color is blank (runspace has no console host)
                $ForeGroundColor = ($host.UI.RawUI.ForegroundColor, "Gray" | Where-Object { $_ -match '\w' } | Select-Object -First 1)
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

    # Format PercentComplete (use empty string if -1 or not applicable)
    $percentString = if ($PercentComplete -ge 0 -and $PercentComplete -le 100) { $PercentComplete.ToString() } else { "" }

    # New log format with additional context fields (Source, ActivityName, PercentComplete, UserID, SessionID, RunspaceID come before Data)
    # Format: UTCTime, LocalTime, Severity, Category, Message, Source, ActivityName, PercentComplete, UserID, SessionID, RunspaceID, Data
    $global:PSWebServer.LogFileFields = 'utcTime','localTime','Severity','Category','escapedMessage','Source','ActivityName','percentString','UserID','SessionID','RunspaceID','dataString'
    foreach ($VarName in ('Category','Source','ActivityName','percentString','UserID','SessionID','RunspaceID')) {
        $var = Get-Variable $VarName
        if ($var.Value -match '[\t\r\n]') {
            $var.Value = [regex]::Escape($var.Value)
        }
    }
    $logEntry = "$utcTime`t$localTime`t$Severity`t$Category`t$escapedMessage`t$Source`t$ActivityName`t$percentString`t$UserID`t$SessionID`t$RunspaceID`t$dataString"

    if ($null -ne $global:PSWebHostLogQueue) {
        $global:PSWebHostLogQueue.Enqueue($logEntry)
    }

    # Only update events if PSWebServer is available (may not be in runspaces during init)
    if ($null -ne $global:PSWebServer) {
        $eventGuid = [Guid]::NewGuid().ToString()
        if ($null -eq $global:PSWebServer.events) {
            $global:PSWebServer.events = [hashtable]::Synchronized([ordered]@{})
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
            Source = $Source
            ActivityName = $ActivityName
            PercentComplete = $PercentComplete
            RunspaceID = $RunspaceID
            Data = @{ Message = $Message; Severity = $Severity; Details = $Data }
            CompletionDate = Get-Date
        }
        try {
            # Clean up events hashtable (keep last 1000)
            while($global:PSWebServer.events.count -gt 1000) {
                $global:PSWebServer.events.keys |
                    Select-Object -First ($global:PSWebServer.events.count - 1000) |
                    ForEach-Object{$global:PSWebServer.events.Remove($_)}
            }

            # Clean up eventGuid hashtable (MEMORY LEAK FIX)
            # This hashtable was growing unbounded - keep last 1000 entries
            while($global:PSWebServer.eventGuid.count -gt 1000) {
                $global:PSWebServer.eventGuid.keys |
                    Select-Object -First ($global:PSWebServer.eventGuid.count - 1000) |
                    ForEach-Object{$global:PSWebServer.eventGuid.Remove($_)}
            }
        }
        catch{}
        $global:PSWebServer.eventGuid[$date] = $eventGuid
    }
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
        [string]$Severity = "*",
        [string]$Source = "*",
        [string]$UserID = "*",
        [string]$SessionID = "*",
        [string]$ActivityName = "*",
        [string]$RunspaceID = "*"
    )
    # Try Logs/PSWebHost.log first (standard location)
    $logFile = Join-Path $Global:PSWebServer.Project_Root.Path "Logs\PSWebHost.log"

    # If not found, try PsWebHost_Data/Logs/ directory (look for most recent .tsv file)
    if (-not (Test-Path $logFile)) {
        $baseDirectory = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data"
        $logDirectory = Join-Path $baseDirectory "Logs"

        if (Test-Path $logDirectory) {
            # Get most recent .tsv file
            $logFile = Get-ChildItem -Path $logDirectory -Filter "*.tsv" -File |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1 -ExpandProperty FullName
        }
    }

    if (-not $logFile -or -not (Test-Path $logFile)) {
        Write-Warning "No log file found. Checked Logs\PSWebHost.log and PsWebHost_Data\Logs\*.tsv"
        return @()
    }

    # New format: UTCTime, LocalTime, Severity, Category, Message, Source, ActivityName, PercentComplete, UserID, SessionID, RunspaceID, Data
    # Old format: UTCTime, LocalTime, Severity, Category, Message, SessionID, UserID, Data
    # Auto-detect format by checking column count
    $firstLine = Get-Content -Path $logFile -TotalCount 1
    $columnCount = ($firstLine -split "`t").Count

    if ($columnCount -ge 12) {
        # New format with enhanced context fields
        $headers = @("UTCTime", "LocalTime", "Severity", "Category", "Message", "Source", "ActivityName", "PercentComplete", "UserID", "SessionID", "RunspaceID", "Data")
        $results = @(Import-Csv -Path $logFile -Delimiter "`t" -Header $headers | Where-Object {
            try {
                ($_.UTCTime -as [datetime]) -ge $StartTime -and
                ($_.UTCTime -as [datetime]) -le $EndTime -and
                $_.Category -like $Category -and
                $_.Severity -like $Severity -and
                $_.Source -like $Source -and
                $_.UserID -like $UserID -and
                $_.SessionID -like $SessionID -and
                $_.ActivityName -like $ActivityName -and
                $_.RunspaceID -like $RunspaceID
            } catch {
                $false
            }
        })
        return $results
    } elseif ($columnCount -ge 8) {
        # Old format (backwards compatibility)
        $headers = @("UTCTime", "LocalTime", "Severity", "Category", "Message", "SessionID", "UserID", "Data")
        $results = @(Import-Csv -Path $logFile -Delimiter "`t" -Header $headers | Where-Object {
            try {
                ($_.UTCTime -as [datetime]) -ge $StartTime -and
                ($_.UTCTime -as [datetime]) -le $EndTime -and
                $_.Category -like $Category -and
                $_.Severity -like $Severity -and
                $_.UserID -like $UserID -and
                $_.SessionID -like $SessionID
            } catch {
                $false
            }
        } | Select-Object *, @{Name='Source';Expression={''}}, @{Name='ActivityName';Expression={''}}, @{Name='PercentComplete';Expression={''}}, @{Name='RunspaceID';Expression={''}})
        return $results
    } else {
        Write-Warning "Unrecognized log format (expected 8+ or 12+ columns, found $columnCount)"
        return @()
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
        if ($session.LastUpdated -and $session.UserID -and $session.Provider) {
            $dbSession = Get-LoginSession -SessionID $sessionID
            if ($dbSession) {
                # Session exists in DB - update if memory version is newer
                $dbLastUpdated = [datetimeoffset]::FromUnixTimeSeconds([int64]$dbSession.AuthenticationTime).DateTime
                if ($session.LastUpdated -gt $dbLastUpdated) {
                    Set-LoginSession -SessionID $sessionID -UserID $session.UserID -Provider $session.Provider -AuthenticationTime $session.LastUpdated -AuthenticationState $session.AuthenticationState -LogonExpires $session.AuthTokenExpiration -UserAgent $session.UserAgent | Out-Null
                }
            } else {
                # Session doesn't exist in DB - create it (e.g., Bearer token auth)
                Set-LoginSession -SessionID $sessionID -UserID $session.UserID -Provider $session.Provider -AuthenticationTime $session.LastUpdated -AuthenticationState $session.AuthenticationState -LogonExpires $session.AuthTokenExpiration -UserAgent $session.UserAgent | Out-Null
            }
        }
    }
}

function Set-WebHostRunSpaceInfo {
    <#
    .SYNOPSIS
        Updates runspace statistics in $global:PSWebServer.Runspaces for monitoring and management.

    .DESCRIPTION
        Called from within runspaces to report their status, statistics, and current activity.
        This allows the main thread to monitor runspace health, track usage, and manage
        runspace lifecycle (including automatic restart after 100 requests).

    .PARAMETER RunspaceId
        The runspace instance ID (from $Host.Runspace.InstanceId).

    .PARAMETER Name
        The name or identifier for this runspace (e.g., "AsyncWorker-5").

    .PARAMETER PoolName
        The pool this runspace belongs to (e.g., "AsyncRunspacePool", "BackgroundTasks").

    .PARAMETER Purpose
        The purpose of this runspace (e.g., "HTTP Request Handler", "Background Job").

    .PARAMETER State
        Current state of the runspace (e.g., "Listening", "Free", "Busy", "Processing").

    .PARAMETER RequestCount
        Total number of requests processed by this runspace.

    .PARAMETER LastRequest
        URL of the last request processed (from $Context.Request.Url).

    .PARAMETER LastSessionID
        Session ID of the last request processed.

    .PARAMETER TimeStarted
        When this runspace was started (datetime).

    .PARAMETER AdditionalData
        Hashtable of any additional custom data to store.

    .EXAMPLE
        Set-WebHostRunSpaceInfo -RunspaceId $Host.Runspace.InstanceId `
                                -Name "AsyncWorker-1" `
                                -PoolName "AsyncRunspacePool" `
                                -Purpose "HTTP Request Handler" `
                                -State "Busy" `
                                -RequestCount 42 `
                                -LastRequest "GET /api/users" `
                                -LastSessionID "abc123"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [guid]$RunspaceId,

        [string]$Name,

        [string]$PoolName,

        [string]$Purpose,

        [string]$State,

        [int]$RequestCount,

        [string]$LastRequest,

        [string]$LastSessionID,

        [datetime]$TimeStarted,

        [hashtable]$AdditionalData = @{}
    )

    $MyTag = "[Set-WebHostRunSpaceInfo]"

    # Validate RunspaceId - catch empty GUIDs early
    if ($RunspaceId -eq [guid]::Empty) {
        if ($null -ne $global:PSWebHostLogQueue) {
            $logEntry = "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ')`t$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`tWarning`tRunspaceManagement`t$MyTag Cannot update runspace info: RunspaceId is empty GUID`t`t`t"
            $global:PSWebHostLogQueue.Enqueue($logEntry)
        }
        return
    }

    try {
        # Initialize Runspaces hashtable if needed
        if ($null -eq $global:PSWebServer.Runspaces) {
            $global:PSWebServer.Runspaces = [hashtable]::Synchronized(@{})
        }

        # Get or create runspace info
        if (-not $global:PSWebServer.Runspaces.ContainsKey($RunspaceId)) {
            $global:PSWebServer.Runspaces[$RunspaceId] = [hashtable]::Synchronized(@{
                RunspaceId = $RunspaceId
                Name = $Name
                PoolName = $PoolName
                Purpose = $Purpose
                TimeStarted = if ($TimeStarted) { $TimeStarted } else { Get-Date }
                FirstReported = Get-Date
                RequestCount = 0
                State = 'Unknown'
                LastRequest = $null
                LastSessionID = $null
                LastUpdated = Get-Date
                AdditionalData = [hashtable]::Synchronized(@{})
            })
        }

        # Update fields (only if provided)
        $rsInfo = $global:PSWebServer.Runspaces[$RunspaceId]

        if ($PSBoundParameters.ContainsKey('Name')) { $rsInfo.Name = $Name }
        if ($PSBoundParameters.ContainsKey('PoolName')) { $rsInfo.PoolName = $PoolName }
        if ($PSBoundParameters.ContainsKey('Purpose')) { $rsInfo.Purpose = $Purpose }
        if ($PSBoundParameters.ContainsKey('State')) { $rsInfo.State = $State }
        if ($PSBoundParameters.ContainsKey('RequestCount')) { $rsInfo.RequestCount = $RequestCount }
        if ($PSBoundParameters.ContainsKey('LastRequest')) { $rsInfo.LastRequest = $LastRequest }
        if ($PSBoundParameters.ContainsKey('LastSessionID')) { $rsInfo.LastSessionID = $LastSessionID }
        if ($PSBoundParameters.ContainsKey('TimeStarted')) { $rsInfo.TimeStarted = $TimeStarted }

        # Merge additional data
        foreach ($key in $AdditionalData.Keys) {
            $rsInfo.AdditionalData[$key] = $AdditionalData[$key]
        }

        # Always update LastUpdated
        $rsInfo.LastUpdated = Get-Date

    } catch {
        # Silently fail to avoid disrupting runspace operations
        # Only log if logging is available
        if ($null -ne $global:PSWebHostLogQueue) {
            $logEntry = "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ')`t$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`tWarning`tRunspaceManagement`t$MyTag Failed to update runspace info: $($_.Exception.Message)`t`t`t"
            $global:PSWebHostLogQueue.Enqueue($logEntry)
        }
    }
}
