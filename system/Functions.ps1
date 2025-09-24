# system\Functions.ps1

# Global hashtable for runspace management
if ($null -eq $global:Runspace) {$global:Runspace = [hashtable]::Synchronized(@{})}

# Function to launch an application (route handler)
function Launch_Application {
    param (
        $User,
        $Query,
        $ApprovedNames = ("App") # Example approved names
    )
    # Parse query string parameters (simplified for now)
    $Arguments = @{}
    if ($Query) {
        $Query -split '&' | ForEach-Object {
            $pair = $_ -split '='
            if ($pair.Count -eq 2) {
                $name = [System.Web.HttpUtility]::UrlDecode($pair[0])
                $value = [System.Web.HttpUtility]::UrlDecode($pair[1])
                $Arguments[$name] = $value
            }
        }
    }

    # Apply HTML sanitization to all argument values
    $SanitizedArguments = @{}
    $Arguments.GetEnumerator() | ForEach-Object {
        $SanitizedArguments[$_.Key] = Sanitize-HtmlInput -InputString $_.Value
    }

    # Example: Dispatch based on 'App' argument
    $RequestedApp = $SanitizedArguments["App"]
    if ($RequestedApp) {
        # In a real scenario, you'd load and execute the app script here
        # For now, just return a message
        return "Launching app: $RequestedApp with sanitized arguments: $($SanitizedArguments | ConvertTo-Json)"
    } else {
        return "No app requested."
    }
}

# Function to handle incoming web requests and dispatch to route handlers
function Invoke-RouteHandler {
    param (
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response,
        [System.Net.HttpListenerContext]$Context
    )

    # Parse query parameters
    $queryParams = @{}
    $Request.QueryString.AllKeys | ForEach-Object {
        $queryParams[$_] = $Request.QueryString[$_]
    }

    # Read request body for POST, PUT, etc.
    $bodyContent = $null
    if ($Request.HasEntityBody) {
        $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
        $bodyContent = $reader.ReadToEnd()
        $reader.Close()
    }

    # Pass relevant data to the route script
    # The route script will then decide how to process this data
    # and set the response. The route script should return the content to be sent back.
    # For now, we'll just return a placeholder.
    # The actual route script will be responsible for setting $Response.StatusCode, $Response.ContentType, and writing to $Response.OutputStream
    $Response.StatusCode = 200
    $Response.ContentType = "text/plain"
    $responseString = "Request handled by Invoke-RouteHandler. Method: $($Request.HttpMethod), Path: $($Request.Url.LocalPath)"
    if ($queryParams.Count -gt 0) {
        $responseString += ", Query: $($queryParams | ConvertTo-Json)"
    }
    if ($bodyContent) {
        $responseString += ", Body: $bodyContent"
    }
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseString)
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.OutputStream.Close()
}

# Example: Simple HTML rendering function
function Render-Html {
    param (
        [string]$Content
    )
    return "<html><body>$Content</body></html>"
}

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
        Write-Verbose "Created Runspace$i for User: $User, Address: $RemoteAddress, Session: $SessionID" -Verbose
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
                Write-Verbose "Removed $key for User: $User, Address: $RemoteAddress, Session: $SessionID" -Verbose
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
        Write-Verbose "Invoked script $ScriptPath in runspace $($availableRunspace.InstanceId)" -Verbose
    } else {
        Write-Error "No available runspace for User: $User, Address: $RemoteAddress, Session: $SessionID. Request not processed."
        $Context.Response.StatusCode = 503 # Service Unavailable
        $Context.Response.OutputStream.Close()
    }
}

#Export-ModuleMember -Function Start-ContextRunspaces, Trim-ContextRunspaces, Invoke-ContextRunspace