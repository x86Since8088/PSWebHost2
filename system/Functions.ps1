# system\Functions.ps1

# Global hashtable for runspace management
if ($null -eq $global:Runspace) {$global:Runspace = [hashtable]::Synchronized(@{})}

# Runspace management functions
function Start-ContextRunspaces {
    param (
        [string]$User,
        [string]$RemoteAddress,
        [string]$SessionID
    )
    
    # Initialize nested hashtables if they don't exist
    if ($null -eq $global:Runspace[$User]) {$global:Runspace[$User] = [hashtable]::Synchronized(@{})}
    if ($null -eq $global:Runspace[$User][$RemoteAddress]) {$global:Runspace[$User][$RemoteAddress] = [hashtable]::Synchronized(@{})}
    if ($null -eq $global:Runspace[$User][$RemoteAddress][$SessionID]) {$global:Runspace[$User][$RemoteAddress][$SessionID] = [hashtable]::Synchronized(@{})}

    $userSessionRunspaces = $global:Runspace[$User][$RemoteAddress][$SessionID]

    # Create and store two runspaces
    for ($i = 1; $i -le 2; $i++) {
        $rs = [runspacefactory]::CreateRunspace()
        $rs.Open()
        $userSessionRunspaces["Runspace$i"] = $rs
        Write-Verbose "Created Runspace$i for User: $User, Address: $RemoteAddress, Session: $SessionID"
    }
    return $userSessionRunspaces
}

function Trim-ContextRunspaces {
    param (
        [string]$User,
        [string]$RemoteAddress,
        [string]$SessionID
    )
    $userSessionRunspaces = $global:Runspace[$User][$RemoteAddress][$SessionID]
    if ($userSessionRunspaces) {
        foreach ($key in $userSessionRunspaces.Keys) {
            $rs = $userSessionRunspaces[$key]
            if ($rs.RunspaceStateInfo.State -eq 'Broken' -or $rs.RunspaceStateInfo.State -eq 'Closed') {
                $rs.Dispose()
                $userSessionRunspaces.Remove($key)
                Write-Verbose "Removed $key for User: $User, Address: $RemoteAddress, Session: $SessionID"
            }
        }
    }
}

function Invoke-ContextRunspace {
    param (
        [System.Net.HttpListenerContext]$Context,
        [string]$ScriptPath,
        [string]$User,
        [string]$RemoteAddress,
        [string]$SessionID
    )

    $userSessionRunspaces = $global:Runspace[$User][$RemoteAddress][$SessionID]
    if (-not $userSessionRunspaces -or $userSessionRunspaces.Count -eq 0) {
        $userSessionRunspaces = Start-ContextRunspaces -User $User -RemoteAddress $RemoteAddress -SessionID $SessionID
    }

    # Find an available runspace
    $availableRunspace = $null
    foreach ($key in $userSessionRunspaces.Keys) {
        $rs = $userSessionRunspaces[$key]
        if ($rs.RunspaceStateInfo.State -eq 'Opened' -and $rs.Availability -eq 'Available') {
            $availableRunspace = $rs
            break
        }
    }

    if ($availableRunspace) {
        try {
            $ps = [powershell]::Create().AddScript($ScriptPath)
            $ps.Runspace = $availableRunspace
            $ps.AddParameter('Request', $Context.Request)
            $ps.AddParameter('Response', $Context.Response)
            $ps.AddParameter('Context', $Context)

            # Begin invocation asynchronously
            $asyncHandle = $ps.BeginInvoke()

            # Store the PowerShell instance with the runspace for later cleanup
            $userSessionRunspaces["$($availableRunspace.InstanceId)_ps"] = $ps
            $userSessionRunspaces["$($availableRunspace.InstanceId)_handle"] = $asyncHandle
            Write-Verbose "Invoked script $ScriptPath in runspace $($availableRunspace.InstanceId)"
        } catch {
            Write-Error "Failed to invoke script '$ScriptPath' in runspace. Error: $($_.Exception.Message)"
        }
    } else {
        Write-Error "No available runspace for User: $User, Address: $RemoteAddress, Session: $SessionID. Request not processed."
        $Context.Response.StatusCode = 503 # Service Unavailable
        $Context.Response.OutputStream.Close()
    }
}

function Get-PSWebHostErrorReport {
    <#
    .SYNOPSIS
        Generates detailed error reports for PSWebHost with role-based access control

    .DESCRIPTION
        Creates comprehensive error diagnostics for Admin/Debug users including:
        - Full call stack
        - Variable enumeration from calling scope
        - Request details (URL, query, body)
        - Error details and stack trace

        Regular users on localhost get basic error info with a reminder about Debug role.
        Remote users get minimal error information for security.

    .PARAMETER ErrorRecord
        The error record to report on (defaults to $Error[0])

    .PARAMETER Context
        The HttpListenerContext object

    .PARAMETER Request
        The HttpListenerRequest object

    .PARAMETER sessiondata
        The session data containing user roles
    #>
    param (
        [Parameter(Mandatory=$false)]
        $ErrorRecord = $Error[0],

        [Parameter(Mandatory=$false)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory=$false)]
        [System.Net.HttpListenerRequest]$Request,

        [Parameter(Mandatory=$false)]
        $sessiondata
    )

    # Determine user roles
    $userRoles = @()
    if ($sessiondata -and $sessiondata.Roles) {
        $userRoles = $sessiondata.Roles
    }

    $hasAdminAccess = ($userRoles -contains 'Admin') -or ($userRoles -contains 'Debug') -or
                      ($userRoles -contains 'site_admin') -or ($userRoles -contains 'system_admin')

    $isLocalhost = $false
    if ($Request -and $Request.RemoteEndPoint) {
        $remoteIP = $Request.RemoteEndPoint.Address.ToString()
        $isLocalhost = $remoteIP -eq '127.0.0.1' -or $remoteIP -eq '::1' -or $remoteIP -like '127.0.*'
    }

    # Build request details
    $requestInfo = @{
        Method = if ($Request) { $Request.HttpMethod } else { 'Unknown' }
        URL = if ($Request) { $Request.Url.ToString() } else { 'Unknown' }
        RawUrl = if ($Request) { $Request.RawUrl } else { 'Unknown' }
        QueryString = @{}
        Headers = @{}
        RequestBody = $null
    }

    if ($Request) {
        # Capture query string
        foreach ($key in $Request.QueryString.Keys) {
            $requestInfo.QueryString[$key] = $Request.QueryString[$key]
        }

        # Capture request body for non-GET methods
        if ($Request.HttpMethod -ne 'GET' -and $Request.HasEntityBody) {
            try {
                $reader = New-Object System.IO.StreamReader($Request.InputStream)
                $requestInfo.RequestBody = $reader.ReadToEnd()
                # Note: Can't close reader here as it may be needed by calling code
            } catch {
                $requestInfo.RequestBody = "Error reading request body: $($_.Exception.Message)"
            }
        }

        # Capture headers (if admin)
        if ($hasAdminAccess) {
            foreach ($key in $Request.Headers.Keys) {
                $requestInfo.Headers[$key] = $Request.Headers[$key]
            }
        }
    }

    # Build error details
    $errorInfo = @{
        Message = if ($ErrorRecord) { $ErrorRecord.Exception.Message } else { 'No error available' }
        Type = if ($ErrorRecord) { $ErrorRecord.Exception.GetType().FullName } else { 'Unknown' }
        StackTrace = if ($ErrorRecord) { $ErrorRecord.ScriptStackTrace } else { 'No stack trace' }
        PositionMessage = if ($ErrorRecord -and $ErrorRecord.InvocationInfo) {
            $ErrorRecord.InvocationInfo.PositionMessage
        } else {
            'No position info'
        }
    }

    # For Admin/Debug users, provide full diagnostic report
    if ($hasAdminAccess) {
        $report = @{
            timestamp = (Get-Date).ToString('o')
            userID = if ($sessiondata -and $sessiondata.UserID) { $sessiondata.UserID } else { 'anonymous' }
            roles = $userRoles
            request = $requestInfo
            error = $errorInfo
            callStack = @()
            variables = @{}
        }

        # Get call stack
        try {
            $callStack = Get-PSCallStack
            $report.callStack = @($callStack | ForEach-Object {
                @{
                    Command = $_.Command
                    Location = $_.Location
                    ScriptName = $_.ScriptName
                    ScriptLineNumber = $_.ScriptLineNumber
                    FunctionName = $_.FunctionName
                }
            })
        } catch {
            $report.callStack = @("Error getting call stack: $($_.Exception.Message)")
        }

        # Enumerate variables from calling scope
        try {
            $callerVariables = Get-Variable -Scope 1 -ErrorAction SilentlyContinue
            foreach ($var in $callerVariables) {
                # Skip sensitive or large objects
                if ($var.Name -in @('PWD', 'PSBoundParameters', 'MyInvocation', 'PSCommandPath',
                                     'Response', 'Context', 'InputStream', 'OutputStream')) {
                    continue
                }

                try {
                    $value = $var.Value
                    if ($null -eq $value) {
                        $report.variables[$var.Name] = '$null'
                    } elseif ($value -is [string] -or $value -is [int] -or $value -is [bool] -or $value -is [datetime]) {
                        $report.variables[$var.Name] = $value
                    } elseif ($value -is [hashtable] -or $value -is [System.Collections.IDictionary]) {
                        $report.variables[$var.Name] = "[Hashtable with $($value.Count) entries]"
                    } elseif ($value -is [array]) {
                        $report.variables[$var.Name] = "[Array with $($value.Count) items]"
                    } else {
                        $report.variables[$var.Name] = "[$($value.GetType().Name)]"
                    }
                } catch {
                    $report.variables[$var.Name] = "[Error accessing value]"
                }
            }
        } catch {
            $report.variables = @{ "_error" = "Could not enumerate variables: $($_.Exception.Message)" }
        }

        return @{
            statusCode = 500
            contentType = 'application/json'
            body = ($report | ConvertTo-Json -Depth 10 -Compress)
            includeInLog = $true
        }
    }

    # For localhost users without admin, provide error details and guidance
    if ($isLocalhost) {
        $basicReport = @{
            timestamp = (Get-Date).ToString('o')
            error = @{
                message = $errorInfo.Message
                type = $errorInfo.Type
                position = $errorInfo.PositionMessage
            }
            request = @{
                method = $requestInfo.Method
                url = $requestInfo.URL
            }
            guidance = "You are accessing from localhost. For detailed diagnostics including call stack and variable enumeration, please use an account with Admin or Debug role."
        }

        return @{
            statusCode = 500
            contentType = 'application/json'
            body = ($basicReport | ConvertTo-Json -Depth 5 -Compress)
            includeInLog = $true
        }
    }

    # For remote users, provide minimal information
    $minimalReport = @{
        timestamp = (Get-Date).ToString('o')
        error = "An internal error occurred. Please contact the administrator."
        requestId = if ($Context) { [guid]::NewGuid().ToString() } else { 'N/A' }
    }

    return @{
        statusCode = 500
        contentType = 'application/json'
        body = ($minimalReport | ConvertTo-Json -Depth 2 -Compress)
        includeInLog = $false
    }
}
