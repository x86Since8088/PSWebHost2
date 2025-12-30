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
